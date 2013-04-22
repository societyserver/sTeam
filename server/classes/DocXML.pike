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
 * $Id: DocXML.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: DocXML.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/classes/Document";


#include <macros.h>
#include <database.h>
#include <attributes.h>
#include <config.h>
#include <classes.h>

#define _XMLCONVERTER _Server->get_module("Converter:XML")

private static int     iSessionPort = 0;


mapping identify_browser(array id, mapping req_headers)
{
    return httplib->identify_browser(id, req_headers);
}

object get_stylesheet()
{
    object xsl = query_attribute("xsl:document"); 
    if ( !objectp(xsl) ) {
	if ( do_query_attribute("xsl:use_public") )
	    return query_attribute("xsl:public");
    }
    return xsl;
}

/**
 * Get the content size of the XML document. This may differ because
 * it is possible to directly transform xml with XSL transformation.
 *  
 * @return the content size of the XML code or the generated code.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_content_callback
 */
int get_content_size()
{
    return ::get_content_size();
}

int get_object_class() { return ::get_object_class() | CLASS_DOCXML; }
string get_class() { return "DocXML"; }
