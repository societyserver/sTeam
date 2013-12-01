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
 * $Id: Events.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Events.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <events.h>
#include <config.h>

#ifdef EVENT_DEBUG
#define DEBUG_EVENT(s,args...)  write(s+"\n",args)
#else
#define DEBUG_EVENT(s,args...) 
#endif

static mapping event_desc = ([ 
    EVENT_ENTER_INVENTORY: "enter-inventory",
    EVENT_LEAVE_INVENTORY: "leave-inventory",
    EVENT_UPLOAD: "upload",
    EVENT_DOWNLOAD: "download",
    EVENT_ATTRIBUTES_CHANGE: "attributes-change",
    EVENT_MOVE: "move",
    EVENT_SAY: "say",
    EVENT_TELL: "tell",
    EVENT_LOGIN: "login",
    EVENT_LOGOUT: "logout",
    EVENT_ATTRIBUTES_LOCK: "lock-attribute",
    EVENT_EXECUTE: "execute",
    EVENT_REGISTER_FACTORY: "register-factory",
    EVENT_REGISTER_MODULE: "register-module",
    EVENT_ATTRIBUTES_ACQUIRE: "acquire-attributes",
    EVENT_ATTRIBUTES_QUERY: "query-attributes",
    EVENT_REGISTER_ATTRIBUTE: "register-attribute",
    EVENT_DELETE: "delete",
    EVENT_ADD_MEMBER: "add-member",
    EVENT_REMOVE_MEMBER: "remove-member",
    EVENT_GRP_ADD_PERMISSION: "add-permissions-for-group",
    EVENT_USER_CHANGE_PW: "user-change-password",
    EVENT_SANCTION: "sanction",
    EVENT_SANCTION_META: "meta-sanction",
    EVENT_ARRANGE_OBJECT: "arrange-object",
    EVENT_ANNOTATE: "annotate",
    EVENT_LISTEN_EVENT: "listen-event",
    EVENT_IGNORE_EVENT: "ignore-event",
    EVENT_GET_INVENTORY: "get_inventory",
    EVENT_DUPLICATE: "duplicate",
    EVENT_REQ_SAVE: "save",
    EVENT_GRP_ADDMUTUAL: "group-add-mutual",
    EVENT_STATUS_CHANGED: "status-changed",
    EVENT_SAVE_OBJECT: "save",
    EVENT_REMOVE_ANNOTATION: "remove-annotation",
    EVENT_DOWNLOAD_FINISHED: "download-finished",
    EVENT_DB_REGISTER: "database-register",
    EVENT_DB_UNREGISTER: "database-unregister",
    EVENT_DB_QUERY: "database-query",
    EVENT_SERVER_SHUTDOWN: "server-shutdown",
    EVENT_CHANGE_QUOTA: "quota-change",
    EVENT_REMOVE_ANNOTATION: "remove-annotation",
    EVENT_DECORATE: "decorate",
    EVENT_REMOVE_DECORATION: "remove-decoration",
    ]);

class Listener {
    static int            event_id;
    static object        event_obj;
    static int         event_phase;
    static function event_callback;
    static string    callback_name;
    static object     callback_obj;
    static object        listening;
    static int           objEvents;
    static string      listener_id;

    void set(int eid, int phase, object obj, function callback, object|void l, void|int oEvents) {
	if ( !objectp(obj) )
	    return;
        if ( functionp(callback) ) {
          callback_name = function_name(callback);
          callback_obj = function_object(callback);
          // need proxy
          if ( objectp(callback_obj) && functionp(callback_obj->this)) 
            callback_obj = callback_obj->this();
        }
	event_id = eid;
	event_phase = phase;
	event_callback = callback;
	event_obj = obj->this();	
	listening = l;
	objEvents = oEvents;
	listener_id = sprintf("%x", hash((string)random(1000000) + time() + eid));
    }

    string get_listener_id() {
	return listener_id;
    }

    void create(int eid, int phase, object obj,function callback,object|void l,void|int oEvents) {
	set(eid, phase, obj, callback, l, oEvents);
    }
    void setObjectEvents()
    {
	objEvents = 1;
    }

    int getObjectEvents() 
    {
	return objEvents;
    }
    int get_event() {
	return event_id;
    }
    object get_object() {
	return event_obj;
    }
    int get_phase() {
	return event_phase;
    }
    function get_callback() {
	return event_callback;
    }
    object get_listening() {
        return listening;
    }

    string describe() { 
	return "Listener("+listener_id+","+
	    (objectp(event_obj)?event_obj->get_identifier():
			    "dead")+","+
	    (functionp(event_callback)?function_name(event_callback):"none")+
	    ", phase="+ (event_phase==PHASE_NOTIFY?"notify":"block")+","+
	    translate_eid(event_id)+")"; 
    }

    string _sprintf() {
      return describe();
    }

    mixed `[] (mixed index) {
	switch ( index ) {
	case 0:
	    return event_callback;
	case 1:
	    return event_id;
	case 2:
	    return event_phase;
	case 3:
	    return event_obj;
	default:
	    return "unknown";
	}
    }
    void notify(int eid, mixed args, object eventObj) {
        if ( !functionp(event_callback) ) {
          // event callback lost ?
          if ( objectp(callback_obj) && callback_obj->status() >= 0 ) {
            event_callback = callback_obj->find_function(callback_name);
          }
        }
	if ( functionp(event_callback) ) {
	    if ( objEvents ) {
		event_callback(eventObj);
	    }
	    else
		event_callback(eid, @args);
	}
    }
    int compare(object eobj, int eid, int ephase, function ecallback) {
	if ( !functionp(ecallback) || !functionp(event_callback) )
	    return 0;
	return event_obj == eobj && eid == event_id && 
	    ephase == event_phase && ecallback == event_callback;

    }
    
    mixed `==(object l) {
	if ( !objectp(l) || !functionp(l->compare) ) 
	    return 0;
	return l->compare(event_obj, event_id, event_phase, event_callback);
    }
    mixed `!=(object l) {
	return !l->compare(event_obj, event_id, event_phase, event_callback);
    }
}

class Event {
    static int            event_id;
    static array(object) listeners;
    mixed params;

    void create(int id) {
	event_id = id;
	listeners = ({ });
    }

    object add_listener(Listener l) {
	// already got such a listener
	if ( !objectp(l) )
	    return 0;

	foreach ( listeners, object listen ) {
	    if ( !objectp(listen) ) continue;
	    if ( listen == l ) {
		return listen;
	    }
	}
	listeners += ({ l });
	return l;
    }

    void remove_listener(Listener l) {
	listeners -= ({ l });
    }

    array(object) get_listeners() {
	return listeners; 
    }

    void set_event(int id) {
	event_id = id;
    }

    int get_event() {
	return event_id;
    }

    static void notify_listener(object l, mixed args) {
	l->notify(event_id, args, this_object());
    }

    void run_event(int phase, mixed args) {
	listeners -= ({ 0 });
	params = copy_value(args);
	foreach( listeners, object l ) {
	    if ( objectp(l) && l->get_phase() == phase ) {
		notify_listener(l, args);
	    }
	}
    }

    mapping get_params() {
	return event_to_params(event_id, params);
    }
    mapping serialize_coal() {
        return get_params();
    }
    string describe() {
	return event_to_description(event_id, params);
    }

    void remove_dead() {
	foreach(listeners, object l) {
	    if ( !objectp(l) )
		listeners -= ({ l });
	}
    }

    string _sprintf() { 
      int ilisten, idead;
      foreach(listeners, object l) {
	if ( !objectp(l) )
	  idead++;
	else if ( functionp(l->get_callback) && !functionp(l->get_callback()) )
	  idead++;
	else
	  ilisten++;
      }
      
      return "Event("+event_id+","+translate_eid(event_id)+", "+
	  (event_id & EVENTS_MONITORED ? "monitored, ": "") + 
	  ilisten+ " Listeners, "+idead+" dead)";
    }
}



/**
 * Returns a string description for a given event.
 *
 * @param int eid - event id (bits)  
 * @return string description
 */
string translate_eid(int eid) 
{
    array index = indices(event_desc);
    eid = eid & EVENT_MASK;

    int events_second = eid & EVENTS_SECOND;
    int events_module = eid & EVENTS_MODULES;
    foreach(index, int id) {
	if ( (id & eid) == (id | events_second | events_module) ) 
	    return event_desc[id];
    }
    return "unknown";
}

/**
 * Split a given integer bit array into segments. The EVENTS_MONITORED bit is 
 * preserved and set for each element of the resulting array.
 *
 * @param int event - the event to split
 * @return array of single event-id-bits.
 */
array(int) split_events(int event) 
{
  // second events
  int events_second = event & EVENTS_SECOND;

  array(int) events = ({ });
  int monitor = (event & EVENTS_MONITORED);
  
  for ( int i = 0; i <= 27; i++ ) {
    if ( event & (1<<i) ) 
      events += ({ (1<<i) | monitor | events_second });
  }
  return events;
}


mapping event_to_params(int event_id, array params)
{
    int offset = 0;
    mapping p = ([ ]);
    if (  event_id & EVENTS_MONITORED ) {
        p->context = params[0];
	offset = 1;
    }
    p->object = params[offset+0];
    p->eventID = event_id;
    p->event = translate_eid(event_id);
    
    if ( event_id & EVENTS_MODULES ) {
	p->object = params[offset+0];
        if ( event_id & EVENT_DB_REGISTER ) 
           p->key = params[offset+1];
        if ( event_id & EVENT_DB_UNREGISTER ) 
           p->key = params[offset+1];
    }
    else if ( event_id & EVENTS_SECOND ) {
	p->object = params[offset+0];
	if ( event_id & EVENT_GET_INVENTORY ) {
	    p->caller = params[offset+1];
	}
	else if ( event_id & EVENT_DUPLICATE ) {
	    p->caller = params[offset+1];
	}
	else if ( event_id & EVENT_GRP_ADDMUTUAL ) {
	    p->caller = params[offset+1];
	    p->group = params[offset+2];
	}
	else if ( event_id & EVENT_STATUS_CHANGED ) {
	    p->user = params[offset+1];
	    p->newFeatures = params[offset+2];
	    p->oldFeatures = params[offset+3];
	}
	else if ( event_id & EVENT_REMOVE_ANNOTATION ) {
	    p->caller = params[offset+1];
	    p->annotation = params[offset+2];
	}
	else if ( event_id & EVENT_DOWNLOAD_FINISHED ) {
	  p->caller = params[offset+1];
	}
	else if ( event_id & EVENT_LOCK ) {
	}
	else if ( event_id & EVENT_DECORATE ) {
          p->caller = params[offset+1];
          p->decoration = params[offset+2];
        }
        else if ( event_id & EVENT_REMOVE_DECORATION ) {
          p->caller = params[offset+1];
          p->decoration = params[offset+2];
        }

    }
    else if ( event_id & EVENT_ENTER_INVENTORY )
    {
	p->container = params[offset+0];
	p->enteringObject = params[offset+1];
    }
    else if ( event_id & EVENT_LEAVE_INVENTORY ) 
    {
	p->container = params[offset+0];
	p->leavingObject = params[offset+1];
    }
    else if ( event_id & EVENT_ATTRIBUTES_CHANGE ) {
	p->caller = params[offset+1];
	p->data = params[offset+2];
	p->olddata = params[offset+3];
    }
    else if ( event_id & EVENT_REGISTER_ATTRIBUTE ) {
	p->caller = params[offset+1];
	p->data = params[offset+2]->get_key();
    }
    else if ( event_id & EVENT_ATTRIBUTES_ACQUIRE ) {
	p->caller = params[offset+1];
	p->data = params[offset+2];
    }
    else if ( event_id & EVENT_USER_CHANGE_PW ) {
	p->caller = params[offset+1];
    }
    else if ( event_id & EVENT_ATTRIBUTES_LOCK ) {
	p->caller = params[offset+1];
	p->data = params[offset+2];
	p->lock = params[offset+3];
    }
    else if ( event_id & EVENT_ARRANGE_OBJECT ) {
	p->caller = params[offset+1];
	p->data = params[offset+2];
    }
    else if ( event_id & EVENT_LISTEN_EVENT ) {
	p->caller = params[offset+1];
	p->event = params[offset+2];
	p->phase = params[offset+3];
    }
    else if ( event_id & EVENT_IGNORE_EVENT ) {
	p->caller = params[offset+1];
	p->event = params[offset+2];
    }
    else if ( event_id & EVENT_UPLOAD ) {
	p->size = params[offset+2];
	p->user = params[offset+1];
    }
    else if ( event_id & EVENT_DOWNLOAD ) {
    }
    else if ( event_id & EVENT_MOVE ) {
	p->movedByObject = params[offset+1];
	p->fromContainer = params[offset+2];
	p->toContainer = params[offset+3];
    }
    else if ( event_id & EVENT_SAY ) {
	p->room = params[offset+0];
	p->message = params[offset+2];
    }
    else if ( event_id & EVENT_TELL ) {
	p->user = params[offset+0];
	p->sender = params[offset+1];
	p->message = params[offset+2];
    }
    else if ( event_id & EVENT_LOGIN ) {
	p->user = params[offset+0];
	p->newFeatures = params[offset+2];
	p->oldFeatures = params[offset+3];
    }
    else if ( event_id & EVENT_LOGOUT ) {
	p->socket = params[offset+2];
    }
    else if ( event_id & EVENT_EXECUTE ) {
	p->caller = params[offset+1];
	p->data = params[offset+2];
    }
    else if ( event_id & EVENT_DELETE ) {
	p->caller = params[offset+1];
    }
    else if ( event_id & EVENT_ADD_MEMBER ) {
	p->addObject = params[offset+2];
	p->caller = params[offset+1];
    }
    else if ( event_id & EVENT_REMOVE_MEMBER ) {
	p->removeObject = params[offset+2];
	p->caller = params[offset+1];
    }
    else if ( event_id & EVENT_SANCTION ) {
	p->caller = params[offset+1];
	p->sanctionObject = params[offset+2];
	p->permission = params[offset+3];
    }
    else if ( event_id & EVENT_SANCTION_META ) {
	p->caller = params[offset+1];
	p->sanctionObject = params[offset+2];
	p->permission = params[offset+3];
    }
    else if ( event_id & EVENT_ANNOTATE ) {
	p->caller = params[offset+1];
	p->annotationObject = params[offset+2];
    }
    return p;
}

string event_to_description(int event_id, array args)
{
    if ( !arrayp(args) ) 
      return "Event(" + event_id + ", never run)";

    mapping p = event_to_params(event_id, args);
    string desc = timelib.event_time(time()) + " ";

    string objstr = (objectp(p->object) ? p->object->describe() : "null");
    string callerstr = (objectp(p->caller) ? 
			(functionp(p->caller->describe) ? p->caller->describe() : 
			 sprintf("Caller:%O", p->caller)) : "null");

    
    if ( objectp(p->context) ) {
	desc += sprintf("in %s(#%d) ",
			p->context->get_identifier(),  
			p->context->get_object_id());
    }
    if ( event_id & EVENTS_MODULES ) {
	if ( event_id & EVENT_DB_REGISTER ) {
            desc += sprintf("%s DB REGISTER %O", objstr, p->key);
        }
	if ( event_id & EVENT_DB_UNREGISTER ) {
            desc += sprintf("%s DB UNREGISTER %O", objstr, p->key);
        }
    }
    else if ( event_id & EVENTS_SECOND ) {
	if ( event_id & EVENT_GET_INVENTORY ) {
	    desc += sprintf("%s INVENTORY by %s", 
			    objstr, 
			    callerstr);
	}
	else if ( event_id & EVENT_DUPLICATE ) {
	    desc += sprintf("%s DUPLICATE by %s", objstr, callerstr);
	}
	else if ( event_id & EVENT_GRP_ADDMUTUAL ) {
	    desc += sprintf("%s ADD MUTUAL %s by %s",
			    objstr, p->group->describe(),
			    callerstr);
	}
	else if ( event_id & EVENT_STATUS_CHANGED ) {
	    desc += sprintf("%s STATUS CHANGED from %d to %d",
			    objstr, p->oldFeatures, p->newFeatures);
	}
	else if ( event_id & EVENT_REMOVE_ANNOTATION ) {
	    desc += sprintf("%s REMOVE ANNOTATION %s by %s",
			    objstr, 
			    p->annotation->describe(), 
			    callerstr);
	}
        else if ( event_id & EVENT_DOWNLOAD_FINISHED ) {
          desc += sprintf("%s DOWNLOAD FINISHED by %s", objstr, callerstr);
        }
	else if ( event_id & EVENT_LOCK ) {
	}
	else {
	    desc += sprintf("UNKNOWN EVENT: %d %O", event_id, p);
	    desc = replace(desc, "\n", "");
	}
    }
    else if ( event_id & EVENT_ENTER_INVENTORY )
    {
	desc += p->enteringObject->describe()+" enters " + objstr;
    }
    else if ( 	 event_id & EVENT_LEAVE_INVENTORY ) 
    {
	desc += p->leavingObject->describe()+" leaves " + objstr;
    }
    else if ( event_id & EVENT_ATTRIBUTES_CHANGE ) {
	string data = indices(p->data) * ",";
	desc += sprintf("%s MODIFY %s by %s",
			objstr,
			data,
			callerstr);
    }
    else if ( event_id & EVENT_ATTRIBUTES_LOCK ) {
	desc += sprintf("%s %s %s by %s",
			objstr,
			(p->lock?"LOCK":"UNLOCK"),
			p->data,
			callerstr);
    }
    else if ( event_id & EVENT_REGISTER_ATTRIBUTE ) {
	desc += sprintf("%s REGISTER %s by %s",
			objstr,
			p->data,
			callerstr);
    }
    else if ( event_id & EVENT_ATTRIBUTES_ACQUIRE ) {
	desc += sprintf("%s ACQUIRE %s by %s",
			objstr,
			p->data,
			callerstr);
    }
    else if ( event_id & EVENT_USER_CHANGE_PW ) {
	desc += sprintf("%s CHANGE PASSWORD by %s",
			objstr,
			callerstr);
    }
    else if ( event_id & EVENT_ARRANGE_OBJECT ) {
	string data = values(p->data) * ",";
	desc += sprintf("%s ARRANGE %s by %s",
			objstr,
			data,
			callerstr);
    }
    else if ( event_id & EVENT_LISTEN_EVENT ) {
	desc += sprintf("%s LISTEN %s %s by %s",
			objstr,
			translate_eid(p->event),
			(p->event & EVENTS_MONITORED ? "monitored":""),
			callerstr);
    }
    else if ( event_id & EVENT_IGNORE_EVENT ) {
	desc += sprintf("%s IGNORE %s %s by %s",
			objstr,
			translate_eid(p->event),
			(p->event & EVENTS_MONITORED ? "monitored":""),
			callerstr);
    }
    else if ( event_id & EVENT_UPLOAD ) {
	desc += sprintf("%s UPLOAD %s (%d bytes)", 
			objectp(p->user) ? (functionp(p->user->describe)?p->user->describe(): sprintf("%O", p->user)):"null",
			objstr,
			p->size);
    }
    else if ( event_id & EVENT_DOWNLOAD ) {
	desc += sprintf("%s DOWNLOAD", objstr);
    }
    else if ( event_id & EVENT_MOVE ) {
	desc += sprintf("%s MOVE %s from %s to %s",
			objstr,
			(objectp(p->movedByObject)?p->movedByObject->describe():"null"),
			(objectp(p->fromContainer)?p->fromContainer->describe():"null"),
			(objectp(p->toContainer)?p->toContainer->describe():"null"));
    }
    else if ( event_id & EVENT_SAY ) {
	desc += sprintf("%s SAY %s in %s", 
			objstr,
			p->message, 
			p->room->describe());
    }
    else if ( event_id & EVENT_TELL ) {
	desc += sprintf("%s TELL by %s: %s", 
			p->user->describe(),
			p->sender->describe(),
			p->message);
    }
    else if ( event_id & EVENT_LOGIN ) {
	desc += sprintf("%s LOGIN", p->user->describe());
    }
    else if ( event_id & EVENT_LOGOUT ) {
	desc += sprintf("%s LOGOUT", objstr);
    }
    else if ( event_id & EVENT_EXECUTE ) {
	string data = replace(sprintf("%O", p->data), "\n", " ");
	desc += sprintf("%s EXECUTE by %s (%O)", 
			objstr, 
			callerstr,
			data);
    }
    else if ( event_id & EVENT_DELETE ) {
	desc += sprintf("%s DELETE %s",
			objstr,
			callerstr);
    }
    else if ( event_id & EVENT_ADD_MEMBER ) {
	desc += sprintf("%s ADD MEMBER %s by %s",
			objstr,
			p->addObject->describe(),
			callerstr);
    }
    else if ( event_id & EVENT_REMOVE_MEMBER ) {
	desc += sprintf("%s REMOVE MEMBER %s by %s",
			objstr,
			p->removeObject->describe(),
			callerstr);
    }
    else if ( event_id & EVENT_SANCTION ) {
	desc += sprintf("%s SANCTION %s with %d by %s",
			objstr,
			p->sanctionObject->describe(),
			p->permission,
			callerstr);
    }
    else if ( event_id & EVENT_SANCTION_META ) {
	desc += sprintf("%s SANCTION META %s with %d by %s",
			objstr,
			p->sanctionObject->describe(),
			p->permission,
			callerstr);
    }
    else if ( event_id & EVENT_ANNOTATE ) {
	desc += sprintf("%s ANNOTATE with %s by %s",
			objstr,
			p->annotationObject->describe(),
			callerstr);
    }
    else {
	    desc += sprintf("UNKNOWN EVENT: %d %O", event_id, p);
	    desc = replace(desc, "\n", "");

    }
    return desc;
}
