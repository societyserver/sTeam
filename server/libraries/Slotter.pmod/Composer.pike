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
 * $Id: Composer.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: Composer.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <database.h>

Slotter.Slot oRootSlot;
array(string) Stylesheets=({});
array(string) JavaScripts=({});
array(string) Meta=({});

//mapping(string:Slotter.Slot) allSlots;

int iSID;

Slotter.Slot get_root_slot()
{
    if (!objectp(oRootSlot))
        oRootSlot = Slotter.Slot();
    return oRootSlot;
}

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
            //            string name= currSlot->get_path_slot_name();
            //            allSlots[name] = currSlot;
            currInsert = currSlot->get_insert();
            if (currInsert)
            {
                if (!currInsert[sFunction])
                    throw( ({sprintf("Missing ("+sFunction+") in %O\n",
                                     currInsert), backtrace()}));
                array temp = currInsert[sFunction]();
                if (!temp)
                    throw(({ sprintf("No Result from "+
                                    sFunction+" in %s\n",
                                    master()->describe_program(
                                        object_program(currInsert))) }));
                if (!temp || search(temp,0)!=-1)
                    throw(({sprintf("Empty Subparts returned %O\n",currInsert),
                          backtrace()}));
                subparts[i] = build_tree(temp, sFunction);
                Stylesheets |= currInsert->need_style_sheets();
                JavaScripts |= currInsert->need_java_scripts();
                Meta |= currInsert->need_meta();
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

    /*    werror(sprintf("composing header with Meta:%O, Stylesheets:%O and Javascripts:%O\n",
          Meta, Stylesheets, JavaScripts));*/
    return "<head>"+
        "<meta http-equiv=\"Content-Type\" content=\"text/html; "+
        "charset=UTF-8\">\n"+
        (sizeof(Meta) ? Meta * "\n" : "")+
        (sizeof(Stylesheets) ?
         "  <link rel=\"stylesheet\" href=\""+
         (Stylesheets*"\">\n  <link rel=\"stylesheet\" href=\"")+
         "\">\n" : "")+
        (sizeof(JavaScripts) ?
         "  <SCRIPT LANGUAGE=\"JavaScript\" SRC=\"" +
         (JavaScripts*"\" TYPE=\"text/javascript\"></SCRIPT>\n <SCRIPT LANGUAGE=\"JavaScript\" SRC=\"")+
         "\" TYPE=\"text/javascript\"></SCRIPT>\n" : "")+
        "</head>\n";
}

/**
 *  run a "generate" composing run
 *  @author Ludger Merkens
 */ 
string compose()
{
    Stylesheets = ({});
    JavaScripts = ({});
    //    allSlots = ([]);
    
    array t = build_tree(({oRootSlot}), "generate");
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
string compose_preview()
{
    Stylesheets = ({});
    //    allSlots = ([]);
    array t = build_tree(({oRootSlot}), "preview");
    return flatten_tree(t);
}

/**
 * during the generation process a mapping of inserts is kept,
 * thus the results of this function depend on and refer to the
 * last run of such a generation process.
 *
 * @param   string       - pathname, the Slot to search
 * @returns Slotter.Slot - the designate Slot
 *
 * @author Ludger Merkens
 */
// Slotter.Slot get_slot_by_name(string pathname)
// {
//     return allSlots[pathname];
// }


/**
 * untility function called from e.g. the sTeamHTMLdisplay insert to
 * read the content of a sTeam Document. Due to this, an insert may be
 * lightweight and dosn't need to be a sTeam object.
 *
 * @param object o - a proxy
 * @author Ludger Merkens
 */
string read_content(object o)
{
    return string_to_utf8(o->get_content());
}

/**
 * another utility function, allowig access to get_inventory
 * @param o - container to access
 * @param cl - class to filter by.
 */
array(object) read_inventory(object o, void|int cl)
{
    if (cl)
        return o->get_inventory_by_class(cl);
    else
        return o->get_inventory();
}

/**
 * retreive a steam insert by oid or pathname
 * @param string insert - a pathname passed to _FILEPATH
 *        int    insert - an OID
 * @returns the insert (not the proxy)
 * @author Ludger Merkens
 */
Slotter.Insert get_steam_insert(string|int insert)
{
    object oInsert;
    if (stringp(insert))
        oInsert = _FILEPATH->path_to_object(insert);
    else
        oInsert = find_object(insert);

    if (objectp(oInsert))
        return oInsert->get_object();
    return 0;
}

object call_factory(object factory, mapping createInfo)
{
    return factory->execute(createInfo);
}

mixed delegate_set_attribute(object target, mixed key, mixed value)
{
    //    werror(sprintf("delegating: %O, %O, %O\n", target, key, value));
    return target->set_attribute(key, value);
}


mixed delegate_sanction_object(object target, object obj, mixed data)
{
    return target->sanction_object(obj, data);
}

mixed delegate_set_acquire_attribute(object target, object obj1, mixed v,
                                     object obj2)
{
    return target->set_acquire_attribute(obj1, v, obj2);
}

mixed delegate_group_add_member(object group, object member)
{
    return group->add_member(member);
}

mixed delegate_group_remove_member(object group, object member)
{
    return group->remove_member(member);
}

string callName()
{
    string path = _FILEPATH->object_to_path(this_object());

    string server = _Server->get_config("web_server");
    string port = _Server->get_config("web_port_https");
    
    if (!path)
        return _Server->get_server_url_administration()+
            "/scripts/execute.pike?script="+this_object()->get_object_id();
    else
        return _Server->get_server_url_administration()+
            combine_path(path, this_object()->get_identifier());
}



