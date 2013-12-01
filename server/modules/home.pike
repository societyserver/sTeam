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
 * $Id: home.pike,v 1.2 2008/04/18 10:02:46 exodusd Exp $
 */

constant cvs_version="$Id: home.pike,v 1.2 2008/04/18 10:02:46 exodusd Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <configure.h>

static bool mount_users = true;
static bool mount_groups = true;

//! The home module must be located in the root-room and resolves
//! any user or group name parsed and gets the appropriate workarea
//! for it. Queried users/groups can be seen in this modules inventory
//! afterwards. This way emacs and other tools may be able to resolve
//! path, even though actually no object is really places in this container.


class GroupWrapper {
    object grp, home;
    void create(object g, object h) { 

      if ( !IS_PROXY(g) ) 
	THROW("GroupWrapper: Group is no proxy !", E_ERROR);
      if ( !objectp(h) ) {
          THROW("Group "+g->get_group_name() + " missing workroom!", E_ERROR);
      }
      if ( !IS_PROXY(h) ) 
	THROW("GroupWrapper: Home is no proxy !", E_ERROR);
      grp = g; home = h; 
    }
    string get_identifier() { return grp->get_identifier(); }
    int get_object_class() { return CLASS_ROOM|CLASS_CONTAINER; }
    object this() { return this_object(); }
    int status() { if ( !objectp(home) ) return 3; return home->status(); }
    int get_object_id() { return home->get_object_id(); }

    final mixed `->(string func) 
    {
	if ( func == "get_identifier" )
	    return get_identifier;
	else if ( func == "create" )
	    return create;
	else if ( func == "get_object_class" )
	    return get_object_class;
	else if ( func == "status" )
	  return status;
	else if ( func == "get_object_id" )
	  return get_object_id;

	return home->get_object()[func];
    }
};


static mapping directoryCache = ([ ]);

string get_identifier() { return "home"; }
static void update_identifier(string name) {};

int get_object_class()  
{ 
    return ::get_object_class() | CLASS_CONTAINER | CLASS_ROOM;
}


bool insert_obj(object obj) 
{ 
    return true; //THROW("No Insert in home !", E_ACCESS); 
}

bool remove_obj(object obj) 
{ 
    return true; // THROW("No Remove in home !", E_ACCESS); 
}

/** Checks whether a user can be mounted. If user mounting is switched off
 * in the config, then only system users ("restricted" users) will be mounted.
 * @param identifier identifier of the user to check
 * @return true if the user can be mounted, false if not
 */
bool can_mount_user ( string identifier ) {
  if ( mount_users ) return true;
  if ( _Persistence->user_restricted( identifier ) ) return true;
  return false;
}

/** Checks whether a group can be mounted. If group mounting is switched off
 * in the config, then only system groups ("restricted" groups) will be
 * mounted.
 * @param identifier identifier of the group to check
 * @return true if the group can be mounted, false if not
 */
bool can_mount_group ( string identifier ) {
  if ( mount_groups ) return true;
  if ( _Persistence->group_restricted( identifier ) ) return true;
  return false;
}

array(object) get_inventory() 
{
  array(object) groups = this_user()->get_groups();
  foreach(groups, object grp) {
    string id = grp->get_identifier();
    if ( !can_mount_group(id) ) 
      continue;
    if ( !directoryCache[id] ) {
      mixed err = catch {
        directoryCache[id] = GroupWrapper(grp, 
                                          grp->query_attribute(GROUP_WORKROOM));
      };
      if (err) {
        FATAL("Failed to mount GROUP in home-Module: %O\n%O\n%O", 
              grp, err[0], err[1]);
      }
    }
  }
  if ( can_mount_user(this_user()->get_identifier()) )
    mount( this_user() );
  return values(directoryCache); 
}

array(object) get_inventory_by_class(int cl) 
{
  if ( can_mount_user(this_user()->get_identifier()) )
    mount( this_user() );

  if ( cl & CLASS_GROUP )
    return values(directoryCache);
  else if ( cl & CLASS_ROOM )
    return values(directoryCache);
  return ({ });
}

array(object) get_users()
{
  return ({ });
}

/*
 * Get the object by its name. This function is overloaded to allow
 * the /home syntax to all directories, without having the workrooms
 * environments point there. This means the Container is actually empty,
 * but you can do cd /home/user and get somewhere.
 *  
 * @param string obj_name - the object to resolve
 * @return the object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object get_object_byname(string obj_name)
{
    object obj, res;

    LOG("Getting "+ obj_name);
    if ( objectp(directoryCache[obj_name]) ) {
      if ( directoryCache[obj_name]->status() >= 0 &&
	   directoryCache[obj_name]->status() != PSTAT_DELETED )
        return directoryCache[obj_name];
      else
        m_delete(directoryCache, obj_name);
    }
    
    obj = MODULE_GROUPS->lookup(obj_name);
    if ( objectp(obj) && can_mount_group(obj_name) ) {
	LOG("Found group - returning workroom !");
	res = obj->query_attribute(GROUP_WORKROOM);
    }
    else {
	obj = MODULE_USERS->lookup(obj_name);
	if ( objectp(obj) && can_mount_user(obj_name) ) {
          if ( obj->status() >= 0 )
	    res = obj->query_attribute(USER_WORKROOM);
	}
    }
    if ( objectp(res) )
	directoryCache[obj_name] = GroupWrapper(obj, res);

    return directoryCache[obj_name];
}

object mount(object grp)
{
  object wr;
  
  string name = grp->get_identifier();

  if ( objectp(directoryCache[name]) )
    return directoryCache[name]->home;
			      
  if ( grp->get_object_class() & CLASS_GROUP ) {
    if ( ! can_mount_group(name) )
      return UNDEFINED;
    wr = grp->query_attribute(GROUP_WORKROOM);
  }
  else if ( grp->get_object_class() & CLASS_USER ) {
    if ( ! can_mount_user(name) )
      return UNDEFINED;
    wr = grp->query_attribute(USER_WORKROOM);
  }
  else
    return UNDEFINED;

  directoryCache[name] = GroupWrapper(grp, wr);

  return wr;
}

void unmount ( object grp )
{
  // allow unmounting only for group and user factory and for admins:
  if ( CALLER != get_factory(CLASS_GROUP) &&
       CALLER != get_factory(CLASS_USER) &&
       ! _ADMIN->is_member( this_user() ) )
    steam_error("Invalid caller for unmount: %O !", CALLER);

  string name = grp->get_identifier();
  if ( !objectp( directoryCache[ name ] ) )
    return;
  m_delete( directoryCache, name );
}

int is_mounted ( object grp )
{
  string name = grp->get_identifier();
  return objectp( directoryCache[ name ] );
}

string contains_virtual(object obj)
{
    object creatorGroup = obj->get_creator();
    string id = creatorGroup->get_identifier();
    if ( creatorGroup->get_object_class() & CLASS_GROUP ) {
      if ( ! can_mount_group(id) )
        return UNDEFINED;
      return id;
    }
    else if ( creatorGroup->get_object_class() & CLASS_USER ) {
      if ( ! can_mount_user(id) )
        return UNDEFINED;
      if ( creatorGroup->query_attribute(USER_WORKROOM) == obj )
        return creatorGroup->get_user_name();
    }
    return UNDEFINED;
}

void add_paths() 
{
    get_module("filepath:url")->add_virtual_path("/home/", this());
}

/**
 * Called after the object is loaded. Move the object to the workroom !
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void load_module()
{ 
    if ( MODULE_OBJECTS && objectp(_ROOTROOM) && oEnvironment != _ROOTROOM ) {
	set_attribute(OBJ_NAME, "home");
	move(_ROOTROOM); 
    }
    call(add_paths, 0);

    // load config mapping only locally to conserve memory:
    mapping config = Config.read_config_file( _Server.get_config_dir()+"/modules/home.cfg", "home" );
    mount_users = !Config.bool_value( config["dont_mount_users"] );
    if ( !mount_users ) MESSAGE( "home: not mounting users" );
    mount_groups = !Config.bool_value( config["dont_mount_groups"] );
    if ( !mount_groups ) MESSAGE( "home: not mounting groups" );
}

/**
 * Get the content size of this object which does not make really
 * sense for containers.
 *  
 * @return the content size: -2 as the container can be seen as an inventory
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see stat
 */
int get_content_size()
{
    return -2;
}

/**
 * This function returns the stat() of this object. This has the 
 * same format as statting a file.
 *  
 * @return status array as in file_stat()
 * @author Thomas Bopp (astra@upb.de) 
 * @see get_content_size
 */
array(int) stat()
{
    int creator_id = objectp(get_creator())?get_creator()->get_object_id():0;
    

    return ({ 16877, get_content_size(), time(), time(), time(),
		  creator_id, creator_id, "httpd/unix-directory" });
}
