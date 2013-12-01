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
 * $Id: module.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: module.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

array(string) Stylesheets=({});
mapping(string:Slotter.Slot) allSlots;

/**
 *  traverses the slots and inserts tree and calculates
 *  the html pieces "generated" by the visited inserts
 *  as a sideeffect each insert is asked for stylesheets it may need,
 *  to collect information for the header generation
 *
 *  @param array subparts - an array as returned from an insert generator
 *  @param string sFunction - the generator to call
 *                             "generate" - the standard html generator
 *                             "preview"  - a debugging generator
 *
 *  @result an array of strings, which can be flattened with
 *  @see flatten_tree
 *  @see compose_header
 *
 *  @author Ludger Merkens
 */
array build_tree(array subparts, string sFunction)
{
    Slotter.Insert currInsert;
    Slotter.Slot   currSlot;

    for(int i;i<sizeof(subparts); i++)
    {
        if (objectp( currSlot = subparts[i]))
        {
            //       werror(sprintf("%O",subparts[i])+"\n");
            allSlots[currSlot->get_path_slot_name()] = currSlot;
            currInsert = subparts[i]->get_insert();
            if (currInsert)
            {
                subparts[i] = build_tree(currInsert[sFunction](), sFunction);
                Stylesheets += currInsert->need_style_sheets();
            }
            else
                subparts[i]= "<td>empty</td>";
        }
    }
    return subparts;
}

/**
 * take a tree of strings as resulted from build_tree and glue them
 * together to a flat string
 * @param array(mixed) tree - the string tree to flatten
 * @result string
 *
 * @author Ludger Merkens
 * 
 */
string flatten_tree(array(mixed) tree)
{
    string out="";
    foreach(tree, mixed leave)
    {
        if (arrayp(leave))
            out += flatten_tree(leave);
        else
            out += leave;
    }
    return out;
}

/**
 * compose the collected header information durin "build_tree" to a
 * header
 *
 * @author Ludger Merkens
 */
string compose_header() {
    return "<head>"+
        "<meta http-equiv=\"Content-Type\" content=\"text/html; "+
        "charset=iso-8859-1\">"+
        (sizeof(Stylesheets) ?
         "<link rel=\"stylesheet\" href=\""+
         (Stylesheets*"\"><link rel=\"stylesheet\" href=\"")+
         "\">" : "")+
        "</head>";
}

/**
 *  run a "generate" composing run
 *  @author Ludger Merkens
 */ 
string compose(Slotter.Slot root)
{
    Stylesheets = ({});
    allSlots = ([]);
    
    array t = build_tree(({root}), "generate");
    return
        "<html>"+
        compose_header() +
        "<body>"+
        flatten_tree(t)+
        "</body>"+
        "</html>";
}


/**
 * run the "preview" composing run
 * @author Ludger Merkens
 */ 
string compose_preview(Slotter.Slot root)
{
    array t = build_tree(({root}), "preview");
    return flatten_tree(t);
}

/**
 * traverse the Slots and Inserts Tree to find an insert
 * via the path_name
 *
 * @author Ludger Merkens
 */
Slotter.Insert get_insert_by_name(string pathname)
{
    return allSlots[pathname];
}
