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

inherit "/usr/local/lib/steam/tools/applauncher.pike";

void ping()
{
  call_out(ping, 60);
  conn->send_command(14, 0); 
}

object conn;

int main(int argc, array(string) argv)
{
  mapping options=init(argv);
  object _Server=conn->SteamObj(0);
  object file;
  if ((string)(int)options->file == options->file)
    file = conn->find_object(options->file);
  else if (options->file[0] == '/')
    file = _Server->get_module("filepath:tree")->path_to_object(options->file);
  else // FIXME: try to find out how to use relative paths
    file = _Server->get_module("filepath:tree")->path_to_object(options->file);
  return applaunch(file, exit);
}

mapping init(array argv)
{
  mapping options = ([ ]);

  array opt=Getopt.find_all_options(argv,aggregate(
    ({"host",Getopt.HAS_ARG,({"-h","--host"})}),
    ({"user",Getopt.HAS_ARG,({"-u","--user"})}),
    ({"port",Getopt.HAS_ARG,({"-p","--port"})}),
    ));

  foreach(opt, array option)
  {
    options[option[0]]=option[1];
  }
  if(!options->host)
    options->host="127.0.0.1";
  if(!options->user)
    options->user="root";
  if(!options->port)
    options->port=1900;
  else
    options->port=(int)options->port;

  options->file = argv[-1];

  string server_path = "/usr/local/lib/steam";

  master()->add_include_path(server_path+"/server/include");
  master()->add_program_path(server_path+"/server/");
  master()->add_program_path(server_path+"/conf/");
  master()->add_program_path(server_path+"/spm/");
  master()->add_program_path(server_path+"/server/net/coal/");

  conn = ((program)"client_base.pike")();

  int start_time = time();

  werror("Connecting to sTeam server...\n");
  while ( !conn->connect_server(options->host, options->port)  ) 
  {
    if ( time() - start_time > 120 ) 
    {
      throw (({" Couldn't connect to server. Please check steam.log for details! \n", backtrace()}));
    }
    werror("Failed to connect... still trying ... (server running ?)\n");
    sleep(10);
  }
 
  ping();
  if(lower_case(options->user) == "guest")
    return options;

  mixed err;
  string pw;
  int tries=3;
  //readln->set_echo( 0 );
  do
  {
    pw = Input.read_password( sprintf("Password for %s@%s", options->user,
           options->host), "steam" );
    //pw=readln->read(sprintf("passwd for %s@%s: ", options->user, options->host));
  }
  while((err = catch(conn->login(options->user, pw, 1))) && --tries);
  //readln->set_echo( 1 );

  if ( err != 0 ) 
  {
    werror("Failed to log in!\nWrong Password!\n");
    exit(1);
  } 
  return options;
}

