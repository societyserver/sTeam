/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: server.pike,v 1.10 2010/01/27 12:05:35 astra Exp $
 */


/*!\mainpage sTeam Function Documentation
 *
 * \section Server Developers
 * - Ludger Merkens
 * - Thomas Bopp
 * - Christian Schmidt
 * - Martin Baehr
 * - Robert Hinn
 * 
 * Consult the Server documentation for more information.
 */

//! server is the most central part of sTeam, loads and handles factories
//! and modules. Global Events are also triggered through the server and
//! can be subcribed by modules.

private static object                   nmaster;
private static int                  iLastReboot;
private static object                 oDatabase;
private static object              _Persistence; // the persistence manager
private static object               oBacktraces;
private static mapping       mGlobalBlockEvents;
private static mapping      mGlobalNotifyEvents;
private static mapping                 mConfigs;
private static mapping         mConfigsFromFile;
private static mapping                 mClasses;
private static mapping                 mModules;
private static mapping                  mErrors;
private static string                     sTest;
private static array            aEmailAddresses;
private static mapping            mPortPrograms; // mapping of port programs
private static object          _stderr, _stdout;

private static mapping userConfigs = ([ "database": 1, "ip": 1, ]);

private static string sandbox_path = "/";


#include <config.h>
#include <macros.h>
#include <classes.h>
#include <database.h>
#include <attributes.h>
#include <assert.h>
#include <access.h>
#include <roles.h>
#include <events.h>
#include <functions.h>
#include <configure.h>

#define CONFIG_FILE "steam.cfg"

#define MODULE_SECURITY mModules["security"]
#define MODULE_FILEPATH mModules["filepath:tree"]
#define MODULE_GROUPS   mModules["groups"]
#define MODULE_USERS    mModules["users"]
#define MODULE_OBJECTS  mModules["objects"]

string get_identifier() { return "Server Object"; }
string describe() { return "Server Object"; }
string _sprintf() { return "Server Object"; }

string get_config_dir () {
  string dir = mConfigs["config-dir"];
  if ( !stringp(dir) ) dir = CONFIG_DIR;
  return dir;
}

string get_sandbox_path () {
  return sandbox_path;
}

private static void update_config_file ()
{
  string data;
  mapping config = ([ ]);
  array obsolete_files = ({ });
  // from old pre 1.6 XML config file:
  catch {
    data = Stdio.read_file( get_config_dir() + "/config.txt" );
    if ( stringp(data) ) {
      config |= Config.get_config( data, "config" );
      MESSAGE( "Found obsolete config file: " + get_config_dir() + "/config.txt" );
      obsolete_files += ({ get_config_dir() + "/config.txt" });
    }
  };
  // from 1.6 - 2.0 text config file:
  catch {
    data = Stdio.read_file( get_config_dir() + "/steam.cnf" );
    if ( stringp(data) ) {
      config |= Config.get_config( data );
      MESSAGE( "Found obsolete config file: " + get_config_dir() + "/steam.cnf" );
      obsolete_files += ({ get_config_dir() + "/steam.cnf" });
    }
  };
  catch {
    if ( Stdio.exist( CONFIG_DIR + "/config.tmp" ) ) {
      MESSAGE( "Found obsolete config file template: "
               + get_config_dir() + "/config.tmp" );
      obsolete_files += ({ get_config_dir() + "/config.tmp" });
    }
  };
  catch {
    if ( Stdio.exist( get_config_dir() + "/config.template" ) ) {
      MESSAGE( "Found obsolete config file template: "
               + get_config_dir() + "/config.template" );
      obsolete_files += ({ get_config_dir() + "/config.template" });
    }
  };

  // remove any hbs() wrappers:
  foreach ( indices(config), string key ) {
    if ( !stringp(config[key]) ) continue;
    string v;
    if ( sscanf( config[key], "hbs(%s)", v ) > 0 ) {
      config[key] = Config.string_to_value(v);
    }
  }

  // write to new config file:
  if ( sizeof(config) > 0 ) {
    data = Stdio.read_file( get_config_dir() + "/" + CONFIG_FILE );
    mixed err = catch {
      Stdio.write_file( get_config_dir() + "/" + CONFIG_FILE,
                        Config.make_config_text_from_template( data, config ) );
    };
    if ( err != 0 ) {
      werror( "Could not write config file (updated from old configs): "
              + get_config_dir() + "/" + CONFIG_FILE + "\n" );
      return;
    }
    // rename obsolete files:
    foreach ( obsolete_files, string filename ) {
      mixed err2 = catch {
        if ( mv( filename, filename + ".old" ) )
        MESSAGE( "Renamed obsolete file " + filename + " to " + filename + ".old" );
      };
      if ( err2 != 0 ) {
        werror( "Could not rename obsolete file " + filename + " to " + filename + ".old\n" );
      }
    }
  }
}


/**
 * read configurations from server config file
 */
private static void read_config_from_file ()
{
  string data = Stdio.read_file( get_config_dir() + "/" + CONFIG_FILE );
  if ( !stringp(data) )
    error("Missing config file. Check for "+get_config_dir()+"/"+CONFIG_FILE+"\n"+
	  "You can either repeat installation or call ./setup manually !");
  
  m_delete(mConfigs, "database");
  
  mConfigsFromFile = Config.get_config( data );
  foreach ( indices(mConfigsFromFile), string key ) {
    if ( stringp(mConfigsFromFile[key]) ) {
      string v;
      if ( sscanf( mConfigsFromFile[key], "hbs(%s)", v ) > 0 )
        //mConfigsFromFile[key] = Config.string_to_value(v);
        mConfigsFromFile[key] = v;
    }
    mixed v = mConfigsFromFile[key];
    if ( stringp(v) ) v = Config.string_to_value( v );
    mConfigs[key] = mConfigsFromFile[key];
  }
}


/**
 * load configurations from config folder (attribute 'configs')
 */
private static void read_config_from_config_folder ()
{
  mapping confs = get_internal_config( this_object() );
  
  if ( ! mappingp(confs) ) {
    object admin = GROUP("admin");
    if ( objectp(admin) )
      confs = admin->query_attribute("configs");
    if ( mappingp(confs) )
      FATAL("Using server config from admin group!");
    else {
      FATAL("Could not get server config from admin group! No config!");
      confs = ([ ]);
    }
  }

  // configs from config file cannot be overwritten:
  confs |= mConfigsFromFile;
  
  // some default configurations to keep compatibility:
  if ( !confs->web_port_http )
    confs->web_port_http = confs->http_port;
  if ( !confs->web_port_ftp )
    confs->web_port_ftp = confs->ftp_port;
  if ( !confs->web_port )
    confs->web_port = confs->http_port;
  
  string name, domain, fullname;
  string hname = gethostname();
  if ( sscanf(hname, "%s.%s", name, domain) != 2 )
    name = hname;
  if ( !stringp(name) || sizeof(name) < 1 )
    name = "localhost";

  // check whether machine, domain or web_server must be autodetected:
  bool autodetect_machine = false;
  if ( !confs->machine || sizeof(confs->machine) < 1 ||
       confs->machine == "<autodetect>" || 
       confs->machine == "(autodetect)" )
    autodetect_machine = true;
  bool autodetect_domain = false;
  if ( !confs->domain || (sizeof(confs->domain) < 1 && autodetect_machine) ||
       confs->domain == "<autodetect>" ||
       confs->domain == "(autodetect)" )
    autodetect_domain = true;
  bool autodetect_webserver = false;
  if ( !confs->web_server || sizeof(confs->web_server) < 1 ||
       confs->web_server == "<autodetect>" ||
       confs->web_server == "(autodetect)" ||
       confs->web_server == "<autodetect-ip>" ||
       confs->web_server == "(autodetect-ip)" )
    autodetect_webserver = true;

  // autodetect domain and machine if necessary:
  if ( autodetect_domain ) {
    confs->domain = domain;
    mConfigs["domain"] = domain;
    MESSAGE( "Autodetected domain: %O", domain );
  }
  if ( autodetect_machine ) {
    confs->machine = name;
    mConfigs["machine"] = name;
    MESSAGE( "Autodetected machine: %O", name );
  }

  // determine fully qualified hostname:
  if ( stringp(confs->domain) && sizeof(confs->domain) > 0 )
    fullname = confs->machine + "." + confs->domain;
  else
    fullname = confs->machine;

  // autodetect web_server if necessary:
  if ( autodetect_webserver ) {
    if ( confs->web_server == "<autodetect-ip>" ||
         confs->web_server == "(autodetect-ip)" ) {
      mixed web_server_ip;
      if ( catch( web_server_ip =
         Protocols.DNS.client()->gethostbyname(System.gethostname())[1][0] ) )
        confs->web_server = fullname;
      else if ( stringp(web_server_ip) && sizeof(web_server_ip)>0 )
        confs->web_server = web_server_ip;
      else
        confs->web_server = fullname;
    }
    else
      confs->web_server = fullname;
    mConfigs["web_server"] = confs->web_server;
    MESSAGE( "Autodetected web_server: %s", confs->web_server );
  }
  
  if ( !confs->web_mount )
    confs->web_mount = "/";
  
  mConfigs = confs | mConfigs;
  write_config_to_admin();
}


private static void write_config_to_admin()
{
  object groups = mModules["groups"];
  if ( ! set_internal_config( this_object(), mConfigs ) ) {
    if ( objectp(groups) ) {
      object admin = groups->lookup("admin");
      if ( objectp(admin) )
	admin->set_attribute("configs", mConfigs);
    }
  }
}

/**
 * Save the modules (additional ones perhaps).
 *  
 */
private static void save_modules()
{
    object groups = mModules["groups"];
    if ( objectp(groups) ) {
	object admin = groups->lookup("admin");
	if ( objectp(admin) ) {
	    admin->set_attribute("modules", mModules);
	}
    }
}

int verify_crypt_md5(string password, string hash)
{
#if constant(Crypto.verify_crypt_md5)
  return Crypto.verify_crypt_md5(password, hash);
#else
  return Crypto.crypt_md5(password, hash) == hash;
#endif
}

string sha_hash(string pw)
{
#if constant(Crypto.SHA1)
    return Crypto.SHA1->hash(pw);
#else
    return Crypto.sha()->update(pw)->digest();
#endif
}

static string prepare_sandbox()
{
  string sandbox = mConfigs->sandbox;
  if ( !stringp(sandbox) )
    sandbox = getcwd()+"/tmp";
  if ( sandbox[-1] == '/' )
    sandbox = sandbox[0..strlen(sandbox)-2];
  Stdio.mkdirhier(sandbox);
  foreach ( get_dir(sandbox), string dir_entry ) {
    if ( dir_entry == "content" ) continue;
    Stdio.recursive_rm( sandbox + "/" + dir_entry );
  }
  string config_dir = get_config_dir();
  if ( config_dir[-1] == '/' )
    config_dir = config_dir[0..strlen(config_dir)-2];
  MESSAGE("Preparing Sandbox in %s (could take a while)", sandbox);
  Process.create_process( ({ "bin/jail", getcwd()+"/server", sandbox, config_dir, get_config("system_user")||"nobody" }),
				 ([ "env": getenv(),
				    "cwd": getcwd(),
				    "stdout": Stdio.stdout,
				    "stderr": Stdio.stderr,
				 ]))->wait();

  mixed pconfig = Config.read_config_file( config_dir+"/persistence.cfg",
                                           "persistence" );
  if ( !mappingp(pconfig) ) pconfig = ([ ]);
  if ( arrayp(pconfig["layer"]) ) {
    foreach ( pconfig["layer"], mixed layer ) {
      if ( !mappingp(layer) || !mappingp(layer["mirror"]) ) continue;
      mixed layer_name = layer["name"];
      if ( !stringp(layer_name) || sizeof(layer_name) < 1 ) continue;
      if ( mappingp(layer["mirror"]["content"]) &&
           stringp(layer["mirror"]["content"]["path"]) &&
           sizeof(layer["mirror"]["content"]["path"]) > 0 ) {
        string mirror_path = layer["mirror"]["content"]["path"];
        catch( mkdir( sandbox + "/mirror" ) );
        catch( mkdir( sandbox + "/mirror/" + layer_name ) );
        mixed err = catch( System.symlink( mirror_path, sandbox + "/mirror/"
                                           + layer_name + "/content" ) );
        if ( err )
          FATAL("Failed to link content mirror for persistence layer %s :\n%O",
                layer_name, err[0]);
      }
      break;
    }
  }
  
  return sandbox;
}

static int start_server()
{
  string sandbox = 0;
  float boottime = gauge {
    
    mGlobalBlockEvents  = ([ ]);
    mGlobalNotifyEvents = ([ ]);
    mClasses            = ([ ]);
    mModules            = ([ ]);
    
    int tt = f_get_time_millis();
    iLastReboot = time();
    MESSAGE("Server startup on " + (ctime(time())-"\n") + " (PID="+getpid()+")");
    
    update_config_file();
    read_config_from_file();
    sandbox = prepare_sandbox();
    sandbox_path = sandbox;

    catch( rm( sandbox_path + "/server.restart" ) );
    
    nmaster = ((program)"kernel/master.pike")();
    replace_master(nmaster);
    
    // default path
    nmaster->mount("/usr", "/usr");
    nmaster->mount("/sw", "/sw");
    nmaster->mount("/opt", "/opt");
    nmaster->mount("/var", "/var");
    
    nmaster->mount("/", sandbox);
    nmaster->mount("/classes", sandbox+"/classes");
    nmaster->mount("/net", sandbox+"/net");
    nmaster->mount("/modules", sandbox+"/modules");
    nmaster->mount("/libraries", sandbox+"/libraries");
    nmaster->mount("/net/base", sandbox+"/net/base");
    
    
    nmaster->add_module_path("/libraries");
    nmaster->add_module_path(sandbox+"/libraries");
    nmaster->add_include_path("/include");
	
    add_constant("_Server", this_object());
    add_constant("query_config", query_config);
    add_constant("vartype", nmaster->get_type);
    add_constant("new", nmaster->new);
    add_constant("this_user", nmaster->this_user);
    add_constant("this_socket", nmaster->this_socket);
    add_constant("geteuid", nmaster->geteuid);
    add_constant("seteuid", nmaster->seteuid);
    add_constant("get_type", nmaster->get_type);
    add_constant("get_functions", nmaster->get_functions);
    add_constant("get_dir", nmaster->get_dir);
    add_constant("rm", nmaster->rm);
    add_constant("file_stat", nmaster->file_stat);
    add_constant("get_local_functions", nmaster->get_local_functions);
    add_constant("_exit", shutdown);
    add_constant("call", nmaster->f_call_out);
    add_constant("call_out_info", nmaster->f_call_out_info);
    add_constant("get_time_millis", f_get_time_millis);
    add_constant("get_time_micros", f_get_time_micros);
    add_constant("check_equal", f_check_equal);
    add_constant("start_thread", nmaster->start_thread);
    add_constant("call_mod", call_module);
    add_constant("get_module", get_module);
    add_constant("get_factory", get_factory);
    add_constant("steam_error", steam_error);
    add_constant("steam_user_error", steam_user_error);
    add_constant("describe_backtrace", nmaster->describe_backtrace);
    add_constant("set_this_user", nmaster->set_this_user);
    add_constant("run_process", Process.create_process);
    
    // crypto changes in 7.6
    add_constant("verify_crypt_md5", verify_crypt_md5);
#if constant(Crypto.make_crypt_md5)
    add_constant("make_crypt_md5", Crypto.make_crypt_md5);
#else
    add_constant("make_crypt_md5", Crypto.crypt_md5);
#endif
    add_constant("sha_hash", sha_hash);
    
    MESSAGE("Loading Persistence...");
    
    _Persistence = ((program)"/Persistence.pike")();
    add_constant("_Persistence", _Persistence);
    _Persistence->init();
    
#if __REAL_VERSION__ >= 7.4
    oDatabase = ((program)"/database.pike")();
#else
    oDatabase = new("/database.pike");
#endif
    add_constant("_Database", oDatabase);
    nmaster->register_constants();  // needed for database/persistence registration
    oDatabase->init();
    MESSAGE("Database is "+ master()->describe_object(oDatabase));
    
    add_constant("find_object", _Persistence->find_object);
    add_constant("serialize", oDatabase->serialize);
    add_constant("unserialize", oDatabase->unserialize);
    
    nmaster->register_server(this_object());
    nmaster->register_constants();
    
    mixed err = catch {
      oDatabase->enable_modules();
    };
    if ( err != 0 ) {
      werror("%O\n%O\n", err[0], err[1]);
      error("Boot failed: Unable to access database !\n"+
            "1) Is the database running ?\n"+
            "2) Check if database string is set correctly \n    ("+
            mConfigs->database+")\n"+
            "3) The database might not exist - you need to create it.\n"+
            "4) The user might not have access for this database.\n"+
            "5) The Pike version you are using does not support MySQL\n"+
            "     Try pike --features to check this.\n");
    }
    

    MESSAGE("Database module support enabled.");
    MESSAGE("Database ready in %d ms, now booting kernel ....",
	    f_get_time_millis() - tt);

    load_modules();
    load_factories();
    load_modules_db();
    
    if ( err = catch(load_objects()) ) {
      FATAL(err[0]+"\n"+
            "Unable to load basic objects of sTeam.\n"+
            "This could mean something is wrong with the database:\n"+
            "If this is a new installation, you have to drop the database and restart.\n");
      FATAL("-----------------------------------------\n"+PRINT_BT(err));
      exit(1);
      
    }
    load_programs();
    load_pmods("/libraries/");
    install_modules();
    _Persistence->post_init();
    
    MESSAGE("Initializing objects... " + (time()-iLastReboot) + " seconds");
    iLastReboot = time();
    MESSAGE("Setting defaults... " + (time()-iLastReboot) + " seconds");
    
    check_root();
    check_config_folder();
    read_config_from_config_folder();

    open_ports();
    iLastReboot = time();
    thread_create(abs);
    // check if root-room is ok...
    ASSERTINFO(objectp(_Persistence->lookup("rootroom")), 
               "Root-Room is null!!!");
  };
    
  MESSAGE("Server started on " + (ctime(time())-"\n") + " (startup took "+boottime+" seconds)");
  start_services();

  if ( check_updates_all() == 1 ) {
    MESSAGE( "Updates require a restart, restarting server.\n");
    oDatabase->wait_for_db_lock();
    return 0;
  }

  string user = get_config( "system_user" );
  nmaster->run_sandbox( sandbox, user );
  sandbox_path = "/";

  if ( stringp(sTest) )
    test();
  return -17;
}

/**
 * Returns the config data stored for some object (server, modules)
 * within the server (not the config file). This is usually for settings
 * that are done via the web-interface.
 * @param obj object for which to fetch the config (e.g. _Server)
 * @return a mapping with configs, or UNDEFINED if no configs were stored
 *   for that object or an error occured.
 */
mapping get_internal_config ( object obj ) {
  object config_folder = get_module("filepath:tree")->path_to_object(
      "/config" );
  if ( ! objectp(config_folder) ) return UNDEFINED;
  object config_obj = config_folder->get_object_byname( obj->get_identifier() );
  if ( ! objectp(config_obj) ) return UNDEFINED;
  return config_obj->query_attribute("config");
}

/**
 * Sets a config mapping for some object (server, modules) within the server
 * (not the config file). This is usually for settings that are done via the
 * web-interface.
 * @param obj object for which to set the config (e.g. _Server)
 * @param config a mapping with config data
 * @return true on success, false if the mapping could not be set
 */
bool set_internal_config ( object obj, mapping config ) {
  object config_folder = get_module("filepath:tree")->path_to_object(
      "/config" );
  if ( ! objectp(config_folder) ) return UNDEFINED;
  object config_obj = config_folder->get_object_byname( obj->get_identifier() );
  if ( ! objectp(config_obj) ) {
    object factory = get_factory( CLASS_OBJECT );
    if ( ! objectp(factory) ) return false;
    config_obj = factory->execute( ([ "name":obj->get_identifier() ]) );
    config_obj->move( config_folder );
  }
  if ( ! objectp(config_obj) ) return UNDEFINED;

  config_obj->set_attribute( "config", config );
  return true;
}

/**
 * Returns an array of all available update objects.
 * @return an array of all updates
 */
array get_updates ()
{
  object updates_folder = get_module("filepath:tree")->path_to_object(
      "/config/updates" );
  if ( ! objectp(updates_folder) ) return UNDEFINED;
  return updates_folder->get_inventory();
}

/**
 * Returns an update object (e.g. log file) by name.
 * @param name identifier (filename) of update to look for
 * @return the update object, or UNDEFINED if such an update could not be found
 */
object get_update ( string name )
{
  object updates_folder = get_module("filepath:tree")->path_to_object(
      "/config/updates" );
  if ( ! objectp(updates_folder) ) return UNDEFINED;
  return updates_folder->get_object_byname( name );
}

/**
 * Adds an update to the server. Call this after an update has been
 * performed to remember that the update has already been applied.
 * @param update an object that represents the update (e.g. a log file
 *   of the update process). Note: the object identifier (filename)
 *   will be used to check whether an update has already been applied
 * @return true when the update object has been successfully added
 */
bool add_update ( object update )
{
  object updates_folder = get_module("filepath:tree")->path_to_object(
      "/config/updates" );
  if ( ! objectp(updates_folder) ) return false;
  return update->move( updates_folder );
}

/**
 * Checks updates in all modules
 * If a function returns > 0, then server will restart
 */
static int check_updates_all ()
{
  MESSAGE("Checking updates ....");
  int ret = 0;
  // check server for updates:
  ret |= check_updates();
  // check databbase for updates:
  if ( functionp( oDatabase->check_updates ) )
    ret |= oDatabase->check_updates();

  // check persistence for updates:
  if ( functionp( _Persistence->check_updates ) )
    ret |= _Persistence->check_updates();
  // check modules for updates:
  foreach ( values(get_modules()), object module  ) {
    if ( !objectp(module) )
      continue;
    if ( functionp( module->check_updates ) )
      ret |= module->check_updates();
  }
  return ret;
}

/**
 * Check for updates and perform updates if necessary.
 * Return 1 if any performed updates require a server restart.
 * Use get_updates() or get_update(name) to check for updates that
 * have already been performed. Use add_update(obj) to remember that
 * an update has been performed (e.g. use a log file of the update).
 * @return 1 if the updates need a server restart, 0 otherwise
 */
int check_updates ()
{
  return 0;
}

static void check_root() {
  MESSAGE("Testing root user ...");
  object root = USER("root");
  int repair = 0;

  foreach ( root->get_groups(), object grp) {
    if ( !objectp(grp) )
      MESSAGE("root user: NULL group detected !");
    /*
    else {
      MESSAGE("GROUP %s", grp->get_identifier());
    }
    */
  }
  if ( ! GROUP("admin")->is_member(root) ) {
    MESSAGE("root user is missing in admin group !");
    repair = 1;
  }
  //else MESSAGE("Root is member of ADMIN !");

  if ( search(root->get_groups(), GROUP("admin")) == -1 )
      repair = 1;

  if ( ! GROUP("steam")->is_member(root) ) {
    MESSAGE("root user is missing in sTeam group !");
    repair = 1;
  }
  //else MESSAGE("Root is member of sTeam !");

  if ( !stringp(root->get_user_name()) ) {
    MESSAGE("root user has NULL username!");
    repair = 1;
  }
  if ( repair )
    repair_root_user();
}

static void repair_root_user() {
    GROUP("admin")->remove_member(USER("root"));
    GROUP("admin")->add_member(USER("root"));
    GROUP("steam")->remove_member(USER("root"));
    GROUP("steam")->add_member(USER("root"));
    FATAL("Status for user root is " + USER("root")->status());
    catch {
      USER("root")->set_user_name("root");
      USER("root")->set_user_password("steam");
    };

    USER("root")->set_attribute(USER_LANGUAGE, "english");
    USER("root")->set_attribute(USER_FIRSTNAME, "Root");
    USER("root")->set_attribute(USER_LASTNAME, "User");
    USER("root")->set_attribute(OBJ_DESC, "The root user is the first administrator");
    USER("root")->set_attribute("xsl:content", ([ GROUP("steam") : get_module("filepath:tree")->path_to_object("/stylesheets/user_details.xsl"), ]) );
    USER("root")->set_attribute(OBJ_ICON, get_module("filepath:tree")->path_to_object("/images/user_unknown.jpg") );
    object wr = USER("root")->query_attribute(USER_WORKROOM);
    if (!objectp(wr)) {
	wr = _Persistence->find_object(USER("root")->get_object_id() + 1);
	if (objectp(wr) && (wr->get_object_class() & CLASS_ROOM) ) 
	{
	    werror("\nrestoring USER_WORKROOM of root\n");
	    USER("root")->unlock_attribute(USER_WORKROOM);
	    USER("root")->set_attribute(USER_WORKROOM, wr);
	    USER("root")->lock_attribute(USER_WORKROOM);
	}
    }
    object tb = USER("root")->query_attribute(USER_TRASHBIN);
    if (!objectp(tb)) {
      tb = _Persistence->find_object(USER("root")->get_object_id() + 3);
      if (objectp(tb) && (tb->get_object_class() & CLASS_CONTAINER) ) {
        werror("\nrestoring USER_TRASHBIN of root\n");
        USER("root")->unlock_attribute(USER_TRASHBIN);
        USER("root")->set_attribute(USER_TRASHBIN, tb);
        USER("root")->lock_attribute(USER_TRASHBIN);
      }
    }
}

static bool check_config_folder ()
{
  // folder: /config
  object config_folder = get_module("filepath:tree")->path_to_object(
      "/config" );
  if ( ! objectp(config_folder) ) {
    object container_factory = get_factory(CLASS_CONTAINER);
    if ( ! objectp(container_factory) ) {
      FATAL("Container factory not found, cannot create /config folder!");
      return false;
    }
    config_folder = container_factory->execute( ([ "name":"config" ]) );
    if ( ! objectp(config_folder) ) {
      FATAL("Could not create /config folder!");
      return false;
    }
    if ( ! config_folder->move( _ROOTROOM ) ) {
      FATAL("Could not move config folder to root room!");
      config_folder->delete();
      return false;
    }
    config_folder->set_attribute( OBJ_TYPE, "container_config" );
    MESSAGE( "Created /config container." );
  }
  int permissions_fixed = false;
  if ( config_folder->query_sanction( _ADMIN ) != SANCTION_ALL ) {
    config_folder->sanction_object( _ADMIN, SANCTION_ALL );
    permissions_fixed = true;
  }
  if ( config_folder->query_meta_sanction( _ADMIN ) != SANCTION_ALL ) {
    config_folder->sanction_object_meta( _ADMIN, SANCTION_ALL );
    permissions_fixed = true;
  }
  if ( permissions_fixed )
    MESSAGE( "Fixed access rights on /config container." );
  if ( config_folder->query_attribute( OBJ_TYPE ) != "container_config" ) {
    config_folder->set_attribute( OBJ_TYPE, "container_config" );
    MESSAGE( "Fixed OBJ_TYPE of /config folder." );
  }

  // folder: /config/updates
  object updates_folder = get_module("filepath:tree")->path_to_object(
      "/config/updates" );
  if ( ! objectp(updates_folder) ) {
    object container_factory = get_factory(CLASS_CONTAINER);
    if ( ! objectp(container_factory) ) {
      FATAL("Container factory not found, cannot create /config/updates folder!");
      return false;
    }
    updates_folder = container_factory->execute( ([ "name":"updates" ]) );
    if ( ! objectp(updates_folder) ) {
      FATAL("Could not create /config/updates folder!");
      return false;
    }
    updates_folder->set_attribute( OBJ_DESC, "Internal server configs and updates" );
    updates_folder->set_attribute( OBJ_TYPE, "container_config_updates" );
    if ( ! updates_folder->move( config_folder ) ) {
      FATAL("Could not move updates folder to /config!");
      updates_folder->delete();
      return false;
    }
    MESSAGE( "Created /config/updates folder." );
  }
  if ( updates_folder->query_attribute( OBJ_TYPE ) != "container_config_updates" ) {
    updates_folder->set_attribute( OBJ_TYPE, "container_config_updates" );
    MESSAGE( "Fixed OBJ_TYPE of /config/updates folder." );
  }

  // folder: /config/packages
  object packages_folder = get_module("filepath:tree")->path_to_object(
    "/config/packages" );
  if ( ! objectp( packages_folder ) ) {
    object container_factory = get_factory(CLASS_CONTAINER);
    if ( ! objectp(container_factory) ) {
      FATAL("Container factory not found, cannot create /config/packages folder!");
      return false;
    }
    packages_folder = container_factory->execute( ([ "name":"packages" ]) );
    if ( ! objectp(packages_folder) ) {
      FATAL("Could not create /config/packages folder!");
      return false;
    }
    packages_folder->set_attribute( OBJ_DESC, "Package configs" );
    packages_folder->set_attribute( OBJ_TYPE, "container_config_packages" );
    if ( ! packages_folder->move( config_folder ) ) {
      FATAL("Could not move packages folder to /config!");
      packages_folder->delete();
      return false;
    }
    MESSAGE( "Created /config/packages folder." );
  }
  if ( packages_folder->query_attribute( OBJ_TYPE ) != "container_config_packages" ) {
    packages_folder->set_attribute( OBJ_TYPE, "container_config_packages" );
    MESSAGE( "Fixed OBJ_TYPE of /config/packages folder." );
  }

  // main server config object:
  object config_obj = config_folder->get_object_byname( get_identifier() );
  if ( ! objectp(config_obj) ) {
    object admin = GROUP("admin");
    if ( objectp(admin) ) {
      mapping confs = admin->query_attribute("configs");
      if ( !mappingp(confs) ) confs = ([ ]);
      if ( ! set_internal_config( this_object(), confs ) ) {
        FATAL( "Could not create /config/%s config object!", get_identifier() );
        return false;
      }
      werror( "Created /config/%s config object.\n", get_identifier() );
    }
  }
  config_obj = config_folder->get_object_byname( get_identifier() );
  if ( objectp(config_obj) && config_obj->query_attribute( OBJ_TYPE ) != "object_config_server" ) {
    config_obj->set_attribute( OBJ_TYPE, "object_config_server" );
    MESSAGE( "Fixed OBJ_TYPE of /config/%s config object.", get_identifier() );
  }

  // decorate server config object with Config decoration:
  string config_decoration = "server:/decorations/Config.pike";
  if ( !config_obj->has_decoration( config_decoration ) ) {
    config_obj->add_decoration( config_decoration );
    MESSAGE( "Decorated /config/%s with Config decoration: %s",
             config_obj->get_identifier(), config_decoration );
  }

  return true;
}


static void start_services()
{
  object u_service = USER("service");

  // generate a ticket for the service user that lasts ca. 10 years
  // (this ticket is generated on every restart, so a server could run
  // up to 10 years without restart before the services can't reconnect):
  Stdio.write_file( "service.pass",
                    u_service->get_ticket( time() + 316224000 ), 0600 );
  return;
}


mixed query_config(mixed config)
{
    if ( config == "database" )
	return 0;
    return mConfigs[config];
}


mapping read_certificate () {
  string path = query_config("config-dir");
  return cert.read_certificate( ({
    ({ path+"steam.crt", path+"steam.key" }),
    path+"steam.cer",
  }) );
}

string plusminus(int num)
{
  return ( num > 0 ? "+"+num: (string)num);
}


string get_database()
{
    //MESSAGE("CALLERPRG="+master()->describe_program(CALLERPROGRAM));
    if ( CALLER == oDatabase || 
	 CALLERPROGRAM==(program)"/kernel/steamsocket.pike" )
	return mConfigs["database"];
    MESSAGE("NO ACCESS to database for "+
            master()->describe_program(CALLERPROGRAM)+
            " !!!!!!!!!!!!!!!!!!!!!!!\n\n");
    return "no access";
}

mapping get_configs()
{
    mapping res = copy_value(mConfigs);
    res["database"] = 0;
    return res;
}

mixed get_config(mixed key)
{
    return  mConfigs[key];
}


string get_version()
{
    return STEAM_VERSION;
}

int get_last_reboot()
{
    return iLastReboot;
}

static private void got_kill(int sig)
{
  MESSAGE("Closing ports!");
  if (objectp(nmaster)) {
    foreach(nmaster->get_ports(), object p)
      catch(close_port(p));
  }
  
  MESSAGE( "Shutting down ! (waiting for database to save %d items [%d queued/%d busy])",
	   oDatabase->get_save_size(), oDatabase->get_save_queue_size()[0],
	   oDatabase->get_save_queue_size()[1]);
  werror( "Shutting down ! (waiting for database to save %d items [%d queued/%d busy])\n",
	   oDatabase->get_save_size(), oDatabase->get_save_queue_size()[0],
	   oDatabase->get_save_queue_size()[1]);
  oDatabase->log_save_queue( 1000 );
  catch(oDatabase->wait_for_db_lock());
  MESSAGE("Database finished, exiting.");
  werror("Database finished, exiting.\n");
  string restart_time = Stdio.read_file( "/server.restart" );
  if ( stringp(restart_time) && restart_time != "" ) {
    MESSAGE( "Will restart due to restart request from %s", restart_time );
    werror( "Will restart due to restart request from %s", restart_time );
    _exit(0);
  }
  _exit(1);
}

static private void got_hangup(int sig)
{
  got_kill(sig);
}

static private void got_sigquit(int sig)
{
  nmaster->describe_threads();
  got_kill(sig);
}



mapping get_errors()
{
    return mErrors;
}

void add_error(int t, mixed err)
{
    mErrors[t] = err;
}

int main(int argc, array(string) argv)
{
    
    mErrors = ([ ]);
    mConfigs = ([ ]);
    int i;
    string path;
    int pid = getpid();
    sTest = 0;
    path = getcwd();

    MESSAGE( "sTeam " + STEAM_VERSION + " running on " + version() + " ..." );
    werror( "sTeam " + STEAM_VERSION + " running on " + version() + "\nStartup on " + ctime(time()) );
    if ( BRAND_NAME != "steam" )
      MESSAGE( "Brand name is '%s'.\n", BRAND_NAME );

    string pidfile = path + "/steam.pid";
    
    mConfigs["logdir"] = LOG_DIR;
    if ( mConfigs["logdir"][-1]!='/' ) mConfigs["logdir"] += "/";
    mConfigs["config-dir"] = CONFIG_DIR;
    if ( mConfigs["config-dir"][-1]!='/' ) mConfigs["config-dir"] += "/";

    for ( i = 1; i < sizeof(argv); i++ ) {
	string cfg, val;
	if ( argv[i] == "--test" )
            sTest = "all";
	else if ( sscanf(argv[i], "--%s=%s", cfg, val) == 2 ) {
	    int v;
	    if ( cfg == "test" ) {
              sTest = val;
            }
	    if ( cfg == "email" || cfg == "mail" ) {
	      aEmailAddresses = Config.array_value( val );
	    }
	    else if ( cfg == "pid" ) {
		pidfile = val;
	    }
	    else if ( sscanf(val, "%d", v) == 1 )
		mConfigs[cfg] = v;
	    else
		mConfigs[cfg] = val;
	}
	else if ( sscanf(argv[i], "-D%s", cfg) == 1 ) {
	  add_constant(cfg, 1);
	}
    }
    
    mixed err = catch(_stderr = Stdio.File(mConfigs["logdir"]+"/errors.log", "r"));
    if(err)
      MESSAGE("Failed to open %s/errors.log", mConfigs["logdir"]);

    signal(signum("QUIT"), got_kill);
    signal(signum("TERM"), got_kill);
    signal(signum("SIGHUP"), got_hangup);
    signal(signum("SIGINT"), got_hangup);
    signal(signum("SIGQUIT"), got_sigquit);
    return start_server();
}

object get_stderr() 
{
  return _stderr;
}

object get_stdout()
{
  return _stdout;
}

mixed get_module(string module_id)
{
    object module;
    module = mModules[module_id];
    if ( objectp(module) && module->status() >= 0 )
      return module->this();
    return 0;
}

mixed call_module(string module, string func, mixed ... args)
{
    object mod = mModules[module];
    if ( !objectp(mod) ) 
	THROW("Failed to call module "+ module + " - not found.", E_ERROR);
    function f = mod->find_function(func);
    if ( !functionp(f) )
	THROW("Function " + func + " not found inside Module " + module +" !", E_ERROR);
    if ( sizeof(args) == 0 )
	return f();
    return f(@args);
}


mapping get_modules()
{
    return copy_value(mModules);
}

array(object) get_module_objs()
{
    return values(mModules);
}

static object f_open_port(string pname)
{
    program prg = (program)("/net/port/"+pname);
    object port = nmaster->new("/net/port/"+pname);
    mPortPrograms[port->get_port_name()] = prg;
    if ( get_config(port->get_port_config()) == "disabled" )
      return 0;
    if ( !port->open_port() && port->port_required() ) 
	return 0;
    nmaster->register_port(port);
    return port;
}

/**
 * Open a single port of the server. 
 *  
 * @param string pname - the name of the port to open.
 * @return the port object or zero.
 */
object open_port(string pname)
{
    if ( _ADMIN->is_member(nmaster->this_user()) ) {
	return f_open_port(pname);
    }
    return 0;
}

/**
 * Open all ports of the server.
 * See the /net/port/ Directory for all available ports.
 *  
 */
static void open_ports()
{
    array(string) ports;
    
    mPortPrograms = ([ ]);

    ports = nmaster->get_dir("/net/port");
    MESSAGE("Opening ports ...");
    // check for steam.cer...
    if ( !Stdio.exist(query_config("config-dir")+"steam.cer") &&
         !Stdio.exist(query_config("config-dir")+"steam.crt") ) {
      MESSAGE("Certificate File Missing - creating new one ...\n");
      string cert = cert.create_cert(  ([
	"country": "Germany",
	"organization": "University of Paderborn",
	"unit": "Open sTeam",
	"locality": "Paderborn",
	"province": "NRW",
	"name": get_server_name(),
      ]) );
      Stdio.write_file( query_config("config-dir") + "steam.cer", cert);
    }
    for ( int i = sizeof(ports) - 1; i >= 0; i-- ) {
	if ( ports[i][0] == '#' || ports[i][0] == '.' || ports[i][-1] == '~' )
	    continue;
	if ( sscanf(ports[i], "%s.pike", ports[i]) != 1 ) continue;
	f_open_port(ports[i]);
    }
}

/**
 * Get all string identifiers of available ports (open and close).
 *  
 * @return Array of port identifier strings.
 */
array(string) get_ports()
{
    return indices(mPortPrograms);
}

int close_port(object p)
{
    if ( !objectp(p) )
	error("Cannot close NULL port !");
    if ( _ADMIN->is_member(nmaster->this_user()) ) {
	if ( functionp(p->close_port) )
	    p->close_port();
	if ( objectp(p) )
	    destruct(p);
	return 1;
    }
    return 0;
}

int restart_port(object p)
{
    if ( _ADMIN->is_member(nmaster->this_user()) ) {
	program prg = object_program(p);
	if ( functionp(p->close_port) )
	    p->close_port();
	if ( objectp(p) )
	    destruct(p);
	p = prg();
	if ( p->open_port() ) 
	    MESSAGE("Port restarted ....");
	else {
	    MESSAGE("Restarting port failed.");
	    return 0;
	}
	nmaster->register_port(p);
	return 1;
    }
    return 0;
}

mapping debug_memory(void|mapping debug_old)
{
  mapping dmap = Debug.memory_usage();
  if (!mappingp(debug_old) )
    return dmap;
  foreach(indices(dmap), string idx)
    dmap[idx] = (dmap[idx] - debug_old[idx]);
  return dmap;
}


/**
 * Install all modules of the server.
 *  
 */
void install_modules()
{
    foreach ( indices(mModules), string module ) {
      if ( !objectp(mModules[module]) ) continue;
      mixed err = catch {
          mModules[module]->runtime_install();
      };
      if(err)
          FATAL( "Failed to install module %s (%O)\n%s",
                 module, mModules[module],PRINT_BT(err) );
    }
    foreach ( indices(mModules), string module ) {
        if ( !stringp(module) || module == "" ) {
            FATAL( "Removing module with invalid name: %O, object: %O\n",
                   module, mModules[module] );
            m_delete( mModules, module );
            continue;
        }
        if ( !objectp(mModules[module]) ) {
            FATAL( "Removing broken (non-object) module: %O\n", module );
            m_delete( mModules, module );
            continue;
        }
	if ( mModules[module]->status() == PSTAT_DELETED ||
	     mModules[module]->status() == PSTAT_FAIL_DELETED ) 
	{
            FATAL( "Removing deleted module: %O, object: %O, status: %O\n",
                   module, mModules[module], mModules[module]->status() );
            m_delete( mModules, module );
	}
    }
    save_modules();
}

/**
 * register a module - can only be called by database !
 *  
 * @param object mod - the module to register
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
final void register_module(object mod)
{
    if ( CALLER == oDatabase ) {
	mModules[mod->get_identifier()] = mod;
	save_modules();
    }
}

final bool is_registered_module(object mod) 
{
  if (mModules[mod->get_identifier()] == mod) {
    return true;
  }
  return false;
}

final void unregister_module(object mod)
{
    if ( !objectp(mod) ) return;
    if ( CALLER->this() == mod->this() &&
         !zero_type(mModules[mod->get_identifier()]) ) {
        m_delete( mModules, mod->get_identifier() );
        save_modules();
    }
}

private static mapping load_module_configuration(string name)
{
  mapping config;

  string content = Stdio.read_file(CONFIG_DIR+"/"+name+".xml");
  if ( stringp(content) )
    config = Module.read_config(content, name);
  else
    config = ([ ]);

  // parse module code for "#define DEPENDENCIES" line:
  array file_dependencies;
  if ( catch {
      array tokens = Parser.Pike.split( Stdio.read_file(nmaster->apply_mount_points("/modules")+"/"+name+".pike") );
      string deps;
      foreach ( tokens, string token ) {
	  if ( sscanf( token, "#define%*[ \t]DEPENDENCIES%*[ \t]%s\n", deps ) > 1 ) {
	      file_dependencies = deps / " ";
	      break;
	  }
      }
  } != 0 ) {
      werror( "Could not parse module : %s\n", name );
  }
  if ( arrayp(file_dependencies) ) {
      if ( !arrayp(config->depends) ) config->depends = file_dependencies;
      else foreach ( file_dependencies, string dep )
	       if ( search( config->depends, dep ) < 0 )
		   config->depends += ({ dep });
  }

  config["score"] = 1000;
  return config;
}

/**
 * Load a module
 *  
 * @param string mpath - the filename of the module
 * @return 
 */
private static object load_module(string mpath)
{
    if ( sscanf(mpath, "%s.pike", mpath) != 1 )
	return 0;
    MESSAGE( "LOADING MODULE:" + mpath + " ... " );
    /* dont load the module that keeps the list of all modules
     * Because it is loaded by database 
     */
    if  ( mpath == "modules" ) 
	return 0;
    
    object module = 0;
    int database_id = oDatabase->get_variable("#"+mpath);
    if ( database_id != 0 )
       module = oDatabase->find_object(database_id);

    // we found an already existing one
    if ( objectp(module) && module->status() >= 0 ) 
    {
	if ( objectp(module->get_object()) )
	    mModules[module->get_identifier()] = module;
	else
	    FATAL("Failed to create instance of "+mpath + " (status="+
		  module->status()+")");
    }
    else
    {
	MESSAGE("Creating new instance of "+mpath);
	// first try to read config file for that module (if any)
	
	mixed err = catch {
	    module = nmaster->new("/modules/"+mpath+".pike");
	};
	if ( err != 0 ) {
	    FATAL("Error while creating new instance of " + mpath + "\n" + 
		  PRINT_BT(err));
	}
	err = catch {
	  if (objectp(module)) {
	    if (!functionp(module->this) ) /* check existance of function */
	    {
	      FATAL("unable to register module \""+mpath+
		      "\" it has to inherit /kernel/module or at least "+
		      "/classes/Object");
	      module = 0;
	    }
	    else
	    {
		oDatabase->set_variable("#"+mpath,
					module->get_object_id());
		module = module->this();
		mModules[module->get_identifier()] = module;
		module->set_attribute(OBJ_DESC, "");
		module->loaded();
		module->created();
	    }
	  }
	};
	if ( err != 0 )
	    FATAL("Error registering module \""+mpath+"\":\n"+PRINT_BT(err));
    }

    if (objectp(module)) 
      MESSAGE("alias " + module->get_identifier() +
	      " OID("+module->get_object_id()+")");

    return module;
}

bool is_module(object mod)
{
  if ( !functionp(mod->get_identifier) )
      return false;
  object module = mModules[mod->get_identifier()];
  if ( objectp(module) )
    return module->this() == mod->this();
  return 0;
}

private static int order_modules(string mod1, string mod2, mapping configs)
{
  if ( sscanf(mod1, "%s.pike", mod1) == 0)
    return 0;
  if ( sscanf(mod2, "%s.pike", mod2) == 0 )
    return 0;

  return configs[mod1]->score < configs[mod2]->score;
}

void update_depend(string depend, mapping conf)
{
  MESSAGE("Updating: %s", depend);
  if ( conf[depend]->mark == 1 )
    steam_error("Loop in module Dependencies detected !");
  conf[depend]->mark = 1;

  conf[depend]->score++;
  if ( arrayp(conf[depend]->depends) ) {
    foreach(conf[depend]->depends, string depdep) {
      update_depend(depdep, conf);
    }
  }
  conf[depend]->mark = 0;
}

static int filter_system(string fname)
{
  if ( search(fname, "~") >= 0 ) return 0;
  if ( fname[0] == '#' || fname[0] == '.' ) return 0;
  return 1;
}

/**
 * Load all modules.
 *  
 */
static void load_modules()
{
    int    i, tt;
    
    object         module;
    array(string) modules;
    
    tt = f_get_time_millis();
    mModules = ([]);
    modules = nmaster->get_dir("/modules");
    
    array(string) priority_load = ({ 
	"log.pike", "security.pike", "cache.pike", "groups.pike", "users.pike",
	"objects.pike", "filepath.pike", "message.pike", "mailbox.pike",
	"xml_converter.pike" });
    
    modules -= priority_load;
    modules = priority_load + modules;
    modules = filter(modules, filter_system);

    mapping configurations = ([ ]);
    for ( i = 0; i < sizeof(modules); i++ ) {
        string modname;
        if ( sscanf(modules[i], "%s.pike", modname) == 0 )
            continue;

	mapping conf = load_module_configuration(modname);
	if ( arrayp(conf->depends) ) {
	  foreach(conf->depends, string depend) {
	    if ( !mappingp(configurations[depend]) )
	      configurations[depend] = ([ "score": 1000, "depends": 0, ]);
	    update_depend(depend, configurations);
	  }
	}

	if ( !mappingp(configurations[modname]) )
	  configurations[modname] = conf;
	else
	  configurations[modname]->depends = conf->depends;
    }
    // now we need to sort our modules according to the graph in configurations
    // sortierung durch vergleich 2er element ist ok
    modules = Array.sort_array(modules, order_modules, configurations);
    
    // finally load the modules
    for ( i = 0; i < sizeof(modules); i++ ) {
	if ( search(modules[i], "~") >= 0 ) continue;
	if ( modules[i][0] == '#' || modules[i][0] == '.' ) continue;
	// only load pike programms !
	load_module(modules[i]);
    }

    foreach(values(mModules), object module) {
      if ( objectp(module) )
	module->post_load_module();
    }
    MESSAGE("Loading modules finished in %d ms...",
	    f_get_time_millis() - tt);
}

void load_programs()
{
    //bugfix for pike 7.8. init ldap protocol once here to prevent exeption caused 
    //by ${PIKE_MODULE_PATH} problem
    catch( Protocols.LDAP.client() );

    string cl;
    int tt = f_get_time_millis();
    
    array(string) classfiles = nmaster->get_dir("/classes");
    foreach(classfiles, cl) {
	if ( cl[0] == '.' || cl[0] == '#' || search(cl, "~") >= 0 || 
	     search(cl, "CVS") >= 0 ) continue;

	MESSAGE("Preparing class: " + cl);
	program prg = (program) ("/classes/"+cl);
    }
    classfiles = nmaster->get_dir("/kernel");
    foreach(classfiles, cl) {
	if ( cl[0] == '.' || cl[0] == '#' || search(cl, "~") >= 0 ||
	     search(cl, "CVS") >= 0 ) 
	     continue;

	MESSAGE("Preparing class: " + cl);
	program prg = (program) ("/kernel/"+cl);
    }
    MESSAGE("Loading programs finished in %d ms...", f_get_time_millis() - tt);
}

static void load_pmods(string path, void|string symbol)
{
  string newsymbol;
  int tt = f_get_time_millis();

  array pmods = nmaster->get_dir(path);
  foreach(pmods, string pmod) {
    if ( nmaster->is_dir(path + pmod) ) {
      sscanf(pmod, "%s.pmod", newsymbol);
      if ( stringp(symbol) )
	load_pmods(path + pmod, symbol + "." + newsymbol);	
      else
	load_pmods(path + pmod, newsymbol);	

      nmaster->resolv(pmod);
    }
    else {
      if (sscanf(pmod, "%s.pmod", pmod) || 
          (stringp(symbol) && sscanf(pmod, "%s.pike", pmod)) ) 
      {
	if ( search(pmod, ".") >= 0 || search(pmod, "#") >= 0 ) continue;
	MESSAGE("Loading Pike-Module %s", 
                (stringp(symbol)?symbol+".":"")+pmod);
	if ( stringp(symbol) )
	  nmaster->resolv(symbol + "." + pmod);
	else
	  nmaster->resolv(pmod);
      }
    }
  }
}

/**
 * Load all modules from the database ( stored in the admin group )
 *  
 */
static void load_modules_db()
{
    MESSAGE("Loading registered modules from database...");
    mixed err = catch {
	object groups = mModules["groups"];
	if ( objectp(groups) ) {
	  object admin = _ADMIN;
	    if ( !objectp(admin) )
		return;
	    mapping modules = admin->query_attribute("modules");
	    if ( !mappingp(modules) ) {
		MESSAGE("No additional modules registered yet!");
		return;
	    }
	    // sync modules saved in admin group with already loaded
	    foreach ( indices(modules), string m ) {
		if ( !mModules[m] )
		    mModules[m] = modules[m];
	    }
	}
	MESSAGE("Loading modules from database finished.");
    };
    if ( err != 0 ) 
	FATAL("Loading Modules from Database failed.\n"+PRINT_BT(err));
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static void load_factories()
{
    int                   i;
    string     factory_name;
    object          factory;
    object            proxy;
    mixed               err;

    array(string) factories;
    array(object) loaded = ({});

    int tt = f_get_time_millis();
    
    factories = nmaster->get_dir("/factories");
    factories -= ({ "DateFactory.pike" });
    factories -= ({ "CalendarFactory.pike" });
    factories -= ({ "AnnotationFactory.pike" });
    factories = ({ "DateFactory.pike", "CalendarFactory.pike" }) + factories;
    for ( i = sizeof(factories) - 1; i >= 0; i-- ) {
	if ( sscanf(factories[i], "%s.pike", factory_name) == 0 )
	    continue;

	if ( search(factory_name, "~") >= 0 || search(factory_name, "~")>=0 ||
	     search(factory_name, ".") == 0 || search(factory_name,"#")>=0 )
	    continue;
        MESSAGE("LOADING FACTORY:%s ...", factory_name);
	proxy = _Persistence->lookup(factory_name);
	if ( !objectp(proxy) ) {
	    MESSAGE("Creating new instance...");
	    err = catch {
		factory = nmaster->new("/factories/"+factory_name+".pike", 
				       factory_name);
	    };
	    if ( err != 0 ) {
		MESSAGE("Error while loading factory " + factory_name + "\n"+
			PRINT_BT(err));
		continue;
	    }
	    
	    proxy = factory->this();
	    mClasses["_loading"] = proxy;
            proxy->created();
	    m_delete(mClasses, "_loading");
            if (proxy->status()>=PSTAT_SAVE_OK)
	    {
	      MESSAGE("New Factory registered !");
	      MODULE_OBJECTS->register(factory_name, proxy);
            }
	}
	else {
            int iProxyStatus;
	    err = catch {
                int iProxyStatus = proxy->force_load();
            };
            if (err!=0) {
                MESSAGE("Error while loading factory %s status(%d)\n%s\n",
                        factory_name, iProxyStatus, master()->describe_backtrace(err));
            }
	}

        if (proxy->status() >= PSTAT_SAVE_OK)
        {
            mClasses[proxy->get_class_id()] = proxy;
            loaded += ({ proxy });
            err = catch {
                proxy->unlock_attribute(OBJ_NAME);
                proxy->set_attribute(OBJ_NAME, proxy->get_identifier());
                proxy->lock_attribute(OBJ_NAME);
            };
            if ( err != 0 ) {
                FATAL("There was an error loading a factory...\n"+
                      PRINT_BT(err));
            }
        }
        else
            MESSAGE("factory is %s with status %d", 
		    factory_name, proxy->status());
    }
    MESSAGE("Loading factories finished in %d ms ...", f_get_time_millis()-tt);
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
void load_objects()
{
    object factory, root, room, admin, world, steam, guest, postman;
    int               i;
    mapping vars = ([ ]);
    
    int tt = f_get_time_millis();
    
    MESSAGE( "Loading Groups:" );
    MESSAGE( "* sTeam" );
    steam = _Persistence->lookup_group("sTeam");
    if ( !objectp(steam) ) {
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "sTeam";
	steam = factory->execute(vars);
	ASSERTINFO(objectp(steam), "Failed to create sTeam group!");
	steam->set_attribute(OBJ_DESC, "The group of all sTeam users.");
    }
    add_constant("_GroupAll", steam);
    MESSAGE( "* Everyone" );
    world = _Persistence->lookup_group("Everyone");
    if ( !objectp(world) ) {
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "Everyone";
	world = factory->execute(vars);
	ASSERTINFO(objectp(world), "Failed to create world user group!");
	world->set_attribute(
	    OBJ_DESC, "This is the virtual group of all internet users.");
    }
    MESSAGE( "* Help" );
    object hilfe = _Persistence->lookup_group("help");
    if ( !objectp(hilfe) ) {
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "help";
	hilfe = factory->execute(vars);
	ASSERTINFO(objectp(hilfe), "Failed to create hilfe group!");
	hilfe->set_attribute(
	    OBJ_DESC, "This is the help group of steam.");
    }
    mixed err = catch {
        hilfe->sanction_object(steam, SANCTION_READ|SANCTION_ANNOTATE);
    };
    if(err)
      MESSAGE("Failed sanction on hilfe group\n"+PRINT_BT(err));

    bool rootnew = false;

    MESSAGE( "Groups loaded (took %d ms)", f_get_time_millis() - tt );
    MESSAGE( "Loading users:" );
    MESSAGE( "* root" );
    root = _Persistence->lookup_user("root");
    if ( !objectp(root) ) {
	rootnew = true;
	factory = get_factory(CLASS_USER);
	vars["name"] = "root";
	vars["pw"] = "steam";
	vars["email"] = "";
        vars["firstname"] = "Root";
	vars["fullname"] = "User";
	root = factory->execute(vars);
	root->activate_user(factory->get_activation());
	ASSERTINFO(objectp(root), "Failed to create root user !");
	root->set_attribute(
	    OBJ_DESC, "The root user is the first administrator of sTeam.");
    }
    if ( mConfigs->password ) {
      root->set_user_password(mConfigs->password);
      m_delete(mConfigs, "password");
      write_config_to_admin();
    }
    MESSAGE( "* guest" );
    guest = _Persistence->lookup_user("guest");
    if ( !objectp(guest) ) {
	factory = get_factory(CLASS_USER);
	vars["name"] = "guest";
	vars["pw"] = "guest";
	vars["email"] = "none";
	vars["firstname"] = "Guest";
	vars["fullname"] = "User";
	guest = factory->execute(vars);
	
	ASSERTINFO(objectp(guest), "Failed to create guest user !");
	guest->activate_user(factory->get_activation());
	guest->sanction_object(world, SANCTION_MOVE); // move around guest
	object guest_wr = guest->query_attribute(USER_WORKROOM);
	guest_wr->sanction_object(guest, SANCTION_READ|SANCTION_INSERT);
	guest->set_attribute(
	    OBJ_DESC, "Guest is the guest user.");
    }
    get_factory(CLASS_USER)->reset_guest();
    ASSERTINFO(guest->get_user_name() == "guest", "False name of guest !");
    world->add_member(guest);

    MESSAGE( "* service" );
    object service = _Persistence->lookup_user("service");
    if ( !objectp(service) ) {
	factory = get_factory(CLASS_USER);
	vars["name"] = "service";
	vars["pw"] = "";
	vars["email"] = "none";
	vars["fullname"] = "Service";
	service = factory->execute(vars);
	
	ASSERTINFO(objectp(service), "Failed to create service user !");
	service->activate_user(factory->get_activation());
	service->set_user_password("0", 1);
	service->sanction_object(world, SANCTION_MOVE); // move around service
	object service_wr = service->query_attribute(USER_WORKROOM);
	service_wr->sanction_object(service, SANCTION_READ|SANCTION_INSERT);
	service->set_attribute(
	    OBJ_DESC, "Service is the service user.");
    }

    MESSAGE( "* postman" );
    postman = _Persistence->lookup_user("postman");
    if ( !objectp(postman) ) 
    {
        factory = get_factory(CLASS_USER);
        vars["name"] = "postman";
#if constant(Crypto.Random)
        vars["pw"] = Crypto.Random.random_string(10); //disable passwd
#else
        vars["pw"] = Crypto.randomness.pike_random()->read(10); //disable passwd
#endif
        vars["email"] = "";
        vars["fullname"] = "Postman";
        postman = factory->execute(vars);

        ASSERTINFO(objectp(postman), "Failed to create postman user !");
        postman->activate_user(factory->get_activation());
        postman->sanction_object(world, SANCTION_MOVE); // move postman around
        object postman_wr = postman->query_attribute(USER_WORKROOM);
        postman_wr->sanction_object(postman, SANCTION_READ|SANCTION_INSERT);
        postman->set_attribute(OBJ_DESC, 
               "The postman delivers emails sent to sTeam from the outside.");
    }
    ASSERTINFO(postman->get_user_name() == "postman", "False name of postman !");
    err = catch {
	 room = _Persistence->lookup("rootroom");
	 if ( !objectp(room) ) {
	     factory = get_factory(CLASS_ROOM);
	     vars["name"] = "root-room";
	     room = factory->execute(vars);
	     ASSERTINFO(objectp(room), "Failed to create root room !");
	     room->sanction_object(steam, SANCTION_READ);
	     ASSERTINFO(MODULE_OBJECTS->register("rootroom", room),
			"Failed to register room !");
	     root->move(room);
	     room->set_attribute(
		 OBJ_DESC, "The root room contains system documents.");
	 }
    };
    if ( err ) {
      MESSAGE( "Failed to create root room" );
      FATAL( "Failed to create root room:\n%s\n", PRINT_BT(err) );
    }

    guest->move(room);
    postman->move(room);
    root->move(room);
    if ( rootnew ) {
	// only create the exit in roots workroom if the user has
	// been just created
        MESSAGE("New roots workroom");
	object workroom = root->query_attribute(USER_WORKROOM);
	if ( objectp(workroom) ) {
	    object exittoroot;
	    factory = get_factory(CLASS_EXIT);
	    exittoroot = factory->execute((["name":"root-room",
					   "exit_to":room,]));
	    exittoroot->move(workroom);
	}
        MESSAGE(" - created exits and root image\n");
    }

    admin = _Persistence->lookup_group("Admin");
    if ( !objectp(admin) ) {
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "Admin";
	admin = factory->execute(vars);
	ASSERTINFO(objectp(admin), "Failed to create Admin user group!");
	admin->set_permission(ROLE_ALL_ROLES);
	admin->add_member(root);
	admin->sanction_object(root, SANCTION_ALL);
	admin->set_attribute(
	    OBJ_DESC, "The admin group is the group of administrators.");
    }
    if ( admin->get_permission() != ROLE_ALL_ROLES )
	admin->set_permission(ROLE_ALL_ROLES);
    admin->add_member(root);
    admin->add_member(service);

    ASSERTINFO(admin->get_permission() == ROLE_ALL_ROLES, 
	       "Wrong permissions for admin group !");

    object groups = _Persistence->lookup_group("PrivGroups");
    if ( !objectp(groups) ) {
        MESSAGE("** Creating PrivGroups");
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "PrivGroups";
	groups = factory->execute(vars);
	ASSERTINFO(objectp(groups), "Failed to create PrivGroups user group!");
	groups->set_attribute(OBJ_DESC, 
			      "The group to create private groups in.");
	groups->sanction_object(steam, SANCTION_INSERT|SANCTION_READ);
	// everyone can add users and groups to that group!
    }

    object wikigroups = _Persistence->lookup_group("WikiGroups");
    if ( !objectp(wikigroups) ) {
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "WikiGroups";
	wikigroups = factory->execute(vars);
	ASSERTINFO(objectp(wikigroups),"Failed to create WikiGroups user group!");
	wikigroups->set_attribute(OBJ_DESC, 
			      "The group to create wiki groups in.");
	wikigroups->sanction_object(steam, SANCTION_INSERT|SANCTION_READ);
	// everyone can add users and groups to that group!
    }
    
    // as soon as the coder group has members, the security is enabled!
    object coders = _Persistence->lookup_group("coder");
    if ( !objectp(coders) ) {
	factory = get_factory(CLASS_GROUP);
	vars["name"] = "coder";
	coders = factory->execute(vars);
	ASSERTINFO(objectp(coders), "Failed to create coder user group!");
	coders->set_attribute(OBJ_DESC, 
			      "The group of people allowed to write scripts.");
	coders->add_member(root);
    }
    mapping roles = ([ ]);

    roles["admin"] = Roles.Role("Administrator", ROLE_ALL_ROLES, 0);
    roles["steam"] = Roles.Role("sTeam User", ROLE_READ_ALL, steam);
    admin->add_role(roles->admin);
    steam->add_role(roles->steam);

    object cont = null;
    err = catch { cont = MODULE_FILEPATH->path_to_object("/factories"); };
    if (err) 
      MESSAGE(PRINT_BT(err));
    
    if ( !objectp(cont) )
    {
	factory = get_factory(CLASS_CONTAINER);
	vars["name"] = "factories";
	cont = factory->execute(vars);
	ASSERTINFO(objectp(cont),"Failed to create the factories container!");
	cont->set_attribute(OBJ_DESC, "This container is for the factories.");
    }
    ASSERTINFO(objectp(cont), "/factories/ not found");
    cont->move(room);
    
    // backtrace container
    
    oBacktraces = _Persistence->lookup("backtraces");
    if ( !objectp(oBacktraces) ) {
      oBacktraces = get_factory(CLASS_CONTAINER)->execute( 
                                 (["name":"backtraces", ]) );
      ASSERTINFO(MODULE_OBJECTS->register("backtraces", oBacktraces),
		 "Failed to register backtraces container !");
    }
    err = catch(oBacktraces->set_attribute(OBJ_URL, "/backtraces"));
    if(err)
      MESSAGE("failed to set attribute ob backtraces\n"+PRINT_BT(err));
    oBacktraces->move(room);

    object oPackages = _Persistence->lookup("packages");
    if ( !objectp(oPackages) ) {
      oPackages = room->get_object_byname("packages");
      if ( !objectp(oPackages) )
	oPackages = get_factory(CLASS_CONTAINER)->execute(
				 (["name":"packages",]));
      ASSERTINFO(MODULE_OBJECTS->register("packages", oPackages),
		 "Failed to register packages container !");
    }
    oPackages->move(room);
    
    factory = get_factory(CLASS_USER);
    factory->sanction_object(world, SANCTION_READ|SANCTION_EXECUTE);
    
    for ( i = 31; i >= 0; i-- ) {
	factory = get_factory((1<<i));
	if ( objectp(factory) ) {
	    factory->sanction_object(admin, SANCTION_EXECUTE);
	    // give execute permissions to all factories for all steam users
	    factory->sanction_object(steam, SANCTION_EXECUTE);
	    if ( objectp(cont) )
	      factory->move(cont);
	 }
    }

    object steamroom = steam->query_attribute(GROUP_WORKROOM);
    MESSAGE("Placing home module");
    object home = get_module("home");
    if ( objectp(home) ) {
	home->set_attribute(OBJ_NAME, "home");
	home->move(room);
	catch(home->set_attribute(OBJ_URL, "/home"));
    }
    MESSAGE("Placing WIKI module");
    object wiki = get_module("wiki");
    if ( objectp(wiki) ) {
        catch(wiki->set_attribute(OBJ_NAME, "wiki"));
        catch(wiki->set_attribute(OBJ_URL, "/wiki"));
	wiki->move(room);
    }
    MESSAGE("Placing Calendar module");
    object calendar = get_module("calendar");
    object cal = get_module("filepath:tree")->path_to_object("/calendar");
    if ( objectp(cal) )
      cal->move(room);

    if ( objectp(calendar) ) {
      calendar->set_attribute(OBJ_NAME, "calendar");
      catch(calendar->set_attribute(OBJ_URL, "/calendar"));
      calendar->move(room);
    }
    object spm = get_module("SPM");
    if ( objectp(spm) ) {
      spm->set_attribute(OBJ_NAME, "SPM");
      spm->move(room);
    }
    
    MESSAGE("Loading Objects finished in %d ms ...",f_get_time_millis()-tt);
}

object insert_backtrace(string btname, string btcontent)
{
  nmaster->seteuid(USER("root"));
  object bt = get_factory(CLASS_DOCUMENT)->execute((["name": btname, 
						     "mimetype":"text/html"]));
  bt->set_content(btcontent);
  bt->set_attribute(DOC_MIME_TYPE, "text/html");
  bt->move(oBacktraces);
  bt->sanction_object(GROUP("Everyone"), SANCTION_READ);
  object temp = get_module("temp_objects");
  int bt_time = get_config("keep_backtraces");
  if ( bt_time <= 0 )
    bt_time = 60*60*24*7; // one week!
  if ( objectp(temp) )
    temp->add_temp_object(bt, time() + bt_time); // a week !
  return bt;
}

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
static void f_run_global_event(int event, int phase, object obj, mixed args)
{
    mapping m;
    
    object logs = get_module("log");
    if ( objectp(logs) ) {
        mixed err;
	if ( phase == PHASE_NOTIFY ) {
	    err = catch {
	      logs->log("events", (event&EVENTS_MONITORED?LOG_LEVEL_DEBUG:LOG_LEVEL_INFO),
			Events.event_to_description(event, ({ obj })+args));
	    };
  	    if ( err ) {
		FATAL("While logging event: %O\n\n%s\n%O", args,err[0],err[1]);
	    }
	}
	else {
	    err = catch(logs->log("events", LOG_LEVEL_DEBUG, "TRY " +
				  Events.event_to_description(
				      event, ({ obj }) + args)));
  	    if ( err ) {
		FATAL("While logging event: %s\n%O", err[0], err[1]);
	    }
	}
    }

    if ( phase == PHASE_NOTIFY ) 
	m = mGlobalNotifyEvents;
    else 
	m = mGlobalBlockEvents;
    
    if ( !arrayp(m[event]) ) 
	return;
    foreach(m[event], array cb_data) {
	if ( !arrayp(cb_data) ) continue;
	string fname = cb_data[0];
	object o = cb_data[1];
	if (!objectp(o)) continue;

        function f = cb_data[2];
	if ( !functionp(f) ) {
	    if (o["find_function"])
		f = o->find_function(fname);
	    else
		f = o[fname];
	}
	
	if ( functionp(f) && objectp(function_object(f)) ) {
          mixed err = catch( f(event, obj, @args) );
          if ( err ) {
	    if ( phase == PHASE_NOTIFY ) 
	      FATAL( "exception in global event:\n%O\n%O\n",
		     err[0], err[1] );
	    else
	      throw(err);
	  }
        }
    }
}

/**
  * run a global event
  *  
  * @param int event - the event id
  * @param int phase - PHASE_BLOCK or PHASE_NOTIFY
  * @param object obj - the event object
  * @param mixed args - array of parameters
  *
  */
void run_global_event(int event, int phase, object obj, mixed args)
{
    if ( CALLER->this() != obj ) 
	return;
    f_run_global_event(event, phase, obj, args);
}


/**
  * subscribe to a global event
  *  
  * @param int event - the event id
  * @param function callback - the function to call when the event occurs
  * @param int phase - PHASE_NOTIFY or PHASE_BLOCK
  *
  */
void 
add_global_event(int event, function callback, int phase)
{
    // FIXME! This should maybe be secured
    object   obj;
    string fname;

    fname = function_name(callback);
    obj   = function_object(callback);
    if ( !objectp(obj) ) 
	THROW("Fatal Error on add_global_event(), no object !", E_ERROR);
    if ( !functionp(obj->this) )
	THROW("Fatal Error on add_global_event(), invalid object !", E_ACCESS);
    obj   = obj->this();
    if ( !objectp(obj) ) 
	THROW("Fatal Error on add_global_event(), no proxy !", E_ERROR);

    if ( phase == PHASE_NOTIFY ) {
	if ( !arrayp(mGlobalNotifyEvents[event]) ) 
	    mGlobalNotifyEvents[event] = ({ });
	mGlobalNotifyEvents[event] += ({ ({ fname, obj, callback }) });
    }
    else {
	if ( !arrayp(mGlobalBlockEvents[event]) ) 
	    mGlobalBlockEvents[event] = ({ });
	mGlobalBlockEvents[event] += ({ ({ fname, obj, callback }) });
    }
}

void
remove_global_events()
{
    array(int)         events;
    int                 event;
    array(function) notifiers;

    events = indices(mGlobalNotifyEvents);
    foreach ( events, event ) {
	notifiers = ({ });
	foreach ( mGlobalNotifyEvents[event], array cb_data ) {
	    if ( cb_data[1] != CALLER->this() )
		notifiers += ({ cb_data });
	}
	mGlobalNotifyEvents[event] = notifiers;
    }
    events = indices(mGlobalBlockEvents);
    foreach ( events, event ) {
	notifiers = ({ });
	foreach ( mGlobalBlockEvents[event], array cb_data ) {
	    if ( cb_data[1] != CALLER )
		notifiers += ({ cb_data });
	}
	mGlobalBlockEvents[event] = notifiers;
    }
}

/**
  *
  *  
  * @param 
  * @return 
  * @author Thomas Bopp (astra@upb.de) 
  * @see 
  */
void
shutdown(void|int reboot)
{
    write_config_to_admin();
    object user = nmaster->this_user();
    if ( !_ADMIN->is_member(user) )
	THROW("Illegal try to shutdown server by "+
	      (objectp(user)?user->get_identifier():"none")+"!",E_ACCESS);
    MESSAGE("Shutting down !\n");
    oDatabase->wait_for_db_lock();
    catch( rm( sandbox_path + "/server.restart" ) );
    if ( !reboot )
	_exit(1);
    _exit(0);
}

/**
 * Check whether a configuration value is permanently changeable from within
 * the server.
 * Configs that are set through the config file cannot be changed permanently
 * from within the server, only through the file (and, thus, a server restart).
 *
 * @param type the config to check
 * @return 1 if the value can be permanently changed, 0 if it can only be
 *   changed until the next restart
 * @see set_config, delete_config
 */
int is_config_changeable ( mixed type )
{
  if ( zero_type(mConfigsFromFile[type]) )
    return 1;
  else
    return 0;
}

/**
  * Set a configuration value. Configs that are set through the config
  * file cannot be changed. (They can be temporarily set by using the
  * "force" param.)
  *  
  * @param type the config to be changed
  * @param val the new value
  * @param force force setting the value (it will be overwritten by the
  *   config file on the next server restart)
  * @return 1 if the value was permanently changed,
  *   0 if it could not be changed or could only be changed temporarily
  *   (until the next restart)
  * @author Thomas Bopp (astra@upb.de)
  * @see query_config, get_config, delete_config
  */
int set_config(mixed type, mixed val, void|bool force)
{
    if ( !is_config_changeable( type ) && !force ) return 0;
    object user = nmaster->this_user();
    if ( objectp(user) && !_ADMIN->is_member(user) ) return 0;

    mConfigs[type] = val;
    write_config_to_admin();
    return is_config_changeable( type );
}


/**
  * Remove a configuration value. Configs that are set through the config
  * file cannot be changed. (They can be temporarily set by using the
  * "force" param.)
  *  
  * @param type the config to be removed
  * @param force force removing the value (it will be overwritten by the
  *   config file on the next server restart)
  * @return 1 if the value was removed, 0 if it could not be changed
  *   or only be changed temporarily
  * @author Thomas Bopp (astra@upb.de)
  * @see query_config, get_config, set_config
  */
int delete_config(mixed type, void|bool force)
{
    if ( !is_config_changeable( type ) && !force ) return 0;
    object user = nmaster->this_user();
    if ( objectp(user) && !_ADMIN->is_member(user) ) return 0;

    m_delete(mConfigs, type);
    write_config_to_admin();
    return is_config_changeable( type );
}

/**
  *
  *  
  * @param 
  * @return 
  * @author Thomas Bopp (astra@upb.de) 
  * @see 
  */
void register_class(int class_id, object factory)
{
    ASSERTINFO(MODULE_SECURITY->check_access(factory, CALLER, 0, 
					     ROLE_REGISTER_CLASSES, false), 
	       "CALLER must be able to register classes !");
    mClasses[class_id] = factory;
}

/**
  *
  *  
  * @param 
  * @return 
  * @author Thomas Bopp (astra@upb.de) 
  * @see 
  */
final object get_factory(int|object|string class_id)
{
    int i, bits;

    if ( stringp(class_id) ) {
	foreach(values(mClasses), object factory) {
	    if ( factory->get_class_name() == class_id )
		return factory;
	}
	return 0;
    }
    if ( objectp(class_id) ) {
	string class_name = 
	    master()->describe_program(object_program(class_id));
	//	MESSAGE("getting factory for "+ class_name);
	if ( sscanf(class_name, "/DB:#%d.%*s", class_id) >= 1 )
	    return oDatabase->find_object(class_id)->get_object();
	class_id = class_id->get_object_class();
    }

    for ( i = 31; i >= 0; i-- ) {
	bits = (1<<i);
	if ( bits <= class_id && bits & class_id ) {
	    if ( objectp(mClasses[bits]) ) {
		return mClasses[bits]->get_object();
	    }
	}    
    }
    return null;
}

/**
  * Check if a given object is the factory of the object class of CALLER.
  *  
  * @param obj - the object to check
  * @return true or false
  * @author Thomas Bopp (astra@upb.de) 
  * @see get_factory
  * @see is_a_factory
  */
bool is_factory(object obj)
{
    object factory;

    factory = get_factory(CALLER->get_object_class());
    if ( objectp(factory) && factory == obj )
	return true;
    return false;
}

/**
  * Check if a given object is a factory. Factories are trusted objects.
  *  
  * @param obj - the object that might be a factory
  * @return true or false
  * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
  * @see is_factory
  * @see get_factory
  */
bool is_a_factory(object obj)
{
    if ( !functionp(obj->this) )
	return false;
    return (search(values(mClasses), obj->this()) >= 0);

}

/**
  * get all classes and their factories.
  *  
  * @return the mapping of all classes
  * @author Thomas Bopp (astra@upb.de) 
  * @see is_factory
  * @see get_factory
  */
final mapping get_classes()
{
    return copy_value(mClasses);
}

array(object) get_factories()
{
    return copy_value(values(mClasses));
}

object get_caller(object obj, mixed bt)
{
    int sz = sizeof(bt);
    object       caller;

    sz -= 3;
    for ( ; sz >= 0; sz-- ) {
	if ( functionp(bt[sz][2]) ) {
	    function f = bt[sz][2];
	    caller = function_object(f);
	    if ( caller != obj ) {
		return caller;
	    }
	}
    }
    return 0;
	
}


void mail_password(object user)
{
    string adminreply = "admin@" + query_config("machine") + (stringp(query_config("domain"))?"." +query_config("domain"):"");
    string pw = user->get_ticket(time() + 3600); // one hour
    int https = query_config(CFG_WEBPORT_HTTP);
    get_module("smtp")->send_mail(
	      user->query_attribute(USER_EMAIL),
	      "You Account Data for sTeam",
	      "Use the following link to login to "+
	      "the server\r\n and change your password "+
	      "within an hour:\r\n"+
	      "https://"+user->get_user_name()+":"+
	      pw+"@"+
	      query_config(CFG_WEBSERVER)+
	      (https!=443?":"+query_config(CFG_WEBPORT_HTTP):"")+
	      query_config(CFG_WEBMOUNT)+
	      "register/forgot_change.html", adminreply, adminreply);
}

mixed steam_error(string msg, mixed ... args)
{
    if ( sizeof(args) > 0 )
	msg = sprintf(msg, @args);

    throw(errors.SteamError(msg, backtrace()[1..]));
}

int f_get_time_millis () {
  array tod = System.gettimeofday();
  return tod[0]*1000 + tod[1]/1000;
}

int f_get_time_micros () {
  array tod = System.gettimeofday();
  return tod[0]*1000000 + tod[1];
}

int f_check_equal ( mixed a, mixed b )
{
  if ( zero_type(a) && !zero_type(b) )
    return 0;
  else if ( !zero_type(a) && zero_type(b) )
    return 0;
  else if ( objectp(a) ) {
    if ( !objectp(b) )
      return 0;
    if ( functionp(a->get_object_id) && functionp(b->get_object_id) )
	 return a->get_object_id() == b->get_object_id();
	 
    if ( functionp(a->equal) && a->equal != a->__null ) return a->equal(b);
    return a == b;
  }
  if ( arrayp(a) && arrayp(b) ) {
    if ( sizeof(a) != sizeof(b) ) return 0;
    for ( int i=0; i<sizeof(a); i++ ) {
      if ( ! f_check_equal( a[i], b[i] ) )
	return 0;
    }
    return 1;
  }
  if ( mappingp(a) && mappingp(b) ) {
    if ( sizeof(a) != sizeof(b) ) return 0;
    foreach ( indices(a), mixed key )
      if ( !f_check_equal( a[key], b[key] ) ) return 0;
    return 1;
  }
  if ( multisetp(a) && multisetp(b) ) {
    if ( sizeof(a) != sizeof(b) ) return 0;
    foreach ( a, mixed val )
      if ( zero_type( b[val] ) ) return 0;
    return 1;
  }
  return a == b;
}



mixed steam_user_error(string msg, mixed ... args)
{
    if ( sizeof(args) > 0 )
	msg = sprintf(msg, @args);
    throw(errors.SteamUserError(msg, backtrace()[1..]));
}

string get_server_name()
{
    string domain=query_config("domain");
    if(stringp(domain) && sizeof(domain))
      return query_config("machine") + "." + domain;
    else
      return query_config("machine");
      
}

string ssl_redirect(string url) 
{
    string sname = get_server_name();
    int https = query_config("https_port");
    if ( https == 443 ) 
	return "https://" + sname + url;
    return "https://" + sname + ":" + https + url;
}

string get_server_ip() 
{
    if ( query_config("ip") )
	return query_config("ip");
    array result = System.gethostbyname(get_server_name());
    if ( arrayp(result) ) {
	if ( sizeof(result) >= 2 ) {
	    if ( arrayp(result[1]) && sizeof(result[1]) > 0 )
		return result[1][0];
	}
    }
    return "127.0.0.1";
}

string get_server_url_presentation()
{
    int port = query_config(CFG_WEBPORT_PRESENTATION);
    
    return "http://"+get_server_name()+(port==80?"":":"+port)+"/";
}

string get_server_url_administration()
{
    int port = query_config(CFG_WEBPORT_ADMINISTRATION);
    
    return "https://"+get_server_name()+(port==443?"":":"+port)+"/";
}

static object test_save;

int check_shutdown_condition()
{
  // check if shutdown is possible right now - check for active connections.
  
  return 1;
}

static void abs()
{
  while ( 1 ) {
    mixed err;
    if ( err=catch(oDatabase->check_save_demon()) ) {
      FATAL("FATAL Error, rebooting !\n"+PRINT_BT(err));
      MESSAGE("ABS: Shutting down on fatal error !");
      oDatabase->wait_for_db_lock();
      _exit(2);
    }

    int reboot_hour = (int)get_config("reboot_hour");
    int reboot_day = (int)get_config("reboot_day");
    int reboot_memory = (int)get_config("max_memory");
    int reboot_connections = (int)get_config("max_connections");

    // find out the hour and only reboot hourly
    if ( time() - iLastReboot > 60*60 ) {
	mapping t = localtime(time());
	if ( !reboot_day || reboot_day == t->mday ) {
	    if ( reboot_hour && reboot_hour == t->hour ) {
		MESSAGE("ABS: Shutting down on reboot time !");
		oDatabase->wait_for_db_lock();
		_exit(0);
	    }
	}
    }
    int num_connections = sizeof(nmaster->get_users());
    mapping memory = debug_memory();
    int mem = 0;
    foreach(indices(memory), string idx) 
      if ( search(idx, "_bytes") > 0 )
	mem += memory[idx];
    
#if 0
    GROUP("admin")->mail("Server " + get_server_name() + " Status: <br>"+
			 "Memory: "+ mem/(1024*1024)+ "M<br>"+
			 "Connections: " + num_connections, "Status of " + 
			 get_server_name());
#endif
    if ( reboot_connections > 0 && num_connections > reboot_connections &&
	 check_shutdown_condition() ) 
    {
      MESSAGE("ABS: Shutting down due to number of connections !");
      oDatabase->wait_for_db_lock();
      _exit(0);
    }
    if ( reboot_memory > 0 && reboot_memory < mem && check_shutdown_condition()) 
    {
      MESSAGE("ABS: Shutting down due to memory usage !");
      oDatabase->wait_for_db_lock();
      _exit(0);
    }
    sleep(300); // 10 minutes
  }
}

array get_cmdline_email_addresses () {
  return aEmailAddresses;
}

void test()
{
    MESSAGE("\n*** Testing sTeam server (%O) ***\n", sTest);
    
    array testsuites = ({ });
    if ( sTest == "all" ) {
      foreach(values(mClasses), object factory)
        testsuites += ({ factory });
      foreach ( values(mModules), object module )
        testsuites += ({ module });
    }
    else {
      object obj = get_module( sTest );
      if ( !objectp(obj) )
        obj = get_factory( sTest );
      if ( !objectp(obj) && sTest == "database" )
        obj = oDatabase;
      if ( !objectp(obj) && sTest == "persistence" )
        obj = _Persistence;
      if ( !objectp(obj) && sTest == "webdav" )
        obj = nmaster->new("/net/webdav.pike", get_module("filepath:tree"), false);
      if ( !objectp(obj) && sTest == "Scripts" )
	obj = get_factory(CLASS_DOCUMENT)->execute((["name":"test.pike",]));
      if ( objectp(obj) )
        testsuites += ({ obj });
    }
    testsuites -= ({ 0 });

    MESSAGE("Testsuites are: %s", (testsuites->get_identifier())*", ");
    foreach ( testsuites, object suite )
      if ( !Test.start_test( suite ) )
	MESSAGE("Starting test in %O failed !", suite);

    //MESSAGE("\n*** All tests finished ***\n");
    nmaster->f_call_out( wait_for_tests, 10 );
    // exit(1); do not exit after test ...
}

void wait_for_tests () {
  if ( Test.all_tests_finished() ) {
    MESSAGE( Test.get_report() );
    exit( 1 );
  }
  mapping tests = Test.get_testsuites();
  int finished = 0;
  int pending = 0;
  foreach ( indices(tests), object suite ) {
    if ( Test.is_test_finished( suite ) ) finished++;
    else pending++;
  }
  MESSAGE( "*** %d tests finished, %d tests running: ***", finished, pending );
  mapping pending_tests = Test.get_pending_tests();
  foreach ( indices(pending_tests), object pending_suite ) {
    MESSAGE( "* %O : %s", pending_suite->get_identifier(),
             pending_tests[pending_suite] * "; " );
  }
  nmaster->f_call_out( wait_for_tests, 10 );
}

int get_object_class() { return 0; }
int get_object_id() { return 0; }

object this() { return this_object(); }
int status() { return PSTAT_SAVE_OK; }
object get_creator() { return USER("root"); }

function find_function(string fname) { return this_object()[fname]; }
