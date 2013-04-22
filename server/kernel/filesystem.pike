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
 * $Id: filesystem.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: filesystem.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

//! Basic filesystem support. Uses environment/inventory relation in order
//! to find an object by a given URL.

inherit Filesystem.Base;
inherit "/modules/filepath";

#include <database.h>

// filesystem stuff
static object cwdCont = _ROOTROOM;

object cd(string|object cont)
{
    if ( stringp(cont) )
	cont = path_to_object(cont);
    if ( !objectp(cont) )
	return 0;
    cwdCont = cont;
    return this();
}

string cwd()
{
    return object_to_filename(cwdCont);
}

array(string) get_dir(void|string directory, void|string|array glob)
{
    object cont;
    if ( stringp(directory) )
	cont = path_to_object(directory);
    else
	cont = cwdCont;
    array files = ({ });
    foreach ( cont->get_inventory(), object obj )
	files += ({ obj->get_identifier() });
    return files;
}

object open(string file)
{
    object cont;
    if ( file[0] != '/' )
	cont = cwdCont;
    else
	cont = _ROOTROOM;

    object doc = resolve_path(cont, file);
    if ( !objectp(doc) )
	error("Unable to resolve " + file + "\nCWD="+cwd()+"\n");
    Stdio.FakeFile f = Stdio.FakeFile(doc->get_content());
    return f;
}



