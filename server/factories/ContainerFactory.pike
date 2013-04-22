/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: ContainerFactory.pike,v 1.2 2010/08/18 20:32:45 astra Exp $
 */

constant cvs_version="$Id: ContainerFactory.pike,v 1.2 2010/08/18 20:32:45 astra Exp $";

inherit "/factories/ObjectFactory";

//! This factory creates intances of the class Container.

import Attributes;

#include <macros.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <events.h>
#include <attributes.h>
#include <types.h>

static void
init_factory()
{
    ::init_factory();
    register_class_attribute(Attribute(
				 CONT_SIZE_X, "x-size", CMD_TYPE_FLOAT,
				 0.0, 0, CONTROL_ATTR_CLIENT));
    register_class_attribute(Attribute(
				 CONT_SIZE_Y, "y-size", CMD_TYPE_FLOAT,
				 0.0, 0, CONTROL_ATTR_CLIENT));
    register_class_attribute(Attribute(
				 CONT_SIZE_Z, "z-size", CMD_TYPE_FLOAT,
				 0.0, 0, CONTROL_ATTR_CLIENT));
    register_class_attribute(Attribute(
				 CONT_EXCHANGE_LINKS, "exchange links", 
				 CMD_TYPE_INT, 0, // link exchange turned off
				 REG_ACQ_ENVIRONMENT, CONTROL_ATTR_USER));
    register_class_attribute(Attribute(
				 CONT_WSDL, "Container WSDL Description", 
				 CMD_TYPE_OBJECT, 0, 
				 REG_ACQ_ENVIRONMENT, CONTROL_ATTR_USER));
}

/**
 * Execute this Container factory to get a new container object.
 * The vars mapping takes indices: "name", "attributes","attributesAcquired",
 * and "attributesLocked".
 *  
 * @param mapping vars - execute vars, especially the containers name.
 * @return proxy of the newly created container.
 */
object execute(mapping vars)
{
    object obj;
    string name = vars["name"];
    try_event(EVENT_EXECUTE, CALLER, obj);
    if ( vars->transient ) {
      if ( mappingp(vars->attributes) )
	vars->attributes[OBJ_TEMP] = 1;
      else
	vars->attributes = ([ OBJ_TEMP : 1 ]);
    }

    obj = ::object_create(
	name, CLASS_NAME_CONTAINER, 0, vars["attributes"],
	vars["attributesAcquired"], vars["attributesLocked"],
	vars["sanction"],
	vars["sanctionMeta"]);

    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

int change_object_to_container ( object obj ) {
  if ( !_SECURITY->access_write(0, obj, CALLER) )
    return 0;

  string old_class = obj->get_class();
  if ( old_class == CLASS_NAME_CONTAINER )
    return 0;  // obj already is a container
  if ( !(old_class == CLASS_NAME_ROOM) )
    steam_error("Class "+old_class+" cannot be changed to a container, only"
                +" rooms can !");

  steam_error( "Rooms cannot be changed to containers, yet." );

  //TODO: check for invalid contents for containers (e.g. users, exits
  // or other rooms) and remove them. Also recurse through all sub-rooms
  // and change them to containers, too.

  if ( _Persistence->change_object_class(obj, CLASS_NAME_CONTAINER) ) {
    obj->set_attribute( OBJ_LAST_CHANGED, query_attribute(FACTORY_LAST_REGISTER)-1 );
    call(obj->drop, 0.0);
    return 1;
  }
  return 0;
}

string get_identifier() { return "Container.factory"; }
string get_class_name() { return "Container"; }
int get_class_id() { return CLASS_CONTAINER; }

void test () {
  object cont = execute( ([ "name": "testcontainer", ]) );
  object doc1 = get_factory(CLASS_DOCUMENT)->execute( ([ "name": "test1", ]));
  object doc2 = get_factory(CLASS_DOCUMENT)->execute( ([ "name": "test2", ]));

  doc1->move(cont);
  Test.test("Inventory",
	    doc1->get_environment() == cont);
  Test.test("Inventory 2",
	    search(cont->get_inventory(), doc1) >= 0 );

  cont->add_annotation(doc2);
  
  Test.test("Anotations Annotating",
	    doc2->get_annotating() == cont);
  Test.test("Annotation available",
	    search(cont->get_annotations(), doc2) >= 0);

  object dup = cont->duplicate(1);
  
  Test.test("Duplicate Container", 
	    dup->get_identifier() == "testcontainer");
  Test.test("Duplicated Inventory",
	    sizeof(dup->get_inventory()) != 0);
  Test.test("Duplicated Annotation",
	    sizeof(dup->get_annotations()) > 0);

  object doc3 = get_factory(CLASS_DOCUMENT)->execute( ([ "name": "test3", ]));
  doc3->move(cont);
  doc3->set_attribute(OBJ_NAME, "test1");
  Test.test("Identifier should be unique after rename!", 
	    doc3->get_identifier() == doc3->get_object_id() + "__test1");
  Test.test("OBJ_NAME should be changed after rename!", 
	    doc3->query_attribute(OBJ_NAME) == "test1");

  object doc4 = get_factory(CLASS_DOCUMENT)->execute( ([ "name": "test1",
							 "move": cont,]));
  Test.test("Create with non-unique identifier in cont should make unique",
	    doc4->get_identifier() != "test1");

  object doc5 = get_factory(CLASS_DOCUMENT)->execute( ([ "name": "test1", ]));
  doc5->move(cont);
  Test.test("Name should change on move!", doc5->get_identifier() != "test1");
  Test.test("OBJ_NAME should be the same after move!", 
	    doc5->query_attribute(OBJ_NAME) == "test1");
}
