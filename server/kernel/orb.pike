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
 * $Id: orb.pike,v 1.3 2010/08/20 20:42:25 astra Exp $
 */

constant cvs_version="$Id: orb.pike,v 1.3 2010/08/20 20:42:25 astra Exp $";

#include <classes.h>
#include <database.h>
#include <attributes.h>
#include <access.h>
#include <macros.h>

object resolve_path(object|string uid, string path);
object path_to_object(string path, void|bool reslv);
string object_to_path(object obj);
object path_to_environment(string url);

static mapping mVirtualPath = ([ ]);

void add_virtual_path(string path, object module)
{
    if ( !_Server->is_module(module) )
	steam_error("Invalid module in filepath: add_virtual_path() !");
    mVirtualPath[module] = path;
}

/**
 * get detailed information about a file
 *  
 * @param url - pathname or object-pointer for an object
 * @return file information for the object
 * @author Thomas Bopp (astra@upb.de) 
 */
array(mixed) identify_file(string|object url)
{
    string       dtype;
    int  last_modified;
    object         obj;
    array(mixed)   res;

    if ( !objectp(url) ) {
	obj = path_to_object(url);
	if ( !objectp(obj) ) 
	    return 0;
    }
    else {
	LOG("identify_file("+url+")");
	obj = url;
	url = object_to_path(obj);
    }
    
    if ( obj->get_object_class() & CLASS_DOCUMENT )
    {
	dtype = obj->query_attribute(DOC_MIME_TYPE);
	LOG("Mime-type is " + dtype);
	if ( !stringp(dtype) ) {
	    string doctype;
	    
	    doctype = obj->query_attribute(DOC_TYPE);
	    if ( stringp(doctype) )
		dtype = _TYPES->query_mime_type(doctype);
	    else
		dtype = "text/html";
	}
	last_modified = obj->query_attribute(DOC_LAST_MODIFIED);
	if ( last_modified == 0 )
	    last_modified = time();
    }
    else {
	dtype = "text/html";
	last_modified = time();
    }
    
    res = ({ obj,
	     url,
	     dtype, // type of document
	     obj->get_content_size(), // size
	     last_modified, // last modified
	     obj->get_object_class(), // the class type of document 
	     obj->stat(), 
	     obj->query_sanction(_WORLDUSER)
    });
    LOG("Identified object=#"+obj->get_object_id()+ " from url="+url + 
	",size="+obj->get_content_size()+" array-size="+sizeof(res));
    LOG("res="+sprintf("%O", res));
    return res;
}

/**
 * Get stats of some file identified by 'f'
 *  
 * @param string f - the filename
 * @return file_stat information (usually an array like Stdio.File->stat())
 */
mixed stat_file(string f, void|object id)
{
    object obj = path_to_object(f, true);
    if ( objectp(obj) )
	return obj->stat();
    return 0; // not found
}

/**
 * Get the mimetype for a given url.
 *  
 * @param string f - the filename
 * @return mimetype like text/plain
 */
string get_mimetype(string f)
{
    object obj = path_to_object(f);
    if ( objectp(obj) )
	return obj->stat()[7];
    return "application/x-unknown";
}

/**
 * create a new directory with name "name" in "path"
 *  
 * @param path - the path to create the directory
 * @param name - the name for the new container
 * @return the container-object
 * @author Thomas Bopp (astra@upb.de) 
 */
object make_directory(string path, string name)
{
    object obj, env, factory;
    env = path_to_object(path, true);
    if ( !objectp(env) )
	return null;
    obj = resolve_path(path, name);

    if ( objectp(obj) ) 
	return obj;
    if (path == "/home") {
      steam_error("Cannot create objects in /home!");
    }
    else if ( _Server->query_config("default_container_type") == "room" )
      factory = _Server->get_factory(CLASS_ROOM);
    else
      factory = _Server->get_factory(CLASS_CONTAINER);
    obj = factory->execute((["name":name,]));
    if ( !objectp(obj) )
	return 0;
    // now move the container in the appropriate place
    obj->move(env);
    return obj;
}

array(string) get_directory(string dir)
{
    array directory = ({ });
    object cont = path_to_object(dir, true);
    if ( objectp(cont) ) {
	array inv = cont->get_inventory();
	if ( !arrayp(inv) )
	  return directory;
	
	foreach(inv, object obj) {
	  if ( objectp(obj) && obj->status() >= 0 && 
	       !(obj->get_object_class() & CLASS_USER) )
	    {
	      int cl = obj->get_object_class();
	      if ( !stringp(obj->get_identifier()) )
		continue;
	      if ( cl & CLASS_EXIT || cl & CLASS_DOCUMENT || 
		   cl & CLASS_CONTAINER || cl & CLASS_LINK )
		directory += ({ obj->get_identifier() });
	    }
	}
    }
    return directory;
	
}

/**
 * return the result of a directory query as a mapping filename:file_stat
 *  
 * @param url - the container to get the directory
 * @return the directory for the container
 * @author Thomas Bopp (astra@upb.de) 
 */
mapping(string:array(int)) query_directory(string|object url)
{
    object                    cont;
    array(object)              inv;
    mapping(string:array(int)) res;
    int                      i, sz;

    LOG("query_directory...");
    res = ([ ]);
    if ( stringp(url) )
	cont = path_to_object(url, true);
    else
	cont = url;
    inv = cont->get_inventory();
    for ( i = 0, sz = sizeof(inv); i < sz; i++ ) {
      int cl = inv[i]->get_object_class();
	if ( objectp(inv[i]) && 
	     stringp(inv[i]->get_identifier()) && 
	     strlen(inv[i]->get_identifier()) > 0 &&
	     !(cl & CLASS_USER) &&
	     (cl & CLASS_EXIT || cl & CLASS_DOCUMENT || cl & CLASS_CONTAINER ))
	{
	    res[inv[i]->get_identifier()] =  inv[i]->stat();
	}
    }
    LOG("mapping:size="+sizeof(indices(res)));
    return res;
}

/**
 * get the filename and path of a given path
 *  
 * @param fname - the file name to process
 * @return path and filename of a file
 * @author Thomas Bopp (astra@upb.de) 
 */
array(string) get_filename(string fname)
{
    int                   sz;
    array(string)     tokens;
    
    tokens = fname / "/";
    if ( !arrayp(tokens) || (sz=sizeof(tokens)) <= 1 ) 
	return ({ fname, "" });
    return ({ tokens[sz-1], (tokens[..sz-2] * "/") + "/"});
}

/**
 * Get a path of objects (array) for a given url.
 *  
 * @param string url - the given url
 * @return array of objects
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
array(object) get_path(object obj)
{
    array(object) path = ({ });
    while ( objectp(obj) ) {
	path = ({ obj }) + path;
	obj = obj->get_environment();
    }
    return path;
}

