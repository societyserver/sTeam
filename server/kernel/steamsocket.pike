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
 * $Id: steamsocket.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: steamsocket.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "socket"    : socket;
inherit "/net/coal" :   coal;

#include <macros.h>

/**
 * This callback function is the standard function to read data.
 * Most importantly it sets the active user before calling the COAL
 * receive_message function
 *  
 * @param mixed id - no idea, does not do anything
 * @param string data - the received data
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see write_callback
 */
static void read_callback(mixed id, string data)
{
    int su = master()->set_this_user(this_object());
    TRACE("Received " + strlen(data)  + " bytes on socket...");
    mixed err = catch {
	coal::receive_message(data);
    };
    if ( err != 0 ) {
	LOG("Error on command:\n" + PRINT_BT(err));
    }
    if ( su ) master()->set_this_user(0);
}

/**
 * Send a message to the socket.
 *  
 * @param string msg - the coal message for the client
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void send_message(string msg)
{
    socket::send_message(msg);
}

/**
 * Overloaded create method calls create in socket and coal basis
 * objects.
 *  
 * @param object f - the connection (file, whatever)
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void create(object f)
{
    coal::create();
    socket::create(f);
}

/**
 * Register a send function to send data to the socket. This is required,
 * because the socket cannot hold all of the data directly, so everytime
 * there is free space on the socket to write out a message the function
 * is called.
 *  
 * @param function f - the send function
 * @param function e - the function called when sending is finished
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void register_send_function(function f, function e)
{
    socket::register_send_function(f,e);
}

void set_id(int i)
{
    socket::set_id(i);
}

void close_connection()
{
    socket::close_connection();
}

string describe()
{
  return "CoalSocket("+get_id()+", closed="+is_closed_num()+","+get_ip()+")";
}



