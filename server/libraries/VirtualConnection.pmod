
class connection {

static string _connection_name;
static object _user;
static string _ip;
static int _client_features;

/**
 * Creates a virtual connection to a user. The connection is not
 * automatically connected to the user, it can be connected via the
 * connect() function and disconnected via the disconnect() function.
 *
 * @see connect
 * @see disconnect
 *
 * @param connection_name a name for the type of virtual connection
 * @param user the user object to which this virtual connection can be
 *   connected
 * @param client_features the client features of this virtual connection
 *   (see client.h)
 * @param ip (optional) the ip address of the virtual connection ("0.0.0.0"
 *   will be used if not specified)
 */
void create ( string connection_name, object user, int client_features,
	      void|string ip ) {
  _connection_name = connection_name;
  _user = user;
  if ( stringp(ip) ) _ip = ip;
  else _ip = "0.0.0.0";
  _client_features = client_features;
}

void connect () {
  _user->connect_virtual( this_object() );
}

void disconnect () {
  _user->disconnect_virtual( this_object() );
}

string get_client_class () {
  return "virtual";
}

int get_client_features () {
  return _client_features;
}

string get_ip () {
  return _ip;
}

string describe () {
  string user_name = "";
  if ( objectp(_user) ) user_name = _user->get_identifier();
  return "VirtualConnection(" + user_name + "," + _ip + ")";
}

}
