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
 * $Id: users.pike,v 1.2 2010/01/25 19:18:18 astra Exp $
 */

constant cvs_version="$Id: users.pike,v 1.2 2010/01/25 19:18:18 astra Exp $";

inherit "/kernel/secure_mapping.pike";

#include <macros.h>
#include <database.h>
#include <classes.h>
#include <attributes.h>

//! This module keeps track of the users in the database. -
//! Therefor it maps a nickname to the related sTeam user object.

private static function             myfDb;
private static string          mysDbTable;
private static array test_objects = ({ });

void load_module() 
{
  ::load_module();
  [myfDb , mysDbTable] = _Database->connect_db_mapping();
  if( search(myfDb()->list_tables(), "i_userlookup" ) == -1 ) {
    MESSAGE("Creating i_userlookup table in users module.");
#if 0
    array types = ({ ([ "name": "login", "type":"char(255) not null", ]),
		     ([ "name": "email", "type":"char(255)", ]),
		     ([ "name": "firstname", "type":"char(255)", ]),
		     ([ "name": "lastname", "type":"char(255)", ]),
		     ([ "name": "user_id", "type":"char(255)", ]),
		     ([ "name": "ob_id", "type":"char(255) not null", 
			"unique":"true"]) });
		     
    myfDb()->create_table("i_userlookup", types);
#endif
    mixed err = catch {
      myfDb()->big_query("create table i_userlookup "
			 "(login char(255) not null, email char(255), firstname char(255), lastname char(255), user_id char(255), ob_id char(255) not null, UNIQUE(ob_id))");

      foreach( get_users(), object u) {
	update_user(u);
      }
    };
    if ( err != 0 ) 
      FATAL("Failed to create userlookup table: %O\n%O", err[0],err[1]);
  }
}

int unregister_user(object u)
{
  if ( u->this() != CALLER->this() ) {
    WARN("users module: unregister from invalid %O", CALLER);
    THROW("Unauthorized call to users module: unregister()", E_ACCESS);
  }
  unregister(u->get_user_name());
}

static int unregister(string key)
{
  int result = ::unregister(key);
  // delete this user from i_userlookup, too
  myfDb()->big_query("delete from i_userlookup where login='"+
                     myfDb()->quote_index(key) + "'");
  return result;
}


void update_user(object u) 
{
  if ( objectp(u) ) {
    if ( u->this() != CALLER->this() ) {
      WARN("users module: update_user from invalid %O", CALLER);
      THROW("Unauthorized call to users module: update_user!", E_ACCESS);
    }
    Sql.sql_result res = myfDb()->big_query("select * from i_userlookup where ob_id='"+u->get_object_id()+"'");
    mixed err = catch {
      string query;
      if ( res->fetch_row() ) {
	query = sprintf("update i_userlookup set login='%s',email='%s',firstname='%s',lastname='%s',user_id='%s' where ob_id='%s'",
			myfDb()->quote(u->get_user_name()||""),
			myfDb()->quote(u->query_attribute(USER_EMAIL)||""),
			myfDb()->quote(u->query_attribute(USER_FIRSTNAME)||""),
			myfDb()->quote(u->query_attribute(USER_FULLNAME)||""),
			myfDb()->quote(u->query_attribute(USER_ID)||""), 
			(string)u->get_object_id());
      }
      else {
	query = 
	  sprintf("insert into i_userlookup values('%s','%s','%s','%s','%s','%s')",
		  myfDb()->quote(u->get_user_name()||""),
		  myfDb()->quote(u->query_attribute(USER_EMAIL)||""),
		  myfDb()->quote(u->query_attribute(USER_FIRSTNAME)||""),
		  myfDb()->quote(u->query_attribute(USER_FULLNAME)||""),
		  myfDb()->quote(u->query_attribute(USER_ID)||""), 
		  (string)u->get_object_id());
      }      
      myfDb()->big_query(query);
    };
    if ( err ) {
      FATAL("Failed to insert user: %O\n%O", err[0], err[1]);
    }
  }  
}

int register(string uname, object user) 
{
  if (!objectp(user) || CALLER->this() != user->this()) {
    WARN("users module: register from invalid %O", CALLER);
    THROW("Unauthorized call to users module: register()", E_ACCESS);
  }
  mixed err = catch(update_user(user));
  if ( err ) 
    FATAL("While updating user: %O\n%O", err[0], err[1]);

  return ::register(uname, user);
}

/**
 * Lookup a user by his login
 *
 * @param string login the login of the user to search
 * @param bool like optional parameter to specify "like" instead of "="
 * @return array of matching users
 */
array(object) lookup_login(string login, void|bool like)
{
  return _Persistence->lookup_users( ([ "login":login ]), false,
                                     (like ? "*" : 0) );
}

/**
 * Lookup a user by his name (firstname, lastname)
 *
 * @param string firstname the firstname of the user to search
 * @param string lastname the last name of the user to search
 * @param bool like optional parameter to specify "like" instead of "="
 * @return array of matching users
 */
array(object) lookup_name(string firstname, string lastname, void|bool like)
{
  return _Persistence->lookup_users( ([ "firstname":firstname,
                                        "lastname":lastname ]), false,
                                     (like ? "*" : 0) );
}

array(object) search_name(string firstname, string lastname, void|bool like)
{
  return _Persistence->lookup_users( ([ "firstname":firstname,
                                        "lastname":lastname ]), true,
                                     (like ? "*" : 0) );
}

/**
 * Lookup a user by his lastname
 *
 * @param string lastname the last name of the user to search
 * @return array of matching users
 */
array(object) lookup_lastname(string lastname, void|bool like)
{
  return _Persistence->lookup_users( ([ "lastname":lastname ]), false,
                                     (like ? "*" : 0) );
}

/**
 * Lookup a user by his first name
 *
 * @param string firstname the first name of the user to search
 * @return array of matching users
 */
array(object) lookup_firstname(string firstname, void|bool like)
{
  return _Persistence->lookup_users( ([ "firstname":firstname ]), false,
                                     (like ? "*" : 0) );
}

/**
 * Search users by a term
 *
 * @param string term the search term 
 * @return array of matching users
 */
array(object) search_users(string term, void|bool like)
{
  return _Persistence->lookup_users( ([ "firstname":term, "lastname":term,
                                        "login":term, "email":term ]), true,
                                     (like ? "*" : 0) );
}

int check_read_attribute(object user, string attribute)
{
  mixed err = catch(user->check_read_attribute(attribute, 
					       geteuid()||this_user()));
  if ( err ) {
    if ( sizeof(err) == 3)
      return 0;
    FATAL("Error while checking for readable attribute %O of %O\n%O:%O",
	  attribute, user, err[0], err[1]);
  }
  return 1;
}

static array(object) check_user(int id, void|string|array attribute) 
{
  // check if user data are still ok ?!
  object user = find_object(id);
  if (attribute) {
    if ( arrayp(attribute) ) {
      foreach(attribute, string a)
	if ( check_read_attribute(user, a) == 0 )
	  return ({ });
    }
    else 
      if ( check_read_attribute(user, attribute) == 0 )
	return ({ });
  }
  return ({ user });
}


/**
 * Lookup a user by id
 *
 * @param string id the id to lookup
 * @return array of matching users
 */
array(object) lookup_id(string id) 
{
  Sql.sql_result res = myfDb()->big_query("select ob_id from i_userlookup where user_id='"+id+"'");

  mixed row;

  if ( !objectp(res) )
    return 0;
 
  array result = ({ });
  while ( row = res->fetch_row() ) {
    result += check_user((int)row[0], USER_ID);
  }
  destruct(res);
  return result;
}

/**
 * Lookup a user by e-mail
 *
 * @param string e-mail the e-mail to lookup
 * @param bool like exact search flag
 * @return array of matching users
 */
array(object) lookup_email(string email, void|bool like) 
{
  if (!stringp(email) || strlen(email) == 0)
    return ({ });

  return _Persistence->lookup_users( ([ "email":email ]), false,
                                     (like ? "*" : 0) );
}

/**
 * Lookup a user by login
 *
 * @param string index the login to lookup
 * @return matching user
 */
object lookup(string index)
{
    return _Persistence->lookup_user(index);
}

string rename_user(object user, string new_name)
{
  if ( CALLER != get_factory(CLASS_USER) )
    steam_error("Invalid call to rename_user() !");
  object other = get_value(new_name);
  if ( objectp(other) && other != user )
    steam_error("There is already a user with the name '"+new_name+"' !");
  string name = user->get_user_name();
  delete( name );
  set_value(new_name, user);
  _Persistence->user_renamed( user, name, new_name );
  return new_name;
}

array(object) get_users() 
{
  array(string) index  = index();
  array(object) users =   ({ });

  foreach ( index, string idx ) {
    object obj = get_value(idx);
    if ( objectp(obj) )
      users += ({ obj });
  }
  return users;
}

object get_user(string name )
{
  return get_value(name);
}

/**
 * Drops a user from any caches, so that it will receive fresh data on the
 * next lookup. This can be useful if you know that user data has changed in
 * one of the persistence layers and you want the user object to update its
 * data accordingly (before the regular update after the cache times out).
 *
 * @param identifier the identifier (user's login name) of the user that shall
 *   be dropped from cache
 * @return 1 if the user was dropped from the object cache,
 *   0 if it wasn't found in the object cache (regardless of this return value,
 *   the user might have been dropped from any persistence layer caches)
 */
int uncache_user ( string identifier )
{
  return _Persistence->uncache_user( identifier );
}

int check_updates () {
  int result = 0;  // set to 1 if an update needs a server restart

  // sent-mail update:
  string sent_mail_update = "activated sent-mail for all users";
  if ( !_Server->get_update( sent_mail_update ) ) {
    array users = get_users();
    int nr_users = sizeof(users);
    MESSAGE( "Activating sent-mail for all %d users...", nr_users );
    string update_log = "=Sent-Mails=\n\n" + ctime(time())
      + sprintf( "\nCreating sent-mail folders and activating sent-mail "
      + "storage for all %d users.\n\n", nr_users );
    int count = 0;
    int failed = 0;
    foreach ( users, object user ) {
      if ( user == _GUEST ) continue;  // skip guest user
      string username = user->get_identifier();
      update_log += "* " + username + " : folder ";
      mixed res;
      mixed err = catch( res = user->create_sent_mail_folder() );
      if ( err ) {
        update_log += "'''could not be created''' (" + err[0] + "), storage ";
        werror("Could not create sent-mail folder for user "+username+"\n");
        failed++;
      }
      else if ( !objectp(res) ) {
        update_log += "'''could not be created''', storage ";
        werror("Could not create sent-mail folder for user "+username+"\n");
        failed++;
      }
      else
        update_log += "created, storage ";
      err = catch( res = user->set_is_storing_sent_mail( 1 ) );
      if ( err ) {
        update_log += "'''could not be activated''' (" + err[0] + ")\n";
        werror("Could not activate sent-mail storage for user "+username+"\n");
        failed++;
      }
      else if ( !user->is_storing_sent_mail() ) {
        update_log += "'''could not be activated'''\n";
        werror("Could not activate sent-mail storage for user "+username+"\n");
        failed++;
      }
      else
        update_log += "activated\n";
      count++;
      if ( (count % 100) == 0 )
        MESSAGE("Activated sent-mails for %d of %d users...", count, nr_users);
    }
    update_log += "\n" + ctime(time()) + "\n";
    update_log += "\n" + failed + " errors occurred.\n";
    object update = get_factory(CLASS_DOCUMENT)->execute(
                      ([ "name":sent_mail_update, "mimetype":"text/wiki" ]) );
    if ( objectp(update) ) {
      update->set_content( update_log );
      _Server->add_update( update );
      MESSAGE( "Finished activating sent-mail for users." );
    }
    else {
      MESSAGE( "Failed to store sent-mail update." );
      werror( "Failed to store sent-mail update.\n" );
    }
  }

  return result;
}

string get_identifier() { return "users"; }
string get_table_name() { return "users"; }

void test()
{
  object factory = get_factory(CLASS_USER);

  string uname;
  object user;
  int uname_count = 1;
  do {
    uname = "test_" + ((string)time()) + "_" + ((string)uname_count++);
    user = USER( uname );
  } while ( objectp(user) );
  user = factory->execute( (["name": uname, "pw":"test", "email": "xyz",]) );
  if ( objectp(user) ) test_objects += ({ user });
  
  //try to find
  array users = lookup_email("xyz");
  Test.test("User searching 1", search(users, user) >= 0);
  Test.test("User lookup", lookup(uname) == user);
  
  user->set_attribute(USER_FIRSTNAME, "xyzz");
  users = lookup_firstname("xyzz");
  Test.test("User searching 2", search(users, user) >= 0);
}

void test_cleanup () {
  if ( arrayp(test_objects) ) {
    foreach ( test_objects, object obj )
      catch( obj->delete() );
  }
}
