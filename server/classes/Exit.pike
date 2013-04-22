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
 * $Id: Exit.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Exit.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/classes/Link";

#include <classes.h>
#include <types.h>
#include <macros.h>
#include <attributes.h>

static void delete_object()
{
    object link = get_link_object();
    LOG("Deleting link object !");
    // two connected exits -> remove both
    if ( objectp(link) && link->get_object_class() & CLASS_EXIT ) {
	if ( link->get_link_object() == this() ) {
	    oLinkObject = 0; // set link to null before that !
	    LOG("Deleting connected Link !");
	    link->delete();
	}
    }
    ::delete_object();
}

mapping do_duplicate(void|mapping vars)
{
  if ( !mappingp(vars) )
    vars = ([ ]);
  vars->exit_to = oLinkObject;
  return ::do_duplicate(vars);
}

/**
 * Get the destination of this exit. This might be another exit or
 * a room.
 *  
 * @return the destination
 */
final object
get_exit()
{
    object destination = get_link_object();
    if ( objectp(destination) && 
	 destination->get_object_class() & CLASS_EXIT ) 
	return destination->get_environment();
    
    return destination;
}

object get_destination()
{
  return get_exit();
}

/**
 * This function returns the stat() of this object. This has the 
 * same format as statting a file.
 *  
 * @return status array as in file_stat()
 * @author Thomas Bopp (astra@upb.de) 
 * @see get_content_size
 */
array(int) stat()
{
    int creator_id = objectp(get_creator())?get_creator()->get_object_id():0;
    

    return ({ 16832, -2, time(), time(), time(),
		  creator_id, creator_id, 
		  "httpd/uni-directory" });
}

object get_icon()
{
	object destination = get_link_object();
   // get the icon of the exit depending on the target
    object icon = destination->query_attribute(OBJ_LINK_ICON);
    if ( !objectp(icon) )
	return query_attribute(OBJ_ICON);
    return icon;
}

int get_object_class() { return ::get_object_class() | CLASS_EXIT; }

