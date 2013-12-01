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
 * $Id: protocoll.pike,v 1.8 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: protocoll.pike,v 1.8 2009/08/07 15:22:36 nicke Exp $";

inherit "binary";
inherit "login";

#include <attributes.h>
#include <coal.h>
#include <assert.h>
#include <macros.h>
#include <events.h>
#include <functions.h>
#include <attributes.h>
#include <classes.h>
#include <database.h>
#include <config.h>
#include <client.h>

//#define DEBUG_PROTOCOL

#ifdef DEBUG_PROTOCOL
#define PROTO_LOG(s, args...) werror(s+"\n", args)
#else
#define PROTO_LOG(s, args...) 
#endif

void send_message(string str);
void close_connection();
void register_send_function(function f, function e);
void set_id(int i);

static mapping        mCommandServer;
static int                 iTransfer;
static int             iTransferSize;
static object              oTransfer;
static string             session_id;

// slow command logging
static int slow = _Server->get_config("log_slow_commands");



//events
static mapping mEvents = ([ ]);


class SocketListener {
    inherit Events.Listener;
    bool myEvents = true;
    bool mapEvents = false;
    object mySocket;
    string session;

    void create(int event, object obj, object socket, bool mapE, bool receiveSelf, string s)
    {
	::create(event, PHASE_NOTIFY, obj, notify, oUser);
	session = s;
	myEvents = receiveSelf;
	mapEvents = mapE;
	mySocket = socket;
    }
    
    void notify(int event, mixed args, object eventObj) {
        object target;
	object socket = this_socket();
	
	if ( zero_type(::get_object()) ) {
	  destruct(this_object());
	  return;
	}
	if ( mySocket == socket && !myEvents ) {
	    return;
	}
        target = args[0];
	if ( mapEvents )
	    SEND_COAL(time(), COAL_EVENT, target->get_object_id(),
		      target->get_object_class(),
		      ({ event, eventObj->get_params(), session_id,
                           socket == mySocket }));
	else
	    SEND_COAL(time(), COAL_EVENT, target->get_object_id(),
		      target->get_object_class(),
		      ({ event, args[1..], session_id,
                           socket == mySocket}));
    }
    mapping save() {
	// do not save !
	return 0;
    }
}

/**
 * COAL_event is not used at all since there are usually
 * no events coming from a client.
 *  
 * @param int t_id - the transaction id
 * @param object obj - the context object
 * @param mixed args - parameter array
 * @return ok or failed
 * @author Thomas Bopp 
 */
int
COAL_event(int t_id, object obj, mixed args)
{
    return _COAL_OK;
}

int COAL_getobject(int t_id, object obj, mixed args)
{
  mapping attributes = obj->query_attributes();

  // sends only attributes yet
  send_message( coal_compose(t_id, COAL_SENDOBJECT, 
			     obj->get_object_id(), obj->get_object_class(),
			     ({ attributes }) ) );
  return _COAL_OK;
}

/**
 * COAL_command: Call a function inside steam. The args are
 * an array with one or two parameters. The first on is the function
 * to call and the second one is an array again containing all the
 * parameters to be passed to the function call.
 *  
 * @param int t_id - the transaction id
 * @param object obj - the context object
 * @param mixed args - parameter array
 * @return ok or failed
 * @author Thomas Bopp 
 */
int
COAL_command(int t_id, object obj, mixed args)
{
    int              cmd;
    function           f;
    mixed            res;
    
    if ( !objectp(obj) ) return E_NOTEXIST | E_OBJECT;
    if ( obj->status && obj->status() == PSTAT_DELETED ) return E_DELETED;
    
    if ( sizeof(args) >= 2 )
	[ cmd, args ] = args;
    else {
	cmd = args[0];
	args = ({ });
    }
    if ( functionp(obj->get_object) ) {
      f = obj->find_function( cmd );
      obj = obj->get_object();
    }
    else if ( !functionp( f = obj[cmd] ) )
      f = obj->this()->find_function( cmd );
    
    if ( !functionp(f) )
      THROW("Function: " + cmd + " not found inside ("+obj->get_object_id()+
	    ")", E_FUNCTION|E_NOTEXIST);
    
    if ( !arrayp(args) ) args = ({ args });
    
    int oid = obj->get_object_id();
    int oclass = obj->get_object_class();

    int tt = get_time_millis();
    res = f(@args);
    tt = get_time_millis() - tt;
    if ( slow && tt > slow )
      get_module("log")->log("slow_requests", LOG_LEVEL_INFO, 
			     "%s Functioncall of %s in %O took %d ms", 
			     timelib.event_time(time()), cmd, obj, tt);
    
    if ( objectp(oUser) ) 
      oUser->command_done(time());
    
    if ( objectp(res) && 
	 functionp(res->is_async_return) && 
	 res->is_async_return() ) 
    {
      res->resultFunc = coal_send_result;
      res->tid = t_id;
      res->cmd = COAL_COMMAND;
      res->oid = oid;
      res->oclass = oclass;
    }
    else {
      SEND_COAL(t_id, COAL_COMMAND, oid, oclass, res);
    }
    
    return _COAL_OK;
}

static void coal_send_result(object ret, mixed res)
{
  SEND_COAL(ret->tid, ret->cmd, ret->oid, ret->oclass, res);
}

/**
 * COAL_query_commands: returns a list of callable commands of the 
 * given object.
 *  
 * @param int t_id - the transaction id
 * @param object obj - the context object
 * @param mixed args - parameter array
 * @return ok or failed
 * @author Thomas Bopp 
 * @see 
 */
int 
COAL_query_commands(int t_id, object obj, mixed args)
{
    if ( !objectp(obj) )
	return E_NOTEXIST | E_OBJECT; 
    THROW("query_commands is unsupported", E_ERROR_PROTOCOL);

    return _COAL_OK;
}

/**
 * Set the client features of this connection.
 *  
 * @param int t_id - the transaction id
 * @param object obj - the context object
 * @param mixed args - parameter array
 * @return ok or failed.
 * @author Thomas Bopp (astra@upb.de) 
 */
int 
COAL_set_client(int t_id, object obj, mixed args)
{
    if ( sizeof(args) != 1 || !intp(args[0]) )
	return E_FORMAT | E_TYPE;
    iClientFeatures = args[0];
    SEND_COAL(t_id, COAL_SET_CLIENT, 0, 0, ({ }));
    return _COAL_OK;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int COAL_ping(int t_id, object obj, mixed args)
{
    SEND_COAL(t_id, COAL_PONG, 0, 0, ({ }));
    return _COAL_OK;
}

int COAL_pong(int t_id, object obj, mixed args)
{
    // clients are not supposed to send pongs
}

/**
 * Login the server with name and password. Optional the parameters client-name
 * and features can be used to login. If no features and name is given the
 * server will use "steam" and all client features. Otherwise the file client.h
 * describes all possible features. Right now only CLIENT_FEATURES_EVENTS 
 * (enables the socket to get events) and CLIENT_FEATURES_MOVE (moves the
 * user to his workroom when disconnecting and back to the last logout place
 * when connecting). Apart from that the features can be checked at the user
 * object by calling the function get_status(). It will return a bit vector
 * of all set features. This enables clients to check if a user hears a chat
 * for example.
 *
 * @param t_id - id of the transfer
 * @param obj_id - the relevant object
 * @param args - the arguments, { user, password } optional two other 
 *               parameters could be used: { user, password, client-name,
 *               client-features }
 * @return ok or error code
 * @author Thomas Bopp 
 * @see COAL_logout
 * @see database.lookup_user
 */
int 
COAL_login(int t_id, object obj, mixed args)
{
    object            uid;
    string u_name, u_pass;

    if ( sizeof(args) < 2 || !stringp(args[0]) || !stringp(args[1]) )
	return E_FORMAT | E_TYPE;
    
    u_name = args[0]; /* first argument is the username */
    u_pass = args[1];
    PROTO_LOG("login("+u_name+")");
    sClientClass = CLIENT_CLASS_STEAM;
    if ( sizeof(args) > 3 ) {
	sClientClass = args[2];
	if ( !intp(args[3]) )
	    THROW("Third argument is not an integer", E_TYPE);
	iClientFeatures = args[3];
    }
    else
	iClientFeatures = CLIENT_STATUS_CONNECTED;

    if ( sizeof(args) == 5 )
      set_id(args[4]);
    
    mixed err = catch(uid = get_module("auth")->authenticate(u_name, u_pass));
    if ( err )
    {
        FATAL("COAL: failed to authenticate: %O\n", err[0], err[1]);
	return E_ACCESS | E_PASSWORD;
    }
    if ( !objectp(uid) )
	return E_ACCESS | E_PASSWORD;

    if ( functionp(uid->is_async_return) && uid->is_async_return() ) {
      uid->resultFunc = async_login_user;
      uid->tid = t_id;
    }
    else {
      do_login_user(uid, t_id);
    }
    return _COAL_OK;
}

static void async_login_user(object async, object uid)
{
  do_login_user(uid, async->tid);
}

static void do_login_user(object uid, int t_id)
{
    // allready connected to user - relogin
    logout_user();

    int last_login = login_user(uid);    
    object server = master()->get_server();
    
    session_id = uid->get_session_id();
    send_message( coal_compose(t_id, COAL_LOGIN, uid->get_object_id(),
			       uid->get_object_class(),
			       ({ uid->get_user_name(), 
				  server->get_version(), 
				  server->get_last_reboot(),
				  last_login,
				  version(), 
				  _Database,
				  MODULE_OBJECTS->lookup("rootroom"),
				  MODULE_GROUPS->lookup("sTeam"),
				  _Server->get_modules(),
				  _Server->get_classes(),
				  _Server->get_configs(),
				  session_id,
				  COAL_VERSION,
			       })) );
}

int COAL_hello(int t_id, object obj, mixed args)
{
    string name, cert;

    if ( sizeof(args) < 2 || !stringp(args[0]) || !stringp(args[1]) )
      return E_FORMAT | E_TYPE;
    
    object cluster = get_module("Cluster");
    if ( !objectp(cluster) )
      steam_error("Standalone sTeam-Server !");
    
    
    name = args[0]; /* first argument is the username */
    cert = args[1];
    object server = cluster->hello(name, cert);
    if ( !objectp(server) )
      steam_error("Unable to verify Authentication !");
    login_user(server); // establish connection with server object
    sClientClass = CLIENT_CLASS_SERVER;
    send_message( coal_compose(t_id, COAL_LOGIN, 0,
			       server->get_id(),
			       ({ name, server->get_version(), 
				      server->get_last_reboot(),
				      0,
				      version(), _Database,
				      MODULE_OBJECTS->lookup("rootroom"),
				      MODULE_GROUPS->lookup("sTeam"),
				      _Server->get_modules(),
				      _Server->get_classes(),
				      _Server->get_configs(),
				      })) );
    return _COAL_OK;
}    

int COAL_relogin(int t_id, object obj, mixed args)
{
    object            uid;
    string u_name, u_pass;
    int        last_login;

    if ( sizeof(args) < 2 || !stringp(args[0]) || !stringp(args[1]) )
	return E_FORMAT | E_TYPE;
    
    u_name = args[0]; /* first argument is the username */
    u_pass = args[1];
        sClientClass = CLIENT_CLASS_STEAM;
    if ( sizeof(args) > 3 ) {
	sClientClass = args[2];
	if ( !intp(args[3]) )
	    THROW("Third argument is not an integer", E_TYPE);
	iClientFeatures = args[3];
    }
    else
	iClientFeatures = CLIENT_STATUS_CONNECTED;

    if ( sizeof(args) == 5 )
      set_id(args[4]);
    
    uid = get_module("auth")->authenticate( u_name, u_pass );
    
    if ( !objectp(uid) )
	return E_ACCESS | E_PASSWORD;

    logout_user();

    last_login = login_user(uid);

    send_message( coal_compose(t_id, COAL_LOGIN, uid->get_object_id(),
			       uid->get_object_class(), ({ })) );
    return _COAL_OK;
}

/**
 * called when logging out
 *  
 * @param t_id - the current transaction id
 * @param obj - the relevant object (not used in this case)
 * @return ok - works all the time
 * @see COAL_login
 */
int
COAL_logout(int t_id, object obj, mixed args)
{
    PROTO_LOG("Logging out...\n");
    close_connection();
    logout_user();
    return _COAL_OK;
}

/**
 * COAL_file_download
 *  
 * @param t_id - the transaction id of the command
 * @param obj - the relevant object
 * @param args - arguments for the download (ignored)
 * @return error code or ok
 * @author Thomas Bopp 
 * @see 
 */
int
COAL_file_download(int t_id, object obj, mixed args)
{
    function send;
    string   type;

    if ( !objectp(obj) )
	return E_NOTEXIST | E_OBJECT;
    else if ( obj->get_content_size() == 0 ) {
      SEND_COAL(t_id, COAL_FILE_UPLOAD, obj->get_object_id(),
		obj->get_object_class(), ({ obj->get_content_size() }));
      return _COAL_OK;
    }
	    
    
    if ( !arrayp(args) )
	args = ({ });

    type = obj->query_attribute(DOC_MIME_TYPE);
    PROTO_LOG("mime:"+type);
    obj = obj->get_object();
    
    if ( !functionp(obj->get_content_callback) ) {
      object index;
      if ( obj->get_object_class() & CLASS_CONTAINER ) {
	
	index = obj->get_object_byname("index.html");
	if ( !objectp(index) ) 
	  index = obj->get_object_byname("index.htm");
	if ( !objectp(index) ) 
	  index = obj->get_object_byname("index.xml");
      }
      if ( !objectp(index) )
	return E_ERROR;
      obj = index->get_object();
    }
    
    if ( sizeof(args) == 0 )
      send = obj->get_content_callback( ([ "raw": 1, ]) );
    else
      send = obj->get_content_callback(args[0]);
    
    PROTO_LOG("Now acknowledging download !");
    SEND_COAL(t_id, COAL_FILE_UPLOAD, obj->get_object_id(),
	      obj->get_object_class(), ({ obj->get_content_size() }));
    type = "";
    
    iTransfer = COAL_TRANSFER_SEND;
    register_send_function(send, download_finished);
    return _COAL_OK;
}

static void receive_message(string str) { } 

/**
 * download finished will set the mode back to no-transfer
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see COAL_file_download
 */
private void download_finished()
{
    PROTO_LOG("transfer finished...");
    iTransfer = COAL_TRANSFER_NONE;
    receive_message("");
}

/**
 * COAL_file_upload
 *  
 * @param t_id - the transaction id of the command
 * @param obj - the relevant object
 * @param args - arguments for the upload (1 arg, url and size)
 * @return error code or ok
 * @author Thomas Bopp 
 * @see COAL_file_download
 */
int
COAL_file_upload(int t_id, object obj, mixed args)
{
    string        url;
    int          size;
    object   path = 0;

    /* 
     * find the object or create it... 
     */
    if ( !arrayp(args) || 
	 (sizeof(args) != 1 && sizeof(args) != 2 && sizeof(args) != 3) )
    { 
	return E_FORMAT | E_TYPE;
    }
    switch ( sizeof(args) ) {
    case 3:
	[ path, url, size ] = args;
	break;
    case 2:
        [url, size] = args;
	break;
    case 1:
        [ url ] = args;
        size = -1;
    }
    
    if ( objectp(path) ) {
	obj = _FILEPATH->resolve_path(path, url);
    }
    else {
	obj = _FILEPATH->path_to_object(url);
    }
    if ( !objectp(obj) ) {
	object factory, cont;

	factory = _Server->get_factory(CLASS_DOCUMENT);
	cont = _FILEPATH->path_to_environment(url);
	obj = factory->execute((["url":url,]));
	if ( objectp(path) )
	    obj->move(path);
	PROTO_LOG("object created="+master()->stupid_describe(obj,255));
    }
    else 
	PROTO_LOG("found object.="+master()->stupid_describe(obj,255));
    
    if ( !functionp(obj->receive_content) )
	return E_NOTEXIST | E_OBJECT;
    PROTO_LOG("sending ok...");
    SEND_COAL(t_id, COAL_FILE_DOWNLOAD, 0, 0, ({ obj }));
    iTransfer = COAL_TRANSFER_RCV;
    iTransferSize = size;
    oTransfer = ((program)"/kernel/DocFile")(obj, "wct");
    obj->set_attribute(DOC_LAST_ACCESSED, time());
    obj->set_attribute(DOC_LAST_MODIFIED, time());
    return _COAL_OK;
}

/**
 * COAL_upload_start - start an upload and
 * call upload_package subsequently.
 *  
 * @param t_id - the transaction id of the command
 * @param obj - the relevant object
 * @param args - arguments for the upload (1 arg, url and size)
 * @return error code or ok
 * @author Thomas Bopp 
 * @see COAL_file_download
 */
int
COAL_upload_start(int t_id, object obj, mixed args)
{
    string|object url;
    int          size;
    /* find the object or create it... */
    
    if ( !arrayp(args) || sizeof(args) != 1 ) 
	return E_FORMAT | E_TYPE;
    size    = 0;
    [ url ] = args;
    
    if ( objectp(url) ) 
	obj = url;
    else
	obj = _FILEPATH->path_to_object(url);

    if ( !objectp(obj) ) {
	object factory, cont;

	factory = _Server->get_factory(CLASS_DOCUMENT);
	if ( !objectp(factory) ) LOG("Unable to find document factory !\n");
	cont = _FILEPATH->path_to_environment(url);
	obj = factory->execute((["url":url,]));
	PROTO_LOG("object created="+master()->stupid_describe(obj,255));
    }
    else 
	PROTO_LOG("found object.="+master()->stupid_describe(obj,255));
    
    if ( !functionp(obj->receive_content) )
	return E_NOTEXIST | E_OBJECT;
    SEND_COAL(t_id, COAL_FILE_DOWNLOAD, 0, 0, ({ obj }) );
    iTransfer = 0; 
    // only set upload function, but dont set transfer mode,
    // this means the protocoll is not blocking anymore !
    oTransfer = ((program)"/kernel/DocFile")(obj, "wct");
    obj->set_attribute(DOC_LAST_ACCESSED, time());
    obj->set_attribute(DOC_LAST_MODIFIED, time());
    return _COAL_OK;
}

/**
 * Upload a package to steam. Before this command can be used
 * there has to be a call to upload start before to define
 * a callback function receiving the data.
 *  
 * @param t_id - the transaction id of the command.
 * @param obj - the relevant object.
 * @param args - arguments for the query containing the content.
 * @return ok or failed.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int COAL_upload_package(int t_id, object obj, mixed args)
{
    if ( !objectp(oTransfer) ) 
	THROW("No upload function - start upload with COAL_UPLOAD_START !",
	      E_ERROR);
    PROTO_LOG("uploading...");
    if ( sizeof(args) != 1 )
	return E_FORMAT | E_TYPE;
    PROTO_LOG("upload_package()");
    if ( !stringp(args[0]) || args[0] == 0 ) {
	oTransfer->close();
	destruct(oTransfer);
	oTransfer = 0;
	PROTO_LOG("Finished upload !\n");
        // at this point send back that we are finished, so client can logout
	SEND_COAL(t_id, COAL_UPLOAD_FINISHED, 0, 0, ({ obj })); 
	return _COAL_OK;
    }
    PROTO_LOG("Received package: " + strlen(args[0]));
    oTransfer->write(args[0]);
    return _COAL_OK;
}


int COAL_log(int t_id, object obj, mixed args)
{
    if ( sizeof(args) != 1 )
	return E_FORMAT | E_TYPE;
}

int COAL_retr_log(int t_id, object obj, mixed args)
{
}

static int add_event(object obj, int event, bool receiveSelf, bool mapEvents)
{
    if ( !mappingp(mEvents[event]) )
      mEvents[event] = ([ ]);
    if ( objectp(mEvents[event][obj]) )
      return event;

    SocketListener l = SocketListener(event, obj, this_object(), mapEvents,
				      receiveSelf, session_id);

    mEvents[event][obj] = l;
    object listener = obj->listen_event(l);
    if ( listener->get_listener_id() != l->get_listener_id() ) {
	steam_error("Found previous listener !");
    }
    return event;
}

int COAL_subscribe(int t_id, object obj, mixed args)
{
    int        id, i;
    array new_events;
    bool receiveSelf;
    bool   mapEvents;

    receiveSelf = true;

    if ( sizeof(args) != 1 && sizeof(args) != 2 )
	return E_FORMAT | E_TYPE;
    
    mixed events = args[0];
    if ( sizeof(args) >= 2 )
	mapEvents = args[1];
    if ( sizeof(args) >= 3 )
	receiveSelf = args[2];

    
    new_events = ({ });

    
    if ( !arrayp(events) ) {
	int mask = events & 0xf0000000;
	for ( i = 0; i < 28; i++ ) {
	    if (  (id = events & (1<<i)) > 0 ) 
		new_events+=({ add_event(obj,id|mask,receiveSelf,mapEvents) });
	}
    }
    else {
	for ( i = 0; i < sizeof(events); i++ )
	    new_events+=({ add_event(obj, events[i], receiveSelf, mapEvents)});
    }
    SEND_COAL(t_id, COAL_SUBSCRIBE, obj->get_object_id(),
	      obj->get_object_class(), ({ new_events }));
    return _COAL_OK;
}

mapping get_events()
{
  return mEvents;
}

int COAL_unsubscribe(int t_id, object obj, mixed args)
{
    int events_removed = 0;
    array           events;
    
    if ( !arrayp(args) )
	events = ({ args });
    else
	events = args;

    PROTO_LOG("Unsubscribing events (%s) = %O", obj->describe(), events);
    for ( int i = 0; i < sizeof(events); i++ ) {
        if ( !mappingp(mEvents[events[i]]) )
	    continue;
        object listener = mEvents[events[i]][obj];
	if ( objectp(listener) ) {
	    object target = listener->get_object();
	    if ( objectp(target) ) 
		target->ignore_event(listener);
	    destruct(listener);
	    m_delete(mEvents[events[i]], obj);
	    events_removed++;
	}
	else
	  FATAL("Cannot remove listener for %d on %s", events[i], 
		obj->describe());
    }
    SEND_COAL(t_id, COAL_UNSUBSCRIBE, obj->get_object_id(),
	      obj->get_object_class(), ({ events_removed }));
    return _COAL_OK;
}

int COAL_reg_service(int t_id, object obj, mixed args)
{
  if ( !objectp(obj) || obj == _Server )
    obj = get_module("ServiceManager");
  obj->register_service(send_service, notify_service, @args);
  SEND_COAL(t_id, COAL_REG_SERVICE, obj->get_object_id(),
	    obj->get_object_class(), ({  }));
  return _COAL_OK;
}

static void send_service(mixed args)
{
  catch(SEND_COAL(0, COAL_COMMAND, 0, 0, ({ "call_service", args })));
}

static void notify_service(object event, string name)
{
  mapping args = event->get_params();
  args->name = name;
  catch(SEND_COAL(0, COAL_COMMAND, 0, 0, ({ "notify", args })));
}



/**
 * Initialize the protocoll.
 */
void
init_protocoll()
{
    mCommandServer = ([
	COAL_EVENT:   COAL_event,
	COAL_COMMAND: COAL_command,
	COAL_LOGIN: COAL_login,
	COAL_LOGOUT: COAL_logout,
	COAL_FILE_UPLOAD: COAL_file_upload,
	COAL_FILE_DOWNLOAD: COAL_file_download,
	COAL_SET_CLIENT: COAL_set_client,
	COAL_UPLOAD_PACKAGE: COAL_upload_package,
	COAL_UPLOAD_START: COAL_upload_start,
	COAL_PING: COAL_ping,
	COAL_PONG: COAL_pong,
	COAL_LOG: COAL_log,
	COAL_RETR_LOG: COAL_retr_log,
	COAL_SUBSCRIBE: COAL_subscribe,
	COAL_UNSUBSCRIBE: COAL_unsubscribe,
	COAL_REG_SERVICE: COAL_reg_service,
	COAL_RELOGIN: COAL_relogin,
	COAL_SERVERHELLO: COAL_hello,
	COAL_GETOBJECT: COAL_getobject,
    ]);
  // any connection is guest user first!
  login_user(_Persistence->lookup_user("guest"));
}

/**
 * send a message to the client - this function can only be called
 * by the connected user-object
 *  
 * @param tid - transaction id
 * @param cmd - the command
 * @param obj - the relevant object
 * @param args - the arguments for the command
 * @see coal_compose
 */
final void
send_client_message(int tid, int cmd, object obj, mixed ... args)
{
    if ( !is_user_object(CALLER) )
	return;
    if ( tid == USE_LAST_TID )
	tid = iLastTID;
    SEND_COAL(tid, cmd, obj->get_object_id(), obj->get_object_class(), args);
}

/**
 * Compose a coal command by passing a number of parameters.
 *  
 * @param int t_id - the transaction id
 * @param int cmd - the coal command to call
 * @param int o_id - the object id of the context object
 * @param int class_id - the class of the context object
 * @param mixed args - the parameters
 * @return composed string
 */
string coal_compose(int t_id, int cmd, int o_id, int class_id, mixed args)
{
    return ::coal_compose(t_id, cmd, o_id, class_id, args);
}


static void logout_user()
{
    foreach(indices(mEvents), int event)
      if ( mappingp(mEvents[event]) )
	foreach(values(mEvents[event]), object listener)
	  destruct(listener);
    ::logout_user();
}
