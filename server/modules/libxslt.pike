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
 * $Id: libxslt.pike,v 1.3 2009/05/18 20:25:24 astra Exp $
 */

//! This is the libxslt module - the run() function is used to
//! transform given xml code with a xsl stylesheet.
//! sleece was here!

constant cvs_version="$Id: libxslt.pike,v 1.3 2009/05/18 20:25:24 astra Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <database.h>

private static object parser = xslt.Parser();
private static Thread.Mutex xsltMutex = Thread.Mutex();


/**
 * callback function to find a stylesheet.
 *  
 * @param string uri - the uri to locate the stylesheet
 * @return the stylesheet content or zero.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static int match_stylesheet(string uri)
{
    if ( search(uri, "steam:") == 0 )
	return 1;
    return 0;
}

static object open_stylesheet(string uri)
{
    sscanf(uri, "steam:/%s", uri);
    return _FILEPATH->path_to_object(uri);
}

static string|int
read_stylesheet(object obj, string language, int position)
{
    if ( objectp(obj) ) {
	LOG("Stylesheet content found !");
	string contstr = obj->get_content(language);
	LOG("length="+strlen(contstr) + " of " + obj->get_object_id());
	return contstr;
    }
    LOG("No Stylesheet given for reading");
    return 0;
}

static void
close_stylesheet(object obj)
{
}

/**
 * Run the conversion and return the html code or whatever.
 *  
 * @param string xml - the xml code.
 * @param string|object xsl - the xsl stylesheet for transformation.
 * @param mapping vars - the variables passed to the stylesheet as params.
 * @return the transformed xml code.
 * @author Thomas Bopp (astra@upb.de) 
 */
string run(string xml, object|string xsl, mapping params)
{
    string    html;
    mapping vars = copy_value(params);

    if ( !stringp(xml) || strlen(xml) == 0 )
	steam_error("Failed to transform xml - xml is empty.");
    
    if ( !objectp(xsl) )
      MESSAGE("No Stylesheet param !");

    object lock = xsltMutex->lock();
    mixed err = catch {
	mapping cfgs = _Server->get_configs();
	foreach ( indices(cfgs), string cfg) {
	  if(stringp(cfg))
	    {
	      if ( intp(cfgs[cfg]) ) 
		cfgs[cfg] = sprintf("%d", cfgs[cfg]);
	      else if ( !stringp(cfgs[cfg]) )
		continue;
	      vars[replace(cfg, ":", "_")] = (string)cfgs[cfg];
	      m_delete(cfgs, cfg);
	    }
	}
	foreach( indices(vars), string index) {
	  if ( (stringp(vars[index]) && search(vars[index], "\0") >= 0 ) ||
	       !stringp(vars[index]) && !intp(vars[index]) )
	    vars[index] = 0;
	  else if ( intp(vars[index]) )
	    vars[index] = (string)vars[index];
	  else {
	    vars[index] = replace(vars[index], 
				  ({ "ä", "ö", "ü", "Ä", "Ö", "Ü", "ß", "\""}),
				  ({ "%e4", "%f6", "%fc", "%c4", "%d6", "%dc",
				     "%df", "\\\"" }));
	  }
	}
	
	parser->set_variables(vars);
	
	object stylesheet;
	if ( !stringp(vars["language"]) ) {
	  //werror("No language defined - setting english !\n");
	  vars["language"] = "english";
	}
	if ( objectp(xsl) ) {
	  string lang = vars["language"];
	  stylesheet = xsl->get_stylesheet(lang);
	}
	else if ( stringp(xsl) ) {
	  stylesheet = xslt.Stylesheet();
	  
	  stylesheet->set_language(vars["language"]);
	  stylesheet->set_include_callbacks(match_stylesheet,
					    open_stylesheet,
					    read_stylesheet,
					    close_stylesheet);
	  stylesheet->set_content(xsl);
	}
	else 
	  error("xslt: Invalid run argument for XSL-Stylesheet !");
	
	parser->set_xml_data(xml);
	html = parser->run(stylesheet);
      };
    destruct(lock);
    if ( arrayp(err) || objectp(err) ) {
	FATAL("Error while processing xml !\n"+PRINT_BT(err));
	
	THROW("LibXSLT (version="+parser->get_version()+
	      ") xsl: Error while processing xsl ("
              +(objectp(xsl)?xsl->get_identifier()+" #"+xsl->get_object_id():
		"no stylesheet")+" ):\n" + 
	      err[0] + "\n", E_ERROR);
    }
    else if ( err )
      FATAL("Error running xslt: %O", err);
    return html;
}

string get_identifier() { return "libxslt"; }
string get_version() { return parser->get_version(); }

