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
 * $Id: orb_url.pike,v 1.4 2010/08/20 20:42:25 astra Exp $
 */

constant cvs_version="$Id: orb_url.pike,v 1.4 2010/08/20 20:42:25 astra Exp $";

inherit "/kernel/secure_mapping";
inherit "/kernel/orb";

#include <macros.h>
#include <attributes.h>
#include <exception.h>
#include <types.h>
#include <classes.h>
#include <events.h>
#include <database.h>

#ifdef URL_DEBUG
#define DEBUG_URL(s, args...) werror("[orb:url] "+s+"\n", args)
#else
#define DEBUG_URL(s, args...)
#endif

static mapping mPathCache = ([ ]);
static mapping newPathCache = ([ ]);

/**
 * overwrites secure_mapping.list to provide additional information
 * @author Daniel Buese
 */
mixed list() {
  mixed result= ::list();
  object filepath = _Server->get_module("filepath:tree");

  if (arrayp(result)) {
    string newresult = "";
    object obj;
    foreach(result, string url) {
      if (stringp(url)) {
        obj = path_to_object(url);
	if ( objectp(obj) ) {
	  url = httplib.replace_uml(url);
	  newresult += "<site><url><![CDATA["+url+"]]><\/url>";
	  newresult += "<id>"+obj->get_object_id()+"<\/id>";
          if (objectp(filepath)) {
	    string path = filepath->object_to_filename(obj);
	    path = httplib.replace_uml(path);
	    newresult += "<path><![CDATA["+path+"]]><\/path>";
	  }
	  newresult += "<\/site>";
	}
      }
    }
    result = newresult;
  }
  return result;
}

mixed list_raw() 
{
  mapping result = ([]);
  foreach (::list();; mixed key)
  {
    result[key] = get_value(key);
  }
  return result;
}

void clean_list()
{
  foreach (::list();; mixed key)
  { 
    if (!get_value(key) && (string)(int)key != key)
    delete(key);
  }
}

/**
 * Conversion function.
 *  
 * @param object obj - the object to convert.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void convert_url(object obj)
{
    if ( obj->this() == this )
	return;
    mixed old_value = obj->query_attribute(OBJ_URL);
    obj->set_acquire_attribute(OBJ_URL,this());
    if ( stringp(old_value) )
	obj->set_attribute(OBJ_URL, old_value);
}

/**
 * Callback function when the module is installed. Registers
 * the 'url' attribute in the object factory.
 *  
 */
void create_module()
{
  set_value("/", get_object_id());
}

private static void low_set_url(object obj, string val) 
{
  int           id;

  if ( stringp(val) ) 
    id = get_value(val);
  if ( id > 0 ) 
    set_value(id, 0);

  string url = get_value(obj->get_object_id());
  if ( stringp(url) )
  {
    set_value(url, 0);
    if (!val)
    {
      werror("obj_url.pike: deleting %O -> %O\n", url, obj); 
      delete(url);
    }
  }
  
  if ( stringp(val) )
    set_value(val, obj->get_object_id());
  set_value(obj->get_object_id(), val);
  if (stringp(url) && strlen(url)>0) {
    m_delete(mPathCache, url);
    if (url[-1] != '/')
      m_delete(mPathCache, url+"/");
    else
      m_delete(mPathCache, dirname(url));
  }
  if (stringp(val) && strlen(val)>0) {
    m_delete(mPathCache, val);
    if (val[-1] != '/')
      m_delete(mPathCache, val+"/");
    else
      m_delete(mPathCache, dirname(val));
  }
}

void update_url(object obj) 
{
  string url = obj->query_attribute(OBJ_URL);
  low_set_url(obj, url);
}

/**
 * The 'url' attribute is acquired from this module and all url change
 * calls on objects will end up here.
 *  
 * @param string|int key - attribute to change, should be 'url'.
 * @param mixed val - new value of 'url' attribute.
 * @return true or new value.
 * @see query_attribute
 */
mixed set_attribute(string|int key, mixed val)
{
    int                      id;

    if ( key == "url" )
	FATAL("Old URL syntax detected - skipping !");
    else if ( key == OBJ_URL && CALLER->this() != this() ) {
      object obj = CALLER->this();
      if ( stringp(val) ) {
	int id = get_value(val);
	if ( id>0 ) {
	  object urlObject = find_object(id);
	  if ( objectp(urlObject) && 
	       urlObject != obj && 
	       urlObject != this() &&
	       urlObject->status() >= 0 && 
	       urlObject->status() != PSTAT_DELETED) 
	  {
	    steam_error("Trying to set URL to conflicting value(%s) for %O,"+
			"taken by %O (%s)",
			val,
			obj->get_object(),
			urlObject->get_object(),
			_FILEPATH->object_to_filename(urlObject));
	  }
	}
      }
      if ( val == "none" || val == "" )
	val = 0;
      low_set_url(obj, val);
      return true;
    }
    else {
	return ::set_attribute(key, val);
    }
}
    
/**
 * Query an attribute, but should be 'url' in general for
 * other objects whose acquiring end up here.
 *  
 * @param string|int key - attribute to query.
 * @return value for url in database or this modules attribute value.
 * @author Thomas Bopp (astra@upb.de) 
 * @see set_attribute
 */
mixed query_attribute(string|int key)
{ 
    if ( key == OBJ_URL ) {
	object obj = CALLER->this();
	return get_value(obj->get_object_id());
    }
    return ::query_attribute(key);
}

/**
 * Get the acquired attribute. No URL to get no loops.
 *  
 * @param string|int key - the key of the attribute.
 * @return the acquire object or function.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
mixed get_acquire_attribute(string|int key)
{
    if ( key == OBJ_URL )
	return 0;
    return ::get_acquire_attribute(key);
}

void set_acquire_attribute(string|int key, mixed val)
{
    if ( key == OBJ_URL )
	return;
    ::set_acquire_attribute(key, val);
}

/**
 * Resolve a path with the url module by getting the saved value for
 * 'path' and returning the appropriate object.
 *  
 * @param object uid - the uid for compatibility with orb:filepath
 * @param string path - the path to resolve.
 * @return the saved object value for 'path'.
 * @author Thomas Bopp (astra@upb.de) 
 */
object
resolve_path(object|string uid, string path)
{
  if ( !objectp(uid) && !stringp(uid)) 
    return path_to_object(path);
  string prefix;
  if (objectp(uid)) {
    prefix = object_to_filename(uid);
  }
  else {
    prefix = uid;
  }
  array tokens = path / "/";
  object obj = uid;

  foreach(tokens, string t) {
    obj = obj->get_object_byname(t);
    if ( !objectp(obj) )
      return 0;
  }
  return obj;
}

object add_vhost(string host, string user_group)
{
    object usergroup = GROUP(user_group) || USER(user_group);
    if (host == "" || !objectp(usergroup))
        return UNDEFINED;

    mapping hosts = GROUP("Admin")->query_attribute("virtual_hosts");
    if (!mappingp(hosts)) hosts = ([]);
    hosts[host] = usergroup;
    GROUP("Admin")->set_attribute("virtual_hosts", hosts);
    return usergroup;
}

void remove_vhost(string host)
{
    mapping hosts = GROUP("Admin")->query_attribute("virtual_hosts");
    m_delete(hosts,  host);
    GROUP("Admin")->set_attribute("virtual_hosts", hosts);
}

object resolve_vhost(string host)
{
    object destination;
    object usergroup = GROUP("Admin")->query_attribute("virtual_hosts")[host];
    if (objectp(usergroup))
        destination = usergroup->query_attribute("GROUP_PUBLICROOM") || 
                      usergroup->query_attribute("USER_PUBLICROOM") ||
                      usergroup->query_attribute("GROUP_WORKROOM") || 
                      usergroup->query_attribute("USER_WORKROOM");
    return destination;
}

object lookup_vhost(string host)
{
    object usergroup = (GROUP("Admin")->query_attribute("virtual_hosts")||([]))[host];
    if (objectp(usergroup))
        return usergroup;
}

mapping list_vhosts()
{
    mapping hosts = GROUP("Admin")->query_attribute("virtual_hosts");
    foreach (hosts; string host; mixed usergroup)
    {
        if (objectp(usergroup))
            hosts[host] = usergroup->describe();
    }
    return hosts;
}

#define NEWURLMODE

object path_to_object(string path)
{
#ifdef NEWURLMODE
    return url_to_object(path);
#else
    return old_path_to_object(path);
#endif
}

/**
 * Returns an object for the given path if some object is registered
 * with value 'path'.
 *  
 * @param string path - the path to process.
 * @return looks up an object in the database.
 * @author Thomas Bopp (astra@upb.de) 
 * @see resolve_path
 */
object old_path_to_object(string path)
{
    object           obj;

    if ( !stringp(path) )
      return 0;

    if (objectp(obj=mPathCache[path])) {
      if (!stringp(obj->query_attribute(OBJ_URL)) || 
          obj->query_attribute(OBJ_URL)==path) 
        return obj;
      
      m_delete(mPathCache, path);
    }

    int l = strlen(path);
    int              oid;
    string             p;

    
    if ( l > 1 ) {
	if ( path[0] != '/' ) {
	    path = "/"+path;
	    l++;
	}
    }
    else if ( l == 0 ) {
	path = "/";
	l = 1;
    }
    LOG("url:path_to_object("+path+")");
  
    p = path;
    oid = get_value(p);
    // if the path is the path to a directory, try to find the index files
    if ( oid == 0 && l >= 1 && path[l-1] == '/' ) {
	p = path + "index.xml";
	oid = get_value(p);
	if ( oid == 0 ) {
	    p = path + "index.html";
	    oid = get_value(p);
	}
	if ( oid == 0 ) {
	    p = path+"index.htm";
	    oid = get_value(p);
	}
    }

    // if we find no registered object we should try to get any registered
    // prefix container of this and use normal filepath handling from there.
    if ( oid == 0 ) {
	array prefixes = path / "/";
	if ( sizeof(prefixes) >= 2 ) {
	    for ( int i = sizeof(prefixes) - 1; i >= 0; i-- ) {
		p = prefixes[..i]*"/";
		oid = get_value(p);
		if ( oid == 0)
		    oid = get_value(p+"/"); // try  also containers with / at the end
		
		if ( oid != 0 ) {
		    obj = find_object(oid);
		    object module = _Server->get_module("filepath:tree");
		    if ( objectp(module) ) {
		      obj = module->resolve_path(obj, (prefixes[i+1..]*"/"));		    
		      mPathCache[path] = obj;
		      return obj;
		    }
		}
	    }
	}
    }

    LOG("Found object: " + oid);
    obj = find_object(oid);
    mPathCache[path] = obj;

    if ( obj == 0 )
	set_value(p, 0);
    return find_object(oid);
}


object url_to_object(string path, void|string _host)
{
    string host = _host;
    if (!host)
        host = _Server->get_server_name();

    //if (!host && objectp(CALLER) && CALLER->get_vhost)
    //    host = CALLER->get_vhost();

    object usergroup = lookup_vhost(host);
    object hostdest;

    // fail if we can't find a requested host, 
    // but don't fail if it's the default host
    if (!objectp(usergroup) && _host)
        return 0;
    else if (!objectp(usergroup))
        return new_path_to_object(path);
    else
        hostdest = resolve_vhost(host);

    if (path[0] != '/') 
       path = "/"+path;
    if (sizeof(path) > 1 && path[-1] == '/')
       path = path[..sizeof(path)-2];

    DEBUG_URL("path: %O:%O", host, path);

    if (path == "/")
        return hostdest;

    array path_tokens = path / "/";

    object filepath = _Server->get_module("filepath:tree");
    object pathdest = filepath->path_to_object("/"+path_tokens[1]);
    if (!objectp(pathdest))
       pathdest = hostdest->get_object_byname(path_tokens[1]);

    if (!objectp(pathdest))
    {
        object group = GROUP(usergroup->get_identifier()+"."+path_tokens[1]);
        if (!objectp(group))
            group = GROUP(path_tokens[1]);
        if (objectp(group) && (host == _Server->get_server_name() || 
                               usergroup->is_member(group)))
            pathdest = group->query_attribute("GROUP_PUBLICROOM") || 
                       group->query_attribute("GROUP_WORKROOM");
        else if (objectp(USER(path_tokens[1])) && 
                  (host == _Server->get_server_name() ||
                   usergroup->is_virtual_member(USER(path_tokens[1]))))
            pathdest = USER(path_tokens[1])->query_attribute("USER_PUBLICROOM") ||
                       USER(path_tokens[1])->query_attribute("USER_WORKROOM");
    }

    if (objectp(pathdest))
        if (sizeof(path_tokens) > 2)
            return resolve_path(pathdest, path_tokens[2..]*"/");
        else
            return pathdest;

    return UNDEFINED;
}

object new_path_to_object(string path)
{
    object           obj;

    if ( !stringp(path) )
      return 0;

    int              oid;
    
    if (!sizeof(path))
        path = "/";
    
    if (path[0] != '/') 
       path = "/"+path;
    LOG("url:new_path_to_object("+path+")");

    if (objectp(obj=newPathCache[path])) 
    {
      if (!stringp(obj->query_attribute(OBJ_URL)) || 
          obj->query_attribute(OBJ_URL)==path) 
        return obj;
      
      m_delete(newPathCache, path);
    }

    array path_tokens = path / "/";
    object filepath = _Server->get_module("filepath:tree");
    if (sizeof(path_tokens) > 1)
    {
       obj = filepath->path_to_object("/"+path_tokens[1]);
       if (!obj)
           if (GROUP(path_tokens[1]))
               obj = GROUP(path_tokens[1])->query_attribute("GROUP_PUBLICROOM") ||
                     GROUP(path_tokens[1])->query_attribute("GROUP_WORKROOM");
           else if (USER(path_tokens[1]))
               obj = USER(path_tokens[1])->query_attribute("USER_PUBLICROOM") ||
                     USER(path_tokens[1])->query_attribute("USER_WORKROOM");
    }

    if (obj && sizeof(path_tokens) > 2)
        obj = filepath->resolve_path(obj, path_tokens[2..]*"/");

    LOG("Found object: " + obj);
    newPathCache[path] = obj;

    if ( obj == 0 )
	delete(path);
    return obj;
}

/**
 * Gets the path for an object by looking up the objects id in the
 * database and returns a path or 0.
 *  
 * @param object obj - the object to get a path for.
 * @return the path for object 'obj'.
 */
string old_object_to_filename(object obj)
{
    string path = get_value(obj->get_object_id());
    if ( !stringp(path) ) {
	
	foreach ( indices(mVirtualPath), object module ) {
	    string vpath = module->contains_virtual(obj);
	    if ( stringp(vpath) )
		return mVirtualPath[module] + vpath;
	}

	path = "";
	object env = obj->get_environment();
	// check if environment is registered


	if ( objectp(env) ) {
	    path = object_to_filename(env);
	}
	if ( !stringp(path) )
	  steam_error("Unable to resolve path for "+obj->describe());
	if ( strlen(path) == 0 )
	  return "";

	if ( path[-1] != '/' )
	    path += "/";

	path += obj->get_identifier();
    }
    return path;
}

string object_to_filename(object obj, void|string server_name)
{
    DEBUG_URL("new_object_to_filename(%O, %O)", obj, server_name);
    string path;
//    path = get_value(obj->get_object_id());
    if ( !stringp(path) ) 
    {
	foreach ( indices(mVirtualPath), object module ) 
        {
	    string vpath = module->contains_virtual(obj);
	    if ( stringp(vpath) )
            {
                DEBUG_URL("new_object_to_filename(%O): %O-%O-%O", obj, module, vpath, mVirtualPath[module]);
		return mVirtualPath[module] + vpath;
            }
	}
    }

    object owner = obj->query_attribute("OBJ_OWNER") || obj->get_root_environment()->query_attribute("OBJ_OWNER");
//    if (objectp(CALLER) && CALLER->get_vhost)
//        DEBUG_URL("new_object_to_filename(%O) caller w vhost:%O", obj, CALLER->get_vhost());
//    else
//        DEBUG_URL("new_object_to_filename(%O) caller:%O", obj, CALLER);
//    object socket = Caller.get_socket(this, backtrace());
//    if (socket && socket->get_vhost)
//        DEBUG_URL("new_object_to_filename(%O) socket w vhost: %O", obj, socket->get_vhost());
//    else
//        DEBUG_URL("new_object_to_filename(%O) socket: %O", obj, socket);
    
    if (owner && obj->get_object_id() == (owner->query_attribute("GROUP_PUBLICROOM") || 
                owner->query_attribute("USER_PUBLICROOM") ||
                owner->query_attribute("GROUP_WORKROOM") || 
                owner->query_attribute("USER_WORKROOM"))->get_object_id())
    {
        
        object socket = Caller.get_socket(this, backtrace());
        if (!server_name && objectp(socket) && socket->get_vhost)
            server_name = socket->get_vhost();
        object vhost_owner = lookup_vhost(server_name);
        
        DEBUG_URL("new_object_to_filename(%O) %O - %O - socket: %O", obj, server_name, vhost_owner, socket);

        if (vhost_owner)
        {
            // if the current host is a virtual host for the owner, path is /
            if (owner == vhost_owner)
                path = "/";

            //    if owner is a subgroup or user check if it is a member of the vhost group,
            //       path is the subgroup or user name.
            else if (server_name == _Server->get_server_name() || 
                     vhost_owner->is_virtual_member(owner))
                if (has_prefix(owner->get_identifier(), vhost_owner->get_identifier()+"."))
                    path = "/"+owner->get_identifier()[sizeof(vhost_owner->get_identifier())+1..];
                else
                    path = "/"+owner->get_identifier();
        }
        else
            // if this is a publicroom then path is groupname.
            path = "/"+owner->get_identifier();
    }
    else
        DEBUG_URL("new_object_to_filename(%O) env: %O owner: %O root: %O owner: %O socket: %O room: %O", obj, obj->get_environment(), obj->query_attribute("OBJ_OWNER"), obj->get_root_environment(), owner, Caller.get_socket(this, backtrace()), 
               (owner && (owner->query_attribute("GROUP_PUBLICROOM") ||
                          owner->query_attribute("USER_PUBLICROOM") ||
                          owner->query_attribute("GROUP_WORKROOM") ||
                          owner->query_attribute("USER_WORKROOM"))));

    if (!owner && obj->query_attribute("OBJ_NAME") == "root-room")
        path = "/";

    if (!path)
    {
        object env = obj->get_environment();

        if ( objectp(env) )
        {
            string parentpath = object_to_filename(env, server_name);
            if (parentpath[-1] != '/')
                parentpath+="/";
            path = parentpath+obj->get_identifier();
        }
    }

    if ( !path )
        steam_error("Unable to resolve path for "+obj->describe());
    DEBUG_URL("new_object_to_filename(%O) result: %O", obj, path);
    return path;
}

mapping object_to_url(object obj)
{
    // find owner
    // check if owner has a virtual host
    // get list of groups owner belongs to
    // get virtual hosts for each group
    mapping vhosts = GROUP("Admin")->query_attribute("virtual_hosts");
    mapping host_groups = ([]);
    foreach (vhosts; string host; object group)
    {
         if (!host_groups[group])
             host_groups[group] = ({ host });
         else
             host_groups[group] += ({ host });
    }
    object owner = obj->query_attribute("OBJ_OWNER") || obj->get_root_environment()->query_attribute("OBJ_OWNER");
    array groups = ({ owner });
    array subgroups = owner->get_groups();
    while(sizeof(subgroups))
    {
        groups += subgroups;
        subgroups = Array.flatten(subgroups->get_groups());
    }
    mapping matches = host_groups & groups; 
    array hosts = Array.flatten(values(matches));
    if (!sizeof(hosts))
        hosts += ({ _Server->get_server_name() });

    mapping urls = ([]);
    foreach (hosts;; string host)
    {
        string path = object_to_filename(obj, host);
        if (path && sizeof(path))
            urls[host] = sprintf("http://%s%s", host, path);
    }
    return urls;
}

string object_to_path(object obj)
{
  string fullpath = object_to_filename(obj);
  return dirname(fullpath);
}

/**
 * Get environment from a given path. This checks if the directory
 * prefix of 'url' is also registered in the database.
 *  
 * @param string url - path to get the environment object for.
 * @return the environment object or 0.
 * @author Thomas Bopp (astra@upb.de) 
 */
object path_to_environment(string url)
{
    sscanf(url, "/%s/%*s", url);
    return path_to_object(url);
}

string execute(mapping vars)
{
  return "<html><body><h2>Welcome to sTeam</h2><br/>"+
    "Congratulations, you successfully installed a sTeam server!"+
    "<br/>To be able to get anything working on this "+
    "Web Port, <br/>you need to install the web Package.</body></html>";
}

string get_identifier() { return "filepath:url"; }
string get_table_name() { return "orb_url"; }
int get_object_class() { return ::get_object_class() | CLASS_SCRIPT; }
