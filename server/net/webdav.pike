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
 * $Id: webdav.pike,v 1.3 2010/08/18 20:32:45 astra Exp $
 */

constant cvs_version="$Id: webdav.pike,v 1.3 2010/08/18 20:32:45 astra Exp $";

inherit "http";

import webdavlib;

#include <macros.h>
#include <classes.h>
#include <attributes.h>
#include <config.h>
#include <database.h>

//#define WEBDAV_DEBUG

#ifdef WEBDAV_DEBUG
#define DAV_WERR(s, args...) werror(s+"\n", args)
#else
#define DAV_WERR(s, args...)
#endif

import httplib;


class steamDAV {
  inherit WebdavHandler;

  object _dav;
  object __fp;

  mapping null_ressources = ([ ]);

  void create(object dav, object fp) {
    _dav = dav;
    __fp = fp;
  }
  string url_name(string fname) {
      return replace_uml(fname);
  }

  string lock(mixed ctx, string fname, mapping lock_data) {
    string token;

    if ( !lock_data->token ) {
	token = Locking.generate_token(ctx);
	lock_data->token = token;
    }
    else
	token = lock_data->token;
    
    if ( objectp(ctx) ) {
	mapping ldata = ctx->query_attribute(OBJ_LOCK) || ([ ]);
	ldata[token] = lock_data;
	ctx->set_attribute(OBJ_LOCK, ldata);
    }
    else {
	mapping ldata = null_ressources[fname] || ([ ]);
	ldata[token] = lock_data;
	null_ressources[fname] = ldata | ([ "isnull": 1, ]) ;
    }
    return lock_data->token;
  }

  void unlock(mixed ctx, string fname, void|string token)
  {
      if ( !stringp(token) )
	  ctx->set_attribute(OBJ_LOCK, 0);
      else {
	  mapping ldata = ctx->query_attribute(OBJ_LOCK);
	  if ( mappingp(ldata) ) {
	      m_delete(ldata, token);
	      ctx->set_attribute(OBJ_LOCK, ldata);
	  }
      }
  }

  mapping get_locks(mixed ctx, string fname) {
      if ( !objectp(ctx) )
	  return null_ressources[fname];
      return ctx->query_attribute(OBJ_LOCK) || ([ ]);
  }

  mapping is_locked(mixed ctx, string fname, void|string gottoken) {
    mapping ldata;
    if ( !objectp(ctx) ) 
	ldata =  null_ressources[fname] || ([ ]);
    else
	ldata = ctx->query_attribute(OBJ_LOCK) || ([ ]);
    DAV_WERR("is_locked(%O, %s, %O)", ctx, fname, gottoken);
    DAV_WERR("locks = %O\n", ldata);
    foreach(indices(ldata), string token) {
	mapping lockdata = ldata[token];
	if ( mappingp(lockdata) ) {
	    int timeout = 180;
	    if ( stringp(lockdata["timeout"]) ) {
		sscanf(lockdata["timeout"], "Second-%d", timeout);
	    }
	    if ( lockdata->locktime > 0 && (time() - lockdata->locktime) < timeout )
	    {
		DAV_WERR("active lock found...");
		if ( !stringp(gottoken) || lockdata->token == gottoken )
		    return lockdata;
	    }
	}
    }
    if ( objectp(ctx) ) {
	object env = ctx->get_environment();
	ldata = is_locked(env, "", gottoken);
	if ( mappingp(ldata) )
	    return ldata;
    }
    if ( !stringp(gottoken) ) {
	if ( objectp(ctx) )
  	    catch(ctx->set_attribute(OBJ_LOCK, 0));
	else
	    null_ressources[fname] = 0;
    }
    return 0;
  }
  string get_user_href() {
    return _Server->get_server_name() + "/~" + this_user()->get_user_name();
  }

  string get_etag(mixed ctx) {
    return ctx->get_etag();
  }

  object get_object_id() { return _dav->get_object_id(); }
  object this() { return _dav->get_user_object(); }
}

static object __webdavHandler;

int check_lock(object obj, mapping vars, void|string fname) 
{
    if ( !objectp(obj) && !stringp(fname) )
	return 1;
    if ( !stringp(fname) )
	fname = "";
    string token = get_opaquelocktoken(__request->request_headers->if);
    if ( stringp(token) ) {
	if ( mappingp(__webdavHandler->is_locked(obj, fname, token)) )
	    return 1;
    }
    mapping res = __webdavHandler->is_locked(obj, fname);
    DAV_WERR("Checking lock (current token=%O) locked=%O", token, res);
    return res == 0;
}

int check_precondition(object obj)
{
  int res = ::check_precondition(obj);
  if ( !res )
    return 0;

  array ifheader = webdavlib.parse_if_header(__request->request_headers->if);
  if ( sizeof(ifheader) == 0 )
    return 1;

  foreach ( ifheader, mapping list) {
    object condobj = obj;
    string path = list->resource || __request->not_query;
    if ( stringp(list->resource) ) {
      condobj = _fp->path_to_object(list->resource);
    }
    if ( stringp(list->state) ) {
      // check state
      if ( search(list->state, "opaquelocktoken") >= 0 ) {
        mapping islocked =__webdavHandler->is_locked(condobj,path,list->state);
        if ( objectp(__webdavHandler) && !mappingp(islocked) ) {
          continue; // match needs resource to be locked
        }
      }
      else if ( list->state == "DAV:no-lock" ) {
        mapping locks = __webdavHandler->get_locks(condobj, path);
        if ( !list->not ) {
            continue;
        }
      }
      if ( stringp(list->entity) )
        if ( objectp(condobj) && list->entity != condobj->get_etag() )
          continue;
      return 1;
    }
    else if ( stringp(list->entity) ) {
      if ( objectp(condobj) && list->entity != condobj->get_etag() )
        continue;
      return 1;
    }
  }
  return 0;
}

mapping handle_OPTIONS(object obj, mapping variables)
{	
    mapping result = ::handle_OPTIONS(obj, variables);
    result->extra_heads += ([ 
	"MS-Author-Via": "DAV",
#ifdef WEBDAV_CLASS2
	"DAV": "1,2",
#else
	"DAV": "1", 
#endif
    ]);
    return result;
}

#ifdef WEBDAV_CLASS2
mapping handle_LOCK(object obj, mapping variables)
{
    if ( this_user() == USER("guest") )
	return response_noaccess(obj, variables);

    obj = _fp->path_to_object(__request->not_query, 1);
    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");

    return lock(__request->not_query, __request->request_headers, 
		__request->body_raw,
		__webdavHandler, obj);
}

mapping handle_UNLOCK(object obj, mapping variables)
{
    if ( this_user() == USER("guest") )
	return response_noaccess(obj, variables);
    obj = _fp->path_to_object(__request->not_query, 1);
    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");

    return unlock(__request->not_query, __request->request_headers,
		  __request->body_raw,
		  __webdavHandler, obj);
}
#endif

static bool move_and_rename(object obj, string name)
{
    string fname, dname, sname;

    sname = _Server->get_server_name();
    sscanf(name, "%*s://" + _Server->get_server_name() + "%s", name);

    if ( name[-1] == '/' )
      name = dirname(name);

    fname = basename(name);
    dname = dirname(name);
    object target;
    if ( dname == "" ) 
      target = obj->get_environment();
    else
      target = _fp->path_to_object(dname);
    
    
    if ( !objectp(target) ) {
      DAV_WERR("No Target directory found at %s", dname);
      return false;
    }
    if ( strlen(fname) > 0 ) 
      obj->set_attribute(OBJ_NAME, fname);
    obj->move(target);
    return true;
}

mapping|void handle_MOVE(object obj, mapping variables)
{
    string destination = __request->request_headers->destination;
    string overwrite   = __request->request_headers->overwrite;

    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");

    if ( !check_lock(obj, variables) ) 
	return low_answer(423, "Locked");

    if ( !objectp(obj) )
      return response_notfound(__request->not_query, variables);

    if ( !stringp(overwrite) )
	overwrite = "T";
    __request->misc->overwrite = overwrite;
    __request->misc->destination = resolve_destination(
	destination,  __request->request_headers->host);

    int res = 201;
    // create copy variables before calling filesystem module
    if ( mappingp(__request->misc->destination) )
	return __request->misc->destination;
    else if ( stringp(__request->misc->destination) )
	__request->misc["new-uri"] = __request->misc->destination;
    DAV_WERR("Handling move:misc=\n"+sprintf("%O\n", __request->misc));
    
    destination = __request->misc["new-uri"];
    if ( catch(destination = url_to_string(destination)) )
	FATAL("Failed to convert destination %s", destination);
    
    object dest = _fp->path_to_object(destination);
    if ( objectp(dest) ) {
      if ( __request->misc->overwrite == "F" ) {
	DAV_WERR("overwritting failed !");
	return low_answer(412, "Pre-Condition Failed");
      }
      else {
	  if ( !check_lock(dest, variables) )
	      return low_answer(423, "Locked");
	  res = 204;
	  dest->delete();
      }
    }    
    if ( !move_and_rename(obj, destination) ) 
      return low_answer(409, "conflict");
    return low_answer(res, "moved");
}

mapping|void handle_MKCOL(object obj, mapping variables)
{
    if ( strlen(__request->body_raw) > 0 )
      return low_answer(415, "unsupported type");
    // todo: read the body ?!
    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");
    mapping result = ::handle_MKDIR(obj, variables);
    if ( mappingp(result) && (result->error == 200 || !result->error) )
	return low_answer(201, "Created");
    return result;
}

mapping|void handle_COPY(object obj, mapping variables)
{
    string destination = __request->request_headers->destination;
    string overwrite   = __request->request_headers->overwrite;

    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");

    if ( !stringp(overwrite) )
	overwrite = "T";
    __request->misc->overwrite = overwrite;
    __request->misc->destination = resolve_destination(
	destination, __request->request_headers->host);
    if ( mappingp(__request->misc->destination) )
	return __request->misc->destination;

    mixed result =  ([ ]); // should now how to copy handle_http();
    object duplicate;

    duplicate = _fp->path_to_object(__request->misc->destination);

    DAV_WERR("Handling COPY:misc=\n"+sprintf("%O\n", __request->misc));
    DAV_WERR("Found dest resource = %s !",
	     (objectp(duplicate) ? "yes" : "no"));
    int res = 201;
    if ( objectp(duplicate) ) {
      if ( __request->misc->overwrite == "F" ) {
	DAV_WERR("overwritting failed !");
	return low_answer(412, "conflict");
      }
      else {
	  if ( !check_lock(duplicate, variables) )
	      return low_answer(423, "Locked");
	  res = 204;
	  duplicate->delete();
      }
    }    
    if ( objectp(obj) ) 
    {
	if ( obj->get_object_class() & CLASS_CONTAINER )
	  duplicate = obj->duplicate(true);
	else
	  duplicate= obj->duplicate();

	// dirname and fname
	if ( !move_and_rename(duplicate, __request->misc->destination) )
	  return low_answer(409, "conflict");
	duplicate->set_attribute(OBJ_LOCK, 0);
	return low_answer(res, "copied");
    }
    else {
	FATAL("Resource could not be found !");
	return low_answer(404, "not found");
    }
}

mapping|void handle_PROPPATCH(object obj, mapping variables)
{
    obj = _fp->path_to_object(__request->not_query, 1);

    if ( !check_lock(obj, variables) ) 
	return low_answer(423, "Locked");

    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");

    return proppatch(__request->not_query, __request->request_headers,
		     __request->body_raw, __webdavHandler, obj);
}

mapping handle_DELETE(object obj, mapping vars)
{

    if ( !check_lock(obj, vars) ) 
	return low_answer(423, "Locked");
    return ::handle_DELETE(obj, vars);
}

mapping handle_PUT(object obj, mapping vars)
{
    string fname = __request->not_query;

    obj = _fp->path_to_object(__request->not_query, 1);

	
    if ( !check_lock(obj, vars, fname) ) 
	return low_answer(423, "Locked");

    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition Failed");

    mapping result = ::handle_PUT(obj, vars);
    mixed err = catch {
	mapping locks = __webdavHandler->get_locks(0, fname);
	if ( mappingp(locks) && sizeof(locks) > 0 ) {
	    // locked null resources
	    object fp = vars->fp;
	    if ( !objectp(fp) )
	    fp = get_module("filepath:tree");
	    obj = fp->path_to_object(fname);
	    if ( objectp(obj) ) {
		if ( !mappingp(obj->query_attribute(OBJ_LOCK)) )
		    obj->set_attribute(OBJ_LOCK, locks);
	    }
	}
    };
    if ( err ) {
	FATAL("While setting lock for previous null resource: %O", err);
    }
    return result;
}

mapping|void handle_PROPFIND(object obj, mapping variables)
{
    isWebDAV = 1; // heuristics ;-)
    
    obj = _fp->path_to_object(__request->not_query, 1);
    
    if ( !objectp(obj) )
	return low_answer(404, "not found");
    
    return propfind(__request->not_query, __request->request_headers, 
		    __request->body_raw, __webdavHandler, obj);
}    

mixed get_property(object obj, Property property)
{
  if ( !objectp(obj) )
    return 0;
  if ( !objectp(property) )
    error("No property found, null-pointer !");
  DAV_WERR("Get property %s, val=%O, ns=%O", property->get_name(),obj->query_attribute(property->get_name()), property->describe_namespace());
  string pname = property->get_ns_name();

#if 0
  switch( property->get_name() ) {
  case "displayname":
    return obj->query_attribute(OBJ_NAME);
  case "name":
    return obj->get_identifier();
  }
#endif
  mixed res = obj->query_attribute(pname);  
  if ( stringp(res) )
    return replace(res, ({ "<", ">" }), ({ "&lt;", "&gt;" }));
  return res;
}

int set_property(object obj, Property property, mapping namespaces)
{
  string val = property->get_value();
  string xmlns = property->describe_namespace();
  DAV_WERR("Set property %s", property->_sprintf());

  obj->set_attribute(property->get_ns_name(), val);
  return 1;
}

string resolve_redirect(object link)
{
  object res = link->get_link_object();
  return _fp->object_to_filename(res);
}

object get_context(object ctx, string f)
{
  if ( objectp(ctx) )
    return ctx->get_object_byname(f);
  return 0;
}

int is_link(object ctx)
{
  if ( objectp(ctx) && ctx->get_object_class() & CLASS_LINK ) 
    return 1;
  return 0;
}

static mapping 
call_command(string cmd, object obj, mapping variables)
{
    mapping result = ([ ]);

    // overwritten - must not forward requests without trailing /
    DAV_WERR("RAW: %s", __request->raw);
    float f = gauge {
    function call = this_object()["handle_"+cmd];
    if ( functionp(call) ) {
        result = call(obj, variables);
    }
    else {
	result->error = 501;
	result->data = "Not implemented";
    }
    if ( mappingp(result) ) {
      if ( stringp(result->data) && strlen(result->data) > 0 && 
	   !result->encoding && !result->type ) 
      {
	result->tags = 0;
	result->encoding = "utf-8";
	result->type = "text/xml";
      }
    }
    };
    
    DAV_WERR("DAV: %s %s %f seconds", cmd, __request->not_query, f);
    return result;
}

void create(object fp, bool admin_port)
{
    ::create(fp, admin_port);
    __webdavHandler = steamDAV(this_object(), fp);
    __webdavHandler->get_directory = fp->get_directory;
    __webdavHandler->stat_file = fp->stat_file;
    __webdavHandler->set_property = set_property;
    __webdavHandler->get_property = get_property;
    __webdavHandler->resolve_redirect = resolve_redirect;
    __webdavHandler->get_context = get_context;
    __webdavHandler->is_link = is_link;
}

void respond(object req, mapping result)
{
    DAV_WERR("Respond: %O", result);
    if ( stringp(result->data) )
	result->length = strlen(result->data);

    ::respond(req, result);
}

string get_identifier() 
{ 
    if ( is_dav() ) 
	return "webdav"; 
    else
	return "http";
}

void test()
{
  webdavlib.test();
}
