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
 * $Id: securesocket.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: securesocket.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/coalsocket" : socket;
inherit "/net/coal" : coal;

#include <macros.h>
#include <config.h>

void receive_message(string data)
{
    coal::receive_message(data);
}

/**
 * Overloaded create method calls create in socket and coal basis
 * objects.
 *  
 * @param object f - the connection (file, whatever)
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void create(object f, object|void ctx)
{
    coal::create();
    socket::create(f);
}
 
static void send_message(string msg)
{
    socket::send_message(msg);
}

string describe()
{
    return "CoalSocket(closed="+is_closed()+","+get_ip()+")";
}

static void register_send_function(function f, function e)
{
    socket::register_send_function(f, e);
}

void close_connection()
{
  coal::close_connection();
  socket::close_connection();
}







