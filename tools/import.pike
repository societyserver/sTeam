inherit "../client/client_base";
inherit "base/xml_parser";
inherit "base/xml_data";

#include <coal.h>
#include <macros.h>
#include <classes.h>
#include <client.h>
#include <access.h>

#define WARNING(s) werror(s)
#define MESSAGE(s, args...) werror(s+"\n", args);

static string      sDirectory;
static mapping      mSwitches;
static mapping       mObjects;
static array(object) aObjects; // array of created objects
mapping mAttributes = ([ ]);

Stdio.File creatorLog = Stdio.File("creators.log", "wct");

mapping xmlMap(NodeXML n)
{
  mapping res = ([ ]);
  foreach ( n->children, NodeXML children) {
    if ( children->name == "member" ) {
      mixed key,value;
      foreach(children->children, object o) {

	if ( o->name == "key" )
	  key = unserialize(o->children[0]);
	else if ( o->name == "value" )
	  value = unserialize(o->children[0]);
      }
      res[key] = value;
    }
  }
  return res;
}

array xmlArray(NodeXML n)
{
  array res = ({ });
  foreach ( n->children, NodeXML children) {
    res += ({ unserialize(children) });
  }
  return res;
}

object create_object(string id, string path)
{
    object     obj;
    Stdio.File   f;

    MESSAGE("Creating object id="+id);
    
    
    mixed err = catch {
	f = Stdio.File(sDirectory + "/__objects__/"+id+"._xml_", "r");
    };
    
    if ( err != 0 || !objectp(f) ) {
        werror("Warning: Failed to find %s\n", id+".xml");
	return 0;
    }
    

    string xml = f->read();
    f->close();
  
    NodeXML n = parse_data(xml);
    set_object(0);
    int clnum = (int)n->get_node("/Object")->attributes["class"];
    object factory = send_command(COAL_COMMAND, ({ "get_factory", ({
      clnum })  }) );
    set_object(factory);
    object linkto = n->get_node("/Object/linkto");
    mapping vars = ([ "name": "import", ]);
    if ( objectp(linkto) ) {
      object lt = mVariables["filepath:tree"]->path_to_object(linkto->data);
      if ( clnum & CLASS_EXIT )
	vars["exit_to"] = lt;
      else
	vars["link_to"] = lt;
    }
    obj = send_command(COAL_COMMAND, ({ "execute", ({ vars }) }) );
    mObjects[id] = obj;
    aObjects += ({ obj });

    err = catch {
	f = Stdio.File(sDirectory + "/__objects__/"+id, "r");
	if ( objectp(f) ) {
	    werror("Uploading Document");
	    send_cmd(obj, "set_content", ({ f->read() }) , 1);
	    f->close();
	    werror(".... finished.\n");
	}
    };
    object_to_server(obj, path + "objects/"+id, n);
   
    return obj;
}

void create_groups()
{
    Stdio.File f;
    mixed err = catch {
	f = Stdio.File(sDirectory + "/groups/groups.xml", "r");
    };
    if ( err != 0 || !objectp(f) )
	return;
    NodeXML n = parse_data(f->read());
    f->close();
    foreach(n->get_node("/groups/array")->get_nodes("object"), NodeXML g) {
	object      grp;
	string grp_name;

	MESSAGE("Group:" + g->get_node("id")->data);
	grp_name = g->get_node("id")->data;
	set_object(mVariables["groups"]);
	grp = send_command(COAL_COMMAND, ({ "lookup", ({ grp_name }) }));
	if ( !objectp(grp) ) {
	    MESSAGE("Creating: " + grp_name);
	    set_object(mVariables["Group.factory"]);
	    grp = send_command(COAL_COMMAND, 
			       ({ "execute", ({([ "name": grp_name, ]) }) }) );
	    aObjects += ({ grp });
	}
	else {
	    MESSAGE("Skipping " + grp_name + " ... group exists !");
	}

    }
}

object create_group(string name, string|object parent)
{
  object factory = mVariables["Group.factory"];
  if ( stringp(parent) )
    parent = mVariables->groups->lookup(parent);
  werror("Creating group %s, parent=%O\n", name, parent);
  object group = factory->execute( ([ 
    "name": name, 
    "parentgroup": parent, ]) );
  return group;
}

object import_groups(string fname)
{
  Stdio.File f;
  mixed err = catch {
    f = Stdio.File(fname, "r");
  };
  if ( err != 0 || !objectp(f) ) {
    werror("Fatal: cannot read %s\n", fname);
    return 0;
  }
  string str = f->read();
  NodeXML n;
  err = catch {
    n = parse_data(str);
  };
  f->close();
  object grp = n->get_node("/group");
  string grpname = grp->attributes->name;
  string identifier = grp->attributes->identifier;
  werror("Looking up group %s\n", identifier);
  object group = mVariables["groups"]->lookup(identifier);
  array grps = identifier / ".";
  string parent;
  if ( sizeof(grps) > 2 ) {
    parent = grps[..sizeof(grps)-2] * ".";
  }
  else
    sscanf(identifier, "%s.%*s", parent);
  
  werror("Importing group " + grpname + " ... ");
  if ( !objectp(group) ) {
    group = create_group(grpname, parent);
    werror("created!\n");
  }
  else
    werror("found on server.\n");
  
  foreach(grp->get_nodes("member"), object m) {
    object user = mVariables->users->lookup(m->data);
    if ( objectp(user) ) {
      group->add_member(user);
      if ( mappingp(m->attributes) && m->attributes->admin )
	group->sanction_object(user, SANCTION_INSERT|SANCTION_MOVE|SANCTION_WRITE);
    }
  }
  string path = dirname(fname);
  foreach(grp->get_nodes("subgroup"), object sg) {
    object g = import_groups(path+"/__group_"+sg->data+"__.xml");
    group->add_member(g);
  }
  if ( mSwitches->rooms ) {
    object wr = group->query_attribute("GROUP_WORKROOM");
    string wrname = wr->get_identifier();
    werror("Checking for %s in %s ...", wrname, path);
    if ( Stdio.exist(path + "/" + wrname) ) {
      werror("yes.\n");
      sDirectory = path;
      container_to_server(wr, path+"/"+wrname, wrname);
    }
    else
      werror("no.\n");
  }
  return group;
}

void import_users(string fname)
{
   Stdio.File f;
    mixed err = catch {
	f = Stdio.File(fname, "r");
    };
    if ( err != 0 || !objectp(f) )
	return;
    string str = f->read();
    NodeXML n;
    err = catch {
      n = parse_data(str);
    };
    f->close();
    string grp = n->get_node("/users")->attributes->group;
    object group = send_cmd(mVariables->groups, "lookup", grp);

    foreach(n->get_nodes("/users/user"), object u) {
        if ( u->get_node("nickname")->data == "0" )
	  continue;
	mapping attr = ([ ]);
	foreach(u->get_children(), object s) {
	    if ( stringp(s->data) && s->data != "0" )
		attr[s->name] = s->data;
	}
	object user = send_cmd(mVariables["users"],"lookup", u->get_node("nickname")->data);
	werror("Importing %s ... ", u->get_node("nickname")->data);
	if ( !xml.utf8_check(lower_case(attr->nickname)) || search(attr->nickname, " ") >= 0 || !stringp(attr->pw)) {
	  werror(" name not utf-8....\n");
	  continue;
	}
	if ( !objectp(user) ) {
	    user = send_cmd(mVariables["User.factory"], "execute", attr);
	    werror("New User!\n");
	}
	else
	  werror("exists...\n");
	send_cmd(user, "set_user_password", ({ attr["pw"], 1}) );
	send_cmd(user, "activate_user");    
	if ( objectp(group) )
	  send_cmd(group, "add_member", user);
    }

}

void create_users()
{
    Stdio.File f;
    mixed err = catch {
	f = Stdio.File(sDirectory + "/groups/users.xml", "r");
    };
    if ( err != 0 || !objectp(f) )
	return;
    NodeXML n = parse_data(f->read());
    f->close();
    foreach(n->get_node("/users/array")->get_nodes("object"), NodeXML u) {
	object      user;
	string user_name;

	MESSAGE("User:" + u->get_node("id")->data);
	user_name = u->get_node("id")->data;
	f = Stdio.File(sDirectory + "/groups/"+user_name+".xml", "r");
	NodeXML user_n = parse_data(f->read());
	f->close();

	set_object(mVariables["users"]);
	user = send_command(COAL_COMMAND, ({ "lookup", ({ user_name }) }));
	if ( !objectp(user) ) {
	    MESSAGE("Creating: " + user_name);
	    set_object(mVariables["User.factory"]);
	    user = send_command(COAL_COMMAND, 
				({ "execute", ({([ "name": user_name,
				   "pw":user_n->get_node(
				       "/Object/password")->data,
						 ]) })}));
	    object_to_server(user, sDirectory + "/groups/"+user_name);
	    aObjects += ({ user });
	}
	else {
	    MESSAGE("Skipping " + user_name + " - user exists !");
	}
    }
}


mixed unserialize(NodeXML n) 
{
  switch ( n->name ) {
  case "struct":
    return xmlMap(n);
    break;
  case "array":
    return xmlArray(n);
    break;
  case "int":
    return (int)n->data;
    break;
  case "float":
    return (float)n->data;
    break;
  case "string":
    return n->data;
    break;
  case "object":
    string type = n->children[0]->data;
    string id = n->children[1]->data;
    object obj;
    int    oid;
    
    switch(type) {
    case "Group":
      oid = set_object(mVariables["groups"]);
      break;
    case "User":
      oid = set_object(mVariables["users"]);
      break;
    case "Module":
	oid = set_object(0); // set the object to _Server
	obj = send_command(COAL_COMMAND, ({ "get_module", ({ id }) }));
	if ( !objectp(obj) )
	    WARNING("Failed to find module " +id + " on target server !");
	set_object(oid);
	return obj;
	break;
    case "ID":
	if ( objectp(mObjects[id]) )
	    return mObjects[id];
	return create_object(id, sDirectory+"/objects");
	break;
    default:
      oid = set_object(mVariables["filepath:tree"]);
      obj = send_command(COAL_COMMAND, ({ "path_to_object", ({ id }) }));
      if ( !objectp(obj) )
	  WARNING("Failed to find path " +id + " on target server !\n");
      set_object(oid);
      return obj;
      break;
    }
    obj = send_command(COAL_COMMAND, ({ "lookup", ({ id }) }));
    
    set_object(oid);
    return obj;
  }
  return 0;
}
  
array read_meta(string path)
{
    Stdio.File f = Stdio.File(path + "/__steam__.xml", "r");
    string meta = f->read();
    f->close();
    NodeXML n = parse_data(meta);
    n = n->get_node("/folder/files");
    array nodes = n->get_nodes("file");
    array res = ({ });
    foreach(nodes, object node) {
	res += ({ node->get_data() });
    }
    return res;
}

void container_to_server(object obj, string directory, string path)
{
    object o;
    if ( obj->get_object_class() & CLASS_USER )
	return;
    array(string) dir = get_dir(directory);
    dir = read_meta(directory);
    foreach(dir, string fname) {
	if ( fname == "xml" || fname == "files" ) continue;
	fname = utf8_to_string(fname);
	NodeXML n;
	Stdio.File f;
	mixed err = catch {
	    f = Stdio.File(sDirectory + "/" +path + "/" + fname+"._xml_","r");
	    if ( !objectp(f) )
	      f = Stdio.File(sDirectory + "/" +path + "/" + fname+".xml","r");
	};
	if ( arrayp(err) ) {
	    werror("Failed to load file %s\n%O\n", fname, err);
	}
	// if the file does not exist its not part of the reference 
	// server installation
	if ( !objectp(f) )
	    continue;

	string xml = f->read();
	f->close();

	n = parse_data(xml);

	
	// is that object already on the server ?
	o = send_cmd(obj, "get_object_byname", string_to_utf8(fname));
	
	if ( Stdio.is_dir(directory + "/" + fname) ) {
	    werror("- Directory:"+fname+":");
	    
	    int cl = (int)n->attributes["class"];
	    
	    if ( !objectp(o) ) {
		if ( mSwitches->test ) {
		    werror("Missing: " + fname + "\n");
		    continue;
		}
		werror("Creating container/room: " + fname+"\n");

		set_object(send_cmd(0, "get_factory", cl));
		o = send_command(COAL_COMMAND, ({ "execute", ({ 
		    ([ "name": string_to_utf8(fname), ]) }) }));
		aObjects += ({ o });
		send_cmd(o, "move", obj, 1);
		object_to_server(o, sDirectory + path +"/"+ fname, n);
	    }
	    container_to_server(o, directory + "/"+ fname, path +"/"+fname);
	}
	else if ( !Stdio.exist(directory + "/" + fname) ) {
	    // no document
	    int classid = (int)(n->get_node("/Object")->attributes->class);
	    werror("Object class = %d\n", classid);
	    object factory = send_cmd(0, "get_factory", classid);
	    if ( classid & 256 ) 
		o = send_cmd(factory, "execute", ([ "name":string_to_utf8(fname), "url":"http://www.dummy.de",]));
	    else
	        o = send_cmd(factory, "execute", ([ "name":string_to_utf8(fname), ]));

	    send_cmd(o, "move", obj);
	    object_to_server(o, sDirectory+path+"/"+fname, n);
	}
	else {
	    f = Stdio.File(directory + "/" + fname, "r");
	    werror("- File:"+fname+":");
	    if ( !objectp(o) ) {
		if ( mSwitches->test ) {
		    werror("Missing!!!\n");
		    continue;
		}
		o = send_cmd(mVariables["Document.factory"], "execute",
			     ([ 
			       "name": string_to_utf8(fname), 
			       "move":obj, ]) );
		send_cmd(o, "move", obj);
		if ( !objectp(o) ) {
		    werror("Failed to create document !");
		    continue;
		}
		aObjects += ({ o });
		object_to_server(o, sDirectory + path +"/"+ fname, n);
	    }
	    if ( !mSwitches->test ) {
		send_cmd(o, "set_content", ({ f->read() }), 1);
		if ( mSwitches->update ) {
		    object_to_server(o, sDirectory + path + "/" + fname, n);
		}
	    }
	    else {
		werror(" found. Skipping upload.\n");
	    }
	    f->close();
	}
    }
}

object annotation_to_server(NodeXML ann, string path)
{
  return create_object(ann->get_node("id")->data, path);
}


int handle_error(mixed err)
{
    return 0;
}
	
void object_to_server(object obj, string path, NodeXML|void n) 
{
    MESSAGE("reading... " + path+".xml");
    set_object(obj);
    if ( !objectp(n) ) {
	Stdio.File f;
	mixed err = catch {
	    f = Stdio.File(path + ".xml", "r");
	};
	// if the file does not exist its not part of the reference 
	// server installation
	if ( !objectp(f) ) {
  	    werror("Not found !\n");
	    return;
	}
	string xml = f->read();
	f->close();
	n = parse_data(xml);
    }
    mapping attributes = xmlMap(n->get_node("/Object/attributes/struct"));
    mapping a_acquire = xmlMap(
	n->get_node("/Object/attributes-acquire/struct"));
    mapping sanction = xmlMap(n->get_node("/Object/sanction/struct"));
    mapping msanction = xmlMap(n->get_node("/Object/sanction-meta/struct"));
    mixed acquire = unserialize(n->get_node("/Object/acquire")->children[0]);
    mapping a_lock = xmlMap(n->get_node("/Object/attributes-locked/struct"));
    
    
    if ( obj->get_object_class() & CLASS_USER ) {
	array(object) groups = 
	    unserialize(n->get_node("/Object/groups/array"));
	foreach(groups, object grp) {
	    send_cmd(grp, "add_member", obj, 1);
	}
    }
    if ( obj->get_object_class() & CLASS_LINK && objectp(n->get_node("/Object/linkto")) ) 
    {
      string link = n->get_node("/Object/linkto")->data;
	
      if ( stringp(link) ) {
	object lnk = mVariables["filepath:tree"]->path_to_object(link);
	if ( objectp(lnk) )
	  obj->set_link_object(lnk);
	else
	  werror("Cannot resolve the link %s\n", link);
      }
      else
	werror("Link not found %O\n", n->get_node("/Object/linkto"));
    }
    foreach(indices(sanction), object sanc) {
	if ( objectp(sanc) ) {
	    send_cmd(obj, "sanction_object", ({ sanc, sanction[sanc] }), 1 );
	}
    }
    foreach(indices(msanction), object msanc) {
	if ( objectp(msanc) ) {
	    send_cmd(obj, "sanction_object_meta", ({ sanction[msanc] }), 1);
	}
    }
    mixed key;
  

  
    send_cmd(obj, "unlock_attributes", ({ }), 1);
    foreach(indices(a_acquire), key) {
	if ( stringp(a_acquire[key]) ) // environment only, may not work *g*
	    send_cmd(obj, "set_acquire_attribute", ({ key, 1 }), 1);
	else
	    send_cmd(obj, "set_acquire_attribute", ({ key, a_acquire[key]}),1);
    }
    foreach(indices(attributes), string key) {
	send_cmd(obj, "set_attribute", ({ key, attributes[key] }), 1);
    }
    //send_cmd(obj, "set_attributes", attributes, 1);
    foreach(indices(a_lock), key ) {
      if ( a_lock[key] != 0 ) {
	  send_cmd(obj, "lock_attribute", ({ key }), 1);
      }
    }
  
    // acquire string should be environment function, but is default setting...
    // cannot handle functions yet
    if ( objectp(acquire) )
	send_cmd(obj, "set_acquire", ({ acquire }), 1);
    mixed creator = unserialize(n->get_node("/Object/creator/object"));
    send_cmd(obj, "set_creator",({ creator }), 1);
    if ( objectp(creator) )
	creatorLog->write(obj->get_object_id() + ", creator="+creator->get_identifier()+"\n");
    NodeXML annotations = n->get_node("/Object/annotations/array");
    if ( objectp(annotations) ) {
	array(object) anns = send_cmd(obj, "get_annotations", ({ }), 1);
	// if the object already has annotations remove them !
	if ( arrayp(anns) ) {
	    foreach(anns, object a) {
		send_cmd(obj, "remove_annotation", a, 1);
	    }
	}
	werror("%d Annotations....\n", sizeof(annotations->children));
	foreach(annotations->children, NodeXML ann) {
	    object annotation = annotation_to_server(ann, dirname(path));
	    send_cmd(obj, "add_annotation", ({ annotation }), 1);
	}
    }
    foreach(indices(mAttributes), string idx) {
	
	send_cmd(obj, "set_attribute", ({ idx, mAttributes[idx] }), 1);
    }
}

int _import(string server, int port, string directory, string outPath)
{
  if ( connect_server(server, port) ) {
      string user = "root";
      string pw   = "steam";

      int t = time();
    
      Stdio.Readline rl = Stdio.Readline();
      string iuser = rl->read("User ? ["+ user + "]: ");
      string ipw = rl->read("Password ? ["+pw+"]: ");
      if ( iuser != "" ) user = iuser;
      if ( ipw != "" ) pw = ipw;
      if ( !login(user, pw, CLIENT_STATUS_CONNECTED) ) {
	error("Wrong User or Password !\n");
      }
      // now get the inventory from the root room
      if ( mSwitches->users ) {
	  import_users(mSwitches->users);
	  return 1;
      }
      if ( mSwitches->group ) {
	import_groups(mSwitches->group);
	return 1;
      }

      if ( search(mSwitches->create, "groups") >= 0 ) 
          create_groups();
      if ( search(mSwitches->create, "users") >= 0 )
          create_users();
      if ( search(mSwitches->create, "objects") >= 0 ) {
          object start = mVariables["rootroom"];
	  
	  if ( (int)directory > 0 ) {
	      int dir = (int)directory;
	      start = send_cmd(0, "find_object", dir);
	      MESSAGE("Starting with %O", start);
	  }
          else if ( directory != "/" ) {
	      int oid = set_object(mVariables["filepath:tree"]);
	      if ( (int)outPath > 0 )
		start = send_cmd((int)outPath, "this");
	      else
		start = send_command(COAL_COMMAND, ({ "path_to_object", 
						      ({ outPath }), }));
	      MESSAGE("Starting with %O", start);
	  }
	  container_to_server(start, directory, "");
      }
      // file of objects that are created during installation
      Stdio.File f = Stdio.File("install.xml", "wct"); 
      f->write(compose(aObjects));
      f->close();
      werror("\n-- finished: Import created " + sizeof(aObjects) + 
	     " new objects on server in " + (time()-t) + " seconds !\n");
  } else
  werror("Cannot connect to server !\n");
  return 0;
}


int main(int argc, array(string) argv)
{
  int            port = 1900;
  string server= "localhost";
  string directory = "/";
  int iDepth;
  string outPath = "";
  mObjects = ([ ]);
  aObjects = ({ });
  mSwitches = ([ "create": "users,groups,objects", ]);

  for ( int i = 1; i < sizeof(argv); i++ ) {
      string cmd, arg;

      if ( sscanf(argv[i], "--%s=%s", cmd, arg) >= 1 ) {
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
	    case "users":
		mSwitches["users"] = arg;
		break;
	    case "group":
	        mSwitches["group"] = arg;
		break;
	    case "rooms":
	      mSwitches["rooms"] = true;
	      break;
	    case "out":
		outPath = arg;
		break;
	    case "test":
		mSwitches["test"] = true;
		break;
	    case "update":
		mSwitches["update"] = true;
	    default:
		break;
	    }
      }
  }

  //subpath is another switch
  sDirectory = directory;
  _import(server, port, directory, outPath);
}

