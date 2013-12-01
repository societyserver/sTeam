/**
 * Config.pmod - Read and parse config data from files or strings.
 *
 * Syntax for plaintext configs:
 * #comment
 * ;comment
 * [my_section]
 * my_key = my_value
 *
 * Syntax for XML configs:
 * <!--comment-->
 * <my_section>
 *   <my_key> my_value </my_key>
 * </my_section>
 */

#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>
#include <configure.h>


enum { CONFIG_TYPE_UNKNOWN, CONFIG_TYPE_TEXT, CONFIG_TYPE_XML };


/**
 * Determine the type of a config string.
 * @param data config data
 * @returns the type of the config data: CONFIG_TYPE_UNKNOWN, CONFIG_TYPE_TEXT, CONFIG_TYPE_XML
 */
int get_config_type ( string data )
{
  if ( !stringp(data) )
    return CONFIG_TYPE_UNKNOWN;
  if ( sizeof(data) >= 5 && lower_case(data[0..4]) == "<?xml" )
    return CONFIG_TYPE_XML;
  else
    return CONFIG_TYPE_TEXT;
}

/**
 * Read and parse a config file. Auto-detect the type (plaintext or xml).
 * @param filename filename of the config file (usually CONFIG_DIR+"...")
 * @param section if specified, then only a certain section of the file is read
 *   and returned.
 *   XML syntax: <my_section>...</my_section>.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns a mapping containing the keys and values from the config file
 */
mapping read_config_file ( string filename, void|string section )
{
  string content = Stdio.read_file( filename );
  if ( !stringp(content) )
    return ([ ]);
  return get_config( content, section );
}


/**
 * Parse a config data string. Auto-detect the type (plaintext or xml).
 * @param data the config data string (e.g. the content of a config file)
 * @param section if specified, then only a certain section of the file is read
 *   and returned.
 *   XML syntax: <my_section>...</my_section>.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns a mapping containing the keys and values from the config file
 */
mapping get_config ( string data, void|string section )
{
  if ( get_config_type(data) == CONFIG_TYPE_XML )
    return get_config_xml( data, section );
  else if ( get_config_type(data) == CONFIG_TYPE_TEXT )
    return get_config_text( data, section );
  else
    return ([ ]);
}


/**
 * Write a mapping of key/value pairs into  a config file.
 * Auto-detect the type of the file (plaintext or xml) if it already exists.
 * @param filename filename of the config file (usually CONFIG_DIR+"...")
 * @param section if specified, then the key/value pairs are only written to
 *   a certain section of the file.
 *   XML syntax: <my_section>...</my_section>.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns true on success, false if the file could not be written
 */
bool write_config_file ( string filename, mapping config, void|string section )
{
    string head = Stdio.read_file( filename, 0, 5 );
    string content = 0;
    if ( lower_case(head) == "<?xml" )
	content = make_config_xml( config );
    else
	content = make_config_text( config );
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


/**
 * Read and parse a plaintext config, returning a mapping of keys, their values,
 *  and the line numbers (starting at 0) where those keys appear in the config.
 * You can use this to find out which keys are defined where in the input file.
 * You will probably never use this function, but rather use get_config_text().
 * @param data a string containing the config data (Lines with "key=value" pairs)
 * @param section if specified, then only a certain section of the file is read
 *   and returned.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns a mapping ([ key : ({ line_nr, value }) ]). If a section was specified,
 *   then the line number of the section tag is returned as key "#SECTION_START"
 *   and the last line of the section as key "#SECTION_END". If the section cannot
 *   be found, then both have a line number of -1.
 * @see get_config_text
 */
mapping find_config_text ( string data, void|string section )
{
    if ( ! stringp(data) ) return 0;
    mapping m = ([ ]);
    array lines = data / "\n";
    int line_nr = 0;
    
    if ( stringp(section) ) {
      m["#SECTION_START"] = ({ -1, "" });
      m["#SECTION_END"] = ({ -1, "" });
      // skip to section:
      for ( ; line_nr < sizeof(lines) ; line_nr++ ) {
	string line = String.trim_all_whites( lines[line_nr] );
        if ( search( line, "["+section+"]" ) == 0 ) {
          m["#SECTION_START"] = ({ line_nr, line });
          line_nr++;
          break;
        }
      }
    }
    
    for ( ; line_nr < sizeof(lines) ; line_nr++ ) {
      string line = String.trim_all_whites( lines[line_nr] );
      if ( strlen(line) == 0 ) continue;
      if ( (line[0] == '#') || (line[0] == ';') ) continue;
      if ( sscanf( line, "[%*s]%*s" ) >= 1 ) {  // next section found
        if ( stringp(section) ) {
          if ( line_nr > 0 )
            m["#SECTION_END"] = ({ line_nr-1, lines[line_nr-1] });
          else
            m["#SECTION_END"] = ({ 0, "" });
          return m;  // only read the specified section
        }
        else
          continue;  // ignore sections if no section was requested
      }
      string key, value;
      if ( sscanf( line, "%s=%s",key, value ) >= 2 ) {
        key = String.trim_all_whites( key );
        value = String.trim_all_whites( value );
        m[key] = ({ line_nr, string_to_value( value ) });
      }
    }
    
    if ( stringp(section) )
      m["#SECTION_END"] = ({ sizeof(lines)-1, "" });
    return m;
}


/**
 * Read and parse a plaintext config.
 * @param data a string containing the config data (Lines with "key=value" pairs)
 * @param section if specified, then only a certain section of the file is read
 *   and returned.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns a mapping containing the keys and values from the config string
 */
mapping get_config_text ( string data, void|string section )
{
  mapping m = find_config_text( data, section );
  if ( !mappingp(m) ) return m;
  mapping res = ([ ]);
  foreach ( indices(m), string key )
    res[key] = m[key][1];
  return res;
}


/**
 * Write a config as plaintext data into a string.
 * @param config a mapping containing the key:value pairs to be stored in the config string
 * @param section if specified, then the data is returned in a section syntax.
 *   and returned.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns data a string containing the config data (Lines with "key=value" pairs)
 */
string make_config_text ( mapping config, void|string section )
{
    if ( !mappingp(config) ) return 0;
    string s = "";

    if ( stringp(section) )
      s += "\n[" + section + "]\n";
    foreach ( indices(config), mixed key ) {
      string v = value_to_string( config[key] );
      if ( stringp(v) )
        s += key + "=" + v + "\n";
    }
    return s;
}


/**
 * Write a config as plaintext data into a string, using a template. The output
 * will look like the template with any values replaces by those of the config,
 * and with all additional values of the config appended at the end (of the
 * section, if a section was specified).
 * @param template the template to use for the output (should contain key=value
 * @param config a mapping containing the key:value pairs to be stored in the config string
 *   pairs for most of the keys)
 * @param section if specified, then the data is returned in a section syntax.
 *   and returned.
 *   Plaintext syntax: [my_section] (up to the next [...] line)
 * @returns data a string containing the config data (Lines with "key=value" pairs)
 */
string make_config_text_from_template ( string template, mapping config, void|string section )
{
    if ( !mappingp(config) || !stringp(template) ) return 0;
    array lines = template / "\n";
    mapping t = find_config_text( template, section );

    array keys_todo = indices(config);

    foreach ( indices(t), string key ) {
      int line_nr = t[key][0];
      mixed value = t[key][1];
      if ( line_nr < 0 || line_nr >= sizeof(lines) ) continue;
      // if key exists in the new config, use the new value,
      // otherwise comment out the line from the template:
      if ( ! zero_type(config[key]) ) {
        lines[line_nr] = key + "=" + value_to_string( config[key] );
        keys_todo -= ({ key });
      }
      else
        lines[line_nr] = "#" + lines[line_nr];
    }

    array extra_lines = ({ });
    if ( stringp(section) && (t["#SECTION_END"][0]+1)<sizeof(lines) ) {
      int section_break = t["#SECTION_END"][0] + 1;
      extra_lines = lines[ section_break..];
      lines = lines[..section_break];
    }

    foreach ( keys_todo, string key )
      lines += ({ key + "=" + value_to_string(config[key]) });

    lines += extra_lines;

    return lines * "\n";
}

static void join_mapping ( mapping a, mapping b ) {
  foreach ( indices(b), mixed key ) {
    if ( arrayp(a[key]) )
      a[key] += ( arrayp(b[key]) ? b[key] : ({ b[key] }) );
    else if ( mappingp(a[key]) )
      a[key] = ({ a[key], b[key] });
    else if ( !zero_type(a[key]) )
      a[key] = ({ a[key], b[key] });
    else
      a[key] = b[key];
  }
}

static mapping|string get_xml_value ( object node ) {
  if ( node->get_node_type() == Parser.XML.Tree.XML_TEXT )
    return node->get_text();

  if ( node->get_node_type() != Parser.XML.Tree.XML_ELEMENT )
    return ([ ]);

  string tag = node->get_tag_name();
  mapping m = ([ ]);

  array children = node->get_children();
  if ( objectp(children) ) children = ({ children });
  else if ( !arrayp(children) ) children = ({ });
  foreach ( children, object child ) {
    mixed res = get_xml_value( child );
    if ( stringp(res) ) {
      res = String.trim_all_whites( res );
      if ( sizeof(res) < 1 ) continue;
      res = string_to_value( res );
      if ( stringp(tag) && sizeof(tag)>0 ) return ([ tag : res ]);
      else return res;
    }
    if ( !mappingp(res) ) continue;
    if ( sizeof(res) < 1 ) continue;
    join_mapping( m, res );
  }

  if ( sizeof(m) > 0 && stringp(tag) && sizeof(tag)>0 )
    m = ([ tag : m ]);

  return m;
}


/**
 * Read and parse an xml config. Tags with values <key>value</key> will be
 * stored as strings in the resulting mapping ([ key : value ]).
 * Tags which contain further tags <tag><subtag>value</subtag></tag> will be
 * stored as mappings in the resulting mapping ([ tag : ([ subtag : value ]) ]).
 * Tags which appear several times <tag>value1</tag><tag>value2</tag> will be
 * stored as arrays in the resulting mapping ([ tag : ({ value1, value2 }) ]).
 *
 * @param data a string containing the config data
 * (Lines with "<key>value</key>" pairs, tags which contain further tags
 * are stored as mappings within the mapping, if a tag)
 * @param section if specified, then only a certain section of the file is read
 *   and returned.
 *   XML syntax: <my_section>...</my_section>.
 * @returns a mapping containing the keys and values from the config string
 */
//mapping get_config_xml ( string data, void|string section )
mixed get_config_xml ( string data, void|string section )
{
    if ( ! stringp(data) ) return 0;
    mapping m = ([ ]);

    object node = Parser.XML.Tree.parse_input( data );
    if ( !objectp(node) )
	return m;

    if ( stringp(section) )
        node = node->get_first_element( section );
    if ( !objectp(node) )
        return m;

    foreach(node->get_elements(), Parser.XML.Tree.Node n) {
        if ( !objectp(n) ) continue;
	mixed val = get_xml_value( n );
        if ( !mappingp(val) ) continue;
        join_mapping( m, val );
    }
    return m;
}


/**
 * Write a config into an XML string.
 * @param config a mapping containing the key:value pairs to be stored in the config string
 * @param section if specified, then the data is returned in a section syntax
 *   XML syntax: <my_section>...</my_section>.
 * @returns data a string containing the config data (Lines with "<key>value</key>" pairs)
 */
string make_config_xml ( mapping config, void|string section )
{
    if ( !mappingp(config) ) return 0;
    string s = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
    if ( stringp(section) )
      s += "\n<" + section + ">\n";
    foreach ( indices(config), string key ) {
	mixed value = config[key];
	if ( arrayp(value) ) {
	    foreach ( value, mixed subvalue ) {
		string v = value_to_string( subvalue );
		if ( stringp(v) ) s += "<"+key+">"+v+"</"+key+">\n";
	    }
	}
	else {
	    string v = value_to_string( value );
	    if ( stringp(v) ) s += "<"+key+">"+v+"</"+key+">\n";
	}
    }
    if ( stringp(section) )
      s += "</" + section + ">";

    return s;
}


/** Interpret a string or int as a boolean value (case-insensitive).
 * "yes", "true", "on", "1" and int values unequal zero are returned as true,
 * "no", "false", "off", "0" and int 0 or zero-type are returned as false.
 * If the value cannot be interpreted, the function returns UNDEFINED.
 * @param val the string to interpret
 * @returns true or false, depending on the value
 */
int bool_value ( string|int value )
{
  if ( intp(value) ) {
    if ( value ) return 1;
    else return 0;
  }
  if ( stringp(value) ) {
    string s = lower_case(value);
    switch ( s ) {
      case "yes" :
      case "true" :
      case "on" :
        return true;
      case "no" :
      case "false" :
      case "off" :
        return false;
      default :
        return UNDEFINED;
    }
  }
  return UNDEFINED;
}


/** Tries to interpret a string (or array) as an array by cutting the string at
 * delimiter characters (default: comma) and trimming the whitespaces
 * from the front and rear of the sub-strings.
 * If there is not delimiter character in the
 * string, then an array with a single element (the string) will be
 * returned. Any empty sub-strings will be removed from the array.
 * If the value already is an array, it is returned unmodified.
 * If the value cannot be interpreted, the function returns UNDEFINED.
 * @param val the string or array to interpret
 * @param delimiter the delimiter at which to cut the string
 * @returns an array of sub-strings
 */
array array_value ( string|array value, void|string delimiter ) {
  if ( arrayp(value) ) return value;
  if ( !stringp(value) ) return UNDEFINED;
  if ( !stringp(delimiter) ) delimiter = ",";
  array arr = value / delimiter;
  if ( zero_type(arr) ) return UNDEFINED;
  if ( !arrayp(arr) ) arr = ({ arr });
  for ( int i=0; i<sizeof(arr); i++ )
    arr[i] = String.trim_all_whites( arr[i] );
  while ( search( arr, "" ) >= 0 ) arr -= ({ "" });
  return arr;
}


/**
 * Try to convert a string into an int, a float or a string (in that order).
 * @param val the string to parse
 * @returns an int, float or string containing the value of the passed string
 */
string|int|float string_to_value( string val )
{
    if ( !stringp(val) ) return UNDEFINED;

    int d;
    float f;
    if ( sscanf(val, "%d", d) == 1 && (string)d == val )
	return d;
    else if ( sscanf(val, "%f", f) == 1 && (string)f == val )
	return f;
    return val;
}


/**
 * Convert an int, float or string value to a string.
 * @param val the value to return as a string
 * @returns a string representing the value of the passed value
 */
string value_to_string ( mixed val )
{
    if ( stringp(val) ) return val;
    else if ( intp(val) ) return sprintf("%d",val);
    else if ( floatp(val) ) return sprintf("%f",val);
    else return "";
}
