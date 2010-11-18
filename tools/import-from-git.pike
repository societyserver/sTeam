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

object git_fast_export(string repo, object dest)
{
    Stdio.File output = Stdio.FILE();
    //output->set_read_callback(lambda(mixed ... args){ read_git(dest, @args); });
    object export = Process.create_process(({ "git", "fast-export", "--all", "--progress=1" }), ([ "cwd":repo, "stdout":output->pipe() ]) );
    mapping commit;
    mapping blobs = ([]);
    string mark;
    int type;
    int COMMIT = 1;
    int BLOB = 2;
    int progress;
    int status = 1;
    string line;

    while(line = output->gets())
    {   
        array command = line/" ";
        switch(command[0])
        {
            case "":
                break;
            case "progress":
                write("%s\n", line);
                progress = (int)command[1];
                break;
            case "blob":
                type = BLOB;
                break;
            case "mark":
                mark = command[1];
                if (type == COMMIT)
                    commit->mark = mark;
                break;
            case "data":
                string data = output->read((int)command[1]);
                write("pos: %d->", output->tell());
                write("%d\n", output->tell());
                write("data: %d:%s\n", sizeof(data), command[1]);
                if (type == BLOB)
                    blobs[mark] = blob_to_steam(mark, data, tmpdest);
                else if (type == COMMIT)
                    commit->message = data;
                else
                    werror("UNKNOWN data:\n%s\n", data);
                break;
            case "commit":
                type = COMMIT;
                commit = ([]);
                commit->branch = command[1];
                break;
            case "committer":
                commit->committer = command[1..];
                break;
            case "author":
                commit->author = command[1..];
                break;
            case "from":
                commit->from = command[1..];
                break;
            case "M":
                commit_to_steam(command[3], command[2], blobs[mark], commit);
                break;
            default:
                werror("UNKNOWN: %O\n", line);
        }
        write("processed: %s: %{%s %}\n", command[0], command[1..]);
        //sleep(1);
    }
    //output->set_nonblocking();
    return export;
}

object blob_to_steam(string mark, string data, obj tmp)
{
    write("writing blob %s: %d\n", mark, sizeof(data));
    return 0;
}

mixed commit_to_steam(string path, string mark, object obj, mapping commit)
{
    write("committing %s: %s: %O\n%s\n", path, mark, obj, commit->message);
    return 0;
}

//void read_git(object dest, mixed ... args)
//{
//    werror("%O", args);
//}

int main(int argc, array(string) argv)
{
    options=init(argv);
    array opt = Getopt.find_all_options(argv,aggregate(
        ({"update",Getopt.NO_ARG,({"-U","--update"})}),
        ({"restart",Getopt.NO_ARG,({"-R","--restart"})}),
        ));
    options += mkmapping(opt[*][0], opt[*][1]);

    options->repo = argv[-2];
    options->dest = argv[-1];
    _Server=conn->SteamObj(0);
    object export = git_fast_export(options->repo, OBJ(options->dest));
    exit(export->wait());
}

