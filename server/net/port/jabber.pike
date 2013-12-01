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
 * $Id: jabber.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: jabber.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Stdio.Port;

#include <config.h>
#include <macros.h>

/***
 *
 *
 * @return 
 * @author Thomas Bopp 
 * @see 
 */

void setup_port() 
{
    object          tmp, u;

    tmp = ::accept();
    if ( !objectp(tmp) ) {
	werror("Failed to bind socket !\n");
	return;
    }
    master()->register_user((u=new(OBJ_JABBER, tmp)));
}

/**
 * Gets the program for the corresponding socket.
 *  
 * @return The socket for this port.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
program get_socket_program()
{
    return (program)OBJ_JABBER;
}

bool port_required() { return false; }

bool open_port()
{
    int port_nr = _Server->query_config("jabber_port");
    if ( port_nr == 0 ) 
	port_nr = 5222;

    string ip = _Server->query_config("ip");
    if ( ! stringp(ip) || sizeof(ip)==0 ) ip = 0;
    if ( !bind(port_nr, setup_port, ip) ) {
	werror("Failed to bind jabber port on " + (stringp(ip) ? ip+":" : "port ") + port_nr + " !\n");
	return false;
    }
    MESSAGE("JABBER port opened on " + (stringp(ip) ? ip+":" : "port ") + port_nr);
    return true;
}

string get_port_config()
{
    return "jabber_port";
}

string get_port_name()
{
    return "jabber";
}

bool close_port()
{
    destruct(this_object());
}

int get_port() { return _Server->query_config("jabber_port"); }
string describe() { return "Jabber(#"+get_port()+")"; }    



