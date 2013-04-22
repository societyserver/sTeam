/* Copyright (C) 2004 Christian Schmidt
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
 */

/**
 * This module is responsible for sending messages to users/groups/... and
 * e-mails to remote adresses. It also keeps track of system-wide
 * alias-adresses and of user-forwards.
 */

inherit "/kernel/module";

#include <database.h>
#include <macros.h>
#include <classes.h>
#include <config.h>
#include <attributes.h>
#include <events.h>

//#define DEBUG_FORWARD

#ifdef DEBUG_FORWARD
#define LOG_FORWARD(s, args...) werror("forward: "+s+"\n", args)
#else
#define LOG_FORWARD
#endif

#if constant(Protocols.SMTP.client) 
#define SMTPCLIENT Protocols.SMTP.client
#else
#define SMTPCLIENT Protocols.SMTP.Client
#endif

//stores aliases & forwards
static mapping(string:array) mAliases, mForwards;
static mapping(object:object) mListeners;
static array whiteDomains;

string _mailserver;
int _mailport;

string get_mask_char() { return "/";}

void init_module()
{
    mAliases=([]);
    mForwards=([]);
    mListeners=([]);
    whiteDomains = Config.array_value(_Server->get_config("mail_whitedomains")) || ({ });
    add_data_storage(STORE_FORWARD,retrieve_aliases,restore_aliases);
}

static array|void get_parent_groups(object group)
{
  object parent = group->get_parent();
  array parents = ({});
  if(!objectp(parent))
    return;
  else
    parents += ({ parent });
  array grandparents=get_parent_groups(parent);
  if(arrayp(grandparents) )
    parents += grandparents;
  return parents;
}

static array get_user_groups(object user)
{
    array groups;
    array usergroups = groups = user->get_groups();
    foreach(usergroups;; object group)
    {
      array parents = get_parent_groups(group);
      if(arrayp(parents))
        groups += parents;
    }
    return(Array.uniq(groups));
}

void load_module()
{ 
  array groups = ({});
  LOG_FORWARD("forwards are: %O\n", mForwards);

  low_add_alias("abuse", "admin");
}

static void send_annotation_remote(int event, object group, object annotated, 
                                   object caller, object ... thread)
{
  // find root of thread...
  object parent = thread[-1];
  while ( objectp(parent->get_annotating()) ) 
  {
    parent = parent->get_annotating();
  }

  LOG_FORWARD("send_annotation_remote(event: %d, group: %O, annotated: %O, caller: %O, thread: %s) - parent: %O\n", 
         event, group->get_identifier(), annotated->get_identifier(),
         caller->get_identifier(), thread->get_identifier()*", ",
         parent->get_identifier());

  if(parent==annotated)
  {
    LOG_FORWARD("sending to %s", group->get_identifier());
    send_group(group, thread[-1]); 
  }
}

void install_module()
{
    _mailserver = _Server->query_config(CFG_MAILSERVER);
    _mailport = (int)_Server->query_config(CFG_MAILPORT);
    LOG_FORWARD("mailserver is: "+_mailserver+":"+_mailport);
}    

string get_identifier() { return "forward"; }

mapping get_aliases()
{
    return mAliases;
}

array get_alias ( string key ) {
  if ( arrayp(mAliases[key]) )
    return copy_value( mAliases[key] );
  else
    return UNDEFINED;
}

mapping retrieve_aliases()
{
    if ( CALLER != _Database )
	    THROW("Caller is not database !", E_ACCESS);

    return (["aliases" : mAliases, "forwards" : mForwards]);
}

void restore_aliases(mapping data)
{
    if ( CALLER != _Database )
	    THROW("Caller is not database !", E_ACCESS);

    mAliases=data["aliases"];
    mForwards=data["forwards"];
    
    LOG_FORWARD("loaded "+sizeof(mAliases)+" aliases and "
                +sizeof(mForwards)+" forwards");
}

/**
 * check if an address is valid
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param string address - the address to check
 * @return int 1 if valid, 0 if invalid, -1 if access denied
 */
int is_valid(string address)
{
    LOG_FORWARD("checking adress \"%O\"",address);
    LOG_FORWARD("alias...");
    if(arrayp(mAliases[address]))
        return 1; //adress is alias
    LOG_FORWARD("no - trying user...");
    if(objectp(MODULE_USERS->lookup(address)))
        return 1; //address is single user
    LOG_FORWARD("no - trying group...");
    if ( address == "steam" )
      return 0; // no mailing to steam-group allowed
    if(objectp(MODULE_GROUPS->lookup(address)))
        return 1; //adress is a group
    LOG_FORWARD("no - trying to replace - with space...");
    if(objectp(MODULE_GROUPS->lookup(replace(address, "-", " "))))
        return 1; //adress is a group
    LOG_FORWARD("no - trying object-id...");
    if(sscanf(address,"%d",int oid))
    {
        LOG_FORWARD("looking for object #%O",oid);
        object tmp=_Database->find_object(oid);
        if(objectp(tmp))
        {
            LOG_FORWARD("checking access on object #%O",oid);
            mixed err = catch { _SECURITY->access_annotate(0, tmp, CALLER, 0); };
            if(err!=0) return -1; //access denied -> invalid target-address
            else return 1; //target is existing object & annotatable
        }
        else LOG_FORWARD("not found");
    }
    LOG_FORWARD("sorry - no valid target found!");
    
    return 0; //no checks succeeded, target address is invalid
}

/**
 * return the remote addresses within an array of mixed addresses
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) names - the addresses to get remotes from
 * @return array(string) the remote adresses
 */
private array(string) get_remote_addresses(array(string) names)
{
    array(string) result=({});
    for(int i=0;i<sizeof(names);i++)
        if(search(names[i],"@")!=-1)
            result+=({names[i]});
    return result;
}

string resolve_name(object grp)
{
  if ( objectp(grp) ) {
    if ( grp->get_object_class() & CLASS_USER )
      return grp->get_user_name();
    return grp->get_identifier();
  }
  return "";
}

/**
 * split targets into remote, groups, users, and objects
 *
 * @author Martin Bähr
 * @param array(string) names - the addresses to work with
 * @return mapping - containing the different recipient types
 */
private mapping resolve_recipients(array(string) names)
{
    array unresolved=({});
    LOG_FORWARD("Resolving: %O", names);
    array(string) resolved=replace_aliases(names);
    LOG_FORWARD("Aliases replaced: %O", resolved);
    resolved=replace_forwards(resolved);
    LOG_FORWARD("Forwards are: %O", resolved);
   
    mapping result =([ "groups":({}), "remote":({}), "users":({}), 
                       "objects":({}) ]);
    object target_obj;
    int oid;
   
    foreach(resolved;; string target)
    {
        if(search(target,"@")!=-1)
            result->remote += ({ target });
        else if ( objectp(target_obj=MODULE_GROUPS->lookup(target)) ) 
            result->groups += ({ target_obj });
        // groupnames may have spaces, but those don't work well with email.
        else if ( objectp(target_obj=MODULE_GROUPS->lookup(replace(target, "-", " "))) ) 
            result->groups += ({ target_obj });
        else if ( objectp(target_obj=MODULE_USERS->lookup(target)) )
            result->users += ({ target_obj });
        else if ( sscanf(target,"%d",oid) 
                  && objectp(target_obj=_Database->find_object(oid)) )
            result->objects += ({ target_obj });
        else
            unresolved += ({ target });
    }
   
    LOG_FORWARD("Remote adresses are: %O", result->remote);
    LOG_FORWARD("Group addresses are: %O", result->groups);
    LOG_FORWARD("User addresses are: %O", result->users);
    LOG_FORWARD("Object addresses are: %O", result->objects);
    if(sizeof(unresolved))
        FATAL("Warning! unresolved addresses: %O", unresolved);
    return result;
}

/**
 * within an array of adresses, search for aliases and replace them with 
 * their targets
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) names - the addresses to work with
 * @return array(string) the input-array with aliases replaced by targets
 */
private array(string) replace_aliases(array(string) names)
{
    array(string) result=({});
    foreach(names;; string name)
    {
        if(arrayp(mAliases[name])) //add code for checking aliases on aliases here...
            result+=mAliases[name];
        else 
           result+=({name});
    }
    return Array.uniq(result);
}


/**
 * within an array of adresses, search for forwards and replace them with 
 * their targets
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) names - the addresses to work with
 * @return array(string) the input-array with forwards replaced by targets
 */
private array(string) replace_forwards(array(string) names, void|mapping fwd_done)
{
    array(string) result=({});

    if ( !mappingp(fwd_done) )
      fwd_done = ([ ]);

    for(int i=0;i<sizeof(names);i++)
    {
        if ( fwd_done[names[i]] )
	  continue;
        if(arrayp(mForwards[names[i]]))
        {
            array(string) tmp=mForwards[names[i]];
            for(int j=0;j<sizeof(tmp);j++)
	    {
		if ( !stringp(tmp[j]) )
		    continue;
		
 	        fwd_done[tmp[j]] = 1;
                if(search(tmp[j],"@")!=-1) //remote address
                    result+=({tmp[j]});
                else
                {
                    if(search(tmp[j],"/")!=-1) //local forward-target starts with "/" -> don't forward further
                        result+=({tmp[j]-"/"});
                    else //lookup forward of this forward-target
                    {
                        array(string) tmp2=replace_aliases( ({tmp[j]}) );
                        result+=replace_forwards(tmp2, fwd_done);
                    }
                }
            }
        }
        else result+=({names[i]});
    }
    return result;
}

/**
 * send a message to multiple recipients
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) target - the addresses to send the message to
 * @param Message msg - the message to send (WARNING msg is destructed by sending!)
 * @return int 1 if successful
 */
int send_message(array(string) target, Messaging.Message msg)
{
    int hasLocal=0;
    string rawText=msg->complete_text();
    string sSender=msg->sender();
    array(string) resolved=replace_aliases(target);
    resolved=replace_forwards(resolved);
    array(string) asRemote=get_remote_addresses(resolved);

    array(string) asLocal=resolved-asRemote;
    if(sizeof(asLocal)>0) hasLocal=1;
    if(hasLocal)
        send_local(asLocal,msg);
    else 
	destruct(msg);
    
    LOG_FORWARD("Sending to " + sizeof(asRemote) + " Remote Recipients !");
    
    asRemote = Array.uniq(asRemote);
    send_remote(asRemote, rawText, sSender);
    return 1;
    for(int i=0;i<sizeof(asRemote);i++)
        send_remote(asRemote[i],rawText,sSender);
        
    return 1; //success, add code for failures!
}

object lookup_sender(string sender)
{
  string user, domain;

  sscanf(sender, "%*s<%s>", sender);
  sscanf(sender, "%s@%s", user, domain);
  if (strlen(sender)==0)
    return USER("postman"); // as in RFC821 empty reverse path is allowed

  array users = get_module("users")->lookup_email(sender);
  if (sizeof(users)==0) {
    foreach(whiteDomains, string d) { 
      if (search(domain, d) >= 0)
	return USER("postman");
    }
  }
  if (sizeof(users) > 0)
    return users[0];
  return 0;
}


/**
 * send a message (rfc2822 raw text) to multiple recipients
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) target - the addresses to send the message to
 * @param string rawText - the text of the message (rfc2822-format!)
 * @param string|void envFrom - the sender-value of the SMTP-envelope (only needed for forwarding, may be left empty)
 * @return int 1 if successful
 */
int send_message_raw(array(string) target, 
                     string rawText, 
                     string envFrom, 
                     void|object messageObj)
{
    int res=1; //success

    float tt = gauge {
      mixed err;
      LOG_FORWARD("Forward: send_message_raw(%O)", target);
      mapping sendAs = resolve_recipients(target);
      if(sizeof(sendAs->users)) {
	if (!objectp(messageObj)) {
	  messageObj = Messaging.MIME2Message(rawText);
	}
	err = catch(res=send_users(sendAs->users, messageObj));
      }
      if ( err ) 
        FATAL("Error while sending message to users: %O, %O", err[0], err[1]);
      if (res==0) 
        LOG_FORWARD("Warning! send_message_raw failed on one ore more recipient users!");
      res=1;
      
      if(sizeof(sendAs->objects)) {
	if (!objectp(messageObj))
	  messageObj = Messaging.MIME2Message(rawText);
	err = catch(res=send_objects(sendAs->objects, messageObj));   
      }
      if ( err ) 
        FATAL("Error while sending message to objects: %O,%O", err[0], err[1]);
      
      if (res==0) 
        LOG_FORWARD("Warning! send_message_raw failed on one ore more recipient objects!");
      
      send_remote(sendAs->remote, rawText, envFrom);
      foreach(sendAs->groups;; object target)
        send_group(target,rawText,envFrom,messageObj);
    };
    MESSAGE("Message to %s send in %f seconds", (target*","), tt);
      
    return res;
}

/**
 * send a message to objects
 *
 * @author Martin Bähr
 * @param array(object) targets - the objects to send the message to
 * @param string msg - the message to send
 * @return int 1 if successful
 */
private int send_objects(array(object) targets, Messaging.Message msg)
{
    LOG_FORWARD("send_objects(%O, %O)\n", targets, msg->header()->subject);
    if(sizeof(targets)==0 || !arrayp(targets)) return 0;

    int errors;

    seteuid(USER("root"));
    foreach(targets; int count; object target)
    {
        Messaging.Message copy;
        if(count<sizeof(targets)-1)
            // duplicate message if more than one recipient
            copy=msg->duplicate();
        else
            // last recipient gets original
            copy=msg;

        mixed err=catch{Messaging.add_message_to_object(copy,target);};
        if(err)
        {
            copy->delete();
            destruct(copy);
            errors++;
            FATAL("unable to add message to: %s(%d):%O", target->get_identifier(), target->get_object_id(), err);
        }
    }

    if(errors) 
    {
      LOG_FORWARD("Warning!! send_objects encountered errors - some recipients failed!");
      return 0;
    }

    return 1;
}

/**
 * send a message to users
 *
 * @author Martin Bähr
 * @param array(object) users - the users to send the message to
 * @param string msg - the message to send
 * @return int 1 if successful
 */
private int send_users(array(object) targets, Messaging.Message msg)
{
    if(sizeof(targets)==0 || !arrayp(targets)) return 0;

    foreach(targets; int count; object user)
    {
        if ( !objectp(user) )
	    continue;
        Messaging.Message copy;
        if(count<sizeof(targets)-1)
            copy=msg->duplicate();
        else
            copy=msg; // last recipient gets original

        //the recipient gets all rights on his/her copy
        copy->grant_access(user); 

        Messaging.BaseMailBox box = Messaging.get_mailbox(user);
        copy->this()->set_acquire(box->this());
        box->add_message(copy);
    }

    seteuid(0);
    return 1;
}

/**
 * create headers to be added to annotations sent as mails
 *
 * @author Martin Bähr
 * @param object group - the group to send the message to
 * @return mapping of headers
 */
mapping create_list_headers(object group)
{
    mapping headers = ([]);
    headers["X-Steam-Group"] = group->get_identifier();
    headers["List-Id"] = replace(group->get_identifier(), " ", "-")+"@"+
                         (_Server->query_config("smtp_host")||(_Server->query_config("machine")+"."+_Server->query_config("domain")));
  
    object group_workroom = group->query_attribute("GROUP_WORKROOM");
    object modpath=get_module("filepath:tree");
    headers["X-Steam-Path"] = _Server->query_config("web_server")+
          modpath->object_to_filename(group_workroom);
  
    headers["X-Steam-Annotates"] = _Server->query_config("web_server")+":"
                                   +(string)group_workroom->get_object_id();
    return headers;
}

/**
 * send a message to a group
 *
 * @author Martin Bähr
 * @param object group - the group to send the message to
 * @param string|object msg - the message to send
 * @return int 1 if successful
 */
private int send_group(object group, 
                       string|object msg, 
                       string|void envFrom, 
                       void|object messageobj)
{
    LOG_FORWARD("send_group(%O)\n", group);
    mapping headers = create_list_headers(group);
    string rawmessage;

    if(stringp(msg))
    {
        rawmessage = (((array)headers)[*]*": ")*"\r\n" + "\r\n" + msg;
        if (!objectp(messageobj))
          messageobj = Messaging.MIME2Message(rawmessage);

        //string messages come from outside, need to be added to group
        send_objects( ({ group->query_attribute(GROUP_WORKROOM) }), messageobj);
    }
    else if(objectp(msg))
    {
        messageobj = Messaging.Message(msg);
        if(!envFrom)
            envFrom = "<"+messageobj->sender()+">";
        LOG_FORWARD("sender is: %O\n", messageobj->sender());
        messageobj->add_to_header(headers);
        messageobj->add_to_header(([ "to":headers["List-Id"] ]));
        rawmessage = (string)messageobj->mime_message();
    }
    else
    {
        FATAL("Warning! unknown message format: %O", msg);
        return 0;
    }

    string settings = group->query_attribute(GROUP_MAIL_SETTINGS) || "open";
    if ( objectp(get_module("users")) && settings != "open" ) {
      string sender = messageobj->sender() || "";
      sscanf(sender, "%*s <%s>", sender);
      array(object) fromUsers = get_module("users")->lookup_email(sender);
      object fromUser;
      if ( sizeof(fromUsers) > 0 )
        fromUser = fromUsers[0];
      if ( !objectp(fromUser) ) {
        FATAL("Unknown Sending User %O - not relayed", sender);
        return 0;
      }
      if ( settings == "closed" && !group->is_member(fromUser) ) {
        FATAL("User %O is not a member of group %O - not relayed", 
              fromUser, group);
        return 0;
      }
    }
    
    //TODO: only send to users that want a copy of group mails
    array(string) members = group->get_members_recursive(CLASS_USER)->get_user_name();
    // each member gets mail once
    members = Array.uniq(members);
    send_message_raw(members, rawmessage, envFrom, messageobj);  
    
    // store message on group
    mixed err = catch {
      group->add_annotation(messageobj->get_msg_object()->duplicate());
    };
    if ( err ) {
      FATAL("Failed to store annotation on group: %O\n%O", err[0], err[1]);
    }
     
    
    return 1;
}

/**
 * send a message to a subgroup
 *
 * @author Martin Bähr
 * @param object group - the group to send the message to
 * @param object parent - the group that the message was initially sent to
 * @param string msg - the message to send
 * @return int 1 if successful
 */
private int send_subgroup(object group, object parent, string msg, string envFrom)
{
  mapping headers = ([]);
  headers["X-sTeam-Subgroup"] = group->get_identifier();
  msg = (((array)headers)[*]*": ")*"\r\n" + "\r\n" + msg;

  //TODO: only send to users that want a copy of group mails
  array(string) members = group->get_members(CLASS_USER)->get_user_name();
  send_message_raw(members, msg, envFrom);  
  
  array subgroups = group->get_sub_groups();
  foreach(subgroups;; object subgroup)
    send_subgroup(subgroup, parent, msg, envFrom);
}


/**
 * send a simple message (subject & text) to multiple recipients
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) target - the addresses to send the message to
 * @param string subject - the subject of the message to send
 * @param string message - the text of the message to send
 * @return int 1 if successful
 */
int send_message_simple(array(string) target, string subject, string message)
{
    int hasLocal=0;
    Messaging.Message msg = Messaging.SimpleMessage(target, subject, message);
    string rawText=msg->complete_text();
    string sSender=msg->sender();
    array(string) resolved=replace_aliases(target);
    resolved=replace_forwards(resolved);
    array(string) asRemote=get_remote_addresses(resolved);
    array(string) asLocal=resolved-asRemote;
    if(sizeof(asLocal)>0) hasLocal=1;
    if(hasLocal)
        send_local(asLocal,msg);
    else destruct(msg);

    asRemote = Array.uniq(asRemote);
    send_remote(asRemote, rawText, sSender);
    return 1;
    for(int i=0;i<sizeof(asRemote);i++)
        send_remote(asRemote[i],rawText,sSender);
        
    return 1; //success, add code for failures!
}

/**
 * replace group-entries with members of group
 * object ids included in input are not changed by this
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) target - the addresses to replace groups in
 * @return array(string) input-array with groups replaced by members of groups
 */
private array(string) expand_local_addresses(array(string) target)
{
    array(string) result=({});
    for(int i=0;i<sizeof(target);i++)
    {
        if(objectp(MODULE_USERS->lookup(target[i])))
        {
            result+=({target[i]});
            continue;
        }
        // FIXME: this is dead code! all groups should have been removed by now.
        object tmp=MODULE_GROUPS->lookup(target[i]);
        if(objectp(tmp))
        {
            result+=tmp->get_members();
            continue;
        }
        if(sscanf(target[i],"%d",int oid))
        {
            result+=({target[i]});
            continue;
        }
        LOG_FORWARD("expand_local_addresses: failed to find \""+target[i]+"\"");
    }
    return result; //now contains only user-names and object-ids
}

private int send_local_single(string recipient, Messaging.Message msg)
{
        int oid;
        if(sscanf(recipient,"%d",oid)!=1)
        {
            object user=MODULE_USERS->lookup(recipient);
            Messaging.BaseMailBox box = Messaging.get_mailbox(user);
            msg->grant_access(user); //the recipient gets all rights on his/her copy
            msg->this()->set_acquire(box->this());
            box->add_message(msg);
        }
        else //store message on object
        {
            object target=_Database->find_object(oid);
            if(!objectp(target)) return 0; //invalid object-id, do nothing
//            msg->grant_access(target->query_attribute(OBJ_OWNER));
            msg->this()->set_acquire(target); 
            Messaging.BaseMailBox box = Messaging.get_mailbox(target);
            if(objectp(box)) //target can be accessed as mailbox
                box->add_message(msg);
            else
                Messaging.add_message_to_object(msg,target);
        }
        return 1;
}
/**
 * send a message to local recipients
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param array(string) target - the local addresses to send the message to
 * @param Message msg - the message to send (WARNING msg is destructed by sending!)
 * @return int 1 if successful
 */
private int send_local(array(string) target, Messaging.Message msg)
{
    if(sizeof(target)==0 || !arrayp(target)) return 0;
    
    int result=1; //success

    // FIXME: expand_local_addresses should not be needed anymore:
    array(string) asLocal=expand_local_addresses(target); //resolve aliases & forwards
    LOG_FORWARD("expanded local adresses are:%O",asLocal);

    for(int i=sizeof(asLocal)-1;i>0;i--) //duplicate message if more than one recipient
    {
        Messaging.Message copy=msg->duplicate();
        if(send_local_single(asLocal[i],copy)==0)
        {
            LOG_FORWARD("failed to send message #"+copy->get_object_id()+" to: "+asLocal[i]);
            copy->delete();
            destruct(copy);
            result=0;
        }
    }
    if(send_local_single(asLocal[0],msg)==0) //last recipient gets "original" message
    {
        LOG_FORWARD("failed to send message #"+msg->get_object_id()+" to: "+asLocal[0]);
        msg->delete();
        destruct(msg);
        result=0;
    }

    if(result==0) LOG_FORWARD("Warning!! send_local encountered errors - some recipients failed!");

    return result;
}

/**
 * send a message to a remote address (-> send e-mail)
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param string address - the address to send the mail to
 * @param string rawText - the text of the message (rfc2822-format!)
 * @param string|void envFrom - the sender-value of the SMTP-envelope
 * @return int 1 if successful, 0 if not
 */
private int send_remote(string|array address, string rawText, string envFrom)
{
    string fixed;
    if( arrayp(address) && sizeof(address)==0 ) return 1;
    if( stringp(address) && strlen(address) == 0 ) return 1;

    if( sscanf(envFrom,"%*s<%s>",fixed) == 0 )
    {
      if ( search( envFrom, '@' ) >= 0 )
        fixed = envFrom;
      else {
        FATAL("send_remote: illegal envFrom! : "+envFrom);
        return 0;
      }
    }
    int l;
    if ( arrayp(address) && (l=sizeof(address)) > 10 ) {
	for ( int i = 0; i < sizeof(address); i+=10 ) {
	    array users;
	    if ( i + 10 >= l )
		users = address[i..];
	    else
		users = address[i..i+9];
	    get_module("smtp")->send_mail_raw(users, rawText, fixed);
	    LOG_FORWARD("Message chunked delivered to "+sprintf("%O", users));
	}
    }
    else {
	get_module("smtp")->send_mail_raw(address, rawText, fixed);
	LOG_FORWARD("Message delivered to " + sprintf("%O", address));
    }
    
    return 1;
}

/**
 * Adds an alias to the system-aliases.
 * If an alias with the given name already exists, the alias
 * will point to a list of targets. The target will be added to the
 * alias if it hasn't been added before. If you want to replace an alias
 * completely, you'll have to delete it first.
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param string alias - the name of the alias to add
 * @param string taget - the target the alias should point to
 * @return 1 if successful
 * @see delete_alias
 */
static int low_add_alias(string alias, string target)
{
  if ( (arrayp(mAliases[alias]) && search(mAliases[alias], target)>=0) )
    return 1;  // target was already set for that alias

    if ( !arrayp(mAliases[alias]) )
        mAliases[alias] = ({ });

    mAliases[alias]+=({target});
    require_save();
    return 1;
}

int add_alias(string alias, string target)
{
  _SECURITY->access_write(0, this_object(), CALLER);
  return low_add_alias(alias, target);
}

/**
 * remove an alias from the system aliases
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param string alias - the alias to delete
 * @return 1 if successful, 0 if alias does not exist
 * @see add_alias
 */
static int low_delete_alias(string alias)
{
    if(arrayp(mAliases[alias]))
    {
        m_delete(mAliases,alias);
        require_save();
        return 1;
    }
    else return 0;
}

int delete_alias(string alias)
{
  _SECURITY->access_write(0, this_object(), CALLER);
  return low_delete_alias(alias);
}

/**
 * add a forward for a specific user
 * if user already has a forward, it is extended by the given target
 * target may be a remote e-mail address or a local system address
 * (user, group, object-id, alias)
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param object user - the user to add a forward for
 * @param string forward - the target address to add (e-mail or other valid system-address)
 * @param int|void no_more - set to 1, if this forward is "final", so mails get stored at this adress,
 *                           no matter if a forward exists for this target, too
 * @return int 1 if successful, 0 if not
 */
int add_forward(object user, string forward, int|void no_more)
{
    _SECURITY->access_write(0, user, CALLER);
    
    LOG_FORWARD("adding forward for %s:%s", user->get_user_name(), forward);
    if ( !stringp(forward) ) {
      FATAL("invalid forward: %O", forward);
      return 0;
    }

    if(intp(no_more) && no_more==1) forward="/"+forward;
    if(user->get_object_class() & CLASS_USER)
    {
        string name=user->get_identifier();
	if ( forward == name )
	  steam_error("add_forward: Unable to resolve forward to itself !");

        if ( mForwards[name] && search( mForwards[name], forward ) >= 0 ) {
          LOG_FORWARD("add_forward(%s : %s) : forward already exists",
                      name, forward);
          return 0;  // forward already exists
        }
        mForwards[name]+=({forward});
        require_save();
        return 1;
    }
    else
    {
        LOG_FORWARD("ERROR, add_forward() called for non-user object #"
                     +user->get_object_id());
        return 0;
    }
}

/**
 * remove a user-forward
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param object user - the user to remove forwarding for
 * @param forward - the forward to remove (if not specified, all forwards
 *   for that user will be removed)
 * @return int 1 if successful, 0 otherwise
 */
int delete_forward(object user, void|string forward)
{
  _SECURITY->access_write(0, user, CALLER);
    
  if ( ! objectp(user) || !(user->get_object_class() && CLASS_USER) ) {
    LOG_FORWARD("delete_forward: invalid user %O", user);
    return 0;
  }

  string name = user->get_identifier();
  if ( ! arrayp(mForwards[name] ) ) {
    LOG_FORWARD("delete_forward: user %s has no forwards", name);
    return 0;  // no forwards for this user
  }

  if ( zero_type(forward) ) {  // delete all forwards for user
    LOG_FORWARD("deleting forwards for %s", name);
    m_delete(mForwards,name);
  }
  else {  // delete single forward
    LOG_FORWARD("deleting forward %O for %s", forward, name);
    if ( search( mForwards[name], forward ) < 0 ) {
      LOG_FORWARD("forward %O not found for %s", forward, name);
      return 0;
    }
    mForwards[name] -= ({ forward });
  }
  require_save();
  return 1;
}

/**
 * get the current forward for a user
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param object user - the user to get forward for
 * @return array(string) of forwards or 0 if user is not a sTeam-user-object
 */
array(string) get_forward(object user)
{
    if(user->get_object_class() & CLASS_USER)
        return mForwards[user->get_identifier()];
    else return 0;
}

/*
string dump_data()
{
    string res;
    res=sprintf("forwards:%O aliases:%O",mForwards,mAliases);
    LOG_FORWARD("current data of forward-module:\n"+res);
    LOG_FORWARD("mailserver is: "+_mailserver+":"+_mailport);
    return res;
}
*/
