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
 * $Id: Container.pike,v 1.5 2009/05/06 19:23:10 astra Exp $
 */
constant cvs_version="$Id: Container.pike,v 1.5 2009/05/06 19:23:10 astra Exp $";

//! A Container is an object that holds other objects (no users).

inherit "/classes/Object";

#include <attributes.h>
#include <macros.h>
#include <assert.h>
#include <events.h>
#include <classes.h>
#include <database.h>
#include <types.h>

private static array(object) oaInventory; // the containers inventory

/**
 * init this object.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see create
 */
static void
init()
{
    ::init();
    oaInventory = ({ });
    add_data_storage(STORE_CONTAINER, store_container, restore_container);
}

/**
 * This function is called by delete to delete this object.
 *  
 */
static void
delete_object()
{
    ::delete_object();
    array(object) inventory = copy_value(oaInventory);
    
    foreach( inventory, object inv ) {
	// dont delete Users !
	if ( objectp(inv) )
	{
	    mixed err;
	    if ( inv->get_object_class() & CLASS_USER) {
		err = catch {
		    inv->move(inv->query_attribute(USER_WORKROOM));
		};
	    }
	    else {
		err = catch {
		    inv->delete();
		};
	    }
	}
    }
}

/**
 * Duplicate an object - that is create a copy, the permisions are
 * not copied though.
 *  
 * @param recursive - should the container be copied recursively?
 * @return the copy of this object
 * @see create
 */
object duplicate(void|bool recursive)
{
  return ::duplicate(([ "recursive": recursive, ]));
}

mapping copy(object obj, mapping vars)
{
  mapping copies = ::copy(obj, vars);
  if ( mappingp(vars) && vars->recursive ) {
    foreach( obj->get_inventory(), object inv ) {
      if ( !objectp(inv) )
	continue;
      if ( inv->get_object_class() & CLASS_USER) 
	continue;
      object new_inv;
      mapping copied;
      mixed err = catch {
	copied = inv->do_duplicate(vars);
	copies |= copied;
	new_inv = copied[inv];
	new_inv->move(this());
      };
      if ( err != 0 ) {
	FATAL("Duplication of #" + inv->get_object_id());
	FATAL("Error while duplicating recursively !\n"+
	      sprintf("%O", err[0])+"\n"+sprintf("%O",err[1]));
      }
    }
  }
  return copies;
}

void update_path()
{
  ::update_path();
  foreach(oaInventory, object inv) {
    if ( objectp(inv) ) {
      mixed err = catch(inv->update_path());
      if ( err ) {
	FATAL("Error while updating path: %O\n%O", err[0], err[1]);
      }
    }
  }
}

/**
 * Check if it is possible to insert the object here.
 *  
 * @param object obj - the object to insert
 * @return true or false
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see insert_obj
 */
static bool check_insert(object obj)
{
    if ( obj->get_object_class() & CLASS_ROOM ) 
      steam_user_error("Unable to insert a Room-Object into Container !");

    if ( obj->get_object_class() & CLASS_USER )
      steam_user_error("Unable to insert User into Container !");

    if ( obj->get_object_class() & CLASS_EXIT )
      steam_user_error("Unable to insert Exits into Container !");

    return true;
}

void check_environment(object env, object obj)
{
    if ( !objectp(env) )
	return;

    if ( env == obj )
	steam_error("Recursion detected in environment!");
    env = env->get_environment();
    check_environment(env, obj);
}

/**
 * Insert an object in the containers inventory. This is called by
 * the move function - don't call this function myself.
 *  
 * @param obj - the object to insert into the container
 * @return true if object was inserted
 * @author Thomas Bopp 
 * @see remove_obj
 */
bool
insert_obj(object obj)
{
    ASSERTINFO(IS_PROXY(obj), "Object is not a proxy");
    
    if ( !objectp(obj) )
	return false;

    if ( CALLER != obj->get_object() ) // only insert proxy objects
      steam_error("Container.insert_obj() failed to insert non-proxy !");
    if ( !arrayp(oaInventory) )
	oaInventory = ({ });

    check_insert(obj); // does throw

    if ( obj == this() )
	steam_error("Cannot insert object into itself !");
    check_environment(get_environment(), obj);

    if ( search(oaInventory, obj) != -1 ) {
	FATAL("Inserting object %O twice into %O! ----\n%s---\n", obj,
              this(), describe_backtrace(backtrace()));
        return true;
    }
	
    try_event(EVENT_ENTER_INVENTORY, obj);

    // do not set, if user is added to inventory
    if ( !(obj->get_object_class() & CLASS_USER) ) {
      do_set_attribute(CONT_USER_MODIFIED, this_user());
      do_set_attribute(CONT_LAST_MODIFIED, time());
    }
    oaInventory += ({ obj });
    
    require_save(STORE_CONTAINER, UNDEFINED, SAVE_INSERT, ({ obj }));
    
    run_event(EVENT_ENTER_INVENTORY, obj);
    return true;
}



/**
 * Remove an object from the container. This function can only be
 * called by the object itself and should only be called by the move function.
 *  
 * @param obj - the object to insert into the container
 * @return true if object was removed
 * @author Thomas Bopp 
 * @see insert_obj
 */
bool remove_obj(object obj)
{
    if ( !objectp(obj) ||
         (obj->get_object() != CALLER && obj->get_environment() == this()) )
	return false;

    ASSERTINFO(arrayp(oaInventory), "Inventory not initialized!");
    try_event(EVENT_LEAVE_INVENTORY, obj);
    
    do_set_attribute(CONT_LAST_MODIFIED, time());
    oaInventory -= ({ obj });
    
    require_save(STORE_CONTAINER, UNDEFINED, SAVE_REMOVE, ({ obj }));
    run_event(EVENT_LEAVE_INVENTORY, obj);
    return true;
}

/**
 * Get the inventory of this container.
 *  
 * @param void|int from_obj - the starting object
 * @param void|int to_obj - the end of an object range.
 * @return a list of objects contained by this container
 * @see move
 * @see get_inventory_by_class
 */
array(object) get_inventory(int|void from_obj, int|void to_obj)
{
    oaInventory -= ({0});
    try_event(EVENT_GET_INVENTORY, CALLER);
    run_event(EVENT_GET_INVENTORY, CALLER);
    
    if ( to_obj > 0 )
	return oaInventory[from_obj..to_obj];
    else if ( from_obj > 0 )
	return oaInventory[from_obj..];
    return copy_value(oaInventory);
}

/**
 * Get the content of this container - only relevant for multi
 * language containers.
 *  
 * @return content of index file
 */
string get_content(void|string language)
{
  if ( do_query_attribute("cont_type") == "multi_language" ) {
    mapping index = do_query_attribute("language_index");
    if ( objectp(index[language]) )
      return index[language]->get_content();
    if ( objectp(index->default) )
      return index["default"]->get_content();
  }
  return 0;
}


/**
 * Returns the inventory of this container, optionally filtered by object
 * class, attribute values or pagination.
 * The description of the filters and sort options can be found in the
 * filter_objects_array() function of the "searching" module.
 *
 * Example:
 * Return all documents with keywords "urgent" or "important" that the user
 * has read access to, that are no wikis and that have been changed in the
 * last 24 hours, sort them by modification date (newest first) and return
 * only the first 10 results:
 * get_inventory_filtered(
 *   ({  // filters:
 *     ({ "-", "!access", SANCTION_READ }),
 *     ({ "-", "attribute", "OBJ_TYPE", "prefix", "container_wiki" }),
 *     ({ "-", "attribute", "DOC_LAST_MODIFIED", "<", time()-86400 }),
 *     ({ "-", "attribute", "OBJ_KEYWORDS", "!=", ({ "urgent", "important" }) }),
 *     ({ "+", "class", CLASS_DOCUMENT })
 *   }),
 *   ({  // sort:
 *     ({ ">", "attribute", "DOC_LAST_MODIFIED" })
 *   }),  );
 *
 * @param filters (optional) an array of filters (each an array as described
 *   in the "searching" module) that specify which objects to return
 * @param sort (optional) an array of sort entries (each an array as described
 *   in the "searching" module) that specify the order of the items
 * @param offset (optional) only return the objects starting at (and including)
 *   this index
 * @param length (optional) only return a maximum of this many objects
 * @return a mapping ([ "objects":({...}), "total":nr, "length":nr,
 *   "start":nr, "page":nr ]), where the "objects" value is an array of
 *   objects that match the specified filters, sort order and pagination.
 *   The other indices contain pagination information ("total" is the total
 *   number of objects after filtering but before applying "length", "length"
 *   is the requested number of items to return (as in the parameter list),
 *   "start" is the start index of the result in the total number of objects,
 *   and "page" is the page number (starting with 1) of pages with "length"
 *   objects each, or 0 if invalid).
 */
mapping get_inventory_paginated ( array|void filters, array|void sort, int|void offset, int|void length )
{
  oaInventory -= ({ 0 });
  try_event(EVENT_GET_INVENTORY, CALLER);
  run_event(EVENT_GET_INVENTORY, CALLER);
  return get_module( "searching" )->paginate_object_array( oaInventory,
      filters, sort, offset, length );
}

/**
 * Returns the inventory of this container, optionally filtered, sorted and
 * limited by offset and length. This returns the same as the "objects" index
 * in the result of get_inventory_paginated() and is here for compatibility
 * reasons and ease of use (if you don't need pagination information).
 *
 * @see get_inventory_paginated
 */
array get_inventory_filtered ( array|void filters, array|void sort, int|void offset, int|void length )
{
  return get_inventory_paginated( filters, sort, offset, length )["objects"];
}


/**
 * Get only objects of a certain class. The class is the bit id submitted
 * to the function. It matches only the highest class bit given.
 * This means get_inventory_by_class(CLASS_CONTAINER) would not return
 * any CLASS_ROOM. Also it is possible to do 
 * get_inventory_by_class(CLASS_CONTAINER|CLASS_EXIT) which would return
 * an array of containers and exits, but still no rooms or links - 
 * Room is derived from Container and Exit inherits Link.
 *
 * @param int cl - the classid
 * @param void|int from_obj - starting object 
 * @param void|int to_obj - second parameter for an object range.
 * @return list of objects matching the given criteria.
 */
array(object) get_inventory_by_class(int cl, int|void from_obj,int|void to_obj)
{
    try_event(EVENT_GET_INVENTORY, CALLER);
    run_event(EVENT_GET_INVENTORY, CALLER);

    array(object) arr = ({ });
    array(int)    bits= ({ });
    for ( int i = 0; i < 32; i++ ) {
        if ( cl & (1<<i) ) 
           bits += ({ 1<<i });
    }
    int cnt = 0;
    foreach(bits, int bit) {
        foreach(oaInventory, object obj) {
	  if ( !objectp(obj) )
	    continue;
	  int ocl = obj->get_object_class();
            if ( (ocl & bit) && (ocl < (bit<<1)) ) {
	      cnt++;
              if ( to_obj != 0 && cnt > to_obj ) break;
	      if ( from_obj < cnt && (to_obj == 0 || cnt < to_obj ) )
		arr += ({ obj });
	    }
        }
    }
    return arr;
}

/**
 * Restore the container data. Most importantly the inventory.
 *  
 * @param data - the unserialized object data
 * @author Thomas Bopp (astra@upb.de) 
 * @see store_container
 */
void restore_container(mixed data)
{
    if (CALLER != _Database )
	THROW("Caller is not Database !", E_ACCESS);

    oaInventory = data["Inventory"];
    if ( !arrayp(oaInventory) )
	oaInventory = ({ });
    
}

/**
 * Stores the data of the container. Returns the inventory
 * of this container.
 *  
 * @return the inventory and possible other important container data.
 * @author Thomas Bopp (astra@upb.de) 
 * @see restore_container
 */
mixed store_container()
{
    if (CALLER != _Database )
	THROW("Caller is not Database !", E_ACCESS);
    return ([ "Inventory": oaInventory, ]);
}

/**
 * Get the content size of this object which does not make really
 * sense for containers.
 *  
 * @return the content size: -2 as the container can be seen as an inventory
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see stat
 */
int get_content_size()
{
    return -2;
}

/**
 * Get the size of documents in this container only or including sub-containers
 *  
 * @param void|bool calculateContainers - also get size of container
 * @return size of documents in container
 */
int get_content_size_inventory(void|bool calculateContainers)
{
  int size = 0;
  foreach(oaInventory, object inv) {
    if ( objectp(inv) ) {
      if ( inv->get_object_class() & CLASS_DOCUMENT )
	size += inv->get_content_size();
      else if ( calculateContainers && 
		inv->get_object_class() & CLASS_CONTAINER ) 
	  size += inv->get_content_size_inventory();
    }
  }
  return size;
}

/**
 * Get the number of objects in this container
 *  
 * @return number of objects in this container
 */
int get_size() 
{
  return sizeof(oaInventory);
}

/**
 * This function returns the stat() of this object. This has the 
 * same format as statting a file.
 *  
 * @return status array as in file_stat()
 * @see get_content_size
 */
array(int) stat()
{
    int creator_id = objectp(get_creator())?get_creator()->get_object_id():0;

    return ({ 16895, get_content_size(), 
	      do_query_attribute(OBJ_CREATION_TIME),
	      do_query_attribute(CONT_LAST_MODIFIED)||
	      do_query_attribute(OBJ_CREATION_TIME),
	      time(),
	      creator_id, creator_id, "httpd/unix-directory" });
}

/**
  * The function returns an array of important events used by this
  * container. In order to observe the actions inside the container,
  * the events should be heared.
  *  
  * @return Array of relevant events
  */
array(int) observe() 
{
    return ({ EVENT_SAY, EVENT_LEAVE_INVENTORY, EVENT_ENTER_INVENTORY });
}

/**
 * This function sends a message to the container, which actually
 * means the say event is fired and we can have a conversation between
 * users inside this container.
 *  
 * @param msg - the message to say
 * @author Thomas Bopp (astra@upb.de) 
 */
bool message(string msg)
{
    /* does almost nothing... */
    try_event(EVENT_SAY, CALLER, msg);
    run_event(EVENT_SAY, CALLER, msg);
    return true;
}

/**
 * Swap the position of two objects in the inventory. This
 * function is usefull for reordering the inventory.
 * You can sort an inventory afterwards or use the order of
 * objects given in the list (array).
 *  
 * @param int|object from - the object or position "from"
 * @param int|object to   - the object or position to swap to
 * @return if successfull or not (error)
 * @see get_inventory
 * @see insert_obj
 * @see remove_obj
 */
bool swap_inventory(int|object from, int|object to)
{
    int sz = sizeof(oaInventory);

    if ( objectp(from) )
	from = search(oaInventory, from);
    if ( objectp(to) )
	to = search(oaInventory, to);
    
    ASSERTINFO(from >= 0 && from < sz && to >= 0 && to < sz,
	       "False position for inventory swapping !");
    if ( from == to ) return true;
    object from_obj = oaInventory[from];
    object to_obj   = oaInventory[to];
    oaInventory[from] = to_obj;
    oaInventory[to]   = from_obj;
    require_save(STORE_CONTAINER, UNDEFINED, SAVE_ORDER);
    return true;
}

/**
 * Changes the order of the inventory by passing an order array,
 * the standard pike sort function is used for this and sorts
 * the array the same way order is sorted (integer values, by numbers).
 *  
 * @param array order - the sorting order.
 * @return whether sorting was successfull or not.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool order_inventory(array order)
{
  int size = sizeof( oaInventory );
  ASSERTINFO( sizeof(order) == size, "Size of order array does not match !" );
  
  array sorter = allocate( size );
  for ( int i=0; i<size; i++ ) {
    if ( order[i] != i ) sorter[ (int)order[i] ] = i;
    else sorter[i] = i;
  }
  sort(sorter, oaInventory);
  require_save(STORE_CONTAINER, UNDEFINED, SAVE_ORDER);
  return true;
}

bool order_inventory_objects ( array objects )
{
  if ( !arrayp(objects) )
    THROW( "Not an array !", E_ERROR );
  array old_indices = ({ });
  array tmp_objects = ({ });
  foreach ( objects, mixed obj ) {
    if ( !objectp(obj) ) catch( obj = find_object( (int)obj ) );
    if ( !objectp(obj) )
      THROW( "Invalid object/id !", E_ERROR );
    int index = search( oaInventory, obj );
    if ( index < 0 )
      THROW( sprintf( "Object %d not in inventory !", obj->get_object_id() ),
             E_ERROR );
    old_indices += ({ index });
    tmp_objects += ({ obj });
  }
  array new_indices = sort( old_indices );
  for ( int i=0; i<sizeof(old_indices); i++ )
    oaInventory[ new_indices[i] ] = tmp_objects[i];
  require_save(STORE_CONTAINER, UNDEFINED, SAVE_ORDER);
  return true;
}

/**
 * Get an object by its name from the inventory of this Container.
 *  
 * @param string obj_name - the object to get
 * @return 0|object found by the given name
 * @see get_inventory
 * @see get_inventory_by_class
 */
object get_object_byname(string obj_name, object|void o)
{
    oaInventory -= ({ 0 });

    if ( !stringp(obj_name) )
        return 0;
    
    foreach ( oaInventory, object obj ) {
	if ( objectp(o) && o == obj ) continue;
	    
	obj = obj->get_object();
	if ( !objectp(obj) ) continue;
	if ( obj->get_object_class() & CLASS_USER )
	    continue; // skip user objects
	if (functionp(obj->get_identifier) && obj_name==obj->get_identifier())
	    return obj->this();
    }
    return 0;
}

bool contains(object obj, bool rec)
{
  if ( search(oaInventory, obj) >= 0 )
    return true;
  if ( rec ) {
    foreach(oaInventory, object o) {
      if ( objectp(o) && o->get_object_class() & CLASS_CONTAINER )
	if ( o->contains(obj, true) )
	  return true;
    }
  }
  return false;    
}

/**
 * Get the users present in this Room. There shouldnt be any User
 * inside a Container.
 *  
 * @return array(object) of users.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
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

void lowAppendXML(object rootNode, void|int depth)
{
  ::lowAppendXML(rootNode, depth);
  if ( depth > 0 ) {
    foreach(oaInventory, object o) {
      if ( objectp(o) ) {
	object objNode = xslt.Node("Object", ([ ]));
	rootNode->add_child(objNode);
	o->lowAppendXML(objNode, depth-1);
      }
    }
  }
}

/**
 * Get the object class of Container.
 *  
 * @return the object class of container. Check with CLASS_CONTAINER.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int get_object_class()
{
    return ::get_object_class() | CLASS_CONTAINER;
}

/**
 * Is this an object ? yes!
 *  
 * @return true
 */
final bool is_container() { return true; }


string describe()
{
    return get_identifier()+"(#"+get_object_id()+","+
	master()->describe_program(object_program(this_object()))+","+
	get_object_class()+","+sizeof(oaInventory)+" objects)";
}


