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
 * $Id: connection.pike,v 1.2 2010/02/13 09:30:55 astra Exp $
 */

constant cvs_version="$Id: connection.pike,v 1.2 2010/02/13 09:30:55 astra Exp $";


/* 
 * installation script
 * the pike call will include the pathnames to the server location
 */ 
inherit "client_base";
inherit "base/xml_parser";

#include <coal.h>
#include <client.h>
#include <classes.h>
#include <attributes.h>

//#define CHECK_ONLY

static object fsystem; // the filesystem to use
static string _fs;

static int debug_output = 0;

private static mapping mFiles = ([ ]);
object _docfactory, _contfactory, _filepath;
int iInstall, iUpdate, iError;

int handle_error(mixed err) {
  if ( arrayp(err) && sizeof(err)>1 ) {
    if ( stringp(err[1]) ) werror( "Error: %s\n", err[1] );
    else werror( "Error: %O\n", err[1] );
  }
  else werror( "Error: %O\n", err );
  throw( ({ "", backtrace() }) );
  if ( debug_output ) {
    werror( "Debug output:\n%O\n", err );
    throw( ({ "", backtrace() }) );
  }
  exit(1);
}

object open_file(string fname, string fs)
{
    return Filesystem.Tar(fs)->open(fname, "r");
}

array(string) get_directory(string dname)
{
    return fsystem->get_dir(dname);
}

void set_debug ( int debug )
{
  debug_output = debug;
}

int get_debug ()
{
  return debug_output;
}

/*****************************************************************************
 * XML stuff
 */
mapping xmlMap(NodeXML n)
{
  mapping res = ([ ]);
  if ( !objectp(n) )
    return res;

  foreach ( n->children, NodeXML children) {
    if ( children->name == "member" ) {
      mixed key,value;
      foreach(children->children, object o) {

	if ( o->name == "key" )
	  key = unserialize(o->children[0]);
	else if ( o->name == "value" )
	  value = unserialize(o->children[0]);
      }
      res[key] = value;
    }
  }
  return res;
}

array xmlArray(NodeXML n)
{
  array res = ({ });
  foreach ( n->children, NodeXML children) {
    res += ({ unserialize(children) });
  }
  return res;
}

mixed unserialize(NodeXML n) 
{
  switch ( n->name ) {
  case "struct":
    return xmlMap(n);
    break;
  case "array":
    return xmlArray(n);
    break;
  case "int":
    return (int)n->data;
    break;
  case "float":
    return (float)n->data;
    break;
  case "string":
    return n->data;
    break;
  case "object":
    string type = n->children[0]->data;
    string id = n->children[1]->data;
    object obj;
    int    oid;

    switch(type) {
    case "Group":
      oid = set_object(mVariables["groups"]);
      break;
    case "User":
      oid = set_object(mVariables["users"]);
      break;
    case "Module":
      oid = set_object(0);
      obj = send_command(COAL_COMMAND, ({ "get_module", ({ id }) }));
      set_object(oid);
      return obj;
      break;
    default:

	
      oid = set_object(mVariables["filepath:tree"]);
      obj = send_command(COAL_COMMAND, ({ "path_to_object", ({ id }) }));
      set_object(oid);
      return obj;
      break;
    }

    obj = send_command(COAL_COMMAND, ({ "lookup", ({ id }) }));
    set_object(oid);
    return obj;
  }
  return 0;
}

void save_xml(NodeXML n, object obj)
{
  set_object(obj);
  mapping attributes = xmlMap(n->get_node("/Object/attributes/struct"));
  mapping a_acquire = xmlMap(n->get_node("/Object/attributes-acquire/struct"));
  mapping sanction = xmlMap(n->get_node("/Object/sanction/struct"));
  mapping msanction = xmlMap(n->get_node("/Object/sanction-meta/struct"));
  mixed acquire = unserialize(n->get_node("/Object/acquire/*"));
  mapping a_lock = xmlMap(n->get_node("/Object/attributes-locked/struct"));


  foreach(indices(sanction), object sanc) {
      if ( objectp(sanc) ) {
	  send_command(COAL_COMMAND, ({ "sanction_object", 
					    ({ sanc, sanction[sanc] }) }) );
      }
  }
  foreach(indices(msanction), object msanc) {
      if ( objectp(msanc) ) {
	  send_command(COAL_COMMAND, ({ "sanction_object_meta", 
					    ({ msanc, msanction[msanc] }) }) );
      }
  }
  mixed key;

  send_command(COAL_COMMAND, ({ "unlock_attributes" }));
  foreach(indices(a_acquire), key) {
    if ( stringp(a_acquire[key]) ) // environment only, may not work *g*
      send_command(COAL_COMMAND, ({ "set_acquire_attribute", 
				    ({ key, 1 }) }));
    else if ( !intp(a_acquire[key]) )
      send_command(COAL_COMMAND, ({ "set_acquire_attribute", 
				    ({ key, a_acquire[key] }) }));
  }
  send_command(COAL_COMMAND, ({ "set_attributes", ({ attributes }) }) );
  foreach(indices(a_lock), key ) {
      if ( a_lock[key] != 0 ) {
	  send_command(COAL_COMMAND, ({ "lock_attribute", ({ key }) }));
      }
  }

  // acquire string should be environment function, but thats default ...
  // cannot handle functions yet
  if ( objectp(acquire) || acquire == 0 )
    send_command(COAL_COMMAND, ({ "set_acquire", ({ acquire }) }));

}

  
void object_to_server(object obj)
{
  string path = "xml";

  if ( obj->get_object_class() & CLASS_USER )
    return;

  
  if ( !objectp(_filepath) )
  _filepath = send_cmd(0, "get_module", "filepath:tree");

  object pname = send_cmd(_filepath, "object_to_filename", obj);  
  path += pname;

  set_object(obj);

  werror("\r"+(" "*79));
  werror("\rreading... " + path+".xml");
  Stdio.File f;
  mixed err = catch {
    f = open_file(path+".xml", _fs);
  };
  // if the file does not exist its not part of the reference 
  // server installation
  if ( !objectp(f) ) {
#if 0
      werror("\r"+path+".xml ... file not found !\n");
#endif
    return;
  }
  string xml = f->read();
  f->close();
  NodeXML n = parse_data(xml);
  save_xml(n, obj);
}

object upload_file(object dir, string fname, object f)
{
    if ( search(fname, ".") == 0 || search(fname, "#") >= 0 ) {
	return 0;
    }
    object obj = send_cmd(dir, "get_object_byname", fname);
    if ( !objectp(obj) ) {
	werror(" (Created)");
	iInstall++;
	obj = send_cmd(_docfactory, "execute", ([ "name": fname, ]));
	send_cmd(obj, "move", dir);
    }
    else
	iUpdate++;
    
    
    send_cmd(obj, "set_content", f->read());
    string filename=send_cmd(_filepath, "object_to_filename", obj);
    mFiles[filename] = obj;
    return obj;
}		 

object create_folder(string inCont, string folderName)
{
    return send_cmd(_filepath,"make_directory", ({ inCont, folderName }) );
}

void upload_directory(object location, string dir, mapping vars)
{
    object f, cont;
    
    if ( !objectp(location) )
	error("Dont know where to install - location non-object !");
    array files = fsystem->get_dir(dir);
    if ( !arrayp(files) ) {
	werror("Directory "+ dir + " is empty .. skipping...\n");
	return 0;
    }
    string path = send_cmd(_filepath, "object_to_filename", location);
    if ( !stringp(path) )
	error("Path is not resolvable (no string)!");
    if ( strlen(path) == 0 )
	error("Path has zero length !");
    cont = send_cmd(location, "get_object_byname", basename(dir));
    if ( !objectp(cont) ) {
	werror("\rFolder %s does not exist on server, creating...", 
	       basename(dir));
#ifdef CHECK_ONLY
	return;
#endif
	cont = create_folder(path, basename(dir));
    }
    path = path + (path[-1] !='/' ?"/":"") + basename(dir);
    mFiles[path] = cont;
    werror("\r%s", " "*79); //clear the line
    werror("\rDIRECTORY: %s", path);
    array dirs = ({ });

    foreach( files, string fname ) {
	if ( basename(fname)=="CVS" ||
	     search(fname, ".")==0 ||
	     search(fname, "#")>= 0 )
	    continue;

	if ( fsystem->stat(fname)->isdir() )
	    dirs += ({ fname });
	else
        {
	    werror("\r%s", " "*79); //clear the line
	    werror("\rUploading: (%s)/%s", path, basename(fname));
	    f = open_file(fname, vars->fs);
#ifndef CHECK_ONLY
	    upload_file(cont, basename(fname), f);
#endif
	    f->close();
        }
    }
    foreach ( dirs, string dir_name ) {
	upload_directory(cont, dir_name, vars);
    }
}


//! upload the package on the server
//! And run update routines...
void upload_package(mapping vars)
{

    object f;
    write("Register package...\n");
    _docfactory = send_cmd(0, "get_factory", CLASS_DOCUMENT);
    if ( !objectp(_docfactory) )
      throw(({"Document Factory not found in server !"}));
    _contfactory = send_cmd(0, "get_factory", CLASS_CONTAINER);
    if ( !objectp(_contfactory) )
      throw( ({ "Container factory not found inside server !" }));
    _filepath = send_cmd(0, "get_module", "filepath:tree");
    if ( !objectp(_filepath) )
	error("Unable to find filepath on server !");
    object _rootroom = send_cmd(_filepath, "path_to_object", "/");
    object dest = send_cmd(_filepath, "path_to_object", vars->dest);
    if ( !objectp(dest) ) {
	dest = send_cmd(_filepath, "make_directory",vars->dest);
    }

    
    array files = fsystem->get_dir("/files");
    if ( !arrayp(files) || sizeof(files) == 0 ) {
      files = fsystem->get_dir("files");
      if ( !arrayp(files) || sizeof(files) == 0 ) {
	werror("Invalid SPM Archive: Empty files/ Directory !\n");
	return;
      }
    }
    foreach( files, string fname ) {
        if ( basename(fname) == "CVS" )
	    continue;
       
        object stat = fsystem->stat(fname);
	if ( stat->isdir() ) {
	  upload_directory(dest, "/"+fname, vars);
	}
	else {
	    f = Filesystem.Tar(vars->fs)->open(fname,"r");
	    upload_file(dest, basename(fname), f); 
	    f->close();
        }
    }
    // now some script needs to be called on the server...
    // they first have to be uploaded from the package/ directory
    // and will be installed in the package/ directory of the 
    // server
    array additional = ({ });
    files = get_directory("/package");
    object pdir = send_cmd(_rootroom, "get_object_byname", "packages");
    if ( !objectp(pdir) ) {
        werror("Creating Packages Folder !\n");
	pdir = create_folder("/", "packages");
    }
    
    object exe;
    int isUpgrade = 0;
    
    foreach ( files, string package ) {
	object file = Filesystem.Tar(vars->fs)->open(package,"r");
	object o = upload_file(pdir, basename(package), file);
	file->close();
	exe = send_cmd(o, "get_instance");
	if ( !objectp(exe) ) {
	    exe = send_cmd(o, "execute", ([ "name":vars->package,]));
	    if ( !objectp(exe) ) {
	      array errlist = o->get_errors();
	      werror("Failed to install package main component. Errors are:\n"+
		     (arrayp(errlist) ? (errlist * "\n") : "No errors can be found ?!")+"\n");
	      return;
	    }
	    send_cmd(exe, "move", pdir);
	    werror("\n\nSetting up " + package + "\n");
	    // return additional files
	    send_cmd(exe, "set_attribute", ({ "package:components", mFiles }));
	    
	    additional = send_cmd(exe, "spm_install_package");
	}
	else {
	    werror("\n\nFound previous package Version=" +
		   send_cmd(exe, "get_version") + "\n");
	    // upgrade!
	    isUpgrade = 1;
	    werror("Upgrading Installation...\n");
	    // return additional files
	    additional = send_cmd(exe, "spm_upgrade_package");
	    send_cmd(exe, "check_package_integrity");
	}
	// check if module is registered
	werror("\nChecking Registration: "+ vars->package+"...");

	object reg = send_cmd(0, "get_module", vars->package);
	if ( !objectp(reg) ) {
	    werror("registered.\n");
	    send_cmd(1, "register_module", ({ vars->package, exe }));
	}
	else
	    werror("found.\n");
    }
    if ( !objectp(exe) ) {
      werror("Unable to find package main component !\nFILE DUMP=%O\n", files);
      return;
    }
    if(arrayp(additional))
      foreach(additional, object installed ) {
	if ( !objectp(installed) ) {
	    werror("Error on Installation: Script failed to upgrade.\n");
	    continue;
	}
	string installedP = send_cmd(_filepath,"object_to_filename",installed);
	mFiles[installedP] = installed;
	werror("Installed Script = " + installedP + "\n");
      }
    if ( !isUpgrade ) {
      werror("Reading XML Object Descriptions !\n");
      // finally do the xml settings
      foreach(indices(mFiles), string comp) {
	object_to_server(mFiles[comp]);
      }
      // after loading all xml descriptions ...
      foreach(indices(mFiles), string comp) {
	if ( mFiles[comp]->get_object_class() & CLASS_DOCXSL &&
             objectp(mFiles[comp+".xml"]) )
	  catch(send_cmd(mFiles[comp], "load_xml_structure"));
      }

    }
    else
      werror("Skipping XML on UPGRADING\n");

    send_cmd(exe, "set_attribute", ({ "package:components", mFiles }));
}

void configure_web()
{
  werror("Configure Web Package!\n");
  object _filepath = send_cmd(0, "get_module", "filepath:tree");
  object web = send_cmd(_filepath, "path_to_object", "/packages/package:web");
  mFiles = send_cmd(web, "query_attribute", "package:components");
  foreach(indices(mFiles), string comp) {
    object_to_server(mFiles[comp]);
  }
}

array(object) list_packages(int|void quiet)
{
    _filepath = send_cmd(0, "get_module", "filepath:tree");
    object _packages = send_cmd(_filepath, "path_to_object", 
				"/home/admin/packages");
    array packages = send_cmd(_packages, "get_inventory");
    if ( quiet != 1 ) {
        werror("List of Packages on sTeam server:\n");
	foreach(packages, object pck) {
	    werror(" " + pck->get_identifier() + ":\t"+
		   send_cmd(pck, "query_attribute", OBJ_DESC)+"\n");
	}
    }
    return packages;
}

string get_package(string pck_name)
{
    array(object) packages = list_packages(1);
    foreach ( packages, object pck )
	if ( pck->get_identifier() == pck_name ) {
	    werror("Retrieving "+pck_name+"\n");
	    return send_cmd(pck, "get_content");
	}
    return 0;
}

void set_fsystem(object fs, mapping vars)
{
    iInstall = 0;
    iUpdate  = 0;
    iError   = 0;
    fsystem  = fs;
    _fs = vars->fs;
}

int start(string server, int port, string user, string pw)
{
    int start_time = time();

    werror("Connecting to sTeam server...\n");
    while ( !connect_server(server, port)  ) {
	if ( time() - start_time > 120 ) {
	    throw (({" Couldn't connect to server. Please check steam.log for details! \n", backtrace()}));
	}
	werror("Failed to connect... still trying ... (server running ?)\n");
	sleep(10);
    }
    
    mixed err = catch {
     if ( !stringp(login(user, pw,CLIENT_STATUS_CONNECTED)))
          throw("Wrong Password !");
    };
    if ( err != 0 ) {
        werror("Error on installation: \n"+sprintf("%O", err));
        throw(({"Wrong Password !", backtrace()}) );
	return 0;
    } 
    mVariables["filepath:tree"] = send_cmd(0, "get_module", "filepath:tree");
    return 1;
}



