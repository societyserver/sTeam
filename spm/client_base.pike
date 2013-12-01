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
 * $Id: client_base.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: client_base.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "kernel/socket";
inherit "net/coal/binary";

#include <coal.h>
#include <macros.h>
#include <client.h>

private static mapping        mObjects; // objects
private static string      sLastPacket; // last package while communicating
private static int                iOID; // the object id of the current object
private static int                iTID; // the current transaction id
private static int            iWaitTID;
        static mapping      mVariables; // session variables
        static array           aEvents;
        static int         __connected;
        static int     __downloadBytes;
               int     __last_response;
        static function  downloadStore;

private static mixed          miResult;
private static int           miCommand;

static Thread.Mutex    cmd_mutex =     Thread.Mutex();
static Thread.Condition cmd_cond = Thread.Condition();
static Thread.Queue      resultQueue = Thread.Queue();
static object                                cmd_lock;

string connected_server;
int connected_port;

class SteamObj 
{
  private static int oID; 
  private static string identifier = 0;
  private static int cl = 0;
  private static int(0..1) nowait;
  private static mapping(string:function) functions=([]);
  
  int get_object_id() {
    return oID;
  }

  object get_environment() {
    return send_command(COAL_COMMAND, ({ "get_environment" }));
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
  int status() {
    return 1; //PSTAT_SAVE_OK
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

  int no_wait(void|int(0..1) _nowait)
  {
    if(!zero_type(_nowait) && nowait == !_nowait)
    {
      nowait=!!_nowait;
      return !nowait;
    }
    else
      return nowait;
  }

  string function_name(function fun)
  {
    return search(functions, fun);
  }

  string _sprintf()
  {
    mixed describe="";
    catch{ describe=`->("describe")(); };
    string format = "";
    if ( stringp(connected_server) ) format += "%s:";
    else format += "%O:";
    if ( intp(connected_port) ) format += "%d/";
    else format += "%O/";
    if ( stringp(describe) ) format += "%s";
    else format += "%O";
    return sprintf( format, connected_server, connected_port, describe );
  }

  function `->(string fun) 
  {
    if(::`->(fun))
      return ::`->(fun);
    else
    {
      if ( fun == "exec_code" )
	return 0;
      else if ( fun == "serialize_coal" )
	return 0;
      if(!functions->fun)
        functions[fun]=lambda(mixed|void ... args)
                       { 
                         return send_cmd(oID, fun, args, nowait); 
                       };
      return functions[fun];
    }
  }
  function find_function(string fun) {
    if(!functions->fun)
      functions[fun]=lambda(mixed|void ... args)
		     { 
		       return send_cmd(oID, fun, args, nowait); 
		     };
    return functions[fun];
  }
};


/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
int set_object(int|object id)
{
    int oldID = iOID;

    if ( objectp(id) )
	iOID = id->get_object_id();
    else
	iOID = id;
    return oldID;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static object find_obj(int id)
{
    if ( !mObjects[id] ) {
	mObjects[id] = SteamObj(id);
	//werror("Created:"+master()->describe_object(mObjects[id])+"\n");
    }
    return mObjects[id];
}

object find_object(int id) { return find_obj(id); }


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

    sLastPacket     = "";
    __downloadBytes =  0;
    mVariables      = ([ ]);
    mObjects        = ([ ]);
    aEvents         = ({ });
    
    open_socket();
    set_blocking();
    if ( connect(server, port) ) {
	MESSAGE("Connected to " + server + ":"+port +"\n");
	connected_server=server;
	connected_port=port;
	__last_response = time(); // timestamp of last response	
	__connected = 1;
	set_buffer(65536, "r");
	set_buffer(65536, "w");
	set_blocking();
	thread_create(read_thread);
	return 1;
    }
    return 0;
}

void create()
{
}

static int write(string str)
{
    __last_response = time();
    return ::write(str);
}


/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
void read_callback(object id, string data)
{
    __last_response = time();
    
    if ( functionp(downloadStore) ) {
	mixed err = catch {
	    downloadStore(data);
	};
	__downloadBytes -= strlen(data);
	if ( __downloadBytes <= 0 ) {
	    downloadStore(0);
	    downloadStore = 0; // download finished
	}
	return;
    }
    sLastPacket += data;
    if ( __downloadBytes > 0 ) {
	if ( __downloadBytes <= strlen(sLastPacket) )
	    resultQueue->write(sLastPacket);
	return;
    }

    mixed res = receive_binary(sLastPacket);
    if ( arrayp(res) ) {
	int tid = res[0][0];
	int cmd = res[0][1];

	sLastPacket = res[2];
	if ( tid == iWaitTID ) {
	    miResult = res[1];
	    miCommand = res[0][1];
	    resultQueue->write(miResult);
	}
    }
}

string download(int bytes, void|function store) 
{
    // actually the last command should have been the upload response,
    // so there shouldnt be anything on the line except events
    // which should have been already processed
    // everything else should be download data
    string data;
    __downloadBytes = bytes;

    if ( functionp(store) ) {
	data = copy_value(sLastPacket[..bytes]);
	__downloadBytes -= strlen(data);
	if ( strlen(data) > 0 )
	    store(data);
	if ( __downloadBytes <= 0 ) {
	    store(0);
	    return "";
	}
	downloadStore = store;
	return "";
    }
    downloadStore = 0;

    if ( strlen(sLastPacket) >= bytes ) {
	data = copy_value(sLastPacket[..bytes]);
	if ( bytes > strlen(sLastPacket) )
	    sLastPacket = sLastPacket[bytes+1..];
	else
	    sLastPacket = "";
	__downloadBytes = 0;
	return data;
    }

    miResult = resultQueue->read();
    data = copy_value(sLastPacket[..bytes]);
    if ( strlen(sLastPacket) > bytes )
	sLastPacket = sLastPacket[bytes+1..];
    else
	sLastPacket = "";
    __downloadBytes = 0;
    return data;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
void handle_error(mixed err)
{
    throw(err);
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

    send_message(nmsg);
    if ( no_wait ) return 0;
    
    mixed result = resultQueue->read();
    if ( miCommand == COAL_ERROR ) {
	handle_error(result);
    }
    return result;
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
mixed 
login(string name, string pw, int features, string|void cname, int|void novars)
{
    if ( !stringp(cname) )
	cname = "steam-pike";
    
    mixed loginData;
    if ( features != 0 )
	loginData =send_command(COAL_LOGIN, ({ name, pw, cname, features, __id }));
    else
	loginData =
	    send_command(COAL_LOGIN,({ name, pw, cname,CLIENT_FEATURES_ALL, __id}));
    
    if ( arrayp(loginData) && sizeof(loginData) >= 9 ) {
	mVariables["user"] = iOID;
	foreach ( indices(loginData[8]), string key ) {
	    mVariables[key] = loginData[8][key];
	}
	mVariables["rootroom"] = loginData[6];
	sLastPacket = "";
	if ( novars != 1 ) {
	    foreach ( values(loginData[9]), object cl ) {
		set_object(cl->get_object_id());
		mVariables[send_cmd(cl,"get_identifier")] = cl;
	    }
	}
	return name;
    }
    return 0;
}

mixed logout()
{
    werror("logout()!!!\n\n");
    __connected = 0;
    write(coal_compose(0, COAL_LOGOUT, 0, 0, 0));
}


void was_closed()
{
    resultQueue->write("");
    ::was_closed();
}


void write_error2file(mixed|string err, int recursive) {

    Stdio.File error_file;
    string             path;
    array(string) directory;
    int file_counter =0;
    int found=0;
    path = getcwd();
    directory = get_dir(path);
    while (found==0){
        int tmp_found=1;
        tmp_found=Stdio.exist(path+"/install_error."+file_counter);
        if (tmp_found==1){
            file_counter = file_counter + 1;
        }
        else{
            found = 1;
        }
    }

    if (recursive==1)
        file_counter = file_counter -1;
    error_file=Stdio.File (path+"/install_error."+file_counter ,"cwa");
    if (stringp (err)){
        error_file->write(err);
    }
    if(arrayp(err)){
        foreach(err, mixed error){
            if ( stringp(error) || intp(error) )
                error_file->write((string)error);
            else if ( objectp(error) )
                error_file->write("<object...>\n");
            else if ( arrayp(error) ){
                write_error2file(error,1);
            }
        }
    }
    if (recursive!=0)
        error_file->close();
}



