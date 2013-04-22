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
 * $Id: xml_data.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: xml_data.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";


#include <attributes.h>
#include <classes.h>

/**
 * Compose a string for a given scalar 's'.
 *  
 * @param mixed s - scalar to convert to a string.
 * @return string representation of 's'.
 * @author Thomas Bopp (astra@upb.de) 
 */
string 
compose_scalar(mixed s)
{
    if (intp(s))
        return "<int>" + (string) s + "</int>";
    else if (stringp(s))
	return "<string><![CDATA[" + s +"]]></string>";
    else if (floatp(s))
	return "<float>" + s +"</float>";
    else if (objectp(s)) {
      if ( functionp(s->get_object_id) ) 
	  return "<object><id>"+s->get_object_id()+"</id><name>"+
	      "<![CDATA["+s->get_identifier()+"]]></name></object>";
      if ( functionp(s) ) 
	  return "<function><name>"+function_name(s)+"</name>"+
	      "<object>"+function_object(s)->get_object_id()+"</object>"+
	      "</function>";
    }
    else if ( programp(s) )
	return "<program>" + master()->describe_program(s) + "</program>";

}

/**
 * Bring an array into an xml representation.
 *  
 * @param array a - the array to compose.
 * @return xml string representation of 'a'.
 * @author Thomas Bopp (astra@upb.de) 
 */
string 
compose_array(array a)
{
    int i,sz;
    string s_compose;
    
    s_compose = "<array>";
    for (i=0,sz = sizeof(a);i<sz;i++)
	s_compose += compose(a[i]);
    s_compose += "</array>\n";
    return s_compose;
}

/**
 * Bring a mapping into an xml representation.
 *  
 * @param mapping m - the mapping to compose.
 * @return xml string representation of 'm'.
 * @author Thomas Bopp (astra@upb.de) 
 * @see compose_struct
 */
string 
compose_struct(mapping m)
{
    int i,sz;
    string s_compose;
    array ind, val;
    ind = indices(m);
    val = values(m);

    s_compose = "<struct>\n";
    for (i=0,sz=sizeof(ind);i<sz;i++)
    {
	s_compose += "<member>\n";
	s_compose += "<key>" + compose(ind[i]) + "</key>\n";
	s_compose += "<value>"+ compose(val[i]) + "</value>\n";
	s_compose += "</member>\n";
    }
    s_compose +="</struct>\n";
    return s_compose;
}

/**
 * Bring any data type of pike into an xml representation.
 *  
 * @param mixed m - some data
 * @return xml string representation of 'm'.
 * @author Thomas Bopp (astra@upb.de) 
 */
string 
compose(mixed m)
{
    if (stringp(m) || intp(m) || floatp(m) || objectp(m) || programp(m) )
	return compose_scalar(m);
    if (mappingp(m))
	return compose_struct(m);
    if (arrayp(m))
	return compose_array(m);
}
