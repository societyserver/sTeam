/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: collect_users.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

//! checks active users and possible moves them home


constant cvs_version="$Id: collect_users.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <events.h>
#include <attributes.h>
#include <coal.h>
#include <database.h>

//#define DEBUG_COLLECT

#ifdef DEBUG_COLLECT
#define LOG_COLLECT(s, args...) werror("Collecting: " + s+ "\n", args)
#else
#define LOG_COLLECT(s, args...) 
#endif

static Thread.Queue userQueue = Thread.Queue();

void load_module()
{
    add_global_event(EVENT_LOGIN, user_login, PHASE_NOTIFY);
    start_thread(collect);
}

void user_login(object obj, object user, int feature, int prev_features)
{
    LOG_COLLECT("User %O logged in ...", user);
    userQueue->write(user);
}

/**
 * Check if a user needs cleanup and should be moved into her
 * workroom.
 *  
 * @param object user - the user to check.
 * 
 */
void check_user_cleanup(object user)
{
    userQueue->write(user);
}

void check_users_cleanup(array users)
{
    foreach(users, object u)
	if ( objectp(u) )
	    userQueue->write(u);
}

static int check_user(object user)
{
    LOG_COLLECT("Checking user %O", user);
    if ( !stringp(user->get_identifier()) )
	return 0;
    if ( user->get_status() == 0 ) {
	if ( user->get_environment() != user->query_attribute(USER_WORKROOM) ){
	    LOG_COLLECT("Collect: Moving user %s", user->get_identifier());
	    object wr = user->query_attribute(USER_WORKROOM);
	    LOG_COLLECT("Found Workroom %O", wr);
	    if ( objectp(wr) ) {
		user->move(wr);
		LOG_COLLECT("Moved !");
	    }
	}
	return 0;
    }
    return 1;
}

static void collect()
{
    while ( 1 ) {
	mixed err = catch {
	    LOG_COLLECT(" Checking users ...");
	    object user;
	    array(object) check_users;
	    check_users = ({ });
	    while ( userQueue->size() > 0 ) {
		user = userQueue->read();
		if ( search(check_users, user) == -1 && 
		     check_user(user) )
		    check_users += ({ user });
	    }
	    foreach ( check_users, user)
	        userQueue->write(user);
	    // also check idle connections!

	    foreach ( master()->get_users(), object socket ) {
	      if ( !objectp(socket) ) continue;
	      
	      // do not close service connections
	      if ( functionp(socket->get_user_object) && 
		   socket->get_user_object() == USER("service") )
		continue;

	      if ( functionp(socket->get_last_response) ) 
	      {
		  int t = time() - socket->get_last_response();
		  if ( t > COAL_TIMEOUT ) {
		    if ( !functionp(socket->get_ip) )
			werror("Socket without IP function !");
		    mixed e = catch(socket->close_connection());
		  }
	      }
	    }
	};
	if ( err != 0 )
	  FATAL("Error on collect_users():\n %s\n%s", 
		  err[0], describe_backtrace(err[1]));
#ifdef DEBUG_COLLECT
	sleep(10);
#else
	sleep(300);
#endif
    }
}

string get_identifier() { return "collect_users"; }

