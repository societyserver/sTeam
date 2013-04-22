/* Copyright (C) 2000-2006  Thomas Bopp
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

//! Code generation tool for sTeam xsl description format.

inherit "/base/xml_parser";

#include <macros.h>
#include <database.h>

constant pike_header =
"inherit \"/classes/Script\";\n"+
"inherit \"/base/xml_parser\";\n\n"+
"#include <macros.h>\n"+
"#include <database.h>\n"+
"#include <classes.h>\n"+
"#include <types.h>\n"+
"#include <attributes.h>\n"+
"#include <events.h>\n"+
"#include <access.h>\n"+
"#include <client.h>\n"+
"#include <roles.h>\n"+
"#include <config.h>\n\n"+
"object XML = OBJ(\"/scripts/xmltools.pike\");\n"+
"mapping selection = ([ ]);\n"+
"static mapping   configs = ([ ]);\n"+
"object obj, active,last;\n\n"+
"mixed err;\n"+
"object tuser;\n\n"+
"mapping read_configs(object obj)\n"+
"{\n"+
"         if ( !objectp(obj) ) return ([ ]);\n"+
"         string configStr = obj->get_content();\n"+
"	  NodeXML cfg = parse_data(configStr);\n"+
"	  if ( objectp(cfg) ) {\n"+
"	    array(NodeXML) cfgs = cfg->get_children();\n"+
"	    foreach(cfgs, object cnf)\n"+
"	      configs[cnf->get_name()] = cnf->get_data();\n"+
"         }\n"+
"         return configs;\n"+
"}\n\n"+
"string class_id_to_name(int id)\n"+
"{\n"+
"    object factory = _Server->get_factory(id);\n"+
"    if ( id & CLASS_SCRIPT ) \n"+
"        return \"'Script'\";\n"+
"    else if ( objectp(factory) )\n"+
"        return \"'\"+factory->get_class_name() + \"'\";\n"+
"    return \"'Object'\";\n"+
"}\n\n"+
"string xmlify(object __obj, mapping vars)\n"+
"{\n"+
"    string xml=\"<?xml version='1.0' encoding='utf-8'?>\";\n"+
"    string out;\n"+
"    object back;\n"+
"    mixed res;\n\n"+
"    if ( vars->this_user )\n"+
"        tuser = find_object(vars->this_user);\n"+
"    else\n"+
"        tuser = this_user();\n"+
"    obj = active = __obj;\n"+
"    array sel = tuser->query_attribute(USER_SELECTION);\n"+
"    if ( arrayp(sel) ) selection = mkmapping(sel, sel);\n";

constant pike_footer = "\n    return xml;\n}\n";

static mapping functions;
static function __reader;
static int   __functions;

static string object_from_string(string str)
{
    string obj, prefix;

    if ( sscanf(str, "%s:%s", prefix, obj) == 2 ) {
      obj = parse_and_replace_config(obj);
      switch(prefix) {
        case "orb":
	    return "OBJ(\""+obj+"\")";
	case "url":
	    return "get_module(\"filepath:url\")->path_to_object(\""+obj+"\")";
	case "group":
	    return "GROUP(\""+obj+"\")";
	case "instance":
	    return "OBJ(\""+obj+"\")->provide_instance()";
        case "resolve":
	  return "get_module(\"filepath:tree\")->resolve_path(active,\""+obj+"\")";
      }
    }
    switch(lower_case(str)) {
    case "this":
	return "obj";
    case "env":
	return "obj->get_environment()";
    case "conv":
	return "XML";
    case "server":
      return "_Server";
    case "this_user":
	return "tuser";
    case "last":
	return "last";
    case "active":
	return "active";
    case "value":
      return "value";
    case "key":
      return "data";
    case "master":
	return "master()";
    }
    return "get_module(\""+str+"\")";
}

static mixed get_default(object node)
{
    if ( !objectp(node) )
	return "";
    int v = (int)node->data;
    if ( (string)v == node->data )
	return v;
    return "\""+node->data+"\"";
}

static string get_var(object node)
{
    mixed v = get_default(node->get_node("def"));
    if ( intp(v) )
	return "(int)vars->"+node->get_node("name")->data+" || "+ v;
    else if ( strlen(v) > 0 )
	return "vars->"+node->get_node("name")->data+" || "+ v;
    return "vars->"+node->get_node("name")->data;
}

static string unserialize(object node)
{
    if ( node->name == "o" || node->name =="object" )
	return object_from_string(node->data);
    else if ( node->name == "string" ) {
      if ( strlen(node->data) > 1 && node->data[0] == '$' )
	return "config["+node->data[1..]+"]";
      return "\""+node->data + "\"";
    }
    else if ( node->name == "int" ) {
	int d;
	if ( sscanf(node->data, "%d", d) == 0 )
	    return "/* This is not an integer: "+node->data + "*/";
	return node->data;
    }
    else if ( node->name == "key" ) {
	return "data";
    }
    else if ( node->name == "value" ) {
	return "value";
    }
    else if ( node->name == "expression" )
	return node->data;
    else if ( node->name == "var" )
	return get_var(node);
    return ::unserialize(node);
}


static string xml_params(object node)
{
  if ( !objectp(node) ) 
    return "";

  array params = xmlArray(node);
  
  return params * ",";
}

static string parse_and_replace_config(string str)
{
  string prefix, postfix, config;
  prefix = postfix = config = "";
  if ( sscanf(str, "%s{$%s}%s", prefix, config, postfix) >= 2 ) {
    str = (strlen(prefix)? prefix + "\"":"\"")+"+configs[\""+config+"\"]+"+(strlen(postfix)?"\""+postfix:"\"");
  }
  return str;
}

// detect new format
static string generate_function(object node, void|string def, void|string arg)
{
    string obj, pcode, func, params;
    
    func = node->attributes->name;
    if ( func[0] == '$' )
      func = "config["+func[1..]+"]";
    if ( stringp(node->attributes->object) )
	obj = object_from_string(node->attributes->object);
    else
	obj = def;
    params = xml_params(node);
    if ( stringp(arg) )
      params += (strlen(params) > 0 ? "," : "") + arg;
    
    pcode = obj + "->"+ func + "(" + params + ")";
    return pcode;
}

static string generate_f(object node, void|string def, void|string arg)
{
    string obj, pcode, func, params;

    NodeXML f = node->get_node("n");
    NodeXML o = node->get_node("o");
    NodeXML p = node->get_node("p");
    
    if ( objectp(o) )
	obj = object_from_string(o->data);
    else
	obj = def;
    if ( !objectp(f) )
      error("Fatal error - no tag <n> found, Context: "+node->get_xml());

    func = f->data;

    if ( objectp(p) )
      pcode += "    // " + replace(node->get_xml(),"\n", " ") + "\n";
    
    params = xml_params(p);

    if ( stringp(arg) )
	params += (strlen(params) > 0 ? "," : "") + arg;
    
    pcode = obj + "->"+ func + "(" + params + ")";
    return pcode;
}

static string generate_func(object node, void|string def, void|string arg)
{
    if ( objectp(node->get_node("function"))  )
	return generate_function(node->get_node("function"), def, arg);
    object f = node->get_node("f");
    if ( !objectp(f) )
      return node->data;
    return generate_f(f, def, arg);
}

static string generate_call(object node)
{
    string pcode = "";
    string fcall = generate_func(node, "active");
    pcode += "    if ( err=catch(res = " + fcall + ") )\n";
    pcode += "    { xml += \"<!-- error calling function: "+replace(fcall,"\"","\\\"")+"\\n\"+err[0]+\"-->\"; werror(\"xmlgen: %s\\n%O\\n\", err[0],err[1]); res=\"\";}\n";
    return pcode;
}

static string generate_attribute(object node)
{
    // this is for <attribute>OBJ_NAME</attribute> (string only)
    return  "    res = active->query_attribute("+node->data+");\n";
    
}

static void handle_imports(array imports)
{
    foreach(imports, object imp) {
	string f = imp->attributes->file;
	// file should be parseable now !!!
	xmlDom.Node n = xmlDom.parse(__reader(f));
	array nodes;
	if ( imp->attributes->xpath ) {
	  nodes = n->get_nodes(imp->attributes->xpath);
	}
	else 
	  nodes = ({ n });
	imp->replace_node(nodes);
    }
}

static string add_function(array nodes)
{
    string pcode = "";
    // generate an additional function
    __functions++;
    string func = "fun_"+__functions;
    pcode += "    back = active;\n";
    pcode += "    if ( arrayp(res) ) {\n"+
	"        foreach ( res, mixed element )\n"+
        "            if (objectp(element)) {\n"+
        "                active=element;\n"+
	"                out += "+func+"(element, 0, vars);\n        }\n"+
        "            else\n"+
        "                werror(\"Warning: non object found in result array %O!\\n\", res);\n"+ 
	"    }\n";
    pcode += "    else if ( objectp(res) ) \n"+
	"            out += "+func+"(res, 0, vars);\n";
    pcode += "    else if ( mappingp(res) ) {\n"+
	"        foreach ( indices(res), mixed key )\n"+
	"            out += "+func+"(key, res[key], vars);\n"+
	"        }\n";
    pcode += "    active = back;\n";
    functions[func] = generate_structure(nodes);
    return pcode;
}

static string generate_show(object node)
{
    string pcode = "";

    if ( !objectp(node) ) // no show node
      return "";

    NodeXML f = node->get_node("f");
    if ( objectp(f) )
      return  "    res = " + 
	generate_f(f, "XML", "res") + ";\n";      

    f = node->get_node("function");
    if ( objectp(f) )
      return  "    res = " + 
	generate_function(f, "XML", "res") + ";\n";      

    array imports = node->get_nodes("import");
    if ( arrayp(imports) ) {
      handle_imports(imports);
    }
    
    array defs = ({ });
    NodeXML m = node->get_node("map");
    if ( !objectp(m) )
      m = node->get_node("structure");
    else {
      // handle def: compatibility
      defs = copy_value(m->get_nodes("def"));
      foreach(defs, object def) 
      {
	  string fname = "/xsl_tags/"+def->data+".xml";
	  string str = __reader(fname);
	  pcode += " // import def: " + def->data+"\n";
	  if ( !stringp(str) )
	      pcode += "    // " + fname + " not found !\n";
	  else {
	      mixed result = def->replace_node("<xml>"+str+"</xml>", "*");
	      if ( !arrayp(result) )
		  pcode += "/* failed to parse import: " + fname + "*/\n";
	  }
      }
    }
    if ( !objectp(m) )
      return "";
    
    array nodes = node->get_nodes("structure") + node->get_nodes("map") +
      m->get_nodes("structure");
    pcode += "    out = \"\";\n";
    
    pcode += add_function(nodes);
    
    pcode += "    res = out;\n";
    
    return pcode;
}

static string generate_tag(object node)
{
    string pcode = "";
    string tag = node->attributes->name;
    if ( !stringp(tag) )
	steam_error("No Name for tag defined !");
   
    object attr = node->get_node("attribute");
    object call = node->get_node("call");
    object ifnode = node->get_node("if");

    if ( objectp(ifnode) ) 
	pcode += " if ( " + ifnode->data + " ) {\n";


    if ( objectp(attr) )
	pcode += generate_attribute(attr);
    else if ( objectp(call) )
        pcode += generate_call(call);
    else {
      array tags = node->get_nodes("tag");
      if ( arrayp(tags) ) {
	pcode += "    xml += \"<" + tag + ">\";";
	foreach ( tags, object t ) {
	  pcode += generate_tag(t);
	}
	pcode += "    xml += \"</"+tag+">\";\n";
	if ( objectp(ifnode) )
	    pcode += " }\n";
	return pcode;
      }
      else
	steam_error("No call or attribute tag found. Context:\n"+
		    node->get_xml());
    }

    // show funktion in xml representation oder string
    pcode += generate_show(node->get_node("show"));

    // xml wandlung

    pcode += "    xml += \"<" + tag + ">\" + res + \"</"+tag+">\";\n";
    if ( objectp(ifnode) )
	pcode += " }\n";

    return pcode;
}

static string generate_class(object node)
{
    string pcode = "";

    string type = node->attributes->type;
    int t = (int) type;
    if ( t == 0 ) {
	object f = _Server->get_factory(type);
	if ( objectp(f) )
	    t = f->get_class_id();
	else
	    steam_error("Unable to find factory for " + type);   
    }
    
    pcode += "    if ( objectp(active) && (active->get_object_class() & " + t + ") ) {\n";
    foreach(node->get_nodes("tag"), object tag) {
	pcode += generate_tag(tag);
    }
    pcode += "    }\n";

    return pcode;
}

static string generate_structure(object|array node)
{
    string pcode = "";
    
    if ( arrayp(node) ) {
	xmlDom.Node n = xmlDom.RootNode("root", ([ ]));
	xmlDom.Node s = xmlDom.Node("structure", ([ ]), n, n);
	foreach(node, object sn)
	  s->add_children(sn->get_children());
	node = s;
	pcode += "/* new structure created: \n"+node->dump()+"*/\n";
    }


    if ( node->name != "structure" && node->name != "map" )
	steam_error("Structure node expected ("+node->name+")!\n"+
	    node->get_xml());
    
    if ( objectp(node->get_node("class")) ) 
	pcode += "    if ( objectp(active) ) { xml += \"<Object type=\"+class_id_to_name(active->get_object_class())+\" selected=\"+(selection[active] ? \"'true'\":\"'false'\")+\">\";\n";

    foreach(node->children, object n) {
	if ( n->name == "class" ) {
	    pcode += generate_class(n);
	}
	else if ( n->name == "def" ) {
	  pcode += "// default structures ? not supported anymore\n";
	}
    }
    foreach(node->get_nodes("tag"), object tag) {
	pcode += generate_tag(tag);
    }
    if ( objectp(node->get_node("class")) ) 
	pcode += "    xml += \"</Object>\";\n}\n";
    return pcode;
}


/**
 * Take xml code (structure root tag) and generate pike representation
 * code from it.
 *
 * @param string xml - the xml code
 * @returns pike code (mostly function calls) for xml generation
 */
string codegen(string|object xml, function read_import, void|NodeXML root)
{
    // add header and footer.
    string pcode = pike_header;
    if ( objectp(xml) ) {
      pcode += "xml += \"<!-- XGL File: " + _FILEPATH->object_to_filename(xml)+
	"-->\";\n";
      xml = xml->get_content();
    }

    if ( !objectp(root) )
      root = parse_data(xml);

    __reader    = read_import;
    __functions = 0;

    if ( !objectp(root) )
	steam_error("root-node not found !");
    else if ( root->name != "structure" )
	steam_error("No <structure> root found !");

    functions = ([ ]);


    
    // read configs...
    mapping pi = root->get_pi();
    if ( mappingp(pi) ) {
      if ( stringp(pi->steam) ) {
	string fname;
	if ( sscanf(pi->steam, "%*sconfig='%s'%*s", fname) == 0 )
	  sscanf(pi->steam, "%*sconfig=\"%s\"", fname);
	
	if ( stringp(fname) ) {
	  pcode += "    configs = read_configs(_FILEPATH->resolve_path(obj,\""+fname+"\"));\n";
	}
      }
    }
    pcode += generate_structure(root);

    pcode += pike_footer;

    // additional function code ...
    
    foreach( indices(functions), string func ) {
	pcode += "\nstring " + func + "(mixed data, mixed value, mapping vars) {\n";

	pcode += "    mixed res;\n    string xml = \"\";\n";
	pcode += "    object back;\n";
	pcode += "    string out;\n";
	pcode += "    if ( objectp(active) ) last = active;\n";
	pcode += "    if ( objectp(data) )\n";
	pcode += "        active = data;\n";
	pcode += functions[func];
	pcode += "    return xml;\n}\n\n";
    }
    
    return pcode;
}







