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
 * 
 * $Id: RoomFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: RoomFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/factories/ContainerFactory";

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
    init_class_attribute(ROOM_TRASHBIN, CMD_TYPE_OBJECT, 
			 "rooms trashbin", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, 0);
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
    obj = ::object_create(vars["name"], CLASS_NAME_ROOM, 0,
			  vars["attributes"],
			  vars["attributesAcquired"], 
			  vars["attributesLocked"],
			  vars["sanction"],
			  vars["sanctionMeta"]);
    
    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

int change_object_to_room ( object obj ) {
  if ( !_SECURITY->access_write(0, obj, CALLER) )
    return 0;

  string old_class = obj->get_class();
  if ( old_class == CLASS_NAME_ROOM )
    return 0;  // obj already is a room
  if ( !(old_class == CLASS_NAME_CONTAINER) )
    steam_error("Class "+old_class+" cannot be changed to a room, only"
                +" containers can !");
  if ( _Persistence->change_object_class(obj, CLASS_NAME_ROOM) ) {
    obj->set_attribute( OBJ_LAST_CHANGED, query_attribute(FACTORY_LAST_REGISTER)-1 );
    call(obj->drop, 0.0);
    return 1;
  }
  return 0;
}
 
string get_identifier() { return "Room.factory"; }
string get_class_name() { return "Room";}
int get_class_id() { return CLASS_ROOM; }

void test() 
{
  //MESSAGE("* Testing RoomFactory ...");
  object room = execute( (["name": "test-room"]) );
  Test.test( "creating room", objectp(room) );
  object cont = get_factory(CLASS_CONTAINER)->execute( (["name":"cont"]) );
  //MESSAGE("Testing movement of room in container...");
  Test.test( "forbid moving room into container",
             catch(room->move(cont)) != 0 );
  //mixed err = catch(room->move(cont)); // should not work
  //if ( !err ) 
  //  steam_user_error("Testing room into container work - should fail !");
  //MESSAGE("Result is %s", err[0]);
  
  cont->move(room);
  Test.test( "moving container into room",
             search(room->get_inventory(), cont)>=0 );

  cont->delete();
  Test.test( "deleting room", room->delete() );
  
  //MESSAGE("** RoomFactory.test(): All tests completed !");
}
