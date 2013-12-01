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
 * $Id: events.pike,v 1.2 2009/05/06 19:23:10 astra Exp $
 */

constant cvs_version="$Id: events.pike,v 1.2 2009/05/06 19:23:10 astra Exp $";

//! sTeam event support - uses Events from Event.pmod and supports
//! listeners. Each event is also triggered globally through the server
//! object (_Server constant).

#include <macros.h>
#include <events.h>
#include <access.h>
#include <assert.h>
#include <database.h>
#include <classes.h>
#include <config.h>

import Events;

#ifdef EVENT_DEBUG
#define DEBUG_EVENT(s, args...) werror(s+"\n", args)
#else
#define DEBUG_EVENT(s, args...)
#endif

private static mapping    mEvents; // list of event listening objects
private static mapping mListeners; // list of events this object listens to

object                   this();
object        get_environment();
int             get_object_id();
static void      require_save(void|string a, void|string b);
object         get_annotating();

class SteamEvent {
    inherit Event;
    
    void notify_listener(object l, mixed args) {
      if ( l->get_phase() == PHASE_NOTIFY ) {
	  mixed err = catch(::notify_listener(l, args));
	  if ( err != 0 ) {
		FATAL("Error on Event: %s\n%s", 
		      err[0],
		      describe_backtrace(err[1]));
		remove_listener(l);
	  }
      }
      else {
	  ::notify_listener(l, args);
      }
    }
    mapping get_params() {
	mapping p = ::get_params();
	p->user = this_user();
	return p;
    }
    // add persistence
    mapping save() {
	mapping s = ([ "listeners": ({ }), "event": get_event(), ]);
	array listeners = get_listeners();
	mixed err = catch {
	    foreach( listeners, object l ) {
		if ( objectp(l) ) {
		  if ( !functionp(l->save) )
		    FATAL("Cannot save listener: %s\n", 
			  (l->describe?l->describe():""));
		  else {
		    mixed data = l->save();
		    if ( data )
		      s->listeners += ({ data });
		  }
		}
	    }
	};
	return s;
    }
    void load(mapping data) {
	if ( !mappingp(data) || data->event == 0 )
	    return;
	set_event(data->event);
	foreach( data->listeners, mapping ldata ) {
	    if ( !mappingp(ldata) ) continue;
	    SteamListener l =
		SteamListener(ldata->id, 
			      ldata->phase, 
			      ldata->obj, 
			      ldata->callback,
			      ldata->objEvents);
	    add_listener(l);
	}
    }
}

class SteamListener {
    inherit Listener;
    
    void 
    create(int|void eid,int|void phase,object|void obj,function|void callback, int|void oEvents)
    {
	::create(eid, phase, obj, callback, 0);
	if ( oEvents )
	    setObjectEvents();
    }

    mapping save() {
	return ([ 
	    "id":get_event(),
	    "obj": get_object(),
	    "phase": get_phase(),
	    "callback": get_callback(),
	    "objEvents": getObjectEvents(),
	    ]);
    }
    
    void load(mapping data) {
	set(data->id, data->phase, data->obj, data->callback);
	if ( data->objEvents )
	    setObjectEvents();
    }

}

/**
 * init_events() need to be called by create() in the inheriting object.
 * The function only initializes the event mappings.
 *  
 * @author Thomas Bopp 
 */
final static void 
init_events()
{
    mEvents   = ([ ]);
    mListeners = ([ ]);
}

/**
 * A function calls event() to define a new event. Other objects are then
 * able to listen or block this event. Callback functions always include
 * the event-type as first parameter, because it is possible to use
 * one event function for several events. This function is to be used
 * in own program code to allow other objects to block actions which 
 * are currently taking place. 
 * The try_event() call should be before the action actually took place, 
 * because there is no rollback functionality.
 *  
 * @param event - the type of the event, all events are located in events.h
 * @param args - number of arguments for that event
 * @return ok or blocked
 * @see add_event
 * @see run_events
 * @see run_event
 */
final static void
try_event(int event, mixed ... args)
{
    if ( event == 0 ) return;
    if ( !objectp(this()) ) return; // object not ready yet (eg being created)
    SteamEvent e = mEvents[event];
    _Server->run_global_event(event, PHASE_BLOCK, this(), args);
    if ( objectp(e) )
	e->run_event(PHASE_BLOCK, ({ this() }) + args);
}

final static void
low_run_event(int event, array monitoring_stack, mixed ... args)
{
    mixed err;

    if ( event == 0 ) return;
    if ( !objectp(this()) ) return; // object no ready yet !
    SteamEvent e = mEvents[event];
    _Server->run_global_event(event, PHASE_NOTIFY, this(), args);  
    if (objectp(e) ) {
        if ( err = catch(e->run_event(PHASE_NOTIFY, ({ this() }) + args)) ) {
            FATAL("Error during notify Event: %O\n%O", err[0], err[1]);
        }
        else
          DEBUG_EVENT("running event {%d} %s", 
                      this()->get_object_id(), e->describe());
    }

    //let the environment be notified about the event,if not allready monitored
    object env = get_environment();
    if ( objectp(env) ) 
	env->monitor_event(event, monitoring_stack, this(), @args);
     
    // for our annotating object also monitor...
    object annotates = this_object()->get_annotating();
    if ( objectp(annotates) ) {
	if ( this_object()->get_object_class() & CLASS_FACTORY )
	    return;
	annotates->monitor_event(event, monitoring_stack, this(), @args);
    }
}

/**
 * Call this function to run an event inside this object. The integer
 * event type is the first argument and each event has a diffent number
 * of arguments. The difference to try_event is that run_event cannot be
 * blocked. This function is to be used in own program code. It makes
 * add_event possible for other objects to be notified about the action
 * which currently takes place.
 *  
 * @param int event - the event to fire
 * @param mixed ... args - a list of arguments for this individual event
 * @see try_event
 * @see run_events
 */
final static void run_event(int event, mixed ... args) 
{
  low_run_event(event, ({ }), @args);
}

/**
  * this functions monitors the attributes of the objects in
  * the containers inventory and fires a EVENT_ATTRIBUTES|EVENTS_MONITORED
  * event.
  *  
  * @param obj - the monitored object
  * @param caller - the object calling set_attribute in 'obj'
  * @param args - some args, like key and value
  */
void monitor_event(int event, array monitoring_stack, object obj, mixed ... args)
{
    if ( !functionp(obj->get_object_id) ||
	 CALLER->get_object_id() != obj->get_object_id() ) 
	return;
    if (search(monitoring_stack, this())>=0) {
      FATAL("Loop in monitoring detected %O, %O", monitoring_stack, this());
      return; // monitoring loop!
    }

    if ( event & EVENTS_MONITORED )
      low_run_event(event, monitoring_stack + ({ this() }), @args);
    else	
      low_run_event(event|EVENTS_MONITORED, monitoring_stack+({this()}),obj,@args);
}



/**
 * Add a new event to this object. The listener object needs to define
 * a callback function. The call will then include some parameters of which
 * the first will always be the event-type.
 * Do not call this function yourself. Call add_event instead, otherwise
 * the data structure that connects listener object and event object will
 * be invalid.
 *  
 * @param type - the event type to add
 * @param callback - the function to call when event happens
 * @return id of the event or FAIL (-1)
 * @author Thomas Bopp 
 * @see remove_event
 */
final object
listen_event(Listener nlistener)
{
    SteamEvent e;
    int event = nlistener->get_event();

    try_event(EVENT_LISTEN_EVENT, CALLER, event, nlistener->get_phase());
    
    DEBUG_EVENT("new event.... = "+ event + " on #"+get_object_id());
    // check what events the listener listens to
    array events = split_events(event);

    foreach( events, event ) {
      e = mEvents[event];
      if ( !objectp(e) ) {
	  e = SteamEvent(event);
      }
      object nlist = e->add_listener(nlistener);
      if ( nlist->get_listener_id() != nlistener->get_listener_id() ) {
	return nlist;
      }
      mEvents[event] = e;
    }
    require_save(STORE_EVENTS);

    run_event(EVENT_LISTEN_EVENT, CALLER, 
	      nlistener->get_event(), nlistener->get_phase());
    return nlistener;
}

/**
 * This is the most central function to be used for subscribing events.
 * Add an event to object obj, the event will be stored in the local 
 * event list. The callback function will be called with the event-id
 * (in case there is one callback function used for multiple events),
 * then the object is provided where the event took place and a number
 * of parameters are passed depending on the event.
 * callback(event-id, object, params)
 *  
 * @param obj - the object to listen to
 * @param event - the event type
 * @param phase - notify or block phase
 * @param callback - the callback function
 *
 * @return event id or fail (-1), but usually will throw an exception
 * @see listen_event
 */
static object 
add_event(object obj, int event, int phase, function callback)
{
    ASSERTINFO(_SECURITY->valid_proxy(obj), "No add event on non proxies !");

    if ( phase == PHASE_BLOCK )
	_SECURITY->access_write(0, this_object(), CALLER);
    else
	_SECURITY->access_read(0, this_object(), CALLER);
    
    SteamListener nlistener = 
	SteamListener(event, phase, this_object(), callback);

    /* the key for mListeners is event/obj/callback */
    if ( !mappingp(mListeners[event]) )
	mListeners[event] = ({ });

    object nlisten = obj->listen_event(nlistener);
    // this one has been added
    if ( nlistener->get_listener_id() == nlisten->get_listener_id() ) 
	mListeners[event] += ({ nlistener });
    else if ( search(mListeners[event], nlisten) == -1 )
	mListeners[event] += ({ nlisten });
    
    return nlisten;
}

static object addEvent(object obj, int event, int phase, function callback)
{
    object listener = add_event(obj, event, phase, callback);
    if ( objectp(listener) )
	listener->setObjectEvents();
    return listener;
}

void restore_listener(object listener)
{
    int event = listener->get_event();
    if ( !mappingp(mListeners[event]) )
	mListeners[event] = ({ });
    mListeners[event] += ({ listener });
}

/**
 * remove an event, it is removed from the object and this object
 * only the local function for remove and add should be called.
 * Event-type, function and object are the identifier for an object.
 * No object should listen to an event through one callback function twice.
 * 
 *  
 * @param obj - the object to listen to
 * @param event - the type of event
 * @param id - function or identifier
 * @return true or false
 * @author Thomas Bopp (astra@upb.de) 
 * @see ignore_event
 */
final static bool remove_event(object obj, int event, function|object id) 
{
    /* event does not exists */
    if ( !mappingp(mListeners[event]) )
	return false;

    /* remove by function pointer, if no functionp is given search
     * it by the given event-id */
    if ( functionp(id) ) {
        int save=0;
	foreach(mListeners[event], Listener l) {
	    if ( l->event_function == id ) {
		mListeners[event] -= ({ l });
		obj->ignore_event(l);
                save=1;
		return true;
	    }
	}
        if (save)
            require_save(STORE_EVENTS);
    }
    else {
	mListeners[event] -= ({ id });
	obj->ignore_event(id);
        require_save(STORE_EVENTS);
	return true;
    }
    return false;
}

/**
 * Listener object removes an event. The event id is what add_event()
 * returns. Usually the function shouldnt be called. It is called
 * automatically, when the function remove_event() is called.
 *  
 * @param event - the type of event
 * @return true or false
 * @author Thomas Bopp 
 * @see add_event
 * @see remove_event
 */
final bool ignore_event(Listener l)
{
    int event = l->event_id;

    SteamEvent e = mEvents[event];
    if ( !objectp(e) )
	return false;

    try_event(EVENT_IGNORE_EVENT, CALLER, event);

    e->remove_listener(l);
    destruct(l);
    require_save(STORE_EVENTS);
    run_event(EVENT_IGNORE_EVENT, CALLER, event);
    return true;
}

/**
 * Get a list of listening objects. The returned mapping is in the form
 * event: array of listening objects.
 *  
 * @return list of listening objects
 * @author Thomas Bopp (astra@upb.de) 
 * @see get_my_events
 */
final mapping get_events()
{
    return copy_value(mEvents);
}

/**
 * Returns the mapping entry for a given event. For example the function
 * could be called with get_event(EVENT_MOVE). Check the file include/events.h
 * for a list of all events.
 *  
 * @param int event - the event to return
 * @return array of listening objects
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see get_events
 */
final array get_event(int event)
{
    return copy_value(mEvents[event]);
}


/**
 * Get a list of events this object listens to. 
 *  
 * @return mapping of array this objects listens to (listeners)
 * @see get_events
 */
final mapping get_listeners()
{
    foreach( indices(mListeners), int event )
	mListeners[event] -= ({ 0 });
    return copy_value(mListeners);
}

/**
 * Get the mapping of events subscribed on object 'where' or 0 if there is
 * no entry of 'event'.
 *  
 * @param int event - the event
 * @param object where - The object to check for subscription
 * @return the listener object.
 */
final object get_listener(int event, object where)
{
    if ( !mappingp(mListeners[event]) )
	return 0;
    foreach( mListeners[event], object l )
	if ( l->get_object() == where )
	    return l;
    return 0;
}

/**
 * restore the events of an object
 *  
 * @param data - the event data for the object
 * @author Thomas Bopp (astra@upb.de) 
 * @see retrieve_events
 */
final void
restore_events(mixed data)
{
    ASSERTINFO(CALLER == _Database, "Invalid call to restore_events()");
    
    if ( !mappingp(data) || data->Events )
	return;
    
    if ( equal(data, ([ ])) )
	return;

    mEvents = ([ ]);

    foreach(indices(data), int event) {
	if ( !mappingp(data[event]) )
	    continue;
	object e = SteamEvent(0);
	e->load(data[event]);
	mEvents[event] = e;
	foreach(e->get_listeners(), object l) {
	    object o = l->get_object();
	    if ( objectp(o) )
		o->restore_listener(l);
	}
    }
}


/**
 * retrieve the event data of the object
 *  
 * @return the events of the object
 * @author Thomas Bopp (astra@upb.de) 
 * @see restore_events
 */
final mapping
retrieve_events()
{
    ASSERTINFO(CALLER == _Database, "Invalid call to retrieve_events()");
    mapping em = map(mEvents, save_events);
    
    return em;
}

static mapping save_events(SteamEvent event)
{
    return event->save();
}

static array save_listeners(array listeners)
{
    array result = ({ });
    foreach (listeners, object l) {
	if ( objectp(l) && functionp(l->save) )
	    result += ({ l->save() });
    }
    return result;
}
