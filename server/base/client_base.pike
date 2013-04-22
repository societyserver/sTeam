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
 * $Id: client_base.pike,v 1.2 2009/08/07 15:22:37 nicke Exp $
 */

constant cvs_version="$Id: client_base.pike,v 1.2 2009/08/07 15:22:37 nicke Exp $";

inherit Stdio.File;
inherit "/net/coal/binary";
inherit "serialize";

#include <coal.h>
#include <exception.h>
#include <client.h>
#include <macros.h>

#define CLIENT_FEATURES ((1<<31)-1)

private static string      sLastPacket; // last package while communicating
private static int                iOID; // the object id of the current object
private static int                iTID; // the current transaction id
private static int            iWaitTID;
        static mapping      mVariables; // session variables
        static array           aEvents;
private static mapping    mVariableReq; // requests for setting variables
private static mapping mVariableReqInv; // inverse requests
private static mapping        mObjects; // objects
private static mixed          miResult;
private static string       sLoginName;
        static int         __connected;
private static int             doThrow;

object decryptRSA;
object encryptRSA;
string decryptBuffer = "";

#define ERR_CONTINUE 0
#define ERR_FATAL    1
#define ERR_THROW    2

// mutex stuff for threads
private static Thread.Mutex      command_mutex = Thread.Mutex();
private static object                     read_lock, write_lock;
private static Thread.Condition  read_cond = Thread.Condition();
private static Thread.Condition write_cond = Thread.Condition();

int set_object(object|int id);
mixed send_command(int cmd, array(mixed) args, int|void do_wait);


class SteamObj 
{
  private static int oID; 
  private static string identifier = 0;
  private static int cl = 0;
  
  int get_object_id() {
    return oID;
  }
  int get_object_class() {
    if ( cl == 0 ) {
      int wid = iWaitTID;
      int id = set_object(oID);
      mixed res = send_command(COAL_COMMAND, ({ "get_object_class" }));
      if ( intp(res) )
	  cl = res;
      set_object(id);
      iWaitTID = wid;
    }
    return cl;
  }
  string get_identifier() {
    if ( !stringp(identifier) ) {
      int wid = iWaitTID;
      int id = set_object(oID);
      identifier = send_command(COAL_COMMAND, ({ "get_identifier" }));
      set_object(id);
      iWaitTID = wid;
    }
    return identifier;
  }
  void create(int id) {
    oID = id;
  }
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 * 
 */
static object find_obj(int id)
{
    if ( !mObjects[id] ) {
	mObjects[id] = SteamObj(id);
    }
    return mObjects[id];
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static string translate_exception(int exc)
{
    string ex = "";
    if ( exc & E_ERROR )
	ex += "error,";
    if ( exc & E_LOCAL )
	ex += "local,";
    if ( exc & E_MEMORY )
	ex += "memory fault,";
    if ( exc & E_EVENT )
	ex += "event,";
    if ( exc & E_ACCESS )
	ex += "access failure,";
    if ( exc & E_PASSWORD )
	ex += "wrong password,";
    if ( exc & E_NOTEXIST )
	ex += "non existing,";
    if ( exc & E_FUNCTION )
	ex += "function,";
    if ( exc & E_FORMAT )
	ex += "invalid format,";
    if ( exc & E_OBJECT )
	ex += "object,";
    if ( exc & E_TYPE )
	ex += "wrong type,";
    if ( exc & E_MOVE )
	ex += "move error,";
    if ( exc & E_LOOP )
	ex += "command will cause endless loop,";
    if ( exc & E_LOCK )
	ex += "object locked,";
    
    return ex;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static string 
get_login()
{
    return sLoginName;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
mixed
get_variable(int|string key)
{
    return mVariables[key];
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static mixed
set_variable(int|string key, mixed val)
{
    mVariables[key] = val;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
int connect_server(string server, int port)
{
    iTID = 1;
    iOID = 0;
    sLastPacket = "";
    mVariableReq    = ([ ]);
    mVariableReqInv = ([ ]); 
    mVariables      = ([ ]);
    mObjects        = ([ ]);
    aEvents         = ({ });
    sLoginName = "not logged in";
    
    open_socket();
    set_blocking();
    if ( connect(server, port) ) {
	LOG("Connected to " + server + ":"+port +"\n");
	__connected = 1;
	set_buffer(65536, "r");
	set_buffer(65536, "w");
	set_blocking();
	thread_create(read_thread);
	return 1;
    }
    return 0;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
int receive_message(int id, string str)
{
    int slen, tid, cmd, lid, len, n;
    mixed                      args;

    if ( !stringp(str) )
	return -1;
    slen = strlen(str);
    if ( slen == 0 )
	return -1;
    for ( n = 0; n < slen-10; n++ )
	if ( str[n] == COMMAND_BEGIN_MASK )
	    break;
    if ( n >= slen-18 ) 
	return -1;
    str = str[n..];
	
    len    = (int)((str[1]<<24)+(str[2]<<16)+(str[3]<<8) + str[4]);

    if ( len > slen )
	return -1;

    tid    = (int)((str[5] << 24) + (str[6]<<16) + (str[7]<<8) + str[8]);
    cmd    = (int)str[9];
    lid    = (int)((str[10] << 24) + (str[11]<<16) + (str[12]<<8) + str[13]);
    
    wstr = str;
    args = receive_args(18);
    if ( arrayp(args) )
	args = args[0];
    wstr = "";
    
    miResult = args;
    iOID = lid;

    doThrow = 0;
    if ( cmd == COAL_ERROR ) {
	sLastPacket = "";
	int errRes = handle_error(miResult);
	switch(errRes) {
	case ERR_FATAL:
	    exit(1);
	    break;
	case ERR_THROW:
	    doThrow = 1;
	    break;
	case ERR_CONTINUE:
	    break;
	}
    }
    else if ( cmd == COAL_EVENT ) {
	miResult += ({ lid });
	handle_event(miResult);
    }
    else {
	//LOG(sprintf("%d:%O\n", tid,miResult));
    }
    
    if ( mVariableReq[tid] !=  0 ) {
	LOG("Setting variable "+ mVariableReq[tid] + "\n");
	mVariables[mVariableReq[tid]] = args[0]; // ?
	mVariableReq[tid] = 0;
    }
    if ( mVariableReqInv[tid] != 0 ) {
	LOG("Setting variable "+ args[0] + ":"+
	    sprintf("%O", mVariableReqInv[tid])+"\n");
	mVariables[args[0]] = mVariableReqInv[tid];
	mVariableReqInv[tid] = 0;
    }
    if ( slen > len )
	sLastPacket = str[len..];
    else
	sLastPacket = "";
    return tid;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int handle_error(mixed err)
{
    return ERR_THROW;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int handle_event(mixed event)
{
    aEvents += ({ event });
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
void read_thread()
{
    int       rcv;
    string   resp;
    mixed     err;

    read_lock = command_mutex->lock();
    read_cond->wait(read_lock);
    sLastPacket = "";
    while( __connected ) 
    {
	rcv = 0;
	while ( rcv != iWaitTID && __connected ) {
	    resp = ::read(8192,1);
            if ( !stringp(resp) ) {
                __connected = 0;
                return;
            }
	    LOG("*");
	    if ( objectp(decryptRSA) ) {
		resp = decryptBuffer + resp;
		decryptBuffer = "";
		int i = 0;
		int l = strlen(resp);
		string decryptBlock = "";
		while ( i+64 <= l ) {
		    decryptBlock += decryptRSA->decrypt(resp[i..i+63]);
		    i+=64;
		}
		if ( (l%64) != 0 )
		    decryptBuffer = resp[(l-(l%64))..];
		resp = decryptBlock;
	    }
	    sLastPacket += resp;
	    rcv = 0;
	    while ( rcv >= 0 && err == 0 && rcv != iWaitTID ) {
		rcv = receive_message(0, sLastPacket);
	    }
	}
	write_cond->signal();
	read_cond->wait(read_lock);
    }
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
mixed send_command(int cmd, array(mixed) args, int|void no_wait)
{
    if ( !no_wait ) iWaitTID = iTID;
    aEvents  = ({ });
    
    string msg = coal_compose(iTID++, cmd, iOID, 0, args);
    string nmsg = copy_value(msg);
    
    if ( objectp(encryptRSA) ) {
	nmsg  = "";
	int l = strlen(msg);
	int i = 0;
	while ( i < l ) {
	    if ( i+32 > l )
		nmsg += encryptRSA->encrypt(msg[i..]);
	    else 
		nmsg += encryptRSA->encrypt(msg[i..i+31]);
	    i+=32;
	}
    }
    
    write(nmsg);
    if ( !no_wait ) {
	read_cond->signal();
	write_cond->wait(write_lock);
	if ( doThrow ) {
	    throw(({"sTeam Server error:\n"+
		  translate_exception(miResult[0])+"\n"+
		  serialize(miResult)+"\n", backtrace() }));
	}
    	return miResult;
    }
    return 0;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
mixed send_cmd(object|int obj, string func, mixed|void args, void|int no_wait)
{
    int oid = set_object(obj);
    if ( zero_type(args) )
	args = ({ });
    else if ( !arrayp(args) )
	args = ({ args });
    
    mixed res = send_command(COAL_COMMAND, ({ func, args }), no_wait);
    set_object(oid);
    return res;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
mixed login(string name, string pw, int features, string|void cname)
{
    if ( objectp(write_lock) )
	destruct(write_lock);
    write_lock = command_mutex->lock();

    if ( !stringp(cname) )
	cname = "steam-pike";

    mixed loginData;
    if ( features == 0 )
      loginData = send_command(COAL_LOGIN,({name, pw, cname, features }));
    else
      loginData = send_command(COAL_LOGIN,({name, pw, cname,CLIENT_FEATURES}));
    if ( arrayp(loginData) && sizeof(loginData) >= 9 ) {
	mVariables["user"] = iOID;
	sLoginName = loginData[0];
	foreach ( indices(loginData[8]), string key ) {
	    mVariables[key] = loginData[8][key];
	}
	mVariables["rootroom"] = loginData[6];
	sLastPacket = "";
	foreach ( values(loginData[9]), object cl ) {
	    set_object(cl->get_object_id());
	    mVariables[send_command(COAL_COMMAND, ({"get_identifier",({ })}))]
		= cl;
	}
	return name;
    }
    return 0;
}

mixed server_hello(string cert)
{
  return send_command(COAL_SERVERHELLO, ({ cert }));
}


mixed logout()
{
    if ( objectp(write_lock) )
	destruct(write_lock);
    write_lock = command_mutex->lock();
    __connected = 0;
    write(coal_compose(iTID++, COAL_LOGOUT,0, 0, ({ })));
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static int set_object(int|object id)
{
  int old_id = iOID;
  if ( objectp(id) )
    iOID = id->get_object_id();
  else
    iOID = id;
  return old_id;
}

static int get_object()
{
    return iOID;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static array
get_events()
{
    return aEvents;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int get_commands()
{
    return iTID;
}

void create(object|void id)
{
    // do nothing...
}
