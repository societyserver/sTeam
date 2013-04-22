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
 * $Id: http.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: http.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <macros.h>

static object _fp;
static bool admin_port = 0;
static program handler = ((program)"/net/http.pike");
static object httpPort;

void http_request(object req)
{
    // create request object
    object obj = get_socket_program()(_fp, admin_port);
    master()->register_user(obj);
    obj->http_request(req);
}

program get_socket_program() 
{
    return handler;
}


bool port_required() { return false; }

bool open_port()
{
    int port_nr = get_port();
    _fp = get_module("filepath:url");
    string ip = _Server->query_config("ip");
    if ( ! stringp(ip) || sizeof(ip)==0 ) ip = 0;
    if ( catch(httpPort = Protocols.HTTP.Server.Port(
	http_request, (int)port_nr, ip)) )
    {
        werror("Internal HTTP Server failed to open on "
            + (stringp(ip) ? ip+":" : "port ") + port_nr + " !\n");
	return false;
    }
    MESSAGE("Internal HTTP port opened on "
        + (stringp(ip) ? ip+":" : "port ") + port_nr);
    _Server->set_config("web_port", port_nr);
    return true;
}


bool close_port()
{
    destruct(httpPort);
    destruct(this_object());
}

string get_port_config()
{
    return "http_port";
}

string get_port_name()
{
    return "http";
}

int get_port()
{
    return _Server->query_config("http_port");
}

string describe() { return "sTeamHTTP("+get_port()+")"; }    
