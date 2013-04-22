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
 * $Id: xml_parser.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: xml_parser.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <macros.h>

import xmlDom;

string node_to_str(object n);


//! this is a structure to make accessing Parser.XML.Node(s) easier.

class NodeXML 
{
  inherit Node;
  
  mapping pi = ([ ]); // processing instructions;
};



/**
 * Parse given data using the Parser.XML.Tree module.
 *  
 * @param string data - the xml data to parse.
 * @return NodeXML structure described by its root-node.
 */
NodeXML parse_data(string data)
{
  return parse(data);
}

/**
 * Converts a node of an XML Tree to a string.
 *  
 * @param NodeXML ann - the node to convert.
 * @return string representation of the Node and it children recursively.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see
 */
string node_to_str(NodeXML ann)
{
    string res = "";
    string     attr;

    res = "<"+ann->name;
    foreach(indices(ann->attributes), attr) {
	if ( attr != ann->name )
	    res += " " + attr + "=\""+ann->attributes[attr]+"\"";
    }
    res += ">"+ann->data;
    foreach(ann->children, NodeXML child) {
	res += "<"+child->name;
	foreach(indices(child->attributes), attr) {
	    if ( attr != child->name )
		res += " " + attr + "=\""+child->attributes[attr]+"\"";
	}
	res += ">" + child->data + children_to_str(child->children)+
	    "</"+child->name+">\n";
    }
    res += "</"+ann->name+">\n";
    return res;
}

/**
 * Some conversion function I forgot where it is used at all.
 *
 * @param array annotations - an array of annotations to convert
 * @return a string representation of the annotations.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string children_to_str(array annotations)
{
    string res = "";
    if ( !arrayp(annotations) )
	return res;
    
    foreach(annotations, NodeXML ann) {
	res += node_to_str(ann);
    }
    return res;
}

/**
 * Convert some annotations to a string representation by using the
 * children_to_str function. Remember annotations can be annotated again!
 *  
 * @param array annotations - the annotations to convert.
 * @return string representation of the annotations.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see children_to_str
 */
string convert_annotations(array annotations)
{
    string res = "";
    foreach(annotations, NodeXML ann) {
	res += children_to_str(ann->children);
    }
    return res;
}

/**
 * Display the structure of a XML Tree given by NodeXML node.
 *  
 * @param NodeXML node - the node, for example the root-node of the tree.
 * @return just writes the structure to stderr.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>)
 */
void display_structure(NodeXML node, void|int depth)
{
    for ( int i = 0 ; i < depth; i++ )
	werror("\t");
    werror(node->name+":"+node->data+"\n");
    foreach(node->children, NodeXML n) {
	display_structure(n, depth+1);
    }
}

/**
 * Create a mapping from an XML Tree.
 *  
 * @param NodeXML n - the root-node to transform to a mapping.
 * @return converted mapping.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
mapping xmlMap(NodeXML n)
{
  mapping res = ([ ]);
  foreach ( n->children, NodeXML children) {
    if ( children->name == "member" ) {
      mixed key,value;
      foreach(children->children, object o) {

	if ( o->name == "key" )
	  key = unserialize(o->children[0]);
	else if ( o->name == "value" )
	  value = unserialize(o->children[0]);
      }
      res[key] = value;
    }
  }
  return res;
}

/**
 * Create an array with the childrens of the given Node.
 *  
 * @param NodeXML n - the current node to unserialize.
 * @return Array with unserialized childrens.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
array xmlArray(NodeXML n)
{
    array res = ({ });
    foreach ( n->children, NodeXML children) {
	res += ({ unserialize(children) });
    }
    return res;
}

/**
 * Create some data structure from an XML Tree.
 *  
 * @param NodeXML n - the root-node of the XML Tree to unserialize.
 * @return some data structure describing the tree.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
mixed unserialize(NodeXML n) 
{
    switch ( n->name ) {
    case "struct":
	return xmlMap(n);
	break;
    case "array":
	return xmlArray(n);
	break;
    case "int":
	return (int)n->data;
	break;
    case "float":
	return (float)n->data;
	break;
    case "string":
	return n->data;
	break;
    }
    return -1;
}


mixed test()
{
    string xml = "<?xml version='1.0'?><a>1<b>2</b>3<c a='1'>4</c></a>";
    object node = parse_data(xml);
    object n = node->get_node("/a/b");
    if ( !objectp(n) || n->data != "2" )
	error("Failed to resolve xpath expression.");
    n->replace_node("<huh/>");
    if ( node->get_xml()!= "<a >13<huh ></huh>\n<c a='1' >4</c>\n</a>\n" )
	error("replacing of <b/> didnt work !\nResult is:"+node->get_xml());
    
    // error testing
    xml = "<a><b/>";
    
    mixed err = catch(parse_data(xml));
    if ( err == 0 )
	error("Wrong xml code does not throw error.\n");
    
    xml = "<a><b test=1/></a>";
    err = catch(parse_data(xml));
    if ( err == 0 )
	error("Wrong xml code does not throw error.\n");
    
    return n;
}

