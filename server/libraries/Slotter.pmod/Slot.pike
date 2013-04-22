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
 * $Id: Slot.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Slot.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

private Slotter.Insert oInsert; // the Insert that will generate the content

/**
 * set the insert to this slot
 * @param Slotter.Insert Insert - the Insert to insert
 * @authot Ludger Merkens
 */
void set_insert(Slotter.Insert Insert)
{
    oInsert = Insert;
}

/**
 * get the current insert
 * @return 0| Slotter.Insert - the current insert
 */
Slotter.Insert get_insert()
{
    return oInsert;
}

/**
 * @return the complete identifier treated as a tree separated with "."
 */
// string get_path_slot_name()
// {
//     return (oParent ? oParent->get_path_slot_name()+"." :"/")+ sSlotName;
// }

/**
 * set the local name according to the generating insert
 * @param string name - the local name to set
 * @see create - you can also set the name during creation
 */
// string set_slot_name(string name)
// {
//     sSlotName = name;
// }

/**
 * return the local name on this level of hierarchy
 * @return string - the name set to this slot (local)
 */
// string get_slot_name()
// {
//     return sSlotName;
// }

int is_slot() {
    return 1;
}
