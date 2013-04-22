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
 * $Id: factory.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: factory.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $";

inherit "/classes/Object";

//! This is the factory class - other factories are derived from this one.
//! See the factory pattern for factories in general. 
//! A factory is used by calling the execute() function and passing a mapping
//! of params. Each factory used the param "name" for execution in order to
//! give a new object a name. The factory for a class is retrieved by calling
//! the globally available function "get_factory(int classbit)", for example
//! get_factory(CLASS_USER).

import Attributes;

#include <macros.h>
#include <roles.h>
#include <assert.h>
#include <attributes.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <types.h>
#include <events.h>
#include <exception.h>

static Thread.Queue updateQueue = Thread.Queue();
static mapping mRegAttributes =([ ]); // "attribute-name":Attribute
static mapping mUpdAttributes=([ ]);
static int modeRegister = 0;

bool check_swap() { return false; }
bool check_upgrade() { return false; }


/**
 * Init callback function sets a data storage.
 *  
  */
static void
init()
{
    ::init();
    add_data_storage(STORE_ATTREG, retrieve_attr_registration,
                     restore_attr_registration);
}

static void init_factory()
{
    register_class_attribute(UserAttribute(OBJ_NAME, "object name", CMD_TYPE_STRING,""));
    register_class_attribute(UserAttribute(OBJ_DESC, "description", CMD_TYPE_STRING,""));
    register_class_attribute(UserAttribute(OBJ_ICON, "icon", CMD_TYPE_OBJECT, 0));
    register_class_attribute(UserAttribute(OBJ_LINK_ICON,"link icon",CMD_TYPE_OBJECT,0));
    register_class_attribute(Attribute(OBJ_URL,"url", CMD_TYPE_STRING, 0,
				 get_module("filepath:url")));
    register_class_attribute(UserAttribute(OBJ_KEYWORDS,"keywords",CMD_TYPE_ARRAY,({})));
    register_class_attribute
      (PositionAttribute(OBJ_POSITION_X, "x-position", CMD_TYPE_FLOAT, 0.0));
    register_class_attribute
      (PositionAttribute(OBJ_POSITION_Y, "y-position", CMD_TYPE_FLOAT, 0.0));
    register_class_attribute
      (PositionAttribute(OBJ_POSITION_Z, "z-position", CMD_TYPE_FLOAT, 0.0));
    register_class_attribute
      (PositionAttribute(OBJ_WIDTH, "width of object", CMD_TYPE_FLOAT, 0.0));
    register_class_attribute
      (PositionAttribute(OBJ_HEIGHT, "height of object", CMD_TYPE_FLOAT, 0.0));

    register_class_attribute(UserAttribute(OBJ_LANGUAGE,"language",CMD_TYPE_STRING,"de"));
    register_class_attribute(Attribute(OBJ_ANNO_MESSAGE_IDS,
                   "maps message ids to annotations",
                                 CMD_TYPE_MAPPING,
                                 ([]),
                                 0,
                                 CONTROL_ATTR_SERVER));
    register_class_attribute(Attribute(OBJ_ANNO_MISSING_IDS,
	            "stores message ids which were missing for annotations",
				       CMD_TYPE_MAPPING,
				       ([]),
				       0,
				       CONTROL_ATTR_SERVER));
    register_class_attribute(Attribute(OBJ_ONTHOLOGY,
				       "Onthology of the object.",
				       CMD_TYPE_OBJECT,
				       0, 
				       0,
				       CONTROL_ATTR_USER));
    
    register_class_attribute(Attribute(OBJ_VERSIONOF, 
				       "points to the current version",
				       CMD_TYPE_OBJECT,
				       0));
    register_class_attribute(Attribute(OBJ_LINKS, 
				       "all links of this object",
				       CMD_TYPE_ARRAY,
				       ({ })));
    register_class_attribute(Attribute(OBJ_PATH,
                                       "the path of this object",
                                       CMD_TYPE_STRING,
                                       ""));
}

/**
 * A factory calls initialization of factory when it is loaded.
 *  
 */
static void load_object()
{
    if ( !mappingp(mRegAttributes) )
	mRegAttributes = ([]);
    mUpdAttributes = ([ ]);

    if ( sizeof(mUpdAttributes) > 0 ) {
      MESSAGE("Updating Instances after loading factory !");
      update_instances(mUpdAttributes);
    }

    mUpdAttributes = ([ ]);
}

/**
 * Object constructor. Here the Attribute registration mapping is initialized.
 *  
 */
static void create_object()
{
    mRegAttributes = ([]);
    init_factory();
    require_save(STORE_ATTREG);
}

/**
 * See if a given name is valid for objects created by this factory.
 *  
 * @param string name - the name of the object
 */
void valid_name(string name)
{
    if ( !stringp(name) )
	steam_user_error("The name of an object must be a string !");
    if ( search(name, "/") >= 0 )
	steam_user_error("/ is not allowed in Object Names...(%O)", name);
    if ( !xml.utf8_check(name) )
	steam_user_error("Name %O of object is not utf-8 !", name);
}


/**
 * create a new object of 'doc_class'
 *  
 * @param string name - the name of the new object
 * @param string doc_class - the class of the new object
 * @param object env - the env the object should be moved to
 * @param mapping|int attr - attribute mapping for initial attribute settings
 * @param void|mapping attrAcq - acquired attributes
 * @param void|mapping attrLocked - locked attributes initialization
 * @param void|mapping sanction - sanction initialization
 * @param void|mapping sanctionMeta - meta sanction initialization
 * @return pointer to the new object
 */
static object
object_create(string name, string doc_class, object env, int|mapping attr,
	      void|mapping attrAcq, void|mapping attrLocked, 
	      void|mapping sanction, void|mapping sanctionMeta)
{
    object obj, user;

    user = geteuid() || this_user();

    doc_class = CLASS_PATH + doc_class + ".pike";
    SECURITY_LOG("New object of class:" + doc_class + " at " + ctime(time()));

    valid_name(name);

    if ( mappingp(attr) ) {
      foreach(values(attr), mixed v) {
	if ( stringp(v) && !xml.utf8_check(v) )
	  error("Create: Invalid Attribute found (utf-8 check failed).");
      }
    }

    if ( objectp(env) && !(env->get_object_class() & CLASS_CONTAINER) )
      steam_error("Failed to move object to " + env->get_object_id() +
		  " : object is no container !");

    obj = new(doc_class, name, attr);
    if ( !objectp(obj) )
	THROW("Failed to create object !", E_ERROR);

    function obj_set_attribute = obj->get_function("do_set_attribute");
    function obj_acquire_attribute = obj->get_function("do_set_acquire_attribute");
    function obj_lock_attribute = obj->get_function("do_lock_attribute");
    function obj_sanction_object = obj->get_function("do_sanction_object");
    function obj_sanction_object_meta =obj->get_function("do_sanction_object_meta");

    install_attributes(obj->this(), attr, UNDEFINED,
                       obj_set_attribute, 
                       obj_acquire_attribute);
    
    if ( !stringp(name) || name == "" ) 
        THROW("No name set for object !", E_ERROR);

    obj_set_attribute(OBJ_NAME, name);
    obj_set_attribute(OBJ_CREATION_TIME, time());

    if ( !mappingp(attr) || !objectp(attr[OBJ_ICON]) )
      obj_acquire_attribute(OBJ_ICON, _Server->get_module("icons"));
    
    if ( !stringp(obj->query_attribute(OBJ_NAME)) || 
         obj->query_attribute(OBJ_NAME) == "" )
       THROW("Strange error - attribute name setting failed !", E_ERROR);
    
    SECURITY_LOG("Object " + obj->get_object_id() + " name set on " +
		 ctime(time()));
    
    if ( !objectp(user) )
	user = MODULE_USERS->lookup("root");
    obj->set_creator(user);
    
    if ( user != MODULE_USERS->lookup("root") && 
	 user != MODULE_USERS->lookup("guest") )
    {
      obj_sanction_object(user, SANCTION_ALL);
      obj_sanction_object_meta(user, SANCTION_ALL);
    }
    obj->set_acquire(obj->get_environment);
    ASSERTINFO(obj->get_acquire() == obj->get_environment,
	       "Acquire not on environment, huh?");

    foreach(indices(attrAcq||([])), string acqi) {
      obj_acquire_attribute(acqi, attrAcq[acqi]);
    }
    foreach(indices(attrLocked||([])), string locki) {
      obj_lock_attribute(locki);
    }
    foreach(indices(sanction||([])), object sanctioni) {
      if ( objectp(sanctioni) )
	obj_sanction_object(sanctioni, sanction[sanctioni]);
    }
    foreach(indices(sanctionMeta||([])), object sanctionmi) {
      if ( objectp(sanctionmi) )
	obj_sanction_object_meta(sanctionmi, sanctionMeta[sanctionmi]);
    }

    obj->created();

    if ( objectp(env) ) {
	obj->move(env->this());
    }
    return obj->this();
}

static bool install_attribute(Attribute attr, 
                              object obj, 
                              void|mixed val, 
                              void|function obj_set_attribute,
                              void|function obj_acquire_attribute)
{
    if ( !objectp(obj) || obj->status() < 0 )
	return true;
    
    if ( !functionp(obj_set_attribute) )
      obj_set_attribute = obj->get_function("do_set_attribute");
    if ( !functionp(obj_acquire_attribute))
      obj_acquire_attribute = obj->get_function("do_set_acquire_attribute");

    mixed err = catch {
	mixed key = attr->get_key();
	mixed def = attr->get_default_value();
	string|object acq = attr->get_acquire();

	if ( obj->is_locked(key) ) 
	  return true;

	if ( !zero_type(def) ) {
	  obj_set_attribute(key, copy_value(def));
        }

	// do not acquire attributes for the default objects set
	if ( !objectp(acq) || acq != obj ) 
	{ 
          if ( stringp(acq) )
            obj_acquire_attribute(key, obj->find_function(acq));
          else 
            obj_acquire_attribute(key, acq);
	}
	if ( !zero_type(val) ) {
	  obj_set_attribute(key, val);
	}
	return true;
    };
    FATAL("Error registering attribute: %s\n%s", 
	  err[0],
	  describe_backtrace(err[1]));
}

array(object) get_inherited_factories() 
{
  array factories = _Server->get_factories();
  array depFactories = ({ });
  array myPrograms = Program.all_inherits(object_program(this_object()));
  foreach ( factories, object factory ) {
    if ( search(myPrograms, object_program(factory->get_object())) >= 0 ) {
      depFactories += ({ factory });
    }
  }
  return depFactories;
}

array(object) get_derived_factories() 
{
  array factories = _Server->get_factories();
  array depFactories = ({ });
  foreach ( factories, object factory ) {
    array facPrograms = Program.all_inherits(object_program(factory->get_object()));
    if ( search(facPrograms, object_program(this_object())) >= 0 ) {
      depFactories += ({ factory });
    }
  }
  return depFactories;
}

/**
 * register all attributes for an object
 *  
 * @param obj - the object to register attributes
 * @see register_class_attribute
 */
static void install_attributes(object obj, 
                               void|mapping mAttr, 
                               string|void key,
                               void|function obj_set_attribute,
                               void|function obj_acquire_attribute)
{
    Attribute attr;
    
    if ( !functionp(obj_set_attribute) )
      obj_set_attribute = obj->get_function("do_set_attribute");
    if ( !functionp(obj_acquire_attribute) )
      obj_acquire_attribute = obj->get_function("do_set_acquire_attribute");
    
    if ( !mappingp(mAttr) )
	mAttr = ([ ]);
    
    if ( stringp(key) ) {
	attr = mRegAttributes[key];
	if ( objectp(attr) ) 
	  install_attribute(attr, obj->this(), mAttr[key], 
                            obj_set_attribute,
                            obj_acquire_attribute);
    }
    else {
	foreach (indices(mRegAttributes), key)  {
	    attr = mRegAttributes[key];
	    install_attribute(attr, obj->this(), mAttr[key], 
                              obj_set_attribute,
                              obj_acquire_attribute);
	}
    }
}

/**
 * register attributes for the class(es) this factory creates.
 * each newly created object will have the attributes registered here.
 *  
 * @param Attribute attr - the new attribute to register.
 * @param void|function conversion - conversion function for all objects
 *
 * @see classes/Object.set_attribute 
 * @see libraries/Attributes.pmod.Attribute
 */
void 
register_attribute(Attribute attr, void|object conversion)
{
    try_event(EVENT_REGISTER_ATTRIBUTE, CALLER, attr);
    
    if ( register_class_attribute(attr, conversion) == 0 )
	return;

    // register on all dependent factories too
    array(object) factories = values(_Server->get_classes());
    foreach ( factories, object factory ) {
      factory = factory->get_object();
      if ( factory->get_object_id() == get_object_id() )
	continue;
      if ( search(Program.all_inherits(object_program(factory)),
		  object_program(this_object())) >= 0 )
	factory->register_attribute(copy_value(attr), conversion);
    }

    update_instances(attr->get_key());

    run_event(EVENT_REGISTER_ATTRIBUTE, CALLER, attr);
}

void unregister_attribute(string key) 
{
  Attribute attr = mRegAttributes[key];
  if ( !objectp(attr) )
    return;
  
  try_event(EVENT_REGISTER_ATTRIBUTE, CALLER, attr);
  if ( unregister_class_attribute(attr) == 0 )
    return;
  array(object) factories = values(_Server->get_classes());
  foreach ( factories, object factory ) {
    factory = factory->get_object();
    if ( factory->get_object_id() == get_object_id() )
      continue;
    if ( search(Program.all_inherits(object_program(factory)),
                object_program(this_object())) >= 0 )
      factory->unregister_attribute(copy_value(attr));
  }
  
  run_event(EVENT_REGISTER_ATTRIBUTE, CALLER, attr);
}

/**
 * Update instances of objects created by this factory when a new 
 * attribute is registered. This sets the new default value for the attribute
 * and the basic acquiring.
 *  
 * @param mixed key - the attribute key.
 * @param function|void conv - the conversion function.
 */
void update_instances(mixed key)
{
    Attribute attr;
    if ( !mappingp(key) ) {
	attr = mRegAttributes[key];
	if ( !objectp(attr) )
	    THROW("Unregistered Attribute !", E_ERROR);
    }
    else {
      if ( sizeof(key) == 0 ) {
	MESSAGE("(%s) Nothing to update !", get_identifier());
	return;
      }
    }
    
    array(object) instances = get_all_objects();
    int cnt = 0;
    int csz = sizeof(instances);
    foreach(instances, object instance) {
      cnt++;
      if ( cnt % 10000 == 0 ) {
	MESSAGE("Registering attribute %O : %d of %d objects done.",
                key, cnt, csz);
      }
      if ( !objectp(instance) || instance->status() < 0 )
        continue;


      // object is saved and can be updated later !
      if ( instance->status() == PSTAT_DISK ) 
        continue;

      // this should not happen anymore!!!
      if ( !functionp(instance->get_object_class) ||
	   !(instance->get_object_class() & get_class_id()) ) {
        FATAL("Got wrong instance %O in %s\n", instance, get_identifier());
	continue;
      }
      if ( mappingp(key) ) {
        function obj_set_attribute = instance->get_function("do_set_attribute");
        function obj_acquire_attribute = instance->get_function("do_set_acquire_attribute");
        foreach( indices(key), mixed k) {
          attr = mRegAttributes[k];
          if ( !attr->check_convert(instance) && 
               !check_attribute_registration(instance, attr) )
            install_attribute(attr, instance, UNDEFINED, 
                              obj_set_attribute, 
                              obj_acquire_attribute);
        }
      }
      else {            
        if ( !attr->check_convert(instance) &&
             !check_attribute_registration(instance, attr) ) {
          install_attribute(attr, instance);
        }
      }
    }
}


/**
 * Register_class_attribute is called by register_attribute,
 * this function is local and does no security checks. All instances
 * of this class are set to the default value and acquiring settings.
 *  
 * @param Attribute attr - the Attribute to register for this factories class
 * @see register_attribute
 */
static int register_class_attribute(Attribute attr, void|object conv)
{
    string|int key = attr->get_key();
    Attribute pattr = mRegAttributes[key];
    if ( pattr == attr ) 
      return 0;
   
    modeRegister = 1;

    do_set_attribute(FACTORY_LAST_REGISTER, time());
    if ( objectp(conv) )
      attr->set_converter(conv);
    mRegAttributes[key] = attr;
    require_save(STORE_ATTREG);

    modeRegister = 0;
    
    foreach( get_inherited_factories(), object factory ) {
	if ( factory->is_attribute(key) )
	    return 1;
    }
    
    mUpdAttributes[key] = 1;
    return 1;
}

static int unregister_class_attribute(Attribute attr)
{
  m_delete(mRegAttributes, attr->get_key());
  require_save(STORE_ATTREG);
  return 1;
}


/*
 * Init an attribute of this class calls registration function.  
 *
 * @see register_class_attribute
 */
static void 
init_class_attribute(mixed key, int type, string desc, 
		     int event_read, int event_write, 
		     object|int acq, int cntrl, mixed def)
{
    Attribute attr = Attribute(key, desc, type, def, acq, 
			       cntrl, event_read, event_write);
    if ( !objectp(mRegAttributes[key]) )
	register_class_attribute(attr);
}

/**
 * Check if an attributes value is going to be set correctly.
 * An objects set_attribute function calls this check and
 * throws an error if the value is incorrect.
 *  
 * @param mixed key - the attributes key.
 * @param mixed data - the new value of the attribute.
 * @param int|void regType - registration data to check, if void use factories.
 * @return true or false.
 */
bool check_attribute(mixed key, mixed data, int|void regType)
{
    object caller = CALLER;

    if ( !objectp(mRegAttributes[key]) ) 
	return true;

    // see if our factory has something about this attribute
    // if previous attribute in zero
    // this will end up in loop when installing attributes
    if ( zero_type(caller->query_attribute(key)) )
        install_attributes(CALLER, ([ ]), key);
    

    // value 0 should be ok
    if ( data == 0 ) return true;
    if ( key == "OBJ_NAME" )
      valid_name(data);
    
    return mRegAttributes[key]->check_attribute(data);
}


/**
 * check the registration of an attribute
 *  
 * @param object obj - the object to check the attribute
 * @param Attribute attr - the new registered attribute
 * @return if the attribute is ok
 */
bool check_attribute_registration(object obj, Attribute attr)
{
  string key = attr->get_key();
  mixed val = obj->query_attribute(key);
  if ( zero_type(val) )
    return false;

  if ( val == attr->get_default_value() )
    return true;
  switch(attr->get_type()) {
    case CMD_TYPE_INT: if ( !intp(val) ) return false; break;
    case CMD_TYPE_FLOAT: if ( !floatp(val) ) return false; break;
    case CMD_TYPE_STRING: if ( !stringp(val) ) return false; break;
    case CMD_TYPE_OBJECT: if ( !objectp(val) ) return false; break;
    case CMD_TYPE_ARRAY: if ( !arrayp(val) ) return false; break;
    case CMD_TYPE_MAPPING: if ( !mappingp(val) ) return false; break;
    case CMD_TYPE_PROGRAM: if ( !programp(val) ) return false; break;
    case CMD_TYPE_FUNCTION: if ( !functionp(val) ) return false; break;
  }  
  return true;
}

/**
 * check all attributes of an object
 *  
 * @param object obj - the object to check
 * @return true or false (attributes changed)
 * @see check_attribute
 */
bool check_attributes(object obj)
{
  int last_change = obj->query_attribute(OBJ_LAST_CHANGED);
  if ( last_change <= do_query_attribute(FACTORY_LAST_REGISTER) ) {
    
    if ( modeRegister ) {
      FATAL("checking object %O while registering .... !\n", obj);
      steam_error("registration failed due to loading objects ...");
    }
    function obj_set_attribute=obj->get_function("do_set_attribute");
    function obj_acquire_attribute=obj->get_function("do_set_acquire_attribute");

    foreach ( indices(mRegAttributes), string key ) {
      Attribute a = mRegAttributes[key];
      if ( !a->check_convert(obj) &&
           !check_attribute_registration(obj, a) )
        install_attribute(a, obj, UNDEFINED, 
			  obj_set_attribute, 
			  obj_acquire_attribute);
           
    }
    obj_set_attribute(OBJ_LAST_CHANGED, time());
    return true;
  }
  return false;
}


/**
 * Get the registration information for one attribute of this class.
 *  
 * @param mixed key the attributes key.
 * @return The array of registered data.
 */
Attribute describe_attribute(mixed key)
{
  return copy_value(mRegAttributes[key]);
}

/**
 * Get all registered attributes for this class.
 *  
 * @return the mapping of registered attributes for this class
 * @author Thomas Bopp (astra@upb.de) 
 * @see register_class_attribute
 */
mapping get_attributes()
{
    return copy_value(mRegAttributes);
}

bool is_attribute(string key)
{
  if ( mRegAttributes[key] )
    return true;
  return false;
}

/**
 * Get the event to fire upon reading the attribute.
 *  
 * @param mixed key - the attributes key.
 * @return read event or zero.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_attribute_change_event
 */
int get_attributes_read_event(mixed key)
{
    if ( !arrayp(mRegAttributes[key]) )
	return 0;
    return mRegAttributes[key]->get_read_event();
}

/**
 * Get the event to fire upon changing an attribute.
 *  
 * @param mixed key - the attributes key.
 * @return change event or zero.
  * @see get_attributes_read_event
 */
int get_attributes_change_event(mixed key)
{
    if ( !mappingp(mRegAttributes) || !objectp(mRegAttributes[key]) )
	return EVENT_ATTRIBUTES_CHANGE;
    return mRegAttributes[key]->get_write_event();
}

/**
 * Get an attributes default value and acquiring.
 *  
 * @param mixed key - the attributes key.
 * @return array of default value and acquiring setting.
 */
array get_attribute_default(mixed key) 
{
    return ({ mRegAttributes[key]->get_default_value(),
		  mRegAttributes[key]->get_acquire() });
}

/**
 * Called by the _Database to get the registered attributes (saved data)
 * for this factory.
 *  
 * @return mapping of registered attributes.
 */
final mapping
retrieve_attr_registration()
{
    if ( CALLER != _Database )
      THROW("Invalid call to retrieve_data()", E_ACCESS);
    return ([ 
      "RegAttributes":map(mRegAttributes, save_attribute),
    ]);
}

static mapping save_attribute(Attribute attr) 
{
    return attr->save();
}

/**
 * Called by _Database to restore the registered attributes data.
 *  
 * @param mixed data - restore data.
 */
final void 
restore_attr_registration(mixed data)
{
    if ( CALLER != _Database )
	THROW("Invalid call to restore_data()", E_ACCESS);
    foreach(indices(data->RegAttributes), mixed key) { 
	if ( !stringp(key) )
	    continue;
	mixed v = data->RegAttributes[key];
	if ( arrayp(v) ) {
	    mixed acq = v[4];
	    if ( intp(acq) && acq == 1 )
		acq = REG_ACQ_ENVIRONMENT;
	    Attribute a = Attribute(key,v[1],v[0],v[6],acq,v[5],v[2],v[3]);
	    mRegAttributes[key] = a;
	}
	else {
	    Attribute a = Attribute(v->key,v->desc,v->type,v->def,v->acquire,
				    v->control, v->event_read, v->event_write);
            if ( v->converter )
              a->set_converter(v->converter);
	    mRegAttributes[key] = a;
	}
    }
}

array(object) get_all_objects()
{
  return _Database->get_objects_by_class("/classes/"+get_class_name());
}

string get_identifier() { return "factory"; }
int get_object_class() { return ::get_object_class() | CLASS_FACTORY; }
string get_class_name() { return "undefined"; }
int get_class_id() { return CLASS_OBJECT; }
