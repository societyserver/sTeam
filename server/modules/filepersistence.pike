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
 */
inherit "/kernel/persistence";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <access.h>

static string mount = "/";

static mapping mFiles = ([ ]);
static mapping mID    = ([ ]);
static int    __id        = 0;
static object     myContainer;
static int persistence_id;
static int oid_length = 4;  // nr of bytes for object ids

class VirtualObject {
  string file;
  VirtualFileContainer environment;
  int myID;

  void create(string name, VirtualFileContainer cont) {
    string fullpath;
    if ( objectp(cont) )
      fullpath = cont->path + "/" + name;
    else
      fullpath = name;
    
    if ( mFiles[fullpath] ) {
      mID[mFiles[fullpath]] = this_object();
      myID = mFiles[fullpath];
    }
    else {
      __id++;
      mID[__id] = this_object();
      mFiles[fullpath] = __id;
      myID = __id;
    }
    environment = cont;
    file = name;
  }
  
  int get_object_id() { return myID; }
    
  mixed query_attribute(string key) {
    switch(key) {
    case "OBJ_NAME":
      return file;
    case "OBJ_DESC":
      return "no description";
    case "OBJ_CREAION_TIME":
      return time();
    case "DOC_LAST_MODIFIED":
      return time();
    case "DOC_MIME_TYPE":
      array types = get_module("types")->query_document_type(file);
      string mime = get_module("types")->query_mime_type(types[1]);
      return mime;
    }
  }
  object get_creator() { return USER("root"); }
  mixed set_attribute(string key, mixed value) {
    return 0;
  }
  int get_content_size() { stat()[1]; }
  array(int) stat() {
    return file_stat(environment->path+"/"+ file);
  }
  int status() { return 1; }
  object get_object() { return this_object(); }
  object get_content_file(string mode, void|mapping vars) { 
    return Stdio.File(environment->path+"/"+file, mode);
  }
  int try_access_object(object grp, int bit, void|int meta) {
    if ( bit == SANCTION_WRITE )
      return 1;
    return 1;
  }
  object this() { return this_object(); }
  string get_content() { return Stdio.read_file(environment->path+"/"+file); }
  string get_identifier() { return file; }
  int get_object_class() { return CLASS_DOCUMENT|CLASS_OBJECT; }
}

class VirtualFileContainer {
  inherit VirtualObject;
  string path;
  mapping mydir = ([ ]);
  
  void create(string p, void|object env) {
    ::create(basename(p), env);
    path = p;
    environment = env;
    get_inventory(); // create stuff
  }

  object get_object_byname(string name) {
    return mydir[name];
  }
  
  array(object) get_inventory() {
    array dir = get_dir(path);
    foreach(dir, string fname) {
      string file = path + "/" + fname;
      if ( !mydir[fname] ) {
	if ( Stdio.is_dir(file) )
	  mydir[fname] = VirtualFileContainer(file, this_object());
	else
	  mydir[fname] = VirtualObject(fname, this_object());
      }
    }
    return values(mydir);
  }
  array get_inventory_by_class(int id)
  {
    array inv = ({ });
    foreach(get_inventory(), object o) {
      if ( o->get_object_class() & id )
	inv += ({ o });
    }
    return inv;
  }
  
  int get_content_size() { return -2; }
  array(int) stat()
  {
    return file_stat(path);
  }
  int get_object_class() { return CLASS_CONTAINER | CLASS_OBJECT; }
}

mixed new_object(string id, object obj, string prog_name)
{
  // no new objects yet
  return 0;
  
  if ( mFiles[id] ) {
    // this file already exists
    __id++;
    //int _id = __id & (get_persistence_id()<<24);
    int _id = _Persistence->make_object_id( __id );
    object p = new("/kernel/proxy.pike", _id, obj);
    return ({ _id, p });
  }
  return 0;
}

object find_object(int|string id)
{
  if ( objectp(mID[id]) )
    return mID[id];
}

bool delete_object(object p)
{
  return false;
}

int|object load_object(object proxy, int|object oid)
{
  // lookup object id
  
}

void load_module()
{
  persistence_id = _Persistence->register("filesystem", this_object());
  mID = do_query_attribute("file_ids");
  if ( !mappingp(mID) )
    mID = ([ ]);
  create_mount();
}

static object create_mount()
{
  mFiles["file_mount"] = 1;
  myContainer = VirtualFileContainer(mount);
  
  return myContainer;
}

array(int) stat()
{
  return ({ 16895, -2,
	    do_query_attribute(OBJ_CREATION_TIME),
	    do_query_attribute(CONT_LAST_MODIFIED),
	    time(),
	    1, 1, "httpd/unix-directory" });
}

array get_inventory_by_class(int id)
{
  array inv = ({ });
  foreach(get_inventory(), object o) {
    if ( o->get_object_class() & id )
      inv += ({ o });
  }
  return inv;
}

object get_object_byname(string id)
{
  if ( !objectp(myContainer) )
    create_mount();
  return myContainer->get_object_byname(id);
}

array get_inventory()
{
  // create everything
  // create an object and directly handle this
  if ( !objectp(myContainer) )
    myContainer = create_mount();
  return myContainer->get_inventory();
}


int get_persistence_id() { return persistence_id; }
string get_identifier() { return "persistence:virtual_fs"; }
int get_object_class() { return ::get_object_class() | CLASS_CONTAINER; }
object lookup_user(string id) { return 0; }
object lookup_group(string id) { return 0; }
