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
 * $Id: cmd.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: cmd.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <macros.h>
#include <database.h>

void check_exec_access()
{
    if ( objectp(_CODER) && sizeof(_CODER->get_members()) > 0 ) {
	// check if User code is allowed, creator needs to be coder
	// and no other user should have write access on this script
	if ( !_CODER->is_member(this_user()) && 
	     !_ADMIN->is_member(this_user()) )
	    THROW("Unauthorized Script", E_ACCESS);
    }
}

static string show_result(mixed result)
{
    string res = "";
    function describe;
    
    if ( objectp(result) ) {
        if (IS_PROXY(result))
            describe = result->find_function("describe");
        else
            describe = result->describe;
        
        if ( functionp(describe) )
	    res += describe();
	else if ( functionp(result->describe) )
	    res += result->describe();
	else if ( functionp(result->get_identifier) && 
                  functionp(result->get_object_id) )
	{
	  if ( result->status() <= 0 )
	    res += "(deleted object)";
	  else
	    res += sprintf("%s[%d]", result->get_identifier(),
			   result->get_object_id());
	}
	else
	    res += "(object)\n"+sprintf("%O",mkmapping(indices(result),values(result)));
    }
    else if ( arrayp(result) ) {
	res += "{ ";
	foreach( result, mixed r ) {
	    res += show_result(r) + ",";
	}
	res += " }";
    }
    else if ( mappingp(result) ) {
	res += "[ ";
	foreach(indices(result), mixed i) {
	    res += show_result(i) + ":"+show_result(result[i]) + ", ";
	}
	res += " ]";
    }
    else {
	res += sprintf("%O", result);
    }
    return res;
}

static string execute(string scode)
{
    check_exec_access();
    if ( scode[strlen(scode)-1] != ';' )
	scode += ";";
    
    string code = "inherit \"/kernel/exec_base\";\n"+
	"inherit \"/classes/Object\";\n"+
	"#include <macros.h>\n"+
	"#include <database.h>\n"+
	"#include <classes.h>\n"+
	"#include <types.h>\n"+
	"#include <attributes.h>\n"+
	"#include <events.h>\n"+
	"#include <access.h>\n"+
	"#include <client.h>\n"+
        "#include <roles.h>\n"+
	"#include <config.h>\n"+
	"mixed exec_code()\n{\n"+
	(scode[0] == '=' ? "return " + scode[1..] :
	 scode[1..]+"\nreturn 0;") + "\n}";
    
    mapping result;
    mixed      res;

    object e = master()->ErrorContainer();
    master()->set_inhibit_compile_errors(e);
    mixed err = catch { 
	program prg = compile_string(code); 
	object o = new(prg);
	o->init_variables(this_user());
	LOG("Executing code !");
	res = o->exec_code();
	LOG("Execution done !");
	o->save_variables(this_user());
	result = this_user()->query_attribute("_exec_");
	result["Result"] = res;
    };
    master()->set_inhibit_compile_errors(0);
    if ( err != 0 ) {
	return sprintf("Err: %s\n%s\n%s", (string)e->get(), err[0], 
		       master()->describe_backtrace(err[1]))+"\n"+code;
    }
    return nice_result(result);
}

static string nice_result(mapping result)
{
    string res = "";
    string v = " ";
    LOG("Creating a nice result ?!");
    foreach(indices(result), mixed idx) {
	if ( stringp(idx) ) {
	    res += sprintf("%s=%s\n", idx, show_result(result[idx]));
	}
	else if ( result[idx] != 0 ) {
	    v[0] = (idx+97);
	    res += sprintf("%s=%s\n", v, show_result(result[idx]));
	}
    }
    LOG("nice_result() done !");
    return res;
}

static string cmd_compile(string fname)
{
    mixed err = 0;

    object doclpc = _FILEPATH->path_to_object(fname);

    if ( fname[0] == '!' ) {
	string content = Stdio.read_file(fname[1..]);
	err = catch {
	    compile_string(content);
	};
    }
    else if ( objectp(doclpc) ) {
	err = catch { 
	    program prg = compile_string(doclpc->get_content());
	};
    }
    else
	return "File not found.\n";
	
    if ( err == 0 ) {
	return "No Errors...\n";
    }
    else 
	return sprintf("%O\n", err);
}
