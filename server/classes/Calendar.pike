/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
inherit "/classes/Room";

//! A Calendar is a room with Date Objects in it.

//#define CALENDAR_DEBUG 1

#ifdef CALENDAR_DEBUG
#define DEBUG_CALENDAR(s, args...) write("Calendar: "+s+"\n", args)
#else
#define DEBUG_CALENDAR(s, args...)
#endif

#include <classes.h>
#include <attributes.h>
#include <macros.h>

string describe() 
{
  object creator = query_attribute(CALENDAR_OWNER);
  return "Calendar("+(objectp(creator) ? 
		      creator->get_identifier() +  "'s calendar" :
		      "Noones calendar")+")";
}

void create_links(object date, object creator, array groups)
{
  object factory = get_factory(CLASS_LINK);
  object link, calendar, ulink;
  array haves = ({ });

  DEBUG_CALENDAR("Creating links for date %O", date);
  foreach(creator->get_members(), object member) {
    if ( member->get_object_class() & CLASS_USER )
      calendar = member->query_attribute(USER_CALENDAR);
    else if ( member->get_object_class() & CLASS_GROUP )
      calendar = member->query_attribute(GROUP_CALENDAR);
    else continue;
    DEBUG_CALENDAR("Checking link for %O (%O)", member->get_identifier(), member->get_object_id());
    if ( !objectp(calendar) ) {
      werror( "Calendar: invalid calendar of member %O\n", member );
      continue;
    }
    if ( search( haves, calendar ) < 0 ) {
      DEBUG_CALENDAR("Creating link for %O (%O)", member->get_identifier(), member->get_object_id());
      link = factory->execute(([ "name": date->get_identifier(),
                                 "attributes": date->query_attributes(),  
                                 "link_to": date,   ]) );
      if ( link->move(calendar) ) haves += ({ calendar });
    }
  }
  
  foreach(groups, object grp) {
    calendar = grp->query_attribute(GROUP_CALENDAR);
    if ( search( haves, calendar ) < 0 ) {
      DEBUG_CALENDAR("Creating link for group %O (%O)", grp->get_identifier(), grp->get_object_id());
      link = factory->execute(([ "name": date->get_identifier(),
                                 "attributes": date->query_attributes(),  
                                 "link_to": date, ]) );
      if ( link->move(calendar) ) haves += ({ calendar });
    }
    foreach(grp->get_members(), object member) {
      if ( member->get_object_class() & CLASS_USER )
        calendar = member->query_attribute(USER_CALENDAR);
      else if ( member->get_object_class() & CLASS_GROUP )
        calendar = member->query_attribute(GROUP_CALENDAR);
      else continue;
      if ( !objectp(calendar) ) {
        werror( "Calendar: invalid calendar of member %O\n", member );
        continue;
      }
      if ( search( haves, calendar ) < 0 ) {
        DEBUG_CALENDAR("Creating sub link for group member %O (%O)", member->get_identifier(), member->get_object_id());
        ulink = factory->execute(([ "name": date->get_identifier(),
                                    "attributes": date->query_attributes(), 
                                    "link_to": link, ]) );
        if ( ulink->move(calendar) ) haves += ({ calendar });
      }
    }
  }
}

object add_entry_recursive(mapping entry_map, void|int link, void|array groups)
{
  array groups_recursive = groups;
  if ( arrayp(groups) ) {
    foreach ( groups, object grp ) {
      array subgroups = grp->get_sub_groups_recursive();
      if ( arrayp(subgroups) ) {
	foreach ( subgroups, object subgrp ) {
	  if ( objectp(subgrp) && search( groups_recursive, subgrp ) < 0 )
	    groups_recursive += ({ subgrp });
	}
      }
    }
  }
  return add_entry( entry_map, link, groups_recursive );
}

object 
add_entry(mapping entry_map,void|int link, void|array groups)
{
  DEBUG_CALENDAR("add_entry(%O, %O)", entry_map, link);
  object entry = _Server->get_factory(CLASS_DATE)->execute(entry_map); 
  entry->move(this());
  // is this a group calendar ?
  object creator = do_query_attribute(CALENDAR_OWNER);
  DEBUG_CALENDAR("creator of calendar is %O", creator);
  if ( (link || entry_map->verteilung) && 
       creator->get_object_class() & CLASS_GROUP ) 
  {
    object t = Task.Task();
    t->obj = this();
    t->func = "create_links";
    if ( !arrayp(groups) )
      groups = ({ });

    t->params = ({ entry, creator, groups });
    DEBUG_CALENDAR("New task %O", t);
    get_module("tasks")->run_task(t);
  }
  
  return entry;
}

object filter_datelinks ( object link ) {
  object linkobj = link;
  do {
    if ( !objectp(linkobj) ) return UNDEFINED;
    if ( linkobj->get_object_class() & CLASS_LINK )
      linkobj = linkobj->get_link_object();
    else if ( linkobj->get_object_class() & CLASS_DATE )
      return linkobj;
    else return UNDEFINED;
  } while ( true );
}

array get_all_entries_day ( void|int offset, void|int type )
{
  object start = Calendar.Day() + offset;
  object end = start + offset + 1;
  return get_all_entries( start->unix_time(), end->unix_time()-1, type );
}

array get_all_entries_week ( void|int offset, void|int type )
{
  object start = Calendar.Week() + offset;
  object end = start + offset + 1;
  return get_all_entries( start->unix_time(), end->unix_time()-1, type );
}

array get_all_entries_month ( void|int offset, void|int type )
{
  object start = Calendar.Month() + offset;
  object end = start + offset + 1;
  return get_all_entries( start->unix_time(), end->unix_time()-1, type );
}

array get_all_entries_year ( void|int offset, void|int type )
{
  object start = Calendar.Year() + offset;
  object end = start + offset + 1;
  return get_all_entries( start->unix_time(), end->unix_time()-1, type );
}

array get_all_entries(void|int start, void|int end, void|int type) 
{
  int result;
  mixed  err;

  array dates = get_inventory_by_class( CLASS_DATE );
  array dlinks = get_inventory_by_class( CLASS_LINK );
  dlinks = filter( dlinks, filter_datelinks );
  if ( start > 0 ) {
    array matches = ({ });
    foreach(dates, object date) {
      err = catch( result =  date->match(start, end) );
      if ( err ) {
	FATAL("While getting entries: %s\n%O", err[0], err[1]);
      }
      else if ( result )
	matches += ({ date });
    }
    foreach(dlinks, object link) {
      object linkobj = filter_datelinks( link );
      err = catch( result =  linkobj->match(start, end) );
      if ( err ) {
	FATAL("While getting entries: %s\n%O", err[0], err[1]);
      }
      else if ( result )
	matches += ({ link });
    }
    if ( intp(type) && type > 0 ) {
      array type_matches = ({ });
      foreach(matches, object match) {
	if ( !objectp(match) ) continue;

	object obj = match;
	if ( match->get_object_class() & CLASS_LINK )
	  obj = match->get_link_object();
	if ( match->query_attribute(DATE_TYPE) == type )
	  type_matches += ({ match });
      }
      return type_matches;
    }
    return matches;
  }

  return dates + dlinks;
}

array check_conflicts(int startdate, int enddate, int starttime, int endtime)
{
  array dates = get_all_entries(startdate, enddate);
  array matches = ({ });
  foreach(dates, object date) {
    if ( date->match_time(starttime, endtime) )
      matches += ({ date });
  }
  return matches;
}

int get_object_class() 
{
  return ::get_object_class() | CLASS_CALENDAR;
}
