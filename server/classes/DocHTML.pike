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
 * $Id: DocHTML.pike,v 1.2 2009/08/07 16:14:56 nicke Exp $
 */

constant cvs_version="$Id: DocHTML.pike,v 1.2 2009/08/07 16:14:56 nicke Exp $";

inherit "/classes/Document";

//! This document type holds html data and handles link consistency.

#include <macros.h>
#include <classes.h>
#include <assert.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <events.h>

private static function        fExchange;
private static int                __size;
private static string      sFilePosition;
private static object            oParser;
        static mapping            mLinks;

#define MODE_NORMAL 0
#define MODE_STRING 1

/**
 * Initialize the document and set data storage.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
static void init_document()
{
    mLinks = ([ ]);
    add_data_storage(STORE_HTMLLINK, store_links, restore_links);
}


/**
 * Return the quoted tag.
 *  
 * @param Parser.HTML p - parser context.
 * @param string tag - the tag.
 * @return quoted tag.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static mixed quote(Parser.HTML p, string tag) {
    return ({ "<!--"+tag+"-->" });
}
/**
 * A scrip tag was found while parsing.
 *  
 * @param Parser.HTML p - the parser context.
 * @return script tag.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static mixed script(Parser.HTML p, string tag) {
    LOG("Script Tag!!!\n"+tag+"\nEND\n");
    return ({ "<SCRIPT "+tag+"SCRIPT>" });
}

/**
 * Main function for link exchange. Called every time a potential
 * link tag was parsed.
 *  
 * @param Parser.HTML p - the parser context.
 * @param string tag - the tag found.
 * @return tag with exchanged links.
 * @author Thomas Bopp (astra@upb.de) 
 */
static mixed exchange_links(Parser.HTML p, string tag) {
    array(string)  attr;
    mapping  attributes;
    string    attribute;
    bool   link = false;
    string        tname;
    int      mode, i, l;
    
    attributes = ([ ]);
    
    //        MESSAGE("TAG:"+tag);
    
    l = strlen(tag);
    mode = MODE_NORMAL;
    i = 1;
    tname = "";
    int start = 1;
    
    attr = ({ });
    while ( i < l ) {	
        if ( tag[i] == '"' || tag[i] == '\'' ) 
            mode = (mode+1)%2;
        else if ( (tag[i] == ' ' || tag[i] == '\t' || tag[i]=='\n') && 
                  mode == MODE_NORMAL ) 
        {
            attr += ({ tag[start..i-1] });
            start = i+1;
        }
        i++;
    }
    
    if ( tag[l-2] == '/' ) {
	if ( start < l-3 )
	    attr += ({ tag[start..l-3] });
    }
    else if ( start <= l-2 ) {
        attr += ({ tag[start..l-2] });
    }
    
    if ( arrayp(attr) && sizeof(attr) > 0 ) {
        string a, b;
        int       p;
        
        tname = attr[0];
        for ( int i = 1; i < sizeof(attr); i++ ) {
            if ( (p = search(attr[i], "=")) > 0 ) {
                a = attr[i][..p-1];
                b = attr[i][p+1..];
                if ( strlen(b) > 0 ) {
                    if ( b[0] == '"' || b[0] == '\'' )
                        b = b[1..strlen(b)-2];
                    attributes[a] = b;
                }
            }
        }
    }
    attr = indices(attributes);
    foreach(attr, attribute) {
        if ( lower_case(attribute) == "src" || 
             lower_case(attribute) == "href" ||
             lower_case(attribute) == "background" )
        {
            mixed err = catch {
                mixed res = fExchange(attributes[attribute]);
                if ( intp(res) && res > 0 ) {
                    attributes["oid"] =  (string)res;
                    attr += ({ "oid" });
                }
                else if ( stringp(res) )
                    attributes[attribute] = res;
            };
            if ( err != 0 )
	      FATAL("Error exchange links: %O\n%O", err[0], err[1]);
            link = true;
        }
        else if ( lower_case(attribute) == "content" ) {
            string ctype;
            if ( sscanf(attributes[attribute], "%*scharset=%s", ctype) )
                do_set_attribute(DOC_ENCODING, lower_case(ctype));
        }
    }
    
    
    string result;
    
    
    if ( link ) {
        result = "<"+tname;
        foreach(attr, attribute) {
            result += " " + attribute + "=\""+attributes[attribute] + "\"";
        }
        if ( search(tag, "/>") > -1 )
            result += "/>";
        else
            result += ">";
        //werror("Exchanged Tag: " + result+"\n");
    }
    else
        result = tag;
    
    return ({ result }); // nothing to be done
}

class UploadHTMLParser {
    object oContentHandle;
    void create(object ContentHandle) {
        oContentHandle = ContentHandle;
    }
    
    /**
     * Callback function to save a chunk of data received by the server.
     *  
     * @param string chunk - the received chunk.
     * @author Thomas Bopp (astra@upb.de) 
     */
    void save_chunk(string chunk) {
	mixed err;
        if ( objectp(oParser) ) {
            if ( !stringp(chunk) ) {
		err = catch(oParser->finish());
                if ( err != 0 ) 
		    FATAL("Parsing HTML failed: %O:%O\n", err[0], err[1]);
 
                destruct(oParser);
                oContentHandle->save_chunk(0);
                return;
            }
            else {
	        err = catch(oParser->feed(chunk, 1));
                if ( err != 0 ) 
		    FATAL("Parsing HTML failed: %O:%O\n", err[0], err[1]);
            }
        }
        
        if ( stringp(chunk) ) {
            oContentHandle->save_chunk(chunk);
        }
        else
            oContentHandle->save_chunk(0);
    }

}

/**
 * Function to start an upload. Returns the save_chunk function.
 *  
 * @param int content_size the size of the content.
 * @return upload function.
 */
function receive_content(int content_size)
{
    object obj = CALLER;
    if ( (obj->get_object_class() & CLASS_USER) &&
	 (functionp(obj->get_user_object) ) &&
	 objectp(obj->get_user_object()) )
      obj = obj->get_user_object();
    
    try_event(EVENT_UPLOAD, obj, content_size);
    
    sFilePosition = _FILEPATH->object_to_path(this_object());
    oParser = Parser.HTML();
    oParser->_set_tag_callback(exchange_links);
    oParser->add_quote_tag("!--", quote, "--");
    oParser->add_quote_tag("SCRIPT", script, "SCRIPT");
    oParser->add_quote_tag("script", script, "script");
    fExchange = exchange_ref;
    reset_links();

    // duplicate object with old content id
    int version = do_query_attribute(DOC_VERSION);
    if ( !version )
      version = 1;
    else {
      seteuid(get_creator());
      object oldversion = duplicate( ([ "content_id": get_content_id(), ])); 
      mapping versions = do_query_attribute(DOC_VERSIONS);
      oldversion->set_attribute(DOC_VERSIONS, copy_value(versions));
      if ( !mappingp(versions) )
	versions = ([ ]);
      versions[version] = oldversion;
      oldversion->set_acquire(this());

      oldversion->set_attribute(OBJ_VERSIONOF, this());
      oldversion->set_attribute(DOC_LAST_MODIFIED, do_query_attribute(DOC_LAST_MODIFIED));
      oldversion->set_attribute(DOC_USER_MODIFIED, do_query_attribute(DOC_USER_MODIFIED));
      oldversion->set_attribute(OBJ_CREATION_TIME, do_query_attribute(OBJ_CREATION_TIME));

      version++;
      do_set_attribute(DOC_VERSIONS, versions);
    }
    do_set_attribute(DOC_VERSION, version);

    do_set_attribute(DOC_LAST_MODIFIED, time());
    do_set_attribute(DOC_USER_MODIFIED, this_user());
    
    object oContentHandler = get_upload_handler(content_size);
    object oUploadHTMLParser = UploadHTMLParser(oContentHandler);
    return oUploadHTMLParser->save_chunk;
}

/**
 * Create a path inside steam which is a sequenz of containers.
 *  
 * @param string p - the path to create.
 * @return the container created last.
 */
static object create_path(string p)
{
  //MESSAGE("create_path("+p+")");
   if ( strlen(p) == 0 )
     return get_environment();

   array(string) tokens = p / "/"; 
   object cont = _ROOTROOM;
   object factory = _Server->get_factory(CLASS_CONTAINER);

   for ( int i = 0; i < sizeof(tokens)-1; i++) {
      object obj;
      if ( tokens[i] == "" ) 
	  continue;
      obj = _FILEPATH->resolve_path(cont, tokens[i]);
      if ( !objectp(obj) ) {
          obj = factory->execute((["name":tokens[i],]));
	  obj->move(cont);
      } 
      //else MESSAGE("Found path in cont: " + tokens[i]);
      cont = obj;
   }
   //MESSAGE("Found:" + cont->get_identifier());
   return cont;
}

int exchange_ref(string link)
{
    object                     obj;
    string linkstr, position, type;

    if ( !objectp(get_environment()) )
      return 0;

    link = replace(link, "\\", "/");
    if ( search(link, "get.pike") >= 0 || search(link, "navigate.pike") >= 0 )
      return 0;
    if ( sscanf(link, "%s://%s", type, linkstr) == 2 ) {
	add_extern_link(linkstr, type);
	return 0;
    }
    if ( sscanf(link, "mailto:%s", linkstr) == 1 )
    {
	add_extern_link(linkstr, "mailto");
	return 0;
    }
    if ( sscanf(lower_case(link), "javascript:%s", linkstr) == 1 ) 
      return 0;
    if ( sscanf(link, "%s#%s", linkstr, position) == 2 ) {
	link = linkstr;
    }

    if ( link == get_identifier() ) {
      add_local_link(this(), type, position, link);
      return 0;
    }
    link = combine_path(_FILEPATH->object_to_filename(get_environment()),
			link);
    mixed err = catch {
	obj = _FILEPATH->path_to_object(link);
    };
    if ( !objectp(obj) )
      return 0;

    add_local_link(obj, type, position, link);
    return obj->get_object_id();
}

object get_link(string href) 
{
    mapping links = do_query_attribute(OBJ_LINKS);
    if ( mappingp(links) )
	return links[href];
    return 0;
}



/**
 * Return mapping with save data used by _Database.
 *  
 * @return all the links.
 * @author Thomas Bopp (astra@upb.de) 
 */
mixed
store_links() 
{
    if ( CALLER != _Database ) 
	THROW("Caller is not Database !", E_ACCESS);
    return ([ "Links": mLinks, ]);
}

/**
 * Restore the saved link data. This is called by database and
 * sets the Links mapping again.
 *  
 * @param mixed data - saved data.
 * @author Thomas Bopp (astra@upb.de) 
 */
void restore_links(mixed data)
{
    if (CALLER != _Database ) THROW("Caller is not Database !", E_ACCESS);
    mLinks = data["Links"];
}

/**
 * Add a local link.
 *  
 * @param object o - the object containing a reference to this doc.
 * @param string type - the typ of reference.
 * @string position - where the link points.
 */
static void add_local_link(object o, string type, string position, string link)
{
    if ( o->get_object_id() == get_object_id() )
      return; // no links to ourself!
    if ( !mappingp(mLinks[o]) ) 
	mLinks[o] = ([ position: 1 ]);
    else {
	if ( zero_type(mLinks[o][position]) )
	    mLinks[o][position] = 1;
	else
	    mLinks[o][position]++;
    }
    mapping links = do_query_attribute(OBJ_LINKS);
    if ( !mappingp(links) )
	links = ([ ]);
    links[link] = o;
    do_set_attribute(OBJ_LINKS, links);
    
    o->add_reference(this());
    require_save(STORE_HTMLLINK);
}

/**
 * Get an array of links pointing to local(steam) objects.
 *  
 * @return array of link objects.
 */
array get_local_links()
{
    array result = ({ });
    array index = indices(mLinks);

    foreach(index, mixed idx) {
	if ( objectp(idx) )
	    result += ({ idx });
    }
    return result;
}

/**
 * Add an extern link to some URL.
 *  
 * @param string url - the url to point to.
 * @param string type - the type of the link.
 * @author Thomas Bopp (astra@upb.de) 
 */
static void add_extern_link(string url, string type)
{
    if ( zero_type(mLinks[url]) )
	mLinks[url] = 1;
    else
	mLinks[url]++;
    require_save(STORE_HTMLLINK);
	
}

/**
 * an object was deleted and so the link to this object is outdated !
 *  
 */
void removed_link()
{
    object link = CALLER->this();
    object creator = get_creator();
    run_event(EVENT_REF_GONE, link, creator);
}


/**
 * Reset all saved link data.
 *  
 */
static void reset_links()
{
    // first remove all references on other objects
    if ( mappingp(mLinks) ) {
	foreach(indices(mLinks), mixed index) {
	    if ( objectp(index) && index->status() >= 0 ) {
	      catch(index->remove_reference(this()));
	    }
	}
    }
    mLinks = ([ ]);
}

/**
 * Get a copy of the Links mapping.
 *  
 * @return copied link mapping.
 * @author Thomas Bopp (astra@upb.de) 
 */
mapping get_links()
{
    return copy_value(mLinks);
}


/**
 * Get the object class which is CLASS_DOCHTML of course.
 *  
 * @return the object class.
 */
int
get_object_class()
{
    return ::get_object_class() | CLASS_DOCHTML;
}

string get_class() { return "DocHTML"; }

/**
 * Get the size of the content which is the size of the document
 * with exchanged links.
 *  
 * @return the content size.
 * @author Thomas Bopp (astra@upb.de) 
 */
int get_content_size()
{
    return (__size > 0 ? __size : ::get_content_size());
}


void test()
{
  // todo: funktionen hinzu zum testen von create_path() und links austauschen
  ::test();
}
