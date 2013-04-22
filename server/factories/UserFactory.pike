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
 * $Id: UserFactory.pike,v 1.3 2010/02/09 19:33:24 astra Exp $
 */

constant cvs_version="$Id: UserFactory.pike,v 1.3 2010/02/09 19:33:24 astra Exp $";

inherit "/factories/ContainerFactory";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <roles.h>
#include <assert.h>
#include <events.h>
#include <attributes.h>
#include <types.h>
#include <access.h>

static int iActivation = 0;

private static array test_objects = ({ });

/**
 * Initialize the factory with its default attributes.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void init_factory()
{
    ::init_factory();
    init_class_attribute(USER_ADRESS, CMD_TYPE_STRING, "user adress",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_USER, "");
    init_class_attribute(USER_MODE,  CMD_TYPE_INT, "user mode", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_CLIENT, 0);
    init_class_attribute(USER_UMASK,  CMD_TYPE_MAPPING, "user umask", 
			 EVENT_ATTRIBUTES_QUERY, EVENT_ATTRIBUTES_CHANGE,0,
			 CONTROL_ATTR_USER, ([ ]));
    init_class_attribute(USER_MODE_MSG, CMD_TYPE_STRING, 
			 "user mode message", 0, 
			 EVENT_ATTRIBUTES_CHANGE, 0,CONTROL_ATTR_USER,"");
    init_class_attribute(USER_EMAIL, CMD_TYPE_STRING, "email", 
			 0, EVENT_ATTRIBUTES_CHANGE,0,
			 CONTROL_ATTR_USER, "");
    init_class_attribute(USER_FULLNAME, CMD_TYPE_STRING, "user fullname",0,
			 EVENT_ATTRIBUTES_CHANGE, 0,CONTROL_ATTR_USER, "");
    init_class_attribute(USER_WORKROOM, CMD_TYPE_OBJECT, "workroom", 0, 
			 EVENT_ATTRIBUTES_CHANGE, 0,CONTROL_ATTR_USER, 0);
    init_class_attribute(USER_LOGOUT_PLACE, CMD_TYPE_OBJECT, "logout-env",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_USER, 0);
    init_class_attribute(USER_LAST_LOGIN, CMD_TYPE_TIME, "last-login", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, 0);
    init_class_attribute(USER_BOOKMARKROOM, CMD_TYPE_OBJECT, "bookmark room",0,
			 EVENT_ATTRIBUTES_CHANGE, 0,CONTROL_ATTR_USER, 0);
    init_class_attribute(USER_FORWARD_MSG, CMD_TYPE_INT, "forward message", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_USER, 1);
    init_class_attribute(USER_FAVOURITES, CMD_TYPE_ARRAY, "favourites list", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_USER, ({ }) );
    init_class_attribute(USER_CALENDAR, CMD_TYPE_OBJECT, "calendar", 0,
                         EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_SERVER,0);
    init_class_attribute(USER_MONITOR, CMD_TYPE_OBJECT, "monitor", 0,
			 EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_SERVER,0);
    init_class_attribute(USER_ID, CMD_TYPE_STRING, "user id",
			 EVENT_ATTRIBUTES_QUERY,
			 EVENT_ATTRIBUTES_CHANGE, 
			 0,CONTROL_ATTR_USER, "");
}

/**
 * Create a new user object with the following vars:
 * name     - the users name (nickname is possible too).
 * email    - the users email adress.
 * pw       - the users initial password.
 * fullname - the full name of the user.
 * firstname - the last name of the user.
 *  
 * @param mapping vars - variables for execution.
 * @return the objectp of the new user if successfully, or 0 (no access or user
 *         exists)
 * @author Thomas Bopp (astra@upb.de) 
 */
object execute(mapping vars)
{
   string name;
   object  obj;

   try_event(EVENT_EXECUTE, CALLER, obj);

   if ( stringp(vars["nickname"]) )
     name = string_to_utf8(lower_case(utf8_to_string(vars["nickname"])));
   else
     name = vars["name"];
   
   obj = MODULE_USERS->lookup(name);
   if ( objectp(obj) ) 
       steam_error("user_create(): User does already exist.");
   obj = MODULE_GROUPS->lookup(name);
   if ( objectp(obj) ) 
       steam_error("user_create(): Group with this name already exist.");

   mixed err = catch {
       object ouid = seteuid(USER("root"));
       obj = user_create(vars);
       seteuid(ouid);
   };
   if ( err ) {
       FATAL("Error in UserFactory: %O\n%O", err[0], err[1]);
       // try to find the user and remove
       obj = MODULE_USERS->lookup(name);
       if ( objectp(obj) ) {
	 obj->delete();
       }
       throw(err);
   }
   run_event(EVENT_EXECUTE, CALLER, obj);
   return obj;
}

private static object user_create(mapping vars)
{
    object  obj;

    try_event(EVENT_EXECUTE, CALLER, obj);

    string name;
    if ( stringp(vars["nickname"]) )
	name = lower_case(vars["nickname"]);
    else
	name = vars["name"];

    if ( search(name, " ") >= 0 )
	steam_error("Whitespaces in Usernames are not allowed");

    string pw = vars["pw"];
    string email = vars["email"];

    if ( stringp(vars->fullname) && !xml.utf8_check(vars->fullname) )
      steam_error("Failed utf8-check for firstname or fullname !");
    
    if ( stringp(vars->firstname) && !xml.utf8_check(vars->firstname) )
      steam_error("Failed utf8-check for firstname or fullname !");

    obj = object_create(name, CLASS_NAME_USER, 0, vars["attributes"],
	    	vars["attributesAcquired"], vars["attributesLocked"]); 

    function obj_set_attribute = obj->get_function("do_set_attribute");
    function obj_lock_attribute = obj->get_function("do_lock_attribute");
    function obj_sanction = obj->get_function("do_sanction_object");

    obj_lock_attribute(OBJ_NAME);
    if ( !objectp(obj) ) {
	SECURITY_LOG("Creation of user " + name + " failed...");
	return null; // creation failed...
    }

    string language;
    if (stringp(vars["language"]))
       language=vars["language"];

    if ( stringp(vars["pw:crypt"]) )
      obj->set_user_password(vars["pw:crypt"],1);
    else
      obj->set_user_password(pw);
    obj->set_user_name(name);
    obj_set_attribute(USER_EMAIL, email);
    obj_set_attribute(USER_FULLNAME, vars["fullname"]);
    obj_set_attribute(USER_FIRSTNAME, vars["firstname"]);

    if (stringp(language)) 
      obj_set_attribute(USER_LANGUAGE, language);
    obj->set_creator(_ROOT);
    obj->set_acquire(0);
    if ( objectp(this_user()) && this_user() != _GUEST )
      obj_sanction(this_user(), SANCTION_ALL);

    if ( stringp(vars["description"]) )
      obj_set_attribute(OBJ_DESC, vars["description"]);
    if ( stringp(vars["contact"]) )
      obj_set_attribute(USER_ADRESS, vars["contact"]);

    // create sent-mail folder and activate storage of sent-mails:
    if ( name != "guest" ) {
      object old_euid = geteuid();
      seteuid( obj );
      catch {
        obj->create_sent_mail_folder();
        obj->set_is_storing_sent_mail( 1 );
      };
      seteuid( old_euid );
    }
    
    object workroom, factory, calendar;

    factory = _Server->get_factory(CLASS_ROOM);
    
    mapping workroomAttributes = ([ 
      OBJ_OWNER: obj->this(),
      OBJ_DESC: name + "s workroom", ]);
    
    workroom = factory->execute( ([ 
      "name":name+"'s workarea", 
      "attributes": workroomAttributes, 
      "sanction": ([ obj->this(): SANCTION_ALL, _GUEST:0, ]),
      "sanctionMeta": ([ obj->this(): SANCTION_ALL, ]),
    ]));

    obj->move(workroom);
    obj_set_attribute(USER_WORKROOM, workroom);
    obj_lock_attribute(USER_WORKROOM);

    workroom->set_creator(obj->this());

    object bookmarkroom = factory->execute(([
      "name":name+"'s bookmarks",
      "sanction": ([ obj->this(): SANCTION_ALL, ]),
      "sanctionMeta": ([ obj->this(): SANCTION_ALL, ]),
    ]));
    obj_set_attribute(USER_BOOKMARKROOM, bookmarkroom);
    obj_lock_attribute(USER_BOOKMARKROOM);

    bookmarkroom->set_creator(obj->this());

    factory = _Server->get_factory(CLASS_TRASHBIN);
    mapping trashbinAttributes = ([ OBJ_DESC: "Trashbin", ]);
    object trashbin = factory->execute( ([
      "name":"trashbin", "attributes":trashbinAttributes,
      "sanction": ([ obj->this(): SANCTION_ALL, _STEAMUSER:SANCTION_INSERT, ]),
      "sanctionMeta": ([ obj->this(): SANCTION_ALL, ]),
    ]));
    trashbin->move(workroom->this());
    trashbin->set_creator(obj->this());
    trashbin->set_acquire(0); 
     
    obj_set_attribute(USER_TRASHBIN, trashbin);

    mapping calendarAttributes = ([ CALENDAR_OWNER: obj->this() ]);
    calendar = _Server->get_factory(CLASS_CALENDAR)->execute( ([
      "name":name+"'s calendar", "attributes":calendarAttributes,
      "attributesLocked": ([ CALENDAR_OWNER: 1, ]),
      "sanction": ([ obj->this(): SANCTION_ALL, ]),
      "sanctionMeta": ([ obj->this(): SANCTION_ALL, ]),
    ]) );
    obj_set_attribute(USER_CALENDAR, calendar);
    obj_lock_attribute(USER_CALENDAR);
    calendar->set_creator(obj->this());

    // steam users can annotate and read the users attributes.
    obj_sanction(_STEAMUSER, SANCTION_READ|SANCTION_ANNOTATE);
    
    object forwards = get_module("forward");
    if ( objectp(forwards) ) {
	string mname = forwards->get_mask_char() + obj->get_user_name();
	forwards->add_forward(obj->this(), mname);
        if ( stringp(email) && sizeof(email) > 0 ) {
          mixed forwardErr = catch(forwards->add_forward(obj->this(), email));
	  if (forwardErr) {
	    FATAL("Failed to set forward to e-mail %O when creating user %O",
		  email, obj);
	  }
	}
    }

    if ( name != "guest" ) {
      _STEAMUSER->add_member(obj->this());
    }
    

    if ( !_Persistence->get_dont_create_exits() ) {
      array(object) inv = workroom->get_inventory_by_class(CLASS_EXIT);
      if ( sizeof(inv) == 0 ) {
        factory = _Server->get_factory(CLASS_EXIT);
        object swa = _STEAMUSER->query_attribute(GROUP_WORKROOM);
        string exitname = "steam";
        if ( objectp(swa) )
          exitname = swa->get_identifier();

        if ( strlen(exitname) == 0 )
          exitname = "steam";
          
        object exit = factory->execute(([ "name": exitname, "exit_to": swa,]));
        exit->set_creator(obj->this());
        exit->move(workroom);
      }
    }
	
    run_event(EVENT_EXECUTE, CALLER, obj);
    
    // now remove all guest privileges on this object
    if ( objectp(_GUEST) ) {
	obj_sanction(_GUEST, 0);
    }
    iActivation = time() + random(100000);
    obj->set_activation(iActivation);

    return obj->this();
}

/**
 * Queries and resets the activation code for an user. Thus
 * it is required, that the creating object immidiately calls
 * this function and sends the activation code to the user.
 *  
 * @return activation code for the last created user
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int get_activation()
{
    int res = iActivation;
    iActivation = 0;
    return res;
}

object create_sent_mail_folder ( object user, void|string name )
{
  _SECURITY->check_access(user, CALLER, SANCTION_READ, ROLE_READ_ALL, false);

  if ( user == _GUEST ) return UNDEFINED;
  object sent_mail = user->query_attribute( USER_MAIL_SENT );
  if ( objectp(sent_mail) ) return sent_mail;
  if ( !stringp(name) ) name = "sent";

  _SECURITY->check_access(user, CALLER, SANCTION_WRITE, ROLE_WRITE_ALL, false);

  catch {
    sent_mail = get_factory( CLASS_CONTAINER )->execute(
        ([ "name" : name, "attributes" : ([ OBJ_OWNER : user ]),
           "sanction" : ([ user : SANCTION_ALL, _GUEST:0 ]) ]) );
    if ( !objectp(sent_mail) )
      return UNDEFINED;
    sent_mail->set_creator( user );
    user->add_annotation( sent_mail );
    return user->set_sent_mail_folder( sent_mail );
  };
  return UNDEFINED;
}

string rename_user(object user, string new_name)
{
  _SECURITY->check_access(user,CALLER,SANCTION_WRITE,ROLE_WRITE_ALL,false);

  _Persistence->uncache_object( user );

  object users = get_module("users");
  
  if ( users->lookup(user->get_user_name()) != user )
    user->set_user_name(new_name);
  
  _Persistence->uncache_object( user );

  // unmount user from home module:
  int is_mounted = get_module( "home" )->is_mounted( user );
  if ( is_mounted ) get_module( "home" )->unmount( user );
  
  if ( users->rename_user(user, new_name) == new_name )
    user->set_user_name(new_name);
  
  _Persistence->uncache_object( user );

  // re-mount user in home module:
  if ( is_mounted ) get_module( "home" )->mount( user );
  
  return user->get_user_name();
}

/**
 * Finds broken user objects (users with 0 username) and returns the user
 * names.
 * @return an array of usernames of broken users
*/
array get_broken_users()
{
  array result = ({ });
  foreach ( get_module("users")->index(), string uname ) {
    catch {
      object user = get_module("users")->lookup(uname);
      if ( objectp(user) && (user->get_object_class() & CLASS_USER) &&
           (user->get_user_name()==0 || user->query_attribute(OBJ_NAME)==0) )
        result += ({ uname });
    };
  }
  return result;
}

/**
 * Function that tries to recover broken user objects (users with 0 username).
 * @param user_names (optional) array of usernames (not user objects!) to
 *   recover. If missing, all broken users will be recovered.
 * @return an array with the recovered user objects
 */
array recover_users( void|array user_names)
{
    array result = ({ });
    int t = time();
    MESSAGE("Starting USER RECOVERY !");

    if ( !arrayp(user_names) ) {
      MESSAGE("Checking all users...");
      user_names = get_broken_users();
    }
    else
      MESSAGE("Checking %d users...", sizeof(user_names));

    foreach( user_names, mixed uname ) {
      if ( !stringp(uname) ) continue;
      mixed err0 = catch {
	object user = get_module("users")->lookup(uname);
	if ( objectp(user) && (user->get_object_class() & CLASS_USER) &&
             user->get_user_name()==0 || user->query_attribute(OBJ_NAME)==0 ) {
	  result += ({ user });
	  user->set_user_name(uname);
	  // heuristics
	  int user_oid = user->get_object_id();
	  mixed err = catch {
            int oid = user_oid + 1;
            object obj = find_object( oid++ );
            if ( objectp(obj) &&
                 ((obj->get_object_class() & CLASS_ROOM) != CLASS_ROOM) ) {
              // probably the sent-mail folder:
              obj = find_object( oid++ );
            }
            if ( objectp(obj) && (obj->get_object_class() & CLASS_ROOM) )
	      user->set_attribute(USER_WORKROOM, obj);
            obj = find_object( oid++ );
            if ( objectp(obj) && (obj->get_object_class() & CLASS_ROOM) )
	      user->set_attribute(USER_BOOKMARKROOM, obj);
            obj = find_object( oid++ );
            if ( objectp(obj) && (obj->get_object_class() & CLASS_TRASHBIN) )
	      user->set_attribute(USER_TRASHBIN, obj);
            obj = find_object( oid++ );
            if ( objectp(obj) && (obj->get_object_class() & CLASS_CALENDAR) )
	      user->set_attribute(USER_CALENDAR, obj);
	  };
	  
	  array groups = user->get_groups();
	  foreach ( get_module("groups")->get_groups(), object grp ) {
	    if ( grp->is_member(user) && search(groups, grp) == -1 ) {
	      grp->remove_member(user);
	      grp->add_member(user);
	    }
	  }
          MESSAGE("Recovered user %O", uname );
	}
      };
      if (err0)
	FATAL("Failed to restore %O\n%O\n%O", uname, err0[0], err0[1]);
    }
    MESSAGE("Finished USER RECOVERY in %d seconds", time() - t);
    return result;
}

void reset_guest()
{
  USER("guest")->unlock_attribute(OBJ_NAME);
  USER("guest")->set_attribute(OBJ_NAME, "guest");
  USER("guest")->set_user_password("guest");
  USER("guest")->set_user_name("guest");
  foreach(USER("guest")->get_groups(), object grp) {
    if ( grp != GROUP("everyone") )
      grp->remove_member(USER("guest"));
  }
}

string get_identifier() { return "User.factory"; }
string get_class_name() { return "User"; }
int get_class_id() { return CLASS_USER; }


void test()
{
    string uname;
    object user;
    int uname_count = 1;
    do {
      uname = "test_" + ((string)time()) + "_" + ((string)uname_count++);
      user = USER( uname );
    } while ( objectp(user) );
    user = execute( (["name": uname, "pw":"test", "email": "xyz",]) );
    if ( objectp(user) ) test_objects += ({ user });
    Test.test( "creating user", objectp(user) );
    
    // try to get attributes
    Test.test("User Attribute e-mail",
	      user->query_attribute(USER_EMAIL) == "xyz");
    // now try to protect
    user->add_attribute_reader(USER_EMAIL, user); // only for himself
    Test.test("User Attribute by Root", 
	      user->query_attribute(USER_EMAIL) == "xyz");
    string uname2;
    object user2;
    do {
      uname2 = "test2_"+ ((string)time()) + "_" + ((string)random(10000));
      user2 = USER( uname2 );
    } while ( objectp(user2) );
    user2 = execute( (["name": uname2, "pw":"test", "email": "xyz",]) );
    if ( objectp(user2) ) test_objects += ({ user2 });
    seteuid(user2);
    Test.test("EUID", geteuid() == user2);
    mixed err = catch(user->query_attribute(USER_EMAIL));
    Test.test("Restricted Attribute access denied", err != 0);
    werror("Looking up by email !\n");
    array users = get_module("users")->lookup_email("xyz");
    Test.test("Restricted email lookup fail", search(users, user)==-1);
    seteuid(0);
    
    if ( GROUP("steam") ) {
        Test.test( "new user is in steam group",
                   GROUP("steam")->is_member( user ) );
        //if ( !GROUP("steam")->is_member(user) )
        //   steam_error("Failure creating user: no in steam group !");
    }
    Test.test( "deleting user", user->delete() );
    user2->delete();
    Test.test( "user unregistered ?", 
	       !objectp(get_module("users")->lookup(uname)),
	       "Lookup of user still found !");
}
 
void test_cleanup () {
  if ( arrayp(test_objects) ) {
    foreach ( test_objects, object obj )
      catch ( obj->delete() );
  }
}
