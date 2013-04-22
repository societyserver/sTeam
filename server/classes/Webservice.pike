inherit "/classes/Script";
inherit "/base/webservice";

import soap;

#include <macros.h>
#include <database.h>
#include <exception.h>
#include <classes.h>
#include <attributes.h>
#include <types.h>


static void init_webservice() { }
static void create_webservice() { }
static void load_webservice() { }

static void init() 
{
  ::init();
  init_webservice();
}

static void create_object()
{
  create_webservice();
}

static void load_object() 
{
  load_webservice();
}

string get_webservice_name() { return "service"; }
string get_webservice_urn() { return "service"; }

mixed execute(mapping vars)
{
  if ( vars->wsdl ) {
    return ({ show_wsdl(), "text/xml" });
  }
}

int get_object_class() { return ::get_object_class() | CLASS_WEBSERVICE; }
string describe() { return _sprintf(); }
