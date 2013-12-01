/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: master.pike,v 1.10 2010/08/21 19:38:00 astra Exp $
 */

constant cvs_version="$Id: master.pike,v 1.10 2010/08/21 19:38:00 astra Exp $";

inherit "/master";

#include <macros.h>
#include <coal.h>
#include <assert.h>
#include <database.h>
#include <attributes.h>
#include <config.h>
#include <classes.h>
#include <exception.h>

#define LMESSAGE(s) if(llog) MESSAGE(s)
#define __DATABASE mConstants["_Database"]
#define MODULE_FILEPATH oServer->get_module("filepath:tree")
#define MODULE_SECURITY   oServer->get_module("security")

#undef MESSAGE_ERR
#define MESSAGE_ERR(x) (oServer->get_module("log")->log_error(x))

//#define MOUNT_TRACE 1

static object          old_master;// = master();
static object first, last, border;
int                          llog;
static int              iInMemory;

private static mapping alias = ([ ]);

#define debug_upgrade 0
#define debug_noncrit 0


private static object       oActiveUser;
private static object    oEffectiveUser;
private static object oOldEffectiveUser;
private static array(object)    oaPorts;
private static array(program) paSockets;
private static array(object)    oaUsers;
private static mapping       mConstants;
private static mapping          mErrors;
private static object           oServer;
private static mapping       mFunctions;//mapping of functions for each program
private static int           iCacheSize;
private static int        iMinCacheTime;
private static int            iLastSwap;
private static int             iSwapped;
private static mapping           mPorts;

#ifdef THREAD_READ
private static Thread.Mutex cmd_mutex = Thread.Mutex();
private static object                         oCmdLock;
#endif


void create() 
{
    oaPorts   = ({ });
    paSockets = ({ });
    oaUsers   = ({ });
    mFunctions = ([ ]);
    mErrors = ([ ]);
    mPorts  = ([ ]);

    LMESSAGE("New Master exchange !\n");
    old_master = master();
    object new_master = this_object();

    foreach( indices(old_master), string varname ) {
	catch { new_master[varname] = old_master[varname]; };
    }
    oActiveUser = thread_local();
    oEffectiveUser = thread_local();
    oOldEffectiveUser = thread_local();
    iMinCacheTime = 600;
    iLastSwap = time();

    oServer = 0;
}


mixed get_constant ( string constant_name )
{
  if ( !mappingp( mConstants ) ) return 0;
  return mConstants[constant_name];
}


string stupid_describe(mixed d, int l)
{
    return sprintf("%O", d);
}

private void insert(object proxy)
{
    mixed err = catch {
        proxy["oNext"] = first;
        proxy["oPrev"] = 0;
        if (!first)
            last = proxy;
        else
            first["oPrev"] = proxy;
        first = proxy;
    };
    if ( err != 0 )
	MESSAGE("Failed to insert proxy:\n"+sprintf("%O\n", err));
}

public void remove(object proxy)
{
    if (proxy == first)
	first = proxy["oNext"];
    else
	proxy["oPrev"]["oNext"] = proxy["oNext"];

    if (proxy == last)
	last = proxy["oPrev"];
    else
	proxy["oNext"]["oPrev"] = proxy["oPrev"];
    proxy["oNext"] = 0;
    proxy["oPrev"] = 0;
}

public void front(object proxy)
{
  if (proxy->check_swap()) {
    if (first!=proxy)
      {
	if (!proxy["oNext"] && !proxy["oPrev"])
	    insert(proxy);
	else
	{
	    remove(proxy);
	    insert(proxy);
	}
    }
  }
}

private void tail(object proxy)
{
  if (last!=proxy)
  {

    if (!proxy["oNext"] && !proxy["oPrev"])
      append(proxy);
    else {
      if (border==proxy)
	border = proxy["oPrev"];
      remove(proxy);
      append(proxy);
    }
  }
}

public int swap(int max_swap_time, int external) 
{
  object oDrop;
  object oServer = mConstants["_Server"];
  
  if (!iCacheSize)
  {
    if (objectp(oServer)) {
      iCacheSize = oServer->get_config("cachesize");
      iMinCacheTime = oServer->get_config("cachetime");
      if ( iCacheSize == 0 ) 
	iCacheSize = 100000;
      if (iMinCacheTime == 0) 
	iMinCacheTime = 600;
    }
  }

  // do only try to swap from time to time
  if ( !external && (time() - iLastSwap) < iMinCacheTime )
    return -1;

  iLastSwap = time();

  if (iInMemory > (iCacheSize < 100 ? 100: iCacheSize))
  {
    int swappedOut = 0;
    int visits = 0;
    function mtime = oServer->f_get_time_millis;
    int tt = mtime();

    oDrop = last;
    
    if (external)
      MESSAGE("Swapp/start with %O/%d projected/%d max visits/%d max time",
	      oDrop, (iInMemory-iCacheSize)/20, iInMemory / 5, max_swap_time);
    
    while ( objectp(oDrop) && iInMemory > iCacheSize && visits < iInMemory &&
      ((swappedOut < (iInMemory - iCacheSize)/20 && visits < iInMemory / 5) ||
       (max_swap_time > 0 && mtime() - tt < max_swap_time)) ) 
    {
      while (objectp(oDrop) && oDrop->status() != PSTAT_SAVE_OK) {
	visits+=(oDrop->status() == PSTAT_SAVE_PENDING);
	oDrop = oDrop["oPrev"];
      }
      if (!objectp(oDrop))
	continue;
      
      visits++;
      if ( oDrop->swap(iMinCacheTime) ) {
	iSwapped++;
	swappedOut++;
	oDrop = oDrop["oPrev"];
      }
      else {
	oDrop = oDrop["oPrev"];
      }
    }
    if (external) {
      MESSAGE( "Swapping %d (%d in memory / %d objects cache size) in %d ms, "+
	       "%d visited",
	       swappedOut, iInMemory, iCacheSize, (mtime()-tt), visits);
    }
    return swappedOut;
  }
  return 0;
}

void got_loaded(object proxy)
{
  if (proxy->check_swap()) {
    iInMemory++;
    front(proxy);   
  }
  // do not spend more than 10 ms in swapping / every x minutes (minCacheTime)
  swap(10, 0);
}   


void got_dropped(object proxy)
{
    iInMemory--;
    tail(proxy);
}

int get_in_memory() {
    return iInMemory;
}

int get_swapped() {
    return iSwapped;
}

void append(object proxy)
{
    mixed err = catch {
        proxy["oNext"]= 0;
        proxy["oPrev"]= last;
        if (!last)
            first = proxy;
        else 
            last["oNext"] = proxy;
        last = proxy;
    };
}

array(array(string)) p_list()
{
    array(array(string)) res = ({});
    object proxy = first;
    string name;
    array errres;
    mixed fun;
    
    while (objectp(proxy))
    {
	
	fun=proxy->find_function("query_attribute");
	if (!functionp(fun))
	    name = "---";
	else
	{
	    errres = catch {name = fun(OBJ_NAME);};
	    if (arrayp(errres))
		name = errres[0][0..20];
	    if (!stringp(name))
		name = "***";
	}
	
	res +=
	    ({
		({ (string) proxy->get_object_id(),
		       ( (proxy->status()==1) ? " " +
			 describe_program(object_program(proxy->get_object()))
			       : "on disk" ),
		       (stringp(name) ? name : "empty"),
		       PSTAT(proxy->status())
		       })
		    });
	//	MESSAGE("running through: object "+proxy->get_object_id());
	proxy = proxy["oNext"];
    }
    //    MESSAGE("List done ...");
    return res;
}

array(program) dependents(program p)
{
  program prog;
  string  progName;
  array(program) ret = ({});
  foreach (indices(programs), progName) {
    prog = programs[progName];
    if ( !programp(prog) )
      continue;
    array(program) inheritlist = Program.all_inherits(prog);
    if ( search(inheritlist, p) >=0 ) {
      ret += ({prog});
    }
  }
  return ret;
}


array(string) pnames(array(program) progs)
{
    program prog;
    array(string) names = ({});
    foreach (progs, prog) { 
	names += ({ describe_program(prog) });
    }
    return names;
}

/**
 *  class ErrorContainer,
 *  it provides means to catch the messages sent from the pike binary to the
 *  compile_error from master.
 *  ErrorContainer.compile_error is called by compile_error
 *                               if an Instance of ErrorContainer is set
 * 
 *  got_error and got_warning provide the messages sent to the ErrorContainer
 */


class ErrorContainer
{
    string d;
    string errors="", warnings="";

    string get() {
	return errors;
    }
    
    final mixed `[](mixed num) {
         switch ( num ) {
	     case 0:
	          return errors;
             case 1:
	          return ({ });
        }
        return "";
    }

    string get_warnings() {
	return warnings;
    }

    void got_error(string file, int line, string err, int|void is_warning) {
	if (file[..sizeof(d)-1] == d) {
	    file = file[sizeof(d)..];
	}
	if( is_warning)
	    warnings+=
		sprintf("%s:%s\t%s\n", file, line ? (string) line : "-", err);
	else
	    errors +=
		sprintf("%s:%s\t%s\n", file, line ? (string) line : "-", err);
    }
    
    // called from master()->compile_error
    void compile_error(string file, int line, string err) {
	got_error(file, line, "Error: " + err);
    }

    void compile_warning(string file, int line, string err) {
	got_error(file, line, "Warning: " + err, 1);
    }
    
    void create() {
	d = getcwd();
	if (sizeof(d) && (d[-1] != '/') && (d[-1] != '\\'))
	    d += "/";
    }
};


object getErrorContainer()
{
    return ErrorContainer();
}

/**
 * clear all broken compilations
 */
void clear_compilation_failures()
{
  foreach (indices (programs), string fname)
    if (!programs[fname]) m_delete (programs, fname);
}

void dump_proxies()
{
  FATAL("Dumping proxies.... (%d in memory, %d swapped)", iInMemory, iSwapped);
  mapping visited = ([ ]);
  object o = first;
  int i = 0;
  while ( objectp(o) && o->status ) {
    i++;
    if ( visited[o] ) {
      werror("Circular dependency in master list: %O", o->get_object());
      _exit(1);
    }
    visited[o] = 1;
    if (o->status()>PSTAT_DISK) {
      werror("OBJ: %O\n", o);
    }
    else {
      werror("on disk: %O\n", o);
    }
    o = o["oNext"];
  }
  werror("----- Found %d proxies\n", i);
}

/**
 * upgrade a program and all its instances.
 * @param    program to update
 * @return   -1 Force needed
 * @return   -2 no program passed
 * @return   number of dropped objects
 * @return   error from compile (with backtrace)
 */
int|string upgrade(program p, void|int force)
{
    if (!p)
    {
        clear_compilation_failures();
        return "Failed to find program";
    }
    
    if (p == programs["/kernel/proxy.pike"])
        throw(({"Its impossible to upgrade a proxy object - You have to "+
                "restart the server", backtrace()}));

    clear_compilation_failures();
    array(program) apDependents = dependents(p)+({ p });
    string fname = search(programs, p);
    
    if ( !stringp(fname) )
      return 0;

    int type;
    mixed id;
    [type,id] = parse_URL_TYPE(fname);
    if ( type != URLTYPE_DB && intp(id) && id > 0 )
      fname = "/DB:#"+id+".pike";

    program tmp;

    ErrorContainer e = ErrorContainer();

    m_delete(mErrors, fname);
    set_inhibit_compile_errors(e);
    mixed err = catch{
	tmp = compile_string(master_read_file(fname), fname);
    };
    set_inhibit_compile_errors(0);
    
    if (err!=0) // testcompile otherwise don't drop !
    {
        clear_compilation_failures();
        mErrors[fname]= e->get() /"\n";
	FATAL("Error while upgrading: %O\n", e->get());

	return "Failed to compile "+fname+"\n"+
	    e->get() + "\n" +
	    e->get_warnings();
    }
    
    // assume compilation is ok, or do we have to check all dependents ?



    object o = first;
    array aNeedDrop = ({ });

    int i = 0;
    while ( objectp(o) && o->status && i < iInMemory )
    {
        i++;
        if (o->status()>PSTAT_DISK) // if not in memory don't drop
        {
            if ( search(apDependents, object_program(o->get_object())) >= 0 )
            {
                if (!zero_type(o->check_upgrade) && o->check_upgrade())
                {
                    aNeedDrop += ({o});
                }
            }
        }
        o = o["oNext"];
    }
    
    
    foreach(aNeedDrop, object o)
    {
        if (functionp(o->upgrade))
        {
            o->upgrade();
        }
    }


    mixed UpgradeErr = catch {
        foreach(aNeedDrop, object o)
        {
            int dropped = o->drop();
        }
        foreach(apDependents, program prg) {
            string pname = search(programs, prg);
	    if ( programp(alias[prg]) )
              m_delete(programs, search(programs,alias[prg]));

            m_delete(programs, pname);
        }
    };
    if (UpgradeErr)
      FATAL("Error in upgrade!\n"+describe_backtrace(UpgradeErr));
    
    return sizeof(aNeedDrop);
}

void 
register_constants()
{
    mConstants = all_constants();
}

void 
register_server(object s)
{
    if ( !objectp(oServer) )
	oServer = s;
}

object 
get_server()
{
    return oServer;
}

void 
register_user(object u)
{
    int i;
    
    if ( search(oaPorts, CALLER) == -1 )
	THROW("Caller is not a port object !", E_ACCESS);
    
    for ( i = sizeof(oaUsers) - 1; i >= 0; i-- ) {
	if ( oaUsers[i] == u )
	    return;
        else if ( oaUsers[i]->is_closed() ) {
           destruct(oaUsers[i]); 
        }
    }
    oaUsers -= ({ 0 });
    oaUsers += ({ u });
}

void unregister_user()
{
    if ( !is_user(CALLER) )
	error("Calling object is not a user !");
    oaUsers -= ({ CALLER });
}

bool is_user(object u)
{
    int i;
    for ( i = sizeof(oaUsers) - 1; i >= 0; i-- ) {
	if ( oaUsers[i] == u )
	    return true;
    }
    return false;
}

bool is_module(object m)
{
  if ( objectp(oServer) )
    return oServer->is_module(m);
  return 0;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
int set_this_user(object obj)
{
#ifdef THREAD_READ
    if ( obj == 0 ) {
	oActiveUser->set(0);
	oEffectiveUser->set(0);
	oOldEffectiveUser->set(0);
	if ( objectp(oCmdLock) )
	    destruct(oCmdLock); // unlocked again
	return 1;
    }
#endif

    if ( (!is_module(CALLER) && !is_user(CALLER)) || 
	 (objectp(obj) && !is_user(obj)) ) 
    {
	MESSAGE("failed to set active user...("+describe_object(obj)+")");
	MESSAGE("CALLER: " + describe_object(CALLER));
	foreach(oaUsers, object u) {
	    MESSAGE("User:"+describe_object(u));
	}
	error("Failed to set active user!\n");
	return 0;
    }

#ifdef THREAD_READ
    if (catch(oCmdLock = cmd_mutex->lock()) ) {
      FATAL("Failed to obtain lock - Backtrace - going on ...");
    }
      
#endif
    if ( objectp(obj) ) {
	oActiveUser->set(obj); // use proxy 
	oEffectiveUser->set(0);
	oOldEffectiveUser->set(0);
    }
    else {
	oActiveUser->set(0);
	oEffectiveUser->set(0);
    }
    return 1;
}

object seteuid(object user)
{
  // now this is tricky
  object caller = CALLER;
  if (!objectp(caller)) 
    error("Failed to seteuid , caller is unknown!");
  if (is_socket(caller))
    caller = caller->get_user_object();

  object users = oServer->get_module("users");
  object root;
  if ( objectp(users) )
    root = users->lookup("root");

  if ( caller->get_creator() == root || 
       caller->get_creator() == user ||
       !objectp(user) || 
       user == oOldEffectiveUser->get() ) 
  {
      oOldEffectiveUser->set(oEffectiveUser->get());
      oEffectiveUser->set(user);
      return user;
  }
  throw( ({ sprintf( "Failed to set effective user %O (caller: %O, creator: %O)!", user, caller, caller->get_creator() ), backtrace() }) );
}

object this_user()
{
    if ( !objectp(oActiveUser) ) return 0;

    object tu = oActiveUser->get();
    if ( !objectp(tu) )
	return 0;
    return tu->get_user_object();
}

object this_socket()
{
    if ( !objectp(oActiveUser) ) return 0;
    
    object tu = oActiveUser->get();
    if ( !objectp(tu) )
	return 0;
    return tu;
}


object geteuid()
{
  return oEffectiveUser->get();
}

void
register_port(object s)
{
    if ( CALLER == oServer ) {
	oaPorts += ({ s });
	paSockets += ({ s->get_socket_program() });
    }
}

array(object) get_ports()
{
  oaPorts -= ({ 0 }); 
  return oaPorts;
}

object get_port(string name)
{
  foreach(oaPorts, object port )
    if ( objectp(port) && port->get_port_name() == name )
      return port;
  return 0;
}

array(object) get_users()
{
    return copy_value(oaUsers);
}


/**
 * bool
 * system_object(object obj)
 * {
 *    program prg;
 *
 *   if ( obj == mConstants["_Security"] || obj == mConstants["_Database"] )
 *	return true;
 *   if ( is_user(obj) )
 *	return true;
 *   prg = object_program(obj);
 *   if ( prg == (program)"classes/object.pike" ||
 *	 prg == (program)"classes/container.pike" ||
 *	 prg == (program)"classes/exit.pike" ||
 *	 prg == (program)"classes/room.pike" ||
 *	 prg == (program)"classes/user.pike" ||
 *	 prg == (program)"classes/group.pike" ||
 *	 prg == (program)"proxy.pike" ||
 *       prg == (program)"/home/steam/pikeserver/kernel/steamsocket.pike" )
 *	return true;
 *   return false;
 * }
 */

mixed parse_URL_TYPE(string f)
{
    string path;
    int id;
    string ext;
    // its DB-type
    if ( sscanf(f, "/DB:%s", path) > 0 ) 
    {
        if (sscanf(path, "#%d.%s", id, ext))
        {
            if ( ext == "pike" )
                return ({ URLTYPE_DB, id });
            else
                return ({ URLTYPE_DBO, id });
        } 
	else
            return ({ URLTYPE_DBFT, path });
    }
    else if ( sscanf(f, "steam:%s", path) > 0 ) {
      return ({ URLTYPE_DBFT, path });
    }
    return ({URLTYPE_FS,0});
}

#if 1

array(array(string)) mount_points;

int mount(string source, string dest)
{
    if ( objectp(oServer) && CALLER != oServer )
      error("Unauthorized call to mount() !");

    MESSAGE("Mounting %s on %s", source, dest);

    // make sure we have proper prefixes
    if (source[strlen(source)-1]!='/')  
	source += "/";                  
    if (dest[strlen(dest)-1]!='/')
	dest += "/";

    if (source == "/")
	set_root(dest);
    // insert them according to strlen
    int i;
    if (!arrayp(mount_points))
	mount_points = ({ ({ source, dest }) });
    else
    {
	i = 0;
	while( i < sizeof(mount_points) &&
	       (strlen(mount_points[i][0])<strlen(source)))
	{
	    i++;
	}
	
	mount_points= mount_points[..i-1] +
	    ({({ source, dest })}) +
	    mount_points[i..];
    }
}

//! Run the server in a chroot environment
void run_sandbox(string cdir, void|string user)
{
  function change_root, switch_user;

  if ( !stringp(cdir) )
    return;

#if constant(System)
  change_root= System.chroot;
  switch_user= System.setuid;
#else
  change_root = chroot;
  switch_user = setuid;
#endif

  change_root = chroot;

  if ( change_root(cdir) ) {
        current_path = "/";
        MESSAGE("Running in chroot environment... (%s)\n", cdir);
	object dir = Stdio.File("/etc","r");
	if ( !objectp(dir) )
	  error("Failed to find /etc directory - aborting !");

        array user_info;
        // try specified user:
        if ( stringp(user) && user != "" ) {
          foreach ( get_all_users(), array tmp_user_info ) {
            if ( tmp_user_info[0] != user ) continue;
            user_info = tmp_user_info;
            break;
          }
        }
        // fallback on user nobody:
        if ( !arrayp(user_info) ) {
          user = "nobody";
          foreach ( get_all_users(), array tmp_user_info ) {
            if ( tmp_user_info[0] != user ) continue;
            user_info = tmp_user_info;
            break;
          }
        }
        if ( arrayp(user_info) && sizeof(user_info) > 3 ) {
          if ( switch_user(user_info[2]) == 0 ) {
            MESSAGE( "Switched to user %s [%O]\n", user, user_info[2] );
          }
        }
        mount_points = ({ ({ "/", "/" }), ({ "/include", "/include" }) });
        pike_include_path += ({ "/include" });
        pike_module_path += ({ "/libraries" });
  }
  else {
    MESSAGE("change_root(%s) Failed !", getcwd());
  }
}


string apply_mount_points(string orig)
{

    int i;
    string res;
    
    if (!arrayp(mount_points))
	return orig;

    if ( search(orig, "/DB:#") == 0 )
      return orig;

    if (orig[0]!='/' && orig[0]!='#')
	orig = "/"+orig;
    res = orig;
    for (i=sizeof(mount_points);i--;)
	if (search(orig, mount_points[i][0]) == 0)
	{
	    res= mount_points[i][1]+orig[strlen(mount_points[i][0])..];
	    break;
	}
    return res;
}

object master_file_stat(string x, void|int follow)
{
    object       p;
    int    TypeURL;
    mixed    path;

#ifdef MOUNT_TRACE
    werror("[master_file_stat("+x+") ->");
#endif
    [TypeURL, path] = parse_URL_TYPE(x);
    switch (TypeURL)
    {
      case  URLTYPE_FS:
	  x = apply_mount_points(x);
#ifdef MOUNT_TRACE
          werror("fs("+x+")\n");
#endif
	  return ::master_file_stat(x);
      case URLTYPE_DB:

#ifdef MOUNT_TRACE
          werror(sprintf("db(%d)]\n",path));
#endif
          p = __DATABASE->find_object(path);
          if (objectp(p)) {
	    array s = p->stat();
	    if ( arrayp(s) && sizeof(s) > 6 )
              return Stdio.Stat(s[..6]);
	    return 0;
	  }
      case URLTYPE_DBO:
#ifdef MOUNT_TRACE
          werror(sprintf("dbo(%d)]\n",path));
#endif
          return 0;
      case URLTYPE_DBFT:
#ifdef MOUNT_TRACE
          werror(sprintf("dbft(%s)]\n", path));
#endif
          p = MODULE_FILEPATH->path_to_object(path);
	  if (objectp(p)) {
	      array s = p->stat();
	      if ( arrayp(s) && sizeof(s) > 6 )
		  return Stdio.Stat(s[..6]);
	      return 0;
	  }
    }
    return 0;
}

array(program) 
get_programs()
{
  return copy_value(values(programs));
}

/**
 * Access the program pointer currently registered for programname
 *
 * @param   string pname - the program to look up
 * @return  program      - the associated program
 * @see     upgrade, new
 * @author Ludger Merkens 
 */
program lookup_program(string pname)
{
  return programs[pname];
}

program compile_string(string source, 
		       void|string filename, 
		       object|void handler, 
		       void|program p, 
		       void|object o,
		       void|int _show_if_constant_errors)
{
  if ( !stringp(source) )
    return compile_file(filename, handler, p, o);
  return ::compile_string(source, filename, handler, p, o, _show_if_constant_errors);
}


program compile_file(string file,
                     object|void handler,
                     void|program p,
                     void|object o)
{
    int    TypeURL;
    string    path;
    string content;
    object     tmp;
 
    llog = 0;
    //LMESSAGE("compile_file("+file+")");
    [ TypeURL, path ] = parse_URL_TYPE(file);
    
    switch (TypeURL)
    {
      case URLTYPE_FS:
          file = apply_mount_points(file);
          tmp = Stdio.File(file, "r");
          content = tmp->read();
          tmp->close();
          break;
          //return ::compile_file(file);
      case URLTYPE_DBO: 
          return 0;       // dump files not supported in database
      case URLTYPE_DB:
          tmp = __DATABASE->find_object((int)path);
          content = tmp->get_source_code();
          break;
      case URLTYPE_DBFT:
          tmp = MODULE_FILEPATH->path_to_object(path);
	  if ( !objectp(tmp) || !functionp(tmp->get_source_code) ) {
	    throw( ({sprintf("COMPILING %O: no get_source_code function in %O (path=%O)", file, tmp, path), backtrace() }));
	  }
	  else
	    content = tmp->get_source_code();
          break;
    }
    if (objectp(tmp)) {
        program _loading;
	if ( !stringp(content) ) 
	{
	  content = "";
	  FATAL("Warning: No content of file %O to compile...\n", file);
	}
        //	_loading = compile(cpp(content, file));	
        if ( stringp(file) )
            m_delete(mErrors, file);
        _loading= compile(cpp(content,
                              file,
                              1,
                              handler,
                              compat_major,
                              compat_minor),
                          handler,
                          compat_major,
                          compat_minor,
                          p,
                          o);
	return _loading;
    }
    llog = 0;
    throw(({"Cant resolve filename\n", backtrace()}));
}

program cast_to_program(string pname, string current_file, void|object handler)
{
    program p;
    int     i;
    if ( (i=search(pname, "/DB:")) == 0 ) {
      if ( search(pname, ".pike") == 0 )
	pname += ".pike";
      p = lookup_program(pname);
      if ( programp(p) ) return p;
      return compile_file(pname);
    } 
    p = ::cast_to_program(pname, current_file);
    return p;
}

static program low_findprog(string pname, 
			    string ext, 
			    object|void handler, 
			    void|int mkobj) 
{
  //return ::low_findprog(apply_mount_points(pname), ext, handler, mkobj);
  return ::low_findprog(pname, ext, handler, mkobj);
}


mixed resolv(string symbol, string filename, object handler)
{
#ifdef MOUNT_TRACE
    werror("[resolve("+symbol+","+filename+sprintf(",%O)\n",handler));
#endif
    mixed erg=::resolv(symbol, filename, handler);
#ifdef MOUNT_TRACE
    werror("[resolve returns:"+sprintf("%O\n",erg));
#endif
    return erg;
}

string id_from_dbpath(string db_path)
{
    int   type_URL;
    string   _path;
    
    [type_URL, _path] = parse_URL_TYPE(db_path);
    if (type_URL == URLTYPE_DB)
    {
	if (search(_path,"#")==0)
	    return _path;
	else
	{
	    object p;
	    p = MODULE_FILEPATH->path_to_object(db_path);
	    if(objectp(p))
		return "#"+ p->get_object_id();
	    return 0;
	}
    }
    return db_path;
}

mapping get_errors()
{
    return mErrors;
}

array get_error(string file)
{
    if (mErrors[file])
        return ({ file+"\n" }) + mErrors[file];
    else
        return 0;
}

void compile_error(string file, int line, string err)
{ 
    if ( !arrayp(mErrors[file]) )
	mErrors[file] = ({ });
    mErrors[file] += ({ sprintf("%s:%s\n", line?(string)line:"-",err) });
    ::compile_error(file, line, err);
}

string handle_include(string f, string current_file, int local_include)
{
    array(string) tmp;
    string path;

    if(local_include)
    {
	tmp=current_file/"/";
	tmp[-1]=f;
	path=combine_path_with_cwd((tmp*"/"));
	if (parse_URL_TYPE(path)[0] == URLTYPE_DB)
	    path = id_from_dbpath(path);
    }
    else
    {
	foreach(pike_include_path, path) {
	    path=combine_path(path,f);
	    if (parse_URL_TYPE(path)[0] == URLTYPE_DB)
		path = id_from_dbpath(path);
	    else {
	      if(master_file_stat(path))
		break;
	      else
		path=0;
	    }
	}
    }
    return path;

}
    

string read_include(string f)
{
    llog = 0;
    llog = 0;
    if (search(f,"#")==0) // #include <%45>
    {
	object p;
	p = mConstants["_Database"]->find_object((int)f[1..]);
	//p = find_object((int)f[1..]);
	if (objectp(p))
	    return p->get_source_code();
	return 0;
    }
    return ::read_include(apply_mount_points(f));
}

#endif

int
get_type(mixed var)
{
    if ( intp(var) )
	return CMD_TYPE_INT;
    else if ( stringp(var) )
	return CMD_TYPE_STRING;
    else if ( objectp(var) )
	return CMD_TYPE_OBJECT;
    else if ( floatp(var) )
	return CMD_TYPE_FLOAT;
    else if ( arrayp(var) )
	return CMD_TYPE_ARRAY;
    else if ( mappingp(var) )
	return CMD_TYPE_MAPPING;
    else if ( functionp(var) )
	return CMD_TYPE_FUNCTION;
    return CMD_TYPE_UNKNOWN;
}

string sRoot;
void set_root(string root)
{
    sRoot = root;
}


string dirname(string x)
{
    if ((stringp(sRoot)) && search(x, sRoot)==0)
	return dirname(x[strlen(sRoot)..]);
    return ::dirname(x);
}

//string master_read_file(string file)
//{
//    LMESSAGE("master_read_file("+file+")");
//    return ::master_read_file(file);
//}

string master_read_file(string file)
{
    int TypeURL;
    string path;
    mixed p;

#ifdef MOUNT_TRACE    
    werror("master_read_file("+file+")");
#endif
    
    [TypeURL, path ] = parse_URL_TYPE(file);
    switch (TypeURL)
    {
      case URLTYPE_FS:
	  //MESSAGE("calling compile_file("+file+")");
	//file = apply_mount_points(file);
	  return ::master_read_file(file);
	  //return ::compile_file(file);
      case URLTYPE_DB:
#ifdef MOUNT_TRACE
          werror(sprintf("db(%s)\n",path));
#endif
          p = __DATABASE->find_object((int)path);
          if (p==1)
              throw(({"sourcefile deleted", backtrace()}));
          else
              if (!objectp(p))
                  throw(({"failed to load sourcefile", backtrace()}));
	  return p->get_source_code();
      case URLTYPE_DBO:
#ifdef MOUNT_TRACE
          werror(sprintf("db(%s)\n",path));
#endif
          return 0;
      case URLTYPE_DBFT:
#ifdef MOUNT_TRACE
          werror(sprintf("db(%s)\n",path));
#endif
          p = MODULE_FILEPATH->path_to_object(path);
          return p->get_source_code();
    }
    throw(({"Failed to load file"+file, backtrace()}));
}

/*object findmodule(string fullname)
{
    object o;
    llog = 0;
    LMESSAGE("findmodule("+fullname+", called by " + describe_object(CALLER));
    o=::findmodule(fullname);
    llog = 0;
    return o;
}
*/

string describe_mapping(mapping m, int maxlen)
{
    mixed keys = indices(m);
    mixed values = values(m);
    string out= "";
    for (int i=0;i<sizeof(keys);i++)
    {
	out += stupid_describe(keys[i], maxlen) +
	    ":" + detailed_describe(values[i], maxlen)
	    + (i<sizeof(keys)-1 ? "," :"");
    }
    return out;
}

string describe_array(array a, int maxlen)
{
    string out="";
    for (int i=0;i<sizeof(a);i++)
    {
	out += detailed_describe(a[i], maxlen) + (i<sizeof(a)-1 ? "," :"");
    }
    return out;
}

string describe_multiset(multiset m, int maxlen)
{
    mixed keys = indices(m);
    string out= "";
    for (int i=0;i<sizeof(keys);i++)
    {
	out += stupid_describe(keys[i], maxlen) + (i<sizeof(keys)-1 ? "," :"");
    }
    return out;
}

string detailed_describe(mixed m, int maxlen)
{
    if (maxlen == 0)
	maxlen = 2000;
    string typ;
    if (catch (typ=sprintf("%t",m)))
	typ = "object";		// Object with a broken _sprintf(), probably.
    switch(typ)
    {
      case "int":
      case "float":
	  return (string)m;
	  
      case "string":
	  if(sizeof(m) < maxlen)
	  {
	      string t = sprintf("%O", m);
	      if (sizeof(t) < (maxlen + 2)) {
		  return t;
	      }
	      t = 0;
	  }
	  if(maxlen>10)
	  {
	      return sprintf("%O+[%d]",m[..maxlen-5],sizeof(m)-(maxlen-5));
	  }else{
	      return "string["+sizeof(m)+"]";
	  }
      
      case "array":
	  if(!sizeof(m)) return "({})";
	  return "({" + describe_array(m,maxlen-2) +"})";
      
      case "mapping":
	  if(!sizeof(m)) return "([])";
	  return "([" + describe_mapping(m, maxlen-2) + "])";

      case "multiset":
	  if(!sizeof(m)) return "(<>)";
	  return "(<" + describe_multiset(m, maxlen-2) + ">)";
	  return "multiset["+sizeof(m)+"]";
      
      case "function":
	  if(string tmp=describe_program(m)) return tmp;
	  if(object o=function_object(m))
	      return (describe_object(o)||"")+"->"+function_name(m);
	  else {
	      string tmp;
	      if (catch (tmp = function_name(m)))
		  // The function object has probably been destructed.
		  return "function";
	      return tmp || "function";
	  }

      case "program":
	  if(string tmp=describe_program(m)) return tmp;
	  return typ;

      default:
	  if (objectp(m))
	      if(string tmp=describe_object(m)) return tmp;
	  return typ;
    }
}


/**
 * perform the call-out, but save the previous user-object
 *  
 */
void f_call(function f, object user, object caller, void|array(mixed) args)
{
    mixed err;

    // skip calls if function is no longer available
    if (!functionp(f)) {
      return;
    }

    //make sure caller is f_call_out....
    object old_user = oActiveUser->get();
    object old_euid = oEffectiveUser->get();
    oActiveUser->set(user);
    oEffectiveUser->set(user);
    err = catch{
      if ( objectp(caller) && functionp(caller->route_call) && function_name(f) != "drop" )
        caller->route_call(f, args);
      else
        f(@args);
    };
    oActiveUser->set(old_user);
    oEffectiveUser->set(old_euid);
    if ( err )
      FATAL("Error on call_out:"+sprintf("%O:\n%O\n", err[0], err[1]));
}

/**
 * call a function delayed. The user object is saved.
 *  
 */
mixed
f_call_out(function f, float|int delay, mixed ... args)
{
  if (!functionp(f))
    error("Unable to call NULL function !");

  object caller = CALLER;
  caller = Caller.get_caller(caller, backtrace());
  return call_out(f_call, delay, f, this_user(), caller, args);
}

mixed f_call_out_info()
{
  return call_out_info(); 
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
array(string) get_dir(string dir)
{
    string fdir = apply_mount_points(dir);
    //    MESSAGE("Getting dir of " + fdir);
    return predef::get_dir(fdir);
}

int is_dir(string dir)
{
  return Stdio.is_dir(apply_mount_points(dir));
}


/**
 * This Function is the mount-point aware of the rm command
 * rm removes a file from the filesystem
 *
 * @param string f
 * @return 0 if it fails. Nonero otherwise
 * @author Ludger Merkens (balduin@upb.de)
 * @see get_dir
 * @caveats this command is limited to removing filesystem files
 */
int rm(string f)
{
    string truef = apply_mount_points(f);
    return predef::rm(truef);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
static void run_thread(function f, object user, mixed ... args)
{
    if ( !objectp(user) ) {
      if ( objectp(oServer) ) {
	object umod = oServer->get_module("users");
	if ( objectp(umod) ) {
	  user = umod->lookup("root");
	  if ( objectp(user) )
	    user->force_load();
	}
      }
    }
    oActiveUser->set(user);
    oEffectiveUser->set(0);
    f(@args);
}

/**
 *
 *  
 * @param 
 * @return 
 * @see 
 */
void start_thread(function f, mixed ... args)
{
  MESSAGE("Starting new Thread %O", f);
  predef::thread_create(run_thread, f, this_user(), @args);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
mixed file_stat(string f, void|int follow)
{
    string ff = apply_mount_points(f);
    return predef::file_stat(ff, follow);
}

#if 0
mapping get_ports()
{
    return mPorts;
}

void use_port(int pid)
{
    mPorts[pid] == 1;
}
#endif

int free_port(int pid)
{
    return mPorts[pid] != 1;
}

void dispose_port(int pid)
{
    mPorts[pid] = 0;
}

/**
 * Find out if a given object is a socket (this means it 
 * has to be in the list of sockets.
 *  
 * @param object o - the socket object
 * @return true or false (0 or 1)
 */
int is_socket(object o)
{
    return (search(paSockets, object_program(o)) >= 0  );
}

object this() { return this_object(); }
function find_function(string f) { return this_object()[f]; }

#if (__MINOR__ > 3) // this is a backwards compatibility function
object new(string|program program_file, mixed|void ...args)
{
    program prg = (program)program_file;
    if ( !programp(prg) )
	return 0;
    
    return  (prg)(@args);
}
#endif



void describe_threads()
{
#if constant (thread_create)
  // Disable all threads to avoid potential locking problems while we
  // have the backtraces. It also gives an atomic view of the state.
  object threads_disabled = _disable_threads();

  werror("### Describing all Pike threads:\n\n");

  array(Thread.Thread) threads = all_threads();
  array(string|int) thread_ids =
    map (threads,
         lambda (Thread.Thread t) {
           string desc = sprintf ("%O", t);
           if (sscanf (desc, "Thread.Thread(%d)", int i)) return i;
           else return desc;
         });
  sort (thread_ids, threads);

  int i;
  for(i=0; i < sizeof(threads); i++) {
    werror("### Thread %s%s:\n",
                 (string) thread_ids[i],
                 threads[i] == backend_thread ? " (backend thread)" : ""
		 );
    werror(describe_backtrace(threads[i]->backtrace()) + "\n");
  }

  werror ("### Total %d Pike threads\n", sizeof (threads));

  threads = 0;
  threads_disabled = 0;
#else
  werror("Describing single thread:\n%s\n",
               describe_backtrace (backtrace()));
#endif

}
