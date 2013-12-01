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
 * $Id: BasicFormular.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: BasicFormular.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Insert;

mapping(string:string) mHiddenVars = ([]);
function fFormCB;
private Slotter.Slot inner;

void set_form_callback(function f)
{
    fFormCB =f;
}

void set_hidden(string name, string value)
{
    mHiddenVars [name]=value;
}

Slotter.Slot get_inner()
{
    if (!objectp(inner))
        inner=Slotter.Slot();
    return inner;
}

array generate() {

    object oSession = Session.get_user_session();
    object oComposer = oSession->get_composer();
    
    string out = "<form action=\""+
        oComposer->callName()+"\" method=\"post\">\n";
    
    foreach(indices(mHiddenVars), string name)
        out += "  <input type=\"hidden\" name=\""+name+"\" value=\""+
            mHiddenVars[name]+"\"/>\n";
    
    out += "  <input type=\"hidden\" name=\"x\" value=\""+
        oSession->get_callback_name(fFormCB)+"\"/>\n";
    out += "  <input type=\"hidden\" name=\"sid\" value=\""+
        oSession->get_SID()+"\"/>\n";
    
    return ({ out, inner, "\n</form>\n"});
}

array preview() {
    return ({ "basic form:<br/>", inner });
}
