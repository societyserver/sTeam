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
 * $Id: DocXSL.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: DocXSL.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";


//! This class keep XSL Stylesheets and is able to do XSLT with libxslt

inherit "/base/xml_data";
inherit "/base/xml_parser";
inherit "/classes/Document";

#include <macros.h>
#include <database.h>
#include <attributes.h>
#include <config.h>
#include <classes.h>
#include <events.h>
#include <exception.h>
#include <access.h>

//#define DOCXSL_DEBUG

#ifdef DOCXSL_DEBUG
#define DEBUG_DOCXSL(s, args...) werror(s+"\n", args)
#else
#define DEBUG_DOCXSL
#endif

static object              XML;
static mapping    mXML = ([ ]);
static mapping mDepend = ([ ]);
static mapping mLang   = ([ ]);
static bool  xmlIsLoad = false;


static mapping   mStylesheets = ([ ]); // all stylesheet objects
static object         oDescriptionXML;


static Thread.Mutex          xmlMutex = Thread.Mutex();

static mapping mAttrConv = ([
    101 : "OBJ_OWNER", 102 : "OBJ_NAME", 104 : "OBJ_DESC",
    105 : "OBJ_ICON", 111 : "OBJ_KEYWORDS", 112 : "OBJ_COMMAND_MAP",
    113 : "OBJ_POSITION_X", 114 : "OBJ_POSITION_Y", 115 : "OBJ_POSITION_Z",
    116 : "OBJ_LAST_CHANGED", 119 : "OBJ_CREATION_TIME", "url" : "OBJ_URL",
    "obj:link_icon" : "OBJ_LINK_ICON", "obj_script" : "OBJ_SCRIPT",
    "obj_annotations_changed" : "OBJ_ANNOTATIONS_CHANGED",
    207 : "DOC_TYPE", 208 : "DOC_MIME_TYPE", 213 :
    "DOC_USER_MODIFIED",
    214 : "DOC_LAST_MODIFIED", 215 : "DOC_LAST_ACCESSED",
    216 : "DOC_EXTERN_URL", 217 : "DOC_TIMES_READ",
    218 : "DOC_IMAGE_ROTATION", 219 : "DOC_IMAGE_THUMBNAIL",
    220 : "DOC_IMAGE_SIZEX", 221 : "DOC_IMAGE_SIZEY",
    300 : "CONT_SIZE_X", 301 : "CONT_SIZE_Y", 302 : "CONT_SIZE_Z",
    303 : "CONT_EXCHANGE_LINKS", "cont:monitor" : "CONT_MONITOR",
    "cont_last_modified" : "CONT_LAST_MODIFIED",
    500 : "GROUP_MEMBERSHIP_REQS", 501 : "GROUP_EXITS",
    502 : "GROUP_MAXSIZE", 503 : "GROUP_MSG_ACCEPT",
    504 : "GROUP_MAXPENDING", 611 : "USER_ADRESS", 612 :
    "USER_FULLNAME",
    613 : "USER_MAILBOX", 614 : "USER_WORKROOM", 615 :
    "USER_LAST_LOGIN",
    616 : "USER_EMAIL", 617 : "USER_UMASK", 618 : "USER_MODE",
    619 : "USER_MODE_MSG", 620 : "USER_LOGOUT_PLACE",
    621 : "USER_TRASHBIN", 622 : "USER_BOOKMARKROOM",
    623 : "USER_FORWARD_MSG", 624 : "USER_IRC_PASSWORD",
    "user_firstname" : "USER_FIRSTNAME", "user_language" :
    "USER_LANGUAGE",
    "user_selection" : "USER_SELECTION",
    "user_favorites" : "USER_FAVOURITES", 700 : "DRAWING_TYPE",
    701 : "DRAWING_WIDTH", 702 : "DRAWING_HEIGHT", 703 :
    "Drawing_COLOR",
    704 : "DRAWING_THICKNESS", 705 : "DRAWING_FILLED",
    800 : "GROUP_WORKROOM", 801 : "GROUP_EXCLUSIVE_SUBGROUPS",
    1000 : "LAB_TUTOR", 1001 : "LAB_SIZE", 1002 : "LAB_ROOM",
    1003 : "LAB_APPTIME", 1100 : "MAIL_MIMEHEADERS",
    1101 : "MAIL_IMAPFLAGS"
    ]);

mapping mUpdates = ([ ]);

class UpdateListener {
    inherit Events.Listener;

    object __obj;

    void create(object obj, object _this) {
	::create(EVENT_UPLOAD, PHASE_NOTIFY, obj, 0);
	__obj = _this;
	obj->listen_event(this_object());
    }
    void notify(int event, mixed args) {
	if ( zero_type(::get_object()) ) {
	  destruct(this_object());
	  return;
	}
	if ( _Server->query_config("xsl_disable_auto_reload") ) {
          //MESSAGE("XSL: no auto reload (server config) ...");
	    return;
	}

	__obj->load_xml_structure(); // reload
        __obj->inc_stylesheet_changed(); // refresh xsl
    }
    mapping save() {
	// do not save !
	return 0;
    }

    string describe() {
      return "UpdateListener("+
	(objectp(__obj)?__obj->get_identifier():"null")+")";
    }
    string _sprintf() { return describe(); }
    
}

/**
 * load the document - initialize the xslt.Stylesheet() object.
 * This is called when the XSL stylesheet is loaded.
 *  
 */
static void load_document()
{
  XML =  _Server->get_module("Converter:XML");
  if ( !do_query_attribute(OBJ_VERSIONOF) )
    load_xml_structure();
}


/**
 * Add a dependant stylesheet and notify it when the content
 * of this stylesheet changed.
 *  
 * @param object o - the dependant stylesheet
 */
void add_depend(object o)
{
    mDepend[o] = 1;
}

static void xsl_add_depend(object obj) 
{
  array listenings = do_query_attribute("DOCXSL_DEPENDS") || ({ });
  if ( search(listenings, obj) >= 0 )
    return;
  listenings += ({ obj });
  do_set_attribute("DOCXSL_DEPENDS", listenings);  
}

static void xsl_listen_depends()
{
  array listenings = do_query_attribute("DOCXSL_DEPENDS") || ({ });
  foreach(listenings, object l) {
    if ( !objectp(mUpdates[l]) )
      mUpdates[l] = UpdateListener(l, this());
  }
}


/**
 * callback function to find a stylesheet.
 *  
 * @param string uri - the uri to locate the stylesheet
 * @return the stylesheet content or zero.
 */
static string|int
find_stylesheet(string uri, string language)
{
    object  obj;
    object cont;
    int       i;
    
    LOG("find_stylesheet("+uri+","+language+")");
    uri = uri[1..];
    if ( uri[0] == '/' ) {
	obj = _FILEPATH->path_to_object(uri);
	if ( objectp(obj) ) {
	  obj->add_depend(this());
	  string contstr = obj->get_language_content(language);
	  return contstr;
	}
	FATAL("Failed to find Stylesheet: "+ uri +" !");
	return 0;
    }
    
    cont = _ROOTROOM;
    while ( (i=search(uri, "../")) == 0 && objectp(cont) ) {
	cont = cont->get_environment();
	uri = uri[3..];
    }
    LOG("Looking up in " + _FILEPATH->object_to_filename(cont));
    obj = _FILEPATH->resolve_path(cont, uri);

    if ( objectp(obj) ) {
	obj->add_depend(this());
        return obj->get_language_content(language);
    }
    return 0;
}

static int match_stylesheet(string uri)
{
    if ( search(uri, "steam:") == 0 )
	return 1;
    return 0;
}

static object open_stylesheet(string uri)
{
    sscanf(uri, "steam:/%s", uri);
    object obj = _FILEPATH->path_to_object(uri);
    
    if ( !objectp(obj) ) {
	FATAL("Stylesheet " + uri + " not found !");
	return 0;
    }
    DEBUG_DOCXSL("open_stylesheet("+uri+") - " + (objectp(obj)?"success":"failed"));
    return obj;
}

static string|int
read_stylesheet(object|string obj, string language, int position)
{
  if ( stringp(obj) ) {
    sscanf(obj, "steam://%s", obj);
    obj = find_object(obj);
  }
  
  if ( objectp(obj) ) {
    obj->add_depend(this());

    DEBUG_DOCXSL("read_stylesheet(language="+language+")");
    string contstr = obj->get_language_content(language);
    DEBUG_DOCXSL("length="+strlen(contstr) + " of " + obj->get_object_id());
    return contstr;
  }
  DEBUG_DOCXSL("No stylesheet given for reading...");
  return 0;
}

static void
close_stylesheet(object obj)
{
}

static void clean_xsls()
{
    foreach(values(mStylesheets), object stylesheet)
	destruct(stylesheet);
  
    mStylesheets = ([ ]);
    foreach( indices(mDepend), object o ) {
	if ( objectp(o) )
	    o->inc_stylesheet_changed();
    }
}

void inc_stylesheet_changed()
{
    DEBUG_DOCXSL("Reloading XSL Stylesheet: "+get_identifier());
    clean_xsls();
}


/**
 * Unserialize a myobject tag from the xml description file.
 *  
 * @param string data - myobject data.
 * @return the corresponding object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static object unserialize_myobject(string data)
{
    int id = (int) data;
    if ( id != 0 ) {
	return (object)find_object(id);
    }
    string prefix, val;
    if ( sscanf(data, "%s:%s", prefix, val) == 2 ) {
      switch ( prefix ) {
      case "group":
	return MODULE_GROUPS->lookup(val);
      case "instance":
      case "orb":
          object oOrb = _FILEPATH->path_to_object(val);
          if (objectp(oOrb) && oOrb->get_object_class() & CLASS_DOCLPC &&
              functionp(oOrb->provide_instance))
          {
              oOrb = oOrb->provide_instance();
              catch{ oOrb->get_identifier(); };
          }
          return oOrb;
      case "url":
	return get_module("filepath:url")->path_to_object(val);
      }
    }
    
    switch(data) {
	case "THIS":
	    return XML->THIS;
	    break;
        case "ENV":
	    return XML->THIS->ENV;
	case "CONV":
	    return XML;
	    break;
	case "THIS_USER":
	    return XML->THIS_USER;
	    break;
	case "SERVER":
	    return _Server;
	    break;
	case "LAST":
	    return XML->LAST;
	    break;
	case "ACTIVE":
	    return XML->ACTIVE;
	    break;
	case "ENTRY":
	    return XML->ENTRY;
	    break;
	case "XSL":
	    return XML->XSL;
	    break;
        case "STEAM":
	    return MODULE_GROUPS->lookup("sTeam");
	    break;
        case "local":
	    return this_object();
	    break;
        case "master": 
	    return master();
	    break;
	case "server":
	    return _Server;
	    break;
        case "ADMIN":
	    return MODULE_GROUPS->lookup("admin");
	    break;
        default:
	    return _Server->get_module(data);
	    break;
    }
    return steam_error("Failed to serialize object:"+data);
}

mapping get_default_map(string data)
{
    switch (data) {
    case "objects":
	return XML->objXML;
	break;
    case "exits":
	return XML->exitXML;
	break;
    case "links":
	return XML->linkXML;
	break;
    case "users":
	return XML->userXML;
	break;
    case "usersInv":
      	return XML->userInvXML;
	break;
    case "container":
	return XML->containerXML;
	break;
    case "properties":
      return 0;
    }
    FATAL("Warning: Default map of " + data + " not found in %s", 
	  get_identifier());
    return 0;
}

mixed unserialize_var(mixed name, mixed defval)
{
    return XML->get_var(name, defval);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
mixed unserialize(NodeXML n) 
{
    function func;
    if ( n->name == "myobject" || n->name == "o" ) {
	return unserialize_myobject(n->data);
    }
    else if ( n->name == "var" ) {
      object datanode = n->get_node("def");
      if ( sizeof(datanode->children) ) {
	FATAL("datanode with children found:" +
	      datanode->children[0]->data+"\n");
	return unserialize_var(
	    n->get_node("name")->data, 
	    unserialize(datanode->children[0]));
      }
      else
	return unserialize_var(
	    n->get_node("name")->data, 
	    n->get_node("def")->data);
    }
    else if ( n->name == "object" ) {
      object node = n->get_node("path");
      if ( objectp(node) ) {
	if ( node->name="group" )
	  return MODULE_GROUPS->lookup(node->data);
	else if ( node->name = "path" )
	  return get_module("filepath:tree")->path_to_object(node->data);
      }
    }
    else if ( n->name == "maps" ) {
	mapping res = ([ ]);
	foreach(n->children, NodeXML children) {
	  mapping m = get_default_map(children->data);
	  res |= m;
	}
	return res;
    }
    else if ( n->name == "function" ) {
	NodeXML obj = n->get_node("object");
	NodeXML f   = n->get_node("name");
	NodeXML id  = n->get_node("id");
	switch ( obj->data ) {
	case "local":
	    func = (function)this_object()[f->data];
	    break;
	case "master": 
	    object m = master();
	    func = [function](m[f->data]);
	    break;
	case "server":
	    func = [function](_Server[f->data]);
	    break;
	default:
	    object o;
	    o = _Server->get_module(obj->data);
	    if ( !objectp(o) ) {
	      FATAL("Module not found: " + obj->data);
	      return 0;
	    }
	    mixed err = catch {
	        func = o->find_function(f->data);
		if (!functionp(func))
		  FATAL("Failed to find function " + f->data + " in %O", o);
	    };
	    if ( err != 0 ) {
		FATAL("Failed to deserialize function: " + f->data + 
		    " inside " + master()->describe_object(o) + "\n"+
		    err[0] + "\n" + sprintf("%O", err[1]));
		return 0;
	    }
	    break;
	}
	if ( !functionp(func) )
	    LOG("unserialize_function: no functionp :"+
		sprintf("%O\n",func));
	return func;
    }
    return ::unserialize(n);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
string compose_scalar(mixed val)
{
    if ( objectp(val) ) {
	if ( val == XML->THIS )
	    return "<myobject>THIS</myobject>";
	else if ( val == XML->CONV )
	    return "<myobject>CONV</myobject>";
	else if ( XML->THIS_USER == val )
	    return "<myobject>THIS_USER</myobject>";
	else if ( _Server == val )
	    return "<myobject>SERVER</myobject>";
	else if ( XML->LAST == val )
	    return "<myobject>LAST</myobject>";
	else if ( XML->ACTIVE == val )
	    return "<myobject>ACTIVE</myobject>";
	else if ( XML->ENTRY == val )
	    return "<myobject>ENTRY</myobject>";
	else if ( XML->XSL == val )
	    return "<myobject>XSL</myobject>";
    }
    return ::compose_scalar(val);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
mixed compose(mixed m)
{
    if ( functionp(m) ) {
	object o = function_object(m);
	if ( !objectp(o) ) {
	    LOG("function without object:" + function_name(m));
	    return "";
	}
	if ( o == this_object()) 
	    return "<function><object>local</object><name>"+function_name(m)+
		"</name></function>";
	else if ( o == master()  )
	    return "<function><object>master</object>"+
		"<name>"+function_name(m) + "</name></function>";
	else if ( o == _Server )
	    return "<function><object>server</object>"+
		"<name>"+function_name(m) + "</name></function>";
	else 
	    return "<function><id>"+o->get_object_id()+
		"</id><object>"+o->get_identifier()+"</object>"+
		"<name>"+function_name(m) + "</name></function>";
    }
    return ::compose(m);
}

object find_xml(void|object xml)
{
  string name;
  if ( objectp(xml) )
    return xml;
  
  if ( objectp(oEnvironment) ) {
    xml = oEnvironment->get_object_byname(get_identifier()+".xml");
    sscanf(get_identifier(), "%s.%*s", name);
    
    if ( !objectp(xml) ) {
      xml = oEnvironment->get_object_byname(name+".xgl");
    }
  }
  if ( !objectp(xml) )
    xml = do_query_attribute(DOC_XSL_XML);

  // fall back to public Stylesheet, if available
  if ( !objectp(xml) || xml->status() < 0 || xml->status() == PSTAT_DELETED ) {
    xml = OBJ("/stylesheets/public.xsl.xml");
  }
  return xml;
}

array load_imports(object n)
{
  array nodes;
  if ( objectp(n) )
    nodes = n->get_nodes("language");
  
  if ( arrayp(nodes) ) 
  {
    foreach(nodes, object node) {
      array(object) imports = ({ });
      
      if ( stringp(node->attributes->auto) ) {
        object languageCont = OBJ("/languages");
        if ( objectp(languageCont) ) {
          array(object) languageNodes = ({ });
          foreach( languageCont->get_inventory_by_class(CLASS_DOCXML), object langXML) 
          {
            NodeXML langnode = xmlCache.parse(langXML);
            imports += langnode->get_nodes("import");
            languageNodes += ({ langnode });
          }
          node->replace_node( languageNodes );
        }
      }
      else 
        imports = node->get_nodes("import");
          
      foreach(imports, object imp) {
        mixed e = catch {
	  object importNodes = parse_import(imp->attributes->file);
	  if ( !objectp(importNodes) )
	    continue;
          imp->replace_node(importNodes,
                            imp->attributes->xpath);
        };
        if ( e ) {
          if ( !stringp(imp->attributes->file) ) 
            FATAL("Importing language: "+
                  "Missing file attribute on %s tag !",
                  imp->get_name());
          else
            FATAL("Failed to import file: %s, %O\%O", 
                  imp->attributes->file, e[0], e[1]);
        }
      }
    }
  }
  return nodes;
}

static int in_backtrace(object obj)
{
  if ( !objectp(obj) || !functionp(obj->get_object) || 
       !objectp(obj->get_object()) )
    return 0;

  foreach( backtrace(), mixed preceed ) {
    if ( function_object(preceed[2]) == obj->get_object() )
      return 1;
  }
  return 0;
}

/**
 * Load the related xgl (or xsl.xml) document
 *  
 */
void load_xml_structure(void|object xml)
{
  if ( in_backtrace(get_module("tar")) ) {
    call(load_xml_structure, 1);
    return;
  }

  if ( do_query_attribute(OBJ_VERSIONOF) || this()->status() < 0 ||
       this()->status() == PSTAT_DELETED )
    return; // do not load xml for old versions

    // factories must be loaded
  if ( !objectp(get_factory(CLASS_OBJECT)) ) {
    call(load_xml_structure,  1);
    return;
  }

  object xmlLock = xmlMutex->trylock();
  if ( !objectp(xmlLock) )
    steam_error("Failed to obtain xml-lock in %O", get_identifier());
  
  mixed xmlErr = catch {
    xml = find_xml(xml);
    if ( objectp(xml) ) {
      xsl_add_depend(xml);
      
      NodeXML n = parse_data(xml->get_content());
      array nodes = load_imports(n);
      mLang = read_languages(nodes);
      
      object xmlscript = do_query_attribute(DOC_XSL_PIKE);

      if ( !objectp(n) ) {
        throw( ({ "Root node '<structure>' not found in "+
                    "XML description file !", backtrace() }) );
      }
      if ( n->name == "structure" ) {
        if ( (stringp(n->attributes->generate) && 
              n->attributes->generate == "pike") ||
             stringp(n->get_pi()["steam"]) ) 
        {
	  object oldeuid = geteuid();
	  seteuid(get_creator());
          hook_xml(xml, n);
	  seteuid(oldeuid);
        }
        else {
          if ( objectp(xmlscript) )
            xmlscript->delete();
          do_set_attribute(DOC_XSL_PIKE);
          mXML = xmlTags(n);
        }
      }
    }
    else {
      if ( CALLER != this_object() ) {
        destruct(xmlLock);
        FATAL("No description file ("+get_identifier()+".xml) found for Stylesheet !");
        return;
      }
    }
    xsl_listen_depends();
  };
  
  xmlIsLoad = true;
  if ( xmlErr ) {
    FATAL("Failed to load xml structure for %s\n%O",
          _FILEPATH->object_to_filename(this_object()),
          xmlErr);
    clean_xsls();
    if ( CALLER != this_object() ) {
      destruct(xmlLock);
      throw(xmlErr);
    }
  }
  destruct(xmlLock);
}

static string read_import(string fname)
{
  object f = _FILEPATH->path_to_object(fname);
  if ( !objectp(f) ) 
    return 0;

  xsl_add_depend(f);
  return f->get_content();
}

static object parse_import(string fname)
{
  object f = _FILEPATH->path_to_object(fname);
  if ( !objectp(f) ) 
    return 0;

  xsl_add_depend(f);
  return xmlCache.parse(f);
}

int check_xgl_consistency(object xmlscript, object xmlObj)
{
  if ( objectp(xmlscript) ) {
    object script_xml = xmlscript->query_attribute(DOCLPC_XGL);
    if ( objectp(script_xml) && do_query_attribute(DOC_XSL_XML) != script_xml )
    {
      FATAL("DocXSL: mismatched Pike-Script and XGL File !");
      do_set_attribute(DOC_XSL_XML);
      xmlObj->set_attribute(DOC_LAST_MODIFIED, time());
      return 0;
    }
  }
  return 1;
}


static void hook_xml(object xmlObj, void|object rootNode)
{
  object xmlscript = do_query_attribute(DOC_XSL_PIKE);
  if (objectp(xmlscript) && xmlscript->status() < 0)
    xmlscript=0;

  check_xgl_consistency(xmlscript, xmlObj);
  if ( xmlObj == OBJ("/stylesheets/public.xsl.xml") ) {
    object oxgl = do_query_attribute(DOC_XSL_XML);
  }
  
  // check for update
  int tss = 0;
  if (objectp(xmlscript))
      tss = xmlscript->query_attribute(DOCLPC_INSTANCETIME);
  int tsc = xmlObj->query_attribute(DOC_LAST_MODIFIED);

  DEBUG_DOCXSL("Timestamp test when hooking XML: (tss=%d, tsc=%d)", tss, tsc);
  // also see if XGL file has not changed !

  if ( tss > tsc && do_query_attribute(DOC_XSL_XML) == xmlObj )
    return;

  string pikecode = XMLCodegen.codegen(xmlObj, read_import);
  set_attribute(DOC_XSL_XML, xmlObj);
  
  DEBUG_DOCXSL("Updating Pike XML Generation ...");
  string scriptname = get_object_id() + ".pike";
  if ( !objectp(xmlscript) )
    xmlscript = get_factory(CLASS_DOCUMENT)->execute(([ "name": scriptname,]));

  mixed err;
  do_set_attribute(DOC_XSL_PIKE, xmlscript);
  xmlscript->set_attribute(DOCLPC_XGL, xmlObj);
  
  if ( !check_xgl_consistency(xmlscript, xmlObj) )
    steam_error("DocXSL: consistency check failed .... !");

  err = catch(xmlscript->set_content(pikecode));
  if ( arrayp(xmlscript->get_errors()) && sizeof(xmlscript->get_errors()) > 0 ) {
    FATAL("Errors in xml Script: %O", xmlscript->get_errors());
  }
  catch(xmlscript->sanction_object(GROUP("everyone"),SANCTION_READ|SANCTION_EXECUTE));
  if ( err ) 
    FATAL("Failed to hook xml content: %s", err[0]);
  xmlscript->provide_instance(); // should create an instance when loaded
}

/**
 * Get the xml structure as a mapping.
 *  
 * @return the xml structure mapping
 */
mapping get_xml_structure()
{
    return copy_value(mXML);
}



/**
 * Resolves the show function of the xml tag definition and returns a
 * mapping or function with corresponding informations.
 *  
 * @param NodeXML n - the node to convert
 * @return mapping or function of node information
 */
function|mapping xmlTagShowFunc(NodeXML n)
{
    if ( !objectp(n) )
      return 0;
    NodeXML f = n->get_node("f");
    if ( !objectp(f) ) {
	NodeXML m = n->get_node("map");
	if ( !objectp(m) )
	    m = n->get_node("structure");
	if ( !objectp(m) )
	    return 0;
	mapping res = ([ ]);
	res += xmlTags(m);
	if ( m->attributes->name )
	    res["name"] = m->attributes->name;
	
	foreach(m->children, object tag) {
	    if ( tag->name == "tag" ) {
		res[tag->attributes->name] += xmlTag(tag);
	    }
	    else if ( tag->name == "def" ) {
		mapping def = get_default_map(tag->data);
		if ( mappingp(def) ) {
		    res += def;		    
		}
	    }
	}
	return res;
    }
    function func;
    object    obj;

    NodeXML na = f->get_node("n");
    NodeXML o  = f->get_node("o");
    if ( !objectp(n) )
	THROW("Function tag (f) has no sub tag 'n' !", E_ERROR);

    if ( !objectp(o) )
	obj = XML;
    else {
	obj = unserialize_myobject(o->data);
	if (!objectp(obj))
	  steam_error("Failed to find object " + o->data);
    }
	
    
    mixed err = catch {
	if ( !objectp(na) ) 
	  steam_user_error("Missing 'n' Node inside <f> to specify function!");
	func = [function]obj->find_function(na->data);
	if (!functionp(func))
	  FATAL("Failed to find function " + na->data + " in %O", obj);
    };
    if ( err != 0 ) {
	FATAL("Failed to deserialize function in: " + f->dump() + 
	    " inside %s\n%s", _FILEPATH->object_to_filename(this()), err[0]);
	return 0;
    }
    return func;
}

/**
 * Convert possible calls to Attribute functions to new string format
 * (previously numbers where used.
 *  
 * @param string fname - name of the function to be called.
 * @param array params - the params to convert
 * @return new parameters
 */
static array attribute_conversion(string fname, array params)
{
    if ( fname == "query_attribute" ) {
      for ( int i = sizeof(params) - 1; i >= 0; i-- ) {
	if ( stringp(mAttrConv[params[i]]) ) {
		params[i] = mAttrConv[params[i]];
	    }
	}
    }
    return params;
}

/**
 * Resolve the xml tag call function definition. Which function to call
 * for the tag.
 *  
 * @param NodeXML n - the Node <tag>
 * @return corresponding information array with structure used by converter
 */
array xmlTagCallFunc(NodeXML n)
{
    array res, params;
    
    if ( !objectp(n) )
      return ({ XML->THIS, "null", ({ }), 0 });

    NodeXML f = n->get_node("n");
    NodeXML o = n->get_node("o");
    NodeXML p = n->get_node("p");
    
    object obj;
    
    if ( !objectp(f) ) 
	THROW("No Node n (function-name) found at function tag", E_ERROR);

    if ( !objectp(o) )
	obj = XML->THIS;
    else 
	obj = unserialize_myobject(o->data);
    if ( objectp(p) ) {
        p->data = String.trim_whites(p->data - "\n");
	if ( stringp(p->data) && strlen(p->data) > 0 )
	    steam_error("Found data in param tag - all params need to be "+
			"in type tags like <int>42</int>.\n"+
		"Context: "+n->get_xml()+"\nOffending:\n"+p->data);
	params = xmlArray(p);
	params = attribute_conversion(f->data, params);
    }
    if ( !arrayp(params) )
	params = ({ });
    
    res = ({ obj, f->data, params, 0 });
    return res;
}

private static array xmlTag(NodeXML n) 
{
    array res;
    object call = n->get_node("call/f");
    res = xmlTagCallFunc(call);
    res[3] = xmlTagShowFunc(n->get_node("show"));
    return res;
}

private static mapping xmlTags(NodeXML n) 
{
    mapping res = ([ ]);
    foreach(n->children, object node) {
	if ( node->name == "class" ) {
	    int t;
	    string type = node->attributes->type;
	    t = (int) type;
	    if ( t == 0 ) {
		object f = _Server->get_factory(type);
		if ( objectp(f) )
		    t = f->get_class_id();
		else
		    steam_error("Unable to find factory for " + type);
	    }
	    if ( t == 0 ) {
		steam_error("Fatal error loading xml structure: " +
			    "Unable to identify class-id for '" + type + "'.");
	    }
	    res[t] = ([ ]);
	    foreach(node->get_nodes("tag"), object tag) {
	      if ( !objectp(tag->get_node("call") ) )
		continue; // ignore nodes with call 
	      res[t][tag->attributes->name] = xmlTag(tag);
	    }
	}
    }
    if ( n->attributes->name )
	res["name"] = n->attributes->name;

    return res;
}

static mapping read_languages(array(NodeXML) nodes, void|object xml)
{
  mapping res = ([ ]);

  if ( !arrayp(nodes) )
    return res;
  
  foreach(nodes, object node) {
    if ( node->name == "language" ) {
      res[node->attributes->name] = ([ ]);
      foreach(node->get_nodes("term"), object term) {
	res[node->attributes->name]["{"+term->attributes->name+"}"]=term->get_data();
      }
    }
  }
  return res;
}

static void 
content_finished()
{
    // successfull upload...
    ::content_finished();
    clean_xsls();
}

/**
 * Get the content of this object with replacements for the language.
 * This means that templates like {TEMPLATE_NAME} are replaced with
 * the corresponding entry in the xml file. If the language is not
 * defined then english is used as default language.
 *  
 * @param void|string language - the language
 * @return the stylesheet.
 */

string get_language_content(void|string language)
{
  string content;
  if ( stringp(language) ) {
    string str = ::get_content();

    if ( mappingp(mLang[language]) ) {
      mapping m = mLang[language];
      content = replace(str, indices(m), values(m));
    }
    else if ( mappingp(mLang->english) ) {
      content = replace(str, indices(mLang->english),values(mLang->english));
    }
    else {
      //FATAL("No Languages initialized for %s", get_identifier());
      return str;
    }
    return content;
  }
  else 
    return ::get_content();
}


/**
 * Get the xslt.Stylesheet() object.
 *  
 * @return the stylesheet.
 */
object get_stylesheet(string|void language)
{
    mixed err;

    object lock = xmlMutex->lock();
    if ( !xmlIsLoad ) {
      destruct(lock);
      steam_error("DocXSL: Cannot retrieve data from uninitialized Stylesheet!");
    }

    if ( !stringp(language) )
      language = "english";

    if  ( !objectp(mStylesheets[language]) ) {
      // now I got some (the real one, but it needs internationalization)
      object stylesheet;
      err = catch {
	
	string xsl_code = get_language_content(language);
	xsl_code = replace( xsl_code, "&nbsp;", "&#160;" );
    
	stylesheet = xslt.Stylesheet();
	mStylesheets[language] = stylesheet;

	stylesheet->set_include_callbacks(match_stylesheet,
					  open_stylesheet,
					  read_stylesheet,
					  close_stylesheet);
	stylesheet->set_language(language);
	stylesheet->set_content(xsl_code);
      };
      if ( err != 0 ) {
	destruct(stylesheet);
	mStylesheets[language] = 0;
	err[0] = "Error Parsing " + get_identifier() + "\n" + err[0];
	destruct(lock);
	throw(err);
      }
    }

    destruct(lock);
    if ( objectp(mStylesheets[language]) ) {
      return mStylesheets[language];
    }
    return mStylesheets["english"];
}

string get_method()
{
    object xsl = get_stylesheet();
    if ( objectp(xsl) )
	return xsl->get_method();
    return "plain";
}

string get_encoding()
{
    object xsl = get_stylesheet();
    if ( objectp(xsl) )
	return xsl->get_encoding();
    return "utf-8";
}

array(string) get_styles() 
{ 
    return ({ "content", "attributes", "access", "annotations" });
}

bool   check_swap() { return false; } // do not swap out stylesheets
int get_object_class() { return ::get_object_class() | CLASS_DOCXSL; }
string get_class() { return "DocXSL"; }


void test()
{
  // check xsl.xml here...
  MESSAGE("* Testing DocXSL functionality and libxslt ...");
  MESSAGE("Creating test container...");
  object testcont = OBJ("/home/steam/__xsltestcont");
  if ( !objectp(testcont) ) {
    testcont=get_factory(CLASS_CONTAINER)->execute( (["name":"__xsltestcont"]) );
    testcont->move(OBJ("/home/steam"));
  } else {
    foreach(testcont->get_inventory(), object inv) {
      inv->delete();
    }
  }
  move(testcont);
  
  MESSAGE("Creating language file...");
  object languages = get_factory(CLASS_DOCUMENT)->execute( (["name":"terms.xml",]) );
  MESSAGE("Language file is %O", languages);
  languages->set_content("<?xml version='1.0' encoding='utf-8'?>\n<language><term name='TERM1'>term_1</term></language>\n");
  languages->move(testcont);

  string pathname = _FILEPATH->object_to_filename(languages);

  MESSAGE("Creating XGL File...");
  object xgl = get_factory(CLASS_DOCUMENT)->execute( (["name": "test.xgl", ]) );
  xgl->set_content("<?xml version='1.0' encoding='utf-8'?>\n<structure generate='pike'>\n<class type='Object'>\n<tag name='test'><call><function name='get_identifier' /></call><show><function name='show' /></show></tag></class><language name='english'><import file='"+pathname+"' xpath='term' /></language>\n</structure>\n");
  
  xgl->move(testcont);
  MESSAGE("Testing xsl...");
  set_content("<?xml version='1.0' encoding='utf-8'?>\n<xsl:stylesheet xmlns:xsl='http://www.w3.org/1999/XSL/Transform' version='1.0'>\n<xsl:output method='html' encoding='utf-8' />\n<xsl:template match='Object/test'>{TERM1}: testing</xsl:template>\n</xsl:stylesheet>");
  if (find_xml()!=xgl)
    steam_error("find_xml() does not return proper XGL file !");
  load_xml_structure(xgl);
  
    object pikescript = do_query_attribute(DOC_XSL_PIKE);
  if ( !objectp(pikescript) )
    steam_error("Generation of Pike-Script failed !");

  MESSAGE("Looking for UpdateListener ...");
  if ( !objectp(mUpdates[xgl]) )
    steam_error("No Update Listener for XGL ...");
  if ( !objectp(mUpdates[languages]) ) {
    MESSAGE("Dumping Update Listeners:\n%O", indices(mUpdates));
    steam_error("No Update Listener for Language Term File (%O) ...", languages);
  }
  call(test_more, 1, pikescript, xgl, languages, testcont, "", 0);
}

void test_more(object pikescript, object xgl, object languages, object testcont, string xml, int test)
{
  if ( pikescript->status() != PSTAT_DISK ) {
    pikescript->drop();
    call(test_more, 5, pikescript, xgl, languages, testcont, xml, test);
    return;
  }
  switch(test) {
  case 0:
    MESSAGE("Testing xml generation !");
    mapping params = ([ "this_user": USER("root")->get_object_id(), ]);
    MESSAGE("DOC_XSL_PIKE=%O", do_query_attribute(DOC_XSL_PIKE));
    xml = get_module("Converter:XML")->get_xml(this(), this(), params);
    // xgl file controls xml generatoin - should be simple xml
    MESSAGE("XML Generated: \n%s---", xml);
    if ( search(xml, "XGL File: "+_FILEPATH->object_to_filename(xgl)) == -1 )
      steam_error("XGL Test: Used wrong xgl file for XML Generation !");
    string result = get_module("libxslt")->run(xml, this(), ([ ]));
    MESSAGE("OUTPUT = %s", result);
    call(test_more, 2, pikescript, xgl, languages, testcont, xml, 1);
    break;
  default:
    MESSAGE("Testing update of depend...");
    languages->set_content("<?xml version='1.0' encoding='utf-8'?>\n<language><term name='TERM1'>modified</term></language>\n");
    result = get_module("libxslt")->run(xml, this(), ([ ]));
    if ( search(result, "modified") == -1 )
      steam_error("Language File Update did not update Term Definition in %O !"+
                  "\nDump: %s", languages, result);
    languages->delete();
    testcont->delete();
    xgl->delete();
    delete();
    MESSAGE("* DocXSL.test() all tests finished successfully !");
  }
}
