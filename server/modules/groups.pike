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
 * $Id: groups.pike,v 1.2 2010/01/26 12:09:01 astra Exp $
 */

constant cvs_version="$Id: groups.pike,v 1.2 2010/01/26 12:09:01 astra Exp $";

inherit "/kernel/secure_mapping.pike";

#include <macros.h>
#include <attributes.h>
#include <classes.h>
#include <events.h>
#include <database.h>

//! This module maps the name of the group to the group object.
//! Its possible to get a list of all groups inside here. Apart
//! from that its only used by the server directly.

private static array test_objects = ({ });

/**
 * Get a list of groups. 
 *  
 * @return an array of groups.
 */
array(object) get_groups()
{
    array(string) index  = index();
    array(object) groups =   ({ });


    foreach ( index, string idx ) {
	object obj = get_value(idx);
	if ( objectp(obj) )
	    groups += ({ obj });
    }
    return groups;
}

array(object) get_top_groups()
{
  array groups = do_query_attribute("groups_top_groups") || ({ });
  groups -= ({ 0 });
  return groups;
}

void unregister_group(object grp) 
{
  if ( grp->this() != CALLER->this() ) {
    WARN("groups module: unregister from invalid %O", CALLER);
    THROW("Unauthorized call to groups module: unregister()", E_ACCESS);
  }
  unregister(grp->get_group_name());
}

static int unregister(string groupName) 
{
  return ::unregister(groupName);
}

int register(string name, object obj)
{
  if (obj->this() != CALLER->this()) {
    WARN("groups module: register from invalid %O", CALLER);
    THROW("Unauthorized call to groups module: register()", E_ACCESS);
  }
  if (!objectp(obj->get_parent())) {
    MESSAGE("New top level group %O", obj);
    array topgroups = get_top_groups();
    topgroups += ({ obj });
    do_set_attribute("groups_top_groups", topgroups);
  }
  return ::register(name, obj);
}

void rename_group(object group, string new_name)
{
    if ( CALLER != get_factory(CLASS_GROUP) )
	steam_error("Invalid call to rename_group() !");
    string old_name = group->get_group_name();
    set_value(new_name, group);
    if ( stringp(old_name) && new_name != old_name ) delete( old_name );
}

/**
 * Initialize the module. Only sets the description attribute.
 *  
 */
void init_module()
{
    set_attribute(OBJ_NAME, "groups");
    set_attribute(OBJ_DESC, "This is the database table for lookup "+
		  "of Groups !");
}

void init_groups() 
{
  array topgroups = ({ });
  array groups = get_groups();
  foreach(groups, object grp) {
    if ( !objectp(grp->get_parent()))
      topgroups += ({ grp });
  }
  do_set_attribute("groups_top_groups", topgroups);
}


static void load_module()
{
  ::load_module();
  array topgroups = do_query_attribute("groups_top_groups");
  if ( !arrayp(topgroups) )
    init_groups();
  add_global_event(EVENT_ADD_MEMBER, event_add_member, PHASE_NOTIFY);
  add_global_event(EVENT_REMOVE_MEMBER, event_remove_member, PHASE_NOTIFY);
}

void event_add_member(int e, object grp, object caller, object add, bool pw)
{
  array topgroups = get_top_groups();
  if ( search(topgroups, add) >= 0 ) {
    topgroups -= ({ add });
    do_set_attribute("groups_top_groups", topgroups);
  }
}

void event_remove_member(int e, object grp, object caller, object user)
{
  array topgroups = get_top_groups();
  if ( user->get_object_class() & CLASS_GROUP ) {
    if ( !objectp(user->get_parent()) ) {
      topgroups += ({ user });
      do_set_attribute("groups_top_groups", topgroups);
    }
  }  
}

object lookup(string index)
{
    return _Persistence->lookup_group(index);
}


/**
 * Lookup a group by name
 *
 * @param string name the name of the group to search
 * @param bool like optional parameter to specify "like" instead of "="
 * @return array of matching groups
 */
array(object) lookup_name(string name, void|bool like)
{
  return _Persistence->lookup_groups( ([ "name":name ]), false,
                                      (like ? "*" : 0) );
}


object get_group ( string name )
{
  return get_value(name);
}

/**
 * Drops a group from any caches, so that it will receive fresh data on the
 * next lookup. This can be useful if you know that group data has changed in
 * one of the persistence layers and you want the group object to update its
 * data accordingly (before the regular update after the cache times out).
 *
 * @param identifier the identifier (full group name with parent groups
 *  separated by ".") of the group that shall be dropped from cache
 * @return 1 if the group was dropped from the object cache,
 *   0 if it wasn't found in the object cache (regardless of this return value,
 *   the group might have been dropped from any persistence layer caches)
 */
int uncache_group ( string identifier )
{
  return _Persistence->uncache_group( identifier );
}

string get_identifier() { return "groups"; }
string get_table_name() { return "groups"; }

void check_integrity()
{
  array topgroups = get_top_groups();
  foreach (topgroups, object grp) {
    if ( objectp(grp) )
      if ( grp->get_parent() )
        steam_error("Found Top-Group with Parent !");
  }
  array groups = get_groups();
  foreach(groups, object grp) {
    if ( !objectp(grp->get_parent()) && search(topgroups, grp) == -1 ) {
      register(grp->get_group_name(), grp);
      steam_error("Found Top-Group %O not in get_top_groups() ... fixed!", 
		  grp->get_object());
    }
  }
}
 
int check_updates () {
  int result = 0;  // set to 1 if an update needs a server restart

  // parent update:
  string parent_update = "fixed parents of all groups";
  if ( !_Server->get_update( parent_update ) ) {
    array groups = get_groups();
    int nr_groups = sizeof(groups);
    MESSAGE( "Fixing parents for all %d groups...", nr_groups );
    string update_log = "=Fixing-Parents=\n\n" + ctime(time())
      + sprintf( "\nFixing parents of all %d groups.\n\n", nr_groups );
    int count = 0;
    int failed = 0;
    object group_factory = get_factory( CLASS_GROUP );
    foreach ( groups, object group ) {
      count++;
      if ( (count % 100) == 0 )
        MESSAGE("Fixed parent for %d of %d groups...", count, nr_groups);
      string identifier = group->get_identifier();
      if ( !stringp(identifier) ) {
        update_log += "* '''ERROR:''' skipping group with empty identifier "
          + "(id: " + group->get_object_id() + ")\n";
        werror( "group with empty identifier: %O\n", group );
        failed++;
        continue;
      }
      object old_parent = group->get_parent();
      if ( objectp(old_parent) ) {
        mixed old_parent_identifier = old_parent->get_identifier();
        if ( !stringp(old_parent_identifier) )
          old_parent_identifier = "(invalid identifier)";
        update_log += "* " + identifier + " : already has parent: "
          + old_parent_identifier + " (id: " + old_parent->get_object_id()
          + ")\n";
        continue;
      }
      object new_parent = group_factory->fix_group_parent( group );
      if ( !objectp(new_parent) ) {
        if ( !arrayp(group->get_groups()) || sizeof(group->get_groups())==0 ) {
          update_log += "* "+identifier+" : is top-level group, skipping\n";
          continue;
        }
        update_log += "* '''ERROR:''' "+identifier+" : could not be fixed\n";
        werror( "Failed to fix group parent of %O\n", group );
        failed++;
        continue;
      }
      mixed new_parent_identifier = new_parent->get_identifier();
      if ( !stringp(new_parent_identifier) )
        new_parent_identifier = "(empty identifier)";
      if ( new_parent != group->get_parent() ) {
        update_log += "* '''ERROR:''' " + identifier + " : parent could not be"
          + " set: " + new_parent_identifier + " (id: "
          + new_parent->get_object_id() + ")\n";
        werror( "Could not set parent %O to group %O\n", new_parent, group );
        failed++;
        continue;
      }
      update_log += "* " + identifier + " : new parent: "
        + new_parent_identifier + " (id: "+new_parent->get_object_id()+")\n";
    }
    update_log += "\n" + ctime(time()) + "\n";
    update_log += "\n" + failed + " errors occurred.\n";
    object update = get_factory(CLASS_DOCUMENT)->execute(
                      ([ "name":parent_update, "mimetype":"text/wiki" ]) );
    if ( objectp(update) ) {
      update->set_content( update_log );
      _Server->add_update( update );
      MESSAGE( "Finished fixing group parents." );
    }
    else {
      MESSAGE( "Failed to store group parent update." );
      werror( "Failed to store group parent update.\n" );
    }
  }

  return result;
}

void test()
{
  object oldgroup = GROUP("groupstestgroup");
  if ( objectp(oldgroup) )
    catch( oldgroup->delete() );
  oldgroup = GROUP("groupstestgroup.groupstestgroup");
  if ( objectp(oldgroup) )
    catch( oldgroup->delete() );
  oldgroup = GROUP("PrivGroups.groupstestgroup");
  if ( objectp(oldgroup) )
    catch( oldgroup->delete() );

  check_integrity();
  // new top level group
  object factory = get_factory(CLASS_GROUP);
  object grp = factory->execute( ([ "name": "groupstestgroup", ]) );
  if ( objectp(grp) ) test_objects += ({ grp });
  Test.test( "creating new top-level group",
             ( search(get_top_groups(), grp) != -1 ) );
  object grp2 = factory->execute( ([ "name": "groupstestgroup", 
				     "parentgroup": grp ]) );
  if ( objectp(grp2) ) test_objects += ({ grp2 });
  Test.test( "creating sub-group",
             ( search(get_top_groups(), grp2) == -1 ),
             "found sub-group in top-level groups" );
  
  // now move
  Test.test( "add_member", 
	     GROUP("PrivGroups")->add_member(grp) == 1,
	     "Cannot Add Group to PrivGroups");
  Test.add_test_function(test_more, 1, grp, grp2);
}

static void test_more(object grp, object grp2) 
{
  Test.test( "moving group",
	     (grp->get_parent() == GROUP("PrivGroups")),
	     "Moved groups parent is not PrivGroups (is "+
	     sprintf("%O", grp->get_parent()) + ")");

  Test.test( "top groups",
             ( search(get_top_groups(), grp) == -1 ),
             "Found moved group (" + grp->get_group_name()+
	     ") in top-level groups" );
}

void test_cleanup () {
  if ( arrayp(test_objects) ) {
    foreach ( test_objects, object obj )
      catch( obj->delete() );
  }
}
