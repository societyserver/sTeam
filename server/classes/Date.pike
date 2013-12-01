/* Copyright (C) 2000-2008  Thomas Bopp, Thorsten Hampel, Ludger Merkens, Martin Baehr
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
 */
inherit "/classes/Object";

//! The Date class features some DATE specific attributes. Dates are
//! usually found inside Calendars.

#include <macros.h>
#include <classes.h>
#include <assert.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <types.h>


int get_object_class()
{
    return ::get_object_class() | CLASS_DATE;
}

string execute(mapping variables)
{
  return "Date"; 
}

string describe()
{
  return "Date()";
}

static void delete_object()
{
    if ( mappingp(mReferences) ) {
      foreach(indices(mReferences), object o) {
	if ( !objectp(o) ) continue;
	
	o->removed_link();
      }
    }
    ::delete_object();
}

bool match(int start, int end)
{
  int startdate, enddate;
  startdate = (int)do_query_attribute(DATE_START_DATE);
  enddate = (int)do_query_attribute(DATE_END_DATE);
  if ( (startdate >= start && startdate <= end ) ||
       (enddate >= start && enddate <= end) ||
       ( start <= enddate && end >= startdate) )
    return true;
  return false;
}

bool match_time(int starttime, int endtime)
{
  int startdate, enddate;
  startdate = (int)do_query_attribute(DATE_START_TIME);
  enddate = (int)do_query_attribute(DATE_END_TIME);

  if ( (startdate >= starttime && startdate <= endtime) ||
       (enddate >= starttime &&	enddate <= endtime) ||
       ( starttime <= enddate && endtime >= startdate ) )
    return true;
  return false;
}



