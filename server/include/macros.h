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
 * $Id: macros.h,v 1.2 2010/01/25 18:50:10 astra Exp $
 */

#ifndef _MACROS_H
#define _MACROS_H


#include "exception.h"
#include "config.h"

#define bool int
#define true  1
#define false 0
#define null  0

#define PROXY(o) (o->this)
#define MIN(i,j) (i < j ? i : j)
#if !constant(steamtools.get_caller) 
#define CALLER Caller.get_caller(this_object(), backtrace())
#else
#define CALLER steamtools.get_caller(this_object())
#endif
#define MCALLER (CALLER == master() ? PREVCALLER : CALLER)

#define PREVCALLER function_object(backtrace()[-3][2])

#define CALLINGFUNCTION function_name(backtrace()[-2][2])

#define CALLERCLASS backtrace()[-2][0]

#define CALLERPROGRAM object_program(function_object(backtrace()[-2][2]))

#define MESSAGE(s, args...) write("["+Calendar.Second(time())->format_time()+"] "+s+"\n", args)
#define MESSAGE_START(s, args...) write("["+Calendar.Second(time())->format_time()+"] "+s, args)
#define MESSAGE_APPEND(s, args...) write(s, args)
#define MESSAGE_END(s, args...) write(s+"\n", args)

#define WARN(s, args...) werror(s+"\n", args)

#ifdef DEBUG
#define LOG(s) werror(s+"\n")
#else
#define LOG(s)
#endif

#define FATAL(s, args...) werror("-------------------------------\n"+ctime(time())+s+"\n", args)

#define _LOG(s) werror("("+this_object()->get_object_id()+") "+s+"\n")

#ifdef DEBUG
#define TRACE(s) werror("["+master()->stupid_describe(this_object())+"]"+s+"\n")
#else
#define TRACE(s) 
#endif

#define LOG_DB(s) catch {_Server->get_module("log")->log_text("database",s); }
//#define LOG_DB

//#define LOG_DB(s) werror("DB:"+s+"\n")

#ifdef DEBUG_SECURITY
#define SECURITY_LOG(s, args...) if (1) {if (_Server->get_module("log")) _Server->get_module("log")->log_security(s, args);}
#else
#define SECURITY_LOG(s, args...)
#endif

#define LOG_BOOT(s) catch { _LOG->log_boot(s); }

#define LOG_EVENT(s) catch{_LOG->log_event(s);}

#define LOG_ERR(s) catch{_LOG->log_error(s);}

#define LOG_DEBUG(s) catch{_Server->get_module("log")->log_debug(s);}
#define PRINT_BT(c) ("Error: " + c[0] + "\n" + master()->describe_backtrace(c[1]))

#define THROW(c, e) throw( ({ c, backtrace(), e}))
#define IS_SOCKET(o) (master()->is_socket(o))

#define NIL (([])[""])

#define CONTENTOF(x) _FILEPATH->path_to_object(x)->get_content()

#define T_INT     "int"
#define T_STRING  "string"
#define T_FLOAT   "float"
#define T_OBJECT  "object"
#define T_MAPPING "mapping"
#define T_ARRAY   "array"



#define IS_PROXY(o) (object_program(o) == (program)"/kernel/proxy.pike" || object_program(o) == (program)"/kernel/proxy")

#define URLTYPE_FS       0
#define URLTYPE_DB       1
#define URLTYPE_HTTP     2
#define URLTYPE_RELOC    3
#define URLTYPE_DBO      4
#define URLTYPE_DBFT     5

#define MAX_BUFLEN       65504    

#endif
