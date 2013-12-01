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
 * $Id: cluster.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */
inherit "/kernel/module";

//! Server Cluster implementation. Keeps track of inter-Server connections
//! and a list of servers with certificates.

import Servers;
import cert;

#include <macros.h>
#include <classes.h>
#include <database.h>


static ServerList list = ServerList();
static object serverCert;

private static object get_cert()
{
  if ( objectp(serverCert) )
    return serverCert;

  object cert = get_module("filepath:tree")->path_to_object("/documents/steam.cer");
  if ( !objectp(cert) ) {
    string c = create_cert( ([
      "country": "Germany",
      "organization": "Uni Paderborn",
      "unit": "sTeam",
      "locality": "Paderborn",
      "province": "NRW",
      "name": _Server->get_server_name(),
    ]) );
    cert = get_factory(CLASS_DOCUMENT)->execute(([ "name":"steam.cer", ]));
    cert->set_content(c);
    cert->move(OBJ("/documents"));
  }
  serverCert = cert;
  return cert;
}

void init_module()
{
    add_data_storage(STORE_SERVERS, save_servers, load_servers, 1);
}

object add_server(string name, string hostname, void|string certificate)
{
    Server s = Server(name, hostname, certificate);
    list->add(s);
    require_save(STORE_SERVERS);
    return s;
}

Server hello(string name, string cert) 
{
  Server s = list->get(name);
  if ( s->verify(cert) )
    return s;
  return 0;
}

ServerList get_serverlist() 
{
  return list;
}

array get_servers() 
{
  return list->list_servers();
}

mixed send_command(string server, int oid, string func, mixed args)
{
    
}

object build_connection(Server|string s)
{
  if ( stringp(s) )
    s = list->get(s);
  object conn = ((program)"/base/client_base.pike")();
  conn->connect_server(s->get_hostname(), 1900);
  conn->server_hello(get_cert());
  list->set_connection(s, conn);
  return conn;
}

mapping save_servers()
{
  return list->save();
}

void load_servers(mapping data)
{
  list->load(data);
}

string get_identifier() { return "Cluster"; }





