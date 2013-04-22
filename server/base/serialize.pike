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
 * $Id: serialize.pike,v 1.2 2009/05/02 05:44:39 astra Exp $
 */

constant cvs_version="$Id: serialize.pike,v 1.2 2009/05/02 05:44:39 astra Exp $";

/*
 * serialization mechanisms for sTeam. They are inherited into _Database and
 * made availiable via add_constant. If you really have to inherit this file,
 * note that you have to provide an implementation for the prototype
 * find_object(), see database.pike for an example. Since _Database inherits
 * serialize.pike, it is compiled without the add_constant on
 * _Database->find_object(), so you can't rely on the constant. If your Object
 * knows about _Database you could do
 * object find_object(int oid) { return _Database->find_object(oid); }
 */


#include <macros.h>
#include <database.h>
#include <attributes.h>

object find_object(int id);
//object oLocal;   // assume this to be this_object()

private static string  serialize_object(object obj);
private static string  serialize_mapping(mapping map);
private static string  serialize_array(array(mixed) arr);
private static string  serialize_function(function f);
        string  serialize(mixed arg,void|string encoding);
private static mapping unserialize_map(string stream);
private static array(mixed)  unserialize_array(string stream);
private static int     unserialize_number(string stream);
private static function unserialize_function(string stream);
        mixed   unserialize(string stream, void|object oThis);
private static object  unserialize_object(string stream);

private Thread.Local fStringSerializer = Thread.Local();

#define STRING_CLOSED 1
#define STRING_OPEN   2
#define STRING_MASKED 4

private static string
serialize_object(object obj)
{
  if ( !functionp(obj->get_object_id) ) {
    return "";
  }
  int oid = obj->get_object_id();
  return "%" + oid;
}

private static string
serialize_function(function f)
{
    int iFOID;
    object  o;
    
    o = function_object(f);
 
    if ( !objectp(o) || !functionp(o->get_object_id) ) return 0;
    
    iFOID = o->get_object_id();
    return "$" + function_name(f) + " " + iFOID;
}

private static string
serialize_mapping(mapping map)
{
    int       i, sz;
    string composed;
    mixed       val;
    array(mixed)    index;
    
    index = indices(map);

    composed = "[";
    for ( i = 0, sz = sizeof(index); i < sz; i++ ) {
	if ( stringp(index[i]) )
	    composed += "\"" + index[i] + "\":";
	else if ( objectp(index[i]) )
	    composed += serialize_object(index[i])  + ":";
	else if ( arrayp(index[i]))
	    composed += serialize_array(index[i]) + ":";
	else if ( functionp(index[i]))
	    composed += serialize_function(index[i]) + ":";
	else
	    composed += index[i] + ":";
	val = map[index[i]];

	if ( arrayp(val) )
	    composed += serialize_array(val) + ",";
	else if ( mappingp(val) )
	    composed += serialize_mapping(val) + ",";
	else if ( stringp(val) )
	    composed += fStringSerializer->get()(val) + ",";
	else if ( objectp(val) )
	    composed += serialize_object(val) + ",";
	else if ( functionp(val) )
	    composed += serialize_function(val) + ",";
	else
	    composed += val + ",";
    }
    composed += "]";
    return composed;    
}

private static string
serialize_array(array(mixed) arr)
{
    int       i, sz;
    string composed;
    
    composed = "{";
    for ( i = 0, sz = sizeof(arr); i < sz; i++ ) {
	if ( arrayp(arr[i]) )
	    composed += serialize_array(arr[i]) + ",";
	else if ( mappingp(arr[i]) )
	    composed += serialize_mapping(arr[i]) + ",";
	else if ( stringp(arr[i]) )
            // composed += "\"" + replace(arr[i],"\"","\\char34") + "\",";
            composed += fStringSerializer->get()(arr[i]) + ",";
	else if ( objectp(arr[i]) )
	    composed += serialize_object(arr[i]) + ",";
	else if ( functionp(arr[i]) )
	    composed += serialize_function(arr[i]) + ",";
	else if ( intp(arr[i]) )
	    composed += sprintf("%d,", arr[i]);
	else
	  composed += sprintf("%O,", arr[i]);
    }
    composed += "}";    
    return composed;
}

private static string serialize_string(string s)
{
    return "\"" + replace(s, "\"", "\\char34") + "\"";
}

private static string serialize_utf8(string s)
{
    return "\"" + string_to_utf8(replace(s, "\"", "\\char34")) + "\"";
}

string
serialize(mixed arg, void|string encoding)
{
    if (encoding == "utf-8")
        fStringSerializer->set(serialize_utf8);
    else
        fStringSerializer->set(serialize_string);
    
    if ( arrayp(arg) )
	return serialize_array(arg);
    else if ( mappingp(arg) )
	return serialize_mapping(arg);
    else if ( stringp(arg) )
        //	return "\"" + replace(arg,"\"", "\\char34") + "\"";
        return fStringSerializer->get()(arg);
    else if ( objectp(arg) )
	return serialize_object(arg);
    else if ( functionp(arg) )
	return serialize_function(arg);
    else
	return (string) arg;
}


private static array(mixed)
unserialize_array(string sArray)
{
    int          i, len;
    int  open_arr_brace;
    int  open_map_brace;
    int           start;
    array(mixed)    arr;
    string         part;
    int     open_string;

    arr = ({ });
    len = strlen(sArray);
    i   = 0; start = 0;
    open_arr_brace = 0;
    open_map_brace = 0;

    open_string = STRING_CLOSED;

    while ( len > i  ) {
	if ( sArray[i] == '\"' && !(open_string & STRING_MASKED) ) {
	    if ( open_string & STRING_CLOSED )
		open_string = STRING_OPEN;
	    else
		open_string = STRING_CLOSED;
	}
	else if ( sArray[i] == '\\' ) {
	    open_string |= STRING_MASKED;
	}
	else if ( open_string == STRING_CLOSED )
	{
	    if ( sArray[i] == '{' ) {
		open_arr_brace++;
	    }
	    else if ( sArray[i] == '[' ) {
		open_map_brace++;
	    }
	    else if ( sArray[i] == '}' ) {
		open_arr_brace--;
	    }
	    else if ( sArray[i] == ']' ) {
		open_map_brace--;
	    }
	    else if ( sArray[i] == ',' && 
		      open_arr_brace == 0 && 
		      open_map_brace == 0 ) 
	    {
		part = sArray[start..i-1];
                mixed res = unserialize(part);
		arr += ({ res });
		start = i+1;
	    }
	    if ( open_string & STRING_MASKED )
		open_string -= STRING_MASKED;
	}
	else if ( open_string & STRING_MASKED )
	    open_string -= STRING_MASKED;
	i++;
    }
    return arr;
}


#define EXTRACT_MODE_INDEX 1
#define EXTRACT_MODE_DATA  2

private static mapping
unserialize_map(string map)
{
    mapping        mapp;
    int          i, len;
    int  open_arr_brace;
    int  open_map_brace;
    int           start;
    int            mode;
    string         part;
    mixed         index;
    int     open_string;

    len = strlen(map);
    i   = 0; start = 0;
    open_arr_brace = 0;
    open_map_brace = 0;
    mapp = ([ ]);

    /* 
     * first thing expected is an index ...
     */
    mode = EXTRACT_MODE_INDEX;
    open_string = STRING_CLOSED;

    while ( len > i ) {
	if ( map[i] == '\"' && !(open_string & STRING_MASKED) )
	{
	    if ( open_string & STRING_CLOSED )
		open_string = STRING_OPEN;
	    else
		open_string = STRING_CLOSED;
	}
	else if ( map[i] == '\\' ) {
	    open_string |= STRING_MASKED;
	}
	else if ( open_string == STRING_CLOSED )
	{
	    if ( mode == EXTRACT_MODE_INDEX )
	    {
		/* no [ or { here */
		if ( map[i] == ':' )
		{
		    part = map[start..i-1];
		    index = unserialize(part);
		    start = i+1;
		    mode = EXTRACT_MODE_DATA;
		}
	    }
	    else
	    {
		if ( map[i] == '{' ) {
		    open_arr_brace++;
		}
		else if ( map[i] == '[' ) {
		    open_map_brace++;
		}
		else if ( map[i] == '}' ) {
		    open_arr_brace--;
		}
		else if ( map[i] == ']' ) {
		    open_map_brace--;
		}
		else if ( map[i] == ',' && 
			  open_arr_brace == 0 && 
			  open_map_brace == 0 ) 
		{
		    part = map[start..i-1];
		    
/*		    ASSERTINFO(stringp(index) || intp(index) || 
			       objectp(index) || arrayp(index), 
			       "False index, not string, integer, "+
			       "object or array!");*/
		    mapp[index] = unserialize(part);
		    start = i+1;
		    mode = EXTRACT_MODE_INDEX;
		}
	    }
	}
	else if ( open_string & STRING_MASKED )
	    open_string -= STRING_MASKED;
	i++;
    }
    return mapp;
}

private static mixed
unserialize_number(string str)
{
    mixed res;
    int  a, b;

    if ( sscanf(str, "%d.%d", a, b) == 2 ) {
	sscanf(str,"%f", res);
	return (float)res;
    }
    sscanf(str, "%d", res);
    return (int)res;
}

private static object
unserialize_object(string stream)
{
    int      res;
    object proxy;

    sscanf(stream, "%d", res);
    
    proxy = find_object(res);

    return proxy; 
}

private static function
unserialize_function(string f)
{
    object             o;
    mixed            res;
    int             iOID;
    string sFunctionName;

    
    if ( sscanf(f, "%s %d",  sFunctionName, iOID) == 2 ) {
	o = find_object(iOID);
    }
    else
	return 0;
    
    if (objectp(o))
    {
	if ( !functionp(o->get_function) ) 
	    return 0;
	res = o->get_function(sFunctionName);
    }
    else
	res = 0;// failed to unserialize function
    return res;
}

mixed
unserialize(string stream, void|object oThis)
{
    int len = strlen(stream);

    if ( len == 0 )
	return 0;
    if ( stream[0] == '\"' )
	return replace((string)stream[1..len-2], "\\char34", "\"");
    else if ( stream[0] == '\{' )
	return (array(mixed))unserialize_array(stream[1..len-2]);
    else if ( stream[0] == '\[' )
	return (mapping)unserialize_map(stream[1..len-2]);
    else if ( stream[0] == '#' )
	return unserialize_object(stream[1..len-1]);
    else if ( stream[0] == '%')
	return unserialize_object(stream[1..len-1]);
    else if ( stream[0] == '$')
	return unserialize_function(stream[1..len-1]);

    return unserialize_number(stream);
}

