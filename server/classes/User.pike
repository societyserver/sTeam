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
 * $Id: User.pike,v 1.7 2010/01/25 19:18:18 astra Exp $
 */

constant cvs_version="$Id: User.pike,v 1.7 2010/01/25 19:18:18 astra Exp $";


//! this is the user object. It keeps track of connections and membership
//! in groups.

inherit "/classes/Container" : __cont;
inherit "/base/member" :     __member;

#include <attributes.h>
#include <assert.h>
#include <macros.h>
#include <events.h>
#include <coal.h>
#include <classes.h>
#include <database.h>
#include <access.h>
#include <types.h>
#include <client.h>
#include <config.h>
#include <exception.h>

//#define EVENT_USER_DEBUG

#ifdef EVENT_USER_DEBUG
#define DEBUG_EVENT(s, args...) werror(s+"\n", args)
#else
#define DEBUG_EVENT(s, args...)
#endif

/* Security relevant functions */
private static string  sUserPass; // the password for the user
private static string sPlainPass;
private static string  sUserName; // the name of the user
private static object oActiveGrp; // the active group
private static int  iCommandTime; // when the last command was send

private static mapping mAttributeAccess = ([ ]); // set readable

private static string         sTicket;
private static array(string) aTickets;
private static int        iActiveCode;

        static mapping          mSockets;
        static mapping       mMoveEvents;
private static mapping     mSocketEvents;
        static mapping mVirtualConnections;

bool userLoaded = false;

static Thread.Mutex annotationMutex = Thread.Mutex();

object this() { return __cont::this(); }
bool   check_swap() { return false; }
bool   check_upgrade() { return false; }

static void 
init()
{
    ::init();
    ::init_member();
    mSockets      = ([ ]);
    mSocketEvents = ([ ]);
    mVirtualConnections = ([ ]);
    sTicket       = 0;
    
    /* the user name is a locked attribute */
    add_data_storage(STORE_USER, store_user_data, restore_user_data, 1);
}

/**
 * Constructor of the user object.
 *
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void
create_object()
{
    ::create_object();

    sUserName  = "noone";
    sUserPass  = "steam";
    sPlainPass = 0;

    sTicket         = 0;
    aTickets        = ({ });
    mAttributeAccess = ([ ]);
    iActiveCode     = 0;
}

/**
 * Creating a duplicate of the user wont work.
 *  
 * @return throws an error
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object duplicate(void|mapping vars)
{
    THROW("User cannot be duplicated !\n", E_ERROR);
}

/**
 * register the object in the database.
 *  
 * @param name - the name of the object
 * @author Thomas Bopp (astra@upb.de) 
 */
static void database_registration(string name)
{
    MODULE_USERS->register(name, this());
}

/**
 * Destructor of the user.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see create
 */
static void
delete_object()
{
    mixed err;

    if ( this() == MODULE_USERS->lookup("root") )
	THROW("Cannot delete the root user !", E_ACCESS);

    WARN("DELETING user %O by %O through %O", sUserName, this_user(), CALLER);
    MODULE_USERS->unregister_user(this());
    object mailbox = do_query_attribute(USER_MAILBOX);
    // delete the mailbox recursively
    if ( objectp(mailbox) ) {
	foreach(mailbox->get_inventory(), object inv) {
	    err = catch {
		inv->delete();
	    };
	}
	err = catch {
	    mailbox->delete();
	};
    }
    err = catch {
      object workroom = do_query_attribute(USER_WORKROOM);
      if ( objectp(workroom) ) workroom->delete();
    };
    if ( err != 0 )
      FATAL( "Failed to delete workroom of \"%s\": %O\n%O\n", sUserName, err[0], err[1] );
    err = catch {
      object bookmarks = do_query_attribute(USER_BOOKMARKROOM);
      if ( objectp(bookmarks) ) bookmarks->delete();
    };
    if ( err != 0 )
      FATAL( "Failed to delete bookmars of \"%s\": %O\n%O\n", sUserName, err[0], err[1] );
    err = catch {
      object calendar = do_query_attribute(USER_CALENDAR);
      if ( objectp(calendar) ) calendar->delete();
    };
    if ( err != 0 )
      FATAL( "Failed to delete calendar of \"%s\": %O\n%O\n", sUserName, err[0], err[1] );
    
    __member::delete_object();
    __cont::delete_object();
}

/**
 * Dont update a users name.
 */
void update_identifier()
{
}

/**
 * Dont update a users path (its ~username anyway)
 */
void update_path() 
{
}

/**
 * Create all the exits to the groups the user is member of.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void create_group_exits()
{
    object workroom = do_query_attribute(USER_WORKROOM);
    if ( objectp(workroom) ) {
	array(object) inv = workroom->get_inventory();
	array(object) groups = get_groups();
	mapping mExits = ([ ]);
	
	foreach ( groups, object grp ) {
	    if ( !objectp(grp) ) continue;
	    mapping exits = grp->query_attribute(GROUP_EXITS);
	    if ( !mappingp(exits) ) {
		object workroom = grp->query_attribute(GROUP_WORKROOM);
		exits = ([ workroom: workroom->get_identifier(), ]);
	    }
	    mExits += exits;
	}
	foreach ( indices(mExits), object exit ) {
	    bool       found_exit;

	    if ( !objectp(exit) ) 
		continue;
	    found_exit = false;
	    foreach ( inv, object o ) {
		if ( o->get_object_class() & CLASS_EXIT ) {
		    object exit_to = o->get_link_object();
		    if ( !objectp(exit_to) )
                       continue;
		    if ( exit_to->get_object_id() == exit->get_object_id() )
			found_exit = true;
		}
	    }
	    if ( !found_exit ) {
		object factory = _Server->get_factory(CLASS_EXIT);
		object exit = factory->execute(
		    ([ "name": mExits[exit], "exit_to": exit, ]) );
		exit->sanction_object(this(), SANCTION_ALL);
		exit->move(workroom);
	    }
	}
    }
}

static string new_session_id()
{
    string sid;
#if constant(Crypto.Random) 
    sid = sprintf("%x", hash(Crypto.Random.random_string(10)));
#else
    sid = sprintf("%x", hash(random(1000000) + time() + sUserName+sUserPass));
#endif
    return sid;
}

/**
 * Connect the user object to a steamsocket.
 *  
 * @param obj - the steamsocket to connect to
 * @return the time of the last login
 * @author Thomas Bopp 
 * @see disconnect
 * @see which_socket
 */
int
connect(object obj)
{
    int last_login, i;
    
    LOG("Connecting "+ get_identifier()+" with "+ obj->describe()+"\n");

    if ( !IS_SOCKET(CALLER) )
	THROW("Trying to connect user to non-steamsocket !", E_ACCESS);
    
    array aoSocket = values(mSockets);
    for ( i = sizeof(aoSocket) - 1; i >= 0; i-- ) {
	if ( aoSocket[i] == obj )
	    return 0;
    }
    int features = obj->get_client_features();
    int prev_features = get_status();
    try_event(EVENT_LOGIN, this(), features, prev_features);


    string sid = new_session_id();
    while ( objectp(mSockets[sid]) || objectp(mVirtualConnections[sid]) )
	sid = new_session_id();
    mSockets[sid] = obj;
    mSockets[obj] = sid;

    m_delete(mSockets, 0);
    foreach ( indices(mSockets), sid) 
	if ( !objectp(mSockets[sid]) && !stringp(mSockets[sid]) ) 
	    m_delete(mSockets, sid);

    last_login = do_query_attribute(USER_LAST_LOGIN);
    do_set_attribute(USER_LAST_LOGIN, time());
    
    if ( (prev_features & features) != features ) 
	run_event(EVENT_STATUS_CHANGED, this(), features, prev_features);
    run_event(EVENT_LOGIN, this(), features, prev_features);

    return last_login;
}

/**
 * Connect the user object to a virtual connection.
 *  
 * @param obj - the virtual connection to connect to
 * @return the time of the last login
 * @see disconnect_virtual
 */
int connect_virtual ( object connection ) {
  int last_login;
  LOG( "Connecting (virtual) " + get_identifier() + " with "
       + connection->describe() + "\n" );
  if ( has_value( mVirtualConnections, connection ) )
    return 0;
  int features = connection->get_client_features();
  int prev_features = get_status();
  try_event( EVENT_LOGIN, this(), features, prev_features );
  
  string sid = new_session_id();
  while ( objectp(mSockets[sid]) || objectp(mVirtualConnections[sid]) )
    sid = new_session_id();
  mVirtualConnections[ sid ] = connection;
  mVirtualConnections[ connection ] = sid;

  m_delete( mVirtualConnections, 0 );
  foreach ( indices(mVirtualConnections), sid )
    if ( !objectp(mVirtualConnections[sid]) &&
         !stringp(mVirtualConnections[sid]) )
      m_delete( mVirtualConnections, sid );

  last_login = do_query_attribute( USER_LAST_LOGIN );
  do_set_attribute( USER_LAST_LOGIN, time() );
    
  if ( (prev_features & features) != features ) 
    run_event(EVENT_STATUS_CHANGED, this(), features, prev_features);
  run_event(EVENT_LOGIN, this(), features, prev_features);

  return last_login;
}

string get_session_id() 
{
    if ( !IS_SOCKET(CALLER) )
	THROW("Trying to steal session by non-socket !", E_ACCESS);
    foreach( indices(mSockets), string sid) {
	if ( mSockets[sid] == CALLER )
	    return sid;
    }
    return "0";
}

string get_virtual_session_id () {
  mixed sid = mVirtualConnections[ CALLER ];
  if ( stringp(sid) ) return sid;
  return "0";
}

bool join_group(object grp)
{
  try_event(EVENT_USER_JOIN_GROUP, CALLER, grp);
  mixed res = ::join_group(grp);
  require_save(STORE_USER);
  run_event(EVENT_USER_JOIN_GROUP, CALLER, grp);
  return res;
}

bool leave_group(object grp)
{
  try_event(EVENT_USER_LEAVE_GROUP, CALLER, grp);
  mixed res = ::leave_group(grp);
  run_event(EVENT_USER_LEAVE_GROUP, CALLER, grp);
  return res;
}

/**
 * Close the connection to socket and logout.
 *  
 * @param obj - the object to remove from active socket list
 * @author Thomas Bopp (astra@upb.de) 
 * @see disconnect
 */
static void
close_connection(object obj)
{
    if ( which_socket(obj) < 0 ) return;
    
    try_event(EVENT_LOGOUT, CALLER, obj);

    foreach(indices(mSockets), string sid)
	if ( mSockets[sid] == obj )
	    m_delete(mSockets, sid);

    int cfeatures = obj->get_client_features();
    int features = get_status();

    if ( (cfeatures & features) != cfeatures ) 
	run_event(EVENT_STATUS_CHANGED, this(), cfeatures, features);

    ASSERTINFO(which_socket(obj) < 0, "Still connected to socket !");
    DEBUG_EVENT(sUserName+": logout event....");
    run_event(EVENT_LOGOUT, CALLER, obj);
}

/**
 * Close the connection to a virtual connection and logout.
 *  
 * @param obj - the object to remove from active virtual connection list
 * @see disconnect_virtual
 */
static void close_virtual_connection ( object connection ) {
  if ( !has_value( mVirtualConnections, connection ) ) return;
    
  try_event( EVENT_LOGOUT, CALLER, connection );

  m_delete( mVirtualConnections, mVirtualConnections[connection] );
  m_delete( mVirtualConnections, connection );

  int cfeatures = connection->get_client_features();
  int features = get_status();

  if ( (cfeatures & features) != cfeatures ) 
    run_event( EVENT_STATUS_CHANGED, this(), cfeatures, features );

  ASSERTINFO( !has_value( mVirtualConnections, connection),
              "Still connected to virtual connection !" );
  DEBUG_EVENT( sUserName+": logout event...." );
  run_event( EVENT_LOGOUT, CALLER, connection );
}

/**
 * Disconnect the CALLER socket from this user object.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see connect
 */
void disconnect()
{
    object socket = CALLER;
    int             status;

    if ( which_socket(socket) == -1 )
      return; 
    
    if ( arrayp(mSocketEvents[socket]) ) {
	foreach ( mSocketEvents[socket], mixed event_data )
	    if ( arrayp(event_data) )
		remove_event(@event_data);
    }
    // get the remaining status of the user
    status = 0;
    array aoSocket = values(mSockets);
    foreach ( aoSocket, mixed sock ) {
	if ( objectp(sock) && sock != socket ) {
	    status |= sock->get_client_features();
	}
    }
    foreach ( values(mVirtualConnections), object conn ) {
      if ( objectp(conn) )
        status |= conn->get_client_features();
    }

#ifdef MOVE_WORKROOM
    // if this is a client which allows movement of the user
    // then move the user back to its workroom
    if ( !(status & CLIENT_FEATURES_MOVE) ) 
    {
	object workroom = do_query_attribute(USER_WORKROOM);
	if ( oEnvironment != workroom ) {
	    LOG("Closing down connection to user - moving to workroom !");
	    do_set_attribute(USER_LOGOUT_PLACE, oEnvironment);
	    if ( objectp(workroom) )
		move(workroom);
	}
    }
#endif
    close_connection(socket);
}

/**
 * Disconnect the CALLER virtual connection from this user object.
 *  
 * @see connect_virtual
 */
void disconnect_virtual () {
  object connection = CALLER;
  
  if ( !has_value( mVirtualConnections, connection) )
    return; 
  
  // get the remaining status of the user
  int status = 0;
  foreach ( values(mSockets), object sock ) {
    if ( objectp(sock) )
      status |= sock->get_client_features();
  }
  foreach ( values(mVirtualConnections), object conn ) {
    if ( objectp(conn) && conn != connection )
      status |= conn->get_client_features();
  }

#ifdef MOVE_WORKROOM
  // if this is a client which allows movement of the user
  // then move the user back to its workroom
  if ( !(status & CLIENT_FEATURES_MOVE) ) {
    object workroom = do_query_attribute( USER_WORKROOM );
    if ( oEnvironment != workroom ) {
      LOG("Closing down connection to user - moving to workroom !");
      do_set_attribute( USER_LOGOUT_PLACE, oEnvironment );
      if ( objectp(workroom) )
        move( workroom );
    }
  }
#endif
  close_virtual_connection( connection );
}

/**
 * find out if the object is one of the connected sockets
 *  
 * @param obj - the object to find out about
 * @return the position of the socket in the socket array
 * @author Thomas Bopp (astra@upb.de) 
 * @see connect
 * @see disconnect
 */
static int 
which_socket(object obj)
{
    return search(values(mSockets), obj);
}

/**
 * Activate the login. Successfull activation code is required to do so!
 *  
 * @param int activation - the activation code
 * @return true or false
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool activate_user(int|void activation)
{
    if ( activation == iActiveCode || _ADMIN->is_member(this_user()) ) {
	iActiveCode = 0;
	require_save(STORE_USER);
	return true;
    }
    return false;
}

/**
 * Set the activation code for an user - this is done by the factory.
 *  
 * @param int activation - the activation code.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see activate_user
 */
void set_activation(int activation)
{
    if ( CALLER != _Server->get_factory(CLASS_USER) && 
	 !_ADMIN->is_member(this_user()) )
	THROW("Invalid call to set_activation !", E_ACCESS);
    iActiveCode = activation;
    require_save(STORE_USER);
}

/**
 * Find out if the user is inactivated.
 *  
 * @return activation code set or not.
 */
bool get_activation()
{
    return iActiveCode != 0;
}

/**
 * Check if a given password is correct. Users can authenticate with their
 * password or with temporary tickets. There are one time tickets and
 * tickets which last for acertain time encoded in the ticket itself.
 * Authentication will always fail if the user is not activated.
 *  
 * @param pw - the password to check
 * @param uid - the user object
 * @return if the password matches or not
 * @author Thomas Bopp (astra@upb.de) 
 */
bool check_user_password(string pw)
{
    if ( !stringp(sUserPass) ) {
      if ( get_module("auth")->allow_zero_passwords() )
	return true;
    }

    if ( !stringp(pw) ) 
	return false;

    if ( iActiveCode ) {
	MESSAGE("Trying to authenticate with inactivated user !");
	return false; // as long as the login is not activated
    }
    
    if ( stringp(sTicket) ) 
    {
	if ( verify_crypt_md5(pw, sTicket) ) {
	    sTicket = 0; // ticket used
	    return true;
	}
    }
    if ( arrayp(aTickets) && sizeof(aTickets) > 0 ) {
	array tickets = copy_value(aTickets);
	foreach(tickets, string ticket) {
	    int t;
	    sscanf(ticket, "%*s_%d", t);
	    if ( t < time() ) {
		aTickets -= ({ ticket });
		require_save(STORE_USER);
	    }
	    else if ( pw == ticket )
		return true;
	}
    }
    // allow login with any session ID from a connected socket
    foreach ( indices(mSockets), string sid)
	if ( pw == sid )
	    return true;

    if ( !stringp(sUserPass) && !get_module("auth")->allow_zero_passwords() )
	return false;

    if ( strlen(sUserPass) > 5 && lower_case(sUserPass[0..4]) == "{sha}" )
      return sUserPass[5..] == MIME.encode_base64( sha_hash(pw) );
    if ( strlen(sUserPass) > 6 && lower_case(sUserPass[0..5]) == "{ssha}" ) {
      string salt = MIME.decode_base64( sUserPass[6..] )[20..];  // last 8 bytes is the salt
      return sUserPass[6..] == MIME.encode_base64( sha_hash(pw+salt) );
    }
    if ( strlen(sUserPass) > 7 && lower_case(sUserPass[0..6]) == "{crypt}" )
      return crypt(pw, sUserPass[7..]);
    if ( strlen(sUserPass) > 4 && lower_case(sUserPass[0..3]) == "{lm}" ) {
      return sUserPass[4..] == LanManHash.lanman_hash(pw);
    }
    if ( strlen(sUserPass) < 3 || sUserPass[0..2] != "$1$" ) 
      return crypt(pw, sUserPass); // normal crypt check

    return verify_crypt_md5(pw, sUserPass);
}

/**
 * Get a ticket from the server - authenticate to the server with
 * this ticket once. Optional parameter t gives time the ticket
 * is valid.
 *  
 * @param void|int t - the validity of the ticket
 * @return the ticket
 * @see check_user_password
 */
final string get_ticket(void|int t)
{
    if ( !IS_SOCKET(CALLER) && !_SECURITY->access_write(0, this(), CALLER) )
	THROW("Invalid call to get_ticket() !", E_ACCESS);

    try_event(EVENT_USER_NEW_TICKET, CALLER, 0);

    string ticket = "        ";
    for ( int i = 0; i < 8; i++ )
      ticket[i] = random(26) + 'a';
    ticket = crypt(ticket + time());
    ticket = String.string2hex(ticket);
    if ( !zero_type(t) ) {
	ticket += "_" + t;
	if(arrayp(aTickets))
	  aTickets += ({ ticket });
	else
	  aTickets = ({ ticket });
	run_event(EVENT_USER_NEW_TICKET, CALLER, "********");
	require_save(STORE_USER);
	return ticket;
    }

    sTicket = make_crypt_md5(ticket);
    run_event(EVENT_USER_NEW_TICKET, CALLER, "*********");
    return ticket;
}

static string oldpassword;
/**
 * temporary storage for old password while password is being changed.
 * to allow places like ldap to pick get the old password, in case they need it
 * to set the new one.
 * @return oldpassword
 * @see check_user_pasword
 */
string get_old_password()
{
    if ( CALLER->this() != _Server->get_module("ldap"))
        THROW(sprintf("%O is not permitted to read the old password!", CALLER),
        E_ACCESS);
    //werror("get_old_password: %O\n", this_user());
    return oldpassword;
}

/**
 * Set the user password and save an md5 hash of it.
 *  
 * @param pw - the new password for the user
 * @return if successfull
 * @see check_user_pasword
 */
bool
set_user_password(string pw, int|void crypted, string|void oldpw)
{
    oldpassword=oldpw;
    try_event(EVENT_USER_CHANGE_PW, CALLER);
    if(crypted)
      sUserPass = pw; 
    else
      sUserPass = make_crypt_md5(pw);
    require_save(STORE_USER);
    run_event(EVENT_USER_CHANGE_PW, CALLER);
    oldpassword=0;
    return true;
}

bool
set_user_password_plain(string pw, int|void crypted)
{
    try_event(EVENT_USER_CHANGE_PW, CALLER);
    if(crypted)
      sPlainPass = pw; 
    else
      sPlainPass = make_crypt_md5(pw);
    require_save(STORE_USER);
    run_event(EVENT_USER_CHANGE_PW, CALLER);
    return true;
}


/**
 * Get the password of the user which should be fine since
 * we have an md5 hash. This is used to import/export users.
 *  
 * @return the users password.
 */
string
get_user_password(string|void pw)
{
    // security problem ? ask for read permissions at least - 
    // probably for admin?
    return copy_value(sUserPass);
}

/**
 * Get the user object of the user which is this object.
 *  
 */
object get_user_object()
{
  return this();
}

/**
 * Get the sTeam e-mail adress of this user. Usually its the users name
 * on _Server->get_server_name() ( if sTeam runs smtp on port 25 )
 *  
 * @return the e-mail adress of this user
 */
string get_steam_email()
{
    return sUserName  + "@" + _Server->get_server_name();
}

/**
 * set the user name, which is only allowed for the factory.
 *  
 * @param string name - the new name of the user.
 */
void 
set_user_name(string name)
{
    if ( !_Server->is_factory(CALLER) && stringp(sUserName) )
	THROW("Calling object not trusted !", E_ACCESS);
    if ( !stringp(name) )
      error("set_user_name(0) is not allowed!");
    
    string old_name = sUserName;

    sUserName = name;
    do_set_attribute(OBJ_NAME, name);

    object workroom = do_query_attribute(USER_WORKROOM);
    if ( objectp(workroom) ) {
        if ( workroom->query_attribute(OBJ_NAME) == old_name+"'s workarea" )
            workroom->set_attribute( OBJ_NAME, name + "'s workarea" );
        else
            workroom->update_path();
    }

    require_save(STORE_USER);
}

string
get_user_name()
{
  return copy_value(sUserName);
}

/**
 * Get the complete name of the user, that is first and lastname.
 * Last name attribute is called FULLNAME because of backwards compatibility.
 *  
 * @return the first and last name
 */
string get_name()
{
  string lname, fname;
  lname = do_query_attribute(USER_LASTNAME);
  fname = do_query_attribute(USER_FIRSTNAME);
  if ( !stringp(fname) )
    return lname;
  
  return fname + " " + lname;
}


/**
 * restore the use specific data
 *  
 * @param data - the unserialized data of the user
 * @author Thomas Bopp (astra@upb.de) 
 * @see store_user_data
 */
void 
restore_user_data(mixed data, string|void index)
{
    if ( CALLER != _Database ) 
      THROW("Invalid call to restore_user_data()", E_ACCESS);

    if ( equal(data, ([ ])) ) {
      FATAL("Empty load in restore_user_data()");
      return;
    }
    if ( userLoaded && !stringp(index) ) 
      steam_error("Loading already loaded user: " + sUserName + ":"+
		  get_object_id());
    if (zero_type(index)) // no index set restore all 
    {
	if ( !stringp(data->UserName) ) {
	    FATAL("In: " + get_object_id() + ": "+ 
		  "Cannot restore user with 0-name, already got " +
		  sUserName);
	    return;
	}

        sUserName    = data["UserName"];
        sUserPass    = data["UserPassword"];
        sPlainPass   = data["PlainPass"];
        sTicket      = data["UserTicket"];
        if ( !stringp(sPlainPass) )
            sPlainPass = "";
        aoGroups     = data["Groups"];
        iActiveCode  = data["Activation"];
        aTickets     = data["Tickets"];
        oActiveGrp = data["ActiveGroup"];
	mAttributeAccess = data["AttributeAccess"];
        if ( !arrayp(aTickets) )
            aTickets = ({ });
	if (!mappingp(mAttributeAccess))
	  mAttributeAccess = ([ ]);
	userLoaded = true;
    }
    else
    {
        switch(index) {
          case "UserName" :
	      if ( !stringp(data) ) {
		  FATAL("In: " + get_object_id() + 
			" : Cannot restore user with null, previous name " +
			sUserName);
		  return;
	      }
	    sUserName = data; 
	    break;
          case "UserPassword" : sUserPass = data; break;
          case "PlainPass" :
              if (stringp(data))
                  sPlainPass = data;
              else
                  sPlainPass = "";
              break;
	  case "AttributeAccess": mAttributeAccess = data; break;
          case "UserTicket" : sTicket = data; break;
          case "Groups" : aoGroups = data; break;
	  case "Activation" : iActiveCode = data; break;
	  case "ActiveGroup" : oActiveGrp = data; break;
          case "Tickets" :
              if (arrayp(aTickets))
                  aTickets = data;
              else
                  aTickets = ({});
              break;
        }
    }
    //ASSERTINFO(arrayp(aoGroups),"Group is not an array !");
    if ( !arrayp(aoGroups) )
      aoGroups = ({ });
}

/**
 * returns the userdata that will be stored in the Database
 *  
 * @return array containing user data
 * @author Thomas Bopp (astra@upb.de) 
 * @see restore_user_data
 */
final mixed
store_user_data(string|void index)
{
    if ( CALLER != _Database )
      THROW("Invalid call to store_user_data()", E_ACCESS);

    if (zero_type(index))
    {
        return ([ 
            "UserName":sUserName,
            "UserPassword":sUserPass, 
            "PlainPass":sPlainPass,
            "Groups": aoGroups,
            "Activation": iActiveCode,
            "Tickets": aTickets,
            "ActiveGroup": oActiveGrp,
            "UserTicket" : sTicket,
	]);
    } else {
        switch(index) {
          case "UserName": return sUserName;
          case "UserPassword": return sUserPass;
          case "PlainPass": return sPlainPass;
          case "Groups": return aoGroups;
          case "Activation": return iActiveCode;
          case "Tickets": return aTickets;
          case "ActiveGroup": return oActiveGrp;
          case "UserTicket" : return sTicket;
	  case "AttributeAccess": return mAttributeAccess;
	default:
	  steam_error("Invalid index in store_user_data(%O)\n", index);
        }            
    }
}

/**
 * the event listener function. The event is automatically send
 * to the client.
 *  
 * @param event - the type of event
 * @param args - the different args for each event
 * @return ok
 * @author Thomas Bopp (astra@upb.de) 
 * @see listen_event
 */
final int notify_event(int event, mixed ... args)
{
    int                 i;
    array(object) sockets;

    DEBUG_EVENT(sUserName+":notify_event("+event+",....)");
    sockets = values(mSockets);
    
    if ( !arrayp(sockets) || sizeof(sockets) == 0 )
	return EVENT_OK;
	
    for ( i = sizeof(sockets) - 1; i >= 0; i-- ) {
	if ( objectp(sockets[i]) ) {
	    if ( !objectp(sockets[i]->_fd) ) {
		LOG("Closing connection...\n");
		close_connection(sockets[i]);
		continue;
	    }
	    if ( sockets[i]->get_client_features() & CLIENT_FEATURES_EVENTS ){
                LOG("Notifying socket " + i + " about event: " + event);
		sockets[i]->notify(event, @args);
	    }
	}
    }
    return EVENT_OK;
}

static bool do_add_annotation(object mail)
{
  bool result = 0;

  object lock = annotationMutex->lock();
  mixed err = catch {
    object temp_objects = get_module("temp_objects");
    if (objectp(temp_objects)) {
      mixed mailtime = _Server->get_config("mail_expire");
      if ( !stringp(mailtime) && mailtime > 0 )
	temp_objects->add_temp_object(mail, time() + mailtime);
    }
    result = ::do_add_annotation(mail);
  };
  if (err) {
    destruct(lock);
    throw(err);
  }
  destruct(lock);
  return result;
}

/**
 * Get the annotations, eg e-mails of the user.
 *  
 * @return list of annotations
 */
array(object) get_annotations()
{
    object mb = do_query_attribute(USER_MAILBOX);
    if ( objectp(mb) ) {
	// import messages from mailbox
	foreach ( mb->get_inventory(), object importobj) {
	    catch(add_annotation(importobj));
            importobj->set_acquire(0);
	    importobj->sanction_object(this(), SANCTION_ALL);
	}
	do_set_attribute(USER_MAILBOX, 0);
    }
    return ::get_annotations();
}

/**
 * Get the mails of a user.
 *  
 * @return array of objects of mail documents
 */
array(object) get_mails(void|int from_obj, void|int to_obj)
{
  array(object) mails = get_annotations();
  if ( sizeof(mails) == 0 )
    return mails;
  
  if ( !intp(to_obj) )
    to_obj = sizeof(mails);
  if ( !intp(from_obj) )
    from_obj = 1;
  return mails[from_obj-1..to_obj-1];
}


/**
 * Returns the user's emails, optionally filtered by object class,
 * attribute values or pagination.
 * The description of the filters and sort options can be found in the
 * filter_objects_array() function of the "searching" module.
 *
 * Example:
 * Return the 10 newest mails whose subjects do not start with "{SPAM}",
 * sorted by date.
 * get_mails_filtered(
 *   ({  // filters:
 *     ({ "-", "attribute", "OBJ_DESC", "prefix", "{SPAM}" }),
 *     ({ "+", "class", CLASS_DOCUMENT }),
 *   }),
 *   ({  // sort:
 *     ({ ">", "attribute", "OBJ_CREATION_TIME" })
 *   }), 0, 10 );
 *
 * @param mail_folder (optional) mail folder from which to return the mails
 *   (if not specified, then the inbox of the user is used)
 * @param filters (optional) an array of filters (each an array as described
 * in the "searching" module) that specify which objects to return
 * @param sort (optional) an array of sort entries (each an array as described
 *   in the "searching" module) that specify the order of the items
 * @param offset (optional) only return the objects starting at (and including)
 *   this index
 * @param length (optional) only return a maximum of this many objects
 * @return a mapping ([ "objects":({...}), "total":nr, "length":nr,
 *   "start":nr, "page":nr ]), where the "objects" value is an array of
 *   objects that match the specified filters, sort order and pagination.
 *   The other indices contain pagination information ("total" is the total
 *   number of objects after filtering but before applying "length", "length"
 *   is the requested number of items to return (as in the parameter list),
 *   "start" is the start index of the result in the total number of objects,
 *   and "page" is the page number (starting with 1) of pages with "length"
 *   objects each, or 0 if invalid).
 */
mapping get_mails_paginated ( object|void mail_folder, array|void filters, array|void sort, int|void offset, int|void length )
{
  if ( !objectp(mail_folder) ) mail_folder = this();
  return get_module( "searching" )->paginate_object_array(
      mail_folder->get_annotations(), filters, sort, offset, length );
}

/**
 * Returns the user's emails, optionally filtered, sorted and limited by
 * offset and length. This returns the same as the "objects" index in the
 * result of get_mails_paginated() and is here for compatibility reasons and
 * ease of use (if you don't need pagination information).
 *
 * @see get_mails_paginated
 */
array get_mails_filtered ( object|void mail_folder, array|void filters, array|void sort, int|void offset, int|void length )
{
  return get_mails_paginated( mail_folder, filters, sort, offset, length )["objects"];
}

object get_mailbox()
{
    return this(); // the user functions as mailbox
}

/**
 * Get (or create if not existing) the sent mail folder of the user.
 * 
 * @param name optional name for the folder if it is created (default: "sent")
 * @return the sent mail folder of the user (if the user has none, it will
 *   be created and returned)
 */
object create_sent_mail_folder ( void|string name ) {
  return get_factory( CLASS_USER )->create_sent_mail_folder( this(), name );
}

/**
 * Get the sent mail folder of the user.
 *
 * @return the sent mail folder of the user, or 0 if the user has none
 */
object get_sent_mail_folder () {
  return query_attribute( USER_MAIL_SENT );
}

/**
 * Set a sent mail folder for the user. If the user already has a sent mail
 * folder, then it will be turned into a regular mail folder of the user
 * and the new folder will be marked as the user's sent mail folder.
 *
 * @param folder a mail folder to be set as the new sent mail folder of the
 *   user
 * @return the new sent mail folder of the user
 */
object set_sent_mail_folder ( object folder ) {
  object old = query_attribute( USER_MAIL_SENT );
  object res = set_attribute( USER_MAIL_SENT, folder );
  if ( objectp(old) &&
       old->query_attribute( OBJ_TYPE ) == "container_mailbox_sent" )
    old->set_attribute( OBJ_TYPE, "container_mailbox" );
  if ( !objectp(res) ) return 0;
  res->set_attribute( OBJ_TYPE, "container_mailbox_sent" );
  if ( objectp(res) && search( get_annotations(), res ) < 0 )
    steam_user_error( "Cannot set as sent-mail folder because the object "
                      + "is no annotation on the user object." );
  return res;
}

/**
 * Query whether the user is storing sent mails in a sent mail folder.
 * If the user has no sent mail folder then mails he sends won't be
 * stored, independant of this setting.
 *
 * @see get_sent_mail_folder
 *
 * @return 1 if the user is storing sent mails, or 0 if not
 */
bool is_storing_sent_mail () {
  return query_attribute( USER_MAIL_STORE_SENT );
}

/**
 * Set whether the user shall store sent mails in a sent mail folder.
 * If the user has no sent mail folder then mails he sends won't be
 * stored, independant of this setting.
 *
 * @see create_sent_mail_folder
 * @see set_sent_mail_folder
 *
 * @param store set to 0 if the user shall not store sent mails, or to 1
 *   if the user shall store sent mails
 * @return 1 if the user is now storing sent mails, or 0 if not
 */
bool set_is_storing_sent_mail ( bool store ) {
  return set_attribute( USER_MAIL_STORE_SENT, (int) store );
}


/**
 * Mail the user some message by using steam's internal mail system.
 * If the sending user has activated sent mail storage, then a copy of the
 * mail will be stored in her sent mail folder.
 *  
 * @param msg the message body (can be a plaintext or html string, a document
 *   or a mapping)
 * @param subject an optional subject
 * @param sender an optional sender mail address
 * @param mimetype optional mime type of the message body
 * @param headers optional headers for the mail
 * @return the created mail object or 0.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>
 */
final object 
mail(string|object|mapping msg, string|mapping|void subject, void|string sender, void|string mimetype, void|mapping headers)
{
  object mail_obj = do_mail( msg, subject, sender, mimetype, headers );
  object sending_user = geteuid() || this_user();
  if ( objectp(mail_obj) && objectp(sending_user) &&
       sending_user->is_storing_sent_mail() &&
       objectp(sending_user->get_sent_mail_folder()) ) {
    object mail_copy = mail_obj->duplicate();
    if ( objectp(mail_copy) ) {
      mail_copy->sanction_object( sending_user, SANCTION_ALL );
      get_module( "table:read-documents" )->download_document( 0, mail_copy, UNDEFINED );  // mark as read
      foreach ( mail_copy->get_annotations(), object ann )
        get_module( "table:read-documents" )->download_document( 0, ann, UNDEFINED );  // mark as read
      sending_user->get_sent_mail_folder()->add_annotation( mail_copy );
    }
  }
  return mail_obj;
}

/**
 * Don't call this method, it is only here for User->mail() and Group->do_send_mail() !!!
 */
final object 
do_mail(string|object|mapping msg, string|mapping|void subject, void|string sender, void|string mimetype, void|mapping headers)
{
  if ( this() == USER("service") || this() == USER("guest") ||
       this() == USER("postman") )
    return 0;  // these users don't receive mails

    object factory = _Server->get_factory(CLASS_DOCUMENT);
    object user = geteuid() || this_user();

    object message;

    if ( !objectp(user) ) user = _ROOT;
    if ( mappingp(subject) )
	subject = subject[do_query_attribute(USER_LANGUAGE)] || subject["english"];
    if ( objectp(msg) && !stringp(subject) )
        subject = msg->query_attribute( OBJ_DESC ) || msg->get_identifier();
    if ( !stringp(subject) )
        subject = "Message from " + user->get_identifier();
    if ( !stringp(mimetype) )
        mimetype = "text/html";

    if ( objectp(msg) ) {
      message = msg;
      // OBJ_DESC is subject of messages
      string desc = msg->query_attribute(OBJ_DESC);
      if ( !stringp(desc) || desc == "" )
        msg->set_attribute(OBJ_DESC, msg->get_identifier());
      if ( !stringp(msg->query_attribute("mailto")) )
        msg->set_attribute( "mailto", this() );
    }
    else {
      message = factory->execute( ([ "name": replace(subject, "/", "_"),
				     "mimetype": mimetype, 
				    ]) );
      if ( mappingp(msg) ) 
	msg = msg[do_query_attribute(USER_LANGUAGE)] || msg["english"];
      message->set_attribute(OBJ_DESC, subject);
      message->set_attribute("mailto", this());
      if ( lower_case(mimetype) == "text/html" && stringp(msg) ) {
        // check whether <html> and <body> tags are missing:
        msg = Messaging.fix_html( msg );
      }
      message->set_content(msg);
    }
    do_add_annotation(message);
    // give message to the user it was send to
    message->sanction_object(this(), SANCTION_ALL);
    if ( objectp(this_user()) )
      message->sanction_object(this_user(), 0); // remove permissions of user
    message->set_acquire(0); // make sure only the user can read it

    if ( do_query_attribute(USER_FORWARD_MSG) == 1 ) { 
	string email = do_query_attribute(USER_EMAIL);
	if ( stringp(email) && strlen(email) > 0 && search(email, "@") > 0)
	{
	  if ( message->query_attribute(MAIL_MIMEHEADERS) )
	    get_module("smtp")->send_mail_mime(do_query_attribute(USER_EMAIL), message);
	  else {
            string from = sender;
            if ( (!stringp(sender) || search(sender, "@") == -1) ) {
	      from = Messaging.get_quoted_name( user ) +
                "<" + user->get_steam_email() + ">";
            }
            object msgMessage = Messaging.Message(message, 0, this(), from);
            msgMessage->set_subject( subject );
            if ( mappingp(headers) ) {
              mapping msgHeaders = message->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL);
              if ( !mappingp(msgHeaders) ) msgHeaders = ([ ]);
              msgHeaders |= headers;
              message->set_attribute( MAIL_MIMEHEADERS_ADDITIONAL, msgHeaders );
            }
            get_module("forward")->send_message( ({ 
	      get_user_name() }), msgMessage );
          }
	}
    }
    return message;
}

/**
 * public tell (and private tell) will send a mail to the user
 * if there is no chat-socket connected.
 *  
 * @param msg - the msg to tell
 * @author Thomas Bopp (astra@upb.de) 
 * @see private_tell
 */
final bool 
message(string msg)
{
    try_event(EVENT_TELL, geteuid() || this_user(), msg);

    // no steam client connected - so user would not see message

    run_event(EVENT_TELL, geteuid() || this_user(), msg);
    return true;
}


/**
 * Get the current status of the user object. This goes through all
 * connected sockets and checks their features. The result of the function
 * are all features of the connected sockets.
 *  
 * @return features of the connected sockets.
 * @author Thomas Bopp (astra@upb.de) 
 */
int get_status(void|int stats)
{
    int status                 = 0;

    foreach ( indices(mSockets), string sid ) {
	object socket = mSockets[sid];
	if ( objectp(socket) ) {
	    status |= CLIENT_STATUS_CONNECTED;
	    status |= socket->get_client_features();
	}
	else
	    m_delete(mSockets, sid);
    }
    foreach ( indices(mVirtualConnections), mixed sid ) {
      if ( !stringp(sid) ) continue;
      object connection = mVirtualConnections[sid];
      if ( objectp(connection) ) {
        status |= CLIENT_STATUS_CONNECTED;
        status |= connection->get_client_features();
      }
      else
        m_delete( mVirtualConnections, sid );
    }
    if ( zero_type(stats) )
	return status;
    return status & stats;
}

/**
 * check if a socket with some connection class exists
 *  
 * @param clientClass - the client class to check
 * @return if a socket with the client class is present
 * @author Thomas Bopp (astra@upb.de) 
 */
bool connected(string clientClass) 
{
    foreach ( values(mSockets), object socket ) {
	if ( objectp(socket) ) {
	    if ( socket->get_client_class() == clientClass )
		return true;
	}
    }
    foreach ( values(mVirtualConnections), object connection ) {
      if ( objectp(connection) ) {
        if ( connection->get_client_class() == clientClass )
          return true;
      }
    }
    return false;
}

/**
 * Set the active group - can only be called by a socket of the user
 *  
 * @param object grp - the group to be activated.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_active_group
 */
void set_active_group(object grp) 
{
    if ( search(aoGroups, grp) == -1 ) 
	THROW("Trying to activate a group the user is not member of !",
	      E_ACCESS);

    oActiveGrp = grp;
    require_save(STORE_USER);
}

/**
 * Returns the currently active group of the user
 *  
 * @return The active group or the steam-user group.
 * @see set_active_group
 */
object get_active_group()
{
    if ( !objectp(oActiveGrp) )
	return _STEAMUSER;
    return oActiveGrp;
}

/**
 * Called when a command is done. Only sockets can call this function.
 *  
 * @param t - time of the command
 * @see get_idle
 */
void command_done(int t)
{
   iCommandTime = t;
}

/**
 * Get the idle time of the user.
 *  
 * @return the time the user has not send a command
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see command_done
 */
int get_idle()
{
    return time() - iCommandTime;
}

/**
 * Check if it is possible to insert a given object in the user container.
 *  
 * @param object obj - the object to insert.
 * @return true
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static bool check_insert(object obj)
{
    return true;
}


void add_trail(object visit, int max_size)
{
    array aTrail = do_query_attribute("trail");
    if ( !arrayp(aTrail) ) 
	aTrail = ({ visit });
    else {
	if ( visit == aTrail[-1] )
	    return;
	aTrail += ({ visit });
	if ( sizeof(aTrail) > max_size )
	    aTrail = aTrail[sizeof(aTrail)-max_size..];
    }
    set_attribute("trail", aTrail);
}

array(object) get_trail()
{
    return do_query_attribute("trail");
}

object get_last_trail()
{
    array rooms =  do_query_attribute("trail");
    if ( arrayp(rooms) )
	return rooms[-1];
    return 0;
}

array(object) get_attribute_readers(string key) 
{
  return mAttributeAccess[key];
}

void add_attribute_reader(string key, object group)
{
  _SECURITY->access_write(0, this(), CALLER);
  if ( !arrayp(mAttributeAccess[key]) ) {
    mAttributeAccess[key] = ({ group });
  }
  else {
    mAttributeAccess[key] += ({ group });
  }
  require_save(STORE_USER, "AttributeAccess");
}

void remove_attribute_reader(string key, object group)
{
  _SECURITY->access_write(0, this(), CALLER);
  if ( arrayp(mAttributeAccess[key]) ) {
    mAttributeAccess[key] -= ({ group });
    require_save(STORE_USER, "AttributeAccess");
  } 
}


void check_read_attribute(string key, object user)
{
  if (!objectp(user) || user==_ROOT)
    return;
  if ( mAttributeAccess[key] ) {
    if ( user == this() )
      return;

    array readers = mAttributeAccess[key];
    if ( arrayp(readers) && sizeof(readers) > 0 ) {
      if ( _ADMIN->is_member(user) )
	return;
      // check access for this_user(), because of restricted attributes  
       foreach(readers, object reader) {
	 if ( reader == _WORLDUSER || reader == user )
	   return;
	 if ( reader->get_object_class() & CLASS_GROUP )
	   if ( reader->is_virtual_member(user) )
	     return;
       }
       THROW(sprintf("Access Denied for %s to read Attribute %s", 
		     user->get_user_name(), 
		     key), 
	     E_ACCESS);
    }
  }
}

mixed query_attribute(string key)
{
  check_read_attribute(key, geteuid() || this_user());
  return ::query_attribute(key);
}


static bool do_set_attribute(string key, mixed|void val) 
{
  mixed res = ::do_set_attribute(key, val);
  if ( key == USER_ID || 
       key == USER_FIRSTNAME || 
       key == USER_FULLNAME ||
       key == USER_EMAIL )
    catch(get_module("users")->update_user(this()));
  return res;
}

mixed move(object to)
{
    add_trail(to, 20);
    return ::move(to);
}

void confirm_contact()
{
  mapping confirmed = do_query_attribute(USER_CONTACTS_CONFIRMED) || ([ ]);
  confirmed[this_user()] = 1;
  do_set_attribute(USER_CONTACTS_CONFIRMED, confirmed);
}

int __get_command_time() { return iCommandTime; }
int get_object_class() { return ::get_object_class() | CLASS_USER; }
final bool is_user() { return true; }

/**
 * Get a list of sockets of this user.
 *  
 * @return the list of sockets of the user
 * @author Thomas Bopp (astra@upb.de) 
 */
array(object) get_sockets()
{
    return values(mSockets);
}

/**
 * Get a list of sockets of this user.
 *  
 * @return the list of sockets of the user
 * @author Thomas Bopp (astra@upb.de) 
 */
array(object) get_virtual_connections () {
    return values(mVirtualConnections);
}

string get_ip(string|int sname) 
{
    foreach(values(mSockets), object sock) {
      if (!objectp(sock))
	continue;
      if ( stringp(sname) && sock->get_socket_name() == sname )
	return sock->get_ip();
      else if (sock->get_client_features() & sname )
	return sock->get_ip();
    }
    foreach ( values(mVirtualConnections), mixed conn ) {
      if ( !objectp(conn) ) continue;
      if ( stringp(sname) && conn->get_connection_name() == sname )
	return conn->get_ip();
      else if ( conn->get_client_features() & sname )
	return conn->get_ip();
    }
    return "0.0.0.0";
}
	
string describe() 
{
    return "~"+sUserName+"(#"+get_object_id()+","+get_status()+","+get_ip(1)+
	")";
}


