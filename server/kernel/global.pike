/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: global.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: global.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <macros.h>

static object   _Database = 0;
static object _FileSystem = 0;
static object   _RootRoom = 0;
static object   _GroupAll = 0;
static object   _Security = 0;
static object        _Log = 0;
static object      _Types = 0;
static object _Initialize = 0;


/**
 * set the global objects
 *  
 * @author Thomas Bopp (astra@upb.de) 
 */
void __set(array(object) globals)
{
    if ( objectp(_Initialize) && CALLER != _Initialize && 
	 CALLER != this_object() )
	return;
    
    [ _Security, _Database, _FileSystem, _Types, _Log, _GroupAll, 
    _RootRoom, _Initialize ] = globals;
}

/**
 * get global objects
 *  
 * @return the global objects
 * @author Thomas Bopp (astra@upb.de) 
 */
array(object) __get_globals()
{
    return ({ _Security, _Database, _FileSystem, _Types, _Log, _GroupAll, 
		  _RootRoom, _Initialize });
}

/**
 * return the object class for global objets "0"
 *  
 * @return the object class
 * @author Thomas Bopp (astra@upb.de) 
 */
int get_object_class() 
{
    return 0;
}
