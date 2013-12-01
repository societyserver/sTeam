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
 * $Id: database.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _DATABASE_H
#define _DATABASE_H

#define ID_DATABASE 1

#define _SECURITY _Server->get_module("security")
#define _FILEPATH _Server->get_module("filepath:tree")
#define _TYPES _Server->get_module("types")
#define _LOG _Server->get_module("log")

#define OBJ(s) _FILEPATH->path_to_object(s)

#define MODULE_USERS   (_Server ? _Server->get_module("users") : 0)
#define MODULE_GROUPS  (_Server ? _Server->get_module("groups") : 0)
#define MODULE_OBJECTS (_Server ? _Server->get_module("objects") : 0)
#define MODULE_SMTP    (_Server ? _Server->get_module("smtp") : 0)
#define MODULE_URL     (_Server ? _Server->get_module("url") : 0)
#define MODULE_ICONS   (_Server ? _Server->get_module("icons") : 0)
#define SECURITY_CACHE (_Server ? _Server->get_module("Security:cache"):0)
#define MODULE_SERVICE (_Server ? _Server->get_module("ServiceManager"):0)

#define MOD(s) (_Server->get_module(s))
#define USER(s) MODULE_USERS->lookup(s)
#define GROUP(s) MODULE_GROUPS->lookup(s)

#define _ROOTROOM _Persistence->lookup("rootroom")
#define _STEAMUSER _Persistence->lookup_group("steam")
#define _ROOT _Persistence->lookup_user("root")
#define _GUEST _Persistence->lookup_user("guest")

#define _ADMIN _Persistence->lookup_group("admin")
#define _WORLDUSER _Persistence->lookup_group("everyone")
#define _AUTHORS _Persistence->lookup_group("authors")
#define _REVIEWER _Persistence->lookup_group("reviewer")
#define _BUILDER _Persistence->lookup_group("builder")
#define _CODER _Persistence->lookup_group("coder")


#define PSTAT_FAIL_DELETED       -3
#define PSTAT_FAIL_UNSERIALIZE   -2
#define PSTAT_FAIL_COMPILE       -1
#define PSTAT_DISK                0
#define PSTAT_SAVE_OK             1
#define PSTAT_SAVE_PENDING        2
#define PSTAT_DELETED             3

#define SAVE_INSERT 1
#define SAVE_REMOVE 2
#define SAVE_ORDER  3

#define PSTAT_NAMES ({ "deletion failed", "unserialize failed","compile failed", \
"on disk", "Ok", "save pending", "deleted" })

#define STORE_GROUP     "group"
#define STORE_ATTRIB    "attrib"
#define STORE_ACCESS    "access"
#define STORE_DATA      "data"
#define STORE_KEYWORDS  "keyword"
#define STORE_EVENTS    "events"
#define STORE_ANNOTS    "annots"
#define STORE_REFS      "refs"
#define STORE_CONTENT   "content"
#define STORE_CONTAINER "container"
#define STORE_HTMLLINK  "htmllink"
#define STORE_DOCLPC    "doclpc"
#define STORE_LINK      "link"
#define STORE_USER      "user"
#define STORE_ATTREG    "attreg"
#define STORE_ICONS     "icons"
#define STORE_NEWSGRP   "newsgrp"
#define STORE_QUOTA     "quota"
#define STORE_SMTP      "smtp"
#define STORE_TASKS     "tasks"
#define STORE_TEMPOBJ   "tempobj"
#define STORE_FORWARD   "forward"
#define STORE_SERVERS   "servers"
#define STORE_AUTH      "auth"
#define STORE_DECORATIONS "decorations"

#define PSTAT(i) PSTAT_NAMES[(i+3)]
#define OID_BITS 28

#endif





