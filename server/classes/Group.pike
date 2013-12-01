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
 * $Id: Group.pike,v 1.8 2010/01/26 12:09:01 astra Exp $
 */

constant cvs_version="$Id: Group.pike,v 1.8 2010/01/26 12:09:01 astra Exp $";

inherit "/classes/Object" : __object;
inherit "/base/member"    : __member;

import Roles;

#include <macros.h>
#include <roles.h>
#include <assert.h>
#include <classes.h>
#include <events.h>
#include <access.h>
#include <database.h>
#include <attributes.h>
#include <types.h>

private int              iGroupRoles; /* special privileges of the group */
private static RoleList   groupRoles; /* all roles for this groups */

private static string     sGroupName; /* the groups name */
private static string       sGroupPW; /* password for the group */
static  array(object) aoGroupMembers; /* members of the group */
static  array(object)      aoInvites; /* invited users */
static  array               aPending; /* waiting users */
static  array      aoExclusiveGroups; /* groups with mutual exclusive members*/
static  object               oParent; /* the groups parent */

object this() { return __object::this(); }

#define GROUP_ADMIN_ACCESS SANCTION_ALL

/**
 * Initialization of the object. 
 *  
 * @see create_object
 */
static void init()
{
    ::init();
    ::init_member(); // groups are also group members !
    aoGroupMembers = ({ });
    aoInvites      = ({ });
    aPending       = ({ });
    groupRoles     = RoleList();
    
    sGroupPW = "";
    add_data_storage(STORE_GROUP,retrieve_group_data, restore_group_data);
}

/**
 * Constructor of the group.
 *  
 * @see duplicate
 */
static void
create_object()
{
    ::create_object();
    iGroupRoles  = 0;
    sGroupName = "";
}

/**
 * Create a duplicate of this object.
 *  
 * @return the duplicate object
 * @see create_object
 */
mapping do_duplicate(void|mapping vars)
{
    mapping dup = ::do_duplicate(vars);
    object dup_obj = dup[this()];

    foreach( aoGroupMembers, object member ) {
	dup_obj->add_member(member);
    }
    return dup;
}

/**
 * Set the parent group of this group.
 *  
 * @param object grp - the new parent
 * @see get_parent
 */
void set_parent(object grp)
{
    if ( _Server->is_a_factory(CALLER) ) {
	oParent = grp;
	require_save(STORE_GROUP);
    }
}

/**
 * Get the parent group. The group is identified by 
 * (parent->identifier).(groups name)
 *  
 * @return the parent group or zero
 */
object get_parent()
{
    return oParent;
}

object get_workroom() {
  return do_query_attribute(GROUP_WORKROOM);
}

/**
 * Get the sub groups of this group (the groups that are members of this
 * group).
 *
 * @see get_sub_groups_recursive
 * @see get_members
 * @see get_members_recursive
 *
 * @return an array containing all groups that are members of this group
 */
array get_sub_groups()
{
  return get_members( CLASS_GROUP );
}

/**
 * Get the sub groups of this group recursively (the groups that are members
 * of this group or any group that is a member of this group, and so on).
 *
 * @see get_subgroups
 * @see get_members
 * @see get_members_recursive
 *
 * @return an array containing all groups that are members of this group,
 *   recursively
 */
array get_sub_groups_recursive() {
  return get_members_recursive( CLASS_GROUP );
}

/**
 * Called when created to register the group in the database.
 *  
 * @param string name - register as name
 */
static void database_registration(string name)
{
    sGroupName = name;
    ASSERTINFO(MODULE_GROUPS->register(name, this()), 
	       "Registration of group " + name + " failed !");
    require_save(STORE_GROUP);
}

/**
 * Set the group's name.
 *  
 * @param string name - the new name of the group
 */
void set_group_name(string name)
{
    if ( CALLER != _Server->get_factory(CLASS_GROUP) )
	THROW("Invalid call to set_group_name !", E_ACCESS);
    sGroupName = name;
    string old_name = do_query_attribute( OBJ_NAME );
    mixed new_name = name / ".";
    new_name = new_name[ sizeof(new_name) - 1 ];
    object workroom = do_query_attribute(GROUP_WORKROOM);
    if ( objectp(workroom) ) {
        if ( workroom->query_attribute(OBJ_NAME) == old_name+"'s workarea" )
            workroom->set_attribute( OBJ_NAME, new_name + "'s workarea" );
        else
            workroom->update_path();
    }
    require_save(STORE_GROUP);
}

string get_name() 
{
  return get_identifier();
}

string get_steam_email() 
{
  return get_identifier() + "@" + _Server->get_server_name();
}

/**
 * Get the group's name.
 *
 * @return the name of the group
 */
string get_group_name()
{
    return sGroupName;
}

/**
 * The destructor of the group object. Removes all members for instance.
 *  
 * @see create
 */
static void 
delete_object()
{
  // let the factory delete the group, because it can do this with the
  // permissions of the group creator:
  get_factory( CLASS_GROUP )->delete_group( this() );
}

/**
 * This is an internal function that can only to be called by the group
 * factory. It recursively deletes the group.
 */
void low_delete_object()
{
  if ( !_Server->is_a_factory(CALLER) )
    steam_error("Illegal call to Group.low_delete_object !");

  object member;
  object obj;

  // delete subgroups:
  foreach ( get_sub_groups(), object grp ) {
    remove_member( grp );
    grp->delete();
  }
  // remove remaining members:
  foreach ( aoGroupMembers, member ) {
    member->leave_group( this() );
  }
  // remove from parents:
  foreach ( get_groups(), object grp ) {
    grp->remove_member( this() );
  }
  // delete workroom and calendar:
  obj = query_attribute( GROUP_WORKROOM );
  if ( objectp(obj) && !obj->delete() )
    werror( "Failed to delete group '%s' workroom (object id %d)\n",
            get_identifier(), obj->get_object_id() );
  obj = query_attribute( GROUP_CALENDAR );
  if ( objectp(obj) && !obj->delete() )
    werror( "Failed to delete group '%s' calendar (object id %d)\n",
            get_identifier(), obj->get_object_id() );
  
  MODULE_GROUPS->unregister_group( this() );
  __object::delete_object();
  __member::delete_object();
}

bool leave_group(object grp, void|object parent)
{
  return ::leave_group(grp);
}

bool join_group(object grp)
{
  // if the user is currently member of no group move the group
  int sz = sizeof(get_groups());
  bool result = ::join_group(grp);
  if ( sz==0 ) {
    oParent = grp;
    call(get_factory(CLASS_GROUP)->move_group, 0, this(), grp);
  }
  return result;
}


/**
 * Checks if the group features some special privileges.
 *  
 * @param permission - does the group feature this permission?
 * @return true or false
 * @see add_permission
 */
final bool
features(int permission, void|mixed ctx)
{
    if ( iGroupRoles & permission )
	return true;
    return groupRoles->check(permission, ctx);
}

/**
 * Returns an integer describing the special privileges of the group.
 *  
 * @return permissions of the group
 * @see add_permission
 */
final int
get_permission()
{
    return iGroupRoles;
}

/**
 * Add special privileges to the group.
 *  
 * @param permission - add the permission to roles of group
 * @see features
 */
final bool
add_permission(int permission)
{
    try_event(EVENT_GRP_ADD_PERMISSION, CALLER, permission);
    iGroupRoles |= permission;
    require_save(STORE_GROUP);
    run_event(EVENT_GRP_ADD_PERMISSION, CALLER, permission);
    return true;
}

/**
 * Set new default permissions for the group. These are role permissions
 * like read-everything,write-everything,etc. which is usually only
 * valid for the ADMIN gorup.
 *  
 * @param int permission - permission bit array.
 * @return true or throw and error.
 * @see get_permission
 */
final bool
set_permission(int permission)
{
    try_event(EVENT_GRP_ADD_PERMISSION, CALLER, permission);
    Role r = Role("general", permission, 0);
    groupRoles->add(r);
    iGroupRoles = permission;
    require_save(STORE_GROUP);
    run_event(EVENT_GRP_ADD_PERMISSION, CALLER, permission);
    return true;
}


final void add_role(Role r)
{
    try_event(EVENT_GRP_ADD_PERMISSION, CALLER, r);
    groupRoles->add(r);
    require_save(STORE_GROUP);
    run_event(EVENT_GRP_ADD_PERMISSION, CALLER, r);
}

final RoleList get_roles() 
{
  return groupRoles;
}

/**
 * Check if a given user is member of this group.
 *  
 * @param user - the user to check
 * @return true of false
 * @see add_member
 * @see remove_member
 */
final bool 
is_member(object user)
{
    for ( int i = sizeof(aoGroupMembers) - 1; i >= 0; i-- ) {
	if ( aoGroupMembers[i] == user )
	    return true;
    }
    return false;
}

/**
 * Check if a given user is member of this group or a subgroup
 *  
 * @param user - the user to check
 * @return true of false
 * @see add_member
 * @see remove_member
 */
final bool
is_virtual_member(object user)
{
  for ( int i = sizeof(aoGroupMembers) - 1; i >= 0; i-- ) {
    if ( aoGroupMembers[i] == user )
      return true;
    else if ( aoGroupMembers[i]->get_object_class() & CLASS_GROUP ) 
      if ( aoGroupMembers[i]->is_virtual_member(user) )
	return true;
  }
  return false;
}

final bool
is_virtual_parent(object group)
{
  if (!objectp(oParent))
    return false;

  if (oParent == group)
    return true;
  return oParent->is_virtual_parent(group);
}



/**
 * See if a user is admin of this group. It doesnt require
 * membership in the group.
 *  
 * @param user - the user to check for admin
 * @return true of false
 * @see is_member
 */
final bool 
is_admin(object user)
{
    if ( !objectp(user) )
	return false;
    ASSERTINFO(IS_PROXY(user), "User is not a proxy !");
    return (query_sanction(user)&GROUP_ADMIN_ACCESS) == GROUP_ADMIN_ACCESS;
}

/**
 * Get all admins of a group. Other groups might be admins of a group
 * too.
 *  
 * @return array of admin objects (Users)
 * @see is_admin
 */
final array(object) get_admins()
{
  array(object) admins = ({ });

  foreach( aoGroupMembers, object member) {
      if ( is_admin(member) ) {
	  if ( member->get_object_class() & CLASS_GROUP )
	      admins += member->get_admins();
	  admins += ({ member });
      }
  }
  return admins;
}


/**
 * Check a group password against a string passed.
 * @param string pass - the group password
 * @return 1 - ok, 0 - failed
 */
final bool
check_group_pw(string pass)
{
  return stringp(pass) && stringp(sGroupPW) && strlen(sGroupPW)!=0 && pass==sGroupPW;
}


/**
 * Checks whether the group is password protected.
 * @return 1 if the group has a password, 0 if it has no password
 */
final bool has_password () {
  return stringp(sGroupPW) && sizeof(sGroupPW) > 0;
}


/**
 * Add a new member to this group. Optionally a password can be 
 * passed to the function so the user joins with a password directly.
 *  
 * @param user - new member
 * @param string|void pass - the group password
 * @see remove_member
 * @see is_member
 * @return 1 - ok, 0 - failed, -1 pending, -2 pending failed
 */
final int 
add_member(object user, string|void pass)
{
    int    i;

    ASSERTINFO(IS_PROXY(user), "User is not a proxy !");
    // guest cannot be in any group 
    if ( user == _GUEST && this() != _WORLDUSER )
      steam_error("The guest user cannot be part of any group !");

    if ( is_member(user) || user == this() )
	return 0;

    object caller = CALLER;

    /* run the event
     * Pass right password to security...
     * The user may add himself to the group with the appropriate password.
     * Invited users may also join
     */
    try_event(EVENT_ADD_MEMBER, caller, user, 
	      (user == this_user() || geteuid() == user) &&
	      (search(aoInvites, user) >= 0 ||
	       (stringp(pass) && stringp(sGroupPW) && strlen(sGroupPW) != 0 && pass == sGroupPW)));
    
    // make sure there won't be any loops
    if ( _SECURITY->valid_group(user) ) {
	array(object)  grp;
	array(object) mems;

	grp = ({ user });
	i   = 0;
	while ( i < sizeof(grp) ) {
	    mems = grp[i]->get_members();
	    foreach(mems, object m) {
		LOG("Member:"+m->get_identifier()+"\n");
		if ( m == this() ) 
		    THROW("add_member() recursion detected !", 
			  E_ERROR|E_LOOP);
		if ( _SECURITY->valid_group(m) )
		    grp += ({ m });
	    }
	    i++;
	}
	// is this group virtually a parent - recursion possible
	if (is_virtual_parent(user)) {
	  steam_error("Cannot add a group that is a virtual parent of this group!");
	}
    }
    // kick user from all exclusive parent groups sub-groups of this group ;)
    foreach( get_groups(), object group) {
	// user joins a subgroup
	LOG("Group to check:" + group->get_identifier()+"\n");
	if ( group->query_attribute(GROUP_EXCLUSIVE_SUBGROUPS) == 1 ) {
	    foreach ( group->get_members(), object xgroup ) 
		if ( xgroup->get_object_class() & CLASS_GROUP &&
		     xgroup->is_member(user) )
		    xgroup->remove_member(user);
	}
    }
    int size = do_query_attribute(GROUP_MAXSIZE);
    if ( size == 0 ||
	 ( user->get_object_class() & CLASS_GROUP) || 
	 count_members() < size )
    {
        do_add_member(user);
        run_event(EVENT_ADD_MEMBER, CALLER, user);
        return 1;
    } 
    else
      return add_pending(user, pass);
}

static void do_add_member(object user) 
{
  if ( !user->join_group(this()) ) 
    steam_error("The user cannot join the group !");
  aoGroupMembers += ({ user });
  
  // remove membership request:
  remove_from_attribute(GROUP_MEMBERSHIP_REQS, user);
  
  if ( arrayp(aoInvites) )
    aoInvites -= ({ user });
  
  /* Users must be able to read the group for tell and say events */
  set_sanction(user, query_sanction(user)|SANCTION_READ);
  
  require_save(STORE_ACCESS);
  require_save(STORE_GROUP);
}

/**
 * Get the number of members (users only)
 *  
 * @return the number of member users of this group
 */
int count_members()
{
    int cnt = 0;
    foreach(aoGroupMembers, object member)
	if ( member->get_object_class() & CLASS_USER )
	    cnt++;
    return cnt;
}



/**
 * Add a request to become member to this group. That is the current
 * use will become member of the group.
 *  
 */
void
add_membership_request(void|object user)
{
  if ( !objectp(user) )
    user = this_user();
  if ( user == USER("guest") )
    steam_error("Cannot add guest user ...");
  do_append_attribute(GROUP_MEMBERSHIP_REQS, user);
}

/**
 * Check whether a given user requested membership for this group.
 *  
 * @param object user - the user to check
 * @return true or false
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool requested_membership(object user)
{
    return !arrayp(do_query_attribute(GROUP_MEMBERSHIP_REQS)) ||
        search(do_query_attribute(GROUP_MEMBERSHIP_REQS), user) >= 0;
}

/**
 * Remove a request for membership from the list of membership
 * requests of this group.
 *  
 * @param object user - remove the request of the user.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see add_membership_request
 */
void remove_membership_request(object user)
{
  if ( (user==this_user()) || (user==geteuid())
       || is_admin( this_user() ) || is_admin( geteuid() ) ) {
    remove_from_attribute(GROUP_MEMBERSHIP_REQS, user);
  }
}

/**
 * Get the array (copied) of membership requests for this group.
 *  
 * @return array of user objects requesting membership.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
array(object) get_requests()
{
    return copy_value(do_query_attribute(GROUP_MEMBERSHIP_REQS));
}


/**
 * Promote a user to group administration. The user does not need to be member.
 *  
 * @param object user - the new admin user of this group
 * @see is_admin
 */
void set_admin(object user)
{
  sanction_object(user, GROUP_ADMIN_ACCESS);
}

/**
 * Remove an administrator from the groups administration
 *  
 * @param object user - the admin user 
 * @see is_admin
 */
void remove_admin(object user)
{
    sanction_object(user, 0);
}

/**
 * allows free entry to this group (everyone can join)
 *
 * @param int entry - boolean value if users can join for free or not
 *  
 */
void set_free_entry(int entry)
{
  if ( entry )
    sanction_object(GROUP("everyone"), SANCTION_INSERT);
  else
    sanction_object(GROUP("everyone"), 0);
}



/**
 * Invite a user to join this group. If the current user has the
 * appropriate permissions the given user will be marked as invited
 * and may join for free.
 *  
 * @param object user - the user to invite.
 * @see is_invited
 */
void invite_user(object user)
{
  try_event(EVENT_ADD_MEMBER, CALLER, user, 0);
  if ( search(aoInvites, user) >= 0 )
    THROW("Failed to invite user - user already invited !", E_ERROR);
  aoInvites += ({ user });
  require_save(STORE_GROUP);
  run_event(EVENT_ADD_MEMBER, CALLER, user);
}

void remove_invite(object user)
{
  try_event(EVENT_REMOVE_MEMBER, CALLER, user);
  if ( search(aoInvites, user) == -1 )
    THROW("Failed to remove invitation for user - user not invited !", E_ERROR);
  aoInvites -= ({ user });
  require_save(STORE_GROUP);
  run_event(EVENT_REMOVE_MEMBER, CALLER, user);
}

/**
 * Check if a given user is invited to join this group.
 *  
 * @param object user - the user to check.
 * @return true of false.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see invite_user
 */
bool is_invited(object user)
{
    if ( !arrayp(aoInvites) )
        aoInvites = ({ });

    return search(aoInvites, user) >= 0;
}


/**
 * Get all invited users of this group.
 *  
 * @return array of invited users
 */
array(object) get_invited()
{
    return copy_value(aoInvites);
}

public void check_consistency() 
{
  bool consistent = true;

  foreach(aoGroupMembers, object o) {
    if (o->status() < 0 || o->status() == 3) {
      consistent = false;
      WARN("Found invalid member %O of group %O", o, this());
      break;
    }
  }
  if (!consistent) {
    array fixed_members = ({ });   
    foreach(aoGroupMembers, object o) {
      if (o->status() >= 0 && o->status() != 3) { 
	fixed_members += ({ o });
      }
    }
    aoGroupMembers = fixed_members;
    require_save(STORE_GROUP);
  }
}

/**
 * remove a member from the group.
 *  
 * @param user - the member to remove
 * @return if successfully
 * @author Thomas Bopp (astra@upb.de) 
 * @see add_member
 */
final bool 
remove_member(object user)
{
    LOG("remove_member");
    ASSERTINFO(!objectp(user) || IS_PROXY(user), "User is not a proxy !");

    check_consistency();
    if ( !is_member(user)  && !is_pending(user) )
	return false;

    if (is_pending(user))
    {
	LOG("is pending");
        remove_pending(user);
        require_save(STORE_GROUP);
    }
    else
    {
        LOG("actual member?");
        try_event(EVENT_REMOVE_MEMBER, CALLER, user);
        if ( !user->leave_group(this()) ) return false;
        set_sanction(user, 0);
        aoGroupMembers -= ({ user });
        //require_save(); // full save due to set_sanction
        require_save(STORE_USER);
        require_save(STORE_ACCESS);
        run_event(EVENT_REMOVE_MEMBER, CALLER, user);

        // try to fill group with first pending
        if (arrayp(aPending) && sizeof(aPending) > 0 ) 
        {
            catch {
                add_member(aPending[0][0], aPending[0][1]);
                string msg = do_query_attribute(GROUP_MSG_ACCEPT);
                if (!msg)
                    msg = "You have been accepted to group:"+
                        do_query_attribute(OBJ_NAME);
                aPending[0][0]->message(msg);
                aPending = aPending[1..];
                require_save(STORE_USER);
            };
        }
    }
    return true;
}


/**
 * Returns the groups members.
 *
 * @see get_members_recursive
 * @see get_sub_groups
 * @see get_sub_groups_recursive
 * @see add_member
 *
 * @param classes (optional) limit the result to the specified class (e.g.
 *   CLASS_USER or CLASS_GROUP)
 * @return the groups members
 *
 */
final array(object)
get_members(int|void classes)
{
    if ( classes != 0 ) {
	array(object) members = ({ });
	foreach(aoGroupMembers, object o) {
	    if ( o->get_object_class() & classes )
		members += ({ o });
	}
	return members;
    }
    return copy_value(aoGroupMembers);
}


/**
 * get the class of the object
 *  
 * @return the class of the object
 * @author Thomas Bopp (astra@upb.de) 
 */
int
get_object_class()
{
    return ::get_object_class() | CLASS_GROUP;
}

/**
 * Returns the members of the group and all subgroups (recursively).
 * If no parameter is specified, then this returns only users, not
 * sub group objects.
 *
 * @see get_members
 * @see get_sub_groups
 * @see get_sub_groups_recursive
 * @see add_member
 *
 * @param classes (optional) limit the result to the specified class (e.g.
 *   CLASS_USER or CLASS_GROUP), default: CLASS_USER
 * @return members of this group and all subgroups
 *
 */
array(object) get_members_recursive ( void|int classes ) {
    if ( zero_type(classes) ) classes = CLASS_USER;  // backwards compatibility
    array(object) result = ({ });
    foreach ( get_members(), object obj ) {
      if ( !objectp(obj) || obj->status() < 0 ) continue;  // only valid objs
      int obj_class = obj->get_object_class();
      if ( obj_class & classes )
        result |= ({ obj });
      if ( obj_class & CLASS_GROUP)
        result |= obj->get_members_recursive( classes );
    }
    return result;
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
 * Returns the group's emails, optionally filtered by object class,
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
 *   (if not specified, then the inbox of the group is used)
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
 * Returns the group's emails, optionally filtered, sorted and limited by
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
    return this(); // the group functions as mailbox
}


/**
 * Send an internal mail to all members of this group.
 * If the sending user has activated sent mail storage, then a copy of the
 * mail will be stored in her sent mail folder.
 *  
 * @param msg the message body (can be a plaintext or html string, a document
 *   or a mapping)
 * @param subject an optional subject
 * @param sender an optional sender mail address
 * @param mimetype optional mime type of the message body
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>
 */
final void mail(string|object|mapping msg, string|mapping|void subject, void|string sender, void|string mimetype)
{
  object user = geteuid() || this_user();
  if ( !objectp(user) ) user = _ROOT;
  if ( mappingp(subject) )
    subject = subject[do_query_attribute("language")||"english"];
  if ( objectp(msg) && !stringp(subject) )
    subject = msg->query_attribute( OBJ_DESC ) || msg->get_identifier();
  if ( !stringp(subject) ) 
    subject = "Message from " + user->get_identifier();
  if ( !stringp(mimetype) )
    mimetype = "text/html";

  object message;
  if ( objectp(msg) ) {
    message = msg;
    // OBJ_DESC is subject of messages
    string desc = msg->query_attribute(OBJ_DESC);
    if ( !stringp(desc) || desc == "" )
      msg->set_attribute(OBJ_DESC, msg->get_identifier());
  }
  else {
    object factory = _Server->get_factory(CLASS_DOCUMENT);
    message = factory->execute( ([ "name": replace(subject, "/", "_"),
                                   "mimetype": mimetype, 
                                   ]) );
    if ( mappingp(msg) )
      msg = msg[do_query_attribute("language")||"english"];
    message->set_attribute(OBJ_DESC, subject);
    if ( lower_case(mimetype) == "text/html" && stringp(msg) ) {
      // check whether <html> and <body> tags are missing:
      msg = Messaging.fix_html( msg );
    }
    message->set_content(msg);
  }
  message->set_attribute("mailto", this());
  message->sanction_object(this(), SANCTION_ALL);

  array(object) targets = get_members_recursive();
  string mailsetting = do_query_attribute(GROUP_MAIL_SETTINGS) || "open";
  if ( mailsetting == "closed" ) {
    if ( !is_member(geteuid() || this_user()) )
      steam_user_error("Group accepts only messages from members!");
  }
  mapping headers = get_module("forward")->create_list_headers( this() );
  object tmod = get_module("tasks");
  object sending_user = this_user();
  if ( !objectp(sending_user) ) sending_user = geteuid();
  if ( objectp(tmod) ) {
    Task.Task task = Task.Task(send_mail);
    task->params = ({ message, subject, sender, mimetype, targets, headers,
                      sending_user });
    tmod->run_task(task);
  }
  else {
    send_mail( message, subject, sender, mimetype, targets, headers,
               sending_user );
  }
}

static void
send_mail(string|object|mapping msg, string|mapping|void subject, void|string sender, void|string mimetype, array targets, mapping headers, object user)
{
  object mail_obj = do_send_mail( msg, subject, sender, mimetype, targets,
				  headers, user );
  if ( objectp(mail_obj) && objectp(user) && user->is_storing_sent_mail() &&
       objectp(user->get_sent_mail_folder()) ) {
    object mail_copy = mail_obj->duplicate();
    if ( objectp(mail_copy) ) {
      mail_copy->sanction_object( user, SANCTION_ALL );
      mail_copy->set_attribute( "mailto", this() );
      object old_euid = geteuid();
      mixed euid_err = catch(seteuid( user ));
      get_module( "table:read-documents" )->download_document( 0, mail_copy, UNDEFINED );  // mark as read
      foreach ( mail_copy->get_annotations(), object ann )
        get_module( "table:read-documents" )->download_document( 0, ann, UNDEFINED );  // mark as read
      if ( !euid_err ) seteuid( old_euid );
      user->get_sent_mail_folder()->add_annotation( mail_copy );
    }
  }
}

static object do_send_mail(string|object|mapping msg, string|mapping|void subject, void|string sender, void|string mimetype, array targets, mapping headers, object user)
{
  object msg_obj;
  array failed = ({ });
  foreach (targets, object member) {
    if ( !objectp(member) ) continue;
    mixed err = catch {
      mixed mailmsg;
      if ( objectp(msg) ) {
	mailmsg = msg->duplicate();
      }
      else
	mailmsg = msg;
      
      object tmp_msg_obj;
      if ( mappingp(headers) ) {
	tmp_msg_obj = member->do_mail(mailmsg, subject, sender, mimetype, headers);
      }
      else {
	tmp_msg_obj = member->do_mail(mailmsg, subject, sender, mimetype);
      }
      if ( !objectp(msg_obj) && objectp(tmp_msg_obj) )
        msg_obj = tmp_msg_obj;
    };
    if ( err ) {
      FATAL("Error while sending group mail to %O: %O\n%O", 
	    member,
	    err[0], err[1]);
      failed += ({ member->get_identifier() + "( " + member->get_name()+ " )" });
    }
  }
  // also notify the user about failed mailing
  if ( sizeof(failed) > 0 ) {
    if ( objectp(user) ) {
      user->do_mail(
       sprintf("Failed to send message '%O' to the following recipients:" + 
               failed * "<br />",
               subject),
       "Failed to send message", "postmaster", "text/html");
    }
  }

  // store message as annotation
  mixed err = catch {
    do_add_annotation(msg->duplicate());
  };
  if ( err ) {
    FATAL("Failed to store annotation on group: %O\n%O", err[0], err[1]);
  }


  return msg_obj;
}

/**
 * Set a new password for this group. A password is used to
 * allow users to join the group without waiting for someone to
 * accept their membership request.
 *  
 * @param string pw - the new group password.
 * @return true or false
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool set_group_password(string pw)
{
    if ( !_SECURITY->access_write(0, this(), CALLER) )
	THROW("Unauthorized call to set_group_password() !", E_ACCESS);
    LOG("set_group_password("+pw+")");
    sGroupPW = pw;
    require_save(STORE_GROUP);
    return true;
}

/**
 * get the data of the group for saving
 *  
 * @return array of group data
 * @author Thomas Bopp (astra@upb.de) 
 * @see restore_group_data
 */
mapping
retrieve_group_data()
{
  ASSERTINFO(CALLER == _Database,
	     "retrieve_group_data() must be called by database !");
  return ([
    "GroupMembers":aoGroupMembers, 
    "GroupRoles":iGroupRoles,
    "Groups": aoGroups,
    "GroupPassword": sGroupPW,
    "GroupInvites": aoInvites,
    "GroupName": sGroupName,
    "GroupPending": aPending,
    "Parent": oParent,
    "ExclusiveGroups": aoExclusiveGroups,
    "Roles": groupRoles->save(),
  ]);
}

/**
 * restore the data of the group: must be called by Database
 *  
 * @param data - the data to restore
 * @author Thomas Bopp (astra@upb.de) 
 * @see retrieve_group_data
 */
void
restore_group_data(mixed data)
{
  ASSERTINFO(CALLER == _Database, "Caller must be database !");
    
  aoGroupMembers    = data["GroupMembers"];
  iGroupRoles       = data["GroupRoles"];
  aoGroups          = data["Groups"];
  sGroupPW          = data["GroupPassword"];
  aoInvites         = data["GroupInvites"];
  sGroupName        = data["GroupName"];
  aPending          = data["GroupPending"];
  oParent           = data["Parent"];
  aoExclusiveGroups = data["ExclusiveGroups"];

  // loading the roles of this group
  // Role code is in libraries/Roles.pmod
  groupRoles = RoleList();
  if ( arrayp(data["Roles"]) )
    groupRoles->load(data->Roles);

  if ( !stringp(sGroupName) || sGroupName == "undefined" )
    sGroupName = get_identifier();
  if ( arrayp(aoGroupMembers) ) 
    aoGroupMembers -= ({ 0 });
}

/**
 * send a message to the group - will only call the SAY_EVENT
 *  
 * @param msg - the message to send
 */
void message(string msg)
{
  try_event(EVENT_SAY, CALLER, msg);
  run_event(EVENT_SAY, CALLER, msg);
}

/**
 * add a user to the pending list, the pendnig list is a list of users
 * waiting for acceptance due to the groups size exceeding the GROUP_MAXSIZE
 *
 * @param user - the user to add
 * @param pass - optional password to pass to add_member
 * @see add_member
 */
final static bool
add_pending(object user, string|void pass)
{
    int iSizePending;
    if ( is_member(user) || is_pending(user) || user == this() )
        return false;

    if (!iSizePending ||(iSizePending > sizeof(aPending)))
    {
        aPending += ({ ({ user, pass }) });
        require_save(STORE_USER);
        return -1;
    }
    return -2;
}

/*
 * check if a user is already waiting for acceptance on the pending list
 * @param user - the user to check for
 * @see add_pending
 * @see add_member
 */
final bool
is_pending(object user)
{
    if ( arrayp(aPending) ) {
	foreach( aPending, mixed pend_arr )
	    if ( arrayp(pend_arr) && sizeof(pend_arr) >= 2 )
		if ( pend_arr[0] == user )
		    return true;
    }
    return false;
}

final bool
remove_pending(object user)
{
    if (arrayp(aPending))
    {
        mixed res;
        res = map(aPending, lambda(mixed a)
                                { return a[0]->get_object_id();} );
        if (res)
        {
            int p = search(res, user->get_object_id());
            if (p!=-1)
            {
                aPending[p]=0;
                aPending -= ({0});
                require_save(STORE_USER);
                return true;
            }
        }
    }
}

/*
 * get the list of users waiting to be accepted to the group, in case the
 * maximum group size is limited.
 * @return - (array)object (the users)
 * @author Ludger Merkens (balduin@upb.de)
 *
 */
final array(object) get_pending()
{
    return map(aPending, lambda(mixed a) { return a[0];} );
}


/*
 * add a group to the mutual list, A user may be only member to one
 * group of this list. Aquiring membership in one of theese groups will
 * automatically remove the user from all other groups of this list.
 * @param group - the group to add to the cluster
 */
final bool add_to_mutual_list(object group)
{
    try_event(EVENT_GRP_ADDMUTUAL, CALLER, group);

    foreach(aoExclusiveGroups, object g)
        g->low_add_to_mutual_list(group);

    group->low_add_to_mutual_list( aoExclusiveGroups +({this_object()}));
    aoExclusiveGroups |= ({ group });

    require_save(STORE_GROUP);
}

/*
 * this function will be called from other groups to indicate, this
 * group isn't required to inform other groups about this addition.
 * To add a group to the cluster call add_to_mutual_list
 * @param group - the group beeing informed
 */
final bool low_add_to_mutual_list(array(object) group)
{
    ASSERTINFO(_SECURITY && _SECURITY->valid_group(CALLER),
               "low_add_to_mutal was called from non group object");
    //    try_event(EVENT_GRP_ADDMUTUAL, CALLER, group);
    //    this is not necessary since SECURITY knows about clusters
    aoExclusiveGroups |= group;
    require_save(STORE_GROUP);
}


/*
 * get the list of groups connected in a mutual exclusive list
 * @return an array of group objects
 */
final array(object) get_mutual_list()
{
    return copy_value(aoExclusiveGroups);
}

string get_identifier()
{
    if ( stringp(sGroupName) && strlen(sGroupName) > 0 )
	return sGroupName;
    return query_attribute(OBJ_NAME);
}

string parent_and_group_name()
{
    if ( objectp(get_parent()) )
	return get_parent()->query_attribute(OBJ_NAME) + "." + 
	    do_query_attribute(OBJ_NAME);
    return do_query_attribute(OBJ_NAME);
}
    
bool query_join_everyone()
{
    return ((query_sanction(_WORLDUSER) & (SANCTION_READ|SANCTION_INSERT)) ==
	    (SANCTION_READ|SANCTION_INSERT));
}

function get_function(string func)
{
  object caller = CALLER;
  if ( caller != _Database && !_Server->is_a_factory(caller->this()) )
    THROW( sprintf("Only database is allowed to get function pointer.\nNOT %O\n%O",
		   caller, backtrace()), E_ACCESS);
  if ( func == "do_add_member" )
    return do_add_member;
  return ::get_function(func);
}
