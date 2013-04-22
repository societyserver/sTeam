inherit "/kernel/module";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <types.h>
#include <events.h>
#include <attributes.h>

object users = get_module("users");
object groups = get_module("groups");


int get_object_class()
{
  return ::get_object_class() | CLASS_CONTAINER;
}


bool insert_obj(object obj)
{
  steam_user_error("empty calendar script !");
}

bool remove_obj(object obj)
{
  steam_user_error("empty calendar script !");
}

array(object) get_inventory()
{
  return ({ });
}

array(object) get_inventory_by_class()
{
  return ({ });
}

object get_object_byname(string obj_name)
{
  object user;
  user = users->lookup(obj_name);
  if ( objectp(user) )
    return user->query_attribute(USER_CALENDAR);
  object group = groups->lookup(obj_name);
  if ( objectp(group) )
    return group->query_attribute(GROUP_CALENDAR);

  return 0;

}

string get_identifier() { return "calendar"; }
