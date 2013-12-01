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
 * $Id: ObjectFactory.pike,v 1.2 2010/08/18 20:32:45 astra Exp $
 */

constant cvs_version="$Id: ObjectFactory.pike,v 1.2 2010/08/18 20:32:45 astra Exp $";

inherit "/kernel/factory";

//! This factory creates Objects.

import Attributes;

#include <classes.h>
#include <macros.h>
#include <events.h>
#include <access.h>
#include <database.h>
#include <attributes.h>
#include <types.h>

static void init_factory()
{
    ::init_factory();
}

/**
 * The execute function - create a new instance of type "Object"
 *  
 * @param mapping vars - variables like name and description
 *                'name' - the name
 *                'attributes' - default attributes
 *                'transient' - for temporary objects
 * @return the newly created object
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
object execute(mapping vars)
{
    object obj;

    string name = vars["name"];
    try_event(EVENT_EXECUTE, CALLER, obj);

    if ( !mappingp(vars->attributes) )
      vars->attributes = ([ ]);
    if ( vars->transient )
      vars->attributes[OBJ_TEMP] = 1;
    obj = ::object_create(name, get_class_name(), vars["move"], 
			  vars["attributes"], 
			  vars["attributesAcquired"],
			  vars["attributesLocked"],
			  vars["sanction"],
			  vars["sanctionMeta"]);

    function obj_set_attribute = obj->get_function("do_set_attribute");
    
    if ( stringp(vars["description"]) )
	obj_set_attribute(OBJ_DESC, vars["description"]);
    if ( this_user() ) {
      string language = this_user()->query_attribute(USER_LANGUAGE);
      if ( stringp(language) )
        obj_set_attribute(OBJ_LANGUAGE, language);
    }
    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

void change_creator ( object obj, object new_creator ) {
  if ( ! GROUP("admin")->is_member( this_user() ) )
    THROW( "Unauthorized call to factory:set_creator() by " + this_user()->get_identifier() + " !", E_ACCESS );
  if ( !objectp(new_creator) || !(new_creator->get_object_class() & CLASS_USER) )
    steam_error( sprintf( "Invalid new creator for object, cannot change creator !\n* object: %O\n* new creator: %O", obj, new_creator ) );
  if ( !objectp(obj) )
    steam_error( sprintf( "Invalid object, cannot change creator !\n* object: %O\n* new creator: %O", obj, new_creator ) );
  obj->set_creator( new_creator );
}

int delete_for_me ( object obj )
{
  if ( CALLER != _Persistence )
    THROW( "Invalid caller, only persistence manager my call delete_for_me !",
           E_ERROR );
  object old_euid = geteuid();
  seteuid( _ROOT );
  int ret;
  mixed err = catch( ret = obj->delete() );
  seteuid( old_euid );
  if ( err ) throw( err );
  return ret;
}

string get_identifier() { return "Object.factory"; }
string get_class_name() { return "Object"; }
int get_class_id() { return CLASS_OBJECT; }


bool test() 
{
  // test Object class:
  object test_obj = execute( ([ "name":"Object-Test" ]) );
  Test.test( "object creation", objectp(test_obj) );
  Test.test( "object icon", objectp(test_obj->query_attribute(OBJ_ICON)));
  Test.test( "object icon acquire", 
	     objectp(test_obj->get_acquire_attribute(OBJ_ICON)));

  object test_icon = execute( ([ "name": "IconLockTest",
				 "attributes": ([ OBJ_ICON: test_obj, ]), ]) );
  Test.test("ICON Attribute creation parameter (acquired attribute setting) is "+
	    sprintf("%O: %O", test_icon->get_acquire_attribute(OBJ_ICON), test_icon->query_attribute(OBJ_ICON)),
	    test_icon->query_attribute(OBJ_ICON) == test_obj);

  Test.start_test( test_obj );

  // first make sure no previous registration is set!
  unregister_attribute("test");
  
  //MESSAGE("* Testing Attribute Registration !");
  string testval = (string)time();
  Attribute attr = Attribute("test", "test", CMD_TYPE_STRING, testval, this());
  register_attribute(attr);
  //MESSAGE("* Creating new Object and testing attribute registrations");
  object o = execute( (["name": "test", ]) );
  //if ( o->get_acquire_attribute("test") != this() )
  //  steam_error("Acquire of test object does not match !");
  Test.test( "attribute registration",
             o->get_acquire_attribute("test")==this() );
  //o->test();
  
  //MESSAGE("* Testing Attribute Registration with Converter Object");
  object converter = get_factory(CLASS_DOCUMENT)->execute((["name":"c.pike"]));
  converter->set_content("inherit \"/classes/Script\"; \nvoid convert_attribute(object attr, object obj) { object oeuid = geteuid(); seteuid(get_module(\"users\")->lookup(\"root\")); obj->set_acquire_attribute(\"test\", 0); seteuid(oeuid);}\n");

  attr = Attribute("test", "test", CMD_TYPE_STRING,"testwert", 0);
  register_attribute(attr, converter->provide_instance());
  // acquire was changed with converter object
  // no changing of acquire when default value is changed, but not the type
  //if ( objectp(o->get_acquire_attribute("test")) )
  //  steam_error("ObjectFactory.test(): test Attribute acquire changed !");
  Test.test( "attribute registration with converter - acquire",
             !objectp(o->get_acquire_attribute("test")) );
  // should not be set to new default value, because already string
  //if ( o->query_attribute("test") != testval )
  //  steam_error("ObjectFactory.test(): should keep old value of attribute!");
  Test.test( "attribute registration with converter - keep value",
             o->query_attribute("test") == testval );

  // circular Acquiring
  object oa = execute( (["name": "test2", ]) );
  o->set_acquire_attribute("test", oa);
  mixed err = catch(oa->set_acquire_attribute("test", o));
  //if ( !err ) 
  //  steam_error("ObjectFactory.test() acquiring from each other !");
  Test.test( "circular acquire", err );

  o->set_acquire_attribute("test", 0);
  oa->delete();

  // try again with object on DB
  o->drop();
  //call(test_more, 5, o);
  Test.add_test_function( test_more, 5, o, 1 );
  
  return true;    
}

static void test_more(object o, int nr_tries)
{
  if ( o->status() != PSTAT_DISK ) {
    if ( nr_tries > 12 ) {
      Test.failed( "additional tests", "failed to drop test object, tried %d "
                    +"times", nr_tries );
      return;
    }
    o->drop();
    //call(test_more, 5, o);
    Test.add_test_function( test_more, 5, o, nr_tries+1 );
    return;
  }
  Attribute attr = Attribute("test", "test", CMD_TYPE_INT, 123, GROUP("steam"));
  register_attribute(attr);

  //if ( o->query_attribute("test") != 123 )
  //  steam_error("Wrong value of registered attribute - should be INT:"+
  //              "is %O in %O (factory=%O).", o->query_attribute("test"), o,
  //              this_object());
  Test.test( "value of registered attribute",
             o->query_attribute("test") == 123 );

  //if ( o->get_acquire_attribute("test") != GROUP("steam") )
  //  steam_error("Acquire of test object does not point to registered Acq!");
  Test.test( "acquire points to registered acquire",
             o->get_acquire_attribute("test") == GROUP("steam") );

  if ( get_class_id() == CLASS_OBJECT ) { // this test is not always valid
    //if ( USER("root")->get_acquire_attribute("test") != GROUP("steam") )
    //  steam_error("Acquire of root user does not point to registered Acq!\n"+
    //  "(%O)\nacquire is %O\n",
    //    this(), USER("root")->get_acquire_attribute("test"));
    Test.test( "acquire of root user points to registered acquire",
               USER("root")->get_acquire_attribute("test") == GROUP("steam") );
  }

  Test.test( "deleting object", o->delete() );
}
