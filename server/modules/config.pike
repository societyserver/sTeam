inherit "/kernel/module";

#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>
#include <configure.h>

/** TODO: handle hbs(...), handle configs in database */

static string config_path = CONFIG_DIR;

string get_identifier() { return "config"; }

static string|int|float get_value( string val )
{
    int d;
    float f;
    if ( sscanf(val, "%d", d) == 1 && (string)d == val )
	return d;
    else if ( sscanf(val, "%f", f) == 1 && (string)f == val )
	return f;
    return val;
}

static string value_to_string ( mixed val )
{
    if ( stringp(val) ) return val;
    else if ( intp(val) ) return sprintf("%d",val);
    else if ( floatp(val) ) return sprintf("%f",val);
    else return 0;
}

mapping read_config_file ( string filename )
{
    string content = Stdio.read_file( filename );
    if ( lower_case(content[0..4]) == "<?xml" )
	return read_config_xml( content, filename );
    else
	return read_config_text( content, filename );
}

bool write_config_file ( string filename, mapping config )
{
    string head = Stdio.read_file( filename, 0, 5 );
    string content = 0;
    if ( lower_case(head) == "<?xml" )
	content = write_config_xml( config );
    else
	content = write_config_text( config );
    if ( !stringp(content) )
	werror( "Could not write config to %s, invalid config\n", filename );
    else {
	mixed err = catch {
	    Stdio.write_file( filename, content );
	};
	if ( err == 0 )
	    return true;
	werror( "Could not write config to %s, i/o error\n", filename );
	return false;
    }
    return false;
}

static mapping read_config_text ( string data, void|string source )
{
    if ( ! stringp(data) ) return 0;
    string source_str = "";
    if ( stringp(source) ) source_str = "in " + source + " ";
    mapping m = ([ ]);
    array lines = data / "\n";
    foreach ( lines, string line ) {
	line = String.trim_all_whites( line );
	if ( strlen(line) == 0 ) continue;
	if ( line[0] == '#' ) continue;
	string key, value;
	if ( sscanf( line, "%s=%s",key, value ) != 2 )
	    werror( "Invalid config line %s: %s\n", source_str, line );
	key = String.trim_all_whites( key );
	value = String.trim_all_whites( value );
	m[key] = get_value( value );
    }
    return m;
}


string write_config_text ( mapping config )
{
    if ( !mappingp(config) ) return 0;
    string s = "";
    foreach ( indices(config), string key ) {
	string v = value_to_string (config[key] );
	if ( stringp(v) )
	    s += key + "=" + v + "\n";
	else
	    werror( "Invalid value for config mapping: %O\n", v );
    }
    return s;
}


mapping read_config_xml ( string data, void|string source )
{
    if ( ! stringp(data) ) return 0;
    string source_str = "";
    if ( stringp(source) ) source_str = ": " + source;
    mapping m = ([ ]);

    object node = Parser.XML.Tree.parse_input( data );
    if ( !objectp(node) ) {
	werror( "Could not parse xml config" + source_str + "\n" );
	return 0;
    }

    node = node->get_first_element("config");
    foreach(node->get_elements(), Parser.XML.Tree.Node n) {
	string t = n->get_tag_name();
	mixed val = get_value( n->get_last_child()->get_text() );

	if ( stringp(m[t]) )
	    m[t] = ({ m[t], val });
	else if ( arrayp(m[t]) )
	    m[t] += ({ val });
	else
	    m[t] = val;
    }
    return m;
}


string write_config_xml ( mapping config )
{
    if ( !mappingp(config) ) return 0;
    string s = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<config>\n";
    foreach ( indices(config), string key ) {
	mixed value = config[key];
	if ( arrayp(value) ) {
	    foreach ( value, mixed subvalue ) {
		string v = value_to_string( subvalue );
		if ( stringp(v) ) s += "<"+key+">"+v+"</"+key+">\n";
		else werror( "Invalid value for config mapping: %O\n", v );
	    }
	}
	else {
	    string v = value_to_string( value );
	    if ( stringp(v) ) s += "<"+key+">"+v+"</"+key+">\n";
	    else werror( "Invalid value for config mapping: %O\n", v );
	}
    }
    s += "</config>";
    return s;
}
