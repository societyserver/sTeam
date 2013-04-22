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
 * $Id: line.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: line.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/coalsocket";

#include <macros.h>

//#define LINE_DEBUG

#ifdef LINE_DEBUG
#define DEBUG_LINE(s) werror(s+"\n")
#else
#define DEBUG_LINE(s)
#endif

static string sReadBuffer = "";
static function dataFunction;

static void register_data_func(function f)
{
  dataFunction = f;
}

static void unregister_data_func()
{
  dataFunction = 0;
}

/**
 * Process an incomming command. Called for each CR-LF Line.
 *  
 * @param string cmd - the command line
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see read_command_lines
 */
static void process_command(string cmd)
{
}

/**
 * This function is called by read_callback. It tries to extract
 * commands (CR-LF) from the read buffer.
 *  
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see read_callback
 * @see process_command
 */
static final void read_command_lines()
{
    int      i;
    string cmd;
    
    while ( (i=search(sReadBuffer, "\n")) != -1 ) {
//	if ( sReadBuffer[i-1] == '\r' ) i--;
	
        cmd = sReadBuffer[..i-1];
        cmd = cmd - "\n"; //sometimes cmd still had \n's or \r's
        cmd = cmd - "\r"; //this should fix it...

	if ( i+2 >= strlen(sReadBuffer) )
	    sReadBuffer = "";
	else
	    sReadBuffer = sReadBuffer[i+1..];

	DEBUG_LINE("CMD: " + cmd);  //FIXME: there might be passwords in here.
	DEBUG_LINE("BUFFER: " + sReadBuffer);
	mixed err = catch {
	    process_command(cmd);
	};
	if ( err != 0 ) {
          FATAL("Error: " + err[0] + "\n"+sprintf("%O", err));
	}
	DEBUG_LINE("set_this_user(0)\n");
    }
}

/**
 * Called when the steam socket receives some message.
 *  
 */
static void receive_message(string data)
{
  if ( functionp(dataFunction) ) {
    dataFunction(data);
    return;
  }
  
  sReadBuffer += data;
  
  while ( search(sReadBuffer, "\n") >= 0 )
    read_command_lines();
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
void send_result(mixed ... results)
{
    DEBUG_LINE("RESULT:  " + (results*" "));
    send_message((results * " ")+"\r\n");
}

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
static void send_message(string msg)
{
    DEBUG_LINE("MESSAGE: " + msg);
    ::send_message(msg);
}
