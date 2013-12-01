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
 * $Id: login.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: login.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <macros.h>

static object           oUser;
static string    sClientClass;
static int    iClientFeatures;

/**
 * Get the connected user object of this socket.
 *  
 * @return the user object
 * @author Thomas Bopp (astra@upb.de) 
 */
object get_user_object()
{
    return oUser;
}

/**
 * return the object id of this object - the id of the connected user
 *  
 * @return the object id
 * @author Thomas Bopp (astra@upb.de) 
 */
final object get_object_id()
{
    if ( objectp(oUser) )
	return oUser->get_object_id();
    else
	return 0;
}

/**
 * Get the object class of the connected user object.
 *  
 * @return the users object class (CLASS_USER)
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
final int get_object_class()
{
    if ( objectp(oUser) )
	return oUser->get_object_class();
    else
	return 0;
}

/**
 * Get the client description of this socket.
 *  
 * @return client description of the socket.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string get_client_class()
{
    return sClientClass;
}

/**
 * Check if a given object is the user object of this connection.
 *  
 * @param object obj - object to check if its oUser
 * @return true or false
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
final static bool
is_user_object(object obj)
{
    if ( !objectp(obj) || !objectp(oUser) )
	return false;
    if ( obj->get_object_id() == oUser->get_object_id() )
	return true;
    return false;
}

/**
 * Connect this socket object with an user object.
 *  
 * @param object uid - the user to connect to
 * @return the last login of the user
 */
static int login_user(object uid)
{
    if ( objectp(oUser) ) {
	// disconnect other user first
	oUser->disconnect();
    }
    oUser = uid;
    return oUser->connect(this_object());
}

static void logout_user()
{
    if ( objectp(oUser) )
	oUser->disconnect();
}


/**
 * Get the client features of the connection set upon login.
 *  
 * @return client features described in client.h
 * @author Thomas Bopp (astra@upb.de) 
 */
int get_client_features()
{
    return iClientFeatures;
}

int get_status()
{
    return iClientFeatures;
}

string get_identifier()
{
  if ( objectp(oUser) )
    return oUser->get_identifier();
  return "unknown";
}

string describe()
{
  return "~" + (objectp(oUser) ? oUser->get_identifier(): "anonymous");
}
