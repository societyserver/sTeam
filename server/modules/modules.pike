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
 * $Id: modules.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: modules.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/db_mapping";

#include <macros.h>
#include <attributes.h>

//! This module is used for storing all other modules inside the database.
//! So it enables a lookup "module" and get the related sTeam module object.


mixed get_value(string|int key)
{
    return ::get_value(key);
}

int set_value(string|int key, mixed value)
{
    if (CALLER!=_Database && CALLER!= _Server)
    	THROW("illegal attempt to register a module from "+
	      master()->stupid_describe(CALLER)+ "different from "+
	      master()->stupid_describe(_Database), E_ACCESS);
    return ::set_value(key, value);
}

/**
 * This is a hack, since the modules module is no real object, it is
 * created each time the server is started. So database connection is done
 * on creation and not on (post)_initialization
 * @see create
 * @see post_init_db_mapping
 */
void create()
{
    load_db_mapping();
}

array(string) index()
{
    return ::index();
}

string get_identifier() { return "modules"; }

int get_object_id() {
    return 0;
}

string get_table_name() {
    return "modules";
}
