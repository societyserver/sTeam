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
 * $Id: exec_base.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: exec_base.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

static mixed a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z;
static object                                           me, here;

#include <macros.h>
#include <database.h>

object FP(string arg)
{
   return MODULE_USERS->lookup(arg);
}

object ENV(object ob)
{
    return ob->get_environment();
}

array(object) INV(object ob)
{
    return ob->get_inventory();
}

void
init_variables(object ob)
{
   mixed exec_map;
   
   if (mappingp(exec_map = ob->query_attribute("_exec_")))
   {
      a = exec_map[0]; b = exec_map[1]; c = exec_map[2];
      d = exec_map[3]; e = exec_map[4]; f = exec_map[5];
      g = exec_map[6]; h = exec_map[7]; i = exec_map[8];
      j = exec_map[9]; k = exec_map[10]; l = exec_map[11];
      m = exec_map[12]; n = exec_map[13]; o = exec_map[14];
      p = exec_map[15]; q = exec_map[16]; r = exec_map[17];
      s = exec_map[18]; t = exec_map[19]; u = exec_map[20];
      v = exec_map[21]; w = exec_map[22]; x = exec_map[23];
      y = exec_map[24]; z = exec_map[25];
   }
   me = ob;
   here = ENV(ob);
}

void
save_variables(object ob)
{
    ob->set_attribute("_exec_", ([0 : a, 1 : b, 2 : c, 3 : d,
				 4 : e, 5 : f, 6 : g, 7 : h, 8 : i, 
				 9 : j, 10 : k, 11 : l, 12 : m,
				 13 : n, 14 : o, 15 : p, 16 : q, 17 : r, 
				 18 : s, 19 : t, 20 : u,
				 21 : v, 22 : w, 23 : x, 24 : y, 25 : z ]));
}

int serialize_coal() { return 0; } // do not send this through COAL
