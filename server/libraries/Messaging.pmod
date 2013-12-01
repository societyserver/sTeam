/* Copyright (C) 2004  Christian Schmidt
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


/** 
 * This module is used for the new message-system of sTeam 1.5
 * It provides methods to access different sTeam-objects as mailboxes
 * for example via IMAP
 */

#include <macros.h>
#include <attributes.h>
#include <database.h>
#include <classes.h>
#include <events.h>
#include <access.h>
#include <mail.h>
#include <config.h>

import Events;

//#define DEBUG_MSG

#ifdef DEBUG_MSG
#define LOG_MSG(s, args...) werror("messaging: "+s+"\n", args)
#else
#define LOG_MSG(s, args...)
#endif

string get_quoted_string ( string str ) {
  if ( !stringp(str) || is_ascii(str) ) return str;
  return MIME.encode_word( ({ str, "utf-8" }), "q" );
}


string get_quoted_name ( object user ) {
  if ( !objectp(user) ) return "";
  string name = user->query_attribute( USER_LASTNAME );
  if ( !stringp(name) ) name = "";
  string firstname = user->query_attribute( USER_FIRSTNAME );
  if ( stringp(firstname) && sizeof(firstname) > 0 )
    name = firstname + " " + name;
  if ( sizeof(name) < 1 ) return "";
  if ( !is_ascii(name) ) name = MIME.encode_word( ({ name, "utf-8" }), "q" );
  return "\"" + name + "\" ";
}


static int is_ascii( string text ) {
  if ( !stringp(text) )
    return 0;
  for ( int i = 0; i < strlen(text); i++ )
    if ( text[i] > 128 )
      return 0;
  return 1;
}


/**
 * implements imap-mailflags
 * used by message-class below
 * names of flags can be found in mail.h
 *
 */
class Flag
{
    private int iFlag; //stores the current value of the flag
    
    /**
     * create a new flag-object
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param void|int flag - the initial value of this flag, defaults to 0
     */
    void create(void|int tflag)
    {
        if(tflag) iFlag=tflag;
        else iFlag=0;
    }
    
    /**
     * get the current value of the flag
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return the value of the flag
     */
    int get() { return iFlag; }

    /**
     * set a new value for the flag
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param int tflag - the new value
     * @return
     */
    void set(int tflag) { iFlag = tflag; }

    /**
     * add a specific flag to the current value
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param int tflag - the flag to add
     */
    void add(int tflag) { iFlag = iFlag | tflag; }

    /**
     * remove a specific flag from the current value
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param int tflag - the flag to remove
     */
    void del(int tflag) { iFlag = iFlag & (~tflag); }

    /**
     * check if a flag is set
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param int tflag - the flag to query
     * @return 1 if flag is set, 0 if not
     */
    int has(int tflag) { return iFlag & tflag; }
}

/**
 * needed for "virtual reply mails"
 * no changes possible to state of flag
 */
class NullFlag
{
    inherit Flag;
    private int iFlag; //stores the current value of the flag
    
    void create(void|int tflag)
    {
        iFlag=SEEN;
    }
    
    int get() { return iFlag; }
    void set(int tflag) {}
    void add(int tflag) {}
    void del(int tflag) {}
    int has(int tflag) { return iFlag & tflag; }

}

/**
 * represents a single message
 * documents and possibly other sTeam-objects may be accessed
 * as mails/messages this way
 */
class Message
{
    static object oMessage; //the sTeam-Object this message refers to
    static string sSubject, sSender, sBody, sBoundary, sType, sSubtype;
    static array(Message) aoAttachment; //keeps all attachments of the messages
    static mapping(string:string) mHeader; //the e-mail headers
    static int iUid,iSize,iIsAttachment;
    static Flag fFlag;
    static int isBuild = 0;
    static object oRcptUser;
    
    static string sServer = _Server->query_config("machine");
    static string sDomain = _Server->query_config("domain");
    static string sFQDN = sServer+"."+sDomain;

    final mixed `->(string func) {
      function f = this_object()[func];
      // local functions which do not require building the Message
      if ( func == "get_object_id" || 
           func == "describe" || 
           func == "get_object" ||
           func == "this" ||
           func == "is_mail" )
        return f;
      if ( !isBuild ) {
        // all calls should be fine immediately
        isBuild = 1;
        build_message();
      }
      return f;
    }

    int is_mail() { return 1; }

    void build_message() {
      if(zero_type(oMessage->query_attribute(MAIL_MIMEHEADERS)))
      {
	add_header(oRcptUser); //header is missing, add a new one
	if ( stringp(sSender) ) 
	  mHeader->from = sSender;
	
	LOG_MSG("adding header within creation");
      }
      else 
      {
	mHeader = oMessage->query_attribute(MAIL_MIMEHEADERS);
	if ( mappingp(mHeader) &&
	     mappingp(oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL)) )
	  mHeader = oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL) | mHeader;
      }
      
      if(!iIsAttachment)
	fFlag = Flag(oMessage->query_attribute(MAIL_IMAPFLAGS));
      else 
	fFlag = 0; //Attachments have no flags
        
      int type=oMessage->get_object_class();
      type-=CLASS_OBJECT; //all sTeam-Objects have type CLASS_OBJECT...
      switch(type) {
      case CLASS_DOCUMENT:
      case CLASS_DOCUMENT|CLASS_DOCHTML:
	init_document( oRcptUser ); //see init_document() below
	break;
      case CLASS_IMAGE:
      case CLASS_DOCUMENT|CLASS_IMAGE:
	sBody="this message is an image, look at the attachment(s)";
	sSubject=mHeader["subject"];
	sType="MULTIPART";
	sSubtype="MIXED";
	aoAttachment = ({oMessage});
	break;
      default:
	LOG_MSG("Message->create() called for unknown class: "+type);
	LOG_MSG("subject, sender an body are EMPTY!!!");
	LOG_MSG("Please add support for this class in Messaging.pmod");
      }
      isBuild = 1;
    }
  
    /**
     * create a new message-object from a sTeam-object
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param object target - sTeam-object to encapsulate
     * @param int|void isAttachment - set to 1 if this message is "only" an attachment
     */
  void create(object target, int|void isAttachment, void|object rcptUser, void|string from)
  {
    if (objectp(target) && functionp(target->is_mail) && target->is_mail() ) {
      object targetMsg = target->get_msg_object();
      if (!objectp(targetMsg))
        steam_error("Cannot duplicate empty message!");
      sBody = target->body();
      sSubject = target->subject();
      sSender = target->sender();
      sBoundary = target->get_boundary();
      sType = target->type();
      sSubtype = target->subtype();
      fFlag = target->flag();
      mHeader = copy_value(target->header());
      iUid = target->uid();
      iSize = target->size();
      iIsAttachment = target->is_attachment();
      oRcptUser = target->get_rcptUser();;
      oMessage = targetMsg->duplicate();
      array attached = target->attachments();
      foreach(attached, object msg) {
        aoAttachment += ({ Message(msg) });
      }
      isBuild = 1;
      return;
    }
    isBuild = 0; // Message has not been build yet
    if(isAttachment)
      iIsAttachment=1;
    else 
      iIsAttachment = 0;
    if ( stringp(from) )
      sSender = from;
    
    oMessage = target;
    oRcptUser = rcptUser;
    aoAttachment = ({});
  }
    
    protected string get_body_encoded()
    {
        string result="";
        
        mixed content = oMessage->get_content();
        if ( !stringp(content) || sizeof(content) < 1 ) content = "";
        string encoding=mHeader["content-transfer-encoding"];
        if(stringp(encoding)) //determine the transfer-encoding and apply it
        {
            switch(lower_case(encoding))
            {
                case "base64":
                    result=MIME.encode_base64(content)+"\r\n";
                    break;
                case "quoted-printable":
                    result=MIME.encode_qp(content)+"\r\n";
                    break;
                //"7bit", "8bit" and "binary" mean "no encoding at all", see rfc2045
                case "7bit":
                case "8bit":
                case "binary":
                default:
                    result=content+"\r\n";
                    break;
            }
        }
        else result=content+"\r\n";
        
        return result;
    }
    
    /**
     * called if this object encapsulates a sTeam-Document
     * there should be no need to call this manually
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    static void init_document( void|object rcptUser )
    {
        int missing=0;
        
	mixed err = catch {
	  sBody=get_body_encoded();
	};
	if ( err != 0 ) {
	  FATAL( "Failed to read body of message: %O, %O", err[0], err[1] );
	  sBody = "Failed to read body - check errors / contact admin";
	}
        
        sSubject=mHeader["subject"]||"";
        if(!stringp(sSender)) 
            sSender=mHeader["from"]||"";

        sType="MULTIPART"; //default values
        sSubtype="MIXED";
        array(object) tmp = oMessage->get_annotations();
        for(int i=sizeof(tmp)-1;i>=0;i--)
            //reverse array, get_annotations returns "wrong" order
            aoAttachment += ({ Message( tmp[i], 1, rcptUser ) });
        if(sizeof(aoAttachment)>0) //message has attachments
        {
            string tmp=mHeader["content-type"];
            if(tmp!=0) //lookup MIME-boundary-string (see rfc 2045-2049)
            {
                int start=search(lower_case(tmp),"boundary=");
                if(start!=-1)
                {
                    start+=10; //skip info at start of header-line
                    int end=search(tmp,"\"",start);
                    sBoundary=tmp[start..end-1]; //copy found string to sBoundary
                }
                else missing=1;
            }
            else missing=1;
            
            if(missing) //the email-headers had no boundary, generate one
            {
                sBoundary=MIME.generate_boundary();
                tmp="MULTIPART/MIXED; BOUNDARY=\""+sBoundary+"\"";
                mHeader["content-type"]=tmp;
                oMessage->set_attribute(MAIL_MIMEHEADERS,mHeader);
                LOG_MSG("Boundary generated: "+sBoundary);
            }
        }
        else //message has no attachments
        {
            sBoundary=""; //non-MIME Message has no boundary-string
            string tmp=mHeader["content-type"];
            if(zero_type(tmp))
                tmp=oMessage->query_attribute(DOC_MIME_TYPE);
            int i=sscanf(tmp,"%s/%s;", sType, sSubtype);
            if(!i)
            {
                sType="TEXT";
                sSubtype="PLAIN";
            }
        }
	if (mHeader["content-type"]) {
          string ct = mHeader["content-type"];
          string charset;
          if (sscanf(ct, "%*s; charset=%s;%*s", charset)==0)
            sscanf(ct, "%*s; charset=%s", charset);
          if (charset)
            oMessage->set_attribute(DOC_ENCODING, lower_case(charset));
        }

        iSize=sizeof(complete_text());
    }
    
    string get_subject() {
	return sSubject;
    }

    void set_subject( string subject ) {
      mHeader["subject"] = (is_ascii(subject) ? subject :
			    MIME.encode_word( ({ subject, "utf-8" }), "q" ));
    }

    string get_boundary() {
      return sBoundary;
    }

    object get_rcptUser() { 
      return oRcptUser;
    }

    /**
     * converts a mapping [header:value] to one string
     * there should be no need to call this manually
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param mapping header - the mapping containing the header of the message
     * @return one string with the contents of the header (incl. linebreaks)
     */
    static string header2text(mapping header)
    {
        string dummy="";
        foreach(indices(header),string key) {
	  string ktext = key;
	  switch(ktext) {
	  case "content-type":
	    ktext = "Content-Type";
	    break;
	  case "message-id":
	    ktext = "Message-ID";
	    break;
          case "mime-version":
            ktext = "Mime-Version";
            break;
          case "content-transfer-encoding":
            ktext = "Content-Transfer-Encoding";
            break;
          default:
	    ktext[0] = upper_case(ktext[0..0])[0];
	    break;
	  }
	  dummy+=ktext+": "+header[key]+"\r\n";
	}
        if ( zero_type(header["mime-version"]) && zero_type(header["Mime-Version"])
             && zero_type(header["MIME-Version"]) )
          dummy += "Mime-Version: 1.0 (generated by open-sTeam)\r\n";
        dummy+="\r\n";
        return dummy;
    }
    object get_msg_object() { return oMessage; }
    object this() { return oMessage; }
    
    /**
     * write non permanent data to the sTeam-object of this message
     * must be called after flag-changes for example
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    void update()
    {
        mixed err = catch 
        {
            oMessage->set_attribute(MAIL_IMAPFLAGS,fFlag->get());
        };
        if(err) LOG_MSG("error on storing flags: %O",err);
    }

    /**
     * permanently adds a rfc2822-compliant header to the sTeam-object
     * no need to call this manually
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    static void add_header(void|object rcptUser)
    {
      LOG_MSG("Adding RFC2822 header to object-id: "+oMessage->get_object_id());
        
      mHeader=([]);
      string tmp=oMessage->query_attribute(OBJ_NAME);
      if ( !stringp(tmp) ) tmp = "";
      
      mHeader["subject"] = (is_ascii(tmp) ? tmp :
			    MIME.encode_word( ({ tmp, "utf-8" }), "q" ));
      
      mHeader["date"] = timelib.smtp_time( oMessage->query_attribute(OBJ_CREATION_TIME) );
      
      int id=oMessage->get_object_id();
      tmp="<"+sprintf("%010d",id)+"@"+sFQDN+">";
      mHeader["message-id"]=tmp;
      
      object test=oMessage->query_attribute(DOC_USER_MODIFIED);
      if(!objectp(test)) test=oMessage->get_creator();
      if (objectp(test)) {
        tmp = get_quoted_name( test ) + "<" + test->get_identifier() + "@" +
          sFQDN + ">";
	mHeader["from"]=tmp;

        if ( !stringp(sSender) )
          sSender = get_quoted_name( test ) + "<"+test->get_steam_email()+">";
      }
      else 
	FATAL("Warning: Failed to set Sender of Message !");
      // add header for "to"
      if ( objectp(test=oMessage->query_attribute("mailto")) )
	mHeader["to"] = get_quoted_name( test ) + "<" + test->get_identifier()
          + "@" + _Server->get_server_name() + ">";
      else if ( objectp(rcptUser) )
	mHeader["to"] = get_quoted_name( rcptUser ) + "<" +
          rcptUser->get_user_name() + "@" + _Server->get_server_name() + ">";
      else
	steam_error("Unable to determine \"To:\"-Header for E-Mail !\n");
      
      tmp = oMessage->query_attribute(DOC_MIME_TYPE);
      if ( !stringp(tmp) || sizeof(tmp) < 1 )
	tmp = "application/x-unknown-content-type";
      if ( search(lower_case(tmp),"text") >= 0 ) {
	mHeader["content-type"]=tmp+"; charset=\"utf-8\"";
	mHeader["content-transfer-encoding"] = "8bit";
      }
      else {
	mHeader["content-type"]=tmp;
	mHeader["content-transfer-encoding"] = "base64";
      }
      if ( mappingp(mHeader) &&
	   mappingp(oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL)) )
	mHeader = oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL) | mHeader;
      mixed err = catch(oMessage->set_attribute(MAIL_MIMEHEADERS,mHeader));
      if ( err ) {
	  FATAL("Failed to add mimeheader (setting attribute) for %O, %O, %O",
		oMessage, err[0], err[1]);
      }
    }
    
    /**
     * add additional informations to the header of this message
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param mapping add - the header-lines and values to add
     */
    void add_to_header(mapping add)
    {
        foreach(add; string index;)
        {
            if(zero_type(mHeader[lower_case(index)])) //only add if not already existing
                mHeader[lower_case(index)]=add[index];
        }
        oMessage->set_attribute(MAIL_MIMEHEADERS,mHeader);
    }
    
    /**
     * delete this message (that is: delete the sTeam-object)
     * existing attachments are removed too
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    void delete()
    {
        foreach(aoAttachment, Message msg)
        {
            aoAttachment-=({msg});
            msg->delete(); //remove all attachments
            destruct(msg);
        }
        oMessage->delete();
        if(objectp(fFlag)) destruct(fFlag);
    }
    
    /**
     * get the uid of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int unique-identifier
     */
    int uid() { return iUid; }

    /**
     * get the flag of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return Flag flag
     */
    Flag flag() { return fFlag; }

    /**
     * get the subject of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string subject
     */
    string subject() { return sSubject; }

    /**
     * get the sender of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string sender
     */
    string sender() { return sSender; }

    /**
     * check if this message is an attachment
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int 1 if message is attachment, 0 if it is a "real" message
     */
    int is_attachment() { return iIsAttachment; }
    
    /**
     * get all attachments of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return array(Message) an array of message-objects with attachments of this message
     */
    array(Message) attachments() { return aoAttachment; }

    /**
     * get the complete header of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return mapping(string:string) mapping with all header-informations
     */
    mapping(string:string) header() { return mHeader; }

    /**
     * get the body of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string body
     */
    string body() { return sBody; }
    
    /**
     * get the date of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int date of creation
     */
    int internal_date()
    {
        return oMessage->query_attribute(OBJ_CREATION_TIME);
    }
    
    /**
     * get the size of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int size in bytes
     */
    int size() { return iSize; }

    /**
     * get the size of the body of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int size of the body in bytes
     */
    int body_size() { return sizeof(sBody); }

    /**
     * get the object-id of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int object-id
     */
    int get_object_id() { return oMessage->get_object_id(); }

    /**
     * check if this message has attachments
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int 0 if no attachments exists or the number of attachments
     */
    int has_attachments() { return sizeof(aoAttachment); }
    
    MIME.Message mime_message()
    {
        MIME.Message msg;
        if(sizeof(aoAttachment))
            msg = MIME.Message(sBody, mHeader, aoAttachment->mime_message());
        else
            msg = MIME.Message(sBody, mHeader);
        msg->setboundary(sBoundary);
        return msg;
    }

    /**
     * returns the text-version of this message (rfc2822-style)
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string rfc2822-text of the message
     */
    string complete_text(void|int attach)
    {
        string dummy="";
	if ( attach )
	    mHeader["content-type"] += "; name=\"" + sSubject + "\"";

        dummy+=header2text(mHeader);

        if(sizeof(aoAttachment)>0)
        {
	    dummy += "--"+sBoundary+"\r\ncontent-type: " + 
		oMessage->query_attribute(DOC_MIME_TYPE) + "\r\n\r\n";    
	    dummy += sBody;
            for(int i=0;i<sizeof(aoAttachment);i++)
            {
                dummy+="\r\n\r\n--"+sBoundary+"\r\n";
                // insert all attachments
                dummy+=aoAttachment[i]->complete_text(1); 
            }
            dummy+="\r\n\r\n--"+sBoundary+"--\r\n\r\n";
        }
	else {
	    dummy += sBody;
	}
        return dummy;
    }
    
    /**
     * get the mimetype (first part) of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string mimetype (first part)
     */
    string type() { return sType; }

    /**
     * get the mimetype (second part) of this message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string mimetype (second part)
     */
    string subtype() { return sSubtype; }
    
    /**
     * duplicates a message, including all attachments
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return Message duplicated message
     */
    Message duplicate()
    {
        Message msg = Message(this_object());
        
        return msg;
        //return Message(copy);
    }

    /**
     * gives all access-rights on this message to a user
     * has to be called by a user who has sufficient rights
     * to do this
     *
     * @param object user the user-object to grant access to
     * @return 1 if successful, 0 otherwise
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    int grant_access(object user)
    {
        mixed err = catch
        {
            oMessage->sanction_object(user,SANCTION_ALL);
            foreach(aoAttachment, Message msg)
	      msg->grant_access(user);
        };
        if(err)
        {
            LOG_MSG("error on granting access to "+user->get_identifier()+" on #"+oMessage->get_object_id()+" :%O",err);
            return 0;
        }
        else return 1;
    }
}

class ContainerMessage
{
    inherit Message;
    
    void create(object target, int|void isAttachment)
    {
        aoAttachment=({}); //default: no attachments
	oMessage = target;
        
        LOG_MSG("ContainerMessage->create("+target->get_object_id()+")");
        if(isAttachment)
        {
            iIsAttachment=1;
            LOG_MSG("creating as attachment");
        }
        else iIsAttachment = 0;

        if (zero_type(target->query_attribute(MAIL_MIMEHEADERS)))
	  add_header();
	else {
	  if ( mappingp(mHeader) &&
	       mappingp(target->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL)) )
	    mHeader = target->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL) | mHeader;
	}

        if(iIsAttachment==0)
        {
            mHeader = target->query_attribute(MAIL_MIMEHEADERS); //copy header from target
            m_delete(mHeader,"content-transfer-encoding");
            m_delete(mHeader,"content-disposition");
            sBoundary="'sTeaMail-RaNdOm-StRiNg-/=_."+target->get_object_id()+"."+target->query_attribute(OBJ_CREATION_TIME)+":";
            mHeader["content-type"]="multipart/mixed; boundary=\""+sBoundary+"\"";
            mHeader["mime-version"]="1.0";
            sBody="This is a multi-part message in MIME format.";
            aoAttachment=({ContainerMessage(target,1)}); //store target as first attachment
            oMessage=aoAttachment[0];
            fFlag = Flag(target->query_attribute(MAIL_IMAPFLAGS));

            sType="multipart";
            sSubtype="mixed";

            array(object) tmp = target->get_annotations();
            for(int i=sizeof(tmp)-1;i>=0;i--)
            aoAttachment+=({ContainerMessage(tmp[i],1)});

        }
        else
        {
            mHeader=([]);
            oMessage = target;
            mapping temp=oMessage->query_attribute(MAIL_MIMEHEADERS);

            string test=temp["content-transfer-encoding"];
            if(stringp(test)) mHeader["content-transfer-encoding"]=test;
            test=temp["content-disposition"];
            if(stringp(test)) mHeader["content-disposition"]=test;
            test=temp["content-type"];
            if(stringp(test))
            {
                mHeader["content-type"]=test;
                sscanf(test,"%s/%s;",sType,sSubtype);
            }
            else //unknown content-type...
            {
                sType="test";
                sSubtype="plain";
            }
            sBody=get_body_encoded();
            fFlag = 0; //Attachments have no flags
            
            if(objectp(target->get_annotating())) //is this a "real" attachment or just the document itself?
            {
                array(object) tmp = oMessage->get_annotations();
                for(int i=sizeof(tmp)-1;i>=0;i--)
                aoAttachment+=({ContainerMessage(tmp[i],1)});
            }
        }
        init_document();
    }
    
    /**
     * called if this object encapsulates a sTeam-Document
     * there should be no need to call this manually
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    static void init_document()
    {
        sSubject=mHeader["subject"];
        if(!stringp(sSubject)) sSubject="";
        sSender=mHeader["from"];
        if(!stringp(sSender)) sSender="";

        iSize=sizeof(complete_text());
    }
    
    object get_msg_object() { return oMessage; }
  
    object this()
    {
         if(objectp(oMessage)) return oMessage;
         else
         {
	   return geteuid();
         }
    }
  
    object get_object() 
    {
        return geteuid();
    }

    void update()
    {
        if(iIsAttachment) return;
        mixed err = catch 
        {   //flag is stored in first attachment as message-object is non-existant!
            aoAttachment[0]->this()->set_attribute(MAIL_IMAPFLAGS,fFlag->get());
        };
        if(err) LOG_MSG("error on storing flags: %O",err);
    }

    int get_object_id()
    {
      return oMessage->get_object_id();
    }

    int internal_date()
    {
        if(iIsAttachment) return oMessage->query_attribute(OBJ_CREATION_TIME);
        else return aoAttachment[0]->internal_date();
    }

    void delete()
    {
        foreach(aoAttachment, Message msg)
        {
            aoAttachment-=({msg});
            msg->delete(); //remove all attachments
            destruct(msg);
        }
        if(iIsAttachment) oMessage->delete();
        if(objectp(fFlag)) destruct(fFlag);
    }

    int grant_access(object user)
    {
        mixed err = catch
        {
//            oMessage->sanction_object(user,SANCTION_ALL);
            foreach(aoAttachment, Message msg)
             msg->grant_access(user);
        };
        if(err)
        {
            LOG_MSG("error on granting access to "+user->get_identifier()+" on #"+this()->get_object_id()+" :%O",err);
            return 0;
        }
        else return 1;
    }

}

/**
 * subclass of Message
 * used for accessing sTeam-messageboards entries
 */
class MessageboardMessage
{
    inherit Message;
    
    void create(object target, int|void isAttachment)
    {
        LOG_MSG("MessageboardMessage->create("+target->get_object_id()+")");
        iIsAttachment = 0;
        aoAttachment = ({}); //messageboard-entries have no attachments...
        
        oMessage = target;
        fFlag = Flag(oMessage->query_attribute(MAIL_IMAPFLAGS));
        
        if(zero_type(oMessage->query_attribute(MAIL_MIMEHEADERS)))
            add_header(); //header is missing, add a new one
        else {
	  mHeader = oMessage->query_attribute(MAIL_MIMEHEADERS);
	  if ( mappingp(mHeader) &&
	       mappingp(oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL)) )
	    mHeader = oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL) | mHeader;
	}
        
        int type=oMessage->get_object_class();
        if(type & CLASS_DOCUMENT)
            init_document(); //see init_document() below
        else
        {
            LOG_MSG("MessageboardMessage->create() called for unknown class: "+type);
            LOG_MSG("subject, sender an body are EMPTY!!!");
            LOG_MSG("Please add support for this class in Messaging.pmod");
        }
        LOG_MSG("NessageboardMessage->create("+target->get_object_id()+") finished!");
    }
    
    static void init_document()
    {
        sBody=oMessage->get_content()+"\r\n";

	string charset = oMessage->query_attribute(DOC_ENCODING);
	if ( stringp(charset) && charset != "utf-8" ) {
	  object enc = Locale.Charset.encoder("utf-8");
	  object dec = Locale.Charset.decoder(charset);
	  sBody = dec->feed(sBody)->drain();
	  sBody = enc->feed(sBody)->drain();
	  // now body should be utf
	}

        sSubject=mHeader["subject"];
        sType="TEXT";
        sSubtype="PLAIN";
        iSize=sizeof(complete_text());
        if(!stringp(mHeader["reply-to"]) || mHeader["reply-to"]=="")
        {
            mHeader["reply-to"]="<"+oMessage->get_object_id()+"@"+sFQDN+">";
            oMessage->set_attribute(MAIL_MIMEHEADERS,mHeader);
        }
    }

    static void add_header()
    {
        LOG_MSG("Adding RFC2822 header to object-id: "+oMessage->get_object_id());
        
        mHeader=([]);
	mHeader["subject"] = oMessage->query_attribute(OBJ_NAME) || "";
        mHeader["date"] = timelib.smtp_time( 
			   oMessage->query_attribute(OBJ_CREATION_TIME));
        
        int id=oMessage->get_object_id();
        mixed tmp="<"+sprintf("%010d",id)+"@"+sFQDN+">";
	//replies should go to the messageboard, not the sender!
        mHeader["reply-to"]=tmp; 
        mHeader["message-id"]=tmp; //use id@server as message-id, too
        
        object test=oMessage->query_attribute(DOC_USER_MODIFIED);
        if (objectp(test))
	  mHeader["from"] = get_quoted_name( test ) + "<" + test->get_identifier() + "@" + sFQDN + ">";
        
        test=oMessage->get_annotating();
        if(objectp(test) && !(test->get_object_class() & CLASS_MESSAGEBOARD) )
	{
	  mapping parentheader = test->query_attribute(MAIL_MIMEHEADERS);
	  if(mappingp(parentheader)) {
	    if(stringp(parentheader["message-id"]))
	      mHeader["in-reply-to"]=parentheader["message-id"];
	    if(stringp(parentheader["references"]))
	      mHeader["references"]=parentheader["message-id"]+","+
		parentheader["references"];
	    else 
	      mHeader["references"]=parentheader["message-id"];
	  }
        }
        
        tmp=oMessage->query_attribute(DOC_MIME_TYPE) || MIMETYPE_UNKNOWN;;
        mHeader["content-type"]=tmp+"; charset=\"utf-8\"";
        LOG_MSG("new header is:%O",mHeader);
	mapping add_headers = oMessage->query_attribute(MAIL_MIMEHEADERS_ADDITIONAL) || ([ ]);
        oMessage->set_attribute(MAIL_MIMEHEADERS,mHeader|add_headers);
    }
}

/**
 * class for "virtual reply mails", subclass of Message
 * these mails are shown in every mailbox of type container or messageboard
 * in order to give a simple way to adress mails to the mailbox itself
 *
 * this means that a message of this class has a reply-adress with the
 * object-id of the mailbox it is shown in
 */
class ReplyMessage
{
    inherit Message;
    
    private int iTime;
    private object oMailBox;
    
    /**
     * create new ReplyMessage
     * @param object target - the mailbox this message is created in
     */
    void create(object target, int|void isAttachment)
    {
        oMailBox = target;
        
        iIsAttachment = 0; //reply-mails are no attachments...
        aoAttachment = ({}); //...and have no attachments
        
        fFlag = NullFlag(); //can't store any flags on this message
        
        iUid = oMailBox->get_object_id(); //we have no uid, so get uid of mailbox we are in
        iTime = oMailBox->query_attribute(OBJ_CREATION_TIME);
        
        //header is always the same...
        mHeader = ([ "from":"\"sTeam-Mail\" <"+iUid+"@"+sFQDN+">",
                     "subject":"neues Dokument erzeugen -create new document",
                     "date":ctime(iTime)-"\n",
                     "message-id":"<"+sprintf("%010d",iUid)+"@"+sFQDN+">",
                     "reply-to":"<"+sprintf("%010d",iUid)+"@"+sFQDN+">",
                     "x-priority":"1",
                     "x-msmail-priority":"High"]);

        //content only describes use of this reply-mail
        sBody = "Um ein neues Dokument in diesem Raum zu erzeugen, beantworte einfach diese Mail!\n";
        sSubject = mHeader["subject"];
        sSender = mHeader["from"];
        
        //message-object does not exist!
        oMessage = 0;

        iSize=sizeof(complete_text());
        
        sType = "text"; //obvious...
        sSubtype = "plain";
    }
    
    //there is no sTeam-object for this message...
    object this() { return 0; }

    //...so flags don't change...
    void update() {}
    
    //...and header's won't do so, too
    static void add_header() {}
    void add_to_header(mapping add) {}
    
    //just delete the flag-object
    void delete()
    {
        destruct(fFlag);
    }

    int internal_date()
    {
        return iTime;
    }
    
    int get_object_id() { return iUid; }
    
    //senseless, but if someone calls it... (may happen when copying mails)
    Message duplicate()
    {
        return ReplyMessage(oMailBox);
    }

    int grant_access(object user)
    {
        return 1;
    }

}

/**
 * Listener for for events called by "external" programs,
 * for example by sTeam-operations on a encapsulated mailbox
 * or another mailbox-object (more than one mailbox-object may
 * exist for a single sTeam-object)
 */
class MessagingListener {
   inherit Events.Listener;

   function fCallback; //stores the callback function
   void create(int events, object obj, function callback) {
     ::create(events, PHASE_NOTIFY, obj, 0);
     fCallback = callback;
     obj->listen_event(this_object());
   }

   void notify(int event, mixed args) {
     if ( functionp(fCallback) )
       fCallback(event, @args);
   }
   mapping save() { return 0; }

   string describe() {
     return "MessagingListener()";
   }
}

/**
 * BaseMailBox is the root-class of all mailbox-types
 * it's pretty useless alone...
 * think of it as an "interface"
 */
class BaseMailBox
{
    static object oMailBox; //sTeam-object this box is built from
    static array(Message) aoMessages;
    static mapping oidMessageCache;
    static int iAllowedTypes, iFolderTypes;
    static array(int) aiEnterEvent, aiLeaveEvent;
    static array(MessagingListener) alEnter, alLeave;
    static object oTarget;
    
    /**
     * create a new BaseMailBox-object
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param object target - the sTeam-object to build MailBox around
     */
    void create(object target)
    {
        oTarget = target;
        oidMessageCache = ([ ]);
        //add code in sub-classes
    }
    
    /**
     * callback function for events when inventory changes
     */
    static void notify_me(int event, mixed ... args)
    {
        LOG_MSG("Event "+event+"%O",args);
        rebuild_box();
    }
    
    object get_object() { 
      return oMailBox;
    }
    
    /**
     * needed for sTeam-security
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return the sTeam-object for this MailBox
     */
    object this()
    {
        return oMailBox;
    }
    
    /**
     * get the messages in this mailbox
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return array of message-objects
     */
    array(Message) messages()
    {
        return aoMessages;
    }
    
    /**
     * get the number of messages in this mailbox
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int containing the number of messages
     */
    int get_num_messages()
    {
        return sizeof(aoMessages);
    }
    
    /**
     * get a specific message
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param int msn - the message sequence number of the desired mail, 1 is first message
     * @return a message-object containing the desired message
     */
    Message get_message(int msn)
    {
        if(msn<=sizeof(aoMessages))
            return aoMessages[msn-1]; //MSNs are counted from 1, not from 0
        else
        {
          FATAL("get_message() called for illegal msn: "+msn+
                " (max is "+sizeof(aoMessages)+")");
        }
    }

    Message get_message_by_oid(int oid) {
      if ( oidMessageCache[oid] )
        return oidMessageCache[oid];
      for ( int i = 0; i < sizeof(aoMessages); i++ ) {
        if ( objectp(aoMessages[i]) )
          oidMessageCache[aoMessages[i]->get_object_id()] = aoMessages[i];
      }
      return oidMessageCache[oid];
    }
    
    /**
     * delete all messages which have the "deleted"-flag set
     * (like "expunge" in IMAP)
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param 
     * @return 
     */
    void delete_mails()
    {
        LOG_MSG("delete_mails() called for "+oMailBox->get_object_id());
        for(int i=sizeof(aoMessages)-1;i>=0;i--)
        {
            LOG_MSG("flags for #"+i+": "+aoMessages[i]->flag()->get());
            if(aoMessages[i]->flag()->has(DELETED))
            {
                LOG_MSG("deleting #"+i);
                Message tmp = aoMessages[i];
                aoMessages -= ({tmp});
                tmp->delete();
                destruct(tmp);
            }
        }
    }
    
    /**
     * delete this mailbox and all messages inside
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     */
    void delete()
    {
        for(int i=0;i<sizeof(aoMessages);i++) //remove all messages
            aoMessages[i]->delete();
        oMailBox->delete(); //remove mailbox
    }
    
    /**
     * convert unique-ids to message sequence numbers
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param array(int) - the uids to convert
     * @return array(int) of matching msns
     */
    array(int) uid_to_num(int|array(int) uids)
    {
        array(int) res = ({});
        mapping(int:int) temp=([]);
        for(int i=0;i<sizeof(aoMessages);i++) //map ALL ids to sequence numbers
            temp+=([aoMessages[i]->get_object_id():i+1]); //numbers start at 1
        foreach(uids, int i) //take requested elements from complete mapping
            if(zero_type(temp[i])!=1) res+=({temp[i]});
        return res;
    }

    int map_object(object msg, int rbegin, int rend) 
    {
      if ( objectp(msg) ) {
        int id = msg->get_object_id();
        if ( id >= rbegin && id <= rend )
          return id;
      }
      return 0; // left out
    }

    array(int) filter_uids(array uids) 
    {
      array(int) res = ({});
      foreach(uids, mixed range) {
        if ( arrayp(range) ) {
          res += (map(aoMessages, map_object, range[0], range[1]) - ({ 0 }));
        }
        else {
          Message msg = get_message_by_oid(range);
          if ( objectp(msg) )
            res += ({ range });
        }
      }
      return res;
    }
    
    /**
     * get a mapping of unique ids to message sequence numbers
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return mapping(int:int) of all existing uids in this box to msns
     */
    mapping(int:int) get_uid2msn_mapping()
    {
        mapping(int:int) temp=([]);
        for(int i=0;i<sizeof(aoMessages);i++)
            temp+=([aoMessages[i]->get_object_id():i+1]); //msns start at 1, not at 0
        return temp;
    }
        
    /**
     * get the total size of this box (that is: size of all messages)
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int containing the size in bytes
     */
    int size()
    {
        int t=0;
        foreach(aoMessages, Message msg)
            t+=msg->size();
        return t;
    }
    
    /**
     * get the object id of this box (-> the sTeam-object of this box)
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int object-id
     */
    int get_object_id()
    {
        return oMailBox->get_object_id();
    }
    
    /**
     * get the identifying string of this box
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return string containing the identifier
     */
    string get_identifier()
    {
        return oMailBox->get_identifier();
    }
    
    /**
     * does this mailbox have subfolders?
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int number of subfolders, 0 if no exist
     */
    int has_subfolders() { return 0; }

    /**
     * get a subfolder of this box
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param string subfolder - the name of the subfolder to fetch
     * @return a MailBox-object of the subfolder, 0 if folder doesn't exist
     */
    BaseMailBox get_subfolder(string subfolder) { return 0; }

    /**
     * list all subfolders of this mailbox
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param int recurse - how "deep" should be searched for folders, -1 means unlimited
     * @return array(string) of mailbox-names, hierarchies seperated by "/"
     */
    array(string) list_subfolders(int recurse) { return({}); }

    /**
     * get the type of sTeam-objects which are allowed as messages in this box
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int with class-type (see classes.h for values)
     */
    int allowed_types() { return iAllowedTypes; }

    /**
     * get the event that is called when a message is removed from this box
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int value of event (see events.h)
     */
    array(int) leave_event() { return aiLeaveEvent; }

    /**
     * get the event that is called when a message is added to this box
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @return int value of event (see events.h)
     */
    array(int) enter_event() { return aiEnterEvent; }

    /**
     * add a message to this box
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param Message msg - message to add
     */
    void add_message(Message msg) {};
    
    /**
     * rebuild the inventory of this mailbox
     * called via event if contents of the encapsulated sTeam-object change
     */
    static void rebuild_box() {};
}

/**
 * UserMailBox manages access to the messages of a user-object
 * these are stored as annotations to the user
 * 
 */
class UserMailBox
{
    inherit BaseMailBox;

    void create(object target)
    {
        ::create( target );
        iAllowedTypes = CLASS_DOCUMENT; //users store their mails as documents
        iFolderTypes = CLASS_CONTAINER;
        aiEnterEvent = ({EVENT_ANNOTATE});
        aiLeaveEvent = ({EVENT_REMOVE_ANNOTATION});
        aoMessages=({});
        oMailBox=target;
            
        LOG_MSG("UserMailBox->create() called:");
        LOG_MSG("target id: "+target->get_object_id());
        LOG_MSG("target name: "+target->get_identifier());
            
        array(object) inv=target->get_annotations_by_class(iAllowedTypes);
        LOG_MSG("box size is: "+sizeof(inv));
            
        for(int i=sizeof(inv)-1;i>=0;i--) //reverse order of inv
        {
	  Message msg;
	  mixed err = catch {
	    msg = Message(inv[i], 0, oTarget);
	  };
	  if ( err != 0 ) {
	    FATAL("Failed to create Messaging.Message for %O\n", inv[i]);
	    FATAL("%O: %O", err[0], err[1]);
	  }
	  else
	    aoMessages+=({msg});
        }
        alEnter=({MessagingListener(aiEnterEvent[0], oMailBox, notify_me)});
        alLeave=({MessagingListener(aiLeaveEvent[0], oMailBox, notify_me)});
/*
        LOG_MSG("Summary of mailbox-creation:");
        for(int i=0;i<sizeof(aoMessages);i++)
            LOG_MSG("#"+i+" id:"+aoMessages[i]->get_object_id()+
                " Subject: "+aoMessages[i]->subject()+
                " ["+aoMessages[i]->has_attachments()+" Attachment(s)]");
*/
    }

    static void rebuild_box()
    {
        array(object) tmp = oMailBox->get_annotations_by_class(iAllowedTypes);
        if(sizeof(tmp)==sizeof(aoMessages))
            return; //nothing changed...
        LOG_MSG("rebuilding box #"+oMailBox->get_object_id());

        array(int) new_ids=({});
        int i;
        for(i=0;i<sizeof(tmp);i++) new_ids+=({tmp[i]->get_object_id()});
//        LOG_MSG("new ids:%O",new_ids);
        array(int) old_ids=({});
        for(i=0;i<sizeof(aoMessages);i++) old_ids+=({aoMessages[i]->get_object_id()});
//        LOG_MSG("old ids:%O",old_ids);
        if(sizeof(old_ids)>sizeof(new_ids)) //one ore more messages were removed
        {
            array(int) diff=old_ids-new_ids;
//            LOG_MSG("diff is:%O",diff);
            for(i=sizeof(aoMessages)-1;i>=0;i--)
                if(search(diff,aoMessages[i]->get_object_id())!=-1)
                {
                    LOG_MSG("removing lost #"+aoMessages[i]->get_object_id());
                    aoMessages-=({aoMessages[i]});
                }
        }
        else //messages were added
        {
            array(int) diff=new_ids-old_ids;
	    for(i=0;i<sizeof(diff);i++)
	      {
                LOG_MSG("adding new #"+diff[i]);
                Message msg;
                object diffobj = _Database->find_object(diff[i]);
                if ( !objectp(diffobj) )
		  continue;
                mixed err = catch {
		  msg = Message(diffobj, 0, oTarget);
                };
                if ( err != 0 ) {
		  FATAL("Failed to create Messaging.Message (rebuilding box\
) for %O\n", diffobj);
		  FATAL("%O: %O", err[0], err[1]);
                }
                else
		  aoMessages+=({msg});
	      }

        }
    }

    int has_subfolders()
    {
        array(object) folders = oMailBox->get_annotations_by_class(iFolderTypes);
        return(sizeof(folders));
    }

    /**
     * search for a specific folder inside a given object
     * no need to call this manually
     *
     * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
     * @param object where - the sTeam-object to search in
     * @param string what - the name of the folder to search for
     * @return object with the folder, 0 if folder is not found
     */
    private object search_for_folder(object where, string what)
    {
        array(object) folders = where->get_annotations_by_class(iFolderTypes);
        if(sizeof(folders)>0)
        {
            int i=0;
            while(i<sizeof(folders))
            {
                if(folders[i]->get_identifier()==what)
                    return folders[i];
                i++;
            }
            LOG_MSG("subfolder not found: "+what);
        }
        return 0;
    }

    BaseMailBox get_subfolder(string subfolder)
    {
        int fail=0;
        array(string) parts=subfolder/"/"; //it is possible to fetch a "deep" folder with one call
        int i=0;
        object current = oMailBox;
        while(i<sizeof(parts) && !fail) //search for folders "deeper" into this box
        {
            current = search_for_folder(current, parts[i]);
            if(objectp(current)) i++;
            else fail=1;
        }
        if(fail) return 0; //couldn't find subfolder
        return UserMailBox(current);
    }
        
    int create_subfolder(string subfolder)
    {
        if(objectp(get_subfolder(subfolder))) return 0; //subfolder already exists
        object factory = _Server->get_factory(CLASS_CONTAINER);
        object tmp = factory->execute( (["name":subfolder]) );
        oMailBox->add_annotation(tmp);
        tmp->set_acquire(oMailBox);
        return 1;
    }
    
    array(string) list_subfolders(int recurse)
    {
        array(string) res = ({});
        if(recurse==0) return res; //nothing to do...
        if(recurse==1) //easy, just get anns of this box
        {
            array(object) folders = oMailBox->get_annotations_by_class(iFolderTypes);
            if(sizeof(folders)>0)
            {
                for(int i=0;i<sizeof(folders);i++)
                    res+=({folders[i]->get_identifier() });
                return res;
            }
            else return ({}); //no subfolders in this mailbox
        }
        else //perform BFS on this mailbox
        {
            int tid = oMailBox->get_object_id();
            array(int) all = ({tid});
            array(int) queue = ({tid});
            mapping(int:int) discover=([tid:0]);
            mapping(int:int) parent=([tid:0]); //starting vertex has no parent
            int iter=0;
            while(sizeof(queue)>0 && discover[queue[0]]!=recurse)
            {
                tid=queue[0];
                array(object) inv=_Database->find_object(tid)->get_annotations_by_class(iFolderTypes);
                foreach(inv, object v)
                {
                    int id=v->get_object_id();
                    if(sizeof(all&({id}))==0)
                    {
                        all+=({id}); queue+=({id});
                        discover+=([id:discover[tid]+1]);
                        parent[id]=tid; //this vertex has been discovered from "tid"
                    }
                 }
                 queue-=({tid}); iter++;
            } //BFS is complete here
            int mboxid=oMailBox->get_object_id();
            m_delete(discover,mboxid); //mailbox is not part of result
            if(sizeof(discover)==0) return ({}); //no subfolders in mailbox
            foreach(indices(discover), tid)
            { //build the complete path to each discovered folder
               string path="";
               while(tid!=mboxid)
               {
                   path="/"+_Database->find_object(tid)->get_identifier()+path;
                   tid=parent[tid];
               }
               path=path[1..sizeof(path)-1]; //remove first "/";
               res+=({path});
            }
            return sort(res);
        }
    }
    
    void add_message(Message msg)
    {
        aoMessages+=({msg});
        object tmp=msg->this()->get_annotating();
        if(objectp(tmp))
            tmp->remove_annotation(msg->this());
        oMailBox->add_annotation(msg->this());
	msg->this()->set_acquire(0);
	msg->this()->sanction_object(oMailBox, SANCTION_ALL);

        LOG_MSG("added #"+msg->get_object_id()+" to user-box #"+oMailBox->get_object_id());
    }
}

/**
 * this class wraps a sTeam-Object of type "container" (but NOT "user")
 * for user-objects use "UserMailBox" instead
 */
class ContainerMailBox
{
    inherit BaseMailBox;

    void create(object target)
    {
        ::create( target );
        iAllowedTypes = CLASS_DOCUMENT | CLASS_IMAGE;
        iFolderTypes = CLASS_CONTAINER | CLASS_ROOM | CLASS_TRASHBIN | CLASS_EXIT | CLASS_MESSAGEBOARD;
        aiEnterEvent = ({EVENT_ENTER_INVENTORY});
        aiLeaveEvent = ({EVENT_LEAVE_INVENTORY});
        aoMessages=({});
        oMailBox=target;
            
        LOG_MSG("ContainerMailBox->create() called:");
        LOG_MSG("target id: "+target->get_object_id());
        LOG_MSG("target name: "+target->get_identifier());
            
        array(object) inv=target->get_inventory_by_class(iAllowedTypes);
        LOG_MSG("box size is: "+sizeof(inv));
        
        Message reply = ReplyMessage(oMailBox);
        aoMessages+=({reply});
        LOG_MSG("added reply-mail to mailbox");
            
        for(int i=0;i<sizeof(inv);i++)
	{
	  mixed err = catch {
            Message msg=ContainerMessage(inv[i]); //ContainerMailBox has ContainerMessages...
            aoMessages+=({msg});
	  };
	  if ( err ) {
	    FATAL("Failed to create Message: %O\n%O\n", err[0], err[1]);
	  }
	}
        alEnter=({MessagingListener(aiEnterEvent[0] | aiLeaveEvent[0], oMailBox, notify_me)});
/*
        LOG_MSG("Summary of mailbox-creation:");
        for(int i=0;i<sizeof(aoMessages);i++)
            LOG_MSG("#"+i+" id:"+aoMessages[i]->get_object_id()+
                " Subject: "+aoMessages[i]->subject()+
                " ["+aoMessages[i]->has_attachments()+" Attachment(s)]");
*/
    }

    static void rebuild_box()
    {
        array(object) tmp = oMailBox->get_inventory_by_class(iAllowedTypes);
        if(sizeof(tmp)==sizeof(aoMessages)-1) //reply-mail doesn't exist in sTeam!!
            return; //nothing changed...
        LOG_MSG("rebuilding box #"+oMailBox->get_object_id());

        array(int) new_ids=({});
        int i;
        for(i=0;i<sizeof(tmp);i++) new_ids+=({tmp[i]->get_object_id()});
//        LOG_MSG("new ids:%O",new_ids);
        array(int) old_ids=({});
        for(i=1;i<sizeof(aoMessages);i++) old_ids+=({aoMessages[i]->get_object_id()});
//        LOG_MSG("old ids:%O",old_ids);
        if(sizeof(old_ids)>sizeof(new_ids)) //one ore more messages were removed
        {
            array(int) diff=old_ids-new_ids;
//            LOG_MSG("diff is:%O",diff);
            for(i=sizeof(aoMessages)-1;i>=1;i--)
                if(search(diff,aoMessages[i]->get_object_id())!=-1)
                {
                    LOG_MSG("removing lost #"+aoMessages[i]->get_object_id());
                    aoMessages-=({aoMessages[i]});
                }
        }
        else //messages were added
        {
            array(int) diff=new_ids-old_ids;
//            LOG_MSG("diff is:%O",diff);
            for(i=0;i<sizeof(diff);i++)
            {
                LOG_MSG("adding new #"+diff[i]);
                Message msg=ContainerMessage(_Database->find_object(diff[i]));
                aoMessages+=({msg});
            }
        }
    }

    int has_subfolders()
    {
        array(object) folders = oMailBox->get_inventory_by_class(iFolderTypes);
        for(int i=sizeof(folders);i>=0;i--) //remove users from list
            if(folders[i]->get_object_class() & CLASS_USER) folders-=({folders[i]});
        return(sizeof(folders));
    }

    private object search_for_folder(object where, string what)
    {
        if(where->get_object_class() & CLASS_EXIT) where=where->get_exit();
        array(object) folders = where->get_inventory_by_class(iFolderTypes);
        if(sizeof(folders)>0)
        {
            int i=0;
            while(i<sizeof(folders))
            {
                if(folders[i]->get_object_class() & CLASS_EXIT)
                    folders[i]=folders[i]->get_exit();
                if(folders[i]->get_identifier()==what )
                    return folders[i];
                i++;
            }
            LOG_MSG("subfolder not found: "+what);
        }
        return 0;
    }

    BaseMailBox get_subfolder(string subfolder)
    {
        int fail=0;
        array(string) parts=subfolder/"/"; //it is possible to fetch a "deep" folder with one call
        int i=0;
        object current = oMailBox;
        while(i<sizeof(parts) && !fail) //search for folders "deeper" into this box
        {
            current = search_for_folder(current, parts[i]);
            if(objectp(current)) i++;
            else fail=1;
        }
        if(fail) return 0; //couldn't find subfolder
        if(current->get_object_class() & CLASS_EXIT)
            current=current->get_exit(); //get target object of exit
        if(current->get_object_class() & CLASS_CONTAINER)
            return ContainerMailBox(current);
        else 
            if(current->get_object_class() & CLASS_MESSAGEBOARD)
                return MessageboardMailBox(current);
            else return 0; //unsupported object-type
    }
        
    int create_subfolder(string subfolder)
    {
        if(objectp(get_subfolder(subfolder))) return 0; //subfolder already exists
        object factory = _Server->get_factory(CLASS_CONTAINER);
        object tmp = factory->execute( (["name":subfolder]) );
        mixed err=catch {tmp->move(oMailBox);};
        if(err!=0)
        {
            tmp->delete();
            return 0;
        }
        else return 1;
    }
    
    array(string) list_subfolders(int recurse)
    {
        array(string) res = ({});
        if(recurse==0) return res; //nothing to do...
        if(recurse==1) //easy, just get subfolders of this box
        {
            array(object) folders = oMailBox->get_inventory_by_class(iFolderTypes);
            if(sizeof(folders)>0)
            {
                for(int i=0;i<sizeof(folders);i++)
                    res+=({folders[i]->get_identifier() });
                return res;
            }
            else return ({}); //no subfolders in this mailbox
        }
        else //perform BFS on this mailbox
        {
            int tid = oMailBox->get_object_id();
            array(int) all = ({tid});
            array(int) queue = ({tid});
            mapping(int:int) discover=([tid:0]);
            mapping(int:int) parent=([tid:0]); //starting vertex has no parent
            int iter=0;
            while(sizeof(queue)>0 && discover[queue[0]]!=recurse)
            {
                tid=queue[0];
                object current=_Database->find_object(tid);
                array(object) inv;
                if(current->get_object_class() & CLASS_MESSAGEBOARD)
                    inv=({});
                    //messageboards have no subfolders, search for this vertex is complete
                else
                    inv=current->get_inventory_by_class(iFolderTypes);
                foreach(inv, object v)
                {
                    int id;
                    if(v->get_object_class() & CLASS_EXIT)
                    { //"resolve" exits
                        mixed err=catch{id=v->get_exit()->get_object_id();};
                        if(err!=0) continue; //can't access target of exit, ignore it
                    }
                    else
                        id=v->get_object_id();
                    if(sizeof(all&({id}))==0)
                    {
                        all+=({id}); queue+=({id});
                        discover+=([id:discover[tid]+1]);
                        parent[id]=tid; //this vertex has been discovered from "tid"
                    }
                 }
                 queue-=({tid}); iter++;
            } //BFS is complete here
            int mboxid=oMailBox->get_object_id();
            m_delete(discover,mboxid); //mailbox is not part of result
            if(sizeof(discover)==0) return ({}); //no subfolders in mailbox
            foreach(indices(discover), tid)
            { //build the complete path to each discovered folder
               string path="";
               while(tid!=mboxid)
               {
                   path="/"+_Database->find_object(tid)->get_identifier()+path;
                   tid=parent[tid];
               }
               path=path[1..sizeof(path)-1]; //remove first "/";
               res+=({path});
            }
            return sort(res);
        }
    }
    
    void add_message(Message msg)
    {
        LOG_MSG("adding #"+msg->get_object_id()+" to container-box #"+oMailBox->get_object_id());

        int i=msg->has_attachments();
        if(i==0) //no attachments -> store without modification
        {
            mapping temp=msg->header();
            // FIXME: in-reply-to and references should not really be removed
            m_delete(temp,"in-reply-to");
            m_delete(temp,"references");
	    object msgObj = msg->get_msg_object();
            msgObj->set_attribute(MAIL_MIMEHEADERS,temp);
            msgObj->move(oMailBox->this());
            msgObj->set_acquire(msg->this()->get_environment);
            LOG_MSG("...stored");
            return;
        }
        LOG_MSG("Type of #"+msg->get_object_id()+" is: "+msg->type()+"/"+msg->subtype());
        LOG_MSG("#"+msg->get_object_id()+" has "+i+" attachments, now converting...");
        array(Message) amAttachments=msg->attachments();
        array(Message) amText=({});
        array(Message) amNonText=({});
        for(int i=0; i<sizeof(amAttachments); i++)
        {
            string type = amAttachments[i]->type();
            string subtype = amAttachments[i]->subtype();
            LOG_MSG("attachment #"+i+" : "+type+"/"+subtype);
            if(lower_case(type)=="text")
            {
                amText+=({amAttachments[i]});
                LOG_MSG("-> comment to new document");
            }
            else
            {
                amNonText+=({amAttachments[i]});
                LOG_MSG("-> new document");
            }
        }
        LOG_MSG("found "+sizeof(amText)+" textual part(s) and "+sizeof(amNonText)+" non-textual part(s)");

	
	array annotations = ({ });
        if ( sizeof(amText) >= 1 )
        {
            LOG_MSG("converting text to annotation, non-text to document:");
            Message ann=amText[0];
	    foreach ( amText, Message ann ) {
	      annotations += ({ ann->this() });
	    }
        }
        if ( sizeof(amNonText) >=1 ) {
	  foreach ( amNonText, Message doc ) {
	    doc->add_to_header( msg->header() );
	    object docObj = doc->get_msg_object();
	    docObj->move(oMailBox->this()); //store document in container
	    docObj->set_acquire(docObj->get_environment);
	    foreach( annotations, object annotation )
	      oMailBox->this()->add_annotation(annotation->duplicate());
	  }
	}
	else {
	  foreach ( annotations, object annotation )
	    oMailBox->this()->add_annotation(annotation->duplicate());
	}
	LOG_MSG("finished!");
	msg->this()->delete();
    }
}

/**
 * this class is used for accessing sTeam-messageboards
 */
class MessageboardMailBox
{
    inherit BaseMailBox;
    
    void create(object target)
    {
        LOG_MSG("MessageboardMailBox->create() called:");
        ::create( target );
        iAllowedTypes = CLASS_DOCUMENT;
        iFolderTypes = 0; //messageboards have no subfolders
        aiEnterEvent = ({EVENT_ANNOTATE | EVENTS_MONITORED, EVENT_ANNOTATE});
        aiLeaveEvent = ({EVENT_REMOVE_ANNOTATION | EVENTS_MONITORED, EVENT_REMOVE_ANNOTATION});
        oMailBox=target;
        Message reply = ReplyMessage(oMailBox); //to simplify creation of new threads
        aoMessages=({reply});
        LOG_MSG("added reply-mail to mailbox");
        LOG_MSG("target id: "+target->get_object_id());
        LOG_MSG("target name: "+target->get_identifier());
        aoMessages+=scan_board_structure();
        LOG_MSG("box size is "+(sizeof(aoMessages)-1));
        alEnter=({MessagingListener(aiEnterEvent[0], oMailBox, notify_enter),
            MessagingListener(aiEnterEvent[1], oMailBox, notify_enter)});
        alLeave=({MessagingListener(aiLeaveEvent[0], oMailBox, notify_leave),
            MessagingListener(aiLeaveEvent[1], oMailBox, notify_leave)});
    }
    
    void notify_enter(int event, mixed ... args)
    {
        object what;
        if(event & EVENTS_MONITORED) what=args[3];
        else what=args[2];
        LOG_MSG("new message to box #"+oMailBox->get_object_id()+" :"+what->get_object_id());
        if(what->get_object_class() & iAllowedTypes)
            aoMessages+=({MessageboardMessage(what)});
        else LOG_MSG("... can't be converted to message - ignored");
    }
    
    void notify_leave(int event, mixed ... args)
    {
        object what;
        if(event & EVENTS_MONITORED) what=args[3];
        else what=args[2];
        int id=what->get_object_id();
        LOG_MSG("remove message in box #"+oMailBox->get_object_id()+" :"+id);
        if(what->get_object_class() & iAllowedTypes)
        {
            int found=0;
            int i=0;
            while(found!=1 && i<sizeof(aoMessages))
            {
                if(aoMessages[i]->get_object_id()==id) found=1;
                else i++;
            }
            if(found) aoMessages-=({aoMessages[i]});
            else LOG_MSG("message not found, already removed");
        }
        else LOG_MSG("... can't be converted to message - ignored");
    }

    private array(Message) scan_board_structure()
    {
        //perform BFS on anns of this board
        array(Message) res = ({});
        int tid = oMailBox->get_object_id();
        array(int) all = ({tid});
        array(int) queue = ({tid});
        mapping(int:int) discover=([tid:0]);
        mapping(int:int) parent=([tid:0]); //starting vertex has no parent
        int iter=0;
        while(sizeof(queue)>0)
        {
            tid=queue[0];
            array(object) inv=_Database->find_object(tid)->get_annotations();
            foreach(inv, object v)
            {
                int id=v->get_object_id();
                if(sizeof(all&({id}))==0)
                {
                    all+=({id}); queue+=({id});
                    discover+=([id:discover[tid]+1]);
                    parent[id]=tid; //this vertex has been discovered from "tid"
                }
             }
             queue-=({tid}); iter++;
        } //BFS is complete here
        int mboxid=oMailBox->get_object_id();
        m_delete(discover,mboxid); //mailbox is not part of result
        if(sizeof(discover)==0) return ({}); //no anns in messageboard
        foreach(sort(indices(discover)), tid)
        { //check if all needed headers are set
            object tmp=_Database->find_object(tid);
            Message msg=MessageboardMessage(tmp);
            mapping header=msg->header();
            if(zero_type(header["in-reply-to"]) && parent[tid]!=mboxid)
            {
                object parentTmp=_Database->find_object(parent[tid]);
                mapping parentHeader = parentTmp->query_attribute(MAIL_MIMEHEADERS);
                string msgId;
                if(mappingp(parentHeader)) msgId=parentHeader["message-id"];
                if(stringp(msgId) && msgId!="")
                    msg->add_to_header((["in-reply-to":msgId,"references":msgId]));
            }
            res+=({msg});
        }
        return res;
    }

    void add_message(Message msg)
    {
        aoMessages+=({msg});
        mapping temp=msg->header();
        m_delete(temp,"in-reply-to");
        m_delete(temp,"references");
        temp["reply-to"]="<"+msg->get_object_id()+"@"+_Server->query_config("machine")+"."+_Server->query_config("domain")+">";
        msg->this()->set_attribute(MAIL_MIMEHEADERS,temp);
        object tmp=msg->this()->get_annotating();
        if(objectp(tmp))
            tmp->remove_annotation(msg->this());
        oMailBox->add_annotation(msg->this());
        
        LOG_MSG("added #"+msg->get_object_id()+" to box #"+oMailBox->get_object_id());
    }

}

/**
 * creates a suitable MailBox-Object for the given target
 * support for more classes may be added in this function
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @param object target - the sTeam-Object to create a mailbox from
 * @return an object (of a subclass) of Messaging.BaseMailBox
 */
BaseMailBox get_mailbox(object target)
{
    if(target->get_object_class() & CLASS_USER)
      return UserMailBox(target);
    if(target->get_object_class() & CLASS_CONTAINER)
        return ContainerMailBox(target);
    if(target->get_object_class() & CLASS_MESSAGEBOARD)
        return MessageboardMailBox(target);

    LOG_MSG("get_mailbox() called for unknown class: "+
             target->get_object_class());
    return 0;
}

/**
 * stores a mail to a non-mailbox object
 * searches the proper target object according to the message-id in in-reply-to
 * or references headers
 * document of message is annotated to target object
 *
 * @author Martin B�hr
 * @param Message msg - the message to store
 * @param object target - the sTeam-object to annotate to
 * @return 1 if successful, 0 otherwise
 */
int add_message_to_object(Message msg, object target)
{   
    mapping header = msg->header();
    LOG_MSG("add_message_to_object(%s, %d)\n", header->subject, target->get_object_id());

    mapping missing_ids = target->query_attribute("OBJ_ANNO_MISSING_IDS");
    if(!mappingp(missing_ids))
        missing_ids = ([]);

    // seems like replies to this mail got here first, reattach them
    if(header["message-id"] && missing_ids[header["message-id"]])
    {
        foreach(missing_ids[header["message-id"]];; int oid)
        {
            object message = _Database->find_object(oid);
            message->get_annotating()->remove_annotation(message);
            message->set_acquire(msg->this());
            msg->this()->add_annotation(message);
        }
        m_delete(missing_ids, header["message-id"]);
    }

    // now lets find our real parent
    if(header["in-reply-to"] || header["references"])
    {
        mapping message_ids = target->query_attribute("OBJ_ANNO_MESSAGE_IDS");
        if(!message_ids)
            message_ids = ([]);
    
        object new_target;
    
        // now find the correct parent
        // best parent is a message with the id from in-reply-to
        // if we don't find that, store that id for reattaching
        array ids = ({});
        if(header["in-reply-to"])
            ids += Array.flatten(array_sscanf(header["in-reply-to"], "%{<%[^>]>%*[^<]%}"));
        if(header["references"])
            ids += reverse(Array.flatten(array_sscanf(header["references"], "%{<%[^>]>%*[^<]%}")));
    
        foreach(ids; int count; string id)
        {   
            id="<"+id+">";
            if(message_ids[id])
            {   
                new_target = _Database->find_object(message_ids[id]);
                break;
            }
            // the first reference is the best, save it, so the message
            // can be reattached, should the reference arrive later
            if(count==0)
            {
                if(!missing_ids[id])
                    missing_ids[id] = ({ msg->get_object_id() });
                else
                    missing_ids[id] += ({ msg->get_object_id() });
            }
        }
        target->set_attribute("OBJ_ANNO_MISSING_IDS", missing_ids);
    
        if(new_target)
            target = new_target;
    }

    // we are back to our regular programming
    mixed err = catch 
    { 
        target->add_annotation(msg->this()); 
	msg->this()->set_acquire(target);
	if ( (target->get_object_class() & CLASS_USER) ) {
	  msg->this()->sanction_object(target, SANCTION_ALL);
	  msg->this()->set_acquire(0);
	}
    };
        //attachments are already annotated to msg-object
    if(err!=0) 
    {
        FATAL("failed to annotate: %O with %O\n", target, msg->this());
        return 0;
    }

    int id=target->get_object_id();
    string reply=header["in-reply-to"];

    //needed for creation of missing headers
    string sServer = _Server->query_config("machine");
    string sDomain = _Server->query_config("domain");
    string sFQDN = sServer+"."+sDomain;

    if(!stringp(reply) || reply=="")
    {   
        if(mappingp(target->query_attribute(MAIL_MIMEHEADERS)))
        {   
            reply=target->query_attribute(MAIL_MIMEHEADERS)["message-id"];
            if(!stringp(reply) || reply=="") reply="<"+sprintf("%010d",id)+"@"+sFQDN+">";
        }
        else reply="<"+id+"@"+sFQDN+">";
    }
    string references=header["references"];
    if(!stringp(references) || references=="") references=reply;

    string message_id=header["message-id"];
    if(!stringp(message_id) || !sscanf(message_id, "<%*s>"))
      message_id = sprintf("<%010d@%s>", msg->get_object_id(), sFQDN);
 
    msg->add_to_header((["in-reply-to":reply,
                         "references":references,
                         "message-id":message_id ]));

    // create a table of all annotations so they can be referenced by the
    // message-id to allow propper threading of incoming mails.
    mapping annotation_ids = target->query_attribute("OBJ_ANNO_MESSAGE_IDS");
    if(!mappingp(annotation_ids))
      annotation_ids = ([]);
    annotation_ids[message_id] = msg->get_object_id();
    target->set_attribute("OBJ_ANNO_MESSAGE_IDS", annotation_ids);

    return 1;
}


/**
 * create an object of class Message
 *
 * @author <a href="mailto:sepp@upb.de">Christian Schmidt</a>
 * @input string raw - a string representing a MIME-message (rfc 2045-2049)
 * @return Message-object
 */
Message MIME2Message(string raw)
{
    MIME.Message msg = MIME.Message(raw);
    
    mapping msg_decoded_headers = ([]);
    foreach(msg->headers; string header; string value)
    {
        string decoded;
        catch
        {  
	    value = replace(value, "\0", "\n");
            decoded = MIME.decode_words_text_remapped(value);
        };
        msg_decoded_headers[header] = string_to_utf8(decoded||value);
    }
    
    if ( !stringp(msg_decoded_headers->subject)
         || sizeof(msg_decoded_headers->subject) < 1 )
      msg_decoded_headers->subject = " no subject ";

    string mimetype=msg->type+"/"+msg->subtype;
    object factory = _Server->get_factory(CLASS_DOCUMENT);
    object mail = factory->execute(
             ([ "name": replace(msg_decoded_headers["subject"], "/", "_"),
                "mimetype": mimetype,
                "attributes": ([ MAIL_MIMEHEADERS: msg_decoded_headers,
                                 OBJ_DESC: msg_decoded_headers->subject ]),
                ]) 
             );
    array (object) parts = msg->body_parts;
    if ( arrayp(parts) ) //multipart message, add parts as separate documents
    {
        LOG_MSG("found "+sizeof(parts)+" parts, now processing...");
        foreach(parts, MIME.Message obj) 
        {
            mapping obj_decoded_headers = ([]);
            foreach(obj->headers; string header; string value)
            {
                string decoded;
                catch
                {  
                    decoded = MIME.decode_words_text_remapped(value);
                };
                obj_decoded_headers[header] = string_to_utf8(decoded||value);
            }

            LOG_MSG("processing part:%O",obj);
            LOG_MSG("header is:%O",obj_decoded_headers);
            string description = obj_decoded_headers["subject"]
                                 || obj->get_filename()
                                 || msg_decoded_headers["subject"];
            string name = replace(description, "/", "_");
            mimetype=obj->type+"/"+obj->subtype;
            object annotation = factory->execute
                ((["name": name,
                   "mimetype" : mimetype]));
	    if ( objectp(annotation) )
	      annotation->set_attribute( OBJ_DESC, description );
            LOG_MSG("created sTeam-Annotation");
            if(obj->getdata()!=0)
              annotation->set_content(obj->getdata());
            else 
              annotation->set_content("dummy value, no real content right now");
            annotation->set_attribute(MAIL_MIMEHEADERS,obj_decoded_headers);
            annotation->set_acquire(mail); //inherit access-rights of mail
            mail->add_annotation(annotation);
        }    
    }
    mixed maildata = msg->getdata();
    if ( !stringp(maildata) ||
         ( sizeof(maildata)<1 && arrayp(msg->body_parts) &&
           sizeof(msg->body_parts)>0 ) )
        mail->set_content("This document was received as a multipart e-mail,"
             "\nthe content(s) can be found in the annotations/attachments!");
    else
        mail->set_content(msg->getdata());

    LOG_MSG("Finished conversion raw text -> message");
    return Message(mail);
}

Message SimpleMessage(array(string) target, string subject, string message)
{
  	object factory = _Server->get_factory(CLASS_DOCUMENT);
	object mail = factory->execute
	    ((["name": subject, "mimetype": "text/plain"]));
	mail->set_content(message+"\r\n");
	if ( objectp(mail) )
	  mail->set_attribute( OBJ_DESC, subject );
	
	Message msg=Message(mail);
	mapping header=msg->header();
	string to = target*", ";
	header["to"]=to;
	msg->this()->set_attribute(MAIL_MIMEHEADERS,header);
	    
	return msg;
}

//support for modified UTF7
//see RFC3501, section 5.1.3 & RFC2152
//
static string mbase64tab="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890+,";

string decode_mbase64(string encoded)
{
    //decode a modified-base64-encoded string
    switch(sizeof(encoded)%4)
    {
        case 0:
            break;
        case 1:
            encoded+="\0\0\0";
            break;
        case 2:
            encoded+="\0\0";
            break;
        case 3:
            encoded+="\0";
    }
    string result="";
    while(sizeof(encoded)>0)
    {
        string part=encoded[0..3];
        if(sizeof(encoded)>3)
            encoded=encoded[4..sizeof(encoded)-1];
        else encoded="";
        int p1=search(mbase64tab,part[0..0]);
        int p2=search(mbase64tab,part[1..1]); if(p2==-1)p2=0;
        int p3=search(mbase64tab,part[2..2]); if(p3==-1)p3=0;
        int p4=search(mbase64tab,part[3..3]); if(p4==-1)p4=0;
        int b1= (p1<<2) | (p2&0b110000);
        int b2= (p2<<4)&255 | (p3&0b111100)>>2;
        int b3= (p3<<6)&255 | p4;
        result+=sprintf("%c%c%c",b1,b2,b3);
    }
    if(sizeof(result)%2==1) result=result[0..sizeof(result)-2];
    result=unicode_to_string(result);
    return result;
}

string encode_mbase64(string input)
{
    //encode a string via modified-base64-encoding
    input=string_to_unicode(input);
    switch(sizeof(input)%3)
    {
        case 0:
            break;
        case 1:
            input+="\0\0";
            break;
        case 2:
            input+="\0";
            break;
    }
    string result="";
    while(sizeof(input)>0)
    {
        string part=input[0..2];
        if(sizeof(input)>2)
            input=input[3..sizeof(input)-1];
        else input="";
        int p1=part[0];
        int p2=part[1];
        int p3=part[2];
        int b1=p1>>2;
        int b2=(p1&0b11)|(p2>>4);
        int b3=(p2&0b1111)<<2|(p3>>6);
        int b4=p3&0b111111;
        result+=mbase64tab[b1..b1];
        if(b2!=0)
        {
            result+=mbase64tab[b2..b2];
            if(b3!=0)
            {
                result+=mbase64tab[b3..b3];
                if(b4!=0)
                    result+=mbase64tab[b4..b4];
            }
        }
    }
    return result;
}

string decode_mutf7(string encoded)
{
    string result="";
    int i=-1;
    while(i<sizeof(encoded))
    {
        int start=i;
        i=search(encoded,"&",i+1);
        if(i==-1)
        {
            result+=encoded[start+1..sizeof(encoded)-1];
            i=sizeof(encoded);
        }
        else
        {
            result+=encoded[start+1..i-1];
            if(encoded[i+1]=='-')
            {
                result+="&"; //sequence "&-" found
                i++;
            }
            else
            {
                int j=search(encoded,"-",i+1);
                if(j!=-1)
                {
                    result+=decode_mbase64(encoded[i+1..j-1]);
                    i=j;
                }
                else return 0; //syntax error in mutf7-string
            }
        }
    }
    return result;
}

string encode_mutf7(string input)
{
    string result="",tombase64="";
    int mode=0;
    for(int i=0;i<sizeof(input);i++)
    {
        int val=input[i];
        if(val==0x26)
        {
            if(mode)
            {
                mode=0;
                result+="&"+encode_mbase64(tombase64)+"-";
                tombase64="";
            }
            result+="&-";
            continue;
        }
        if(val>=0x20 && val<=0x7e)
        {
            if(mode)
            {
                mode=0;
                result+="&"+encode_mbase64(tombase64)+"-";
                tombase64="";
            }
            result+=input[i..i];
            continue;
        }
        mode=1;
        tombase64+=input[i..i];
    }
    if(mode)
        result+="&"+encode_mbase64(tombase64)+"-";
    return result;
}

//the following functions are only needed to avoid security-errors while creating
//sTeam-objects in "MIME2MEssage":
// get_object_id, this & get_object_class


int get_object_id()
{
  return get_object()->get_object_id();
}

object this()
{
  return get_object();
}

object get_object() 
{
  object user = geteuid();
  if ( !objectp(user) )
    user = this_user();

  if ( objectp(user) )
    return user;
  return get_module("forward");
}

int get_object_class()
{
  return get_object()->get_object_class();
}

string fix_html ( string text )
{
  string new_text = text;
  string tmp = lower_case( text );
  if ( search( tmp, "<body" ) < 0 ) new_text = "<BODY>\n" + new_text;
  if ( search( tmp, "</body>" ) < 0 ) new_text = new_text + "\n</BODY>";
  if ( search( tmp, "<html" ) < 0 ) new_text = "<HTML>\n" + new_text;
  if ( search( tmp, "</html>" ) < 0 ) new_text = new_text + "\n</HTML>";
  return new_text;
}
