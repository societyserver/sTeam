import soap;

#include <attributes.h>
#include <macros.h>

static array webservices = ({ });


static bool do_set_attribute(string key, mixed|void val);

static void register_webservice(function func, mixed ... params)
{
  object service = ServiceFunction(func, params);
  webservices += ({ service });
}

static void deploy_webservice(string deploy)
{
  do_set_attribute(OBJ_URL, deploy);
}

string show_wsdl() 
{
  object ws = Service(this_object());
  object wsdl = WSDL(ws);
  return wsdl->render_wsdl();
}

array get_webservices() 
{
  return webservices;
}





