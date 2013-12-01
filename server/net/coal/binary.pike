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
 * $Id: binary.pike,v 1.2 2009/05/06 19:23:10 astra Exp $
 */

constant cvs_version="$Id: binary.pike,v 1.2 2009/05/06 19:23:10 astra Exp $";

//! Implementation of the COAL binary format. Consult coal documentation for
//! serialization and deserialization of sTeam objects and basic pike
//! types (as well as java).

#include <coal.h>
#include <macros.h>
#include <assert.h>
#include <database.h>

static string     wstr;
static int    iLastTID;

object find_obj(int id)
{
#if constant(_Server)
    return find_object(id);
#endif
}

/**
 * convert an array to binary string
 *  
 * @param arr - the array to send
 * @return the binary representation of the array
 * @author Thomas Bopp (astra@upb.de) 
 * @see send_binary
 */
string send_array(array(mixed) arr)
{
    int  i, sz;
    string str;
    
    sz = sizeof(arr);
    str = "   ";
    str[0] = CMD_TYPE_ARRAY;
    str[1] = (sz & (255<<8)) >> 8;
    str[2] = (sz & 255);    

    for ( i = 0; i < sz; i++ )
	str += send_binary(arr[i]);
    return str;
}

/**
 * convert a mapping to a binary string
 *  
 * @param map - the mapping to send
 * @return the binary representation of the mapping
 * @author Thomas Bopp (astra@upb.de) 
 * @see send_binary
 */
string send_mapping(mapping map)
{
    int  i, sz;
    string str;
    array(mixed) ind;
    
    ind = indices(map);
    sz  = sizeof(ind);
    str = "   ";
    str[0] = CMD_TYPE_MAPPING;
    str[1] = (sz & (255<<8)) >> 8;
    str[2] = (sz & 255);    

    for ( i = 0; i < sz; i++ ) {
	str += send_binary(ind[i]);
	str += send_binary(map[ind[i]]);
    }
    return str;
}

/**
 * convert a variable to a binary string
 *  
 * @param arg - the variable to convert
 * @return the binary representation of the variable
 * @author Thomas Bopp (astra@upb.de) 
 * @see receive_binary
 */
string 
send_binary(mixed arg)
{
    int    len;
    string str;

    if ( zero_type(arg) )
	arg = 0; //send zero

    if ( floatp(arg) ) {
	string floatstr;

	str = "     ";
	floatstr = sprintf("%F", arg);
	str[0] = CMD_TYPE_FLOAT;
	str[1] = floatstr[0];
	str[2] = floatstr[1];
	str[3] = floatstr[2];
	str[4] = floatstr[3];
    }
    else if ( intp(arg) ) {
	str = "     ";
	str[0] = CMD_TYPE_INT;
	if ( arg < 0 ) {
	    arg = -arg;
            arg = (arg ^ 0x7fffffff) + 1; // 32 bit
	    str[1] = ((arg & ( 0xff000000)) >> 24);
	    str[1] |= (0x80);
	}
	else {
	    str[1] = ((arg & ( 0xff000000)) >> 24);
	}
	str[2] = (arg & ( 255 << 16)) >> 16;
	str[3] = (arg & ( 255 << 8)) >> 8;
	str[4] = (arg & ( 255 ));
    }
    else if ( functionp(arg) ) {
	str = "     ";
	string fname;
	object o = function_object(arg);
	if ( !objectp(o) || !functionp(o->get_object_id) )
	    fname = "(function)";
	else
	    fname = "("+function_name(arg) + "():" + o->get_object_id() + ")";

	len = strlen(fname);
	str[0] = CMD_TYPE_FUNCTION;
	str[1] = (len & ( 255 << 24)) >> 24;
	str[2] = (len & ( 255 << 16)) >> 16;
	str[3] = (len & ( 255 << 8)) >> 8;
	str[4] = (len & 255);

	str += fname;
    }
    else if ( programp(arg) ) {
	string prg = master()->describe_program(arg);

	str = "     ";
	len = strlen(prg);
	str[0] = CMD_TYPE_PROGRAM;
	str[1] = (len & 0xff000000) >> 24;
	str[2] = (len & 0x0000ff00) >> 16;
	str[3] = (len & 0x00ff0000) >> 8;
	str[4] = (len & 0x000000ff);
	str += prg;
	
    }
    else if ( stringp(arg) ) {
	str = "     ";
	len = strlen(arg);
	str[0] = CMD_TYPE_STRING;
	str[1] = (len & 0xff000000) >> 24;
	str[2] = (len & 0x00ff0000) >> 16;
	str[3] = (len & 0x0000ff00) >> 8;
	str[4] = (len & 0x000000ff);
	str += arg;
    }
    else if ( objectp(arg) ) {
        int id;
	if ( functionp(arg->serialize_coal) && 
	     arg->serialize_coal!=arg->__null ) 
	{
	   mixed map = arg->serialize_coal();
	   if ( mappingp(map) )
	       return send_mapping(map);
	   id = 0;
	}
	else if ( !functionp(arg->get_object_id) ) {
	  id = 0;
	}
	else if ( functionp(arg->status) 
                  && (arg->status() < 0 || arg->status() == PSTAT_DELETED)) 
	  id = 0;
	else
	  id = arg->get_object_id();


	if ( id >= 0x80000000 ) {
	    str = " ";
	    str[0] = CMD_TYPE_OBJECT;
	    str += compose_object(id);
	}
	else {
	    str = "     ";
	    str[0] = CMD_TYPE_OBJECT;
	    str[1] = (id & ( 255 << 24)) >> 24;
	    str[2] = (id & ( 255 << 16)) >> 16;
	    str[3] = (id & ( 255 << 8))  >>  8;
	    str[4] = (id & ( 255 ));
	}
	
	if ( id == 0 || !functionp(arg->get_object_class) )
	  arg = 0;
	else
	  arg = arg->get_object_class();

	string classStr = "    ";
	classStr[0] = (arg & ( 255 << 24)) >> 24;
	classStr[1] = (arg & ( 255 << 16)) >> 16;
	classStr[2] = (arg & ( 255 << 8))  >>  8;
	classStr[3] = (arg & ( 255 ));
	str += classStr;
    }
    else if ( arrayp(arg) )
	return send_array(arg);
    else if ( mappingp(arg) )
	return send_mapping(arg);
    else
	error("Failed to serialize - unknown type of arg="+sprintf("%O",arg));
    return str;
}

/**
 * a mapping was found at offset position pos
 *  
 * @param pos - the position where the mapping starts in the received string
 * @return the mapping and the end position of the mapping data
 * @author Thomas Bopp (astra@upb.de) 
 * @see receive_args
 */
array(int|mapping)
receive_mapping(int pos)
{
    mapping   map;
    int    i, len;
    mixed     val;
    mixed  ind, v;

    map = ([ ]);
    len = (wstr[pos] << 8) + wstr[pos+1];
    pos += 2;

    for ( i = 0; i < len; i++ )
    {
	val = receive_args(pos);
	pos = val[1];
	ind = val[0];
	val = receive_args(pos);
	pos = val[1];
	v   = val[0];
	map[ind] = v;
    }
    return ({ map, pos });
}

/**
 * an array was found in the received string
 *  
 * @param pos - the startposition of the array data
 * @return the array and the end position
 * @author Thomas Bopp (astra@upb.de) 
 * @see receive_args
 */
array(mixed)
receive_array(int pos)
{
    int    i, len;
    array(mixed)    arr;
    mixed     val;
    
    len = (wstr[pos] << 8) + wstr[pos+1];
    pos += 2;
    arr = allocate(len);
    for ( i = 0; i < len; i++ )
    {
	val = receive_args(pos);
	pos = val[1];
	arr[i] = val[0];
    }
    return ({ arr, pos });
}


/**
 * receive a variable at position i, the type is not yet known
 *  
 * @param i - the position where the variable starts, 
 *            including type information
 * @return the variable and end position in the binary string
 * @author Thomas Bopp (astra@upb.de) 
 * @see send_binary
 */
mixed
receive_args(int i)
{
    int    type, tmp;
    object       obj;
    int          len;
    mixed        res;

    type = wstr[i];
    switch(type) { 
    case CMD_TYPE_INT:
	res = (int)((wstr[i+1]<<24) + (wstr[i+2] << 16) + 
			(wstr[i+3] << 8) + wstr[i+4]);
	if ( res > 0 && res & (1<<31) ) {
	    // conversion from 32 to 64 bit if negative
	    res = (res ^ (0xffffffff)) + 1;
	    res *= -1; // negative
	}
	return ({ res, i+5 });
    case CMD_TYPE_FLOAT:
	string floatstr;
	floatstr = "    ";
	floatstr[0] = wstr[i+1];
	floatstr[1] = wstr[i+2];
	floatstr[2] = wstr[i+3];
	floatstr[3] = wstr[i+4];
	sscanf(floatstr, "%4F", res);
	return ({ res, i+5 });
    case CMD_TYPE_OBJECT:
	tmp = (int)((wstr[i+1]<<24) + (wstr[i+2] << 16) + 
		    (wstr[i+3] << 8) + wstr[i+4]);
	if ( tmp & 0x80000000 ) {
	    int oid_len, namespace_id;
	    
	    namespace_id = (tmp & 0x00ffff00) >> 8;
	    oid_len = (tmp & 0x000000ff);
	    int oid = 0;
	    for ( int x = 0; x < oid_len; x++ ) {
		oid |= ( wstr[i + x + 5] << ( 8 * (oid_len-x-1) ));
	    }
	    tmp = oid | ( tmp << (oid_len*8) );
	    return ({ find_obj(tmp), i+oid_len+9 });
	}
	else {
	    obj = find_obj(tmp);
	    return ({ obj, i+9 });
	}
    case CMD_TYPE_PROGRAM:
    case CMD_TYPE_STRING:
	len = (int)((wstr[i+1]<<24)+(wstr[i+2]<<16) +
		    (wstr[i+3] << 8) + wstr[i+4]);
	return ({ wstr[i+5..i+len-1+5], i+len+5 });
    case CMD_TYPE_FUNCTION:
	len = (int)((wstr[i+1]<<24)+(wstr[i+2]<<16) +
		    (wstr[i+3] << 8) + wstr[i+4]);
	function   f;
	object     o;
	int       id;
	string fname;
	sscanf(wstr[i+5..i+len-1+5], "(%s():%d)", fname, id);
	o = find_obj(id);
	if ( objectp(o) )
	    f = o->find_function(fname);
	return ({ f, i+len+5 });
    case CMD_TYPE_ARRAY:
	return receive_array(i+1);
    case CMD_TYPE_MAPPING:
	return receive_mapping(i+1);
    }
    error("coal::Unknown type "+ type);
}

static string compose_object(int id)
{
    string bitstr = " ";
    while ( id > 0 ) {
	int sid = ( id & 0xff );
	bitstr[0] = sid;
	bitstr = " " + bitstr;
	id = (id >> 8);
    }
    return bitstr;
}

static int receive_object(string str)
{
}


static string coal_compose_header(int t_id, int cmd, int o_id, int class_id)
{
    string scmd = "          ";
    scmd[0] = COMMAND_BEGIN_MASK; /* command begin flag */
    scmd[5] = (t_id & (255 << 24)) >> 24;
    scmd[6] = (t_id & (255 << 16)) >> 16;
    scmd[7] = (t_id & (255 <<  8)) >> 8;
    scmd[8] = t_id & 255;
    scmd[9] = cmd%256;

    string bitstr = "";
    if ( o_id >= 0x80000000 ) {
	// new! long oid supported
	bitstr = compose_object(o_id);
    }
    else {
	bitstr = "    ";
	bitstr[0] = (o_id & (255 << 24)) >> 24;
	bitstr[1] = (o_id & (255 << 16)) >> 16;
	bitstr[2] = (o_id & (255 <<  8)) >>  8;
	bitstr[3] = o_id & 255;
    }
    scmd += bitstr;
    string strClass = "    ";
    strClass[0] = (class_id & (255 << 24)) >> 24;
    strClass[1] = (class_id & (255 << 16)) >> 16;
    strClass[2] = (class_id & (255 <<  8)) >>  8;
    strClass[3] = class_id & 255;
    scmd += strClass;
    return scmd;
}

/**
 * converts a coal command to a binary string
 *  
 * @param t_id - the transaction id
 * @param cmd - the command
 * @param o_id - the relevant object id
 * @param args - the additional args to convert
 * @return the binary string representation
 * @author Thomas Bopp (astra@upb.de) 
 * @see send_binary
 */
string
coal_compose(int t_id, int cmd, object|int o_id, int class_id, mixed args)
{
    string scmd;
    if (objectp(o_id) )
	o_id = o_id->get_object_id();
#if !constant(coal.coal_compose)
    scmd = coal_compose_header(t_id, cmd, o_id, class_id);
    scmd += send_binary(args);
#else
    scmd = coal.coal_compose(t_id, cmd, o_id, class_id);
    string params = coal.coal_serialize(args);
#ifdef VERIFY_CMOD
    // lots of overhead !
    if ( scmd != coal_compose_header(t_id, cmd, o_id, class_id) )
      FATAL("FATAL ERROR in communication header\n%O", scmd);
    string binary_params = send_binary(args);
    if ( params != binary_params ) {
      FATAL("FATAL ERROR in coal arguments when serializing: %O", 
	    args);
      string prefix = String.common_prefix(({params, binary_params}));
      FATAL("Common Prefix:\n%O", prefix);
      FATAL("Rest coal.coal_serialize:\n%O", params[strlen(prefix)-1..]);
      FATAL("Rest serialize:\n%O", binary_params[strlen(prefix)-1..]);
    }
#endif
    scmd += params;
    
#endif

    int slen = strlen(scmd);
    scmd[1] = (slen & 0xff000000) >> 24;
    scmd[2] = (slen & 0x00ff0000) >> 16;
    scmd[3] = (slen & 0x0000ff00) >> 8;
    scmd[4] = (slen & 0x000000ff);

    return scmd;
}

static array|int coal_uncompose_header(string str)
{
    int cmd, t_id, len, i, slen, id, n;
    int offset = 18;

    if ( !stringp(str) )
      return -1; 
    slen = strlen(str);
    if ( slen == 0 )
	return -1;
    for ( n = 0; n < slen-10; n++ )
	if ( str[n] == COMMAND_BEGIN_MASK )
	    break;
    if ( n >= slen-18 ) 
	return -1;

    len    = (int)((str[n+1]<<24) + (str[n+2]<<16) + (str[n+3]<<8) +str[n+4]);
    if ( len+n > slen || len < 12 ) // need whole string in buffer
	return 0;

    t_id   = (int)((str[n+5] << 24) + (str[n+6]<<16) + 
		   (str[n+7]<<8) + str[n+8]);
    cmd    = (int)str[n+9];
    id     = (int)((str[n+10] << 24) + (str[n+11]<<16) + 
		   (str[n+12]<<8) + str[n+13]);
    
    int nid, sid;
    nid = sid = 0;
    // highest bit set - read additional information about server and namespace
    if ( id & 0x80000000 ) { 
	int oid_len, namespace_id;

	namespace_id = (id & 0x00ffff00) >> 8;
	oid_len = (id & 0x00000fff);
        
        if ( oid_len + offset > slen ) 
          throw( ({ "Protocol Error - OID length larger than package",
                      ({ }), t_id, cmd, id }) );
	int oid = 0;
	for ( i = 0; i < oid_len; i++ ) {
	    oid |= ( str[n + i + offset] << ( 8 * (oid_len-i-1) ));
	}
	offset += oid_len;
	id = oid | ( id << (oid_len*8) );
    }
    return ({ t_id, cmd, id, n, len });
}


/**
 * receive_binary
 *  
 * @param str - what is received
 * @return array containing { tid, cmd, obj_id }, args, unparsed rest 
 * @author Thomas Bopp 
 * @see send_binary
 */
static mixed
receive_binary(string str)
{
    int cmd, t_id, len, id, n;
    mixed        result, args;
    int offset = 18;

#if !constant(coal.coal_uncompose)
    result = coal_uncompose_header(str);
    if ( !arrayp(result) )
      return result;
    [ t_id, cmd, id, n, len] = result;

    wstr = str;
    args = receive_args(n+offset);    
    args = args[0];
#else
    if (strlen(str) < 18)
      return -1;
    result = coal.coal_uncompose(str);
    if ( !arrayp(result) )
      return result;
    [ t_id, cmd, id, n, len] = result;
    args = coal.coal_unserialize(str, n+offset, find_obj);
#if constant(check_equal)
#ifdef VERIFY_CMOD
    wstr = str;
    array verify = coal_uncompose_header(str);
    if ( t_id != verify[0] || cmd != verify[1] || id != verify[2] || n != verify[3] ||
	 len != verify[4] )
    {
      FATAL("Error in COAL communication header (receive): \nParsed: %O, Expected: %O",
	    result, verify);
    }
    array params = receive_args(n+offset);
    if (!check_equal(args, params[0])) {
      FATAL("Error in COAL Communication params (receive):\n Parsed: %O, Expected: %O",
	    args, params[0]);
    }
#endif
#endif
#endif
    iLastTID = t_id;
    
    wstr = "";
    return ({ ({ t_id, cmd, id }), args, str[n+len..] });
}






