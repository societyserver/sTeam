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
 * $Id: classes.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _CLASSES_H
#define _CLASSES_H

#include "config.h"

#define CLASS_USER CLASS_PATH + "user.pike"  //TODO: this is redefined below!

#define CLASS_PATH "/classes/"

#define CLASS_NAME_OBJECT "Object"
#define CLASS_NAME_CONTAINER "Container"
#define CLASS_NAME_ROOM "Room"
#define CLASS_NAME_USER "User"
#define CLASS_NAME_DOCUMENT "Document"
#define CLASS_NAME_LINK "Link"
#define CLASS_NAME_GROUP "Group"
#define CLASS_NAME_EXIT    "Exit"
#define CLASS_NAME_DOCEXTERN "DocExtern"
#define CLASS_NAME_DOCLPC "DocLPC"
#define CLASS_NAME_SCRIPT "Script"
#define CLASS_NAME_DOCHTML "DocHTML"
#define CLASS_NAME_DATE     "Date"
#define CLASS_NAME_MESSAGEBOARD "Messageboard"
#define CLASS_NAME_GHOST   "Ghost"  //TODO: there's no "Ghost" class
#define CLASS_NAME_SERVERGATE "ServerGate"
#define CLASS_NAME_TRASHBIN "TrashBin"
#define CLASS_NAME_DOCXML "DocXML"
#define CLASS_NAME_DOCXSL "DocXSL"
#define CLASS_NAME_LAB "Laboratory"  //TODO: there's no "Laboratory" class
#define CLASS_NAME_CALENDAR "Calendar"
#define CLASS_NAME_DRAWING "Drawing"
#define CLASS_NAME_AGENT "Agent"
#define CLASS_NAME_ANNOTATION "Annotation"  //TODO: there's no "Annotation" class

#define CLASS_OBJECT        (1<<0)
#define CLASS_CONTAINER     (1<<1)
#define CLASS_ROOM          (1<<2)
#define CLASS_USER          (1<<3)
#define CLASS_DOCUMENT      (1<<4)
#define CLASS_LINK          (1<<5)
#define CLASS_GROUP         (1<<6)
#define CLASS_EXIT          (1<<7)
#define CLASS_DOCEXTERN     (1<<8)
#define CLASS_DOCLPC        (1<<9)
#define CLASS_SCRIPT        (1<<10)
#define CLASS_DOCHTML       (1<<11)
#define CLASS_DATE          (1<<12)
#define CLASS_FACTORY       (1<<13)
#define CLASS_MODULE        (1<<14)
#define CLASS_DATABASE      (1<<15)
#define CLASS_PACKAGE       (1<<16)
#define CLASS_IMAGE         (1<<17)
#define CLASS_MESSAGEBOARD  (1<<18)
#define CLASS_GHOST         (1<<19)
#define CLASS_WEBSERVICE    (1<<20)
#define CLASS_TRASHBIN      (1<<21)
#define CLASS_DOCXML        (1<<22)
#define CLASS_DOCXSL        (1<<23)
#define CLASS_LAB           (1<<24)
#define CLASS_CALENDAR      (1<<27)
#define CLASS_SCORM         (1<<28)
#define CLASS_DRAWING       (1<<29)
#define CLASS_AGENT         (1<<30)

#define CLASS_ALL 0x3cffffff  // bits 25 and 26 aren't used by CLASS_*

#define CLASS_SERVER        0x00000000
#define CLASS_USERDEF       0x30000000

#endif
