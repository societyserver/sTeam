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
inherit "/kernel/module";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>

//! The rss module return rss code for objects in steam.
//! It is also able to read and parse external rss streams

static mapping import_cache = ([ ]);
static mapping import_time = ([ ]);
static mapping import_tree = ([ ]);

#define REFRESH_TIME 60*15

string get_rss_time(object o, void|string attr)
{
  if ( !stringp(attr) )
    attr = OBJ_CREATION_TIME;
  string t = ctime(o->query_attribute(attr));
  string day, clock, date, year, month, mday;

  day = t[..2];
  date = t[4..9];
  clock = t[11..18];
  year = t[20..23];
  sscanf(date, "%s %s", month, mday);

  int d;
  sscanf(mday, "%d", d);
  if ( d < 10 )
    mday = "0" + d;
  else
    mday = (string)d;

  string res = day + ", " + mday + " " + month + " " + year + " " + clock + " CET";
  return res;
}

void load_module()
{
  start_thread(external_rss_loader);
}

string get_rss_author(object o)
{
  object user;
  if ( o->get_object_class() & CLASS_DOCUMENT )
    user = o->query_attribute(DOC_USER_MODIFIED);

  if ( !objectp(user) )
    user = o->get_creator();
  

  return user->get_steam_email()+ " ("+ user->get_name() + ")";
}

string uml_to_entity(string str)
{
    if ( !stringp(str) ) return "";
    return 
	replace(str, ({ "ä","ö","ü", "Ä", "Ö", "Ü", "&" }),
		({ "&auml;", "&ouml;", "&uuml;", "&Auml;", "&Ouml;",
		   "&Uuml;", "&amp;" }));
}

string rss_extern(object o, string mode, object fp, string server)
{
  string rss = "";

  string t = get_rss_time(o);
  rss = "<item>\n"+
    " <title>"+o->get_identifier() + "</title>\n"+
    " <description>"+o->query_attribute(OBJ_DESC)+"</description>\n"+
    " <link>"+o->query_attribute(DOC_EXTERN_URL)+"</link>\n";
  
  if ( mode == "2.0" ) {
    rss +=
      " <category>steam</category>\n"+
      " <category>documents</category>\n"+
      " <pubDate>"+t+"</pubDate>\n";
    rss += "<author>"+get_rss_author(o)+"</author>\n";
  }
  rss += "</item>\n";
  return rss;
}


string rss_document(object o, string mode, object fp, string server)
{
  string rss = "";
  string t = get_rss_time(o, DOC_LAST_MODIFIED);

  object ann = o->get_annotating();
  string link = "";

  if ( objectp(ann) ) {
    object forum;
    while ( objectp(ann) ) {
      forum = ann;
      ann = ann->get_annotating();
    }
    link = _FILEPATH->object_to_filename(forum);
    link = httplib.replace_uml(link);
    link += "?active="+o->get_object_id();
  }
  else {
    link = _FILEPATH->object_to_filename(o);
    link = httplib.replace_uml(link);
  }
  link = "https://"+_Server->get_server_name() + link;
  
  rss = "<item>\n"+
    " <title>"+o->get_identifier() + "</title>\n"+
    " <description>"+o->query_attribute(OBJ_DESC)+"</description>\n"+
    " <link>"+link+"</link>\n";
  if ( mode == "2.0" ) {
    rss +=
      " <category>steam</category>\n"+
      " <category>documents</category>\n"+
      " <pubDate>"+t+"</pubDate>\n"+
     " <lastBuildDate>"+get_rss_time(o,DOC_LAST_MODIFIED)+"</lastBuildDate>\n";
  
    rss += "<author>"+get_rss_author(o)+"</author>\n";

    if ( o->get_content_size() > 0 ) {
      string str = o->get_content();
      if ( search(o->query_attribute(DOC_MIME_TYPE), "text/html") == 0 ) {
	str = htmllib.parse_rxml(str, ([ ]), ([ ]));
	rss += " <content:encoded><![CDATA[\n"+str + "\n]]></content:encoded>\n";
      }
      else if ( search(o->query_attribute(DOC_MIME_TYPE), "text/wiki") == 0 ) {
	str = get_module("wiki")->wiki_to_html_plain(o);
	str = "<html><body>"+str + "</body></html>";
	
	rss += " <content:encoded><![CDATA[\n"+str + "\n]]></content:encoded>\n";
      }
      else if ( search(o->query_attribute(DOC_MIME_TYPE), "text/") == 0 ) {
	str = uml_to_entity(str);
	rss += " <content:encoded><![CDATA[\n"+str + "\n]]></content:encoded>\n";
      }
    }
  }
  rss += "</item>\n";
  return rss;
}

static string rss_doc_versions(object o, object fp, string server)
{
#ifdef DOC_VERSIONS
  mapping versions = o->query_attribute(DOC_VERSIONS);
  if ( !mappingp(versions) )
    return "";
  int i = 1;
  string rss = "";
  object prev;
  while ( objectp(versions[i]) ) {
    object v = versions[i];
    string link = "/scripts/get.pike?object="+v->get_object_id();
    link = server + link;
    object creator = v->get_creator();
    string t = 
    rss += "<item>\n"+
      " <title>Version: "+ v->query_attribute(DOC_VERSION)+ "</title>\n"+
      " <description>"+v->query_attribute(OBJ_DESC)+"</description>\n"+
      " <link>"+link+"</link>\n"+
      " <category>steam</category>\n"+
      " <category>wiki</category>\n"+
      " <category>versions</category>\n"+
      " <pubDate>"+get_rss_time(v)+"</pubDate>\n"+
      " <lastBuildDate>"+get_rss_time(v, DOC_LAST_MODIFIED)+"</lastBuildDate>";
    
    if ( objectp(prev) ) 
	rss += "<content:encoded><![CDATA[" +
	    get_module("diff")->diff_html(prev, v) + "]]></content:encoded>";
    prev = v;
    rss += "<author>" + get_rss_author(v) + "</author>\n";
    
    rss +=" </item>\n";
    i++;
  }
  return rss;
#endif
  return "";
}


mixed rss(object obj, void|object fp, string|void v)
{
  string mode = "2.0";
  string tag = "rss";
  string mimetype = "application/rss+xml";
  
  if ( !objectp(fp) ) {
    fp = _FILEPATH;
  }

  string server = _Server->get_server_name();
  if ( fp == _FILEPATH )
    server = "https://"+server;
  else
    server = "http://"+server;

  if ( stringp(v) )
    mode = v;

  string rss = "<?xml version='1.0' encoding='utf-8'?>\n";
  switch ( mode ) {
    case "0.9" :
      rss += "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\" xmlns=\"http://my.netscape.com/rdf/simple/0.9/\">";
      tag = "rdf";
      mimetype = "text/xml";
      break;
    default :
      rss += "<rss version='"+mode+"' "+
	"xmlns:content=\"http://purl.org/rss/1.0/modules/content/\">\n";
      tag = "rss";
      mimetype = "application/rss+xml";
  }
  
  rss += "<channel>\n"+
    "<title>"+obj->query_attribute(OBJ_NAME)+"</title>\n"+
    "<description>"+obj->query_attribute(OBJ_DESC)+"</description>\n"+
    "<link>https://"+_Server->get_server_name()+_FILEPATH->object_to_filename(obj)+"</link>\n";
  
  rss += "<generator>http://www.open-steam.org/scripts/rss.pike?v=0.1</generator>\n";
  
  array inv;
  
  if ( obj->get_object_class() & CLASS_CONTAINER )
    inv = obj->get_inventory();
  else if ( obj->get_object_class() & CLASS_MESSAGEBOARD )
    inv = obj->get_annotations();
  else if ( obj->get_object_class() & CLASS_DOCUMENT ) {
    // first versioning for wiki
    if ( obj->query_attribute(DOC_MIME_TYPE) == "text/wiki" )
      rss += rss_doc_versions(obj, fp, server);
    rss += rss_document(obj, mode, fp, server);
    inv = ({ });
  }  
  
  foreach(inv, object o) {
    if ( !objectp(o) )
      continue;
    if ( o->get_object_class() & CLASS_DOCUMENT ) {
      rss += rss_document(o, mode, fp, server);
    }
    else if ( o->get_object_class() & CLASS_DOCEXTERN ) {
      rss += rss_extern(o, mode, fp, server);
    }
  }
  
  rss += "</channel>\n</" + tag + ">\n";
  return rss;
}


string rss_import(string url)
{
  string data;
  werror("rss_import(%s)\n", url);
  if ( import_time[url] > 0 && time() - import_time[url] < REFRESH_TIME )
    data = import_cache[url];
  else {
    import_cache[url] = _rss_import(url);
    import_time[url] = time();
    data = import_cache[url];
  }
  return data;
}

static string value_from_tree(object node, string xpath)
{
  object n = node->get_node(xpath);
  if ( objectp(n) ) 
    return n->get_data();
  return "";
}

static mapping make_tree(string data)
{
  mapping tree = ([ "title": "this channel", 
		    "description": "some channel",
		    "link": "http://www.open-steam.org/somlink",
		    "language": "de",
		    "items": ({ }),
  ]);

  // tree returns mapping as [ "channel": ...., "link":...., "items": <array>
  object node = xmlDom.parse(data);
  tree->title = value_from_tree(node, "/rss/channel/title");
  tree->link = value_from_tree(node, "/rss/channel/link");
  tree->description = value_from_tree(node, "/rss/channel/description");
  tree->language = value_from_tree(node, "/rss/channel/language");
  foreach(node->get_nodes("channel/item"), object n) {
    mapping item = ([ "title": "unknown",
		      "description": "undefined",
		      "category": "none",
		      "pubDate": "never",
		      "content:encoded": "", ]);
    item->title = value_from_tree(n, "title");
    item->link = value_from_tree(n, "link");
    item["content:encoded"] = value_from_tree(n, "content:encoded");
    tree->items += ({ item });
  }
  return tree;
}

mapping rss_parsed_import(string url)
{
  if ( mappingp(import_tree[url]) && 
       import_time[url] > 0 && time() - import_time[url] < REFRESH_TIME ) 
  {
    return import_tree[url];
  }
  string data = rss_import(url);
  import_tree[url] = make_tree(data);
  return import_tree[url];
}

static void external_rss_loader()
{
}

static string _rss_import(string url)
{
  // this needs to be cached
  string data = Protocols.HTTP.get_url_data(url);
  if ( !stringp(data) ) {
    error("Unable to fetch url " + url);
  }
  array lines = data / "\n";
  data = "";
  foreach(lines, string l) {
    if ( search(l, "<?") == -1 && search(l, "<!") == -1 )
      data += l + "\n";
  }
  return data;
}


string get_identifier() { return "rss"; }
