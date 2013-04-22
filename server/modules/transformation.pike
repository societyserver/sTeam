inherit "/kernel/module";

#include <macros.h>
#include <classes.h>
#include <database.h>

string get_identifier() { return "transformation"; }


string transform_dc(object|array(object) objs)
{
  object xsl = get_module("libxslt");
  object stylesheet = OBJ("/stylesheets/DublinCore.xsl");
  string res = "";
  if ( !arrayp(objs) )
    objs = ({ objs });
  foreach( objs, mixed obj ) {
    if ( intp(obj) )
      obj = find_object(obj);
    string xml = get_module("Converter:XML")->get_xml(obj, stylesheet, ([ ]));
    string tf = xsl->run(xml, stylesheet, ([ ]));
    array lines = tf / "\n";
    if ( search(lines[0], "<?xml") >= 0 )
      res += lines[1..]*"\n";
    else 
      res += tf;
  }
  res = 
    "<transform>"+res+"</transform>";
  return res;
}

