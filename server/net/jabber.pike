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
 * $Id: jabber.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: jabber.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/net/coal/login";
inherit "/kernel/coalsocket";
inherit "/net/base/cmd";

#include <macros.h>
#include <database.h>
#include <attributes.h>
#include <events.h>
#include <client.h>
#include <classes.h>

//#define JABBER_DEBUG

#ifdef JABBER_DEBUG
#define DEBUG_JABBER(s, args...) werror("Jab: "+s+"\n", args)
#else
#define DEBUG_JABBER(s, args...)
#endif

class JabberListener {
  inherit Events.Listener;

  void create(int events, object obj) {
    ::create(events, PHASE_NOTIFY, obj, 0, oUser);
    obj->listen_event(this_object());
  }
  
  void notify(int event, mixed args) {
    notify_jabber(event, @args);
  }
  function get_callback() {
    return notify;
  }

  mapping save() { return 0; }

  string describe() {
    return "JabberListener()";
  }
}


static array(string) queue = ({ });
static mapping command = ([ ]);
static mapping insertMap;
static mapping mRegisterKeys = ([ ]);

// listener
static JabberListener tellListen;
static mapping       loginListen = ([ ]);
static mapping      logoutListen = ([ ]);
static mapping         sayListen = ([ ]);

static string sUserName = "";

#if constant(Parser.get_xml_parser)
static Parser.HTML xmlParser = Parser.get_xml_parser();
#else
static object xmlParser = 0;
#endif

void open_stream()
{
  send_message("<stream:stream from=\""+_Server->get_server_name()+
	       "\" xmlns=\"jabber:client\" "+
		 "xmlns:stream=\"http://etherx.jabber.org/streams\">");
}

void close_stream()
{
    send_message("</stream:stream>\n");
    if ( objectp(oUser) )
	oUser->disconnect();
    foreach(values(logoutListen), object o)
      destruct(o);
    foreach(values(loginListen), object x)
      destruct(x);
    foreach(values(sayListen), object s)
      destruct(s);
    destruct(tellListen);
    close_connection();
}

void disconnect()
{
  DEBUG_JABBER("Disconnecting");
  if ( objectp(oUser) )
    oUser->disconnect();
  ::close_connection();
}

void send_iq_result(int code, string|void desc)
{
    if ( !stringp(desc) ) desc = "";

    if ( !stringp(command->iq->id) )
	return;

    if ( code == 0 ) 
	send_message("<iq type=\"result\" id=\""+command["iq"]["id"]+"\">\n"+
		     desc+"</iq>\n");
    else
	send_message("<iq type=\"result\" id=\""+command["iq"]["id"]+"\">\n"+
		     "<error code=\""+code+"\">"+desc+"</error>\n</iq>\n");
}

string name_on_server(string|object user)
{
    string n;

    if ( stringp(user) ) 
	n = user;
    else if ( objectp(user) )
      n = user->get_identifier();
    else
      n = sUserName;
    
    return n + "@"+_Server->get_server_name();
}

string get_nick(string name)
{
    sscanf(name, "%s@%*s", name);
    return name;
}

void notify_jabber(int event, mixed ... args)
{
    DEBUG_JABBER("notify("+event+", in %O): " + sprintf("%O\n", args), oUser);
    switch( event ) {
    case EVENT_LOGIN: {
	send_message("<presence from=\""+name_on_server(geteuid() || this_user()) +"\"/>");
    } break;
    case EVENT_LOGOUT: {
	send_message("<presence type=\"unavailable\" from=\""+
		     name_on_server(args[0]) +"\"/>");
    } break;
    case EVENT_TELL: {
      string msg = htmllib.quote_xml( args[2] );
	send_message("<message type='chat' to=\""+name_on_server(oUser)+
		     "\" from=\""+
		     name_on_server(geteuid() || this_user())+
		     "\"><body>"+msg+"</body></message>\n");
    } break;
    case EVENT_SAY: {
      if  ( (geteuid() || this_user()) == oUser )
	return;
      string msg = htmllib.quote_xml( args[2] );
      msg = (geteuid() || this_user())->get_user_name() + ": "+ msg;
      object grp = args[0]->get_creator();
      string rcpt = (geteuid() || this_user())->get_user_name();
      if ( objectp(grp) )
	rcpt = grp->get_identifier();
      send_message("<message type='chat' to=\""+name_on_server(oUser)+
		   "\" from=\""+ name_on_server(rcpt)+
		   "\"><body>"+msg+"</body></message>\n");
    } break;
    }
}


array get_roster()
{
  array roster;
  object user;
    
  user = USER(sUserName);
  if ( !objectp(user) ) 
    return ({ });
  roster = user->query_attribute(USER_FAVOURITES);
  if ( !arrayp(roster) )
    roster = ({ });
  return roster;
}

void handle_auth(string user, string pass, string|void digest)
{
    object u = _Persistence->lookup_user(user);
    if ( stringp(digest) )
	DEBUG_JABBER("DIGEST="+digest+", MD5="+u->get_password()+"\n");
    if ( !objectp(u) )
      FATAL("Unable to find user " + user);
    if ( objectp(u) && u->check_user_password(pass) ) {
	login_user(u);
	tellListen = JabberListener(EVENT_TELL, u);
	send_iq_result(0);

	loginListen = ([ ]);
	logoutListen = ([ ]);
	sayListen = ([ ]);

	foreach(get_roster(), object user) {
	  if ( user->status() < 0 ) continue;
	  
	  if ( user->get_object_class() & CLASS_USER ) {
	    loginListen[user] = JabberListener(EVENT_LOGIN, user);
	    logoutListen[user] = JabberListener(EVENT_LOGIN, user);
	  }
	  else if ( user->get_object_class() & CLASS_GROUP ) {
	    sayListen[user] = 
	      JabberListener(EVENT_SAY, user->query_attribute(GROUP_WORKROOM));
	  }
	}
	// initial presence ?
    }
    else {
	send_iq_result(401, "Unauthorized");
    }
}

void handle_roster()
{
    object u;
    array roster = get_roster();
    string result = "<query xmlns=\"jabber:iq:roster\">\n";

    if ( command->iq->type == "get" ) {
	foreach(roster, u) {
	    result += "<item jid=\""+name_on_server(u->get_identifier())+"\""+
		" name=\""+u->get_identifier()+
		"\" subscription=\"both\">"+
		" <group>steam</group></item>";
	}
	result += "</query>";
	send_iq_result(0, result);
	return;
    }
    else if ( command->iq->type == "set" ) {
	string nick = get_nick(command->iq->item->jid);
	string gname = command->iq->item->group;
	if ( !stringp(gname) ) gname = "Friends";
	
	//! TODO: add support for rooms
	u = _Persistence->lookup_user(nick);
	if ( !objectp(u) )
	  u = GROUP(nick);

	if ( command->iq->item->subscription == "remove" ) {
	    result += "<item jid=\""+name_on_server(u)+"\""+
		" name=\""+u->get_identifier()+
		"\" subscription=\"remove\">"+
		" <group>steam</group></item>";
	    roster -= ({ u });
	    (geteuid() || this_user())->set_attribute(USER_FAVOURITES, roster);
	    if ( objectp(loginListen[u]) )
	      destruct(loginListen[u]);
	    if ( objectp(logoutListen[u]) )
	      destruct(logoutListen[u]);
	}
	else {
	  if ( objectp(u) ) {
	    // see if user is online
	    if ( search(roster, u) == -1 ) {
	      roster += ({ u });	    
	      if ( u->get_object_class() & CLASS_USER && 
		   u->get_status() & CLIENT_FEATURES_CHAT ) 
	      {
		loginListen[u] = JabberListener(EVENT_LOGIN, u);
		logoutListen[u] = JabberListener(EVENT_LOGOUT, u);
	      }
	      if ( u->get_object_class() & CLASS_GROUP ) {
		sayListen[u] = 
		  JabberListener(EVENT_SAY, u->query_attribute(GROUP_WORKROOM));
	      }
	      oUser->set_attribute(USER_FAVOURITES, roster);
	    }
	    result += "<item jid=\""+name_on_server(u)+"\""+
	      " name=\""+u->get_identifier()+"\" subscription='to'>" +
		" <group>steam</group> </item>";
	  }
	}
	result += "</query>";
	send_iq_result(0, result);
	send_message(
	    "<iq type=\"set\" to=\""+name_on_server(geteuid() || this_user())+"\">"+
	    result+"</iq>\n");
	if ( u->get_object_class() & CLASS_GROUP || 
	     u->get_status() & CLIENT_FEATURES_CHAT ) 
	{
	  send_message("<presence from='"+name_on_server(u)+"' />\n");
	}
    }
}

void handle_vcard()
{
    mixed err;
    // whom ???
    string nick = get_nick(command->iq->to);

    object u = _Persistence->lookup_user(nick);
    if ( objectp(u) ) {
	string uname = u->query_attribute(USER_FULLNAME);
	string gname,sname, email;
	sscanf(uname, "%s %s", gname, sname);
	err = catch {
	    email = u->query_attribute(USER_EMAIL);
	};
	send_message("<iq type=\"result\" from=\""+command->iq->to+"\" id=\""+
		     command->iq->id+"\">"+
		     "<vCard xmlns=\"vcard-temp\">\n"+
		     "<N><FAMILY>"+ sname + "</FAMILY>"+
		     "<GIVEN>"+gname+"</GIVEN>"+
		     "<MIDDLE/></N>\n"+
		     "<NICKNAME>"+u->get_identifier()+"</NICKNAME>"+
		     "<TITLE/>"+
		     "<ROLE/>"+
		     "<TEL/>"+
		     "<ADR/>"+
		     "<EMAIL>"+email+"</EMAIL>"+
		     "</vCard>"+
		     "</iq>\n");
	    
    }
    else {
	send_iq_result(400, "No Such User");
    }
}

void handle_register()
{
    if ( command->iq->type == "get" ) {
	string uname = get_nick(command->iq->to);
	object u = _Persistence->lookup_user(uname);
	if ( !objectp(u) )
	  u = GROUP(uname);
	if ( objectp(u) ) {
	    send_message("<iq type=\"result\" from=\""+command->iq->to+
			 "\" to=\""+name_on_server(geteuid() || this_user()) + "\" id=\""+
			 command->id->id+"\">\n"+
			 "<query xmlns=\"jabber:iq:register\">\n"+
			 "<registered />"+
			 "</query>\n"+
			 "</iq>\n");
	}
	else {
	    send_message("<iq type=\"result\" from=\""+command->iq->to+
			 "\" to=\""+name_on_server(geteuid() || this_user()) + "\" id=\""+
			 command->id->id+"\">\n"+
			 "<query xmlns=\"jabber:iq:register\">\n"+
			 "<username />"+
			 "<password />"+
			 "</query>\n"+	
		 "</iq>\n");
	}
    }
}

void handle_auth_init(string user)
{
    if ( command->iq->type == "get" ) {
      object uobj = USER(user);
      if ( !objectp(uobj) ) 
	send_message("<iq type=\"error\" from=\""+_Server->get_server_name()+
		     "\" id=\""+		     command->iq->id+"\">\n"+
		     "<query xmlns=\"jabber:iq:auth\">\n"+
		     "<error type='cancel' code='409'>\n"+
		     "  <conflict xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>\n"+ 
		     "</error>\n</query>\n</id>\n");
      else
	send_message("<iq type=\"result\" from=\""+user+ "\" id=\""+
		     command->iq->id+"\">\n"+
		     "<query xmlns=\"jabber:iq:auth\">\n"+
		     "<username />"+
		     "<password />"+
		     "</query>\n"+	
		     "</iq>\n");
    }
}

void handle_private()
{
}

int check_auth()
{
  object user = USER(sUserName);
  if ( !objectp(user) ) {
    send_message("<stream:error>\n"+
		 "  <not-authorized />\n"
		 "</stream:error>\n");
    return 0;
  }
  return 1;
}

void handle_iq()
{
    if ( command->vCard ) {
	handle_vcard();
    }
    if ( command->iq->query ) {
	switch(command->iq->query->xmlns) {
	case "jabber:iq:auth":
	  sUserName = command->iq->query->username->data;
	  if ( mappingp(command->iq->query->password) )
	    handle_auth(sUserName, command->iq->query->password->data);
	  else if ( mappingp(command->iq->query->digest) )
	    handle_auth(sUserName, 0, command->iq->query->digest->data);
	  else
	    handle_auth_init(sUserName);
	  break;
	case "jabber:iq:roster":
	  if ( !check_auth() )
	    return;
	  handle_roster();
	  break;
	case "jabber:iq:register":
	    handle_register();
	    break;
	case "jabber:iq:agents":
	  if ( !check_auth() )
	    return;
	  // deprecated anyway
	  send_message("<iq id='"+command->iq->id+"' type='result'>"+
		       "<query xmlns='jabber:iq:agents' /> </iq>\n");
	  break;
	case "jabber:iq:private":
	  if ( !check_auth() )
	    return;
	  handle_private();
	  break;
	}
    }
}

static string compose_html(mapping html)
{
  string result = "";
  foreach(indices(html), string idx) {
    if ( stringp(html[idx]) )
      result += html[idx];
    else if ( mappingp(html[idx]) )
      result += sprintf("<%s>%s</%s>", idx, compose_html(html[idx]), idx);
  }
  return result;
}

void handle_message()
{
    string nick = command->message->to;
    sscanf(nick, "%s@%*s", nick);
   
    object u = MODULE_USERS->lookup(nick);
    if ( !objectp(u) ) {
      u = GROUP(nick);
      if ( objectp(u) )
	u = u->query_attribute(GROUP_WORKROOM);
    }
    MESSAGE("handle_message() to %s, %O", nick, u);
    string msg;
    if ( stringp(command->message->body->data) )
      msg = command->message->body->data;
    else if ( stringp(command->message->html->data) )
      msg = compose_html(command->message->html);
    else 
      FATAL("Cannot get jabber message: %O\n", command);
    
    if ( stringp(msg) && strlen(msg) > 0 && msg[0] == '=' ) {
      msg = htmllib.unquote_xml(msg);
      string result = execute(msg);
      send_message("<message type='chat' to=\""+name_on_server(oUser)+
		   "\" from=\""+name_on_server(nick)+"\"><body>"+
		   htmllib.quote_xml(result)+"</body></message>\n");
      return;
    }

    if ( objectp(u) ) {
      u->message(msg);
    }
       
}

void handle_presence()
{
    if ( stringp(command->presence->to) ) {
	string uname = get_nick(command->presence->to);
	object user = USER(uname);
	if ( !objectp(user) ) {
	  send_message("<presence from=\""+command->presence->to+"\" "+
		       "to=\""+name_on_server(geteuid() || this_user())+"\" "+
		       "type=\"unsubscribed\" />\n");
	  
	  return;
	}
	// TODO: handle subscription
	if ( command->presence->type == "subscribe" ) {
	  send_message("<presence from=\""+name_on_server(user)+"\" "+
		       "to=\""+name_on_server(geteuid() || this_user())+"\" "+
		       "type=\"subscribed\" />\n");
	  array roster = get_roster();
	  if ( search(roster, user) == -1 ) {
	    loginListen[user] = JabberListener(EVENT_LOGIN, user);
	    logoutListen[user] = JabberListener(EVENT_LOGOUT, user);
	    roster += ({ user });
	    (geteuid() || this_user())->set_attribute(USER_FAVOURITES, roster);
	  }
	  if ( user->get_status() & CLIENT_FEATURES_CHAT )
	    send_message("<presence from=\""+name_on_server(user) + "\" />\n");
	}

    }
    else {
      //send_message("<presence from=\""+name_on_server(geteuid() || this_user())+"\"/>\n");
      foreach(get_roster(), object u) {
	DEBUG_JABBER("PRESENCE: Roster %O", u);
	if ( u == oUser ) continue;
	
	if ( u->get_object_class() & CLASS_GROUP || 
	     u->get_status() & CLIENT_FEATURES_CHAT ) 
	{
		send_message("<presence from=\""+
			     name_on_server(u)+"\"/>\n");
	}
      }
    }
}

void handle_command(string cmd)
{
  mixed err = catch {
    DEBUG_JABBER("HANDLE_COMMAND: "+cmd+"\n"+sprintf("%O\n",command));
    switch(cmd) {
    case "presence":
      handle_presence();
      break;
    case "iq":
      handle_iq();
      break;
    case "message":
      handle_message();
      break;
    }
    command = ([ ]);
  };
  if ( err ) {
    FATAL("Error in JABBER: handle_command():\n%O\O", err[0], err[1]);
    send_message("<stream:error>\n"+
		 "  <internal-server-error/>\n"
		 "</stream:error>\n");
  }
}

private static int data_callback(Parser.HTML p, string data)
{
    if ( sizeof(queue) == 0 )
	return 0;
    string name = queue[-1];
    insertMap[name]["data"] = data;
    return 0;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
private static int tag_callback(Parser.HTML p, string tag)
{
    string name;
    mapping attr = ([ ]);
    if ( tag[-2] == '/' ) {
	attr["/"] = "/";
	tag[-2] = ' ';
    }
    attr += p->parse_tag_args(tag);
    
    foreach(indices(attr), string a ) {
	if ( a != "/" && attr[a] == a ) {
	    name = a;
	    m_delete(attr, name);
	    break;
	}
    }

    if ( name == "stream:stream" ) {
	open_stream();
    }
    else if ( name == "/stream:stream" ) {
	close_stream();
    }
    else if ( name[0] == '/' ) {
	if ( name[1..] == queue[-1] ) {
	    if ( sizeof(queue) == 1 ) {
		queue = ({ });
		handle_command(name[1..]);
	    }
	    else {
		queue = queue[..sizeof(queue)-2];
	    }
	}
	else {
	    DEBUG_JABBER("Mismatched tag: " + name);
	}
    }
    else if ( attr["/"] == "/" ) {
	m_delete(attr, "/");
        insertMap = command;
        foreach(queue, string qtag) {
          if ( mappingp(insertMap[qtag]) )
            insertMap = insertMap[qtag];
        }
	insertMap[name] = attr;
	if ( sizeof(queue) == 0 ) {
	    handle_command(name);
	}
    }
    else {
      insertMap = command;
      foreach(queue, string qtag) {
	if ( mappingp(insertMap[qtag]) )
	  insertMap = insertMap[qtag];
      }
      insertMap[name] = attr;
      queue += ({ name });
    }
    return 0;
}

static void receive_message(string data)
{
  DEBUG_JABBER("feeding: %s", data);
  xmlParser->feed(data);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
static void send_message(string msg)
{
  DEBUG_JABBER("MESSAGE(%O): %s", oUser, msg);
  ::send_message(msg);
}

static void create(object f)
{
    ::create(f);
    xmlParser->_set_tag_callback(tag_callback);
    xmlParser->_set_data_callback(data_callback);
}

string get_socket_name() { return "Jabber"; }
int get_client_features() { return CLIENT_FEATURES_ALL; }
