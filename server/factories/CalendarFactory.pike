/* Copyright (C) 2000-2003  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
inherit "/factories/RoomFactory";

#include <macros.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <events.h>
#include <attributes.h>
#include <types.h>

static void init_factory()
{
 ::init_factory();
 init_class_attribute(CALENDAR_TIMETABLE_START, CMD_TYPE_INT, 
		      "timetable start", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 8*60);
 init_class_attribute(CALENDAR_TIMETABLE_END, CMD_TYPE_INT, 
		      "timetable end", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 18*60);
 init_class_attribute(CALENDAR_TIMETABLE_ROTATION, CMD_TYPE_INT, 
		      "timetable rotation", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 60);
 init_class_attribute(CALENDAR_DATE_TYPE, CMD_TYPE_MAPPING, 
		      "calendar date type", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, ([ ]));
 init_class_attribute(CALENDAR_TRASH, CMD_TYPE_OBJECT, 
		      "calendar trash", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(CALENDAR_STORAGE, CMD_TYPE_OBJECT, 
		      "calendar storage", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
 init_class_attribute(CALENDAR_OWNER, CMD_TYPE_OBJECT, 
		      "calendar owner", 0,
		      EVENT_ATTRIBUTES_CHANGE, 0, CONTROL_ATTR_USER, 0);
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

    obj = ::object_create(vars["name"], CLASS_NAME_CALENDAR, 0,
			  vars["attributes"],
			  vars["attributesAcquired"], 
			  vars["attributesLocked"],
			  vars["sanction"],
			  vars["sanctionMeta"]);

    object factory = _Server->get_factory(CLASS_TRASHBIN);
    object trashbin = factory->execute((["name":"trashbin", ]));
    function do_set_attribute = obj->get_function("do_set_attribute");
    do_set_attribute(CALENDAR_TRASH, trashbin);
    trashbin->move(obj->this());
    
    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

string get_identifier() { return "Calendar.factory"; }
string get_class_name() { return CLASS_NAME_CALENDAR;} 
int get_class_id() { return CLASS_CALENDAR; } 

void test () {
}
