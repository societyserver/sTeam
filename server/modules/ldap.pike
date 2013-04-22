/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens, Robert Hinn
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
 * $Id: ldap.pike,v 1.15 2010/08/18 20:32:45 astra Exp $
 */

constant cvs_version = "$Id: ldap.pike,v 1.15 2010/08/18 20:32:45 astra Exp $";

inherit "/kernel/module";

#include <configure.h>
#include <macros.h>
#include <config.h>
#include <attributes.h>
#include <classes.h>
#include <events.h>
#include <database.h>

#define LDAP_DEBUG 1

#ifdef LDAP_DEBUG
#define LDAP_LOG(s, args...) werror("ldap: "+s+"\n", args)
#else
#define LDAP_LOG(s, args...)
#endif

#define LOG_AUTH(s, args...) werror("ldap-auth (%s): "+s+"\n", Calendar.Second(time())->format_time(), args)

#define LOG_TIME( start_time, msg, args... ) { int tmp_diff_time = get_time_millis() - start_time; if ( tmp_diff_time >= log_connection_times_min && tmp_diff_time <= log_connection_times_max ) MESSAGE( "LDAP took %d milliseconds: " + msg, tmp_diff_time, args ); }

#define NR_RETRIES 1

//! This module is a ldap client inside sTeam. It reads configuration
//! parameters of sTeam to contact a ldap server.
//! All the user management can be done with ldap this way. Some
//! special scenario might require to modify the modules code to 
//! make it work.
//!
//! The configuration variables used are:
//! server - the server name to connect to (if none is specified, then ldap will not be used)
//! cacheTime - how long (in seconds) shall ldap entries be cached? (to reduce server requests)
//! reuseConnection - "true" if you want to keep a single ldap connection open and reuse it, "false" if you want to close the connection after each request
//! restrictAccess - "true" if the ldap module shall only allow certain modules
//!   (persistence:ldap and auth) to call it (this is a privacy feature that
//!   prevents users to query ldap data of other users)
//! user   - ldap user for logging in
//! password - the password for the user
//! base_dc - ldap base dc, consult ldap documentation
//! userdn - the dn path where new users are stored
//! groupdn - the dn path where new groups are stored
//! objectName - the ldap object name to be used for the search
//! userAttr - the attribute containing the user's login name
//! passwordAttr - the attribute containing the password
//! passwordPrefix - a string to put before the password from passwordAttr, e.g. {sha}, {crypt}, {lm}, $1$
//! emailAttr - the attribute containing the user's email address
//! iconAttr - the attribute containing the user's icon
//! fullnameAttr - the attribute containing the user's surname
//! nameAttr - the attribute containing the user's first name
//! userClass - an attribute value that identifies users
//! userId - an attribute that contains a value that can be used to match users to groups
//! userAttributes - a (comma-separated) list of ldap attributes that should be copied as attributes to the user object (the steam attributes will be called the same as the ldap attributes)
//! groupAttr - the attribute (or comma-separated attributes) containing the group's name (must match the entries in groupClass)
//! groupParentAttr - an attribute specifying an ldap attribute that contains the name of the parent group for a group (Note: this is only a workaround for two-level hierarchies in certain settings. Real group hierarchies in ldap will be implemented later!)
//! groupClass - an attribute value (or comma-separated list of attribute values) that identifies groups (must match the entries in groupAttr)
//! groupId - an attribute that contains a value that can be used to match users to groups
//! subgroupMethod - determines how group hierarchies are done in ldap:
//!           "structural" : subgroups are children in the ldap tree and the
//!                          parent group thus appears in their dn
//!           "attribute" : a single attribute specifies the name of the
//!                         parent group (which doesn't have to exist in ldap),
//!                         this method is considered deprecated and only
//!                         allows one level group hierarchies
//! subgroupIgnore - (may be specified multiple times) identifies dn parts
//!                  that should not be considered parent groups if they appear
//!                  in the dn of a group
//! memberAttr - an attribute that contains a value that can be used to match users to groups
//! groupAttributes - a (comma-separated) list of ldap attributes that should be copied as attributes to the group object (the steam attributes will be called the same as the ldap attributes)
//! descriptionAttr - the attribute that contains a user or group description
//! notfound - defines what should be done if a user or group could not be found in LDAP:
//!            "create" : create and insert a new user in LDAP (at userdn)
//!            "ignore" : do nothing
//! sync - "true"/"false" : sync user or group data (false: read-only LDAP access)
//! bindUser - "true" : when authorizing users, try ldap bind first (you will need this if the ldap lookup doesn't return a password for the user)
//! bindUserWithoutDN - "false" : when binding users, only use the user name instead of the dn
//! prefetchUsers : set to true to prefetch all users from ldap
//! updateCacheInterval: interval in hours to update cache, set cacheTime to 0
//! updateCacheStartHour: start hour for update as a string, e.g. 4 for 4am
//! requiredAttr : required attributes for creating new users in LDAP
//! adminAccount - "root" : sTeam account that will receive administrative mails about ldap
//! charset - "utf-8" : charset used in ldap server
//! suspendAttr - an ldap attribute that is used to suspend (lock out) users
//! suspendAttrValue - the value (or values, separated by commas) of the suspendAttr ldap attribute. If the attribute has one of these values, the user will be suspended
//! logAuthorization - switch on logging of authorization attempts by default,
//!                    can be any combination of the following (separated by
//!                    commas):
//!                    "failure" : log failed authorization attempts (and
//!                                the first subsequent successful attempt)
//!                    "success" : log successful authorization attempts
//!                    "details" : output more details (crc checksums of
//!                                passwords)

static string sServerURL;
static mapping    config = ([ ]);

static object charset_decoder;
static object charset_encoder;

static object user_cache;
static object group_cache;
static object authorize_cache;

static Thread.Local single_ldap;
static string last_bind_dn;
static string last_bind_password_hash;
static int reconnection_time = 30;

static bool restrict_access = true;
static array valid_caller_objects = ({ });
static array valid_caller_programs = ({ });

static int log_connection_times_min = Int.NATIVE_MAX;
static int log_connection_times_max = 0;

static int log_level_auth = 0;
constant LOG_AUTH_FAILURE = 1;
constant LOG_AUTH_SUCCESS = 2;
constant LOG_AUTH_DETAILS = 4;
static mapping log_failed_auth = ([ ]);

static object admin_account = 0;
static array ldap_conflicts = ({ });

static int last_error = 0;
constant NO_ERROR = 0;
constant ERROR_UNKNOWN = -1;
constant ERROR_NOT_CONNECTED = -2;

static Thread.Queue invalidate_queue = Thread.Queue();

string get_identifier() { return "ldap"; }


class LDAPCache {
  static mapping by_identifier = ([ ]);
  static int cache_time;
  static function sync_func;
  static function last_modified_func;
  static function multi_sync_func;

  object create ( int cache_time_seconds, function synchronize_function,
                  function|void last_modified_function, 
		  function|void multi_synchronize_function ) {
    if ( !functionp(synchronize_function) )
      FATAL( "ldap: no synchronize function specified on cache creation" );
    sync_func = synchronize_function;
    multi_sync_func = multi_synchronize_function;
    last_modified_func = last_modified_function;
    cache_time = cache_time_seconds;
  }

  array list () {
    check_access();
    return indices( by_identifier );
  }

  mapping find ( string identifier ) {
    check_access();
    return by_identifier[ identifier ];
  }

  static void update_cache() {
    while (invalidate_queue->size() > 0) {
      mapping update_entry = invalidate_queue->read();
      LDAP_LOG("Updating cached entry of %O", update_entry);
      by_identifier[update_entry[config->userAttr]] = update_entry;
    }
  }

  mixed fetch ( string identifier, mixed ... args ) {
    check_access();
    if ( !stringp(identifier) ) return 0;

    // first try to update the cache if an update thread is running
    update_cache();
    
    // check whether object is already cached:
    mapping cache_entry = by_identifier[ identifier ];
    if ( mappingp(cache_entry) ) {
      if ( cache_time > 0 && 
	   time() - cache_entry->last_synchronized >= cache_time ) 
      {
        int last_modified;
        if ( !functionp(last_modified_func) ||
             (cache_entry->last_modified == 0) ||
             ((last_modified = last_modified_func( identifier, @args )) >
              cache_entry->last_modified) ) {
          mixed tmp_data = sync_func( identifier, @args );
          if ( !tmp_data ) return 0;  // only cache values != 0
          if ( stringp(tmp_data) && sizeof(tmp_data) < 1 ) return 0;
          cache_entry->data = tmp_data;
          if ( last_modified ) cache_entry->last_modified = last_modified;
          cache_entry->last_synchronized = time();
        }
      }
      cache_entry->last_accessed = time();
      return cache_entry->data;
    }
    // need to add object to cache:
    cache_entry = ([ ]);
    cache_entry->data = sync_func( identifier, @args );
    if ( !cache_entry->data ) return 0;  // only cache values != 0
    if ( stringp(cache_entry->data) && sizeof(cache_entry->data)<1 ) return 0;
    cache_entry->identifier = identifier;

    by_identifier[ identifier ] = cache_entry;
    
    if ( functionp(last_modified_func) )
      cache_entry->last_modified = last_modified_func( identifier );

    cache_entry->last_synchronized = time();
    cache_entry->last_accessed = time();

    return cache_entry->data;
  }

  void pre_fetch() {
    check_access();
    array userdata = multi_sync_func();
    foreach(userdata, mapping data) {
      mapping cache_entry = ([ ]);
      string identifier;

      if (sizeof(data) == 0) {
	continue;
      }

      data = fix_charset( data );
      identifier = data[config->userAttr];
      LDAP_LOG("pre_fetch: %s  %O (%d rows)",identifier,data->cn,sizeof(data));
      cache_entry->data = data;
      cache_entry->identifier = identifier;
      by_identifier[identifier] = cache_entry;

      if ( functionp(last_modified_func) )
	cache_entry->last_modified = last_modified_func( identifier );
      cache_entry->last_synchronized = time();
      cache_entry->last_accessed = time();
    }
  }

  int drop ( void|string identifier ) {
    if ( !has_index( by_identifier, identifier ) )
      return 0;
    m_delete( by_identifier, identifier );
    return 1;
  }

  int size() {
    return sizeof(by_identifier);
  }
}

bool ldap_activated ()
{
  array servers = Config.array_value( config["server"] );
  if ( arrayp(servers) ) {
    if ( sizeof(servers) < 1 ) return false;
    foreach ( servers, mixed server )
      if ( stringp(server) && sizeof(server) > 0 ) return true;
    return false;
  }
  return false;
}


int get_last_error () {
  return last_error;
}


string make_dn ( mixed ... parts ) {
  string dn = "";
  foreach ( parts, mixed part ) {
    if ( stringp(part) && sizeof(part) > 0 ) {
      if ( sizeof(dn) > 0 && dn[-1] != ',' ) dn += ",";
      dn += part;
    }
  }
  return dn;
}


mapping get_group_spec () {
  array groupAttrs = Config.array_value( config->groupAttr );
  array groupClasses = Config.array_value( config->groupClass );
  if ( !arrayp(groupAttrs) || sizeof(groupAttrs) == 0 ||
       !arrayp(groupClasses) || sizeof(groupClasses) == 0 ||
       sizeof(groupAttrs) != sizeof(groupClasses) )
    return UNDEFINED;
  return mkmapping( groupAttrs, groupClasses );
}


string get_group_attr ( mapping data, void|mapping group_spec ) {
  if ( !mappingp(group_spec) )
    group_spec = get_group_spec();
  if ( !mappingp(group_spec) ) return UNDEFINED;
  foreach ( indices(group_spec), string attr ) {
    mixed value = data[ attr ];
    if ( stringp(value) && value != "" )
      return value;
  }
  return UNDEFINED;
}


string dn_to_group_name ( string dn, void|int dont_strip_base_dc ) {
  string name = low_dn_to_group_name( dn );
  if ( !stringp(name) || sizeof(name) < 1 ) return name;
  if ( dont_strip_base_dc || !stringp(config->base_dc) ) return name;
  string base = low_dn_to_group_name( config->base_dc );
  if ( !has_prefix( lower_case(name), lower_case(base) ) ) return name;
  name = name[(sizeof(base)+1)..];
  if ( sizeof(name)<1 ) return 0;
  else return name;
}

static string low_dn_to_group_name ( string dn ) {
  if ( !stringp(dn) || sizeof(dn)<1 ) return 0;
  string name;
  array ignore = Config.array_value(config->subgroupIgnore);
  if ( !arrayp(ignore) ) ignore = ({ });
  for ( int i=0; i<sizeof(ignore); i++ )
    ignore[i] = lower_case( String.trim_all_whites(ignore[i]) );
  foreach ( reverse( dn / "," ), string part ) {
    part = String.trim_all_whites( part );
    // TODO: handle wildcard *
    if ( search( ignore, lower_case( part ) ) >= 0 ) continue;
    sscanf( part, "%*s=%s", part );
    if ( stringp(part) && sizeof(part)>0 ) {
      if ( stringp(name) && sizeof(name)>0 )
        name += "." + part;
      else
        name = part;
    }
  }
  return name;
}


bool check_access () {
  if ( !restrict_access ) return true;
  // check objects:
  if ( search( valid_caller_objects, CALLER ) >= 0 ) return true;
  // check programs:
  string prog = sprintf( "%O",object_program(CALLER) );
  if ( search( valid_caller_programs, prog ) >= 0 ) return true;
  // if caller is not valid, throw an exception:
  steam_error( sprintf("ldap may not be accessed by caller %O\n", CALLER) );
}

object connect ( void|string user, void|string password, void|bool dont_reconnect ) {
  check_access();
  last_error = ERROR_NOT_CONNECTED;
  if ( !ldap_activated() ) return 0;

  string bind_dn = "";
  if ( Config.bool_value( config->bindUser ) && stringp(user) ) {
    if ( Config.bool_value(config->bindUserWithoutDN) )
      bind_dn = user;
    else {
      bind_dn = make_dn( config->userAttr + "=" + user, config["userdn"], config["base_dc"] );
    }
  }
  else if ( stringp(config["user"]) && sizeof(config["user"]) > 0 ) {
    // bind with default/root user
    if ( search( config["user"], "=" ) >= 0 )
      bind_dn = config["user"];
    else
      bind_dn = make_dn( "cn="+config["user"] );
    password = config["password"];
  }
  else {  // don't bind at all:
    bind_dn = 0;
  }

  LDAP_LOG("count of open file desciptors: " + sizeof(Stdio.get_all_active_fd()) );
  object ldap;
  mixed err = catch {
    if ( Config.bool_value(config["reuseConnection"]) ||
         config["reconnectTime"] > 0 ) {
      if ( objectp(single_ldap) ) {
        ldap = single_ldap;
      }
    }
    else
      disconnect( single_ldap );
    if ( !objectp(ldap) ) {
      array servers = Config.array_value( config["server"] );
      if ( arrayp(servers) ) {
        foreach ( servers, mixed server ) {
          if ( !stringp(server) || sizeof(server) < 1 ) continue;
          ldap = Protocols.LDAP.client( server );
          if ( objectp(ldap) ) break;
          LDAP_LOG( "failed connection to %s", server );
        }
      }
      if ( objectp(ldap) )
	LDAP_LOG( "new connection: %O", ldap );
    }
  };
  if ( err ) FATAL( "ldap: error while connecting: %O\n", err[0] );
  if ( !objectp(ldap) ) return 0;

  single_ldap = ldap;

  err = catch {
    if ( stringp(bind_dn) && stringp(password) ) {
      if ( bind_dn != last_bind_dn ||
           !verify_crypt_md5( password, last_bind_password_hash ) ) {
        LDAP_LOG( "binding %O", bind_dn );
        if ( !ldap->bind( fix_query_string(bind_dn), password ) )
          throw( "bind failed on " + bind_dn );
        // remember dn and password hash, so we don't need to re-bind if
        // the user and password haven't changed:
        last_bind_dn = bind_dn;
        last_bind_password_hash = make_crypt_md5( password );
      }
    }
    else LDAP_LOG( "using without bind" );
    ldap->set_scope( 2 );
    if ( stringp(config["base_dc"]) && sizeof(config["base_dc"]) )
      ldap->set_basedn( fix_query_string(config["base_dc"]) );
  };
  if ( err != 0 ) {
    string error_msg = "";
    mixed ldap_error_nr = ldap->error_number();
    if ( ldap_error_nr > 0 )
      error_msg = "\n" + ldap->error_string() +
	sprintf( " (#%d)", ldap_error_nr );
    LDAP_LOG( "Failed to bind " + bind_dn + " on ldap" + error_msg );
    if ( ldap_error_nr == 0x31 || // invalid credentials
         ldap_error_nr == 0x30 ) {  // no such object
      disconnect( ldap );
      return 0;
    }
    else {
      disconnect( ldap, true );
      last_error = ERROR_NOT_CONNECTED;
      if ( dont_reconnect ) {
        FATAL("Failed to bind " + bind_dn + " on ldap" + error_msg);
        return 0;
      }
      else
        return connect( user, password, true );  // try to reconnect once
    }
  }
  last_error = NO_ERROR;
  return ldap;
}


void disconnect ( object ldap, void|bool force_disconnect ) {
  check_access();
  last_error = NO_ERROR;
  if ( !objectp(ldap) ) return;
  if ( Config.bool_value(config["reuseConnection"]) ||
       config["reconnectTime"] > 0 ) {
    if ( !force_disconnect ) return;
    single_ldap = 0;
  }
  last_bind_dn = 0;
  last_bind_password_hash = 0;
  
  //removed for pike 7.8: method query_fd() on ldap no longer exists.
//  int fd = ldap->query_fd();
  destruct( ldap );
//  if ( fd > 600 ) {
//    FATAL( "ldap: %d open file descriptors, calling garbage collector...\n",
//            sizeof( Stdio.get_all_active_fd() ) );
//    int time_start = get_time_millis();
//    gc();  // force garbage collection to free ldap file descriptors
//    FATAL( "ldap: garbage collector done, %d open file descriptors remain.\n",
//            sizeof( Stdio.get_all_active_fd() ) );
//    LOG_TIME( time_start, "disconnect[gc]" );
//  }
//  LDAP_LOG( "connection closed (file descriptor was %d)", fd );
}


mapping get_config ()
{
  check_access();
  return config;
}


object get_user_cache () {
  if ( !GROUP("admin")->is_member( this_user() ) ) return 0;
  return user_cache;
}


object get_group_cache () {
  if ( !GROUP("admin")->is_member( this_user() ) ) return 0;
  return group_cache;
}


object get_authorize_cache () {
  if ( !GROUP("admin")->is_member( this_user() ) ) return 0;
  return authorize_cache;
}


mapping get_failed_authorize () {
  if ( !GROUP("admin")->is_member( this_user() ) ) return 0;
  return log_failed_auth;
}

static int hashcode(map userdata)
{
  int hashvalue = 0;
  if (!mappingp(userdata))
    return 0;

  foreach(values(userdata), mixed v) {
    if (stringp(v)) {
      hashvalue += hash(v);
    }
  }
  return hashvalue;
}

static void update_cache() {
  while ( 1 ) {
    // first check if the time is right
    int startUpdate = config->updateCacheStartHour;
    if (!intp(startUpdate))
      startUpdate = 5;

    int hour = 0;
      
    sleep(1800);
    string current_time = ctime(time());
    sscanf(current_time, "%*s %*s %*d %d:%*d:%*d %*s\n", hour);
    LDAP_LOG("Checking update time: Hour = %O, update = %O\n", 
	     hour, startUpdate);

    if ( hour == startUpdate) {
      while ( 1 ) {
	int updateInterval = config->updateCacheInterval;
	
	int time_start = get_time_millis();
	object ldap = connect();
	array(map) users = fetch_users_internal();
	disconnect(ldap);
	foreach(users, mapping user_data) {
	  if (sizeof(user_data) == 0)
	    continue;
	  
	  user_data = fix_charset( user_data );
	  
	  mapping cached_data = user_cache->fetch(user_data[config->userAttr]);
	  if (hashcode(user_data) != hashcode(cached_data)) {
	    LDAP_LOG("User updated in LDAP directory: invalidating user %O\n", 
		     user_data);
	    invalidate_queue->write(user_data);
	  }
	}
	MESSAGE("Invalidating LDAP cache in %d ms, %d updates", 
		get_time_millis() - time_start, invalidate_queue->size());
	sleep(updateInterval*3600);
      }
    }
  }
}


static void init_module()
{
    valid_caller_objects = ({ master() });
    // since ldap is initialized before ldappersistence, we cannot fetch the
    // ldappersistence object yet... we just check against the program path:
    valid_caller_programs = ({ "/modules/ldappersistence", "/modules/auth" });

    last_error = NO_ERROR;
    config = Config.read_config_file( _Server.get_config_dir()+"/modules/ldap.cfg", "ldap" );
    if ( !mappingp(config) ) {
        config = ([ ]);
	MESSAGE("LDAP Service not started - missing configuration !");
        last_error = ERROR_NOT_CONNECTED;
	return; // ldap not started !
    }
    if ( !ldap_activated() ) {
      MESSAGE("LDAP deactivated.");
      last_error = ERROR_NOT_CONNECTED;
      return;  // ldap deactivated
    }

    LDAP_LOG("configuration is %O", config);

    // charset:
    if ( stringp(config["charset"]) && config["charset"] != "utf-8" ) {
      charset_decoder = Locale.Charset.decoder( config["charset"] );
      charset_encoder = Locale.Charset.encoder( "utf-8" );
      if ( !objectp(charset_decoder) || !objectp(charset_encoder) )
        FATAL( "LDAP: could not create a charset converter for %s\n",
                config["charset"] );
    }
    else {
      charset_decoder = 0;
      charset_encoder = 0;
    }

    // caches:
    int cache_time = config["cacheTime"];
    user_cache = LDAPCache( cache_time, fetch_user_internal,
                            user_last_modified, fetch_users_internal );
    group_cache = LDAPCache( cache_time, fetch_group_internal,
                             group_last_modified );
    authorize_cache = LDAPCache( cache_time, authenticate_user_internal,
                                 user_last_modified );

    // log levels:
    if ( stringp(config["logAuthorization"]) ) {
      array a = Config.array_value( config["logAuthorization"] );
      foreach ( a, string s ) {
        switch ( lower_case(s) ) {
          case "failed":
          case "failure":
            log_level_auth |= LOG_AUTH_FAILURE;
            break;
          case "succeeded":
          case "success":
            log_level_auth |= LOG_AUTH_SUCCESS;
            break;
          case "detailed":
          case "details":
            log_level_auth |= LOG_AUTH_DETAILS;
            break;
        }
      }
    }

    // restricted access:
    if ( !zero_type(config->restrictAccess) &&
         !Config.bool_value(config->restrictAccess) )
      restrict_access = false;
    else
      restrict_access = true;
    valid_caller_objects += ({ user_cache, group_cache, authorize_cache });

    if ( stringp(config->notfound) && lower_case(config->notfound) == "create"
         && !config->objectName )
      steam_error("objectName configuration missing !");

    if ( Config.bool_value( config->sync ) ) {
      // if our main dc does not exist - create it
      object ldap = connect();
      mixed err = catch {
        ldap->add( config->base_dc, ([
          "objectclass": ({ "dcObject", "organization" }),
       	  "o": "sTeam Authorization Directory",
          "dc": "steam" ]) );
      };
      if ( err ) FATAL( "ldap: failed to create main dc: %O\n", err[0] );
      disconnect( ldap );
    }
    else {
      // check whether the connection is working
      object ldap;
      string server;
      mixed err = catch {
	array servers = Config.array_value( config["server"] );
        if ( arrayp(servers) ) {
          foreach ( servers, mixed tmp_server ) {
            if ( !stringp(tmp_server) || sizeof(tmp_server) < 1 ) continue;
            server = tmp_server;
            ldap = Protocols.LDAP.client( server );
            if ( objectp(ldap) ) break;
          }
        }
      };
      if ( err ) FATAL( "ldap: error while connecting: %O\n", err[0] );
      if ( objectp(ldap) ) {
	MESSAGE( "LDAP: connected to %s", server );
	disconnect( ldap );
      }
      else {
        last_error = ERROR_NOT_CONNECTED;
	MESSAGE( "LDAP: failed to connect to %s", server );
	werror( "LDAP: failed to connect to %s\n", server );
      }
    }

    if (stringp(config->prefetchUsers)) {
      int time_start = get_time_millis();
      user_cache->pre_fetch();
      MESSAGE("LDAP: pre-fetched " + user_cache->size() + " users in %d ms", 
	      get_time_millis() - time_start);
    }
    if (intp(config->updateCacheInterval)) {
      start_thread(update_cache);
    }
}


void load_module()
{
  if ( ldap_activated() ) {
    add_global_event(EVENT_USER_CHANGE_PW, sync_password, PHASE_NOTIFY);
    add_global_event(EVENT_USER_NEW_TICKET, sync_ticket, PHASE_NOTIFY);
    add_global_event(EVENT_ADD_MEMBER, event_add_member, PHASE_NOTIFY);
    add_global_event(EVENT_REMOVE_MEMBER, event_remove_member, PHASE_NOTIFY);
  }
}


void event_add_member ( int e, object grp, object caller, object member, bool pw ) {
  if ( member->get_object_class() & CLASS_GROUP ) {
    uncache_group( member->get_identifier() );
    uncache_group( grp->get_identifier() );
  }
}


void event_remove_member ( int e, object grp, object caller, object member ) {
  if ( member->get_object_class() & CLASS_GROUP ) {
    uncache_group( member->get_identifier() );
    uncache_group( grp->get_identifier() );
  }
}


private static bool notify_admin ( string msg ) {
  if ( zero_type( config["adminAccount"] ) ) return false;
  object admin = USER( config["adminAccount"] );
  if ( !objectp(admin) ) admin = GROUP( config["adminAccount"] );
  if ( !objectp(admin) ) return false;
  string msg_text = "The following LDAP situation occured on the server "
    + _Server->get_server_name() +" at "+ (ctime(time())-"\n") + " :\n" + msg;
  admin->mail( msg_text, "LDAP on " + _Server->get_server_name(), 0, "text/plain" );
  return true;
}


static mixed map_results(object results)
{
  array result = ({ });
  LDAP_LOG("map_results with " + results->num_entries() + " entries");
  for ( int i = 1; i <= results->num_entries(); i++ ) {
    mapping            data = ([ ]);
    mapping res = results->fetch(i);
   
    if (!mappingp(res)) {
      LDAP_LOG("unable to map result!");
      res = ([ ]);
    }
    foreach(indices(res), string attr) {
      if ( arrayp(res[attr]) ) {
	if ( sizeof(res[attr]) == 1 )
	  data[attr] = res[attr][0];
	else
	  data[attr] = res[attr];
      }
    }
    if ( results->num_entries() == 1 )
      return data;
    result += ({ data });
  }
  return result;
}


int uncache_user ( string user ) {
  if ( !objectp(user_cache) ) return 0;
  LDAP_LOG( "uncaching user %s from user cache", user );
  int dropped = user_cache->drop( user );
  if ( !objectp(authorize_cache) ) return 0;
  LDAP_LOG( "uncaching user %s from authorize cache", user );
  return dropped & authorize_cache->drop( user );
}


int uncache_group ( string group ) {
  if ( !objectp(group_cache) ) return 0;
  LDAP_LOG( "uncaching group %s from group cache", group );
  return group_cache->drop( group );
}


array(mapping) search_data ( string search_str, array result_attributes,
                void|string base_dn, void|string user, void|string pass,
                void|int nr_try ) {
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  if ( !stringp(search_str) || sizeof(search_str) < 1 )
    return UNDEFINED;

  mixed udata;
  object results;
  
  int time_start = get_time_millis();
  
  object ldap;
  if ( Config.bool_value(config->bindUser) && stringp(user) && stringp(pass) )
    ldap = connect(user, pass);
  else
    ldap = connect();

  LDAP_LOG("searching data %s (user %O) : ldap is %O", search_str, user, ldap);

  if ( !objectp(ldap) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_data( search_str, result_attributes, base_dn,
                          user, pass, nr_try+1 );
    }
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  LDAP_LOG("searching data in LDAP: %s\n", search_str);
  if ( base_dn ) {
    ldap->set_basedn( fix_query_string(make_dn( base_dn, config->base_dc )) );
    if ( ldap->error_number() ) {
      if ( nr_try < NR_RETRIES ) {
        disconnect( ldap, true );
        return search_data( search_str, result_attributes, base_dn,
                            user, pass, nr_try+1 );
      }
      FATAL( "ldap: error searching data: %s (#%d)\n",
	      ldap->error_string(), ldap->error_number() );
  }
  }

  mixed err = catch( results = ldap->search( fix_query_string(search_str), result_attributes ) );
  if ( err ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_data( search_str, result_attributes, base_dn,
                          user, pass, nr_try+1 );
    }
    FATAL( "ldap: error searching data: %s\n", err[0] );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  LOG_TIME( time_start, "search_data( %s )", search_str );

  if ( objectp(ldap) && ldap->error_number() ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_data( search_str, result_attributes, base_dn,
                          user, pass, nr_try+1 );
    }
    FATAL( "ldap: Error while searching data: %s (#%d)\n",
	    ldap->error_string(), ldap->error_number() );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  if ( !objectp(results) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_data( search_str, result_attributes, base_dn,
                          user, pass, nr_try+1 );
    }
    FATAL("ldap: Invalid results while searching data.\n");
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
    
  if ( results->num_entries() == 0 ) {
    LDAP_LOG("No matching data found in LDAP directory: %s", search_str);
    disconnect( ldap );
    return ({ });
  }
  
  udata = map_results( results );
  if ( mappingp(udata) ) udata = ({ udata });

  disconnect( ldap );

  LOG_TIME( time_start, "search_data( %s )", search_str );

  if ( !arrayp(udata) ) return 0;
  else return udata;
}


array(string) search_users ( mapping terms, bool any,
                             void|string user, void|string pass ) {
  check_access();
  if ( !mappingp(terms) || sizeof(terms)<1 ) {
    LDAP_LOG( "search_users: invalid terms: %O\n", terms );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  string search_str = "";
  foreach ( indices(terms), mixed attr ) {
    mixed value = terms[attr];
    if ( !stringp(attr) || sizeof(attr) < 1 ||
         !stringp(value) || sizeof(value) < 1 ) continue;
    switch ( attr ) {
      case "login" : attr = config->userAttr; break;
      case "firstname" : attr = config->nameAttr; break;
      case "lastname" : attr = config->fullnameAttr; break;
      case "email" : attr = config->emailAttr; break;
    }
    search_str += "(" + attr + "=" + replace( value, ([ "(":"", ")":"", "=":"", ":":"" ]) ) + ")";
  }
  if ( any ) search_str = "(&(objectclass=" + config->userClass + ")(|" +
               search_str + "))";
  else search_str = "(&(objectclass=" + config->userClass + ")" +
         search_str + ")";

  string base_dn;
  if ( stringp(config->user_dn) ) base_dn = config->user_dn;
  array result = search_data( search_str, ({ config->userAttr }),
                              base_dn, user, pass );
  array users = ({ });
  foreach ( result, mixed res ) {
    if ( mappingp(res) ) {
      res = res[ config->userAttr ];
      if ( stringp(res) && sizeof(res) > 0 )
        users += ({ res });
    }
  }
  return users;
}


/**
 * Returns an array of distinct names of all sub-groups of a group.
 *
 * @param dn the dn of the group of which to return the sub-groups
 * @param recursive if 0 (default) then return only the immediate sub-groups of
 *   the group, otherwise return sub-groups recursively
 * @return an array of dn entries of the sub-groups
 */
array(string) get_sub_groups ( string dn, int|void recursive, void|int nr_try ) {
  //check_access();  // group structures are no privacy data
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  if ( !stringp(dn) || sizeof(dn)<1 ) {
    FATAL( "LDAP: get_subgroups: invalid dn: %O\n", dn );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  mapping group_spec = get_group_spec();
  if ( !mappingp(group_spec) ) {
    LDAP_LOG( "get_sub_groups: no groupAttr/groupClass configured" );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  string group_identifier = dn_to_group_name( dn );
  string group_name = (group_identifier / ".")[-1];

  object results;

  int time_start = get_time_millis();

  object ldap = connect();

  if ( !objectp(ldap) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return get_sub_groups( dn, recursive, nr_try+1 );
    }
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  int old_scope = -1;
  LDAP_LOG( "fetching subgroups of: %s%s\n",
            dn, (recursive ? " (recursive)":"") );
  ldap->set_basedn( fix_query_string(dn) );
  if ( recursive ) old_scope = ldap->set_scope( 2 );
  else old_scope = ldap->set_scope( 1 );
  if ( ldap->error_number() ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return get_sub_groups( dn, recursive, nr_try+1 );
    }
    FATAL( "ldap: error fetching subgroups of %s : %s (#%d)\n", dn,
           ldap->error_string(), ldap->error_number() );
  }
  
  string search_str = "";
  foreach ( values(group_spec), string groupClass )
    search_str += "(objectclass=" + groupClass + ")";
  if ( sizeof(group_spec) > 1 )
    search_str = "(|" + search_str + ")";
  mixed err = catch( results = ldap->search( fix_query_string(search_str) ) );
  if ( err ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return get_sub_groups( dn, recursive, nr_try+1 );
    }
    FATAL( "ldap: error fetching subgroups of %s : %s\n", dn, err[0] );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  LOG_TIME( time_start, "get_subgroups( %s )", dn );

  if ( objectp(ldap) && ldap->error_number() ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return get_sub_groups( dn, recursive, nr_try+1 );
    }
    FATAL( "ldap: Error while fetching subgroups of %s : %s (#%d)\n", dn,
	    ldap->error_string(), ldap->error_number() );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  if ( !objectp(results) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return get_sub_groups( dn, recursive, nr_try+1 );
    }
    FATAL("ldap: Invalid results while fetching subgroups of %s .\n", dn);
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
    
  if ( results->num_entries() == 0 ) {
    disconnect( ldap );
    return ({ });
  }

  array data = map_results(results);
  array dns = ({ });
  foreach ( data, mapping subgroup ) {
    string sub_dn = subgroup["dn"];
    if ( stringp(sub_dn) && sizeof(sub_dn) > 0 ) dns += ({ sub_dn });
  }
  LDAP_LOG( "group %s has %d subgroups", dn, sizeof(dns) );

  if ( old_scope < 0 ) catch( ldap->set_scope( 2 ) );
  else catch( ldap->set_scope( old_scope ) );
  disconnect( ldap );

  return dns;
}


array(string) search_groups ( mapping terms, bool any,
                             void|string user, void|string pass ) {
  check_access();
  if ( !mappingp(terms) || sizeof(terms)<1 ) {
    LDAP_LOG( "search_groups: invalid terms: %O\n", terms );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  mapping group_spec = get_group_spec();
  if ( !mappingp(group_spec) ) {
    LDAP_LOG( "search_groups: cannot search: no groupAttr/groupClass " +
              "configured" );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
  
  string search_str = "";
  foreach ( indices(terms), mixed attr ) {
    mixed value = terms[attr];
    if ( !stringp(attr) || sizeof(attr) < 1 ||
         !stringp(value) || sizeof(value) < 1 ) continue;
    value = replace( value, ([ "(":"", ")":"", "=":"", ":":"" ]) );
    if ( attr == "name" ) {
      string name_search_str = "";
      foreach ( indices( group_spec ), string groupAttr ) {
        string groupClass = group_spec[ groupAttr ];
        name_search_str += "(&(" + groupAttr + "=" + value + ")(objectclass=" +
          groupClass + "))";
      }
      if ( sizeof(group_spec) > 1 )
        name_search_str += "(|" + name_search_str + ")";
      search_str += name_search_str;
    }
    else
      search_str += "(" + attr + "=" + value + ")";
  }
  if ( any ) search_str = "(|" + search_str + ")";
  else search_str = "(&" + search_str + ")";

  string base_dn;
  if ( stringp(config->group_dn) ) base_dn = config->group_dn;
  mixed result = search_data( search_str, ({ "dn" }) + indices(group_spec),
                              base_dn, user, pass );
  if ( !arrayp(result) )
    return ({ });
  array groups = ({ });
  foreach ( result, mixed res ) {
    if ( mappingp(res) ) {
      if ( !stringp(get_group_attr( res, group_spec )) ||
           !stringp(res["dn"]) || res["dn"] == "" )
        continue;
      groups += ({ dn_to_group_name( res["dn"] )  });
    }
  }
  return groups;
}


mapping search_user ( string search_str, void|string user, void|string pass,
                      void|int nr_try )
{
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  if ( !stringp(search_str) || sizeof(search_str)<1 ) {
    FATAL( "LDAP: search_user: invalid search_str: %O\n", search_str );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  mapping udata = ([ ]);
  object results;
  
  int time_start = get_time_millis();
  
  object ldap;
  if ( Config.bool_value(config->bindUser) && stringp(user) && stringp(pass) )
    ldap = connect(user, pass);
  else
    ldap = connect();

  LDAP_LOG("searching %s (user %O) : ldap is %O", search_str, user, ldap);

  if ( !objectp(ldap) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_user( search_str, user, pass, nr_try+1 );
    }
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  LDAP_LOG("looking up user in LDAP: %s\n", search_str);
  if ( config->userdn ) {
    ldap->set_basedn( fix_query_string(make_dn( config->userdn, config->base_dc )) );
    if ( ldap->error_number() ) {
      if ( nr_try < NR_RETRIES ) {
        disconnect( ldap, true );
        return search_user( search_str, user, pass, nr_try+1 );
      }
      FATAL( "ldap: error searching user: %s (#%d)\n",
	      ldap->error_string(), ldap->error_number() );
  }
  }

  mixed err = catch( results = ldap->search( fix_query_string(search_str) ) );
  if ( err ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_user( search_str, user, pass, nr_try+1 );
    }
    FATAL( "ldap: error searching user: %s\n", err[0] );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  LOG_TIME( time_start, "search_user( %s )", search_str );

  if ( objectp(ldap) && ldap->error_number() ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_user( search_str, user, pass, nr_try+1 );
    }
    if ( ldap->error_number() != 32 )  // 32 = no such object
      FATAL( "ldap: Error while searching user: %s (#%d)\n",
             ldap->error_string(), ldap->error_number() );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  if ( !objectp(results) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_user( search_str, user, pass, nr_try+1 );
    }
    FATAL("ldap: Invalid results while searching user.\n");
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
    
  if ( results->num_entries() == 0 ) {
    LDAP_LOG("User not found in LDAP directory: %s", search_str);
    disconnect( ldap );
    return UNDEFINED;
  }

  udata = map_results( results );
  LDAP_LOG( "user %s has dn: %O and %d data entries",
            search_str, udata["dn"], sizeof(indices(udata)) );

  disconnect( ldap );

  LOG_TIME( time_start, "search_user( %s )", search_str );

  return udata;
}


mapping search_group ( string search_str, void|int nr_try )
{
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  if ( !stringp(search_str) || sizeof(search_str)<1 ) {
    FATAL( "LDAP: search_group: invalid search_str: %O\n", search_str );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
  
  mapping gdata = ([ ]);
  object results;

  if ( !mappingp(get_group_spec()) ) {
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  int time_start = get_time_millis();

  object ldap = connect();

  if ( !objectp(ldap) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_group( search_str, nr_try+1 );
    }
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  LDAP_LOG("looking up group in LDAP: %s\n", search_str);
  if ( config->groupdn ) {
    ldap->set_basedn( fix_query_string(make_dn( config->groupdn, config->base_dc )) );
    if ( ldap->error_number() ) {
      if ( nr_try < NR_RETRIES ) {
        disconnect( ldap, true );
        return search_group( search_str, nr_try+1 );
      }
      FATAL( "ldap: error searching group: %s (#%d)\n",
             ldap->error_string(), ldap->error_number() );
    }
  }

  mixed err = catch( results = ldap->search( fix_query_string(search_str) ) );
  if ( err ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_group( search_str, nr_try+1 );
    }
    FATAL( "ldap: error searching group: %s\n", err[0] );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  LOG_TIME( time_start, "search_group( %s )", search_str );

  if ( objectp(ldap) && ldap->error_number() ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_group( search_str, nr_try+1 );
    }
    if ( ldap->error_number() != 32 )  // 32 = no such object
      FATAL( "ldap: Error while searching group: %s (#%d)\n",
             ldap->error_string(), ldap->error_number() );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  if ( !objectp(results) ) {
    if ( nr_try < NR_RETRIES ) {
      disconnect( ldap, true );
      return search_group( search_str, nr_try+1 );
    }
    FATAL("ldap: Invalid results while searching group.\n");
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
    
  if ( results->num_entries() == 0 ) {
    LDAP_LOG("Group not found in LDAP directory: %s", search_str);
    disconnect( ldap );
    return UNDEFINED;
  }

  gdata = map_results(results);
  LDAP_LOG( "group %s has dn: %O", search_str, gdata["dn"] );

  disconnect( ldap );

  return gdata;
}


int user_last_modified ( string identifier, void|string pass )
{
  check_access();
  //TODO: query ldap attribute modifyTimestamp
  return 0;
}


mapping fetch_user ( string identifier, void|string pass )
{
  check_access();
  int time_start = get_time_millis();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }
  if ( !stringp(identifier) ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  LDAP_LOG("fetch_user(%s) %d", identifier, stringp(pass));

  mapping result = user_cache->fetch( identifier, pass );
  if ( !mappingp(result) ) authorize_cache->drop( identifier );
  LOG_TIME( time_start, "fetch_user( %s )", identifier );
  return result;
}


static mapping fetch_user_internal ( string identifier, void|string pass )
{
  check_access();
  LDAP_LOG("fetch_user_internal(%s) %d", identifier, stringp(pass));
  string search_str = "("+config->userAttr+"="+identifier+")";
  if ( stringp(config->userClass) && sizeof(config->userClass)>0 )
    search_str = "(&"+search_str+"(objectclass="+config->userClass+"))";
  mapping result = fix_charset( search_user( search_str, identifier, pass ) );
  if ( !mappingp(result) ) 
    return UNDEFINED;
  if ( lower_case(result[config->userAttr]) != lower_case(identifier) )
    return UNDEFINED;
  else 
    return result;
}


static array(mapping) fetch_users_internal ()
{
  check_access();
  LDAP_LOG("fetch_users_internal()");
  string search_str = "("+config->userAttr+"=*)";
  if ( stringp(config->userClass) && sizeof(config->userClass)>0 )
    search_str = "(&"+search_str+"(objectclass="+config->userClass+"))";
  object ldap = connect();
  if ( !objectp(ldap) )
    return ({ });

  object results = ldap->search (fix_query_string(search_str));
  if ( results->num_entries() == 0 ) {
    LDAP_LOG("No matching data found in LDAP directory: %s", search_str);
    disconnect( ldap );
    return ({ });
  }
  LDAP_LOG("Found %d results", results->num_entries());
  disconnect( ldap );
  return map_results( results );
}

int group_last_modified ( string identifier )
{
  check_access();
  //TODO: query ldap attribute modifyTimestamp
  return 0;
}


mapping fetch_group ( string identifier )
{
  check_access();
  int time_start = get_time_millis();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }
  if ( !stringp(identifier) || sizeof(identifier) < 1 ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  if ( !mappingp(get_group_spec()) ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  LDAP_LOG("fetch_group(%s)", identifier);
  mapping result = group_cache->fetch( identifier );
  LOG_TIME( time_start, "fetch_group( %s )", identifier );
  return result;
}


static mapping fetch_group_internal ( string identifier )
{
  check_access();
  LDAP_LOG("fetch_group_internal(%s)", identifier);
  mapping group_spec = get_group_spec();
  if ( !mappingp(group_spec) ) {
    LDAP_LOG( "fetch_group_internal: could not fetch: no " +
              "groupAttr/groupClass specified in config." );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  array parts = identifier / ".";
  string search_str = "(|";
  foreach ( indices(group_spec), string groupAttr ) {
    search_str += "(&(" + groupAttr + "=" + parts[-1] +
      ")(objectclass=" + group_spec[groupAttr] + "))";
  }
  search_str += ")";
  // sub-groups by structural method are already handled by that query

  // pseudo sub-groups by attribute:
  if ( config->subgroupMethod == "attribute" &&
       stringp(config->groupParentAttr) &&
       sizeof(config->groupParentAttr) > 0 && sizeof(parts) > 1 ) {
    search_str = "(&" + search_str + "(" + config->groupParentAttr +
      "=" + parts[-2] + "))";
  }

  mixed results = fix_charset( search_group( search_str ) );

  if ( config->subgroupMethod == "structural" && arrayp(results) ) {
    string lower_identifier = lower_case( identifier );
    foreach ( results, mapping m ) {
      string result_name = dn_to_group_name( m->dn );
      if ( lower_case( result_name ) == lower_identifier ) {
        results = m;
        break;
      }
    }
  }

  // if there is more than one result, only return one:
  mapping result;
  if ( arrayp(results) ) result = results[0];
  else if ( mappingp(results) ) result = results;
  if ( !mappingp(result) ) return UNDEFINED;
  string identifier_last_part = (identifier / ".")[-1];
  string result_last_part = (dn_to_group_name( result->dn ) / ".")[-1];
  if ( lower_case(result_last_part) != lower_case(identifier_last_part) )
    return UNDEFINED;
  return result;
}

mixed fetch ( string dn, string pattern )
{
  return fetch_scope( dn, pattern, 2 );
}

mixed fetch_scope ( string dn, string pattern, int scope )
{
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }
  if ( !stringp(dn) || !stringp(pattern) ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  // caller must be module...
  if ( !_Server->is_module( CALLER ) )
    steam_error( "Access for non-module denied !" );

  object results;

  object ldap = connect();

  if ( !objectp(ldap) ) {
    last_error = ERROR_NOT_CONNECTED;
    return UNDEFINED;
  }

  ldap->set_scope( scope );
  if ( stringp(dn) && sizeof(dn)>0 ) {
    if ( has_suffix( dn, config->base_dc ) )
      ldap->set_basedn( fix_query_string(dn) );
  else
      ldap->set_basedn( fix_query_string(make_dn( dn, config->base_dc )) );
  }
  else
    ldap->set_basedn( fix_query_string(config->base_dc) );
  if ( ldap->error_number() )
    FATAL( "ldap: error fetching: %s (#%d)\n",
	    ldap->error_string(), ldap->error_number() );

  mixed err = catch( results = ldap->search( fix_query_string(pattern) ) );
  if ( err ) {
    FATAL( "ldap: error fetching: %s\n", err[0] );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  if ( objectp(ldap) && ldap->error_number() ) {
    if ( ldap->error_number() != 32 )  // 32 = no such object
      FATAL( "ldap: Error while fetching: %s (#%d)\n",
             ldap->error_string(), ldap->error_number() );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }

  if ( !objectp(results) ) {
    FATAL("ldap: Invalid results while fetching.\n");
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return UNDEFINED;
  }
    
  if ( results->num_entries() == 0 ) {
    LDAP_LOG("No results when fetching: %s", pattern);
    disconnect( ldap );
    return UNDEFINED;
  }

  disconnect( ldap );

  return map_results( results );
}


array fetch_url ( string url, string additional_filter ) {
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }
  if ( !stringp(url) || sizeof(url) < 1 ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }
  // caller must be module...
  if ( !_Server->is_module( CALLER ) )
    steam_error( "Access for non-module denied !" );

  object results;

  object ldap = connect();

  if ( !objectp(ldap) ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }

  mapping parts = ldap->parse_url( url );
  if ( !mappingp(parts) ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  string basedn = parts["basedn"];
  if ( !stringp(basedn) ) basedn = "";
  string filter = parts["filter"];
  if ( !stringp(filter) ) filter = "";
  if ( sizeof(filter) < 1 && sizeof(basedn) > 0 ) {
    // basedn without filter:
    array basedn_parts = basedn / ",";
    filter = "(" + basedn_parts[0] + ")";
    basedn = basedn_parts[1..] * ",";
  }
  else if ( sizeof(filter) < 1 && sizeof(basedn) < 1 ) {
    last_error = ERROR_UNKNOWN;
    return 0;
  }
  ldap->set_scope( parts["scope"] );
  ldap->set_basedn( fix_query_string(basedn) );
  if ( stringp(additional_filter) && sizeof(additional_filter) > 0 ) {
    if ( !has_prefix( additional_filter, "(" ) )
      additional_filter = "(" + additional_filter;
    if ( !has_suffix( additional_filter, ")" ) )
      additional_filter += ")";
    filter = "(&" + filter + additional_filter + ")";
  }
  mixed err = catch( results = ldap->search( fix_query_string(filter) ) );
  if ( err ) {
    FATAL( "ldap: error fetching url: %s\n", err[0] );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  if ( objectp(ldap) && ldap->error_number() ) {
    if ( ldap->error_number() != 32 )  // 32 = no such object
      FATAL( "ldap: Error while fetching url: %s (#%d)\n",
             ldap->error_string(), ldap->error_number() );
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return 0;
  }

  if ( !objectp(results) ) {
    FATAL("ldap: Invalid results while fetching url.\n");
    disconnect( ldap );
    last_error = ERROR_UNKNOWN;
    return 0;
  }
    
  if ( results->num_entries() == 0 ) {
    LDAP_LOG("No results when fetching url: %s", url);
    disconnect( ldap );
    return ({ });
  }

  disconnect( ldap );

  mixed res = map_results( results );
  if ( mappingp(res) ) res = ({ res });
  return res;
}


string fix_query_string ( string s )
{
  if ( !stringp(s) ) return s;
  string s2 = "";
  for ( int i=0; i<sizeof(s); i++ ) {
    if ( (32 <= (int)s[i]) && ((int)s[i] < 128) ) s2 += s[i..i];
    else s2 += sprintf( "\\%X", (int)s[i] );
  }
  return s2;
}


mixed fix_charset ( string|mapping|array v )
{
  if ( zero_type(v) ) return UNDEFINED;
  if ( !objectp(charset_encoder) || !objectp(charset_decoder) ) return v;
  if ( stringp(v) ) {
    if ( xml.utf8_check(v) ) return v;  // already utf-8
    string tmp = charset_decoder->clear()->feed(v)->drain();
    tmp = charset_encoder->clear()->feed(tmp)->drain();
    // LDAP_LOG( "charset conversion: from \"%s\" to \"%s\".", v, tmp );
    return tmp;
  }
  else if ( arrayp(v) ) {
    array tmp = ({ });
    foreach ( v, mixed i )
      tmp += ({ fix_charset(i) });
    return tmp;
  }
  else if ( mappingp(v) ) {
    mapping tmp = ([ ]);
    foreach ( indices(v), mixed i )
      tmp += ([ fix_charset(i) : fix_charset(v[i]) ]);
    return tmp;
  }
  else return UNDEFINED;
}


static bool check_password(string pass, string user_pw)
{
  if ( !stringp(pass) || !stringp(user_pw) )
    return false;

  LDAP_LOG("check_password()");
  if ( strlen(user_pw) > 5 && lower_case(user_pw[0..4]) == "{sha}" )
    return user_pw[5..] == MIME.encode_base64( sha_hash(pass) );
  if ( strlen(user_pw) > 6 && lower_case(user_pw[0..5]) == "{ssha}" ) {
    string salt = MIME.decode_base64( user_pw[6..] )[20..];  // last 8 bytes is the salt
    return user_pw[6..] == MIME.encode_base64( sha_hash(pass+salt) );
  }
  if ( strlen(user_pw) > 7 && lower_case(user_pw[0..6]) == "{crypt}" )
    return crypt(pass, user_pw[7..]);
  if ( strlen(user_pw) > 4 && lower_case(user_pw[0..3]) == "{lm}" ) {
    return user_pw[4..] == LanManHash.lanman_hash(pass);
  }
  if ( strlen(user_pw) < 3 || user_pw[0..2] != "$1$" ) 
    return crypt(pass, user_pw); // normal crypt check
  
  return verify_crypt_md5(pass, user_pw);
}


bool authorize_ldap ( object user, string pass )
{
  return authenticate_user( user, pass );
}


bool authenticate_user ( object user, string pass )
{
  check_access();
  int time_start = get_time_millis();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return false;
  }

  if ( !objectp(user) )
    steam_error("User object expected for authentication !");

  if ( !stringp(pass) || sizeof(pass)<1 ) {
    last_error = ERROR_UNKNOWN;
    return false;
  }

  string uname = user->get_user_name();

  // don't authenticate restricted users:
  if ( _Persistence->user_restricted( uname ) ) return false;

  string cached = authorize_cache->fetch( uname, pass );

  if ( stringp(cached) && check_password( pass, cached ) ) {
    // successfully authorized from cache
    LDAP_LOG("user %s LDAP cache authorized", uname);
    LOG_TIME( time_start, "authenticate_user[success]( %s )", uname );
    bool log_auth = false;
    if ( log_level_auth & LOG_AUTH_FAILURE ) {
      if ( has_index( log_failed_auth, uname ) ) {
        LOG_AUTH( "%s finally authorized by ldap cache after %d seconds "+
          "(crc: %d)", uname, time()-log_failed_auth[uname], Gz.crc32(pass) );
        m_delete( log_failed_auth, uname );
        log_auth = true;
      }
    }
    if ( log_level_auth & LOG_AUTH_SUCCESS ) {
      LOG_AUTH( "%s authorized by ldap cache (crc: %d)",
                uname, Gz.crc32(pass) );
      log_auth = true;
    }
    return true;
  }

  // failed to authorize from cache
  if ( log_level_auth & LOG_AUTH_FAILURE ) {
    if ( !has_index( log_failed_auth, uname ) ) {
      log_failed_auth[ uname ] = time();
      LOG_AUTH( "%s : %s failed", (ctime(time())-"\n"), uname );
    }
    LOG_AUTH( "%s not authorized by ldap cache (password check) (crc: %d)",
            uname, Gz.crc32(pass) );
  }
  LDAP_LOG("user %s found in LDAP cache - password failed: %O",
           uname, cached);
  LOG_TIME( time_start, "authenticate_user[failed]( %s )", uname );
  return false;
}


static string authenticate_user_internal ( string uname, string pass,
                                           void|int nr_try )
{
  int time_start = get_time_millis();

  // try authorizing via bind:
  if ( Config.bool_value(config->bindUser) &&
       stringp(uname) && sizeof(uname) > 0 &&
       stringp(pass) && sizeof(pass) > 0) {
    object ldap = connect( uname, pass );
    if ( !objectp(ldap) ) {
      if ( nr_try < NR_RETRIES ) {
        disconnect( ldap, true );
        return authenticate_user_internal( uname, pass, nr_try+1 );
      }
    }
    if ( objectp(ldap) ) {
      disconnect( ldap );
      LDAP_LOG("authorized %s via bind", uname);
      LOG_TIME( time_start, "authenticate_user[bind]( %s )", uname );
      string cached_pw = make_crypt_md5( pass );
      bool log_auth = false;
      if ( (log_level_auth & LOG_AUTH_FAILURE) &&
           has_index( log_failed_auth, uname ) ) {
        LOG_AUTH( "%s finally authorized via ldap bind (after %d "+
                "seconds)", uname, time() - log_failed_auth[uname] );
        log_auth = true;
      }
      if ( log_level_auth & LOG_AUTH_SUCCESS ) {
        LOG_AUTH( "%s authorized via ldap bind", uname );
        log_auth = true;
      }
      if ( log_auth && (log_level_auth & LOG_AUTH_DETAILS) )
        LOG_AUTH( "%s password crc32 : %d", uname, Gz.crc32( pass ) );
      return cached_pw;
    }
    else {
      LDAP_LOG("could not authorize %s via bind (no ldap connection)", uname);
      if ( log_level_auth & LOG_AUTH_FAILURE ) {
        LOG_AUTH( "%s not authorized via ldap bind", uname );
        if ( log_level_auth & LOG_AUTH_DETAILS )
          LOG_AUTH( "%s password crc32: %d", uname, Gz.crc32( pass ) );
      }
    }
  }

  // fetch user data and authorize via password:
  mapping udata = fetch_user(uname, pass);
  LDAP_LOG("trying to authorize user %s via password", uname);

  LOG_TIME( time_start, "authenticate_user[fetch]( %s )", uname );

  if ( mappingp(udata) ) {
    object user = USER( uname );
    string dn = udata["dn"];
    if ( !stringp(dn) ) dn = "";

    // check for conflicts (different user in sTeam than in LDAP):
    if (config->checkConflicts && !stringp(user->query_attribute("ldap:dn"))) {
      if ( search(ldap_conflicts,uname)<0 ) {
	ldap_conflicts += ({ uname });
        if ( notify_admin(
	    "Dear LDAP administrator at "+_Server->get_server_name()
	    +",\n\nthere has been a conflict between LDAP and sTeam:\n"
	    +"User \""+uname+"\" already exists in sTeam, but now "
	    +"there is also an LDAP user with the same name/id.\nYou "
	    +"will need to remove/rename one of them or, if they are "
	    +"the same user, you can overwrite the sTeam data from LDAP "
	    +"by adding a \"dn\" attribute to the sTeam user." ) );
	else
	  FATAL( "ldap: user conflict: %s in sTeam vs. %s in LDAP\n", uname, dn );
	return 0;
      }
    }
    else if ( search(ldap_conflicts,uname) >= 0 )
      ldap_conflicts -= ({ uname });

    string ldap_password = udata[config->passwordAttr] || "";
    if ( stringp(config->passwordPrefix) && sizeof(config->passwordPrefix)>0 )
      ldap_password = config->passwordPrefix + ldap_password;

    if ( check_password( pass, ldap_password ) ) {
      // need to synchronize passwords from ldap if ldap is down ?!
      // this is only done when the ldap password is received
      if ( ldap_password != user->get_user_password())
	user->set_user_password(ldap_password, 1);
      LDAP_LOG("user %s authorized via password from LDAP", uname);
      string cached_pw = make_crypt_md5( pass );
      bool log_auth = false;
      if ( (log_level_auth & LOG_AUTH_FAILURE) &&
           has_index( log_failed_auth, uname ) ) {
        LOG_AUTH( "%s finally authorized via password (after %d seconds)",
                  uname, time() - log_failed_auth[uname] );
        log_auth = true;
      }
      if ( log_level_auth & LOG_AUTH_SUCCESS ) {
        LOG_AUTH( "%s authorized via password", uname );
        log_auth = true;
      }
      if ( log_auth && (log_level_auth & LOG_AUTH_DETAILS) )
        LOG_AUTH( "%s password crc32: %d\n* ldap hash: %O",
                uname, Gz.crc32(pass), ldap_password );
      return cached_pw;
    }
    else {
      if ( log_level_auth & LOG_AUTH_FAILURE ) {
        LOG_AUTH( "%s not authorized via password", uname );
        if ( log_level_auth & LOG_AUTH_DETAILS )
          LOG_AUTH( "%s password crc32: %d\n* ldap hash: %O",
                    uname, Gz.crc32(pass), ldap_password );
      }
      LDAP_LOG("user %s found in LDAP directory - password failed!", uname);
      return 0;
    }
  }
  LDAP_LOG("user " + uname + " was not found in LDAP directory.");
  // if notfound configuration is set to create, then we should create a user:
  if ( config->notfound == "create" ) {
    object user = USER( uname );
    if ( add_user( uname, pass, user ) )
      return make_crypt_md5( pass );
  }
  return 0;
}

object sync_user(string name)
{
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }

  // don't sync restricted users:
  if ( _Persistence->user_restricted( name ) )
    return 0;

  mapping udata = fetch_user( name );
  if ( !mappingp(udata) )
    return 0;

  LDAP_LOG("sync of ldap user \"%s\": %O", name, udata);
  object user = get_module("users")->get_value(name);
  string ldap_password = udata[config->passwordAttr];
  if ( stringp(ldap_password) && stringp(config->passwordPrefix) &&
       sizeof(config->passwordPrefix)>0 )
    ldap_password = config->passwordPrefix + ldap_password;
  if ( objectp(user) ) {
    // update user date from LDAP
    if ( ! user->set_attributes( ([
             "pw" : ldap_password,
	     "email" : udata[config->emailAttr],
	     "fullname" : udata[config->fullnameAttr],
	     "firstname" : udata[config->nameAttr],
	     "OBJ_DESC" : udata[config->descriptionAttr],
	   ]) ) )
      FATAL( "LDAP: Could not sync user attributes with ldap for \"%s\".\n", name );
  } else {
    // create new user to match LDAP user
    object factory = get_factory(CLASS_USER);
    user = factory->execute( ([
	     "name" : name,
	     "pw" : udata[config->passwordAttr],
	     "email" : udata[config->emailAttr],
	     "fullname" : udata[config->fullnameAttr],
	     "firstname" : udata[config->nameAttr],
	     "OBJ_DESC" : udata[config->descriptionAttr],
	   ]) );
    user->set_user_password( ldap_password, 1 );
    user->activate_user( factory->get_activation() );
  }
  // sync group membership:
  if ( objectp( user ) ) {
    string primaryGroupId = udata[config->groupId];
    if ( stringp( primaryGroupId ) ) {
      mapping group = search_group("("+config->groupId+"="+primaryGroupId+")");
    }
  }

  return user;
}

object sync_group(string name)
{
  check_access();
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return 0;
  }

  // don't syncronize restricted groups:
  if ( _Persistence->group_restricted( name ) )
    return 0;

  mapping gdata = fetch_group( name );
  if ( !mappingp(gdata) )
    return 0;

  LDAP_LOG("sync of ldap group: %O", gdata);
  //object group = get_module("groups")->lookup(name);
  object group = get_module("groups")->get_value( name );
  if ( objectp(group) ) {
    // group memberships are handled by the persistence manager
    // update group date from LDAP
    group->set_attributes( ([
	     "OBJ_DESC" : gdata[config->descriptionAttr],
	   ]) );
  } else {
    // create new group to match LDAP group
    object factory = get_factory(CLASS_GROUP);
    group = factory->execute( ([
	      "name": name,
	      "OBJ_DESC" : gdata[config->descriptionAttr],
	    ]) );
  }
  return group;
}

static void sync_password(int event, object user, object caller)
{
  if ( !Config.bool_value(config->sync) )
    return;
  string oldpw = user->get_old_password();
  string crypted = user->get_user_password();
  string name = user->get_user_name();
  // don't sync password for restricted users:
  if ( _Persistence->group_restricted( name ) ) return;
  LDAP_LOG("password sync for " + user->get_user_name());

  object ldap;
  string dn;

  if ( Config.bool_value(config->bindUser) && oldpw &&
       objectp(ldap = connect( name, oldpw )) ) {
    if ( config->userdn )
      dn = make_dn(config->userAttr+"="+name, config->userdn, config->base_dc);
    else
      dn = make_dn(config->userAttr+"="+name, config->base_dc);
  }
  else if ( ldap = connect() ) {
    dn = make_dn( config->base_dc, config->userAttr+"="+name );
  }

  if ( !stringp(dn) ) {
    LDAP_LOG("sync_password(): no dn");
    disconnect( ldap );
    return;
  }

  mixed err;
  if ( crypted[..2] == "$1$" )
    crypted = "{crypt}" + crypted;
  err = catch( ldap->modify(dn, ([ config->passwordAttr: ({ 2,crypted }),])) );
  authorize_cache->drop( name );
  user_cache->drop( name );
  LDAP_LOG("sync_password(): %s - %s - %O\n", crypted, dn, ldap->error_string());
  disconnect( ldap );
}

static void sync_ticket(int event, object user, object caller, string ticket)
{
  last_error = NO_ERROR;
  mixed err;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return;
  }
  if ( !Config.bool_value(config->sync) )
    return;
  string name = user->get_user_name();
  string dn = make_dn( config->base_dc, config->userAttr + "=" + name );
  object ldap = connect();
  err = catch( ldap->modify(dn, ([ "userCertificate": ({ 2,ticket }),])) );
  disconnect( ldap );
}

bool is_user(string user)
{
  check_access();
  last_error = NO_ERROR;
  object ldap = connect();
  if ( !objectp(ldap) ) {
    last_error = ERROR_NOT_CONNECTED;
    return false;
  }
  object results = ldap->search( "("+config["userAttr"]+"="+user+")" );
  bool result = (objectp(results) && results->num_entries() > 0);
  disconnect( ldap );
  return result;
}

static bool add_user(string name, string password, object user)
{
  last_error = NO_ERROR;
  if ( !ldap_activated() ) {
    last_error = ERROR_NOT_CONNECTED;
    return false;
  }
  if ( !Config.bool_value(config->sync) ) return false;
  if ( !stringp(config->notfound) || lower_case(config->notfound) != "create" )
    return false;

  // don't add restricted users:
  if ( _Persistence->user_restricted( name ) ) return false;
  
  string fullname = user->get_name();
  string firstname = user->query_attribute(USER_FIRSTNAME);
  string email = user->query_attribute(USER_EMAIL);
  
  mapping attributes = ([
    config["userAttr"]: ({ name }),
    config["fullnameAttr"]: ({ fullname }),
    "objectClass": ({ config["objectName"] }),
    config["passwordAttr"]: ({ make_crypt_md5(password) }),
  ]);
  if ( stringp(firstname) && strlen(firstname) > 0 )
    config["nameAttr"] = ({ firstname });
  if ( stringp(email) && strlen(email) > 0 )
    config["emailAttr"] = ({ email });

  array(string) requiredAttributes =  config["requiredAttr"];
  
  if ( arrayp(requiredAttributes) && sizeof(requiredAttributes) > 0 ) {
    foreach(requiredAttributes, string attr) {
      if ( zero_type(attributes[attr]) )
	attributes[attr] = ({ "-" });
    }
  }
  
  object ldap = connect();
  if ( !objectp(ldap) ) {
    last_error = ERROR_NOT_CONNECTED;
    return false;
  }
  ldap->add( make_dn(config["userAttr"]+"="+name, config["base_dc"]),
             attributes );
  int err = ldap->error_number();
  if ( err != 0 )
    FATAL( "Failed to add user , error is " + ldap->error_string() );
  bool result = ldap->error_number() == 0;
  disconnect( ldap );
  return result;
}


/**
 * Returns the minimum number of milliseconds a connection request must take
 * to appear in the log. Note: if logging is switched off, then this will be
 * the maximum value an integer can take.
 *
 * @return the minimum threshold (in milliseconds) for connection times logging
 */
int get_log_connection_times_min () {
  return log_connection_times_min;
}


/**
 * Returns the maximum number of milliseconds a connection request must take
 * to appear in the log. Note: if no upper threshold is used, then this will be
 * the maximum value an integer can take.
 *
 * @return the maximum threshold (in milliseconds) for connection times logging
 */
int get_log_connection_times_max () {
  return log_connection_times_max;
}


/**
 * Activate or deactivate connection times logging and set the threshold for
 * log entries.
 *
 * @param min_milliseconds the minimum number of milliseconds a connection
 *   request must take to appear in the log (if -1, then logging will be
 *   deaktivated)
 * @param max_milliseconds the maximum number of milliseconds a connection
 *   request must take to appear in the log (if -1, then no upper limit will
 *   be used)
 * @return true if logging is now active, false if it is now not active
 */
bool set_log_connection_times ( int min_milliseconds, void|int max_milliseconds ) {
  if ( min_milliseconds < 0 )
    log_connection_times_min = Int.NATIVE_MAX;
  else
    log_connection_times_min = min_milliseconds;
  if ( zero_type(max_milliseconds) || max_milliseconds < 0 )
    log_connection_times_max = Int.NATIVE_MAX;
  else
    log_connection_times_max = max_milliseconds;
  return log_connection_times_min < Int.NATIVE_MAX &&
    log_connection_times_max >= log_connection_times_min;
}


static int get_time_millis () {
  array tod = System.gettimeofday();
  return tod[0]*1000 + tod[1]/1000;
}


/**
 * Set the log level for authentication logging during runtime.
 * The log levels are:
 * 0 : no logging,
 * 1 : failed authentication,
 * 2 : successful authentication,
 * 3 : failed and successful authentication,
 * 5 : detailed failed authentication (with password hashes in the log),
 * 6 : detailed successful authentication (with password hashes in the log),
 * 7 : detailed failed and successful authentication (with password hashes in
 *     the log).
 *
 * @param log_level authentication log level
 * @return the new log level
 */
int set_authorize_log_level ( int log_level ) {
  log_level_auth = log_level;
  if ( log_level_auth < 1 ) log_failed_auth = ([ ]);
  return log_level_auth;
}


/**
 * Query the authentication log level
 * The log levels are:
 * 0 : no logging,
 * 1 : failed authentication,
 * 2 : successful authentication,
 * 3 : failed and successful authentication,
 * 5 : detailed failed authentication (with password hashes in the log),
 * 6 : detailed successful authentication (with password hashes in the log),
 * 7 : detailed failed and successful authentication (with password hashes in
 *     the log).
 *
 * @return the authentication log level
 */
int get_authorize_log_level () {
  return log_level_auth;
}


/*
void synchronization_thread () {
  while ( 1 ) {
    int cache_time = config["cacheTime"];
    int cache_live_time = config["cacheTime"] * 2;  //TODO: make this configurable
    foreach ( indices( user_cache ), string identifier ) {
      mapping entry = user_cache[ identifier ];
      int t = time();
      if ( t - entry->last_accessed > cache_live_time ) {
        //TODO: drop entry
        continue;
      }
      if ( t - entry->last_synchronized > cache_time ) {
        //TODO: sync entry
      }
    }
    foreach ( indices( group_cache ), string identifier ) {
    }
    foreach ( indices( authorize_cache ), string identifier ) {
    }
    sleep( cacheTime ); //TODO: substract the time needed for sync
  }
}
*/
