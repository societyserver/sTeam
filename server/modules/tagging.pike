inherit "/kernel/module";

#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>
#include <attributes.h>

#define TAG_MAP "TAG_MAP"

void tag_object(object obj, string|array tag)
{
  seteuid(USER("root"));
  mapping map = do_query_attribute(TAG_MAP) || ([ ]);
  array keywords = obj->query_attribute(OBJ_KEYWORDS) || ({ });
  
  if ( stringp(tag) )
    tag = ({ tag });
  else if ( !arrayp(tag) )
    error("Wrong Parameter to tag_object, needs string or Array");
  
  foreach(tag, string t) {
    if (search(keywords, t) >= 0)
      continue;
    
    keywords += ({ t });
    map[t]++;
  }
  obj->set_attribute(OBJ_KEYWORDS, keywords);
  do_set_attribute(TAG_MAP, map);
  seteuid(0);
}

array get_tags()
{
  mapping map = do_query_attribute(TAG_MAP) || ([ ]);
  return indices(map);
}

mapping get_tag_map(void|object room)
{
  if ( !objectp(room) )
    return do_query_attribute(TAG_MAP) || ([ ]);
  array inventory = room->get_inventory();
  mapping tags = ([ ]);
  foreach(inventory, object obj) {
    array keywords = get_object_tags(obj);
    foreach(keywords, string key)
      tags[key]++;
    if ( obj->get_object_class() & CLASS_CONTAINER )
      if ( !(obj->get_object_class() & CLASS_ROOM) )
	tags |= get_tag_map(obj);
  }  
  return tags;
}

string get_tag_cloud(void|object room)
{
  mapping tags = get_tag_map(room);
  string html = "<div class='tag_cloud'>\n";
  float fsize, fweight, maxval;
  
  foreach( values(tags), int v ) {
    if ( v > maxval )
      maxval = (float)v;
  }
  
  foreach(indices(tags), string t) {
    int count = tags[t];
    fsize = 150.0*(1.0+1.5*count-maxval/2.0)/maxval;
    fsize = fsize * 4.0 / 100.0;
    fweight = 50.0 * count / maxval;
    fweight = 10.0;
    
    html += 
      sprintf("<a href='#' style='font-weight: %dem; font-size: %dem;'>%s</a>",
	      (int)fweight, (int)fsize, t) + "&nbsp; &nbsp;";
  }

  html += "</div>";
  return html;
}

array(string) get_object_tags(object obj)
{
  return obj->query_attribute(OBJ_KEYWORDS);
}


string get_identifier() { return "tagging"; }
