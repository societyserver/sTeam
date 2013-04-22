#define READ_INPUT_METHOD_GETS 1
#define READ_INPUT_METHOD_READLINE 0

static private int read_input_method = READ_INPUT_METHOD_GETS;
static private Stdio.Readline readln;

void set_input_method_gets () {
  read_input_method = READ_INPUT_METHOD_GETS;
}

void set_input_method_readln () {
  read_input_method = READ_INPUT_METHOD_READLINE;
  if ( !objectp(readln) ) readln = Stdio.Readline(Stdio.stdin);
}


/**
 * Reads user input from stdin. The user is polled for input until it matches
 * certain requirements (same type as default value, and, if specified,
 * equality with one of the valid input values).
 * 
 * @see read_password
 *
 * @param desc description that is written to the user
 * @param def_value default value (type also sets the return type, int or
 *   string)
 * @param valid_inputs an (optional) array of allowed values, only input that
 *   matches one of these values will be accepted
 * @return the user input, same type as the default_value
 * @author Thomas Bopp (astra@upb.de) 
 */
mixed read_input ( string desc, mixed default_value, void|mixed ... valid_inputs ) {
    string                               str;
    mixed                              value;
    int                               ok = 0;

    while ( !ok ) {
      if ( read_input_method == READ_INPUT_METHOD_GETS ) {
	write(desc+" ["+default_value+"]: ");
	str = Stdio.stdin.gets();
      }
      else {
	str = readln->read(desc + " ["+default_value+"]: ");
      }

      if ( !stringp(str) || strlen(str) == 0 ) {
	value = default_value;
	ok = 1; 
      }
      else {
	if ( sscanf(str, "%d", value) != 1 || str != (string)value )
	  value = str;
	
	if ( stringp(default_value) && stringp(value) )
	  ok = 1;
	else if ( intp(default_value) && intp(value) )
	  ok = 1;
	if ( arrayp(valid_inputs) && sizeof(valid_inputs) > 0 && 
	     search(valid_inputs, value) < 0 )
	  ok = 0;
      }
    }
    return value;
}


/**
 * Reads a password from standard input. Works exactly like read_input()
 * but doesn't show the characters the user types (masks them with '*').
 *
 * @see read_input
 * 
 * @param desc description that is written to the user
 * @param def_value default value (type also sets the return type, int or
 *   string)
 * @param valid_inputs an (optional) array of allowed values, only input that
 *   matches one of these values will be accepted
 * @return the user input, same type as the default_value
 */
mixed read_password ( string desc, mixed default_value, void|mixed ... valid_inputs ) {
  mixed old_method = read_input_method;
  set_input_method_readln();
  readln->set_echo( 0 );
  mixed result = read_input( desc, default_value, @valid_inputs );
  readln->set_echo( 1 );
  if ( old_method == READ_INPUT_METHOD_GETS )
    set_input_method_gets();
  return result;
}
