/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: log.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: log.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

inherit "/kernel/module";

#include <database.h>
#include <config.h>
#include <macros.h>
#include <attributes.h>

int     iLogDebug=0;

constant LOG_LEVEL = ([ "none":LOG_LEVEL_NONE,
                        "error":LOG_LEVEL_ERROR, 
			"fatal":LOG_LEVEL_ERROR,
                        "warning":LOG_LEVEL_WARNING,
                        "info":LOG_LEVEL_INFO,
                        "debug":LOG_LEVEL_DEBUG ]);

static      int iRequests;
static mapping  mRequests;
static      int iDownload;
static mapping    mMemory;
static mapping   mObjects;
static mapping  mLogFiles;
static mapping mLogLevels;
static mapping mBacktraceLevels;
static string logs;

void init_module()
{
    iRequests = 0;
    iDownload = 0;
    mRequests = ([ ]);
    mMemory   = ([ ]);
    mObjects  = ([ ]);

    logs = _Server->get_config("logdir");
    mLogFiles = ([ "security": LOG_LEVEL_ERROR,
                   "events": LOG_LEVEL_ERROR,
                   "http": LOG_LEVEL_ERROR,
                   "smtp":LOG_LEVEL_ERROR, 
		   "slow_requests":LOG_LEVEL_INFO,
    ]);
    mLogLevels = ([ ]);
    mBacktraceLevels = ([ ]);
    
    foreach ( indices(mLogFiles), string logname ) 
      log_init(logname);
}

void debug_mem()
{
    int t = time();
    mMemory[t] = _Server->debug_memory();
    mObjects[t] = master()->get_in_memory();
    mRequests[t] = iRequests;
    call_out(debug_mem, 60);
}

mapping get_memory()
{ 
    return mMemory;
}

mapping get_objects()
{
  return mObjects;
}

mapping get_request_map()
{
  return mRequests;
}

void add_request()
{
  iRequests++;
}


int get_requests()
{
  return iRequests;
}

void add_download(int bytes)
{
  iDownload += bytes;
}

int get_download()
{
  return iDownload;
}

void log_init(string logfile)
{
    mLogFiles[logfile] = Stdio.File(logs + logfile + ".log", "wct");
    if ( !zero_type(_Server->get_config(logfile+"_log_level")) )
      mLogLevels[logfile] = LOG_LEVEL[_Server->get_config(logfile+"_log_level")];
    else
      mLogLevels[logfile] = LOG_LEVEL_ERROR;
    if ( !zero_type(_Server->get_config(logfile+"_backtrace_level")) )
      mBacktraceLevels[logfile] = LOG_LEVEL[_Server->get_config(logfile+"_backtrace_level")];
    else
      mBacktraceLevels[logfile] = LOG_LEVEL_NONE;
}

array get_logs()
{
  return indices( mLogFiles );
}

void set_log_level(string logfile, int level)
{
    mLogLevels[logfile] = level;
}

int get_log_level(string logfile)
{
  return mLogLevels[logfile];
}

void set_backtrace_level(string logfile, int level)
{
  mBacktraceLevels[logfile] = level;
}

int get_backtrace_level(string logfile)
{
  return mBacktraceLevels[logfile];
}

void log_error(string logfile, string msg, mixed ... args)
{
  log( logfile, LOG_LEVEL_ERROR, "["+Calendar.now()->format_time()+"] ERROR: "+msg+"\n", @args );
}

void log_warning(string logfile, string msg, mixed ... args)
{
  log( logfile, LOG_LEVEL_WARNING, "["+Calendar.now()->format_time()+"] WARNING: "+msg+"\n", @args );
}

void log_info(string logfile, string msg, mixed ... args)
{
  log( logfile, LOG_LEVEL_INFO, "["+Calendar.now()->format_time()+"] INFO: "+msg+"\n", @args );
}

void log_debug(string logfile, string msg, mixed ... args)
{
  log( logfile, LOG_LEVEL_DEBUG, "["+Calendar.now()->format_time()+"] DEBUG: "+msg+"\n", @args );
}

void log(string logfile, int level, string msg, mixed ... args) 
{
  if ( mLogLevels[logfile] < level && mBacktraceLevels[logfile] < level ) {
    return;
  }
  Stdio.File log = mLogFiles[logfile];
  if ( !objectp(log) )
    steam_error("No such Logfile " + logfile);

  string what = msg;
  if ( arrayp(args) && sizeof(args) > 0 )
    what = sprintf(what, @args);
  
  log->write(what+"\n");

  if ( mBacktraceLevels[logfile] >= level )
    log->write( describe_backtrace( backtrace() ) );
}

void log_security(string str, mixed ... args)
{
  log("security", LOG_LEVEL_DEBUG, str, @args);
}


void set_debug(int on)
{
    iLogDebug = on;
}

string get_identifier() { return "log"; }
