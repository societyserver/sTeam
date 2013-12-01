inherit "/kernel/module";

#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>
#include <attributes.h>

private static object myDB;

void post_load_module()
{
  myDB = _Database->get_db_handle();
}

public int swap_objects(int max_swaptime)
{
  return master()->swap(max_swaptime, 1);
}

mapping(object:int) check_memory(array(object) objects, int max_size)
{
  mapping(object: int) results = ([ ]);
  foreach(objects, object obj) {
    int mem = Pike.count_memory(0, obj->get_object());
    if (mem > max_size) {
      results[obj] = mem;
    }
  }
  return results;
}

array(object) get_null_users() 
{
  string query = "select ob_id from ob_data where ob_attr='UserName' and ob_data='0'";
  array users = ({ });
  array result = myDB->query(query);
  foreach(result, mapping res) {
    users += ({ find_object((int)res["ob_id"]) });
  }
  return users;
}

static string show_status(object user) 
{
  switch(user->status()) {
  case PSTAT_DISK:
    return "- DISK -";
  case "PSTAT_OK":
    return "MEMORY " + user->get_user_name() + 
      ", OBJ_NAME="+user->query_attribute(OBJ_NAME);
  case PSTAT_SAVE_PENDING:
    return "SAVING" + user->get_user_name() + 
      ", OBJ_NAME="+user->query_attribute(OBJ_NAME);
  }
  return "unknown";
}

mixed execute(mapping vars)
{
  string html = "<ul>";
  array nullUsers = get_null_users();
  foreach(nullUsers, object user) {
    html += sprintf("<li>%d, %s</li>", 
		    user->get_object_id(), 
		    show_status(user));
  }

  html += "</ul>";
  return html;
}

void clear_security_cache()
{
  object cache = get_module("Security:cache");
  cache->clear_cache();
}

void recover_users() 
{
  object factory = get_factory(CLASS_USER);
  factory->recover_users();
  factory->reset_guest();
}



string get_identifier() 
{
  return "housekeeping";
}

int get_object_class() { return ::get_object_class() | CLASS_SCRIPT; }
