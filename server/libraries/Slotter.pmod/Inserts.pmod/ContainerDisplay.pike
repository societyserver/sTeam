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
 * $Id: ContainerDisplay.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: ContainerDisplay.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Insert;

#include <attributes.h>
#include <database.h>
#include <classes.h>
#include <access.h>

private static string DirName = "";
private static string varPathName = "";
private static string Header = "";
private static string Footer = "";
private static int FootUpload =0;

array(string) need_java_scripts() {

    if (FootUpload)
        return ({ "/gui_js/main.js" });
    return ({ });
}


void set_variable(string wv)
{
    varPathName = wv;
    Session.get_user_session()->define_global(wv);
}

string get_variable()
{
    return varPathName;
}

void set_base_dir(string base)
{
    DirName = base;
}

string get_base_dir()
{
    return DirName;
}

void set_footer(string f)
{
    Footer = f;
}

void enable_upload_footer(string f)
{
    FootUpload = 1;
    set_footer(f);
}

void disable_upload_footer()
{
    FootUpload = 0;
}

void set_header(string h)
{
    Header = h;
}

string get_footer()
{
    return Footer;
}

string get_header()
{
    return Header;
}


array generate()
{
    string server = _Server->get_config("web_server");
    string port = _Server->get_config("web_port_http");
    object oSession = Session.get_user_session();
    object oComposer = oSession->get_composer();
    
    if (!oSession)
    {
        return ({ "<h3>Session lost ...</h3><br/>" });
    }
    if (!oComposer)
    {
        return ({ "<h3>Internal Script Error <b>Compser lost</b></h3><br/>" });
    }

    string path = oSession->get_global(varPathName);
    object oContainer = _FILEPATH->path_to_object(combine_path(DirName, path));

    if (!oContainer)
    {
        return ({ "<h3>Directory not found on this server!</h3><br/>" });
    }
    
    object header = oContainer->get_object_byname("header.html");
    object footer = oContainer->get_object_byname("footer.html");
    object index = oContainer->get_object_byname("index.html");

    if (index)
    {
        Slotter.Insert iIndex = Slotter.Inserts.sTeamHTMLDisplay();
        Slotter.Slot IndexSlot = Slotter.Slot();
        iIndex -> set_steam_object(index);
        IndexSlot->set_insert(iIndex);
        return ({ IndexSlot });
    }

    array(object) content = oComposer->read_inventory(oContainer);
    
    content -= ({ header });
    content -= ({ footer });
    
    string body = "<table>\n";

    foreach(content, object obj)
    {
        if (!( obj->get_class()& CLASS_EXIT))
        {
            body += "  <tr>\n";
            body += "     <td><img src=\"https://"+server+":"+port+"/scripts/get.pike?object="+
                obj->query_attribute(OBJ_ICON)->get_object_id()+"\"/></td>\n";
            body += "     <td><a href=\"https://"+server+":"+
                port+combine_path(DirName, path)+"/"+obj->get_identifier()+"\"/>"+
                obj->query_attribute(OBJ_NAME)+"</a></td>\n";
            body += "     <td>"+obj->query_attribute(OBJ_DESC)+"</td>\n";
            body += "  </tr>\n";
        }
    }

    body += "</table>\n";

    array out = ({});

    if (header)
    {
        Slotter.Insert iHeader = Slotter.Inserts.sTeamHTMLDisplay();
        iHeader->set_steam_object(header);
        Slotter.Slot HeadSlot = Slotter.Slot();
        HeadSlot->set_insert(iHeader);
        out += ({ HeadSlot });
    } else if (Header)
    {
        out += ({ Header });
    }
        

    out += ({ body });

    if (footer)
    {
        Slotter.Insert iFooter = Slotter.Inserts.sTeamHTMLDisplay();
        iFooter->set_steam_object(header);
        Slotter.Slot FootSlot = Slotter.Slot();
        FootSlot->set_insert(iFooter);
        out += ({ FootSlot });
    } else if(Footer)
    {
        
        if (FootUpload &&
            (_SECURITY->get_user_permissions(oContainer, this_user(),
                                             SANCTION_WRITE)
            & SANCTION_WRITE) == SANCTION_WRITE)
        {
            out += ({ "<table width=\"600\"><tr><td align=\"right\">"+
                      "<a href=\"javascript:open_createmode('"+
                      oContainer->get_object_id()+"','Document')\">"+Footer+
                      "</a></td></tr></table>\n"});
        } else {
            out += ({ Footer });
        }
            
    }
    return out;
        
}

array preview() {

    return ({ "ContainerDisplay ["+varPathName+"]" });
}
