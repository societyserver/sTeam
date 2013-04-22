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
 * $Id: config.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: config.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";


#define METHOD_GETS     1
#define METHOD_READLINE 0

static         mapping vars = ([ ]);
private static string      sContext;
static         int           method;
Stdio.Readline readln = Stdio.Readline(Stdio.stdin);

/**
 *
 *  
 * @param 
 * @return 
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see 
 */
mapping handle_options(array argv, mapping options)
{
    mapping mOptions = ([ "options": ({ }) ]);

    foreach ( argv, string arg ) {
	string oname, oval;
	if ( sscanf(arg, "--%s=%s", oname, oval) == 2 ) {
	    mOptions[oname] = oval;
	}
	else if ( sscanf(arg, "--%s", oname) == 1 )
	    mOptions[oname] = 1;
	else if ( sscanf(arg, "-%s", oname) == 1 ) {
	    if ( stringp(options[oname]) )
		mOptions[options[oname]] = 1;
	    else
		werror("Unknown Option: " + arg + "\n");
	}
	else
	    mOptions["options"] += ({ arg });
    }
    return mOptions;
}


/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
mixed read_input(string desc, mixed def_value, void|mixed ... values)
{
    string                               str;
    mixed                              value;
    int                               ok = 0;

    while ( !ok ) {
      if ( method == METHOD_GETS ) {
	write(desc+" ["+def_value+"]: ");
	str = Stdio.stdin.gets();
      }
      else {
	str = readln->read(desc + " ["+def_value+"]: ");
      }

      if ( !stringp(str) || strlen(str) == 0 ) {
	value = def_value;
	ok = 1; 
      }
      else {
	if ( sscanf(str, "%d", value) != 1 || str != (string)value )
	  value = str;
	
	if ( stringp(def_value) && stringp(value) )
	  ok = 1;
	else if ( intp(def_value) && intp(value) )
	  ok = 1;
	if ( arrayp(values) && sizeof(values) > 0 && 
	     search(values, value) < 0 )
	  ok = 0;
      }
    }
    return value;
}


/**
 *
 *  
 * @param fname - a file that should be detected at the path
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
string read_path(string desc, string def_value, string fname)
{
    string server_path;
    int         ok = 0;
    Stdio.File       f;

    while ( !ok ) {
	server_path = read_input(desc, def_value);
	if ( server_path[strlen(server_path)-1] != '/' )
	    server_path += "/";
	mixed err = catch {
	    f = Stdio.File(server_path + fname, "r");
	};
	if ( objectp(f) ) {
	    ok = 1;
	    f->close();
	}
    }
    return server_path;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static mixed exchange_vars(Parser.HTML p, string data)
{
    if ( stringp(data) && strlen(data) > 0 )
    {
	if ( data[0] == '$' && 
	     zero_type(vars[data[1..]]) != 1 ) {
	    data = (string)vars[data[1..]];
	}
    }
    return ({ data });
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
void copy_config_file(string from, string to, object parser)
{
    Stdio.File   f;
    string content;

    f = Stdio.File(from, "r");
    content = f->read();
    f->close();
    parser->feed(content);
    parser->finish();
    content = parser->read();
    f = Stdio.File(to, "wct");
    f->write(content);
    f->close();
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
private static int cb_context(Parser.HTML p, string tag)
{
    tag = p->parse_tag_name(tag);
    tag = tag[1..strlen(tag)-2];
    sContext = replace(tag,":", "_");
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
private static int read_config(Parser.HTML p, string data)
{ 
    int d;

    if ( sContext[0] == '/' ) return 0;
    
    // empty config file ?
    if ( stringp(data) && data[0] == '$' )
	return 0;
    
    if ( sscanf(data, "%d", d) == 1 )
	vars[sContext] = d;
    else
	vars[sContext] = data;
    return 0;
}

static void read_configs(string fname)
{
    string content;

    if ( !Stdio.exist(fname) )
	error("Configuration file " + fname +  " not found.");
    
    content = Stdio.read_file(fname);
    object p = Parser.HTML();
    p->_set_tag_callback(cb_context);
    p->_set_data_callback(read_config);
    p->feed(content);
    p->finish();
}

