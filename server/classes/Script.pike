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
 * $Id: Script.pike,v 1.2 2009/08/07 15:22:37 nicke Exp $
 */

constant cvs_version="$Id: Script.pike,v 1.2 2009/08/07 15:22:37 nicke Exp $";


//! the Script class is for web scripts with helper function to 
//! generate html.

inherit "/classes/Object";
inherit httplib;
inherit "/base/xml_parser";

#include <macros.h>
#include <database.h>
#include <exception.h>
#include <classes.h>
#include <attributes.h>
#include <types.h>

static void init_script() { }
static void create_script() { }

static mapping mLanguages = ([ ]);

static int __upgrading = 0;

/**
 * Initialization.
 */
static void init() 
{
    ::init();
    init_script();
}

static void load_object() 
{
    object lobj = do_query_attribute(SCRIPT_LANGUAGE_OBJ);
    if ( objectp(lobj) )
	init_languages(lobj);
}

string get_language_term(string term, string language)
{
    if ( mappingp(mLanguages) ) {
	if ( mappingp(mLanguages[language]) )
	    return mLanguages[language][term];
    }
    return "!! unknown internationalization for " + term;
}

void init_languages(object languageObj)
{
    set_attribute(SCRIPT_LANGUAGE_OBJ, languageObj);

    NodeXML n = parse_data(languageObj->get_content());
    array nodes = n->get_nodes("language");
    if ( arrayp(nodes) ) {
	foreach ( nodes, object node ) {
	    string lang = node->attributes->name;
	    if ( !stringp(lang) ) 
		steam_error("Uninitialized language in language document !");

	    mLanguages[lang] = ([ ]);
	    foreach( node->get_nodes("term"), object term ) {
		if ( !stringp(node->attributes->name) ) 
		    steam_error("Broken language file - missing name attribute on term.");
		mLanguages[lang][term->attributes->name] = term->get_data();
	    }
	}
    }
}

static void create_object()
{
    create_script();
}

static object find_document(string path)
{
    object env = get_environment();
    if ( !objectp(env) ) {
	env = do_query_attribute(OBJ_SCRIPT);
	if ( objectp(env) && !(env->get_object_class() & CLASS_CONTAINER) )
	    env = env->get_environment();
    }
    return _FILEPATH->resolve_path(env, path);
}

static string nav_link(object id, string name) {
    if ( !objectp(id) )
	return "";
    return "<a href=\"/scripts/navigate.pike?object="+id->get_object_id()+"\">"+name+"</a>";
}

/**
 *
 *  
 * @return 0 upon successfull checking or string (html code)
 */
static string check_variables(mapping req, mapping vars)
{
    foreach ( indices(req), string key ) {
	if ( !vars[key] ) 
	    THROW("The variable '"+key+"' was not found, but is "+
		  "required !", E_ERROR);
	switch(req[key]) {
	case CMD_TYPE_INT:
	    int v;
	    if ( sscanf(vars[key], "%d", v) == 0 )
		return error_page(
		    "The variable '"+key+"' needs an integer.. <br/>"+
		    sprintf("%O",vars[key]), 
		    "JavaScript:history.back();");
	    break;
	case CMD_TYPE_STRING:
	    if ( !stringp(vars[key]) )
		return error_page(
		    "The variable '"+key+"' needs a string.. <br/>"+
		    sprintf("%O",vars[key]), 
		    "JavaScript:history.back();");
	    break;
        default:
	break;
	}
    }
    return 0;
}

/**
 * Get the value for a variable set by the web-interface which is always
 * a string.
 *  
 * @param the original string value
 * @return integer or float or still a string
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
mixed
get_value(mixed v)
{
    mixed val;

    if ( v == 0 ) return 0;
    if ( intp(v) ) return v;
    
    val = v / "\0";
    if ( sizeof(val) > 1 )
	return val;

    if ( sscanf(v, "%d", val) == 1 && ((string)val) == v )
	return val;
    if ( sscanf(v, "%f", val) == 1 && search((string)val, v) == 0 )
	return val;
    return v;
}


/**
 * If multiple values are assigned to a single variable it is
 * converted to an array in this function.
 *  
 * @param v - the original string value
 * @return the resulting array
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_value
 */
array get_values(string v)
{
    array res = v / "\0";
    array result = ({ });

    foreach ( res, string str ) {
	if ( stringp(str) && strlen(str) > 0 )
	    result += ({ get_value(str) });
    }
    return result;
}

/**
 * Extract an array of objects from a given string value.
 * An object-array is provided by the web-interface as a string of
 * integers separated by \0
 *  
 * @param str - the source string
 * @return an array of objects
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_values
 */
static array(object) extract_objects(string str)
{
    array(object) result = ({ });
    
    if ( !stringp(str) )
	return result;

    array(string) res = str / "\0";
    foreach( res, string oid ) {
	object obj;
	obj = find_object((int)oid);
	if ( objectp(obj) )
	    result += ({ obj });
    }
    LOG("Result="+sprintf("%O\n",result));
    return result;
}

/**
 * Get an array of objects which are in the vars mapping passed to
 * steam by the web server. The mapping will contain an array of
 * object ids.
 *  
 * @param mapping vars - the parameter mapping.
 * @param string index - the index to lookup inthe mapping.
 * @return array of objects found in the mapping.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
array(object) get_objects(mapping vars, string index)
{
    array(object) result = ({ });
    
    array(string) res;
    if ( arrayp(vars[index]) )
	res = vars[index];
    else if ( !stringp(vars[index]) )
	return result;
    else
	res = vars[index] / "\0";

    foreach( res, string oid ) {
	object obj;
	obj = find_object((int)oid);
	if ( objectp(obj) )
	    result += ({ obj });
    }
    return result;
}

/**
 * Replace all variables in a html template.
 *  
 * @param string templ - the html template string
 * @param mapping vars - variables to exchange
 * @return the exchanged template
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string html_template(string|object templ, mapping vars)
{
    mapping templ_vars = ([ ]);

    if ( objectp(templ) ) {
      if ( !(templ->get_object_class() & CLASS_DOCUMENT) )
	THROW("Template object is not a document.", E_ERROR);

      templ = templ->get_content();
    }

    foreach(indices(vars), string key) {
	mixed val = vars[key];
	if ( stringp(val) )
	    templ_vars["{"+key+"}"] = val;
    }
    templ_vars["{SCRIPT}"] = "/scripts/execute.pike?script="+get_object_id();

    return replace(templ, indices(templ_vars), values(templ_vars));
}

/**
 * Create a new instance of a CLASS_
 *  
 * @param int cid - the class flag
 * @param mapping vars - vars mapping for the factory.
 * @return newly created object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object new_instance(int cid, mapping vars)
{
    object factory = _Server->get_factory(cid);
    object obj = factory->execute(vars);
    return obj;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
string html_template_block(string|object templ, string block, array bvars)
{
    mapping templ_vars = ([ ]);

    if ( objectp(templ) ) {
      if ( !(templ->get_object_class() & CLASS_DOCUMENT) )
	THROW("Template object is not a document.", E_ERROR);

      templ = templ->get_content();
    }

    int count = 0;
    templ = replace(templ, "<!-- END " + block + " -->",
		    "<!-- BEGIN " + block + " -->");
    array(string) blocks = templ / ("<!-- BEGIN " + block + " -->");
    string block_html = "";
    foreach ( bvars, mapping vars ) {
	templ_vars = ([ ]);
	foreach( indices(vars), string index )
	    templ_vars["{"+index+"}"] = (string)vars[index];
	block_html += replace(blocks[1], indices(templ_vars), values(templ_vars));
    }
    return blocks[0] + block_html + blocks[2];
}

/**
 * Create a selection field for an object. The parameter passed has to be a container
 * or a Group and will list the content as selections.
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
string make_selection(string name, object obj, object|void val, int|void classbit)
{
    string html = "<select name=\""+name+"\">\n";
    if ( classbit == 0 )
	classbit = CLASS_OBJECT;

    array(object) res = ({ });
    
    if ( obj->get_object_class() & CLASS_CONTAINER ) {
	foreach( obj->get_inventory(), object o )
	    if ( o->get_object_class() & classbit )
		res += ({ o });
    }
    else if ( obj->get_object_class() & CLASS_GROUP ) {
	foreach( obj->get_members(), object m )
	    if ( m->get_object_class() & classbit )
		res += ({ m });
    }
    foreach(res, object r) {
	html += sprintf("<option value=\"%d\""+
			(objectp(val) && val == r ? " selected='true'":"")+
			">%s</option>",
			r->get_object_id(),
			(r->get_object_class() & CLASS_USER ? 
			 r->query_attribute(USER_FULLNAME) :
			 r->get_identifier()));
    }
    html += "</select>\n";
    return html;
}

string image(object obj, mapping args)
{
    return "<image src=\"/scripts/get.pike?object="+obj->get_object_id()+"\""+
	(args->xsize ? " xsize=\""+args->xsize+"\"":"")+
	(args->ysize ? " xsize=\""+args->ysize+"\"":"")+
	" border=\"0\"/>";
}

/**
 * Upgrade callback function - the the creation time to current timestamp.
 *  
 */
void upgrade()
{
  __upgrading = 1;
}

final object get_source_object()
{
  program prg = object_program(this_object());
  string desc = master()->describe_program(prg);
  int id;
  if ( !sscanf(desc, "%*s#%d", id) )
    sscanf(desc, "%*s#%d", id);
  
  return find_object(id);
}


/**
 * Describe the Script in a backtrace.
 *  
 * @return description string of the object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string _sprintf()
{
    return master()->describe_program(object_program(this_object())) + " ("+
	get_identifier()+", #"+get_object_id()+")";
}

int is_upgrading() { return __upgrading; }
int get_object_class() { return ::get_object_class() | CLASS_SCRIPT; }
string describe() { return _sprintf(); }

void test()
{
  Test.test( "float value is float", floatp(get_value("1.1")) );
  Test.test( "string match", get_value("1test") == "1test" );
  Test.test( "\\0 separated string returns array", arrayp(get_value("a\0b")) );
  Test.test( "get_value() handles integers correctly",
	     intp(get_value("22")) && get_value("42") == 42 );
}

