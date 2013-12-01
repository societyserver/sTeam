/* Copyright (C) 2002-2004  Christian Schmidt
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
 * implements a imap4-server, see rfc3501 (http://www.ietf.org/rfc/rfc3501.txt)
 * sTeam-documents are converted using the messaging-module (/libraries/messaging.pmod)
 *
 * NOTE: this server uses '/' as the hierarchy-delimiter (see rfc for details)
 *       do NOT change this, it's hardcoded in _many_ places and WILL cause trouble!!
 */

import Messaging;

inherit "/net/coal/login";
inherit "/net/base/line";

#include <macros.h>
#include <config.h>
#include <database.h>
#include <events.h>

#include <client.h>
#include <attributes.h>
#include <classes.h>

#include <mail.h>

//#define DEBUG_IMAP

#ifdef DEBUG_IMAP
#define LOG_IMAP(s, args...) werror("imap: "+s+"\n", args)
#else
#define LOG_IMAP
#endif


static int _state = STATE_NONAUTHENTICATED;
static Messaging.BaseMailBox oMailBox; //stores the current selected mailbox
static Messaging.BaseMailBox oInbox; //keeps the inbox, for performance...
static Messaging.BaseMailBox oWorkarea;
static array(string) aSubscribedFolders=({}); //folders a user has subscribed to
static int iUIDValidity=0;
static mapping (int:int) mMessageNums=([]);
int iContinue=0; //for command continuation request
int iBytes=0;
string sData="";
string sCurrentCommand="";
array(IMAPListener) alEnter, alLeave;

//the following maps commands to functions
//depending on the state of the server
static mapping mCmd = ([
    STATE_NONAUTHENTICATED: ([
        "CAPABILITY":   capability,
        "NOOP":         noop,
        "LOGOUT":       logout,
        "AUTHENTICATE": authenticate,
        "LOGIN":        login,
        "STARTTLS":     starttls,
    ]),
    STATE_AUTHENTICATED: ([
        "CAPABILITY":   capability,
        "NOOP":         noop,
        "LOGOUT":       logout,
        "SELECT":       select,
        "EXAMINE":      examine,
        "CREATE":       do_create,
        "DELETE":       delete,
        "RENAME":       rename,
        "SUBSCRIBE":    subscribe,
        "UNSUBSCRIBE":  unsubscribe,
        "LIST":         list,
        "LSUB":         lsub,
        "STATUS":       status,
        "APPEND":       append,
    ]),
    STATE_SELECTED: ([
        "CAPABILITY":   capability,
        "NOOP":         noop,

        "LOGOUT":       logout,
        "SELECT":       select,
        "EXAMINE":      examine,
        "CREATE":       do_create,
        "DELETE":       delete,
        "RENAME":       rename,
        "SUBSCRIBE":    subscribe,
        "UNSUBSCRIBE":  unsubscribe,
        "LIST":         list,
        "LSUB":         lsub,
        "STATUS":       status,
        "APPEND":       append,
        "CHECK":        check,
        "CLOSE":        close,
        "EXPUNGE":      expunge,
        "SEARCH":       do_search,
        "FETCH":        fetch,
        "STORE":        store,
        "COPY":         copy,
        "UID":          uid,
    ]),
]);



/**********************************************************
 * conversion, parser...
 */

//converts a timestamp to a human-readable form
static string time_to_string(int timestamp)
{
    array(string) month=({"Jan","Feb","Mar","Apr","May","Jun",
                          "Jul","Aug","Sep","Oct","Nov","Dec"});

    mapping(string:int) parts=localtime(timestamp);
    parts["year"]+=1900;
    string result;
    if(parts["mday"]<10) result=" "+parts["mday"];
    else result=(string)parts["mday"];
    result=result+"-"+month[parts["mon"]]+"-"+parts["year"]+" ";
    if(parts["hour"]<10) result+="0"+parts["hour"];
    else result+=parts["hour"];
    result+=":";

    if(parts["min"]<10) result+="0"+parts["min"];
    else result+=parts["min"];
    result+=":";

    if(parts["sec"]<10) result+="0"+parts["sec"];
    else result+=parts["sec"];
    result+=" ";

    int timezone=parts["timezone"]/-3600;
    if(timezone<0)
    {
        timezone=0-timezone;
        result+="-";
    }
    else result+="+";
    if(timezone<10) result=result+"0"+timezone+"00";
    else result=result+timezone+"00";
    return result;
}

//convert a flag-pattern to a string
static string flags_to_string(int flags)
{
    string t="";

    if (flags==0) return t;

    if (flags & SEEN) t=t+"\\Seen ";
    if (flags & ANSWERED) t=t+"\\Answered ";
    if (flags & FLAGGED) t=t+"\\Flagged ";
    if (flags & DELETED) t=t+"\\Deleted ";
    if (flags & DRAFT) t=t+"\\Draft ";

    t=String.trim_whites(t);

    return t;
}

//convert a flag-string to a number
static int string_to_flags(string flags)
{
    int t=0;
    if(flags=="") return 0;

    array parts = flags/" ";
    int err=0;

    for (int i=0;i<sizeof(parts);i++)  //parse flags
    {
        string tmp=upper_case(parts[i]);
        tmp=String.trim_whites(tmp); //remove trailing whitespace
        switch(tmp)
        {
            case "\\SEEN":
                t=t|SEEN;
                break;
            case "\\ANSWERED":
                t=t|ANSWERED;
                break;
            case "\\FLAGGED":
                t=t|FLAGGED;
                break;
            case "\\DELETED":
                t=t|DELETED;
                break;
            case "\\DRAFT":
                t=t|DRAFT;
                break;
            default: //unsupported flag -> error!
                LOG_IMAP("Unknown flag in STORE: "+tmp);
                err=1;
        }
    }

    if(err) t=-1;

    return t;
}


//convert a range-string ("4:7") to array (4,5,6,7)
//changed to array ({ 4, 7 }) (min, max) now
#if 0
static array(int) parse_range(string range)
{
    array(int) set=({});

    if(sscanf(range,"%d:%d", int minrange, int maxrange)==2)
    {
      //for(int i=min;i<=max;i++) set=set+({i});
      return ({ minrange, maxrange });
    }
    else if(sscanf(range,"%d",int val)==1) set=set+({val});
    //if range can't be parsed, an empty array is returned

    return set;
}
#else
static array parse_range(string range)
{
    if(sscanf(range,"%d:%d", int minrange, int maxrange)==2)
    {
      return ({ ({ minrange, maxrange }) });
    }
    else if(sscanf(range,"%d",int val)==1) 
      return ({ val });
    return ({ });
}
#endif

//convert a set ("2,4:7,12") to array (2,4,5,6,7,12);
//now its ( 2,(4,7),12 )
static array(int) parse_set(string range)
{
    array(int) set=({});

    array(string) parts=range/","; //split range into single ranges/numbers
    foreach(parts,string tmp) {set=set+parse_range(tmp);}

    return set;
}

//split a quoted string into its arguments
static array(string) parse_quoted_string(string data)
{
    array(string) result=({});

    if(search(data,"\"")!=-1)
    {
        //process string
        int i=0,j=0;
        while(i<sizeof(data))
        {
            switch (data[i])
            {
                case '\"':
                    j=search(data,"\"",i+1); //search for matching "
                    if (j==-1) return ({}); //syntax error
                    else result=result+({data[i+1..j-1]});
                    i=j+1;
                    break;
                case ' ':
                    i=i+1;
                    break;
                default:
                    j=search(data," ",i); //unquoted string mixed with quoted string
                    if (j==-1)
                    {
                        result=result+({data[i..sizeof(data)-1]});
                        i=sizeof(data);
                    }
                    else
                    {
                        result=result+({data[i..j-1]});
                        i=j+1;
                    }
                    break;
            }
        }
    }
    else result=data/" "; //data had no ", just split at spaces

    return result;
}

//remove the quoting "..." from a string
static string unquote_string(string data)
{
    if(search(data,"\"")==-1)
        return data;
    else
        return data[1..sizeof(data)-2];
}

string mimetype(object obj)
{
    mapping header=obj->query_attribute(MAIL_MIMEHEADERS);
    string tmp;
    if(mappingp(header))
    {
        tmp=header["content-type"];
        if(!zero_type(tmp))
            sscanf(tmp,"%s;",tmp);
        else tmp=obj->query_attribute(DOC_MIME_TYPE);
    }
    else tmp=obj->query_attribute(DOC_MIME_TYPE);
    return upper_case(tmp);
}

//parse the parameter of a fetch-command
//see rfc3501 for details
static array(string) parse_fetch_string(string data)
{
    array(string) result=({});
    array(string) tmp;

    if(data[0]=='(')
    {
        if(data[sizeof(data)-1]==')')
            {
                data=data[1..sizeof(data)-2]; //remove ()
                tmp=parse_quoted_string(data);
            }
    }
    else tmp=({data}); //parameter has only one argument

    int i=0;
    while(i<sizeof(tmp))
    {
        switch(upper_case(tmp[i]))
        {
            case "ENVELOPE":
            case "FLAGS":
            case "INTERNALDATE":
            case "RFC822":
            case "RFC822.HEADER":
            case "RFC822.SIZE":
            case "RFC822.TEXT":
            case "BODY":
            case "BODYSTRUCTURE":
            case "UID":
                string t=upper_case(tmp[i]);
                result=({t})+result;
                i++;
                break;
            case "ALL":
                result=({"FLAGS","INTERNALDATE","RFC822.SIZE","ENVELOPE"})+result;
                i++;
                break;
            case "FAST":
                result=({"FLAGS","INTERNALDATE","RFC822.SIZE"})+result;
                i++;
                break;
            case "FULL":
                result=({"FLAGS","INTERNALDATE","RFC822.SIZE","ENVELOPE","BODY"})+
                 result;
                i++;
                break;
            default:
                if(search(upper_case(tmp[i]),"BODY")!=-1) //"BODY..." has special syntax
                {
                    string t="";
                    int j=i+1;
                    if(j==sizeof(tmp)) //last argument, no further processing needed
                    {
                        result+=({upper_case(tmp[i])});
                        return result;
                    }
                    if(search(tmp[i],"]")==-1)
                    {
                        while(search(tmp[j],"]")==-1 && j<sizeof(tmp))
                            j++; //search for closing ]
                        if(j<sizeof(tmp))
                            for(int a=i;a<=j;a++) t+=tmp[a]+" ";
                            //copy the whole thing as one string
                        else
                        {
                            LOG_IMAP("unexpected end of string while parsing BODY...");
                            return ({}); //syntax error
                        }

                        t=t[0..sizeof(t)-2];
                        result+=({t});
                        i=j+1;
                    }
                    else
                    {
                        result+=({upper_case(tmp[i])});
                        i++;
                    }
                }
                else
                {
                    LOG_IMAP("unknown argument to FETCH found: "+upper_case(tmp[i]));
                    return ({}); //syntax error
                }
        }//switch
    }//while
    return result;
}

//reformat a mail-adress, see rfc3501
string adress_structure(string data)
{
    data-="\"";
    string result="(";

    array(string) parts=data/",";
    for(int i=0;i<sizeof(parts);i++)
    {
        string name,box,host;
        int res=sscanf(parts[i],"%s<%s@%s>",name,box,host);
        if(res!=3)
        {
            res=sscanf(parts[i],"%s@%s",box,host); 
            if (res!=2)
            {
                LOG_IMAP("parse error in adress_structure() !");
                return ""; //parse error
            }
            name="NIL";
        }
        if(sizeof(name)==0) name="NIL";
        else
        {
            name=String.trim_whites(name);
            name="\""+name+"\"";
        }
        result+="("+name+" NIL \""+box+"\" \""+host+"\")";
    }

    result+=")";
    return result;
}

//convert header-informations to structured envelope-data
string get_envelope_data(int num)
{
    mapping(string:string) headers=oMailBox->get_message(num)->header();
    string t,result="(\"";

    t=headers["date"];
    if(t==0) t=time_to_string(oMailBox->get_message(num)->internal_date());
    result=result+t+"\" ";

    t=headers["subject"];
    if(t==0) t="";
    result=result+"\""+t+"\" ";

    string from=headers["from"];
    if(from==0) from="NIL";
        else from=adress_structure(from);
    result=result+from+" ";

    t=headers["sender"];
    if(t==0) t=from;
        else t=adress_structure(t);
    result=result+t+" ";

    t=headers["reply-to"];
    if(t==0) t=from;
        else t=adress_structure(t);
    result=result+t+" ";

    t=headers["to"];
    if(t==0) t="NIL";
        else t=adress_structure(t);
    result=result+t+" ";

    t=headers["cc"];
    if(t==0) t="NIL";
        else t=adress_structure(t);
    result=result+t+" ";

    t=headers["bcc"];
    if(t==0) t="NIL";
        else t=adress_structure(t);
    result=result+t+" ";

    t=headers["in-reply-to"];
    if(t==0) t="NIL";
        else t="\""+t+"\"";
    result=result+t+" ";

    t=headers["message-id"];
    if(t==0) t="NIL";
        else t="\""+t+"\"";
    result=result+t;

    result+=")";
    return result;
}

//combine all headers of a message to one string
string headers_to_string(mapping headers)
{
    string result="";

    foreach(indices(headers),string key)
        result+=String.capitalize(key)+": "+headers[key]+"\r\n";

    return result+"\r\n"; //header and body are seperated by newline
}

//parse & process the "BODY..." part of a fetch-command
//see rfc3501 for complete syntax of "BODY..."
string process_body_command(Message msg, string data)
{
    string result,tmp,dummy,cmd,arg;
    mapping(string:string) headers;
    int i=0;

    data-=".PEEK"; //already processed in fetch(...)
    while(data[i]!='[' && i<sizeof(data)) i++;
    if(i==sizeof(data)) return ""; //parse error
    result=data[0..i];
    tmp=data[i+1..sizeof(data)-2];
    if(sscanf(tmp,"%s(%s)", cmd, arg)==0)
        cmd=tmp;
    cmd-=" ";
    switch(cmd)
    {
        case "HEADER":
            headers=msg->header();
            dummy=headers_to_string(headers);
            result+="HEADER] {"+sizeof(dummy)+"}\r\n"+dummy;
            break;
        case "TEXT":
            dummy=msg->body()+"\r\n";
            result+="TEXT] {"+sizeof(dummy)+"}\r\n"+dummy;
            break;
        case "HEADER.FIELDS":
            dummy="";
            headers=msg->header();
            array(string) wanted=arg/" ";
            foreach(wanted,string key)
                if(headers[lower_case(key)]!=0)
                    dummy+=String.capitalize(lower_case(key))+
                     ": "+headers[lower_case(key)]+"\r\n";
            dummy+="\r\n";
            result+="HEADER] {"+sizeof(dummy)+"}\r\n"+dummy;
            break;
        default:
            int part;
            if(sscanf(cmd,"%d",part)==1)
            {
                object target;
                if(msg->has_attachments())
                {
                    target=msg->attachments()[part-1];
                    dummy=target->body()+"\r\n";
                }
                else
                    dummy=msg->body();

                result+=part+"] {"+sizeof(dummy)+"}\r\n"+dummy;
            }
            else
            {
                dummy=msg->complete_text()+"\r\n";
                result+="] {"+sizeof(dummy)+"}\r\n"+dummy;
            }
            break;
    }

    return result;
}

string get_bodystructure_msg(Messaging.Message obj)
{
    mapping header;
    string type,subtype,result,tmp;

    type=obj->type();
    subtype=obj->subtype();    
    result="(\""+type+"\" \""+subtype+"\" ";
    header=obj->header();
    tmp=header["content-type"];
    LOG_IMAP("content-type header:%O",tmp);
    if(!zero_type(tmp) && (search(tmp,";")!=-1))
    {
        sscanf(tmp,"%*s; %s",tmp);
        array(string) parts=tmp/";";
        LOG_IMAP("parts=%O",parts);
        result+="(";
        foreach(parts, string part)
        {
            part = String.trim_whites(part);
            sscanf(part,"%s=%s",string left, string right);
            right-="\"";
            result+="\""+upper_case(left)+"\" \""+right+"\" ";
        }
        result = String.trim_whites(result) + ") ";
    }
    else result+="NIL ";

    tmp=header["content-id"];
    if(!zero_type(tmp))
        result+="\""+tmp+"\" ";
    else result+="NIL ";
    tmp=header["content-description"];
    if(!zero_type(tmp))
        result+="\""+tmp+"\" ";
    else result+="NIL ";
    tmp=header["content-transfer-encoding"];
    if(!zero_type(tmp))
        result+="\""+tmp+"\" ";
    else result+="\"8BIT\" ";

    int size=obj->body_size();
    if(obj->is_attachment()) size+=2;
    result+=size+" ";
    result+=sizeof(obj->body()/"\n")+")";
    
    return result;
}

//get the imap-bodystructure of a message
string get_bodystructure(Message msg)
{
    string result="";
    
    int iAttch=msg->has_attachments();
    if(iAttch)
    {
        array(Message) elems=msg->attachments();
        result="(";
        for(int i=0;i<sizeof(elems);i++)
            result+=get_bodystructure_msg(elems[i]);
        result+=" \"MIXED\")";
    }
    else
        result+=get_bodystructure_msg(msg);
    return result;
}

static void send_reply_untagged(string msg)
{
    send_message("* "+msg+"\r\n");
}

static void send_reply(string tag, string msg)
{
    call(send_message, 0, tag+" "+msg+"\r\n");
}

static void send_reply_continue(string msg)
{
    send_message("+ "+msg+"\r\n");
}

void create(object f)
{
    ::create(f);

    string sTime=ctime(time());
    sTime=sTime-"\n";   //remove trailing LF
    send_reply_untagged("OK IMAP4rev1 Service Ready on "+_Server->get_server_name()+", "+sTime);
}

//called automatic for selected events
void notify_enter(int event, mixed ... args)
{
    if(args[0]->get_object_id()!=iUIDValidity) return;
     //target object is not the mailbox -> ignore this event
    object what;
    if(event & EVENTS_MONITORED) what=args[3];
    else
    {
        if(event & EVENT_ANNOTATE) what=args[2];
        else what=args[1];
    }
    if(what->get_object_class() & oMailBox->allowed_types())
    { //only update if new object can be converted to mail
        int id=what->get_object_id();
        LOG_IMAP(oUser->get_identifier()+" recieved new mail #"+id);
        if(!zero_type(mMessageNums[id]))
            LOG_IMAP("ignored - mail is not new...");
        else
        {
            int num=oMailBox->get_num_messages();
            send_reply_untagged(num+" EXISTS");
            mMessageNums+=([id:num]); //new message added, update mapping of uids to msns
        }
    }
}

void notify_leave(int event, mixed ... args)
{
    if(args[0]->get_object_id()!=iUIDValidity) return;
     //target object is not the mailbox -> ignore this event
    object what;
    if(event & EVENTS_MONITORED) what=args[3];
    else
    {
        if(event & EVENT_REMOVE_ANNOTATION) what=args[2];
        else what=args[1];
    }
    if(what->get_object_class() & oMailBox->allowed_types())
    { //only update if removed object can be converted to mail
        int id=what->get_object_id();
        LOG_IMAP("Mail #"+id+
         " removed from mailbox of "+oUser->get_identifier());
        if(zero_type(mMessageNums[id]))
            LOG_IMAP("ignored - mail is already removed...");
        else
        {
            send_reply_untagged(mMessageNums[id]+" EXPUNGE");
            m_delete(mMessageNums,id);
            //message deleted, remove its record from mapping of uids to msns
        }
    }
}

class IMAPListener {
   inherit Events.Listener;

   function fCallback; //stores the callback function
   void create(int events, object obj, function callback) {
     ::create(events, PHASE_NOTIFY, obj, 0);
     fCallback = callback;
     obj->listen_event(this_object());
   }

   void notify(int event, mixed args, object eObject) {
     if ( functionp(fCallback) )
       fCallback(event, @args);
   }

   mapping save() { return 0; }

   string describe() {
     return "IMAPListener()";
   }
}

void reset_listeners()
{
    if(arrayp(alEnter))
        foreach(alEnter,object tmp) destruct(tmp);
    alEnter=({});
    if(arrayp(alLeave))
        foreach(alLeave,object tmp) destruct(tmp);
    alLeave=({});
}

/***************************************************************************
 * IMAP commands
 */


static void capability(string tag, string params)
{
    if ( sizeof(params)>0 ) send_reply(tag,"BAD arguments invalid");
    else
    {
        send_reply_untagged("CAPABILITY IMAP4rev1");
        send_reply(tag,"OK CAPABILITY completed");
    }
}

static void noop(string tag, string params)
{
    send_reply(tag,"OK NOOP completed");
}

static void logout(string tag, string params)
{
    _state = STATE_LOGOUT;
    reset_listeners();
    if(objectp(oMailBox)) destruct(oMailBox);
    if(objectp(oWorkarea)) destruct(oWorkarea);
    send_reply_untagged("BYE server closing connection");
    send_reply(tag,"OK LOGOUT complete");

    if( objectp(oUser) )
        oUser->disconnect();

    close_connection();
}

static void authenticate(string tag, string params)
{
    send_reply(tag,"NO AUTHENTICATE command not supported - use LOGIN instead");
}

static void starttls(string tag, string params)
{
    send_reply(tag,"NO [ALERT] STARTTLS is not supported by this server");
}

static void login(string tag, string params)
{
    array(string) parts = parse_quoted_string(params);
    if( sizeof(parts)==2 )
    {
        oUser = _Persistence->lookup_user(parts[0]);
        if ( objectp(oUser) )
        {
            if ( oUser->check_user_password(parts[1]) ) //passwd ok, continue
            {
                login_user(oUser);
                aSubscribedFolders=oUser->query_attribute(MAIL_SUBSCRIBED_FOLDERS);
                if(!arrayp(aSubscribedFolders))
                {
                    aSubscribedFolders=({});
                    oUser->set_attribute(MAIL_SUBSCRIBED_FOLDERS,aSubscribedFolders);
                }
                _state = STATE_AUTHENTICATED;
                send_reply(tag,"OK LOGIN completed");
                
                LOG_IMAP("user "+oUser->get_identifier()+
                         " logged in, subscribed folders:%O",aSubscribedFolders);
            }
            else send_reply(tag,"NO LOGIN failed");
        }
        else send_reply(tag,"NO LOGIN failed");
    }
    else send_reply(tag,"BAD arguments invalid");
}

static void select(string tag, string params)
{
    //deselect any selected mailbox
    _state = STATE_AUTHENTICATED;
    iUIDValidity=0;
    reset_listeners();

    params=decode_mutf7(unquote_string(params));
    array(string) folders=params/"/";

    if ( upper_case(folders[0])=="INBOX" || folders[0]=="workarea" )
    {
        if (upper_case(folders[0])=="INBOX")
        {
            if(!objectp(oInbox))
                oInbox = Messaging.get_mailbox(oUser);
            oMailBox = oInbox;
        }
        else //path starts with "workarea"...
        {
            if(!objectp(oWorkarea))
                oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
            oMailBox = oWorkarea;
        }
        if(sizeof(folders)>1) //subfolder of inbox or workarea
        {
            Messaging.BaseMailBox tmp = oMailBox;
            tmp=tmp->get_subfolder(folders[1..sizeof(folders)-1]*"/");
            if(objectp(tmp)) oMailBox = tmp;
            else oMailBox=0; //subfolder doesn't exist
        }
        
        if(objectp(oMailBox))
        {
            _state = STATE_SELECTED;
            iUIDValidity=oMailBox->get_object_id();
            mMessageNums=oMailBox->get_uid2msn_mapping();
//            LOG_IMAP("selected mailbox #"+iUIDValidity);
//            LOG_IMAP("mapping uid<->msn is: %O",mMessageNums);

            array(int) events = oMailBox->enter_event();
            foreach(events, int event)
                alEnter+=({IMAPListener(event,oMailBox->this(), notify_enter)});
            events = oMailBox->leave_event();
            foreach(events, int event)
                alLeave+=({IMAPListener(event,oMailBox->this(), notify_leave)});

            int num = oMailBox->get_num_messages();
        
            send_reply_untagged("FLAGS (\\Answered \\Deleted \\Seen \\Flagged \\Draft)");
            send_reply_untagged("OK [PERMANENTFLAGS (\\Answered \\Deleted \\Seen \\Flagged \\Draft)]");
            send_reply_untagged(num+" EXISTS");
            send_reply_untagged("0 RECENT"); //"recent"-flag is not supported yet
            send_reply_untagged("OK [UIDVALIDITY "+iUIDValidity+"] UIDs valid");

            send_reply(tag,"OK [READ-WRITE] SELECT completed");
         }
         else send_reply(tag,"NO SELECT failed, Mailbox does not exist");
    }
    else send_reply(tag,"NO SELECT failed, Mailbox does not exist");
}

static void examine(string tag, string params)
{
    //deselect any selected mailbox
    _state = STATE_AUTHENTICATED;
    iUIDValidity=0;
    reset_listeners();

    //TODO: support subfolders of inbox
    if ( params=="INBOX" )
    {
        _state = STATE_SELECTED;
        oMailBox = Messaging.get_mailbox(oUser);
        iUIDValidity=oMailBox->get_object_id();

        int num = oMailBox->get_num_messages();

        send_reply_untagged("FLAGS (\\Answered \\Deleted \\Seen \\Flagged \\Draft)");
        send_reply_untagged(num+" EXISTS");
        send_reply_untagged("0 RECENT");
        send_reply_untagged("OK [UIDVALIDITY "+iUIDValidity+"] UIDs valid");

        send_reply(tag,"OK [READ-ONLY] EXAMINE completed");
    }
    else send_reply(tag,"NO EXAMINE failed, Mailbox does not exist");
}

static void do_create(string tag, string params)
{
    array(string) parts = parse_quoted_string(decode_mutf7(params));

    if(sizeof(parts)==1)
    {
        array(string) folders = parts[0]/"/"; //separate hierarchy-levels
        Messaging.BaseMailBox tmp;
        LOG_IMAP("CREATE: " +parts[0]);
        if(upper_case(folders[0])=="INBOX" || folders[0]=="workarea")
        {
            if(upper_case(folders[0])=="INBOX")
            {
                if(!objectp(oInbox))
                    oInbox = Messaging.get_mailbox(oUser);
                tmp=oInbox;
            }
            else
            {
                if(!objectp(oWorkarea))
                    oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
                tmp=oWorkarea;
            }
        }
        else //try to create subfolder outside inbox or workarea
        {
            send_reply(tag,"NO [ALERT] cannot create top-level mailboxes");
            return;
        }
                
        int i=1;
        //skip folders in hierarchy that already exist
        while(i<sizeof(folders) && objectp(tmp->get_subfolder(folders[i])))
        {
            tmp=tmp->get_subfolder(folders[i]);
            i++;
        }
        
        //all subfolders listed in 'params' exist -> nothing to do...
        if(i==sizeof(folders))
        {
            send_reply(tag, "NO CREATE failed, folder already exists!");
            return;
        }

        //create ALL subfolders given in 'params' that do not exist
        while(i<sizeof(folders))
        {
            if(folders[i]!="")
            {
                LOG_IMAP("about to create folder "+folders[i]);
                int result=tmp->create_subfolder(folders[i]);
                if(result==0)
                {
                    send_reply(tag,"NO CREATE unable to create that folder");
                    return;
                }
                tmp=tmp->get_subfolder(folders[i]);
                LOG_IMAP("created folder "+folders[i]+"["+tmp->get_object_id()+"]");
                i++;
            }
            else
            {
                if(i==sizeof(folders)-1)
                {
                    send_reply(tag,"OK CREATE completed");
                    return;
                }
                LOG_IMAP("illegal call to CREATE: "+parts[0]);
                send_reply(tag,"NO CREATE unable to create that folder");
                return;
            }
        }
        send_reply(tag,"OK CREATE completed");
    }
    else send_reply(tag,"BAD arguments invalid");
}

static void delete(string tag, string params)
{
    array(string) parts = parse_quoted_string(decode_mutf7(params));

    if(sizeof(parts)==1)
    {
        LOG_IMAP("DELETE called for "+parts[0]);
        if(upper_case(parts[0])=="INBOX")
        {
            send_reply(tag,"NO cannot delete inbox");
            return;
        }
        array(string) folders = parts[0]/"/";
        int i=0; 
        Messaging.BaseMailBox tmp;
        if(upper_case(folders[0])=="INBOX")
        {
            i++;
            if(!objectp(oInbox))
                oInbox = Messaging.get_mailbox(oUser);

            tmp=oInbox;
        }
        int success=1;
        
        while(i<sizeof(folders) && success && objectp(tmp))
        {
            LOG_IMAP("searching for "+folders[i]+" in "+tmp->get_identifier()+"["+tmp->get_object_id()+"]");
            object tt=tmp->get_subfolder(folders[i]);
            if( !objectp(tt) )
            {
                success=0;
                LOG_IMAP("not found...");
            }
            else tmp=tt;
            i++;
        }
        if(!objectp(tmp)) success=0;
        if(success)
        {
            //delete folder folders[i] if empty
            LOG_IMAP("DELETE found mailbox "+parts[0]+": "+tmp->get_identifier()+"["+tmp->get_object_id()+"]");
            if(tmp->has_subfolders()==0)
            {
                int id=-1;
                if(objectp(oMailBox)) id=oMailBox->get_object_id();
                if(tmp->get_object_id()!=id)
                {
                    LOG_IMAP("deleting mailbox "+parts[0]);
                    tmp->delete();
                    send_reply(tag,"OK DELETE succeded");
                }
                else send_reply(tag,"NO cannot delete selected folder, please deselect first");
            }
            else send_reply(tag,"NO folder has subfolders, delete them first");
        }
        else send_reply(tag,"NO folder does not exist");
    }
    else send_reply(tag,"BAD arguments invalid");
}

static void rename(string tag, string params)
{
    array(string) parts = parse_quoted_string(params);

    if(sizeof(parts)==2) send_reply(tag,"NO RENAME Permission denied");
    else send_reply(tag,"BAD arguments invalid");
}

static void subscribe(string tag, string params)
{
    array(string) parts = parse_quoted_string(decode_mutf7(params));

    if(sizeof(parts)==1)
    {
        array(string) folders=parts[0]/"/"; //split mailbox-name at hierarchy-delimiter "/"
        if(!(upper_case(folders[0])=="INBOX" || folders[0]=="workarea"))
        {
            send_reply(tag,"NO SUBSCRIBE can't subscribe to that name");
            return;
        }
        Messaging.BaseMailBox tmp;
        if(upper_case(folders[0])=="INBOX")
        {
            folders[0]="INBOX";
            if(!objectp(oInbox))
                oInbox = Messaging.get_mailbox(oUser);
            tmp=oInbox;
        }
        else
        {
            if(!objectp(oWorkarea))
                oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
            tmp=oWorkarea;
        }
        if(sizeof(folders)>1) tmp=tmp->get_subfolder(folders[1..sizeof(folders)-1]*"/");
        if(objectp(tmp))
        {
            string res=folders*"/";
            LOG_IMAP("subscribed to folder "+res);
            aSubscribedFolders+=({res});
            aSubscribedFolders=sort(Array.uniq(aSubscribedFolders));
            oUser->set_attribute(MAIL_SUBSCRIBED_FOLDERS,aSubscribedFolders);
            send_reply(tag,"OK SUBSCRIBE completed");
        }
        else send_reply(tag,"NO SUBSCRIBE can't subscribe to that name");
    }
    else send_reply(tag,"BAD arguments invalid");
    
    return;
}

static void unsubscribe(string tag, string params)
{
    array(string) parts = parse_quoted_string(decode_mutf7(params));

    if(sizeof(parts)==1)
    {
        if(search(aSubscribedFolders,parts[0])!=-1)
        {
            aSubscribedFolders-=({parts[0]});
            oUser->set_attribute(MAIL_SUBSCRIBED_FOLDERS,aSubscribedFolders);
            send_reply(tag,"OK UNSUBSCRIBE completed");
        }
        else send_reply(tag,"NO UNSUBSCRIBE can't unsubscribe that name");
    }
    else send_reply(tag,"BAD arguments invalid");
    
    return;
}

object validate_reference_name(string refname)
{
    array(string) parts=refname/"/"; parts-=({""});
    object startbox;
    if(upper_case(parts[0])=="INBOX") // "inbox" is case-insensitive
    {
        parts[0]=="INBOX";
        if(!objectp(oInbox))
            oInbox = Messaging.get_mailbox(oUser);
        startbox=oInbox;
    }
    else if(parts[0]=="workarea")
    {
        if(!objectp(oWorkarea))
            oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
        startbox=oWorkarea;
    }
    else //start of reference name is invalid (not "inbox" or "workarea")
        return 0;

    object tmp;
    if(sizeof(parts)>1) 
        tmp=startbox->get_subfolder(parts[1..sizeof(parts)-1]*"/");
    else tmp=startbox;
    if(objectp(tmp)) return tmp;
    else return 0;
}

static void list_all_folders(int depth)
{
    array(string) folders;
    int i;
    if(!objectp(oInbox))
        oInbox = Messaging.get_mailbox(oUser);
    if(!objectp(oWorkarea))
        oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
    //list all subfolders of inbox
    folders=oInbox->list_subfolders(depth-1);
    send_reply_untagged("LIST () \"/\" \"INBOX\"");
    for(i=0;i<sizeof(folders);i++)
        send_reply_untagged("LIST () \"/\" \"INBOX/"+encode_mutf7(folders[i])+"\"");
    //list all subfolders of workarea
    folders=oWorkarea->list_subfolders(depth-1);
    send_reply_untagged("LIST () \"/\" \"workarea\"");
    for(i=0;i<sizeof(folders);i++)
        send_reply_untagged("LIST () \"/\" \"workarea/"+encode_mutf7(folders[i])+"\"");
}

static void list(string tag, string params)
{
    array (string) args=parse_quoted_string(params);
    
    //first argument contains reference-name ("root" of mailbox-path in 2nd arg)
    //second argument contains mailbox name (wildcards allowed)
    //for further details see rfc3501, Section 6.3.8.
    
    if(sizeof(args)!=2)
    {
        send_reply(tag,"BAD LIST arguments invalid");
        return;
    }
    
    string refname = decode_mutf7(args[0]);
    string boxname = decode_mutf7(args[1]);
    string start;
    array(string) parts;
    object startbox;
    LOG_IMAP("LIST called with reference: "+refname+" and mailbox: "+boxname);
    int result=0;
    
    if(refname!="")
    {
        startbox = validate_reference_name(refname);
        if(objectp(startbox)) result=1;
        parts=refname/"/"; parts-=({""});
        if(upper_case(parts[0])=="INBOX") parts[0]="INBOX";
        start=parts*"/" + "/"; //add hierarchy-delimiter at end of starting path
        LOG_IMAP("result of validate_reference_name: "+result);
//        LOG_IMAP("startbox: %O",startbox);
//        LOG_IMAP("start: "+start);
//        LOG_IMAP("parts: %O",parts);
    }
    if(boxname=="")
    {
        if(refname!="")
        {
            if(result==0)
            {
                send_reply(tag,"OK LIST completed");
                return;
            }
        }
        else //special case: boxname AND refname are empty
        {
            send_reply_untagged("LIST (\\Noselect) \"/\" \"\"");
            send_reply(tag,"OK LIST completed");
            return;
        }
    }
    else //boxname!=""
    {
        if(refname!="" && result==0)
        {
            send_reply(tag,"OK LIST completed");
            return;
        }
    }        
    if(refname=="" && (boxname[0]=='%' || boxname=="*" ))
    {
        if(boxname=="*") list_all_folders(-1);
        else //boxname=="%"
        {
            int depth=sizeof(boxname/"/"-({}));
            list_all_folders(depth);
        }
        send_reply(tag,"OK LIST completed");
        return;
    }
    int i=0;
    if(upper_case(boxname)=="INBOX*")
    {
        boxname="*"; refname="INBOX/"; start="INBOX/";
        if(!objectp(oInbox))
            oInbox=Messaging.get_mailbox(oUser);
        startbox=oInbox;
        send_reply_untagged("LIST () \"/\" \"INBOX\"");
    }
    if(boxname=="workarea*")
    {
        boxname="*"; refname="workarea/"; start="workarea/";
        if(!objectp(oWorkarea))
            oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
        startbox=oWorkarea;
        send_reply_untagged("LIST () \"/\" \"workarea\"");
    }
    parts=boxname/"/";
    if(upper_case(parts[0])=="INBOX") parts[0]="INBOX";
    if(refname=="")
    {
        if(parts[0]=="INBOX")
        {
            if(!objectp(oInbox))
                oInbox=Messaging.get_mailbox(oUser);
            startbox=oInbox;
            start="INBOX/";
            if(sizeof(parts)==1) send_reply_untagged("LIST () \"/\" \"INBOX\"");
        }
        else if(parts[0]=="workarea")
        {
            if(!objectp(oWorkarea))
                oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
            startbox=oWorkarea;
            start="workarea/";
            if(sizeof(parts)==1) send_reply_untagged("LIST () \"/\" \"workarea\"");
        }
        if(sizeof(parts)==1)
        {
            send_reply(tag,"OK LIST completed");
            return;
        }
    }
    parts-=({"INBOX"});
    parts-=({"workarea"});
    while(i<sizeof(parts) && parts[i]!="%" && parts[i]!="*")
        i++; //search for first wildcard in boxname
    if(i==sizeof(parts) && parts[i-1]!="%" && parts[i-1]!="*") //no wildcard, test if folder exists
    {
        string path = parts[0..i-1]*"/";
        object tmp=startbox->get_subfolder(path);
        if(objectp(tmp))
        {
            start+=path;
            send_reply_untagged("LIST () \"/\" \""+encode_mutf7(start)+"\"");
        }
        send_reply(tag,"OK LIST completed");
        return;
    }
    if(i>0)
    {
        string path = parts[0..i-1]*"/"; //path until the first wildcard
        object tmp=startbox->get_subfolder(path);
        if(objectp(tmp))
        {
            startbox=tmp;
            start+=path+"/";
        }
        else //refname + boxname (without wildcards) is invalid
        {
            send_reply(tag,"OK LIST completed");
            return;
        }
    }
    int depth;
    if(parts[i]=="*") depth=-1; //get _all_ subfolders
    else // parts[i]=="%", "count" # of %'s to get depth
    {
        depth=1;
        if(i<sizeof(parts)-1) //current "%" is not the last part
            for(int j=i+1;j<sizeof(parts);j++)
            {
                if(parts[j]=="%") depth++;
                else
                {
                    LOG_IMAP("error in LIST-Command: "+refname+" "+boxname);
                    send_reply(tag,"NO LIST cannot list that reference or name");
                    return;
                }
            }
    }
    array(string) folders = startbox->list_subfolders(depth);
    if(arrayp(folders))
        for(int j=0;j<sizeof(folders);j++)
            send_reply_untagged("LIST () \"/\" \""+start+encode_mutf7(folders[j])+"\"");
    send_reply(tag,"OK LIST completed");
    return;
}

static void lsub(string tag, string params)
{
    array(string) args=parse_quoted_string(params);
    if(sizeof(args)==2)
    {
        args[0]=decode_mutf7(args[0]);
        args[1]=decode_mutf7(args[1]);
        if(args[0]=="" && (args[1]=="*" || upper_case(args[1])=="INBOX*"))
        {
            aSubscribedFolders=oUser->query_attribute(MAIL_SUBSCRIBED_FOLDERS);
            for(int i=0;i<sizeof(aSubscribedFolders);i++)
                send_reply_untagged("LSUB () \"/\" \""+encode_mutf7(aSubscribedFolders[i])+"\"");
            send_reply(tag,"OK LSUB completed");
        }
        else send_reply(tag,"OK LSUB completed");
    }
    else send_reply(tag,"BAD arguments invalid");
}

static void status(string tag, string params)
{
    string mailbox, what;
    if(sscanf(params,"%s (%s)", mailbox, what)!=2)
    {
        send_reply(tag,"BAD arguments invalid");
        return;
    }
    Messaging.BaseMailBox mbox;
    array(string) parts = decode_mutf7(unquote_string(mailbox))/"/";
    if(upper_case(parts[0])=="INBOX") //lookup mailbox
    {
        parts[0]="INBOX";
        if(!objectp(oInbox))
            oInbox = Messaging.get_mailbox(oUser);
        mbox = oInbox;
    }
    else if(parts[0]=="workarea")
    {
        if(!objectp(oWorkarea))
            oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
        mbox = oWorkarea;
    }
    if(sizeof(parts)>1) mbox=mbox->get_subfolder(parts[1..sizeof(parts)-1]*"/");
    if(!objectp(mbox))
    {
        send_reply(tag,"NO mailbox does not exist");
        return;
    }
    mailbox=encode_mutf7(parts*"/");
    array(string) items=what/" ";
    string result="";
    foreach(items, string tmp)
    {
        switch (upper_case(tmp))
        {
            case "MESSAGES":
                result+=" MESSAGES "+mbox->get_num_messages();
                break;
            case "RECENT":
                result+=" RECENT 0"; // recent-flag is not supported
                break;
            case "UIDNEXT":
                result+=" UIDNEXT 12345"; //TODO: return correct value
                break;
            case "UIDVALIDITY":
                result+=" UIDVALIDITY "+iUIDValidity;
                break;
            case "UNSEEN":
                int max=mbox->get_num_messages();
                int unseen=max;
                for(int i=0;i<max;i++)
                    if(mbox->get_message(i)->flag()->has(SEEN)) unseen--;
                result+=" UNSEEN "+unseen;
                break;
            default:
                send_reply(tag,"BAD arguments invalid");
                return;
        }
    }
    result="("+String.trim_whites(result)+")";
    send_reply_untagged("STATUS \""+mailbox+"\" "+result);
    send_reply(tag,"OK STATUS completed");
}

static void append(string tag, string params)
{
//    LOG_IMAP("APPEND called:%O",params);
    string sFolder, sData;
    if(sscanf(params,"%s %s",sFolder,sData)!=2)
    {
        send_reply(tag,"BAD Arguments invalid");
        return;
    }
    array(string) parts=decode_mutf7(sFolder)/"/";
    if(upper_case(parts[0])=="INBOX" || parts[0]=="workarea")
    {
        Messaging.BaseMailBox tmp;
        if(upper_case(parts[0])=="INBOX")
        {
            if(!objectp(oInbox))
                oInbox=Messaging.get_mailbox(oUser);
            tmp=oInbox;
        }
        else
        {
            if(!objectp(oWorkarea))
                oWorkarea=Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
            tmp=oWorkarea;
        }
        tmp=tmp->get_subfolder(parts[1..sizeof(parts)-1]*"/");
        if(objectp(tmp))
        {
            Messaging.Message msg = Messaging.MIME2Message(sData);
            if(objectp(msg))
            {
                tmp->add_message(msg);
                send_reply(tag,"OK APPEND completed");
            }
            else send_reply(tag,"NO Syntax-error in data");
        }
        else send_reply(tag,"NO cannot append to non-existent folder");
    }
    else send_reply(tag,"NO cannot append to non-existent folder");
}

static void check(string tag, string params)
{
    send_reply(tag,"OK CHECK completed");
}

static void close(string tag, string params)
{
    _state = STATE_AUTHENTICATED;
    
    reset_listeners();
    oMailBox->delete_mails();
    
    send_reply(tag,"OK CLOSE completed");
}

static void expunge(string tag, string params)
{
    oMailBox->delete_mails();
    /* This causes the mailbox-module to delete all mails, which have the
     * deleted-flag set. The notify-function of this socket is called then
     * with a suitable "leave"-event, which sends the required "* #msn EXPUNGE"
     * message(s) to the connected mailclient.
     */

    send_reply(tag,"OK EXPUNGE completed");
}

static void do_search(string tag, string params)
{
    array(string) parts = parse_quoted_string(params);
    int i=0,err=0;
    int not=0, or=0;
    int num=oMailBox->get_num_messages();

    array(int) result=({});
    array(int) tmp=({});

    while (i<sizeof(parts))
    {
        tmp=({});
        switch(parts[i])
        {   //not all search-parameters are supported yet
            case "ALL":
                for(int j=0;j<num;j++) tmp=tmp+({j+1});
                result=tmp;
                i++;
                break;
            case "ANSWERED":
                for (int j=0;j<num;j++)
                    if(oMailBox->get_message(j)->flag()->has(ANSWERED)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "BCC":
                i+=2;
                break;
            case "BEFORE":
                i+=2;
                break;
            case "BODY":
                i+=2;
                break;
            case "CC":
                i+=2;
                break;
            case "DELETED":
                for (int j=0;j<num;j++)
                    if(oMailBox->get_message(j)->flag()->has(DELETED)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "FLAGGED":
                for (int j=0;j<num;j++)
                    if(oMailBox->get_message(j)->flag()->has(FLAGGED)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "FROM":
                i+=2;
                break;
            case "KEYWORD":
                i+=2;
                break;
            case "NEW":
                break;
            case "OLD":
                break;
            case "ON":
                i+=2;
                break;
            case "RECENT":
                i++;
                break;
            case "SEEN":
                for (int j=0;j<num;j++)
                    if(oMailBox->get_message(j)->flag()->has(SEEN)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "SINCE":
                i+=2;
                break;
            case "SUBJECT":
                i+=2;
                break;
            case "TEXT":
                i+=2;
                break;
            case "TO":
                i+=2;
                break;
            case "UNANSWERED":
                for (int j=0;j<num;j++)
                    if(!oMailBox->get_message(j)->flag()->has(ANSWERED)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "UNDELETED":
                for (int j=0;j<num;j++)
                    if(!oMailBox->get_message(j)->flag()->has(DELETED)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "UNFLAGGED":
                for (int j=0;j<num;j++)
                    if(!oMailBox->get_message(j)->flag()->has(FLAGGED)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "UNKEYWORD":
                i+=2;
                break;
            case "UNSEEN":
                for (int j=0;j<num;j++)
                    if(!oMailBox->get_message(j)->flag()->has(SEEN)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "DRAFT":
                for (int j=0;j<num;j++)
                    if(oMailBox->get_message(j)->flag()->has(DRAFT)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            case "HEADER":
                i+=3;
                break;
            case "LARGER":
                i+=2;
                break;
            case "NOT":
                not=1; i++;
                break;
            case "OR":
                or=1; i++;
                break;
            case "SENTBEFORE":
                i+=2;
                break;
            case "SENTON":
                i+=2;
                break;
            case "SENTSINCE":
                i+=2;
                break;
            case "SMALLER":
                i+=2;
                break;
            case "UID":
                i+=2;
                break;
            case "UNDRAFT":
                for (int j=0;j<num;j++)
                    if(!oMailBox->get_message(j)->flag()->has(DRAFT)) tmp=tmp+({j+1});
                result=result&tmp;
                i++;
                break;
            default:
                //todo: support "(...)"
                tmp=parse_set(parts[i]);
                if (tmp!=({}))
                {
                    result=result&tmp;
                    i++;
                }
                else
                {
                    send_reply(tag,"BAD arguments invalid");
                    return;
                }
                break;
        }
    }//while

    if(!err)
    {
        string final_result="";
        for(i=0;i<sizeof(result);i++) final_result=final_result+" "+result[i];
        send_reply_untagged("SEARCH"+final_result);
        send_reply(tag,"OK SEARCH completed");
    }
    else send_reply(tag,"BAD arguments invalid");
}


static string fetch_result(int i, array parts, function getMessageFunc,void|int uid_mode)
{
  string res=i+" FETCH (";
  if ( !functionp(getMessageFunc) )
    return "";
  Message msg = getMessageFunc(i);
  if ( !objectp(msg) )
    return "";
  if(uid_mode) res+="UID "+msg->get_object_id()+" ";
  for(int j=0;j<sizeof(parts);j++) {
    switch(parts[j]) {
    case "FLAGS":
      string tmp=flags_to_string(msg->flag()->get());
      res+="FLAGS ("+tmp+") ";
      break;
    case "UID":
      if(uid_mode) break; //UID is already in response string
      int uid=msg->get_object_id();
      res+="UID "+uid+" ";
      break;
    case "INTERNALDATE":
      res+="INTERNALDATE \""+
	time_to_string(msg->internal_date())+
	"\" ";
      break;
    case "ENVELOPE":
      res+="ENVELOPE "+
	get_envelope_data(i)+" ";
      break;
    case "RFC822.SIZE":
      res+="RFC822.SIZE "+
	msg->size()+" ";
      break;
    case "RFC822.HEADER":
      string dummy=headers_to_string(msg->header());
      res+="RFC822.HEADER {"+sizeof(dummy)+"}\r\n"+dummy;
      break;
    case "RFC822":
      string t=msg->complete_text();
      res+="RFC 822 {"+sizeof(t)+"}\r\n"+t;
      break;
    case "BODYSTRUCTURE":
    case "BODY":
      res+="BODY "+get_bodystructure(msg)+" ";
      break;
    default:
      if(search(upper_case(parts[j]),"BODY")!=-1) {
	if(search(upper_case(parts[j]),"PEEK")==-1
	   && !msg->flag()->has(SEEN)) {
	  msg->flag()->add(SEEN);
	  msg->update();
	  res+="FLAGS ("+
	    flags_to_string(msg->flag()->get())+") ";
	}
	res+=process_body_command(msg,parts[j]);
      }
      else {
	return 0;
      }
      break;
    }
  }
  return res;
}

static void fetch(string tag, string params, int|void uid_mode)
{
    int num=sscanf(params,"%s %s",string range, string what);
    if(num!=2)
    {
        send_reply(tag,"BAD arguments invalid");
        return;
    }

    int err=0;
    array(int) nums=({});
    function getMessageFunc = oMailBox->get_message;

    if(uid_mode)
    {
        LOG_IMAP("starting FETCH in uid-mode: "+range);
        
        if(search(range,"*")!=-1)
        {
            if(range=="*" || range=="1:*")
            {
                LOG_IMAP("range selects ALL messages");
                range="1:"+oMailBox->get_num_messages();
                nums=parse_set(range);
                if( nums==({}) ) err=1;
            }
            else
            {
                int start;
                sscanf(range,"%d:*",start);
                LOG_IMAP("starting uid is "+start);
                if(zero_type(mMessageNums[start])==1)
                {
                    //search for following uid
                    int maximum=0xFFFFFFFF;
                    foreach(indices(mMessageNums),int t)
                        if(t>start && t<maximum)
                            maximum=t;
                    start=maximum;
                    LOG_IMAP("uid not present, next fitting is "+start);
                }
                if(start<0xFFFFFFFF) start=mMessageNums[start];
                else start=oMailBox->get_num_messages()+1;
                LOG_IMAP("starting msn is "+start);
                nums=parse_set(start+":"+oMailBox->get_num_messages());
                if( nums==({}) ) err=1;
            }
        }
        else
        {
            nums=parse_set(range);
            if( nums==({}) ) err=1;
            getMessageFunc = oMailBox->get_message_by_oid;
            nums=oMailBox->filter_uids(nums);
            LOG_IMAP("filtered UIDS = %O\n", nums);
        }
    }
    else
    {
        if(range=="*") range="1:*";
        range=replace(range,"*",(string)oMailBox->get_num_messages());
        nums=parse_set(range);
        if( nums==({}) ) err=1;
    }

    array(string) parts=parse_fetch_string(what);
    if( parts==({}) ) err=1;
    LOG_IMAP("fetch attributes parsed, result:\n"+sprintf("%O",parts));

    if(!err)
    {
        mixed res;
        foreach(nums, mixed i)
        {
	  if ( arrayp(i) ) {
	    // min/max notation
	    for ( int j=i[0]; j < i[1]; j++ ) {
	      res = fetch_result(j, parts, getMessageFunc, uid_mode);
	      if ( !stringp(res) )
		send_reply(tag,"BAD arguments invalid");
	      else if ( strlen(res) > 0 ) {
		res=String.trim_whites(res)+")";
		send_reply_untagged(res);
	      }
	    }
	  }
	  else {
	    res = fetch_result(i, parts, getMessageFunc, uid_mode);
	    if ( !stringp(res) )
	      send_reply(tag,"BAD arguments invalid");
	    else {
	      res=String.trim_whites(res)+")";
	      send_reply_untagged(res);
	    }
	  }
	}
        send_reply(tag,"OK FETCH completed");
    }
    else
    {
        if(nums==({})) send_reply(tag,"OK FETCH completed"); //empty or invalid numbers
        else send_reply_untagged("BAD arguments invalid"); //parse error
    }
}

static void store(string tag, string params, int|void uid_mode)
{
    werror("STORE %O\n", params);
    int num=sscanf(params,"%s %s (%s)",string range,string cmd, string tflags);

    if(num!=3)
    {
        send_reply(tag,"BAD arguments invalid");
        return;
    }

    int err=0;

    array(int) nums=({});

    function getMessageFunc = oMailBox->get_message;
    if(uid_mode)
    {
        if(range=="*" || range=="1:*")
        {
            range=replace(range,"*",(string)oMailBox->get_num_messages());
            nums=parse_set(range);
            if( nums==({}) ) err=1;
        }
        else
        {
            nums=parse_set(range);
            if( nums==({}) ) err=1;
            getMessageFunc = oMailBox->get_message_by_oid;
            nums = oMailBox->filter_uids(nums);
        }
    }
    else
    {
        if(range=="*") range="1:*";
        range=replace(range,"*",(string)oMailBox->get_num_messages());
        nums=parse_set(range);
        if( nums==({}) ) err=1;
    }

    int flags=string_to_flags(tflags);
    if (flags==-1) err=1; //can't parse flags

    werror("STORE %O, flags=%O nums=%O\n", cmd, flags, nums);

    if(err==0)
    {
        int silent=0;
        string tmp;
        cmd=upper_case(cmd);

        switch(cmd)
        {
            case "FLAGS.SILENT":
                silent=1;
            case "FLAGS":
              foreach(nums,mixed i) {
                if ( !arrayp(i) ) 
                  i = ({ i, i });
                for (int j = i[0]; j <= i[1]; j++) {
                  getMessageFunc(j)->flag()->set(flags);
                  getMessageFunc(j)->update();
                  if (!silent) {
                    tmp=flags_to_string(getMessageFunc(j)->flag()->get());
                    send_reply_untagged(i+" FETCH (FLAGS ("+tmp+"))");
                  }
                }
              }
              break;
            case "+FLAGS.SILENT":
                silent=1;
            case "+FLAGS":
                foreach(nums,mixed i)
                {
                  if ( !arrayp(i) )
                    i = ({ i, i });
                  for (int j = i[0]; j <= i[1]; j++) {
                    Messaging.Message msg = getMessageFunc(j);
                    werror("Adding %O flag to %O\n", flags, msg);
                    msg->flag()->add(flags);
                    msg->update();
                    if (!silent)
                    {
                      tmp=flags_to_string(msg->flag()->get());
                      send_reply_untagged(j+" FETCH (FLAGS ("+tmp+"))");
                    }
                  }
                }
                break;
            case "-FLAGS.SILENT":
                silent=1;
            case "-FLAGS":
                foreach(nums,mixed i)
                {
                  if ( !arrayp(i) )
                    i = ({ i, i });
                  for (int j = i[0]; j <= i[1]; j++) {
                    Messaging.Message msg = getMessageFunc(j);
                    msg->flag()->del(flags);
                    msg->update();
                    if (!silent)
                    {
                        tmp=flags_to_string(msg->flag()->get());
                        send_reply_untagged(j+" FETCH (FLAGS ("+tmp+"))");
                    }
                  }
                }
                break;
            default:
                send_reply(tag,"BAD arguments invalid");
                return;
        }
        send_reply(tag,"OK STORE completed");
    }
    else send_reply(tag,"BAD arguments invalid");
}

static void copy(string tag, string params, int|void uid_mode)
{
    int num=sscanf(params,"%s %s", string range, string targetbox);
    if(num!=2)
    {
        send_reply(tag,"BAD arguments invalid");
        return;
    }

    int err=0;
    array nums = ({});
    function getMessageFunc = oMailBox->get_message;

    if(uid_mode)
    {
        if(range=="*" || range=="1:*")
            range=replace(range,"*",(string)oMailBox->get_num_messages());
        nums=parse_set(range);
        if( nums==({}) ) err=1;
        getMessageFunc = oMailBox->get_message_by_oid;
        nums = oMailBox->filter_uids(nums);
    }
    else
    {
        if(range=="*") range="1:*";
        range=replace(range,"*",(string)oMailBox->get_num_messages());
        nums=parse_set(range);
        if( nums==({}) ) err=1;
    }
    
    if(err)
    {
        send_reply(tag,"OK COPY completed");
        return;
    }

    array(string) parts = decode_mutf7(unquote_string(targetbox))/"/";
    if(upper_case(parts[0])=="INBOX" || parts[0]=="workarea")
    {
        Messaging.BaseMailBox tmp;
        if(upper_case(parts[0])=="INBOX")
        {
            if(!objectp(oInbox))
                oInbox = Messaging.get_mailbox(oUser);
            tmp = oInbox;
        }
        else
        {
            if(!objectp(oWorkarea))
              oWorkarea = Messaging.get_mailbox(oUser->query_attribute(USER_WORKROOM));
            tmp = oWorkarea;
        }
        tmp = tmp->get_subfolder(parts[1..sizeof(parts)-1]*"/");
        if(!objectp(tmp))
        {
            send_reply(tag, "NO [TRYCREATE] target mailbox does not exist");
            return;
        }
        LOG_IMAP("COPY found target mailbox: "+tmp->get_identifier());
        for(int i=0;i<sizeof(nums);i++)
        {
          if ( !arrayp(nums[i]) )
            nums[i] = ({ nums[i], nums[i] });
          for ( int j = nums[i][0]; j < nums[i][1]; j++ ) {
            LOG_IMAP("COPY processing mail #"+j);
            Message copy = getMessageFunc(j)->duplicate();
            LOG_IMAP("COPY duplicated mail #"+j);
            tmp->add_message(copy);
            LOG_IMAP("COPY stored mail #"+j+" to target "+
                     tmp->get_identifier());
          }
        }
        send_reply(tag,"OK COPY completed");
    }
    else send_reply(tag,"NO COPY cannot copy to that mailbox");
}

static void uid(string tag, string params)
{
    sscanf(params,"%s %s",string cmd,string args);
    args=String.trim_whites(args);

    switch(upper_case(cmd))
    {
        case "COPY":
            copy(tag, args, 1);
            break;
        case "FETCH":
            fetch(tag, args, 1);
            break;
        case "SEARCH":
            send_reply(tag,"NO command is not implemented yet!");
            break;
        case "STORE":
            store(tag, args, 1);
            break;
        default:
            send_reply(tag,"BAD arguments invalid");
            break;
    }
    //completion reply is already sent in called funtion
    //no further send_reply() is needed!
}

static void call_function(function f, mixed ... params)
{
  get_module("tasks")->add_task(0, this_object(), f, params, ([ ]));
}

static void process_command(string _cmd)
{
    string sTag, sCommand, sParams;
    string cmd;
    if(iContinue) //processing command continuation request
    {
        if(sizeof(_cmd)<iBytes-2)
        {
            LOG_IMAP("received "+sizeof(_cmd)+ "bytes (+2 for CRLF)");
            sData+=_cmd+"\r\n";
            iBytes-=sizeof(_cmd);
            iBytes-=2; //CRLF at end of line counts too
            LOG_IMAP(""+iBytes+" bytes remaining");
            return;
        }
        else
        {
            sData+=_cmd+"\r\n";
            iBytes=0;
            iContinue=0;
            sscanf(sCurrentCommand,"%s %s %s",sTag, sCommand, sParams);
            sCurrentCommand="";
            sParams+=" "+sData;
            function f = mCmd[_state][upper_case(sCommand)];
            if(functionp(f)) call_function(f,sTag,sParams);
            else send_reply(sTag,"BAD unknown error");
            LOG_IMAP("command continuation received "+sizeof(sData)+" bytes of data");
            return;
        }
    }    
    if(_cmd=="") return; //ignore empty command lines
    int length;
    if(sscanf(_cmd,"%s {%d}",cmd,length)==2)
    {
        iContinue=1;
        iBytes=length;
        sCurrentCommand=cmd;
        LOG_IMAP("command continuation request accepted for "+length+" bytes");
    }
    else cmd=_cmd;

    array(string) tcmd = cmd/" ";

    if(sizeof(tcmd)>1) //tag + command
    {
        if(sizeof(tcmd)==2) //command without parameter(s)
        {
            sTag=tcmd[0];
            sCommand=tcmd[1];
            sParams="";
        }
        else sscanf(cmd,"%s %s %s", sTag, sCommand, sParams);

        sCommand = upper_case(sCommand);

//      LOG_IMAP("Tag: "+sTag+" ; Command: "+sCommand+" ; Params: "+sParams);

        function f = mCmd[_state][sCommand];
        if ( functionp(f) )
        {
            if(!iContinue) call_function(f, sTag, sParams);
            else send_reply_continue("ready for literal data");
        }
        else 
        {
            send_reply(sTag,"BAD command not recognized");
            if(iContinue) iContinue=0;
        }
    }
    else send_reply(cmd,"BAD command not recognized");
}

void close_connection()
{
    reset_listeners();
    if(objectp(oMailBox)) destruct(oMailBox);
    if(objectp(oWorkarea)) destruct(oWorkarea);

    if(_state!=STATE_LOGOUT) //we got called by idle-timeout
        catch(send_reply_untagged("BYE Autologout; idle for too long"));
    ::close_connection();
}

string get_socket_name() { return "imap4"; }

int get_client_features() { return CLIENT_FEATURES_EVENTS; }
