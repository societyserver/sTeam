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

inherit "applauncher.pike";
#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)
#include <classes.h>

Stdio.Readline readln;
mapping options;
int flag=1,c=1;
string pw,str;
object me;

protected class StashHelp {
  inherit Tools.Hilfe;
  string help(string what) { return "Show STASH help"; }

  void exec(Evaluator e, string line, array(string) words,
      array(string) tokens) {
    line = words[1..]*" ";
    function(array(string)|string, mixed ... : void) write = e->safe_write;

          constant all = #"
list            List Gates/Exits, Documents, Containers in the current Room.
goto            Goto a Room using a full path to the Room.
title           Set your own description.
room            Describe the Room you are currently in.
look            Look around the Room.
take            Copy a object in your inventory.
gothrough       Go through a gate.
create          Create an object (File/Container/Exit). Provide the full path of the destination or a . if you want it in current folder.
delete          Delete an object. The user can delete the objects inside the current folder. User can delete objects like documents, containers and rooms.
peek            Peek through a container.
inventory(i)    List your inventory.
edit            Edit a file in the current Room.
join            Join a group.
leave           Leave a group.
send_email      Send an email to the sTeam user, user group or external email.
log             Open sTeam server log files.
hilfe           Help for Hilfe commands.
";
    switch(line) {

    case "commands":
      write(all);
      return;

                    case "list":
                        write("List Gates/Exits, Documents, Containers in the current Room.\n");
                        return;
                    case "goto":
                        write("Goto a Room using a full path to the Room.\n");
                        return;
                    case "title":
                        write("Set your own description.\n");
                        return;
                    case "room":
                        write("Describe the Room you are currently in.\n");
                        return;
                    case "look":
                        write("Look around the Room.\n");
                        return;
                    case "take":
                        write("Copy a object in your inventory.\n");
                        return;
                    case "gothrough":
                        write("Go through a gate.\n");
                        return;
 	            case "create":
                        write("Create an object (File/Container/Exit). Provide the full path of the destination or a . if you want it in current folder.\n");
                        return;
                    case "delete":
                        write("Delete an object. The user can delete the objects inside the current folder. User can delete objects like documents, containers and rooms.\n");
                        return; 
                    case "peek":
                        write("Peek through a container.\n");
                        return;
                    case "i":
                    case "inventory":
                        write("Lists your inventory\n");
                        return;
                    case "edit":
                        write("Edit a file in the current Room.\n");
                        return;
                    case "join":
      			write("Join a group.\n");
      			return;
    		    case "leave":
      			write("Leave a group.\n");
     			 return;
                    case "send_email":
                        write("Send an email to the sTeam user, user group or external email.\n");
                        return;
		    case "log":
                        write("Open sTeam server log files.\n");
   			 //Hilfe internal help
                    case "me more":
                        write(documentation_help_me_more);
                        write("Type \"hilfe\" to get more help on Hilfe commands\n");
                        return;
                    case "hilfe todo":
                        write(hilfe_todo);
                        return;
                    case "about hilfe":
                        e->print_version();
                        write(cvs_version +#"
                                Initial version written by Fredrik Hübinette 1996 - 2000
                                Rewritten by Martin Nilsson 2002
                                ");

                        return;
                    default:
                        write(stash_help_doc);
                                write(all);
                                write("\n\nEnter \"help me more\" for further Hilfe help.\n\n");
                }
    }
  
}

class Handler
{
  inherit Tools.Hilfe.Evaluator;
  inherit Tools.Hilfe;

  object p;
  void create(mapping _constants)
  {
    readln = Stdio.Readline();
    p = ((program)"tab_completion.pmod")();
    readln = p->readln;
    write=predef::write;
    ::create();
    p->load_hilferc();
    p->constants+=_constants;  //For listing sTeam commands and objects on tab
    constants = p->constants;  //For running those commands
    readln->get_input_controller()->bind("\t",p->handle_completions);
    commands->help = StashHelp();
    commands->hilfe = CommandHelp();
  }

  void add_constants(mapping a)
  {
      constants = constants + a;
  }
/*  void add_variables(mapping a)
  {
      variables = variables + a;
  }*/
}

object _Server,users;
mapping all;
string path="/";
Stdio.Readline.History readline_history;

void ping()
{
  call_out(ping, 10);
  mixed a = conn->send_command(14, 0);
  if(a=="sTeam connection lost.")
  {
      flag = 0;
      readln->set_prompt(getpath()+"~ ");
      conn = ((program)"client_base.pike")();
      conn->close();
      if(conn->connect_server(options->host, options->port))
      {
          remove_call_out(ping);
          ping();
          if(str=conn->login(options->user, pw, 1))
          {
          _Server=conn->SteamObj(0);
          users=_Server->get_module("users");
          me = users->lookup(options->user);
          handler->add_constants(assign(conn,_Server,users));
          flag=1;
          readln->set_prompt(getpath()+"> ");
          }
      }
  }
}

object handler, conn;
mapping myarray;
array(string) command_arr;

int main(int argc, array(string) argv) {

    	    options = init(argv);
            _Server = conn->SteamObj(0);
            users = _Server->get_module("users");
            me = users->lookup(options->user);
            all = assign(conn, _Server, users);
            all = all + (([
            ]));
            handler = Handler(all);
            array history = (Stdio.read_file(options->historyfile) || "") / "\n";
    	    if (history[-1] != "")
            	history += ({""});
	    readline_history = Stdio.Readline.History(512, history);
            readln->enable_history(readline_history);
            handler->add_input_line("start backend");
	    write("User: " + options->user +"\n");
            string command;
            //  Regexp.SimpleRegexp a = Regexp.SimpleRegexp("[a-zA-Z]* [\"|'][a-zA-Z _-]*[\"|']");

            if (sizeof (argv) > 1) {
	    	string cmd = "";
          	if (sizeof (argv) >= 3){
			for (int i = 1; i<sizeof (argv); i++){
	        	        if(argv[i]!=0){	        	        
					if(i==sizeof(argv)-1) 
						cmd += argv[i];
					else cmd += argv[i] +" ";
				}
	        	}
		}
		else cmd += argv[1];
                write("Command: %s",cmd);
	        write("\n");
                exec_command(cmd);
                if(cmd!="")
	                exit(0);
            }
    while ((command = readln->read(
            sprintf("%s", (handler->state->finishedp() ? getstring(1) : getstring(2)))))) {
        if (sizeof (command)) {
            Stdio.write_file(options->historyfile, readln->get_history()->encode());
                    command = String.trim_whites(command);
                    //      if(a->match(command))
                    //          command_arr = array_sscanf(command,"%s [\"|']%s[\"|']");
                    //      else
                    exec_command(command);

                    //      array hist = handler->history->status()/"\n";
                    //      if(hist)
                    //        if(search(hist[sizeof(hist)-3],"sTeam connection lost.")!=-1){
                    //          handler->write("came in here\n");
                    //          flag=0;
                    //        }
                    handler->p->set(handler->variables);

            continue;
        }
        //    else { continue; }
    }
    handler->add_input_line("exit");
}

void exec_command(string command) {
    myarray = ([
            "list" : list,
            "goto" : goto_room,
            "title" : set_title,
            "room" : desc_room,
            "look" : look,
            "take" : take,
            "gothrough" : gothrough,
	    "create" : create_ob,
            "delete" : delete,
            "peek" : peek,
            "inventory" : inventory,
            "i" : inventory,
            "edit" : editfile,
            "join" : join,
            "leave" : leave,
            "send_email" : send_email,
            "log" : open_log,
            ]);

            command_arr = command / " ";

    if (myarray[command_arr[0]]) {
        int num = sizeof (command_arr);
                mixed result = catch {
            if (num == 2)
                    myarray[command_arr[0]](command_arr[1]);
            else if (num == 3)
                    myarray[command_arr[0]](command_arr[1], command_arr[2]);
            else if (num == 1)
                    myarray[command_arr[0]]();
            else if (num == 4)
                    myarray[command_arr[0]](command_arr[1], command_arr[2], command_arr[3]);
            else
                myarray[command_arr[0]](@command_arr[1..]);
            };

        if (result != 0) {
            write(result[0]);
                    write("Wrong command.||maybe some bug.\n");
        }
    }

    else

        handler->add_input_line(command);


}
mapping init(array argv) {

    mapping options = ([ "file" : "/etc/shadow" ]);

            array opt = Getopt.find_all_options(argv, aggregate(
            ({"file", Getopt.HAS_ARG, (
        {"-f", "--file"})}),
    ({"host", Getopt.HAS_ARG, (
        {"-h", "--host"})}),
    ({"user", Getopt.HAS_ARG, (
        {"-u", "--user"})}),
    ({"port", Getopt.HAS_ARG, (
        {"-p", "--port"})}),
    ));

    options->historyfile = getenv("HOME") + "/.steam_history";

            foreach(opt, array option) {
        options[option[0]] = option[1];
    }
    if (!options->host)
            options->host = "127.0.0.1";
        if (!options->user)
                options->user = "root";
            if (!options->port)
                    options->port = 1900;
            else
                options->port = (int) options->port;

                    string server_path = "/usr/local/lib/steam";

                    master()->add_include_path(server_path + "/server/include");
                    master()->add_program_path(server_path + "/server/");
                    master()->add_program_path(server_path + "/conf/");
                    master()->add_program_path(server_path + "/spm/");
                    master()->add_program_path(server_path + "/server/net/coal/");

                    conn = ((program) "client_base.pike")();

                    int start_time = time();

                    werror("Connecting to sTeam server...\n");
                while (!conn->connect_server(options->host, options->port)) {
                    if (time() - start_time > 120) {
                        throw (({" Couldn't connect to server. Please check steam.log for details! \n", backtrace()}));
                    }
                    werror("Failed to connect... still trying ... (server running ?)\n");
                            sleep(10);
                }

    ping();
    if (lower_case(options->user) == "guest")
        return options;

            mixed err;
            int tries = 3;
            //readln->set_echo( 0 );
        do {
            pw = Input.read_password(sprintf("Password for %s@%s", options->user,
                    options->host), "steam");
                    //pw=readln->read(sprintf("passwd for %s@%s: ", options->user, options->host));
        } while ((err = catch (conn->login(options->user, pw, 1))) && --tries);
                    //readln->set_echo( 1 );

                if (err != 0) {

                    werror("Failed to log in!\nWrong Password!\n");
                            exit(1);
                }
    return options;
}

mapping assign(object conn, object _Server, object users) {

    return ([
    "_Server" : _Server,
            "get_module" : _Server->get_module,
            "get_factory" : _Server->get_factory,
            "conn" : conn,
            "find_object" : conn->find_object,
            "users" : users,
            "groups" : _Server->get_module("groups"),
            "me" : users->lookup(options->user),
            "edit" : applaunch,
	    "create" : create_object,
            "delete" : delete,
            "list" : list,
            "goto" : goto_room,
            "title" : set_title,
            "room" : desc_room,
            "look" : look,
            "take" : take,
            "gothrough" : gothrough,
            "join" : join,
            "leave" : leave,
            "send_email" : send_email,
            "log" : open_log,

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
    ]);
}

void leave(string what,void|string name)
{
  if(what=="group")
  {
    if(!stringp(name)){
        write("leave group <group name>\n");
        return;
      }
      object group = _Server->get_module("groups")->get_group(name);
      if(group == 0){
        write("The group does not exists\n");
        return;
      }
      group->remove_member(me);
  }
}

void join(string what,void|string name)
{
  if(what=="group")
  {
    if(!stringp(name)){
        write("join group <name of the group>\n");
        return;
      }
      object group = _Server->get_module("groups")->get_group(name);
      if(group == 0){
        write("The group does not exists\n");
        return;
      }
      int result = group->add_member(me);
      switch(result){
        case 1:write("Joined group "+name+"\n");
          break;
        case 0:write("Couldn't join group "+name+"\n");
          break;
        case -1:write("pending\n");
          break;
        case -2:write("pending failed");
          break;
      }
  }
}

// create new sTeam objects
// with code taken from the web script create.pike
mixed create_object(string|void objectclass, string|void name, void|mapping data, void|string desc, )
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
    case "Exit":
      if(!data->exit_from)
        return "exit_from missing";
      break;
    case "Link":
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

string getstring(int i)
{
//  write("came in here\n");
  string curpath = getpath();
  if(i==1&&flag==1)
      return curpath+"> ";
  else if(i==1&&(flag==0))
      return curpath+"~ ";
  else if(i==2&&flag==1)
      return curpath+">> ";
  else if(i==2&&(flag==0))
      return curpath+"~~ ";

}

int list(string what,string|void command)
{
  if(what==""||what==0 || what=="members")
  {
    write("Wrong usage\n");
    return 0;
  }
  else if(what=="my" && command == "groups")
  what+=command; 
  int flag=1;
  string toappend="";
  array(string) display;
  if(command=="members"){
    what+=command;
    command=what-command;
    what=what-command;
    display = get_list(what,command);
  }
  else  display = get_list(what);
  string a="";
  if(sizeof(display)==0)
    toappend = "There are no "+what+".\n";
  else if(display[0]=="Invalid command")
    write("Invalid command.\n");
  else
  { 
    flag = 0;
    if(what=="users"||what=="groups")
      toappend = "Here is a list of all " + what +".\n";
    else if(what=="mygroups")
      toappend = "Here is a list of all the groups that "+me->get_user_name() + " is member.\n";
    else if(what=="members")
      toappend = "Here is a list of all the users who are member of the group "+ command +".\n";
    else toappend = "Here is a list of all "+what+" in the current room.\n";
    foreach(display,string str)
      a+=(str+"    ");
  }
  write(toappend);
  if(flag==0){
    mapping mp = Process.run("tput cols");
    int screenwidth = (int)mp["stdout"];
    write("\n");
    write("%-$*s\n", screenwidth,a);
    write("\n");
  }  
  return 0;
}

array(string) get_list(string what,string|object|void lpath)
{
  array(string) whatlist = ({});
  object pathobj;
      if(!lpath)
       pathobj = OBJ(getpath());
      else if(stringp(lpath))
       pathobj = OBJ(lpath);
      else if(objectp(lpath))
       pathobj = lpath;
  switch (what)  
  {
    case "containers":
    {
      mixed all = pathobj->get_inventory_by_class(CLASS_CONTAINER);
      foreach(all, object obj)
      {
        string fact_name = _Server->get_factory(obj)->query_attribute("OBJ_NAME");
        string obj_name = obj->query_attribute("OBJ_NAME");
        whatlist = Array.push(whatlist,obj_name);
      }
    }
    break;
    case "files":
    {
      mixed all = pathobj->get_inventory_by_class(CLASS_DOCUMENT|CLASS_DOCLPC|CLASS_DOCEXTERN|CLASS_DOCHTML|CLASS_DOCXML|CLASS_DOCXSL);
      foreach(all, object obj)
      {
        string fact_name = _Server->get_factory(obj)->query_attribute("OBJ_NAME");
        string obj_name = obj->query_attribute("OBJ_NAME");
        whatlist = Array.push(whatlist,obj_name);
      }
    }
    break;
    case "exits":
    case "gates":
    case "rooms":
    {
      mixed all = pathobj->get_inventory_by_class(CLASS_ROOM|CLASS_EXIT);
      foreach(all, object obj)
      {
        string fact_name = _Server->get_factory(obj)->query_attribute("OBJ_NAME");
        string obj_name = obj->query_attribute("OBJ_NAME");
        whatlist = Array.push(whatlist,obj_name);
      }
    }
    break;
    case "groups":
    {
      array(object) groups = _Server->get_module("groups")->get_groups();
      foreach(groups,object group)
      {
        string obj_name = group->get_name();
        whatlist = Array.push(whatlist,obj_name);
      }
    }
    break;
    case "mygroups":
    {
       array(object) groups = _Server->get_module("groups")->get_groups();
       foreach(groups,object group)
       {
          if(group->is_member(me)){ 
            string obj_name = group->get_name();          
	    whatlist = Array.push(whatlist,obj_name); 
          }  
       }
    }
    break;
    case "members":
    {
     if(!objectp(_Server->get_module("groups")->lookup(lpath))){
	write("Group does not exist.\n");        
     }
     else {
       array(object) members = _Server->get_module("groups")->lookup(lpath)->get_members();
       foreach(members,object member)
       {
         string obj_name = member->get_user_name();
         whatlist = Array.push(whatlist,obj_name);
       }
      }
    }
    break;
    case "users":
    {
      array(object) users = _Server->get_module("users")->get_users();
      foreach(users,object user)
      {
        string obj_name = user->get_user_name();
        whatlist = Array.push(whatlist,obj_name);
      }      
    }
    break;
    default:
      whatlist = ({"Invalid command"});
  }
  return whatlist;
}

int goto_room(string where)
{
  string roomname="";
  object pathobj;
  //USER CANT GO TO A RUCKSACK. HE CAN JUST LOOK INSIDE RUCKSACK
/*  if(where=="rucksack")
  {
      pathobj=users->lookup(options->user);
      path="/home/~"+pathobj->query_attribute("OBJ_NAME");
      roomname="Your rucksack";
  }
*/
//  else
//  {
    pathobj = OBJ(where);
    if(!pathobj)    //Relative room checking
    {
      pathobj = OBJ(getpath()+"/"+where);
      where=getpath()+"/"+where;
    }
    roomname = pathobj->query_attribute("OBJ_NAME");
    string factory = _Server->get_factory(pathobj)->query_attribute("OBJ_NAME");
    //DONT NEED THIS. NEED TO USE me->move() to these locations
//    if(pathobj&&((factory=="Room.factory")||(factory=="User.factory")||(factory=="Container.factory")))
//        path = where;
    string oldpath = getpath();
    mixed error = catch{
        me->move(pathobj);
        write("You are now inside "+roomname+"\n");
    };

    if(error && pathobj)
    {
      write("Please specify path to room. Not a "+((factory/".")[0])+"\n");
      me->move(OBJ(oldpath));
    }
    else if(error)
    {
      write("Please specify correct path to a room.\n");
    }
//  }
//  roomname = pathobj->query_attribute("OBJ_NAME");
//  write("You are now inside "+roomname+"\n");
  return 0;
}

int set_title(string desc)
{
 if(users->lookup(options->user)->set_attribute("OBJ_DESC",desc))
    write("You are now described as - "+desc+"\n");
  else
    write("Cannot set description.\n");
  return 0;
}

int desc_room()
{
//  write("path : "+path+"\n");
  object pathobj = OBJ(getpath());
  string desc = pathobj->query_attribute("OBJ_DESC");
//  write("desc : "+desc+"\n");
  if((desc=="")||(Regexp.match("^ +$",desc)))
    desc = "This room does not have a description yet.\n";
  write("You are currently in "+pathobj->query_attribute("OBJ_NAME")+"\n"+desc+"\n");
  return 0;
}

int look(string|void str)
{
  if(str)
  {
    write("Just type in 'look' to look around you\n");
    return 0;
  }
  desc_room();
  list("files");
  write("---------------\n");
  list("containers");
  write("---------------\n");
  list("gates");
  write("---------------\n");
  list("rooms");
  write("---------------\n");
  return 0;
}

int take(string name)
{
    string fullpath="";
    fullpath = getpath()+"/"+name;
    object orig_file = OBJ(fullpath);
    if(orig_file)
    {
      object dup_file = orig_file->duplicate();
      dup_file->move(me);
      write(name+" copied to your rucksack.\n");
    }
    else
      write("Please mention a file in this room.");
    return 0;
}

int gothrough(string gatename)
{
    string fullpath = "";
    fullpath = getpath()+"/"+gatename;
    object gate = OBJ(fullpath);
    if(gate)
    {
      object exit = gate->get_exit();
      string exit_path1 = "",exit_path2 = "";
//      exit_path1 = _Server->get_module("filepath:tree")->check_tilde(exit);
//      exit_path2 = _Server->get_module("filepath:tree")->object_to_path(exit);
//      if(exit_path1!="")
//          goto_room(exit_path1);
//      else if(exit_path2!="/void/"||exit_path2!="")
//          goto_room(exit_path2);
//      else
//          write("Problem with object_to_path\n");
      exit_path1 = exit->query_attribute("OBJ_PATH"); //change to object_to_path
      if(exit_path1!="")
        goto_room(exit_path1);
    }
    else
      write(gatename+" is not reachable from current room\n");
    return 0;
}

int delete(string type, string name) 
{  
    type = String.capitalize(type);
    switch(type)
    {
      case "Container":
      case "File":
      case "Exit":
      case "Gate":
      case "Room":
      {  
        string fullpath = "";
        fullpath = getpath() + "/" + name;
        if(OBJ(fullpath)){
          OBJ(fullpath)->delete(); 
          write(type + ": "+ name + " deleted successfully.\n");
        }
        else write("Object does not exist.\n") ;  }
    break;
    case "Group":
    {
      if(!_Server->get_factory("Group")->delete_group(_Server->get_module("groups")->lookup(name)))
         write("Group deleted successfully.\n");
      else write("Only the admin of the group can delete the group.\n");
    }
    break;
    case "User":
      if(options->user!="root"){
        write("You cannot create a user. You need to be a root user.\n");
      return 0;
      }
      else{        
        _Server->get_module("users")->get_user(name)->delete();
        write("User: " + name + " deleted successfully.\n");    
      return 0;
      }
    default:
      write("Invalid Command. Enter the type of the object carefully.\n");
    }
    return 0;
}


int create_ob(string type,string name,string destination)
{
  mapping data = ([]);
  string desc;
  type = String.capitalize(type);
  if(destination == ".")
    destination = getpath();
  object myobj ;
  switch(type)
  {
    case "User":
      {
        if(options->user!="root"){
          write("You cannot create a user. You need to be a root user.\n");
        }
        else{
          string pass = Input->read_password("Please enter the password for the user.",name);
          write("Enter the email id for the user. ");
          string email = readln->read();
          _Server->get_factory("User")->execute( (["name": name, "pw":pass, "email": email]) );
          _Server->get_module("users")->get_user(name)->activate_user();
          write("User: " + name + " created successfully.\n");     
        }
      }
    break;
    case "Group":
    {
      if(options->user != "root"){
        write("Only a root user can create a group.\n");
      return 0;
      }
      string parent = readln->read("Subgroup of?\n");
      data = (["parentgroup":parent]);
      desc = readln->read("How would you describe it?\n");
      myobj = create_object(type,name,data,desc);
      myobj->add_member(me);
    } 
    break;
    case "File":
    {
       data=(["mimetype":"auto-detect"]);
       myobj = create_object("Document",name,data,desc);
       myobj->move(OBJ(destination));
       write("File type: "+ myobj->query_attribute("DOC_MIME_TYPE") + "\n");
    }
    break;
    case "Gate" :
    case "Exit" :
    {
      desc = readln->read("How would you describe it?\n");
      object exit_to = OBJ(readln->read("Where do you want to exit to?(full path)\n"));
      data = ([ "exit_from":OBJ(destination), "exit_to":exit_to ]);
      myobj = create_object(type,name,data,desc);
    }
    break;
    case "Link" :
    {
      desc = readln->read("How would you describe it?\n");    
      object link_to = OBJ(readln->read("Where does the link lead?\n"));
      data = ([ "link_to":link_to ]);
      myobj = create_object(type,name,data,desc);
      myobj->move(OBJ(destination));
    }
    break;
    case "Room" :
    case "Container" :
    {
      desc = readln->read("How would you describe it?\n");
      myobj = create_object(type,name,data,desc);
      myobj->move(OBJ(destination));
    }
    break;
    default:
      write("Invalid object type. Enter the object type correctly\n");
    }
    if(objectp(myobj))
      write(type + ": " + name + " created successfully.\n");
    else write(type + ": " + name + " not created.\n");
  return 0;
}



int peek(string container)
{
  string fullpath = "";
  if(getpath()[-1]==47)    //check last "/"
      fullpath = getpath()+container;
  else
      fullpath = getpath()+"/"+container;
  string pathfact = _Server->get_factory(OBJ(fullpath))->query_attribute("OBJ_NAME");
  if(pathfact=="Room.factory")
  {
    write("Maybe you are looking for the command 'look'\n");
    return 0;
  }
  if(pathfact!="Container.factory")
  {
    write("You can't peek into a "+pathfact[0..sizeof(pathfact)-8]+"\n");
    return 0;
  }
  array(string) conts = get_list("containers", fullpath);
  array(string) files = get_list("files", fullpath);
  write("You peek into "+container+"\n\n");
  display("containers", conts);
  display("files", files);
}

void display(string type, array(string) strs)
{
  if(sizeof(strs)==0)
   write("There are no "+type+" here\n");
  else if(sizeof(strs)==1)
    write("There is 1 "+type[0..sizeof(type)-2]+" here\n");
  else
    write("There are "+sizeof(strs)+" "+type+" here\n");
  foreach(strs, string str)
  {
    write(str+"   ");
  }
  write("\n-----------------------\n");
}

int inventory()
{
  array(string) conts = get_list("containers", me);
  array(string) files = get_list("files", me);
  array(string) others = get_list("others", me);
  write("You check your inventory\n");
  display("containers", conts);
  display("files", files);
  display("other files", others);
}

int editfile(string filename)
{
  string fullpath = "";
  if(getpath()[-1]==47)    //check last "/"
      fullpath = getpath()+filename;
  else
      fullpath = getpath()+"/"+filename;
  string pathfact = _Server->get_factory(OBJ(fullpath))->query_attribute("OBJ_NAME");
  if(pathfact=="Document.factory")
    applaunch(OBJ(fullpath),exitnow);
  else
    write("You can't edit a "+pathfact[0..sizeof(pathfact)-8]);
  return 0;
}

void send_email(){
          mapping vars;
          string users,subject,messagebody;
          write("The recipients can be an sTeam user, User group or an external email. Enter the receipents of the email.\nNote: The recipients should be separated by \",\".\n");
          users = readln->read();
	  write("Enter the subject of the email.The subject should not be blank.\n");
          subject = readln->read();
          write("Enter the body of the email.The subject should not be blank.\n");
          messagebody = readln->read();
          vars = (["to_free" : users, "messagesubject" : subject, "messagebody" : messagebody,]);
          //write("\n"+users+"\t" + subject + "\t" + messagebody + "\n");
	  array tousers = ({ });
	  array(string) invalid = ({ });
	  object smtp = _Server->get_module("smtp");
	  object mail;
	  int noContent = 0;
	  int produceWarnings = 0;
          string errTextE = "Failed to send Message!Causes:";
	  array(string) to_free;
	  if(stringp(users) && sizeof(users) != 0) {
		  to_free = users / ",";
		  foreach(to_free, string elem) {
			  elem = String.trim_all_whites(elem);
			  if(elem != "" && !isEmptyString(elem)) {
				  if(objectp(_Server->get_module("users")->lookup(elem))) {
					  tousers += ({ _Server->get_module("users")->lookup(elem) });
				  }else if(objectp(_Server->get_module("groups")->lookup(elem))){
					  tousers += ({ _Server->get_module("groups")->lookup(elem)});

				  }else if(mailAdressValid(elem)) {
					  tousers += ({ elem });

			      }else {
					  invalid += ({ elem });
				  }
			  }
		  }

	  }
	  if(sizeof(tousers) != 0 && stringp(subject) && subject != ""){
		  string body = "";
		  
		  string message_name = replace(subject,"/","_");
//write("\n" + message_name +"\n");
		  mail = _Server->get_factory("Document")->execute( ([ "name":message_name, "mimetype":"text/plain"]));
		  mail->set_attribute("OBJ_DESC", subject);
		  if(stringp(messagebody) && messagebody != "") {
			  mail->set_content(messagebody);
			  body = messagebody;
		  }else {
			  noContent = 1;
		  }
		  mail->set_attribute("DOC_ENCODING", "utf-8");
// To support attachments, induce a variable called as annotfile.
	/*	  string annotfile = readln("Enter the file to be attached.(sTeam address).\n");
                  string url = annotfile;
		  if ( stringp(url) && strlen(url) > 0 &&
		  stringp(annotfile  ) {
			  object factory = _Server->get_factory(CLASS_DOCUMENT);
                          object obj;
			  object ann = factory->execute( ([ "name":url, "acquire":obj, ]) );
			  function f = ann->receive_content(strlen(vars["annotfile"]));
			  f(vars["annotfile"]);
			  f(0);
			  mail->add_annotation(ann); 
		  }*/
//write("Mail : %O\n",mail);
//write("\nMail Content = %s", mail->get_content());
          array(string) stringadresses = ({}); 
		  foreach(tousers, mixed user) {
			  if(objectp(user)) {
          			if (objectp(mail->get_annotating())) {
            				mail = mail->duplicate();
        			  }
				  user->mail(mail);
			  }
			  else if(stringp(user)) {
				  stringadresses += ({ user });
			  }
		  }
      //write( "\nString addresses\n");
      //write( "%O\n",stringadresses );
      //write("Sizeof stringaddr %d \n",sizeof(stringadresses) );
      if (sizeof(stringadresses) > 0) {
        smtp->send_mail(stringadresses, vars["messagesubject"], body);
      }
      //write("Sizeof invalid and noContent %d %d \n",sizeof(invalid), noContent );
      write("Mail Successfully sent\n");  	   
      if(sizeof(invalid) != 0 || noContent == 1) {
	produceWarnings = 1;
	errTextE = "Mail successfully sent!But there were some warnings:";
	  if(sizeof(invalid) != 0) {
            errTextE += "There were invalid entries. The entries";
     	    foreach(invalid, string s) {
		errTextE += ""+s+"";
            }
      errTextE += " do not seem to be valid users or groups in your sTeam system. No messags have been send there!";
      }	  
           if(noContent == 1) {
	     errTextE += "Your message contains no text.";
            }
            else{
	      errTextE += "";
            }
      }
      if(produceWarnings)
        write(errTextE +"\n");
      }
      else {
	errTextE += "";
	if(sizeof(tousers) == 0) {
          errTextE += "There are no valid recipients for your message because ";
	  if(sizeof(invalid) == 0) {
	     errTextE += "you have not specified any for your message.";
	  } else {
	      errTextE += "you only entered invalid recipients:";
	      foreach(invalid, string s) {
		errTextE += ""+s+"";
	      }
              errTextE += "";
	   }
	}
	if(stringp(!subject) || subject == "") {
	  errTextE += "No subject is specified for your message. Please give an subject.";
	}
        write("\n"+ errTextE +"\n");
      }  
}

int isEmptyString(string s) {
  for(int i = 0; i < sizeof(s); i++)
    if(s[i] != ' ') return 0;
      return 1;
}


int mailAdressValid(string adress){
  string localPart;
  string domainPart;
  if(sscanf(adress, "%s@%s", localPart, domainPart) != 2){
    return 0;
  }
  else if(sscanf(localPart, "%*[A-Za-z0-9.!#$%&'*+-/=?^_`{|}~]") != 1 || sizeof(localPart) == 0 || sizeof(localPart) > 64){
    return 0;
  }
  else if(sscanf(domainPart, "%*[A-Za-z0-9.-]") != 1 || sizeof(domainPart) == 0 || sizeof(domainPart) > 255){
    return 0;
   }else return 1;
}

int open_log(){
  write("The log files include errors, events, fulltext.pike, graphic.pike, http, search.pike, security, server, slow_requests, smtp, spm.pike and tex.pike.\nEnter the name of the log files you want to open.\nNote: The filenames should be separated by \",\".\n");
  string files = readln->read();
  files-=" ";
  array(string) open_files = files / ",";
  string command="sudo*vi*-o*-S*/usr/local/lib/steam/tools/steam-shell.vim*-S*/usr/local/lib/steam/tools/watchforchanges.vim*-S*/usr/local/lib/steam/tools/golden_ratio.vim*-c*edit";
  foreach(open_files, string cmd){
      command+= "/var/log/steam/"+cmd+".log*";
  }
 open_files = command / "*";
 object editor=Process.create_process(open_files,
                                     ([ "cwd":getenv("HOME"), "env":getenv(), "stdin":Stdio.stdin, "stdout":Stdio.stdout, "stderr":Stdio.stderr ]));
 editor->wait();
return 0;
}

void exitnow()
{}

string getpath()
{
  return me->get_last_trail()->query_attribute("OBJ_PATH");
}

constant stash_help_doc = #"This is a sTeam Advanced Shell. All the STASH commands work with normal pike commands. Tab completion is available for both STASH commands and pike commands.\n\n";
