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
 * $Id: secure_mapping.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: secure_mapping.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";
inherit "/kernel/db_mapping";

#include <macros.h>
#include <events.h>

/**
 * Callback function when the module is loaded.
 *  
 * @author Ludger Merkens
 */
static void load_module()
{
    load_db_mapping();
}

/**
 * look up a user object from the sTeam database by username.
 *
 * @param  string - username
 * @return object - proxy associated with the user.
 * @see    register_user
 * @author Ludger Merkens 
 */
object lookup(string key)
{
    object res;
    res = get_value(key);
    return res;
}

/**
 * removes a key from the key lookup table, called on deletion of a key.
 * @param   string key - the name the key is registered with
 * @return  (0|1)
 * @see     
 * @author  Ludger Merkens 
 */
int unregister(string key)
{
    int res;
    try_event(EVENT_DB_UNREGISTER, CALLER, key);
    res = delete(key);
    run_event(EVENT_DB_UNREGISTER, CALLER, key);
    return res;
}

/**
 * registers a key in the sTeam database with it's keyname.
 *
 * @param  string - uname (name to register with)
 * @param  object - key  (the (proxy) object to register)
 * @return (1|0)
 * @see    lookup_key
 * @author Ludger Merkens 
 */
int register(string uname, object key)
{
    int res;
    try_event(EVENT_DB_REGISTER, CALLER, uname, key);
    ::set_value(uname, key);
    res = (::get_value(uname) == key);
    run_event(EVENT_DB_REGISTER, CALLER, uname, key);
    return res;
}

//  int get_object_id()
//  {
//      return __module::get_object_id();
//  }

//  object this()
//  {
//      return ::this();
//  }

mixed list() {
    mixed res;
    try_event(EVENT_DB_QUERY, CALLER);
    res = index();
    run_event(EVENT_DB_QUERY, CALLER);
    return res;
}
