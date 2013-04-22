#include <macros.h>

static object decorated_object;
private static function f_query_attribute;
private static function f_set_attribute;

void register_attribute_functions(function setAttr, function getAttr)
{
  if (CALLER->this()!=decorated_object)
    steam_error("Only decorated object is allowed to register functions!");
  f_set_attribute = setAttr;
  f_query_attribute = getAttr;
}

static mixed query_attribute(string attr)
{
  return f_query_attribute(attr);
}

static mixed set_attribute(string key, mixed val)
{
  return f_set_attribute(key, val);
}

void create(object obj)
{
  decorated_object = obj;
}

function find_function(string f)
{
  return this_object()[f];
}

