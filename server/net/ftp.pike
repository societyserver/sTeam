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
 * $Id: ftp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: ftp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "base/ftp" : FTP;
inherit "/net/coal/login" : LOGIN;

#include <classes.h>
#include <attributes.h>
#include <macros.h>

//#define FTP_DEBUG

#ifdef FTP_DEBUG
#define DEBUG_FTP(s,args...) werror(s+"\n",args)
#else
#define DEBUG_FTP(s,args...)
#endif

int received = 0;
int hsent = 0;
mapping options;
int sessions = 0;
int ftp_users = 0;
int requests = 0;
static object   _fp; // filpath module
static object _auth;// auth module.


void create(object f)
{
    _fp = get_module("filepath:tree");
    _auth = get_module("auth");
    options = ([ 
	"FTPWelcome":"Welcome to sTeam ftp server.\n",
	"passive_port_min": 60000,
	"passive_port_max": 65000,
	]);
    ::create(f, this_object());
}

void close_connection()
{
  ftp_logout();
}

mixed stat_file(string file, mixed session) 
{
    DEBUG_FTP("stat_file(%s)", file);
    mixed res, err;
    err = catch {
      res = _fp->stat_file(make_utf8(file));
    };
    if ( err ) {
      // this is access denied for example
      FATAL("Error during stat_file: %O", err);
      return 0;
    }
    return res;

}

void log(mixed response, mixed session)
{
}

mixed find_dir_stat(string dir, mixed session) 
{
  mixed directory, err;
  
  err = catch {
    directory = _fp->query_directory(make_utf8(dir));
    mapping mdir = ([ ]);
    foreach(indices(directory), string f)
      mdir[make_utf8(f)] = directory[f];

    return mdir;
  };
  if ( err ) {
    FATAL("Error on find_dir_stat()\n%O", err);
    return 0;
  }
}

static string make_utf8(mixed data) 
{
  if ( stringp(data) ) {
    string res;
    data = replace(data, "\\ ", " ");
    if ( xml.utf8_check(data) )
      return data;
    if ( catch(res = string_to_utf8(data)) )
      error("Invalid Filename");
    return res;
  }
  error("No Filename!");
}


mixed find_dir(string dir, object session) 
{
    mixed directory, err;
    err = catch {
      directory = _fp->get_directory(make_utf8(dir));
      return map(directory, make_utf8);
    };
    if ( err ) {
      FATAL("Error on find_dir()\n%O", err);
      return 0;
    }
}

string type_from_filename(string filename)
{
    string ext;
    filename = make_utf8(filename);
    sscanf(basename(filename), "%*s.%s", ext);
    return get_module("types")->query_mime_type(ext);
}

void done_with_put( array(object) id )
{
  id[0]->close();
  id[1]->done( ([ "error":226, "rettext":"Transfer finished", ]) );
  catch(destruct(id[0]));
}

void got_put_data( array (object) id, string data )
{
  id[0]->write( data );
}

string to_utf8(string f)
{
  
}

mixed get_file(string fname, mixed session) 
{
    mixed  err;
    object doc;

    fname = make_utf8(fname); // make sure it utf8

    object obj = _fp->path_to_object(fname, true); // resolve links!

    DEBUG_FTP(session->method + " " + fname);
    switch ( session->method ) {
    case "GET":
        doc = obj->get_content_file("r", ([ "raw":1, ]));
	return ([ "file": doc, "len":obj->get_content_size(), "error":200, ]);
    case "PUT":
        int setuser = 0;
        // passive or active ftp?
        if ( !objectp(this_user()) )
	  setuser = 1;
	if ( setuser )
	  set_this_user(this_object());
	
	err = catch {
    	  object document = _fp->path_to_object(fname, true);
	  if ( !objectp(document) )
	    document = get_factory(CLASS_DOCUMENT)->execute((["url":fname,]));
	  doc = document->get_content_file("wct", ([ ]));
	};
	if ( setuser )
	  set_this_user(0);
	if ( err )
	  throw(err);

	session->my_fd->set_id( ({ doc, session->my_fd }) );
	session->my_fd->set_nonblocking(got_put_data, 0, done_with_put);

	return ([ "file": doc, "pipe": -1, "error":0,]);
    case "MV":
        string from = make_utf8(session->misc->move_from);
	doc = _fp->path_to_object(from, true);
	string name = basename(fname);
	string dir = dirname(fname);
        object cont = _fp->path_to_object(dir, true);
	if ( objectp(cont) )
	    doc->move(cont);
	doc->set_attribute(OBJ_NAME, name);	
	return ([ "error": 200, "data": "Ok", ]);
    case "DELETE":
	if ( (obj->get_object_class() & CLASS_USER) || 
	     (obj->get_object_class() & CLASS_GROUP) )
	    return ([ "error":403, "data":"Permission denied." ]);
	
	if ( err = catch(obj->delete()) ) {
	    DEBUG_FTP("ftp error:\n"+err[0] + "\n" + sprintf("%O\n", err[1]));
	    return ([ "error":403, "data":"Permission denied." ]);
	}
	
	return ([ "error":200, "data": fname + " DELETED." ]);
    case "MKDIR":
	string dirn = dirname(fname);
	string cname = basename(fname);
	_fp->make_directory(dirn, cname);
	return ([ "error":200, "data":"Ok.", ]);
    case "CHMOD":
      if ( objectp(obj) )
	return ([ "error": 200, "data": "Ok.", ]);
    case "QUIT":
	DEBUG_FTP("ftp: quitting...");
    }
}

object authenticate(mixed session) 
{
  object user;

  mixed err = catch {
    if ( !objectp(_auth) )
      steam_error("Fatal error - no authentication module found !");
    
    user = _auth->authenticate(session->misc->user, session->misc->password);
    if ( objectp(user) )
      login_user(user);
    else 
      DEBUG_FTP("User " + session->misc->user + " not found ?");
    return user;
  };
  DEBUG_FTP("FTP auth failed.");
  FATAL("Auth failed: %O", err);
  return 0;
}

mixed query_option(mixed opt) 
{
    return options[opt];
}    

void ftp_logout()
{
  if ( objectp(oUser) )
    oUser->disconnect();
  ::ftp_logout();
}

string describe()
{
    return "FTP("+LOGIN::describe() + "," + FTP::describe()+")";
}
