/* Copyright (C) 2000-2010  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: GroupFactory.pike,v 1.7 2010/08/20 20:42:25 astra Exp $
 */

constant cvs_version="$Id: GroupFactory.pike,v 1.7 2010/08/20 20:42:25 astra Exp $";

inherit "/factories/ObjectFactory";

//! This factory creates a group with group workarea.

import Attributes;

#include <macros.h>
#include <classes.h>
#include <access.h>
#include <roles.h>
#include <database.h>
#include <events.h>
#include <attributes.h>
#include <types.h>
#include <exception.h>

static array(string) 
    sReservedNames = ({ "steam", "admin", "everyone", "privgroups" });

private static array test_objects = ({ });

static void init_factory() 
{
    ::init_factory();
    register_attribute(Attribute(GROUP_MEMBERSHIP_REQS, "request membership",
				 CMD_TYPE_ARRAY, ({ }), 0, CONTROL_ATTR_USER,
				 EVENT_ATTRIBUTES_QUERY, EVENT_ATTRIBUTES_CHANGE));
    register_attribute(UserAttribute(GROUP_WORKROOM,"workroom",CMD_TYPE_OBJECT,0));
    register_attribute(UserAttribute(GROUP_CALENDAR,"calendar",CMD_TYPE_OBJECT,0));
    register_attribute(UserAttribute(GROUP_MAXSIZE,"Group Maximum Pending Size",
				     CMD_TYPE_INT, 0));
    register_attribute(UserAttribute(GROUP_MSG_ACCEPT,"Group Accept Message",
				     CMD_TYPE_STRING, 0));
}

/**
 * Create a new group with the name "name" and optionally a parent group. The 
 * name parameter needs to be without "." in it. The group will become a 
 * top-level group if no parent group is set. Otherwise it will become
 * a member of the specified group. If the parent is called "Test" and
 * this group is named "subgroup" the result would be "Test.subgroup".
 * Params:
 *   string name - the name for the new group(without parents)
 *   object parentgroup - the parent group object.
 *  
 * @param mapping vars - the parameters within a mapping (see function docs)
 * @return the created group object or 0
 * @see group_add_user
 */
object execute(mapping vars)
{
    object grp, parentgroup;
    string             name;
    
    name               = vars["name"];
    parentgroup = vars["parentgroup"];
    // check if the parent group can be used

    if ( search(name, ".") >= 0 )
	steam_error("Using '.' in group names is forbidden !");
    
    if ( objectp(parentgroup) ) {
	_SECURITY->check_access(
	    parentgroup, CALLER, SANCTION_INSERT, ROLE_INSERT_ALL ,false);
	name = parentgroup->get_identifier() + "." + name;
    }
    else
	_SECURITY->check_access(
	    this(), CALLER, 
	    SANCTION_WRITE, 
	    ROLE_CREATE_TOP_GROUPS, 
	    false);

    object ogrp = MODULE_GROUPS->lookup(name);
    if ( objectp(ogrp) ) {
	if ( search(sReservedNames, lower_case(name)) >= 0 ) 
	    THROW("The name " + name + " is reserved for system groups.", 
		  E_ACCESS);	
	THROW("Group with that name ("+name+") already exists!", E_ACCESS);
    }
    ogrp = MODULE_USERS->lookup(name);
    if ( objectp(ogrp) )
	steam_error("There is already a user named '"+name+"' !");

    try_event(EVENT_EXECUTE, CALLER, grp);
    grp = object_create(name, CLASS_NAME_GROUP, 0, 
			vars["attributes"],
			vars["attributesAcquired"], 
			vars["attributesLocked"],
			vars["sanction"],
			vars["sanctionMeta"]);

    function grp_set_attribute = grp->get_function("do_set_attribute");
    function grp_lock_attribute = grp->get_function("do_lock_attribute");
    function grp_sanction_object = grp->get_function("do_sanction_object");

    grp->set_group_name(name);
    grp_set_attribute(OBJ_NAME, vars->name);
    grp_lock_attribute(OBJ_NAME);

    if ( objectp(parentgroup) ) {
      grp->set_parent(parentgroup);

      int parentAddMember = parentgroup->add_member(grp->this());
      if ( parentAddMember != 1 ) {
	FATAL("Failed to add group %O as member to parent %O, result of parent->add_member() is %d", grp->this(), parentgroup, parentAddMember);
      }
    }
    
    object workroom, factory;

    factory = _Server->get_factory(CLASS_ROOM);
    
    workroom = factory->execute(([
      "name":vars->name+"'s workarea",
      "attributes": ([ OBJ_OWNER: grp->this(), ]),
      "sanction": ([ grp->this(): SANCTION_ALL, ]),
      "sanctionMeta": ([ grp->this(): SANCTION_ALL, ]),
    ]));
    grp_set_attribute(GROUP_WORKROOM, workroom);
    grp_lock_attribute(GROUP_WORKROOM);

    object steam = GROUP("steam");
    if ( objectp(steam) )
      grp_sanction_object(steam, SANCTION_READ); // make readable

    workroom->set_creator(grp->this());

    object calendar=_Server->get_factory(CLASS_CALENDAR)->execute(([
      "name":name+"'s calendar",
      "attributes": ([ CALENDAR_OWNER: grp->this(), ]),
      "attributesLocked": ([ CALENDAR_OWNER: 1, ]),
      "sanction": ([ grp->this(): SANCTION_ALL, ]),
      "sanctionMeta": ([ grp->this(): SANCTION_ALL, ]),
    ]) );
    grp_set_attribute(GROUP_CALENDAR, calendar);
    grp_lock_attribute(GROUP_CALENDAR);

    if ( mappingp(vars["exits"]) )
      grp_set_attribute(GROUP_EXITS, vars["exits"]);
    else
      grp_set_attribute(GROUP_EXITS, ([ workroom:
					workroom->get_identifier(), ]));
    run_event(EVENT_EXECUTE, CALLER, grp);

    return grp->this();
}

object find_parent(object group)
{
  if ( objectp(group) )
      return group->get_parent();
  else
      return 0;
}


/**
 * Move a group to a new parent group. Everything is updated accordingly.
 *  
 * @param object group - the group to move
 * @param object new_parent - the new parent group
 * @return true or false
 */
bool move_group(object group, object new_parent)
{
    if ( !objectp(group) )
	steam_error("move_group() needs a group object to move!");
    if ( !objectp(new_parent) )
	steam_error("move_group() needs a target for moving the group!");

    _SECURITY->check_access(group,CALLER,SANCTION_WRITE,ROLE_WRITE_ALL,false);

    string identifier = get_group_name(group);
    foreach(new_parent->get_members(), object grp) {
	if ( objectp(grp) && grp->get_object_class() & CLASS_GROUP )
	    if ( grp != group && get_group_name(grp) == identifier )
		steam_error("Naming conflict for group: already found group "+
			    "with same name in target!");
    }
    object parent = group->get_parent();
    object groups = get_module("groups");
    if ( !objectp(parent) ) {
	// try to find some parent anyhow
      parent = find_parent(group);
    }

    // unmount group from home module:
    int is_mounted = get_module( "home" )->is_mounted( group );
    if ( is_mounted ) get_module( "home" )->unmount( group );

    if ( objectp(parent) && parent != new_parent ) {
        //werror("- found parent group: " + parent->get_identifier() + "\n");
	// check for permissions required
	parent->remove_member(group);
    }
    if ( !new_parent->is_member(group) )
      new_parent->add_member(group);

    string new_name = new_parent->get_identifier()+"."+get_group_name(group);
    groups->rename_group(group, new_name);
    group->set_group_name(new_name);

    // re-mount group in home module:
    if ( is_mounted ) get_module( "home" )->mount( group );

    // now we have to rename all subgroups:
    foreach(group->get_sub_groups(), object subgroup) {
      if ( objectp(subgroup) && subgroup->status() > 0 ) {
	move_group(subgroup, group); // this is not actually a move, but should update name
      }
    }
    object workroom = group->query_attribute(GROUP_WORKROOM);
    workroom->update_path();
    return true;
}

string get_group_name(object group)
{
  string identifier = group->get_identifier();
  array gn = (identifier / ".");
  if ( sizeof(gn) == 0 )
    return identifier;
  return gn[sizeof(gn)-1];
}

bool rename_group(object group, string new_name)
{
    _SECURITY->check_access(group,CALLER,SANCTION_WRITE,ROLE_WRITE_ALL,false);
    if ( search( new_name, "." ) >= 0 ) return false;
    object groups = get_module("groups");
    
    object parent = find_parent(group);
    string raw = new_name;
    if ( objectp(parent) )
      new_name = parent->get_identifier() + "." + new_name;
    
    if ( new_name == group->get_group_name() )
      return false;
    
    // check whether a group with the target name already exists:
    object old_group = groups->lookup( new_name );
    if ( objectp(old_group) && old_group != group )
      return false;

    _Persistence->uncache_object( group );

    string old_name = group->get_group_name();
    // unmount group from home module:
    int is_mounted = get_module( "home" )->is_mounted( group );
    if ( is_mounted ) get_module( "home" )->unmount( group );
    // rename group:
    groups->rename_group(group, new_name);
    group->set_group_name(new_name);
    group->unlock_attribute(OBJ_NAME);
    group->set_attribute(OBJ_NAME, raw);
    group->lock_attribute(OBJ_NAME);
    // re-mount group in home module:
    if ( is_mounted ) get_module( "home" )->mount( group );

    _Persistence->uncache_object( group );

    // notify persistence layers:
    _Persistence->group_renamed( group, old_name, new_name );
    // update sub-groups' names:
    foreach(group->get_sub_groups(), object subgroup) {
      if ( objectp(subgroup) && subgroup->status() > 0 ) {
        // this is not actually a move, but should update name:
	rename_group(subgroup, subgroup->query_attribute(OBJ_NAME));
      }
    }
    return true;
}

object fix_group_parent ( object group )
{
  _SECURITY->check_access(group,CALLER,SANCTION_WRITE,ROLE_WRITE_ALL,false);
  object parent = group->get_parent();
  if ( objectp(parent) ) return parent;
  string identifier = group->get_identifier();
  array parts = identifier / ".";
  if ( sizeof(parts) < 2 ) return 0; // top-level group
  string parent_identifier = parts[0..(sizeof(parts)-2)] * ".";
  parent = get_module("groups")->lookup( parent_identifier );
  if ( objectp(parent) ) group->set_parent( parent );
  return parent;
}

void delete_group ( object group )
{
  // check for write access on group and all sub-groups (recursively):
  _SECURITY->check_access(group,CALLER,SANCTION_WRITE,ROLE_WRITE_ALL,false);
  foreach ( group->get_sub_groups_recursive(), object subgroup )
    _SECURITY->check_access(subgroup,CALLER,SANCTION_WRITE,ROLE_WRITE_ALL,false);
  // unmount group from home module:
  get_module( "home" )->unmount( group );
  // delete group recursively with it's creator as euid:
  object old_euid = geteuid();
  object delete_euid = group->get_creator();
  if ( !objectp(delete_euid) ) delete_euid = _ROOT;
  seteuid( delete_euid );
  mixed err = catch( group->low_delete_object() );
  seteuid( old_euid );
  if ( err ) throw( err );
}

void test()
{
  string name = sprintf("test%d", time() );
  object grp = execute( (["name": name, ]) );
  if ( objectp(grp) ) test_objects += ({ grp });
  Test.test( "creating group", objectp(grp) );
  if ( !objectp(grp) ) return;
  object grp2 = execute( (["name": name+"_tmp", ]) );
  if ( objectp(grp2) ) test_objects += ({ grp2 });
  Test.test( "forbid renaming group with same name",
             !rename_group(grp, name) );
  Test.test( "forbid renaming group to an existing name",
             !rename_group(grp, grp2->get_identifier()) );
  Test.test( "forbid renaming group to a name with a '.' in it",
             !rename_group(grp, "PrivGroups."+name) );

  GROUP("PrivGroups")->add_member(grp);
  // changing group name is delayed ....
  Test.add_test_function( test_more, 1, grp, name );
  test_load_group(grp);
}

void test_load_group(object grp) 
{
  object uf = get_factory(CLASS_USER);
  int tt = get_time_millis();
  for (int i = 0; i < 500; i++) {
    object u = _Persistence->lookup_user("grouptester" + i);
    if (objectp(u)) {
      u->delete();
    }
    u = uf->execute( (["name": "grouptester" + i, "pw":"test", ]));
    grp->add_member(u->this());
  }
  werror("500 User created and joined test group in " + 
	 (get_time_millis() - tt) / 1000 + " seconds\n");
  tt = get_time_millis();
  grp->add_member(USER("root"));
  werror("join group of this user in " + (get_time_millis() - tt) + "ms\n");
  tt = get_time_millis();
  grp->remove_member(USER("root"));
  werror("leave group of this user in " + (get_time_millis() - tt) + "ms\n");
  for (int i = 0; i < 500; i++) {
    object u = USER("grouptester"+i);
    u->delete();
  }
}

static void test_more(object grp, string name)
{
  Test.test( "adding group to another group changes the identifier",
             has_prefix( grp->get_identifier(), "PrivGroups." ) );
  Test.test( "forbid renaming group with same parent name",
             !rename_group(grp, name));
  Test.test( "Moved group is still a top-level-group!",
	     search(get_module("groups")->get_top_groups(), grp)==-1);
  
  string new_name = sprintf("bingo%d", time());
  Test.test( "renaming group",
             rename_group(grp, new_name) );
  Test.test( "renamed group still has parent prefix",
             has_prefix( grp->get_identifier(), "PrivGroups." ) );
  Test.test( "renamed group can be found under the new name",
             get_module("groups")->lookup( "PrivGroups."+new_name ) == grp );
  Test.test( "old name of renamed group is no longer valid",
             !objectp(get_module("groups")->lookup( name )) );
  Test.test("group does not have a workroom!", grp->get_workroom());
  Test.test( "workroom path has been updated",
             grp->get_workroom()->query_attribute(OBJ_PATH)
             == "/home/"+grp->get_identifier() );
  Test.test( "workroom path in home module has been updated",
             grp->get_workroom() == OBJ( "/home/"+grp->get_identifier() ) );
}

void test_cleanup () {
  if ( arrayp(test_objects) ) {
    foreach ( test_objects, object obj )
      catch( obj->delete() );
  }
}

string get_identifier() { return "Group.factory"; }
string get_class_name() { return "Group"; }
int get_class_id() { return CLASS_GROUP; }
