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
 * $Id: name_index.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: name_index.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/secure_n_one";

#include <macros.h>
#include <attributes.h>
#include <exception.h>
#include <types.h>
#include <classes.h>
#include <events.h>
#include <database.h>

//! This module maps all object names to a table in the database
//! to allow the lookup of "name" and get an array of objects with this
//! name. This is used for searching objects in the database.

/**
 * Called on installation of module, registers the keywords attribute
 * of all classes to this module, to store the values in an indexed
 * database table for fast lookup.
 *  
 * @param  none
 * @return nothing
 * @author Ludger Merkens (balduin@upb.de)
 * @see    set_attribute
 * @see    query_attribute
 */
void load_module()
{
    ::load_module();
    set_attribute(OBJ_DESC, "This module keeps track of all objects name "+
		  "in the system - for search purposes.");
    add_global_event(EVENT_ATTRIBUTES_CHANGE, attribute_changed, PHASE_NOTIFY);
}

/**
 * This function associates the CALLER with the keywords set within the
 * database, search ability is improved by creating an reverse index.
 *  
 * @param   key - checked for OBJ_KEYWORDS
 * @param   mixed - the list of keywords to store for the caller
 * @return  (true|false) 
 * @author Ludger Merkens (balduin@upb.de)
 * @see     query_attribute
 * @see     /kernel/secure_mapping.register
 */
void attribute_changed(int e, object obj, object caller, mixed attr)
{
    foreach( indices(attr), mixed key ) {
	if ( key == OBJ_NAME ) {
	    set_value(attr[key], obj);
	}
    }
}

/**
 * executes a query in the database according to a search term
 *
 * @param  string - search-term
 * @return a list of objects
 * @author Ludger Merkens 
 */
array(object) search_objects(string searchterm)
{
    searchterm = replace(searchterm, "*", "%");
    mixed result = lookup(searchterm);
    object p;
    
    if ( objectp(result) )
	return ({ result });
    else if ( !arrayp(result) )
	return ({ });

    foreach(result, p)
    {
	if ( !objectp(p) ) continue;
	
        if (p->status() == PSTAT_FAIL_DELETED)
        {
            delete_value(p);
            p = 0;
        }
    }
    return result - ({ 0 });
}

/**
 * Get the identifier of this module.
 * 
 * @return  "index:names"
 * @author Ludger Merkens 
 */
string get_identifier() { return "index:names"; }
string get_table_name() { return "name_index"; }

