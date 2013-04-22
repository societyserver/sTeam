#include <coal.h>
#include <configure.h>


//#define SERVICE_DEBUG

#ifdef SERVICE_DEBUG
#define DEBUG_SERVICE(s, args...) werror(s+"\n", args)
#else
#define DEBUG_SERVICE(s, args...)
#endif


class Client {
    inherit "client_base";
    
    static Service myService;

    void create(object service) {
      myService = service;
    }
  
  static void handle_command(string func, mixed args) {
    DEBUG_SERVICE( "handle_command: %s, %O\n", func, args );
    if ( func == "notify" )
      myService->notify(args);
    else
      myService->call_service(args->user, args->params, args->id);
  }
}


class Service {
  string           name;
  mapping     serverCfg;
  mapping    serviceCfg;
  object     connection;
  object serviceManager;
  object         myUser;
  static private string login;
  static private string password;
  static private int eid;
  
  string get_server_name()
  {
    string domain=query_config("domain");
    if(stringp(domain) && sizeof(domain))
      return query_config("machine") + "." + domain;
    else
      return query_config("machine");
    
  }

  mixed query_config(string cfg) { return serverCfg[cfg]; }

  void notify ( mapping event ) {
  }

  void create () {
    connection = Client(this_object());
  }

  mixed send_cmd(object obj, string func, mixed args, int|void nowait) {
    return connection->send_cmd(obj, func, args, nowait);
  }
  
  static void run() {
  }

  static void check_connection () {
      int commit_suicide = 0;
      mixed err = catch {
	if ( connection->query_address() == 0 )
          commit_suicide = 1;
      };
      if ( err != 0 || commit_suicide != 0 ) {
	werror( "[%s] Service::check_connection() lost connection. Exiting.\n",
                timelib.log_time() );
	exit( 1 );
      }
      call_out( check_connection, 5 );
  }
  
  void call_service(object user, mixed args, int|void id) {
    myUser = user;
    DEBUG_SERVICE("service called !\n");
  }
  
  void callback_service(object user, object obj, int id, mixed res) {
    send_cmd(serviceManager, "handle_service", ({ user, obj, id, res }), 1);
  }

  void async_result(int id, mixed res) {
    DEBUG_SERVICE("async_result is " + strlen(res) + " bytes ...\n");
    serviceManager->async_result(id, res);
  }
  
  
  /**
   * Initialize the service.
   * @param args command line arguments (this array will be modified, the service
   *   will remove any arguments it recognizes; the first entry is ignored, since
   *   it is usually the program name)
   */
  final static void init ( string service_name, array(string) argv ) {
    name = service_name;

    mapping env = getenv();
    if ( !mappingp(env) ) env = ([ ]);
    if ( stringp(env["STEAM_SERVICE_USER"]) )
      login = env["STEAM_SERVICE_USER"];
    else login = "service";
    if ( stringp(env["STEAM_SERVICE_PASSWORD"]) )
      password = env["STEAM_SERVICE_PASSWORD"];
    else password = "";

    string server_config_file = Getopt.find_option( argv, "c", "server-config",
        UNDEFINED, CONFIG_DIR + "/steam.cfg" );
    serverCfg = Config.read_config_file( server_config_file );
    if ( !mappingp(serverCfg) )
      serverCfg = ([ ]);

    string service_config_file = Getopt.find_option( argv, "f", "service-config",
        UNDEFINED, CONFIG_DIR + "/services/" + name + ".cfg" );
    serviceCfg = Config.read_config_file( service_config_file );

    login = Getopt.find_option( argv, "u", "user", UNDEFINED, "service" );
    password = Getopt.find_option( argv, "p", "password", UNDEFINED, password );

    mixed server = Getopt.find_option( argv, "h", ({ "host", "server" }),
        UNDEFINED, 1 );
    if ( stringp(server) ) serverCfg["ip"] = server;
    if ( !stringp(serverCfg["ip"]) ) serverCfg["ip"] = "localhost";

    string port_str = Getopt.find_option( argv, "p", "port", UNDEFINED, "" );
    int port;
    if ( sscanf( port_str, "%d", port ) >= 1 ) serverCfg["port"] = port;

    string eid_str = Getopt.find_option( argv, "e", "eid", UNDEFINED, "" );
    int tmp_eid;
    if ( sscanf( eid_str, "%d", tmp_eid ) >= 1 ) eid = tmp_eid;
  }

  /**
   * Starts the service.
   */
  final static void start () {
    string host = serverCfg->ip;
    if ( !stringp(host) || sizeof(host)==0 ) host = "localhost";
    int port = (int)serverCfg->port;
    if ( !intp(port) ) port = 1900;

    werror( "[%s] Connecting to %s:%d ...\n", timelib.log_time(), host, port );
    int tries = 0;
    while ( !connection->connect_server(host, port) && tries < 20 ) {
	sleep(10);
	tries++;
	if ( tries > 10 && host == "localhost" ) {
	  host = "127.0.0.1";
	  werror("[%s] Trying 127.0.0.1 instead....\n", timelib.log_time() );
	}
    }
    if ( tries >= 100 ) {
        werror( "[%s] Failed to connect to server !\n", timelib.log_time() );
	error("Failed to build connection to server.");
    }
    
    werror( "[%s] Registering service \"%s\"...\n", timelib.log_time(), name );
    DEBUG_SERVICE("User = "+login+", Ticket/Password = "+password+"\n");
    // register service
    if ( !connection->login( login, password, 0 ) ) {
      error("Service: Fatal error while connecting to server, "+
	    "ticket/password rejected !");
      
    }
    
    connection->set_object(0);
    serviceManager =connection->send_cmd(0, "get_module", "ServiceManager");
    connection->set_object(serviceManager);
    
    connection->send_command(COAL_REG_SERVICE, ({ name, eid }));
    werror( "[%s] Service \""+name+"\" registered and running.\n", timelib.log_time() );
    
    call_out( check_connection, 5 );

    // run service - events call notify function
    run();
  }
}


object get_module (string str) {
  return this_object();
}
