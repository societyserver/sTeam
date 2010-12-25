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

constant cvs_version="$Id: fix-encoding.pike.in,v 1.0 2010/12/25 14:19:52 martin Exp $";

object _Server;

void walk_objects(object obj)
{
    if (obj->get_object_class() & CLASS_DOCUMENT)
    {
        fix_content(obj);   
    }
    if (obj->get_object_class() & CLASS_CONTAINER)
    {
        foreach(obj->get_inventory();; object cont)
        {
            walk_objects(cont);
        }
    }
}
object fix_content(object obj)
{
    if (obj->query_attribute("DOC_MIME_TYPE") == "text/html")
    {
        string content = obj->get_content();
        obj->set_content(string_to_utf8(content));
    }
    return obj;
}

int main(int argc, array(string) argv)
{
    options=init(argv);

    options->path = argv[-1];
    _Server=conn->SteamObj(0);
    walk_objects(OBJ(options->path));
}
