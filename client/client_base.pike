/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: client_base.pike,v 1.2 2008/07/17 16:45:00 astra Exp $
 */

constant cvs_version="$Id: client_base.pike,v 1.2 2008/07/17 16:45:00 astra Exp $";

inherit "kernel/socket";
inherit "net/coal/binary";

#include <coal.h>
#include <classes.h>
#include <macros.h>
#include <client.h>

#undef CLIENT_DEBUG

#ifdef CLIENT_DEBUG
#define DEBUG_CLIENT(s, args...) werror(s+"\n", args)
#else
#define DEBUG_CLIENT(s, args...)
#endif

private static mapping        mObjects; // objects
private static string      sLastPacket; // last package while communicating
private static int                iOID; // the object id of the current object
private static int                iTID; // the current transaction id
private static int            iWaitTID;
        static mapping      mVariables; // session variables
        static array           aEvents;
        static int         __connected;
        static int     __downloadBytes;
               int     __last_response;
        static function  downloadStore;
        static mapping         mEvents;

private static mixed          miResult;
private static int           miCommand;

static Thread.Mutex    cmd_mutex =     Thread.Mutex();
static Thread.Condition cmd_cond = Thread.Condition();
static Thread.Queue      resultQueue = Thread.Queue();
static Thread.Queue         cmdQueue = Thread.Queue();
static object                                cmd_lock;

string connected_server;
int connected_port;


class SteamObj 
{
  private static int oID; 
  private static string identifier = 0;
  private static int cl = 0;
  private static int(0..1) nowait;
  private static mapping(string:function) functions=([]);
  
  int get_object_id() {
    return oID;
  }

  int get_object_class() {
    if ( cl == 0 ) {
      int wid = iWaitTID;
      int id = set_object(oID);
      mixed res = send_command(COAL_COMMAND, ({ "get_object_class" }));
      if ( intp(res) )
	  cl = res;
      set_object(id);
      iWaitTID = wid;
    }
    return cl;
  }

  object get_environment() {
    return send_command(COAL_COMMAND, ({ "get_environment" }));
  }

  string get_identifier() {
    if ( !stringp(identifier) ) {
      int wid = iWaitTID;
      int id = set_object(oID);
      identifier = send_command(COAL_COMMAND, ({ "get_identifier" }));
      set_object(id);
      iWaitTID = wid;
    }
    return identifier;
  }

  void create(int id) {
    oID = id;
  }

  int status() {
    return 1; // PSTAT_SAVE_OK
  }

  int no_wait(void|int(0..1) _nowait)
  {
    if(!zero_type(_nowait) && nowait == !_nowait)
    {
      nowait=!!_nowait;
      return !nowait;
    }
    else
      return nowait;
  }

  string function_name(function fun)
  {
    return search(functions, fun);
  }

  string _sprintf()
  {
    return "OBJ#"+oID;
    string describe="";
    catch{ describe=`->("describe")(); };
    return sprintf("%s:%d/%s", connected_server, connected_port, describe);
  }

  function `->(string fun) 
  {
    if(::`->(fun))
      return ::`->(fun);
    else
    {
      if(fun == "exec_code")
	return 0;
      else if (fun=="serialize_coal")
	return 0;
      if(!functions->fun)
        functions[fun]=lambda(mixed|void ... args) { 
                         return send_cmd(oID, fun, args, nowait); 
                       };
      return functions[fun];
    }
  }
  
  function find_function(string fun) 
  {
      if(!functions->fun)
        functions[fun]=lambda(mixed|void ... args) { 
                         return send_cmd(oID, fun, args, nowait); 
                       };
      return functions[fun];
  }
};


/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int set_object(int|object|string id)
{
    int oldID = iOID;

    if ( stringp(id) ) {
	if ( objectp(mVariables[id]) )
	    iOID = mVariables[id]->get_object_id();
	else
	    iOID = mVariables[id];
    }
    else if ( objectp(id) )
	iOID = id->get_object_id();
    else
	iOID = id;
    return oldID;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static object find_obj(int|string id)
{
    int oid;
    if ( stringp(id) ) {
      object fp = send_cmd( 0, "get_module", "filepath:tree" );
      object obj = send_cmd( fp, "path_to_object", id );
      if ( !objectp(obj) ) return 0;
      oid = obj->get_object_id();
    }
    else oid = id;

    if ( !mObjects[oid] ) {
	mObjects[oid] = SteamObj(oid);
	//werror("Created:"+master()->describe_object(mObjects[id])+"\n");
    }
    return mObjects[oid];
}

object find_object(int|string id) { return find_obj(id); }

mixed get_variable(string key)
{
  return mVariables[key];
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
int connect_server(string server, int port)
{
    iTID = 1;
    iOID = 0;

    sLastPacket     = "";
    __downloadBytes =  0;
    mVariables      = ([ ]);
    mObjects        = ([ ]);
    aEvents         = ({ });
    mEvents         = ([ ]);
    
    open_socket();
    set_blocking();
    if ( connect(server, port) ) {
	MESSAGE("Connected to " + server + ":"+port +"\n");
	connected_server=server;
	connected_port=port;
	__last_response = time(); // timestamp of last response	
	__connected = 1;
	set_buffer(65536, "r");
	set_buffer(65536, "w");
	set_blocking();
	thread_create(read_thread);
	thread_create(handle_commands);
	return 1;
    }
    return 0;
}

void create()
{
}

static int write(string str)
{
    __last_response = time();
    return ::write(str);
}

static void handle_command(string func, mixed args) { }

void handle_commands() 
{
  mixed res;
  while ( res = cmdQueue->read() ) {
      if ( arrayp(res) ) {
	if ( arrayp(res[1]) ) {
	  mixed err = catch {
	    handle_command(res[1][0], res[1][1]);
	  };
	  if ( err != 0 )
	    werror("Fatal error while calling command: %O\n%O", err[0], err[1]);
	}
      }
  }
}


void read_callback(object id, string data)
{
    __last_response = time();
    
    if ( functionp(downloadStore) ) {
	mixed err = catch {
	    downloadStore(data);
	};
	__downloadBytes -= strlen(data);
	if ( __downloadBytes <= 0 ) {
	    downloadStore(0);
	    downloadStore = 0; // download finished
	}
	return;
    }
    sLastPacket += data;
    if ( __downloadBytes > 0 ) {
	if ( __downloadBytes <= strlen(sLastPacket) )
	    resultQueue->write(sLastPacket);
	return;
    }
    mixed res;
    res = receive_binary(sLastPacket);
    while ( arrayp(res) ) {
	int tid = res[0][0];
	int cmd = res[0][1];
	
	if ( cmd == COAL_EVENT ) {
	    DEBUG_CLIENT("Event %O", res[1]);
	}
	DEBUG_CLIENT("RCVD Package(%d): Waiting for %d\n", tid, iWaitTID);
	sLastPacket = res[2];
	if ( tid == iWaitTID ) {
	    miResult = res[1];
	    miCommand = res[0][1];
	    resultQueue->write(miResult);
	}
	else if ( cmd == COAL_COMMAND ) {
	    cmdQueue->write(res);
	}
	res = receive_binary(sLastPacket);
    }
}

string download(int bytes, void|function store) 
{
    // actually the last command should have been the upload response,
    // so there shouldnt be anything on the line except events
    // which should have been already processed
    // everything else should be download data
    string data;
    __downloadBytes = bytes;

    if ( functionp(store) ) {
	data = copy_value(sLastPacket[..bytes]);
	__downloadBytes -= strlen(data);
	if ( strlen(data) > 0 )
	    store(data);
	if ( __downloadBytes <= 0 ) {
	    store(0);
	    return "";
	}
	downloadStore = store;
	return "";
    }
    downloadStore = 0;

    if ( strlen(sLastPacket) >= bytes ) {
	data = copy_value(sLastPacket[..bytes]);
	if ( bytes > strlen(sLastPacket) )
	    sLastPacket = sLastPacket[bytes+1..];
	else
	    sLastPacket = "";
	__downloadBytes = 0;
	return data;
    }

    miResult = resultQueue->read();
    data = copy_value(sLastPacket[..bytes]);
    if ( strlen(sLastPacket) > bytes )
	sLastPacket = sLastPacket[bytes+1..];
    else
	sLastPacket = "";
    __downloadBytes = 0;
    return data;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
void handle_error(mixed err)
{
    throw(err);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
mixed send_command(int cmd, array(mixed) args, int|void no_wait)
{
    if ( !no_wait ) iWaitTID = iTID;
    aEvents  = ({ });

    
    string msg = coal_compose(iTID++, cmd, iOID, 0, args);
    string nmsg = copy_value(msg);

    send_message(nmsg);
    if ( no_wait ) return 0;
     
    mixed result = resultQueue->read();
    if ( miCommand == COAL_ERROR ) {
	handle_error(result);
    }
    return result;
}

void subscribe_event(object obj, int eid, function callback)
{
  int oid = set_object(obj);
  send_command(COAL_SUBSCRIBE, ({ eid }) );
  mEvents[eid] = callback;
  set_object(oid);
}

mixed send_cmd(object|int obj, string func, mixed|void args, void|int no_wait)
{
    int oid = set_object(obj);
    if ( zero_type(args) )
	args = ({ });
    else if ( !arrayp(args) )
	args = ({ args });
    mixed res = send_command(COAL_COMMAND, ({ func, args }), no_wait);
    set_object(oid);
    return res;
}

mixed 
login(string name, string pw, int features, string|void cname, int|void novars)
{
    if ( !stringp(cname) )
	cname = "steam-pike";
    
    mixed loginData;
    if ( features != 0 )
	loginData =send_command(COAL_LOGIN, ({ name, pw, cname, features, __id }));
    else
	loginData =
	    send_command(COAL_LOGIN,({ name, pw, cname,CLIENT_FEATURES_ALL, __id}));
    
    if ( arrayp(loginData) && sizeof(loginData) >= 9 ) {
      mVariables["user"] = iOID;
      foreach ( indices(loginData[8]), string key ) {
	mVariables[key] = loginData[8][key];
      }
      mVariables["rootroom"] = loginData[6];
	sLastPacket = "";
	if ( novars != 1 ) {
	  foreach ( values(loginData[9]), object cl ) {
	    set_object(cl->get_object_id());
	    mVariables[send_cmd(cl,"get_identifier")] = cl;
	  }
	}
	return name;
    }
    return 0;
}

mixed logout()
{
    __connected = 0;
    write(coal_compose(0, COAL_LOGOUT, 0, 0, 0));
}


void was_closed()
{
    resultQueue->write("");
    ::was_closed();
}


void write_error2file(mixed|string err, int recursive) {

    Stdio.File error_file;
    string             path;
    array(string) directory;
    int file_counter =0;
    int found=0;
    path = getcwd();
    directory = get_dir(path);
    while (found==0){
        int tmp_found=1;
        tmp_found=Stdio.exist(path+"/install_error."+file_counter);
        if (tmp_found==1){
            file_counter = file_counter + 1;
        }
        else{
            found = 1;
        }
    }

    if (recursive==1)
        file_counter = file_counter -1;
    error_file=Stdio.File (path+"/install_error."+file_counter ,"cwa");
    if (stringp (err)){
        error_file->write(err);
    }
    if(arrayp(err)){
        foreach(err, mixed error){
            if ( stringp(error) || intp(error) )
                error_file->write((string)error);
            else if ( objectp(error) )
                error_file->write("<object...>\n");
            else if ( arrayp(error) ){
                write_error2file(error,1);
            }
        }
    }
    if (recursive!=0)
        error_file->close();
}


/**
 * Creates a new document object on the server.
 *
 * @param name the name of the new object
 * @param where the container or room in which to create the new object
 * @param mimetype (optional) the mime type of the new object (if not
 *   specified, the mime type will be determined by the object name)
 * @param content (optional) the content for the new object (if not specified,
 *   the new object will not have any content)
 * @return the newly created object (if an error occurs, an exception will be
 *   thrown instead)
 */
object create_document ( string name, object where, void|string mimetype, void|string content )
{
  if ( !stringp(name) || sizeof(name) < 1 )
    throw( ({ "No name specified !" }) );
  if ( !objectp(where) )
    throw( ({ "No room or container specified !" }) );
  object obj = send_cmd( where, "get_object_byname", name );
  if ( objectp(obj) )
    throw( ({ "Object \""+name+"\" already found !" }) );
  object factory = send_cmd( 0, "get_factory", CLASS_DOCUMENT );
  if ( !objectp(factory) )
    throw( ({ "Document factory not found on server !" }) );
  mapping params = ([ "name":name ]);
  if ( stringp(mimetype) && sizeof(mimetype) > 0 )
    params["mimetype"] = mimetype;
  obj = send_cmd( factory, "execute", params );
  if ( !objectp(obj) )
    throw( ({ "Could not create document !" }) );
  send_cmd( obj, "move", where );
  
  if ( stringp(content) )
    send_cmd( obj, "set_content", content );
  
  return obj;
}


/**
 * Creates a new room object on the server.
 *
 * @param name the name of the new object
 * @param where the room in which to create the new object
 * @return the newly created object (if an error occurs, an exception will be
 *   thrown instead)
 */
object create_room ( string name, object where )
{
  if ( !stringp(name) || sizeof(name) < 1 )
    throw( ({ "No name specified !" }) );
  if ( !objectp(where) )
    throw( ({ "No room specified !" }) );
  object obj = send_cmd( where, "get_object_byname", name );
  if ( objectp(obj) )
    throw( ({ "Object \""+name+"\" already found !" }) );
  object factory = send_cmd( 0, "get_factory", CLASS_ROOM );
  if ( !objectp(factory) )
    throw( ({ "Room factory not found on server !" }) );
  obj = send_cmd( factory, "execute", ([ "name":name ]) );
  if ( !objectp(obj) )
    throw( ({ "Could not create room !" }) );
  send_cmd( obj, "move", where );
  return obj;
}

/**
 * Creates a new container object on the server.
 *
 * @param name the name of the new object
 * @param where the container or room in which to create the new object
 * @return the newly created object (if an error occurs, an exception will be
 *   thrown instead)
 */
object create_container ( string name, object where )
{
  if ( !stringp(name) || sizeof(name) < 1 )
    throw( ({ "No name specified !" }) );
  if ( !objectp(where) )
    throw( ({ "No room or container specified !" }) );
  object obj = send_cmd( where, "get_object_byname", name );
  if ( objectp(obj) )
    throw( ({ "Object \""+name+"\" already found !" }) );
  object factory = send_cmd( 0, "get_factory", CLASS_CONTAINER );
  if ( !objectp(factory) )
    throw( ({ "Container factory not found on server !" }) );
  obj = send_cmd( factory, "execute", ([ "name":name ]) );
  if ( !objectp(obj) )
    throw( ({ "Could not create container !" }) );
  send_cmd( obj, "move", where );
  return obj;
}
