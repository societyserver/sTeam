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
 * $Id: MessageboardFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: MessageboardFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/factories/ObjectFactory";

#include <classes.h>
#include <macros.h>
#include <events.h>
#include <access.h>
#include <database.h>
#include <attributes.h>

string get_identifier() { return "Messageboard.factory"; }
string get_class_name() { return "Messageboard"; }
int get_class_id() { return CLASS_MESSAGEBOARD; }

/**
 * The execute function - create a new instance of type "Object"
 *  
 * @param mapping vars - variables like name and description
 * @return the newly created object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object execute(mapping vars)
{
    object obj;

    string name = vars["name"];
    try_event(EVENT_EXECUTE, CALLER, obj);
    if ( vars->transient ) {
      if ( mappingp(vars->attributes) )
	vars->attributes[OBJ_TEMP] = 1;
      else
	vars->attributes = ([ OBJ_TEMP : 1 ]);
    }
    obj = ::object_create(name, get_class_name(), 0, 
			  vars["attributes"],
			  vars["attributesAcquired"],
			  vars["attributesLocked"],
			  vars["sanction"],
			  vars["sanctionMeta"]);
			   
    if ( stringp(vars["description"]) )
	obj->set_attribute(OBJ_DESC, vars["description"]);
    object nntp = _Server->get_module("nntp");
    if ( objectp(nntp) ) 
	nntp->register_group(obj);
    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

void test () {
}
