#!/usr/local/lib/steam/bin/steam

/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2003-2004  Martin Baehr
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
 * $Id: debug.pike.in,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: debug.pike.in,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/usr/local/lib/steam/tools/applauncher.pike";

Stdio.Readline readln = Stdio.Readline(Stdio.stdin);

class Handler
{
  inherit Tools.Hilfe.Evaluator;

  void create(mapping _constants)
  {
    write=predef::write;
    ::create();
    constants+=_constants;
  }
}

void ping()
{
  call_out(ping, 60);
  conn->send_command(14, 0); 
}

object handler, conn;

int main(int argc, array(string) argv)
{
  mapping options=init(argv);
  object _Server=conn->SteamObj(0);
  //write("%O\n", options);
  //Tools.Hilfe.StdinHilfe();

  object users=_Server->get_module("users");

  handler = Handler(([
    "_Server"     : _Server,
    "get_module"  : _Server->get_module,
    "get_factory" : _Server->get_factory,
    "conn"        : conn,
    "find_object" : conn->find_object,
    "users"       : users,
    "groups"      : _Server->get_module("groups"),
    "me"          : users->lookup(options->user),
    "edit"        : applaunch,
    "create"      : create_object,

    // from database.h :
    "_SECURITY" : _Server->get_module("security"),
    "_FILEPATH" : _Server->get_module("filepath:tree"),
    "_TYPES" : _Server->get_module("types"),
    "_LOG" : _Server->get_module("log"),
    "OBJ" : _Server->get_module("filepath:tree")->path_to_object,
    "MODULE_USERS" : _Server->get_module("users"),
    "MODULE_GROUPS" : _Server->get_module("groups"),
    "MODULE_OBJECTS" : _Server->get_module("objects"),
    "MODULE_SMTP" : _Server->get_module("smtp"),
    "MODULE_URL" : _Server->get_module("url"),
    "MODULE_ICONS" : _Server->get_module("icons"),
    "SECURITY_CACHE" : _Server->get_module("Security:cache"),
    "MODULE_SERVICE" : _Server->get_module("ServiceManager"),
    "MOD" : _Server->get_module,
    "USER" : _Server->get_module("users")->lookup,
    "GROUP" : _Server->get_module("groups")->lookup,
    "_ROOTROOM" : _Server->get_module("filepath:tree")->path_to_object("/"),
    "_STEAMUSER" : _Server->get_module("users")->lookup("steam"),
    "_ROOT" : _Server->get_module("users")->lookup("root"),
    "_GUEST" : _Server->get_module("users")->lookup("guest"),
    "_ADMIN" : _Server->get_module("users")->lookup("admin"),
    "_WORLDUSER" : _Server->get_module("users")->lookup("everyone"),
    "_AUTHORS" : _Server->get_module("users")->lookup("authors"),
    "_REVIEWER" : _Server->get_module("users")->lookup("reviewer"),
    "_BUILDER" : _Server->get_module("users")->lookup("builder"),
    "_CODER" : _Server->get_module("users")->lookup("coder"),
    "PSTAT_FAIL_DELETED" : -3,
    "PSTAT_FAIL_UNSERIALIZE" : -2,
    "PSTAT_FAIL_COMPILE" : -1,
    "PSTAT_DISK" : 0,
    "PSTAT_SAVE_OK" : 1,
    "PSTAT_SAVE_PENDING" : 2,
    "PSTAT_DELETED" : 3,
    "SAVE_INSERT" : 1,
    "SAVE_REMOVE" : 2,
    "SAVE_ORDER" : 3,
    "OID_BITS" : 28,

    // from sanction.h :
    "ACCESS_DENIED" : 0,
    "ACCESS_GRANTED" : 1,
    "ACCESS_BLOCKED" : 2,
    "SANCTION_READ" : 1,
    "SANCTION_EXECUTE" : 2,
    "SANCTION_MOVE" : 4,
    "SANCTION_WRITE" : 8,
    "SANCTION_INSERT" : 16,
    "SANCTION_ANNOTATE" : 32,
    "SANCTION_SANCTION" : (1<<8),
    "SANCTION_LOCAL" : (1<<9),
    "SANCTION_ALL" : (1<<15)-1,
    "SANCTION_SHIFT_DENY" : 16,
    "SANCTION_COMPLETE" : (0xffffffff),
    "SANCTION_POSITIVE" : (0xffff0000),
    "SANCTION_NEGATIVE" : (0x0000ffff),
    "SANCTION_READ_ROLE" : (1|2|32),

    // from attributes.h :
    "OBJ_OWNER" :                 "OBJ_OWNER",
    "OBJ_NAME" :                  "OBJ_NAME",
    "OBJ_DESC" :                  "OBJ_DESC",
    "OBJ_ICON" :                  "OBJ_ICON",
    "OBJ_KEYWORDS" :              "OBJ_KEYWORDS",
    "OBJ_POSITION_X" :            "OBJ_POSITION_X",
    "OBJ_POSITION_Y" :            "OBJ_POSITION_Y",
    "OBJ_POSITION_Z" :            "OBJ_POSITION_Z",
    "OBJ_WIDTH" :                 "OBJ_WIDTH",
    "OBJ_HEIGHT" :                "OBJ_HEIGHT",
    "OBJ_LAST_CHANGED" :          "OBJ_LAST_CHANGED",
    "OBJ_CREATION_TIME" :         "OBJ_CREATION_TIME",
    "OBJ_URL" :                   "OBJ_URL",
    "OBJ_LINK_ICON" :             "OBJ_LINK_ICON",
    "OBJ_SCRIPT" :                "OBJ_SCRIPT",
    "OBJ_ANNOTATIONS_CHANGED" :   "OBJ_ANNOTATIONS_CHANGED",
    "OBJ_LOCK" :                  "OBJ_LOCK",
    "OBJ_ACL_ADDS" :              "OBJ_ACL_ADDS",
    "OBJ_LANGUAGE" :              "OBJ_LANGUAGE",
    "OBJ_VERSIONOF" :             "OBJ_VERSIONOF",
    "OBJ_TEMP" :                  "OBJ_TEMP",
    "OBJ_ANNO_MESSAGE_IDS" :      "OBJ_ANNO_MESSAGE_IDS",
    "OBJ_ANNO_MISSING_IDS" :      "OBJ_ANNO_MISSING_IDS",
    "OBJ_ONTHOLOGY" :             "OBJ_ONTHOLOGY",
    "OBJ_LINKS" :                 "OBJ_LINKS",
    "OBJ_PATH" :                  "OBJ_PATH",
    "OBJ_NAMESPACES" :            "OBJ_NAMESPACES",
    "OBJ_EX_NAMESPACES" :         "OBJ_EX_NAMESPACES",
    "OBJ_TYPE" :                  "OBJ_TYPE",
    "DOC_TYPE" :                  "DOC_TYPE",
    "DOC_MIME_TYPE" :             "DOC_MIME_TYPE",
    "DOC_USER_MODIFIED" :         "DOC_USER_MODIFIED",
    "DOC_LAST_MODIFIED" :         "DOC_LAST_MODIFIED",
    "DOC_LAST_ACCESSED" :         "DOC_LAST_ACCESSED",
    "DOC_EXTERN_URL" :            "DOC_EXTERN_URL",
    "DOC_TIMES_READ" :            "DOC_TIMES_READ",
    "DOC_IMAGE_ROTATION" :        "DOC_IMAGE_ROTATION",
    "DOC_IMAGE_THUMBNAIL" :       "DOC_IMAGE_THUMBNAIL",
    "DOC_IMAGE_SIZEX" :           "DOC_IMAGE_SIZEX",
    "DOC_IMAGE_SIZEY" :           "DOC_IMAGE_SIZEY",
    "DOC_HAS_FULLTEXTINDEX" :     "DOC_HAS_FULLTEXTINDEX",
    "DOC_ENCODING" :              "DOC_ENCODING",
    "DOC_XSL_PIKE" :              "DOC_XSL_PIKE",
    "DOC_XSL_PASSIVE" :           "DOC_XSL_PASSIVE",
    "DOC_XSL_XML" :               "DOC_XSL_XML",
    "DOC_LOCK" :                  "DOC_LOCK",
    "DOC_AUTHORS" :               "DOC_AUTHORS",
    "DOC_BIBTEX" :                "DOC_BIBTEX",
    "DOC_VERSIONS" :              "DOC_VERSIONS",
    "DOC_VERSION" :               "DOC_VERSION",
    "DOC_THUMBNAILS" :            "DOC_THUMBNAILS",
    "DOCLPC_INSTANCETIME" :       "DOCLPC_INSTANCETIME",
    "DOCLPC_XGL" :                "DOCLPC_XGL",
    "MAIL_EXPIRE" :               "MAIL_EXPIRE",
    "CONT_SIZE_X" :               "CONT_SIZE_X",
    "CONT_SIZE_Y" :               "CONT_SIZE_Y",
    "CONT_SIZE_Z" :               "CONT_SIZE_Z",
    "CONT_EXCHANGE_LINKS" :       "CONT_EXCHANGE_LINKS",
    "CONT_MONITOR" :              "CONT_MONITOR",
    "CONT_LAST_MODIFIED" :        "CONT_LAST_MODIFIED",
    "CONT_USER_MODIFIED" :        "CONT_USER_MODIFIED",
    "CONT_CONTENT_SVG" :          "CONT_CONTENT_SVG",
    "CONT_WSDL" :                 "CONT_WSDL",
    "GROUP_MEMBERSHIP_REQS" :     "GROUP_MEMBERSHIP_REQS",
    "GROUP_EXITS" :               "GROUP_EXITS",
    "GROUP_MAXSIZE" :             "GROUP_MAXSIZE",
    "GROUP_MSG_ACCEPT" :          "GROUP_MSG_ACCEPT",
    "GROUP_MAXPENDING" :          "GROUP_MAXPENDING",
    "GROUP_CALENDAR" :            "GROUP_CALENDAR",
    "GROUP_INVITES_EMAIL" :       "GROUP_INVITES_EMAIL",
    "GROUP_NAMESPACE_USERS_CRC" : "GROUP_NAMESPACE_USERS_CRC",
    "GROUP_NAMESPACE_GROUPS_CRC" : "GROUP_NAMESPACE_GROUPS_CRC",
    "GROUP_MAIL_SETTINGS" :       "GROUP_MAIL_SETTINGS",
    "USER_ADRESS" :               "USER_ADRESS",
    "USER_FULLNAME" :             "USER_FULLNAME",
    "USER_LASTNAME" :             "USER_FULLNAME",
    "USER_MAILBOX" :              "USER_MAILBOX",
    "USER_WORKROOM" :             "USER_WORKROOM",
    "USER_LAST_LOGIN" :           "USER_LAST_LOGIN",
    "USER_EMAIL" :                "USER_EMAIL",
    "USER_EMAIL_LOCALCOPY" :      "USER_EMAIL_LOCALCOPY",
    "USER_UMASK" :                "USER_UMASK",
    "USER_MODE" :                 "USER_MODE",
    "USER_MODE_MSG" :             "USER_MODE_MSG",
    "USER_LOGOUT_PLACE" :         "USER_LOGOUT_PLACE",
    "USER_TRASHBIN" :             "USER_TRASHBIN",
    "USER_BOOKMARKROOM" :         "USER_BOOKMARKROOM",
    "USER_FORWARD_MSG" :          "USER_FORWARD_MSG",
    "USER_IRC_PASSWORD" :         "USER_IRC_PASSWORD",
    "USER_FIRSTNAME" :            "USER_FIRSTNAME",
    "USER_LANGUAGE" :             "USER_LANGUAGE",
    "USER_SELECTION" :            "USER_SELECTION",
    "USER_FAVOURITES" :           "USER_FAVOURITES",
    "USER_CALENDAR" :             "USER_CALENDAR",
    "USER_SMS" :                  "USER_SMS",
    "USER_PHONE" :                "USER_PHONE",
    "USER_FAX" :                  "USER_FAX",
    "USER_WIKI_TRAIL" :           "USER_WIKI_TRAIL",
    "USER_MONITOR" :              "USER_MONITOR",
    "USER_ID" :                   "USER_ID",
    "USER_CONTACTS_CONFIRMED" :   "USER_CONTACTS_CONFIRMED",
    "USER_NAMESPACE_GROUPS_CRC" : "USER_NAMESPACE_GROUPS_CRC",
    "USER_MAIL_SENT" :            "USER_MAIL_SENT",
    "USER_MAIL_STORE_SENT" :      "USER_MAIL_STORE_SENT",
    "GATE_REMOTE_SERVER" :        "GATE_REMOTE_SERVER",
    "GATE_REMOTE_OBJ" :           "GATE_REMOTE_OBJ",
    "ROOM_TRASHBIN" :              "ROOM_TRASHBIN",
    "DRAWING_TYPE" :              "DRAWING_TYPE",
    "DRAWING_WIDTH" :             "DRAWING_WIDTH",
    "DRAWING_HEIGHT" :            "DRAWING_HEIGHT",
    "DRAWING_COLOR" :             "DRAWING_COLOR",
    "DRAWING_THICKNESS" :         "DRAWING_THICKNESS",
    "DRAWING_FILLED" :            "DRAWING_FILLED",
    "GROUP_WORKROOM" :            "GROUP_WORKROOM",
    "GROUP_EXCLUSIVE_SUBGROUPS" : "GROUP_EXCLUSIVE_SUBGROUPS",
    "DATE_KIND_OF_ENTRY" :     "DATE_KIND_OF_ENTRY",
    "DATE_IS_SERIAL" :         "DATE_IS_SERIAL",
    "DATE_PRIORITY" :          "DATE_PRIORITY",
    "DATE_TITLE" :             "DATE_TITLE",
    "DATE_DESCRIPTION" :       "DATE_DESCRIPTION",
    "DATE_START_DATE" :        "DATE_START_DATE",
    "DATE_END_DATE" :          "DATE_END_DATE",
    "DATE_RANGE" :             "DATE_RANGE",
    "DATE_START_TIME" :        "DATE_START_TIME",
    "DATE_END_TIME" :          "DATE_END_TIME",
    "DATE_INTERVALL" :         "DATE_INTERVALL",
    "DATE_LOCATION" :          "DATE_LOCATION",
    "DATE_NOTICE" :            "DATE_NOTICE",
    "DATE_WEBSITE" :           "DATE_WEBSITE",
    "DATE_TYPE" :              "DATE_TYPE",
    "DATE_ATTACHMENT" :        "DATE_ATTACHMENT",
    "DATE_PARTICIPANTS" :      "DATE_PARTICIPANTS",
    "DATE_ORGANIZERS" :        "DATE_ORGANIZERS",
    "DATE_ACCEPTED" :          "DATE_ACCEPTED",
    "DATE_CANCELLED" :         "DATE_CANCELLED",
    "DATE_STATUS" :            "DATE_STATUS",
    "CALENDAR_TIMETABLE_START" :    "CALENDAR_TIMETABLE_START",
    "CALENDAR_TIMETABLE_END" :      "CALENDAR_TIMETABLE_END",
    "CALENDAR_TIMETABLE_ROTATION" : "CALENDAR_TIMETABLE_ROTATION",
    "CALENDAR_DATE_TYPE" :          "CALENDAR_DATE_TYPE",
    "CALENDAR_TRASH" :              "CALENDAR_TRASH",
    "CALENDAR_STORAGE" :            "CALENDAR_STORAGE",
    "CALENDAR_OWNER" :              "CALENDAR_OWNER",
    "FACTORY_LAST_REGISTER" :       "FACTORY_LAST_REGISTER",
    "SCRIPT_LANGUAGE_OBJ" :         "SCRIPT_LANGUAGE_OBJ",
    "PACKAGE_AUTHOR" :            "PACKAGE_AUTHOR",
    "PACKAGE_VERSION" :           "PACKAGE_VERSION",
    "PACKAGE_CATEGORY" :          "PACKAGE_CATEGORY",
    "PACKAGE_STABILITY" :         "PACKAGE_STABILITY",
    "LAB_TUTOR" :                 "LAB_TUTOR",
    "LAB_SIZE" :                  "LAB_SIZE",
    "LAB_ROOM" :                  "LAB_ROOM",
    "LAB_APPTIME" :               "LAB_APPTIME",
    "MAIL_MIMEHEADERS" :          "MAIL_MIMEHEADERS",
    "MAIL_MIMEHEADERS_ADDITIONAL" : "MAIL_MIMEHEADERS_ADDITIONAL",
    "MAIL_IMAPFLAGS" :            "MAIL_IMAPFLAGS",
    "MAIL_SUBSCRIBED_FOLDERS" :   "MAIL_SUBSCRIBED_FOLDERS",
    "MESSAGEBOARD_ARCHIVE" :       "messageboard_archive",
    "WIKI_LINKMAP" :              "WIKI_LINKMAP",
    "CONTROL_ATTR_USER" :          1,
    "CONTROL_ATTR_CLIENT" :        2,
    "CONTROL_ATTR_SERVER" :        3,
    "DRAWING_LINE" :               1,
    "DRAWING_RECTANGLE" :          2,
    "DRAWING_TRIANGLE" :           3,
    "DRAWING_POLYGON" :            4,
    "DRAWING_CONNECTOR" :          5,
    "DRAWING_CIRCLE" :             6,
    "DRAWING_TEXT" :               7,
    "SPM_FILES" :                 "SPM_FILES",
    "SPM_MODULES" :               "SPM_MODULES",
    "REGISTERED_TYPE" :            0,
    "REGISTERED_DESC" :            1,
    "REGISTERED_EVENT_READ" :      2,
    "REGISTERED_EVENT_WRITE" :     3,
    "REGISTERED_ACQUIRE" :         4,
    "REGISTERED_CONTROL" :         5,
    "REGISTERED_DEFAULT" :         6,
    "REG_ACQ_ENVIRONMENT" :        "get_environment",
    "CLASS_ANY" :                  0,

    // from classes.h :
    "CLASS_PATH" : "/classes/",
    "CLASS_NAME_OBJECT" : "Object",
    "CLASS_NAME_CONTAINER" : "Container",
    "CLASS_NAME_ROOM" : "Room",
    "CLASS_NAME_USER" : "User",
    "CLASS_NAME_DOCUMENT" : "Document",
    "CLASS_NAME_LINK" : "Link",
    "CLASS_NAME_GROUP" : "Group",
    "CLASS_NAME_EXIT" :    "Exit",
    "CLASS_NAME_DOCEXTERN" : "DocExtern",
    "CLASS_NAME_DOCLPC" : "DocLPC",
    "CLASS_NAME_SCRIPT" : "Script",
    "CLASS_NAME_DOCHTML" : "DocHTML",
    "CLASS_NAME_DATE" :     "Date",
    "CLASS_NAME_MESSAGEBOARD" : "Messageboard",
    "CLASS_NAME_GHOST" :   "Ghost",
    "CLASS_NAME_SERVERGATE" : "ServerGate",
    "CLASS_NAME_TRASHBIN" : "TrashBin",
    "CLASS_NAME_DOCXML" : "DocXML",
    "CLASS_NAME_DOCXSL" : "DocXSL",
    "CLASS_NAME_LAB" : "Laboratory",
    "CLASS_NAME_CALENDAR" : "Calendar",
    "CLASS_NAME_DRAWING" : "Drawing",
    "CLASS_NAME_AGENT" : "Agent",
    "CLASS_NAME_ANNOTATION" : "Annotation",
    "CLASS_OBJECT" :        (1<<0),
    "CLASS_CONTAINER" :     (1<<1),
    "CLASS_ROOM" :          (1<<2),
    "CLASS_USER" :          (1<<3),
    "CLASS_DOCUMENT" :      (1<<4),
    "CLASS_LINK" :          (1<<5),
    "CLASS_GROUP" :         (1<<6),
    "CLASS_EXIT" :          (1<<7),
    "CLASS_DOCEXTERN" :     (1<<8),
    "CLASS_DOCLPC" :        (1<<9),
    "CLASS_SCRIPT" :        (1<<10),
    "CLASS_DOCHTML" :       (1<<11),
    "CLASS_DATE" :          (1<<12),
    "CLASS_FACTORY" :       (1<<13),
    "CLASS_MODULE" :        (1<<14),
    "CLASS_DATABASE" :      (1<<15),
    "CLASS_PACKAGE" :       (1<<16),
    "CLASS_IMAGE" :         (1<<17),
    "CLASS_MESSAGEBOARD" :  (1<<18),
    "CLASS_GHOST" :         (1<<19),
    "CLASS_WEBSERVICE" :    (1<<20),
    "CLASS_TRASHBIN" :      (1<<21),
    "CLASS_DOCXML" :        (1<<22),
    "CLASS_DOCXSL" :        (1<<23),
    "CLASS_LAB" :           (1<<24),
    "CLASS_CALENDAR" :      (1<<27),
    "CLASS_SCORM" :         (1<<28),
    "CLASS_DRAWING" :       (1<<29),
    "CLASS_AGENT" :         (1<<30),
    "CLASS_ALL" : 0x3cffffff,
    "CLASS_SERVER" :        0x00000000,
    "CLASS_USERDEF" :       0x30000000,

    // from events.h :
    "EVENT_ERROR" :  -1,
    "EVENT_BLOCKED" : 0,
    "EVENT_OK" :      1,
    "EVENTS_SERVER" :            0x00000000,
    "EVENTS_USER" :              0xf0000000,
    "EVENTS_MODULES" :           0x10000000,
    "EVENTS_MONITORED" :         0x20000000,
    "EVENTS_SECOND" :            0x40000000,
    "EVENT_MASK" :               0xffffffff - 0x20000000,
    "EVENT_ENTER_INVENTORY" :          1,
    "EVENT_LEAVE_INVENTORY" :          2,
    "EVENT_UPLOAD" :                   4,
    "EVENT_DOWNLOAD" :                 8,
    "EVENT_ATTRIBUTES_CHANGE" :       16,
    "EVENT_MOVE" :                    32,
    "EVENT_SAY" :                     64,
    "EVENT_TELL" :                   128,
    "EVENT_LOGIN" :                  256,
    "EVENT_LOGOUT" :                 512,
    "EVENT_ATTRIBUTES_LOCK" :       1024,
    "EVENT_EXECUTE" :               2048,
    "EVENT_REGISTER_FACTORY" :      4096,
    "EVENT_REGISTER_MODULE" :       8192,
    "EVENT_ATTRIBUTES_ACQUIRE" :   16384,
    "EVENT_ATTRIBUTES_QUERY" :     32768,
    "EVENT_REGISTER_ATTRIBUTE" :   65536,
    "EVENT_DELETE" :              131072,
    "EVENT_ADD_MEMBER" :          262144,
    "EVENT_REMOVE_MEMBER" :       524288,
    "EVENT_GRP_ADD_PERMISSION" : 1048576,
    "EVENT_USER_CHANGE_PW" :     2097152,
    "EVENT_SANCTION" :           4194304,
    "EVENT_SANCTION_META" :      8388608,
    "EVENT_ARRANGE_OBJECT" :     (1<<24),
    "EVENT_ANNOTATE" :           (1<<25),
    "EVENT_LISTEN_EVENT" :       (1<<26),
    "EVENT_IGNORE_EVENT" :       (1<<27),
    "EVENT_GET_INVENTORY" :      (1|0x40000000),
    "EVENT_DUPLICATE" :          (2|0x40000000),
    "EVENT_REQ_SAVE" :           (4|0x40000000),
    "EVENT_GRP_ADDMUTUAL" :      (8|0x40000000),
    "EVENT_REF_GONE" :           (16|0x40000000),
    "EVENT_STATUS_CHANGED" :     (32|0x40000000),
    "EVENT_SAVE_OBJECT" :        (64|0x40000000),
    "EVENT_REMOVE_ANNOTATION" :  (128|0x40000000),
    "EVENT_DOWNLOAD_FINISHED" :  (256|0x40000000),
    "EVENT_LOCK" :               (512|0x40000000),
    "EVENT_USER_JOIN_GROUP" :    (1024|0x40000000),
    "EVENT_USER_LEAVE_GROUP" :   (2048|0x40000000),
    "EVENT_UNLOCK" :             (4096|0x40000000),
    "EVENT_DECORATE" :           (8192|0x40000000),
    "EVENT_REMOVE_DECORATION" :  (16384|0x40000000),
    "EVENT_USER_NEW_TICKET" :    (2097152|0x40000000),
    "EVENTS_OBSERVE" : (64|1|2),
    "EVENT_DB_REGISTER" :        0x10000000 | 1 << 1,
    "EVENT_DB_UNREGISTER" :      0x10000000 | 1 << 2,
    "EVENT_DB_QUERY" :           0x10000000 | 1 << 3,
    "EVENT_SERVER_SHUTDOWN" :    0x10000000 | 1 << 4,
    "EVENT_CHANGE_QUOTA" :       0x10000000 | 1 << 5,
    "PHASE_BLOCK" :  1,
    "PHASE_NOTIFY" : 2,
    "_EVENT_FUNC" :   0,
    "_EVENT_ID" :     1,
    "_EVENT_PHASE" :  2,
    "_EVENT_OBJECT" : 3,
    "_MY_EVENT_ID" :  0,
    "_MY_EVENT_NUM" : 1,

    // from roles.h :
    "ROLE_READ_ALL" :          1,
    "ROLE_EXECUTE_ALL" :       2,
    "ROLE_MOVE_ALL" :          4,
    "ROLE_WRITE_ALL" :         8,
    "ROLE_INSERT_ALL" :        16,
    "ROLE_ANNOTATE_ALL" :      32,
    "ROLE_SANCTION_ALL" :      (1<<8),
    "ROLE_REBOOT" :            (1<<16),
    "ROLE_REGISTER_CLASSES" :  (1<<17),
    "ROLE_GIVE_ROLES" :        (1<<18),
    "ROLE_CHANGE_PWS" :        (1<<19),
    "ROLE_REGISTER_MODULES" :  (1<<20),
    "ROLE_CREATE_TOP_GROUPS" : (1<<21),
    "ROLE_ALL_ROLES" :       (1<<31)-1+(1<<30),

    // from types.h :
    "CMD_TYPE_UNKNOWN" :   0,
    "CMD_TYPE_INT" :       1,
    "CMD_TYPE_FLOAT" :     2,
    "CMD_TYPE_STRING" :    3,
    "CMD_TYPE_OBJECT" :    4,
    "CMD_TYPE_ARRAY" :     5,
    "CMD_TYPE_MAPPING" :   6,
    "CMD_TYPE_MAP_ENTRY" : 7,
    "CMD_TYPE_PROGRAM" :   8,
    "CMD_TYPE_TIME" :      9,
    "CMD_TYPE_FUNCTION" : 10,
    "CMD_TYPE_DATA" :     11,
    "XML_NORMAL" :  (1<<0),
    "XML_SIZE" :    (1<<1),
    "XML_OBJECTS" : (1<<2),
    "XML_TIME" :    (1<<3),
    "XML_OBJECT" :  (1<<4),
    "XML_TYPE_MASK" :   (0x0000000f),
    "XML_DISPLAY" :     (1<<8),
    "XML_ATTRIBUTES" :  (1<<8),
    "XML_ANNOTATIONS" : (1<<9),
    "XML_ACCESS" :      (1<<10),
    "XML_INVENTORY" :   (1<<11),
    "XML_BASIC" :       (1<<12),
    "XML_STYLESHEETS" : (1<<13),
    "XML_DETAILS" :     (1<<16),
    "XML_ALWAYS" : ((1<<8)|(1<<9)|(1<<10)|(1<<11)|(1<<12)|(1<<16)),

    ]));

  array history=(Stdio.read_file(options->historyfile)||"")/"\n";
  if(history[-1]!="")
    history+=({""});

  Stdio.Readline.History readline_history=Stdio.Readline.History(512, history);

  readln->enable_history(readline_history);

  handler->add_input_line("start backend");

  string command;
  while(command=readln->read(
           sprintf("%s", (handler->state->finishedp()?"> ":">> "))))
  {
    if(sizeof(command))
    {
      Stdio.write_file(options->historyfile, readln->get_history()->encode());
      handler->add_input_line(command);
    }
  }
  handler->add_input_line("exit");
}

mapping init(array argv)
{
  mapping options = ([ "file":"/etc/shadow" ]);

  array opt=Getopt.find_all_options(argv,aggregate(
    ({"file",Getopt.HAS_ARG,({"-f","--file"})}),
    ({"host",Getopt.HAS_ARG,({"-h","--host"})}),
    ({"user",Getopt.HAS_ARG,({"-u","--user"})}),
    ({"port",Getopt.HAS_ARG,({"-p","--port"})}),
    ));

  options->historyfile=getenv("HOME")+"/.steam_history";

  foreach(opt, array option)
  {
    options[option[0]]=option[1];
  }
  if(!options->host)
    options->host="127.0.0.1";
  if(!options->user)
    options->user="root";
  if(!options->port)
    options->port=1900;
  else
    options->port=(int)options->port;

  string server_path = "/usr/local/lib/steam";

  master()->add_include_path(server_path+"/server/include");
  master()->add_program_path(server_path+"/server/");
  master()->add_program_path(server_path+"/conf/");
  master()->add_program_path(server_path+"/spm/");
  master()->add_program_path(server_path+"/server/net/coal/");

  conn = ((program)"client_base.pike")();

  int start_time = time();

  werror("Connecting to sTeam server...\n");
  while ( !conn->connect_server(options->host, options->port)  ) 
  {
    if ( time() - start_time > 120 ) 
    {
      throw (({" Couldn't connect to server. Please check steam.log for details! \n", backtrace()}));
    }
    werror("Failed to connect... still trying ... (server running ?)\n");
    sleep(10);
  }
 
  ping();
  if(lower_case(options->user) == "guest")
    return options;

  mixed err;
  string pw;
  int tries=3;
  //readln->set_echo( 0 );
  do
  {
    pw = Input.read_password( sprintf("Password for %s@%s", options->user,
           options->host), "steam" );
    //pw=readln->read(sprintf("passwd for %s@%s: ", options->user, options->host));
  }
  while((err = catch(conn->login(options->user, pw, 1))) && --tries);
  //readln->set_echo( 1 );

  if ( err != 0 ) 
  {
    werror("Failed to log in!\nWrong Password!\n");
    exit(1);
  } 
  return options;
}

// create new sTeam objects
// with code taken from the web script create.pike
mixed create_object(string|void objectclass, string|void name, void|string desc, void|mapping data)
{
  if(!objectclass && !name)
  {
    write("Usage: create(string objectclass, string name, void|string desc, void|mapping data\n");
    return 0;
  }
  object _Server=conn->SteamObj(0);
  object created;
  object factory;

  if ( !stringp(objectclass))
    return "No object type submitted";

  factory = _Server->get_factory(objectclass);

  switch(objectclass)
  {
    case "exit":
      if(!data->exit_from)
        return "exit_from missing";
      break;
    case "link":
      if(!data->link_to)
        return "link_to missing";
      break;
  }

  if(!data)
    data=([]);
  created = factory->execute(([ "name":name ])+ data );

  if(stringp(desc))
    created->set_attribute("OBJ_DESC", desc);

//  if ( kind=="gallery" )
//  {
//    created->set_acquire_attribute("xsl:content", 0);
//    created->set_attribute("xsl:content",
//      ([ _STEAMUSER:_FILEPATH->path_to_object("/stylesheets/gallery.xsl") ])
//                          );
//  }

//  created->move(this_user());

  return created;
}

