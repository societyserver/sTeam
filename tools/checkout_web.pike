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
 * $Id: checkout_web.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: checkout_web.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "pikewww/local/base/client_base";
inherit "base/xml_data";

#include <coal.h>
#include <macros.h>
#include <classes.h>
#include <client.h>

string compose_scalar(mixed s) 
{
  if ( objectp(s) ) {
    string type, name;
    if ( s->get_object_class() & CLASS_USER ) {
      type = "User";
      name = s->get_identifier();
    }
    else if ( s->get_object_class() & CLASS_GROUP ) {
      type = "Group";
      name = s->get_identifier();
    }
    else if ( s->get_object_class() & CLASS_MODULE ) {
      type = "Module";
      name = s->get_identifier();
    }
    else {
      type = "Path";
      int oid = set_object(mVariables["filepath:tree"]);
      name = send_command(COAL_COMMAND, ({ "object_to_filename", ({ s }) }));
      set_object(oid);
    }
    return "<object><type>"+type+"</type><id>"+name+"</id></object>";
  }
  else
    return ::compose_scalar(s);
}

void update_content(object obj, string path)
{
  string content = send_command(COAL_COMMAND, ({ "get_content" }));
  path = "files"+path;

  if ( !stringp(content) )
    return;
  // create the directory structure !
  string dir;
  array tokens = (path/"/");
  dir = tokens[..sizeof(tokens)-2]*"/";
  Stdio.mkdirhier(dir);

  Stdio.File f = Stdio.File(path, "wct");
  f->write(content);
  f->close();
}

void xmlize_object(object obj, object xml)
{
    set_object(obj);
    xml->write("<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>\n"+
	       "<Object class=\""+
	       obj->get_object_class()+"\">\n");
    
    mapping attributes = send_command(COAL_COMMAND, ({ "query_attributes" }));
    
    xml->write("<attributes>\n"+compose_struct(attributes)+ "</attributes>\n");
    mapping acquire_map = send_command(COAL_COMMAND, 
				       ({ "get_acquired_attributes" }));
    xml->write("<attributes-acquire>\n"+
	       compose_struct(acquire_map) + "\n</attributes-acquire>\n");
    mapping sanction  = send_command(COAL_COMMAND, ({ "get_sanction" }));
    mapping msanction = send_command(COAL_COMMAND, ({ "get_meta_sanction" }));
    
    xml->write("<sanction>\n"+compose_struct(sanction) + "</sanction>\n");
    xml->write("<sanction-meta>\n"+compose_struct(msanction)+
	       "</sanction-meta>\n");
    xml->write("<acquire>\n"+
	       compose(send_command(COAL_COMMAND,({ "get_acquire" })))+
	       "</acquire>\n");
    xml->write("</Object>\n");
}

void object_from_server(object obj)
{
  if ( obj->get_object_class() & CLASS_USER )
    return;

  set_object(mVariables["filepath:tree"]);
  string path = send_command(COAL_COMMAND, 
			     ({ "object_to_filename", ({ obj }) }));
  set_object(obj);
  string id = send_command(COAL_COMMAND, ({ "get_identifier" }));

 
  if ( obj->get_object_class() & CLASS_DOCUMENT )
    update_content(obj, path);

  path = "xml" + path;
  // create the directory structure !
  string dir;
  array tokens = (path/"/");
  dir = tokens[..sizeof(tokens)-2]*"/";
  Stdio.mkdirhier(dir);

  werror("Checking out " + path + "... ok\n");
  // now write xml for the object
  Stdio.File xml = Stdio.File(path + ".xml", "wct");
  xmlize_object(obj, xml);
  xml->close();

  if ( obj->get_object_class() & CLASS_CONTAINER && 
       !(obj->get_object_class() & CLASS_MODULE) ) 
  {
    array inv = send_command(COAL_COMMAND, ({ "get_inventory" }));
    foreach(inv, object o)
      object_from_server(o);
  }

}

int run(int argc, array(string) argv)
{
  int            port = 1900;
  string server= "localhost";
  string     directory = "/";
  int                      i;
  string            file = 0;

  for ( i = 1; i < sizeof(argv); i++ ) {
      string cmd, arg;
      if ( sscanf(argv[i], "--%s=%s", cmd, arg) == 2 ) {
	  switch ( cmd ) {
	  case "server":
	      server = arg;
	      break;
	  case "port":
	      port = (int) arg;
	      break;
	  case "directory":
	      directory = arg;
	      break;
	  case "file":
	      file = arg;
	      break;
	  default:
	      werror(sprintf("Unknown parameter %s\n", argv[i]));
	      break;
	  }
      }
  }
  if ( connect_server(server, port) ) {
    string user = "root";
    string pw   = "steam";

    
    Stdio.Readline rl = Stdio.Readline();
    string iuser = rl->read("User ? ["+ user + "]: ");
    string ipw = rl->read("Password ? ["+pw+"]: ");
    if ( iuser != "" ) user = iuser;
    if ( ipw != "" ) pw = ipw;

    
    login(user, pw, CLIENT_STATUS_CONNECTED);
    // now get the inventory from the root room

    object start = mVariables["rootroom"];
    if ( directory != "/" ) {
	int oid = set_object(mVariables["filepath:tree"]);
	start = send_command(COAL_COMMAND, ({ "path_to_object", 
						  ({ directory }), }));
    }
    else if ( stringp(file) ) {
	start = send_cmd(mVariables["filepath:tree"], "path_to_object",file);
    }
       
    object_from_server(start);
    if ( !stringp(file) ) {
	set_object(0);
	array modules = send_command(COAL_COMMAND, ({ "get_module_objs" }));
	foreach( modules, object module ) {
	    string p = "modules-xml/"+module->get_identifier();
            Stdio.mkdirhier(dirname(p));

	    write("Module: " + p + "\n");
	    object mf = Stdio.File(p,"wct");
	    xmlize_object(module, mf);
	    mf->close();
	}
    }
    return 0;
  }
}
