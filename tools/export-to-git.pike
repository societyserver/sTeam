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
inherit .client;
 
#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)
 
constant cvs_version="$Id: export-to-git.pike.in,v 1.1 2010/09/28 14:19:52 martin Exp $";
 
array history = ({});
object _Server;
 
void git_object(object obj, string to)
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
             this_history += ({ ([ "obj":version, "version":nr, "time":version->query_attribute("DOC_LAST_MODIFIED"), "path":obj->query_attribute("OBJ_PATH") ]) });
         }
         sort(this_history->version, this_history);
         this_history += ({ ([ "obj":obj, "version":this_history[-1]->version+1, "time":obj->query_attribute("DOC_LAST_MODIFIED"), "path":obj->query_attribute("OBJ_PATH") ]) });
         
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
            if (timestamp > version->obj->query_attribute("DOC_LAST_MODIFIED"))
            {
               werror("timeshift! %d -> %d\n", timestamp, version->obj->query_attribute("DOC_LAST_MODIFIED"));
            }
         }
         history += this_history;
    }
    if (obj->get_object_class() & CLASS_CONTAINER && obj->query_attribute("OBJ_PATH") != "/home")
    {
        mkdir(to+obj->query_attribute("OBJ_PATH"));
 
        foreach(obj->get_inventory();; object cont)
        {
            git_object(cont, to);
        }
    }
}
 
void git_add(mapping doc, string to, string complete_path)
{
    string content = doc->obj->get_content();
    if (!content)
        return;
    string actual;
    //Checks whether there is a / at the end of to, if yes first one writes otherwise second one writes
    object err = catch
    {
        Stdio.write_file(to+doc->name, content);
        actual = doc->name[1 ..];
    };
    if (err)
    {
        Stdio.write_file(complete_path, content);
        actual = doc->path;
    }
    Process.create_process(({ "git", "add", complete_path }), ([ "cwd": to ]))->wait();
}
 
string git_commit(string message, string to, string author, int time)
{
    Stdio.File output = Stdio.File();
    int errno = Process.create_process(({ "git", "commit", "-m", message, "--author", author }), ([ "env":([ "GIT_AUTHOR_DATE":ctime(time), "GIT_COMMITTER_DATE":ctime(time) ]), "cwd":to , "stdout":output->pipe() ]))->wait();
    output->read();
    if (!errno)
    {
        Process.create_process(({ "git", "rev-parse", "HEAD" }), ([ "cwd": to, "stdout":output->pipe() ]))->wait();
        write("Commit hash :  "+output->read()+"\n");
        return output->read()-"\n";
    }
    else
        return "";
}
 
void git_init(string dir)
{
    dir_check("",dir);
    if (Process.create_process(({ "git", "status" }), ([ "cwd":dir ]))->wait())
    {
        Process.create_process(({ "git", "init" }), ([ "cwd":dir ]))->wait();
        write("Git Initialized\n\n");
    }
}
 
int main(int argc, array(string) argv)
{
    options=init(argv);
    array opt = Getopt.find_all_options(argv,aggregate(
    ({"update",Getopt.NO_ARG,({"-U","--update"})}),
    ({"restart",Getopt.NO_ARG,({"-R","--restart"})}),
    ));
    options += mkmapping(opt[*][0], opt[*][1]);
    options->src = argv[-2];
    options->dest = argv[-1];
    _Server=conn->SteamObj(0);
    export_to_git(OBJ(options->src), options->dest, ({ OBJ("/home") }));
}
 
int count=0;
string dir_check(string def, string dir)
{
   if(def!="")
   {
        int y=1;
        array(string) new = dir/"/";
        string oclass = OBJ(dir)->get_class();
        if(oclass=="Container"||oclass=="Room") //if its a container/room like /sources , then last element of new doesn't get discarded. 
            y=1;
        else
            y=2;      //if it is a file like /sources/file , then file gets discarded because only sourced folder needs to be created
        foreach(new[1..sizeof(new)-y] , string x)
        {
               
                if (!Stdio.is_dir(def+"/"+x))
                {
                        mkdir(def+"/"+x);
                }
                def = def+"/"+x;
        }
        if(oclass=="Container"||oclass=="Room")
          return def;
        return def+"/"+new[sizeof(new)-1];  //complete path to file or folder
   }
   else
   {
        array(string) arr = dir/"/";
        if(arr[-1] == "")
          arr = arr[0 .. sizeof(arr)-2]; //last "/" should not be counted
        array(string) temp = arr;
        int flag = 0;
        int x = 0;
        while (!Stdio.is_dir(temp*"/")) //checking what all directories need to be created
        {
                flag=1;
                temp = temp[0 .. sizeof(temp)-2];
                x = sizeof(temp);
        }
        while(!Stdio.is_dir(dir) && flag==1) //flag is 1 means some directories have to be created. this loop creates the directories one by one.
        {
          temp = temp + ({ arr[x] });
          mkdir(temp*"/");
          x++;
        }
   }
  return "";
}
 
void git_create_branch(string to)
{
    string cur_time = replace(ctime(time(0))[4 ..]-"\n",([":":"-" , " ":"-"]));
    Process.create_process(({ "git", "checkout", "--orphan", cur_time }), ([ "cwd": to ]))->wait();
    Process.create_process(({ "git", "rm", "-rf", "."}),([ "cwd": to]))->wait();
    dir_check("",to);
}
    
void export_to_git(object from, string to, void|array(object) exclude)
{
    git_init(to);
    git_create_branch(to);
    string complete_path = dir_check(to,options->src);
    git_object(from, to);
    sort(history->time, history);
    foreach(history;; mapping doc)
    {  
            git_add(doc, to, complete_path);
            string message = sprintf("%s - %d - %d", doc->obj->get_identifier(), doc->obj->get_object_id(), doc->version);
            write("Commit message : "+message+"\n");
            object author = doc->obj->query_attribute("DOC_USER_MODIFIED")||doc->obj->query_attribute("OBJ_OWNER");
            string author_name = "unknown";
            if (author)
                author_name = author->get_user_name();
            string author_field = sprintf("%s <%s@%s>", author_name, author_name, _Server->get_server_name());
            string hash = (string)git_commit(message, to, author_field, doc->time);
    }
}
