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
 * $Id: telnet.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: telnet.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

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
    master()->register_user((u=new(OBJ_TELNET, tmp)));
    destruct(tmp);
}

/**
 * Gets the program for the corresponding socket.
 *  
 * @return The socket for this port.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
program get_socket_program()
{
    return (program)OBJ_TELNET;
}

bool port_required() { return false; }
string describe() { return "Telnet(#"+get_port()+")"; }    
int get_port() { return _Server->query_config("telnet_port"); }

bool open_port()
{
    int port_nr = _Server->query_config("telnet_port");
    string hostname = _Server->query_config("telnet_host");

    if (  port_nr == 0 )
	port_nr = 2000; //23; must be root ?
    if (!hostname)
        hostname = _Server->query_config("ip");
    if(!hostname)
        hostname="localhost";

    if ( !bind(port_nr, setup_port, hostname) ) {
	werror("Failed to open telnet socket on %s:%d !\n", hostname, port_nr);
	return false;
    }
    MESSAGE("Telnet port opened on " + hostname + ":" + port_nr);
    return true;
}

bool close_port()
{
    return true;
}

string get_port_config()
{
    return "telnet_port";
}

string get_port_name()
{
    return "telnet";
}

