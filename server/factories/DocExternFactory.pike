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
 * $Id: DocExternFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: DocExternFactory.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/factories/DocumentFactory";

#include <macros.h>
#include <classes.h>
#include <events.h>
#include <exception.h>
#include <database.h>
#include <attributes.h>
#include <types.h>

private static object mExternLookup;

void init()
{
    ::init();
    mExternLookup = _Server->get_module("extern_documents");
}

static void init_factory()
{
  ::init_factory();
  init_class_attribute(DOC_EXTERN_URL,  CMD_TYPE_STRING, "extern url", 
		       EVENT_ATTRIBUTES_QUERY, EVENT_ATTRIBUTES_CHANGE,0,
		       CONTROL_ATTR_USER, "");
}

object execute(mapping vars)
{
    object obj;
    if ( !stringp(vars["url"]) )
	THROW("No url given!", E_ERROR);
    
    int l = strlen(vars["url"]);
    if ( l >= 2 && vars["url"][l-1] == '/' )
	vars["url"] = vars["url"][..l-2];
    
    if ( !stringp(vars->name) || strlen(vars->name) == 0 )
      vars->name = vars->url;

    try_event(EVENT_EXECUTE, CALLER, obj);
    if ( vars->transient ) {
      if ( mappingp(vars->attributes) )
	vars->attributes[OBJ_TEMP] = 1;
      else
	vars->attributes = ([ OBJ_TEMP : 1 ]);
    }
    obj = ::object_create(
	vars["name"], CLASS_NAME_DOCEXTERN, 0, 
	vars["attributes"],
	vars["attributesAcquired"], 
	vars["attributesLocked"],
	vars["sanction"],
	vars["sanctionMeta"]);

    obj->set_attribute(DOC_EXTERN_URL, vars["url"]);
    obj->set_attribute(DOC_MIME_TYPE, ""); // no mime type for external docs
    run_event(EVENT_EXECUTE, CALLER, obj);
    return obj->this();
}

object
get_document(string url)
{
    int l = strlen(url);
    if ( l >= 2 && url[l-1] == '/' )
	url = url[..l-2];
    return mExternLookup->lookup(url);
}

void test() {
}

array(object) get_all_objects()
{
  return _Database->get_objects_by_class("/classes/"+get_class_name());
} 


string get_identifier() { return "DocExtern.factory"; }
string get_class_name() { return "DocExtern"; }
int get_class_id() { return CLASS_DOCEXTERN; }
