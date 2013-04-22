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
 * $Id: Room.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Room.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

//! A room is a Container with say functionality and users in it.
//! Rooms are connected through exits (bi-directional and uni-directional).

inherit "/classes/Container";

#include <attributes.h>
#include <events.h>
#include <macros.h>
#include <classes.h>
#include <assert.h>
#include <exception.h>
#include <database.h>

bool is_workplace()
{
    object creator = get_creator();
    if ( creator->get_object_class() & CLASS_USER )
    {
	if ( creator->query_attribute(USER_WORKROOM) == this() )
	    return true;
    }
    else {
	if ( creator->query_attribute(GROUP_WORKROOM) == this() )
	    return true;
    }
    return false;
}

bool move(object dest) 
{
    if ( is_workplace() ) 
	THROW("Cannot move workareas", E_ACCESS);
    return ::move(dest);
}

static void
delete_object()
{
    if ( objectp(_ROOTROOM) && get_object_id() == _ROOTROOM->get_object_id() )
	THROW("Cannot delete rootroom !", E_ACCESS);
    object c = CALLER;
    if ( is_workplace() && (!functionp(c->this) || c->this() != get_creator()) )
	steam_error("Cannot delete a workarea !");	

    ::delete_object();
}


/**
 * Check if its possible to insert an object.
 *  
 * @param object obj - the object to insert
 * @return true or false
 */
static bool check_insert(object obj)
{
    return true;
}

/**
 * Get the users inside this room.
 *  
 * @return An array of user objects.
 */
array(object) get_users() 
{
    array(object) users = ({ });
    foreach(get_inventory(), object inv) {
	if ( inv->get_object_class() & CLASS_USER )
	    users += ({ inv });
    }
    return users;
}

/**
 * This function sends a message to the container, which actually
 * means the say event is fired and we can have a conversation between
 * users inside this container.
 *  
 * @param msg - the message to say
 */
bool message(string msg)
{
    /* does almost nothing... */
    try_event(EVENT_SAY, CALLER, msg);
        
    run_event(EVENT_SAY, CALLER, msg);
    return true;
}

array get_messages()
{
    return query_attribute("messages");
}

int get_object_class()
{
    return ::get_object_class() | CLASS_ROOM;
}


/**
 * Is this an object ? yes!
 *  
 * @return true
 */
final bool is_room() { return true; }













