/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: attributes.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */
#ifndef _ATTRIBUTES_H
#define _ATTRIBUTES_H

#define OBJ_OWNER                 "OBJ_OWNER"
#define OBJ_NAME                  "OBJ_NAME"
#define OBJ_DESC                  "OBJ_DESC"
#define OBJ_ICON                  "OBJ_ICON"
#define OBJ_KEYWORDS              "OBJ_KEYWORDS"
#define OBJ_POSITION_X            "OBJ_POSITION_X"
#define OBJ_POSITION_Y            "OBJ_POSITION_Y"
#define OBJ_POSITION_Z            "OBJ_POSITION_Z"
#define OBJ_WIDTH                 "OBJ_WIDTH"
#define OBJ_HEIGHT                "OBJ_HEIGHT"
#define OBJ_LAST_CHANGED          "OBJ_LAST_CHANGED"
#define OBJ_CREATION_TIME         "OBJ_CREATION_TIME"
#define OBJ_URL                   "OBJ_URL"
#define OBJ_LINK_ICON             "OBJ_LINK_ICON"
#define OBJ_SCRIPT                "OBJ_SCRIPT"
#define OBJ_ANNOTATIONS_CHANGED   "OBJ_ANNOTATIONS_CHANGED"
#define OBJ_LOCK                  "OBJ_LOCK"
#define OBJ_ACL_ADDS              "OBJ_ACL_ADDS"
#define OBJ_LANGUAGE              "OBJ_LANGUAGE"
#define OBJ_VERSIONOF             "OBJ_VERSIONOF"
#define OBJ_TEMP                  "OBJ_TEMP"
#define OBJ_ANNO_MESSAGE_IDS      "OBJ_ANNO_MESSAGE_IDS"
#define OBJ_ANNO_MISSING_IDS      "OBJ_ANNO_MISSING_IDS"
#define OBJ_ONTHOLOGY             "OBJ_ONTHOLOGY"
#define OBJ_LINKS                 "OBJ_LINKS"
#define OBJ_PATH                  "OBJ_PATH"
#define OBJ_NAMESPACES            "OBJ_NAMESPACES"
#define OBJ_EX_NAMESPACES         "OBJ_EX_NAMESPACES"
#define OBJ_WIKILINKS             "OBJ_WIKILINKS"
#define OBJ_TYPE                  "OBJ_TYPE"

#define DOC_TYPE                  "DOC_TYPE"
#define DOC_MIME_TYPE             "DOC_MIME_TYPE"
#define DOC_USER_MODIFIED         "DOC_USER_MODIFIED"
#define DOC_LAST_MODIFIED         "DOC_LAST_MODIFIED"
#define DOC_LAST_ACCESSED         "DOC_LAST_ACCESSED"
#define DOC_EXTERN_URL            "DOC_EXTERN_URL"
#define DOC_TIMES_READ            "DOC_TIMES_READ"
#define DOC_IMAGE_ROTATION        "DOC_IMAGE_ROTATION"
#define DOC_IMAGE_THUMBNAIL       "DOC_IMAGE_THUMBNAIL"
#define DOC_IMAGE_SIZEX           "DOC_IMAGE_SIZEX"
#define DOC_IMAGE_SIZEY           "DOC_IMAGE_SIZEY"
#define DOC_HAS_FULLTEXTINDEX     "DOC_HAS_FULLTEXTINDEX"
#define DOC_ENCODING              "DOC_ENCODING"
#define DOC_XSL_PIKE              "DOC_XSL_PIKE"
#define DOC_XSL_PASSIVE           "DOC_XSL_PASSIVE"
#define DOC_XSL_XML               "DOC_XSL_XML"
#define DOC_LOCK                  "DOC_LOCK"
#define DOC_AUTHORS               "DOC_AUTHORS"
#define DOC_BIBTEX                "DOC_BIBTEX"
#define DOC_VERSIONS              "DOC_VERSIONS"
#define DOC_VERSION               "DOC_VERSION"
#define DOC_THUMBNAILS            "DOC_THUMBNAILS"
#define DOCLPC_INSTANCETIME       "DOCLPC_INSTANCETIME"
#define DOCLPC_XGL                "DOCLPC_XGL"

#define MAIL_EXPIRE               "MAIL_EXPIRE"

#define CONT_SIZE_X               "CONT_SIZE_X"
#define CONT_SIZE_Y               "CONT_SIZE_Y"
#define CONT_SIZE_Z               "CONT_SIZE_Z"
#define CONT_EXCHANGE_LINKS       "CONT_EXCHANGE_LINKS"
#define CONT_MONITOR              "CONT_MONITOR"
#define CONT_LAST_MODIFIED        "CONT_LAST_MODIFIED"
#define CONT_USER_MODIFIED        "CONT_USER_MODIFIED"
#define CONT_CONTENT_SVG          "CONT_CONTENT_SVG"
#define CONT_WSDL                 "CONT_WSDL"

#define GROUP_MEMBERSHIP_REQS     "GROUP_MEMBERSHIP_REQS"
#define GROUP_EXITS               "GROUP_EXITS"
#define GROUP_MAXSIZE             "GROUP_MAXSIZE"
#define GROUP_MSG_ACCEPT          "GROUP_MSG_ACCEPT"
#define GROUP_MAXPENDING          "GROUP_MAXPENDING"
#define GROUP_CALENDAR            "GROUP_CALENDAR"
#define GROUP_INVITES_EMAIL       "GROUP_INVITES_EMAIL"
#define GROUP_NAMESPACE_USERS_CRC "GROUP_NAMESPACE_USERS_CRC"
#define GROUP_NAMESPACE_GROUPS_CRC "GROUP_NAMESPACE_GROUPS_CRC"
#define GROUP_MAIL_SETTINGS       "GROUP_MAIL_SETTINGS"

#define USER_ADRESS               "USER_ADRESS"
#define USER_FULLNAME             "USER_FULLNAME"
#define USER_LASTNAME             "USER_FULLNAME"
#define USER_MAILBOX              "USER_MAILBOX"
#define USER_WORKROOM             "USER_WORKROOM"
#define USER_LAST_LOGIN           "USER_LAST_LOGIN"
#define USER_EMAIL                "USER_EMAIL"
#define USER_EMAIL_LOCALCOPY      "USER_EMAIL_LOCALCOPY"
#define USER_UMASK                "USER_UMASK"
#define USER_MODE                 "USER_MODE"
#define USER_MODE_MSG             "USER_MODE_MSG"
#define USER_LOGOUT_PLACE         "USER_LOGOUT_PLACE"
#define USER_TRASHBIN             "USER_TRASHBIN"
#define USER_BOOKMARKROOM         "USER_BOOKMARKROOM"
#define USER_FORWARD_MSG          "USER_FORWARD_MSG"
#define USER_IRC_PASSWORD         "USER_IRC_PASSWORD"
#define USER_FIRSTNAME            "USER_FIRSTNAME"
#define USER_LANGUAGE             "USER_LANGUAGE"
#define USER_SELECTION            "USER_SELECTION"
#define USER_FAVOURITES           "USER_FAVOURITES"
#define USER_CALENDAR             "USER_CALENDAR"
#define USER_SMS                  "USER_SMS"
#define USER_PHONE                "USER_PHONE"
#define USER_FAX                  "USER_FAX"
#define USER_WIKI_TRAIL           "USER_WIKI_TRAIL"
#define USER_MONITOR              "USER_MONITOR"
#define USER_ID                   "USER_ID"
#define USER_CONTACTS_CONFIRMED   "USER_CONTACTS_CONFIRMED"
#define USER_NAMESPACE_GROUPS_CRC "USER_NAMESPACE_GROUPS_CRC"
#define USER_MAIL_SENT            "USER_MAIL_SENT"
#define USER_MAIL_STORE_SENT      "USER_MAIL_STORE_SENT"

#define GATE_REMOTE_SERVER        "GATE_REMOTE_SERVER"
#define GATE_REMOTE_OBJ           "GATE_REMOTE_OBJ"

#define ROOM_TRASHBIN              "ROOM_TRASHBIN"

#define DRAWING_TYPE              "DRAWING_TYPE"
#define DRAWING_WIDTH             "DRAWING_WIDTH"
#define DRAWING_HEIGHT            "DRAWING_HEIGHT"
#define DRAWING_COLOR             "DRAWING_COLOR"
#define DRAWING_THICKNESS         "DRAWING_THICKNESS"
#define DRAWING_FILLED            "DRAWING_FILLED"

#define GROUP_WORKROOM            "GROUP_WORKROOM"
#define GROUP_EXCLUSIVE_SUBGROUPS "GROUP_EXCLUSIVE_SUBGROUPS"

#define DATE_KIND_OF_ENTRY     "DATE_KIND_OF_ENTRY"
#define DATE_IS_SERIAL         "DATE_IS_SERIAL"
#define DATE_PRIORITY          "DATE_PRIORITY"
#define DATE_TITLE             "DATE_TITLE"
#define DATE_DESCRIPTION       "DATE_DESCRIPTION"
#define DATE_START_DATE        "DATE_START_DATE"
#define DATE_END_DATE          "DATE_END_DATE"
#define DATE_RANGE             "DATE_RANGE"
#define DATE_START_TIME        "DATE_START_TIME"
#define DATE_END_TIME          "DATE_END_TIME"
#define DATE_INTERVALL         "DATE_INTERVALL"
#define DATE_LOCATION          "DATE_LOCATION"
#define DATE_NOTICE            "DATE_NOTICE"
#define DATE_WEBSITE           "DATE_WEBSITE"
#define DATE_TYPE              "DATE_TYPE"
#define DATE_ATTACHMENT        "DATE_ATTACHMENT"
#define DATE_PARTICIPANTS      "DATE_PARTICIPANTS"
#define DATE_ORGANIZERS        "DATE_ORGANIZERS"
#define DATE_ACCEPTED          "DATE_ACCEPTED"
#define DATE_CANCELLED         "DATE_CANCELLED"
#define DATE_STATUS            "DATE_STATUS"

#define CALENDAR_TIMETABLE_START    "CALENDAR_TIMETABLE_START"
#define CALENDAR_TIMETABLE_END      "CALENDAR_TIMETABLE_END"
#define CALENDAR_TIMETABLE_ROTATION "CALENDAR_TIMETABLE_ROTATION"
#define CALENDAR_DATE_TYPE          "CALENDAR_DATE_TYPE"
#define CALENDAR_TRASH              "CALENDAR_TRASH"
#define CALENDAR_STORAGE            "CALENDAR_STORAGE"
#define CALENDAR_OWNER              "CALENDAR_OWNER"

#define FACTORY_LAST_REGISTER       "FACTORY_LAST_REGISTER"

#define SCRIPT_LANGUAGE_OBJ         "SCRIPT_LANGUAGE_OBJ"

#define PACKAGE_AUTHOR            "PACKAGE_AUTHOR"
#define PACKAGE_VERSION           "PACKAGE_VERSION"
#define PACKAGE_CATEGORY          "PACKAGE_CATEGORY"
#define PACKAGE_STABILITY         "PACKAGE_STABILITY"

#define LAB_TUTOR                 "LAB_TUTOR"
#define LAB_SIZE                  "LAB_SIZE"
#define LAB_ROOM                  "LAB_ROOM"
#define LAB_APPTIME               "LAB_APPTIME"

#define MAIL_MIMEHEADERS          "MAIL_MIMEHEADERS"
#define MAIL_MIMEHEADERS_ADDITIONAL "MAIL_MIMEHEADERS_ADDITIONAL"
#define MAIL_IMAPFLAGS            "MAIL_IMAPFLAGS"
#define MAIL_SUBSCRIBED_FOLDERS   "MAIL_SUBSCRIBED_FOLDERS"

#define MESSAGEBOARD_ARCHIVE       "messageboard_archive"

#define WIKI_LINKMAP              "WIKI_LINKMAP"

#define CONTROL_ATTR_USER          1
#define CONTROL_ATTR_CLIENT        2
#define CONTROL_ATTR_SERVER        3

#define DRAWING_LINE               1
#define DRAWING_RECTANGLE          2
#define DRAWING_TRIANGLE           3
#define DRAWING_POLYGON            4
#define DRAWING_CONNECTOR          5
#define DRAWING_CIRCLE             6
#define DRAWING_TEXT               7

#define SPM_FILES                 "SPM_FILES"
#define SPM_MODULES               "SPM_MODULES"



#define REGISTERED_TYPE            0
#define REGISTERED_DESC            1
#define REGISTERED_EVENT_READ      2
#define REGISTERED_EVENT_WRITE     3
#define REGISTERED_ACQUIRE         4
#define REGISTERED_CONTROL         5
#define REGISTERED_DEFAULT         6

#define REG_ACQ_ENVIRONMENT        "get_environment"
#define CLASS_ANY                  0 // for packages and registering attributes

#endif
