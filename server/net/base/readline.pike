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
 * $Id: readline.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: readline.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <macros.h>

static object _fd;

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

static final void read_command_lines(mixed id, string cmd)
{
  cmd-="\n";
  cmd-="\r";
  master()->set_this_user(this_object());
  mixed err = catch { process_command(cmd); };
  if ( err != 0 ) 
  {
    MESSAGE("Error: " + err[0] + "\n"+
	    sprintf("%O", err));
  }
  master()->set_this_user(0);
}

static void read_callback(mixed id, string data)
{
  MESSAGE("READ_CALLBACK(%s)", data);
  read_command_lines(id, data);
}

void send_result(mixed ... results)
{
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
static void send_message(string format, mixed ... args)
{
    string msg=sprintf(format, @args);
    if(readln && readln->readline)
      readln->readline->write(msg);
    else
    {   
      write(msg);
      //::send_message(msg);
      //init(my_fd);
    }
}

object readln;

//readline seems to need some time to set up.
//it also seems to insist on a static string here
int n;
static void init_readline( )
{ 
  if( readln->readline )
  { 
      werror("Readline initialized !\n");
      readln->readline->set_echo(1);
      readln->readline->write("-\n", 1);
      process_command("connect"); 
      // initialize the command loop
      // if we don't do this here, then the initial messages would have to
      // be sent from create and init_readline would mess them up
      return;
  }
  n++;
  if( n < 100 )
    call_out( init_readline, 0.1 );
  else
  { 
    readln->message("Failed to set up terminal.\n");
  }
}

/**
 *
 *
 * @param
 * @return
 * @author Thomas Bopp
 * @see
 */
static void disconnect()
{
    mixed err = catch {
      readln->close();
    };
//    if ( err != 0 )
//        DEBUG("While disconnecting socket:\n"+sprintf("%O",err));
}

int __id;
void set_id(int i) { __id = i; }
int isClosed;
bool is_closed() { isClosed; }
// int is_closed_num() { return 0; }


void create(object f)
{
    _fd = f;
    readln = Protocols.TELNET.Readline(f, read_callback, 0, 0, 0);
    init_readline();
}

/**
 * Get the ip of this socket.
 *  
 * @return the ip number 127.0.0.0
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
string|int get_ip()
{
    string addr = _fd->query_address();
    string ip = 0;
    if ( stringp(addr) )
	sscanf(addr, "%s %*d", ip);
    return ip;
}
