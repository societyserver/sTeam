inherit "../client/client_base";
inherit "base/xml_data";

import xml;

#include <coal.h>
#include <macros.h>
#include <classes.h>
#include <client.h>

static int     iDepth;
static string outPath;
static int    withAnn;

static mapping mUsers, mGroups, mObjects, mExclude;

mapping mSwitches = ([]);

void handle_error(mixed err)
{
    Stdio.append_file("export_errors.log", sprintf("-------\n%s%O\n", ctime(time()), err));
}

string compose_scalar(mixed s) 
{
  if ( objectp(s) ) {
    string type, name;
    if ( s->get_object_class() & CLASS_USER ) {
      type = "User";
      name = s->get_identifier();
      mUsers[s] = 1;
    }
    else if ( s->get_object_class() & CLASS_GROUP ) {
      type = "Group";
      name = s->get_identifier();
      mGroups[s] = 1;
    }
    else if ( s->get_object_class() & CLASS_MODULE ) {
      type = "Module";
      name = s->get_identifier();
    }
    else {
      type = "Path";

      int oid = set_object(s);
      object env = send_cmd(s, "get_environment");
      if ( !objectp(env) ) {
	  mObjects[s] = 1;
	  return "<object><type>ID</type><id>"+s->get_object_id() + 
	      "</id></object>\n";
      }
      name = send_cmd(mVariables["filepath:tree"], "object_to_filename", 
		      ({ s }));
    }
    return "<object><type>"+type+"</type><id><![CDATA["+name+"]]></id></object>";
  }
  else
    return ::compose_scalar(s);
}

void update_content(object obj, string path)
{
  if ( Stdio.exist(path) )
    return;
  string content = send_cmd(obj, "get_content", ({ }));

  if ( !stringp(content) )
      return;
  // create the directory structure !
  string dir;

  array tokens = (path/"/");
  dir = tokens[..sizeof(tokens)-2]*"/";
  Stdio.mkdirhier(dir);

  Stdio.File f = Stdio.File(path, "wct");
  f->write(content);
  f->close();
}

void obj_from_server(object obj, string path) 
{
    Stdio.File xml = Stdio.File(path + "._xml_", "wct");
    
    set_object(obj);
  
    xml->write("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"+
	       "<Object class=\""+
	       obj->get_object_class()+"\">\n");
    
    mapping attributes = send_cmd(obj, "query_attributes");
    foreach(indices(attributes), string|int a) {
      if ( !stringp(attributes[a]) )
	continue;
      if ( !utf8_check(attributes[a]) )
	attributes[a] = string_to_utf8(attributes[a]);
    }
    xml->write("<attributes>\n"+compose_struct(attributes)+ "</attributes>\n");
    mapping acquire_map = send_cmd(obj, "get_acquired_attributes");
    xml->write("<attributes-acquire>\n"+
	       compose_struct(acquire_map) + "\n</attributes-acquire>\n");
    mapping a_lock = ([ ]);
    foreach(indices(attributes), mixed idx) {
	a_lock[idx] = send_cmd(obj, "is_locked", ({ idx }) );

    }
    xml->write("<attributes-locked>\n"+
	       compose_struct(a_lock) + "\n</attributes-locked>\n");
    
    mapping sanction  = send_cmd(obj, "get_sanction" );
    mapping msanction = send_cmd(obj, "get_meta_sanction" );
    
    if ( withAnn && !(obj->get_object_class() & CLASS_USER) ) {
	array(object) annotations = send_cmd(obj, "get_annotations");
	xml->write("<annotations>"+compose(annotations) + "</annotations>\n");
	foreach(annotations, object ann)
	    annotation_from_server(ann);
    }
    if ( obj->get_object_class() & CLASS_USER ) {
	array(object) groups = send_cmd(obj, "get_groups");
	xml->write("<groups>"+compose_array(groups) + "</groups>\n");
	string pw = send_cmd(obj, "get_user_password");
	xml->write("<password>"+pw +"</password>\n");
    }
    if ( obj->get_object_class() & CLASS_LINK && objectp(obj->get_link_object()))
      xml->write("<linkto>"+mVariables["filepath:tree"]->object_to_filename(obj->get_link_object()) + "</linkto>\n");

    xml->write("<sanction>\n"+compose_struct(sanction) + "</sanction>\n");
    xml->write("<sanction-meta>\n"+compose_struct(msanction)+
	       "</sanction-meta>\n");
    xml->write("<acquire>\n"+compose(send_cmd(obj, "get_acquire"))+
	       "</acquire>\n");
    object creator = send_cmd(obj, "get_creator");
    xml->write("<creator>"+compose(creator)+"</creator>\n");
    xml->write("</Object>\n");
    xml->close();
}

void annotation_from_server(object ann) 
{
    werror("Checking out " + ann->get_identifier() +"["+ann->get_object_id()+
	   "]\n");
    string path = outPath + "/__objects__";
    Stdio.mkdirhier(path);
    obj_from_server(ann, path + "/" + ann->get_object_id());
    update_content(ann, path + "/" + ann->get_object_id());
}

void store_meta(object obj, string subpath, array inventory)
{
    Stdio.mkdirhier(outPath + subpath);
  
    Stdio.File xml = Stdio.File(outPath + subpath + "/__steam__.xml", "wct");
    xml->write("<?xml version='1.0' encoding='utf-8'?>\n"+
	       "<folder name='"+string_to_utf8(subpath)+"'>\n"+
	       "  <server>\n"+
	       "    <adress>"+mSwitches->server+"</adress>\n"+
	       "    <port>"+mSwitches->port+"</port>\n"+
	       "    <checkout>"+mSwitches->checkout + "</checkout>\n"+
	       "  </server>\n\n");
    xml->write("  <files>\n");
    foreach(inventory, object o ) {
      if ( !objectp(o) )
	continue;
        string id = o->get_identifier();
	if ( !stringp(id) )
	  continue;
	id = replace(id, "&", "und");
	if ( o->get_object_class() & CLASS_DRAWING )
	    id = "_"+o->get_object_id()+"_";
	xml->write("    <file>" + id + "</file>\n");
    }
    xml->write("  </files>\n</folder>");
    
}

string readable_filename(string fname)
{
  if ( !stringp(fname) )
    return "__unknown__";
  fname = replace(fname, ({ "&"}), ({ "und"}));
  return utf8_to_string(fname);
}

void object_from_server(object obj, string subpath, int|void d)
{
  if ( !objectp(obj) )
    return;
  if ( obj->get_object_class() & CLASS_USER || obj->get_object_class() & CLASS_SCRIPT )
    return;

  if ( mExclude[subpath] == 1 ) {
      return;
  }

  string path = send_cmd(mVariables["filepath:tree"], 
			     "object_to_filename", ({ obj }));
  string id = send_cmd(obj, "get_identifier");
 
  id = readable_filename(id);
  if ( obj->get_object_class() & CLASS_DOCUMENT )
      update_content(obj, outPath + subpath + "/" + id);
  else if ( obj->get_object_class() & CLASS_DRAWING )
      id = "_"+obj->get_object_id()+"_";

  path = outPath + subpath + "/" + id;

  // create the directory structure !
  string dir;
  array tokens = (path/"/");
  dir = tokens[..sizeof(tokens)-2]*"/";
  Stdio.mkdirhier(dir);

  werror("Checking out " + path);
  // now write xml for the object
  obj_from_server(obj, path);
  werror("... ok\n");
  array inv;
  
  if ( obj->get_object_class() & CLASS_CONTAINER && (iDepth==0 || d < iDepth))
  {
      inv = send_cmd(obj, "get_inventory");
      foreach(inv, object o)
	  object_from_server(o, subpath + "/" + readable_filename(obj->get_identifier()), d+1);
  }
  if ( arrayp(inv) && sizeof(inv) > 0 )
    store_meta(obj, subpath + "/" + readable_filename(obj->get_identifier()), inv);

}

string group_to_string(object grp)
{
  return grp->get_identifier();
}

void store_group(string group) 
{
    object grp;
    if ( (int)group > 0 ) {
      grp = send_cmd((int)group, "this");
      group = grp->get_identifier();
    }
    else
      grp = send_cmd(mVariables["groups"], "lookup", group);
    array users = send_cmd(grp, "get_members");
    do_store_groups(users, grp, group);
}

void do_store_groups(array groups, object grp, string group)
{    

  Stdio.File f;
  Stdio.mkdirhier(outPath);
  werror("Exporting Group %s\n", group);
  f = Stdio.File(outPath+"/__group_"+group+"__.xml", "wct");
  f->write("<?xml version='1.0' encoding='utf-8'?>\n");
  f->write("<group identifier=\""+group+"\" name=\""+
	   grp->query_attribute("OBJ_NAME")+"\">\n");
  foreach(groups, object g) {
    if ( !objectp(g) )
      continue;
    if ( g->get_object_class() & CLASS_GROUP ) {
      f->write("  <subgroup name=\""+g->query_attribute("OBJ_NAME")+"\">"+
	       g->get_identifier()+ "</subgroup>\n");
    }
    else if ( grp->is_admin(g) )
      f->write("  <member admin='true'>"+g->get_identifier()+ "</member>\n");
    else
      f->write("  <member>"+g->get_identifier()+ "</member>\n");
  }
  f->write("</group>\n");
  f->close();
  foreach(groups, object grp) 
    if ( grp->get_object_class() & CLASS_GROUP )
      do_store_groups(grp->get_members(), grp, grp->get_identifier());
}

void store_users(string group)
{
    object grp = send_cmd(mVariables["groups"], "lookup", group);
    array users = send_cmd(grp, "get_members");
    do_store_users(users, group);
}

void do_store_users(array users, void|string group)
{
    Stdio.File f;

    if ( !stringp(group) )
      group = "steam";

    Stdio.mkdirhier(outPath);
    werror("writing %s\n", outPath+"/__users__.xml");
    f = Stdio.File(outPath+"/__users__.xml", "wct");
    f->write("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    f->write("<users group='"+group+"'>\n");
    foreach(users, object u) {
        mapping attr;
	if ( !objectp(u) )
	  continue;
	object user = u;
	if ( u->get_object_class() & CLASS_GROUP )
	    continue;
	
	attr = send_cmd(user, "query_attributes", 
#if 1
			([ 
			    "OBJ_NAME":1,
			    "USER_FIRSTNAME":1,
			    "USER_FULLNAME":1,
			    "USER_EMAIL":1,
			    "OBJ_DESC":1,
			    "USER_ADRESS": 1,
			    ])
	    );
#else
			([ 
			    102: 1,
			    612:1,
			    616:1,
			    104:1,
			    611: 1,
			    ])
	    );
	attr["OBJ_NAME"] = attr[102];
	attr["USER_EMAIL"] = attr[616];
	attr["USER_FULLNAME"] = string_to_utf8(attr[612]);
	attr["OBJ_DESC"] = attr[104] || "";
	attr["OBJ_DESC"] = string_to_utf8(attr->OBJ_DESC);
	attr["USER_FISTNAME"] = "";
#endif		      

	string pw = send_cmd(user, "get_user_password");
	array groups = send_cmd(user, "get_groups");
	f->write(" <user>\n"+
		 "   <nickname>"+attr->OBJ_NAME+"</nickname>\n"+
		 "   <firstname>"+attr->USER_FIRSTNAME+"</firstname>\n"+
		 "   <fullname>"+attr->USER_FULLNAME+"</fullname>\n"+
		 "   <pw>"+pw+"</pw>\n"+
		 "   <email>"+attr->USER_EMAIL+"</email>\n"+
		 "   <description>"+attr->OBJ_DESC+"</description>\n"+
		 "   <contact>"+attr->USER_ADRESS+"</contact>\n");
	foreach(groups, object grp) 
	  if ( objectp(grp) )
	    f->write("   <group>"+grp->get_identifier()+"</group>\n");
	
	f->write(" </user>\n");
    }
	
    f->write("</users>\n");
    f->close();
}

void store_users_and_groups()
{
    Stdio.File f;
    string path;
    path = outPath + "/__groups__/";

    Stdio.mkdirhier(path);
    
    f = Stdio.File(path+"users.xml", "wct");
    f->write("<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>\n<users>\n");
    f->write(compose(indices(mUsers)));
    f->write("</users>\n");
    f->close();
    foreach(indices(mUsers), object u) {
	obj_from_server(u, path + u->get_identifier());
    }
    f = Stdio.File(path+"groups.xml", "wct");
    f->write("<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>\n<groups>\n");
    f->write(compose(indices(mGroups)));
    f->write("</groups>\n");
    f->close();
    foreach(indices(mGroups), object g) {
	obj_from_server(g, path + g->get_identifier());
    }
}

void store_objects() 
{
    string path;

    path = outPath + "/__objects__/";
    Stdio.mkdirhier(path);
    
    foreach(indices(mObjects), object o) {
	set_object(o);
	if ( o->get_object_class() & CLASS_DOCUMENT ) 
	    update_content(o, path + o->get_object_id());
	obj_from_server(o, path  + o->get_object_id());
    }
}

array get_all_rooms(array groups)
{
  array rooms = ({ });
  foreach(groups, object member) {
    if ( member->get_object_class() & CLASS_GROUP ) {
      rooms += ({ send_cmd(member, "query_attribute", "GROUP_WORKROOM") });
      rooms += get_all_rooms(member->get_members());
    }
  }
  return rooms;
}

array get_all_users(object grp)
{
  array users = ({ });
  array u = send_cmd(grp, "get_members");
  foreach(u, object user) {
    if ( user->get_object_class() & CLASS_USER )
      users += ({ user });
    else if ( user->get_object_class() & CLASS_GROUP )
      users += get_all_users(user);
  }
  return users;
}

void room_from_server(object start, void|string pos)
{
  if ( !stringp(pos) )
    pos = "";
  array inv = send_cmd(start, "get_inventory");
  werror("room_from_server, %O\n", start);
  foreach(inv, object o)
    object_from_server(o, pos, 0);
  store_meta(start, pos, inv);
}

int main(int argc, array(string) argv)
{
  int            port = 1900;
  string server= "localhost";
  string directory = "/";

  string user = "root";
  string pw   = "steam";
  int i;


  mUsers   = ([ ]);
  mGroups  = ([ ]);
  mObjects = ([ ]);
  mExclude = ([ ]);

  outPath = "export";
  withAnn = 0;

  if ( search(argv, "--help") >= 0 ) {
      werror("sTeam export tool. Options are:\n"+
	     "--server= specify the server.\n"+
	     "--port= server port (COAL).\n"+
	     "--in=Directory to export from on server.\n"+
	     "--out=Directory to store the exported files.\n"+
	     "--depth=How many levels of containers/rooms should be exported?\n");
      return 0;
  }

  for ( i = 1; i < sizeof(argv); i++ ) {
      string cmd, arg;
      if ( sscanf(argv[i], "--%s=%s", cmd, arg) == 2 ||
	   sscanf(argv[i], "--%s", cmd) == 1 ) 
	  {
	    if (  stringp(arg) && strlen(arg) > 0 )
	      sscanf(arg, "\"%s\"", arg);
	      
	    switch ( cmd ) {
		case "server":
		    server = arg;
		    break;
		case "port":
		    port = (int) arg;
		    break;
		case "in":
		    directory = arg;
		    break;
		case "depth":
		    iDepth = (int)arg;
		    break;
	        case "user": // checkout user of group
		    mSwitches->user = arg;
		    break;
	        case "group": // checkout user of group
		    mSwitches->group = arg;
		    break;
		case "out":
		    outPath = arg;
		    break;
	        case "exclude":
		    mExclude[arg] = 1;
		    break;
		case "with-annotations":
		    withAnn = 1;
		    break;
		case "help":
		    write("Usage is export "+
			  "--in=<server-path> --out=<export-path>\n");
		    break;
		default:
		    werror(sprintf("Unknown parameter %s\n", argv[i]));
		    break;
	    }
      }
  }
  werror("Connecting "+server+":"+port+"\n");
  if ( connect_server(server, port) ) {
    if ( outPath[-1] == '/' )
	outPath = outPath[..strlen(outPath)-2];
    
    Stdio.mkdirhier(outPath);
    werror("Exporting to " + outPath + "\n");

    mSwitches->server = server;
    mSwitches->port = port;
    mSwitches->checkout = directory;



    Stdio.Readline rl = Stdio.Readline();
    string iuser = rl->read("User ? ["+ user + "]: ");
    string ipw = rl->read("Password ? ["+pw+"]: ");
    if ( iuser != "" ) user = iuser;
    if ( ipw != "" ) pw = ipw;

    
    login(user, pw, CLIENT_STATUS_CONNECTED, "ftp");
    // now get the inventory from the root room

    if ( mSwitches->user ) {
	store_users(mSwitches->user );
	return 0;
    }
    if ( mSwitches->group ) {
      store_group(mSwitches->group);
      return 0;
    }

    object start = mVariables["rootroom"];
    object group = send_cmd(mVariables["groups"], "lookup", directory);
    if ( (int)directory > 0 ) {
	int dir = (int)directory;
	set_object(dir);
	start = send_cmd(dir, "this");
    }
    else if ( directory == "all" ) {
      start = mVariables["groups"];
    }
    else if ( directory == "all" ) {
      start = mVariables["groups"];
    }
    else if ( objectp(group) )
      start = group;
    else if ( directory != "/" ) {
	int oid = set_object(mVariables["filepath:tree"]);
	start = send_command(COAL_COMMAND, ({ "path_to_object", 
						  ({ directory }), }));
    }
    array(string) excludes = indices(mExclude);
    foreach(excludes, string ex) {
	mExclude["/"+start->get_identifier() + "/" + ex] = 1;
	werror("Excluding directory:"+ex + "\n");
	m_delete(mExclude, ex);
    }
    if ( !objectp(start) ) {
	werror("Start Directory not found !");
	return 1;
    }
    if ( directory == "all" ) {
      array members = send_cmd(start, "get_groups");
      array rooms = ({ });
      mapping workrooms = ([ ]);

      foreach(members, object member) {
	object grp_wr = send_cmd(member, "query_attribute", "GROUP_WORKROOM");
	if ( objectp(grp_wr) )
	  rooms += ({ grp_wr });
      }
      object steam = send_cmd(start, "lookup", "steam");
      array users = send_cmd(steam, "get_members");
      do_store_users(users);
      foreach(rooms, object room) {
	workrooms[send_cmd(room, "get_creator")] = room;
	room_from_server(room, "/"+room->get_identifier());
	Stdio.File f = Stdio.File(outPath+"/__steam__.xml", "wct");
	f->write("<?xml version='1.0' encoding='utf-8'?>\n<groups>");
	foreach(indices(workrooms), object grp) {
	  f->write("<group name='"+grp->get_identifier()+"'>"+
		   workrooms[grp]->get_identifier()+"</group>\n");
	}
	f->write("</groups>");
	f->close();
      }
    }
    if ( directory == "all" ) {
      array members = send_cmd(start, "get_groups");
      array rooms = ({ });
      mapping workrooms = ([ ]);

      foreach(members, object member) {
	object grp_wr = send_cmd(member, "query_attribute", "GROUP_WORKROOM");
	if ( objectp(grp_wr) )
	  rooms += ({ grp_wr });
      }
      object steam = send_cmd(start, "lookup", "steam");
      array users = send_cmd(steam, "get_members");
      do_store_users(users);
      foreach(rooms, object room) {
	workrooms[send_cmd(room, "get_creator")] = room;
	room_from_server(room, "/"+room->get_identifier());
	Stdio.File f = Stdio.File(outPath+"/__steam__.xml", "wct");
	f->write("<?xml version='1.0' encoding='utf-8'?>\n<groups>");
	foreach(indices(workrooms), object grp) {
	  f->write("<group name='"+grp->get_identifier()+"'>"+
		   workrooms[grp]->get_identifier()+"</group>\n");
	}
	f->write("</groups>");
	f->close();
      }
    }
    if ( start->get_object_class() & CLASS_GROUP ) {
      //export group structures
      array members = send_cmd(start, "get_members");
      array rooms = ({ send_cmd(start,"query_attribute","GROUP_WORKROOM")});
      array users = get_all_users(start);
      do_store_users(users);
      rooms += get_all_rooms(members);
      mapping workrooms = ([ ]);
      foreach(rooms, object room) {
	workrooms[send_cmd(room, "get_creator")] = room;
	room_from_server(room, "/"+room->get_identifier());
	Stdio.File f = Stdio.File(outPath+"/__steam__.xml", "wct");
	f->write("<?xml version='1.0' encoding='utf-8'?>\n<groups>");
	foreach(indices(workrooms), object grp) {
	  f->write("<group name='"+grp->get_identifier()+"'>"+
		   workrooms[grp]->get_identifier()+"</group>\n");
	}
	f->write("</groups>");
	f->close();
      }
    }
    else {
      room_from_server(start);
    }
      
    store_users_and_groups();
    store_objects();
  }
  else
    werror("Failed to connect\n");
  return 0;
}

