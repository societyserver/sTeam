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
 * $Id: objects.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: objects.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/secure_mapping.pike";

#include <attributes.h>

//! This maps the global objects name:object inside the database so
//! things like "root-room" can be looked up.

/**
 * Callback function when the module is loaded.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void init_module()
{
    set_attribute(OBJ_DESC, "This module is a lookup table of registered "+
		  "objects in the database.");
}

string get_table_name()
{
  return "objects";
}

string get_identifier() { return "objects"; }
