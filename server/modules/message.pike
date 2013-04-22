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
 * $Id: message.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: message.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <macros.h>
#include <database.h>
#include <attributes.h>
#include <classes.h>
#include <exception.h>

#define HEADER_SEP "\r\n"

//! This module converts a normal sTeam document to a Mime Object.
//! The object of type MimeMessage is then returned when calling
//! the function fetch_message(). This is used by POP3.

static string    sServer;
static mapping mMessages;


string header(object obj)
{
    if ( !objectp(obj) ) return "";
    object creator = obj->get_creator();
    string name = creator->query_attribute(USER_EMAIL);
    if ( !stringp(name) || name == "" ) 
	name = creator->get_identfier() + "@"+sServer;
    else
	name = creator->query_attribute(USER_FULLNAME) + " <"+name+">";
    return "From: " + name + HEADER_SEP +
	"Date: " + timelib.smtp_time(obj->query_attribute(OBJ_CREATION_TIME))+
	HEADER_SEP+
	"Subject: "+obj->query_attribute(OBJ_NAME)+HEADER_SEP+
	"Message-ID: <" + sprintf("%010d",obj->get_object_id())+"@"+sServer+">"+HEADER_SEP+
	"Lines: " + (sizeof((obj->get_content()/"\n"))) + HEADER_SEP;
}

object fetch_message(object obj)
{
    string mimetype = obj->query_attribute(DOC_MIME_TYPE);
#if 0
    if ( mimetype == "text/html" || mimetype == "text/plain" ) {
	return header(obj) + "\r\n" + obj->get_content();
    }
#endif
    object creator = obj->get_creator();
    MIME.Message msg = MIME.Message(
		    obj->get_content(), 
		    ([ "MIME-Version": "1.0",
		     "Content-Type": mimetype, 
		     "Content-Transfer-Encoding": "base64",
		     "Subject": obj->get_identifier(),
		     "Message-ID": "<"+sprintf("%010d",obj->get_object_id())+"@"+sServer+">",
		     "Date": timelib.smtp_time(obj->query_attribute(OBJ_CREATION_TIME)),
		     "From": creator->get_identifier() + "@"+sServer + "("+
		     creator->query_attribute(USER_FULLNAME) + ")",
		     ]) );
    return msg;
}

/**
 * Callback function for module initialization.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
void init_module()
{
    sServer = _Server->get_server_name();
    set_attribute(OBJ_DESC, "The Module converts sTeam Objects into "+
		  "mime-messages.");
}


string get_identifier() { return "message"; }





