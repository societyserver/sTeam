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
 * $Id: events.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _EVENT_H
#define _EVENT_H

#define EVENT_ERROR  -1
#define EVENT_BLOCKED 0
#define EVENT_OK      1

#define EVENTS_SERVER            0x00000000
#define EVENTS_USER              0xf0000000
#define EVENTS_MODULES           0x10000000
#define EVENTS_MONITORED         0x20000000
#define EVENTS_SECOND            0x40000000

#define EVENT_MASK               0xffffffff - EVENTS_MONITORED


#define EVENT_ENTER_INVENTORY          1
#define EVENT_LEAVE_INVENTORY          2
#define EVENT_UPLOAD                   4
#define EVENT_DOWNLOAD                 8
#define EVENT_ATTRIBUTES_CHANGE       16
#define EVENT_MOVE                    32
#define EVENT_SAY                     64
#define EVENT_TELL                   128
#define EVENT_LOGIN                  256
#define EVENT_LOGOUT                 512
#define EVENT_ATTRIBUTES_LOCK       1024
#define EVENT_EXECUTE               2048 // scripts and the like
#define EVENT_REGISTER_FACTORY      4096
#define EVENT_REGISTER_MODULE       8192
#define EVENT_ATTRIBUTES_ACQUIRE   16384
#define EVENT_ATTRIBUTES_QUERY     32768
#define EVENT_REGISTER_ATTRIBUTE   65536
#define EVENT_DELETE              131072
#define EVENT_ADD_MEMBER          262144
#define EVENT_REMOVE_MEMBER       524288
#define EVENT_GRP_ADD_PERMISSION 1048576
#define EVENT_USER_CHANGE_PW     2097152
#define EVENT_SANCTION           4194304
#define EVENT_SANCTION_META      8388608
#define EVENT_ARRANGE_OBJECT     (1<<24)
#define EVENT_ANNOTATE           (1<<25)
#define EVENT_LISTEN_EVENT       (1<<26)
#define EVENT_IGNORE_EVENT       (1<<27)

#define EVENT_GET_INVENTORY      (1|EVENTS_SECOND)
#define EVENT_DUPLICATE          (2|EVENTS_SECOND)
#define EVENT_REQ_SAVE           (4|EVENTS_SECOND)
#define EVENT_GRP_ADDMUTUAL      (8|EVENTS_SECOND)
#define EVENT_REF_GONE           (16|EVENTS_SECOND)
#define EVENT_STATUS_CHANGED     (32|EVENTS_SECOND)
#define EVENT_SAVE_OBJECT        (64|EVENTS_SECOND)
#define EVENT_REMOVE_ANNOTATION  (128|EVENTS_SECOND)
#define EVENT_DOWNLOAD_FINISHED  (256|EVENTS_SECOND)
#define EVENT_LOCK               (512|EVENTS_SECOND)
#define EVENT_USER_JOIN_GROUP    (1024|EVENTS_SECOND)
#define EVENT_USER_LEAVE_GROUP   (2048|EVENTS_SECOND)
#define EVENT_UNLOCK             (4096|EVENTS_SECOND)
#define EVENT_DECORATE           (8192|EVENTS_SECOND)
#define EVENT_REMOVE_DECORATION (16384|EVENTS_SECOND)

#define EVENT_USER_NEW_TICKET    (EVENT_USER_CHANGE_PW|EVENTS_SECOND)

#define EVENTS_OBSERVE (EVENT_SAY|EVENT_ENTER_INVENTORY|EVENT_LEAVE_INVENTORY)

#define EVENT_DB_REGISTER        EVENTS_MODULES | 1 << 1
#define EVENT_DB_UNREGISTER      EVENTS_MODULES | 1 << 2
#define EVENT_DB_QUERY           EVENTS_MODULES | 1 << 3
#define EVENT_SERVER_SHUTDOWN    EVENTS_MODULES | 1 << 4
#define EVENT_CHANGE_QUOTA       EVENTS_MODULES | 1 << 5

#define PHASE_BLOCK  1
#define PHASE_NOTIFY 2

#define _EVENT_FUNC   0
#define _EVENT_ID     1
#define _EVENT_PHASE  2
#define _EVENT_OBJECT 3

#define _MY_EVENT_ID  0
#define _MY_EVENT_NUM 1

#endif
