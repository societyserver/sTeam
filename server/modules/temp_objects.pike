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
 * $Id: temp_objects.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: temp_objects.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <database.h>

static mapping mTempObjects;
static Thread.Mutex mutex = Thread.Mutex();
static Thread.Queue deleteQueue = Thread.Queue();

/**
 * Callback function to initialize module. Sets the save and restore function.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void init_module()
{
    add_data_storage(STORE_TEMPOBJ, retrieve_temp_objects,
                     restore_temp_objects);
    mTempObjects = ([ ]);
}

void queued_destruct()
{
    deleteQueue->write(CALLER->this());
}

/**
 * Thread to check for temporary objects and deletes out of date objects.
 * It also handles a deletion queue to prevent objects from being
 * destructed while still cleaning up.
 *  
 */
void check_temp_objects()
{
    mixed err;
    while ( 1 ) {
	while ( deleteQueue->size() > 0 ) {
	    object obj = deleteQueue->read();
	    if ( objectp(obj) ) {
		err = catch(obj->drop());
                if ( err )
		    FATAL("Error while deleting:\n"+sprintf("%O\n", err));
	    }
	}

	object l = mutex->lock();

	array(object) idx = indices(mTempObjects);
	foreach ( idx, object tmp ) {
	    LOG("Checking " + tmp->get_identifier() + " for deletion ("+
		time()+":"+mTempObjects[tmp]+")!\n");
	    if ( time() > mTempObjects[tmp] ) {
		if ( objectp(tmp) )
		    catch(tmp->delete());
		m_delete(mTempObjects, tmp);
	    }
	}
	require_save(STORE_TEMPOBJ);
	destruct(l);
	sleep(300);
    }
}

/**
 * Callback function when the module is loaded starts the 
 * thread to check for objects to be deleted.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see check_temp_objects
 */
void load_module()
{
    start_thread(check_temp_objects);
}

/**
 * Add a temporary object with a given timestamp when it should be deleted.
 *  
 * @param object obj - the temporary object.
 * @param int validT - the timestamp for that the object wont be deleted.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void add_temp_object(object obj, int validT)
{
    if ( _SECURITY->access_delete(0, obj, CALLER) ) {
	object l = mutex->lock();
	mTempObjects[obj] = validT;
	require_save(STORE_TEMPOBJ);
	destruct(l);
    }
}

/**
 * Callback function to retrieve all temporary objects.
 *  
 * @return mapping of temporary objects.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see restore_temp_objects
 */
final mapping retrieve_temp_objects()
{
    if ( CALLER != _Database ) 
	THROW("Invalid call to retrieve_temp_objects()", E_ACCESS);
    return ([ "tempObjects": mTempObjects, ]);
}

/**
 * Restore the temporary objects from the database.
 *  
 * @param mapping data - saved data of temp objects to be restored.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see retrieve_temp_objects
 */
final void restore_temp_objects(mapping data)
{
    if ( CALLER != _Database ) 
	THROW("Invalid call to restore_temp_objects()", E_ACCESS);
    mTempObjects = data["tempObjects"];
}

/**
 * Get the identifier of this module.
 *  
 * @return the identifier "temp_objects"
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string get_identifier() { return "temp_objects"; }




