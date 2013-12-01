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
 * 
 * $Id: smtp.pike,v 1.2 2009/05/06 19:23:10 astra Exp $
 */

constant cvs_version="$Id: smtp.pike,v 1.2 2009/05/06 19:23:10 astra Exp $";
inherit "/kernel/secure_mapping";
inherit "/base/serialize";

#include <macros.h>
#include <access.h>
#include <config.h>
#include <database.h>
#include <attributes.h>
#include <classes.h>

//#define SMTP_DEBUG

#ifdef SMTP_DEBUG
#define SMTP_LOG(s, args...) werror("smtp: "+s+"\n", args)
#else
#define SMTP_LOG(s, args...)
#endif

#if constant(Protocols.SMTP.client) 
#define SMTPCLIENT Protocols.SMTP.client
#else
#define SMTPCLIENT Protocols.SMTP.Client
#endif


static string server;
static int port;

//! This is the SMTP module for sTeam. It sends mail to some e-mail adress
//! by using a local mailserver or doing MX lookup and sending directly
//! to the targets mail server.

static Thread.Queue MsgQueue  = Thread.Queue();
static Thread.Mutex saveMutex = Thread.Mutex();

static object oSMTP; // cache smtp object (connection)
static object oDNS; // cache DNS Client

private static function    myfDb;
private static string mysDbTable;
static int                 msgId;

private static mapping test_objects = ([ ]);

static void init_module()
{
  mixed err = catch( oDNS = Protocols.DNS.client() );
  if ( err ) {
    werror( "smtp: warning, could not create DNS client.\n" );
  }
  add_data_storage(STORE_SMTP, retrieve_mails, restore_mails);
}

mapping retrieve_mails()
{
  return ([ ]);
}

void restore_mails(mapping data) 
{
}


static void load_module() 
{
  ::load_module();
  [myfDb , mysDbTable] = _Database->connect_db_mapping();
  mixed err = catch {
    if( search(myfDb()->list_tables(), "i_rawmails" ) == -1 ) {
      myfDb()->big_query("create table i_rawmails (mailid int, rawdata longtext, UNIQUE(mailid))");
    }
  };
  // load all mails, which have not been send previously
  msgId = 1;
  err = catch(load_mails());
  if ( err ) MESSAGE("Error loading mails:\n%O\n%O", err[0], err[1]);
}

static void load_mails()
{
  mapping msg;
  
   // load mails where ?
   array mails = index();

   foreach(mails, string id) {
     int i = (int)id;
     msgId = max(i, msgId);
     msg = get_value(id);

     // see if something is in raw data table
     Sql.sql_result res = myfDb()->big_query(sprintf("select rawdata from i_rawmails where mailid='%s'", id));
     mixed row;
     while ( row = res->fetch_row() ) {
#if constant(steamtools.unserialize)
       msg->raw = steamtools.unserialize(row[0], find_object);
#else
       msg->raw = unserialize(row[0]);
#endif
     }
     if ( mappingp(msg) ) {
       msg->msgid = i;
       deliver_message(msg);
     }
   }
}

static void save_mail(mapping msg) 
{
  // save mails where ?
   mapping   m;

   object lock = saveMutex->lock();
   mixed err = catch {
     msgId++;
     msg->msgid = msgId;
     m = copy_value(msg);
     m_delete(m, "raw");

     function serializer;
 #if constant(steamtools.serialize) 
     serializer =  steamtools.serialize;
 #else
     serializer = serialize;
#endif
     set_value((string)msgId, m);
     if ( stringp(msg->raw) && strlen(msg->raw)>0 ) {
       myfDb()->big_query(sprintf("insert into i_rawmails values ('%d', '%s')",
                                  msgId, myfDb()->quote(serializer(msg->raw))));
     }
   };
   if ( err != 0 ) {
     FATAL("Failed to save mail: %O\n%O", err[0], err[1]);
   }
   destruct(lock);
}

static void delete_mail(mapping msg)
{
  delete(msg->msgid);
  myfDb()->big_query(sprintf("delete from i_rawmails where mailid='%d'",
                             msg->msgid));
}

void runtime_install()
{
     SMTP_LOG("Init module SMTP !");

     // an initial connection needs to be created to load some libraries
     // otherwise creating connections will fail after the sandbox
     // is in place (chroot("server/"))
     server = _Server->query_config(CFG_MAILSERVER);
     port = _Server->query_config(CFG_MAILPORT);
     if (objectp(oDNS) && stringp(server) && sizeof(server) > 0 ) {
       array result = oDNS->gethostbyname(lower_case(server));
       if (arrayp(result) && sizeof(result)>1 && arrayp(result[1]) && sizeof(result[1])>0) {
	 server = result[1][0];
         MESSAGE("Using SMTP Server Adress: %O", server);
       }
     }
     if ( !intp(port) || port <= 0 ) 
       port = 25;
     
     mixed err;

     if ( stringp(server) && sizeof(server) > 0 && server != "disabled" )
         err = catch( oSMTP = SMTPCLIENT( server, port ) );
     if ( err ) 
         FATAL("Failed to connect to " + server+" :\n"+sprintf("%O\n", err));

     start_thread(smtp_thread);
}

void deliver_message(mapping msg)
{
  object serviceMod = get_module("ServiceManager");
  if ( objectp(serviceMod) && serviceMod->is_service("smtp") ) {
    serviceMod->call_service("smtp", ([ "action": "send", "msg": msg, ]));
  }
  else {
    MsgQueue->write(msg);
  }
}


void 
send_mail(array|string email, string subject, string body, void|string from, void|string fromobj, void|string mimetype, void|string fromname, void|string date, void|string message_id, void|string in_reply_to, void|string reply_to, void|string mail_followup_to)
{
  mapping msg = ([ ]);
  msg->email   = email;
  msg->subject = subject;
  if ( stringp(subject) )
    msg->subject = Messaging.get_quoted_string( subject );
  msg->mimetype = (stringp(mimetype) ? mimetype : "text/plain");
  if ( lower_case(msg->mimetype) == "text/html" )
    msg->body = Messaging.fix_html( body );
  else
    msg->body = body;
  msg->date    = date || timelib.smtp_time(time());
  msg->message_id = message_id||("<"+(string)time()+(fromobj||("@"+_Server->get_server_name()))+">");
  msg->rawmime = 0;
  if(reply_to)
    msg->reply_to=reply_to;
  if(mail_followup_to)
    msg->mail_followup_to=mail_followup_to;
  if(in_reply_to)
    msg->in_reply_to=in_reply_to;
  
  get_module("log")->log_debug( "smtp", "send_mail: to=%O", email );
  
  if ( stringp(from) && sizeof(from) > 0 )
    msg->from    = from;
  else
    msg->from = this_user()->get_identifier() +
      "@" + _Server->get_server_name();
  if ( stringp(fromobj) )
    msg->fromobj = fromobj;
  if ( stringp(fromname) )
    msg->fromname = fromname;
  
  save_mail(msg);
  deliver_message(msg);

  object user = geteuid() || this_user();
  if ( objectp(user) && user->is_storing_sent_mail() &&
       objectp(user->get_sent_mail_folder()) ) {
    object mail_copy = get_factory(CLASS_DOCUMENT)->execute(
                        ([ "name":msg->subject, "mimetype": msg->mimetype ]) );
    mail_copy->set_attribute( OBJ_DESC, msg->subject );
    array to_arr;
    if ( arrayp(email) ) to_arr = email;
    else to_arr = ({ email });
    mail_copy->set_attribute( "mailto", to_arr );
    mail_copy->set_content( msg->body );
    mail_copy->sanction_object( user, SANCTION_ALL );
    mail_copy->set_acquire( 0 );
    object old_euid = geteuid();
    seteuid( user );
    get_module( "table:read-documents" )->download_document( 0, mail_copy, UNDEFINED );  // mark as read
    foreach ( mail_copy->get_annotations(), object ann )
      get_module( "table:read-documents" )->download_document( 0, ann, UNDEFINED );  // mark as read
    seteuid( old_euid );
    user->get_sent_mail_folder()->add_annotation( mail_copy );
  }
}

void send_mail_raw(string|array email, string data, string from)
{
  
  mapping msg = ([ ]);
  msg->email   = email;
  msg->rawmime = data;
  if ( stringp(from) && sizeof(from) > 0 )
    msg->from = from;
  else
    msg->from = this_user()->get_identifier()
      + "@" + _Server->get_server_name();
  
  save_mail(msg);
  deliver_message(msg);
}

void send_mail_mime(string email, object message)
{
     mapping mimes = message->query_attribute(MAIL_MIMEHEADERS);
     string from;
     sscanf(mimes->from, "%*s<%s>", from);
     if ( !stringp(from) || sizeof(from) < 1 )
       from = this_user()->get_identifier() + "@" + _Server->get_server_name();
     send_mail(email, message->get_identifier(), message->get_content(), from);
}

static mixed cb_tag(Parser.HTML p, string tag)
{
     if ( search(tag, "<br") >= 0 || search (tag, "<BR") >= 0 )
         return ({ "\n" });
     return ({ "" });
}

void send_message(mapping msg)
{
   object   smtp;

   if ( !intp(port) || port <= 0 ) port = 25;

   object log = get_module("log");

   log->log_debug( "smtp", "send_message: server: %O:%O", server, port );

   if ( !stringp(msg->from) ) {
     msg->from = "admin@"+_Server->get_server_name();
     log->log_debug( "smtp", "send_message: invalid 'from', using %s",
                     msg->from );
   }
   log->log_debug( "smtp", "send_message: mail from %O to %O (server: %O:%O)\n"
       + "  Subject: %O", msg->from, msg->email, server, port, msg->subject );

   if ( !arrayp(msg->email) )
     msg->email = ({ msg->email });

   foreach ( msg->email, string email ) {
     string tmp_server = server;
     int tmp_port = port;
     mixed smtp_error;
     if ( stringp(server) && sizeof(server) > 0 ) {
       smtp_error = catch {
         smtp = SMTPCLIENT( server, port );
       };
     }
     else {
       // if no server is configured use the e-mail of the receiver
       string host;
       sscanf( email, "%*s@%s", host );
       if ( !stringp(host) )
         steam_error("MX Lookup failed, host = 0 in %O", msg->email);

       if ( !objectp(oDNS) )
         steam_error("MX Lookup failed, no DNS");
       tmp_server = oDNS->get_primary_mx(host);
       if ( !stringp(tmp_server) )
	 return;
       array dns_data = oDNS->gethostbyname(tmp_server);
       if ( arrayp(dns_data) && sizeof(dns_data) > 1 &&
            arrayp(dns_data[1]) && sizeof(dns_data[1]) > 0 )
         tmp_server = dns_data[1][0];
       tmp_port = 25;
       log->log_debug( "smtp", "send_message: MX lookup: %O:%O",
                       tmp_server, tmp_port );
       smtp_error = catch {
         smtp = SMTPCLIENT( tmp_server, tmp_port );
       };
     }

     if ( !objectp(smtp) || smtp_error ) {
       string msg = sprintf( "Invalid mail server %O:%O (from %O to %O)\n",
                            tmp_server, tmp_port, msg->from, email );
       if ( smtp_error ) msg += sprintf( "%O", smtp_error );
       log->log_error( "smtp", msg );
       continue;
     }

     if ( stringp(msg->rawmime) ) { 
       // send directly
       smtp_error = catch {
         smtp->send_message(msg->from, ({ email }),  msg->rawmime);
       };
       if ( smtp_error ) {
         log->log_error( "smtp",
             "Failed to send mail directly from %O to %O via %O:%O : %O",
             msg->from, email, tmp_server, tmp_port, smtp_error[0]);
       }
       else {
         log->log_info( "smtp", "Mail sent directly from %O to %O via %O:%O\n",
             msg->from, email, tmp_server, tmp_port );
       }
       continue;
     }

     if ( !stringp(msg->mimetype) )
       msg->mimetype = "text/plain";

     if ( !stringp(msg->body) )
       log->log_error( "smtp", "Invalid message body from %O to %O:\n%O",
                         msg->from, email, msg->body );

     MIME.Message mmsg = MIME.Message(
         msg->body||"",
         ([ "Content-Type": (msg->mimetype||"text/plain") + "; charset=utf-8",
            "Mime-Version": "1.0 (generated by open-sTeam)",
            "Subject": msg->subject||"",
           "Date": msg->date || timelib.smtp_time(time()),
           "From": msg->fromname||msg->from||msg->fromobj||"",
           "To": (msg->fromobj ? msg->fromobj : email)||"",
           "Message-Id": msg->message_id||"",
        ]) );
	 
    if(msg->mail_followup_to)
      mmsg->headers["Mail-Followup-To"]=msg->mail_followup_to;
    if(msg->reply_to)
      mmsg->headers["Reply-To"]=msg->reply_to;
    if(msg->in_reply_to)
      mmsg->headers["In-Reply-To"]=msg->in_reply_to;
  
    smtp_error =  catch {
      smtp->send_message(msg->from, ({ email }), (string)mmsg);
    };
    if ( smtp_error ) {
      log->log_error( "smtp", "Failed to send mail from %O to %O via %O:%O"
          + " : %O\n", msg->from, email, tmp_server, tmp_port, smtp_error[0] );
    }
    else {
      log->log_info( "smtp", "Mail sent from %O to %O via %O:%O\n",
        msg->from, email, tmp_server, tmp_port );
    }
  }
}

static void smtp_thread()
{
    mapping msg;

    while ( 1 ) {
	SMTP_LOG("smtp-thread running...");
	msg = MsgQueue->read();
	mixed err = catch {
	    send_message(msg);
            delete_mail(msg);
            get_module("log")->log_debug( "smtp",
                    "Message from %O to %O sent: '%O'", msg->from, msg->email,
                    (stringp(msg->rawmime)?"mime message": msg->subject) );
	};
	if ( err != 0 ) {
	    FATAL("Error while sending message: " + err[0] + 
		sprintf("\n%O\n", err[1]));
	    if ( server == "disabled" ) {
	      sleep(600); // wait 10 minutes (config could change) and continue
	      continue;
	    }

	    FATAL("MAILSERVER="+_Server->query_config(CFG_MAILSERVER));
	    if ( objectp(oSMTP) ) {
		destruct(oSMTP);
		oSMTP = 0;
	    }
	    sleep(60); // wait one minute before retrying
	}
    }
}

string get_identifier() { return "smtp"; }
string get_table_name() { return "smtp"; }



void test( void|int try_nr )
{
  object services = get_module("ServiceManager");
  if ( !objectp(services) || !services->is_service("smtp") && try_nr < 12 ) {
    Test.add_test_function( test, 10, try_nr+1 );
    return;
  }
  Test.test( "have smtp service",
             objectp(services) && services->is_service("smtp") );
  // check the send mail functionality using different ways
  // due to the behaviour of the message system the mails are sent and
  // later checked to see whether the have been received within the server

  // use configured email(s)
  string email = _Server->query_config("email");
  if ( !stringp(server) || strlen(server) == 0 ) {
    Test.skipped( "smtp", "no mailserver set" );
    return;
  }

  object old_euid = geteuid();
  seteuid( USER("root") );

  // create temporary test users and group:
  string tmp_name;
  int tmp_name_count = 1;
  object user_sender;
  do {
    tmp_name = "mailtest_sender_" + ((string)time()) + "_" +
      ((string)tmp_name_count++);
    user_sender = USER( tmp_name );
  } while ( objectp(user_sender) );
  user_sender = get_factory(CLASS_USER)->execute( ([ "name": tmp_name,
                "pw":"test", "email": GROUP("admin")->get_steam_email(), ]) );
  if ( objectp(user_sender) )
    test_objects["sender"] = user_sender;

  object user_receiver;
  tmp_name_count = 1;
  do {
    tmp_name = "mailtest_receiver_" + ((string)time()) + "_" +
      ((string)tmp_name_count++);
    user_receiver = USER( tmp_name );
  } while ( objectp(user_receiver) );
  user_receiver = get_factory(CLASS_USER)->execute( ([ "name": tmp_name,
		"pw":"test", ]) );
  if ( objectp(user_receiver) )
    test_objects["receiver"] = user_receiver;

  object group;
  tmp_name_count = 1;
  do {
    tmp_name = "mailtest_group_" + ((string)time()) + "_" +
      ((string)tmp_name_count++);
    group = GROUP( tmp_name );
  } while ( objectp(group) );
  group = get_factory(CLASS_GROUP)->execute( ([ "name": tmp_name, ]) );
  if ( objectp(group) )
    test_objects["group"] = group;

  // setup temporary users and group:
  object sent_mail = user_sender->create_sent_mail_folder();
  user_sender->set_is_storing_sent_mail( true );
  user_receiver->set_attribute( USER_FORWARD_MSG, 1 );
  if ( arrayp(_Server->get_cmdline_email_addresses()) ) {
    if ( sizeof(_Server->get_cmdline_email_addresses()) > 0 )
      user_receiver->set_attribute( USER_EMAIL,
                        _Server->get_cmdline_email_addresses()[0] );
    foreach ( _Server->get_cmdline_email_addresses(), string email ) {
      get_module("forward")->add_forward( user_receiver, email );
    }
  }
  group->add_member( user_receiver );

  // switch to sender uid and prepare tests:
  seteuid( user_sender );
  mapping sent = ([ ]);
  mapping receive = ([ ]);
  string testname;

  // test sending to users:
  object testmail1 = user_receiver->mail( "test user mail (1)",
                                          "test mailsystem 1" );
  Test.test( "sending direct user mail", objectp(testmail1) );
  if ( objectp(testmail1) )
    sent[ "storing direct user mail in sent-mail" ] = "test mailsystem 1";
  else
    Test.skipped( "storing direct user mail in sent-mail" );

  object factory = get_factory(CLASS_DOCUMENT);
  object plaintext = factory->execute( (["name":"test2.txt" ]) );
  plaintext->set_content("mail mit object an user (2)");
  object testmail2 = user_receiver->mail(plaintext, "test mailsystem 2");
  Test.test( "sending mail document", objectp(testmail2) );
  if ( objectp(testmail2) )
    sent[ "storing mail document in sent-mail" ] = "test2.txt";
  else
    Test.skipped( "storing mail document in sent-mail" );

  object html = factory->execute( (["name":"test3.html", ]) );
  html->set_content("<html><body><h2>Testing mail function with HTML body! (3)</h2></body></html>");
  object testmail3 = user_receiver->mail(html, "test mailsystem 3");
  Test.test( "sending mail with html document", objectp(testmail3) );
  if ( objectp(testmail3) )
    sent[ "storing mail with html document in sent-mail" ] = "test3.html";
  else
    Test.skipped( "storing mail with html document in sent-mail" );

  object ann = factory->execute( (["name":"test4.html", ]) );
  plaintext = factory->execute( (["name":"test4.txt" ]) );
  plaintext->set_content("mail with object and attachement (4)");
  ann->set_content("<html><body><h2>Testing mail function as HTML annotation!</h2></body></html>");
  plaintext->add_annotation(ann);
  object testmail4 = user_receiver->mail(plaintext, "test mailsystem 4");
  Test.test( "sending mail with annotated document", objectp(testmail4) );
  if ( objectp(testmail4) )
    sent[ "storing mail with annotated document in sent-mail" ] = "test4.txt";
  else
    Test.skipped( "storing mail with annotated document in sent-mail" );

  MESSAGE("Testing direct sending with mail system to %O", 
          user_receiver->get_steam_email());
  testname = "testmail-5 to user address " + ((string)time());
  send_mail( user_receiver->get_steam_email(), testname,
             "direct test (5)", "admin@steam.uni-paderborn.de" );
  receive[ "sending directly to user email address" ] = testname;
  testname = "testmail-6 to user addresses (array) " + ((string)time());
  send_mail( ({ user_receiver->get_steam_email(),
                user_receiver->get_steam_email() }), testname,
             "test with an array of recipients (6)",
             "admin@steam.uni-paderborn.de" );
  receive[ "sending directly to user email addresses (array)" ] = testname;

  plaintext = factory->execute( (["name":"mailtest-7.txt" ]) );
  plaintext->set_content("Testing mail with PDF attachement (0 byte) (7)");
  object pdf = factory->execute( ([ "name": "test.pdf" ]) );
  pdf->set_content("");
  plaintext->add_annotation( pdf );
  object testmail7 = user_receiver->mail( plaintext );
  Test.test( "sending mail with empty pdf attachment", objectp(testmail7) );
  if ( objectp(testmail7) )
    sent[ "storing mail with empty pdf attachment in sent-mail" ] = "mailtest-7.txt";
  else
    Test.skipped( "storing mail with empty pdf attachment in sent-mail" );
  
  // temporary disable mail host (MX test)
  string smtphost = _Server->query_config(CFG_MAILSERVER);
  _Server->set_config(CFG_MAILSERVER, 0, true);

  MESSAGE("Testing MX Lookup !");
  testname = "testmail-8 to user address (mx)" + ((string)time());
  send_mail( user_receiver->get_steam_email(), testname,
             "Testing mail with MX (8)", "admin@steam.uni-paderborn.de" );
  receive[ "sending mail to user via mx lookup" ] = testname;

  _Server->set_config(CFG_MAILSERVER, smtphost, true);
  
  // test sending to groups
  testname = "testmail-9 to group address " + ((string)time());
  send_mail( group->get_steam_email(), testname,
             "Testing mail to group", "admin@steam.uni-paderborn.de" );
  receive[ "sending mail to group via mail address" ] = testname;

  testname = "testmail-10 to a group " + ((string)time());
  plaintext = factory->execute( ([ "name":testname ]) );
  plaintext->set_attribute(DOC_MIME_TYPE, "text/plain");
  plaintext->set_content("Mail to group (10) ");
  group->mail( plaintext );
  receive[ "sending mail as plaintext to group" ] = testname;
  sent[ "storing mail as plaintext to group in sent-mail" ] = testname;

  seteuid( old_euid );

  Test.add_test_function( test_more, 10, sent, receive );
}

void test_more ( mapping sent, mapping receive, void|int nr_try ) {
  array received = test_objects["receiver"]->get_annotations();
  foreach ( indices(receive), string msg ) {
    object found;
    string name = receive[msg];
    foreach ( received, object obj ) {
      if ( obj->get_identifier() == name ||
           obj->query_attribute(OBJ_DESC) == name ) {
        found = obj;
        break;
      }
    }
    if ( objectp(found) ) {
      m_delete( receive, msg );
      Test.succeeded( msg );
    }
  }

  array sent_mails = test_objects["sender"]->get_sent_mail_folder()->get_annotations();
  foreach ( indices(sent), string msg ) {
    object found;
    string name = sent[msg];
    foreach ( sent_mails, object obj ) {
      if ( obj->get_identifier() == name ||
           obj->query_attribute(OBJ_DESC) == name ) {
        found = obj;
        break;
      }
    }
    if ( objectp(found) ) {
      m_delete( sent, msg );
      Test.succeeded( msg );
    }
  }

  if ( sizeof(receive) > 0 && sizeof(sent) > 0 ) {
    if ( nr_try < 12 ) Test.add_test_function( test_more, 10, sent, receive, nr_try+1 );
    else {
      foreach ( indices(receive), string msg )
        Test.failed( msg );
      foreach ( indices(sent), string msg )
        Test.failed( msg );
    }
  }

  Test.add_test_function( test_wait_for_empty_mail_queue, 10, 0 );
}

void test_wait_for_empty_mail_queue ( void|int try_nr ) {
  if ( MsgQueue->size() > 0 && try_nr < 18 ) {
    Test.add_test_function( test_wait_for_empty_mail_queue, 10, try_nr+1 );
    return;
  }
  // This doesn't seem to work, we might need to wait for the MsgQueue to be
  // empty for a longer time or something, don't know...
  //Test.test( "\"send\" mail queue empty", MsgQueue->size() < 1 );
  Test.skipped( "\"send\" mail queue empty (test currently broken)" );
}

void test_cleanup () {
  if ( mappingp(test_objects) ) {
    object old_euid = geteuid();
    seteuid( USER("root") );
    foreach ( values(test_objects), object obj ) {
      catch( obj->delete() );
    }
    seteuid( old_euid );
  }
}
