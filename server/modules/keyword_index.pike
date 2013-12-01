inherit "/kernel/module";

#include <macros.h>
#include <attributes.h>

// this module exists for compatibility reasons
// when acquire is set, turn it off!

mixed set_attribute(string|int key, mixed val)
{
  if ( key == OBJ_KEYWORDS ) {
    object obj = CALLER->this();
    obj->set_acquire_attribute(OBJ_KEYWORDS);
    return obj->set_attribute(OBJ_KEYWORDS, val);
  }
  return ::set_attribute(key, val);
}

mixed query_attribute(mixed key)
{
  if ( key == OBJ_KEYWORDS ) {
    object obj = CALLER->this();
    obj->set_acquire_attribute(OBJ_KEYWORDS);
    return obj->query_attribute(OBJ_KEYWORDS);
  }
  return ::query_attribute(key);
}

string get_identifier () { return "keyword_index"; }
