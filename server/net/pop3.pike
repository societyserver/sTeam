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
 * $Id: pop3.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: pop3.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/net/coal/login";
inherit "/net/base/line";

#include <macros.h>
#include <config.h>
#include <database.h>

#define STATE_AUTHORIZATION 1
#define STATE_TRANSACTION   2
#define STATE_UPDATE        3

static int _state = STATE_AUTHORIZATION;
static string sServer = _Server->query_config("server");
static object oMailBox;

static void send_ok(string msg)
{
    LOG("Sending ok ("+msg+")");
    send_message("+OK " + msg + "\r\n");
}

static void send_err(string msg)
{
    LOG("Sending error ("+msg+")");
    send_message("-ERR " + msg + "\r\n");
}


static mapping mCmd = ([ 
    STATE_AUTHORIZATION: ([ 
	"APOP": apop, 
	"USER": user,
	"PASS": pass,
	"AUTH": auth,
	"QUIT": quit,
	"CAPA": capa,
	]),
    STATE_TRANSACTION: ([
	"STAT": stat,
	"LIST": list,
	"RETR": retr,
	"DELE": dele,
	"QUIT": quit,
	"UIDL": uidl,
	"TOP": top,
	"CAPA": capa,
	]),
    ]);


static string greeting()
{
    return "<1234."+time()+"@"+sServer+">";
}

void create(object f)
{
    ::create(f);
    send_ok("POP3 Server ready " + greeting());
}

string tohex(string what)
{
    int i = 0;
    for ( int q = 0; q < strlen(what); q++ ) {
	i <<= 8;
	i |= what[strlen(what)-1-q];
    }
    return sprintf("%x", i);
}

/**
 * Authenticate to the pop server.
 *  
 * @param string user - the current user.
 * @param string auth - the authorization string.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void apop(string user, string auth)
{
    if ( oUser->check_user_password_md5(greeting(), auth) )
	send_ok("maildrop has 0 message (0 octets)");
    else
	send_err("authentification failed");
}

static void auth(string type)
{
  LOG("auth("+type+")");
  send_err("Unrecognized authentication type");
}

static void user(string u)
{
    oUser = _Persistence->lookup_user(u);
    if ( !objectp(oUser) )
	send_err("no such user ("+u+")");
    send_ok("user, now send pass");
}

static string status_mailbox()
{
    return oUser->get_identifier()+"'s maildrop has " + 
	oMailBox->get_num_messages() + " messages ("+
	oMailBox->get_size() + " octets)";
}

static void pass(string p)
{
    if ( oUser->check_user_password(p) ) {
	oMailBox = _Server->get_module("mailbox")->get_mailbox(oUser);
	login_user(oUser);
	send_ok(status_mailbox());
	_state = STATE_TRANSACTION;
	LOG("login ok..."+sprintf("%O", get_user_object()));
    }
    else
	send_err("Password does not match");
}

static void stat() 
{
    send_ok(oMailBox->get_num_messages() + " " + oMailBox->get_size());
}

static void list(int num)
{
    stat();
    for ( int i = 0; i < oMailBox->get_num_messages(); i++ ) {
	send_message((i+1) + " " + oMailBox->get_message_size(i) +"\r\n");
    }
    send_message(".\r\n");
}

static void retr(int num)
{
    send_ok(oMailBox->get_message_size(num-1)+ " octets");
    send_message(oMailBox->retrieve_message(num-1));
    send_message("\r\n.\r\n");
}

static void dele(int num)
{
    if ( oMailBox->delete_message(num-1) ) 
	send_ok("message "+ num + " deleted");
    else
	send_err("failed to delete message");
}

static void capa()
{
    send_ok("Capability list follows");
    foreach(indices(mCmd[_state]), string idx) {
      send_message(idx + "\r\n");
    }
    send_message(".\r\n");
}

/**
 * Returns the unique id for a message, (object-id)
 *  
 * @param int num - the message to identify
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void uidl(int num)
{
    send_ok(num + " " + oMailBox->get_message_id(num-1));
    send_message(".\r\n");
}

static void top(int num, int l)
{
    send_ok("");
    string message = oMailBox->retrieve_message(num-1);
    string header, body;
    int i = search(message, "\r\n");
    header = message[..i-1];
    send_message(header);
    body = message[i+2..];
    array(string) lines = body / "\n";
    if ( l >= sizeof(lines) )
	send_message(body + "\r\n.\r\n");
    else {
	send_message((lines[..l-1]*"\n")+ "\r\n.\r\n");
    }
}


static void quit()
{
    _state = STATE_AUTHORIZATION;
    oMailBox->cleanup(); // remove all messages scheduled for deletion
    int messages_left = (objectp(oMailBox) ? oMailBox->get_num_messages() : 0);
    send_ok("steam POP3 server signing off (" + messages_left + 
	    " messages left)");
	    
    oUser->disconnect();
    close_connection();
}

static void process_command(string cmd)
{
    array(string) commands;

    commands = cmd / " ";

    for ( int i = 0; i < sizeof(commands); i++ ) {
	mixed token = commands[i];
	int l = strlen(token);

	if ( sscanf(token, "%d", token) && strlen((string)token)==l)
	    commands[i] = token;
    }
    function f = mCmd[_state][commands[0]];
    if ( functionp(f) ) {
	if ( sizeof(commands) == 1 )
	    f();
	else
	    f(@commands[1..]);
	return;
    }
    send_err("command not recognized");
}

string get_socket_name() { return "pop3"; }
