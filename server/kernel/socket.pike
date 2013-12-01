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
 * $Id: socket.pike,v 1.2 2009/08/04 16:28:01 nicke Exp $
 */

constant cvs_version="$Id: socket.pike,v 1.2 2009/08/04 16:28:01 nicke Exp $";

inherit Stdio.File : socket;

#include <classes.h>
#include <macros.h>
#include <assert.h>
#include <config.h>

private static string          __buffer;
private static int                __len;
private static function  fWriteFunction;
private static function fFinishFunction;

#ifdef THREAD_READ
private static Thread.Condition write_cond = Thread.Condition();
private static Thread.Mutex         read_mutex = Thread.Mutex();
private static Thread.Queue msgQueue = Thread.Queue();
private static Thread.Queue closeQueue = Thread.Queue();
#endif

#ifdef SOCKET_DEBUG
#define DEBUG(s) werror("["+__id+"] "+s+"\n")
#else
#define DEBUG(s)
#endif

#define ISCLOSED (closeQueue->size() > 0)

int __id;

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp 
 * @see 
 */
static void 
disconnect()
{
    DEBUG("DISCONNECT()\n");
    mixed err = catch {
        ::close();
    };
    if ( err != 0 )
	DEBUG("While disconnecting socket:\n"+sprintf("%O",err));
    if ( objectp(read_mutex) )
	destruct(read_mutex);
}

/**
 * send a message to the client
 *  
 * @param str - the message to send
 * @author Thomas Bopp 
 * @see write_callback
 */
static void send_message(string str) 
{
    DEBUG("send_message("+strlen(str)+" bytes...)");
    msgQueue->write(str);
}

/**
 * this function is called when there is free space for writting
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see read_callback
 * @see register_send_function
 * @see send_message
 */
static void write_callback(string __buffer)
{
    int written;
    mixed     w;
    int     len;
    
    DEBUG("write_callback("+strlen(__buffer)+
	  ", closed?"+(ISCLOSED?"true":"false"));


    if ( ISCLOSED ) return;

    len = strlen(__buffer);

    if ( functionp(fWriteFunction) ) {
	w = fWriteFunction(__len);
       
	if ( !stringp(w) ) {
	    fFinishFunction();
	    fWriteFunction  = 0;
	    fFinishFunction = 0;
	}
	else {
	    __len += strlen(w);
	    msgQueue->write(w);
	}
    }
    while ( strlen(__buffer) > 0 ) {
	mixed err = catch {
	    written = write(__buffer);
	    DEBUG("written " + written + " bytes...");
	};
	if ( err != 0 ) {
	    __buffer = "";
	    DEBUG("error while writting:\n"+sprintf("%O\n",err));
	    return;
	}
	
	if ( written < 0 ) {
	    return;
	}
	if ( written < strlen(__buffer ) ) {
	    if ( written > 0 )
		__buffer = __buffer[written..];
	    else if ( written == 0 ) 
		sleep(0.1);
	}
	else
	    return;
    }
}

/**
 * this function is called when data is received on the socket
 *  
 * @param id - data for the socket
 * @param data - the arriving data
 * @author Thomas Bopp 
 * @see write_callback
 */
static void read_callback(mixed id, string data) 
{
}

static void was_closed()
{
    closeQueue->write("");
}

/**
 * The read thread reads data.
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
final static void tread_data()
{
    string str;

    if ( ISCLOSED ) return;
    
    mixed err = catch {
	str = socket::read(SOCKET_READ_SIZE, 1);
    };
    DEBUG("Returning from read...\n");
    
    if ( err != 0 || !stringp(str) || strlen(str) == 0 ) {
      DEBUG("Socket was closed while in read...");
      was_closed();
    }
    else {
        DEBUG("Reading " + strlen(str) + " bytes...\n");
	read_callback(0, str);
    }
}

/**
 * close the connection to the client
 *  
 * @author Thomas Bopp 
 */
void
close_connection()
{
    DEBUG("close_connection()");
    closeQueue->write("");
    msgQueue->write("");

    mixed err = catch {
        socket::set_read_callback(0);
    };
}

/**
 * create the object (the constructor)
 *  
 * @param f - the portobject
 * @author Thomas Bopp 
 */
static void create(object f) 
{
    socket::assign(f);
    __buffer = "";
    fWriteFunction = 0;
    socket::set_blocking();
    socket::set_buffer(65536*10, "w");
    socket::set_buffer(65536*10, "r");
    thread_create(read_thread);
}

/**
 * Get the ip of this socket.
 *  
 * @return the ip number 127.0.0.0
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string|int get_ip()
{
  mixed   err;
  string addr;

  err = catch {
    addr = query_address();
  };
  if ( err != 0 )
    addr = "no connected";
  LOG("query_adress() returns " + addr);
  string ip = 0;
  if ( stringp(addr) )
    sscanf(addr, "%s %*d", ip);
  return ip;
}


/**
 * register a callback function for writting data to the socket
 * if there is already a function defined there will be a runtime error
 *  
 * @param f - the callback function
 * @author Thomas Bopp (astra@upb.de) 
 * @see write_callback
 */
static void register_send_function(function f, function e)
{
    ASSERTINFO(!functionp(fWriteFunction), 
	       "Allready defined writer function !");

    string w = f(0);
    if ( !stringp(w) )
	return;
    
    fWriteFunction  = f;
    fFinishFunction = e;
    __len = strlen(w);
    msgQueue->write(w);
}


#ifdef THREAD_READ

/**
 * The main function for the reader thread. Calls tread_data() repeatedly.
 *  
 * @author Thomas Bopp (astra@upb.de) 
 * @see tread_data
 */
final static void read_thread()
{
    DEBUG("read_thread() created, now creating write_thread()...");

    thread_create(write_thread);
    while ( !ISCLOSED ) {
	DEBUG("!ISCLOSED and reading data....");
	tread_data();
    }
    DEBUG("Read Thread Ended....");
    closeQueue->write("");
    DEBUG("Read Thread Ended....: CloseQueue="+closeQueue->size());
    msgQueue->write("end");
}


/**
 * The main function for the writer thread. Calls the write_callback() 
 * repeatedly and waits for signals.
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
final static void
write_thread()
{
    string msg;
    DEBUG("write_thread() created ...");
    while ( !ISCLOSED && (msg = msgQueue->read()) ) {
	write_callback(msg);
    }
    DEBUG("disconnecting socket...: CloseQueue="+closeQueue->size());
    
    disconnect();
    closeQueue->write("");
}
#endif

string describe()
{
  return "Socket("+__id+", closed="+closeQueue->size()+","+get_ip()+")";
}

void set_id(int i) { __id = i; }
int get_id() { return __id; }
bool is_closed() { return closeQueue->size() >= 2; }
int is_closed_num() { return closeQueue->size(); }
string get_identifier() { return "socket"; }





