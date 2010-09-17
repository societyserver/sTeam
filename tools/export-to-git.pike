#!/usr/local/lib/steam/bin/steam

/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2003-2010  Martin Baehr
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

#include "/usr/local/lib/steam/server/include/classes.h"

constant cvs_version="$Id: export-to-git.pike.in,v 1.1 2009/09/28 14:19:52 nicke Exp $";

void ping()
{
  call_out(ping, 60);
  conn->send_command(14, 0); 
}

object conn;

mapping options = ([ ]);

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
  options->dest = argv[-1];

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


array history = ({});

void get_object(object obj)
{
    if (obj->get_object_class() & CLASS_DOCUMENT)
    {
         mapping versions = obj->query_attribute("DOC_VERSIONS");
         if (!sizeof(versions))
         {
             versions = ([ 1:obj ]);
         }

             array this_history = ({});
             foreach(versions; int nr; object version)
             {
                 this_history += ({ ([ "obj":version, "version":nr, "time":version->query_attribute("OBJ_LAST_CHANGED") ]) });
             }
             sort(this_history->version, this_history);
             this_history += ({ ([ "obj":obj, "version":this_history[-1]->version+1, "time":obj->query_attribute("OBJ_LAST_CHANGED") ]) });
             
             int timestamp = 0;
             string oldname;
             foreach(this_history; int nr; mapping version)
             {
                string newname;
                if (version->obj->query_attribute("OBJ_VERSIONOF"))
                    newname = version->obj->query_attribute("OBJ_VERSIONOF")->query_attribute("OBJ_PATH");
                else
                    newname = version->obj->query_attribute("OBJ_PATH");
                if (oldname && oldname != newname)
                {
                    werror("rename %s -> %s\n", oldname, newname);
                    version->oldname = oldname;
                }
                oldname = newname;
                version->name = newname;
                if (timestamp > version->obj->query_attribute("OBJ_LAST_CHANGED"))
                {
                   werror("timeshift! %d -> %d\n", timestamp, version->obj->query_attribute("OBJ_LAST_CHANGED"));
                }
             }
             history += this_history[1..];
             export_and_add(this_history[0]); 
    }
    if (obj->get_object_class() & CLASS_CONTAINER && obj->query_attribute("OBJ_PATH") != "/home")
    {
        mkdir(options->dest+obj->query_attribute("OBJ_PATH"));

        foreach(obj->get_inventory();; object cont)
        {
            get_object(cont);
        }
    }
}

void export_and_add(mapping doc)
{
    string content = doc->obj->get_content();
    if (!content)
        return;
    Stdio.write_file(options->dest+doc->name, content);
    Process.create_process(({ "git", "add", options->dest+doc->name }), ([ "cwd":options->dest ]))->wait();
}

void commit(string message)
{
    Process.create_process(({ "git", "commit", "-m", message }), ([ "cwd":options->dest ]))->wait();
}

int main(int argc, array(string) argv)
{
    options=init(argv);
    object _Server=conn->SteamObj(0);
    get_object(_Server->get_module("filepath:tree")->path_to_object("/"));
    commit("initial state");
    sort(history->time, history);
    foreach(history;; mapping doc)
    {
        export_and_add(doc);
        // commitmessage: name, version nr, object_id
        string message = sprintf("%s - %d - %d", doc->obj->get_identifier(), doc->obj->get_object_id(), doc->version);
        commit(message);
        // FIXME: get hash and add to object.
    }
}
