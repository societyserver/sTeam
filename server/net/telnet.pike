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
 * $Id: telnet.pike,v 1.2 2009/05/04 19:16:48 astra Exp $
 */

constant cvs_version="$Id: telnet.pike,v 1.2 2009/05/04 19:16:48 astra Exp $";

inherit "/net/coal/login";
inherit "/net/base/readline";
inherit "/net/base/cmd";

#include <macros.h>
#include <config.h>
#include <database.h>
#include <events.h>
#include <client.h>
#include <attributes.h>
#include <classes.h>

#define MODE_CONNECT 0
#define MODE_LOGIN 1
#define MODE_PASS  2
#define MODE_CMD   3
#define MODE_MORE_INPUT 4

static int      iMode;
mapping         mMode= ([ "cmd":0 ]);
static int      passwdtries;
static object tmpUser;
static int      iCreate;
static mapping(string:string) mCreate = ([]);

void create(object f)
{
    ::create(f);
    iMode = MODE_CONNECT;
}

/**
 * creates an new user and activates him. adduser is called in Mode_Create several times.
 */
int cmd_adduser(string cmd, string|void args)
{
    if (iMode == MODE_CMD) {
        iMode = MODE_MORE_INPUT;
        iCreate = 1;
        mCreate["name"] = args;
        send_message("Weitere Daten werden zum Anlegen des Nutzers \"" + args + "\" benötigt.\n");
        send_message("Passwort des Nutzers:");
    } else {
        switch (iCreate) {
          case 0:
              mCreate["name"] = args;
              iCreate = 1;
              send_message("Passwort des Nutzers:");
              break;
          case 1:
              mCreate["pw"] = cmd;
              iCreate = 2;
              send_message("E-Mail des Nutzers:");
              break;
          case 2:
              mCreate["email"] = cmd;
              LOG("now fetching factory\n");
              object factory = _Server->get_factory(CLASS_USER);
              LOG("Now executing factory\n");
              object user = factory->execute(mCreate);
              LOG("Factory executed");
              if (user == 0) {
                  send_message("Ein Fehler ist aufgetreten. Nutzer wurde nicht angelegt\n");
              } else {
                  LOG("Now activating user.\n");
                  if (user->activate_user(factory->get_activation())) {
                      send_message("Nutzer wurde angelegt und aktiviert.\n");
                  } else {
                      send_message("Nutzer wurde angelegt, aber nicht aktiviert!\n");
                  }
              }
              iMode = MODE_CMD;
              iCreate = 0;
              break;
        }
    }
    return 1;
}

void addlink(object to)
{
    mapping (string:object) mName = ([]);
    mName["link_to"] = to;
    object factory = _Server->get_factory(CLASS_LINK);
    object link = factory->execute(mName);
    if (link == 0) {
        send_message("Ein Fehler ist aufgetreten. Der Link konnte nicht angelegt werden.\n");
    } else {
        send_message("Der Link wurde angelegt. Seine ID ist " + link->get_object_id() );
    }
    
}

void create_object(string type, string name)
{
    mixed err;
    object newobject;
    mapping (string:string) mName = ([]);
    mName["name"] = name;
    object factory = _Server->get_factory(type);
    if(!factory)
    {
      send_message("Es gibt keine Klasse vom typ '"+type+"'.\n");
      return;
    }
    err = catch{ newobject = factory->execute(mName); };
    if (newobject == 0) 
    {
        send_message("Ein Fehler ist aufgetreten. Das Objekt konnte nicht angelegt werden:\n"+err[0]+"\n");
        LOG(sprintf("%O", err));
    } 
    else 
    {
        send_message("Das Objekt wurde angelegt. Seine ID ist " + newobject->get_object_id() );
        newobject->move(oUser->get_environment());
    }
}


/**
 * Shows the inventory of the given object
 * grouped by the object classes
 *
 * @param object obj - the target object
 * @return the inventory formatted as string
 * @author <a href="mailto:joergh@upb.de">Joerg Halbsgut</a>) 
 */
static string show_inventory(object obj) {
    string res = "";

    // NOT COMPLETE !(see also "classes.h")
    mapping classes_names = ([ CLASS_USER:CLASS_NAME_USER,
                               CLASS_OBJECT:CLASS_NAME_OBJECT,
                               CLASS_CONTAINER:CLASS_NAME_CONTAINER,
                               CLASS_ROOM:CLASS_NAME_ROOM,
                               CLASS_DOCUMENT:CLASS_NAME_DOCUMENT,
                               CLASS_LINK:CLASS_NAME_LINK,
                               CLASS_GROUP:CLASS_NAME_GROUP,
                               CLASS_EXIT:CLASS_NAME_EXIT,
                               CLASS_IMAGE:"Image",
                               CLASS_MESSAGEBOARD:"Messageboard",
                               CLASS_GHOST:CLASS_NAME_GHOST, 
                               CLASS_TRASHBIN:CLASS_NAME_TRASHBIN,
                               /*,CLASS_SHADOW:"Shadow"*/ ]);

    int flag = 0; 
    int counter = 0;

    if (arrayp(obj->get_inventory())) {
        res = res +"\nThis is the inventory of " 
                  + obj->get_identifier() +":\n";
        res += "----------------------------------------------------\n";
        foreach (indices(classes_names), int cl) {
            array(object) inventory_class = 
                obj->get_inventory_by_class(cl);
            flag = 0;
			
            if (arrayp(inventory_class) && sizeof(inventory_class)>0) {
                res += "  " + classes_names[cl] +":\n";
                foreach (inventory_class, object inv_obj) {
                    counter++;
                    string ident = inv_obj->get_identifier();
                    int id = inv_obj->get_object_id();
                    if (flag!=0)
                        res += ", \n";
                    res += sprintf ("    %s[%d]", ident, id); 
                    flag = 1;		
                }
                res += "\n\n";
            }	
        }
        if (counter == 0)
            res += "\n No objects in the inventory.\n";
    }
    else
        res = res +"\""+obj->get_identifier()+"\" has no inventory.\n";

    return res;
}


static void send_room(object room)
{
    if ( objectp(room) ) {
	send_message(
	    "[#"+room->get_object_id() + ","+_FILEPATH->object_to_filename(room)+"]\n"+
	    "You are in a large area called " + room->get_identifier() + ".\n"+
	    "There are the following exits:\n");
	array(object) inv = room->get_inventory();
	foreach(inv, object o) {
	    if ( o->get_object_class() & CLASS_EXIT )
		send_message(o->get_identifier()+",");
	}
	send_message("\nThere are the following people:\n");
	array(object) users = room->get_inventory_by_class(CLASS_USER);
	foreach(users, object u) {
	    send_message(u->get_identifier()+",");
	}
	send_message("\n");
    }
    else {
	send_message("You are in the big black void.\n");
    }
}

static void enter_room(object room, void|object from)
{
    if ( objectp(from) )
	oUser->dispose_event(EVENT_SAY|EVENT_LEAVE_INVENTORY|EVENT_ENTER_INVENTORY, from);

    oUser->listen_to_event(EVENT_SAY, room);
    oUser->listen_to_event(EVENT_LEAVE_INVENTORY, room);
    oUser->listen_to_event(EVENT_ENTER_INVENTORY, room);
}

void notify(int event, mixed ... args)
{
    LOG("SAY: "+sprintf("%O\n", args));
    object user = this_user();
    LOG("oUser="+sprintf("%O", oUser));
    LOG("user="+sprintf("%O", user));
    if ( !objectp(oUser) || !objectp(user) )
        return;
    LOG("sending event response !");

    switch(event) {
    case EVENT_TELL:
	send_message(user->get_identifier() + " tells you: " + args[2]+"\n");
	break;
    case EVENT_SAY:
	if ( user == oUser )
	    send_message("You say: "+args[2]+"\n");
	else
	    send_message(user->get_identifier() + " says: "+args[2]+"\n");
	break;
    case EVENT_ENTER_INVENTORY:
	if ( args[1] == oUser ) {
	    send_message("You move to " + args[0]->get_identifier()+"\n");
	}
	else {
	    send_message(args[1]->get_identifier() + " enters the room.\n");
	    send_message("%O:%O\n", args[1]->get_status(), args[1]->get_status()& CLIENT_FEATURES_MOVE);
	}
	break;
    case EVENT_LEAVE_INVENTORY:
	send_message(args[1]->get_identifier() +  " leaves the room.\n");
	break;
    }
}

int cmd_delete(string cmd, string args)
{
    int id; 
    sscanf(args,"#%i",id);

    object oTmp=find_object(id);
    if (objectp(oTmp)) 
    {
        mixed err = catch { oTmp->delete(); };
        if (err!=0) send_message("Failed to delete Object #"+id+"\r\n");
        else send_message("Deleted Object #"+id+"\r\n");
    }
    else send_message("Unable to find Object #"+id+"\r\n");
    return 1;
}

int cmd_take(string cmd, string args)
{
    int id;
    sscanf(args,"#%i",id);

    object oTmp=find_object(id);
    if (objectp(oTmp))
    {
        mixed err = catch { oTmp->move(oUser); };
        if (err!=0) send_message("Cannot take object #"+id+"\r\n");
	else send_message("Object #"+id+" is now in your inventory!\r\n");
    }
    else send_message("Can't find Object #"+id+"\r\n");
    return 1;
}

int cmd_drop(string cmd, string args)
{
    int id;
    sscanf(args,"#%i",id);

    object oTmp=find_object(id);

    if(objectp(oTmp))
    {
        //check if object is in user's inventory
        array(object) oaInv = oUser->get_inventory();
        foreach( oaInv, object item )
        {
            if ( item->get_object_id() == id )
            {
                mixed err = catch { oTmp->move(oUser->get_environment()); };
                if (err!=0) send_message("Cannot drop object #"+id+"\r\n");
                else send_message("Dropped Object #"+id+"\r\n");
                return 1;
            }
        }
        // foreach did not find object in user's inventory
        send_message("Object #"+id+" is not in your inventory!\r\n");
    }
    else send_message("Can't find Object #"+id+"\r\n");
    return 1;
}

int cmd_quit(string cmd, string args)
{
  if(readln)
    oUser->set_attribute("telnet_history", readln->readline->historyobj->encode()/"\n");
  send_message("Bye %s, see you again soon!\n", oUser->get_identifier());
  oUser->disconnect();
  disconnect();
  return -1; 
}

int cmd_look(string cmd, string args)
{
	//send_room(oUser->get_environment());
        object oRoom = oUser->get_environment();
        send_message(show_inventory(oRoom));
        return 1;
}

int cmd_inv(string cmd, string args)
{
        int oid;
        object obj;
        if ( sscanf(args, "#%d",oid) == 1)
            obj = find_object(oid);	
        else {
            obj = oUser;
            LOG("Inventory of User");
        }

        send_message(show_inventory(obj));
        return 1;
}

int cmd_say(string cmd, string args)
{
	object env = oUser->get_environment();
	env->message(args);
	return 1;
}

int cmd_tell(string cmd, string args)
{
	string user, msg;
	object    target;

	if ( sscanf(args, "%s %s", user, msg) != 2 ) {
	    send_message("Usage is tell <user> <message>.\n");
	    return 1;
	}
	target = _Persistence->lookup_user(user);
	if ( !objectp(target) ){
	    send_message("Failed to find user '"+user+"'.\n");
	    return 1;
	}
	target->message(msg);
	send_message("You told " + user + ": "+msg+"\n");
	return 1;
}

int cmd_move(string cmd, string args)
{
  object env = oUser->get_environment();
  object exit;
  int      id;
  if(args == "home")
  {
    send_message("Going home now...");
    exit = oUser->query_attribute(USER_WORKROOM);
  }  
  else if ( sscanf(args, "#%d", id) ==  1 )
    exit = find_object(id);
  else if(sizeof(args))
    exit = env->get_object_byname(args);
  else
    send_message(cmd + " where?\n");

  if ( objectp(exit) ) 
  {
    mixed err = catch { oUser->move(exit); };
    if ( err != 0 ) 
    {
      send_message("Failed to move there...\n");
    }
    else 
    {
      enter_room(oUser->get_environment(), env);
      //send_room(oUser->get_environment());
      send_message(show_inventory(oUser->get_environment()));
    }
  }
  else if(sizeof(args))
    send_message("The exit '" + args + "' was not found.\n");
  return 1;
}


int cmd_create(string cmd, string args)
{
  array tmp=args/" ";
  create_object(tmp[0], tmp[1..]*" ");
  return 1;
}

int cmd_addroom(string cmd, string args)
{
  create_object("Room", args);
  return 1;
}

int cmd_addcontainer(string cmd, string args)
{
  create_object("Container", args);
  return 1;
}

int cmd_addlink(string cmd, string args)
{
  int objectid;
  object room;
  if ( sscanf(args, "#%d",objectid) == 1) {
    room = find_object(objectid);
    addlink (room);
  } else {
    send_message("Es gibt keinen Raum mit der Angegebenen ID.");
  }
  return 1;
}

int cmd_execute_cmd(string cmd, string args)
{
  send_message("\n"+execute(" "+args)+"\n");
  return 1;
}

// copied from masterlist.pike

int cmd_load(string cmd, string args)
{
  int iOID;
  sscanf(args,"#%i",iOID);
  
  find_object(iOID)->get_identifier();
  return 1;
}

int cmd_upgrade(string cmd, string args)
{
  string option;
  int iOID, force;
  [option, iOID] = array_sscanf(args,"%s#%i");
  
  if(option=="--force " || option=="-f ")
    force=1;
  
  object pOID;
  program target;
  
  pOID = find_object(iOID);
  
  if(!pOID && master()->programs[option])
    target=master()->programs[option];
  else if (pOID->status() <= PSTAT_DISK) {
    send_message("Use Load instead\n");
    return 0;
  }
  
  target=object_program(pOID->get_object());
  
  if(!target) {
    send_message("could not find program\n");
    return 0;
  }
  else
    send_message("upgrading...\n");
  
  mixed res = master()->upgrade(target, force);
  if(res==-1)
    send_message("Upgrade failed, try --force\n");
  else
    send_message("Result: %s\n", (string)res);
  
  return 1;
}

mapping(string:function) run_commands = ([ "l":cmd_look,
                                           "look":cmd_look,
                                           "inv":cmd_inv,
                                           "say":cmd_say,
                                           "tell":cmd_tell,
                                           "go":cmd_move,
                                           "move":cmd_move,
                                           "delete":cmd_delete,
                                           "take":cmd_take,
                                           "drop":cmd_drop,
                                           "adduser":cmd_adduser,
                                           "addroom":cmd_addroom,
                                           "addcontainer":cmd_addcontainer,
                                           "addlink":cmd_addlink,
                                           "create":cmd_create,
                                           "upgrade":cmd_upgrade,
                                           "load":cmd_load,
                                           "cmd":cmd_execute_cmd,
                                           "man":cmd_man,
                                           "?":cmd_help,
                                           "help":cmd_help,
                                           "quit":cmd_quit
                                          ]);

static int handle_command(string cmd)
{
    string args = "";
    sscanf(cmd, "%s %s", cmd, args);
    mMode->cmd=run_commands[cmd];
    if(run_commands[cmd])
      return run_commands[cmd](cmd, args);
    else return 0;
}

static void process_command(string cmd)
{
    switch ( iMode ) {

    case MODE_CONNECT:
        send_message("Welcome to sTeam\n: ");
        send_message("Login: ");
        iMode=MODE_LOGIN;
      break;
    case MODE_LOGIN:
	tmpUser = _Persistence->lookup_user(cmd);
	if ( !objectp(tmpUser) )
        {
	    send_message("User '"+cmd+"' does not exist !\n");
            send_message("Login: ");
        }
	else {
            if(readln)
              readln->set_secret( 1 );
	    send_message("Password for "+cmd+": ");
	    iMode = MODE_PASS;
	}
	break;
    case MODE_PASS:
	if ( objectp(tmpUser) && tmpUser->check_user_password(cmd) ) {
	    send_message("Hi, " + tmpUser->get_identifier() + " - last seen "+
			 "you on " +
			 ctime(tmpUser->query_attribute(USER_LAST_LOGIN)));
	    login_user(tmpUser);
	    iMode = MODE_CMD;
	    enter_room(tmpUser->get_environment());
	    //send_room(tmpUser->get_environment());
            send_message(show_inventory(tmpUser->get_environment()));
            if(readln)
              readln->set_secret( 0 );
	    tmpUser->listen_to_event(EVENT_TELL, tmpUser);
            if(readln)
            {
              array history=tmpUser->query_attribute("telnet_history");
              if(!arrayp(history))
                history=({});
              readln->readline->historyobj=readln->readline->History(512, history+({ "" }));
              if(sizeof(history))
                readln->readline->historyobj->delta_history(sizeof(history));
            }
	}
        else
        {
          passwdtries++;
          if(passwdtries<3)
            send_message("Wrong password, please try again: ");
          else
          { 
            tmpUser->disconnect();
            disconnect();
          }
        }
	break;
    case MODE_MORE_INPUT:
        mMode->cmd(cmd);
        break;
    case MODE_CMD:
	if ( strlen(cmd) != 0 && !handle_command(cmd) )
	    send_message("The command %O was not understood.\n", cmd);
        send_message("["+_FILEPATH->object_to_path(oUser)+"] > ");
	break;
    }
}

int get_client_features() { return CLIENT_FEATURES_ALL; }
string get_socket_name() { return "telnet"; }
 
// allow user to store stuff somewhere
mapping temp_cmd=([]);

int cmd_man(string cmd, string args)
{
		string filename = "server/net/manpages/" + args + ".man";
		if(Stdio.exist(filename))
		{
			write ("\n" + Stdio.read_file(filename) + "\n");
		}
		else
		{			
			write("There is no command \"" + args + "\"\n");
			write("usage : man <command>\n");
		}

  return 1;
}

int cmd_help(string cmd, string args)
{
  send_message("\nthe following commands are available:\n%s\n", 
        sort(indices(run_commands))*" ");
  return 1;
}

