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
 * $Id: doxygen.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: doxygen.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#define MODE_IN_CLASS 6
#define MODE_FUNCDEF  4
#define MODE_REMOVE   2

int convert_file(string fname)
{
    string name, ext, dir;
    dir = dirname(fname);
    name = basename(fname);
    if ( sscanf(name, "%s._%s", name, ext) != 2 )
	return 0;
    
    write("reading... "+ fname);
    string code = Stdio.read_file(dir + "/"+name+"."+ext);
    if ( !stringp(code) )
      return 0;
    Stdio.File outfile = Stdio.File(fname, "wct");
    string header;
    sscanf(code, "%*s/*%s*/%s", header, code);

    // todo detect all classes and do inherit correct for all classes.

    array(string) tokens = Parser.Pike.split(code);
    array inherits = ({ });
    for ( int i = 0; i < sizeof(tokens); i++) {
	if ( tokens[i] == "inherit" ) {
	    string inh_name;
	    if ( sscanf(tokens[i+2], "\"%s\"", inh_name) != 1 )
		continue;
	    inh_name = basename(inh_name);
	    inherits += ({ inh_name });
	}
    }
    array lines = code / "\n";
    string inherit_code = "";
    string include_code = "";
    string mod_doc = "";

    code = "";
    int level = 0;
    int colevel = 0;
    int mode = 0;
    mapping _inherits = ([ ]);
    int clnum = 0;


    foreach ( lines, string l ) {
	if ( colevel == level ) {
	    if ( mode == 2 ) {
		code += "\npublic:\n";
		mode = 0;
	    }
	    if ( mode == 4 ) {
		code += "\npublic:\n";
		mode = 0;
	    }
	    if ( mode == MODE_IN_CLASS )
		mode = 0;
	}

	if ( (search(l, "init_") >= 0 || search(l, "retrieve_") >= 0 ||
	      search(l, "store_") >= 0 || search(l, "private") >= 0 ) && 
	     search(l, ";") == -1 ) 
	{
	    code += "private:\n";
	    mode = 1;
	}
	else if ( search(l, "static ") >= 0 && search(l, ";") == -1 )
	{
	    code += "protected:\n";
	    mode = 3;
	}

	if ( search(l, "{") >= 0 ) {
	    if ( (mode % 2) == 1 ) {
		colevel = level;
		mode++;
	    }
	    level++;
	}
	if ( search(l, "}") >= 0 )
	    level--;

	if ( search(l, "inherit ") >= 0 ) {
	    string inh;
	    sscanf(l, "%*s\"%s\"%*s", inh);
	    
	    inherit_code += l + "\n";
	    if ( clnum > 0 && stringp(inh)) {
		if ( inh[0] == '/' )
		    inh = inh[1..];
		sscanf(inh, "%s.pike", inh);
		_inherits[clnum] += ({ inh });
	    }
	}
	else if ( search(l, "#include") == 0 )
	    include_code += l +"\n";
	else if ( search(l, "//!") == 0 ) 
	    mod_doc += l + "\n";
	else if ( search(l, "class") == 0 ) {
	    string clname;
	    if ( sscanf(l, "class %s{", clname) == 1 ) {
		code += "class "+ clname +" {\npublic:\n";
	    }
	    else {
		code += l + "\n";
		mode = 5;
	    }
	    clnum++;
	    _inherits[clnum] = ({ });
	}
	else if ( search(l, "constant cvs_version") == -1 &&
		  search(l, "this()") == -1 &&
		  search(l, "test()") == -1 &&
		  search(l, "require_save()") == -1 &&
		  search(l, "@author") == -1 )
	    code += l +"\n";

	if ( mode == 6 ) {
	    code += "public:\n";
	    mode = 0;
	}
    }
    array linherits = ({ });
    foreach(indices(_inherits), clnum) {
	if ( sizeof(_inherits[clnum]) == 0 )
	    linherits += ({ "" });
	else
	    linherits += ({ ": public " + (_inherits[clnum]*",") });
    }
    
    string out;

    if ( search(fname, "pmod") == -1 ) 
	out = "class "+name+" "+
	    //(sizeof(inherits) > 0 ? "extends "+inherits[0] + " " : "")+
	    (sizeof(inherits) > 0 ? ": public " + (inherits * ","):"")+
	    //(sizeof(inherits) > 1 ? "implements "+(inherits[1..]*",") + " ":"")+
	    "{\npublic:\n";
    else
	out = "";
    
    if ( 0 && sizeof(linherits) ) 
	code = sprintf(code, @linherits);

    out += replace(code, ({ 
	"array(string)", "array(object)", "array(int)",
	    "array(mixed)",
	    "mapping(int:mapping(string:int))",
	    "mapping(string:object)",
	    "mapping(int:object)",
	    "static",
	    }),
		   ({ "array","array","array","array",
			  "mapping","mapping","mapping", "",
			  }));
    out += "\n};\n";
    outfile->write("/*"+header+"*/\n"+inherit_code + include_code + 
		   mod_doc + out);
    outfile->close();
    return 1;
}

void main(int argc, array argv)
{
    // read doxygen configuration
    array files = ({ });
    string conf = Stdio.read_file("Doxyfile");
    string input;
    sscanf(conf, "%*sINPUT%*s=%s", input);
    array lines = input / "\n";
    int cont = 1;
    foreach(lines, string line) {
	string fname = line;
	if ( sscanf(line, "%s \\",fname) != 1 )
	    cont = 0;

	fname = String.trim_whites(fname);
	if ( convert_file(fname) )
	    files += ({ fname });
	werror("FILE="+fname+"\n");
	if ( cont == 0 ) {
	    break;
	}
    }
    int ret = Process.create_process( ({ "doxygen" }),
				      ([ "env": getenv(),
				       "cwd": getcwd(),
				      ]))->wait();

    foreach(files, string f )
	rm(f);
}





