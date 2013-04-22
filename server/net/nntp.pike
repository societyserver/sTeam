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
 * $Id: nntp.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: nntp.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $";

inherit "/net/coal/login";
inherit "/net/base/line";

#include <macros.h>
#include <config.h>
#include <database.h>

#define NNTP_DEBUG

#ifdef NNTP_DEBUG
#define NNTP_LOG(s, args...) werror(s +"\n", args);
#else
#define NNTP_LOG(s, args...)
#endif

#define CHECK_GROUP if ( !objectp(oCurrentGroup) ) {\
  send_response(412);\
  return;\
}

#define CHECK_ARTICLE if ( !objectp(oCurrentArticle) ) {\
    send_response(420);\
    return;\
}
 
#define MODE_READ 1
#define MODE_POST 2

static string sPost       = "";
static int    iMode = MODE_READ;

static mapping mResponses = ([
    100: "help text follows",
    199: "debug output",
    200: "sTeam news server ready - posting allowed",
    201: "sTeam news server ready - no posting allowed",
    202: "slave status noted",
    205: "closed connection - goodbye!",
    211: "n f l s group selected",
    215: "list of newsgroups follows",
    220: "n <a> article retrieved - head and body follow", 
    221: "n <a> article retrieved - head follows",
    222: "n <a> article retrieved - body follows",
    223: "n <a> article retrieved - request text separately",
    224: "Overview information follows",
    230: "list of new articles by message id follows",
    231: "list of new newsgroups follows",
    235: "article transferred ok",
    240: "article posted ok",
    281: "Authentication accepted",
    335: "send article to be transferred. End with <CR-LF>.<CR-LF>",
    340: "send article to be posted. End with <CR-LF>.<CR-LF>",
    381: "More authentication information required",
    400: "service discontinued",
    411: "no such news group",
    412: "no newsgroup has been selected",
    420: "no current article has been selected",
    421: "no next article in this group",
    423: "no such article number in this group",
    430: "no such article found",
    440: "posting not allowed",
    441: "posting failed",
    480: "Authentication required",
    482: "Authentication rejected",
    500: "Command not recognized",
    501: "command syntax error",
    502: "No permission",
    503: "program fault - command not performed",
    ]);

static object oGroups = 0;
static object oCurrentGroup = 0;    
static object oCurrentArticle = 0;
	
/**
 * Send a list of groups.
 *  
 * @param void|string type - send subscribed groups or overview.fmt
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void list_groups(void|string type)
{
    if ( zero_type(type) || lower_case(type) == "subscriptions" ) {
	send_response(215);
	array(object) groups = oGroups->list_groups();
	
	
	if ( arrayp(groups) ) {
	    foreach( groups, object grp ) {
		send_result(grp->get_name(),
			    (string)grp->get_last_message(),
			    (string)grp->get_first_message(),
			    (grp->can_post()?"y":"n"));
	    }
	}
	send_message(".\r\n");
	return;
    }
    if ( lower_case(type) == "overview.fmt" )
    {
	send_result("215", "Order of Fields in Overview database.");
	send_message("Subject: \r\n");
	send_message("From: \r\n");
	send_message("Date: \r\n");
	send_message("Message-ID: \r\n");
	send_message("References: \r\n");
	send_message("Bytes: \r\n");
	send_message("Lines: \r\n");
	send_message("Xref:full \r\n");
	send_message(".\r\n");
	return;
    }
    send_response(503);
}

/**
 * Send a list of new groups.
 *  
 * @param string date - last newsgroup check date.
 * @param string t - time of last check.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */

static void new_groups(string date, string t)
{
    send_result("231", "New newsgroups follow");
    array(object) groups = oGroups->list_groups();

    if ( arrayp(groups) ) {
	foreach(groups, object grp) {
	    // FIXME! Check if newer
	    send_result(grp->get_name());
	}
    }
    send_result(".");
}

/**
 * Get a list of new groups newer than date, time t.
 *  
 * @param int date - date of last check
 * @param int t - time of last check.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void list_new_groups(int date, int t)
{
    send_response(231);
    array(object) groups = oGroups->list_groups();

    foreach( groups, object grp ) {
	if ( grp->newer_than(date, t) )
	    send_result(grp->get_name(),
			(string)grp->get_last_message(),
			(string)grp->get_first_message(),
			(grp->can_post()?"y":"n"));
    }
    send_message(".\r\n");
}

/**
 * Get a list of new news entries newer than date, time t.
 *  
 * @param int date - date of last check
 * @param int t - time of last check.
 * @author <a href="mailto:kamikaze@iaeste.at">Axel Gross</a>) 
 */
static void new_news(string newsgroups, string|int date, string|int t){
  //FIXME this is work in progress...
  // this is not finished - so stop processing
  send_response(500); 

  // Todo '*' wildcard
  // Todo ',' separated groupsnames
  // Check 512 character command length limit
  
  int idate;
  int itime;
  if( stringp(date) ) {
    // Format is either YYMMDD with YY rounded to the nearest century (RFC 977)
    //        or YYYYMMDD
    if( sizeof(date)==8 ){
      sscanf(date, "%4d%2d%2d", int year,int month,int day);
      Calendar.Day(year,month,day);
    }else {
      NNTP_LOG("Got unsupported/bad date format '" + date + "'");
      send_response(500); 
    }
    idate=(int)date;
  }
  if( stringp(t) ) {
    itime=(int)t;
  }
  // FIXME TODO
  //  send
}

/**
 * Select an article from the current group.
 *  
 * @param string num - number of the article.
 * @return object of selected article.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static object select_article(string num)
{
    int art_num;

    if ( sscanf(num, "<%d@%*s", art_num) == 0 ) {
	art_num = (int)num;
	// RFC says article pointer is set by article (numeric)
	oCurrentArticle = oCurrentGroup->get_article(art_num);
	return oCurrentArticle;
    }
    return find_object(art_num);
}


/**
 * Select the article with id 'id' and send status of it.
 *  
 * @param string id - id of article
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void stat(string id)
{
    if ( !objectp(oCurrentGroup) ) {
	send_response(412);
	return;
    }
    object article = select_article(id);
    send_result("223", (string)oCurrentGroup->get_article_num(article), 
		oCurrentGroup->message_id(article), 
		"article retrieved - request text separately");
}

/**
 * Set the next article as current.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void next()
{
    CHECK_GROUP;
    CHECK_ARTICLE;
    
    object article = oCurrentGroup->get_next_article(oCurrentArticle);
    oCurrentArticle = article;
    send_result("223", (string)oCurrentGroup->get_article_num(article), 
		oCurrentGroup->message_id(article), 
		"article retrieved - request text separately");
}


/**
 * XOVER command sends article overview.
 *  
 * @param string|void range
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void xover(string|void range)
{
    if ( !objectp(oCurrentGroup) ) {
	send_response(412);
	return;
    }
    NNTP_LOG("xover range=%O\n", range);

    int from, to;
    if ( stringp(range) ) {
	if ( sscanf(range, "%d-%d", from, to) != 2 ) {
	    if ( sscanf(range, "%d-", from) == 1 ) {
		to = 0xffffffff;
	    }
	    else if ( sscanf(range, "%d", from ) == 1 ) {
		to = from;
	    }
	    else
		send_response(420);
	    
	}
    }
    else {
	if ( oCurrentArticle ) 
	    from = oCurrentGroup->get_article_num(oCurrentArticle);
	else
	    from = oCurrentGroup->get_first_message();
	to = from; // no argument given - use current message
    }
    array(object) articles = oCurrentGroup->get_articles();
    array(object) inRange = ({ });
    object art;

    foreach( articles, art ) {
	int oid = oCurrentGroup->get_article_num(art);
	if ( oid >= from && oid <= to )
	    inRange += ({ art });
    }
    if ( sizeof(inRange) > 0 ) {
	send_response(224);
	foreach(inRange, art) {
	    send_message(oCurrentGroup->header(art) + "\r\n");
	}
    }
    else {
	send_response(420);
    }
	    
    send_message(".\r\n");
}

/**
 * Select the group 'grp' as current group.
 *  
 * @param string grp - name of the group to select.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void group(string grp) 
{
    object group = oGroups->get_group(grp);
    if ( !objectp(group) ) {
	send_response(411);
	return;
    }
    else if ( !group->read_access(oUser) ) {
	if ( oUser == _GUEST )
	    send_response(480);
	else
	    send_response(411); // is this correct ? no such newsgroup ???
	return;
    }

    oCurrentGroup  = group;
    send_result((string)211, (string)group->get_num_messages(), 
		(string)group->get_first_message(),
		(string)group->get_last_message(),
		group->get_name(),
                "Newsgroup selected");
}

/**
 * Set the mode to new mode 'm'. Just sends back 200 response.
 *  
 * @param string m - the new mode.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void mode(string m)
{
    send_result("200","Hello, you can post");
}

/**
 * Authorize with user or password. 
 *  
 * @param string subcmd - authorization method, only 'user' and 'pass' allowed.
 * @param string auth - auth parameter.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void authorize(string subcmd, string auth)
{
    LOG("authorize("+subcmd+","+auth+")");
    switch ( lower_case(subcmd) ) {
    case "user":
	oUser = _Persistence->lookup_user(auth);
	LOG("User="+sprintf("%O", oUser));
	if ( objectp(oUser) )
	    send_response(381);
	else
	    send_response(482);
	break;
    case "pass":
	if ( !objectp(oUser) )
	    send_response(381);
	if ( oUser->check_user_password(auth) ) {
	    login_user(oUser);
	    send_response(281);
	}
	else {
	    oUser = 0;
	    send_response(482);
	}
	break;
    default:
	send_response(500);
    }
}


/**
 * Send back the body of article 'id'.
 *  
 * @param string|void id - send body of id or current article.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void body(string|void id) {
    object article;
    CHECK_GROUP;

    if ( stringp(id) ) {
	article = select_article(id);
    }
    else {
	CHECK_ARTICLE;
	article = oCurrentArticle;
    }
    send_result("223", (string)oCurrentGroup->get_article_num(article), 
		oCurrentGroup->message_id(article), 
		"article retrieved - body follows");
    send_message(oCurrentGroup->get_body(article)+"\r\n");
    send_message(".\r\n");
}

/**
 * This command returns a one-line response code of 111 followed by the
 * GMT date and time on the server in the form YYYYMMDDhhmmss.
 */
static void date() {
  Calendar.Calendar cal = Calendar.now()-> set_timezone(Calendar.Timezone["GMT"]);
  string YYYYMMDDhhmmss = cal->format_ymd_short() + cal->format_tod_short();
  send_result("111", YYYYMMDDhhmmss);
}

/**
 * Send back the head of article 'num' or the currently selected one.
 *  
 * @param string|void num - number of article.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void head(string|void num)
{
    object article;
    CHECK_GROUP;

    if ( stringp(num) )
	article = select_article(num);
    else {
	CHECK_ARTICLE;
	article = oCurrentArticle;
    }

    string header = oCurrentGroup->get_header(article);

    if ( !stringp(header) )
	send_response(430);
    else {
	send_result("221", (string)oCurrentGroup->get_article_num(article), 
		    oCurrentGroup->message_id(article), 
		    "article retrieved - head follows");

	send_message(header);
	send_message(".\r\n");
    }
}

/**
 * Sets mode to posting.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void post()
{
    if ( oUser == _GUEST ) {
	send_response(480);
	return;
    }
	
    iMode = MODE_POST;
    sPost = "";
    send_response(340);
}



/**
 * Retrieve header and body of article 'num'.
 *  
 * @param string num - the article to retrieve.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void article(string num)
{
    object article;

    CHECK_GROUP;
    article = select_article(num);

    send_result("220", (string)oCurrentGroup->get_article_num(article), 
		oCurrentGroup->message_id(article), 
		"article retrieved - head and body follows"); 
    send_message(oCurrentGroup->get_header(article)+"\r\n");
    send_message(oCurrentGroup->get_body(article)+"\r\n.\r\n");
}

/**
 * Process the command 'cmd'.
 *  
 * @param string cmd - the command to process.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void process_command(string cmd)
{
    array(string) commands;


    if ( iMode == MODE_POST ) {
	if ( cmd == "." ) {
	    iMode = MODE_READ;
	    int result = oGroups->post_article(sPost);
	    if ( result == 1 )
		send_response(240);
	    else if ( result == -1 )
		send_response(440);
	    else
		send_response(441);
	}
	else
	    sPost += cmd + "\r\n";
	return;
    }

    mixed err = catch {
	commands = cmd / " ";
	if ( !arrayp(commands) || sizeof(commands) == 0)
	    commands = ({ cmd });
	
	NNTP_LOG("commands:"+sprintf("%O\n", commands));
	switch ( lower_case(commands[0]) ) {
	case "quit":
	    if (objectp(oUser) )
		oUser->disconnect();
	    close_connection();
	    break;
	case "date":
	    date();
	    break;
	case "list":
	    if ( sizeof(commands) == 2 )
		list_groups(commands[1]);
	    else
		list_groups();
	    break;
	case "newgroups":
	    // TODO "GMT"  could be third command - we ignore timezones at the moment
	    new_groups(commands[1], commands[2]);
	    break;
	case "newsgroups":
	  // actually this command doesnt exist in RFC 977
	    list_new_groups((int)commands[1], (int)commands[2]);
	    break;
        case "newnews":
	  // TODO "GMT"  could be fourth command - we ignore timezones at the moment
	  // TODO distributions  could be fourth or fith command - ignored
	    new_news(commands[1], commands[2], commands[3]);
	    break;
	case "xover":
	    //RFC 2980
	    if ( sizeof(commands) == 2 )
		xover(commands[1]);
	    else
		xover();
	    break;
	case "stat":
	    stat(commands[1]);
	    break;
	case "mode":
	    mode(commands[1]);
	    break;
	case "group":
	    group(commands[1]);
	    break;
	case "head":
	    if ( sizeof(commands) == 1 )
		head();
	    else
		head(commands[1]);
	    break;
	case "body":
	    if ( sizeof(commands) == 1 )
		body();
	    else
		body(commands[1]);
	    break;
	case "next":
	    next();
	    break;
	case "article":
	    article(commands[1]);
	    break;
	case "post":
	    post();
	    break;
	case "authinfo":
	    if ( sizeof(commands) != 3 )
		send_response(501);
	    else
		authorize(@commands[1..]);
	    break;
	default:
	    send_response(500);
	    break;
	}
    };
    if ( err != 0  ) {
	if ( arrayp(err) && sizeof(err) == 3 && err[2] & E_ACCESS )
	    send_response(502);
	else
	    send_response(503);
	FATAL("Error!-------------\n"+err[0]+"\n"+sprintf("%O", err[1]));
    }
}

/**
 * Send back a response with code 'code' and an optional id.
 *  
 * @param int code - response code.
 * @param int|void id - message id.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void send_response(int code, int|void id)
{
    NNTP_LOG("RESPONSE: " + code + "("+mResponses[code]+")");
    if ( id > 0 ) {
	send_message(code + " " + id + " <"+id+"@"+_Server->get_server_name()
                     +" " +  mResponses[code]+"\r\n");
    }
    else
	send_message(code + " " + mResponses[code] + "\r\n");
}

void send_result(mixed ... result)
{
  ::send_result(@result);
  NNTP_LOG("Result="+(result * " ")+"\r\n");
}

/**
 * Constructor of the nntp socket.
 *  
 * @param object f - file descriptor to assign.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void create(object f)
{
    ::create(f);
    LOG("Setting Groups object...\n");
    oGroups = _Server->get_module("nntp");
    oUser = _GUEST;
    
    send_response(200);
}

string get_socket_name() { return "nntp"; }
