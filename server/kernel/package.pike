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
 * $Id: package.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: package.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "module";

import Attributes;

#include <macros.h>
#include <database.h>
#include <classes.h>
#include <attributes.h>
#include <types.h>
#include <events.h>


/**
 * Constructor for a module initializes the package attributes.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
static void create_module()
{
    ::create_module();
 
}


/**
 * Callback function for package initialization code.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
static void init_package()
{
    set_attribute("package:components", ([ ]) );
    set_attribute("package:log", ({ }) );
    set_attribute("package:factories", ([ ]) );
    set_attribute("package:classes", ([ ]) );
    set_attribute("package:class_ids", 1);
}


/**
 * Initialize the module and call the init_package function.
 *  
 * @see init_package
 */
static void init_module()
{
    ::init_module();
    init_package();
}


/**
 * The package was loaded. Callback function.
 *  
 */
static void load_package()
{
}


/**
 * Load the module. Calls load_package.
 *  
 */
static void load_module()
{
    if ( !mappingp(query_attribute("package:factories")) )
	set_attribute("package:factories", ([ ]) );
    if ( !mappingp(query_attribute("package:classes")) )
	set_attribute("package:classes", ([ ]) );
    if ( query_attribute("package:class_ids") == 0 )
	set_attribute("package:class_ids", 1);

    load_package();
}


/**
 * This function will be called when the package is being installed.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
static void install_package(string source, string|void version)
{
}


/**
 * This function will be called when the package is being uninstalled.
 */
static void uninstall_package ()
{
}


/**
 * Function called when the package is uninstalled.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
static void uninstall()
{
    uninstall_package();
    mixed val;
    mixed comps = do_query_attribute("package:components") || ([ ]);
    
    foreach ( indices(comps), string comp ) 
    {
	if ( objectp(val=comps[comp]) )
	{
	    if ( val->get_object_class() & CLASS_OBJECT )
		val->delete();
	}
	else if ( intp(val) && val == 1 )
	{
	    // this wont happen I guess...
	    LOG("Removing file " + comp);
	    rm(comp);
	}
    }
}


/**
 * Package uninstallation function calls uninstall().
 *  
 * @return 0 or 1.
 * @author Thomas Bopp (astra@upb.de) 
 * @see uninstall
 */
int pck_uninstall()
{
    LOG("pck_uninstall()");
    if ( _SECURITY->access_write(0, this(), CALLER) ) {
	uninstall();
	return 1;
    }
    return 0;
}


/*
static void delete_object ()
{
  try_event( EVENT_DELETE, CALLER );
  mixed err = catch( uninstall() );
  if ( err ) werror( "%s\n%O\n", err[0], err[1] );
  ::delete_object();
}
*/


/**
 * Can be called in order to update the packet. This is used by the web-package
 * for example.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string pck_update()
{
}


/**
 * Called when the package is installed and calls install_package().
 * This function is called by the database.
 *  
 * @param string source - the source directory to copy files from.
 * @return 0 or 1.
 * @author Thomas Bopp (astra@upb.de) 
 * @see pck_install
 */
int install(string source, string|void version)
{
   LOG("Installing package !");
    if ( CALLER != _Database )
	THROW("Caller must be the sTeam Server !", E_ACCESS);


    mixed err = catch {
	install_package(source, version);
    };
    if ( err != 0 ) {
      MESSAGE("Error while installing package: \n"+
	      err[0]+"\n"+
	      PRINT_BT(err));
      uninstall();
      _Database->delete_object(this());
      throw(err);
    }
    return 1;
}


/**
 * Add something to the package log attribute.
 *  
 * @param string str - the string to log
 * @author Thomas Bopp (astra@upb.de) 
 */
static void pck_log(string str)
{
    //    require_save();??
}


/**
 * Get the logged string array for this package.
 *  
 * @return Array of logged string messages.
 * @author Thomas Bopp (astra@upb.de) 
 */
array(string)
pck_get_log()
{
}


/**
 * Add a component to this package. This function is usually
 * used when the package is installed.
 *  
 * @param string desc - description of the component.
 * @param object obj - the component to add.
 * @param string|void fname - the file name of the component inside steam.
 * @author Thomas Bopp (astra@upb.de) 
 */
static void add_component(string desc, object obj,string|void fname)
{
    mixed err;

    do_append_attribute("package:components",([desc :  obj ]));
    if ( obj->get_object_class() & CLASS_DOCLPC ) {
	object script = get_component("/scripts/"+fname);
	array(object) instances = obj->get_instances();

	if ( stringp(fname) && objectp(script) && 
	     script->get_identifier() == fname && 
	     search(instances, script) >= 0 ) 
	{
	    pck_log("Upgrading script: " + fname);
	    if ( objectp(obj->get_object()) )
		master()->upgrade(object_program(obj->get_object()));
	    add_component("/scripts/"+fname, script, fname);
	}
	else {
	    if ( objectp(script) ) {
		// something is horrible wrong !
		// script exists, but not in instances
		pck_log("Replacing script " + fname);
		err = catch {
		    script->delete();
		};
		if ( err != 0 )
		    pck_log("Error while deleting old script");
	    }		
	    LOG("Creating new script:"  + fname);
	    err = catch {
	      script = obj->execute( ([ "name": fname, ]) );
	      object scripts = _FILEPATH->path_to_object("/scripts");
	      script->move(scripts);
	      pck_log("Created new script:" + fname + " from " +
		      master()->describe_object(obj) + " (Instances:"+
		      sizeof(obj->get_instances())+")");
	    };
	    if ( err != 0 ) 
	      pck_log("Failed to create script: " + fname);
	}
	if ( objectp(script) )
	  add_component("/scripts/"+fname, script);
    }
    require_save(); // why? better save then sorry?
}


/**
 * Get a component by its description.
 *  
 * @param string desc - description of the component to find.
 * @return the found component.
 * @author Thomas Bopp (astra@upb.de) 
 */
object
get_component(string desc)
{
    return do_query_attribute("package:components")[desc];
}


/**
 * Get all registered component of this package.
 *  
 * @return mapping of components.
 * @author Thomas Bopp (astra@upb.de) 
 */
mapping get_components()
{
    return copy_value(do_query_attribute("package:components"));
}


/**
 * Register an attribute inside object obj and set its default value
 * and acquireing.
 *  
 * @param object obj - the object to register the attribute.
 * @param int|string key - the key of the attribute.
 * @param mixed def - the attributes default value.
 * @author Thomas Bopp (astra@upb.de) 
 */
static void
pck_reg_attribute(object obj, int|string key, mixed def, mixed acq)
{
    if ( intp(acq) && acq == REG_ACQ_ENVIRONMENT )
	obj->set_acquire_attribute(key, obj->get_environment);
    else if ( objectp(acq) ) {
	if ( obj->get_object_id() != acq->get_object_id() )
	    obj->set_acquire_attribute(key, acq);
	else
	    obj->set_acquire_attribute(key, 0);
    }
    LOG("Setting value for "+ obj->get_identifier() + ",key="+key+",value="+
	(objectp(def) ? def->get_identifier():"?"));
    obj->set_attribute(key, def);
}


/**
 * Provide an attribute for a class or one object, CLASS_ANY also includes
 * all modules
 *  
 * @param object_class - an object or a class of objects, CLASS any for all
 * @param key - the attribute key
 * @param desc - the description of this attribute
 * @param cntrl - the control registration info,CONTROL_ATTR_USER|SERVER|CLIENT
 * @param perm - permission for the attribute: ATTR_FREE_READ|WRITE|RESTRICTED
 * @param def - the default value of an attribute, 
 *              only set if attribute is not acquired
 * @param acq - acquiring information, nothing, an object or and integer for
 *              setting acquiring to the objects environment
 * @param obj_def - the default object from that is acquired - this object
 *                  will contain the default value for the attribute (see def)
 * @author Thomas Bopp (astra@upb.de) 
 * @see kernel/factory.register_attributes
 */
static void 
provide_attribute(int|object object_class, int|string key,int type,string desc,
		  int read_event, int write_event, string|object|void acq, 
		  int cntrl, mixed def, void|object obj_def)
{
    object factory;
    
    if ( intp(object_class) )
    {
	factory = _Server->get_factory(object_class);
	Attribute pattr  = factory->describe_attribute(key);
	Attribute attr = Attribute(key, desc, type, def, acq, cntrl, 
				   read_event, write_event);
	
	if ( !objectp(pattr) || pattr != attr )
        {
	    factory->register_attribute(attr);
	}  
    }
    else 
	pck_reg_attribute(object_class, key, def, acq);
	
    if ( objectp(obj_def) ) 
	pck_reg_attribute(obj_def, key, def, acq);
}


/**
 * Add a new class handled by this package.
 *  
 * @param int id - the class id
 * @param object factory - the factory handling the class
 * @param void|bool force - overwrite existing classes
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void add_class(int id, object factory, void|bool force)
{
    mapping mFactories = query_attribute("package:factories");

    if ( !force && objectp(mFactories[id]) )
	THROW("Class is already defined !", E_ERROR);
    
    mFactories[id] = factory;
    set_attribute("package:factories", mFactories);
}


/**
 * Register a new class and get the id for it.
 *  
 * @param string name - the name of the class
 * @return the class id for the class
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int register_class(string name)
{
    mapping mClasses = query_attribute("package:classes");
    int id = query_attribute("package:class_ids");
    mClasses[name] = id;
    set_attribute("package:classes", mClasses);
    set_attribute("package:class_ids", (id<<1));
}


/**
 * Get the class id for a given class.
 *  
 * @param string name - the name of the class.
 * @return the class id or 0 if not registered.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int get_class_id(string name)
{
    mapping mClasses = query_attribute("package:classes");
    return mClasses[name];
}


/**
 * Get the mapping of classes handled by this package.
 *  
 * @return mapping of classes, index is class id and value is the factory.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
mapping get_classes()
{
    return query_attribute("package:factories");
}


mixed get_config ( string key )
{
  object config = get_config_object();
  if ( !objectp(config) ) return UNDEFINED;
  return config->get_config( key );
}


mapping get_configs ( array|void configs )
{
  object config = get_config_object();
  if ( !objectp(config) ) return UNDEFINED;
  return config->get_configs( configs );
}


mixed set_config ( string key, mixed value )
{
  object config = get_config_object( 1 );
  if ( !objectp(config) ) return UNDEFINED;
  return config->set_config( key, value );
}


mapping set_configs ( mapping configs )
{
  object config = get_config_object( 1 );
  if ( !objectp(config) ) return UNDEFINED;
  return config->set_configs( configs );
}  


object get_config_object ( int|void create_if_missing )
{
  object config = OBJ( "/config/packages/" + get_identifier() );
  if ( objectp(config) || !create_if_missing ) return config;
  object package_configs = OBJ( "/config/packages" );
  if ( !objectp(package_configs) ) return UNDEFINED;
  config = get_factory( CLASS_DOCUMENT )->execute( ([
    "name" : get_identifier(),
    "mimetype" : "application/x-steam-config",
  ]) );
  if ( !objectp(config) ) return UNDEFINED;
  if ( !config->move( package_configs ) ) {
    config->delete();
    return UNDEFINED;
  }
  get_module( "decorator" )->add_decoration( config, "server:/decorations/Config.pike" );
  config->set_attribute( OBJ_TYPE, "object_config_package" );
  return config;
}

    
int get_object_class() { return ::get_object_class() | CLASS_PACKAGE | CLASS_SCRIPT; }
object get_source_object() { return this(); }
string get_version() { return do_query_attribute(PACKAGE_VERSION); }
