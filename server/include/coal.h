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
 * $Id: coal.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

/* COAL - Client object access layer */
#ifndef _COAL_H
#define _COAL_H

#include "types.h"

#define COAL_QUERY_COMMANDS  0
#define COAL_COMMAND         1
#define COAL_EVENT           2
#define COAL_LOGIN           3
#define COAL_LOGOUT          4
#define COAL_FILE_DOWNLOAD   5
#define COAL_FILE_UPLOAD     6
#define COAL_QUERY_PROGRAMS  7
#define COAL_ERROR           8
#define COAL_SET_CLIENT      9
#define COAL_UPLOAD_START    10
#define COAL_UPLOAD_PACKAGE  11
#define COAL_CRYPT           12
#define COAL_UPLOAD_FINISHED 13
#define COAL_PING            14
#define COAL_PONG            15
#define COAL_LOG             16
#define COAL_RETR_LOG        17
#define COAL_SUBSCRIBE       18
#define COAL_UNSUBSCRIBE     19
#define COAL_REG_SERVICE     20
#define COAL_RELOGIN         21
#define COAL_SERVERHELLO     22
#define COAL_GETOBJECT       23
#define COAL_SENDOBJECT      24

#define COAL_TIMEOUT         600 // 10 minutes

#define _COAL_OK                   0

#define SEND_ERROR(e, d, t, oid, cid, cmd, args, bt) send_message(coal_compose(t, COAL_ERROR, oid,cid, ({ e, d, cmd, args, bt }) ))
#define SEND_COAL(t, cmd, o, cid, a) send_message(coal_compose(t, cmd, o, cid, a ))

#define HL_CMD  0
#define HL_ARGS 1
#define HL_REST 2

#define COALLINE_TID     0
#define COALLINE_COMMAND 1
#define COALLINE_OBJECT  2
#define COALLINE_NAMESPACE 3
#define COALLINE_SERVER    4

#define INT2BYTES(arg) str[1] = (arg & ( 255 << 24));\
	    str[2] = (arg & ( 255 << 16));\
	    str[3] = (arg & ( 255 << 8));\
	    str[4] = (arg & ( 255 ))

#define COMMAND_BEGIN_MASK 255
#define COMMAND_RAW        127

#define USE_LAST_TID -1

#define LONG_INTEGER ((int)(1<<31)>0)

#define COAL_TRANSFER_RCV  1
#define COAL_TRANSFER_SEND 2
#define COAL_TRANSFER_NONE 0

#define CLIENT_CLASS_STEAM "steam"
#define CLIENT_CLASS_FTP "ftp"
#define CLIENT_CLASS_HTTP "http"
#define CLIENT_CLASS_SERVER "peer"

#define CRYPT_KEY 512
#define CRYPT_WSIZE (CRYPT_KEY/16)
#define CRYPT_RSIZE (CRYPT_KEY/8)

#define COAL_VERSION "1.0"

#endif





