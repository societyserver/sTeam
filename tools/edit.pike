#!/usr/local/lib/steam/bin/steam

/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2003-2004  Martin Baehr
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
 * $Id: debug.pike.in,v 1.1 2009/09/28 14:19:52 nicke Exp $
 */

constant cvs_version="$Id: edit.pike.in,v 1.0 2010/09/15 14:19:52 martin Exp $";

inherit "applauncher.pike";
inherit "client.pike";
//inherit "/usr/local/lib/steam/server/modules/groups.pike";
void ping(string host, string port, string user, string|void pw)
{
  call_out(ping, 10, host, port, user, pw);
  mixed a = conn->send_command(14, 0);
  if (a=="sTeam connection lost.")
  {
      conn = ((program)"client_base.pike")();
      conn->close();
      if (conn->connect_server(host, port) && user != "guest")
      {
        if(conn->send_command(14,0)!="sTeam connection lost.")
        {
          conn->login(user, pw, 1);
          _Server=conn->SteamObj(0);
          user_obj = _Server->get_module("users")->lookup(options->user);
          gp = user_obj->get_groups();
	        get_file_object();
          update(file);
        }
      }
  }
}

object conn;
mapping conn_options = ([]);
object _Server,user_obj,file;
array(object) gp;
mapping options = ([ ]);

int main(int argc, array(string) argv)
{

//  program pGroup = (program)"/classes/Group.pike";
   options=init(argv);
   options->file = argv[-1];
   ping(options->host, options->port, options->user, pw);
//  gp=_Server->get_module("groups")->lookup("helloworld");
  _Server=conn->SteamObj(0);
  user_obj = _Server->get_module("users")->lookup(options->user); 
  gp = user_obj->get_groups();

/* WORKING AND GIVING GROUP OBJECTS AND NAMES */
  int i = 1; 
  write("Listing all groups : \n\n");
  foreach(gp, object obj) {
	write("Group "+i+" : "+obj->get_group_name()+".\n");
        i=i+1;
	}

//	 groups_pgm = ((program)"/usr/local/lib/steam/server/modules/groups.pike")();
//   gp= _Server->get_module("groups")->lookup(1);
/*   gp=_Server->get_module("filepath:tree")->path_to_object("/home/WikiGroups"); 
//   write(gp->get_group_name());
 */
//  mystr = gp->get_group_name();
//  write(mystr);
// array(string) gps = ({ "Admin" , "coder" , "help" , "PrivGroups" , "WikiGroups" , "sTeam" });
  get_file_object();
  return applaunch(file,demo);
}

void demo(){}

void get_file_object()
{
  int len = sizeof(gp);
  if ((string)(int)options->file == options->file)
    file = conn->find_object(options->file);
  else if (options->file[0] == '/')
    file = _Server->get_module("filepath:tree")->path_to_object(options->file);
  else // FIXME: try to find out how to use relative paths
  {
   string a = options->file;
   int tmp_len = 0;
   while(!file && tmp_len!=(len+2)){
    write("Checking in "+(string)a+"\n");
    file = _Server->get_module("filepath:tree")->path_to_object(a);
  if(tmp_len<len)
  {
    string gp_name = gp[tmp_len]->get_group_name();
    if(gp_name[.. 10] == "WikiGroups.")
    {
	gp_name=gp_name[11 ..];
        a = "/wiki/"+gp_name+"/"+options->file;
    }
    else
    {
   	 a="/home/"+gp_name+"/"+options->file;
    }
  }
    tmp_len=tmp_len+1;
   }
  }
  if (file->get_class() == "Link")
      file = file->get_link_object();
}