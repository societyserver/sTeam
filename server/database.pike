/* Copyright (C) 2000-2009  Thomas Bopp, Thorsten Hampel, Ludger Merkens, 
 *                          Robert Rosendahl, Daniel Büse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 * 
 * $Id: database.pike,v 1.7 2010/01/27 12:42:33 astra Exp $
 */

constant cvs_version="$Id: database.pike,v 1.7 2010/01/27 12:42:33 astra Exp $";

inherit "/base/serialize.pike";

#include <macros.h>
#include <assert.h>
#include <attributes.h>
#include <database.h>
#include <config.h>
#include <classes.h>
#include <access.h>
#include <roles.h>
#include <events.h>
#include <exception.h>
#include <types.h>
#include <configure.h>

#define MODULE_SECURITY _Server->get_module("security")
#define MODULE_USERS    _Server->get_module("users")

#define PROXY "/kernel/proxy.pike"

private static mapping(string:int)     mCurrMaxID;
private static mapping(int:object  )              mProxyLookup;
private static Thread.Mutex         loadMutex = Thread.Mutex();
private static Thread.Mutex    serializeMutex = Thread.Mutex();
private static Thread.Mutex       createMutex = Thread.Mutex();
private static Thread.Mutex       updateMutex = Thread.Mutex();
private static Thread.Mutex           idMutex = Thread.Mutex();
private static Thread.Mutex      lowSaveMutex = Thread.Mutex();

private static object                oSaveQueue;
private static object              preSaveQueue;
private static mapping               mSaveCount;
private static mapping               mSaveIndex;
private static int               iSaves, iSkips;

private static object               oTlDbHandle;
private static object                 oDbHandle;
private static Thread.Local      dbHandlesLocal;
private static array                  dbHandles;
private static object                tSaveDemon;
private static object             tPreSaveDemon;
private static object            oDemonDbHandle;
private static object                  oModules;

private static Stdio.File              lostData;
private static array(object)     tReaderThreads;
private static object             tWriterThread;
private static Thread.Queue           readQueue;
private static Thread.Queue          writeQueue;
private static Thread.Queue         globalQueue;

#define DBM_UNDEF   0
#define DBM_ID      1
#define DBM_NAME    2

#define CHECKISO(s, mime, obj) if (search(s, mime)>0) { obj->restore_attr_data(mime, DOC_ENCODING); werror(" %s",mime); }
#define SAVESTORE(ident, index) ((ident||"") + "#" + (index||""))

private static mapping(string:object) oModuleCache;
private static Calendar.Calendar cal = Calendar.ISO->set_language("german");

static object SqlHandle(string dbconnect)
{
  object sqlHandle;
  string dbtype;

  sscanf(dbconnect, "%s://%*s", dbtype);

  switch ( dbtype ) {
  case "mysql":
    sqlHandle = new("dbadaptors/mysql.pike", dbconnect);
    break;
  case "postgres":
    sqlHandle = new("dbadaptors/postgres.pike", dbconnect);
    break;
  }
  return sqlHandle;
}


private static int log_save_queue_modulo = 0;

class SqlReadRecord {
  int  iMaxRecNbr; // record number
  int         iID; // doc_it
  int iNextRecNbr; // record number current
  object   dbfile;
  function restore; // function if record needs to be restored
  Thread.Fifo   contFifo;
  Thread.Mutex fullMutex;

  int stopRead = 0;
  int myId = time();

  int check_timeout() {
    if ( objectp(dbfile) ) {
      int t = time() - dbfile->get_last_access();
      if ( !objectp(contFifo) )
	return 0;
      if ( t > 600 )
	return 0;
      return 1;
    }
    return 0;
  }
}


/**
 * return a thread-local (valid) db-handle
 *
 * @param  none
 * @return the database handle
 */
private static Sql.Sql db()
{
    if (this_thread() == tSaveDemon) // give saveDemon its own handle
	return oDemonDbHandle;

#ifdef USE_LOCAL_SQLCONNECT
    if (!objectp(dbHandlesLocal))
      dbHandlesLocal = thread_local();
#endif

    // everybody else gets the same shared handle
    if (!objectp(oDbHandle)) {
        oDbHandle = SqlHandle(STEAM_DB_CONNECT);
        if (!validate_db_handle(oDbHandle))
            setup_sTeam_tables(oDbHandle);
#ifdef USE_LOCAL_SQLCONNECT
	// if oDbHandle is not set this is the initial startup
	dbHandlesLocal->set(oDbHandle);
#endif
    }

#ifdef USE_LOCAL_SQLCONNECT
    object handle = dbHandlesLocal->get();
    if (!objectp(handle)) {
        // this might fail later on!
        mixed err = catch {
	  handle = SqlHandle(STEAM_DB_CONNECT);
	  dbHandles += ({ handle });
	};
	if (err) {
	  handle = oDbHandle;
	  FATAL("Failed to create database handle for Thread - using main handle!");
	}
	  
	dbHandlesLocal->set(handle);
    }
    
    //    FATAL(cal->Second()->format_nice()+": database handle requested.");
    return dbHandlesLocal->get();
#else
    return oDbHandle;
#endif
}

object get_db_handle() 
{
  if ( _Server->is_module(CALLER) )
    return db();
  error("Unauthorized call to get_db_handle!");
}
    
/**
 * mimick object id for serialization etc. 
 * @return  ID_DATABASE from database.h
 * @see    object.get_object_id
 * @author Ludger Merkens 
 */
final int get_object_id()
{
    return ID_DATABASE;
}

private static void db_execute(string db_query)
{
    db()->big_query(db_query);
}

int get_save_size()
{
    return preSaveQueue->size() + oSaveQueue->size();
}

array get_save_queue_size() 
{
  return ({ preSaveQueue->size(), oSaveQueue->size() });
}
  

/**
 * Set logging of the save queue size. If bigger than 0, then the save daemon
 * will output the size of the save queue every "modulo" elements. You can
 * switch this off again by setting this value to 0.
 *
 * @param modulo the save daemon will output the save queue size whenever it
 *   is a multiple of this value
 * @return the previously set modulo
 */
int log_save_queue ( int modulo )
{
  int tmp = log_save_queue_modulo;
  log_save_queue_modulo = modulo;
  return tmp;
}

/**
 * demon function to store pending object saves to the database.
 * This function is started as a thread and waits for objects entering
 * a queue to save them to the database.
 *
 * @param  nothing
 * @return void
 * @see    save_object
 * @author Ludger Merkens 
 */
void database_save_demon()
{
    MESSAGE("DATABASE SAVE DEMON ENABLED");
    mixed job = "";

    while(!intp(job)) {
        // if oSaveQueue contains an integer the server has been stopped
	job = oSaveQueue->read();
	mixed cerr = catch {
          if (arrayp(job)) {
	    object proxy;
	    string ident, index;
	    [proxy, ident, index] = job;

	    low_save_object(proxy, ident, index);
	  }
	  else if (stringp(job)) {
	    if (stringp(job))
	      db_execute(job);
	  }
        };
	int save_size = oSaveQueue->size();
        if ( save_size > 0 &&
	     (log_save_queue_modulo > 0) &&
	     (save_size % log_save_queue_modulo == 0) ) {
          MESSAGE( "database: %d items left to save...", save_size );
          werror( "database: %d items left to save...\n", save_size );
        }

	if ( cerr ) {
	  FATAL("/**************** database_save_demon *************/\n"+
		PRINT_BT(cerr));
	}
    }
    MESSAGE_END("");
    MESSAGE("DATABASE SAVE DEMON EXITED!");
}


private static void emergency_save()
{
  mixed job;
  FATAL("Emergency SAVE of " + get_save_size() + " items ....\n");
  while (preSaveQueue->size() > 0) {
    job = preSaveQueue->read();
    if (arrayp(job))
      low_save_object(job[0], job[1], job[2], 1);
  }
  while (oSaveQueue->size() > 0) {
    job = oSaveQueue->read();
    // save object in kill mode!
    if (arrayp(job))
      low_save_object(job[0], job[1], job[2], 1);
  }
}

/**
 * wait_for_db_lock waits until all pending database writes are done, and
 * afterwards aquires the save_demon lock, thus stopping the demon. Destruct
 * the resulting object to release the save demon again.
 *
 * @param nothing
 * @return the key object 
 * @see Thread.Mutex->lock
 * @author Ludger Merkens
 */
void wait_for_db_lock()
{
  int sz = get_save_size();
  int cnt = 0;

  MESSAGE("Save Demon is %O status=%d", tSaveDemon,
	  objectp(tSaveDemon) ? tSaveDemon->status() : "not available");

  MESSAGE("LowSave Lock currently held by %O %O", 
	  lowSaveMutex->current_locking_key() || "none",
	  lowSaveMutex->current_locking_thread() || "none");

  if (!objectp(tSaveDemon) || tSaveDemon->status() != Thread.THREAD_RUNNING) {
    if (tSaveDemon->status() == Thread.THREAD_EXITED)
      MESSAGE("Save demon EXITED!!!");
    else if (tSaveDemon->status() == Thread.THREAD_NOT_STARTED) 
      MESSAGE("Save demon thread was not yet started!");
    emergency_save();
    return;
  }

  MESSAGE("Waiting to finish SAVE");
  while ( sz > 0 ) {
    write(".");
    int size = get_save_size();
    if ( size == sz )
      cnt++;
    else
      cnt=0;
    if ( cnt > 20 ) {
      // nothing saved ?!
      emergency_save();
    }
    sz = size;
    sleep(2);
  }

  MESSAGE_START("Waiting for Database Save Demon to stop");
  oSaveQueue->write(1); // stop database_save_demon
  cnt = 0;
  while(tSaveDemon->status() != Thread.THREAD_EXITED && cnt < 10) {
    MESSAGE_APPEND(".");
    cnt++;
    oSaveQueue->write(1);
    oSaveQueue->signal();
    sleep(1);
  }
  MESSAGE_END("");
  
  return;
}

/**
 * constructor for database.pike
 * - starts thread to keep objects persistent
 * - enables commands in database
 * @param   none
 * @return  void
 * @author Ludger Merkens 
 */
void create()
{
    // first check for lost data, etc.
  
    mProxyLookup = ([ ]);
    mCurrMaxID = ([ ]);
    oSaveQueue = Thread.Queue();
    preSaveQueue = Thread.Queue();
    oTlDbHandle = thread_local();
    mSaveCount = ([ ]);
    mSaveIndex = ([ ]);
    iSaves = 0;
    iSkips = 0;
}

int get_saves() { return iSaves; }
int get_skips() { return iSkips; }


void init()
{
    _Persistence->register("mysql", this_object());
}

object enable_modules()
{
  if ( CALLER != _Server )
    error("Unauthorized Call to enable_modules!");

  dbHandles = ({ });
  tSaveDemon = thread_create(database_save_demon);
  tPreSaveDemon = thread_create(database_manager);

  tReaderThreads = ({ });
  readQueue = Thread.Queue();
  writeQueue = Thread.Queue();
  globalQueue = Thread.Queue();
  for ( int i = 0; i < 1; i++ )
    tReaderThreads += ({ thread_create(db_reader) });
  tWriterThread = thread_create(db_writer);
  
  oModules = ((program)"/modules/modules.pike")();
  oModuleCache = ([ "modules": oModules ]);
  
  oDemonDbHandle = SqlHandle(STEAM_DB_CONNECT);
  int x=validate_db_handle(oDemonDbHandle);
  if (x==0)
    setup_sTeam_tables(oDemonDbHandle);
  else if (x==1)
    add_new_tables(oDemonDbHandle);
  
  check_journaling(oDemonDbHandle);
  check_tables(oDemonDbHandle);
  check_database_updates(oDemonDbHandle);
  return oModules;
}

//#define DBREAD(l, args...) werror("%O"+l+"\n", Thread.this_thread(), args)
#define DBREAD(l, args ...)

static void add_record(object record)
{
  readQueue->write(record);
}

void db_reader()
{
  SqlReadRecord   record;
  Sql.sql_result odbData;
  array       fetch_line;

  while ( 1 ) {
    DBREAD("Waiting for queue...");
    
    mixed err = catch {
      record = readQueue->read();
      DBREAD("Jobs in readQueue = %d", readQueue->size());
      if ( record->check_timeout() && !record->stopRead ) {
	odbData = db()->big_query
	  ( "select rec_data,rec_order from doc_data"+
	    " where doc_id ="+record->iID+
	    " and rec_order >="+record->iNextRecNbr+
	    " and rec_order < "+(record->iNextRecNbr+READ_ONCE)+
	    " order by rec_order" );
	DBREAD("Queueing read result for %d job=%d",record->iID,record->myId);
	while ( fetch_line=odbData->fetch_row() ) {
	  if ( record->contFifo->size() > 100 ) {
	    break;
	  }
	  record->contFifo->write(db()->unescape_blob(fetch_line[0]));
	  record->iNextRecNbr= (int)fetch_line[1] +1;
	}
	DBREAD("next=%d, last=%d", record->iNextRecNbr, record->iMaxRecNbr);
	if ( record->iNextRecNbr > 0 &&
	     record->iNextRecNbr <= record->iMaxRecNbr) 
	{
	  DBREAD("Continue reading...\n");
	  object mlock = record->fullMutex->lock();
	  if ( record->contFifo->size() > 100 ) 
	    record->restore = add_record;
	  else
	    readQueue->write(record); // further reading
	  destruct(mlock);
	}
	else {
	  DBREAD("Read finished...\n");
	  record->contFifo->write(0);
	}
      }
      else 
	destruct(record);
    };
    if ( err ) {
      FATAL("Error while reading from database: %O", err);
      catch {
	DBREAD("finished read on %d", record->iID);
	record->contFifo->write(0);
      };
    }
  }
}

static void db_writer() {
  while ( 1 ) {
    array job = writeQueue->read(); 
    function|string data;
    int id, iNextRecNbr;
    [id, iNextRecNbr,data] = job;
    if (stringp(data)) {
      string line = "insert into doc_data values('"+
	db()->escape_blob(data)+"', "+ id +", "+iNextRecNbr+")";
      mixed err = catch{db()->big_query(line);};
      if (err) {
	FATAL("Fatal error while writting FILE into database: %O\n%O", err[0], err[1]);
      }
    }
    else if (functionp(data)) {
      catch(data());
    }
  }
}


object read_from_database(int id, int nextID, int maxID, object dbfile) 
{
  SqlReadRecord record = SqlReadRecord();
  record->iID = id;
  record->dbfile = dbfile;
  record->iNextRecNbr = nextID;
  record->iMaxRecNbr = maxID;
  record->contFifo = Thread.Fifo();
  record->fullMutex = Thread.Mutex();
  readQueue->write(record);
  globalQueue->write(record);
  return record;
}

void write_into_database(int id, int iRecNr, string|function data) 
{
  if ( object_program(CALLER) != (program)"/kernel/db_file" )
    error("No Access to write into Database!");
  writeQueue->write(({id, iRecNr, data}));
}

int check_save_demon()
{

  if ( CALLER != _Server ) 
      error("Unauthorized Call to check_save_demon() !");

  int status = tSaveDemon->status();
  //werror(ctime(time())+" Checking Database SAVE DEMON\n");
  if ( status != 0 ) {
    FATAL("----- DATABASE SAVE DEMON restarted ! ---");
    tSaveDemon = thread_create(database_save_demon);
  }
  status = tPreSaveDemon->status();
  if ( status != 0 ) {
    FATAL("----- DATABASE MANAGER DEMON restarted ! ---");
    tSaveDemon = thread_create(database_manager);
  }
  
  foreach(dbHandles, object handle) 
    handle->keep();
  oDbHandle->keep();
  oDemonDbHandle->keep();

  if ( objectp(globalQueue) ) {
    int sz = globalQueue->size();
    while ( sz > 0 ) {
      sz--;
      object record = globalQueue->try_read();
      // record has restore function set for 15 minutes (timeout)
      // this means the record is also not in the readQueue
      if ( objectp(record) ) {
	if ( functionp(record->restore) && !record->check_timeout() ) { 
	  object dbfile = record->dbfile;
	  destruct(record->contFifo);
	  record->contFifo = 0;
	  destruct(record);
	  destruct(dbfile); // make sure everything is gone and freed
	}
	else
	  globalQueue->write(record); // keep
      }
    }
  }     
  return status;
}

void register_transient(array(object) obs)
{
    ASSERTINFO(CALLER==MODULE_SECURITY || CALLER== this_object(), 
	       "Invalid CALLER at register_transient()");
    object obj;
    foreach (obs, obj) {
	if (objectp(obj))
	    mProxyLookup[obj->get_object_id()] = obj;
    }
}


/**
 * set_variable is used to store database internal values. e.g. the last
 * object ID, the last document ID, as well as object ID of modules etc.
 * @param name - the name of the variable to store
 * @param int value - the value
 * @author Ludger Merkens
 * @see get_variable
 */
void set_variable(string name, int value)
{
  if(sizeof(db()->query("SELECT var FROM variables WHERE var='"+name+"'"))) 
  {
    db()->big_query("UPDATE variables SET value='"+value+
                    "' WHERE var='"+name+"'" );
  }
  else
  {
    db()->big_query("INSERT into variables values('"+name+"','"+value+"')");
  }
}

/**
 * get_variable reads a value stored by set_variable
 * @param name - the name used by set_variable
 * @returns int - value previously stored under given name
 * @author Ludger Merkens
 * @see set_variable
 */
int get_variable(string name)
{
    object res;
    res = db()->big_query("select value from variables where "+
                          "var ='"+name+"'");
    if (objectp(res) && res->num_rows())
        return (int) res->fetch_row()[0];
    
    return 0;
}
    
/**
 * reads the currently used max ID from the database and given table
 * and increments. for performance reasons this ID is cached.
 * 
 * @param  int       db - database to connect to
 * @param  string table - table to choose
 * @return int          - the calculated ID
 * @see    free_last_db_id
 * @author Ludger Merkens 
 */
private static
int create_new_database_id(string table)
{
  object lock = idMutex->lock(2);
  mixed err = catch {
    if (!mCurrMaxID[table]) {
      string          query;
      int            result;
      Sql.sql_result    res;
      
      result = get_variable(table);
      if (!result) {
	switch(table)  {
	case "doc_data" :
	  query = sprintf("select max(doc_id) from %s",table);
	  res = db()->big_query(query);
	  result = (int) res->fetch_row()[0];
	  break;
	case "ob_class":
	  query  = sprintf("select max(ob_id) from %s",table);
	  res = db()->big_query(query);
	  result = max((int) res->fetch_row()[0], 1);
	}
      }
      mCurrMaxID[table] = result;
    }
    mCurrMaxID[table] += 1;
    //    MESSAGE("Created new database ID"+(int) mCurrMaxID[table]);
    set_variable(table, mCurrMaxID[table]);
  };
  if ( err != 0 )
    FATAL("Error whilte creating database ID: %O\n%O", err[0], err[1]);
  destruct(lock);
  return mCurrMaxID[table];
}

/**
 * called in case, a newly created database id is obsolete,
 * usually called to handle an error occuring in further handling
 *
 * @param  int       db - Database to connect to
 * @param  string table - table choosen
 * @return void
 * @see    create_new_databas_id()
 * @author Ludger Merkens 
 */
void free_last_db_id(string table)
{
    mCurrMaxID[table]--;
}

/**
 * creates a new persistent sTeam object.
 *
 * @param  string prog (the class to clone)
 * @return proxy and id for object
 *         note that proxy creation implies creation of associated object.
 * @see    kernel.proxy.create, register_user
 * @author Ludger Merkens 
 */
mixed new_object(object obj, string prog_name)
{
    int         new_db_id;
    object p;
    // check for valid object has to be added
    // create database ID

    if ( CALLER != _Persistence )
      error("Only Persistence Module is allowed to get in here !");

    int id = obj->get_object_id();
    if ( id )
    {
	ASSERTINFO((p=mProxyLookup[id])->get_object_id() == id,
		   "Attempt to reregister object in database!");
	return ({ id, p });
    }
    
    object lock = createMutex->lock(); // make sure creation is save

    mixed err = catch {

      new_db_id = create_new_database_id("ob_class");
      
      p = new(PROXY, new_db_id, obj );
      if (!objectp(p->get_object())) // error occured during creation
      {
	  free_last_db_id("ob_class");
	  destruct(p);
      }
      
      // insert the newly created Object into the database
      if (prog_name!="-") {
	if ( search(prog_name, "classes/") == 0 ) {
	  // something is wrong here - when does this happen ??
	  prog_name = "/" + prog_name; // use absolute path for classes
	  FATAL("database.new_object: Warning - incorrect program name !");
	}
	Sql.sql_result res1 = db()->big_query(
		     sprintf("insert into ob_class (ob_id, ob_class) values "+
			     "(%d, '%s')", new_db_id, prog_name)
		     );
        mProxyLookup[new_db_id] = p;
        save_object(p, 0);
      }
    };
    if ( err ) {
      FATAL("database.new_object: failed to create object\n %O", err);
    }

    destruct(lock); 

    return ({ new_db_id, p});
}

/**
 * permanently destroys an object from the database.
 * @param  object represented by (proxy) to delete
 * @return (0|1)
 * @see    new_object
 * @author Ludger Merkens 
 */
bool delete_object(object p)
{
  if ( CALLER!=_Persistence &&
       (!MODULE_SECURITY->valid_object(CALLER) || CALLER->this() != p->this()))
  {
    werror("caller of delete_object() is %O\n", CALLER);
    THROW("Illegal call to database.delete_object", E_ACCESS);
  }
  return do_delete(p);
}

private bool do_delete(object p)
{
    object proxy;
    int iOID = p->get_object_id();
    db()->query("delete from ob_data where ob_id = "+iOID);
    db()->query("delete from ob_class where ob_id = "+iOID);
    proxy = mProxyLookup[iOID];
    if ( objectp(proxy) )
      catch(proxy->set_status(PSTAT_DELETED));
    m_delete(mProxyLookup, iOID);

    return 1;
}

static void fail_unserialize(int iOID, string sData, mapping mData, mapping oldData)
{
  FATAL("MISMATCH in unserialize %d\n%s\nNEW=%O\n\nOLD=%O\n", iOID, sData,
	mData,
	oldData);
}


/**
 * load and restore values of an object with given Object ID
 * @param   int OID
 * @return  0, object deleted
 * @return  1, object failed to compile
 * @return  2, objects class deleted
 * @return  3, object fails to load
 * @return  the object
 * @see
 * @author Ludger Merkens 
 */
int|object load_object(object proxy, int|object iOID)
{
    string      sClass;
    string      sIdent;
    string     sAttrib;
    string       sData;
    object           o;

    if ( CALLER != _Persistence )
      error("Unable to load objects directly !");
        
    mixed catched;
    
    Sql.sql_result res = db()->big_query(
        sprintf("select ob_class from ob_class where ob_id = %d", iOID)
        );
    mixed line = res->fetch_row();
    // object deleted?!
    if (!arrayp(line))
        return 0;

    if (objectp(iOID)) {
        o = iOID;
    }
    else
    {
        catched = catch {
	  sClass = line[0];
	  int pos;
	  if ( (pos = search(sClass, "DB:#")) >= 0 ) {
	    sClass = "/"+sClass[pos..];
            if (search(sClass, ".pike")==-1)
              sClass += ".pike";
	  }
	  o = new(sClass, proxy);
        };

        if (!objectp(o)) // somehow failed to load file
        {
            if ( catched ) {
                _Server->add_error(time(), catched);
		string pikeClass = sClass;
		sscanf(pikeClass, "%s.pike", pikeClass);
                if (!master()->master_file_stat(pikeClass+".pike")) {
		  return 2;
		}
                FATAL("Error loading object %d (%s)\n%s", iOID, sClass, 
                      master()->describe_backtrace(catched));
            }
            return 1; // class exists but failes to compile
        }
        proxy->set_steam_obj(o); // o is the real thing - no proxy!
    }
    mapping mData;

    res = db()->big_query(
        sprintf("select ob_ident, ob_attr, ob_data from ob_data where "+
                "ob_id = %d", iOID));

    mapping mStorage = get_storage_handlers(o);
    if ( !mappingp(mStorage) || sizeof(mStorage) == 0 ) {
	proxy->set_status(PSTAT_FAIL_UNSERIALIZE);
	FATAL("Setting UNSERIALIZE on %O - no storage map!\n%O", proxy, 
	      backtrace());
	FATAL("OBJECT is %O", o);
	return 3;
    }
    mapping mIndexedStorage = ([]);

    foreach(indices(mStorage), string _ident) // precreate indexed idents
        if (mStorage[_ident][2])
            mIndexedStorage[_ident]=([]);
    
    while (line = res->fetch_row())
    {
        [sIdent, sAttrib, sData] = line;
        catched = catch {
#if !constant(steamtools.unserialize) || !USE_CSERIALIZE
	  mData = unserialize(sData); // second arg is "this_object()"
#else          
          mixed sErr = catch(mData = steamtools.unserialize(sData, find_object));
          if ( sErr ) {
            FATAL("Failed to load object - error in unserialize: %O\nData:%O",
                  sErr[0], sData);
          }
#if constant(check_equal) 
#ifdef VERIFY_CMOD
	  mapping oldData = unserialize(sData);
	  if ( !check_equal(mData, oldData) ) {
	    call(fail_unserialize, 1, iOID, sData, mData, oldData);
	    //exit(1);
	  }
#endif
#endif	  
#endif
        };
        if ( catched ) {
	    FATAL("While loading ("+iOID+","+sClass+"):\n%O\n%O\n%O",
		  sData,
		  catched[0], 
		  catched[1]);
            proxy->set_status(PSTAT_FAIL_UNSERIALIZE);
	    werror("Setting UNSERIALIZE on %O - error while loading!!\n", proxy);
            return 3;
        }
        if ( sAttrib != "")
        {
	  if ( !mIndexedStorage[sIdent] ) {
	    FATAL("WARNING:  Missing Storage %s in %d, %s, attrib=%O", 
		  sIdent, iOID, sClass, sAttrib);
	    continue;
	  }
	  mIndexedStorage[sIdent][sAttrib]=mData;
        }
	else if ( !mStorage[sIdent] ) {
	  FATAL("No storage handler %s defined in %d (%s).\ndata=%O",
		sIdent, iOID, sClass, mData); // INFO ?!
	}
        else
        {
	  catched = catch {
	    if ( proxy->is_loaded() ) {
	      error(sprintf("Fatal error: already loaded %O\n", proxy));
	    }
	    mStorage[sIdent][1](mData); // actual function call
	  };
	  if ( catched ) {
	    FATAL("Error while loading (%d, %s)\n"+
		  "Error while calling storage handler %s: %O\n"+
		  "Full Storage:%O\nData: %O", 
		  iOID, sClass,
		  sIdent, catched, 
		  mStorage, mData);
	  }
        }
    } 
    
    foreach(indices(mIndexedStorage), string _ident)
        mStorage[_ident][1](mIndexedStorage[_ident]); // prepared call

    mixed err = catch { 
      if ( !mSaveCount[o->this()] )
	o->this()->set_status(PSTAT_SAVE_OK);
      o->loaded(); 
    };
    if ( err != 0 ) 
      FATAL("POST load failure: %O\n%O", err[0], err[1]);
    return o;
}

static mapping get_storage_handlers(object o)
{
    if ( !objectp(o) )
	FATAL("Getting storage handlers for %O", o);
    
    mapping storage = _Persistence->get_storage_handlers(o);
    return storage;
}

mixed call_storage_handler(function f, mixed ... params)
{
  if ( CALLER != _Persistence )
    error("Database:: call_storage_handler(): Unauthorized call !");
  mixed res = f(@params);
  return res;
}

int get_class_id(string classname) 
{
  switch(classname) {
  case "/classes/Object":
    return CLASS_OBJECT;
  case "/classes/User":
    return CLASS_OBJECT + CLASS_CONTAINER + CLASS_USER;
  case "/classes/Group":
    return CLASS_GROUP + CLASS_OBJECT;
  case "/classes/Container":
    return CLASS_OBJECT + CLASS_CONTAINER;
  case "/classes/Room":
    return CLASS_OBJECT + CLASS_CONTAINER + CLASS_ROOM;
  case "/classes/Link":
    return CLASS_OBJECT + CLASS_LINK;
  case "/classes/Exit":
    return CLASS_OBJECT + CLASS_LINK+CLASS_EXIT;
  case "/classes/Document":
    return CLASS_OBJECT + CLASS_DOCUMENT;
  case "/classes/Messageboard":
    return CLASS_MESSAGEBOARD + CLASS_OBJECT;
  case "/classes/Drawing":
    return CLASS_DRAWING + CLASS_OBJECT;
  case "/classes/Date":
    return CLASS_OBJECT + CLASS_DATE;
  case "/classes/DocXSL":
    return CLASS_OBJECT + CLASS_DOCUMENT + CLASS_DOCXSL;
  case "/classes/DocHTML":
    return CLASS_OBJECT + CLASS_DOCUMENT + CLASS_DOCHTML;
  default:
    return 0;
  }
}

string get_class_string(int classid) 
{
  for (int i=0;i<32;i++)
    if ( classid & (1<<i))
      classid = (1<<i);
  
  switch(classid) {
  case CLASS_ROOM:
    return "/classes/Room";
  case CLASS_USER:
    return "/classes/User";
  case CLASS_CONTAINER:
    return "/classes/Container";
  case CLASS_DOCUMENT:
    return "/classes/Document";
  case CLASS_GROUP:
    return "/classes/Group";
  case CLASS_LINK:
    return "/classes/Link";
  case CLASS_EXIT:
    return "/classes/Exit";
  case CLASS_MESSAGEBOARD:
    return "/classes/Messageboard";
  case CLASS_DRAWING:
    return "/classes/Drawing";
  }
  return "/classes/Object";
}

/**
 * find an object from the global object cache or retreive it from the
 * database.
 *
 * @param  int - iOID ( object ID from object to find ) 
 * @return object (proxy associated with object)
 * @see    load_object
 * @author Ludger Merkens 
 */
final object find_object(int|string iOID)
{
    object p;

    if ( stringp(iOID) ) 
	return _Server->get_module("filepath:tree")->path_to_object(iOID);

    if ( !intp(iOID) )
	THROW("Wrong argument to find_object() - expected integer!",E_ERROR);

    if ( iOID == 0 ) return 0;
    if ( iOID == 1 ) return this_object();
    
    if ( objectp(p = mProxyLookup[iOID]) )
	return p;

    Sql.sql_result res;
    
    res = db()->big_query(sprintf("select ob_class from ob_class"+
				  " where ob_id = %d", iOID));
    
    if (!objectp(res) || res->num_rows()==0)
        return 0;

    // create an empty proxy to avoid recursive loading of objects
    array row = res->fetch_row();
    p = new(PROXY, iOID, UNDEFINED, get_class_id(row[0]));
    mProxyLookup[iOID] = p;

    return p;
}

/**
 * The function is called to set a flag in an object for saving.
 * Additionally the functions triggers the global EVENT_REQ_SAVE event.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see save_object
 */
void require_save(object proxy, void|string ident, void|string index, void|int action, void|array args)
{
    if (proxy && proxy->status()>=PSTAT_SAVE_OK) {
      preSaveQueue->write( ({ proxy, ident, index }) );
    }
}

static void database_manager()
{
  while ( 1 ) {
    object proxy;
    string ident;
    string index;

    [proxy, ident, index] = preSaveQueue->read();
    save_object(proxy, ident, index);
  }
}


/**
 * callback-function called to indicate that an object has been modified
 * in memory and needs to be saved to the database.
 *
 * @param  object p - (proxy) object to be saved
 * @return void
 * @see    load_object
 * @see    find_object
 * @author Ludger Merkens 
 */
static void
save_object(object proxy, void|string ident, void|string index)
{
    if ( !objectp(proxy) )
	return;

    string savestore = SAVESTORE(ident,index); 

    Thread.MutexKey low=lowSaveMutex->lock();
    mixed err = catch {
      if (!mappingp(mSaveIndex[proxy]))
	mSaveIndex[proxy] = ([ ]);
      
      if (mSaveIndex[proxy][savestore] == 1) {
	iSkips++;
	destruct(low);
	return;
      }
      
      if (proxy->status() == PSTAT_SAVE_OK) {
	proxy->set_status(PSTAT_SAVE_PENDING);
	if ( !mSaveCount[proxy] )
	  mSaveCount[proxy] = 0;
      }
      
      mSaveIndex[proxy][savestore] = 1;
      mSaveCount[proxy] = mSaveCount[proxy] + 1;
    };
    if (err) {
      FATAL("Failure in save_object(): %O\n%O", err[0], err[1]);
    }
    destruct(low);

    oSaveQueue->write(({proxy, ident, index }));
}

/**
 * quote and check for maximum length of serialized data.
 * @param string data      - string to handle
 * @param object o         - object saved (for error reporting)
 * @param string ident     - ident block (for error reporting)
 * @author <a href="mailto:balduin@upb.de">Ludger Merkens</a>
 */
private static string
quote_data(mixed data, object o, string ident, function quoter, int|void utf8)
{
    string sdata;
    data = copy_value(data);
    if (utf8) {
        sdata = serialize(data, "utf-8");
    }
    else {
#if constant(steamtools.serialize) && USE_CSERIALIZE
        sdata = steamtools.serialize(data);
#ifdef VERIFY_CMOD
	string verifydata = serialize(data);
	if ( sdata != verifydata ) {
	  // unable to verify mappings: index is not the same
	  if ( (mappingp(data) && strlen(sdata) != strlen(verifydata)) || !mappingp(data) )
	    FATAL("Failed to verify quoted data, steamtools.serialize returns %O, should be %O\ndata=%O", sdata, verifydata, data);
	  sdata = verifydata;
	}
#endif
#else
        sdata = serialize(data);
#endif
    }
    
    if (strlen(sdata)> 16777215)
        FATAL("!!! FATAL - data truncated inserting %d bytes for %s block %s",
              strlen(data),
              (objectp(o) ? "broken" : o->get_identifier()),
              ident);
    return quoter(sdata);
}

/**
 * generate a "mysql-specific" replace statement for saving data according
 * to needs of require_save()
 * @param object o          - object to save data from
 * @param mapping storage   - storage_data to access
 * @param string|void ident - optional arg to limit to ident
 * @param string|void index - optional arg to limit to index
 * @return the mysql statement
 * @author Ludger Merkens
 */
private static array(string)
prepare_save_statement(object o, mapping storage,
                       string|void ident, string|void index)
{
    int oid = o->get_object_id();
    mapping statements = ([]);
    // in case you change the behavoir below - remember to change
    // behaviour in prepeare_clear_statement also
    array(string) idents =
        arrayp(storage[ident]) ? ({ ident }) : indices(storage);
    string data;
    string sClass = master()->describe_program(object_program(o->get_object()));
    function db_quote_data = db()->quote;
    foreach(idents, string _ident)
    {
        if (!arrayp(storage[_ident]))
        {
            FATAL("missing storage handler for _ident %O\n", _ident);
            FATAL("prepare_save_statement object=%O, storage=%O, "+
		  "ident=%O, index=%O\n", o, storage, ident, index);
        }
        else if (storage[_ident][2]) // an indexed data-storage
        {
            if (zero_type(index))
            {
                mapping mData = storage[_ident][0](); // retrieve all
                foreach(indices(mData), mixed _index)
                {
                    if (!stringp(_index))
                        continue;
                    data = quote_data(mData[_index], o, _ident,
                                      db_quote_data);
                    statements[_ident+_index] = 
		      sprintf("(%d,'%s','%s','%s')",
			      oid, _ident, db_quote_data(_index),
			      data );
                }
            }
            else
            {
                if (_ident != "user" && index!="UserPassword")
                  data = quote_data(storage[_ident][0](index), o, _ident,
                                    db_quote_data);
                else
                  data = quote_data(storage[_ident][0](index), o, _ident,
                                    db_quote_data); // never convert user pw
                                                      // to utf8
                statements[_ident+index] = 
		  sprintf("(%d,'%s','%s','%s')",
			  oid, _ident, db_quote_data(index), data);
            }
            
        }
        else // the usual unindexed data-storage
	  {
	    data = quote_data(storage[_ident][0](), o, "all", db_quote_data);
            statements[_ident] = 
	      sprintf("(%d,'%s','%s','%s')",
		      oid, _ident, "", data);
        }
    }
    return values(statements);
}


/**
 * generate a delete statement that will clear all entries according to
 * the data that will be saved.
 * @author Ludger Merkens
 * @see prepare_save_statement
 */
private static string
prepare_clear_statement(object o, mapping storage,
                        string|void ident, string|void index, string|void tb)
{
    if ( !stringp(tb) )
      tb = "ob_data";

    if (ident=="0" || index=="0")
      FATAL("strange call to prepare_clear_statement \n%s\n",
	    describe_backtrace(backtrace()));
    
    if (!storage[ident]) ident =0; // better save then sorry - wrong ident
                                   // invoces a full save.
    if (ident && index)
        return sprintf("delete from %s where ob_id='%d' and "+
                       "ob_ident='%s' and ob_attr='%s'",
                       tb, o->get_object_id(), ident, index);
    else if (ident)
        return sprintf("delete from %s where ob_id='%d' and "+
                       "ob_ident='%s'", tb, o->get_object_id(), ident);
    else
        return sprintf("delete from %s where ob_id='%d'",
                       tb, o->get_object_id());
        
}

/**
 * low level database function to store a given (proxy) object into the
 * database immediately.
 *
 * @param  object proxy - the object to be saved
 * @return void
 * @see    save_object
 * @author Ludger Merkens 
 */
private static void
low_save_object(object p, string|void ident,string|void index,int|void killed)
{
    array(string) sStatements;

    int stat = p->status();
    // saved twice while waiting
    if (stat==PSTAT_DISK || stat==PSTAT_DELETED || stat==PSTAT_FAIL_DELETED) 
    {
      m_delete(mSaveCount, p);
      m_delete(mSaveIndex, p);
      return; // low is local so this will unlock also
    }

    ASSERTINFO(!objectp(MODULE_SECURITY) ||
	       MODULE_SECURITY->valid_object(p),
	       sprintf("invalid object in database.save_object: %O",p));

    if (p->status() < PSTAT_SAVE_OK)
    {
	FATAL("DBSAVEDEMON ->broken instance not saved(%d, %s, status=%s)",
              p->get_object_id(),
              master()->describe_object(p->get_object()),
	      PSTAT(p->status()));
	return;
    }

    if ( !p->is_loaded() ) {
	FATAL("DBSAVEDEMON ->trying to save an object that was not "+
	      "previously loaded !!!!!\nObject ID="+p->get_object_id()+"\n");
	return;
    }

    if (p->status()<PSTAT_SAVE_OK) 
      THROW("Invalid proxy status for object:"+
            p->get_object_id()+"("+p->status()+")", E_MEMORY);
    mapping storage = get_storage_handlers(p);
    if ( !mappingp(storage) )
      THROW("Corrupted data_storage in "+master()->stupid_describe(p), E_MEMORY);

    if (master()->describe_program(object_program(p->get_object()))=="-")
        return; // temporary objects like executer
    
    sStatements =
        prepare_save_statement(p, storage, ident, index );

    ASSERTINFO(sizeof(sStatements)!=0,
               sprintf("trying to insert empty data into object %d class %s",
                    p->get_object_id(),
	       master()->describe_program(object_program(p->get_object()))));
    
    mixed err;
    if (!killed) {
      Thread.MutexKey low=lowSaveMutex->lock();
      err = catch {
	mSaveCount[p]--;
	
	iSaves++;
	if ( !mappingp(mSaveIndex[p]) ) {
	  FATAL("Save index not mapped in %O, SaveCount = %O\n",
		p, mSaveCount[p]);
	}
	else {
	  mSaveIndex[p][SAVESTORE(ident, index)] = 0;
	}
	if ( mSaveCount[p] <= 0 ) {
	  m_delete(mSaveCount, p);
	  m_delete(mSaveIndex, p);
	  p->set_status(PSTAT_SAVE_OK);
	}
      };
      if (err) {
	FATAL("Error in low_save_object(): %O\n%O", err[0], err[1]);
      }
      destruct(low);  // status set, so unlock
    }

    string s;
    err = catch {
      // remove from ob_data
      db()->big_query("BEGIN;");
      mixed delete_err = catch {
	s = prepare_clear_statement(p, storage, ident, index, "ob_data");
	db()->big_query(s);
      };
      if ( delete_err ) 
	FATAL("FATAL in save-demon, deletion statement %s failed\n%O:%O\n",
	      s, delete_err[0], delete_err[1]);
      
      // add new value
      s = db()->create_insert_statement(sStatements);
      db()->big_query(s);
      db()->big_query("COMMIT;");
    };
    if ( err )
    {
      FATAL("FATAL - Error in save-demon ------------\n%s\n---------!!!",
	    master()->describe_backtrace(err));
      if ( objectp(lostData) ) 
	catch(lostData->write(sprintf("%d: %s--\n\n", p->get_object_id(), 
				      (sStatements*"\n")+"\n")));
    }

    err = catch(update_classtable(p, index));
    if ( err ) {
      FATAL("ERROR IN SAVE-DEMON (Updating classtable): %O\n%O\n", 
	    err[0], err[1]);
    }
}

static string db_get_path(int oid)
{
  string path = db_get_attribute(oid, OBJ_PATH);

  if ( !zero_type(path) ) 
    return path;

  object env = db_get_attribute(oid, "Environment");
  if ( !objectp(env) ) {
    object obj = find_object(oid);

    if ( !(obj->get_object_class() & CLASS_ROOM) )
      path = "";
    else if ( !objectp(_ROOTROOM) )
      path = "";
    else 
      path = _FILEPATH->object_to_filename(obj);

    if ( obj->status() == PSTAT_SAVE_OK || obj->status() == PSTAT_DISK ) {
      string query = sprintf("INSERT into ob_data values (%d,'%s','%s','%s')",
                             oid, "attrib", OBJ_PATH, 
                             oDemonDbHandle->quote(serialize(path)));
      oDemonDbHandle->query(query);
    }
    return path;
  }
  path = db_get_path(env->get_object_id());
  path = path + (path != "/"?"/":"") + db_get_attribute(oid, OBJ_NAME);

  string query = sprintf("INSERT into ob_data values (%d,'%s','%s','%s')",
                         oid, "attrib", OBJ_PATH, 
                         oDemonDbHandle->quote(serialize(path)));
  oDemonDbHandle->query(query);

  return path;
}


static mixed db_get_attribute(int oid, string attribute)
{      
  string q;
  q = "select ob_data from ob_data where ob_attr='"+attribute+
    "' and ob_id='"+ oid+"'";
  object data = oDemonDbHandle->big_query(q);
  if ( objectp(data) && data->num_rows() > 0 )
    return unserialize(data->fetch_row()[0]);  
  return UNDEFINED;
}

static void update_classtableobject(int oid, void|object obj)
{
  object lock = updateMutex->lock(2); // only lock for current thread

  mixed err = catch {
    string name = db_get_attribute(oid, OBJ_NAME) || "";
    string desc = db_get_attribute(oid, OBJ_DESC) || "";
    array keywords = db_get_attribute(oid, OBJ_KEYWORDS);
    if ( !arrayp(keywords) )
        keywords = ({ });
    keywords += ({ name, desc });
    string mimetype = db_get_attribute(oid, DOC_MIME_TYPE) || "";
    mixed versionof = db_get_attribute(oid, OBJ_VERSIONOF) || "";
    if ( objectp(versionof) )
        versionof = versionof->get_object_id();
    
    string query = "UPDATE ob_class SET"+
        " obkeywords='"+oDemonDbHandle->quote(keywords*" ")+
        "', obname='"+oDemonDbHandle->quote(name)+
        "', obdescription='"+oDemonDbHandle->quote(desc)+
        "', obmimetype='"+oDemonDbHandle->quote(mimetype)+
        "', obversionof='" + versionof + "' WHERE ob_id='"+oid+"'";
    oDemonDbHandle->big_query(query);
  };
  destruct(lock);
  if ( err ) {
    FATAL("Error while updating class index %O\n%O", err[0], err[1]);
    throw(err);
  }
}

static void update_classtable(object p, void|string index)
{
  if (stringp(index)) {
    if (index == OBJ_NAME || index == OBJ_DESC || index == DOC_MIME_TYPE ||
        index == OBJ_KEYWORDS || index == OBJ_VERSIONOF) 
      update_classtableobject(p->get_object_id());
  }
  else
    update_classtableobject(p->get_object_id(), p);
}

/**
 * Change the class of an object in the database. Drop the object to
 * get an object with the modified class.
 *  
 * @param object doc - change class for this document
 * @param string classfile - the new class
 */
int change_object_class(object doc, string classfile)
{
    if ( CALLER != _Persistence )
	steam_error("Illegal call to database.change_class() !");
    
    if ( !functionp(doc->get_object_id) )
	steam_error("database.change_class: object is no valid steam object!");
    int id = doc->get_object_id();

    classfile = CLASS_PATH + classfile; // only from classes directory
    MESSAGE("Changing Document class of %d to %s", id, classfile);
    db()->query("delete from ob_class where ob_id='" + id+"'");
    db()->query("insert into ob_class (ob_id, ob_class) values (%d, '%s')",
		id, classfile);
    return 1; 
}


/**
 * register an module with its name
 * e.g. register_module("users", new("/modules/users"));
 *
 * @param   string - a unique name to register with this module.
 * @param   object module - the module object to register
 * @param   void|string source - a source directory for package installations 
 * @return  (object-id|0)
 * @see     /kernel/db_mapping, /kernel/secure_mapping
 * @author  Ludger Merkens 
 */
int register_module(string oname, object module, void|string source)
{
    object realObject;
    string version = "";

    //FATAL(sprintf("register module %s with %O source %O", oname, module, source));
    if ( CALLER != _Server && 
	 !MODULE_SECURITY->access_register_module(0, 0, CALLER) )
	THROW("Unauthorized call to register_module() !", E_ACCESS);

    object mod;
    int imod = get_variable("#" + oname);

    if ( imod > 0 )
    {
	mod = find_object(imod); // get old module
	if ( objectp(mod) && mod->status() >= 0 && 
	     mod->status() != PSTAT_DELETED) 
	{
	    object e = master()->getErrorContainer();
	    master()->set_inhibit_compile_errors(e);
	    realObject = mod->get_object();
	    master()->set_inhibit_compile_errors(0);
	    if (!realObject)
	    {
		FATAL("Failed to compile update instance, re-installing");
	    }
	}
    }    

    if ( objectp(realObject) && functionp(realObject->version) &&
	 functionp(realObject->upgrade) ) 
    {
	FATAL("Found previously registered version of module !");
	if ( objectp(module) && module->get_object() != realObject )
	    THROW("Trying to register a previously registered module.",
		  E_ERROR);
	
	version = realObject->get_version();
	
	mixed erg = master()->upgrade(object_program(realObject));
	if (!intp(erg) ||  erg<0)
	{
	    if (stringp(erg))
		THROW(erg, backtrace());
	    else
	    {
		FATAL("New version of "+oname+" doesn't implement old "+
		    "versions interface");
		master()->upgrade(object_program(mod->get_object()),1);
	    }
	}
        module = mod;
    }
    else if ( !objectp(module) ) 
    {
	// module is in the /modules directory.
	object e = master()->getErrorContainer();
	master()->set_inhibit_compile_errors(e);
	module = new("/modules/"+oname+".pike");
	master()->set_inhibit_compile_errors(0);
	if (!module)
	{
	    FATAL("Failed to compile new instance - throwing");
	    THROW("Failed to load module\n"+e->get()+"\n"+
		  e->get_warnings(), backtrace());
	}
    }
    
    MESSAGE("Installing module %s ...", oname);
    if ( !stringp(source) )
	source = "";
    
    if ( module->get_object_class() & CLASS_PACKAGE ) {
	
	if ( module->install(source, version) == 0 )
	    error(sprintf("Failed to install module %s !", oname));
        else
          MESSAGE("Installation of module %s succeeded.", oname);
    }    
    _Server->register_module(module);

    _Server->run_global_event(EVENT_REGISTER_MODULE, PHASE_NOTIFY, 
			      this_object(), ({ module }) );
    LOG_DB("event is run");
    if ( objectp(module) ) 
    {
	set_variable("#"+oname, module->get_object_id());
	_Server->register_module(module);
	return module->get_object_id();
    }
    return 0;
}

/**
 * Check if a database handle is connected to a properly setup database.
 *
 * @param   Sql.Sql handle - the handle to check
 * @return  1 - old format
 * @return  2 - new format
 * @see     setup_sTeam_tables
 * @author  Ludger Merkens 
 */
int validate_db_handle(object handle)
{
    multiset tables = (<>);
    array(string) aTables = handle->list_tables();

    foreach(aTables, string table)
	tables[table] = true;
    if (tables["objects"] && tables["doc_data"])
        return 1;
    if (tables["ob_class"] && tables["ob_data"] && tables["doc_data"])
        return 2;
}

static void add_database_update(object handle, string name)
{
  handle->query("insert into database_updates values(\""+name+"\")");
}

static int is_database_update(object handle, string name)
{
  object result = handle->big_query("select * from database_updates where "
                                    + "(database_update='" + name + "')");
  if ( !objectp(result) || result->num_rows() == 0 )
    return 0;
  return 1;
}

static int check_database_updates(object handle)
{
  if ( search(handle->list_tables(), "database_updates") == -1 ) {
    handle->query("create table database_updates (database_update char(128))");
  }

  // depending objects: from attribute to data storage
  if ( !is_database_update( handle, "depending_objects_data_store" ) ) {
    MESSAGE( "Database update: converting depending objects" );
    werror( "Database update: converting depending objects\n" );
    // replace OBJ_DEPENDING_OBJECTS with DependingObjects:
    object res = oDemonDbHandle->big_query( "select * from ob_data where "
      + "(ob_ident='attrib' and ob_attr='OBJ_DEPENDING_OBJECTS')" );
    array rows = ({ });
    if ( objectp(res) ) {
      for ( int i=0; i<res->num_rows(); i++ ) {
        mixed row = res->fetch_row();
        if ( !arrayp(row) || sizeof(row) < 4 ) continue;
        rows += ({ row });
      }
    }
    foreach ( rows, mixed row ) {
      mixed dbres = oDemonDbHandle->big_query( "select ob_id from ob_data "
        + "where (ob_id=" + row[0] + " and ob_ident='data' and "
        + "ob_attr='DependingObjects')" );
      if ( !objectp(dbres) || dbres->num_rows() < 1 )
        oDemonDbHandle->big_query( "insert into ob_data "
          + "(ob_id,ob_ident,ob_attr,ob_data) values("
          + row[0] + ",'data','DependingObjects','" + row[3] + "')" );
      dbres = oDemonDbHandle->big_query( "select ob_id from ob_data where "
        + "(ob_id=" + row[0] + " and ob_ident='data' and "
        + "ob_attr='DependingObjects')" );
      if ( objectp(dbres) && dbres->num_rows() > 0 ) {
        oDemonDbHandle->big_query( "delete from ob_data where (ob_id="
          + row[0] + " and ob_ident='attrib' and "
          + "ob_attr='OBJ_DEPENDING_OBJECTS')" );
      }
    }
    // replace OBJ_DEPENDING_ON with DependingOn:
    res = oDemonDbHandle->big_query( "select * from ob_data where "
      + "(ob_ident='attrib' and ob_attr='OBJ_DEPENDING_ON')" );
    rows = ({ });
    if ( objectp(res) ) {
      for ( int i=0; i<res->num_rows(); i++ ) {
        mixed row = res->fetch_row();
        if ( !arrayp(row) || sizeof(row) < 4 ) continue;
        rows += ({ row });
      }
    }
    foreach ( rows, mixed row ) {
      mixed dbres = oDemonDbHandle->big_query( "select ob_id from ob_data "
        + "where (ob_id=" + row[0] + " and ob_ident='data' and "
        + "ob_attr='DependingOn')" );
      if ( !objectp(dbres) || dbres->num_rows() < 1 )
        oDemonDbHandle->big_query( "insert into ob_data "
          + "(ob_id,ob_ident,ob_attr,ob_data) values("
          + row[0] + ",'data','DependingOn','" + row[3] + "')" );
      dbres = oDemonDbHandle->big_query( "select ob_id from ob_data where "
        + "(ob_id=" + row[0] + " and ob_ident='data' and "
        + "ob_attr='DependingOn')" );
      if ( objectp(dbres) && dbres->num_rows() > 0 ) {
        oDemonDbHandle->big_query( "delete from ob_data where (ob_id="
          + row[0] + " and ob_ident='attrib' and "
          + "ob_attr='OBJ_DEPENDING_ON')" );
      }
    }
    // check whether there are still OBJ_DEPENDING_* attributes:
    res = oDemonDbHandle->big_query( "select * from ob_data where "
      + "(ob_ident='attrib' and (ob_attr='OBJ_DEPENDING_OOBJECTS' or "
      + "ob_attr='OBJ_DEPENDING_ON'))" );
    if ( objectp(res) && res->num_rows() == 0 ) {
      add_database_update( handle, "depending_objects_data_store" );
      werror( "Database update: finished depending objects update.\n" );
      MESSAGE( "Database update: finished depending objects update." );
    }
    else {
      werror( "Database update: errors occurred, there are still %O "
              + "depending object entries. Will run update again on next "
              + "server restart.\n", res->num_rows() );
      MESSAGE( "Database update: errors occurred, there are still %O "
              + "depending object entries. Will run update again on next "
              + "server restart.", res->num_rows() );
    }
  }
}

int check_updates()
{
  object dbupdates = _Server->get_update("database");
  if ( !objectp(dbupdates) ) {
    dbupdates = get_factory(CLASS_CONTAINER)->execute((["name":"database"]));
    _Server->add_update(dbupdates);
  }
  mapping result = oDemonDbHandle->check_updates(dbupdates, 
						 update_classtableobject);
  foreach(indices(result), string updateIdx) {
    object update = get_factory(CLASS_DOCUMENT)->execute((["name":updateIdx,
						  "mimetype":"text/plain"]));
    update->set_content(result[updateIdx]);
    update->move(dbupdates);
  }

  return 0;
}

static void check_tables(object handle)
{
  handle->check_tables();
}

static void check_journaling(Sql.Sql handle) 
{
  mixed row, res, err;

  string lost = Stdio.read_file("/tmp/lost_data."+BRAND_NAME);
  lostData = Stdio.File("/tmp/lost_data."+BRAND_NAME, "wct");
  if ( stringp(lost) && strlen(lost) > 0 ) {
    array lostlines = lost / "--\n\n";
    foreach(lostlines, string ll) {
      werror("LOST DATA: Restoring %s\n", ll);
      MESSAGE("LOST DATA: Restore %s", ll);
      int oid;
      string ident, attr, val, rest;
      if ( sscanf(ll, "%d: %s", oid, ll) != 2 )
	continue;
      while ( sscanf(ll, "(%*s,%s,%s,%s)\n%s", ident, attr, val, rest) >= 3 ) {
	werror("values are %O %O %O %O\n", oid, ident, attr, val);
	err = catch {
	  res = handle->query(sprintf("select ob_data from ob_data where ob_id='%d' and ob_ident=%s and ob_attr=%s", oid, ident, attr));
	  row = res->fetch_row();
	  if ( sizeof(row) > 0 ) {
	    handle->query(sprintf("update ob_data SET ob_data=%s where ob_id='%d' and ob_ident=%s and ob_attr=%s", val, oid, ident, attr));
	    werror("updated!\n");
	  }
	  else {
	    handle->query(sprintf("insert into ob_data values (%d,%s,%s,%s)",
				  oid, ident, attr, val));
	  }
	  ll = rest;
	};
	if ( err ) {
	  FATAL("Failed to restore data: %O", err);
	}
	if ( stringp(rest) || strlen(rest) > 1 )
	  ll = rest[1..];
	else
	  ll = "";
      }
    }
  }
}

static void add_new_tables(Sql.Sql handle) {
    MESSAGE("adding new format tables\n");
    MESSAGE("adding ob_class ");
    catch {
        handle->query("drop table if exists ob_class");
        handle->query("drop table if exists ob_data");
    };
    handle->query("create table ob_class ("+
                  " ob_id int primary key, "+
                  " ob_class char(128) "+
                  ")");

    MESSAGE("adding ob_data ");
    handle->query("create table ob_data ("+
                  " ob_id int, "+
                  " ob_ident char(15),"+
                  " ob_attr char(50), "+
                  " ob_data mediumtext,"+
                  " unique(ob_id, ob_ident, ob_attr),"+
                  " index i_attr (ob_attr),"+
		  " index i_ident (ob_ident),"+
                  " index i_attrdata (ob_attr, ob_data(80))"+
                  ")");

    handle->query("create table ob_journaling ("+
                  " ob_id int, "+
                  " ob_ident char(15),"+
                  " ob_attr char(50), "+
                  " ob_data mediumtext,"+
                  " unique(ob_id, ob_ident, ob_attr),"+
                  " index i_attr (ob_attr)"+
                  ")");
}

/**
 * set up the base sTeam tables to create an empty database.
 *
 * @param  none
 * @return (1|0)
 * @author Ludger Merkens 
 */
int setup_sTeam_tables(object handle)
{
    /* make sure no old tables exist and delete them properly */
    MESSAGE("Checking for old tables.\n");

    array(string) res = handle->list_tables();
    if (sizeof(res))
    {
        foreach(res, string table)
	{
	    MESSAGE(sprintf("dropping (%s)\n",table));
	    handle->big_query("drop table "+table);
	}
    }
    else
	MESSAGE("no old tables found");

    MESSAGE("CREATING NEW BASE TABLES:");
    handle->create_tables();
    
    res = handle->list_tables();
    if (!sizeof(res)) {
	FATAL("\nFATAL: failed to create base tables");
    }
    else
    {
	MESSAGE("\nPOST CHECK retrieves: ");
        foreach(res, string table)
	    MESSAGE(table+" ");
    }
    return 1;
}

/**
 * create and return a new instance of db_file
 *
 * @param  int iContentID - 0|ID of a given Content
 * @return the db_file-handle
 * @see    db_file
 * @see    file/IO
 * @author Ludger Merkens 
 */
object new_db_file_handle(int iContentID, string mode)
{
    return new("/kernel/db_file.pike", iContentID, mode);
}

/**
 * connect_db_file, connect a /kernel/db_file instance with the database
 * calculate new content id if none given.
 *
 * @param    id
 * @return   function db()
 */
final mixed connect_db_file(int id)
{
  if ( object_program(CALLER)  != (program)"/kernel/db_file.pike" )
    steam_error("Security Error: Failed to connect db file !");
  return ({ db, (id==0 ? create_new_database_id("doc_data") : id)});
}

/**
 * valid_db_mapping - check if an object pretending to be an db_mapping
 * really inherits /kernel/db_mapping and thus is a trusted program
 * @param     m - object inheriting db_mapping
 * @return    (TRUE|FALSE)
 * @see       connect_db_mapping
 * @author Ludger Merkens 
 */
private static bool valid_db_mapping(object m)
{
    if ( Program.inherits(object_program(m),
			  (program)"/kernel/db_mapping.pike") ||
         Program.inherits(object_program(m),
                          (program)"/kernel/db_n_one.pike") ||
         Program.inherits(object_program(m),
                          (program)"/kernel/db_n_n.pike") ||
         Program.inherits(object_program(m),
                          (program)"/kernel/db_searching.pike"))
	return true;
    return false;
}

/**
 * connect_mapping, connect a /kernel/db_mapping instance with the database
 * @param    none
 * @return   a pair ({ function db, string tablename })
 */
final mixed connect_db_mapping()
{
    if (!(valid_db_mapping(CALLER)))
    {
        FATAL("illegal access %s from %O\n",CALLINGFUNCTION, CALLER);
	THROW("illegal access to database ", E_ACCESS);
    }
    string sDbTable;
    // hack to allow the modules table to be a member of _Database

    sDbTable = CALLER->get_table_name();


    if (!sDbTable)
        THROW(sprintf("Invalid tablename [%s] in module '%s'\n",sDbTable,
                      master()->describe_program(CALLERPROGRAM)), E_ERROR);
    return ({ db, sDbTable });
}

string get_identifier() { return "database"; }
string _sprintf() { return "database"; }
string describe() { return "database"; }
int get_object_class() { return CLASS_DATABASE; }
object this() { return this_object(); }
int status() { return PSTAT_SAVE_OK; }




/**
 * get_objects_by_class()
 * mainly for maintenance reasons, retreive all objects matching a given
 * class name, or program
 * @param class (string|object|int) - the class to compare with
 * @return array(object) all objects found in the database
 * throws on access violation. (ROLE_READ_ALL required)
 */
final array(object) get_objects_by_class(string|program|int mClass)
{
    Sql.sql_result res;
    int i, sz;
    object security;
    array(object) aObjects;
    string sClass;

    if (objectp(security=MODULE_SECURITY) && objectp(lookup_user("root")) ) {
        if ( !_Server->is_a_factory(CALLER) )
          security->check_access(0, this_user(), 0, ROLE_READ_ALL, false);
    }

    if ( intp(mClass) ) {
      mixed factory = _Server->get_factory(mClass);
      if ( !objectp(factory) )
        return UNDEFINED;
      if ( !stringp(CLASS_PATH) || !stringp(factory->get_class_name()) )
        return UNDEFINED;
      mClass = CLASS_PATH + factory->get_class_name();
    }

    if (programp(mClass))
        sClass = master()->describe_program(mClass);
    else
        sClass = mClass;
    
    res = db()->big_query("select ob_id from ob_class where ob_class='"+
                          mClass+"'");

    aObjects = allocate((sz=res->num_rows()));

    for (i=0;i<sz;i++)
    {
        aObjects[i]=find_object((int)res->fetch_row()[0]);
    }
    return aObjects;
}


/**
 * get_all_objects()
 * mainly for maintenance reasons
 * @return array(object) all objects found in the database
 * throws on access violation. (ROLE_READ_ALL required)
 */
final array(object) get_all_objects()
{
  if ( !_Server->is_a_factory(CALLER) )
    THROW("Illegal attempt to call database.get_all_objects !", E_ACCESS);
  return low_get_all_objects();
}
    
private static array(object) low_get_all_objects()
{
    Sql.sql_result res;
    int i, sz;
    array(object) aObjects;

    res = db()->big_query("select ob_id from ob_class where ob_class !='-'");
    aObjects = allocate((sz=res->num_rows()));

    for (i=0;i<sz;i++)
    {
        aObjects[i]=find_object((int)res->fetch_row()[0]);
    }
    return aObjects;
}

/**
 * visit_all_objects
 * loads all objects from the database, makes sure each object really loads
 * and calls the function given as "visitor" with consecutive with each object.
 * @param function visitor
 * @return nothing
 * @author Ludger Merkens
 * @see get_all_objects
 * @see get_all_objects_like
 * @caveats Because this function makes sure an object is properly loaded
 *          when passing it to function "visitor", you won't
 *          notice the existence of objects currently not loading.
 */
final void visit_all_objects(function visitor, mixed ... args)
{
    FATAL("visit_all_objects not yet converted to new database format");
    return;
    Sql.sql_result res = db()->big_query("select ob_id,ob_class from ob_class");
    int i;
    int oid;
    string oclass;
    object p;
    FATAL("Number of objects found:"+res->num_rows());
    for (i=0;i<res->num_rows();i++)
    {
        mixed erg =  res->fetch_row();
        oid = (int) erg[0];  // wrong casting with 
        oclass = erg[1];     // [oid, oclass] = res->fetch_row()
        
        if (oclass[0]=='/') // some heuristics to avoid nonsene classes
        {
            p = find_object((int)oid);         // get the proxy
            catch{p->get_object();};      // force to load the object
            if (p->status() > PSTAT_DISK) // positive stati mean object loaded
                visitor(p, @args);
        }
    }
}

/**
 * Check for a list of objects, if they really exist in the database
 *
 * @param objects - the list of object to be checked
 * @return a list of those objects, which really exist.
 * @author Ludger Merkens
 * @see get_not_existing
 */
array(int) get_existing(array(int) ids)
{
    Sql.sql_result res;
    int i, sz;
    string query = "select ob_id from ob_class where ob_id in (";
    array(int) result;
    
    if (!ids || !sizeof(ids))
        return ({ });
    for (i=0,sz=sizeof(ids)-1;i<sz;i++)
        query +=ids[i]+",";
    query+=ids[i]+")";
    res = db()->big_query(query);

    result = allocate((sz=res->num_rows()));
    for (i=0;i<sz;i++)
        result[i]=(int) res->fetch_row()[0];

    return result;
}

/**
 * Get a list of the not-existing objects.
 *  
 * @param objects - the list of objects to be checked
 * @return a list of objects that are not existing
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
array(int) get_not_existing(array(int) ids)
{
    return ids - get_existing(ids);
}

object get_environment() { return 0; }
object get_acquire() { return 0; }

mapping get_xml_data()
{
    return ([ "configs":({_Server->get_configs, XML_NORMAL}), ]);
}

/**
 * clears lost content records from the doc_data table, used for the
 * db_file emulation. This function is purely for maintainance reasons, and
 * should be obsolete, since we hope no content records will get lost
 * anymore.
 * @param none
 * @returns a debug string containing the number of deleted doc_id's
 */
string clear_lost_content()
{
    Sql.Sql h = db();
    LOG("getting doc_ids");
    Sql.sql_result res = h->big_query("select distinct doc_id from doc_data");
    array(int) doc_ids = allocate(res->num_rows());
    for(int i=0;i<sizeof(doc_ids);i++)
        doc_ids[i]=(int)res->fetch_row()[0];

    FATAL("deleting '-' files");
    h->big_query("delete from objects where ob_class='-'");
    FATAL("getting all objects");
    res = h->big_query("select ob_id from ob_class");
    int oid; object p; mixed a;
    while (a = res->fetch_row())
    {
        oid = (int)a[0];
        if (p=find_object(oid))
        {
            FATAL("accessing object"+oid);
            object try;
            catch{try=p->get_object();};
            if (objectp(try) &&
                Program.inherits(object_program(try),
                                 (program)"/base/content"))
            {
                FATAL("content "+p->get_content_id()+" is in use");
                doc_ids  -= ({ p->get_content_id() });
            }
        }
    }

    FATAL("number of doc_ids to be deleted is:"+sizeof(doc_ids));

    foreach (doc_ids, int did)
    {
        h->big_query("delete from doc_data where doc_id = "+did);
        FATAL("deleting doc_id"+did);
    }
    FATAL("calling optimize");
    h->big_query("optimize table doc_data");
    return "deleted "+sizeof(doc_ids)+"lost contents";
}

object lookup (string identifier)
{
    return get_module("objects")->lookup(identifier);
}

object lookup_user (string identifier)
{
  return get_module("users")->get_user(identifier);
}

object lookup_group (string identifier)
{
  return get_module("groups")->get_group(identifier);
}

int supported_classes () { return CLASS_ALL; }

/**
 * Searches for users in the persistence layer.
 *
 * @param terms a mapping ([ attrib : value ]) where attrib can be "firstname",
 *   "lastname", "login" or "email" and value is the text ot search for in the
 *   attribute. If the values contain wildcards, specify the wildcard character
 *   in the wildcard param.
 * @param any true: return all users that match at least one of the terms
 *   ("or"), false: return all users that match all of the terms ("and").
 * @param wildcard a string containing the wildcard used in the search term
 *   values, or 0 (or unspecified) if no wildcards are used
 * @return an array of user names (not objects) of matching users
 */
array(string) search_users ( mapping terms, bool any, string|void wildcard ) {
  string eq = " = ";
  if ( stringp(wildcard) && sizeof(wildcard) > 0 ) eq = " like ";

  array queries = ({ });
  foreach ( indices(terms), mixed attr ) {
    mixed value = terms[ attr ];
    if ( !stringp(attr) || sizeof(attr)<1 ||
         !stringp(value) || sizeof(value)<1 )
      continue;
    switch ( attr ) {
      case "login" :
      case "firstname" :
      case "lastname" :
      case "email" :
        // additional strings might be mapped to column names...
        break;
      default : continue;  // don't make invalid queries
    }
    if ( stringp(wildcard) && sizeof(wildcard) > 0 )
      value = replace( value, wildcard, "%" );
    queries += ({ attr + eq + "'" + db()->quote(value) + "'" });
  }
  string op = " and ";
  if ( any ) op = " or ";
  mixed where = queries * op;
  if ( !stringp(where) || sizeof(where) == 0 ) {
    werror( "database(%s): search_users called with invalid search terms: %O "
            + "(any: %O, wildcard: %O)\n",
            Calendar.Second(time())->format_time(), terms, any, wildcard );
    return ({ });
  }

  Sql.sql_result res = db()->big_query( "select distinct ob_id from " +
                                   "i_userlookup where " + where );
  mixed row;

  if ( !objectp(res) )
    return 0;
 
  array result = ({ });
  while ( row = res->fetch_row() ) {
    object user = find_object( (int)row[0] );
    if ( objectp(user) )
      result += ({ user->get_identifier() });
  }
  destruct(res);
  return result;
}


/**
 * Searches for groups in the persistence layer.
 *
 * @param terms a mapping ([ attrib : value ]) where attrib can be "name"
 *   and value is the text ot search for in the attribute.
 *   If the values contain wildcards, specify the wildcard character in the
 *   wildcard param.
 * @param any true: return all groups that match at least one of the terms
 *   ("or"), false: return all groups that match all of the terms ("and").
 * @param wildcard a string containing the wildcard used in the search term
 *   values, or 0 (or unspecified) if no wildcards are used
 * @return an array of group names (not objects) of matching groups
 */
array(string) search_groups ( mapping terms, bool any, string|void wildcard ) {
  string eq = " = ";
  if ( stringp(wildcard) && sizeof(wildcard) > 0 ) eq = " like ";

  array queries = ({ });
  foreach ( indices(terms), mixed attr ) {
    mixed value = terms[ attr ];
    if ( !stringp(attr) || sizeof(attr)<1 ||
         !stringp(value) || sizeof(value)<1 )
      continue;
    switch ( attr ) {
      case "name" : attr = "k"; break;
      // additional strings might be mapped to column names...
      default : continue;  // don't make invalid queries
    }
    if ( stringp(wildcard) && sizeof(wildcard) > 0 )
      value = replace( value, wildcard, "%" );
    queries += ({ attr + eq + "'" + db()->quote(value) + "'" });
  }
  string op = " and ";
  if ( any ) op = " or ";
  mixed where = queries * op;
  if ( !stringp(where) || sizeof(where) == 0 ) {
    werror( "database(%s): search_groups called with invalid search terms: %O "
            + "(any: %O, wildcard: %O)\n",
            Calendar.Second(time())->format_time(), terms, any, wildcard );
    return ({ });
  }

  Sql.sql_result res = db()->big_query( "select distinct v from i_groups " +
                                        "where " + where );
  mixed row;

  if ( !objectp(res) )
    return 0;
 
  array result = ({ });
  while ( row = res->fetch_row() ) {
    int ob_id;
    if ( sscanf( row[0], "%%%d", ob_id ) > 0 ) {
      object group = find_object( ob_id );
      if ( objectp(group) )
        result += ({ group->get_identifier() });
    }
  }
  destruct(res);
  return result;
}
