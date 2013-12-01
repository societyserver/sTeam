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
 * $Id: UniTabbing.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: UniTabbing.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Inserts.HorizontalSimpleMenu;

string sBaseDir = ".";
string sProto = "";

void create(string|void basedir, string|void proto) {
    if (basedir)
        sBaseDir = basedir;

    if (proto)
        sProto = proto;
    
    set_active_icons(sProto + combine_path(basedir,"./unimenu/ReiterMBaL.gif"), 12 ,
                     sProto + combine_path(basedir,"./unimenu/ReiterMBaBg.gif"), 22,
                     sProto + combine_path(basedir,"./unimenu/ReiterMBaR.gif"),9);
    set_inactive_icons(sProto + combine_path(basedir,"./unimenu/ReiterMBiL.gif"), 12,
                       sProto + combine_path(basedir,"./unimenu/ReiterMBiBg.gif"), 22,
                       sProto + combine_path(basedir,"./unimenu/ReiterMBiR.gif"),10);

    set_start_end_icons(0,
                        sProto + combine_path(basedir, "./unimenu/ReiterMBEnd.gif"));
    set_active_style("class=\"TabActiv\"");
    set_inactive_style("class=\"TabInActiv\"");
}


array generate()
{
    object session = Session.get_user_session();
    string var = get_variable();
    string val = session->get_global(var);
    set_state(val);
    return ::generate();
}

                  
array(string) need_style_sheets() {
    return ({ sProto + combine_path(sBaseDir,"./unimenu/menu.css") });
}
