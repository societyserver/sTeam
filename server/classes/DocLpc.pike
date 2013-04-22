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
 * $Id: DocLpc.pike,v 1.2 2008/05/01 14:52:20 exodusd Exp $
 */

constant cvs_version="$Id: DocLpc.pike,v 1.2 2008/05/01 14:52:20 exodusd Exp $";

/* this object really represents a factory if executed !
 */
inherit "/classes/Document";

import Attributes;

#include <classes.h>
#include <access.h>
#include <database.h>
#include <attributes.h>
#include <macros.h>
#include <types.h>
#include <classes.h>
#include <events.h>
#include <exception.h>

static mapping       mRegAttributes; // registered attributes for this factory
static array(object)    aoInstances; // Instances of this class
static int              __uploading;

/**
 * Initialize the document.
 *  
 */
static void
init_document()
{
    __uploading = 0;
    mRegAttributes = ([ ]);
    aoInstances     = ({ });
    add_data_storage(STORE_DOCLPC, retrieve_doclpc, restore_doclpc);
}

/**
 * Get the object class - CLASS_DOCLPC in this case.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
int
get_object_class()
{
    return ::get_object_class() | CLASS_DOCLPC;
}

/**
 * Destructor of this object.
 *  
 */
static void
delete_object()
{
    aoInstances -= ({ 0 });
    
    foreach(aoInstances, object obj)
	if ( objectp(obj) )
	    obj->delete(); // delete all instances
    ::delete_object();
}

/**
 * Execute the DocLPC which functions as a factory class.
 * The parameters must include a name 'name' and might include
 * a 'moveto' variable to move the object.
 *  
 * @param mapping variables - execution parameters.
 * @return the newly created object.
 */
mixed execute(mapping variables)
{
    if ( objectp(_CODER) && sizeof(_CODER->get_members()) > 0 ) {
	// check if User code is allowed, creator needs to be coder
	// and no other user should have write access on this script
	object creator = get_creator();
	if ( !_CODER->is_member(creator) && !_ADMIN->is_member(creator) )
	    THROW("Unauthorized Script", E_ACCESS);
	mapping sanc = get_sanction();
	foreach(indices(sanc), object grp) {
	    if ( (sanc[grp] & SANCTION_WRITE ) && !_ADMIN->is_member(grp) &&
		 !_CODER->is_member(grp) && grp != _ADMIN && grp != _CODER )
		THROW("Write access for non coder group enabled - aborting !",
		      E_ACCESS);
	}
    }

    try_event(EVENT_EXECUTE, CALLER, 0);
    clean_instances();

    if ( !mappingp(variables) )
      THROW( "No variables param to DocLpc->execute()!", E_ERROR );
    if ( !stringp(variables->name) || variables->name == "" )
      THROW( "No name provided to DocLpc->execute()!", E_ERROR );
    
    object obj;
    master()->clear_compilation_failures();
    object oeuid = geteuid();
    seteuid(get_creator());
    obj = ((program)("/DB:#"+get_object_id()+".pike"))(variables->name);
    if ( !objectp(obj) )
      THROW( "Failed to obtain instance for /DB:#"+get_object_id()+".pike"+
             "with name '"+variables->name+"'!", E_ERROR );

    install_attributes(obj->this());
    
    object mv = find_object((int)variables["moveto"]);
    if ( objectp(mv) )
	obj->move(mv);

    if ( !stringp(variables["name"]) )
	variables->name = "";
    // first add to instances
    aoInstances += ({ obj->this() });
    aoInstances -= ({ 0 });
    obj->sanction_object(get_creator(), SANCTION_ALL);

    obj->set_attribute(OBJ_NAME, variables["name"]);
    obj->set_attribute(OBJ_CREATION_TIME, time());
    obj->set_attribute(OBJ_SCRIPT, this());
    obj->set_acquire(obj->get_environment);
    obj->set_acquire_attribute(OBJ_ICON, _Server->get_module("icons"));
    obj->created();
    seteuid(oeuid);
    set_attribute(DOCLPC_INSTANCETIME, time());
    require_save(STORE_DOCLPC);
    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj;
}

object provide_instance()
{
    object o;
    array instances = aoInstances;
    if ( arrayp(instances) )
        clean_instances();
	//instances -= ({ 0 });
    o = get_instance();
    if ( objectp(o) )
	return o;

    object e = master()->ErrorContainer();
    master()->set_inhibit_compile_errors(e);
    mixed err = catch {
	o = execute((["name":"temp", ]));
	o->set_acquire(this());
    };
    master()->set_inhibit_compile_errors(0);
    if ( err != 0 ) {
	FATAL("While providing instance of %s\n%s, %s\n%O", 
	      get_identifier(), err[0], e->get(), err[1]);
	throw(err);
    }
    return o->this();
}

/**
 * Call this script - use first instance or create one if none.
 *  
 * @param mapping vars - normal variable mapping
 * @return execution result
 */
mixed call_script(mapping vars)
{
    object script = provide_instance();
    return script->execute(vars);
}

/**
 * register all attributes for an object
 *  
 * @param obj - the object to register attributes
 * @author Thomas Bopp (astra@upb.de) 
 * @see register_class_attribute
 */
private static void
install_attributes(object obj)
{
    object factory = _Server->get_factory(obj->get_object_class());
    if ( !objectp(factory) )
	factory = _Server->get_factory(CLASS_OBJECT);
    
    mapping mClassAttr = factory->get_attributes() + mRegAttributes;
    foreach ( indices(mClassAttr), mixed key ) 
	install_attribute(mClassAttr[key], obj);
}

bool install_attribute(Attribute attr, object obj)
{
    mixed err = catch {
	mixed key = attr->get_key();
	mixed def = attr->get_default_value();
	if ( !zero_type(def) )
	    obj->set_attribute(key, def);
	string|object acq = attr->get_acquire();
	if ( stringp(acq) )
	    obj->set_acquire_attribute(key, obj->find_function(acq));
	else 
	    obj->set_acquire_attribute(key, acq);
	return true;
    };
    FATAL("Error registering attribute: %O", err);
}


bool check_attribute(mixed key, mixed data) 
{
    Attribute a = mRegAttributes[key];
    if ( objectp(a) )
	return a->check_attribute(data);
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
register_attribute(Attribute attr, void|function conversion)
{
    try_event(EVENT_REGISTER_ATTRIBUTE, CALLER, attr);
    register_class_attribute(attr, conversion);

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
    run_event(EVENT_REGISTER_ATTRIBUTE, CALLER, attr);
}


/**
 * Register_class_attribute is called by register_attribute,
 * this function is local and does no security checks. All instances
 * of this class are set to the default value and acquiring settings.
 *  
 * @param Attribute attr - the Attribute to register for this factories class
 * @param void|function conversion - conversion function.
 * @see register_attribute
 */
static void register_class_attribute(Attribute attr, void|function conversion)
{
    string|int key = attr->get_key();
    MESSAGE("register_class_attribute(%O)",key);
    Attribute pattr = mRegAttributes[key];
    if ( pattr == attr ) {
	MESSAGE("re-registering class attribute with same value.");
	return;
    }
    foreach(aoInstances, object inst)
	install_attribute(attr, inst);

    mRegAttributes[key] = attr;
    require_save(STORE_DOCLPC);
}

/**
 * get the registration information for one attribute of this class
 *  
 * @param mixed key - the attribute to describe.
 * @return array of registered attribute data.
 */
Attribute describe_attribute(mixed key)
{
    return copy_value(mRegAttributes[key]);
}

/**
 * Get the source code of the doclpc, used by master().
 *  
 * @return the content of the document.
 */
string get_source_code()
{
    return get_content();
}

/**
 * Get the compiled program of this objects content.
 *  
 * @return the pike program.
 */
final program get_program() 
{ 
    program p = (program)("/DB:#"+get_object_id()+".pike");
    return p;
}

/**
 * Get an Array of Error String description.
 *  
 * @return array list of errors from last upgrade.
 */
array(string) get_errors()
{
    return master()->get_error("/DB:#"+get_object_id()+".pike") || ({ });
}

/**
 * Upgrade this script and all instances.
 *
 * @return -2 : no program passed, -1 : force needed, otherwise: number of
 *   dropped objects
 */
int upgrade()
{
  program p = get_program();
  //  MESSAGE("*** Upgrade of Program %O, %d instances\n", p, sizeof(aoInstances));

  mixed res = master()->upgrade(p);
  if ( stringp(res) )
    steam_error(res);

  if ( objectp(get_environment()) ) {
    string path = _FILEPATH->object_to_filename(this());
    program pp;
    catch(pp = (program)("/DB:/"+path));

    if ( programp(pp) ) {
      mixed err = catch(master()->upgrade(pp));
      if ( err )
        FATAL("Error while upgrading: %O", err);
    }
    catch(pp = (program) ("steam:"+path));
    if ( programp(pp) )
      master()->upgrade(pp);
  }


  do_set_attribute(DOCLPC_INSTANCETIME, time());
  if ( stringp(res) ) {
    steam_error(res);
  }
  else {
    foreach(aoInstances, object script) {
      if ( !objectp(script) )
        continue;
      if ( functionp(script->upgrade) )
        script->upgrade();
      script->drop();
    }
  }
    
  return res;
}

static void content_begin() 
{
  __uploading = 1;
}

static void content_finished()
{
    ::content_finished();
    do_set_attribute(DOCLPC_INSTANCETIME, time());
    mixed err = catch(upgrade());
    __uploading = 0;
    if ( err ) {
      FATAL("Error when updating after content_finished(): %O\n%O",
	    err[0], err[1]);
    }
}

/**
 * Retrieve the DocLPC data for storage in the database.
 *  
 * @return the saved data mapping.
 */
final mapping
retrieve_doclpc()
{
    if ( CALLER != _Database )
	THROW("Invalid call to retrieve_data()", E_ACCESS);
    
    return ([ 
	"RegAttributes":map(mRegAttributes, save_attribute),
	"Instances": aoInstances,
	]);
}

static mapping save_attribute(Attribute attr)
{
    return attr->save();
}

/**
 * Restore the data of the LPC document.
 *  
 * @param mixed data - the saved data.
 */
final void 
restore_doclpc(mixed data)
{
    if ( CALLER != _Database )
	THROW("Invalid call to restore_data()", E_ACCESS);

    aoInstances = data["Instances"];
    if ( !arrayp(aoInstances) )
	aoInstances = ({ });
    foreach(indices(data->RegAttributes), mixed key) { 
	mixed v = data->RegAttributes[key];
	if ( arrayp(v) ) {
	    mixed acq = v[4];
	    if ( intp(acq) && acq == 1 )
		acq = REG_ACQ_ENVIRONMENT;
	    Attribute a = Attribute(key, v[1],v[0],v[6],acq,v[5],v[2],v[3]);
	    mRegAttributes[key] = a;
	}
	else {
	    Attribute a = Attribute(v->key,v->desc,v->type,v->def,v->acquire,
				    v->control, v->event_read, v->event_write);
	    mRegAttributes[key] = a;
	}
    }
}

/**
 * Get the existing instances of this pike program.
 *  
 * @return array of existing objects.
 */
array(object) get_instances()
{
  array instances = ({ });

  for ( int i = 0; i < sizeof(aoInstances); i++ ) {
    if ( objectp(aoInstances[i]) && 
	 aoInstances[i]->status() != PSTAT_FAIL_DELETED && 
	 aoInstances[i]->status() != PSTAT_FAIL_COMPILE)
      instances += ({ aoInstances[i] });
  }
  return instances;
}

void clean_instances()
{
    aoInstances-= ({ 0 });
    
    foreach(aoInstances, object instance) {
      if( objectp(instance) && (instance->status() == PSTAT_FAIL_COMPILE
|| instance->status() == PSTAT_FAIL_DELETED) )
      {
	  aoInstances-= ({ instance });
	  instance->delete();
      }
    }
}

object get_instance() 
{
    clean_instances();
    foreach ( aoInstances, object instance ) {
	if ( objectp(instance) && instance->status() != PSTAT_FAIL_DELETED 
	     && instance->status() != PSTAT_FAIL_COMPILE)
	    return instance;
    }
    return 0;
}

string describe()
{
  mixed err = catch {
    return sprintf("%s+(#%d,%s,%d,%s,%d Instances, ({ %{%O,%} }))", 
                   get_identifier() || "(no identifier)",
		   get_object_id() || "(no id)",
	           master()->describe_program(object_program(this_object()))
                     || "(no program)",
	           get_object_class() || "(no class)",
		   do_query_attribute(DOC_MIME_TYPE) || "unknown",
	           sizeof(aoInstances),
		   aoInstances);
  };
  if ( err ) {
    werror("%O: %O\n", err[0], err[1]);
    throw(err);
  }
}

string get_class() { return "DocLpc"; }


void test() 
{
  // test script creation and upgrading
  Test.test( "setting pike script content",
             set_content("inherit \"/classes/Script\";\n#include <macros.h>"+
                         "\n#include <database.h>\nint test() {return 1; }\n")
             > 0 );

  object script = provide_instance();
  if ( !Test.test( "providing script instance",
                   objectp(script) && programp(get_program()) ) )
    return;

  if ( !Test.test( "running script",
                   functionp(script->test) && script->test() == 1 ) )
    return;

  script->drop();

  Test.add_test_function( test_more, 10, script, 0 );
}

void test_more(object script, int test, void|int nr_tries)
{
  if ( test == 2 ) {
    if ( __uploading ) {
      Test.add_test_function( test_more, 
			      max(5,nr_tries), 
			      script, 
			      test, 
			      nr_tries+1 );
      return;
    }
  }
  else if ( script->status() != PSTAT_DISK ) {
    MESSAGE( "DocLpc: waiting for drop of event script (try #%d, test#%d) ... ",
             nr_tries+1, test );
    script->drop();
    if ( nr_tries > 5 && script->status() == PSTAT_SAVE_PENDING )
      MESSAGE(" DocLpc, waiting to save: Queue Size = %d",
	      _Database->get_save_size());
    if ( nr_tries > 12 )
      Test.failed( "additional tests", "timeout while waiting for event "
                   +"script to drop, tried %d times, status %d", nr_tries,
		   script->status());
    else
      Test.add_test_function( test_more, 
			      max(5,nr_tries), 
			      script, 
			      test, 
			      nr_tries+1 );
    return;
  }
  
  switch(test) {
    case 0:
      if ( Test.test( "testing automatic upgrading on set_content()",
                      (set_content("inherit \"/classes/Script\";\n"+
                       "#include <macros.h>\n#include <database.h>\n"+
                       "int test() {return 2; }\n") > 0)
                      && (script->status() == PSTAT_DISK
			  || script->is_upgrading()),
		      "Errors: " + get_errors()*"\n"+
	   "status="+script->status() +",upgrading="+script->is_upgrading()) )
        Test.add_test_function( test_more, 0, script, 1 );
      break;
    case 1:
      // now error handling
      if ( !Test.test( "script automatically upgraded by set_content()",
                       script->test() == 2 ) ) return;

      MESSAGE("Testing Pike Script Error Handling ...");
      Test.test( "content handling",
		 (set_content("inherit \"/classes/Script;\n"+
			      "#include <macros.h>;\n#include <database.h>;\n"+
			      "int test() {return 1; }\n") > 0));
      Test.add_test_function( test_more, 0, script, 2);
      break; 
    case 2:
      if ( Test.test( "error handling",
                      (sizeof(get_errors()) > 0) ) )
      {
	if ( !Test.test( "script error keeps old instance",
			 script->test() == 2 , "Test Result="+script->test()) )
	  return;
      }
      else {
	FATAL("Failed to produce errors ?!: \n%O", get_errors());
	FATAL("PROGAM is %O", get_program());
	
      }
	  
      set_content("inherit \"/classes/Script\";\n#include <macros.h>;\n"+
                  "#include <database.h>;\nint test() {return 3; }\n");
      Test.add_test_function( test_more, 0, script, 3 );
      break;
    case 3:
      if ( !Test.test( "upgrading script that had an error",
                       script->test() == 3 ) )
        return;

      // test script and events - events after upgrade
      set_content("inherit \"/classes/Script\";\n#include <macros.h>;\n"+
                  "#include <events.h>;\n#include <database.h>;\n"+
                  "object test() { return addEvent(find_object("+
                  get_object_id()+"), EVENT_ATTRIBUTES_CHANGE, PHASE_NOTIFY, "+
                  "attribute_callback); }\nvoid attribute_callback(object "+
                  "event) { if ( event->get_params()->data[\"__test\"] ) { "+
                  "werror(\"***** Test notify !\\n\"); set_attribute("+
                  "\"events\", do_query_attribute(\"events\")+1); } }\n");
      //MESSAGE("Dropping event script ...");
      Test.add_test_function( test_more, 0, script, 4 );
      break;
    case 4:
      mixed res = script->test();
      if ( !Test.test( "script upgraded for event handling",
                       objectp(res) ) )
        return;

      //MESSAGE("Event Listener set to %O", res);
      
      set_attribute("__test", "ok");
      if ( !Test.test( "simple event test",
                       script->query_attribute("events") == 1 ) )
        return;

      //MESSAGE("Testing Event Script Events ...(%d)", test);
      set_attribute("__test", "testing");
      if ( !Test.test( "advanced event test",
                       script->query_attribute("events") == 2 ) )
        return;

      //MESSAGE("--- Testing upgrade --- Events received (2)");
      Test.test( "upgrading", upgrade() >= 0 );
      Test.add_test_function( test_more, 0, script, 6 );
      break;
    default:
      set_attribute("__test", "test");
      if ( script->query_attribute("events") == 3 )
        Test.succeeded( "event after upgrade", "script status: %d",
                        script->status() );
      else
        Test.failed( "event after upgrade",
                     "script status: %d, event result is %O",
                     script->status(), script->query_attribute("events") );
      //MESSAGE("* DocLpc all Tests finished successfully !");
      script->delete();
  }
}
