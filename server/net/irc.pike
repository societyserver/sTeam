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
 * $Id: irc.pike,v 1.3 2010/01/27 12:05:35 astra Exp $
 */

constant cvs_version="$Id: irc.pike,v 1.3 2010/01/27 12:05:35 astra Exp $";

inherit "/net/coal/login";
inherit "/net/base/line";
inherit "/net/base/cmd";

#include <macros.h>
#include <config.h>
#include <access.h>
#include <database.h>
#include <events.h>
#include <client.h>
#include <classes.h>
#include <attributes.h>

#define STATE_AUTHORIZATION 1
#define STATE_TRANSACTION   2
#define STATE_UPDATE        3


//#define IRC_DEBUG 1

#ifdef IRC_DEBUG
#define DEBUG_IRC(s, args...) werror("IRC: " + s+"\n", args)
#else
#define DEBUG_IRC(s, args...) 
#endif

#define I_TIMEOUT         100

static string sServer = _Server->get_server_name();

static object oMailBox;
static object oChannel;
static string sNick;
static string sUser;
static string sChannel;
static string sPass;

class Dcc {
    Stdio.Port dcc_port;
    int port_nr;
    object doc;
};


class IrcListener {
  inherit Events.Listener;

  void create(int events, object obj) {
    ::create(events, PHASE_NOTIFY, obj, 0, oUser);
    obj->listen_event(this_object());
  }
  
  void notify(int event, mixed args, object eObject) {
    mixed err = catch(notify_irc(event, @args));
    DEBUG_IRC("Failed to notify in IRC: %O", err);
  }
  function get_callback() {
    return notify;
  }

  mapping save() { return 0; }

  string describe() {
    return "IrcListener()";
  }
}

static IrcListener   roomListener;
static IrcListener logoutListener;
static IrcListener   tellListener;

#define RPL_AWAY              301
#define RPL_ISON              303
#define RPL_WHOISUSER         311
#define RPL_WHOISOPERATOR     313
#define RPL_WHOISIDLE         314
#define RPL_ENDOFWHO          315
#define RPL_ENDOFWHOIS        318
#define RPL_WHOISCHANNELS     319

#define RPL_LISTSTART         321
#define RPL_LIST              322
#define RPL_LISTEND           323
#define RPL_WHOREPLY          352 
#define RPL_NAMEREPLY         353
#define RPL_ENDOFNAMES        366

#define RPL_MOTDSTART         375
#define RPL_MOTD              372
#define RPL_ENDOFMOTD         376

#define RPL_USERSSTART        392
#define RPL_USERS             393
#define RPL_ENDOFUSERS        394

#define ERR_NOSUCHNICK         401
#define ERR_NOSUCHSERVER       402
#define ERR_NOSUCHCHANNEL      403
#define ERR_CANNOTSENDTOCHAN   404
#define ERR_TOOMANYCHANNELS    405
#define ERR_WASNOSUCHNICK      406
#define ERR_TOOMANYTARGET      407
#define ERR_NORECIPIENT        411
#define ERR_UNKNOWNCOMMAND     421

#define ERR_NICKCOLLISION      436
#define ERR_NOTONCHANNEL       442

#define ERR_NEEDMOREPARAMS     461
#define ERR_PASSWDMISSMATCH    464
#define ERR_UNKNOWNMODE        472
#define ERR_INVITEONLYCHAN     473

static mapping mReplies = ([
    ERR_NOSUCHNICK: "No such nick/channel",
    ERR_PASSWDMISSMATCH: "Password incorrect",
    ERR_NICKCOLLISION: "Nickname collision KILL",
    RPL_ENDOFWHOIS: "End of /WHOIS list",
    ERR_INVITEONLYCHAN: "Cannot join channel (+i)",
    ERR_TOOMANYCHANNELS: "You have joined too many channels",
    ERR_UNKNOWNMODE: "is unknown mode char to me",
    RPL_USERSSTART: "UserID   Terminal   Host",
    RPL_ENDOFUSERS: "End of users",
    RPL_ENDOFWHO:  "End of /WHO",
    ]);

static void send_reply(string|int cmd, string|void|array(string) params)
{
    string trailing = 0;

    if ( arrayp(params) ) {
	params = params * " ";
    }
    else if ( !stringp(params) )
	params = "";
    
    LOG("Sending ok ("+cmd+")");
    if ( intp(cmd) ) {
	if ( stringp(mReplies[cmd]) )
	    trailing = mReplies[cmd];
	if ( cmd < 10 )
	    cmd = "00" + cmd;
	else if ( cmd < 100 )
	    cmd = "0" + cmd;
    }
    cmd = ":"+sServer+" "+ cmd + " " + 
        (objectp(oUser) ?  " " + oUser->get_identifier() : "");
    if ( stringp(trailing) ) {
	params += ":"+trailing;
    }
    
    if ( stringp(params) )
	send_message(cmd + " " + params + "\r\n");
    else
	send_message(cmd + "\r\n");
}

static void send_myself(string msg)
{
    send_message(cryptic_irc_name(oUser) + " PRIVMSG SERVER :" +msg+ "\r\n");
}

int get_port()
{
    string addr = query_address();
    int port;
    sscanf(addr, "%*s %d", port);
    return port;
}

void identd()
{
    Stdio.File identsock = Stdio.File();
    string ip = get_ip();
    if ( stringp(ip) && identsock->connect(ip, 113) ) {
	send_message(":"+sServer+
		     " NOTICE AUTH : *** Got Ident response\r\n");
	string msg = _Server->query_config("irc_port")+","+
	    get_port()+"\r\n";
	LOG("IDENTD:"+msg);
	identsock->write(msg);
	string str;
	
	int t = time();
	while ( (time()-t) < I_TIMEOUT && (
	    !stringp(str=identsock->read()) || strlen(str) == 0) ) 
	    ;
	
	LOG("REPLIES:"+str);
	send_message(":"+sServer+ 
		     " NOTICE AUTH : *** Found your hostname\r\n");
    }
}

void pinging()
{
    while ( 1 ) {
	sleep(120);
	if ( catch(send_message("PING " + sServer + "\r\n")) ) 
	    return; // end thread when connection is down
    }
}

void create(object f)
{
    ::create(f);
    send_message(":"+sServer+
		 " NOTICE AUTH : *** Looking up your hostname...\r\n");
    send_message(":"+sServer+" NOTICE AUTH : *** Checking Ident\r\n");
    
    //thread_create(identd);
    thread_create(pinging);
	
    sClientClass = "irc";
    oChannel = 0;
}


string cryptic_irc_name(object obj) 
{
    if ( !objectp(obj) )
	return "none";
    
    if ( IS_SOCKET(obj) ) {
        if ( !functionp(obj->get_socket_name) )
	    FATAL("No socket-name function in %O", obj);
	else if ( obj->get_socket_name() == "irc" )
	    return ":"+obj->get_nick() + "!~"+obj->get_nick() + "@"+obj->get_ip();
	obj = obj->get_user_object();
    }
    if ( !(obj->get_object_class() & CLASS_USER) )
	return ":("+obj->get_identifier()+")!~"+obj->get_identifier() +"@"+sServer;


    return ":"+obj->get_identifier() + "!~"+obj->get_identifier()+"@"+
	obj->get_ip(CLIENT_FEATURES_CHAT);
}

string channel_name(object obj)
{
    string channel;

    if ( objectp(obj) ) {
	channel = _FILEPATH->object_to_filename(obj);
	if ( sscanf(channel, "/home/%s", channel) > 0 )
	    channel = "&" + replace(channel," ", "^");
	else
	    channel = "#" + channel;
	return channel;
    }
    return "";
}

void notify_irc(int event, mixed ... args)
{
    object user = geteuid() || this_user();
    if ( !objectp(oUser) || !objectp(user) ) 
	return;

    switch(event) {
	case EVENT_SAY:
	    if ( user != oUser )
		send_message(cryptic_irc_name(user) + " PRIVMSG " + 
			     channel_name(args[0]) + " :" + args[2] +"\r\n");
	    break;
        case EVENT_LOGIN|EVENTS_MONITORED:
	    if ( intp(args[4]) && (args[4] & CLIENT_FEATURES_CHAT) )
		return; //previously had chat client active
	    if (intp(args[3]) && (args[3] & CLIENT_FEATURES_CHAT) )
		send_message(cryptic_irc_name(user) + " JOIN " + 
			     channel_name(user->get_environment())+"\r\n");
	    break;
        case EVENT_ENTER_INVENTORY:
	    if ( user->get_object_class() & CLASS_USER &&
		 user->get_status() & CLIENT_FEATURES_CHAT )
		send_message(cryptic_irc_name(user) + " JOIN " + 
			     channel_name(args[0])+"\r\n");
	    break;
        case EVENT_LOGOUT|EVENTS_MONITORED:
	    if ( user->get_object_class() & CLASS_USER )
		send_message(cryptic_irc_name(user) + " PART " + 
			     channel_name(args[0])+"\r\n");
	    break;
        case EVENT_LEAVE_INVENTORY:
	    if ( user->get_object_class() & CLASS_USER &&
		 user->get_status() & CLIENT_FEATURES_CHAT )
		send_message(cryptic_irc_name(user) + " PART " + 
			     channel_name(args[0])+"\r\n");
	    break;
        case EVENT_TELL:
	    send_message(cryptic_irc_name(user) + " PRIVMSG "+
			 args[0]->get_identifier() + " :"+args[2] + "\r\n");
	    break;
    }
}

object str_to_channel(string channel)
{
    int chann;
    if ( sscanf(channel, "#%d", chann) == 1 ) 
	return find_object(chann);
    else if ( channel[0] == '&' ) 
	return _FILEPATH->path_to_object(
	    "/home/"+replace(channel[1..],"^"," "));
    else
	return _FILEPATH->path_to_object(channel[1..]);
}

/*************************************************************************
 * authorization, login stuff
 */

static void pass(string p)
{
    sPass = p;
    if ( oUser == _GUEST )
    {
	if ( stringp(sNick) )
	    user(sNick);
    }
}

static void welcome_user()
{
    send_reply(1, ({ ":Welcome to the sTeam IRC network "+
			 cryptic_irc_name(oUser) }));
    send_reply(2, ({ ":Your host is "+ get_ip() }));
    send_reply(3, ({ ":This server was created " + 
			 replace(ctime(_Server->get_last_reboot()),"\n","")}));
    send_reply(4, ({ ":"+sServer+ " 1.0 steam users and channels " }) );
    send_reply(RPL_MOTDSTART, ":- "+ sServer+
               " Message of the day - ");
    send_reply(RPL_MOTD, ":- sTeam IRC Server");
    send_reply(RPL_MOTD, ":- Use your sTeam login as nick and");
    send_reply(RPL_MOTD, ":- your user password as server password or /msg steam pass <pass>");
    send_reply(RPL_MOTD, ":- Welcome! steam's workroom is default meeting place");
    send_reply(RPL_ENDOFMOTD, ":End of /MOTD command");
}

static void connect_user(object u)
{
    login_user(u);
    welcome_user();
    object channel = u->get_environment();
    DEBUG_IRC("Connecting user, environment is %O\n", channel);
    if ( objectp(channel) )
	join(channel_name(channel));
    if ( objectp(tellListener) )
      destruct(tellListener);
    tellListener = IrcListener(EVENT_TELL, u);
}

static void nick(string n)
{
    sNick = n;
}

static void user(string u)
{
    object user;
    
    sUser = u;
    if ( !stringp(sPass) ) {
	send_message(":sTeam!~steam@"+sServer+" PRIVMSG SERVER :" +
		     "Nickname " + sNick + 
		     " needs pass, /msg sTeam pass <yourpass> to login !\r\n");
	return;
    }
    user = get_module("auth")->authenticate(sNick, sPass);
    if ( objectp(user) ) 
    {
	if ( objectp(oUser) ) {
	    login_user(user);
	}
	else {
	    connect_user(user);
	}

    }
    else {
	send_reply(ERR_PASSWDMISSMATCH, sPass);
    }
    /* ERR_NICKNAMEINUSE ??? */

}


static void list(void|string param)
{
    LOG("list(" + param+")");
    array(object) rooms = ({ });
    array(object) groups = MODULE_GROUPS->get_groups();
    foreach(groups, object g) {
	object r = g->query_attribute(GROUP_WORKROOM);
	if ( objectp(r) )
	    rooms += ({ r });
    }
    send_reply(RPL_LISTSTART, "Channel: Users Name");
    foreach(rooms, object room) {
	string topic = room->query_attribute("irc:topic");
	if ( !stringp(topic) )
	    topic = room->get_identifier();
	send_reply(RPL_LIST, " "+channel_name(room)+ " " +
		   sizeof(get_users(room))+" :"+topic+"\r\n");
    }
    send_reply(RPL_LISTEND, ":End of /LIST");
}



static int join_channel(object channel)
{
    mixed err = catch {
	oUser->move(channel);
	if ( objectp(roomListener) )
	  destruct(roomListener);
	if ( objectp(logoutListener) )
	  destruct(logoutListener);
	
	roomListener = IrcListener(EVENT_SAY|EVENT_ENTER_INVENTORY|
				   EVENT_LEAVE_INVENTORY, channel);
	logoutListener= IrcListener(EVENT_LOGIN|EVENT_LOGOUT|EVENTS_MONITORED, 
				    channel);
    };
    return err == 0;
}

static void list_users(object channel) 
{
    array(object) users = get_users(channel);
    string user_str = "sTeam ";
    foreach(users, object u) {
	if ( u->get_status() & CLIENT_FEATURES_CHAT )
	    user_str += u->get_identifier() + " ";
    }
    send_reply(RPL_NAMEREPLY, " = " + channel_name(channel)+" :" + 
	       user_str);
    send_reply(RPL_ENDOFNAMES, ":End of /NAMES list.");
}

static array get_users(object channel)
{
   array(object) users = ({ });
   object event = channel->get_event(EVENT_SAY);
   array listeners = event->get_listeners();
   foreach(listeners, object l) {
     if ( !objectp(l) )
       continue;
     object u = l->get_listening();
     if ( objectp(u) && u->get_status() & CLIENT_FEATURES_CHAT )
       users += ({ u });
   }
   return users;
}

static void who(string channel)
{
    array(object) users = ({ });

    object chann = str_to_channel(channel);
    
    if ( objectp(chann) ) {
      users = get_users(chann);
    }
    if ( sizeof(users) > 0 ) {
	foreach(users, object user ) {
	    send_reply(RPL_WHOREPLY, 
		       ({ channel_name(chann),
			      user->get_identifier(),
			      user->get_ip(CLIENT_FEATURES_CHAT),
			      _Server->get_server_name(),
			      user->get_identifier(),
			      "H",
			      ": 0 "+user->query_attribute(USER_FULLNAME) }));
	}
	send_reply(RPL_WHOREPLY, 
		   ({ channel_name(chann),
			  "sTeam",
			  _Server->get_server_name(),
			  _Server->get_server_name(),
			  "sTeam",
			  "H",
			  ": 0 sTeam Server" }));
	send_reply(RPL_ENDOFWHO);
    }			  
}
	
static void join(string channels) 
{
    string keys = "";
    array(string) channs;
    
    sscanf(channels, "%s %s", channels, keys);
    channs = channels / ",";
    
    object chann = str_to_channel(channs[0]);
    if ( objectp(oChannel) && oChannel != chann ) {
	send_message(cryptic_irc_name(oUser) + " PART "+
		     channel_name(oChannel)+"\r\n");
    }

    if ( objectp(chann) ) {
	if ( join_channel(chann) ) {
	    oChannel = chann;
	    string msg = cryptic_irc_name(oUser)+" JOIN "+
			 channel_name(chann)+"\r\n";
	    send_message(msg);
	    reply_topic(chann);
	    list_users(chann);
	}
	else {
	    DEBUG_IRC("Invite Only Channel Message returned ...");
	    send_reply(ERR_INVITEONLYCHAN, channs[0]);
	}
    }
    else {
	DEBUG_IRC("No such channel returned upon joining %s", channels);
	send_reply(ERR_NOSUCHCHANNEL, channs[0]);
    }
}

static void part(string channel)
{
    object chann = str_to_channel(channel);
    if ( objectp(chann) ) {
	if ( chann == oChannel ) {
	    oChannel = 0;
	    send_message(cryptic_irc_name(oUser)+" PART "+
			 channel_name(chann)+"\r\n");
	}
	else
	    send_reply(ERR_NOTONCHANNEL, channel);
    }
    else
	send_reply(ERR_NOSUCHCHANNEL, channel);
}

void send_invite(string channel)
{	    
    send_reply(324, ({ channel, "+i", oUser->get_identifier() }));
    send_message(cryptic_irc_name(geteuid() || this_user()) + " INVITE "+oUser->get_identifier() + " "+channel+"\r\n");
}

static void invite(string user, string channel)
{
    object chann = str_to_channel(channel);
    if ( objectp(chann) ) {
	// give the user permissions
	object u = MODULE_USERS->lookup(user);
	if ( objectp(u) ) {
	    chann->sanction_object(u, SANCTION_READ|SANCTION_ANNOTATE);
	    send_reply(341, ({ user, channel }));
	    array(object) sockets = u->get_sockets();
	    foreach(sockets, object sock ) {
		if ( sock->get_socket_name() == "irc" )
		    sock->send_invite(channel);
	    }
	    return;
	}
	send_reply(ERR_NOSUCHNICK);
    }
    send_reply(ERR_NOSUCHCHANNEL, channel);
}

static void ison(string userlist) 
{
  array(string) rpl_user_list = ({ });
  array ul = userlist / " ";
  foreach(ul, string user) {
    object u = MODULE_USERS->lookup(user);
    if ( objectp(u) ) {
      if (u->get_client_features() & CLIENT_FEATURES_CHAT) {
	rpl_user_list += ({ user });
      }
    }
  }
  if (sizeof(rpl_user_list) > 0) {
    rpl_user_list[0] = ":" + rpl_user_list[0];
  }
  send_reply(RPL_ISON, rpl_user_list);
}

static void mode(string channel, void|string m)
{
    LOG("mode("+m+")");
    if ( !stringp(m) || strlen(m) == 0 ) 
	return;

    send_reply(ERR_UNKNOWNMODE); 
}

static void reply_topic(object channel)
{
    string channelstr, topic;
    channelstr = channel_name(channel);
    topic = channel->query_attribute("irc:topic");
    if ( !stringp(topic) )
	topic = channel->get_identifier();
    send_reply(332, ({ channelstr, ":" + topic }));
}

static void topic(string channel, string topic)
{
    LOG("topic("+topic+")");
    if ( !stringp(topic) )
	send_reply(ERR_NEEDMOREPARAMS, "topic");
    object chann = str_to_channel(channel);
    if ( objectp(chann) ) {
	chann->set_attribute("irc:topic", topic);
	reply_topic(chann);
    }
}

static void exec_response(string res)
{
    array(string) result = res / "\n";
    send_message(cryptic_irc_name(geteuid() || this_user()) + " PRIVMSG "+
		 _ROOT->get_identifier()+
		 " :---Result of execution---\r\n");
    foreach(result, string r) {
	send_message(cryptic_irc_name(geteuid() || this_user()) + " PRIVMSG "+
		     _ROOT->get_identifier()+" :"+r+"\r\n");
    }
}

static void exec(string msg)
{
    string res = execute("^" + msg);
    exec_response(res);
}

static void establish_dcc(string ip, int port, string fname, int size)
{
    object conn = Stdio.File();
    DEBUG_IRC("establishing dcc to "+ip+"\n");
    conn->connect(ip, port);
    conn->set_buffer(200000);
    string data, rd;
    rd = "";
    data = "";
    while ( stringp(rd=conn->read(1024,1)) && strlen(rd) > 0 ) {
	DEBUG_IRC("Read "+ strlen(rd) + " bytes...\n");
	data += rd;
	int sz = strlen(data);
	string str = "    ";
	str[0] = (sz & ( 255 << 24)) >> 24;
	str[1] = (sz & ( 255 << 16)) >> 16;
	str[2] = (sz & ( 255 << 8))  >>  8;
	str[3] = (sz & ( 255 ));
	conn->write(str);
    }
    conn->close();
    object doc = oChannel->get_object_byname(fname);
    if ( !objectp(doc) ) {
	object factory = get_factory(CLASS_DOCUMENT);
	doc = factory->execute( ([ "name": fname, ]) );
	doc->move(oChannel);
    }
    doc->set_content(data);
}

static void privmsg(string channel, string msg)
{
    LOG("privmsg("+channel+","+msg+")");
    
    if ( lower_case(channel) == "steam" ) {
	string cmd;
	
	if ( sscanf(msg, "\1%s %s\1", cmd, msg) != 2 &&
	     sscanf(msg, "%s %s", cmd, msg) != 2 )
	    cmd = "";
	DEBUG_IRC("Command is "+ cmd+"\n");
	switch ( cmd ) {
	case "PASS":
	case "pass":
#if 0
	    if ( oUser != _GUEST ) {
		send_message(cryptic_irc_name(oUser) + " PRIVMSG NICKSERV :" +
			     "You are already registered as "+
			     oUser->get_identifier()+"\r\n");
		return;
	    }
#endif
	    sPass = msg;
	    object u = get_module("auth")->authenticate(sNick, sPass);
	    if ( !objectp(u) )
		send_message(cryptic_irc_name(oUser) + " PRIVMSG NICKSERV :"+
			     "User not found or wrong password !\r\n");
	    else 
		connect_user(u);
	    return;
	case "DCC":
	case "dcc":
	    int sz = 0;
	    array args = (msg / " ");
	    DEBUG_IRC("DCC="+sprintf("%O",args)+"\n");
	    if ( sizeof(args) > 4 )
		sz = args[4];
	    if ( args[0] == "SEND" ) {
		establish_dcc(get_ip(), (int)args[3], args[1], sz);
	    }
	    break;
        case "LOG":
        case "log":
          object chatlog = get_module( "package:chatlog" );
          if ( !objectp(chatlog) ) {
            if ( stringp(channel) && sizeof(channel)>0 )
              send_message( cryptic_irc_name(oUser) + " PRIVMSG " + channel +
                           " : Could not find chatlog module\r\n" );
            return;
          }
          object room = oUser->get_environment();
          if ( !objectp(room) ) {
            if ( stringp(channel) && sizeof(channel)>0 )
              send_message( cryptic_irc_name(oUser) + " PRIVMSG " + channel +
                           " : Invalid room for logging\r\n");
            return;
          }
          switch ( msg ) {
            case "list" :
            case "LIST" :
              {
              send_message( cryptic_irc_name(oUser) + " PRIVMSG " + channel +
                            sprintf(" : Active chat-Logs: %O\r\n", chatlog->get_rooms()) );
              }
              break;
            case "on" :
            case "ON" :
              {
              int success;
              mixed err = catch { success = chatlog->log_room( room, true ); };
              object file = chatlog->get_logfile( room );
              string filename = "";
              if ( objectp(file) ) filename = sprintf( " to %s", get_module("filepath:tree")->object_to_filename(file) );
              string result_msg = sprintf("Logging chat in room %s to file %s\r\n",
                  room->query_attribute(OBJ_NAME), filename );
              if ( err ) result_msg = err[0];
              else if ( !success ) result_msg = sprintf("Failed to turn on logging for room %s", room->query_attribute(OBJ_NAME));
              send_message( cryptic_irc_name(oUser) + " PRIVMSG " + channel +
                            " : " + result_msg + "\r\n");
              }
              break;
            case "off" :
            case "OFF" :
              {
              int success;
              object file = chatlog->get_logfile( room );
              string filename = "";
              if ( objectp(file) ) filename = sprintf( " to %s", get_module("filepath:tree")->object_to_filename(file) );
              mixed err = catch { success = chatlog->log_room( room, 0 ); };
              string result_msg = sprintf("Stopped logging chat in room %s to file %s\r\n",
                  room->query_attribute(OBJ_NAME), filename );
              if ( err ) result_msg = err[0];
              else if ( !success ) result_msg = sprintf("Failed to turn off logging for room %s", room->query_attribute(OBJ_NAME));
              send_message( cryptic_irc_name(oUser) + " PRIVMSG " + channel +
                            " : " + result_msg + "\r\n");
              }
              break;
            default :
              {
              int success;
              mixed err = catch { success = chatlog->log_room( room, true, msg ); };
              object file = chatlog->get_logfile( room );
              string filename = "";
              if ( objectp(file) ) filename = sprintf( " to %s", get_module("filepath:tree")->object_to_filename(file) );
              string result_msg = sprintf("Logging chat in room %s to file %s\r\n",
                  room->query_attribute(OBJ_NAME), filename );
              if ( err ) result_msg = err[0];
              else if ( !success ) result_msg = sprintf("Failed to turn on logging for room %s", room->query_attribute(OBJ_NAME));
              send_message( cryptic_irc_name(oUser) + " PRIVMSG " + channel +
                            " : " + result_msg + "\r\n");
              }
              break;
          }
          
          break;
	}
	DEBUG_IRC("Command not understood !\n");
	return;
    }


    object chann = str_to_channel(channel);
    if ( objectp(chann) ) {
	sChannel = channel;
	if ( msg[0] == '=' || msg[0] == '^' ) {
	    string res = execute(msg);
	    exec_response(res);
	    return;
	}
	chann->message(msg);
	return;
    }
    else {
	object user = MODULE_USERS->lookup(channel);
	if ( objectp(user) ) {
	    if ( user == (geteuid() || this_user()) ) {
		string res = execute("="+msg);
		exec_response(res);
		return;
	    }
	    user->message(msg);
	    if ( !(user->get_status() & CLIENT_FEATURES_CHAT) ) {
		user->mail(msg);
		send_reply(RPL_AWAY, 
			   ({ channel, ": The user is currently "+
				  "not connected to sTeam - message mailed"}));
	    }
	}
	return;
    }
    send_reply(ERR_NORECIPIENT, ({ ":No recipient given (PRIVMSG)" }));
}

static void names(string channel) 
{
    object chann = str_to_channel(channel);
    if ( objectp(chann) )
	list_users(chann);
}

static void inventory()
{
    array inv = (geteuid() || this_user())->get_inventory();
    send_reply(371, ({ ":You are carrying: " }) );
    foreach(inv, object o) {
	send_reply(371, ({ ": " + o->get_identifier() + "[" +
			       o->get_object_id() + "]" }));
    }
}

string describe_object(object obj)
{
    return obj->get_identifier() + " ["+obj->get_object_id() + "]";
}

static void look()
{
    object channel = (geteuid() || this_user())->get_environment();
    send_message(cryptic_irc_name(geteuid() || this_user()) + " PRIVMSG " +
		 channel_name(channel) + " : Container in Area:\r\n");
    
    string str = "  ";
    foreach(channel->get_inventory_by_class(CLASS_CONTAINER), object obj) {
	str += obj->get_identifier()+", ";
    }
    send_message(cryptic_irc_name(geteuid() || this_user()) + " PRIVMSG " +
		 channel_name(channel) + " : " +
		 str + "\r\n");
    str = "";
    send_message(cryptic_irc_name(geteuid() || this_user()) + " PRIVMSG " +
		 channel_name(channel) + " : Documents in Area:\r\n");
    foreach(channel->get_inventory_by_class(CLASS_DOCUMENT), object doc) {
	str += doc->get_identifier()+", ";
    }
    send_message(cryptic_irc_name(geteuid() || this_user()) + " PRIVMSG " +
		 channel_name(channel) + " : " +
		 str + "\r\n");
}

static void give(string ostr, string toto, string tostr)
{
    object too = MODULE_USERS->lookup(tostr);
    object obj = oUser->get_object_byname(ostr);
    if ( !objectp(too) )
	send_reply(ERR_NOSUCHNICK);
    if ( objectp(obj) )
    {
	mixed err = catch {
	    obj->move(too);
	};
	if ( err == 0 )
	    send_reply(371, ({ ": " + ostr + " given to " + tostr }));
    }
}

static void compile(string fname)
{
    send_myself(cmd_compile(fname));
}

static void ping(string t)
{
    send_message(":"+sServer+ " PONG " + sServer + "\r\n");
}

static void pong(string t)
{
}

static void whois(string user)
{
    object ouser = MODULE_USERS->lookup(user);
    if ( !objectp(ouser) ) {
	send_reply(ERR_NOSUCHNICK);
    }
    else {
	send_reply(RPL_WHOISUSER, 
		   ({ ouser->get_identifier(),
			  ouser->get_identifier(),
			  ouser->get_ip(CLIENT_FEATURES_CHAT),
			  "*",
			  ":"+ouser->query_attribute(USER_FULLNAME) }));
	send_reply(RPL_WHOISCHANNELS,
		   ({ ouser->get_identifier(),
			  ":"+channel_name(ouser->get_environment()) }) );
	array(object) sockets = ouser->get_sockets();
	mapping socketClasses = ([ ]);
	foreach(sockets, object s) {
	    socketClasses[s->get_socket_name()]++;
	}
	string socketStr = "";
	foreach(indices(socketClasses), string c) {
	    socketStr += c+"("+socketClasses[c]+"), ";
	}
	send_reply(RPL_WHOISCHANNELS,
		   ({ ouser->get_identifier(), ":"+socketStr }));
        if ( !(ouser->get_status() & CLIENT_FEATURES_CHAT) )
            send_reply(RPL_AWAY, ({ ouser->get_identifier(), 
               ":No chat client" }));
	send_reply(RPL_ENDOFWHOIS);
    }
}

static void dcc_send(object id)
{
    Stdio.File sock = id->dcc_port->accept();
    object doc = id->doc;
    function f = doc->get_content_callback();
    sock->set_buffer(200000);
    string data;
    while ( (stringp(data = f())) ) {
	sock->write(data);
	sock->read(4);
    }
    sock->close();
    master()->dispose_port(id->port_nr);
    destruct(id->dcc_port);
    destruct(id);
}

static void download(string fname)
{
    object doc = oChannel->get_object_byname(fname);
    int port = 33333;
    string ipaddr = _Server->get_server_ip();
    
    if ( stringp(ipaddr) && objectp(doc) ) {
	object id_dcc = Dcc();
	for ( ; port < 34000; port++ ) 
	    if ( master()->free_port(port) )
		break;
	id_dcc->doc = doc;
	id_dcc->dcc_port = Stdio.Port();
	id_dcc->port_nr = port;
	id_dcc->dcc_port->set_id(id_dcc);
	id_dcc->dcc_port->bind(id_dcc->port_nr, dcc_send);
	master()->use_port(port);
	int ip, one, two, three, four;
	
	sscanf(ipaddr, "%d.%d.%d.%d", one, two, three, four);
	ip = (one<<24)+(two<<16)+(three<<8)+four;
	send_message(":sTeam!~steam@"+sServer+ 
		     " PRIVMSG "+oUser->get_identifier()+
		     " :\1DCC SEND "+fname+" "+
		     ip + " " + id_dcc->port_nr + " " + 
		     doc->get_content_size()+"\1\r\n");
    }
}

static void users(string|void server)
{
    array(object) users = _STEAMUSER->get_members();
    
    send_reply(RPL_USERSSTART);
    foreach(users, object u) {
        if ( u->get_status() & CLIENT_FEATURES_CHAT ) {
            send_reply(RPL_USERS, ({ sprintf(":%-8s %-9s %-8s",
                       u->get_identifier(), "IRC", "*" )}));
        }
    }
    send_reply(RPL_ENDOFUSERS);
}

static void quit(string message)
{
    if ( objectp(oUser) ) oUser->disconnect();
    if ( objectp(roomListener) )
      destruct(roomListener);
    if ( objectp(logoutListener) )
      destruct(logoutListener);
    if ( objectp(tellListener) )
      destruct(tellListener);
    close_connection();
}

object get_user()
{
    return oUser;
}

static mapping mCmd = ([ 
    "user": user,
    "pass": pass,
    "nick": nick,
    "list": list,
    "join": join,
    "mode": mode,
    "part": part,
    "leave": part,
    "privmsg": privmsg,
    "names": names,
    "users": users,
    "who": who,
    "whois": whois,
    "quit": quit,
    "ping": ping,
    "pong": pong,
    "ison": ison,
    "topic": topic,
    "invite": invite,
    "x": exec,
    "give": give,
    "compile": compile,
    "inv": inventory,
    "download": download,
    "look": look,
    ]);

static void process_command(string cmd)
{
    array(string)           commands;
    string      prefix, trailing = 0;
    
    if ( sscanf(cmd, ":%s %s", prefix, cmd) > 0 ) {
	LOG("Prefix: "+ prefix);
    }
    if ( sscanf(cmd, "%s :%s", cmd, trailing ) == 2 ) {
	LOG("Trailing: "+ trailing);
    }
    
    commands = cmd / " ";
    LOG("COMMANDS:"+sprintf("%O",commands));
    if ( stringp(trailing) )
	commands += ({ trailing });
    
    for ( int i = 0; i < sizeof(commands); i++ ) {
	mixed token = commands[i];
        int l = strlen(token);
	if ( sscanf(token, "%d", token) && strlen((string)token) == l )
	    commands[i] = token;
    }
    string fcmd = lower_case(commands[0]);
    function f = mCmd[fcmd];
    if ( functionp(f) ) {
	if ( objectp(oUser) ) {
	    if ( fcmd != "ping" && fcmd != "pong" )
		oUser->command_done(time());
	}
	if ( sizeof(commands) == 1 )
	    f();
	else
	    f(@commands[1..]);
	return;
    }
    send_reply(ERR_UNKNOWNCOMMAND, ({ cmd, ":Unknown command" }));
}

int get_client_features() { return CLIENT_FEATURES_ALL; }
string get_socket_name() { return "irc"; }
string get_nick() { return sNick; }
string describe() { return "IRC("+sNick+","+get_ip()+")"; }




