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
 * $Id: Attributes.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Attributes.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <attributes.h>
#include <exception.h>
#include <events.h>
#include <types.h>
#include <macros.h>

#define WRONG_TYPE(key, expected, data) THROW("Wrong value to attribute "+ key +" (expected "+expected+" got "+sprintf("%O",_typeof(data))+").", E_ERROR)

/** @defgroup attribute 
 *  Attribute functions
 */
    

/**
 * @ingroup attribute
 */
class Attribute {
    static string     a_key; // the name of the attribute
    static int    a_classid; // corresponding class id of this Attribute
    static string    a_desc; // description of the attribute
    static int      a_cntrl; // who/what controls this attribute
    static int       a_type;
    static mixed   a_defval; // the default value
    static object converter;

    // value is stored somewhere else ...
    // if set to a string a function name is meant
    static string|object a_acquire; 
    
    // coupled events
    static int a_event_read;
    static int a_event_write;

    mixed get_default_value() { return a_defval;  }
    void set_default_value(mixed v) { a_defval = v; }
    string get_description() {	return a_desc;  }
    string|int get_key() { return a_key;   }
    int get_type() { return a_type; }
    object|function get_acquire() { return a_acquire; }
    int get_read_event() { return a_event_read;  }
    int get_controler() { return a_cntrl; }
    int get_class() { return a_classid; }
    int get_write_event() { return a_event_write; }
    void set_read_event(int re) { a_event_read = re; }
    void set_write_event(int we) { a_event_write = we; }
    void set_acquire(string|object acq) { a_acquire = acq; }
    void set_converter(object script) { converter = script; }

    void create(string|int key, string desc, int type, mixed def_val, 
		void|string|object acq, void|int cntrl, 
		void|int read_event, void|int write_event)
    {
	a_key = key;
	a_desc = desc;
	a_type = type;
	a_cntrl = cntrl;
	a_acquire = acq;
	a_defval = def_val;
	a_event_read = read_event;
	if ( zero_type(write_event) )
	    a_event_write = EVENT_ATTRIBUTES_CHANGE;
	else
	    a_event_write = write_event;
    }
    int check_convert(object obj) {
      if ( objectp(converter) ) { 
        if ( functionp(converter->convert_attribute) ) {
          converter->convert_attribute(this_object(), obj);
          return 1;
        }
      }
      return 0;
    }

    bool check_attribute(mixed data) 
    {
	switch(a_type) {
	case CMD_TYPE_INT:
	    if ( !intp(data) ) WRONG_TYPE(a_key, "int", data);
	    break;
	case CMD_TYPE_FLOAT:
	    if ( !floatp(data) ) WRONG_TYPE(a_key, "float", data);
	    break;
	case CMD_TYPE_STRING:
	    if ( !stringp(data) ) WRONG_TYPE(a_key, "string", data);
	    if ( !xml.utf8_check(data) )
		steam_error("Non-utf8 data for Attribute " + a_key + " !");
	    break;
	case CMD_TYPE_OBJECT:
	    if ( !objectp(data) ) WRONG_TYPE(a_key, "object", data);
	    break;
	case CMD_TYPE_ARRAY:
	    if ( !arrayp(data) ) WRONG_TYPE(a_key, "array", data);
	    break;
	case CMD_TYPE_MAPPING:
	    if ( !mappingp(data) ) WRONG_TYPE(a_key, "mapping", data);
	    break;
	case CMD_TYPE_PROGRAM:
	    if ( !programp(data) ) WRONG_TYPE(a_key, "program", data);
	    break;
	case CMD_TYPE_FUNCTION:
	    if ( !programp(data) ) WRONG_TYPE(a_key, "function", data);
	    break;
	}
	return true;
    }

    int `==(Attribute a) {
	if ( !objectp(a) || !functionp(a->get_default_value) )
	    return 0;
	return 
	    equal(a_defval, a->get_default_value()) &&
	    a_key == a->get_key() &&
	    a_acquire == a->get_acquire() &&
	    a_type == a->get_type();
    }
    mapping serialize_coal() {
      return ([ "key": a_key,
		"type": a_type,
		"description": a_desc,
		"eventRead": a_event_read,
		"eventWrite": a_event_write,
		"acquire": a_acquire,
		"default": a_defval,
		"control": a_cntrl, 
                "converter": converter, ]);
    }
  
    mixed `[](int index) {
	switch(index) {
	case REGISTERED_TYPE:
	    return a_type;
	case REGISTERED_DESC:
	    return a_desc;
	case REGISTERED_EVENT_READ:
	    return a_event_read;
	case REGISTERED_EVENT_WRITE:
	    return a_event_write;
	case REGISTERED_ACQUIRE:
	    return a_acquire;
	case REGISTERED_DEFAULT:
	    return a_defval;
	case REGISTERED_CONTROL:
	    return a_cntrl;
	}
    }
    
    string describe() { 
	return "Attribute("+a_key+", "+ a_desc + ", acq="+
	    (objectp(a_acquire) ? a_acquire->get_object_id(): a_acquire)+
	    ",default="+ (objectp(a_defval) ? a_defval->get_object_id():
			  (stringp(a_defval) || intp(a_defval) ? 
			   a_defval : sprintf("%O", a_defval)))+  ")";
    }
    string _sprintf() {
      return describe();
    }

    mapping save() {
	return ([
	    "key": a_key,
	    "desc": a_desc,
	    "acquire": a_acquire,
	    "def": a_defval,
	    "type": a_type,
	    "control": a_cntrl,
	    "event_read": a_event_read,
	    "event_write": a_event_write,
            "converter": converter,
	    ]);
    }

    void load(mapping data) {
    }
}

class UserAttribute {
    inherit Attribute;
    
    void create(string|int key, string desc, int type, mixed def_val)
    {
	::create(key, desc, type, def_val, 
		 0, 
		 CONTROL_ATTR_SERVER, 
		 0, 
		 EVENT_ATTRIBUTES_CHANGE);
    }
}

class PositionAttribute {
    inherit Attribute;
    
    void create(string|int key, string desc, int type, mixed def_val) {
	::create(key, desc, type, def_val, 
		 0, 
		 CONTROL_ATTR_CLIENT, 
		 0, 
		 EVENT_ARRANGE_OBJECT);
    }
}

class FreeAttribute {
    inherit Attribute;
    
    void create(string|int key, string desc, int type, mixed def_val)
    {
	::create(key, desc, type, def_val, 
		 0, 
		 CONTROL_ATTR_SERVER, 
		 0, 
		 0);
    }
}
