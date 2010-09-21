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
         //git_add(this_history[0]); 
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

void git_add(mapping doc, string to)
{
    string content = doc->obj->get_content();
    if (!content)
        return;
    string actual;
    object err = catch
    {
        Stdio.write_file(to+doc->name, content);
        actual = doc->name;
    };
    if (err)
    {
        Stdio.write_file(to+doc->path, content);
        actual = doc->path;
    }
    Process.create_process(({ "git", "add", to+actual }), ([ "cwd":to ]))->wait();
}

string git_commit(string message, string to, string author, int time)
{
    Stdio.File output = Stdio.File();
    int errno = Process.create_process(({ "git", "commit", "-m", message, "--author", author }), ([ "env":([ "GIT_AUTHOR_DATE":ctime(time), "GIT_COMMIT_DATE":ctime(time) ]), "cwd":to, "stdout":output->pipe() ]))->wait();
    output->read();
    if (!errno)
    {
        Process.create_process(({ "git", "rev-parse", "HEAD" }), ([ "cwd":to, "stdout":output->pipe() ]))->wait();
        return output->read()-"\n";
    } 
    else
        return "";
}

void git_init(string dir)
{
    if (!Stdio.is_dir(dir))
        mkdir(dir);
    if (Process.create_process(({ "git", "status" }), ([ "cwd":dir ]))->wait())
        Process.create_process(({ "git", "init" }), ([ "cwd":dir ]))->wait();
}

int main(int argc, array(string) argv)
{
    options=init(argv);
    array opt = Getopt.find_all_options(argv,aggregate(
    ({"update",Getopt.NO_ARG,({"-U","--update"})}),
    ({"restart",Getopt.NO_ARG,({"-R","--restart"})}),
    ));
    options += mkmapping(opt[*][0], opt[*][1]);

    options->dest = argv[-1];
    _Server=conn->SteamObj(0);
    export_to_git(OBJ("/"), options->dest+"/root", ({ OBJ("/home") }));
}

void export_to_git(object from, string to, void|array(object) exclude)
{
    git_init(to);

    git_object(from, to);
    //git_commit("initial state");
    sort(history->time, history);
    foreach(history;; mapping doc)
    {
        mapping git_version = doc->obj->query_attribute("git-version");
        if (!mappingp(git_version))
            git_version = ([]);
        if (options->restart || !git_version[to])
        {
            git_add(doc, to);
            string message = sprintf("%s - %d - %d", doc->obj->get_identifier(), doc->obj->get_object_id(), doc->version);
            object author = doc->obj->query_attribute("DOC_USER_MODIFIED")||doc->obj->query_attribute("OBJ_OWNER");
            string author_name = "unknown";
            if (author)
                author_name = author->get_user_name();
            string author_field = sprintf("%s <%s@%s>", author_name, author_name, _Server->get_server_name());
            string hash = git_commit(message, to, author_field, doc->time);
            git_version[to] = hash;
            doc->obj->set_attribute("git-version", git_version);
        }
    }
}
