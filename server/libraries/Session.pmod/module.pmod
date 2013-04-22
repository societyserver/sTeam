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
 * $Id: module.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: module.pmod,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

mapping(object:mapping(int:object)) sessions;
mapping(object:int) currUserSession =([]);
mapping currSimpleSessions = ([ ]);

#include <attributes.h>
#include <database.h>


class SimpleSession {
  mapping sessionData;
  string sid;
  string getSID() { return sid; }

  void create() {
#if constant(Crypto.Random) 
    sid = sprintf("%x", hash(Crypto.Random.random_string(10)));
#else
    sid = sprintf("%x", hash(Crypto.randomness.reasonably_random()->read(10)));
#endif
    sessionData = ([ ]);
  }
  mixed get(string key) {
    return sessionData[key];
  }
  void put(string key, mixed value) {
    sessionData[key] = value;
  }
}

private int new_session_id()
{
    return hash(this_user()->query_attribute(OBJ_NAME)+(string)time());
}

object new_session()
{
  object session = SimpleSession();
  currSimpleSessions[session->getSID()] = session;
  return session;
}

object get_session(string id)
{
  return currSimpleSessions[id];
}

mixed get(string sid, string key)
{
  object session = currSimpleSessions[sid];
  if ( !objectp(session) )
    steam_error("Your session has expired !");
  return session->get(key);
}

void put(string sid, string key, mixed val)
{
  object session = currSimpleSessions[sid];
  if ( !objectp(session) )
    steam_error("Your session has expired !");
  session->put(key, val);
}


object new_user_session()
{
    mapping usersessions;

    if (!mappingp(sessions))
        sessions=([]);
    
    usersessions = sessions[this_user()];
    if (!mappingp(usersessions))
    {
        int id = new_session_id();
        object oSession = Session.Session(id);
        usersessions=([]);
        usersessions[id]=oSession;
        sessions[this_user()]=usersessions;
        currUserSession[this_user()] = id;
        return oSession;
    }
    
    array(int) aSIDs = indices(usersessions);
    if (sizeof(aSIDs) > 10)
        m_delete(usersessions,aSIDs[sizeof(aSIDs)-1]);
    
    currUserSession[this_user()] = new_session_id();
 
    object oSession = Session.Session(currUserSession[this_user()]);
    usersessions[currUserSession[this_user()]]= oSession;
    sessions[this_user()]=usersessions;
    return oSession;
}

object get_user_session_by_id(int sid)
{
    if (!sid)
        throw( ({"Illegal to access Session by ID without ID",
                 backtrace() }));

    if (!sessions)
        sessions = ([]);

    mapping usersessions = sessions[this_user()];
    object session;
    
    if (!mappingp(usersessions))
        usersessions=([]);
    
    if (!(session=usersessions[sid]))
    {
        werror("asking guest ...");
        object guest = MODULE_USERS->lookup("guest");
        
        mapping guestsessions = sessions[guest];
        if (session = guestsessions[sid])
        {
            // most probably a login during session - ok we will
            // continue to use this.
            werror("found guest session ... borrowing\n");
            m_delete(guestsessions, sid);
            usersessions[sid]= session;
            currUserSession[this_user()]= sid;
            sessions[this_user()]=usersessions;
            werror(sprintf("New Usersessions for %s are %O\n",
                           this_user()->get_identifier(),
                           sessions[this_user()]));
        }
    }

    if (session)
        currUserSession[this_user()] = sid;
    
    return session;
}

object get_user_session()
{
    object o= get_user_session_by_id(currUserSession[this_user()]);
    return o;
}

void set_user_session(int sid)
{
    currUserSession[this_user()]=sid;
}
