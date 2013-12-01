/* Copyright (C) 2000-2007  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: Object.pike,v 1.9 2010/10/08 14:45:56 nicke Exp $
 */

constant cvs_version="$Id: Object.pike,v 1.9 2010/10/08 14:45:56 nicke Exp $";


//! Each Object in sTeam is derived from this class


inherit "/base/access"       : __access;
inherit "/base/events"       : __events;
inherit "/base/annotateable" : __annotateable;
inherit "/base/decorateable" : __decorateable;
inherit "/base/references"   : __references;

#include <macros.h>
#include <attributes.h>
#include <classes.h>
#include <access.h>
#include <events.h>
#include <assert.h>
#include <functions.h>
#include <database.h>
#include <types.h>

private static  mapping        mAttributes; /* attribute mapping of object */
private static  mapping mAttributesAcquire;
private static  mapping  mAttributesLocked;

static  int              iObjectID; /* Database ID of object */
static  object        oEnvironment; /* the environment of the object */
private object              oProxy; /* the corresponding pointer object */
static  string         sIdentifier; /* the identifier of the object */
private static function  fGetEvent; /* cache function to get event for attr */
private static bool       __loaded; /* true if object is loaded */
static array     aDependingObjects; /* objects that depend on this object */
static array          aDependingOn; /* objects that this object depends on */


mixed set_attribute(string index, mixed data);

/**
 * create_object() is the real constructor, not called when object is loaded
 *  
 * @see create
 */
static void create_object()
{
}

/**
 * Called after the object was created. Then calls create_object() which 
 * actually is the function to be overwritten.
 *
 * @see create
 * @see create_object
 */
final void created()
{
    object caller = MCALLER;
    if ( caller != _Database && 
         caller != _Server && 
         caller != _Persistence && 
	 !(get_object_class() & CLASS_FACTORY) &&
	 !_Server->is_factory(caller) &&
	 !_SECURITY->access_create_object(0, caller) ) 
    {
	FATAL("Calling object is not a factory !");
	THROW("Security violation while creating object", E_ACCESS);
    }
    create_object();
    load_object();
}


/**
 * init the object, called when object is constructed _and_ loaded
 * Notice during this function, the object ID of the object is not yet
 * valid. See load_object for a function that will be called after the
 * object id is valid.
 *
 * @see create
 * @see load_object
 */
static void 
init()
{
    init_events();
    init_access();
    init_annotations();
    init_decorations();
    init_references();

    add_data_storage(STORE_DECORATIONS,retrieve_decorations, restore_decorations);
    add_data_storage(STORE_ACCESS,retrieve_access_data, restore_access_data, 1);
    add_data_storage(STORE_ATTRIB,retrieve_attr_data, restore_attr_data, 1);
    add_data_storage(STORE_DATA, retrieve_data, restore_data, 1);
    add_data_storage(STORE_EVENTS,retrieve_events, restore_events);
    add_data_storage(STORE_ANNOTS,retrieve_annotations, restore_annotations);
    add_data_storage(STORE_REFS,store_references, restore_references);
}

/**
 * Called after the Database has loaded the object data.
 *  
 * @see loaded
 */
static void load_object()
{
}


/**
 * Database calls this function after loading an object.
 *  
 * @see upgrade
 * @see init
 */
final void loaded()
{
    if ( CALLER != _Database && CALLER != _Server && CALLER != _Persistence )
	THROW("Illegal Call to loaded() !", E_ACCESS);
    __loaded = true;
    load_object();
    object factory = _Server->get_factory(get_object_class());
    if ( objectp(factory) )
      factory->check_attributes(this());
    foreach ( aDecorations, string decoration_path ) {
      mixed err = catch( register_decoration( decoration_path ) );
      if ( err )
        werror( "Could not register decoration %s while loading %d : %s\n%O\n",
                decoration_path, get_object_id(), err[0], err[1] );
    }
}


private bool register_decoration ( string path )
{
  object deco = load_decoration( path );
  if ( !objectp(deco) ) return false;
  deco->register_attribute_functions( do_set_attribute, do_query_attribute );
  this()->set_decoration_object( path, deco );
  return true;
}


private void unregister_decoration ( string path )
{
  this()->set_decoration_object( path );
}


final bool is_loaded() { return __loaded; }


/**
 * See if this object can be dropped (swapping)
 *  
 * @return can this object be swapped out or not.
 */
bool check_swap() { return true; }
bool check_upgrade() { return true; }


/**
 * Master calls this function in each instance when the class is upgraded.
 *  
 */
void upgrade()
{
}  


/** 
 * This is the constructor of the object.
 *
 * @param string|object id - the name of the object if just created,
 *                           or the proxy 
 */
final static void 
create(string|object id, void|mapping attributes)
{
    object caller = MCALLER;
    if ( caller != _Database && caller != _Server && caller != _Persistence &&
	 !(get_object_class() & CLASS_FACTORY) &&!_Server->is_factory(caller) &&
	 !_SECURITY->access_create_object(0, caller) ) 
    {
	FATAL("-- Calling object is not a factory ! - aborting creation!");
	THROW("Security violation while creating object", E_ACCESS);
    }

    if ( mappingp(attributes) )
      mAttributes = copy_value(attributes);
    else
      mAttributes        = ([ ]);
    mAttributesAcquire = ([ ]);
    mAttributesLocked  = ([ ]);

    init();

    if ( objectp(id) ) { // object is newly loaded
	oProxy = id;
	iObjectID = oProxy->get_object_id();
	sIdentifier = "object";
    }
    else 
    {
        [ iObjectID, oProxy ] = _Persistence->new_object(id);
	__loaded = true;
	sIdentifier = id;
	database_registration(id);
    }
}      

/**
 * Save the object. This call is delegated to the Database singleton.
 *  
 */
static void require_save(void|string ident, void|string index, void|int action, void|array args)
{
    _Persistence->require_save(ident, index);
    if (stringp(index) && index != DOC_LAST_ACCESSED) {
      mAttributes[OBJ_LAST_CHANGED] =  time();
      _Persistence->require_save(STORE_ATTRIB, OBJ_LAST_CHANGED);
    }
}

object duplicate(void|mapping vars)
{
  mapping duplicates = do_duplicate(vars);
  foreach(values(duplicates), object dup) {
    dup->fix_references(duplicates);
  }
  return duplicates[this()];
}

static mapping do_fix_references(mapping duplications, mixed val)
{
  mapping result = ([ "val": 0, "fixed": 0, ]);
  if ( arrayp(val) ) {
    result->val = ({ });
    foreach ( val, mixed v ) {
      mapping res = do_fix_references(duplications, v);
      result->val += ({ res->val });
      result->fixed |= res->fixed;
    }
  }
  else if ( mappingp(val) ) {
    result->val = ([ ]);
    foreach(indices(val), mixed v) {
      mapping res = do_fix_references(duplications, val[v]);
      result->val[v] = res->val;
      result->fixed |= res->fixed;
    }
  }
  else if ( objectp(val) ) {
    if ( objectp(duplications[val]) ) {
      result->fixed = 1;
      result->val = duplications[val];
    }
  }
  return result;
}

void fix_references(mapping duplications)
{
  if ( !_SECURITY->access_write(0, this(), CALLER) )
    THROW("Security Violation", E_ACCESS);
  
  mapping attr = copy_value(mAttributes);

  foreach(indices(attr), mixed key) {
    mapping result = do_fix_references(duplications, attr[key]);
    if ( result->fixed ) {
      do_set_attribute(key, result->val);
    }
  }
}

/**
 * Duplicate an object - that is create a copy, the permisions are
 * not copied though.
 *  
 * @return the copy of this object
 * @see create
 */
mapping do_duplicate(void|mapping vars)
{
  try_event(EVENT_DUPLICATE, CALLER);
  object factory = _Server->get_factory(get_object_class());
  mapping attr = copy_value(mAttributes);
  array keys = indices(attr);
  foreach(keys, mixed idx) {
    if ( mAttributesAcquire[idx] != 0 )
      m_delete(attr, idx);
  }
  m_delete(attr, DOC_VERSIONS);
  m_delete(attr, DOC_VERSION);
  m_delete(attr, OBJ_VERSIONOF);
  m_delete(attr, OBJ_LOCK); // get rid of locks in copy
  
  if ( mappingp(vars) && !zero_type(vars["version_of"]) )
    attr[OBJ_VERSIONOF] = vars["version_of"];
  
  mapping exec_vars = 
    ([ "name": do_query_attribute(OBJ_NAME), 
       "attributes":attr, 
       "attributesAcquired": mAttributesAcquire,
       "attributesLocked": mAttributesLocked, ]);
  if ( mappingp(vars) )
    exec_vars += vars;
  if ( !stringp(exec_vars->name) || exec_vars->name == "" )
    exec_vars->name = "Copy of " + get_object_id();
  
  
  object dup_obj = factory->execute( exec_vars );
  mapping duplicates = dup_obj->copy(this(), vars);

  mapping dup_depending_objects = ([ ]);
  foreach ( get_depending_objects(), object dep ) {
    dup_depending_objects |= dep->do_duplicate( vars );
  }
  foreach ( values(dup_depending_objects), object dep ) {
    dup_obj->add_depending_object( dep );
  }
  duplicates |= dup_depending_objects;
  
  run_event(EVENT_DUPLICATE, CALLER);
  duplicates[this()] = dup_obj;
  return duplicates;;
}

mapping copy(object obj, mapping vars)
{
  mapping copies = ([ ]);
  foreach ( obj->get_annotations(), object ann ) {
    mapping copied;
    catch(copied = ann->do_duplicate());
    object dup_ann = copied[ann];
    if ( objectp(dup_ann) ) {
      __annotateable::add_annotation(dup_ann);
      dup_ann->add_reference(this());
      dup_ann->set_acquire(this());
    }
    copies |= copied;
  }
  return copies;
}


/**
 * currently no idea what this function is good for ... maybe comment
 * directly when writing the code ?
 *  
 */
static void database_registration(string name)
{
}

/**
 * This is the destructor of the object - the object will be swapped out.
 *  
 * @see delete_object
 */
final void
destroy()
{
}

static final void do_lock_attribute(int|string key)
{
  mAttributesLocked[key] = true;
  require_save(STORE_DATA);
}

/**
 * Set the event for a specific attribute.
 *  
 * @param key - the key of the attribute
 * @see set_attribute
 */
final void 
lock_attribute(int|string key)
{
    try_event(EVENT_ATTRIBUTES_LOCK, CALLER, key, true);
    do_lock_attribute(key);
    run_event(EVENT_ATTRIBUTES_LOCK, CALLER, key, true);
}

/**
 * Unlock all attributes. 
 *  
 * @see lock_attribute
 */
final void unlock_attributes()
{
    try_event(EVENT_ATTRIBUTES_LOCK, CALLER, 0, false);
    mAttributesLocked = ([ ]);
    run_event(EVENT_ATTRIBUTES_LOCK, CALLER, 0, false);    
    require_save(STORE_DATA);
}


static void do_unlock_attribute(string key)
{
   m_delete(mAttributesLocked, key);
   require_save(STORE_DATA);
}

/**
 * Set the event for a specific attribute.
 *  
 * @param key - the key of the attribute
 * @see set_attribute
 */
final void 
unlock_attribute(string key)
{
    try_event(EVENT_ATTRIBUTES_LOCK, CALLER, key, false);
    do_unlock_attribute(key);
    run_event(EVENT_ATTRIBUTES_LOCK, CALLER, key, false);
}

/**
 * Returns whether an attribute is locked or not. Attributes can be locked
 * to keep people from moving objects around (for example coordinates)
 *  
 * @param mixed key - the attribute key to check
 * @return locked or not
 */
bool is_locked(mixed key)
{
    return mAttributesLocked[key];
}

/**
 * Returns an array containing all locked attributes
 *
 * @return locked attributes as array
 */
array get_locked_attributes() 
{   
    array locked_attributes = ({});
    array locked_keys = indices(mAttributesLocked);
    foreach (locked_keys, string key) {
        if (mAttributesLocked[key]) {
            locked_attributes += ({key});
        }
    }
    return locked_attributes;
}


/**
 * Each attribute might cause a different event to be fired, get
 * the one for changing the attribute.
 *  
 * @param int|string key - the attribute key
 * @return the corresponding event 
 * @see get_attributes_read_event
 */
int get_attributes_change_event(int|string key)
{
   object factory = _Server->get_factory(get_object_class());
   if ( objectp(factory) )
       return factory->get_attributes_change_event(key);
    return EVENT_ATTRIBUTES_CHANGE;
}

/**
 * Each attribute might cause a different event to be fired, get
 * the one for reading the attribute.
 *  
 * @param int|string key - the attribute key
 * @return the corresponding event 
 * @see get_attributes_read_event
 */
int get_attributes_read_event(int|string key)
{
    if ( !functionp(fGetEvent) ) {
        object factory = _Server->get_factory(get_object_class());
        if ( objectp(factory) ) {
   	    fGetEvent = factory->get_attributes_read_event;
            return fGetEvent(key);
        }
        return 0;
    }
    else
        return fGetEvent(key);
}

/**
 * Get the mapping of all registered attributes. That is only the
 * descriptions, permissions, type registration of the attributes.
 *  
 * @return mapping of all registered attributes
 * @see describe_attribute
 */
mapping describe_attributes()
{
    object factory = _Server->get_factory(get_object_class());
    mapping attributes = factory->get_attributes();
    foreach(indices(mAttributes)+indices(mAttributesAcquire), mixed attr) {
	if ( !attributes[attr] )
	    attributes[attr] = ([
	      "type": CMD_TYPE_UNKNOWN, 
	      "key": (string)attr, 
	      "description": "",
	      "eventRead": 0,
	      "acquire": 0,
	      "eventWrite": EVENT_ATTRIBUTES_CHANGE, 
	      "control": CONTROL_ATTR_USER
	      ]);
    }
    return attributes;
}

mapping get_attributes() 
{
  return describe_attributes();
}

/**
 * Get the mapping of acquired Attributes.
 *  
 * @return Mapping of acquired attributes (copy of the mapping of course)
 */
mapping get_acquired_attributes()
{
    return copy_value(mAttributesAcquire);
}

/**
 * Get the names of all attributes used in the object. Regardless if 
 * they are registered or not.
 *
 * @param   none
 * @return  list of names
 * @see get_attributes
 */
array get_attribute_names()
{
    return indices(mAttributes);
}
/**
 * Describe an attribute - call the factory of this class for it.
 * It will return an array of registration data.
 *  
 * @param mixed key - the attribute to describe
 * @return array of registration data - check attributes.h for it.
 */
array describe_attribute(mixed key)
{
    object factory = _Server->get_factory(this_object());
    return factory->describe_attribute(key);
}

/**
 * Check before setting an attribute. This include security checks
 * and finding out if the type of data matches the registered type.
 *  
 * @param mixed key - the attribute key 
 * @param mixed data - the new value for the attribute
 * @return true|throws exception 
 * @see set_attribute 
 */
static bool check_set_attribute(string key, mixed data)
{
    if ( intp(key) || arrayp(key) || mappingp(key) )
      steam_error("Wrong key for Attribute '"+key+"'");

    if ( mappingp(mAttributesLocked) && mAttributesLocked[key] )
	THROW("Trying to set locked attribute '"+key+" ' in '"+
	      get_identifier()+ "' !", E_ACCESS);
    
    // check only with real objects and no factory involved whatsoever
    object factory = _Server->get_factory(this_object());
    if ( factory == CALLER || get_object_class() & CLASS_FACTORY )
	return true;
    if ( objectp(factory) ) 
	return factory->check_attribute(key, data);
    return true;
}

/**
 * This function is called when an attribute is changed in the object, 
 * that acquires an attribute from this object.
 *  
 * @param object o - the object where an attribute was changed
 * @param key - the key of the attribute
 * @param val - the new value of the attribute
 * @return false will make the acquire set to none in the calling object
 */
bool keep_acquire(object o, mixed key, mixed val)
{
    return false; // nothing is acquired from the object anymore
}

/** 
 * Sets a single attribute of an object. This function checks for acquiring
 * and possible sets the attribute in the object acquired from.
 *
 * @param index - what attribute
 * @param data - data of that attribute
 * @return successfully or not, check attributes.h for possible results
 * @see query_attribute
 **/
static bool do_set_attribute(string index, mixed|void data)
{
    object|function acquire;
    
    acquire = mAttributesAcquire[index];
    /* setting attributes removes acquiring settings */
    if ( functionp(acquire) ) acquire = acquire();
    if ( objectp(acquire) ) {
	/* if the attribute was changed in the acquired object we should
	 * get information about it too */
	bool acq = acquire->keep_acquire(this(), index, data);
	if ( acq ) {
	    acquire->set_attribute(index, data);
	    if ( index == OBJ_NAME )
		set_identifier(data);
	    return data;
	}
	else {
	    // set acquire to zero
	    mAttributesAcquire[index] = 0;
            require_save(STORE_DATA);
	}
    }

    /* OBJ_NAME requires speccial actions: the identifier (sIdentifier) must
     * be unique inside the objects current environment */
    if ( index == OBJ_NAME ) 
	set_identifier(data); 
    
    if ( zero_type(data) )
	m_delete(mAttributes, index);
    else
	mAttributes[index] = copy_value(data);
    
    /* Database needs to save changes sometimes */
    require_save(STORE_ATTRIB, index); 
    return true;
}

/**
 * Set an attribute <u>key</u> to new value <u>data</u>. 
 *  
 * @param mixed key - the key of the attribute to change. 
 * @param mixed data - the new value for that attribute.
 * @return the new value of the attribute | throws and exception 
 * @see query_attribute
 */
mixed set_attribute(string key, void|mixed data)
{
    check_set_attribute(key, data);
    mixed oldval = do_query_attribute(key);
    
    try_event(get_attributes_change_event(key), CALLER, ([ key:data ]),
	      ([ key: oldval ]) );

    do_set_attribute(key, data);
    run_event(get_attributes_change_event(key), CALLER, ([ key:data ]), 
	      ([ key: oldval ]) );
    return data;
}

int arrange(float x, float y)
{
    try_event(EVENT_ARRANGE_OBJECT, CALLER, 
	      ([ OBJ_POSITION_X: x, OBJ_POSITION_Y: y, ]) );
    do_set_attribute(OBJ_POSITION_X, x);
    do_set_attribute(OBJ_POSITION_Y, y);
    run_event(EVENT_ARRANGE_OBJECT, CALLER, 
	      ([ OBJ_POSITION_X: x, OBJ_POSITION_Y: y, ]) );
}

static mixed do_append_attribute(string key, mixed data)
{
    array val = do_query_attribute(key);
    if ( mappingp(data) ) {
	if ( mappingp(val) )
	    return do_set_attribute(key, data + val);
    }
    if ( zero_type(val) || val == 0 )
	val = ({ });
    if ( !arrayp(data) ) {
	if ( search(val, data) >= 0 )
	    return val;
	data = ({ data });
    }
    return do_set_attribute(key, data + val);
    THROW("Can only append arrays on attributes !", E_ERROR);
}

static mixed remove_from_attribute(string key, mixed data)
{
    mixed val = do_query_attribute(key);
    if ( arrayp(val) ) {
	if ( search(val, data) >= 0 ) {
	    return do_set_attribute(key, val - ({ data }));
	}
    }
    else if ( mappingp(val) ) {
	m_delete(val, data);
	return do_set_attribute(key, val);
    }
    return val;
}


/**
 * Sets a number of attributes. The format is 
 * attr = ([ key1:val1, key2:val2,...]) and the function calls set_attribute
 * for each key.
 *  
 * @param mapping attr - the attribute mapping. 
 * @return true | throws exception 
 * @see set_attribute 
 */
bool set_attributes(mapping attr)
{
    int                 event;
    mapping eventAttr = ([ ]);
    mapping oldAttr   = ([ ]);
    
    foreach(indices(attr), mixed key) {
	check_set_attribute(key, attr[key]);
	event = get_attributes_change_event(key);
	// generate packages for each event that should be fired
	if ( !mappingp(eventAttr[event]) ) 
	    eventAttr[event] = ([ ]);
	if ( !mappingp(oldAttr[event]) )
	    oldAttr[event] = ([ ]);
	eventAttr[event][key] = attr[key];
	oldAttr[event][key] = do_query_attribute(key);
    }
    // each attribute might run a different event, run each event individually
    // if security fails one of this the attribute-setting is canceled
    foreach( indices(eventAttr), event ) 
	try_event(event, CALLER, eventAttr[event], oldAttr[event]);
  
    // now the attributes are really set
    foreach(indices(attr), mixed key) {
	do_set_attribute(key, attr[key]);
    }
   
    // notification about the change, again for each package individually
    foreach( indices(eventAttr), event )
	run_event(event, CALLER, eventAttr[event], oldAttr[event]);

    return true;
}

static void do_set_acquire_attribute(mixed index, void|object|function|int acquire)
{
    object acq;

    // quick and dirty hack, because protocoll cannot send functions
    if ( intp(acquire) && acquire == REG_ACQ_ENVIRONMENT )
      acquire = get_environment;

    if ( functionp(acquire) ) 
	acq = acquire();
    else 
	acq = acquire;
    
    while ( objectp(acq) && acq->status() >= 0 ) {
	if ( functionp(acq->get_object) )
	    acq = acq->get_object();
	if ( acq == this_object() )
	    THROW("Acquire ended up in loop !", E_ERROR);
	acq = acq->get_acquire_attribute(index);
    }

    mAttributesAcquire[index] = acquire;
    require_save(STORE_DATA);
}

/**
 * Set the object to acquire an attribute from. When querying the attribute
 * inside this object the value will actually the one set in the object
 * acquired from. Furthermore when changing the attributes value it
 * will be changed in the acquired object.
 *  
 * @param index - the attribute to set acquiring
 * @param acquire - object or function(object) for acquiring
 * @see set_attribute
 */
void
set_acquire_attribute(mixed index, void|object|function|int acquire)
{
    try_event(EVENT_ATTRIBUTES_ACQUIRE, CALLER, index, acquire);
    // check for possible endless loops

    do_set_acquire_attribute(index, acquire);

    run_event(EVENT_ATTRIBUTES_ACQUIRE, CALLER, index, acquire);
}

/**
 * Retrieve the acquiring status for an attribute.
 *  
 * @param mixed key - the key to get acquiring status for
 * @return function|object of acquiring or 0.
 * @see set_acquire_attribute
 */
object|function get_acquire_attribute(mixed key)
{
    return mAttributesAcquire[key];
}

/** 
 * Get the value of one attribute.
 * 
 * @param mixed key - what attribute to query.
 * @return the value of the queried attribute
 * @see set_attribute
 **/
mixed
query_attribute(mixed key)
{
    mixed val;

    int event = get_attributes_read_event(key);
    if ( event > 0 ) try_event(event, CALLER, key);

    val = do_query_attribute(key);
    
    if ( event > 0 ) run_event(event, CALLER, key );

    return copy_value(val);
}

/**
 * Query an attribute locally. This also follows acquired attributes.
 * No event is run by calling this and local calls wont have security
 * or any blocking event problem.
 *  
 * @param mixed key - the attribute to query.
 * @return value of the queried attribute
 * @see query_attribute
 */
static mixed do_query_attribute(mixed key)
{
    object|function acquire;

    if ( mappingp(mAttributesAcquire) )
      acquire = mAttributesAcquire[key];
    if ( functionp(acquire) ) acquire = acquire();
    
    // if the attribute is acquired from another object query the attribute
    // there.
    if ( objectp(acquire) )
        return acquire->query_attribute(key);
    return mAttributes[key];
}


/**
 * Query the value of a list of attributes. Subsequently call
 * <a href="#query_attribute">query_attribute()</a> 
 * and returns the result as an array or, if a mapping with keys was 
 * given, the result is returned as a mapping key:value
 *  
 * @param array|mapping|void keys - the attributes to query
 * @return the result of the query as elements of an array.
 * @see query_attribute
 */
array(mixed)|mapping
query_attributes(void|array(mixed)|mapping keys)
{
    int               i;
    array(mixed) result;

    function qa = query_attribute;
    
    if ( !arrayp(keys) ) {
      if ( !mappingp(keys) )
	keys = mkmapping(indices(mAttributes), values(mAttributes)) | 
	  mkmapping(indices(mAttributesAcquire), values(mAttributesAcquire));

      if ( mappingp(keys) ) {
	foreach(indices(keys), mixed key) {
	  mixed err = catch {
	    keys[key] = qa(key);
	  };
	  if ( err != 0 )
	    FATAL( "Could not query attribute: %O\n", key );
	}
	return keys;
      }
    }
    result = allocate(sizeof(keys));;
    

    for ( i = sizeof(keys)-1; i >= 0; i-- )
      result[i] = qa(keys[i]);
    return result;
}


/**
 * Set new permission for an object in the acl. Old permissions
 * are overwritten.
 *  
 * @param grp - the group or object to change permissions for
 * @param permission - new permission for this object
 * @return the new permission
 * @see sanction_object_meta
 * @see /base/access.set_sanction
 */
int sanction_object(object grp, int permission)
{
    ASSERTINFO(_SECURITY->valid_proxy(grp), "Sanction on non-proxy!");
    if ( query_sanction(grp) == permission )
      return permission; // if permissions are already fine

    try_event(EVENT_SANCTION, CALLER, grp, permission);
    set_sanction(grp, permission);

    run_event(EVENT_SANCTION, CALLER, grp, permission);
    return permission;
}

/**
 * Sets the new meta permissions for an object. These are permissions
 * that are used for giving away permissions on this object.
 *  
 * @param grp - group or object to sanction
 * @param permission - new meta permission for this object
 * @return the new permission
 * @see sanction_object
 */
int
sanction_object_meta(object grp, int permission)
{
    try_event(EVENT_SANCTION_META, CALLER, grp, permission);
    set_meta_sanction(grp, permission);
    run_event(EVENT_SANCTION_META, CALLER, grp, permission);
    return permission;
}

/**
 * Add an annotation to this object. Each object in steam
 * can be annotated.
 *  
 * @param object ann - the annotation to add
 * @return successfull or not.
 */
bool add_annotation(object ann)
{
    try_event(EVENT_ANNOTATE, CALLER, ann);
    __annotateable::add_annotation(ann);
    do_set_attribute(OBJ_ANNOTATIONS_CHANGED, time());
    ann->add_reference(this());
    run_event(EVENT_ANNOTATE, CALLER, ann);
}

/**
 * Remove an annotation from this object. This only removes
 * it from the list of annotations, but doesnt delete it.
 *  
 * @param object ann - the annotation to remove
 * @return true or false
 * @see add_annotation
 */
bool remove_annotation(object ann)
{
    try_event(EVENT_REMOVE_ANNOTATION, CALLER, ann);
    __annotateable::remove_annotation(ann);
    do_set_attribute(OBJ_ANNOTATIONS_CHANGED, time());
    ann->remove_reference(this());
    run_event(EVENT_REMOVE_ANNOTATION, CALLER, ann);
}

/**
 * Add a decoration to this object. The decoration is identified by a path of
 * the form: "server:/path-in-server-sandbox" or "object:/object-path" or
 * "object:#object-id". An instance of the decoration will be provided and
 * attached to the proxy of this object.
 *  
 * @param string path the path to the decoration source code
 * @return true if the decoration could be successfully added, false if not
 * @see remove_decoration
 */
bool add_decoration ( string path )
{
  try_event( EVENT_DECORATE, CALLER, path );
  if ( ! register_decoration( path ) )
    return false;
  __decorateable::add_decoration( path );
  run_event( EVENT_DECORATE, CALLER, path );
  return true;
}

/**
 * Removes a decoration from the object. This function just removes
 * the decoration path from the list of decorations.
 * 
 * @param string path the decoration path to remove
 * @return true if the decoration was successfully removed, false otherwise
 * @see add_decoration
 */
bool remove_decoration ( string path )
{
  try_event( EVENT_REMOVE_DECORATION, CALLER, path );
  __decorateable::remove_decoration( path );
  unregister_decoration( path );
  run_event( EVENT_REMOVE_DECORATION, CALLER, path );
  return true;
}

/**
 * The persistent id of this object.
 *  
 * @return the ID of the object
 */
final int
get_object_id()
{
    return iObjectID;
}

string
get_etag()
{
  string etag = sprintf("%018x",iObjectID);
  if ( sizeof(etag) > 18 ) etag = etag[(sizeof(etag)-18)..];
  return etag[0..4]+"-"+etag[5..10]+"-"+etag[11..17];
}

/**
 * Is this an object ? yes!
 *  
 * @return true
 */
final bool is_object() { return true; }

/**
 * Sets the object id, but requires privileges in order to be successfull.
 * This actually means the caller has to be the <u>database</u> so this 
 * function is not callable for normal use.
 *  
 * @param id - the new id
 */
final void
set_object_id(int id)
{
    if ( CALLER == _Database && CALLER != _Persistence )
	iObjectID = id;
}

/**
 * Returns a bit array of classes and represent the inherit structure.
 *  
 * @return the class of the object
 */
int get_object_class()
{
    return CLASS_OBJECT;
}

string get_class() 
{
    object factory = _Server->get_factory(get_object_class());
    return factory->get_class_name();
}

/**
 * update the current identifier of the object. This must happen
 * on each movement, because there might be an object of the same
 * name in the new environment.
 *  
 * @see get_identifier
 */
static void 
set_identifier(string name)
{
    string identifier;
    
    if ( !stringp(name) )
      name = "* unknown *";

    identifier = replace(name, "/", "_");

    if ( identifier == sIdentifier )
      return;
    
    object env = get_environment();
    if ( objectp(env) ) {
      object other = env->get_object_byname(identifier,this());
      if ( objectp(other) && other != this() ) {
	identifier = get_object_id() + "__" + identifier;
      }
    }
    sIdentifier = identifier;
    require_save(STORE_DATA);
    update_path();
      
    return;    
}

void update_identifier() 
{
  object env = get_environment();
  if ( ! objectp(env) ) return;
  object oo = env->get_object_byname(sIdentifier,this());
  if ( objectp(env) && objectp(oo) ) {
    set_identifier(get_object_id()+"__"+sIdentifier);
  }
}

void update_path()
{
  if ( _FILEPATH && objectp(this())) {
    do_set_attribute(OBJ_PATH, _FILEPATH->object_to_filename(this(), 1));
    foreach(get_annotations(), object ann) { 
      if (objectp(ann))
	catch(ann->update_path());
    }
  }
}


/**
 * Moves the object to a destination, which requires move permission.
 *  
 * @param dest - the destination of the move operation
 * @return move successfull or throws an exception 
 */
bool move(object dest)
{
    mixed err;

    if ( !objectp(dest) ) {
      try_event(EVENT_MOVE, CALLER, oEnvironment, dest);
      
      /* first remove object from its current environment */
      if ( objectp(oEnvironment) && oEnvironment->status() >= 0 ) {
	if ( !oEnvironment->remove_obj(this()) )
	  THROW("failed to remove object from environment !",E_ERROR|E_MOVE);
      } 
      // finally set objects new environment 
      oEnvironment = 0;
      update_path();
      run_event(EVENT_MOVE, CALLER, oEnvironment, dest);
      
      return true;
    }

    ASSERTINFO(IS_PROXY(dest), "Destination is not a proxy object !");

    /* Moving into an exit takes the exits location as destination */
    if ( dest->get_object_class() & CLASS_EXIT ) 
	dest = dest->get_exit();
    
    if ( dest->get_environment() == this() || dest == this() ) 
	THROW("Moving object inside itself !", E_ERROR|E_MOVE);
    if ( !(dest->get_object_class() & CLASS_CONTAINER) )
       THROW("Failed to move object into non-container!", E_ERROR|E_MOVE);

    if ( dest->this() == oEnvironment && oEnvironment->contains(this()) ) 
	return true;
    
    try_event(EVENT_MOVE, CALLER, oEnvironment, dest);

    /* first remove object from its current environment */
    if ( objectp(oEnvironment) && oEnvironment->status() >= 0 ) {
	if ( !oEnvironment->remove_obj(this()) )
	    THROW("failed to remove object from environment !",E_ERROR|E_MOVE);
    }
    /* then insert object into new environment */
    err = catch(dest->insert_obj(this()));
    if ( err != 0 ) {
	if ( objectp(oEnvironment) ) /* prevent object from being in void */
	  oEnvironment->insert_obj(this());
        throw(err);
    }
    // finally set objects new environment 
    run_event(EVENT_MOVE, CALLER, oEnvironment, dest);
    oEnvironment = dest;
    update_path();
    
    require_save(STORE_DATA);
    
    // now check for name and rename other object
    update_identifier();
    
    return true;
}
 
/**
 * Get the environment of this object.
 *
 * @see get_root_environment
 *  
 * @return environment of the object
 * @see move
 */
public object get_environment()
{
  return oEnvironment;
}

/**
 * Get the root environment of this object by recursively going through the
 * environments until one without environment is reached. If this object has
 * no environment, then the object itself will be returned.
 * This function will not pass through user objects into the environment of
 * a user unless explicitly ordered to do so. Otherwise it will stop if it
 * encounters a user object and return it (meaning the root environment is the
 * user's rucksack).
 *
 * @see get_environment
 *
 * @param pass_through_users if 1 then this function will pass through user
 *   objects and continue into the room a user is in. If 0 then it will stop
 *   when it encounters a user, thus returning the user object (rucksack) as
 *   the root environemnt.
 * @return root environment of the object, or the object itself if it has no
 *   environment
 */
public object get_root_environment( int|void pass_through_users )
{
  object env;
  object tmp_env = this();
  while ( objectp(tmp_env) ) {
    if ( !pass_through_users &&
         tmp_env->get_object_class() & CLASS_USER ) return tmp_env;
    env = tmp_env;
    tmp_env = env->get_environment();
  }
  return env;
}

/**
 * Unserialize data of the object. Called when Database loads the object
 *  
 * @param str - the serialized object data
 * @see unserialize_access
 * @see retrieve_data
 */
final void 
restore_data(mixed data, string|void index)
{
    if ( CALLER != _Database )
	THROW("Invalid call to restore_data()", E_ACCESS);

    if (index) {
        switch(index) {
          case "AttributesLocked" : mAttributesLocked = data; break;
          case "AttributesAcquire" : mAttributesAcquire = data; break;
          case "Environment" : oEnvironment = data; break;
          case "identifier" : sIdentifier = data; break;
          case "DependingObjects" : aDependingObjects = data; break;
          case "DependingOn" : aDependingOn = data; break;
        }
    }
    else
    {
      if ( mappingp(data->AttributesLocked) )
	mAttributesLocked  = data["AttributesLocked"];
      if ( mappingp(data->AttributesAcquire) )
	mAttributesAcquire = data["AttributesAcquire"];
      if ( arrayp(data->DependingObjects) )
        aDependingObjects = data["DependingObjects"];
      if ( arrayp(data->DependingOn) )
        aDependingOn = data["DependingOn"];

      oEnvironment       = data["Environment"];
      sIdentifier        = data["identifier"];
    }
}

/**
 * Unserialize data of the object. Called when Database loads the object
 *  
 * @param str - the serialized object data
 * @see retrieve_attr_data
 */
final void
restore_attr_data(mixed data, string|void index)
{
    if ( CALLER != _Database )
	THROW("Invalid call to restore_attr_data()", E_ACCESS);
    if (!zero_type(index))
    {
      if (index==OBJ_NAME) {
	if ( !stringp(data) )
	  data = "";
      }
      mAttributes[index] = data;

    }
    else if ( mappingp(data) ) {
        mAttributes = data;
    }
    else {
      FATAL("Failed to restore Attribute data in %d (data=%O)",
	    get_object_id(),
	    data);
    }
}

/**
 * serialize data of the object. Called by the Database object to save
 * the objects varibales into the Database.
 *  
 * @return the Variables of the object to be stored into database.
 * @see restore_data
 */
final mixed
retrieve_data(string|void index)
{
    if ( CALLER != _Database )
	THROW("Invalid call to retrieve_data()", E_ACCESS);

    if (zero_type(index))
    {
        return ([ 
            "identifier": sIdentifier,
            //"Attributes":mAttributes, 
            "AttributesLocked":mAttributesLocked,
            "AttributesAcquire":mAttributesAcquire,
            "Environment":oEnvironment,
            "DependingObjects":aDependingObjects,
            "DependingOn":aDependingOn,
	]);
    } else {
        switch(index) {
          case "identifier": return sIdentifier;
          case "AttributesLocked": return mAttributesLocked;
          case "AttributesAcquire": return mAttributesAcquire;
          case "Environment": return oEnvironment;
          case "DependingObjects": return aDependingObjects;
          case "DependingOn": return aDependingOn;
        }
    }
}


/**
 * serialize data of the object. Called by the Database object to save
 * the objects varibales into the Database.
 * This callback is registered as indexed data_storage
 *  
 * @return mixed - single attribute if index is given 
 *                 full attribute data otherwise
 *
 * @see restore_data
 */
final mixed
retrieve_attr_data(string|void index)
{
    if ( CALLER != _Database )
	THROW("Invalid call to retrieve_data()", E_ACCESS);
    if (zero_type(index))
        return mAttributes;
    else
        return mAttributes[index];
}

/**
 * returns the proxy object for this object, the proxy is set 
 * when the object is created.
 *  
 * @return the proxy object of this object
 * @see create
 */
object
this()
{
    return oProxy;
}

/**
 * trusted object mechanism - checks if an object is trusted by this object
 *  
 * @param object obj - is the object trusted
 * @return if the object is trustedd or not. 
 */
bool trust(object obj)
{
    if ( obj == oProxy )
	return true;
    return false;
}

/**
 * This function is called by delete to delete this object.
 *  
 * @see delete
 */
static void
delete_object()
{
    if ( objectp(oEnvironment) ) {
      if (!oEnvironment->remove_obj(this())) {
	FATAL("Failed to remove object from environment when deleting %O",
	      this());
      }
    }

    mixed err;
    err = catch {
	remove_all_annotations();
    };

    // delete all objects that dpend on this object:
    mixed deps = get_depending_objects();
    if ( arrayp(deps) ) {
      foreach ( deps, mixed dep ) {
        if ( !objectp(dep) ) continue;
        err = catch {
          if ( !dep->delete() )
            FATAL("Failed to delete %O (which depended on %O)", dep, this());
        };
        if ( err )
          FATAL("Failed to delete %O (which depends on %O): %O\n%O", dep,
                this(), err[0], err[1]);
      }
    }
    // remove this object from the depending objects list of the objects it
    // depends on:
    deps = get_depending_on();
    if ( arrayp(deps) ) {
      foreach ( deps, mixed dep ) {
        if ( !objectp(dep) ) continue;
        if ( err = catch( dep->remove_depending_object( this() ) ) )
          FATAL("Failed to unregister depending object on delete: %O (which "
                + "depends on %O)", dep, this());
      }
    }
    catch(this()->set_status(PSTAT_DELETED));
}

/**
 * Call this function to delete this object. Of course this requires 
 * write permissions.
 *  
 * @see destroy
 * @see delete_object
 */
final bool
delete()
{
    // delete this object:
    try_event(EVENT_DELETE, CALLER);
    delete_object();
    run_event(EVENT_DELETE, CALLER);
    oEnvironment = 0;
    _Persistence->delete_object(this());
    object temp = get_module("temp_objects");
    if ( objectp(temp) )
	temp->queued_destruct();
    else
	destruct(this_object());
    return true;
}

/**
 * non-documents have no content, see pike:file_stat() for sizes of 
 * directories, etc.
 *  
 * @return the content size of an object
 * @see stat
 */
int 
get_content_size()
{
    return 0;
}

/**
 * Returns the id of the content inside the Database.
 *  
 * @return the content-id inside database
 */
final int get_content_id()
{
    return 0;
}


/**
 * get the identifier of an object, this is the unique name inside 
 * the current environment of the object
 *  
 * @return the unique name
 * @see update_identifier
 */
string
get_identifier()
{
  if ( !stringp(sIdentifier) )
    return do_query_attribute(OBJ_NAME) || "";
  return sIdentifier;
}

/**
 * file stat information about the object
 *  
 * @return the information like in file_stat() 
 */
array stat()
{
    return ({ 33261, get_content_size(), 
		  mAttributes[OBJ_CREATION_TIME], time(), time(),
		  (objectp(get_creator()) ? 
		   get_creator()->get_object_id():0),
		  0,
		  "application/x-unknown-content-type", });
}

/**
 * Database is allowed to get any function pointer (for restoring object data)
 * and is the only object allowed to call this function.
 *  
 * @param string func - the function to get the pointer to.
 * @return the functionp to func
 * @see is_function 
 */
function get_function(string func)
{
    object caller = CALLER;

    if ( caller != _Database && !_Server->is_a_factory(caller) )
      throw(sprintf("Only database is allowed to get function pointer. NOT %O", caller));
    
    switch(func) {
    case "do_set_acquire_attribute":
      return do_set_acquire_attribute;
    case "do_set_attribute":
      return do_set_attribute;
    case "do_sanction_object":
      return set_sanction;
    case "do_lock_attribute":
      return do_lock_attribute;
    case "do_unlock_attribute":
      return do_unlock_attribute;
    case "do_sanction_object_meta":
      return set_meta_sanction;
    }
    
    return this_object()[func];
}


object get_icon()
{
    return query_attribute(OBJ_ICON);
}

/**
 * Find out if a given function is present inside this object.
 *  
 * @param string func - the function to find out about. 
 * @return is the function present ? 
 * @see get_function 
 */
bool is_function(string func)
{
    return functionp(this_object()[func]);
}

void test()
{
    object factory = get_factory(CLASS_DOCUMENT);

    // attribute testing
    set_attribute("objtest", "hello");
    Test.test( "setting attribute",
               do_query_attribute("objtest") == "hello" );

    Test.test( "acquire to self throws", 
               catch(set_acquire_attribute("objtest", this())) );

    // depending objects test
    object obj1 = factory->execute( ([ "name":"obj_for_deps", "mimetype":"text/plain" ]) );
    object obj2 = factory->execute( ([ "name":"dep_obj_1", "mimetype":"text/plain" ]) );
    object obj3 = factory->execute( ([ "name":"dep_obj_2", "mimetype":"text/plain" ]) );
    obj1->add_depending_object( obj2 );
    obj1->add_depending_object( obj3 );
    Test.test( "adding depending object",
               search(obj1->get_depending_objects(), obj2)>=0
               && search(obj2->get_depending_on(), obj1)>=0 );
    obj1->remove_depending_object( obj2 );
    Test.test( "removing depending object",
               search(obj1->get_depending_objects(), obj2)<0
               && search(obj2->get_depending_on(), obj1)<0 );
    obj1->add_depending_object( obj2 );
    Test.test( "re-adding depending object",
               search(obj1->get_depending_objects(), obj2)>=0
               && search(obj2->get_depending_on(), obj1)>=0 );

    obj2->delete();
    Test.test( "deleting depending object", search(obj1->get_depending_objects(), obj2)<0 );
    obj1->delete();
    Test.test( "deleting object that others depended on",
               (!objectp(obj1) || obj1->status()==PSTAT_DELETED)
               && (!objectp(obj3) || obj3->status()==PSTAT_DELETED) );
    if ( objectp(obj3) ) obj3->delete();

    // sanction test, access
    object steam = GROUP("steam");
    if ( !objectp(steam) )
	steam_error("Something seriously wrong - no steam group !");
    int val = sanction_object(steam, SANCTION_EXECUTE);
    Test.test( "sanction", (val & SANCTION_EXECUTE) );

    // annotations
    object ann = factory->execute( ([ 
	"name":"an annotation", "mimetype":"text/html" ]) );
    Test.test( "annotation has correct class",
               (ann->get_object_class() & CLASS_DOCHTML) );
    add_annotation(ann);
    Test.test( "adding annotation",
               ( search(get_annotations(), ann) != -1 ) );
    Test.test( "new annotation references this()",
               ann->get_references()[this()] );

    // Duplicate tests
    object ref = get_factory(CLASS_CONTAINER)->execute((["name": "reference",]));
    move(ref);
    do_set_attribute("ref", ref);
    do_set_attribute("refmap", ([ "ref": ref, ]));
    do_set_attribute("refarr", ({ ref }));
    
    // recursive duplication
    object dup = ref->duplicate(true);

    object dupthis = dup->get_inventory()[0];
    Test.test("Duplicated Object", dupthis->get_identifier() == get_identifier());
    Test.test("Single Ref", dupthis->query_attribute("ref") == dup);
    Test.test("Map Ref", dupthis->query_attribute("refmap")["ref"] == dup);
    Test.test("Array Ref", dupthis->query_attribute("refarr")[0] == dup);

    remove_annotation(ann);
    Test.test( "removing annotation",
               ( search(get_annotations(), ann) == -1 ) );
    Test.test( "removed annotation reference",
               !ann->get_references()[this()] );

    //test events
    object listener = add_event(ann, EVENT_ANNOTATE, PHASE_NOTIFY, 
				lambda (mixed args) { });
    Test.skipped( "event listener",
                  "listener="+listener->describe() );

    // todo: much more event testing ...
    
    object obj = factory->execute( (["name":"object", ]) );
    ann->add_annotation(obj);

    ann->delete();
    ref->delete();

    delete();  // we are just a test object...
}


string describe()
{
    return get_identifier()+"(#"+get_object_id()+","+
	master()->describe_program(object_program(this_object()))+","+
	get_object_class()+")";
}

string _sprintf() 
{
  return describe();
}

string get_xml()
{
    object serialize = get_module("Converter:XML");
    string xml = "<?xml version='1.0' encoding='iso-8859-1'?>";
    mapping val = mkmapping(::_indices(1), ::_values(1));
    foreach ( indices(val), string idx ) {
	if ( !functionp(val[idx]) )
	    xml += "<"+idx+">\n" +
		serialize->compose(val[idx])+"\n</"+idx+">\n";
    }
    return xml;
}

static string get_typeof(mixed val)
{
    if ( intp(val) )
	return "Int";
    if ( floatp(val) )
	return "Float";
    if ( objectp(val) )
	return "Object";
    if ( arrayp(val) )
	return "Array";
    if ( mappingp(val) )
	return "Map";
    if ( stringp(val) )
	return "String";
    return "unknown";
}

static void lowSerializeXML(object parent, mixed val)
{
  if ( intp(val) ) {
    parent->add_prop("Type", "Int");
    parent->add_data((string)val);
  }
  else if ( floatp(val) ) {
    parent->add_prop("Type", "Float");
    parent->add_data((string)val);
  }
  else if ( stringp(val) ) {
    parent->add_prop("Type", "String");
    parent->add_data((string)val);
  }
  else if ( objectp(val) ) {
    parent->add_prop("Type", "Object");
    parent->add_data("ID#"+val->get_object_id());
  }
  else {
    parent->add_prop("Type", (arrayp(val) ?"Array":"Map"));
    foreach ( indices(val), mixed idx ) {
      mixed vlx = val[idx];
      object item = xslt.Node("item", ([ ]) );
      object key = xslt.Node("key", ([ ]) );
      object value = xslt.Node("value", ([ ]) );
      parent->add_child(item);
      item->add_child(key);
      item->add_child(value);
      lowSerializeXML(key, idx);
      lowSerializeXML(value, vlx);
    }
  }
}

void lowAppendXML(object rootNode, void|int depth)
{
    rootNode->add_prop("ID", (string)get_object_id());
    rootNode->add_prop("Type", 
		       get_factory(get_object_class())->get_class_name());
    rootNode->add_prop("Name", do_query_attribute(OBJ_NAME));
    object attributesNode = xslt.Node("Attributes", ([ ]));
    rootNode->add_child(attributesNode);
    foreach ( indices(mAttributes), string key ) {
	object attrNode; 
	mixed val = mAttributes[key];
	if ( arrayp(val) || mappingp(val) ) {
	  attrNode = xslt.Node("ComplexAttribute",([ "Key": key, ]));
	  lowSerializeXML(attrNode, val);
	}
	else if ( objectp(val) ) {
	  attrNode = xslt.Node("Attribute",([ "Key": key, ]));
	  attrNode->add_prop("Type", "Object");
	  attrNode->add_data("ID#" + val->get_object_id());
	}
	else {
	  attrNode = xslt.Node("Attribute",([ "Key": key, ]));
	  attrNode->add_prop("Type", get_typeof(val));
	  attrNode->add_data((string)val);
	}
	attributesNode->add_child(attrNode);
    }
}

string getXML(void|int depth)
{
  object doc = xslt.DOM("Object");
  object rootNode = doc->get_root();
  lowAppendXML(rootNode, depth);
  return doc->render_xml();
}


void route_call(function f, void|array args)
{
  if ( CALLER != master() )
    steam_error("Invalid call to route_call !");
  f(@args);
}


array get_depending_objects () {
  if ( !arrayp(aDependingObjects) ) return ({ });
  else return aDependingObjects;
}


void add_depending_object ( object obj ) {
  if ( !objectp(obj) || obj == this() ) return;
  if ( !arrayp(aDependingObjects) ) aDependingObjects = ({ });
  if ( search( aDependingObjects, obj ) < 0 )
    aDependingObjects += ({ obj });
  require_save( STORE_DATA );
  obj->add_depending_on( this() );
}


void remove_depending_object ( object obj ) {
  obj->remove_depending_on( this() );
  if ( arrayp(aDependingObjects) ) {
    if ( search( aDependingObjects, obj ) >= 0 )
      aDependingObjects -= ({ obj });
  }
  require_save( STORE_DATA );
}


array get_depending_on () {
  if ( !arrayp(aDependingOn) ) return ({ });
  else return aDependingOn;
}


void add_depending_on ( object obj ) {
  if ( !objectp(obj) || obj == this() ) return;
  if ( search( obj->get_depending_objects(), this() ) < 0 ) return;
  if ( !arrayp(aDependingOn) ) aDependingOn = ({ });
  if ( search( aDependingOn, obj ) < 0 )
    aDependingOn += ({ obj });
  require_save( STORE_DATA );
}


void remove_depending_on ( object obj ) {
  if ( !objectp(obj) || obj == this() ) return;
  if ( search( obj->get_depending_objects(), this() ) < 0 ) return;
  if ( arrayp(aDependingOn) && search( aDependingOn, obj ) >= 0 ) {
    aDependingOn -= ({ obj });
    require_save( STORE_DATA );
  }
}
