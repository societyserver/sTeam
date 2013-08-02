/* Copyright (C) 2000-2010 Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: http.pike,v 1.5 2010/08/20 20:42:25 astra Exp $
 */
constant cvs_version="$Id: http.pike,v 1.5 2010/08/20 20:42:25 astra Exp $";

inherit "coal/login";

#include <macros.h>
#include <database.h>
#include <classes.h>
#include <attributes.h>
#include <access.h>
#include <roles.h>
#include <config.h>
#include <client.h>

import httplib;

#define DEBUG_HTTP

#ifdef DEBUG_HTTP
#define HTTP_DEBUG(s, args...) get_module("log")->log_debug("http", s, args)
#else
#define HTTP_DEBUG(s, args...)
#endif

object                    _fp;
static object      __notfound;
static int         __finished;
static bool      __admin_port;
static object       __request; // the saved request object
static string       not_query; // initial not_query, saved because of rewrite

static int           __toread; // how many bytes to go to read body
static string          __body; // the request body
static object        __upload;
static object         __tasks;
static object           __cgi;
static int            __touch;
static int          __newfile;
static object       __docfile;
static int       isWebDAV = 0;

constant automatic_tasks = ({ "create_group_exit", "remove_group_exit" });

void create(object fp, bool admin_port)
{
    _fp = fp;
    __finished = 0;
    __admin_port = admin_port;
    __tasks = get_module("tasks");
    __cgi = get_module("cgi");
    __touch = time();
}

int check_notprecondition(object obj)
{
  string etag;
  string ifheader = __request->request_headers["if-none-match"];
  if ( !stringp(ifheader) )
    return 1;
  if ( objectp(obj) )
    etag = obj->get_etag();

  ifheader = String.trim_all_whites(ifheader);
  sscanf(ifheader, "\"%s\"", ifheader);
  array entitytags = ifheader / ",";
  if ( search(entitytags, "*") >= 0 || search(entitytags, etag) >= 0 )
    return 0;
  return 1;
}


int check_precondition(object obj)
{
  string etag;
  string ifheader = __request->request_headers["if-match"];
  if ( !stringp(ifheader) )
    return 1;
  if ( objectp(obj) )
    etag = obj->get_etag();

  ifheader = String.trim_all_whites(ifheader);

  sscanf(ifheader, "\"%s\"", ifheader);

  array entitytags = ifheader / ",";
  if ( search(entitytags, "*") >= 0 || search(entitytags, etag) >= 0 )
    return 1;
  return 0;
}

/**
 * authenticate with server. Normal http authentication
 *  
 * @param string basic - the auth in base64 encoding
 * @return 0 if the authentication was successfull, otherwise error codes
 */
int authenticate(string basic, void|object obj)
{
    string auth, user, pass;
    object userobj;
    
    auth = __request->cookies->steam_auth;
    if ( stringp(auth) && strlen(auth) > 0 && auth != "0" )
    {
      auth = Protocols.HTTP.Server.http_decode_string(auth);
      basic = auth; 
      __request->variables["auth"] = "cookie"; 
      __request->cookies->steam_auth = "****";
    
    }
    else {
      __request->variables["auth"] = "http"; 
    }

    if ( stringp(basic) ) {
	string method;
	if ( sscanf(basic, "%s %s", method, auth) == 0 )
	    auth = basic;
        else
	    switch ( lower_case(method) ) 
            {
	        case "negotiate": 
	            login_user(_GUEST);
	            return 0;
	        case "basic":
	        default:
	            break;
	    }
	
	auth = MIME.decode_base64(auth);
	auth = string_to_utf8(auth);
	sscanf(auth, "%s:%s", user, pass);
	
	userobj = get_module("auth")->authenticate(user,pass);
	if ( !objectp(userobj) )
	    return 401;
	login_user(userobj);
	return 0;
    }
    
    if ( !__admin_port )
      login_user(_GUEST);
    else if ( objectp(obj) && obj->query_sanction(_GUEST) & SANCTION_READ )
      login_user(_GUEST); 
    else
	return 401;
    return 0;
}

/**
 * This thread is used for downloading stuff.
 *  
 * @param object req - the request object.
 * @param function dataf - the function to call to read data
 */
static void download_thread(object req, function dataf)
{
    string str;
    while ( stringp(str=dataf()) ) {
	int sz = strlen(str);
	int written = 0;
	while ( written < sz ) {
	    written += req->my_fd->write(str[written..]);
	}
    }
}


static int handle_cgi(object obj, mapping vars)
{
  object file;
  float    ga;

  ga = gauge(file = __cgi->call_script(obj, vars, __request));
  HTTP_DEBUG("CGI Call took %f seconds.", ga);
  // pipe the file to the fd
  object pipe = ((program)"base/fastpipe")();
  pipe->set_done_callback(finish_pipe);
  pipe->input(file);
  pipe->output(__request->my_fd);
  return 0;
}

int is_dav()
{
    if ( objectp(__request) && mappingp(__request->request_headers) ) {
	string useragent = __request->request_headers["user-agent"] || "";
	if ( search(lower_case(useragent), "webdav") >= 0 || 
	     search(useragent, "DAV") >= 0 )
	    return 1;
    }
    return isWebDAV; // heuristic from webdav.pike if PROPFIND is called
}

int exchange_links(object obj) 
{
  if (!objectp(obj))
    return 0;
  object env = obj->get_environment();
  if (objectp(env) && env->query_attribute(CONT_EXCHANGE_LINKS))
    return 1;
  return 0;
}

/**
 * Handle the GET method of the HTTP protocol
 *  
 * @param object obj - the object to get
 * @param mapping vars - the variable mapping
 * @return result mapping with data, type, length
 */
mapping handle_GET(object obj, mapping vars)
{
    mapping result = ([ ]);
    mapping  extra = ([ ]); // extra headers
    object    _obj =   obj; // if some script is used to display another object
    int           modified;

    // redirection
    if ( obj == get_module("home") && _fp == get_module("filepath:url") ) 
	return low_answer(302, "Found", 
			  ([ "Location": _Server->ssl_redirect("/home/"), ]));


    // the variable object is default for all requests send to sTeam
    // whenever some script is executed, object defines the sTeam object
    // actually requested.
    if ( !objectp(obj) ) 
	return response_notfound(__request->not_query, vars);
    if ( vars->object ) 
	_obj = find_object((int)vars->object);
    if ( !objectp(_obj) ) 
	return response_notfound(vars->object, vars);


    HTTP_DEBUG("GET " + obj->describe() + "\n%O\n", vars);

    string mimetype = obj->query_attribute(DOC_MIME_TYPE) || "";      

    if ( obj->get_object_class() & CLASS_SCRIPT ) 
    {
        result = handle_POST(obj, vars);
	if ( !mappingp(result) )
	  return result;
    }
    else if ( vars->type == "execute" &&
              obj->get_object_class() & CLASS_DOCLPC ) 
    {
        result = handle_POST(obj, vars);
    }
    else if ( vars->type == "content" && 
	      ( obj->get_object_class() & CLASS_DOCXML || 
		mimetype == "text/xml" ) )
    {
	string xml = obj->get_content();
	object xsl = httplib.get_stylesheet(obj);
	if ( objectp(xsl) && !stringp(vars->source) ) {
	  result->data = run_xml(xml, xsl, vars);
	  string method = xsl->get_method();
	  if ( !stringp(method) || method == "" || method == "xml" )
	    method = "html";
	  result->type = "text/" + method;
	}
	else if ( vars->source == "transform" ) {
	  vars->object = (string)obj->get_object_id();   
	  mixed res = show_object(obj, vars);
	  if ( mappingp(res) )
	    return res;
	}
	else {
	  result->data = xml;
	  result->type = "text/xml";
	}
    }
    else if ( vars->type == "content" &&
	      obj->get_object_class() & CLASS_DOCEXTERN )  
    {
	result->data = redirect(obj->query_attribute(DOC_EXTERN_URL), 0);
	result->type = "text/html";
    }
    else if ( vars->type == "content" && 
	      obj->get_object_class() & CLASS_DOCUMENT ) 
    {
      object xsl = obj->query_attribute("xsl:public");
      if ( search(mimetype, "text") >= 0 && 
	   objectp(xsl) && 
	   !is_dav() && 
	   obj->query_attribute("xsl:use_public") ) 
      {
	// if xsl:document is set for any document then
	// instead of downloading the document, do an
	// xml transformation.
	// the xml code is generated depending on the stylesheet
	// This is actually show_object() functionality, but
	// with type content set.
	result->data = run_xml(obj, xsl, vars);
	if ( stringp(vars->source) )
	  result->type = "text/xml";
	else
	  result->type = "text/html";

	result->encoding = xsl->get_encoding();
      }
      else if ( objectp(__cgi) && __cgi->get_program(mimetype) )
      {
	handle_cgi(obj, vars);
	return 0;
      }
      else if ( mimetype == "text/wiki" ) {
	object wikimod = get_module("wiki");
	if ( objectp(wikimod) && !is_dav()) {
	    object wikixsl = get_stylesheet(obj);
	    if ( !objectp(wikixsl) )
		wikixsl = OBJ("/stylesheets/wiki.xsl");
	    
	    if ( objectp(wikixsl) ) {
	      result->data = run_xml(obj, wikixsl, vars);
	      if ( stringp(vars->source) ) 
		result->type = "text/xml";
	      else
		result->type = "text/html";

	      result->encoding = wikixsl->get_encoding();
	    }
	    else {
	      if ( stringp(vars->source) )
		result->data = obj->get_content();
	      else
		result->data = wikimod->wiki_to_html(obj, _fp, vars);
	      result->type = "text/html";
	      result->encoding = "utf-8";
	    }
	}
	else {
	  result->type = "text/plain";
	  result->data = obj->get_content();
	}
      }
      else {
	// download documents, but only if type is set to content
	// because we might want to look at the objects annotations
	object doc = obj->get_content_file("r", vars, "http");
	result->file = doc;
	result->type = obj->query_attribute(DOC_MIME_TYPE);
	__docfile = doc;
	modified = doc->stat()->mtime;
	result->modified = modified;
	result->len = doc->_sizeof()-1;
	string objEnc = obj->query_attribute(DOC_ENCODING);
	if ( stringp(objEnc) )
	    result->encoding = objEnc;  
      }
      if ( mimetype == "text/html" )
	  result->tags = find_tags(OBJ("/tags"));
    }
    else {
	vars->object = (string)obj->get_object_id();   
	mixed res = show_object(obj, vars);
	if ( mappingp(res) )
	    return res;
	
	result->data  = res;
	result->length = strlen(result->data);
	result->type = "text/html";
    }
    if ( stringp(result->type) ) {
	if( search(result->type, "image") >= 0 ||
	    search(result->type, "css") >= 0 ||
	    search(result->type, "javascript") >= 0 )
	    extra->Expires = http_date(60*60*24*365+time());
    }
    extra->ETag = "\""+obj->get_etag() + "\"";
    
    if ( !mappingp(result->extra_heads) )
	result->extra_heads = extra;
    else
	result->extra_heads |= extra;
    if ( !result->error )
      result->error = 200;
    return result;
}

static void finish_pipe()
{
  __request->finish();
}

/**
 * handle the http POST method. Also it might be required to
 * read additional data from the fd.
 *  
 * @param object obj - script to post data to
 * @param mapping m - variables
 * @return result mapping
 */
mapping handle_POST(object obj, mapping m)
{
    mapping result = ([ ]);
    //HTTP_DEBUG("POST(%O)", m);
    // need to read the request yourself...
    if ( !objectp(obj) )
	return response_notfound(__request->not_query, m);


    if (objectp(__cgi) && 
	__cgi->get_program(obj->query_attribute(DOC_MIME_TYPE)))
    {
      handle_cgi(obj, m);
      return 0;
    }
    if ( obj->is_upgrading() ) {
      string html = result_page("The Script is being upgraded, try again !",
                                "JavaScript:history.back();");
      return ([ "data": html, "type":"text/html", "error":200, ]);
    }
    m->fp = _fp;
    mixed res = ([ ]);
    
    if ( obj->get_object_class() & CLASS_DOCLPC ) {
      object script;
      mixed err = catch(script=obj->provide_instance());
      mixed script_errors = obj->get_errors();
  
      if ( sizeof(script_errors) > 0 ) {
        res->data = error_page("There are errors executing script<br/>"+
                                  (script_errors * "<br />"));
        res->type = "text/html";
      }
      else if ( err ) {
        FATAL("Error handling script: %O, %O", err[0], err[1]);
      }
      else if ( objectp(script) ) {
        res = script->execute(m);
      }
    }
    else if ( obj->get_object_class() & CLASS_WEBSERVICE ) {
      werror("WEBSERVICE\n%s\n", __request->raw);
      if ( m->wsdl ) {
	res->data = obj->show_wsdl();
        res->type = "text/xml";
      }
      else if ( !stringp(__body) || strlen(__body) == 0 ) {
        res = obj->execute(m);
      }
      else {
	// analyse body of request (if available)
	werror("Request Body = %O\n", __body);
	object envelope = soap.parse_soap(__body);
	array callNodes = envelope->lookup_body_elements(
				   "urn:"+obj->get_webservice_urn());

	mapping callResults = ([ ]);
	foreach(callNodes, object callNode ) {
	  mapping fcall = soap.parse_service_call(obj->get_object(), callNode);
	  fcall->result = fcall->function(@fcall->params);
	  callResults[callNode] = fcall;
	  if (objectp(fcall->result)) {
	    res = fcall->result;
	    res->userData = ([ "callResults": callResults, "callNode": callNode]);
	    res->webservice = 1;
	  }
	}
	if (!objectp(res)) {
	  // create a new SOAP Envelope
	  envelope = soap.SoapEnvelope();
	  soap.add_service_results(envelope, callResults);
	  res->data = envelope->render();
	  res->type = "text/xml";
	}
      }
    }
    else 
      res = obj->execute(m);

    if ( objectp(res) ) {
      res->resultFunc = async_respond;
      __request->my_fd->write("HTTP/1.1 100 Continue\r\n\r\n");
      res->set_request(__request);
      return 0;
    }
    else if ( mappingp(res) ) {
	return res;
    }
    else if ( intp(res) ) {
	if ( res == -1 ) {
	    result->error = 401;
	    result->type = "text/plain";
	    result->extra_heads = 
		([ "WWW-Authenticate": "basic realm=\"steam\"", ]);
	    return result;
	}
    }
    else if ( arrayp(res) ) {
	if ( sizeof(res) == 2 )
	    [ result->data, result->type ] = res;
	else
	    [ result->data, result->type, result->modified ] = res;
    }
    else {
	result->data = res;
	result->type = "text/html";
    }
    return result;
}

mapping handle_OPTIONS(object obj, mapping vars)
{
    string allow = "";
    mapping result = low_answer(200, "OK");
    
    
    foreach ( indices(this_object()), string ind) {
	string cmd_name;
	if ( sscanf(ind, "handle_%s", cmd_name) > 0 )
	    allow += cmd_name + ", ";
    }

    result->extra_heads = ([
	"Allow": allow, 
	]);
    return result;
}

mapping handle_PUT(object obj, mapping vars)
{
    // handle_PUT only deals with uploading files via webdav
    // PUT requests for scripts are done in handle_POST
    mapping result;
    if ( obj->get_object_class() & CLASS_SCRIPT ) 
    {
        result = handle_POST(obj, vars);
	if ( !mappingp(result) )
	  return result;
    }
    else if ( vars->type == "execute" &&
              obj->get_object_class() & CLASS_DOCLPC ) 
    {
        result = handle_POST(obj, vars);
    }
    else return handle_webdav_PUT(obj, vars);

    return result;
}

mapping handle_webdav_PUT(object obj, mapping vars)
{
    __newfile = 0;

    if ( !check_precondition(obj) )
      return low_answer(412, "Precondition failed");

    if ( !objectp(obj) ) {
	string fname = __request->not_query;
	__newfile = 1;
	obj = get_factory(CLASS_DOCUMENT)->execute( ([ "url":fname, ]) );
    }
    // create Stdio.File wrapper class for a steam object
    string token = webdavlib.get_opaquelocktoken(__request->request_headers->if);

    __upload = ((program)"/kernel/DocFile")(obj, "wct", vars, "http", token);
    __toread = (int)__request->request_headers["content-length"];

    int max_read = _Server->get_config("upload_max");
    if (!zero_type(max_read) && __toread > max_read) {
      steam_error("Maximum upload limit exceeded!");
    }
    if ( strlen(__request->body_raw) > 0 ) {
	__toread -= strlen(__request->body_raw);
	__upload->write(__request->body_raw);
    }
    if ( __toread > 0 ) {
      __request->my_fd->set_nonblocking(read_put_data,0,finish_put);
    }
    else {
      __upload->close();
      return low_answer((__newfile ? 201:200), "created");
    }
    return 0;
}

static void read_put_data(mixed id, string data)
{
    __upload->write(data);
    __toread -= strlen(data);
    __touch = time();
    if ( __toread <= 0 )
	finish_put(0);
}

static void finish_put(mixed id)
{
    __upload->close();
    __upload = 0;
    __finished = 1;
    __touch = time();
    HTTP_DEBUG("Finish HTTP PUT !");
    if ( __newfile )
      respond(__request, low_answer(201, "created") );
    else
      respond(__request, low_answer(200, "ok") );
}


mapping handle_MKDIR(object obj, mapping vars)
{
  string fname = __request->not_query;
  if ( fname[-1] == '/' )
    fname = dirname(fname); // remove trailing /
  if ( objectp(_fp->path_to_object(fname, 1)) ) { // already exists
    return low_answer(405, "not allowed");
  }
  object inter = _fp->path_to_object(dirname(fname));
  if ( !objectp(inter) )
    return low_answer(409, "Missing intermediate");
  
  if ( !check_precondition(obj) )
    return low_answer(412, "Precondition failed");
  
  obj = _fp->make_directory(dirname(fname), basename(fname));
  if ( objectp(obj) ) { 
    HTTP_DEBUG("Created/Returned Collection %O", obj);
    return low_answer(201, "Created.");
  }
  return low_answer(403, "forbidden");
}

mapping handle_DELETE(object obj, mapping vars)
{
  if ( !objectp(obj) )
    return response_notfound(__request->not_query, vars);
  if ( !check_precondition(obj) )
    return low_answer(412, "Precondition failed");
  if ( catch(obj->delete()) )
    return low_answer(403, "forbidden");
  return low_answer(200, "Ok");
}


mapping handle_HEAD(object obj, mapping vars)
{
  if ( !objectp(obj) )
    return response_notfound(__request->not_query, vars);
  
  mapping result = low_answer(200, "Ok");
  result->type = obj->query_attribute(DOC_MIME_TYPE);
  result->modified = obj->query_attribute(DOC_LAST_MODIFIED);
  result->len = obj->get_content_size();
  mapping lockdata = obj->query_attribute(OBJ_LOCK);
  if ( mappingp(lockdata) && lockdata->token )
    result->extra_heads = ([ "Lock-Token": "<" + lockdata->token + ">", ]);
  return result;
}



/**
 * Read the body for a request. Usually the body is ignored, but
 * POST with multipart form data need the body for the request.
 *  
 * @param object req - the request object
 * @param int len - the length of the body (as set in request headers)
 * @return the parsed form data (variables set in a mapping) or 0
 */
mapping read_body(object req, int len)
{
    if ( len == 0 )
	return ([ ]);

    HTTP_DEBUG("trying to read length of body = %O", len);
    if ( stringp(req->body_raw) )
      len -= strlen(req->body_raw);
    
    if ( req->request_type == "PUT" )
	return ([ ]);

    __toread = len;
    __body = "";
    if ( len > 0 ) 
	return 0;
    __body = req->body_raw;

    string content_type = req->request_headers["content-type"] || "";
    
    if ( strlen(__body) == 0 )
	return ([ ]);
    
    content_type = lower_case(content_type);
    if ( search(content_type, "multipart/form-data") >= 0 )
	return parse_multipart_form_data(req, __body);
    else 
      return ([ "__body": __body, ]);
}

/**
 * Read the body of a http request - if the POST sends
 * multipart/formdata, then the request is not read by 
 * Protocols.HTTP.Server.
 *  
 * @param mixed id - id object
 * @param string data - the body data
 */
void read_body_data(mixed id, string data)
{
    if ( stringp(data) ) {
	__body += data;
	__toread -= strlen(data);
	if ( __toread <= 0 ) {
	    __request->body_raw += __body;
	    __request->variables|=parse_multipart_form_data(
		__request,__request->body_raw);
	    __body = "";
	    http_request(__request);
	}
	else if ( strlen(data) < __toread && __toread > 1024 ) {
	  // if another package of same size is not enough
	  werror("continue....\n");
	  __request->my_fd->write("HTTP/1.1 100 Continue\r\n\r\n");
	}
    }
}

/**
 * Call a command in the server. Return the result of the call or
 * if no function was found 501.
 *  
 * @param string cmd - the request_type to call
 * @param object obj - the object
 * @param mapping vars - the variables
 * @return result mapping
 */
static mapping call_command(string cmd, object obj, mapping vars)
{
    mapping result = ([ ]);

    if ( !stringp(vars->host) )
	vars->host = _Server->get_server_name();

    // redirect a request on a container or a room that does not
    // include the trailing /
    if ( objectp(obj) && obj->get_object_class() & CLASS_CONTAINER && 
	 __request->not_query[-1] != '/' )
    {
	// any container access without the trailing /
	result->data = redirect(
	    replace_uml(__request->not_query)+"/"+
	    (strlen(__request->query) > 0 ? "?"+ __request->query : ""),0);
	result->type = "text/html";
	return result;
    }
    HTTP_DEBUG("HTTP: " + __request->not_query + " (%O)", get_ip());

    function call = this_object()["handle_"+cmd];
    if ( functionp(call) ) {
        vars->__internal->request_method = cmd;
	result = call(obj, vars);
    }
    else {
	result->error = 501;
	result->data = "Not implemented";
    }
    result->extra_heads += ([
        "Access-Control-Allow-Origin": vars->__internal->request_headers->origin,
        "Access-Control-Allow-Headers": vars->__internal->request_headers["access-control-request-headers"],
        "Access-Control-Allow-Methods": vars->__internal->request_headers["access-control-request-method"],
	]);
    return result;
}

/**
 * Handle a http request within steam.
 *  
 * @param object req - the request object
 */
mapping run_request(object req)
{
    mapping result = ([ ]);
    mixed              err;


    // see if the server is ready for requests
    if ( !objectp(get_module("package:web") ) && 
	 !objectp(OBJ("/stylesheets")) &&
	 !objectp(get_module("package:spm_support")) )
    {
      result->data = "<html><head><title>open-sTeam</title></head><body>"+
        "<h2>Welcome to sTeam</h2><p>"+
        "Congratulations, you successfully installed an open-sTeam server!"+
	"</p><p>"+
        "To be able to get anything working on this web port, you need to "+
        "install the web package."+
        "</p><p><strong>"+
        "This open-sTeam server's installation has not finished yet, but "+
        "automatic installation of some basic packages is currently in "+
        "progress. Please check back in a few minutes - you will be able "+
        "to use the package manager then!"+
        "</strong></p>"+
        "</body></html>";
      result->error = 200;
      result->type = "text/html";
      return result;
    }

    //  find the requested object
    req->not_query = url_to_string(req->not_query);
    not_query = req->not_query;
    req->not_query = rewrite_url(req->not_query, req->request_headers);


    // cookie based authorization
    if ( req->not_query == "/login" ) {
	login_user(_GUEST); // make sure this_user is set correctly
	if ( req->variables->user && req->variables->password ) {
	  object u;
	  err = catch {
	    u = get_module("auth")->authenticate(req->variables->user, 
						 req->variables->password);
	  };
	  if ( err || !objectp(u) )
	    return response_loginfailed(u, req->variables);
	    
	    result->extra_heads = 
	      set_auth_cookie(req->variables->user, req->variables->password);
	    // redirect !
	    string re = req->variables->area;
	    if ( !stringp(re) )
		re = "/";
	    result->data = redirect(re, 0);
	    result->type = "text/html";
            result->error = 200;
            result->extra_heads |= ([ "Pragma":"No-Cache", 
                                     "Cache-Control":"No-Cache" ]);    
	}
	else {
	  object login = _fp->path_to_object("/documents/login.html");
	  if ( objectp(login) ) 
	    result = ([ "data": login->get_content(), "type": "text/html", ]);
          else 
            result = ([ "data": "Access denied", "error": 401, ]);
	}
	return result;
    }
    else if ( req->not_query == "/logout" ) {
      result->extra_heads = ([ 
	"Set-Cookie":"steam_auth=;expires=Thu, 01-Jan-70 00:00:01 GMT; path=/",
      ]);
      object logout = _fp->path_to_object("/documents/logout.html");
      if ( objectp(logout) ) 
	result += ([ "data": logout->get_content(), "type": "text/html", ]);
      else 
	result += ([ "data": "You are logged out!", "type": "text/html", ]);
      return result;
    }

    object obj = _fp->path_to_object(req->not_query);
    if ( !objectp(obj) ) {
      obj = _fp->path_to_object(req->not_query, 1);
    }

    mapping m = req->variables;

    // the type variable is crucial for steam, since
    // It defines how the object is displayed.
    // the content type is the default and also
    // means objects are downloaded instead of displayed by show_object()
    if ( !stringp(m->type) || m->type == "" ) {
        if ( objectp(obj) && obj->get_object_class() & CLASS_MESSAGEBOARD )
	    m->type = "annotations";
	else
	    m->type = "content";
    }
    if ( m->type == "content" ) {
      if ( objectp(obj) && obj->get_object_class() & CLASS_LINK ) {
	if ( objectp(obj->get_link_object()) )
	  obj = obj->get_link_object();
      }
    }

    object _obj = obj;
    if ( m->object ) 
	_obj = find_object((int)m->object);

    if ( objectp(_obj) ) {
      // handle if-modified-since header as defined in HTTP/1.1 RFC
      // instead of any script called the actually referred object (m->object)
      // is used here for DOC_LAST_MODIFIED
      string mod_since = req->request_headers["if-modified-since"];
      int modified = _obj->query_attribute(DOC_LAST_MODIFIED);
      if ( _obj->get_object_class() & CLASS_DOCUMENT && 
	   m->type == "content" &&
	   _obj->query_attribute(DOC_MIME_TYPE) != "text/wiki" && 
	   !is_modified(mod_since, modified, _obj->get_content_size()) )
	{
	  HTTP_DEBUG("Not modified.");
	  return ([ "error":304, 
		    "data":"not modified", 
		    "extra_heads": (["ETag": "\""+_obj->get_etag()+"\"", ]), 
	  ]);
	}
      
      if ( !(_obj->get_object_class() & CLASS_SCRIPT) ) {
	if ( !check_precondition(_obj) ||
	     !check_notprecondition(_obj) )
	  return low_answer(304, "not modified");
      }
    }

    int authn = authenticate(req->request_headers->authorization, obj);
    if ( authn > 0 ) 
    {
	login_user(_GUEST);
	result = response_loginfailed(_GUEST, m);
	result->extra_heads = 
	    ([ "WWW-Authenticate": "basic realm=\"steam\"", ]);
	// set auth cookie to zero again if auth fails.
	if ( req->cookies->steam_auth )
	    result->extra_heads += ([ 
		"Set-Cookie":
		"steam_auth=;expires=Thu, 01-Jan-70 00:00:01 GMT; path=/",
		]);
	
	result->error=authn;
	return result;
    }


    // make variable mapping compatible with old format used by caudium
    string referer = "none";
    if ( mappingp(req->request_headers) && req->request_headers->referer )
	referer = req->request_headers->referer;
    
    m->__internal = ([ 
      "request_headers": req->request_headers, 
      "client": ({ "Mozilla", }), 
    ]);
    m->referer = referer;
    m->interface = (__admin_port ? "admin" : "public" );

    float tt = gauge {
      err = catch ( result = call_command(req->request_type, obj, m) );
    };
    tt = tt*1000.0;
    int slow = (int)_Server->get_config("log_slow_commands_http");
    if ( slow && (int)tt > slow )
      get_module("log")->log("slow_requests", LOG_LEVEL_INFO, 
			     "%s Request %O in %O took %d ms",
			     timelib.event_time(time()), 
			     req->request_raw,obj,(int)tt);

    if ( mappingp(result) ) {
      string encoding = result->encoding;
      if ( !stringp(encoding) && objectp(obj) )
	encoding = obj->query_attribute(DOC_ENCODING);	
      
      if ( mappingp(result->tags) && !is_dav() && exchange_links(obj)) {
	// run rxml parsing/replacing when file extension is xhtm
	// ! fixme !! how to get the tags mapping ??
	float t;
	
	if ( result->type == "text/html" ) {
	  t = gauge {
	    if ( result->file ) {
	      result->data = result->file->read(result->file->_sizeof());
	      destruct(result->file);
	    }
	    if ( objectp(obj) && obj->get_object_class() & CLASS_CONTAINER )
	      m["env"] = obj;
	    else
	      m["env"]=_fp->path_to_object(dirname(req->not_query),1);
	    
	    m["fp"] = _fp;
	    m["obj"] = obj; 

	    result->data = htmllib.parse_rxml(result->data, 
					      m, 
					      result->tags,
					      encoding);
	    result->length = strlen(result->data);
	  };
	}
      }
    }
    if (mappingp(result) && stringp(result->type)&&stringp(result->encoding)) 
	result->type += "; charset="+result->encoding;
    if ( err ) 
    {
      if ( arrayp(err) && sizeof(err) == 3 && (err[2] & E_ACCESS) ) {
	result = response_noaccess(obj, m);
	HTTP_DEBUG("No access returned...\n");	
	get_module("log")->log("security", LOG_LEVEL_DEBUG, "%O\n%O",
			       err[0], err[1]);
      }
      else {
	FATAL(sprintf("error:\n%O\n%O\n", err[0], err[1]));
	result = response_error(obj, m, err);
      }
    }
    return result;
}

string rewrite_url(string url, mapping headers)
{
    if ( !stringp(headers->host) )
	return url;
    mapping virtual_hosts = _ADMIN->query_attribute("virtual_hosts");
    // virtual_hosts mapping is in the form
    // http://steam.uni-paderborn.de : /steam
    if ( mappingp(virtual_hosts) ) {
      foreach(indices(virtual_hosts), string host) 
	if ( search(headers->host, host) >= 0 )
	  return virtual_hosts[host] + url;
    }
    return url;
}

/**
 * A http request is incoming. Convert the req (Request) object
 * into a mapping.
 *  
 * @param object req - the incoming request.
 */
void http_request(object req)
{
    mapping result;
    int        len;

    __request = req;
    __touch   = time();

    HTTP_DEBUG("HTTP: %O(%O)",req, req->request_headers);

    // read body always...., if body is too large abort.
    len = (int)req->request_headers["content-length"];

    mapping body_variables = read_body(req, len);
    // sometimes not the full body is read
    if ( !mappingp(body_variables) ) {
	// in this case we need to read the body
	req->my_fd->set_nonblocking(read_body_data,0,0);
	return;
    }
    req->my_fd->set_blocking();

    int slow = (int)_Server->get_config("log_slow_commands_http");
    int tt = get_time_millis();
    int loaded_objects = master()->get_in_memory();
    int saved_objects = _Database->get_saves();

    set_this_user(this_object());
    
    mixed err = catch {
	req->variables |= body_variables;
	result = run_request(req);
    };

    if ( err != 0 ) {
	mixed ie = catch {
            result = response_error(0, req->variables, err);
	};
	
	if ( ie ) {
	    FATAL("Internal Server error on error.\n%O\n%O\n",ie[0],ie[1]);
            FATAL("Original Error:\n%O\n%O", err[0], err[1]);
	    result = ([ "error":500, 
			"data":
			"Internal Server Error - contact your administrator",
			"type": "text/html", ]);
	}
    }
    set_this_user(0);
    if (slow) {
      tt = get_time_millis() - tt;
      loaded_objects = master()->get_in_memory() - loaded_objects;
      saved_objects = _Database->get_saves() - saved_objects;

      if ( tt > slow ) 
	MESSAGE("Request %O took %d ms, %d objects loaded, %d saved", 
		req->request_raw, 
		tt,
		loaded_objects,
		saved_objects);
    }

    // if zero is returned, then the http request object is 
    // still working on the request
    if ( mappingp(result) ) {
      respond( req, result );
      __finished = 1;
    }
}

/**
 * Get the appropriate stylesheet for a user to display obj.
 *  
 * @param object user - the active user
 * @param object obj - the object to show
 * @param mapping vars - variables.
 * @return the appropriate stylesheet to be used.
 */
object get_xsl_stylesheet(object user, object obj, mapping vars)
{
    mapping xslMap = obj->query_attribute("xsl:content");
    object     xsl;
    
    // for the presentation port the public stylesheets are used.
    if ( !__admin_port ) {
	xsl = obj->query_attribute("xsl:public");
	if ( !objectp(xsl) )
	    xsl = OBJ("/stylesheets/public.xsl");
	return xsl;
    }
    return httplib.get_xsl_stylesheet(user, obj, vars);
}

/**
 * handle the tasks. Call the task module and try to run a task
 * if any none-automatic task is in the queue then display
 * a html page.
 *  
 * @param object user - the user to handle tasks for
 * @param mapping vars - the variables mapping
 * @return string|int result, 0 means no tasks
 */
string|int run_tasks(object user, mapping vars, mapping client_map)
{
    mixed tasks = __tasks->get_tasks(user);
    string                            html;
    int                           todo = 0;

    if ( arrayp(tasks) && sizeof(tasks) > 0 ) {
	if ( !stringp(vars["type"]) )
	    vars["type"] = "content";
	if ( !stringp(vars->object) )
	    vars->object = (string)user->query_attribute(USER_WORKROOM)->
		get_object_id();
	html = "<form action='/scripts/browser.pike'>"+
	    "<input type='hidden' name='_action' value='tasks'/>"+
	    "<input type='hidden' name='object' value='"+vars["object"]+"'/>"+
	    "<input type='hidden' name='id' value='"+vars["object"]+"'/>"+
	    "<input type='hidden' name='type' value='"+vars["type"]+"'/>"+
	    "<input type='hidden' name='room' value='"+vars["room"]+"'/>"+
	    "<input type='hidden' name='mode' value='"+vars["mode"]+"'/>"+
	    "<h3>Tasks:</h3><br/><br/>";
	
	foreach(tasks, object t) {
	  mixed err = catch {
  	    if ( !objectp(t) ) continue;
	    if ( search(automatic_tasks, t->func) == -1  ) {
	      html += "<input type='checkbox' name='tasks' value='"+
		t->tid+"' checked='true'/><SPAN CLASS='text0sc'> "+
		t->descriptions[client_map["language"]] + 
		    "</SPAN><br/>\n";
	      todo++;
	    }
	    else 	    {
	      if ( t->obj == __tasks || t->obj == 
		   _FILEPATH->path_to_object("/scripts/browser.pike") ) 
		__tasks->run_task(t->tid); // risky ?
	      else
		FATAL("Cannot run unauthorized Task: " + 
		      t->func + " inside %O", t->obj);
	    }
	  };
	  if ( err ) {
	    FATAL("Error while executing task: %O\n%O", err[0], err[1]);
	  }
	}
	__tasks->tasks_done(user);
	html += "<br/><br/><input type='submit' value='ok'/></form>";
	if ( todo > 0 )
	    return html;
    }
    return 0;
}
    

/**
 * Show an object by doing the 'normal' xsl transformation with 
 * stylesheets. Note that the behaviour of this function depends
 * of the type of port used. There is the admin port and the presentation
 * port.
 *  
 * @param object obj - the object to display
 * @param mapping vars - variables mapping
 * @return string|mapping result of transformation
 */
string|int|mapping show_object(object obj, mapping vars)
{
    string     html;

    object user = this_user();

    HTTP_DEBUG("show_object("+obj->describe()+")");

    if ( obj == _ROOTROOM && !_ADMIN->is_member(user) ) {
      mapping result = ([
         "data": redirect("/home/"+user->get_user_name()+"/", 0),
         "extra_heads": ([ "Pragma":"No-Cache", 
                           "Cache-Control":"No-Cache" ]) ]);
      result->type = "text/html";
      result->error = 200;
      return result;
    }
    
    _SECURITY->check_access(obj, user, SANCTION_READ,ROLE_READ_ALL, false);

    mapping client_map = get_client_map(vars);
    if ( user != _GUEST ) {
      if ( !stringp(user->query_attribute(USER_LANGUAGE)) )
	user->set_attribute(USER_LANGUAGE, client_map->language);
    }

    string lang = client_map->language;
    // the standard presentation port shouild behave like a normal webserver
    // so, if present, index files are used instead of the container.
    if ( !__admin_port && obj->get_object_class() & CLASS_CONTAINER )
    {
      if ( obj->query_attribute("cont_type") == "multi_language" ) {
	    mapping index = obj->query_attribute("language_index");
	    if ( mappingp(index) ) {
	      object indexfile = obj->get_object_byname(index[lang]);
	      if ( !objectp(indexfile) )
		indexfile = obj->get_object_byname(index->default);
	      if ( objectp(indexfile) ) {
		// indexfile need to be in the container
		  if ( indexfile->get_environment() == obj ) {
		      vars->type = "content";
		      return handle_GET(indexfile, vars);    
		  }
	      }
	    }
	}
	object indexfile = obj->get_object_byname("index.html");
	if ( objectp(indexfile) ) {
	    vars->type = "content";
	    return handle_GET(indexfile, vars);
	}
    }

    if ( obj->get_object_class() & CLASS_ROOM && !user->contains(obj, true) ) 
    {
	// check for move clients !
	if ( !(user->get_status() & CLIENT_FEATURES_MOVE) ) 
	    user->move(obj);
	else
	    user->add_trail(obj, 20);
	// possible move other users to their home area
	catch(get_module("collect_users")->
	      check_users_cleanup(obj->get_users()));
    }
    else if ( obj->get_object_class() & CLASS_TRASHBIN ) {
	if ( !(user->get_status() & CLIENT_FEATURES_MOVE) ) {
	    object wr = user->query_attribute(USER_WORKROOM); 
	    if ( objectp(wr) )
		user->move(wr);
	}
    }

    if ( __admin_port ) {
	mixed result = run_tasks(user, vars, client_map);
	if ( stringp(result) )
	    return result_page(result, "no");
    }

    
    // PDA detection - use different stylesheet (xsl:PDA:content, etc)
    if ( client_map["xres"] == "240" ) 
	vars->type = "PDA:" + vars->type;

    vars |= client_map;

    object xsl = get_xsl_stylesheet(user, obj, vars);
    if ( !objectp(xsl) ) 
      error("Failed to find xsl stylesheet !");

    HTTP_DEBUG("Using stylesheet: "+xsl->describe());
    html = run_xml(obj, xsl, vars);

    if ( !stringp(html) )
	error("Failed to process XSL (Stylesheet is " +
	      _FILEPATH->object_to_filename(xsl) + ")");

    if ( vars->source == "true" )
	return ([ 
	    "data"   : html, 
	    "length" : strlen(html), 
	    "type"   : "text/xml", ]);

    string method = "text/"+xsl->get_method();
    
    return ([ "data": html, 
	      "length": strlen(html), 
	      "type": "text/html",
	      "tags": find_tags(xsl), 
	      "encoding": xsl->get_encoding(),
    ]);
}


mapping response_noaccess(object obj, mapping vars)
{
    mapping result;
    object script;
    object noaccess = OBJ("/documents/access.xml");
    vars->type = "content";
    result = handle_GET(noaccess, vars);


    // on the admin port users are already logged in - so just show no access
    if ( this_user() == _GUEST && (__admin_port || !_Server->query_config("secure_credentials")) )
      result->error = 401;
    else
      result->error = (__admin_port ? 403 : 
		       ( _Server->query_config("secure_credentials") ? 
			 403 : 401 ) );

    if ( result->error == 401 )
	result->extra_heads = 
	    ([ "WWW-Authenticate": "basic realm=\"steam\"", ]);

    result->type = "text/html";
    string ressource = __request->not_query;
    if ( objectp(obj) && obj->get_object_class() & CLASS_SCRIPT ) {
	script = obj;
	if ( vars->id )
	    obj = find_object((int)vars->id);
	else if ( vars->object )
	    obj = find_object((int)vars->object);
	else if ( vars->path ) {
	    if ( objectp(vars->fp) )
		obj = vars->fp->path_to_object(vars->path);
	}
    }
    if ( objectp(obj) ) {
	if ( !objectp(obj->get_environment()) )
	    ressource = obj->get_identifier();
	else if ( objectp(vars->fp) )
	    ressource = vars->fp->object_to_filename(obj);
    }
    if ( !stringp(ressource) ) ressource = "0";
    if ( objectp(script) && vars->_action && script->is_function("translate"))
	ressource = script->translate(vars->_action, vars->language) + " " + 
	    ressource;
	
    result->data = replace(result->data, ({ "{FILE}", "{USER}" }), 
			   ({ ressource, 
				  this_user()->get_identifier() }));
    return result;
}

mapping response_too_large_file(object req)
{
    string html = error_page(
	"The amount of form/document data you are trying to "+
	"submit is<br/>too large. Use the FTP Protocol to upload files "+
	"larger than 20 MB.");
    return ([ "data": html, "type":"text/html", "error":413, ]);
}

mapping response_notfound(string|int f, mapping vars)
{
    string html = "";
    object xsl, cont;

    HTTP_DEBUG("The object %O was not found on server.", f);

    if ( zero_type(f) )
	f = __request->not_query;
    
    xsl = OBJ("/stylesheets/notfound.xsl");
    if ( !objectp(xsl) || xsl->get_content_size() == 0 ) {
      return ([ "error":404,"data":"Unable for find "+f,"type":"text/plain"]);
    }
    if ( stringp(f) ) {
	string path = f;
	array tokens = path / "/";

	
	for ( int i = sizeof(tokens)-1; i >= 1; i-- )
	{
	    path = tokens[..i]*"/";
	    cont = _fp->path_to_object(path);
	    if ( objectp(cont) ) {
		catch(xsl = cont->query_attribute("xsl:notfound"));
	        if ( !objectp(xsl) )
		    xsl = OBJ("/stylesheets/notfound.xsl");
		break;
	    }
	}
    }
    else {
	f = "Object(#"+f+")";
    }
    if ( !objectp(cont) )
	cont = _ROOTROOM;

    f = string_to_utf8(f);
    f = replace(f, "&", "&amp;");
    f = replace(f, "%", "%25");
    f = replace(f, "<", "&lt;");
    f = replace(f, ">", "&gt;");
    string xml =  
	"<?xml version='1.0' encoding='utf-8'?>\n"+
	"<error><actions/>"+
	"<message><![CDATA[The Document '"+f+"' was not found on the "+
	"Server.]]></message>\n"+
	"<orb>"+_fp->get_identifier()+"</orb>\n"+
	"<url>"+f+"</url>\n"+
	"<user>"+this_user()->get_identifier()+"</user>\n"+
	"<container>"+get_module("Converter:XML")->show(cont)+
	get_module("Converter:XML")->get_basic_access(cont)+
	"</container>\n"+
	"</error>";

    html = run_xml(xml, xsl, vars);
    html += "\n<!--"+xml+"-->\n";
    mapping result = ([
	"error":404,
	"data":html,
	"type":"text/html",
	]);
    return result;
}

mapping response_error(object obj, mapping vars, mixed err)
{
  string xml, html, btname;
  
  FATAL("err=%O\n", err);
  if ( objectp(err) && functionp(err->display) && err->display() == 1 )
  {
      html = result_page(err->message(), "JavaScript:history.back();");
      return ([ "data": html, "type": "text/html", "error": 500, ]);
  }

  FATAL("err=%s\n%O\n", err[0], err[1]);
  int errid = time();
  btname = "html_backtrace_"+errid;
  catch(vars->__internal->request_headers["authorization"] = "********");
  object bt = 
    _Server->insert_backtrace(btname, 
			      "<html><body><b>Requesting "+
			      __request->not_query+"</b>"+
			      replace(err[0],({"<",">","\n" }), 
				      ({"&lt;","&gt;","<br/>"}))+
			      backtrace_html(err[1]) + "<br/><br/>"+
			      replace(sprintf("%O", vars), "\n", "<br/>")+
			      "</body></html>");
  object err_cont = OBJ("/documents/errors");
  xml = "<h3>An error occured while processing your request !</h3>";

  if ( objectp(err_cont) ) {
    mapping err_index = err_cont->query_attribute("language_index");
    if ( mappingp(err_index) ) {
      object errdoc = err_cont->get_object_byname(err_index[identify_language(__request->request_headers)]);
      if ( objectp(errdoc) )
	xml = errdoc->get_content();
    }
  }
  xml += "<br/>&#160;"+
    "Detailed Error Description: <a href='/backtraces/"+btname+"'>"+ _Server->query_config("web_server")  +"/backtraces/"+btname+"</a><br /><br />&#160;Error data:"+
    "<ul><li>ID: "+errid+"</li><li>Object: "+
    (objectp(obj) ? _FILEPATH->object_to_filename(obj)+
     "("+obj->get_object_id()+")":"none")+
    "</li>"+
    "<li>Report Bug: <a href=\"http://www.open-steam.org:8080/jira\">http://www.open-steam.org:8080/jira</a></li>"+
    "</ul>";
  object xsl = OBJ("/stylesheets/errors.xsl");
  xml =  
    "<?xml version='1.0' encoding='utf-8'?>\n"+
    "<error><actions/><message><![CDATA["+xml+"]]></message></error>";
  html = run_xml(xml, xsl, vars);
  return ([ "data": html, "type": "text/html", "error": 500, ]);
}

mapping response_loginfailed(object obj, mapping vars)
{
    string message = "<html><head><title>Login failed</title></head><body><br />Login Failed !<br /><br /></body></html>";
    object xsl = OBJ("/stylesheets/login_failed.xsl");

    if ( !objectp(xsl) )
      return ([ "data": message , "type":"text/html", "error":500,]);

    string xml =  
	    "<?xml version='1.0' encoding='utf-8'?>\n"+
	    "<error><actions/><message><![CDATA["+ message +
	    "]]></message></error>";
      
    string html = run_xml(xml, xsl, vars);
    return ([ "data": html, 
	      "type": "text/html",
	      "error": 500, ]);  
}

static void async_respond(object res, mixed data)
{
  if (res->webservice) {
    mapping callResults = res->userData->callResults;
    res->userData->callResults[res->userData->callNode]->result = data;
    foreach(values(callResults), mixed result) {
      if ( !stringp(result->result) )
	return;
    }
    object envelope = soap.SoapEnvelope();
    soap.add_service_results(envelope, callResults);
    data = ([ "data": envelope->render(), "type": "text/xml", "error":200, ]);
    respond(__request, data);
  }
  else {
    data = ([ "data": data, "type": res->mimetype, "error":200, ]);
    respond(__request, data);
  }
}

static void respond(object req, mapping result)
{
    if ( objectp(req->my_fd) )
      req->my_fd->set_close_callback(close_connection);
    result->server = "sTeam Webserver";
    
    if ( __REAL_MAJOR__ == 7 && __REAL_MINOR__ <= 4 ) {
	if ( mappingp(result->extra_heads) ) 
	    result->extra_heads->connection = "close";
	else
	    result->extra_heads = ([ "connection": "close" ]);
    }
    if ( !result->error )
	result->error = 200;
    int length = result->length;
    if ( !length ) {
	if ( stringp(result->data) )
	    length = strlen(result->data);
	else if ( objectp(result->file) )
	    length = result->file->_sizeof();
    }
    else {
	if ( stringp(result->data) )
	    if ( length != strlen(result->data) )
		steam_error("Length mismatch in http!\n");
    }
    get_module("log")->log("http", LOG_LEVEL_INFO, "%s - - %s \"%s\" %d %d \"%s\" \"%s\"",
			   get_ip() || "unknown", 
			   timelib.event_time(time()), 
			   __request->request_raw,
			   result->error,
			   length,
			   __request->request_headers["referer"] || "-",
			   __request->request_headers["user-agent"] || "-");
    req->response_and_finish(result);
    req = 0;
}

string|int get_ip()
{
  mixed   err;
  string addr;
  
  err = catch {
    addr = __request->my_fd->query_address();
  };
  if ( err != 0 )
    addr = "no connected";
  string ip = 0;
  if ( stringp(addr) )
    sscanf(addr, "%s %*d", ip);
      
  return ip;
}

void close_connection()
{
  HTTP_DEBUG("HTTP: Closing Connection !");
  master()->unregister_user(this_object());
  if ( objectp(__request) ) {
    HTTP_DEBUG("HTTP: Closing request socket: %O", __request->my_fd);
    //    catch(respond(__request, low_answer(200, "ok") ));
    catch(__request->my_fd->close());
  }
  if ( objectp(__docfile) ) {
      HTTP_DEBUG("HTTP: Closing file... %O", __docfile);
      catch(__docfile->close());
      catch(destruct(__docfile));
  }
  logout_user();
}

string describe() 
{ 
  return "HTTP-Request(" + ::describe() + 
    ",idle="+get_idle()+"s,closed="+is_closed()+")"; 
}

int get_last_response() 
{
    mixed err;
    if ( objectp(__request) ) {
	HTTP_DEBUG("HTTP:Last Response is %O\n", __request->my_fd);
	err = catch {
	    if ( !__request->my_fd || 
		 ( functionp(__request->my_fd->is_open) && 
		   !__request->my_fd->is_open() == 0) ) 
	    {
		HTTP_DEBUG("HTTP: closed connection ...\n");
		return 0;
	    }
	};
	if ( err != 0 )
	    return 0;
    }
    if ( objectp(__docfile) )
	return __docfile->get_last_response();
    return __touch; 
}

string get_socket_name() { return "http"; }
int is_closed() { return __finished; }
int get_client_features() { return 0; }
string get_client_class() { return "http"; }
string get_identifier() { return "http"; }
object get_object() { return this_object(); }
int get_idle() { return time() - __touch; }
object this() { return this_object(); }
