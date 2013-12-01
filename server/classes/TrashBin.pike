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
 * $Id: TrashBin.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: TrashBin.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/classes/Container";

#include <classes.h>
#include <macros.h>
#include <exception.h>
#include <attributes.h>

static void 
delete_object()
{
    THROW("Cannot delete the trashbin!", E_ACCESS);
    ::delete_object();
}

void empty()
{
  mixed err;

  foreach(get_inventory(), object obj) {
    err = catch {
      obj->delete();
    };
  }
}

static bool check_insert(object obj)
{
    // everything goes in here !
    return true;
}

bool move(object dest)
{
    if ( objectp(oEnvironment) ) {
	// if the trashbin is inside the users inventory
	// move it to the workroom instead (old version in inventory)
	if ( oEnvironment->get_object_class() & CLASS_USER ) 
	    return ::move(oEnvironment->query_attribute(USER_WORKROOM));

	THROW("Cannot move trashbin out of users workroom !", E_ACCESS);
    }

    return ::move(dest);
}

int get_object_class() { return ::get_object_class() | CLASS_TRASHBIN; }
string get_identifier() { return "trashbin"; }    
