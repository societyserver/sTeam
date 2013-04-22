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
 * $Id: Alternator.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Alternator.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Insert;
mapping(string:Slotter.Slot) alternatives= ([]);
string|function mControl;

void create(string|function sC)
{
    mControl = sC;
}

Slotter.Slot get_slot_to_state(string state)
{
    Slotter.Slot slot = Slotter.Slot();
    alternatives[state]= slot;
    werror(sprintf("getting slot (%O) to state \"%s\"\n", slot, state));
    return slot;
}

array list_alternatives() {
    array alt = ({});
    foreach (indices(alternatives), string alternative)
    {
        alt += ({ "<dl><dt>"+alternative+"</td><dd>" , alternative, "</dd></dl>" });
    }
    return alt;
}
        
array preview() {
    return ({ "Alternator"+
              "["+(stringp(mControl) ? mControl :
                        function_name(mControl)+"()")+"]" })+
        ({ "<ul>" }) + list_alternatives() + ({ "</ul>" });
}

array generate() {

    string val;
    if (stringp(mControl))
    {        
        object session = Session.get_user_session();
        val = session->get_global(mControl);
    }
    else
    {
        val = mControl();
    }
    
    return ({ alternatives[val]? alternatives[val]:
              (alternatives["@default"] ? alternatives["@default"] :
              "Variable ["+(stringp(mControl) ? mControl
                            : function_name(mControl))+
               "] state ["+val+"] not handled and no @default given") });
}
