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
 * $Id: VerticalMenu.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: VerticalMenu.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Inserts.Dispatcher;

string al, ab, ar;
int alw, ah, arw;
string astyle;
string il, ib, ir;
int ilw, ih, irw;
string istyle;

string sGlobalVar;
int iDisable=0; // set to 1 to allow disabling the activ entry by clicking it

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
    if (!stringp(s) && !iDisable)
    {
        if (sizeof(states))
            value = states[0]->name;
    } else
        value = s;

    if (iDisable && get_state()==s)
        s=0;
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

    array generate() {
        object session = Session.get_user_session();

        if (get_state() == desc)
            return
                ({ "<td align=\"right\" height=\""+ah+"\""+
                   "width=\""+alw+"\" background=\""+al+"\"/>"+
                   "<td background=\""+ab+"\" align=\"center\">"+
                   "<a "+(astyle?astyle:"")+
                   " href=\""+session->callSession()+
                   "&amp;"+sGlobalVar+"="+desc+"\">"+
                   desc+"</a></td>"+
                   "<td align=\"left\" height=\""+ah+"\""+
                   "width=\""+arw+"\" background=\""+ar+"\"/>" });
        else return
            ({ "<td align=\"right\" height=\""+ih+"\""+
               "width=\""+ilw+"\" background=\""+il+"\"/>"+
               "<td background=\""+ib+"\" align=\"center\">"+
               "<a "+(istyle?istyle:"")+
               " href=\""+session->callSession()+
               "&amp;"+sGlobalVar+"="+desc+"\">"+
               desc+"</a></td>"+
               "<td align=\"left\" height=\""+ih+"\""+
               "width=\""+irw+"\" background=\""+ir+"\"/>"});
    }

    array preview() {
        return ({ "<td align=\"center\">"+desc+"</td>" });
    }
}

class CellSlot{
    inherit Slotter.Slot;
    
    string state;
    void create(string _state) {
        state = _state;
        set_insert(CellRenderer(state));
    }
}

class StateRenderer {
    inherit Slotter.Insert;
    string desc;
    string sVar;
    string sVal;
    
    void create(string state, string var, string val) {
        desc = state;
        sVar = var;
        sVal = val;
    }

    array generate() {
        object session = Session.get_user_session();

        if (get_state() == desc)
            return
                ({ "<td align=\"right\" height=\""+ah+"\""+
                   "width=\""+alw+"\" background=\""+al+"\"/>"+
                   "<td background=\""+ab+"\" align=\"center\">"+
                   "<a "+(astyle?astyle:"")+
                   " href=\""+session->callSession()+
                   "&amp;"+sGlobalVar+"="+desc+"&amp;"+sVar+"="+sVal+"\">"+
                   desc+"</a></td>"+
                   "<td align=\"left\" height=\""+ah+"\""+
                   "width=\""+arw+"\" background=\""+ar+"\"/>" });
        else return
            ({ "<td align=\"right\" height=\""+ih+"\""+
               "width=\""+ilw+"\" background=\""+il+"\"/>"+
               "<td background=\""+ib+"\" align=\"center\">"+
               "<a "+(istyle?istyle:"")+
               " href=\""+session->callSession()+
               "&amp;"+sGlobalVar+"="+desc+"&amp;"+sVar+"="+sVal+"\">"+
               desc+"</a></td>"+
               "<td align=\"left\" height=\""+ih+"\""+
               "width=\""+irw+"\" background=\""+ir+"\"/>"});
    }

    array preview() {
        return ({ "<td align=\"center\">"+desc+"</td>" });
    }
}

class StateSlot{
    inherit Slotter.Slot;
    string sVar;
    string sVal;
    string state;
    
    void create(string _state, string var, string val) {
        sVar = var;
        sVal = val;
        state = _state;
        set_insert(StateRenderer(state, sVar, sVal));
    }
}


class ExpandRenderer {
    inherit Slotter.Insert;
    CellSlot passiv;
    Slotter.Slot subnav;
    string desc;
    
    void create (string _desc) {
        passiv = CellSlot(_desc);
        subnav = Slotter.Slot();
        desc = _desc;
    }

    Slotter.Slot get_subnav() {
        return subnav;
    }
    
    array generate() {
        if (get_state() == desc)
            return ({ passiv, "</tr><tr><td colspan=\"3\" align=\"right\">",
                      subnav, "</td></tr><tr>" });
        else
            return ({ passiv });
    }

    array preview() {
        return generate();
    }
}

int add_state(string s)
{
    ::add_state(s, CellSlot(s));
}


int add_state_controler(string s, string var, string val)
{
    ::add_state(s, StateSlot(s, var, val));
}

int add_submenu(string s, Slotter.Slot sub)
{
    ::add_state(s, sub);
}

int allow_disable()
{
    iDisable = 1;
}

int forbit_disable()
{
    iDisable = 0;
}

Slotter.Slot add_expand(string s)
{
    Slotter.Slot ExpandSlot = Slotter.Slot();
    ExpandRenderer iExpand = ExpandRenderer(s);
    ExpandSlot->set_insert(iExpand);
    ::add_state(s, ExpandSlot);
    return iExpand->get_subnav();
}

array generate()
{
    array(Slotter.Slot) slots = ::generate();
    array out = ({"<table cellpadding=\"0\" cellspacing=\"0\" border=\"0\">"});

    foreach(slots, Slotter.Slot slot)
    {
        out += ({"<tr>"}) + ({ slot }) + ({"</tr>"});
    }

    out += ({"</table>"});
    return out;
}

array preview()
{
    array out = ({"<table>"});
    array(Slotter.Slot) slots =::preview();
    
    foreach(slots, Slotter.Slot slot)
    {
        out += ({"<tr>"}) + ({ slot }) + ({"</tr>"});
    }
    
    return out +({ "</table>" });
}

object get_cell() {
    return CellRenderer("test");
}
