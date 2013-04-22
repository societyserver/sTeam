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
 * $Id: module.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: module.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/classes/Object";

#include <classes.h>
#include <macros.h>
#include <assert.h>
#include <exception.h>
#include <attributes.h>
#include <events.h>


static void install_module() { }
static void create_module() {}
static void load_module() { }
bool check_swap() { return false; }

/**
 * Callback function to initialize a module. This will call init_module()
 * for any module.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
static final void init()
{
    ::init();
    init_module();
}

/**
 * init_module is called by the Server when starting or when a package is 
 * registered.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
void init_module()
{
}

/**
 * Called from _Server when loading is finished.
 *  
 */
static void load_object()
{
    load_module();
}

void post_load_module()
{
}

static mapping read_config(string cdata, string roottag)
{
  return Module.read_config(cdata, roottag);
}

/**
 * Called after all modules and factories are loaded at startup
 * or right after the package has been installed. This way the function
 * might use factories for installation for example. The server has
 * basically started at this point.
 *  
 */
void runtime_install()
{
    if ( CALLER != _Server && !(CALLER->get_object_class() & CLASS_PACKAGE) ) 
	return;

    install_module();
}

/**
 * Create the module.
 *  
 * @param string|object id - the related id.
 */
final static void 
create_object(string|object id)
{
    do_set_attribute(OBJ_CREATION_TIME, time());
    create_module();
}

/**
 * Create a duplicate of the module, which will fail in this case.
 * The function was only overriden to prevent duplication of modules.
 *  
 * @return throws an error.
 */
final object duplicate()
{
    THROW("Modules cannot be duplicated!", E_ERROR);
    return 0;
}

/**
 * return the object class for global objets "0"
 *  
 * @return the object class
 * @author Thomas Bopp (astra@upb.de) 
 */
int get_object_class()
{
    return CLASS_MODULE | ::get_object_class();
}


/**
 * Add a global event. This will only call the server object to
 * listen to the appropriate events. This is basic functionality of a
 * module. Register the event-callback function.
 *  
 * @param int event - the event to subscribe to
 * @param function cb - the callback function to be called
 * @param int phase - the phase: blocking or notification
 * @author Thomas Bopp (astra@upb.de) 
 */
static void add_global_event(int event, function cb, int phase)
{
    _Server->add_global_event(event, cb, phase);
}

/**
 * Remove all subscribed global events.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see add_global_event
 */
static void remove_global_events()
{
    _Server->remove_global_events();
}

/**
 * This function is called when an attribute is changed in the object, 
 * that acquires an attribute from this object.
 *  
 * @param object o - the object where an attribute was changed
 * @param key - the key of the attribute
 * @param val - the new value of the attribute
 * @return false will make the acquire set to none in the calling object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool keep_acquire(object o, mixed key, mixed val)
{
    return true; // should still acquire from module
}


static void delete_object()
{
  catch {
    try_event( EVENT_DELETE, CALLER );
    _Server->unregister_module( this() );
  };
  ::delete_object();
}


void test() 
{
// do not run the default Object test
}
