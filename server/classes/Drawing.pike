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
 * $Id: Drawing.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Drawing.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/classes/Object";

#include <macros.h>
#include <classes.h>
#include <attributes.h>

int get_object_class() 
{ 
    return CLASS_DRAWING | ::get_object_class();
}

mapping do_duplicate(void|mapping vars)
{
  if ( !mappingp(vars) )
    vars = ([ ]);
  vars->type = do_query_attribute(DRAWING_TYPE);
  return ::do_duplicate(vars);
}
