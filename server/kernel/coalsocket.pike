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
 * $Id: coalsocket.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: coalsocket.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";


//! this is a basic socket object with nonblocking IO
//! it just handles correct receiving and writting of data
//! and calls appropriate callback functions.

#include <macros.h>
#include <config.h>

//#define SOCKET_DEBUG

#ifdef SOCKET_DEBUG
#define DEBUG(s) werror("["+__id+"]: "+s+"\n")
#else
#define DEBUG(s)
#endif

object _fd;

private static Thread.Queue msgQueue = Thread.Queue();

private static string          __buffer;
private static int             __closed;
private static int                __len;
private static int      __last_response;
private static int                 __id; // identifier - for debugging

private static function  fWriteFunction;
private static function fFinishFunction;

void receive_message(string data) { }

/**
 * This callback function is the standard function to read data.
 * Most importantly it sets the active user before calling the COAL
 * receive_message function
 *  
 * @param mixed id - no idea, does not do anything
 * @param string data - the received data
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see write_callback
 */
void f_read_callback(mixed id, string data)
{
    int su = set_this_user(this_object());
    mixed err = catch {
	__last_response = time();
	receive_message(data);
    };
    if ( err != 0 ) {
	FATAL("Error on command:\n" + PRINT_BT(err));
    }
    if ( su ) set_this_user(0);
}

void f_write_callback(mixed id)
{
    string str;

    // main backend needs to call this / no concurrent threads!
    while ( stringp(str=msgQueue->try_read()) )
      __buffer += str;

    if ( __closed )
	return;
    
    int written = 1;
    mixed         w;
    int         len;
    

    while ( written > 0 ) {
	if ( functionp(fWriteFunction) ) {
	    w = fWriteFunction(__len);
	    
	    if ( !stringp(w) ) {
		fFinishFunction();
		fWriteFunction  = 0;
		fFinishFunction = 0;
	    }
	    else {
		__len += strlen(w);
		__buffer += w;
	    }
	}
	len = strlen(__buffer);
	if ( len == 0 )
	    return;
	
	mixed err = catch {
	  written = _fd->write(__buffer);
	  DEBUG("Written " + written + " bytes...");
	};
	if ( err != 0 ) {
	    DEBUG("Error while writting(buffer="+strlen(__buffer)+" bytes)\n");
	    __buffer = "";
	    __closed = 1;
	    return;
	}
	
	if ( written < 0 ) {
	    __closed = 1;
	    return;
	}
	if ( written < strlen(__buffer ) ) {
	    if ( written > 0 )
		__buffer = __buffer[written..];
	}
	else {
	    __buffer = "";
	}
    }
}

/**
 * Send a message to the socket.
 *  
 * @param string msg - the coal message for the client
 */
static void send_message(string msg)
{
    if ( is_closed() ) {
	DEBUG("sending on closed socket\n");
	error("Attempt to send on a closed socket.\n");
    }
    msgQueue->write(msg);
    call(f_write_callback, 0.0, 0);
}


static void set_fd(object fd)
{
    __buffer = "";
    __len = 0;
    __closed = 0;
    fWriteFunction = 0;

    __last_response = time();

    _fd = fd;
    
    _fd->set_nonblocking(f_read_callback,f_write_callback,f_close_connection);
    if ( functionp(_fd->set_buffer) ) {
	_fd->set_buffer(64000,"r");
	_fd->set_buffer(64000,"w");
    }

}

/**
 * Overloaded create method calls create in socket and coal basis
 * objects.
 *  
 * @param object f - the connection (file, whatever)
 */
void create(object f)
{
    set_fd(f);
}

/**
 * Register a send function to send data to the socket. This is required,
 * because the socket cannot hold all of the data directly, so everytime
 * there is free space on the socket to write out a message the function
 * is called.
 *  
 * @param function f - the send function
 * @param function e - the function called when sending is finished
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void register_send_function(function f, function e)
{
    if ( functionp(fWriteFunction) )
	steam_error("Allready defined writer function !");
    
    string w = f(0);
    if ( !stringp(w) )
	return;
    
    fWriteFunction  = f;
    fFinishFunction = e;

    // initially call function to get writting going
    __len = strlen(w);
    msgQueue->write(w);
    f_write_callback(0);
}

void set_id(int i)
{
    __id = i;
}

int get_id()
{
    return __id;
}

void close_connection()
{
    DEBUG("Connection closed by\n");
    __closed = 1;
    catch(_fd->close());
}

private final static void f_close_connection()
{
    DEBUG("Connection closed by peer.");
    close_connection();
}

string describe()
{
    return "CoalSocket(closed="+__closed+","+get_ip()+","+
	(time()-__last_response)+")";
}

/**
 * Get the ip of this socket.
 *  
 * @return the ip number 127.0.0.0
 */
string|int get_ip()
{
  mixed   err;
  string addr;

  err = catch {
    addr = _fd->query_address();
  };
  if ( err != 0 )
    addr = "no connected";
  string ip = 0;
  if ( stringp(addr) )
    sscanf(addr, "%s %*d", ip);
  return ip;
}

string query_address() 
{
    return _fd->query_address();
}

int get_last_response() 
{
    return __last_response;
}

int get_idle()
{
    return time() - __last_response;
}

void destroy()
{
    DEBUG("coalsocket::destroy()\n");
}

int is_closed()
{
    return __closed;
}

object query_fd()
{
  return _fd;
}


