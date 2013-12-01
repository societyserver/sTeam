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
 * $Id: sTeamHTMLDisplay.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: sTeamHTMLDisplay.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Insert;

#include <macros.h>

object sTeamObject;
string stylesheet;

void set_style_sheet(string style)
{
    stylesheet = style;
}

void set_steam_object(object o)
{
    sTeamObject = o;
}

array preview()
{
    if (sTeamObject)
        return ({ sTeamObject->get_identifier() });
    return ({ "empty sTeamHTMLDisplay" });
}

array generate()
{
    Session.Session oSession = Session.get_user_session();
    object oComposer = oSession->get_composer();

    if (!oComposer)
        return ({ sprintf("%s Session: %d Composer missing\n",
                          this_user()->get_identifier(),
                          oSession->get_SID()) });
    
    if (sTeamObject)
        return ({
            oComposer->read_content(sTeamObject)
        });
    return ({ "empty sTeamHTMLDisplay" });
}

array(string) need_style_sheets()
{
    if (stringp(stylesheet))
        return ({ stylesheet });
    else
        return ({});
}
