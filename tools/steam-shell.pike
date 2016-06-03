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

constant cvs_version = "$Id: debug.pike.in,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "applauncher.pike";
#define OBJ(o) _Server->get_module("filepath:tree")->path_to_object(o)

Stdio.Readline readln;
mapping options;
int flag = 1, c = 1;
string pw, str;
object me;

protected

class StashHelp {
    inherit Tools.Hilfe;

    string help(string what) {
        return "Show STASH help";
    }

    void exec(Evaluator e, string line, array(string) words,
            array(string) tokens) {
        line = words[1..]*" ";
        function(array(string) | string, mixed ... : void) write = e->safe_write;

        constant all =#"
list            List Gates/Exits, Documents, Containers in the current Room.
goto            Goto a Room using a full path to the Room.
title           Set your own description.
room            Describe the Room you are currently in.
look            Look around the Room.
take            Copy a object in your inventory.
gothrough       Go through a gate.
create          Create an object (File/Container/Exit). Provide the full path of the destination or a . if you want it in current folder.
peek            Peek through a container.
inventory(i)    List your inventory.
edit            Edit a file in the current Room.
hilfe           Help for Hilfe commands.
                   ";
                switch (line) {

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

class Handler {

    inherit Tools.Hilfe.Evaluator;
            inherit Tools.Hilfe;

            object p;
            void create(mapping _constants) {

        readln = Stdio.Readline();
                p = ((program) "tab_completion.pmod")();
                readln = p->readln;
                write = predef::write;
                ::create();
                p->load_hilferc();
                p->constants += _constants; //For listing sTeam commands and objects on tab
                constants = p->constants; //For running those commands
                readln->get_input_controller()->bind("\t", p->handle_completions);
                commands->help = StashHelp();
                commands->hilfe = CommandHelp();
    }

    void add_constants(mapping a) {

        constants = constants + a;
    }
    /*  void add_variables(mapping a)
      {
          variables = variables + a;
      }*/
}

object _Server, users;
mapping all;
string path = "/";
Stdio.Readline.History readline_history;

void ping() {
    call_out(ping, 10);
            mixed a = conn->send_command(14, 0);
    if (a == "sTeam connection lost.") {
        flag = 0;
                readln->set_prompt(getpath() + "~ ");
                conn = ((program) "client_base.pike")();
                conn->close();
        if (conn->connect_server(options->host, options->port)) {
            remove_call_out(ping);
                    ping();
            if (str = conn->login(options->user, pw, 1)) {

                _Server = conn->SteamObj(0);
                        users = _Server->get_module("users");
                        me = users->lookup(options->user);
                        handler->add_constants(assign(conn, _Server, users));
                        flag = 1;
                        readln->set_prompt(getpath() + "> ");
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
            string command;
            //  Regexp.SimpleRegexp a = Regexp.SimpleRegexp("[a-zA-Z]* [\"|'][a-zA-Z _-]*[\"|']");

            if (sizeof (argv) > 1) {
	    	string cmd = "";
          	if (sizeof (argv) >= 3){
			for (int i = 1; i<sizeof (argv); i++)
	        	        cmd += argv[i] + " ";
	        }
		else cmd += argv[1];
            write("Command: %s",cmd);
	    write("\n");
            exec_command(cmd);
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
            "peek" : peek,
            "inventory" : inventory,
            "i" : inventory,
            "edit" : editfile,
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
            "list" : list,
            "goto" : goto_room,
            "title" : set_title,
            "room" : desc_room,
            "look" : look,
            "take" : take,
            "gothrough" : gothrough,

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

// create new sTeam objects
// with code taken from the web script create.pike
mixed create_object(string | void objectclass, string | void name, void | string desc, void | mapping data) {
    if (!objectclass && !name) {
        write("Usage: create(string objectclass, string name, void|string desc, void|mapping data\n");
        return 0;
    }
    object _Server = conn->SteamObj(0);
            object created;
            object factory;

    if (!stringp(objectclass))
        return "No object type submitted";

        factory = _Server->get_factory(objectclass);

        switch (objectclass) {
            case "Exit":
                if (!data->exit_from)
                    return "exit_from missing";
                    break;
                    case "Link":
                    if (!data->link_to)
                        return "link_to missing";
                        break;
                    }

    if (!data)
            data = ([]);
            created = factory->execute(([ "name" : name ]) + data);

        if (stringp(desc))
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

string getstring(int i) {
    //  write("came in here\n");
    string curpath = getpath();
    if (i == 1 && flag == 1)
        return curpath + "> ";
    else if (i == 1 && (flag == 0))
        return curpath + "~ ";
    else if (i == 2 && flag == 1)
        return curpath + ">> ";
    else if (i == 2 && (flag == 0))

        return curpath + "~~ ";
    }

int list(string what) {
    if (what == "" || what == 0) {
        write("Wrong usage\n");
        return 0;
    }
    int flag = 0;
            string toappend = "";
            array(string) display = get_list(what);
            string a = "";
    if (sizeof (display) == 0)
            toappend = "There are no " + what + " in this room\n";
    else if (display[0] == "Invalid command") {
        flag = 1;
                write(display[0] + "\n");
    } else {

        toappend = "Here is a list of all " + what + " in the current room\n";
                foreach(display, string str) {
            a = a + (str + "\n");
        }
    }
    if (flag == 0) {

        write(toappend + "\n");
                write(sprintf("%#-80s", a));
                write("\n");
    }
    return 0;
}

array(string) get_list(string what, string | object | void lpath) {
    //  string name;
    //  object to;
    array(string) gates = ({}), containers = ({}), documents = ({}), rooms = ({}), rest = ({});
    //  mapping(string:object) s = ([ ]);
    object pathobj;
    if (!lpath)
            pathobj = OBJ(getpath());
    else if (stringp(lpath))
            pathobj = OBJ(lpath);
    else

        if (objectp(lpath))
            pathobj = lpath;
            //  string pathfact = _Server->get_factory(pathobj)->query_attribute("OBJ_NAME");
            mixed all = pathobj->get_inventory_by_class(0x3cffffff); //CLASS_ALL
            foreach(all, object obj) {
            string fact_name = _Server->get_factory(obj)->query_attribute("OBJ_NAME");
                    string obj_name = obj->query_attribute("OBJ_NAME");
                    //    write("normally : "+obj_name+"\n");
            if (fact_name == "Document.factory"){
//Check the Mimetype for the object created		    
//write("Object: %s Mimetype: %s \n",obj_name,obj->query_attribute("DOC_MIME_TYPE"));
                    documents = Array.push(documents, obj_name);
                    //          write(obj_name+"\n");
}
            else if (fact_name == "Exit.factory") {
                string fullgate = obj_name + " : " + obj->get_exit()->query_attribute("OBJ_NAME");
                        gates = Array.push(gates, fullgate);
                        //          write("in gates : "+fullgate+"\n");
            } else if (fact_name == "Container.factory")
                    containers = Array.push(containers, obj_name);
                    //          write("in containers : "+obj_name+"\n");
            else if (fact_name == "Room.factory")
                    rooms = Array.push(rooms, obj_name);
            else
                rest = Array.push(rest, obj_name);
            }
    if (what == "gates")
        return gates;
    else if (what == "rooms")
        return rooms;
    else if (what == "containers")
        return containers;
    else if (what == "files")
        return documents;
    else if (what == "others")
        return rest;

    else
        return ({"Invalid command"});
    }


int goto_room(string where) {
    string roomname = "";
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
    if (!pathobj) //Relative room checking
    {
        pathobj = OBJ(getpath() + "/" + where);
                where = getpath() + "/" + where;
    }
    roomname = pathobj->query_attribute("OBJ_NAME");
            string factory = _Server->get_factory(pathobj)->query_attribute("OBJ_NAME");
            //DONT NEED THIS. NEED TO USE me->move() to these locations
            //    if(pathobj&&((factory=="Room.factory")||(factory=="User.factory")||(factory=="Container.factory")))
            //        path = where;
            string oldpath = getpath();
            mixed error = catch {
        me->move(pathobj);
                write("You are now inside " + roomname + "\n");
    };

    if (error && pathobj) {
        write("Please specify path to room. Not a " + ((factory / ".")[0]) + "\n");
                me->move(OBJ(oldpath));
    } else if (error) {

        write("Please specify correct path to a room.\n");
    }
    //  }
    //  roomname = pathobj->query_attribute("OBJ_NAME");
    //  write("You are now inside "+roomname+"\n");
    return 0;
}

int set_title(string desc) {
    if (users->lookup(options->user)->set_attribute("OBJ_DESC", desc))
            write("You are now described as - " + desc + "\n");
    else
        write("Cannot set description.\n");

        return 0;
    }

int desc_room() {
    //  write("path : "+path+"\n");
    object pathobj = OBJ(getpath());
            string desc = pathobj->query_attribute("OBJ_DESC");
            //  write("desc : "+desc+"\n");
    if ((desc == "") || (Regexp.match("^ +$", desc)))
            desc = "This room does not have a description yet.\n";
            write("You are currently in " + pathobj->query_attribute("OBJ_NAME") + "\n" + desc + "\n");

        return 0;
    }

int look(string | void str) {
    if (str) {
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

int take(string name) {
    string fullpath = "";
            fullpath = getpath() + "/" + name;
            object orig_file = OBJ(fullpath);
    if (orig_file) {
        object dup_file = orig_file->duplicate();
                dup_file->move(me);
                write(name + " copied to your rucksack.\n");
    } else
        write("Please mention a file in this room.");

        return 0;
    }

int gothrough(string gatename) {
    string fullpath = "";
            fullpath = getpath() + "/" + gatename;
            object gate = OBJ(fullpath);
    if (gate) {
        object exit = gate->get_exit();
                string exit_path1 = "", exit_path2 = "";
                //      exit_path1 = _Server->get_module("filepath:tree")->check_tilde(exit);
                //      exit_path2 = _Server->get_module("filepath:tree")->object_to_path(exit);
                //      if(exit_path1!="")
                //          goto_room(exit_path1);
                //      else if(exit_path2!="/void/"||exit_path2!="")
                //          goto_room(exit_path2);
                //      else
                //          write("Problem with object_to_path\n");
                exit_path1 = exit->query_attribute("OBJ_PATH"); //change to object_to_path
        if (exit_path1 != "")
                goto_room(exit_path1);
        } else
        write(gatename + " is not reachable from current room\n");

        return 0;
    }

int delete(string file_cont_name) {
    string fullpath = "";
            fullpath = getpath() + "/" + file_cont_name;
    if (OBJ(fullpath))

        return 0;
        return 0;
    }

int create_ob(string type, string name, string destination) {
    string desc = readln->read("How would you describe it?\n");
            mapping data = ([]);
            type = String.capitalize(type);
    if (destination == ".")
            destination = getpath();
        if (type == "Exit") {
            object exit_to = OBJ(readln->read("Where do you want to exit to?(full path)\n"));
                    //    object exit_from = OBJ(getpath());
                    data = ([ "exit_from" : OBJ(destination), "exit_to" : exit_to ]);
        } else if (type == "Link") {
            object link_to = OBJ(readln->read("Where does the link lead?\n"));
                    data = ([ "link_to" : link_to ]);
        }
    object myobj = create_object(type, name, desc, data);
            /*  if(type=="Room" || type=="Container"){
                if(destination==".")
                  myobj->move(OBJ(getpath()));
                else
                  myobj->move(OBJ(destination));
              }
             */
    if (!(type == "Exit"))
            myobj->move(OBJ(destination));

        return 0;
    }

int peek(string container) {
    string fullpath = "";
            fullpath = getpath() + "/" + container;
            string pathfact = _Server->get_factory(OBJ(fullpath))->query_attribute("OBJ_NAME");
    if (pathfact == "Room.factory") {
        write("Maybe you are looking for the command 'look'\n");
        return 0;
    }
    if (pathfact != "Container.factory") {
        write("You can't peek into a " + pathfact[0..sizeof (pathfact) - 8] + "\n");

        return 0;
    }
    array(string) conts = get_list("containers", fullpath);
            array(string) files = get_list("files", fullpath);
            write("You peek into " + container + "\n\n");
            display("containers", conts);
            display("files", files);
}

void display(string type, array(string) strs) {
    if (sizeof (strs) == 0)
            write("There are no " + type + " here\n");
    else if (sizeof (strs) == 1)
            write("There is 1 " + type[0..sizeof (type) - 2] + " here\n");

    else
        write("There are " + sizeof (strs) + " " + type + " here\n");
            foreach(strs, string str) {

            write(str + "   ");
        }
    write("\n-----------------------\n");
}

int inventory() {

    array(string) conts = get_list("containers", me);
            array(string) files = get_list("files", me);
            array(string) others = get_list("others", me);
            write("You check your inventory\n");
            display("containers", conts);
            display("files", files);
            display("other files", others);
}

int editfile(string...args) {
    int size = sizeof (args);
    if (size < 1) {
        write("Please provide a file name\n");
        return 0;
    }
    array(string) fullpatharr = allocate(size);
            array(string) pathfactarr = allocate(size);
            array(object) obj = allocate(size);
    for (int j = 0; j < size; j++) {
        fullpatharr[j] = getpath() + "/" + args[j];
                pathfactarr[j] = _Server->get_factory(OBJ(fullpatharr[j]))->query_attribute("OBJ_NAME");

        if (pathfactarr[j] != "Document.factory") {
            write("You can't edit a " + pathfactarr[j][0..sizeof (pathfactarr[j]) - 8]);
            return 0;
        }
        obj[j] = OBJ(fullpatharr[j]);
    }

    applaunch(obj, exitnow);

    return 0;
}

void exitnow() {
}

string getpath() {
    return me->get_last_trail()->query_attribute("OBJ_PATH");
}

constant stash_help_doc =#"This is a sTeam Advanced Shell. All the STASH commands work with normal pike commands. Tab completion is available for both STASH commands and pike commands.\n\n";
