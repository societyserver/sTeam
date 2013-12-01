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
 * $Id: htmllib.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: htmllib.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <classes.h>
#include <macros.h>
#include <database.h>
#include <attributes.h>

//#define KEEP_UTF // keep the UTF8 converted encoding for output

import httplib;

string ahref_link_navigate(object obj, void|string prefix)
{
    if ( !stringp(prefix) ) prefix = "";
    return "<a "+href_link_navigate(obj)+">"+prefix+obj->get_identifier()+
	"</a>";
}

string href_link_navigate_postfix(object obj, string prefix, string postfix)
{
    string path;
    string href;
    object dest = obj;

    if (!stringp(prefix)) prefix="";
    if (!stringp(postfix))postfix="";

    if ( obj->get_object_class() & CLASS_EXIT ) {
        dest = obj->get_exit();
        path = get_module("filepath:tree")->object_to_filename(dest);
        href = "href=\""+path+postfix+"\"";
    }
    else
        href = "href=\""+prefix+replace_uml(obj->get_identifier())+postfix+"\"";
    return href;
}

string href_link_navigate(object obj, void|string prefix)
{
    string path;
    string href;
    object dest = obj;

    if ( !stringp(prefix) ) prefix = "";

    if ( obj->get_object_class() & CLASS_EXIT ) {
	dest = obj->get_exit();
	path = get_module("filepath:tree")->object_to_filename(dest);
	href = "href=\""+path+"\"";
    }
    else 
	href = "href=\""+prefix+replace_uml(obj->get_identifier())+"\"";
    return href;
}

string create_tag(string name, mapping attrs)
{
  string attr_string = "";
  foreach(indices(attrs), string a) {
    attr_string += " " + a + "=\""+attrs[a]+"\"";
  }
  return sprintf("<%s%s>", name, attr_string);
}

class rxmlHandler 
{
    inherit "AbstractCallbacks";

    static string           output = ""; // the output
    static mapping rxml_handlers   = ([ ]);
    static mapping rxml_attributes = ([ ]);
    static mapping variables       = ([ ]);
    static string encoding         = "utf-8";
    static int scriptmode          = 0;

    static ADT.Queue NodeDataQueue = ADT.Queue();

    void create(mapping vars) {
        variables = vars;
    }

    int store_data(string data) {
      string node_data = NodeDataQueue->read();
      if ( stringp(node_data) ) {
	node_data += data;
	NodeDataQueue->write(node_data);
	return 1;
      }
      return 0;
    }
    
    void startDocumentSAX(object parser, void|mixed userData) {
      output = "<!-- sTeam link consistency and HTML extension parser - modified document view !-->\n";
    }

    void startElementSAX(object parser, string name, 
			 mapping(string:string) attrs, void|mixed userData) 
    {
      if ( name == "script" )
	  scriptmode = 1;

      if ( !rxml_handlers[name] ) {
	string attr_string = "";
	if ( mappingp(attrs) ) {
	  foreach(indices(attrs), string a) {
	    
	    attr_string += " " + a + "=\""+attrs[a]+"\"";
	  }
	}
	string tagstr = "<"+name+ attr_string + ">";
	
	if ( !store_data(tagstr) )
	  output += tagstr;
      }
      else {
	rxml_attributes[name] = attrs;
	NodeDataQueue->write(""); // if is empty string then fill
      }
    }
    static string call_handler(function f, mapping attributes, string data)
    {
        mapping params = variables;
	if ( !mappingp(attributes) )
	  attributes = ([ ]);
	
	params->args = attributes;
	params->args->body = data;
	string result;
	mixed err = catch(result=f(params));
	if ( err ) {
	  FATAL("SAX: error calling handler %s\n%O", err[0], err[1]);
	  result = "<!-- error calling handler -->";
	}
	return result;
    }

    void endElementSAX(object parser, string name, void|mixed userData)
    {
        string tagstr;
	
	if ( name == "script" )
	    scriptmode = 0;
	function hfunc = rxml_handlers[name];
	mapping attr = rxml_attributes[name];
	
	if ( functionp(hfunc) ) {
	  tagstr = call_handler(hfunc, attr, NodeDataQueue->read());
	  if ( !store_data(tagstr) )
	    output += tagstr;
	}
	else if ( lower_case(name) != "br" ) 
	{
	  tagstr = "</"+name+">";
	  if ( !store_data(tagstr) )
	    output += tagstr;
	}
    }

    void errorSAX(object parser, string msg, void|mixed userData) {
        output += "<!-- SAX: " + msg + "-->\n";
    }
    void cdataBlockSAX(object parser, string value, void|mixed userData)
    {
	if ( !scriptmode )
	    value = replace(value, ({ "<", ">", }), ({ "&lt;", "&gt;" }));
	if ( !store_data(value) )
	    output += value;
    }
    void charactersSAX(object parser, string chars, void|mixed userData)
    {
	if ( !scriptmode )
	    chars = replace(chars, ({ "<", ">", }), ({ "&lt;", "&gt;" }));
	
	if ( !store_data(chars) )
	    output += chars;
    }
    void commentSAX(object parser, string value, void|mixed userData) 
    {
      output += "<!--"+value+"-->\n";
    }
    void referenceSAX(object parser, string name, void|mixed userData)
    {
      werror("referenceSAX(%s)\n", name);
      output += name;
    }
    void entityDeclSAX(object parser, string name, int type, string publicId,
		       string systemId, string content, void|mixed userData)
    {
      werror("entityDecl(%s)\n", name);
      output +=name;
    }
    void notationDeclSAX(object parser, string name, string publicId, 
			 string systemId, void|mixed userData) 
    {
        werror("notationDecl(%s)\n", name);
    }
    void unparsedEntityDeclSAX(object parser, string name, string publicId, 
			       string systemId, string notationName, 
			       void|mixed userData) 
    {
        werror("unparsedEntityDecl(%s)\n", name);
    }
    string getEntitySAX(object parser, string name, void|mixed userData)
    {
        werror("getEntitySax(%s)\n", name);
    }
    void attributeDeclSAX(object parser, string elem, string fullname, 
			  int type, int def, void|mixed userData)
    {
        werror("attributeDeclSAX(%s, %s)\n", elem, fullname);
    }
    void internalSubsetSAX(object parser, string name, string externalID, 
			   string systemID, void|mixed uData)
    {
    }
    void ignorableWhitespaceSAX(object parser, string chars, void|mixed uData)
    {
    }

    void set_handlers(mapping h) 
    {
	rxml_handlers = h;
    }
    string get_result() 
    {
      return output;
    }
}

string get_tag_name(object tag)
{
  string name = tag->get_identifier();
  sscanf(name, "%s.pike", name);
  return name;
}

function get_tag_function(object tag)
{
  object instance;  
  if ( !objectp(tag) )
    return 0;
  catch(instance = tag->provide_instance());
  if ( !objectp(instance) )
    return 0;

  return instance->execute;
}



string parse_rxml(string|object html, mapping variables, mapping tags, string|void encoding)
{
    object cb = rxmlHandler(variables);
    string inp;

    cb->set_handlers(tags);
    if ( objectp(html) ) {
	encoding = html->query_attribute(DOC_ENCODING);
    }
    else if ( !stringp(encoding) )
	encoding = detect_encoding(html);
    
    encoding = lower_case(encoding);

    inp = html;
    if ( stringp(inp) && strlen(inp) == 0 )
      return "";
    
    object sax = xml.HTML(inp, cb, ([ ]), 0, stringp(html));
    sax->parse(encoding);
    string res = cb->get_result();
#ifndef KEEP_UTF
    // now it IS utf8 - change back to former encoding
    if ( stringp(encoding) && encoding != "utf-8" ) {
      if ( catch(res = xml.utf8_to_html(res)) ) {
	werror("HTML Conversion failed !\n");
	if ( encoding == "iso-8859-1" ) {
	  if ( catch(res = xml.utf8_to_isolat1(res)) ) {
	    werror("Failed conversion - skipping rxml !\n");
	    return html;
	  }
	}
	else {
	  werror("Failed conversion - skipping !\n");
	  return html; // do nothing
	}
      }
    }
#endif
    return res;
}


class testTag {
    string execute(mapping vars) {
	return "Hello World to " + vars->args->name;
    }
}

class tagTag {
    string execute(mapping vars) {
	return "<BODY>"+vars->args->body+"</BODY>";
    }
}

void test()
{
    // first test rxml
    string result = 
	"<html><body>Welcome! <h2><test name='test'/></h2></body></html>";

    result = parse_rxml(result, ([ ]), ([ "test": testTag()->execute, ]));
    if ( result !=
	 "<html><body>Welcome! <h2>Hello World to test</h2></body></html>" )
	error("rxml test failed - wrong result " + result);
    
    result =  "<a><b>&lt;c&gt;<c apply='1'>"+
	"<d name='x'/></c>"+
	"<d name='y'/></b></a>";

    result = parse_rxml(result, ([ ]), ([ "d": testTag()->execute, 
					  "c":tagTag()->execute,]));
    if ( result != 
	 "<a><b><c><BODY>Hello World to x</BODY>Hello World to y</b></a>" )
	error("nested rxml test failed !");
}

function find_tag(string name)
{
  object tags = OBJ("/tags");
  if ( !objectp(tags) ) 
    return 0;
  object tag = tags->get_object_byname(name+".pike");
  if ( !objectp(tag) )
    return 0;
  return get_tag_function(tag);
}


mapping find_tags(object obj)
{
  if ( !objectp(obj) )
    return 0;
  if ( obj->get_object_class() & CLASS_CONTAINER ) {
    mapping result = ([ ]);
    foreach(obj->get_inventory_by_class(CLASS_DOCLPC), object tag) {
      function f = get_tag_function(tag);
      string tagname = get_tag_name(tag);
      if ( !functionp(f) )
	FATAL("Warning - no tag function for tag: %s", tagname);
      else
	result[tagname] = f;
    }
    return result;
  }
  else if ( obj->get_object_class() & CLASS_DOCXSL) {
    object env = obj->get_environment();
    if ( objectp(env) )
      return find_tags(env->get_object_byname("tags"));
  }
  return 0;
}


/**
 * Replace XML entities (&lt; &gt; &amp;)
 * with simple characters (< > &).
 * 
 * @param str the string to replace
 * @return a string without quoted characters
 */
string unquote_xml ( string str )
{
  return replace( str, ({ "&lt;", "&gt;", "&amp;" }), ({ "<", ">", "&" }) );
}


/**
 * Replace problematic characters (< > &)
 * with XML entities (&lt; &gt; &amp;).
 * 
 * @param str the string to replace
 * @return a string with problematic characters quoted
 */
string quote_xml ( string str )
{
  return replace( str, ({ "<", ">", "&" }), ({ "&lt;", "&gt;", "&amp;" }) );
}


/**
 * Replace HTML entities with umlauts, <, >, & etc.
 * This method was taken from Pike Protocols.HTTP.unentity() and reversed.
 * 
 * @param str the string to replace
 * @return a utf-8 string without quoted characters
 */
string unquote_html ( string str )
{
  return replace( str,

    ({ "&AElig;", "&Aacute;", "&Acirc;", "&Agrave;", "&Aring;", "&Atilde;",
       "&Auml;", "&Ccedil;", "&ETH;", "&Eacute;", "&Ecirc;", "&Egrave;",
       "&Euml;", "&Iacute;", "&Icirc;", "&Igrave;", "&Iuml;", "&Ntilde;",
       "&Oacute;", "&Ocirc;", "&Ograve;", "&Oslash;", "&Otilde;", "&Ouml;",
       "&THORN;", "&Uacute;", "&Ucirc;", "&Ugrave;", "&Uuml;", "&Yacute;",
       "&aacute;", "&acirc;", "&aelig;", "&agrave;", "&apos;", "&aring;",
       "&ast;", "&atilde;", "&auml;", "&brvbar;", "&ccedil;", "&cent;",
       "&colon;", "&comma;", "&commat;", "&copy;", "&deg;", "&dollar;",
       "&eacute;", "&ecirc;", "&egrave;", "&emsp;", "&ensp;", "&equals;",
       "&eth;", "&euml;", "&excl;", "&frac12;", "&frac14;", "&frac34;",
       "&frac18;", "&frac38;", "&frac58;", "&frac78;", "&gt;", "&gt",
       "&half;", "&hyphen;", "&iacute;", "&icirc;", "&iexcl;", "&igrave;",
       "&iquest;", "&iuml;", "&laquo;", "&lpar;", "&lsqb;", "&lt;",
	   "&lt", "&mdash;", "&micro;", "&middot;", "&nbsp;", "&ndash;",
	   "&not;", "&ntilde;", "&oacute;", "&ocirc;", "&ograve;", "&oslash;",
	   "&otilde;", "&ouml;", "&para;", "&percnt;", "&period;", "&plus;",
	   "&plusmn;", "&pound;", "&quest;", "&quot;", "&raquo;", "&reg;",
	   "&rpar;", "&rsqb;", "&sect;", "&semi;", "&shy;", "&sup1;",
	   "&sup2;", "&sup3;", "&szlig;", "&thorn;", "&tilde;", "&trade;",
	   "&uacute;", "&ucirc;", "&ugrave;", "&uuml;", "&yacute;", "&yen;",
	   "&yuml;", "&verbar;", "&amp;", "&#34;", "&#39;", "&#0;", "&#58;" }),

    ({ "?", "¡", "¬", "¿", "?", "?",
       "?", "«", "?", "?", " ", "»",
       "À", "Õ", "?", "Ã", "?", "?",
       "?", "?", "?", "ÿ", "?", "÷",
       "?", "?", "?", "?", "?", "?",
       "·", "?", "Ê", "?", "&apos;", "Â",
       "&ast;", "?", "?", "¶", "Á", "¢",
       ":", ",", "&commat;", "©", "?", "$",
       "È", "Í", "Ë", "&emsp;", "&ensp;", "&equals;",
       "?", "Î", "!", "?", "º", "æ",
       "&frac18;", "&frac38;", "&frac58;", "&frac78;", ">", ">",
       "&half;", "&hyphen;", "Ì", "Ó", "°", "Ï",
       "ø", "Ô", "´", "(", "&lsqb;", "<",
       "<", "&mdash;", "µ", "?", "", "&ndash;",
       "¨", "Ò", "Û", "Ù", "Ú", "¯",
       "?", "?", "?", "%", ".", "+",
       "±", "£", "?", "\"", "ª", "Æ",
       ")", "&rsqb;", "ß", "&semi;", "?", "?",
       "?", "?", "?", "?", "~", "&trade;",
       "?", "?", "?", "¸", "?", "?",
       "?", "&verbar;", "&", "\"", "\'", "\000", ":" }),

  );
}


/**
 * Replace umlauts, <, >, & etc. with HTML entities.
 * This method was taken from Pike Protocols.HTTP.unentity() and reversed.
 * 
 * @param str the string to replace (utf-8 encoding expected)
 * @return a string with problematic characters quoted to html entities
 */
string quote_html ( string str )
{
  return replace( str,

    ({ "?", "¡", "¬", "¿", "?", "?",
       "?", "«", "?", "?", " ", "»",
       "À", "Õ", "?", "Ã", "?", "?",
       "?", "?", "?", "ÿ", "?", "÷",
       "?", "?", "?", "?", "?", "?",
       "·", "?", "Ê", "?", "&apos;", "Â",
       "&ast;", "?", "?", "¶", "Á", "¢",
       ":", ",", "&commat;", "©", "?", "$",
       "È", "Í", "Ë", "&emsp;", "&ensp;", "&equals;",
       "?", "Î", "!", "?", "º", "æ",
       "&frac18;", "&frac38;", "&frac58;", "&frac78;", ">", ">",
       "&half;", "&hyphen;", "Ì", "Ó", "°", "Ï",
       "ø", "Ô", "´", "(", "&lsqb;", "<",
       "<", "&mdash;", "µ", "?", "", "&ndash;",
       "¨", "Ò", "Û", "Ù", "Ú", "¯",
       "?", "?", "?", "%", ".", "+",
       "±", "£", "?", "\"", "ª", "Æ",
       ")", "&rsqb;", "ß", "&semi;", "?", "?",
       "?", "?", "?", "?", "~", "&trade;",
       "?", "?", "?", "¸", "?", "?",
       "?", "&verbar;", "&", "\"", "\'", "\000", ":" }),

    ({ "&AElig;", "&Aacute;", "&Acirc;", "&Agrave;", "&Aring;", "&Atilde;",
       "&Auml;", "&Ccedil;", "&ETH;", "&Eacute;", "&Ecirc;", "&Egrave;",
       "&Euml;", "&Iacute;", "&Icirc;", "&Igrave;", "&Iuml;", "&Ntilde;",
       "&Oacute;", "&Ocirc;", "&Ograve;", "&Oslash;", "&Otilde;", "&Ouml;",
       "&THORN;", "&Uacute;", "&Ucirc;", "&Ugrave;", "&Uuml;", "&Yacute;",
       "&aacute;", "&acirc;", "&aelig;", "&agrave;", "&apos;", "&aring;",
       "&ast;", "&atilde;", "&auml;", "&brvbar;", "&ccedil;", "&cent;",
       "&colon;", "&comma;", "&commat;", "&copy;", "&deg;", "&dollar;",
       "&eacute;", "&ecirc;", "&egrave;", "&emsp;", "&ensp;", "&equals;",
       "&eth;", "&euml;", "&excl;", "&frac12;", "&frac14;", "&frac34;",
       "&frac18;", "&frac38;", "&frac58;", "&frac78;", "&gt;", "&gt",
       "&half;", "&hyphen;", "&iacute;", "&icirc;", "&iexcl;", "&igrave;",
       "&iquest;", "&iuml;", "&laquo;", "&lpar;", "&lsqb;", "&lt;",
	   "&lt", "&mdash;", "&micro;", "&middot;", "&nbsp;", "&ndash;",
	   "&not;", "&ntilde;", "&oacute;", "&ocirc;", "&ograve;", "&oslash;",
	   "&otilde;", "&ouml;", "&para;", "&percnt;", "&period;", "&plus;",
	   "&plusmn;", "&pound;", "&quest;", "&quot;", "&raquo;", "&reg;",
	   "&rpar;", "&rsqb;", "&sect;", "&semi;", "&shy;", "&sup1;",
	   "&sup2;", "&sup3;", "&szlig;", "&thorn;", "&tilde;", "&trade;",
	   "&uacute;", "&ucirc;", "&ugrave;", "&uuml;", "&yacute;", "&yen;",
	   "&yuml;", "&verbar;", "&amp;", "&#34;", "&#39;", "&#0;", "&#58;" }),

  );
}


string describe() { return "htmllib"; }

