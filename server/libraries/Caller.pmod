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
 * $Id: Caller.pmod,v 1.2 2009/05/02 05:44:39 astra Exp $
 */

constant cvs_version="$Id: Caller.pmod,v 1.2 2009/05/02 05:44:39 astra Exp $";

#if constant(steamtools.get_caller)
static function __cf = steamtools.get_caller;

object get_caller(object obj, mixed bt)
{
  object caller = __cf(obj);
  object callero = low_get_caller(obj, bt);
  
  if ( caller != callero )
    werror("********* Caller differs: %O, should be %O\n", caller, callero);
  return caller;
}
#else
object get_caller(object obj, mixed bt) 
{
  return low_get_caller(obj, bt);
}
#endif

object low_get_caller(object obj, mixed bt)
{
    int sz = sizeof(bt);
    object       caller;

    sz -= 2;
    for ( ; sz >= 0; sz-- ) {
	if ( functionp(bt[sz][2]) ) {
	    function f = bt[sz][2];
	    caller = function_object(f);
	    if ( caller != obj ) { 
              return caller;
	    }
	}
    }
    return 0;
}

