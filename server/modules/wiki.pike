/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Robert Hinn
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
import httplib;

#include <macros.h>
#include <database.h>
#include <attributes.h>
#include <classes.h>

#define WIKITRAIL_SIZE 6

//#define WIKI_DEBUG 1

#ifdef WIKI_DEBUG
#define DEBUG_WIKI(s, args ...) werror("WIKI: "+ s+"\n", args)
#else
#define DEBUG_WIKI(s, args ...)
#endif


static constant features = ({
  "anchor", "annotation", "footnote", "list", "math", "pike","toc",
    "overview", });

bool has_feature ( string feature ) {
  if ( !stringp(feature) || sizeof(feature) < 1 ) return false;
  return search( features, lower_case( feature ) ) >= 0;
}

array get_features () {
  return features;
}


static int is_safe_url_char ( int c ) {
  return (c>='a' && c<='z') || (c>='A' && c<='Z') || (c=='_') ||
    (c=='0') || (c>='1' && c<='9');
}

string str_to_safe_url ( string s ) {
  if ( !stringp(s) ) return 0;
  return filter( replace( s, ([ " ":"_",
    "ä":"ae", "Ä":"AE", "ö":"oe", "Ö":"OE", "ü":"ue", "Ü":"UE", "ß":"ss",
	]) ), is_safe_url_char );
}

class WikiContext {
    object filepath;
    object      obj;
    object wikiParser;
    mapping parsedObjects = ([ ]);
    int footnote_cnt = 0;
    array footnotes = ({ });
    array footnotes_links = ({ });
    mapping footnotes_numbers = ([ ]);
    array headings = ({ });
    array headings_links = ({ });
    array headings_levels = ({ });
    array anchors_links = ({ });
    mapping tocs = ([ ]);

    array parse_stack = ({ });  // contains a stack of embedded objects

    int has_toc = false;
    int has_footnotes = false;
    int has_list = false;
    int has_overview = false;

    void create(object fp, object o, object parser) {
	filepath = fp;
	obj = o;
	parsedObjects[obj] = 1;
        parse_stack = ({ o });
	wikiParser = parser;
    }
    object resolve_path(object obj, string path) {
	return filepath->resolve_path(obj, path);
    }
    string object_to_filename(object obj) {
	if ( obj == OBJ("/scripts/wikiedit.pike") ) {
	    string fname = filepath->object_to_filename(obj);
	    string sname = _Server->get_server_name();
	    
	}
	return filepath->object_to_filename(obj);
    }
    object path_to_object(string path) {
	return filepath->path_to_object(path);
    }
    string object_to_path(object obj) {
	return filepath->object_to_path(obj);
    }
    int add_footnote(string link, string desc) {
	footnotes += ({ desc });
        footnotes_links += ({ link });
	return footnote_cnt++;
    }
    void add_heading ( string link, string heading, int level ) {
        headings += ({ heading });
        headings_links += ({ link });
        headings_levels += ({ level });
    }
    void add_anchor ( string link ) {
        anchors_links += ({ link });
    }
    void add_toc ( string str, string levels ) {
        tocs[ str ] = levels;
    }
}

class WikiConfig {
    string currentH1="";
    string currentH2="";
    string currentH3="";
    string currentH4="";

    string headingWiki(object obj, object fp, string heading) {
	string htext;
	if ( sscanf(heading, "====%s====", htext) > 0 )
	    currentH4 = htext;
	else if ( sscanf(heading, "===%s===", htext) > 0 )
	    currentH3 = htext;
	else if ( sscanf(heading, "==%s==", htext) > 0 )
	    currentH2 = htext;
	else if ( sscanf(heading, "=%s=", htext) > 0 )
	    currentH1 = htext;
	return "";
    }

    string pikeWiki(object obj, object fp, string pcode) {
	return "";
    }

    string embedWiki(object obj, object fp, string embed) {
	return "embed(" + embed + ")\n";
    }

    string annotationWiki(object obj, object fp, string ann) {
	return "annotation(" + ann + "\n";
    }
    
    string tagWiki(object obj, object fp, string tagStr) {
	return tagStr + "\n";
    }
    string mathWiki(object obj, object fp, string tagStr) {
	return tagStr + "\n";
    }
    
    string linkInternalWiki(object obj, object fp, string link) {
	return "Link(" + link+")\n";
    }
    
    string hyperlinkWiki(object obj, object fp, string link) {
	return link + "\n";
    }
    
    string barelinkWiki(object obj, object fp, string link) {
	return "<a class=\"external\" href=\""+link+"\">"+link+"</a>";
    }
    
    string imageWiki(object obj, object fp, string link) {
	return "image(" + link + ")\n";
    }
}


string headingWiki(object obj, object fp, string heading)
{
    string htext;
    if ( sscanf(heading, "====%s====", htext) > 0 ) {
        string anchor = str_to_safe_url( htext );
        fp->add_heading( anchor, htext, 4 );
	return "<a name=\""+anchor+"\"></a><h4>" + htext + "</h4>\n";
    }
    if ( sscanf(heading, "===%s===", htext) > 0 ) {
        string anchor = str_to_safe_url( htext );
        fp->add_heading( anchor, htext, 3 );
	return "<a name=\""+anchor+"\"></a><h3>" + htext + "</h3>\n";
    }
    if ( sscanf(heading, "==%s==", htext) > 0 ) {
        string anchor = str_to_safe_url( htext );
        fp->add_heading( anchor, htext, 2 );
	return "<a name=\""+anchor+"\"></a><h2>" + htext + "</h2>\n";
    }
    if ( sscanf(heading, "=%s=", htext) > 0 ) {
        string anchor = str_to_safe_url( htext );
        fp->add_heading( anchor, htext, 1 );
	return "<a name=\""+anchor+"\"></a><h1>" + htext + "</h1>\n";
    }
    return heading;
}

string pikeWiki(object obj, object fp, string pcode)
{
  if ( pcode == "@@TOC@@" ) {
    fp->add_anchor( "TOC" );
    fp->add_toc( "<!--TOC-->", "" );
    return "<!--TOC-->";
  }
  string toc_levels;
  if ( sscanf( pcode, "@@TOC:%s@@", toc_levels ) > 0 ) {
    toc_levels = filter( toc_levels,
                         lambda(int c){ return (c>='1' && c<='9'); } );
    fp->add_anchor( "TOC" );
    fp->add_toc( "<!--TOC:"+toc_levels+"-->", toc_levels );
    return "<!--TOC:"+toc_levels+"-->";
  }
  if ( pcode == "@@FOOTNOTES@@" ) {
    fp->add_anchor( "FOOTNOTES" );
    return "<!--FOOTNOTES-->";
  }
  if ( has_prefix( pcode, "@@LIST" ) ) {
    sscanf( pcode, "@@LIST%s@@", pcode );
    return add_wiki_list( obj, fp, pcode );
  }
  if ( has_prefix( pcode, "@@OVERVIEW" ) ) {
    sscanf( pcode, "@@OVERVIEW%s@@", pcode );
    return add_wiki_overview(obj, fp, pcode );
  }
  
  string result;

  sscanf(pcode, "@@PIKE%s@@", pcode);
  string code = "#include <macros.h>\n#include <attributes.h>\n#include <classes.h>\n#include <database.h>\nmixed exec(object env, object fp) {\n" + pcode + "\n}";
  
  object e = master()->ErrorContainer();
  master()->set_inhibit_compile_errors(e);
  mixed err = catch { 
    program prg = compile_string(code); 
    object o = new(prg);
    result = o->exec(obj, fp);
  };
  if ( err != 0 ) {
    return "<!-- error calling function:"+sprintf("%O\n%O\n",err, e->get())+"-->\n";
  }
  return result;
}

string embedWiki(object obj, object fp, string embed)
{
  string link, prefix, args, desc;
  mapping            vars = ([ ]);
  
  if ( sscanf(embed, "{%s}", link) == 0 )
    return "<!-- unable to embed " + embed + " -->\n";

  while ( sscanf(link, "%s:%s", prefix, link) >= 1 ) {
    object namespace = get_wiki_room(prefix, obj);
    if ( !objectp(namespace) )
      return "<!-- Wiki Prefix not found: "+prefix+"-->\n";
    if ( objectp(namespace) )
      obj = namespace;
  }
  if ( sscanf(link, "%s$%s", link, args) == 2 ) {
    array params = args / ",";
    foreach(params, string param) { 
      // trim whitespaces ?
      string key, val;
      if ( sscanf(param, "%s=%s", key, val) == 2 )
	vars[key] = val;
    }
  }
  if ( sscanf(link, "%s|%s", link, desc) != 2 )
    desc = "";
    

  object o;
  int  oid;

  if ( sscanf(link, "#%d", oid) ) {
    o = find_object(oid);
  }
  else {
    o = fp->resolve_path(obj, link);
  }
  if ( !objectp(o) )
    return "<!-- object " + embed + " not found !-->\n";
  
  if ( o->get_object_class() & CLASS_SCRIPT )
    return o->execute( vars );
    
  if ( o->get_object_class() & CLASS_DOCEXTERN )
    return sprintf("<iframe width=\"90%%\" height=\"400\" src=\"%s\">Das Frame kann nicht angezeigt werden</iframe>", o->query_attribute(DOC_EXTERN_URL));
  
  string mtype = o->query_attribute(DOC_MIME_TYPE) || "";
  
  switch(mtype) {
  case "image/svg+xml":
      int h, w;
      h = o->query_attribute(OBJ_HEIGHT);
      w = o->query_attribute(OBJ_WIDTH);
      return sprintf("<embed height='%d' width='%d' type='%s' "+
		     " source='/scripts/get.pike?object='%d' />\n",
		     h, w, mtype, o->get_object_id());
  case "text/wiki":
      if ( search( fp->parse_stack, o ) >= 0 )
          return("<!--Recursive Embedding of Wiki Documents "+link+"!-->");
    fp->parsedObjects[o] = 1;
      fp->parse_stack += ({ o });
    fp->wikiParser->parse_buffer(o->get_content());
      fp->parse_stack = fp->parse_stack[..(sizeof(fp->parse_stack)-1)];
    return "";  
  case "text/xml":
    return replace(o->get_content(), 
		   ({ "<", ">", "\n", " " }), 
		   ({ "&lt;", "&gt;", "<BR />", "&#160;" }));
  }
  // all images, videos, audio and all none-text documents

  if ( search(mtype, "image") >= 0 ) {
    return sprintf("<div class='wiki_image'><img alt='%s' src='%s' /><div class='desc'>%s</div></div>",  desc, replace_uml(fp->object_to_filename(o)), desc);
  }
  else if ( search(mtype, "video") >= 0 )
      return sprintf("<embed src=\"%s\" />", replace_uml(fp->object_to_filename(o)));
  else if ( search(mtype, "audio") >= 0 )
      return sprintf("<embed src=\"%s\" />", replace_uml(fp->object_to_filename(o)));
  else if ( search(mtype, "text") == -1 && search(mtype, "source") == -1 )
      return "<a href='"+replace_uml(fp->object_to_filename(o))+"'>"+
	o->get_identifier()+"</a>\n";

  
  
  string embed_class = replace(mtype, "/", "_");

  string maint, subt;
  sscanf(mtype, "%s/%s", maint, subt);

  string content = o->get_content();
  if ( !stringp(content) )
    content = "";

  content = replace(content, "\n", "<br />");
  return "<div class='embedded'><div class='"+maint+"'><div class='"+subt+"'>"+
    content+"</div></div></div>\n";
}

string annotationWiki(object obj, object fp, string ann) 
{
  string text, desc;

  sscanf( ann, "[%s[%s]]", text, desc );
  if ( has_prefix( desc, "%" ) || has_prefix( desc, "#" ) ) {
    int id;
    object o;
    if ( has_prefix( desc, "%" ) )
    sscanf( desc, "%%%d", id );
    else
      sscanf( desc, "#%d", id );
    if ( id != 0 )
      o = find_object( id );
    if ( objectp(o) ) {
      desc = o->get_content();
      replace( desc, "\"", "'" );
    }
  }

  // footnote:
  if ( has_prefix( text, "#" ) ) {
    if ( sizeof(text) < 2 ) text = "footnote_" + (fp->footnote_cnt+1);
    int id = fp->add_footnote( str_to_safe_url( text ), desc );
    return "<!--FOOTNOTE:" + id + "-->";
  }
  else {
    return "<div class='annotate'><div class='annotation'>" + desc + "</div>" +
      "<div class='annotated'>" + text + "</div></div>";
  }
}

static void formulaWiki(string result, mapping args)
{
    seteuid(USER("root"));
    object factory = get_factory(CLASS_DOCUMENT);
    object obj = factory->execute( ([ "name": "Wiki Formel",
				      "mimetype": "image/png", ]));
    obj->set_content(result);
    obj->set_acquire(args->object);

    mapping links = args->object->query_attribute("WIKI_FORMULAS");
    if ( !mappingp(links) )
	links = ([ ]);
    links[args->formula] = obj;
    args->object->set_attribute("WIKI_FORMULAS", links);
    werror("WIkiLinks now: %O\n", links);
}

void formulaWikiRes(string result)
{
}

string mathWiki(object obj, object fp, string tagStr) 
{
    string formula = tagStr;
    mapping links = fp->obj->query_attribute("WIKI_FORMULAS");
    if ( !mappingp(links) )
	links = ([ ]);
    if ( !objectp(links[formula]) )
    {
        if ( !get_module("ServiceManager")->is_service("tex") )
          return "<tt>"+formula+"</tt>";
	Async.Return res = get_module("ServiceManager")->call_service_async("tex", ([ "formula": formula, ]));
	if ( objectp(res) ) {
	    res->processFunc = formulaWiki;
	    res->resultFunc = formulaWikiRes;
	    res->userData = ([ "formula": formula, "object": fp->obj, ]);
	}
	return "<tt>"+formula+"</tt>";
    }
    else
	return "<img src='/scripts/get.pike?object=" + 
	    links[formula]->get_object_id() + "' border='0' />";
}

string tagWiki(object obj, object fp, string tagStr) 
{
    return replace(tagStr, ({ "<", ">" }), ({ "&lt;", "&gt;" }));
}

object get_object_in_cont(object cont, string name, int classid)
{
    array inv = cont->get_inventory_by_class(classid);
    foreach(inv, object obj) {
	if ( obj->query_attribute(OBJ_NAME) == name )
	    return obj;
    }
    return 0;
}

string linkInternalWiki(object obj, object fp, string link) 
{
  string desc, prefix, space, image, mydesc;
  mixed  err;
  int objClass = CLASS_CONTAINER;
  mapping objVars = ([ ]);


  space = "";

  if ( strlen(link) > 1 && link[0] == ' ' ) {
    link = link[1..];
    space = " ";
  }
  link = String.trim_whites(link); // remove other whitespaces
  string fullLink = link;
  
  if ( sscanf(link, "[[%s|%s]]", link, mydesc) == 0 ) {
      sscanf(link, "[[%s]]", link);
      desc = basename(link);
  }
  else {
      desc = mydesc;
  }
  string anchor = "";
  // split at last '#':
  int anchor_index = search( reverse(link), '#' );
  if ( anchor_index > 0 ) {
    anchor_index = sizeof(link) - anchor_index - 1;
    anchor = link[(anchor_index+1)..];
    if ( anchor_index > 0 )
      link = link[..(anchor_index-1)];
    else link = "";
  }
  if ( !stringp(mydesc) ) desc = basename(link);
  DEBUG_WIKI("Link %O : anchor %O, description %O", link, anchor, desc);

  // footnote / anchor:
  if ( sizeof(link) < 1 &&
       ( sizeof(anchor) > 0 || (stringp(desc) && sizeof(desc)>0) ) ) {
      // don't use the link as description for footnotes/anchors:
      if ( !stringp(mydesc) || sizeof(mydesc) < 1 )
          desc = "";
      // check for anchors (descriptions without links):
    if ( sizeof(anchor) < 1 && sizeof(desc) > 0 ) {  // anchor
        desc = str_to_safe_url( desc );
          fp->add_anchor( desc );
          return "<a name=\"" + desc + "\"></a>";
      }
    anchor = str_to_safe_url( anchor );
    int id = fp->add_footnote(anchor, desc);
      return "<!--FOOTNOTE:" + id + "-->";
  }

  object namespace, lnk; // namespace and link object

  while ( stringp(link) && sscanf(link, "%s:%s", prefix, link) >= 1 ) {
      string uname, ulink;

      DEBUG_WIKI("Prefix Wiki: %s::%s", prefix, link);
      if ( prefix == "wikipedia" ) {
          string wikipedialink = "<a href='http://de.wikipedia.org/wiki/"+link;
          if ( stringp(anchor) && sizeof(anchor) > 0 )
            wikipedialink += "#" + replace_uml(anchor);
          wikipedialink += "'>"+desc+"</a>";
          return wikipedialink;
      }
      objVars->name = prefix;
      objClass = CLASS_CONTAINER;
      
      string objtype;
      if ( sscanf(prefix, "(%s)%s", objtype, prefix) == 2 ) {
	  
	  switch ( lower_case(objtype) ) {
	  case "room":
	  case "raum":
	      objClass = CLASS_ROOM;
	  case "container":
	  case "ordner":
	      namespace = get_object_in_cont(obj, prefix, objClass);
	      objVars->name = prefix;
	      break;
	  case "verbindung":
	  case "exit":
	      objVars->name = prefix;
	      namespace = get_object_in_cont(obj, prefix, CLASS_EXIT);
	      objClass = CLASS_EXIT;
	      objVars["exit_to"] = OBJ("/home/" + prefix);
	      break;
	  }
      }
      else {
	  switch(lower_case(prefix)) {
	  case "user":
	  case "benutzer":
	      if ( sscanf(link, "%s:%s", uname, ulink ) < 2 ) 
		  uname = link;
	      else
		  link = ulink;
	      
	      // wenn Benutzer nicht existiert ? Anlegen - vorher E-mail
	      // und optionale weitere Daten abfragen. Benutzer einladen per e-mail
	      object uobj = get_module("users")->lookup(uname);
	      if ( !objectp(uobj) ) {
		  return "<a href=\"/register/newuser.xml?name=" + uname + "&mode=simple\" class=\"notexistant\">"+prefix+":"+link+"</a>\n";
	      }
	      namespace = uobj->query_attribute(USER_WORKROOM);
	      break;
	  case "group":
	  case "gruppe":
	      if ( sscanf(link, "%s:%s", uname, ulink ) < 2 ) 
		  uname = link;
	      else
		  link = ulink;
	      
	      object grp;
	      
	      if ( lower_case(uname) == "everyone" )
		  grp = GROUP("everyone");
	      else
		  grp = get_module("groups")->lookup("WikiGroups." + uname);
	      
	      if ( !objectp(grp) ) {
		  // create not existing groups ?!
		  err = catch {
		      grp = wiki_create_group(uname);
		  };
                  if ( err ) {
		      FATAL("wiki: creation of wikigroup %s failed: %s\n%O",
			    uname, err[0], err[1]);
		  }
	      }
	      namespace = grp->query_attribute(GROUP_WORKROOM);
	      break;
	  default:
	      namespace = get_wiki_room(prefix, obj);
	  }
      }
      
      if ( objectp(namespace) )
	  obj = namespace;
      else {
	  mixed err = catch {
	      object factory = get_factory(objClass);
	      object cont = factory->execute( objVars );
	      cont->move(obj);
	      obj = cont;
	  };
	  if ( err ) {
	      FATAL("Error while creating container: %O, %O", err[0], err[1]);
	      return "<!-- the link " + link +" could not be created !-->\n";
	  }
      }
  }
  if ( objectp(namespace) ) {
    if ( namespace->get_object_class() & CLASS_EXIT )
      lnk = namespace->get_exit();
    else if ( namespace->get_object_class() & CLASS_LINK )
      lnk = namespace->get_object();
    else
      lnk = namespace;
    // treat containers as several links
    if ( !stringp(link) || link == "" ) {
      DEBUG_WIKI("Empty link desc=%s", desc);
      int id = lnk->get_object_id();
      string html = "<div class='container'>\n"; 
      html += "<div class='title'>"+ 
	  desc + 
	  "&nbsp;<img src='/images/unfold.gif' alt='unfold' onClick='contClick("+
	  id+ ", event);'/></div>\n";
      html += "<div class='inv' id='"+id+"'><div class='topbar'>"+
	  "<img alt='close' src='/images/closetop.gif' onClick='closeClick("+id+
	  ", event);'/></div>\n";
      
      array inv;
      if ( catch(inv = lnk->get_inventory_by_class(CLASS_DOCUMENT)) ||
           !arrayp(inv) )
	  return "<!-- unreadable container in " + link + "--></div></div>\n";
      foreach(inv, object o) {
	if ( !objectp(o) ) continue;
	switch(o->query_attribute(DOC_MIME_TYPE)) {
	case "text/wiki": 
	  string n;
	  sscanf(o->get_identifier(), "%s.%*s", n);
	  html += "<div class='wikilink'>\n";
	  html += "<a href='"+fp->object_to_filename(o)+"'>"+ n + "</a>\n";
	  html += "<div class='description'>"+o->query_attribute(OBJ_DESC)+
	    "</div>\n";
	  html += "</div>\n";
	  break;
	default:
	  html += "<div class='contlink'>\n";
	  html += "<a href='"+fp->object_to_filename(o)+"'>"+ 
	    o->get_identifier() + "</a>\n";
	  html += "<div class='description'>"+o->query_attribute(OBJ_DESC)+
	    "</div>\n";
	  html += "</div>\n";
	  break;
	}
      }
      html += "</div></div>\n";
      return html;
    }
  }
  
  if ( sscanf(desc, "{%s}", image) == 1 ) 
      desc = embedWiki(obj, fp, desc);
  
  if ( !stringp(link) || link == "" )
      lnk = obj;
  else {
      DEBUG_WIKI("trying to resolve %s in %s", link, obj->describe());
      lnk = fp->resolve_path(obj, link);
  }
  
  mapping linkMap;
  mapping currentLinks;

  catch(currentLinks = fp->obj->query_attribute("OBJ_WIKILINKS_CURRENT"));
  if ( !mappingp(currentLinks) )
      currentLinks = ([ ]);
  catch(linkMap = fp->obj->query_attribute(OBJ_WIKILINKS));
  if ( !mappingp(linkMap) )
      linkMap = ([ ]);

  if ( !objectp(lnk) ) {
      // try to find the link object if any
      if ( objectp(linkMap[fullLink]) && linkMap[fullLink]->status() >= 0 ) {
	  lnk = linkMap[fullLink];
	  link = fp->object_to_filename(lnk);
      }
  }
  else {
      if ( !has_value( linkMap, lnk ) )
      linkMap[fullLink] = lnk;
  }

  if ( !objectp(lnk) || (lnk->get_object_class() & CLASS_CONTAINER) ) {
      link += ".wiki";  
      DEBUG_WIKI("trying to resolve %s in %s", link, obj->describe());
      lnk = fp->resolve_path(obj, link);
      if ( !objectp(lnk) ) {
	  if ( objectp(linkMap[fullLink]) ) {
	      lnk = linkMap[fullLink];
	      DEBUG_WIKI("Using stored link for %O:%O", fullLink, lnk->describe());
	      link = fp->object_to_filename(lnk);
	  }
      }
      else {
          if ( !has_value( linkMap, lnk ) )
	  linkMap[link]= lnk;
  }
  }
  if ( !has_value( currentLinks, lnk ) )
  currentLinks[fullLink] = lnk;
  
  catch(fp->obj->set_attribute("OBJ_WIKILINKS", linkMap));
  catch(fp->obj->set_attribute("OBJ_WIKILINKS_CURRENT", currentLinks));
  

  if ( !objectp(lnk) ) {
    string wiki_edit = "/scripts/wikiedit.pike";
    
    link = replace_uml(fp->object_to_filename(obj) + "/"+link);
    object wedit = fp->path_to_object("/scripts/wikiedit.pike");
    if ( objectp(wedit) )
      wiki_edit = replace_uml(fp->object_to_filename(wedit));
    return sprintf("%s<a class=\"%s\" href=\"%s\">%s</a>",
		   space, "notexistant",
		   wiki_edit+"?path="+ link+"&mode=create", desc);
  }
  catch(lnk->add_reference(fp->obj));
  if ( objectp(namespace) )
    link = fp->object_to_filename(lnk);
  link = replace_uml(link);
  if ( stringp(anchor) && sizeof(anchor) > 0 )
    link += "#" + replace_uml(anchor);
  
  return sprintf("%s<a class=\"%s\" href=\"%s\">%s</a>%s",
		 space, "internal", link, desc, (!objectp(lnk)?"?":""));
}

string hyperlinkWiki(object obj, object fp, string link) 
{
  string dest, desc;
  if ( sscanf(link, "[%s|%s]", dest, desc) != 2 && 
       sscanf(link, "[%s %s]", dest, desc) != 2 ) 
  {
    sscanf(link, "[%s]", link);
    dest = link;
    desc = link;
  }
  if ( sscanf(desc, "{%*s}") )
    desc = embedWiki(obj, fp, desc);
  if ( has_prefix( dest, "local://" ) )
    dest = dest[8..];

  return "<a class=\"external\" href=\""+dest+"\">"+desc+"</a>";
}

string barelinkWiki(object obj, object fp, string link) 
{
  return "<a class=\"external\" href=\""+link+"\">"+link+"</a>";
}

string imageWiki(object obj, object fp, string link) 
{
  string img, alt;
  string img_tag = "image";
  if ( has_prefix( link, "[[Image:" ) ) img_tag = "Image";
  if ( sscanf(link, "[["+img_tag+":%s|%s]]", img, alt) != 2 )
    sscanf(link, "[["+img_tag+":%s]]", img);
  
  return "<img alt=\""+alt+"\" src=\""+img+"\">";
}


/** call immediately after parsing */
static string post_process ( object wikiContext, string html )
{
  array footnotes = copy_value( wikiContext->footnotes );
  array footnotes_links = copy_value( wikiContext->footnotes_links );
  wikiContext->footnotes = ({ });
  wikiContext->footnotes_links = ({ });
  wikiContext->footnotes_numbers = ([ ]);  // link : nr
  mapping replacements = ([ ]);
  int footnote_count = 1;
  for ( int i = 0; i<sizeof(footnotes); i++ ) {
    if ( !stringp(footnotes_links[i]) ) continue;
    string link = footnotes_links[i];
    string desc = footnotes[i];
    int index = search( wikiContext->headings_links, link );
    if ( index >= 0 ) {
      // heading:
      if ( sizeof(desc) < 1 ) desc = link;
      replacements[ "<!--FOOTNOTE:"+i+"-->" ] = "<a href=\"#" + link +
        "\">" + desc + "</a>";
    }
    else if ( (index = search( wikiContext->anchors_links, link )) >= 0 ) {
      // anchor:
      if ( sizeof(desc) < 1 ) desc = link;
      replacements[ "<!--FOOTNOTE:"+i+"-->" ] = "<a href=\"#" + link +
        "\">" + desc + "</a>";
    }
    else {
      // footnote:
      int nr;
      if ( has_index( wikiContext->footnotes_numbers, link ) )
        nr = wikiContext->footnotes_numbers[link];
      else {
        nr = footnote_count++;
        wikiContext->footnotes_numbers[ link ] = nr;
      }
      replacements[ "<!--FOOTNOTE:"+i+"-->" ] = "<a href=\"#" + link +
        "\" class=\"footnote\">" + nr + "</a>";
      wikiContext->footnotes += ({ desc });
      wikiContext->footnotes_links += ({ link });
    }
  }
  wikiContext->footnote_cnt = sizeof( wikiContext->footnotes );

  foreach ( indices(wikiContext->tocs), string toc ) {
    replacements[ toc ] = add_toc( wikiContext, wikiContext->tocs[ toc ] );
  }

  if ( search( html, "<!--FOOTNOTES-->" ) >= 0 ) {
    replacements[ "<!--FOOTNOTES-->" ] = add_footnotes( wikiContext );
    wikiContext->has_footnotes = true;
  }

  return replace( html, replacements );
}


static string add_footnotes(object wikiContext) 
{
  string html = "";

  if ( sizeof(wikiContext->footnotes) > 0 ) {
    html += "<hr/>";
    mapping descriptions = ([ ]);  // link : desc
    for ( int i = 0; i < sizeof(wikiContext->footnotes); i++ ) {
      mixed desc = wikiContext->footnotes[i];
      mixed link = wikiContext->footnotes_links[i];
      if ( !stringp(desc) || sizeof(desc)<1 || !stringp(link) ||
           sizeof(link)<1 || has_index(descriptions, link) )
        continue;  // invalid desc/link or footnote has already been described
      descriptions[ link ] = desc;
    }
    array links = indices(wikiContext->footnotes_numbers);
    array numbers = values(wikiContext->footnotes_numbers);
    sort( numbers, links );
    for ( int i=0; i<sizeof(numbers); i++ ) {
      string link = links[i];
      string desc = descriptions[link];
      if ( !stringp(desc) ) desc = link;
      html += sprintf( "<a name=\"FOOTNOTES\"></a><div class=\"footnote\">"+
                       "<a name=\"%s\" class=\"footnote\" title=\"%s\">"+
                       "%d</a> %s</div>", link, link, numbers[i], desc );
      }
  }
  return html;
}


static string add_toc ( object wikiContext, string|void levels ) {
  if ( sizeof(wikiContext->headings) < 1 )
    return "";
  string html = "<a name=\"TOC\"></a><div class=\"toc\"><ul>\n";
  array lv = ({ });
  if ( !stringp(levels) || sizeof(levels) < 1 )
    lv = ({ 1, 2, 3, 4 });
  else for ( int i=0; i<sizeof(levels); i++ )
    lv += ({ (int)levels[i..i] });
  if ( sizeof(lv) < 1 ) return "";
  lv = sort( lv );
  int current_level = lv[0];
  for ( int i=0; i<sizeof(wikiContext->headings); i++ ) {
    string heading = wikiContext->headings[i];
    string heading_link = wikiContext->headings_links[i];
    int level = wikiContext->headings_levels[i];
    if ( search( lv, level ) < 0 ) continue;
    while ( current_level < level ) {
      html += "<ul>\n";
      current_level++;
    }
    while ( current_level > level ) {
      html += "</ul>\n";
      current_level--;
    }
    html += "<li><a href=\"#" + heading_link + "\">" + heading + "</a></li>";
  }
  // close list:
  while ( current_level > lv[0] ) {
    html += "</ul>\n";
    current_level--;
  }
  return html + "</ul></div>\n";
}


static string add_wiki_list ( object env, object wikiContext, string code ) {
  if ( !stringp(code) || !objectp(env) ||
       (env->get_object_class() & CLASS_CONTAINER == 0) )
    return "";
  array files = env->get_inventory_filtered(
    ({
      ({ "-", "!class", CLASS_DOCUMENT }),
      ({ "+", "attribute", DOC_MIME_TYPE, "==", "text/wiki" })
    }), ({
      ({ "<", "attribute", OBJ_NAME })
    })
  );
  array identifiers = files->get_identifier();
  array list = allocate( sizeof(files) );
  for ( int i=0; i<sizeof(list); i++ ) list[i] = i;
  int reset = false;
  int show_desc = false;
  code = replace( code, "\r\n", " " );
  code = replace( code, "\n", " " );
  foreach ( code / " ", string spec ) {
    if ( has_prefix( spec, "+" ) ) {
      if ( !reset ) {
        list = ({ });
        reset = true;
      }
      string name = spec[1..];
      int index = search( identifiers, name );
      if ( index >= 0 ) list += ({ index });
      else list += ({ name });
    }
    else if ( has_prefix( spec, "-" ) ) {
      string name = spec[1..];
      int index = search( identifiers, name );
      if ( index >= 0 ) list -= ({ index });
      else list -= ({ name });
    }
    else if ( spec == ":description" ) {
      show_desc = true;
    }
  }
  string html = "<ul>";
  foreach ( list, mixed item ) {
    string link = stringp(item) ? item : identifiers[ item ];
    string name = link;
    if ( has_suffix( lower_case(name), ".wiki" ) )
      name = name[..(sizeof(name)-6)];
    html += "<li><a href=\"" + link + "\">" + name + "</a>";
    if ( show_desc && intp(item) && objectp( files[ item ] ) ) {
      string desc = files[ item ]->query_attribute( OBJ_DESC );
      if ( stringp(desc) && desc != "" ) html += " - " + desc;
    }
    html += "</li>\n";
  }
  html += "</ul>\n";
  return html;
}


static string add_wiki_overview ( object env, object wikiContext, string code ) {
  if ( !stringp(code) || !objectp(env) ||
       (env->get_object_class() & CLASS_CONTAINER == 0) )
    return "";
  array files = env->get_inventory_by_class( CLASS_DOCUMENT );
  files = filter( files, lambda(object o){
    return o->query_attribute(DOC_MIME_TYPE) == "text/wiki"; } );
  files = sort( files->get_identifier() );  // object names
  int reset = false;
  code = replace( code, "\r\n", " " );
  code = replace( code, "\n", " " );
  foreach ( code / " ", string spec ) {
    if ( has_prefix( spec, "+" ) ) {
      if ( !reset ) {
        files = ({ });
        reset = true;
      }
      files += ({ spec[1..] });
    }
    else if ( has_prefix( spec, "-" ) ) {
      files -= ({ spec[1..] });
    }
  }
  string html = "";
  foreach ( files, string link ) {
    // prevent recursion:
    object o;
    int oid;
    if ( sscanf( link, "#%d", oid ) )
      o = find_object( oid );
    else
      o = wikiContext->resolve_path( env, link );
    if ( !objectp(o) ||
         search(wikiContext->parse_stack, o) >= 0 ) continue;
    html += embedWiki( env, wikiContext, "{" + link + "}" );
  }
  return html;
}


static array add_wiki_trail(object user, object doc)
{
  if ( !objectp(user) )
    user = USER("guest");
  
  array wikiTrail = user->query_attribute(USER_WIKI_TRAIL);
  if ( !arrayp(wikiTrail) )
      wikiTrail = ({ });
  wikiTrail -= ({ doc });
  
  wikiTrail += ({ doc });
  
  if ( sizeof(wikiTrail) > WIKITRAIL_SIZE )
      wikiTrail = wikiTrail[..WIKITRAIL_SIZE-1];
  
  user->set_attribute(USER_WIKI_TRAIL, wikiTrail);
  return wikiTrail;
}

string wiki_parse(object doc, object wikiObj, void|object fp, void|mapping vars)
{
    if ( !objectp(fp) )
	fp = _FILEPATH;
    object WParser = wiki.Parser(wikiObj);
    object wikiroom = doc->get_environment();
    catch(doc->set_attribute("OBJ_WIKILINKS_CURRENT", ([ ])));
    
    wikiroom = get_room_environment(wikiroom);
    string content = doc->get_content();
    object context = WikiContext(fp, doc, WParser);
    if ( stringp(content) ) {
	string enc = doc->query_attribute(DOC_ENCODING);
	if ( enc == "iso-8859-1" || !xml.utf8_check(content) )
	    content = string_to_utf8(content);

        if ( !xml.utf8_check(content) )
          steam_user_error("Unable to render wiki - wrong encoding (non utf8)");
	
	return WParser->parse(wikiroom, context, content);
    }
    return "";
}

string wiki_to_html_plain(object doc, void|object fp, void|mapping vars)
{
    if ( !objectp(doc) )
	return "<!-- wiki: cannot transform null document -->";
    if ( doc->query_attribute(DOC_MIME_TYPE) != "text/wiki" )
	return "<!-- wiki: Source Document is not a wiki file !-->\n";
    
  if ( !objectp(fp) )
    fp = _FILEPATH;

  add_wiki_trail(this_user(), doc);

  object WParser = wiki.Parser(this_object());
  object wikiroom = doc->get_environment();
  catch(doc->set_attribute("OBJ_WIKILINKS_CURRENT", ([ ])));
    
  wikiroom = get_room_environment(wikiroom);
  if ( !objectp(wikiroom) )
    wikiroom = OBJ("/home/steam");

  string res = "";
  string content = doc->get_content();
  if ( !stringp(content) ) return "";
  object context = WikiContext(fp, doc, WParser);
  string enc = doc->query_attribute(DOC_ENCODING);
  if ( enc == "iso-8859-1" || !xml.utf8_check(content) )
    content = string_to_utf8(content);
     
    if ( !xml.utf8_check(content) )
      steam_user_error("Unable to render wiki - wrong encoding (non utf8)");

  res = WParser->parse(wikiroom, context, content);
  res = post_process(context, res);
  if ( !context->has_footnotes )
  res += add_footnotes(context);
  res = "<div class='html'>"+res+"</div>";
  return res;
}


string wiki_to_html(object doc, void|object fp, void|mapping vars)
{

    if ( !objectp(fp) )
        fp = _FILEPATH;

    object env = doc->get_environment();
    string envname = "";
    if ( objectp(env) )
        envname = env->get_identifier();
    // get the room if we are currently in a container
    object wikiroom = get_room_environment(env);
    string wikipath = "";
    object WParser = wiki.Parser(this_object());
    object wikiContext = WikiContext(fp, doc, WParser);
    catch(doc->set_attribute("OBJ_WIKILINKS_CURRENT", ([ ])));

    if ( objectp(wikiroom) )
        wikipath = wikiContext->object_to_filename(wikiroom);
    string title = doc->get_identifier();
    if ( objectp(env) && wikiroom != env )
        title = env->get_identifier() + ": " + title;

  string html =
      "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">"+
      "\n<html><head>"+
      "<meta content=\"text/html; charset=utf-8\" http-equiv=\"Content-Type\" />"+
      "<link rel=\"alternate\" type=\"application/rss+xml\" title=\""+doc->get_identifier()+"\" href=\"/scripts/rss.pike?feed="+doc->get_object_id()+"\" />\n"+
      "<link rel=\"stylesheet\" href=\"/gui_css/default/wiki.css\" />"+
      "<script src=\"/gui_js/wiki.js\" type=\"text/javascript\"></script>\n"+
      "<script src=\"/gui_js/main.js\" type=\"text/javascript\"></script>\n"+
      "<title>WIKI:"+title+"</title>"+
      "</head><body>";
  
  string path = replace_uml(wikiContext->object_to_path(doc));
  object cuser = doc->query_attribute(DOC_USER_MODIFIED);
  object user = this_user();
  string content = doc->get_content();

  array wikiTrail = add_wiki_trail(user, doc);
  
  html += //article-Tab. Here active, i.e. white
      "<div class=\"article\">"+
      "<span class=\"active_tab\">"+
      "&nbsp;Artikel&nbsp;"+
      "</span>"+
      "</div>";

  html += //edit tab, here passvie, i.e. gray
    "<div class=\"edit\">"+
    "<a href=\"/scripts/wikiedit.pike?path="+
      replace_uml(wikiContext->object_to_filename(doc))+"\">&nbsp;Bearbeiten&nbsp;</a>"+
      "</div>";
  

  html += //versions tab, here passive, i.e. gray
      "<div class=\"version\">"+
      "<a href='?type=wiki'>&nbsp;Versionsverwaltung&nbsp;</a>"+
      "</div>";

  html += //4th, invisible tab in order to get the rest of the line back to bachground color
      "<div class=\"empty\">&nbsp; </div>";



  html += 
    "<div class=\"engine_top\">"+
      "<img class=\"logo\" alt=\"RoomWiki Logo\" src=\"/images/RoomWiki.gif\" border=\"0\"/>";
 

  // user information
  object uicon = user->query_attribute(OBJ_ICON);
  html += //should result in the username being displayed
      "<div class='user'>"+
      (objectp(uicon) ?
       "<img class=\"user_img\" src=\"/scripts/get.pike?object=" + uicon->get_object_id()+"\" />":"")+
      
      "<div class='user_info'>"+user->get_name()+
      "</div></div>";

  html +="<div class='search'>"+ //Search and room
      "<form action='/scripts/browser.pike' enctype='multipart/form-data' method='post'>"+
      "<input type='hidden' name='_action' value='search' />"+
      "<input type='hidden' name='advsearch_mimetype' value='text/wiki' />"+
      "<input type='hidden' name='advsearch_objtype' value='document' />"+
      "Suche: <input type='text' name='keywords' />&nbsp;<input type='submit' value='Wiki finden'/>"+ 
      "</form></div><div class='room'>"+
      "Raum: "+
      (objectp(wikiroom) ? wikiroom->get_identifier() + "(<a href='"+wikipath+"'>"+wikipath+"</a>)": "none")+
      "<br><a href='"+wikipath+"?type=wiki'>&Uuml;bersicht</a></div>";
  
//wikitrail
  if ( this_user() != USER("guest") ) {
      html += "<div class='wiki_trail'> zuletzt besucht: ";
      foreach(wikiTrail, object trail) {
          if ( !objectp(trail) )
              continue;
          html += "&nbsp; &gt; <a class='wiki_trail' href='"+ 
              fp->object_to_filename(trail) + "'>" + trail->get_identifier() + 
              "</a>";
      }
      html += "</div>";
  }

  html += "</div>";

  string result = "";
  if ( stringp(content) ) {
      string enc = doc->query_attribute(DOC_ENCODING);
      if ( (stringp(enc) && enc == "iso-8859-1") || !xml.utf8_check(content) )
          content = string_to_utf8(content);
    
      if ( !xml.utf8_check(content) )
        steam_user_error("Unable to render wiki - wrong encoding (non utf8)");

      result = WParser->parse(wikiroom, wikiContext, content);
  }
  
  html += "<div class='wiki_content'>\n"+result+"</div>\n";
  
  html = post_process(wikiContext, html);
  if ( !wikiContext->has_footnotes )
  html += add_footnotes(wikiContext);

  html += "<div class='engine_bottom'>\n"+
    "&nbsp;</div>";

    //html += "<div class='annotations'>";
    //html += html_show_annotations(doc->get_annotations());
    //html += "</div>";
    html += "</body></html>";
    return html;
} 

 
object get_wiki_group(object obj)
{
    object creator, env;
    
    env = obj;
    while ( objectp(env) ) {
	creator = env->get_creator();
	if ( creator->get_object_class() & CLASS_GROUP ) 
	    return creator;
	env = env->get_environment();
    }
    return 0;
}

object get_wiki_room(string wiki, void|object env)
{
  if ( objectp(env) ) {
    object room = env;
    object cont = room->get_object_byname(wiki);
    if ( objectp(cont) ) {
      if ( cont->get_object_class() & CLASS_EXIT )
	return cont->get_exit();
      return cont;
    }
  }
  return 0; // fall back to wiki path
}

object get_room_environment(object obj)
{
  if ( !objectp(obj) )
    return 0;

  object room = obj;
  while ( objectp(room) &&  !(room->get_object_class() & CLASS_ROOM) ) {
      room = room->get_environment();
  }
  if ( !objectp(room) )
      return obj->get_environment();
  return room;
}

string make_diff(object newv, object oldv)
{
  if ( !objectp(newv) )
    error("Param 1: No new version object found !");
  if ( !objectp(oldv) )
    error("Param 2: No old version object found !");

  int i = 0; // compare element #
  string diff = sprintf("Diff of %s (Versions %d and %d):\n\n",
			newv->get_identifier(), 
			newv->query_attribute(DOC_VERSION),
			oldv->query_attribute(DOC_VERSION));
  string first, second;
  first = newv->get_content();
  second = oldv->get_content();

}

static string wiki_get_group_config(object grp)
{
    string config = "";
    array members = grp->get_members();
    config = "=" + grp->get_identifier() + "=\n\n";
    config = "==Members==\n";
    foreach ( members, object user ) {
	if ( !objectp(user) ) continue;
	if ( user->get_object_class() & CLASS_USER ) 
	    config += sprintf("[[user:%s]]", user->get_user_name());
	else if ( user->get_object_class() & CLASS_GROUP )
	    config += sprintf("[[group:%s]]", user->get_identifier());
    }
    return config;
}

static object wiki_create_index(object room)
{
    object indexWiki = OBJ("/packages/wikiroom/index.wiki");
    object factory = get_factory(CLASS_DOCUMENT);
    object index = factory->execute( ([ "name": "index.wiki", ]) );
    if ( objectp(indexWiki) )
	index->set_content(indexWiki->get_content());
    else
	index->set_content("=" + room->get_identifier() + "=\n"+
			   "{config:inventory.wiki}");
    index->move(room);
    return index;
}

object wiki_create_group(string name) 
{
    object grp = GROUP("WikiGroups." + name);
    if ( !objectp(grp) ) {
	object factory = get_factory(CLASS_GROUP);
	object parent = GROUP("WikiGroups");
	grp = factory->execute( ([ "name": name, "parentgroup": parent, ]) );
	grp->add_member(this_user());
	object room = grp->query_attribute(GROUP_WORKROOM);
	factory = get_factory(CLASS_CONTAINER);
	object configs = factory->execute( ([ "name": "config", ]) );
	configs->move(room);
	factory = get_factory(CLASS_DOCUMENT);
	object cfg = factory->execute( (["name":"group.wiki", ]) );
	cfg->set_content(wiki_get_group_config(grp));
	cfg->move(configs);
    }
    return grp;
}

// Container Emulation Code

object get_object_byname(string name)
{
    string grpname = "WikiGroups." + name;
    object grp = get_module("groups")->lookup(grpname);
    if ( !objectp(grp) )
	return 0;
    
    object obj = grp->query_attribute(GROUP_WORKROOM);
    return obj;
}

string contains_virtual(object obj)
{
    object creatorGroup = obj->get_creator();
    if ( creatorGroup->get_object_class() & CLASS_GROUP ) {
	if ( creatorGroup->get_parent() == GROUP("WikiGroups") )
	    return creatorGroup->query_attribute(OBJ_NAME);
    }
    return 0;
}

array(object) get_inventory() 
{
    return ({ });
}

bool insert_obj(object obj) 
{ 
    return true; //THROW("No Insert in home !", E_ACCESS); 
}

bool remove_obj(object obj) 
{ 
    return true; // THROW("No Remove in home !", E_ACCESS); 
}

void add_paths()
{
    get_module("filepath:tree")->add_virtual_path("/wiki/", this());
    get_module("filepath:url")->add_virtual_path("/wiki/", this());
}

static void load_module()
{
    call(add_paths, 0);
}

string get_identifier() { return "wiki"; }
int get_object_class() { return ::get_object_class() | CLASS_CONTAINER; }

void test()
{
  object wiki = get_factory(CLASS_DOCUMENT)->execute((["name":"test.wiki" ]));
  Test.test( "creating wiki", objectp(wiki) );
  wiki->set_content("==Wiki Test==\n");
  Test.test( "setting wiki content", sizeof(wiki_to_html_plain(wiki)) > 0 );
  
  Test.test( "deleting wiki", wiki->delete() );
}
