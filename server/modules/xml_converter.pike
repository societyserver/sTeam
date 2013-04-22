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
 * $Id: xml_converter.pike,v 1.3 2009/08/07 16:14:56 nicke Exp $
 */

/************** deprecated module *****************/

constant cvs_version="$Id: xml_converter.pike,v 1.3 2009/08/07 16:14:56 nicke Exp $";

inherit "/kernel/module";
inherit "/base/xml_data";

import XMLCodegen;
import httplib;



#include <macros.h>
#include <database.h>
#include <attributes.h>
#include <classes.h>
#include <types.h>
#include <access.h>
#include <events.h>
#include <client.h>
#include <config.h>

//#define XML_DEBUG

#ifdef XML_DEBUG
#define DEBUG_XML(s) werror(s+"\n")
#else
#define DEBUG_XML(s)
#endif

#define ID_OBJECT 0
#define ID_FUNC   1
#define ID_PARAMS 2
#define ID_CONV   3

#define ID_THIS      1
#define ID_THIS_USER 2

#ifdef RESTRICTED_NAMES
#define OBJ_DESC_OR_NAME OBJ_DESC
#else
#define OBJ_DESC_OR_NAME OBJ_NAME
#endif

class OBJECT {
    int       id;
    object   obj;
    mapping vars;
    void create(int i, void|object o) { id = i; obj = o; }
    object this() { return obj; }
    string get_identifier() { return obj->get_identifier(); }
    function find_function(string f) { return obj->find_function(f); }
};

class Param {
    mixed val;
    mixed def; // the default value
    string name;
   
    mixed cast(string castto) {
	switch(castto) {
	case "int":
	    return (int)val; 
	case "string":
	    return (string)val;
	default:
	    return val;
	}
    }
    mixed this() { return val; }
};

OBJECT THIS = OBJECT(ID_THIS);
OBJECT THIS_USER = OBJECT(ID_THIS_USER);
OBJECT CONV = OBJECT(0);
OBJECT LAST = OBJECT(0);
OBJECT ACTIVE = OBJECT(0);
OBJECT XSL = OBJECT(0);
OBJECT ENV = OBJECT(0);

class KEYVALUE {
    mixed key;
    mixed val;
    object this() { return this_object(); }
};

static mapping activeThreadMap = ([ ]);
static mapping params = ([ ]);

KEYVALUE ENTRY = KEYVALUE();


mapping objXML = ([ CLASS_OBJECT: ([
    "name":          ({ THIS, "query_attribute", ({ OBJ_NAME }), show }), 
    "icon":          ({ THIS, "get_icon", ({  }), show_object_ext }),
    "environment":   ({ THIS, "get_environment", ({          }), show }),
    "id":            ({ THIS, "get_object_id",   ({          }), show }),
    "last-modified": ({ CONV, "get_last_modified", ({ THIS,  }), get_time }),
    "modified-by":   ({ THIS, "query_attribute", ({DOC_USER_MODIFIED }),show}),
    "created":       ({ THIS, "query_attribute", 
			    ({OBJ_CREATION_TIME }), get_time }),
    "owner":         ({ THIS, "get_creator", ({ }), show }),
    "URL":           ({ THIS, "get_identifier", ({ }), no_uml }),
    "content":       ({ CONV, "show_content", ({ THIS }), 0 }),
    "annotated":     ({ CONV, "show_annotations_size", ({ THIS }), 0 }),
    ]), 
]);

mapping annotationXML = ([ CLASS_OBJECT: objXML[CLASS_OBJECT] + 
([  "mime-headers": ({ THIS, "query_attribute", ({ MAIL_MIMEHEADERS }),
     show_mapping }),
   "description":  ({ THIS, "query_attribute", ({OBJ_DESC_OR_NAME}), show })
]), ]);

mapping linkXML = ([ CLASS_LINK: ([
    "link":   ({ THIS, "get_link_object", ({ }), show_object_ext }),
    "action": ({ THIS, "get_link_action", ({ }), show }),
    ]), ]);

mapping exitXML = ([ CLASS_EXIT: ([
    "exit": ({ THIS, "get_exit", ({ }), show_exit }),
    ]), ]);


mapping userXML = ([ CLASS_USER: ([
    "email":        ({ THIS, "query_attribute", ({ USER_EMAIL }), show }),
    "inventory":    ({ THIS, "get_inventory",   ({       }), show_size}),
    "mailbox-size": ({ THIS, "get_annotations", ({  }), show_mailbox_size }), 
    "trail":        ({ THIS, "query_attribute", ({ "trail" }), show_trail }),
    "id":            ({ THIS, "get_object_id",   ({          }), show }),
    "fullname":     ({ THIS, "query_attribute", ({USER_FULLNAME}),show}),
    "firstname":    ({ THIS, "query_attribute", ({USER_FIRSTNAME}), show}),
    "name":          ({ THIS, "query_attribute", ({ OBJ_NAME }), 0 }), 
    "identifier":    ({ THIS, "get_user_name",   ({ }), show }),
    "icon":          ({ THIS, "query_attribute", ({ OBJ_ICON }), show }),
    "environment":   ({ THIS, "get_environment", ({          }), show }),
    "description":   ({ THIS, "query_attribute", ({ OBJ_DESC }), show }),
    "carry":         ({ CONV, "show_carry",      ({ }), 0 }),
    "admin":         ({ (MODULE_GROUPS ? MODULE_GROUPS->lookup("admin") : 0),"is_member", ({ THIS }), show_truefalse }),
    "active-group":  ({ THIS, "get_active_group", ({ }), show }),
    "status":        ({ THIS, "get_status", ({ }), show_status }),
    "language":      ({ THIS, "query_attribute", ({ USER_LANGUAGE }), show }),
    ]), ]);    

mapping userInvXML = ([ CLASS_USER: ([
    "id":            ({ THIS, "get_object_id",   ({          }), show }),
    "name":          ({ THIS, "query_attribute", ({ OBJ_NAME }), 0 }), 
    "icon":          ({ THIS, "query_attribute", ({ OBJ_ICON }), show }),
    "status":        ({ THIS, "get_status", ({ }), show_status }),
  ]), ]);
  

mapping annotationsXML = ([ CLASS_OBJECT: ([
    "annotations": ({ THIS, "get_annotations_for", ({ THIS_USER }),
			  show_annotations }),
    "active-content": ({ ACTIVE, "get_content", ({ }), show }),
    ]), ]);

mapping userDetailsXML = ([ CLASS_USER: ([
    "groups": ({ THIS, "get_groups", ({ }), show }),
    "access":        ({ CONV, "get_basic_access", ({ THIS }), 0 }),
    "user":      ({ 0,    this_user,       ({      }), userXML }),
    "attributes": ({ THIS, "get_attributes", ({ }), ([
	"attribute": ({ CONV, "show_attribute", ({ ENTRY }),0})
	]), })
    ]) + userXML[CLASS_USER], ]);
    
    
mapping containerXML = ([
    CLASS_CONTAINER: ([
	"description":   ({ THIS, "query_attribute", ({ OBJ_DESC }), show }),
	"inventory": ({ THIS, "get_inventory", ({ }), show_size }),
	]),
    ]);
	

mapping mailboxXML = ([ 
    CLASS_OBJECT: 
    ([
	"path":      ({ CONV, "get_path",      ({ THIS }), 0 }),
	"user":      ({ 0,    this_user,       ({      }), userXML }),
	])+objXML[CLASS_OBJECT],
    CLASS_CONTAINER: 
    ([
	"inventory": ({ THIS, "get_inventory", ({      }),
			    objXML+exitXML+linkXML+userInvXML+containerXML }),
	]),
    ]);

mapping iconsXML = ([
    CLASS_OBJECT:
    ([ "icons": ({ THIS, "get_icons", ({ }), show }),
       "user":      ({ 0,    this_user,       ({      }), userXML }),
     ])+objXML[CLASS_OBJECT], ]);
    
mapping contentXML = ([ 
    CLASS_OBJECT: 
    ([
	"path":      ({ CONV, "get_path",      ({ THIS }), 0 }),
	"user":      ({ 0,    this_user,       ({      }), userXML }),
	])+objXML[CLASS_OBJECT],
    CLASS_CONTAINER: 
    ([
	"inventory": ({ THIS, "get_inventory", ({      }),
			    objXML+exitXML+linkXML+userInvXML+containerXML}),
	]),
    ]);

    

array(string) __sanction;
static mapping mXML = ([ ]);
static mapping mSelection = ([ ]);
static array(object) selection;


static mapping entities = ([
    "ä": "&#228;",
    "Ä": "&#196;",
    "ü": "&#252;",
    "Ü": "&#220;",
    "ö": "&#246;",
    "Ö": "&#214;",
    "<": "&lt;",
    ">": "&gt;",
    ]);

/**
 * Initialize the module, this function is called when the module is loaded.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void load_module()
{
    if ( objectp(_SECURITY) )
	__sanction = _SECURITY->get_sanction_strings();
    CONV->obj = this();
    // if the state of an object changed, we have to update cache !
}

string no_uml(string str)
{
    return httplib.no_uml(str);
}



/**
 * Exchange some entities to fix the html sources. Especially umlaute.
 *  
 * @param string txt - the text where to exchange Umlaute, etc.
 * @return the replaced text.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
string htmlize(string txt)
{
    string html = replace(txt, indices(entities), values(entities));
    return html;
}

/**
 * Show function to bring a config mapping in xml format.
 * It will have each configuration listed as config name='config-name'
 * with the value as container data.
 *  
 * @param mapping configs - the configuration mapping to bring to xml.
 * @return the converted mapping.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_configs(mapping configs)
{
    string xml = "";
    foreach(indices(configs), mixed index) {
	if ( stringp(configs[index]) || intp(configs[index]) )
	    xml += "\t<config name=\""+index+"\">"+configs[index]+"</config>\n";
    }
    return xml;
}

string show_ports(array ports)
{
    string xml = "";
    foreach(ports, object port) {
	xml += "<port nr='"+port->get_port()+"'>"+port->describe()+"</port>";
    }
    return xml;
}

/**
 * Time function just calls time().
 *  
 * @return the current timestamp (unix-time).
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int gettime() 
{ 
    return time(); 
}

int cmp_names(object obj1, object obj2)
{
  return lower_case(obj1->get_identifier())>lower_case(obj2->get_identifier());
}

int cmp_size(object obj1, object obj2)
{
  if ( obj1->get_object_class() & CLASS_CONTAINER )
    return sizeof(obj1->get_inventory()) > sizeof(obj2->get_inventory());
  return obj1->get_content_size() > obj2->get_content_size();
}

int cmp_date(object obj1, object obj2)
{
  return obj1->query_attribute(DOC_LAST_MODIFIED) > 
    obj2->query_attribute(DOC_LAST_MODIFIED);
}

int cmp_names_rev(object obj1, object obj2)
{
  return lower_case(obj1->get_identifier())<lower_case(obj2->get_identifier());
}

int cmp_size_rev(object obj1, object obj2)
{
  if ( obj1->get_object_class() & CLASS_CONTAINER )
    return sizeof(obj1->get_inventory()) < sizeof(obj2->get_inventory());
  return obj1->get_content_size() < obj2->get_content_size();
}

int cmp_date_rev(object obj1, object obj2)
{
  return obj1->query_attribute(DOC_LAST_MODIFIED) <
    obj2->query_attribute(DOC_LAST_MODIFIED);
}

/**
 * Get the inventory of a container, parameters have to include
 * an object range, optionally the container can bhe sorted with
 * "name", "reverse-name", "size", "reverse-size", "modified" or
 * "reverse-modified".
 *  
 * @param object cont - the container to show
 * @param int from_obj - the start of the object range
 * @param int to_obj - the end of the object range.
 * @param string sort - sort option.
 * @return (sorted) array of objects
 */
array(object) 
get_cont_inventory(object cont, int from_obj, int to_obj, void|string sort)
{
    array(object) inv = cont->get_inventory();
    array(object) arr = ({ });
    array(object) obj_arr = ({ });
    array(object) cont_arr = ({ });

    foreach( inv, object obj ) {
	if ( obj->get_object_class() & CLASS_EXIT || 
	     obj->get_object_class() & CLASS_ROOM ||
	     obj->get_object_class() & CLASS_USER )
	    arr += ({ obj });
	else if ( obj->get_object_class() & CLASS_CONTAINER )
	  cont_arr += ({ obj });
	else if ( !(obj->get_object_class() & CLASS_DRAWING) )
	  obj_arr += ({ obj });
    }
    if ( !stringp(sort) || sort == "none" ) {
	sort = cont->query_attribute("web:sort:objects");
	if ( sort == "last-modified/time" )
	    sort = "modified";
    }

    // sort the array of objects
    if ( stringp(sort) ) {
      switch ( sort ) {
      case "name":
	obj_arr = Array.sort_array(obj_arr, cmp_names);
	cont_arr = Array.sort_array(cont_arr, cmp_names);
	break;
      case "size":
	obj_arr = Array.sort_array(obj_arr, cmp_size);
	cont_arr = Array.sort_array(cont_arr, cmp_size);
	break;
      case "modified":
	obj_arr = Array.sort_array(obj_arr, cmp_date);
	cont_arr = Array.sort_array(cont_arr, cmp_date);
	break;
      case "reverse-name":
	obj_arr = Array.sort_array(obj_arr, cmp_names_rev);
	cont_arr = Array.sort_array(cont_arr, cmp_names_rev);
	break;
      case "reverse-size":
	obj_arr = Array.sort_array(obj_arr, cmp_size_rev);
	cont_arr = Array.sort_array(cont_arr, cmp_size_rev);
	break;
      case "reverse-modified":
	obj_arr = Array.sort_array(obj_arr, cmp_date_rev);
	cont_arr = Array.sort_array(cont_arr, cmp_date_rev);
	break;
      }
    }
    obj_arr = cont_arr + obj_arr;
    if ( to_obj == 0 ) to_obj = sizeof(obj_arr);
    
    return obj_arr[from_obj-1..to_obj-1] + arr;
}

string show_inventory_size(object cont)
{
    string xml = "";
    int docs, conts, rooms, exits, users;


    // fixme: use this function ?
    array(object) inv = cont->get_inventory();
    foreach(inv, object o) {
	if ( o->get_object_class() & CLASS_USER )
	    users++;
	else if ( o->get_object_class() & CLASS_ROOM )
	    rooms++;
	else if ( o->get_object_class() & CLASS_EXIT )
	    exits++;
	else if ( o->get_object_class() & CLASS_CONTAINER )
	    conts++;
	else if ( o->get_object_class() & CLASS_DOCUMENT )
	    docs++;
    }
    return xml;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int get_last_modified(object obj)
{
    if ( obj->get_object_class() & CLASS_DOCUMENT )
	return obj->query_attribute(DOC_LAST_MODIFIED);
    else if ( obj->get_object_class() & CLASS_CONTAINER )
	return obj->query_attribute(CONT_LAST_MODIFIED);
    else
	return obj->query_attribute(OBJ_LAST_CHANGED);
}

/**
 * Get the name for an object class. This function queries the factory
 * of the object to get the name.
 *  
 * @param int id - the class id
 * @return the class-name string
 * @author Thomas Bopp (astra@upb.de) 
 */
string class_id_to_name(int id)
{
    if ( id & CLASS_SCRIPT )
      return "\"Script\"";

    object factory = _Server->get_factory(id);
    if ( objectp(factory) ) 
	return "\""+factory->get_class_name()+"\"";
    else
	return "\"Object\"";
}

/**
 * Show extended object information.
 * <object type='Object'><name/><id/><path/><description/></object>
 *  
 * @param object obj - the object to show.
 * @return extended object information xml code.
 */
string show_object_ext(object obj)
{
    if ( !objectp(obj) )
	return "";

    return "<object type="+class_id_to_name(obj->get_object_class())+
	"><name><![CDATA["+obj->query_attribute(OBJ_NAME)+"]]></name>"+
	"<id>"+obj->get_object_id()+"</id><path><![CDATA["+
      (obj->get_object_class() & CLASS_DOCEXTERN ?
       obj->query_attribute(DOC_EXTERN_URL):
	replace_uml(_FILEPATH->object_to_filename(obj)))+
	"]]></path><description><![CDATA["+
	obj->query_attribute(OBJ_DESC)+"]]></description></object>";
}


string show_objects_ext(array(object) objs)
{
    string xml = "<array>";
    foreach(objs, object obj)
	xml += show_object_ext(obj);
    xml += "</array>\n";
    return xml;
}

string show_trail(array(object) trail, int|void sz)
{
    array walk = ({ });
    int i, way;

    if ( sz == 0 )
	sz = 4;
    string xml = "";

    // try to detect loop in trail, only A,B,A,B
    way = 0;


    xml = "<array>";
    for ( i = sizeof(trail) - 1 - sz; i < sizeof(trail); i++ ) {
	if ( i < 0 ) continue;
	xml += show_object_ext(trail[i]);
    }
    xml += "</array>";
	
    return xml; 
}


/**
 * Show extended information for XSL objects in this converter.
 *  
 * @param mixed s - the value to show in xml
 * @return the value in xml
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see show
 */
string compose_scalar(mixed s)
{
    if ( objectp(s) && s->get_object_class() & CLASS_DOCXSL) {
	return "<object><name>"+s->get_identifier()+"</name>"+
	    "<id>"+s->get_object_id()+"</id><path>"+
	    _FILEPATH->object_to_filename(s)+"</path></object>";
    }
    return ::compose_scalar(s);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
array(object) get_filtered_inventory(object obj, mixed key, mixed val)
{
    array inv = obj->get_inventory();
    array res = ({ });
    foreach ( inv, object o ) {
        mixed v = o->query_attribute(key);
	if ( objectp(val) )
	  val = val->this();
	if ( !v )
	    res += ({ o });
	else if ( arrayp(v) && !arrayp(val) && search(v,val) >= 0 )
	    res += ({ o });
	else if ( val == v )
	    res += ({ o });
    }
    return res;
}

/**
 * Show an attribute. This is done without the basic conversion to
 * xml with string|int, because for example the data type of
 * name or id tags is already known.
 *  
 * @param mixed val - the value to convert
 * @return the converted value
 */
string show(string|int|object|mapping|program|array val)
{
    DEBUG_XML("show:"+sprintf("%O", val));
    if ( stringp(val) )
	return "<![CDATA["+val+"]]>";
    else if ( intp(val) )
	return (string)val;
    else if ( objectp(val) && stringp(val->query_attribute(OBJ_NAME)) &&
	      !xml.utf8_check(val->query_attribute(OBJ_NAME)) )
      return "<invalid_object_utf8>"+val->get_object_id()+"</invalid_object_utf8>";
    return compose(val);
}

/**
 * Show xml code for an exit - that is the destination.
 *  
 * @param object exit - the exit to show.
 * @return xml string representation.
 * @see show
 */
string show_exit(object exit)
{ 
    string p = 	_FILEPATH->object_to_filename(exit);
    if ( p[-1] != '/' )
	p+="/";
    p = no_uml(p);
    return "<object><id>"+exit->get_object_id()+"</id><path>"+p+"</path>"+
	"<name>"+exit->get_identifier()+"</name></object>\n";
}

/**
 * Gives xml code for the creator of an object.
 *  
 * @param object creator - the creator.
 * @return xml code for creator object.
 */
string show_creator(object creator)
{
    // show also type
    return "<object type="+class_id_to_name(creator->get_object_class())+"><id>"+creator->get_object_id()+"</id>"+
	"<name>"+creator->get_identifier()+"</name></object>\n";
}


/**
 * Show the status status in terms of CLIENT_FEATURES_*
 *  
 * @param int status - the status to xmlize.
 * @return the xml converted status.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_status(int status)
{
    string xml = "";
    
    if ( status & CLIENT_FEATURES_CHAT )
	xml += "<chat>true</chat>";
    else
       	xml += "<chat>false</chat>";

    if ( status & CLIENT_STATUS_CONNECTED )
	xml += "<connected>true</connected>";
    else
	xml += "<connected>false</connected>";
    return xml;
}

/**
 * Return false for value 0 and otherwise true.
 *  
 * @param mixed val - the value for true or false
 * @return true or false as a string
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_truefalse(mixed val)
{
    if ( val == 0 )
	return "false";
    return "true";
}

/**
 * Show the size of an array or the inventory size of an container.
 * an container ?
 *  
 * @param object|array o - the array or container to show its size.
 * @return size of container or array.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_size(object|array o)
{
    if ( arrayp(o) )
	return (string)sizeof(o);
    else if ( objectp(o) && o->get_object_class() & CLASS_CONTAINER )
	return (string)sizeof(o->get_inventory());
    return 0;
}

string show_size_unread(object|array o)
{
    object trd = _Server->get_module("table:read-documents");
    if ( arrayp(o) ){
	int sz = 0;
	int msgs = 0;
	foreach(o, object obj) {
	    o += obj->get_annotations();
	    if ( objectp(trd) ) {
		if ( !trd->is_reader(obj, this_user()) )
		    sz++;
	    }
	    msgs++;
	}
	return"<unread>"+sz+"</unread><messages>"+msgs+"</messages>";
    }
    return "<unread>0</unread><messages>0</messages>";
}

string show_mailbox_size(object|array o)
{
  return show_size_unread(o);
}

string show_annotations_size(object o)
{
  if ( o->get_object_class() & CLASS_USER )
    return "<unread>0</unread><messages>0</messages>";
  return show_size_unread(o->get_annotations());
}


/**
 * Get the permission role for some access bit array or an object.
 *  
 * @param int|object access - the access integer or access object
 * @return string description of the objects access permissions.
 * @author Thomas Bopp (astra@upb.de) 
 */
string get_role(int|object access)
{
    if ( objectp(access) )
	access = LAST->obj->query_sanction(access);
    
    if ( (access & SANCTION_ALL)==SANCTION_ALL ) 
	return "admin";
    else if ( access & SANCTION_READ && access & SANCTION_WRITE ) 
	return "author";
    else if ( (access & SANCTION_READ) && (access & SANCTION_ANNOTATE) )
        return "reviewer";
    else if ( access & (SANCTION_READ) ) 
	return "reader";
    return "nothing";
}

/**
 * Check the access of an object for a given access bit.
 *  
 * @param object obj - the object to check access.
 * @param object caller - the calling object.
 * @param int accBit - the access Bit to test.
 * @return true or false.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool check_access(object obj, object caller, int accBit)
{
    return _SECURITY->check_user_access(obj, caller, accBit, accBit, false);
}

/**
 * Get the time string for a given timestamp 't'.
 *  
 * @param int tt - timestamp to get a string description for.
 * @return string description of timestamp in "month date year/time".
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string get_time(int tt)
{
    int t = 0;
    if ( intp(tt) ) t = tt;
    string ti = ctime(t);
    string  month, year;
    string date, hour, minute;
   
    if (sscanf(ti,"%*s %s %s %s:%s:%*d %s\n",month,date,hour,minute,year) != 5)
	sscanf(ti,"%*s %s  %s %s:%s:%*d %s\n", month,date,hour,minute,year);
    string gettime = month + "/"+ date + "/" + (year[2..3]) + "/" + hour +
	":" + minute;
    return "<date>"+gettime+"</date><time>"+t+"</time>";
}

/**
 * Get the standard ctime output format. <date>ctime(t)</date><time>t</time>.
 *  
 * @param int t - the timestamp (unix)
 */
string get_ctime(int tt)
{
    int t = 0;
    if ( intp(tt) ) t = tt;
    return "<date>"+ctime(t)+"</date><time>"+t+"</time>";
}

/**
 * Get the content of an object.
 *  
 * @param object obj - the object to get the content for.
 * @return the content of the object.
 */
string
get_obj_content(object obj)
{
    if ( !objectp(obj) )
	return "";
    if ( search(obj->query_attribute(DOC_MIME_TYPE), "txt") >= 0 ||
	 search(obj->query_attribute(DOC_MIME_TYPE), "text") >= 0 ) 
    {
	string content = obj->get_content();
	if ( obj->query_attribute(DOC_MIME_TYPE) == "text/plain" )
	    content = text_to_html(content);
	if ( !stringp(content) )
	    content = "";

	return "<![CDATA["+string_to_utf8(content)+"]]>";
    }
    return "";
}

string get_obj_content_detect(object obj)
{
  if ( !objectp(obj) )
    return "";
  if ( search(obj->query_attribute(DOC_MIME_TYPE), "txt") >= 0 ||
       search(obj->query_attribute(DOC_MIME_TYPE), "text") >= 0 ) 
  {
    string content = obj->get_content();
    string encoding = obj->query_attribute(DOC_ENCODING);
    if ( !stringp(encoding) && 
	 search(obj->query_attribute(DOC_MIME_TYPE), "html") >= 0 )
      encoding = detect_encoding(content);

    if ( !stringp(content) )
	content = "";

    if ( encoding != "utf-8" )
      return "<![CDATA["+string_to_utf8(content)+"]]>";
    else
      return "<![CDATA["+content+"]]>";
  }
  return "";
}

string
get_obj_content_raw(object obj)
{
    if ( !objectp(obj) )
	return "";
    if ( search(obj->query_attribute(DOC_MIME_TYPE), "txt") >= 0 ||
	 search(obj->query_attribute(DOC_MIME_TYPE), "text") >= 0 ) 
    {
	string content = obj->get_content();
	if ( !stringp(content) )
	    content = "";
	if ( obj->query_attribute(DOC_MIME_TYPE) == "text/plain" )
	    content = text_to_html(content);
	
	if ( obj->query_attribute(DOC_ENCODING) == "iso-8859-1" )
	    content = string_to_utf8(content);
	if ( !xml.utf8_check(content) )
	    content = string_to_utf8(content);

	return "<![CDATA["+content+"]]>";
    }
    return "";
}

class xsltTag {
    object get_object(string o) {
	if ( (int)o > 0 )
	    return find_object((int)o);
	else
	    return find_object(o);
    }

    string execute(mapping vars) {
	object obj;
	object xsl;
	
	obj = get_object(vars->args->object);
	if ( !objectp(obj) )
	    return "<!-- xslt: no object found ("+vars->args->object+")-->";
	xsl = get_object(vars->args->xsl);
	if ( !objectp(xsl) )
	    return "<!-- xslt: no xsl Stylesheet found ("+
		vars->args->xsl+")-->";
	return run_xml(obj, xsl, vars);
    }

    int get_object_class() { return 0; }
}

/**
 * Get the content of a given object and parse all rxml tag
 * inside the well formed html or text content.
 *  
 * @param object obj - the object to get the content for.
 * @return the resulting code
 */
string get_obj_content_rxml(object obj)
{
    if ( !objectp(obj) )
        return "";

    return "<!-- this function is no longer available !-->";

    if ( search(obj->query_attribute(DOC_MIME_TYPE), "txt") >= 0 ||
	 search(obj->query_attribute(DOC_MIME_TYPE), "text") >= 0 ) 
    {
      string content = obj->get_content();
      mapping tags = ([ "xslt": xsltTag()->execute, ]);
      string result;
      mixed err = catch {
	result = htmllib.parse_rxml(string_to_utf8(content), 
				    XSL->vars, tags, "utf-8");
      };
      if ( err != 0 ) {
	werror("Got error upon get_obj_content_rxml:\n%O", err);
	result = err[0];
      }
      return "<![CDATA["+result+"]]>";
    }
    steam_error("Cannot parse rxml in non-text content !");
}


/**
 * Describe the params of an attribute. The function gets the attribute
 * registration array which is available from the factory.
 *  
 * @param array reg - the registered attribute data.
 * @return string description of the registered type.
 * @author Thomas Bopp (astra@upb.de) 
 */
string describe_params(mixed reg)
{
    int type = reg[REGISTERED_TYPE];
    
    if ( type == CMD_TYPE_ARRAY )
	return "array";
    else if ( type == CMD_TYPE_FLOAT )
	return "float";
    else if ( type == CMD_TYPE_MAPPING )
        return "mapping";
    else if ( type == CMD_TYPE_STRING )
        return "string";
    else if ( type == CMD_TYPE_TIME )
       return "time";
    else if ( type == CMD_TYPE_INT )
        return "int";
    else if ( type == CMD_TYPE_OBJECT )
	return "object";
    return "mixed";
}

array 
_get_annotations_thread(object obj, object user , int d, int|void active_flag)
{
    string xml;
    int   read;
    
    if ( !active_flag )
	active_flag = activeThreadMap[obj];

    read =(search(
	_Server->get_module("table:read-documents")->get_readers(obj),
	user) >= 0 );
    xml = "<thread>\n"+
	"<depth>"+d+"</depth>\n"+
	"<subject><![CDATA["+obj->query_attribute(OBJ_DESC_OR_NAME) +"]]></subject>"+
	"<accessed>"+obj->query_attribute(DOC_TIMES_READ)+"</accessed>\n"+
	"<id>"+obj->get_object_id() + "</id>\n"+
	"<created>"+get_time(obj->query_attribute(OBJ_CREATION_TIME))+"</created>\n"+
	"<modified>"+get_time(obj->query_attribute(DOC_LAST_MODIFIED))+"</modified>\n"+
	"<active-thread>"+active_flag+"</active-thread>\n"+
	"<read>"+read+"</read>\n"+
	"<author>"+compose_scalar(obj->get_creator())+"</author>\n";
    
    array(object) annotations = obj->get_annotations_for(user);
    if ( arrayp(annotations) ) {
	foreach(annotations, object ann) {
	    if ( !objectp(ann) ) continue;
	    array res;
	    res = _get_annotations_thread(ann, user, d+1, active_flag);
	    xml += res[0];
	    read = (read || res[1]);
	}
    }
    xml += "<read_thread>"+read+"</read_thread>\n";
    xml += "</thread>\n";
    return ({ xml, read });
}

/**
 * Convert an annotation thread into xml. This function is called
 * recursively. Dont call this function directly, use show_annotations
 * instead.
 *  
 * @param object obj - the current annotation object.
 * @param object user - the user reading the annotations.
 * @param int d - the current depth in the thread.
 * @return xml string representation of an annotation thread.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see show_annotations
 */
string 
get_annotations_thread(object obj, object user, int d, int|void active_flag)
{
    return _get_annotations_thread(obj, user, d, active_flag)[0];
}

/**
 * Recursively insert annotations in the annotation array. This just
 * builds an array which is used by show_annotations. The user object
 * parameter is used for calling the get_annotations_for() function.
 *  
 * @param object ann - the current annotation
 * @param object user - the user reading the anntotations.
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see show_annotations
 */
array(object) insert_annotations(object ann, object user)
{
    array(object) annotations = ann->get_annotations_for(user);
    if ( arrayp(annotations) ) {
	foreach ( annotations, object a) {
	    annotations += insert_annotations(a, user);
	}
    }
    else {
	return ({ });
    }
    return annotations;
}

/**
 * Bring the given array of annotation objects to XML.
 *  
 * @param array(object) annotations - array of annotation documents.
 * @return xml presentation of the annotations and their sub-annotations.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see insert_annotations
 * @see get_annotations_thread
 */
string show_annotations(array(object) annotations)
{
    string xml = "";
    for ( int i = 0; i < sizeof(annotations); i++ ) {
	if ( !objectp(annotations[i]) ) continue;
	xml += get_annotations_thread(annotations[i], this_user(), 0);
    }
    foreach ( annotations, object ann ) {
	annotations += insert_annotations(ann, this_user());
    }
    foreach(annotations, object annotation) {
	xml += serialize_xml_object(
	    annotation, annotationXML, true);
    }
    return xml;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
string do_show_attribute(object obj, mixed key, mixed val, mixed attrReg)
{
    return 
	"\t\t\t<locked>"+(obj->is_locked(key) ? "true":"false")+"</locked>\n"+
	"\t\t\t<type>"+describe_params(attrReg)+"</type>\n"+
	"\t\t\t<key>"+compose(key) + "</key>\n"+
	"\t\t\t<acquire>"+describe_acquire(val[1])+ "</acquire>\n"+
        "\t\t\t<description>"+attrReg[REGISTERED_DESC]+"</description>\n"+
	"\t\t\t<data>"+compose(val[0])+"</data>\n";
}

/**
 * Show the registered data of an attribute and its value. This is
 * used by attributes.xsl.
 *  
 * @param KEYVALUE k - key/value pair from a mapping.
 * @return xml presentation of the attribute data.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_attribute(KEYVALUE k)
{
    object obj = THIS->this();
    mixed key = k->key;
    mixed attrReg = k->val;
    mixed val= ({ obj->query_attribute(key), obj->get_acquire_attribute(key) });
    return do_show_attribute(obj, key, val, attrReg);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
string show_attribute_reg(KEYVALUE k)
{
    object obj = THIS->this();
    mixed key = k->key;
    mixed attrReg = k->val;
    mixed val= obj->get_attribute_default(key);
    return do_show_attribute(obj, key, val, attrReg);
}

/**
 * Show how many objects a user carries.
 *  
 * @return the size of the current user selection.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_carry()
{
    return (string)sizeof(selection);
}

/**
 * Get the objects this() pointer, or 0 if its an invalid object.
 * This checks if there is a valid proxy.
 *  
 * @param object o - the object.
 * @return the proxy of the object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
object get_local_object(object o)
{
    if ( objectp(o) && objectp(o->this()) )
	return o->this();
    return 0;
}

/**
 * Describe a sanction bit array as a number of 'permission' tags.
 *  
 * @param int saction - the permission bit array.
 * @return xml presentation of access permissions.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_access(int sanction)
{
    string xml = "";

    int sz = sizeof(__sanction);
    for ( int i = 0; i < sz; i++ ) {
	if ( __sanction[i] == "free" ) continue;
	
	if ( sanction & ((1<<i)<<16) )
	    xml += "\t\t\t<permission type=\""+__sanction[i]+
		"\">2</permission>\n";
	else if ( sanction & (1<<i) )
	    xml += "\t\t\t<permission type=\""+__sanction[i]+
		"\">1</permission>\n";
	else
	    xml += "\t\t\t<permission type=\""+__sanction[i]+
		"\">0</permission>\n";
    }
    return xml;
}

/**
 * Get basic access permissions for an object. Checks whether the
 * user can read,write,execute and annotate the object and if the
 * steam-group is able to read. Finally its checked if also everyone
 * can read the object.
 *  
 * @param objcet obj - the object to check.
 * @return the xml access string.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string get_basic_access(object obj)
{
    string xml;

    int access  = _SECURITY->get_user_permissions(obj, this_user(), SANCTION_READ|SANCTION_WRITE|SANCTION_EXECUTE|SANCTION_ANNOTATE|SANCTION_INSERT);
    int gaccess = _SECURITY->get_user_permissions(obj, _WORLDUSER, SANCTION_READ|SANCTION_WRITE|SANCTION_EXECUTE|SANCTION_ANNOTATE|SANCTION_INSERT);
    int saccess = _SECURITY->get_user_permissions(obj, _STEAMUSER, SANCTION_READ);
    if ( obj == this_user() )
	access = saccess = SANCTION_ALL;
    
    xml = "";
    if ( gaccess & SANCTION_READ )
	xml += "<readable guest=\"true\" user=\"true\" steam=\"true\"/>";
    else
	xml += "\t<readable guest=\"false\" user=\""+
	    ((access & SANCTION_READ) ?   "true":"false") + "\" steam=\""+
	    ((saccess&SANCTION_READ)  ?   "true":"false") + "\" />\n";
    if ( gaccess & SANCTION_WRITE )
	xml += "<writeable guest=\"true\" user=\"true\" steam=\"true\"/>";
    else
	xml += "\t<writeable guest=\"false\" user=\""+
	    ((access&SANCTION_WRITE)  ?   "true":"false") + "\"/>\n";

    if ( gaccess & SANCTION_EXECUTE )
	xml += "<executeable guest=\"true\" user=\"true\" steam=\"true\"/>";
    else
	xml += "\t<executeable guest=\"false\" user=\""+
	    ((access&SANCTION_EXECUTE)?   "true":"false") + "\"/>\n";
    if ( gaccess & SANCTION_ANNOTATE )
	xml += "<annotateable guest=\"true\" user=\"true\" steam=\"true\"/>";
    else
	xml += "\t<annotateable guest=\"false\" user=\""+
	    ((access&SANCTION_ANNOTATE) ? "true":"false") + "\"/>\n";
    if ( gaccess & SANCTION_INSERT )
	xml += "<insertable guest=\"true\" user=\"true\" steam=\"true\"/>";
    else
	xml += "\t<insertable guest=\"false\" user=\""+
	    ((access&SANCTION_INSERT) ? "true":"false") + "\"/>\n";
    return xml;
}

/**
 * Describe the acquired access of an object.
 *  
 * @param object obj - the object to describe its acquiring.
 * @return xml string about acquired access permission.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string get_acquired_access(object obj)
{
    string   xml = "";
    mapping mSanction;
    int            sz;

    //DEBUG_XML("get_acquired_access("+obj->get_identifier()+")");
    object|function acquire = obj->get_acquire();
    
    if ( functionp(acquire) )
	acquire = acquire();

    while ( acquire != 0  ) {
	mSanction = acquire->get_sanction();
	foreach(indices(mSanction), object sanctioned) {
	    if ( !objectp(sanctioned) ) continue;
	    xml += "\t\t\t<Object "+
		"type="+class_id_to_name(sanctioned->get_object_class())+
		">\n";
	    xml += "\t\t\t\t<from>"+compose(acquire)+"</from>\n";
	    xml += "\t\t\t\t<id>"+sanctioned->get_object_id() + "</id>\n"+
		"\t\t\t\t<name>"+sanctioned->get_identifier()+"</name>\n";
	    sz = sizeof(__sanction);
	    for ( int i = 0; i < sz; i++ ) {
		if ( __sanction[i] == "free" ) continue;
		
		if ( mSanction[sanctioned] & ((1<<i)<<16) )
		    xml += "\t\t\t\t\t<permission type=\""+__sanction[i]+
			"\">2</permission>\n";
		else if ( mSanction[sanctioned] & (1<<i) )
		    xml += "\t\t\t\t<permission type=\""+__sanction[i]+
			"\">1</permission>\n";
		else
		    xml += "\t\t\t\t<permission type=\""+__sanction[i]+
			"\">0</permission>\n";
	    }
	    xml +="\t\t\t</Object>\n";
	}
	acquire = acquire->get_acquire();
	if ( functionp(acquire) ) 
	    acquire = acquire();
    }
    return xml;
}

/**
 * Describe the acquire situation of an object.
 *  
 * @param function|object acquire the acquire setting
 * @return xml description of the given function or object.
 * @author Thomas Bopp (astra@upb.de) 
 */
string describe_acquire(function|object|int acquire)
{
    if ( functionp(acquire) && acquire == THIS->obj->get_environment ) 
    {
	acquire = acquire();
	if ( objectp(acquire) ) 
	    return "<function><name>get_environment</name><id>"+
		acquire->get_object_id()+ "</id></function>\n";
    }
    else if ( intp(acquire) && acquire == REG_ACQ_ENVIRONMENT )
	return "<function><name>get_environment</name></function>";
    else if ( objectp(acquire) )
	return compose_scalar(acquire);
    return "<object><name/><id>0</id></object>";
}

/**
 * Serialize an XML tag with serialization data 'data'.
 *  
 * @param string tag - the name of the tag to serialize.
 * @param array data - the data for the tag.
 * @return tag and data in XML.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string serialize_xml_tag(string tag, array data)
{
    function   f;
    object     o;
    mixed      v;
    array params;
    
    DEBUG_XML("<"+tag+">");

    string xml = "<"+tag+">";

    if ( !arrayp(data) )
      return xml + "</"+tag+">";

    if ( functionp(data[ID_FUNC]) ) {
	f = data[ID_FUNC];
    }
    else {
	o = get_local_object(data[ID_OBJECT]);
	if ( objectp(o) )
	    f = o->find_function(data[ID_FUNC]);
    }

    params = ({ });
    for ( int i = 0; i < sizeof(data[ID_PARAMS]); i++ ) {
	if ( objectp(data[ID_PARAMS][i]) ) 
	    params += ({ data[ID_PARAMS][i]->this() });
	else
	    params += ({ data[ID_PARAMS][i] });
    }	    

    mixed err;

    if ( functionp(f) ) {
	err = catch {
	    v = f(@params);
	};
	if ( err != 0 ) {
	  xml += "<!-- While serializing XML: " +err[0] + "-->\n";
	}
    }
    else
	v = -1;

    if ( functionp(data[ID_CONV]) ) {
	err = catch {
	    xml += data[ID_CONV](v);
	};
        if ( err != 0 ) {
	    FATAL("While serializing XML:\n"+err[0]+
		sprintf("%O", err[1]));
	}
    }
    else if ( mappingp(data[ID_CONV]) ) 
    {
	if ( arrayp(v) ) {
	    foreach( v, object obj) {
		if ( data[ID_CONV]->name == "none" )
		    xml += serialize_xml_object(obj, data[ID_CONV], false);
		else
		    xml += serialize_xml_object(obj, data[ID_CONV], true);
	    }
	}
	else if ( mappingp(v) ) {
	    foreach( indices(v), mixed ind ) {
		ENTRY->key = ind;
		ENTRY->val = v[ind];
		if ( objectp(ind) && intp(data[ID_CONV][0]) ) {
		  LAST->obj = THIS->obj;
		  if ( data[ID_CONV]->name == "none" )
		    xml += serialize_xml_object(ind, data[ID_CONV], false);
		  else
		    xml += serialize_xml_object(ind, data[ID_CONV], true);
		  
		}
		else {
		    foreach(indices(data[ID_CONV]), mixed idx) {
			xml += serialize_xml_tag(idx, data[ID_CONV][idx]);
		    }
		}
	    }
	}
	else if ( objectp(v) ) {
	    LAST->obj = THIS->obj;
	    xml += serialize_xml_object(v, data[ID_CONV], false);
	}
    }
    else if ( objectp(v) ) {
	xml += compose(v);
    }
    else if ( stringp(v) || intp(v) )
	xml += v;
    
    xml += "</"+tag+">\n";
    DEBUG_XML("</"+tag+">");
    return xml;
    
}

/**
 * Serialize an object to XML using the xml description mapping 'mXML'.
 * The mapping defines what the xml code for the object should look like.
 *  
 * @param object obj - the object to serialize.
 * @param mapping mXML - xml description mapping.
 * @return xml code for object 'obj'.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see serialize_xml_tag
 */
string 
serialize_xml_object(object obj, mapping mXML, bool|void obj_tag )
{
    object xml = String.Buffer();
    
    if ( !objectp(obj) )
	return "<!-- Null Object cannot be serialized -->";
    
    if ( !mappingp(mXML) )
	return "";

    if (obj->status()<PSTAT_DISK) // broken instance already loaded
        return "<!-- Unable to load broken instance from DB -->";

    if (!functionp(obj->this))    // broken instance on first load
        return "";

    THIS->obj = obj->this();
    ENV->obj  = obj->get_environment();
    
    DEBUG_XML("serialize_xml_object(THIS="+THIS->obj->get_identifier()+",LAST="+
		(objectp(LAST->obj) ? LAST->obj->get_identifier():"NULL")+")");

    string tagname = mXML->name;
    if ( !stringp(tagname) ) 
	tagname = "Object";
    if ( obj_tag )
	xml->add("<"+tagname+" type="+
		 class_id_to_name(obj->get_object_class())+
		 (mSelection[obj] ? 
		  " selected=\"true\"":" selected=\"false\"")+
		 ">");

    for ( int i = 31; i >= 0; i-- ) {
	int idx = (1<<i);
	if ( (idx & obj->get_object_class()) && mappingp(mXML[idx]) ) 
	{
	    foreach(indices(mXML[idx]), string tag) {
		THIS->obj = obj->this();
		xml->add(serialize_xml_tag(tag, mXML[idx][tag]));
	    }
	}
    }
    if ( obj_tag ) 
	xml->add("</"+tagname+">\n");
    return xml->get();
}

/**
 * Show the content description of an object 'p'. For Documents it
 * will list the size and the mime-type. For Containers it lists the
 * html:index atribute for the containers index file.
 *  
 * @param object p - the content object
 * @return content description for the object.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string show_content(object p)
{
    if ( p->get_object_class() & CLASS_DOCUMENT )
	return "<size>"+p->get_content_size()+"</size>"+
	    "<mime-type>"+p->query_attribute(DOC_MIME_TYPE) + "</mime-type>";
    if ( p->get_object_class() & CLASS_CONTAINER ) 
	return "<index>"+p->query_attribute("html:index") + "</index>";
    return "";
}


/**
 * show a simple mapping in compact form
 * each key is a tag, and the value its content
 *  
 * @param mapping of strings
 * @return xml form of the mapping
 * @author Martin Bähr
 */
string show_mapping(mapping(string:string) data)
{
  string xml="";
  if(mappingp(data))
    foreach(data; string key; string value)
      foreach(value/"\0";; string part)
        xml += sprintf("<%s><![CDATA[%s]]></%s>\n", key, part, key);
  return xml;
}

/**
 * Get a path as a series of object tags in XML.
 *  
 * @param object p - the object to get the path for.
 * @return xml path description for the object.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string get_path(object p)
{
    object xml = String.Buffer();
    
    array(object|string) paths = ({ });
    string path = "";
    string s;
    while ( p != null ) {
	if ( stringp(s=_FILEPATH->check_tilde(p)) ) {
	    paths = ({ p, s }) + paths;
	    p = null;
	}
	else {
	    paths = ({ p, p->get_identifier() }) + paths;
	    p = p->get_environment();
	}
    }
    for ( int i = 0; i < sizeof(paths)-2; i+=2 ) {
	xml->add("<object><id>");
	xml->add((string)paths[i]->get_object_id());
	xml->add("</id><name><![CDATA[");
	xml->add(paths[i+1]);
	xml->add("]]></name>");
	path += paths[i+1] + "/";
	xml->add("<path>"+no_uml(path)+"</path></object>");
    }
    if ( paths[-2]->get_object_class() & CLASS_CONTAINER )
	path += paths[-1] + "/";
    else
	path += paths[-1];

    xml += "<path>"+no_uml(path)+"</path>\n";
    return xml->get();
}

/**
 * Get a path as a series of object tags in XML.
 *
 * XML Description of returned value
 * <!Element path (object*)>               <!-- sequence of objects in path -->
 * <!Element object (name, description, relpath)>      <!-- data per object -->
 * <!Element name (#cdata)>                         <!-- attribute OBJ_NAME -->
 * <!Element description (#cdata)>                  <!-- attribute OBJ_DESC -->
 * <!Element relpath (#cdata)>               <!-- relative path to object p -->
 *
 * @param object p - the object to get the path for.
 * @return xml path description for the object.
 * @author <a href="mailto:balduin@upb.de">Ludger Merkens</a>)
 */
string get_rel_path(object p, void|int fsname)
{
    object xml = String.Buffer();

    array(object|string) paths = ({ });
    string path = "";
    string s;
    while ( p != null ) {
        if ( stringp(s=_FILEPATH->check_tilde(p)) ) {
            paths = ({ p, s }) + paths;
            p = null;
        }
        else {
            paths = ({ p,
                       (fsname ?
                        p->query_attribute("fs_name") : p->get_identifier())
            }) + paths;
            p = p->get_environment();
        }
    }
    for ( int i = 0; i < sizeof(paths)-2; i+=2 ) {
        xml->add("<object><id>");
        xml->add((string)paths[i]->get_object_id());
        xml->add("</id><name><![CDATA[");
        xml->add(paths[i+1]);
        xml->add("]]></name><description><![CDATA[");
        xml->add(paths[i]->query_attribute(OBJ_DESC));
        xml->add("]]></description><relpath>");
        xml->add("../"*((sizeof(paths)-i)/2)+paths[i+1]);
        xml->add("</relpath></object>");
        path += paths[i+1] + "/";
    }
    if ( paths[-2]->get_object_class() & CLASS_CONTAINER )
        path += paths[-1] + "/";
    else
        path += paths[-1];

    xml += "<path>"+no_uml(path)+"</path>\n";
    return xml->get();
}

/**
 * Get the neighbours of an object.
 * This function returns a XML part containing the left and right neighbours of
 * the object. The optional argument filterclass allows to find the neighbours
 * of the same objectclass only. (previous/next image, container)
 *
 * XML Description of returned value
 * <!Element left (object*)>                  <!-- left neighbour -->
 * <!Element right (object*)>                 <!-- right neighbour -->
 * <!Element object (id, name, description)>  <!-- information per object -->
 * <!Element id (#cdata)>                     <!-- decimal object id -->
 * <!Element name (#cdata)>                   <!-- attribute OBJ_NAME -->
 * <!Element description (#cdata)>            <!-- attribute OBJ_DESC -->
 *
 * @param object o - The object to calculate the neighbours for.
 * @param void|int filterclass - (bool)
 * @caveats This function doesn't regard the currently active sorting option of
 *          the user but uses unsorted inventory always.
 *
 * @author <a href="mailto:balduin@upb.de">Ludger Merkens</a>)
 */
string get_neighbours(object p, void|int filterclass, void|int fsname)
{
    DEBUG_XML(sprintf("get_neighbours %O, %d\n", p, filterclass));
    object env = p->get_environment();
    array(object) inv;
    if (!filterclass)
        inv = env->get_inventory();
    else
    {
        inv = env->get_inventory_by_class(p->get_object_class());
        DEBUG_XML(sprintf("inv is %O\n", inv));
    }
    int i = search(inv, p);
    object xml = String.Buffer();

    object left, right;
    if (i>0) left = inv[i-1];
    if ((i!=-1) && (i<sizeof(inv)-1)) right = inv[i+1];

    xml->add("<left>");
    if (objectp(left))
    {
        xml->add("<object><id>");
        xml->add((string)left->get_object_id());
        xml->add("</id><name><![CDATA[");
        xml->add((string)left->get_identifier());
        xml->add("]]></name>");
        if (fsname)
        {
            xml->add("<fsname>");
            xml->add((string)left->query_attribute("fs_name"));
            xml->add("</fsname>");
        }
        xml->add("<description><![CDATA[");
        xml->add(left->query_attribute(OBJ_DESC));
        xml->add("]]></description></object>");
    }
    xml->add("</left><right>");
    if (objectp(right))
    {
        xml->add("<object><id>");
        xml->add((string)right->get_object_id());
        xml->add("</id><name><![CDATA[");
        xml->add((string)right->get_identifier());
        xml->add("]]></name>");
        if (fsname)
        {
            xml->add("<fsname>");
            xml->add((string)right->query_attribute("fs_name"));
            xml->add("</fsname>");
        }
        xml->add("<description><![CDATA[");
        xml->add(right->query_attribute(OBJ_DESC));
        xml->add("]]></description></object>");
    }
    xml->add("</right>");

    return xml->get();
}

private
void xml_describe(object node, int selected, int depth, string url,
                  String.Buffer xml)
{
    string fsname;
    object o = node->get_object();
    function qa = o->query_attribute;
    
    xml->add("<id>");
    xml->add((string)o->get_object_id());
    xml->add("</id>\n<name><![CDATA[");
    xml->add((string)o->get_identifier());
    xml->add("]]></name>\n");
    if (fsname = qa("fs_name"))
    {
        xml->add("<fsname>");
        xml->add(fsname);
        xml->add("</fsname>\n");
    }
    xml->add("<description><![CDATA[");
    xml->add(qa(OBJ_DESC));
    xml->add("]]></description>\n<selected>");
    if (selected)
        xml->add("yes");
    else
        xml->add("no");
    xml->add("</selected>\n<depth>");
    xml->add((string)depth);
    xml->add("</depth>\n<url><![CDATA[");
    xml->add(url+"/");
    xml->add("]]></url>\n");
}

private
void xml_recurse(object root, int depth, int level, string url, int filter,
                 String.Buffer xml)
{
    xml->add("<object>\n");
    xml_describe(root, 0, level, url, xml);
    array(object) inv = root->get_inventory_by_class(filter);
    foreach(inv, object node)
    {
        if (depth==0) {
            xml->add("<object>\n");
            xml_describe(node, 0, level,
                         url + "/" + root->query_attribute(OBJ_NAME),
                         xml);
            xml->add("</object>\n");
        }
        else
            xml_recurse(node, depth-1, level+1,
                        url + "/" + root->query_attribute(OBJ_NAME),
                        filter, xml);
    }
    xml->add("</object>\n");
}

private
void xml_subtree(array(object) path, String.Buffer xml,
                 int depth, int level, string url, int filter)
{
    object root = path[0];
    path = path[1..];

    xml->add("<object>\n");
    xml_describe(root, 1, level, url, xml);

    object nextnode = sizeof(path) ? path[0] : 0;
    array(object) inv = root->get_inventory_by_class(filter);
    foreach(inv, object node)
    {
        if (node == nextnode)
            xml_subtree(path, xml, depth-1, level+1,
                        url+"/"+node->query_attribute(OBJ_NAME), filter);
        else
            if (depth==0) {
                xml->add("<object>\n");
                xml_describe(node, 0, level+1,
                             url + "/" + node->query_attribute(OBJ_NAME),
                             xml);
                xml->add("</object>\n");
            }
            else
                xml_recurse(node, depth-1 , level+1,
                            url + "/" + node->query_attribute(OBJ_NAME),
                            filter, xml);
    }
    xml->add("</object>\n");
}

string get_rel_tree(object root, object leaf, int depth, int filter)
{
    array(object) path = ({ leaf });

    object node = leaf;
    while (node && node!=root)
    {
        node = node->get_environment();
        if (node)
            path = ({ node }) + path;
    }
    if (node != root)
        return "<relpath></relpath>";

    object xml = String.Buffer();
    xml_subtree(path, xml, depth, 0, "", filter);
    return xml->get();
}



/**
 * Get the public path of an object.
 * This calculation uses the public "url" of its closest published parent and
 * combines this with the relative path from this object to its published parent.
 *
 * @param object o - The object to get the path for.
 * @return  (string) The public path of the object
 * @author <a href="mailto:balduin@upb.de">Ludger Merkens</a>)
 */
string get_public_name(object o)
{
    string sPublicRoot;
    string sPublicPath;
    object x = o;

    sPublicPath = o->get_identifier();
    while ((x=x->get_environment()) && !(sPublicRoot = x->query_attribute("url")))
    {
        if (objectp(x))
            sPublicPath = x->get_identifier() + "/" + sPublicPath;
    }

    if (sPublicRoot)
        return combine_path(sPublicRoot, sPublicPath);

    return 0;
}


/**
 * Get the XML representation of this object. To speed up things, the
 * type selects which part of the data should be xmlified.
 *  
 * @param obj - the object to convert
 * @param type - the type of the object
 * @return the xml data
 * @author Thomas Bopp (astra@upb.de) 
 */
string get_xml(object obj, object xsl, void|mapping vars, mixed|void active)
{
    object    xml = String.Buffer(32468);
    int                                i;
    object                          user;
    mixed                            err;


    if ( mappingp(vars) && vars->this_user > 0 )
      user = find_object(vars->this_user);
    else 
      user = this_user();

    if ( !objectp(user) )
      user = CALLER;

    object pike = xsl->query_attribute(DOC_XSL_PIKE);
    if ( objectp(xsl) && objectp(pike) ) {
	string res;
        array pikeErr = pike->get_errors();
        if ( arrayp(pikeErr) && sizeof(pikeErr) > 0 )
          throw( ({pikeErr*"\n", backtrace()}));
	object inst = pike->get_instance();
	if ( objectp(inst) ) {
	    err = catch(res=inst->xmlify(obj, vars));
            if ( err ) {
	      mixed errerr = catch {
		array lines = pike->get_content() / "\n";
		int line;
		string func;
		string outp = sprintf("\n%O", err[1][-1]);
		sscanf(outp, "%*s.pike:%d, %s,%*s", line, func);
		int fromline = max(0, line-20);
		int toline = min(line+20, sizeof(lines)-1);
		for (i=fromline; i<toline;i++)
		  err[0] += sprintf("%d: %s\n", i, lines[i]);
	      };
	      if ( errerr ) {
		FATAL("Error modifying error in xml_converter.pike: %O",
		      errerr);
	      }

	      throw(err);
	    }
	    return res;
	}
    }
   

    selection = user->query_attribute(USER_SELECTION);
    if ( !arrayp(selection) ) 
	selection = ({ });
    mSelection = mkmapping(selection, selection);
 
   
   

    mapping mXML = 
	([ CLASS_OBJECT: 
	 ([
	     "path":      ({ CONV, "get_path",      ({ THIS }), 0 }),
	     "user":      ({ 0,    this_user,       ({      }), userXML }),
	     ])+objXML[CLASS_OBJECT],
	 CLASS_CONTAINER: 
	 ([
	     "inventory": ({ THIS, "get_inventory", ({      }),
				objXML+exitXML+linkXML+userXML+containerXML}),
	     ]),
	 ]);
    
    if ( objectp(xsl) && mappingp(xsl->get_xml_structure()) ) {
	mXML = xsl->get_xml_structure();
	if ( equal(mXML, ([ ])) ) {
	    xsl->load_xml_structure();
	    mXML = xsl->get_xml_structure();
	}
    }
    if ( equal(mXML, ([ ])) ) 
	THROW("No XML Description found for Stylesheet !", E_ERROR);
    
    THIS_USER->obj = user;
    CONV->obj = this();
    LAST->obj = obj;
    XSL->obj = xsl;

    if (!mappingp(vars))
        vars = ([]);
    XSL->vars = vars;

    
    foreach(indices(params), string p) {
	if ( vars[p] ) {
	    int d;
	    sscanf(vars[p], "%d", d);
	    if ( (string)d == vars[p] ) {
	      if ( objectp(params[p]->val) )
		params[p]->val = find_object(d);
	      else
		params[p]->val = d;
	    }
	    else
		params[p]->val = vars[p];
	}
	else
	    params[p]->val = params[p]->def;
    }
	

    if ( intp(active) && active > 0 ) {
	ACTIVE->obj = find_object(active);
    }
    else {
	if ( vars->type == "annotations" ||
	    obj->get_object_class() & CLASS_MESSAGEBOARD )
	{
	    object from_obj = get_var("from_obj", 1);
	    array annotations = obj->get_annotations_for(
		this_user(),
		(int)get_var("from_obj", 1)->val,
		(int)get_var("to_obj", 20)->val);
	    if ( sizeof(annotations) > 0 )
		ACTIVE->obj = annotations[0];
	}
	    
    }
    if ( objectp(ACTIVE->obj) ) {
	activeThreadMap = ([ ACTIVE->obj: 1, ]);
	object ann = ACTIVE->obj->get_annotating();
	while ( objectp(ann) ) {
	    activeThreadMap[ann] = 1;
	    ann = ann->get_annotating();
	}
    }

    DEBUG_XML("XML:Convertor - Using\n"+sprintf("%O", mXML));
    
    xml->add(  "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    xml->add(  serialize_xml_object(obj, mXML, true) );

    string result = xml->get();
    return result;
}

bool check_swap() { return false; }
string get_identifier() { return "Converter:XML"; }
function find_function(string f) { return this_object()[f]; }

object get_var(string name, mixed val)
{
    object param = params[name];
    if ( !objectp(param) ) {
	param = Param();
	int v;
	if ( !stringp(val) ) {
	  param->val = val;
	  param->def = val;
	}
	else {
	  sscanf(val, "%d", v);
	  if ( (string)v == val ) {
	    param->val = v;
	    param->def = v;
	  }
	  else {
	    param->val = val;
	    param->def = val;
	  }
	}
	param->name = name;
	params[name] = param;
    }
    return param;
}

mixed test()
{
    // try images folder...
    object images = find_object("/images");
    if ( !objectp(images) )
	return 0;

    array inv;
    if (sizeof(images->get_inventory()) < 15) {
      error(sprintf("/images Container not filled correctly:\n%O", 
		    images->get_inventory()));
    }
    inv = get_cont_inventory(images, 1, 15);
    if ( sizeof(inv) != 15 ) // no rooms in image container
      error("Test failed - from 1 to 15 are not 15 objects, but " + sizeof(inv));
    int containers = 1;
    foreach(inv, object obj) {
	if ( !(obj->get_object_class() & CLASS_CONTAINER) )
	    containers = 0;
	if ( !containers && obj->get_object_class() & CLASS_CONTAINER )
	    error("Containers not correctly sorted");
    } 
    
    object rxml = get_factory(CLASS_DOCUMENT)->execute(
	([ "name": "rxml.html", ]));
    rxml->set_content("<html><body><xslt object='/home/sTeam/bugs' "+
		      "xsl='/stylesheets/annotations.xsl'/></body></html>");
    XSL->vars = ([ "__internal": ([ ]), ]);
    return get_obj_content_rxml(rxml);
}


