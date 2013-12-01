/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2002-2004 Christian Schmidt
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
 * $Id: smtp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: smtp.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

/*
 * implements a smtp-server (see rfc2821 for details)
 */

inherit "/net/coal/login";
inherit "/net/base/line";

#include <macros.h>
#include <config.h>
#include <database.h>
#include <attributes.h>
#include <classes.h>
#include <exception.h>
#include <access.h>

#include <mail.h>

//#define SMTP_DEBUG

#ifdef SMTP_DEBUG
#define DEBUG_SMTP(s, args...) werror("net/smtp: "+s+"\n", args)
#else
#define DEBUG_SMTP
#endif


static int _state = STATE_INITIAL;
static int _esmtp = 0;
static string sServer = _Server->query_config("machine");
static string sDomain = _Server->query_config("domain");
static string sIP = _Server->query_config("ip");
static string sFQDN = sServer+"."+sDomain;
static object oRcpt;
static object _Forward = _Server->get_module("forward");

static string sMessage="";
static string sSender="";
static array(object) aoRecipients=({});

//sends a reply to the client, prefixed by a response code
//if msg is more than one line, each is preceded by this code
static void send_reply(int code, string msg)
{
    array lines = msg / "\n";
    for(int i=0;i<sizeof(lines); i++)   //multiline reply
    {
        if(i==sizeof(lines)-1) send_message(""+code+" "+lines[i]+"\r\n");
        else send_message(""+code+"-"+lines[i]+"\r\n");
    }
}

//called upon connection, greets the client
void create(object f)
{
    ::create(f);

    string sTime=ctime(time());
    sTime=sTime-"\n";   //remove trailing LF
    oUser = MODULE_USERS->lookup("postman");
    send_reply(220,sFQDN+" sTeaMail SMTP-Server ver1.0 ready, "+sTime);
}

string query_address_name()
{
  string addr = query_address();
  sscanf(addr,"%s %*s",addr);
  object dns = Protocols.DNS.client();
  array res = dns->gethostbyaddr(addr);
  if (arrayp(res) && sizeof(res) > 1 )
    return res[0];
  return addr;
}

static void ehlo(string client)
{
    if(_state!=STATE_INITIAL)
    {
        //reset everything important
        sMessage="";
        aoRecipients=({});
    }
    _esmtp=1;   //client supports ESMTP
    _state=STATE_IDENTIFIED;    //client identified correctly

    string addr=query_address();
    sscanf(addr,"%s %*s",addr); //addr now contains ip of connecting host

    //verify if given name is correct    
    object dns = Protocols.DNS.client();
    array res = dns->gethostbyaddr(addr);
    if (res[0]==client)    
      send_reply(250,sServer+" Hello "+client+" ["+addr+"]");
    else 
      send_reply(250,sServer+" Hello "+client+" ["+addr+"] (Expected \"EHLO "+res[0]+"\")");
}

static void helo(string client)
{
    if(_state!=STATE_INITIAL)
    {
        //reset everything important
        sMessage="";
        aoRecipients=({});
    }
    _esmtp=0;   //client does not support ESMTP
    _state=STATE_IDENTIFIED;    //client identified correctly

    string addr=query_address();
    sscanf(addr,"%s %*s",addr);
    
    //verify if given name is correct    
    object dns = Protocols.DNS.client();
    array res = dns->gethostbyaddr(addr);
    if (res[0]==client)    
        send_reply(250,sServer+" Hello "+client+" ["+addr+"]");
    else send_reply(250,sServer+" Hello "+client+" ["+addr+"] (Expected \"HELO "+res[0]+"\")");    
}

static void help()
{ 
    send_reply(250,"This is the opensTeam-Mailserver\n"+
	       "Contact: http://www.open-steam.org");
}

static string mail(string sender)
{
  string localpart, domain;
  //sender must look like '<sender@domain>'
  oUser = USER("postman");
  if ( sender == "" || sender == "<>" || 
      sscanf(sender,"%*s<%s@%s>", localpart, domain) >= 2 ||
      sscanf(sender, "%s@%s", localpart, domain) == 2 )
  {
    object user = _Forward->lookup_sender(sender);
    if (_Server->get_config("mail_mailsystem")=="closed") {
      if (!objectp(user)) {
	MESSAGE("MAIL: Rejecting from " + sender);
        return "Mailing is restricted: members only - " + sender + " not a "+
          "sTeam user!";
      }
      else {
        oUser = user;
      }
    }
    sSender=sender;
    _state=STATE_TRANSACTION;   //waiting for RCPT command(s) now
    send_reply(250,"Sender accepted"); //NOTE: sender can't be verified
    return 0;
  }
  return "syntax error, wrong sender format!";
}

static array(string) getIPs(string addr)
{
  object dns = Protocols.DNS.client();

  array result = dns->gethostbyname(lower_case(addr));
  if ( !arrayp(result) || sizeof(result) < 2 )
    return ({ });
  
  return result[1];
}

int check_rcpt(string user, string domain)
{
  DEBUG_SMTP("Mail to domain=%s - LOCALDOMAIN=%s", domain, sFQDN);
  
  int success = 0;
  if( lower_case(domain) == lower_case(sFQDN) )
    success = 1;
  else {   
    //test if given domain-name matches local ip-adress (->accept it)
    //workaround for multiple domains on same machine
    //like "uni-paderborn.de"<->"upb.de"
    array domains = _Server->query_config("domains");   
    if ( !arrayp(domains) ) 
      domains = ({ });

    domains += ({ _Server->query_config("domain") });
    if ( search(domains, domain) >= 0 )
      return 1;
    
    array(string) myIPs = getIPs(_Server->get_server_name());
    array(string) remoteIPs = getIPs(domain);
    
    DEBUG_SMTP("Checking IPS: local=%O, remote=%O", myIPs, remoteIPs); 
    if ( sizeof( (myIPs & remoteIPs) ) > 0 )
      return 1;
  }
  return success;
}

static void rcpt(string recipient)
{
  string address;
  if ( sscanf(recipient, "%*s<%s>", address) == 0 )
    address = recipient;
  
  
  if(lower_case(address)=="postmaster")
    address="postmaster@"+sFQDN; //rcpt to:<postmaster> is always local!
  
  string user, domain;
  if ( sscanf(address, "%s@%s", user, domain) != 2 ) {
      FATAL("501 upon smtp: rctp(%O)", recipient);
    send_reply(501, "syntax error, recipient adress has illegal format");
    return;
  }

  int success = check_rcpt(user, domain);

  if ( success ) //only accept for local domain
  {
      string user = lower_case(user);
      if(user=="postmaster") user="root";//change to other user,if needed
      
      int valid = _Forward->is_valid(user); //check if rcpt is ok
      DEBUG_SMTP("is_valid() returned "+valid+" for target "+user);
      if(valid > 0)
      {
	aoRecipients+=({user}); //"doubled" recipients will be removed later!
	send_reply(250,"Recipient ok");
	_state=STATE_RECIPIENT; //waiting for DATA or RCPT
      }
      else if (valid == -1)
	send_reply(550,"write access failed, set permissions on target first");
      else if ( valid == 0 ) 
	send_reply(550,"unknown recipient "+user);
      else
	send_reply(450,"unknown error");
  }
  else
    send_reply(550,"we do not relay for you!");
}


static void data()
{
    //"minimize" list of recipients
    aoRecipients=Array.uniq(aoRecipients);
    
    send_reply(354,"send message now, end with single line containing '.'");
    _state=STATE_DATA;
    register_data_func(process_data);

    //add "received"-Header, see rfc for details
    string addr=query_address_name();;
    sMessage="Received: from "+addr+" by "+sFQDN+" "+ctime(time())+
      "X-Envelope_from: "+sSender +"\n";
}

static void process_data(string data)
{
    int i;
    if ( (i=search(data, "\n.\r\n")) > 0 || (i=search(data, "\n.\n")) > 0 ) {
      data = data[..i];
    } 
    else if ( (i=search(sMessage + data, "\n.\r\n")) > 0 ) {
      sMessage = sMessage[..i];
      data = "";
    }

    if ( i != 0 )
      sMessage += data;

    if ( i != -1 )
    {
        sMessage+="\r\n";

        send_reply(250,"Message accepted, size is "+sizeof(sMessage));
        DEBUG_SMTP("received mail, recipients are:%O",aoRecipients);

	int res;

	// make it a task (do not block!)
	object tmod = get_module("tasks");
	if ( objectp(tmod) ) {
	  Task.Task rcvTask = Task.Task(_Forward->send_message_raw);
	  rcvTask->params = ({ aoRecipients, sMessage, sSender });
	  tmod->run_task(rcvTask);
	  res = 1;
	}
	else
	  res=_Forward->send_message_raw(aoRecipients,sMessage,sSender);
        DEBUG_SMTP("result of _Forward->send_message_raw(...) is "+res);
	_state=STATE_IDENTIFIED;
	unregister_data_func();
	sMessage="";
	aoRecipients=({});
	DEBUG_SMTP("processing data finished !");
     }
}

static void rset()
{
    if(_state>STATE_IDENTIFIED) _state=STATE_IDENTIFIED;
    sMessage="";
    sSender="";
    aoRecipients=({});
    send_reply(250,"RSET completed");
}

static void noop()
{
    send_reply(250,"NOOP completed");
}

static void quit()
{
    send_reply(221,""+sServer+" closing connection");
    _state=STATE_QUIT;
    close_connection();
}

static void vrfy(string user)
{
    send_reply(252,"Cannot VRFY user, but will accept message and attempt delivery");
    //verification code may be added here
}

//this function is called for each line the client sends
static void process_command(string cmd)
{
    if(_state==STATE_DATA)
    {
        process_data(cmd);
        return;
    }

    string command,params;
    if(sscanf(cmd,"%s %s",command,params)!=2)
    {
        command=cmd;
        params="";
    }

    switch(upper_case(command))
    {
        case "EHLO":
            if(search(params," ")==-1) ehlo(params);
            else send_reply(501,"wrong number of arguments");
            break;
        case "HELO":
            if(search(params," ")==-1) helo(params);
            else send_reply(501,"wrong number of arguments");
            break;
        case "HELP":
            help();
            break;
        case "MAIL":
            if(_state==STATE_IDENTIFIED)
            {
                array(string) parts=params/":";
                if(upper_case(parts[0])=="FROM" && sizeof(parts)==2) {
                  string res = mail( String.trim_whites(parts[1]));
                  if ( stringp(res) ) {
		    send_reply(501, res);
		  }
		}
		else 
		  send_reply(501,"syntax error");
            }
            else send_reply(503,"bad sequence of commands - EHLO expected");
            break;
        case "RCPT":
            if(_state==STATE_TRANSACTION||_state==STATE_RECIPIENT)
            {
                array(string) parts=params/":";
                if(upper_case(parts[0])=="TO" && sizeof(parts)==2)
                    rcpt( String.trim_whites(parts[1]) );
                else send_reply(501,"syntax error");
            }
            else send_reply(503,"bad sequence of commands");
            break;
        case "DATA":
            if(_state==STATE_RECIPIENT)
            {
                if (params=="") data();
                else send_reply(501,"wrong number of arguments");
            }
            else send_reply(501,"bad sequence of commands");
            break;
        case "RSET":
            if (params=="") rset();
            else send_reply(501,"wrong number of arguments");
            break;
        case "NOOP":
            noop();
            break;
        case "QUIT":
            if (params=="") quit();
            else send_reply(501,"wrong number of arguments");
            break;
        case "VRFY":
            vrfy(params);
            break;
        default:
            send_reply(500,"command not recognized");
            break;
    }
}

void close_connection()
{
    if(_state!=STATE_QUIT) //we got called by idle-timeout
        send_reply(221,""+sServer+" closing connection, idle for too long");
    ::close_connection();
}




