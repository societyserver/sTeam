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
 * $Id: read_documents.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: read_documents.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/secure_mapping";

#include <macros.h>
#include <attributes.h>
#include <exception.h>
#include <events.h>

mapping mReaders = ([ ]);

//! This module keeps track about what document is read by which users.
//! It adds a global EVENT_DOWNLOAD and stores the user downloading
//! in the database.

static void load_module()
{
    add_global_event(EVENT_DOWNLOAD, download_document, PHASE_NOTIFY);
    LOG("table:documents - init_module()");
    ::load_module();
}

void download_document(int event, object obj, object caller)
{
    object user = geteuid() || this_user();
    array readers = get_value(obj->get_object_id());
    if ( !arrayp(readers) ) readers = ({ });
    if ( search(readers, user) == -1 )
	readers += ({ user });
    if ( mappingp(mReaders[obj]) )
      mReaders[obj][user] = 1;
    else {
      mReaders[obj] = ([ ]);
      foreach( readers, object r ) 
	mReaders[obj][r] = 1;
    }
    set_value(obj->get_object_id(), readers);
}

array(object) get_readers(object doc)
{
    array readers = get_value(doc->get_object_id());
    if ( !arrayp(readers) ) return ({ });
    return readers;
}

bool is_reader(object doc, object user)
{
    if ( mappingp(mReaders[doc]) )
        return mReaders[doc][user];

    array(object) readers = get_readers(doc);
    int res = search(readers, user) >= 0;

    // just load
    mReaders[doc] = ([ ]);
    foreach ( readers, object u ) {
      mReaders[doc][u] = 1;
    }
    return res;
}

string get_identifier() { return "table:read-documents"; }
string get_table_name() { return "read_documents"; }
