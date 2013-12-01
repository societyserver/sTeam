/* Copyright (C) 2000-2007  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: filepath.pike,v 1.3 2010/08/20 20:42:25 astra Exp $
 */

constant cvs_version="$Id: filepath.pike,v 1.3 2010/08/20 20:42:25 astra Exp $";

inherit "/kernel/module";
inherit "/kernel/orb";

#include <macros.h>
#include <assert.h>
#include <database.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <attributes.h>

//#define FILEPATH_DEBUG

#ifdef FILEPATH_DEBUG
#define DEBUG_FILEPATH(s,args...) werror(s+"\n",args)
#else
#define DEBUG_FILEPATH(s,args...) 
#endif

#define MODE_ANNOTATE 1
#define MODE_VERSION  2

//! This module represents an ORB which converts a given pathname to
//! an sTeam object by using the structure of environment/inventory or
//! vice versa.
//!
//! There are several different trees with the 
//! roots "/", "~user" or "/home/user".

static object db_handle;
static mapping mPathCache = ([ ]);

/**
 * Initialize the module. This time only the description attributes is set.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void init_module()
{
    set_attribute(OBJ_DESC,"This is the filepath object for simulating "+
	"a filepath in steam. It works by traversing through rooms in rooms/"+
	"containers in containers starting from the Users "+
		  "and Groups workrooms");
}

void post_load_module() {
  db_handle = _Database->get_db_handle();
}

/**
 * Convert a given path to ~ syntax to retrieve a user or a workarea.
 *  
 * @param string path - the path to convert.
 * @return user or workarea object or 0.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object get_tilde(string path)
{
    string user;
    object  uid;

    DEBUG_FILEPATH("get_tilde("+path+")");
    if ( sscanf(path, "~%ss workroom", user) > 0 ) 
    {
	object workroom;
	
	uid = MODULE_USERS->lookup(user);
	if ( !objectp(uid) ) {
	    uid = MODULE_GROUPS->lookup(user);
	    if ( !objectp(uid) )
		return 0;
	    workroom = uid->query_attribute(GROUP_WORKROOM);
	}
	else {
	    workroom = uid->query_attribute(USER_WORKROOM);
	}
	DEBUG_FILEPATH("Returning workroom="+workroom->get_object_id());
	return workroom;
    }
    else if ( sscanf(path, "~%s", user) > 0 ) 
    {
	// object is the user
	uid = MODULE_USERS->lookup(user);
	if ( !objectp(uid) ) 
	    uid = MODULE_GROUPS->lookup(user);
	return uid;
    }
    return 0;
}

object get_annotation_on_obj(object obj, string name)
{
  return obj->get_annotation_byid(name);
}

object get_version_of_obj(object obj, string name)
{
}

/**
 * get_object_in_cont
 *  
 * @param cont - the container
 * @param obj_name - path to object name (only one token: container or object)
 * @return the appropriate object in the container
 * @author Thomas Bopp 
 * @see 
 */
object
get_object_in_cont(object cont, string obj_name)
{
    object        obj;

    DEBUG_FILEPATH("get_object_in_cont("+cont->get_identifier()+","+
		   obj_name+")");

    if ( !objectp(cont) )
	return 0;
    if ( strlen(obj_name) > 0 && obj_name[0] == '~' )
	return get_tilde(obj_name);

    obj = cont->get_object_byname(obj_name);
    return obj;
}

/**
 * Get an array of objects which represent the environment of the environment
 * (and so on) of the given object. 
 *  
 * @param object obj - the object to retrieve the environment hierarchy for.
 * @return array of objects which represent the path to environment = null.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
array(object) object_to_environment_path(object obj)
{
    array(object) objects = ({ });
    
    object current = obj;
    object env = obj->get_environment();
    while ( objectp(env) ) {
      DEBUG_FILEPATH("object_to_environment_path: " + obj->query_attribute(OBJ_NAME));
	objects = ({ env }) + objects;
	current = env;
	env = current->get_environment();
    }
    // check root object if it is a workroom
    if (  stringp(check_tilde(current)) ) 
	objects = ({ _Server->get_module("home") }) + objects;

    return objects;
}

/**
 * resolves a given path, by starting with container uid and
 * traversing through the tree to find the appropriate object
 *  
 * @param uid - the user logged in (for ~ syntax) or null
 * @param path - path to an object
 * @return the object
 * @see object_to_path
 * @see path_to_object
 */
object resolve_path(string|object env, string path, void|int rs_links)
{
  object      obj;
  int     i, mode;
  
  if (!objectp(env) && !stringp(env)) {
    env = MODULE_OBJECTS->lookup("rootroom");
    if ( !objectp(env) ) {
      FATAL("Root-Room is null on resolve_path()...");
      return 0;
    }
  } 
  else if (objectp(env)) {
    path = Stdio.append_path(object_to_filename(env), path);
  }
  else if (stringp(env)) {
    path = Stdio.append_path(env, path);
  }

  if ( !stringp(path) || strlen(path) == 0 || path == "/" ) {
    if (objectp(env)) {
      return env;
    }
    return path_to_object(env);
  }
  
  if ( path[0] != '/' )
    path = "/" + path;
  if ( path[-1] == '/' ) 
    path = path[..strlen(path)-2];
  
  if (objectp(db_handle)) {
    mixed err = catch {
      string query = "select ob_id from ob_data where ob_attr='OBJ_PATH' and ob_data='\""+db_handle->quote(path)+"\"'";
      Sql.sql_result res = db_handle->big_query(query);
      if (objectp(res) && res->num_rows() == 1) {
        mixed row = res->fetch_row();
        return find_object((int)row[0]);
      }
    };
    if (err) {
      FATAL("Error while resolving path: %O\n%O", err[0], err[1]);
    }
  }
  path = Stdio.append_path(path, "");

  if (!objectp(env)) 
    env = path_to_object(env);
  
  obj = env;
  array tokens = path / "/";
  for ( mode = 0, i = 1; i < sizeof(tokens); i++ ) {
    string token = tokens[i];
    if (!objectp(env) ) return 0;
    switch(mode) {
    case MODE_ANNOTATE:
      env = get_annotation_on_obj(env, token);
      break;
    case MODE_VERSION:
      env = get_version_of_obj(env, token);
      break;
    default:
      env = get_object_in_cont(env, token);
    }
    if ( objectp(env) ) {
      // if links should be resolved...
      if ( rs_links ) {
	if ( env->get_object_class() & CLASS_EXIT )
	  env = env->get_exit();
	else if ( env->get_object_class() & CLASS_LINK ) 
	  env = env->get_link_object();
      }
      obj = env;
    }
    else if ( token == "annotations" ) {
      mode = MODE_ANNOTATE;
      env = obj; // fall back to object in annotate mode!
    }
    else if ( token == "versions" ) {
      mode = MODE_VERSION;
      env = obj;
    }
  }
  return obj->this();
}

/**
 * Resolve a path. The ~ syntax will be converted to user/path.
 * additionally the __oid syntax is understood by this function.
 *  
 * @param path - the path to convert to an object
 * @return the resolved object or 0
 * @author Thomas Bopp (astra@upb.de) 
 * @see resolve_path
 */
object path_to_object(string path, void|bool rs_links)
{
    object         obj;

    if ( !stringp(path) || strlen(path) == 0 )
	return 0;

    obj = mPathCache[path];
    if (objectp(obj) && obj->status()>=0 && obj->status() != PSTAT_DELETED) {
      if (!stringp(obj->query_attribute(OBJ_PATH)) || obj->query_attribute(OBJ_PATH) == path) {
	if (rs_links) {
          if (objectp(obj)) {
            if (obj->get_object_class() & CLASS_LINK)
              obj = obj->get_link_object();
            else if (obj->get_object_class() & CLASS_EXIT)
              obj = obj->get_exit();
          }
	}
        return obj;
      }
      m_delete(mPathCache, obj);
    }

    DEBUG_FILEPATH("path_to_object("+path+")");
    if ( strlen(path) > 0 && path[0] != '/' && !IS_SOCKET(CALLER) ) {
	obj = resolve_path(CALLER->get_environment(), path, rs_links);
    }
    else {
      obj = resolve_path(0, path, rs_links);
    }
    mPathCache[path] = obj;
    return obj;
}

/**
 * Check if a given object is a groups workarea or a user workroom 
 * and return the appropriate path.
 *  
 * @param object obj - the object to check.
 * @return tilde path or "" or 0.
 */
string|int check_tilde(object obj)
{
    object creator, workroom;

    if ( obj->get_object_class() & CLASS_ROOM ) {
	if ( obj == _ROOTROOM )
	    return "";
	foreach ( indices(mVirtualPath), object module ) {
	    string vpath = module->contains_virtual(obj);
	    if ( stringp(vpath) )
		return mVirtualPath[module] + vpath;
	}
	
	object owner = obj->query_attribute(OBJ_OWNER);
	if ( objectp(owner) ) 
	    creator = owner;
	else
	    creator = obj->get_creator();
	
	if ( objectp(creator) ) {
	  if ( creator->get_object_class() & CLASS_USER )
	    workroom = creator->query_attribute(USER_WORKROOM);
	  else 
	    workroom = creator->query_attribute(GROUP_WORKROOM);
	}

	if ( objectp(workroom) && workroom->this() == obj->this() ) {
	  if ( creator->get_object_class() & CLASS_USER )
	    return "/home/"+creator->get_user_name();
	  else
	    return "/home/"+creator->get_identifier();
	}
    } 
    else if ( obj->get_object_class() & CLASS_USER ) {
	return "/~"+obj->get_user_name();
    }
    
    return 0;
}

string annotation_object_to_path(object obj)
{
  object annotated;
  string path = "/";
  string name = obj->get_object_id();

  object ann = obj->get_annotating();
  if (objectp(ann) ) {
    annotated = ann;
    ann = ann->get_annotating();
  }
  while ( objectp(ann) ) {
    path = "/" + name + path;
    name = ann->get_object_id();
    annotated = ann;
    ann = ann->get_annotating();
  }
  if ( !objectp(annotated) )
    return "/void/" + obj->get_object_id();
  return object_to_filename(annotated) + "/annotations" + path;
}

string calendar_object_to_path(object obj)
{
  return "/calendar/";
}

string version_object_to_path(object obj)
{
  object version = obj->query_attribute(OBJ_VERSIONOF);
  if (objectp(version->query_attribute(OBJ_VERSIONOF)))
      return "/versionmismatch/"+ version->get_object_id() + "/";
  return object_to_filename(version) + "/versions/";
}

/**
 * return the path equivalent to an object
 *  
 * @param obj - the object
 * @return converts the object to a path description
 * @author Thomas Bopp 
 * @see path_to_object
 */
string
object_to_path(object obj)
{
    object env, last_env;
    string          path;
    mixed           name;
    string      workroom;
	

    if ( !objectp(obj) )
	return "";

    if (obj == _ROOTROOM)
      return "/";
    
    /* traverse through the tree beginning with the object itself
     * and following the environment structure */
    env  = obj->get_environment();
    last_env = env;
    if ( last_env == _ROOTROOM )
        return "/";
    else if ( objectp(env) )
	env = env->get_environment();
    else if ( objectp(obj->get_annotating()) )
        return annotation_object_to_path(obj);
    else if ( obj->get_object_class() & CLASS_CALENDAR ) 
      return calendar_object_to_path(obj);
    else if ( objectp(obj->query_attribute(OBJ_VERSIONOF)) )
        return version_object_to_path(obj);
    else 
	return "/void/";

    if ( stringp(workroom=check_tilde(last_env)) ) 
        return workroom + "/";

    path = "/";

    while ( objectp(env) ) {
	name = last_env->get_identifier();
	
	path = "/" + name + path;
	last_env = env;
	if ( stringp(workroom=check_tilde(env)) ) {
	    return workroom + path;
	}
	env = env->get_environment();
    }
    string tilde = check_tilde(last_env);
    if ( !stringp(tilde) ) {
	if ( last_env == _ROOTROOM )
	    return path;
	return "/void/";
    }
    return tilde + path;
}

string object_to_identifier(object obj)
{
  if (obj->get_object_class() & CLASS_CALENDAR) {
    object creator = obj->get_creator();
    if ( objectp(creator) )
      return creator->get_identifier();
  }
  if (objectp(obj->get_environment()))
    return obj->get_identifier();
  return obj->get_object_id();
}

/**
 * Return the whole path, including the filename, for the given object.
 *  
 * @param obj - the object to get the filename
 * @return the filename
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string object_to_filename(object obj, void|int force)
{
    if ( !objectp(obj) )
	steam_error("Cannot resolve filename for non-object !");
    
    if ( objectp(_ROOTROOM) && obj->this() == _ROOTROOM->this() )
	return "/";

    if ( !force ) {
      string path = obj->query_attribute(OBJ_PATH);
      if ( stringp(path) && strlen(path) > 0 )
        return path;
    }

    string workroom;
    if ( stringp(workroom=check_tilde(obj)) )
        return workroom;
    return object_to_path(obj) + object_to_identifier(obj);
}

/**
 * Get the Container or Room a given url-object is located.
 *  
 * @param string url - the url to find the objects environment.
 * @return the environment.
 * @author Thomas Bopp (astra@upb.de) 
 */
object
path_to_environment(string url)
{
    int i;

    i = strlen(url) - 1;
    while ( i > 0 && url[i] != '/' ) i--;
    if ( i == 0 ) return _ROOTROOM;
    return path_to_object(url[..i]);
}

string get_identifier() { return "filepath:tree"; }

/**
 * Check whether the current user is able to read the given file.
 *  
 * @param string file - the file to check.
 * @return 0 or 1.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int check_access(string file)
{
    object obj;
    obj = path_to_object(file);
    if ( objectp(obj) ) {
	mixed err = catch { 
	    _SECURITY->access_read(0, obj, this_user());
	};
	if ( arrayp(err) ) return 0;
	DEBUG_FILEPATH("Access ok !");
	return 1;
    }
    return 0;
}


