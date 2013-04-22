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
 * $Id: Insert.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Insert.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

//private Slotter.Slot inSlot;
private mapping mCallbacks = ([]);

/*
 * This is the very basic html Slot, it is almost a virtual class
 * meant as parent for all more elaborate insert classes
 */


/**
 * return some useful html representation suitable for a rough preview
 * of the final result. Most times an empty table with a name will do
 *
 * @return array - a vector of slots and strings to be composed by the
 *                 Slotter main module
 * @author Ludger Merkens
 */ 
array preview()
{
    return ({"<td>empty slot</td>"});    
}

/**
 * return the final design, the html representation meant for application
 * purposes.
 *
 * @return array - a vector of slots and strings to be composed by the
 *                 Slotter main module
 * @author Ludger Merkens
 */
array generate()
{
    return ({"<td></td>"});
}

array(string) need_style_sheets() {
    return ({});
}

array(string) need_java_scripts() {
    return ({});
}

array(string) need_meta() {
    return ({});
}
