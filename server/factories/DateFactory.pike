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
 */
inherit "/factories/ObjectFactory";

// Wir wissen nicht wirklich welche includes werden muessen.
#include <macros.h>
#include <classes.h>
#include <database.h>
#include <assert.h>
#include <events.h>
#include <attributes.h>
#include <types.h>
#include <macros.h>


static void init_factory()
{
 ::init_factory();

 init_class_attribute(DATE_KIND_OF_ENTRY, CMD_TYPE_UNKNOWN, 
		      "the kind of this entry", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,-1);
 
 init_class_attribute(DATE_IS_SERIAL, CMD_TYPE_INT, 
		      "is this entry serial or not", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,-1);
 
 init_class_attribute(DATE_PRIORITY, CMD_TYPE_INT, 
		      "the priority of this entry", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,-1);
 
 init_class_attribute(DATE_TITLE, CMD_TYPE_STRING, 
		      "the title of this entry", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,"");
 
 init_class_attribute(DATE_DESCRIPTION, CMD_TYPE_STRING, 
		      "the description of this entry",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,"");

 init_class_attribute(DATE_START_TIME, CMD_TYPE_INT, "start time of date",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(DATE_END_TIME, CMD_TYPE_INT, "end time of date",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);

 init_class_attribute(DATE_START_DATE, CMD_TYPE_INT, "start date of date",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);

 init_class_attribute(DATE_END_DATE, CMD_TYPE_INT, "end date of date",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);

 init_class_attribute(DATE_INTERVALL, CMD_TYPE_STRING, 
		      "intervall of date (day, week, month, year)",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,"");

 init_class_attribute(DATE_LOCATION, CMD_TYPE_STRING, "location of date",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,"");
 init_class_attribute(DATE_WEBSITE, CMD_TYPE_STRING, "website",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,"");
 init_class_attribute(DATE_NOTICE, CMD_TYPE_STRING, "notice",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,"");
 init_class_attribute(DATE_TYPE, CMD_TYPE_INT, "type of date",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(DATE_ATTACHMENT, CMD_TYPE_OBJECT, "attachement",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);


 init_class_attribute(DATE_PARTICIPANTS, CMD_TYPE_ARRAY, "participating users",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(DATE_ORGANIZERS, CMD_TYPE_ARRAY, "organizing user",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(DATE_ACCEPTED, CMD_TYPE_ARRAY, "accepting users",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(DATE_CANCELLED, CMD_TYPE_ARRAY, "cancelling users",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);

 init_class_attribute(DATE_STATUS, CMD_TYPE_INT, "date status",
		      0, EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);


 init_class_attribute(DATE_RANGE, CMD_TYPE_OBJECT, 
		      "an mapping, which includes all the dates informations",
		      0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER,0);
			      
}			     

object execute(mapping vars)
{
    object obj;
    try_event(EVENT_EXECUTE, CALLER, obj);
    if ( vars->transient ) {
      if ( mappingp(vars->attributes) )
	vars->attributes[OBJ_TEMP] = 1;
      else
	vars->attributes = ([ OBJ_TEMP : 1 ]);
    }
    
    obj = ::object_create(vars["name"], CLASS_NAME_DATE, 0,
			  vars["attributes"],
			  vars["attributesAcquired"], 
			  vars["attributesLocked"],
			  vars["sanction"],
			  vars["sanctionMeta"]);

    run_event(EVENT_EXECUTE, CALLER, obj);
    
    object start = Calendar.Second(vars->start);
    object end = Calendar.Second(vars->end);
    if ( objectp(start) && objectp(end) ) {
      object rangeObject = start->range(end);
      obj->set_attribute(DATE_RANGE, rangeObject);
    }
    return obj->this();
}

 
string get_identifier() { return "Date.factory"; }
string get_class_name() { return CLASS_NAME_DATE;}
int get_class_id() { return CLASS_DATE; }

void test () {
}
