/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 */
inherit "/kernel/persistence";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <access.h>

static mapping mObjects = ([ ]);
static mapping mID    = ([ ]);
static int    __id        = 0;
static int oid_length = 4;  // nr of bytes for object ids
static int persistence_id;


#define PROXY "/kernel/proxy.pike"

mixed new_object(string id, object obj, string prog_name)
{
  if ( !obj->query_attribute(OBJ_TEMP) )
    return 0;
  __id++;
  //int newid = __id | (get_persistence_id() << OID_BITS);
  int newid = _Persistence->make_object_id( __id );
  object p = new(PROXY, newid, obj);
  
  _Persistence->set_proxy_status(p, PSTAT_SAVE_OK);
  mObjects[newid] = p;
  return ({ newid, p });
}

object find_object(int|string id)
{
  if ( objectp(mObjects[id]) )
    return mObjects[id];
}

bool delete_object(object p)
{
  return false;
}

int|object load_object(object proxy, int|object oid)
{
  return 0;
}

void save_object(object proxy, void|string ident, void|string index)
{
}

void require_save(object proxy, void|string indent, void|string index)
{
}

object lookup(string identifier)
{
  return 0;
}

mixed lookup_user(string identifier)
{
  return 0;
}

mixed lookup_group(string identifier)
{
  return 0;
}

static void init_module()
{
  persistence_id = _Persistence->register("none", this_object());
}

int get_persistence_id() { return persistence_id; }
string get_identifier() { return "persistence:none"; }
