/* Copyright (C) 2000-2006  Thomas Bopp
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
 */
inherit "/kernel/module" : __module;
inherit "/base/webservice" : __ws;

import steamXML;

#include <macros.h>
#include <events.h>
#include <attributes.h>
#include <coal.h>
#include <database.h>
#include <classes.h>


static void deploy_webservice(string path)
{
  object fpurl = get_module("filepath:url");
  if (!objectp(fpurl)) {
    call_out(deploy_webservice, 1, path);
    return;
  }
  fpurl->set_attribute(OBJ_URL, path);
}

void load_module()
{
  set_acquire_attribute(OBJ_URL, get_module("filepath:tree"));
  register_webservice(getCurrentUser);
  register_webservice(createUser);
  register_webservice(deleteUser);
  register_webservice(searchUser);
  register_webservice(getMembership);
  register_webservice(joinGroup);
  register_webservice(leaveGroup);

  register_webservice(uploadFile);
  register_webservice(createFile);
  register_webservice(moveFile);
  register_webservice(searchFile);

  register_webservice(createGroup);
  register_webservice(createSubgroup);
  register_webservice(getSubgroups);
  register_webservice(deleteGroup);
  register_webservice(searchGroup);
  register_webservice(getMembers);

  register_webservice(createFolder);
  register_webservice(deleteFolder);
  register_webservice(renameFolder);
  register_webservice(getInventory);

  register_webservice(getRootFolder);
  register_webservice(getHomeFolder);
  register_webservice(searchFolder);

  register_webservice(createRoom);
  register_webservice(deleteRoom);
  register_webservice(enterRoom);
  register_webservice(leaveRoom);

  register_webservice(createAppointment);
  register_webservice(deleteAppointment);
  
  register_webservice(search);
  register_webservice(publish);

  deploy_webservice("/cowapi");
}

mixed execute(mapping vars) {
  if (vars->wsdl)
    return ({ show_wsdl(), "text/xml" });
  return "The CowAPI - MUH!";
}

string get_identifier() { return "CowAPI"; }
int get_object_class() { return ::get_object_class() | CLASS_WEBSERVICE | CLASS_SCRIPT; }
string get_webservice_name() { return "CowAPI"; }
string get_webservice_urn() { return "CowAPI"; }

/**************** helper functions ***********/
string muh(string|object|array xml)
{
  if (objectp(xml)) 
    xml = object_to_xml(xml);
  if (arrayp(xml)) {
    string res = "";
    foreach(xml, mixed x) {
      if (objectp(x))
        res += object_to_xml(x);
      else if (stringp(x))
        res += x;
      else
        res += sprintf("%O", x);
    }
    xml = res;
  }
  return replace("<result>" + xml + "</result>", 
                 ({ "<", ">" }), ({ "&lt;", "&gt;" }));
}

string label(string message, void|string lang)
{
  return sprintf("<label xml:lang=\"%s\">%s</label>\n", lang||"en", message);
}

string muh_error(string message, int errcode)
{
  return sprintf("<error><code>%d</code>%s</error>", 
                 errcode, 
                 label(message, "en"));
}

/**************   CowAPI *****************/
string explain(string method)
{
  string xml = "<?xml version='1.0' encoding='utf-8'?>";
  xml += "<explain>\n"+
    "<services>\n"+
    "<service name='Files' />\n"+
    "<service name='Users' />\n"+
    "<service name='Groups' />\n"+
    "<service name='Rooms' />\n"+
    "<service name='Calendars' />\n"+
    "</services>"+
    "</explain>";
  
  return xml;
}

string getCurrentUser() 
{
  // xml of current user
  return muh(object_to_xml(this_user()));
}


// USER Functions
string createUser(string name, string password) 
{
  object factory = get_factory(CLASS_USER);
  object user = factory->execute(([ "nickname": name, "pw": password ]));
  return muh(user);
}

string deleteUser(string userid)
{
  object user = find_object((int)userid);
  // todo: check for user ?!
  mixed err = catch(user->delete_object());
  if ( err )
    return muh_error("Failed to delete User", 401);
  return muh(label("User deleted"));
}

string searchUser(string pattern, string type)
{
  array users = get_module("users")->search_users(pattern, true);
  return muh(users);
}


// GROUP Functions
static string|object check_group(string groupid)
{
  object group = find_object((int)groupid);
  if (!objectp(group))
    return muh_error("Group not found!", 404);
  if (!(group->get_object_class()&CLASS_GROUP))
    return muh_error("groupid param is not a group!", 412);
  return group;
}


string getMembers(string groupid)
{
  string|object group = check_group(groupid);
  if ( stringp(group) ) return group;
  return muh(group->get_members());
}

string getMembership(string userid)
{
  object user = find_object((int)userid);
  if (!objectp(user))
    return muh_error("User not found", 404);
  if (!(user->get_object_class()&CLASS_USER))
    return muh_error("Object is not a user", 412);
  return muh(user->get_groups());
}

string joinGroup(string userid, string groupid)
{
  object user = find_object((int)userid);
  if (!objectp(user))
    return muh_error("User not found", 404);
  object|string group = check_group(groupid);
  if ( stringp(group) ) return group;

  group->add_member(user);
  return muh(label("User added to group"));
}

string leaveGroup(string userid, string groupid)
{
  object user = find_object((int)userid);
  if (!objectp(user))
    return muh_error("User not found", 404);
  object group = find_object((int)groupid);
  if ( !objectp(group) )
    return muh_error("Group not found", 404);
  if (!(group->get_object_class() & CLASS_GROUP))
    return muh_error("Cannot remove member from non-group", 412);
  group->remove_member(user);
  return muh(label("User removed from group"));
}

string createGroup(string name)
{
  object group = get_factory(CLASS_GROUP)->execute((["name":name,]));
  return muh(group);
}

string createSubgroup(string groupid, string name)
{
  object pgroup = find_object((int)groupid);
  if ( !objectp(pgroup) )
    return muh_error("Group not found", 404);
  if (!(pgroup->get_object_class() & CLASS_GROUP))
    return muh_error("Cannot create sub-group of non-group", 412);
  
  object group = get_factory(CLASS_GROUP)->execute((["name":name, "parent": pgroup]));
  return muh(group);
}

string getSubgroups(string groupid)
{
  string|object group = check_group(groupid);
  if ( stringp(group) ) return group;
  return muh(group->get_members(CLASS_GROUP));
}

string deleteGroup(string groupid)
{
  object group = find_object((int)groupid);
  if ( !objectp(group) )
    return muh_error("Group not found", 404);
  if (!(group->get_object_class() & CLASS_GROUP))
    return muh_error("Cannot delete non-group", 412);
  group->delete();
  return muh(label("Group deleted!"));
}

string searchGroup(string pattern, string type)
{
  return muh(get_module("groups")->lookup_name(pattern, true));
}

// FILE methods!

string createFile(string name, string path)
{
  object doc = get_factory(CLASS_DOCUMENT)->execute((["name":name,]));
  if ( strlen(path) > 0 ) {
    object cont = _FILEPATH->path_to_object(path);
    doc->move(cont);
  }
  return muh(doc);
}

string createFolder(string name)
{
  string dir = dirname(name);
  string fname= basename(name);
  object folder = get_factory(CLASS_CONTAINER)->execute((["name": fname,]));
  if ( strlen(dir) > 0 ) {
    object moveto = _FILEPATH->path_to_object(dir);
    folder->move(moveto);
  }
  return muh(folder);
}

string deleteFolder(string folderId)
{
  object obj = find_object((int)folderId);
  if ( !objectp(obj) )
    return muh_error("File not found", 404);
  if ( !(obj->get_object_class() & CLASS_CONTAINER) )
    return muh_error("Object is no Folder", 412);
  obj->delete();
  return muh(label("Folder deleted!"));
}

string renameFolder(string folderId, string name)
{
  object folder = find_object((int)folderId);
  if ( !objectp(folder) )
    return muh_error("Folder not found!", 404);
  if ( !(folder->get_object_class() & CLASS_CONTAINER) )
    return muh_error("Object is no folder", 412);
  
  string dir = dirname(name);
  string fname = basename(name);
  object dest;

  if ( strlen(dir) > 0 ) {
    dest = _FILEPATH->path_to_object(dir);
    if ( !objectp(dest) )
      return muh_error("Destination path not found", 412);
    if ( !(dest->get_object_class() & CLASS_CONTAINER) )
      return muh_error("Destination path is no folder!", 412);
  }
  folder->set_attribute(OBJ_NAME, fname);
  if ( objectp(dest) )
    folder->move(dest);
  return muh(label("Folder renamed!"));
}

string uploadFile(string docid, string protocol, string data)
{
  object doc = find_object((int)docid);
  if (!objectp(doc)) 
    return muh_error("File not found", 404);
  if (!(doc->get_object_class()&CLASS_DOCUMENT))
    return muh_error("Object is not a file", 412); // precondition failed
  doc->set_content(data);
  return muh(doc);
}

string moveFile(string fileId, string destinationId)
{
  object obj = find_object((int)fileId);
  if ( !objectp(obj) )
    return muh_error("File not found", 404);
  object dest = find_object((int)destinationId);
  if ( !objectp(dest) )
    return muh_error("Destination not found", 404);
  if ( !(dest->get_object_class() & CLASS_CONTAINER) )
    return muh_error("Destination is no Folder", 412);
  obj->move(dest);
  return muh(label("Object moved !"));
}

string getInventory(string folderId)
{
  object folder = find_object((int)folderId);
  if ( !objectp(folder) )
    return muh_error("Folder not found!", 404);
  if ( !(folder->get_object_class() & CLASS_CONTAINER) )
    return muh_error("Object is no folder", 412);
  return muh(folder->get_inventory());
}

string getRootFolder()
{
  return muh(_ROOTROOM);
}

string getHomeFolder(string userId)
{
  object user = find_object((int)userId);
  if ( !objectp(user) )
    return muh_error("User not found!", 404);
  if ( !(user->get_object_class() & CLASS_USER) )
    return muh_error("Object is not a user!", 412);
  return muh(user->query_attribute(USER_WORKROOM));
}

string searchFile(string pattern, string type)
{
}

string searchFolder(string pattern, string type)
{
}

// ROOM functions
string createRoom(string name)
{
  string dir = dirname(name);
  string fname= basename(name);
  object folder = get_factory(CLASS_ROOM)->execute((["name": fname,]));
  if ( strlen(dir) > 0 ) {
    object moveto = _FILEPATH->path_to_object(dir);
    folder->move(moveto);
  }
  return muh(folder);
}

string deleteRoom(string roomId)
{
  object room = find_object((int)roomId);
  if ( !objectp(room) )
    return muh_error("Room not found!", 404);
  if ( !(room->get_object_class() & CLASS_ROOM) )
    return muh_error("Object is no Room!", 412);
  room->delete();
  return muh(label("Room deleted!"));
}

string enterRoom(string userId, string roomId)
{
  object user = find_object((int)userId);
  if ( !objectp(user) )
    return muh_error("User not found!", 404);
  if ( !(user->get_object_class() & CLASS_USER) )
    return muh_error("Object is not a user!", 412);
  object room = find_object((int)roomId);
  if ( !objectp(room) )
    return muh_error("Room not found!", 404);
  if ( !(room->get_object_class() & CLASS_ROOM) )
    return muh_error("Object is no Room!", 412);
  user->move(room);
  return muh(label("User moved into room!"));
}

string leaveRoom(string userId, string roomId)
{
  object user = find_object((int)userId);
  if ( !objectp(user) )
    return muh_error("User not found!", 404);
  if ( !(user->get_object_class() & CLASS_USER) )
    return muh_error("Object is not a user!", 412);
  object room = find_object((int)roomId);
  if ( !objectp(room) )
    return muh_error("Room not found!", 404);
  if ( !(room->get_object_class() & CLASS_ROOM) )
    return muh_error("Object is no Room!", 412);
  if ( user->get_environment() != room )
    return muh_error("User is not in Room!", 412);
  user->move(user->query_attribute(USER_WORKROOM));
  return muh(label("User left room!"));
}

// CALENDAR functions
string createAppointment(string calendarId, string title, int start, int end,
			 string desc, string location) 
{
  object calendar = find_object((int)calendarId);
  if ( !objectp(calendar) )
    return muh_error("Calendar not found!", 404);
  if ( !(calendar->get_object_class() & CLASS_CALENDAR) )
    return muh_error("Object is no calendar!", 412);
  mapping attributes = ([ DATE_DESCRIPTION: title,
			  DATE_START_TIME: start,
			  DATE_END_TIME: end,
			  DATE_LOCATION: location, ]);
  object appointment = calendar->add_entry(([ "name": "title", 
					      "attributes": attributes ]));
  return muh(appointment);
}

string deleteAppointment(string appointmentId)
{
  object appointment = find_object((int)appointmentId);
  if ( !objectp(appointment) )
    return muh_error("Appointment not found!", 404);
  if ( !(appointment->get_object_class() & CLASS_DATE) )
    return muh_error("Object is no appointment!", 412);
  appointment->delete();
  return muh(label("Appointment deleted!"));
}

static mapping parse_querymeta(object node)
{
  mapping metaquery = ([ 
    "sortby": "none",
    "maxresults": 10000,
    "startresults": 0,
  ]);
  if (!objectp(node))
    return metaquery;

  return metaquery;
}

static string search_finished(array results, object userData)
{
  for ( int i=0; i < sizeof(results); i++ )
    results[i] = find_object((int)results[i]);
  results -= ({ 0 });
  string xml = muh(results);
  return xml;
}

// mistel services
string|object search(string searchXML)
{
  // parse xml 
  object xml = xmlDom.parse(searchXML);
  object method = xml->get_node("/search/method");
  if ( !objectp(method) )
    return muh_error("No Search method selected", 412);
  string query = method->get_node("query")->get_data();
  mapping metaquery = parse_querymeta(method->get_node("querymeta"));
  object q = get_module("searching")->searchQuery(search_finished, ([ ]),  ({ }));

  switch(method->get_node("name")->get_data()) {
  case "keyword":
    // usual keyword search
    q->extend(STORE_ATTRIB, OBJ_NAME, q->like(query));
    q->extend(STORE_ATTRIB, OBJ_DESC, q->like(query));
    q->extend(STORE_ATTRIB, OBJ_KEYWORDS, q->like(query));
    break;
  }
  object result = q->run_async();
  result->processFunc = search_finished;
  return result;
}

string publish(string publishXML)
{
}

