#include <macros.h>
#include <events.h>
#include <attributes.h>
#include <classes.h>
#include <coal.h>
#include <database.h>

static mapping classNames = ([ "Container": "Folder", "Document": "File", "Date":"Appointment", ]);

string typeOf(mixed val)
{
  if (intp(val))
    return "Int";
  else if (floatp(val))
    return "Float";
  else if (stringp(val))
    return "String";
  else if (objectp(val))
    return "Object";
  return "unknown";
}

string valueOf(mixed val)
{  
  if (intp(val))
    return val;
  else if (floatp(val))
    return val;
  else if (stringp(val))
    return val;
  else if (objectp(val))
    return "ID#"+val->get_object_id();
  return "unknown";
}

string object_to_xml(object obj) 
{
  string classname = obj->get_class();
  string changed = "";
  string docsize = "";
  int      changeTime;
  
  if (classNames[classname])
    classname = classNames[classname];
  if (obj->get_object_class() & CLASS_DOCUMENT) {
    docsize = sprintf("size=\"%d\"", obj->get_content_size());
    changeTime = obj->query_attribute(DOC_LAST_MODIFIED);
  }
  else
    changeTime = obj->query_attribute(OBJ_LAST_CHANGED) || 
      obj->query_attribute(OBJ_CREATION_TIME);

  changed = Calendar.Second(changeTime)->format_iso_time();

  string attributeStr = "<Attributes>";
  mapping attributes = obj->query_attributes();
  foreach(indices(attributes), string attribute) {
    attributeStr += sprintf("<Attribute key='%s' Type='%s'>%s</Attribute>\n",
			    attribute, 
			    typeOf(attributes[attribute]), 
			    valueOf(attributes[attribute]));
  }
  attributeStr += "</Attributes>\n";

  return sprintf("<%s name=\"%s\" path=\"%s\" ID=\"%d\" Type=\"%s\" changed=\"%s\"%s>%s</Object>", 
		 "Object",
		 obj->get_identifier(), 
		 get_module("filepath:tree")->object_to_filename(obj),
		 obj->get_object_id(),
		 classname,
		 changed, 
		 docsize,
		 attributeStr);
}
