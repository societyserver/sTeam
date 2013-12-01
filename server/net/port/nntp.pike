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
 * $Id: nntp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: nntp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

//inherit SSL.sslport;
inherit Stdio.Port;

import cert;

#include <config.h>
#include <macros.h>

static object context;

//#define NNTP_DEBUG

#ifdef NNTP_DEBUG
#define NNTP_LOG(s, args...) werror("[nntp](port) " + s +"\n", args);
#else
#define NNTP_LOG(s, args...)
#endif

void setup_port () 
{
    NNTP_LOG("setup_port()");
    object          tmp, u;
    tmp = ::accept();
    if ( !objectp(tmp) ) {
	werror("Failed to bind socket !\n");
	return;
    }
    master()->register_user((u=new(OBJ_NNTP, tmp, context)));
}

/**
 * Gets the program for the corresponding socket.
 *  
 * @return The socket for this port.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
program get_socket_program ()
{
    NNTP_LOG("get_socket_program()");
    return (program)OBJ_NNTP;
}

/**
 * Open the port on the configured value (nntp_port).
 *  
 * @return true or false.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
bool open_port ()
{
    NNTP_LOG("open_port()");
    int port_nr = get_port();

    if ( port_nr == 0 ) 
	port_nr = 119;

    string ip = _Server->query_config("ip");

    NNTP_LOG("NNTP port trying to open on " + pretty_port_ip( port_nr, ip ) );

    if ( ! stringp(ip) || sizeof(ip)==0 ) ip = 0;
    if ( !bind(port_nr, setup_port, ip) ) {
        werror(  "Failed to bind nntp port on " + pretty_port_ip( port_nr, ip ) + " !\n");
	NNTP_LOG("Failed to bind nntp port on " + pretty_port_ip( port_nr, ip ) + " !\n");
	return false;
    }
    MESSAGE("NNTP port opened on " + pretty_port_ip( port_nr, ip ) );

    LOG("NNTP Port registered on " + pretty_port_ip( port_nr, ip ));
    return true;
}

string get_port_config () { return "nntp_port"; }
string get_port_name () { return "nntp"; }
bool   port_required () { return false; }
int    get_port () { return  _Server->query_config("nntp_port"); }
string describe () { return "NNTP(#"+get_port()+")"; }

string pretty_port_ip ( int port_nr, void|string ip )
{
  return (stringp(ip) ? ip+":" : "port ") + port_nr;
}
