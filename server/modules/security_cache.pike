/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: security_cache.pike,v 1.12 2010/01/26 15:45:39 astra Exp $
 */

constant cvs_version="$Id: security_cache.pike,v 1.12 2010/01/26 15:45:39 astra Exp $";

inherit "/kernel/secure_mapping";

#include <macros.h>
#include <exception.h>
#include <database.h>
#include <access.h>
#include <classes.h>

//! This module caches security checks in a mapping or the database.
//! Instead of traversing the whole group structure it directly
//! answers questions like is user A allowed to read document B,
//! and document B wont have user A explicitely in its ACL.

mapping         mCache =([ ]);
int         hits=0, total = 0;
private static function myfDb;

void load_module() 
{
  string mysDbTable;

  ::load_module();
  [myfDb , mysDbTable] = _Database->connect_db_mapping();
  if( search(myfDb()->list_tables(), "i_cache_security" ) == -1 ) {
    MESSAGE("Creating i_userlookup table in users module.");
    mixed err = catch {
      myfDb()->big_query("create table i_cache_security " +
	 "(obj int not null, user int not null, permissions int not null, "+
			 "UNIQUE(obj, user), INDEX(obj), INDEX(user))");

    };
    if ( err != 0 ) 
      FATAL("Failed to create security cache table: %O\n%O", err[0],err[1]);
  }
}

mixed get_value(mixed idx) {
  mixed res = mCache[idx];
  if (res) {
    return res;
  }
  res = ::get_value(idx);
  mCache[idx] = res;
  return res;
}

mixed set_value(mixed idx, mixed val) {
  mCache[idx] = val;
  ::set_value(idx, val);
}

string get_index(mixed obj, mixed user)
{
  if (objectp(obj) && objectp(user)) {
    return obj->get_object_id() + ":" + user->get_object_id(); 
  }
  return obj + ":" + user;
}

static mixed set_permission(object obj, object user, int permission)
{
  SECURITY_LOG("Cache: Setting permissions: %O, %O, %O\n", obj, user, permission);
  int oldPermission = get_permission(obj, user);
  if ( zero_type(oldPermission) ) {
    myfDb()->big_query(
        "insert into i_cache_security (obj, user, permissions) values ("+
	obj->get_object_id() + "," + user->get_object_id() + "," +
	permission + ")");
  }
  else {
    myfDb()->big_query("update i_cache_security set permissions="+permission+" where " +
		       "user="+user->get_object_id() + " and obj="+obj->get_object_id());
  }
  string idx = get_index(obj, user);
  mCache[idx] = permission;
  return permission;
}

void add_permission(object obj, object user, int value)
{
    int       perm, o_idx;

    SECURITY_LOG("Cache: Adding permissions: %O, %O, %O\n", obj, user, value);

    if ( !objectp(obj) ) return;

    if ( user == _ROOT && value > ( 1<< SANCTION_SHIFT_DENY) )
	THROW("Odd status of permissions - setting denied permissions for Root-user !", E_ERROR);
    
    if ( CALLER->this() != _SECURITY->this() )
	THROW("No permission to use security cache !", E_ACCESS);

    // add all dependend objects into the databasese
    object|function acquire = obj->get_acquire();
    if ( functionp(acquire) ) acquire = acquire();
    
    if ( objectp(acquire ) ) {
	o_idx = acquire->get_object_id();
	mixed val = get_value(o_idx);
	if ( !arrayp(val) ) 
	    val = ({ });
	if ( search(val, obj) == -1 ) {
	  set_value(o_idx, val + ({ obj }) );
	}
    }
    
    perm = get_permission(obj, user);
    set_permission(obj, user, perm | value);
}

void remove_permission(object obj)
{
    if ( !objectp(obj) ) return;
    Sql.sql_result res = myfDb()->big_query("select obj, user from i_cache_security where obj="+ obj->get_object_id());
 
    array data;
    while (data = res->fetch_row()) {
      string idx = get_index(data[0], data[1]);
      m_delete(mCache, idx);
    }
    
    array depends;
    depends = get_value(obj->get_object_id());
    if ( arrayp(depends) ) 
	foreach(depends, object dep)
	    remove_permission(dep);

    myfDb()->big_query("delete from i_cache_security where obj="+ obj->get_object_id());
    m_delete(mCache, obj->get_object_id());
}

void remove_permission_user(object user)
{
    Sql.sql_result res = myfDb()->big_query("select obj, user from i_cache_security where user="+user->get_object_id());
    array data;
    while (data = res->fetch_row()) {
      string idx = get_index(data[0], data[1]);
      m_delete(mCache, idx);
    }
    myfDb()->big_query("delete from i_cache_security where user=" + user->get_object_id());
}

int get_permission(object obj, object user)
{
    if ( !objectp(obj) || !objectp(user) ) return 0;

    Sql.sql_result res = myfDb()->big_query("select permissions from i_cache_security where obj="+ obj->get_object_id() + " and user="+user->get_object_id());
    mixed row = res->fetch_row();
    if (row) {
      int permission = (int)row[0];
      mCache[get_index(obj, user)] = permission;
      return permission;
    }
    return UNDEFINED;
}

void clear_cache() 
{
  if ( GROUP("admin")->is_member(this_user()) ) {
    clear_table();
    mCache = ([ ]);
    return;
  }
  steam_error("Unauthorized call to clear_cache()");
}

void test() {
  object testuser = get_factory(CLASS_USER)->execute( (["name": "security_cache_test_user", "pw":"test", "email": "xyz",]) );

  seteuid(testuser);
  object obj2 = get_factory(CLASS_OBJECT)->execute( (["name":"security_cache_obj" ]));  
  Test.test("Correct permissions from security module for simple object test case",
	    _SECURITY->get_user_permissions(obj2, testuser, SANCTION_READ) == SANCTION_READ);
  seteuid(0);

  seteuid(USER("root"));
  Test.test("Correct permissions from security module for simple object test case for user ROOT",
	    _SECURITY->get_user_permissions(obj2, USER("root"), SANCTION_READ) == SANCTION_READ);
  seteuid(0);
    
  object testgroup = get_factory(CLASS_GROUP)->execute( (["name":"security_cache_test_group" ]));
  seteuid(testuser);
  catch(testuser->move(testgroup->get_workroom()));
  // moving a user into a room only required read permissions
  Test.test("Permissions cached for user NOT member of group ("+
	    get_permission(testgroup->get_workroom(), testuser) +")!",
	    get_permission(testgroup->get_workroom(), testuser) == 
	    (SANCTION_READ << SANCTION_SHIFT_DENY));
  Test.test("Test User cannot retrieve inventory", 
	    catch(testgroup->get_workroom()->get_inventory()) != null);
  Test.test("Permissions !READ cached for user NOT member of group ("+
	    get_permission(testgroup->get_workroom(), testuser) +")!",
	    get_permission(testgroup->get_workroom(), testuser) == 
	    (SANCTION_READ << SANCTION_SHIFT_DENY));
  seteuid(0);
  // now set read permissions
  testgroup->get_workroom()->sanction_object(testuser, SANCTION_READ);
  Test.test("Correct permissions from security module for user",
	    _SECURITY->get_user_permissions(testgroup->get_workroom(), testuser, SANCTION_READ) == SANCTION_READ);
  seteuid(testuser);
  Test.test("Successfully retrieved inventory!",
	    testgroup->get_workroom()->get_inventory() != null);
  Test.test("Permissions READ cached for user allowed to read ("+
	    get_permission(testgroup->get_workroom(), testuser) +")!",
	    get_permission(testgroup->get_workroom(), testuser) == 
	    (SANCTION_READ));
  seteuid(0);
  // now revoke read permissions
  testgroup->get_workroom()->sanction_object(testuser, 0);
  Test.test("Permissions READ cache updated for user NOT allowed to read ("+
	    get_permission(testgroup->get_workroom(), testuser) +")!",
	    get_permission(testgroup->get_workroom(), testuser) == 0);
  testgroup->add_member(testuser);
  Test.test("Permissions cached for user ADDED to new group!",
	    get_permission(testgroup->get_workroom(), testuser) == 0,
	    "CACHE="+get_permission(testgroup->get_workroom(), testuser));
  Test.test("Correct permissions from security module for user member of group",
	    _SECURITY->get_user_permissions(testgroup->get_workroom(), testuser, SANCTION_READ) == SANCTION_READ);
  
  seteuid(testuser);
  // user should be able to access groups workroom now
  catch(testuser->move(testgroup->get_workroom()));
  Test.test("Permissions cached for user member of group!",
	    get_permission(testgroup->get_workroom(), testuser) != 
	    (SANCTION_INSERT|SANCTION_READ));
  seteuid(0);
  // remove user from group
  testgroup->remove_member(testuser);
  Test.test("Permissions cache updated for user removed from group ("+
	    get_permission(testgroup->get_workroom(), testuser) +")!",
	    get_permission(testgroup->get_workroom(), testuser) == 0);
  object subgroup = get_factory(CLASS_GROUP)->execute( (["name":"security_cache_sub_group" ]));
  subgroup->add_member(testuser);
  testgroup->add_member(subgroup);
  seteuid(testuser);
  catch(testuser->move(testgroup->get_workroom()));
  seteuid(0);
  Test.test("Permissions cached for user member of SUB group!",
	    get_permission(testgroup->get_workroom(), testuser) != 
	    (SANCTION_INSERT|SANCTION_READ));
  
  testgroup->remove_member(testuser);
  Test.test("Permissions cleaned for user member of previous sub group!",
	    get_permission(testgroup->get_workroom(), testuser) == 0,
	    "CACHE="+get_permission(testgroup->get_workroom(), testuser));
  object subroom = get_factory(CLASS_ROOM)->execute( (["name":"security_cache_sub_room1" ]));
  subroom->move(subgroup->get_workroom());
  seteuid(testuser);
  catch(testuser->move(subroom));
  Test.test("Permissions SUBROOM cached for user member of SUB group!",
	    get_permission(subroom, testuser) != 
	    (SANCTION_INSERT|SANCTION_READ));
  seteuid(0);
  subgroup->remove_member(testuser);
  Test.test("Permissions acquired cleaned for user member of no group!",
	    get_permission(subroom, testuser) == 0,
	    "CACHE="+get_permission(subroom, testuser));
  testgroup->add_member(subgroup);
  subgroup->add_member(testuser);
  object room2 = get_factory(CLASS_ROOM)->execute( (["name":"security_cache_sub_room2" ]));
  room2->move(testgroup->get_workroom());
  seteuid(testuser);
  catch(testuser->move(room2));
  Test.test("Permissions SUBROOM-2 cached for user member of group!",
	    get_permission(room2, testuser) != 
	    (SANCTION_INSERT|SANCTION_READ));
  seteuid(0);
  subgroup->remove_member(testuser);
  Test.test("Permissions acquired cleaned for user member of no group (2)!",
	    get_permission(room2, testuser) == 0,
	    "CACHE="+get_permission(room2, testuser));
  testgroup->get_workroom()->sanction_object(testuser, SANCTION_READ|SANCTION_INSERT);
  object obj = get_factory(CLASS_OBJECT)->execute( (["name":"security_cache_obj" ]));  
  obj->sanction_object(testuser, SANCTION_MOVE);
  seteuid(testuser);
  obj->move(room2);
  testuser->move(testgroup->get_workroom());
  seteuid(0);
  testgroup->get_workroom()->sanction_object(testuser, SANCTION_WRITE);
  Test.test("Permissions acquired cleaned for user member of no group (3)!",
	    get_permission(room2, testuser) == 0,
	    "CACHE="+get_permission(room2, testuser));
  Test.test("Direct Permissions cleaned for user!",
	    get_permission(testgroup->get_workroom(), testuser) == 0,
	    "CACHE="+get_permission(testgroup->get_workroom(), testuser));
  obj->delete();
  room2->delete();
  subroom->delete();
  subgroup->delete();
  testuser->delete();
  testgroup->delete();
  
  obj2->delete();
}

string get_identifier() { return "Security:cache"; }
string get_table_name() { return "security_cache"; }
