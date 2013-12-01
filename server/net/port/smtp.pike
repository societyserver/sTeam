/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2002-2003  Christian Schmidt
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
 * $Id: smtp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: smtp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Stdio.Port;

#include <config.h>
#include <macros.h>


void setup_port()
{
    object tmp,u;

    tmp = ::accept();
    if ( !objectp(tmp) )
    {
        werror("Failed to bind socket !\n");
        return;
    }
    master()->register_user((u=new(OBJ_SMTP, tmp)));
}

program get_socket_program()
{
    return (program)OBJ_SMTP;
}

bool port_required() { return false; }
int get_port() { return _Server->query_config("smtp_port"); }
string describe() { return "SMTP(#"+get_port()+")"; }    

bool open_port()
{
    int port_nr = (int)_Server->query_config("smtp_port");
    string hostname = _Server->query_config("smtp_host");
    if ( !stringp(hostname) )
      hostname = _Server->get_server_name();
    
    if ( port_nr == 0 )
    {
        MESSAGE("Port for incoming SMTP not defined - service is NOT started");
        return false;
    }

    string ip = _Server->query_config("ip");
    if ( ! stringp(ip) || sizeof(ip)==0 ) ip = 0;
    if ( !bind(port_nr, setup_port, ip) )
    {
	werror("Failed to open SMTP port on '"
               + (stringp(ip) ? ip+":" : "port ") + port_nr + "' !\n");
        return false;
    }
    MESSAGE("SMTP port opened on " + (stringp(ip) ? ip+":" : "port ")
        + port_nr);
    return true;
}

string get_port_config()
{
    return "smtp_port";
}

string get_port_name()
{
    return "smtp";
}
