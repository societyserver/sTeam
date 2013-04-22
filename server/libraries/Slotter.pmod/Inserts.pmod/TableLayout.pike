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
 * $Id: TableLayout.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: TableLayout.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit Slotter.Insert;

mapping(Slotter.Slot:SlotInfo) paneLookup;
pane RootPane;
string sTableSettings;

#define PREVIEW_SETTING "cellspacing=\"0\" cellpadding=\"0\" border=\"1\""
#define RENDER_SETTING "cellspacing=\"0\" cellpadding=\"0\" border=\"0\""

/*
 * Class SlotInfo keeps the additional Information stored to a Slot
 * like the pane it lies in, and the alignment it has to be
 * rendererd with.
 */
class SlotInfo {
    pane Pane;
    string valign;
    string halign;
    int width;
    string bgcolor;
    void create(pane|void oPane) {
        Pane = oPane;
    }
}

/*
 * Helperclass Pane, this class contains either vertical or horizontal
 * aligned slots. And provides primitive possibilities to move slots
 * between panes.
 */
class pane {
    private int level;
    array(Slotter.Slot|pane) content = ({});

    void create(int _level) {
        level = _level;
    }

    void add(Slotter.Slot oSlot, void|Slotter.Slot after) {
        int p = search(content, after);
        if (p==-1)
            content += ({ oSlot });
        else
            content = content[0..p] + ({ oSlot }) + content[p+1..];
        
        if (!paneLookup[oSlot])
            paneLookup[oSlot] = SlotInfo(this_object());
        else
            paneLookup[oSlot]->Pane = this_object();
    }
    
    pane movedown(Slotter.Slot oSlot) {
        if (!sizeof(content))
        {
            pane target = pane(level+1);
            content+= ({target});
            return target;
        }
        int p = search(content, oSlot);
        if (p!=-1)
        {
            pane target = pane(level+1);
            target->add(oSlot);
            content[p]=target;
            return target;
        }
    }

    int is_slot() { return 0;}
    int get_level() {
        return level;
    }

    array get_content() {
        return content;
    }
}

/**
 * create() called on instantiation
 * @author Ludger Merkens
 */
void create() {
    paneLookup = ([]);
    RootPane = pane(0);
}


/**
 * split the Layouter in a way, that the new Slot, will appear right to
 * the given Slot, if nothing is given, the root pane will be splitted
 * @param Slotter.Slot  - the Slot to split
 * @return Slotter.Slot - the new Slot
 *
 * @author Ludger Merkens
 */
Slotter.Slot hsplit(Slotter.Slot oSlot, string name)
{
    pane parent;
    if (!oSlot)
        parent = RootPane;
    else
        parent = paneLookup[oSlot]->Pane;
    
    Slotter.Slot oChild = Slotter.Slot();

    if (!(parent->get_level() %2))
        parent->add(oChild, oSlot);
    else {
        pane oNewPane = parent->movedown(oSlot);
        oNewPane->add(oChild, oSlot);
    }
    return oChild;
}

/**
 * same as hsplit, but a new slot will be inserted below the
 * given slot.
 * @param Slotter.Slot oSlot - The Slot after wich will be splitted
 * @return Slotter.Slot - the newly created Slot
 * @author Ludger Merkens
 */
Slotter.Slot vsplit(Slotter.Slot oSlot, string name)
{
    pane parent;
    if (!oSlot)
        parent = RootPane;
    else
        parent = paneLookup[oSlot]->Pane;

    Slotter.Slot oChild = Slotter.Slot();
    if (parent->get_level() %2)
        parent->add(oChild, oSlot);
    else {
        pane oNewPane = parent->movedown(oSlot);
        oNewPane->add(oChild, oSlot);
    }
    return oChild;
}

/**
 * adjust the vertical align of an insert according to the Layouter
 *
 * at current see html table definition for <td> which alignment are
 * possible
 *
 * according to the german self-html 8.0 these are:
 * top      = obenbündig,
 * middle   = mittig,
 * bottom   = untenbündig,
 * baseline = an gemeinsamer Basislinie, so dass erste Textzeile
 *            immer auf gleicher Höhe begin
 *
 * @return 1 - Slot found and info set
 *         0 - Unknwon Slot info lost
 */
int v_align(Slotter.Slot Slot, string align)
{
    SlotInfo i;
    if (!(i=paneLookup[Slot]))
        return 0;

    i->valign=align;
    return 1;
}

/**
 * adjust the horizontal align of an insert according to the Layouter
 *
 * at current see html table definition for <td> which alignment are
 * possible
 *
 * according to the german self-html 8.0 these are:
 * left    = linksbündig,
 * center  = zentriert,
 * right   = rechtsbündig,
 * justify = Blocksatz,
 * char    = um Dezimalzeichen. In diesem Fall char= als zusätzliches Attribut
 *           notieren und als Wert ein Dezimalzeichen wie Komma zuweisen
 *           (char=","). Mit einem weiteren Attribut charoff= gegebenenfalls
 *           angeben, an welcher Position das Dezimalzeichen frühestens
 *           vorkommen kann (z.B. charoff="10").
 *
 * @return 1 - Slot found and info set
 *         0 - Unknwon Slot info lost
 */
int h_align(Slotter.Slot Slot, string align)
{
    SlotInfo i;
    if (!(i=paneLookup[Slot]))
        return 0;
    
    i->halign=align;
    return 1;
}

/**
 * give hints about the expected width of the inserts to expect.
 * @param Slotter.Slot Slot - the Slot to hint about
 * @param int width         - the width to store.
 *
 * @author Ludger Merkens
 */
int set_width(Slotter.Slot Slot, int width)
{
    SlotInfo i;
    if (!(i=paneLookup[Slot]))
        return 0;

    i->width=width;
    return 1;
}


int set_bgcolor(Slotter.Slot Slot, string color)
{
    SlotInfo i;
    if (!(i=paneLookup[Slot]))
        return 0;

    i->bgcolor = color;
    return 1;
}

/**
 * traverse the pane structure build through the various split functions.
 * @return a strict array consisting of strings and Slots.
 * @author Ludger Merkens
 */
private array traverse(pane oPane)
{
    array out = ({});
    array data = oPane->get_content();
    
    if (oPane->get_level() %2) // vertical pane
    {
        foreach(data, object m)
        {
            if (m->is_slot())
            {
                SlotInfo oInfo = paneLookup[m];
                string valign = oInfo->valign;
                string halign = oInfo->halign;
                int width = oInfo->width;
                string bgcolor = oInfo->bgcolor;
                
                out += ({ "<table "+sTableSettings+
                          (width ? " width=\""+width+"\"":"")+
                          (bgcolor ? " bgcolor=\""+bgcolor+"\"":"")+
                          "><!-- vertical -->\n<tr><td"+
                          (valign ? " valign=\""+valign+"\"":"")+
                          (halign ? " align=\""+halign+"\"":"")+
                          ">"})+ ({m}) +
                    ({ "</td></tr></table>\n" });
            }
            else
                out += ({ "<table "+sTableSettings+"><tr>"})+ traverse(m)+
                    ({ "</tr></table>\n" });
        }
    } else // horizontal pane
    {
        foreach(data, object m)
        {
            if (m->is_slot())
            {
                SlotInfo oInfo = paneLookup[m];
                string valign = oInfo->valign;
                string halign = oInfo->halign;
                int width = oInfo->width;
                out += ({ "<td"+
                          (valign ? " valign=\""+valign+"\"":"")+
                          (halign ? " align=\""+halign+"\"":"")+
                          (width ? " width=\""+width+"\"":"")+
                          ">"})+({ m}) +({"</td>  " });
            }
            else
                out += ({ "<td valign=\"top\">"})+ // this is a kludge!
                traverse(m) +({"</td>" });
        }
    }
    return out;
}

/**
 * generate the table environment for the generic Layouter.
 * @author Ludger Merkens
 */
array generate() {
    sTableSettings = RENDER_SETTING;
    return ({"<table "+sTableSettings+"><tr>"})+ traverse(RootPane)+({ "</tr></table>"});
}

/**
 * generate the basic table environment for the generic Layouter
 * in previw mode.
 * @author Ludger Merkens
 */ 
array preview() {
    sTableSettings = PREVIEW_SETTING;
    return ({"<table "+sTableSettings+"><tr>"})+ traverse(RootPane)+({ "</tr></table>"});
}
