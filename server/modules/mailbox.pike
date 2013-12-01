/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
 * Copyright (C) 2002       Christian Schmidt
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
 * $Id: mailbox.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: mailbox.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";
inherit "/net/coal/binary";

#include <macros.h>
#include <exception.h>
#include <attributes.h>
#include <database.h>

//Flags stored for each mail, also needed in net/imap.pike !!
#define SEEN     (1<<0)
#define ANSWERED (1<<1)
#define FLAGGED  (1<<2)
#define DELETED  (1<<3)
#define DRAFT    (1<<4)

//! This module simulates a Mailbox for use with pop3 and imap4
//! That is normal sTeam documents are kept inside the Mailbox,
//! but Access of them is encapsulated by some functions.

static object oMessages;

static string sServer = _Server->query_config("machine");
static string sDomain = _Server->query_config("domain");
static string sFQDN = sServer+"."+sDomain;

class MailBox {
    object           oMailBox;
    mapping mMessages = ([ ]);
    array(object)   to_delete;
    
    mapping (int:int) mMessageNums=([]);

    static void create(object o) {
        oMailBox = o;
        to_delete = ({ });
    }

    //return flags of message(num)
    int get_flags(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        int flags=inv[num]->query_attribute(MAIL_IMAPFLAGS);
        return flags;
    }

    //set flags of message(num), overwrite existing flags
    int set_flags(int num, int flags)
    {
        array(object) inv = oMailBox->get_inventory();
        mixed err = catch { inv[num]->set_attribute(MAIL_IMAPFLAGS,flags); };
        if (err==0) return inv[num]->query_attribute(MAIL_IMAPFLAGS);
        else return -1;
    }

    //add flags to message(num), keep existing flags
    int add_flags(int num, int flags)
    {
        array(object) inv = oMailBox->get_inventory();
        int tflags=get_flags(num);
        tflags = tflags | flags;

        set_flags(num,tflags);
        if(!has_flag(num,flags)) 
            set_flags(num,flags); //attribute was not set before
    }

    //remove given flags from message(num)
    int del_flags(int num, int flags)
    {
        array(object) inv = oMailBox->get_inventory();
        int tflags=get_flags(num);
        tflags = tflags & (~flags); //"substract" flags from tflags

        return set_flags(num,tflags);
    }

    //check if a flag is set or not
    int has_flag(int num,int flag)
    {
        return( get_flags(num) & flag );
    }

    //returns the internal date of a message
    int message_internal_date(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        return inv[num]->query_attribute(OBJ_CREATION_TIME);
    }

    //get the rfc2822-headers of a message
    mapping(string:string) message_headers(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        
        if(zero_type(inv[num]->query_attribute(MAIL_MIMEHEADERS)))
            add_header(num); //no headers found, create them now
            
        return inv[num]->query_attribute(MAIL_MIMEHEADERS);
    }
    
    //check if a message has a rfc822-header
    int has_header(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        return !zero_type(inv[num]->query_attribute(MAIL_MIMEHEADERS));
    }

    //add a rfc822-header to a message
    void add_header(int num, int|void force)
    {
        if(has_header(num) && !force)
        {
            LOG("Message #:"+num+" already has rfc822 data - add_header() aborted!");
            return;
        }

        array(object) inv = oMailBox->get_inventory();
        mapping(string:string) mHeader=([]);
        string tmp;
            
        LOG("creating rfc822-header for msg #"+num);
        tmp=inv[num]->query_attribute(OBJ_NAME);
        mHeader+=(["subject":tmp]);
        
        tmp=ctime(inv[num]->query_attribute(OBJ_CREATION_TIME))-"\n";
        mHeader+=(["date":tmp]);
        
        tmp=inv[num]->query_attribute(DOC_USER_MODIFIED)->get_identifier();
        string fullname = inv[num]->query_attribute(DOC_USER_MODIFIED)->query_attribute(USER_FULLNAME);
        tmp="\""+fullname+"\" <"+tmp+"@"+sFQDN+">";
        mHeader+=(["from":tmp]);

        tmp=inv[num]->query_attribute(DOC_MIME_TYPE);
        mHeader+=(["content-type":tmp]);
        
        LOG(sprintf("%O",mHeader));
        inv[num]->set_attribute(MAIL_MIMEHEADERS,mHeader);
        LOG("added rfc822-header to msg #"+num);
    }

    //returns the body of a message
    string message_body(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        return inv[num]->get_content();
    }

    //converts a sequence of uids to message sequence numbers
    array(int) uid_to_num(array(int) uids)
    {
        array(int) res=({});
        mapping(int:int) temp=([]);
        array(object) inv = oMailBox->get_inventory();
        for(int i=0;i<sizeof(inv);i++)
            temp+=([inv[i]->get_object_id():i]); //maps uids to sequence numbers

        foreach(uids, int i)
            if(zero_type(temp[i])!=1) res+=({temp[i]+1});

        return res;
    }
    
    mapping(int:int) get_uid2msn_mapping()
    {
        array(object) inv = oMailBox->get_inventory();
        mapping(int:int) temp=([]);
        for(int i=0;i<sizeof(inv);i++)
            temp+=([inv[i]->get_object_id():i+1]);
        return temp;
    }

    //logs some statistics for a specific mailbox
    void init_mailbox()
    {
        LOG("init_mailbox() ...");
        array(object) inv = oMailBox->get_inventory();
        for (int i=0; i<sizeof(inv); i++)
        {
            mMessageNums+=([inv[i]->get_object_id():i]);
            LOG(i+": #"+inv[i]->get_object_id()+", Flags: "+get_flags(i));
            if(!has_header(i))
            {
                LOG("WARNING! Message #"+i+" has no header-data!");
                add_header(i);
            }
        }        
        LOG("init_mailbox() complete");
    }

    //returns a complete message, needed for pop3
    object fetch_message(int num)
    {
        if ( objectp(mMessages[num]) )
            return mMessages[num];
        array(object) inv = oMailBox->get_inventory();
        mMessages[num] = oMessages->fetch_message(inv[num]);
        return mMessages[num];
    }

    //delete all mails marked by 'delete_message()', only for pop3
    void cleanup()
    {
        foreach(to_delete, object del)
            del->delete();
    }

    //delete all mails flagged 'deleted' (imap4)
    //all connected imap-clients are notified via event-system
    void delete_mails()
    {
        array(object) inv = oMailBox->get_inventory();
        for(int i=sizeof(inv)-1;i>=0;i--)
        {
            if(has_flag(i,DELETED))
            {
                object msg=inv[i];
                mixed err = catch {
                    _SECURITY->access_delete(0, msg, msg);
                };
                if(err==0)
                {
                    msg->delete();
                }
            }
        }
    }

    //returns the number of messages in a mailbox
    int get_num_messages()
    {
        return sizeof(oMailBox->get_inventory());
    }

    //size of a message (header + body)
    int get_message_size(int num)
    {
        array(object) inv=oMailBox->get_inventory();
        mapping(string:string) headers=inv[num]->query_attribute(MAIL_MIMEHEADERS);
        string dummy="";
//        if(zero_value(inv[num]->query_attribute(MAIL_MIMEHEADERS))!=1)
//        {
            foreach(indices(headers),string key)
                dummy+=key+": "+headers[key]+"\r\n";
            dummy+="\r\n";
//        }

        return inv[num]->get_content_size() + sizeof(dummy);
    }

    //size of a message-body (without header)
    int get_body_size(int num)
    {
        array(object) inv=oMailBox->get_inventory();
        return inv[num]->get_content_size();
    }

    //message id for pop3
    string get_message_id(int num)
    {
        int char_min = 0x21; // 33
        int char_max = 0x7E; // 126
        array(object) inv = oMailBox->get_inventory();
        int id = inv[num]->get_object_id();
        string binary_str = send_binary(id);
        return MIME.encode_base64(binary_str);
    }

    //message uid for imap4
    int get_message_uid(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        return inv[num]->get_object_id();
    }

    //size of all messages in the mailbox
    int get_size()
    {
        array(object) inv = oMailBox->get_inventory();
        int sz = 0;
        for ( int i = sizeof(inv) - 1; i >= 0; i-- ) {
            sz += get_message_size(i);
        }
        return sz;
    }

    //mark a message as deletet (only for pop3)
    bool delete_message(int num)
    {
        array(object) inv = oMailBox->get_inventory();
        object msg = inv[num];
        mixed err = catch {
            _SECURITY->access_delete(0, msg, msg);
        };
        if ( err != 0 ) {
            LOG("Error: " + err[0] + "\n"+sprintf("%O", err));
        }
        else
            to_delete += ({ msg });
        return ( err == 0 );
    }

    object this() {
        return oMailBox;
    }

    int get_object_id() {
        return oMailBox->get_object_id();
    }

    //returns a message as one string (for pop3)
    string retrieve_message(int num) {
        object msg = fetch_message(num);
        return (string)msg;
    }
};

void init_module()
{
    oMessages = _Server->get_module("message");
    set_attribute(OBJ_DESC, "This module functions as a pop3 and imap4 "+
		  "server for getting the users mailbox content to the mailreader "+
		  "of the user.");
}

object get_mailbox(object user)
{
    object mb = user->query_attribute(USER_MAILBOX);
    if ( objectp(mb) )
        return MailBox(mb);
    return 0;
}

string get_identifier() { return "mailbox"; }
