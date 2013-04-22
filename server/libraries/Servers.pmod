class Server {
    static string certificate;
    static string        name;
    static string    hostname;
    static string          ip;

    array(object) aoSockets = ({ });
    
    void create(string server_name, string host, string _certificate) {
	name = server_name;
	hostname = host;
	certificate = _certificate;
    }

    // check whether the submitted and remembered certificate are the same
    int check(string _certificate) {
	return 1;
    }
    string get_hostname() { return hostname; }
    string get_name() { return name; }
    int verify(string cert) { return certificate == cert; }
    int get_id() { return 1; }

    int connect(object socket) {
      aoSockets += ({ socket });
    }
    int disconnect(object socket) {
      aoSockets -= ({ socket });
    }
    array(object) get_sockets() {
      return aoSockets;
    }

    string describe() { return "Server("+name+","+hostname+")"; }

    void load(mapping data) {
      name = data->name;
      hostname = data->hostname;
      ip = data->ip;
      certificate = data->certificate;
    }

    mapping save() {
      return ([ 
	"name": name,
	"hostname": hostname,
	"ip": ip,
	"certificate": certificate,
      ]);
    }
}

class ServerList {
    mapping   connections; // COAL connections
    array(object) servers;

    void create() {
	connections = ([ ]);
	servers = ({ });
    }

    array list() {
      return servers;
    }
  
    array list_servers() {
      return map(servers, 
		 lambda (Server s) { 
		   mapping res =  s->save(); 
		   res->connected=arrayp(connections[s]);
		   return res;
		 } 
	       );
    }

    void add(Server s) {
	if ( !arrayp(connections[s]) )
	    connections[s] = ({ });
	servers += ({ s });
    }
    Server get(string name) {
      foreach(servers, object s)
	if ( s->get_name() == name )
	  return s;
      return 0;
    }

    array(object) get_connections(Server s) {
      return connections[s];
    }
    void set_connection(Server s, object conn) {
      connections[s] += ({ conn });
    }
    string describe() {
	return "ServerList("+sizeof(servers) + " entries)";
    }

    void load(mapping data) {
      servers = ({ });
      if ( arrayp(data->servers) ) {
	foreach(data->servers, mapping server) {
	  Server s = Server(server->name, 
			    server->hostname, 
			    server->certificate);
	  servers += ({ s });
	}
      }
    }
  
    mapping save_server(Server s) {
      return s->save();
    }

    mapping save() {
      return ([ "servers": map(servers, save_server), ]);
    }
}


class ServerConnection {
}

// this represents a simple non-persistence steam-object
class SimpleObject {
  mapping attributes;
  string content;

  // query operations
  mixed query_attribute(string key) {
    return attributes[key];
  }
  
  mixed set_attribute(string key, string value) {
    // this is a distant action
    attributes[key] = value;
  }
  
}
