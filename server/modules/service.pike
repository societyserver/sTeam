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
 * $Id: service.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: service.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <events.h>

class Service {
  function   send_function;
  function notify_function;
  object            socket;
  string              name;

  void create(string n, function sf, function nf, object sock) {
    send_function = sf;
    notify_function = nf;
    name = n;
    socket = sock;
  }
  void send(mapping args) {
    args->name = name;
    args->user = this_user();
    send_function(args);
  }
  void notify(object event) {
      if ( functionp(notify_function) )
	  notify_function(event, name);
  }
}

static mapping  mServices;
static mapping    mEvents;
static int            _id;
static mapping mCallbacks;

void init_module() 
{
  mServices  = ([ ]);
  mEvents    = ([ ]);
  mCallbacks = ([ ]);
  _id        =     1;
}

void notify_services(int e, mixed ... args)
{
  foreach(indices(mEvents), int event) {
    if ( (event & e) > 0  ) {
      foreach(mEvents[event], Service s) {
	Events.Event event = Events.Event(e);
	event->params = args;
	s->notify(event);
      }
    }
  }
}

static void register_service_event(string name, int event) 
{
  if ( !arrayp(mEvents[event]) )
    mEvents[event] = ({ mServices[name] });
  else {
    for ( int i = 0; i < sizeof(mEvents[event]); i++ ) {
      object service = mEvents[event][i];
      if ( objectp(service) ) {
	if ( service->name == name ) {
	  // overwrite existing service
	  mEvents[event][i] = mServices[name];
	}
	return; // do not register twice!!
      }
    }
    mEvents[event] += ({ mServices[name] });
  }
  add_global_event(event, notify_services, PHASE_NOTIFY);
}

void 
register_service(function send_function,function notify, string name,void|int|array event)
{
    array allowed_ips = ({ "127.0.0.1" });
    mixed server_ip = _Server->query_config("ip");
    if ( stringp(server_ip) && sizeof(server_ip)>0 )
      allowed_ips += ({ server_ip });
    mixed config_allowed_ips = _Server->query_config("trusted_hosts");
    if ( stringp(config_allowed_ips) ) {
      foreach ( config_allowed_ips / " ", string ip )
        if ( sizeof(ip)>0 ) allowed_ips += ({ ip });
    }
    if ( this_user() != USER("root")
         && search( allowed_ips, CALLER->get_ip() )<0 )
        steam_error("Invalid call - cannot register non-local services !\n"+
		    "CALLER: %O, SERVER: %O", 
		    CALLER->get_ip(), _Server->query_config("ip") );


    MESSAGE("Service '" + name + "' registered!");    
    mServices[name] = Service(name, send_function, notify, CALLER);
    if ( !arrayp(event) ) {
      event = ({ event });
    }
    for ( int i = 0; i < sizeof(event); i++ )
      register_service_event(name, event[i]);
}

void call_service(string name, mixed args) 
{
  Service s = mServices[name];
  if ( !objectp(s) )
    steam_error("No such Service: " + name);
  mapping params = ([ ]);
  params->params = args;
  s->send(params);
}

Async.Return call_service_async(string name, mixed args)
{
  Service s = mServices[name];
  if ( !objectp(s) )
    steam_error("No such Service: " + name);
  Async.Return res = Async.Return();
  _id++;
  mCallbacks[_id] = res;
  mapping params = ([ ]);
  params->params = args;
  params->id = _id;

  res->id = _id;
  s->send(params);
  return res;
}

void async_result(int id, mixed result)
{
  // todo: check for socket
  object res = mCallbacks[id];
  if ( objectp(res) ) {
    res->asyncResult(id, result);
  }

}

void handle_service(object user, object obj, mixed id, mixed res)
{
  if ( CALLER->get_ip() != "127.0.0.1" && CALLER->get_ip() != _Server->query_config("ip") )
    steam_error("Invalid call - cannot callback non-local services !");
  object ouid = this_user();
  
  obj->handle_service(id, res);
}

int is_service(mixed name)
{
  object service = mServices[name];
  if ( !objectp(service) || !functionp(service->send_function) )
    return 0;
  return 1;
}

mapping get_services()
{
  return copy_value(mServices);
}

string get_identifier() { return "ServiceManager"; }


mixed handleSearchResult(mixed id, array search_result)
{
  Test.succeeded( "testing search service", "search revealed %d results",
                  sizeof( search_result ) );
}

