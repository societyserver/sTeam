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
 * $Id: HorizontalSimpleMenu.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: HorizontalSimpleMenu.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Inserts.Dispatcher;

string al, ab, ar;
int alw, ah, arw;
string astyle;
string il, ib, ir;
int ilw, ih, irw;
string istyle;

string start, end;
string sWidth, sAlign;

string sGlobalVar;

void set_start_end_icons(string s, string e)
{
    start =s;
    end = e;
}

void set_active_icons(string left, int lw,
                 string back, int h,
                 string right, int rw)
{
    al = left; alw=lw;
    ab = back; ah=h;
    ar = right; arw=rw;
}

void set_inactive_icons(string left, int lw,
                   string back, int h,
                   string right, int rw)
{
    il = left; ilw=lw;
    ib = back; ih=h;
    ir = right; irw=rw;
}

void set_active_style(string style)
{
    astyle=style;
}

void set_inactive_style(string style)
{
    istyle=style;
}

void set_variable(string wv)
{
    sGlobalVar =wv;
    Session.get_user_session()->define_global(wv);
}

string get_variable()
{
    return sGlobalVar;
}

int set_state(string|int s)
{
    string value;
    if (!stringp(s))
    {
        if (sizeof(states))
            value = states[0]->name;
    } else
        value = s;
    
    if (::set_state(value))
    {
        Session.get_user_session()->set_global(sGlobalVar, value);
        return 1;
    }
    return 0;
}

class CellRenderer {
    inherit Slotter.Insert;
    string desc;

    void create(string state) {
        desc = state;
    }

    array preview() {
        return ({ desc });
    }

    array generate() {
        object session = Session.get_user_session();
        
        if (get_state() == desc)
            return
                ({ "     <td align=\"right\" height=\""+ah+"\""+
                   "width=\""+alw+"\" background=\""+al+"\"/>"+
                   "<td background=\""+ab+"\" align=\"center\">\n"+
                   "        <a "+(astyle?astyle:"")+
                   " href=\""+session->callSession()+
                   "&amp;"+sGlobalVar+"="+desc+"\">"+
                   desc+"</a>\n    </td>\n"+
                   "     <td align=\"left\" height=\""+ah+"\""+
                   "width=\""+arw+"\" background=\""+ar+"\"/>\n" });
        else return
            ({ "    <td align=\"right\" height=\""+ih+"\""+
               "width=\""+ilw+"\" background=\""+il+"\"/>"+
               "<td background=\""+ib+"\" align=\"center\">\n"+
               "       <a "+(istyle?istyle:"")+
               " href=\""+session->callSession()+
               "&amp;"+sGlobalVar+"="+desc+"\">"+
               desc+"</a>\n     </td>\n"+
               "     <td align=\"left\" height=\""+ih+"\""+
               "width=\""+irw+"\" background=\""+ir+"\"/>\n"});
    }
}


class CellSlot{
    inherit Slotter.Slot;

    string state;
    void create(string _state) {
        state = _state;
    }

    Slotter.Insert get_insert() {
        return CellRenderer(state);
    }
}

        
int add_state(string s)
{
    ::add_state(s, CellSlot(s));
}

array generate()
{
    array(Slotter.Slot) slots = ::generate();
    array out = ({"  <table cellpadding=\"0\" cellspacing=\"0\" border=\"0\">\n"});

    out += ({ "  <tr><!--MenuRow-->\n" });

    if (start) out += ({ "    <td><img src=\""+start+"\"/></td>\n" });
    foreach(slots, Slotter.Slot slot)
    {
        out += ({ slot }) ;
    }
    if (end) out += ({ "     <td><img src=\""+end+"\"/></td>\n" });
    
    out += ({"  </tr><!--MenuRow-->\n"});
    out += ({"  </table>\n"});
    return out;
}

array preview()
{
    array(Slotter.Slot) slots = ::preview();
    array out = ({ "<table cellpadding=\"0\" cellspacing=\"0\" border=\"1\" >\n",
                   "<tr>HorizontalSimpleMenu<br/>" });

    foreach(slots, Slotter.Slot slot)
    {
        out += ({ slot , "<br/>"});
    }
    out += ({"</tr></table>\n"});
    return out;
}


object get_cell() {
    return CellRenderer("test");
}

void set_width(string width) {
    sWidth = width;
}

void set_align(string align) {
    sAlign = align;
}
