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
 * $Id: webdavlib.pmod,v 1.2 2009/08/07 15:22:37 nicke Exp $
 */

constant cvs_version="$Id: webdavlib.pmod,v 1.2 2009/08/07 15:22:37 nicke Exp $";

import httplib;

#include <config.h>
#include <macros.h>

//#define WEBDAV_DEBUG

#ifdef WEBDAV_DEBUG
#define DAV_WERR(s, args...) werror(s+"\n", args)
#else
#define DAV_WERR(s, args...) 
#endif

#define TYPE_DATE  (1<<16)
#define TYPE_DATE2 (1<<17)
#define TYPE_FSIZE (1<<18)
#define TYPE_EXEC  (1<<19)

class Property {
  void create(string p) {
    prop = p;
    ns = 0;
  }
  void set_namespace(NameSpace n) {
    ns = n;
  }
  string describe_namespace() {
    if ( !objectp(ns) )
      return "";
    return ns->get_name();
  }
  void set_value(string v) { 
    value = v;
  }
  string get_value() {
    return value;
  }
  string get_name() {
    return prop;
  }
  string get_ns_name() {
    if ( objectp(ns) ) {
      string id = ns->get_id();
      if ( stringp(id) ) {
	return sprintf("%s:%s", id, prop);
      }
    }
    return prop;
  }
  
  string get() {
    if ( objectp(ns) ) {
      string id = ns->get_id();
      if ( stringp(id) ) {
	return sprintf("<%s:%s xmlns:%s=\"%s\">" + value + "</%s:%s>", 
		       id, prop, id, ns->get_name(), id, prop);
      }
	return sprintf("<%s xmlns=\"%s\">" + value + "</%s>", 
		       prop, ns->get_name(), prop);
    }
    return prop;
  }
  object get_namespace() {
    return ns;
  }
  string _sprintf() {
    return "Property("+prop+","+describe_namespace()+")";
  }
  static string  prop;
  static string value;
  static NameSpace ns;
}

class NameSpace {
  static array(Property) props;
  static string       name, id;

  string get_name() { return name; }
  void create(string n) { 
    name = n;
    props = ({ });
  }
  void set_id(string i) {
    id = i;
  }
  string get_id() { 
    return id;
  }

  void add_prop(Property p) {
    props += ({ p });
    p->set_namespace(this_object());
  }
  Property get_prop(string name) {
    
    foreach(props, Property p) {
      if ( p->get_name() == name )
	return p;
    }
    return 0;
  }
}

static mapping mNameSpaces; // available namespaces

void create()
{
  mNameSpaces = ([ "" : NameSpace(""), ]);
}

array parse_if_header(string header)
{
  array result = ({ });
  if ( !stringp(header) )
    return result;
  string resource, list;
  header = String.trim_all_whites(header);
  // tagged list
  
  //werror("Parsing header: %s\n", header);
  while ( strlen(header) > 0 && 
          sscanf(header, "%s(%s)%s", resource, list, header) > 0 )
  {
    string url, state, entity;

    //werror("---\nLIST=%s\nRESOURCE=%s\nREST=%s\n---\n", list, resource,header);
    mapping res = ([ ]);
    if ( search(lower_case(resource), "not") == 0 ) {
      res->not = 1;
      resource = resource[3..];
    }
    resource = String.trim_all_whites(resource);
    if ( sscanf(resource, "<%s>", url) ) {
      if ( sscanf(url, "%*s://%*s/%s", url) > 0 )
        url = "/" + url;

      res->resource = url;
    }
    
    sscanf(list, "<%s>%s", state, list);
    list = String.trim_all_whites(list);
    sscanf(list, "[%s]", entity);

    res->state = state;
    res->entity = entity;
    result += ({ res });
  }
  return result;
}

NameSpace add_namespace(string name, void|string id)
{
  if ( stringp(id) && (!stringp(name) || name == "") )
    error("Invalid namespace!");
  if ( mNameSpaces[name] ) 
    return mNameSpaces[name];
  NameSpace n = NameSpace(name);
  mNameSpaces[n->get_name()] = n;
  n->set_id(id);
  mNameSpaces[id] = n;
  return n;
}

NameSpace get_namespace(string name, void|string id)
{
  if ( mNameSpaces[id] )
    return mNameSpaces[id];
  
  if ( name == "" )
    return 0;

  if ( !stringp(name) )
    return mNameSpaces[""];

  if ( name == "DAV:" )
    return mNameSpaces[""];
  
  NameSpace n = mNameSpaces[name];
  if ( !objectp(n) ) {
    DAV_WERR("Failed to find namespace %s", name);
    return 0;
  }
    
  return n;
}

Property find_prop(string ns, string pn) 
{
  NameSpace n = get_namespace(ns);
  if ( objectp(n) ) {
    Property p = n->get_prop(pn);
    if ( !objectp(p) ) {
      p = Property(pn);
      n->add_prop(p);
    }
    return p;
  }
  return 0;
}
  
    

class WebdavHandler {
// the stat file function should additionally send mime type
#if 0
  array get_directory(string fname) { }
  mixed stat_file(mixed f) { }
  string resolve_redirect(mixed ctx) { }
  int set_property(mixed ctx, Property p, mapping namespaces) { }
  mixed get_property(mixed ctx, Property p) { }
  mixed get_context(mixed old_ctx, string f) { }
#endif

  void lock(mixed ctx, string fname) { }
  void unlock(mixed ctx, string fname) { }
  int is_locked(mixed ctx, string fname) { }

  function stat_file; 
  function resolve_redirect;
  function get_directory;
  function set_property;
  function get_property;
  function get_context;
  function is_link;
 
}


static mapping properties = ([
    "getlastmodified":3|TYPE_DATE,
    "creationdate":2|TYPE_DATE,
    ]);

static array _props = ({"getcontenttype","resourcetype", "getcontentlength", "href", "lockdiscovery", "getetag", "supportedlock" })+indices(properties);
			    
array(string) get_dav_properties(array fstat)
{
    return _props;
}

string concat_namespaces(mapping ns, void|int intSpaces)
{
  string res = "";
  if ( !mappingp(ns) )
    return res;
  foreach ( indices(ns), mixed nsid) {
    if ( !intSpaces && stringp(nsid) )
      res += sprintf(" xmlns:%s=\"%s\"", nsid, ns[nsid]);
    else if ( intSpaces && intp(nsid) )
      res += sprintf(" xmlns:ns%d=\"%s\"", nsid, ns[nsid]);
  }
  return res;
}

/**
 * Retrieve the properties of some file by calling the
 * config objects stat_file function.
 *  
 * @param string file - the file to retrieve props
 * @param mapping xmlbody - the xmlbody of the request
 * @param array|void fstat - file stat information if previously available
 * @return xml code of properties
 */
string retrieve_props(string file, mapping xmlbody, array fstat, 
		      WebdavHandler h, mixed context) 
{
    string response = "";
    string unknown_props;
    string   known_props;
    array        __props;
    string      property;

    if ( !arrayp(fstat) ) {
	error("Failed to find file: " + file);
	return "";
    }

    if ( sizeof(fstat) < 8 ) {
	if ( fstat[1] < 0 )
	    fstat += ({ "httpd/unix-directory" });
	else
	    fstat += ({ "application/x-unknown-content-type" });
    }

    unknown_props = "";
    known_props = "";
    __props = get_dav_properties(fstat);

    mapping mprops = ([ ]);
    mapping nsmap  = copy_value(xmlbody->namespaces);
    m_delete(xmlbody, "namespaces");
    if ( !mappingp(nsmap) )
	nsmap = ([ ]);
    
    if ( !xmlbody->allprop ) {
	foreach(indices(xmlbody), Property p) {
	    if ( !objectp(p) )
	      continue;
	    string property = p->get_name();  
	    if ( property == "allprop" || property == "")
		continue;
	    if ( search(__props, property) == -1 ) {
	      mixed val = h->get_property(context, p);
	      if ( val != 0 ) {
		object ns = p->get_namespace();
		if ( ns->get_name() != "DAV:" ) {
		  if ( ns->get_id() != 0 ) {
		    nsmap[ns->get_id()] = ns->get_name();
		    known_props += "<"+ns->get_id() + ":" +property+
		      ">"+val+"</"+ns->get_id()+":" + property + ">\r\n";
		  }
		  else {
		    known_props += "<"+property+ " xmlns=\""+ns->get_name()+
		      "\">"+val+"</"+property + ">\r\n";
		  }
		}
		else
		  known_props += "<D:"+property+">"+val+"</D:"+property+">\r\n";
	      }
	      else {
		object ns = p->get_namespace();
		if ( objectp(ns) && ns->get_name() != "DAV:" ) {
		  if ( ns->get_id() != 0 ) {
		      nsmap[ns->get_id()] = ns->get_name();
		    unknown_props += "<"+ns->get_id() + ":" +property+"/>\r\n";
		  }
		  else {
		    unknown_props += "<"+property+ " xmlns=\""+ns->get_name()+
		      "\"/>\r\n";
		  }
		}
		else
		  unknown_props += "<i0:"+property+"/>\r\n";
	      }
	    }
	    else
	      mprops[p->get_name()] = 1;    
	}
    } 

    response += "<D:response"+
      (strlen(unknown_props) > 0 ? " xmlns:i0=\"DAV:\"":"") + 
      concat_namespaces(nsmap) + ">\r\n";
    
    if ( fstat[1] < 0 && file[-1] != '/' ) file += "/";

    response += "<D:href>"+h->url_name(file) + "</D:href>\r\n";

    if ( mprops->propname ) {
	response += "<D:propstat>\r\n";	   
	// only the normal DAV namespace properties at this point
	response += "<D:prop>";
	foreach(__props, property) {
	    if ( fstat[1] < 0 )
		response += "<"+property+"/>\r\n";
	}	
	response += "</D:prop>";
	response += "</D:propstat>\r\n";
    }

    if ( sizeof(mprops) > 0 || xmlbody->allprop || strlen(known_props) > 0 ) 
    {
      response += "<D:propstat>\r\n";
      response += "<D:prop xmlns:lp0=\"DAV:\" xmlns:lp1=\"http://apache.org/dav/props\">\r\n";
      
      
      if ( fstat[1] == -2 ) { // its a directory
	if ( mprops->resourcetype || xmlbody->allprop ) 
	  response+="<D:resourcetype><D:collection/></D:resourcetype>\r\n";
	if ( mprops->getcontentlength )
	  response += "<D:getcontentlength></D:getcontentlength>\r\n";
      }
      else { // normal file
	if ( mprops->resourcetype || xmlbody->allprop )
	  response += "<D:resourcetype/>\r\n";
	if ( mprops->getcontentlength || xmlbody->allprop )
	  response += "<D:getcontentlength>"+fstat[1]+
	    "</D:getcontentlength>\r\n";
	if ( h->is_link(context) ) {
	  response += "<D:link><D:src>"+h->url_name(file) + "</D:src><D:dst>"+
	    h->resolve_redirect(context) + "</D:dst></D:link>\n";
	  //response += "<D:reftarget><D:href>"+h->resolve_redirect(context)+
	  //"</D:href></D:reftarget>\r\n";
	}
      }
      
      if ( mprops->getcontenttype || xmlbody->allprop )
	response+="<D:getcontenttype>"+fstat[7]+
	  "</D:getcontenttype>\r\n";
      
      
      foreach(indices(properties), string prop) {
	if ( mprops[prop] || xmlbody->allprop ) {
	  if ( properties[prop] & TYPE_DATE ) {
	    response += "<lp0:"+prop+" xmlns:b="+
	      "\"urn:uuid:c2f41010-65b3-11d1-a29f-00aa00c14882/\""+
	      " b:dt=\"dateTime.rfc1123\">";
	    response += http_date(fstat[properties[prop]&0xff]);
	    response += "</lp0:"+prop+">\r\n";
	  }
	  else if ( properties[prop] & TYPE_FSIZE ) {
	    int sz = fstat[(properties[prop]&0xff)];
	    if ( sz >= 0 ) { 
	      response += "<lp0:"+prop+">";
	      response += sz;
	      response += "</lp0:"+prop+">\r\n";
	    }
	  }
	  else if ( properties[prop] & TYPE_EXEC ) {
	    //int stats = fstat[0][
	  }
	}
      }
      if ( mprops->getetag || xmlbody->allprop ) {
	response += "<lp0:getetag>\""+h->get_etag(context) +"\"</lp0:getetag>\n";
      }
#ifdef WEBDAV_CLASS2
      if ( mprops->supportedlock || xmlbody->allprop ) {
	response += "<D:supportedlock>";
	response += "<D:lockentry>\n";
	response += "  <D:lockscope>exclusive</D:lockscope>\n";
	response += "  <D:locktype>write</D:locktype>\n";
	response += "</D:lockentry>\n";
	response += "<D:lockentry>\n";
	response += "  <D:lockscope>shared</D:lockscope>\n";
	response += "  <D:locktype>write</D:locktype>\n";
	response += "</D:lockentry></D:supportedlock>\n";
      }
      if ( mprops->lockdiscovery || xmlbody->allprop) 
	response += "<D:lockdiscovery>" + discover_lock(file, h, context) + 
	  "</D:lockdiscovery>\n";
      
#endif
      
      response += known_props;
      response+="</D:prop>\r\n";
      response+="<D:status>HTTP/1.1 200 OK</D:status>\r\n";
      response+="</D:propstat>\r\n";
    }

    // props not found...
    if ( strlen(unknown_props) > 0 ) {
	response += "<D:propstat>\r\n";
	response += "<D:prop>\r\n";
	response += unknown_props;
	response += "</D:prop>\r\n";
	response += "<D:status>HTTP/1.1 404 Not Found</D:status>\r\n";
	response += "</D:propstat>\r\n";
    }

    response += "</D:response>\r\n";    
    return response;
}

/**
 * Retrieve the properties of a colletion - that is if depth
 * header is given the properties of the collection and the properties
 * of the objects within the collection are returned.
 *  
 * @param string path - the path of the collection
 * @param mapping xmlbody - the xml request body
 * @return the xml code of the properties
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string
retrieve_collection_props(string colpath, mapping xmlbody, WebdavHandler h, mixed context)
{
    string response = "";
    int                i;
    mapping       fstats;
    array      directory;


    int         len;
    array     fstat;
    
    directory = h->get_directory(colpath);
    len = sizeof(directory);
    
    string path;
    fstats = ([ ]);
    
    for ( i = 0; i < len; i++) {
	DAV_WERR("stat_file("+colpath+"/"+directory[i]);
	if ( strlen(colpath) > 0 && colpath[-1] != '/' )
	    path = colpath + "/" + directory[i];
	else
	    path = colpath + directory[i];
	fstat = h->stat_file(path, this_object());
	if ( !arrayp(fstat) ) {
	  DAV_WERR("Skipping %s", path);
	  continue;
	}
	else if ( fstat[1] >= 0 )
	    response += 
	      retrieve_props(path, xmlbody, fstat, h, 
			     h->get_context(context, directory[i]));
	else
	    fstats[path] = fstat;
    }
    foreach(indices(fstats), string f) {
	string fname;

	if ( f[-1] != '/' ) 
	    fname = f + "/";
	else
	    fname = f;
	response += retrieve_props(fname, xmlbody, fstats[f], h, context);
    }
    return response;
}

/**
 * Converts the XML structure into a mapping for prop requests
 *  
 * @param object node - current XML Node
 * @param void|string pname - the name of the previous (father) node
 * @return mapping
 */
mapping convert_to_mapping(object node, void|string pname)
{
    string tname = node->get_tag_name();
    string                      ns = "";
    NameSpace                    nspace;

    // find all namespaces first
   
    ns = node->get_ns();
      
    DAV_WERR("node: %s (of %O)", tname, ns);
    // add or lookup local namespace
    mapping m = ([ "namespaces": ([ ]), ]);

    if ( ns != 0 ) 
	nspace = add_namespace(ns, node->get_ns_prefix()); 
       
    if ( tname == "allprop" )
      return ([ "allprop": find_prop("", "allprop"), ]);
    
    if ( stringp(nspace->get_id()) && nspace->get_id() != "" )
	m->namespaces[nspace->get_id()] = nspace->get_name();

    if ( pname == "prop" || tname == "allprop" ) {
      Property p = nspace->get_prop(tname);
      if ( !objectp(p ) ) {
	p = Property(tname);
	nspace->add_prop(p);
      }
      m[p] = nspace->get_name();
      p->set_value(node->get_text());
    }
    array(object) elements = node->get_children();
    foreach(elements, object n) {
	m += convert_to_mapping(n, tname);
    }
    return m;
}      


/**
 * Parse body data and return a mapping.
 *  
 * @param string data - the data of the XML body.
 */
mapping get_xmlbody_props(string data)
{
  mapping xmlData= ([ ]);
  object            node;

    if ( !stringp(data) || strlen(data) == 0 ) {
      xmlData = ([ "allprop": Property("allprop"), ]);
	// empty BODY treated as allprop
    }
    else {
      node = xmlDom.parse(data);
      xmlData = convert_to_mapping(node);
      // add all root namespaces...
      mapping nsmap = node->get_namespaces();
      int cnt = 1;
      foreach(indices(nsmap), string nsprefix) {
	if ( stringp(nsprefix) && nsprefix != "" ) {
	  xmlData->namespaces[cnt] = nsmap[nsprefix];
	  cnt++;
	}
      }
    }
    DAV_WERR("Props mapping:\n"+sprintf("%O", xmlData));
    return xmlData;
}

array(object) get_xpath(object node, array(string) expr)
{
    array result = ({ });
    
    if ( expr[0] == "/" )
	throw( ({ "No / in front of xpath expresions", backtrace() }) );
    array childs = node->get_children();
    foreach(childs, object c) {
	string tname;
	tname = c->get_tag_name();
	sscanf(tname, "%*s:%s", tname); // this xpath does not take care of ns
	
	if ( tname == expr[0] ) {
	    if ( sizeof(expr) == 1 )
		result += ({ c });
	    else
		result += get_xpath(c, expr[1..]);
	}
    }
    return result;
}

mapping|string resolve_destination(string destination, string host)
{
    string dest_host;

    if ( sscanf(destination, "%*s://%s/%s", dest_host, destination) == 2 )
    {
	if ( dest_host != host ) 
	    return low_answer(502, "Bad Gateway");
	destination = "/" + destination;
    }
    return destination;
}

/**
 *
 *  
 * @param 
 * @return 
 * @see 
 */
mapping get_properties(object n)
{
    mapping result = ([ ]);
    foreach(n->get_children(), object c) {
	string tname = c->get_tag_name();
	if ( search(tname, "prop") >= 0 ) {
	    foreach (c->get_children(), object prop) {
		if ( prop->get_tag_name() == "" ) continue;
		// make sure no wide strings appear
		string xmlns = prop->get_ns();
		NameSpace nspace = add_namespace(xmlns, prop->get_ns_prefix());

		if ( !objectp(nspace) )
		  error("Namespace " + xmlns+
			" not found for property " + prop->get_tag_name());
		
		Property p = find_prop(xmlns, prop->get_tag_name());
		if ( !objectp(p) ) {
		  p = Property(prop->get_tag_name());
		  nspace->add_prop(p);
		}
		result[p] = xmlns;
		
		if ( String.width(prop->value_of_node()) == 8 ) 
		  p->set_value(prop->value_of_node());
		else
		  p->set_value(string_to_utf8(prop->value_of_node()));
	    }
	}
    }
    return result;
}

mapping|void proppatch(string url, mapping request_headers, string data, WebdavHandler h, mixed context)
{
    mapping          result;
    object             node;
    array(object)     nodes;
    string         response;
    string host = request_headers->host;
    
    DAV_WERR("Proppatch data = %O", data);


    if ( !stringp(url) || strlen(url) == 0 )
	url = "/";
    
    response ="<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
    response+="<D:multistatus xmlns:D=\"DAV:\">\n";
    response+="<D:response>\n";
    
    array fstat = h->stat_file(url, this_object());
    response += "<D:href>http://"+host+url+"</D:href>\n";

    node = xmlDom.parse(data);
    if ( !objectp(node) ) {
	error("Fatal error: Failed to parse data %O", data);
    }
    //nodes = get_xpath(node, ({ "propertyupdate" }) );
    nodes = node->get_nodes("/propertyupdate");
    if ( sizeof(nodes) == 0 ) 
	error("No propertyupdates given !");

    mapping namespaces = nodes[0]->get_attributes();
    DAV_WERR("Namespaces:\n"+sprintf("%O", namespaces));
#if 0
    array sets    = get_xpath(nodes[0], ({ "set" }));
    array updates = get_xpath(nodes[0], ({ "update" }));
    array removes = get_xpath(nodes[0], ({ "remove" }));
#endif
    array sets    = nodes[0]->get_nodes("set");
    array updates = nodes[0]->get_nodes("update");
    array removes = nodes[0]->get_nodes("remove");

    object n;
    foreach(sets+updates, n) {
	mapping props = get_properties(n);
	foreach (indices(props), Property p) {
	    int patch;
	    string prop = p->get_name();
	    response += "<D:propstat>\n";
	    patch = h->set_property(context, p, namespaces);
	    response += "<D:prop>"+p->get()+"</D:prop>\n";
	    response += "<D:status>HTTP/1.1 "+
		(patch ? " 200 OK" : " 403 Forbidden")+ "</D:status>\r\n";
	    response += "</D:propstat>\n";
	}
    }
    foreach(removes, n) {
	mapping props = get_properties(n);
	foreach (indices(props), Property p) {
	    int patch;
	    string prop = p->get_name();
	    response += "<D:propstat>\n";
	    p->set_value(0);
	    patch = h->set_property(context, p, namespaces);
	    response += "<D:prop>"+p->get()+"</D:prop>\n";
	    response += "<D:status>HTTP/1.1 "+
		(patch ? " 200 OK" : " 403 Forbidden")+ "</D:status>\r\n";
	    response += "</D:propstat>\n";
	}
      
    }

    response+="</D:response>\n";
    response+="</D:multistatus>\n";
    DAV_WERR("RESPONSE="+response);
    result = low_answer(207, "Multi-Status");
    result["type"] = "text/xml; charset=\"utf-8\"";
    result->data = response;
    return result;
}

mapping|void propfind(string raw_url,mapping request_headers,string data,WebdavHandler h, mixed context)
{
    mapping result, xmlData;
    string         response;

    mixed err = catch {
      xmlData = get_xmlbody_props(data);
    };
    if ( err != 0 ) {
      if ( sizeof(err) >= 2 )
	DAV_WERR("Error in get_xmlbody_props: %O\n%O", 
		 err[0], describe_backtrace(err[1]));
      DAV_WERR("Webdav error: %O", err);
      return low_answer(400, "bad request");
    }
	
    response ="<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
    
    if ( !stringp(raw_url) || strlen(raw_url) == 0 )
	raw_url = "/";
    
    array fstat = h->stat_file(raw_url, this_object());
    
    if ( !stringp(request_headers->depth) )
	request_headers["depth"] = "infinity";
    

    if ( !arrayp(fstat) ) {
        DAV_WERR("404");
	return low_answer(404,"");
    }
    else if ( fstat[1] < 0 ) {
	response += "<D:multistatus xmlns:D=\"DAV:\""+concat_namespaces(xmlData->namespaces, 1)+">\r\n";
	if ( request_headers->depth != "0" ) 
	  response += retrieve_collection_props(raw_url, xmlData, h, context);
	response += retrieve_props(raw_url, xmlData, fstat, h, context);
	response += "</D:multistatus>\r\n";
    }
    else {
	response += "<D:multistatus xmlns:D=\"DAV:\""+concat_namespaces(xmlData->namespaces, 1)+">\r\n";
	response += retrieve_props(raw_url, xmlData, 
				   h->stat_file(raw_url), h, context);
	response += "</D:multistatus>\r\n";
    }
    DAV_WERR("Propfind reponse=\n%s", response);
    result = low_answer(207, "Multi-Status");
    result->data = response;
    result["type"] = "text/xml; charset=\"utf-8\"";
    return result;
}

static string discover_lock(string fname, object handler, mixed ctx)
{
    mapping locks = handler->get_locks(ctx, fname);
    string response = "";
    foreach(indices(locks), string lock) {
	mapping result = locks[lock];
	if ( !mappingp(result) )
	  continue;
	response += "<D:activelock>\n";
	response += "<D:locktype><D:"+result->locktype+"/></D:locktype>\n";
	response += "<D:lockscope><D:"+result->lockscope+"/></D:lockscope>\n";
	
	if ( result->owner )
	    response+="<ns0:owner xmlns:ns0=\"DAV:\">"+result->owner+"</ns0:owner>\n";
	if ( result->timeout )
	    response += "<D:timeout>" + result->timeout + "</D:timeout>";
	response += "<D:depth>"+result->depth+"</D:depth>\n";
	if ( result->token )
	    response += "<D:locktoken><D:href>"+result->token+
		"</D:href></D:locktoken>\n";
	
	response += "</D:activelock>\n";
    }
    return response;
}

string get_opaquelocktoken(string ifHeader)
{
    if ( !stringp(ifHeader) )
	return 0;
    // this is fully invalid ;-) But works most of the time I guess
    array tokens = ifHeader / " ";
    foreach(tokens, string token) {
	if ( search(token, "opaquelocktoken") >= 0 ) {
	    if ( token[0] == '(' )
		sscanf(token, "(<%s>)", token);
	    else
		sscanf(token, "<%s>", token);
	    return token;
	}
    }
    return 0;
}

string get_lock_token(mapping headers)
{
    string token = headers["lock-token"];
    sscanf(token, "<%s>%*s", token);
    return token;
}


mapping lock(string fname, mapping headers, string body, object handler, mixed ctx)
{
    mapping lock_data, currentLock;
    DAV_WERR("lock(%s %s)", body, (objectp(ctx)?"":"null resource!"));
    DAV_WERR("Authorization: %O", headers);
    
    currentLock = handler->is_locked(ctx, fname);
    string tokenHead = get_opaquelocktoken(headers->if);

    if ( mappingp(currentLock) )
    {
	if (  currentLock->lockscope == "exclusive" ) {
	    DAV_WERR("Exclusive Lock Found %O", currentLock);
	    
	    if ( !stringp(tokenHead) )
		return low_answer(423, "locked");
	    
	    if ( currentLock->token != tokenHead )
		return low_answer(423, "locked");
	}
    }

    lock_data = ([ 
		     "lockscope": "exclusive",
		     "depth": 0,
		     "locktype":"write",
		     "owner": "",
		     "timeout": "Second-180",
		     "locktime": time(), 
		     ]);
    if ( headers->timeout )
	lock_data->timeout = headers->timeout;
    if ( headers->depth ) {
	if ( (string)((int)headers->depth) == headers->depth )
	    lock_data->depth = (int)headers->depth;
	else
	    lock_data->depth = headers->depth;
    }
    
    object __lock = xmlDom.parse(body);
    object ownernode, scopenode;
    if ( objectp(__lock) ) {
	ownernode = __lock->get_node("owner");
	scopenode = __lock->get_node("lockscope");
	if ( objectp(scopenode->get_node("shared")) )
	    lock_data->lockscope = "shared";
	if ( search(scopenode->get_xml(), "shared") >= 0 )
	    lock_data->lockscope = "shared";
    }
    if ( mappingp(currentLock) ) {
	if ( lock_data->lockscope == "exclusive" ) {
	    if ( currentLock->token != tokenHead ) 
		return low_answer(423, "locked");
	    else // refresh 
		lock_data->token = currentLock->token;
	}
    }
    
    if ( objectp(ownernode) )
	lock_data->owner = ownernode->get_data();
    else
	lock_data->owner = "<D:href>" + handler->get_user_href() + "</D:href>";
    
    
    lock_data->token = 
	handler->lock(ctx, fname, lock_data); // do not lock upon lockinfo!
    
    string response ="<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
    response += "<D:prop xmlns:D=\"DAV:\">\n";
    response += "<D:lockdiscovery>\n";
    response += discover_lock(fname, handler, ctx);
    response += "</D:lockdiscovery>\n";
    response += "</D:prop>";
    
    DAV_WERR("LOCK reponse=\n%s", response);

    mapping result = low_answer(200, "OK");
    result->data = response;
    result["type"] = "text/xml; charset=\"utf-8\"";
    result["extra_heads"]["Lock-Token"] = "<" + lock_data->token + ">";
    return result;  
}

mapping unlock(string fname, mapping headers, string body, object handler, mixed ctx)
{
  DAV_WERR("unlock(%s, %O)", body, headers);


  string token = get_lock_token(headers);
  mapping lock_data = handler->is_locked(ctx, fname, token);
  mapping result;

  DAV_WERR("Unlock, lock_data=%O\n", lock_data);

  if ( mappingp(lock_data) ) {
      if ( stringp(token) ) {
	  handler->unlock(ctx, fname, token);
	  result = low_answer(204, "No data");
      }
      else
	  result = low_answer(401, "Access denied");	  
  }
  else {
      if ( stringp(token) )
	  result = low_answer(423, "locked");
      else 
	  result = low_answer(204, "No data");
  }

  result["type"] = "text/xml; charset=\"utf-8\"";
  return result;
}

mapping response_locked(string res)
{
  string response ="<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n";
  response += "<d:multistatus xmlns:d=\"DAV:\">\n";
  response += "  <d:response>\n";
  response += "    <d:href>"+res+"</d:href>\n";
  response += "    <d:status>HTTP/1.1 423 Locked</d:status>\n";
  response += "  </d:response>\n";
  response += "</d:multistatus>\n";

  DAV_WERR("LOCKED reponse=\n%s", response);

  mapping result = low_answer(207, "Multi-Status");
  result->data = response;
  result["type"] = "text/xml; charset=\"utf-8\"";
  return result;
}

mapping low_answer(int code, string str)
{
    return ([ "error": code, "rettext": str, "extra_heads": ([ ]), ]);
}

void test()
{
  string header1 = "(<locktoken:a-write-lock-token> [\"I am an ETag\"]) ([\"I am another ETag\"])";
  string header2 = "<http://www.foo.bar/resource1> (<locktoken:a-write-lock-token> [W/\"A weak ETag\"]) ([\"strong ETag\"]) <http://www.bar.bar/random>([\"another strong ETag\"])";
  MESSAGE("* Testing webdavlib ...");
  MESSAGE("header1: %O", parse_if_header(header1));
  MESSAGE("header2: %O", parse_if_header(header2));
  MESSAGE("** Testring webdavlib done ...");
}
