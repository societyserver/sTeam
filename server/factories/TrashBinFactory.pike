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
 * $Id: TrashBinFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: TrashBinFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/factories/ContainerFactory";

#include <macros.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <events.h>

object execute(mapping vars)
{
    object obj;
    try_event(EVENT_EXECUTE, CALLER, obj);
    obj = ::object_create(vars["name"], CLASS_NAME_TRASHBIN, 0,
			  vars["attributes"],
			  vars["attributesAcquired"], 
			  vars["attributesLocked"],
			  vars["sanction"],
			  vars["sanctionMeta"]);

    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

void test() 
{
  // nothing to check
}
 
string get_identifier() { return "Trashbin.factory"; }
string get_class_name() { return "Trashbin";}
int get_class_id() { return CLASS_TRASHBIN; }

