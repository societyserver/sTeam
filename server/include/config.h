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
 * $Id: config.h,v 1.6 2010/01/23 08:40:29 astra Exp $
 */

#ifndef _CONFIG_H
#define _CONFIG_H

#define USE_LOCAL_SQLCONNECT 1
//#define DEBUG 1
//#define DEBUG_MEMORY
//#define EVENT_DEBUG
#define DEBUG_PROFILE 1
//#define VERIFY_CMOD 1
#define DEBUG_SECURITY
#define DEBUG_EVENTS 1
#define DEBUG_HTTP 1
#define DEBUG_SECURITY
//#define TASK_DEBUG 1
//#define DEBUG_PROTOCOLL
//#define EVENT_DEBUG

#define LOG_LEVEL_NONE 0
#define LOG_LEVEL_ERROR 1
#define LOG_LEVEL_WARNING 2
#define LOG_LEVEL_INFO 3
#define LOG_LEVEL_DEBUG 4

#define USER_SCRIPTS 0

#define BLOCK_SIZE 32000
#define DB_CHUNK_SIZE 8192
#define SOCKET_READ_SIZE 65536
#define HTTP_MAX_BODY  20000000
#define MIMETYPE_UNKNOWN "application/x-unknown-content-type"

#define WEBDAV_CLASS2

#define READ_ONCE 80

#define OBJ_COAL   "/kernel/securesocket.pike"
#define OBJ_SCOAL  "/kernel/securesocket.pike"
#define OBJ_NNTP   "/net/nntp.pike"
#define OBJ_SMTP   "/net/smtp.pike"
#define OBJ_SMB    "/net/smb.pike"
#define OBJ_IMAP   "/net/imap.pike"
#define OBJ_POP3   "/net/pop3.pike"
#define OBJ_IRC    "/net/irc.pike"
#define OBJ_FTP    "/net/ftp.pike"
#define OBJ_JABBER "/net/jabber.pike"
#define OBJ_TELNET "/net/telnet.pike"
#define OBJ_XMLRPC "/net/xmlrpc.pike"

#define STEAM_VERSION "2.9.5"

#define CLASS_PATH "classes/"

#define LOGFILE_DB "database.log"
#define LOGFILE_SECURITY "security.log"
#define LOGFILE_ERROR "errors.log"
#define LOGFILE_BOOT "boot.log"
#define LOGFILE_EVENT "events.log"
#define LOGFILE_DEBUG "debug.log"

#define STEAM_DB_CONNECT _Server->get_database()

#define CFG_WEBSERVER      "web_server"
#define CFG_WEBPORT_HTTP   "web_port_http"
#define CFG_WEBPORT_FTP    "web_port_ftp"
#define CFG_WEBPORT        "web_port_"
#define CFG_WEBPORT_URL    "web_port"
#define CFG_WEBMOUNT       "web_mount"
#define CFG_MAILSERVER     "mail_server"
#define CFG_MAILPORT       "mail_port"
#define CFG_EMAIL          "account_email"
#define CFG_DOMAIN         "domain"


#define CFG_WEBPORT_PRESENTATION  "web_port"
#define CFG_WEBPORT_ADMINISTRATION "web_port_http"

#define THREAD_READ 1

#endif

































