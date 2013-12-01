/* Copyright (C) 2005-2008  Thomas Bopp, Thorsten Hampel, Robert Hinn
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
 */

static Thread.Queue saveQueue = Thread.Queue();

#include <macros.h>
#include <assert.h>
#include <attributes.h>
#include <database.h>
#include <config.h>
#include <classes.h>
#include <access.h>
#include <roles.h>
#include <events.h>
#include <exception.h>
#include <types.h>
#include <configure.h>

//#define DEBUG_PERSISTENCE 1

#ifdef DEBUG_PERSISTENCE
#define PDEBUG(s, args...) werror("persistence: "+s+"\n", args)
#else
#define PDEBUG(s, args...)
#endif

#define PROXY "/kernel/proxy.pike"

static mapping config = ([ ]);

static mapping namespaces = ([ ]);
static mapping namespace_types = ([ ]);
static mapping namespace_configs = ([ ]);

static mapping pending_users = ([ ]);
static mapping pending_groups = ([ ]);
static mapping pending_objects = ([ ]);
static array pending_synchronizations = ({ });
static bool dont_create_users = false;  // used by lookup_internal()

static array restricted_users = ({ "root", "service", "postman", "guest" });
static array restricted_groups = ({ "steam", "admin", "coder", "privgroups",
                                    "wikigroups", "help", "everyone" });

static array(string) whitelist_users;
static array(string) whitelist_groups;

static object __Database;
static object root_user;

static int store_content_in_database;
static int store_content_in_filesystem;

static object object_cache = ObjectCache();


class ObjectCacheEntry {
  object proxy;
  int obj_class;
  int obj_id;
  string identifier;

  int time_loaded;
  int time_accessed;
  int time_synchronized;

  int `<(object o) { return time_accessed < o->time_accessed; }
  int `>(object o) { return time_accessed > o->time_accessed; }
  int `==(object o) { return time_accessed == o->time_accessed; }
}

class ObjectCache {
  static mapping by_id = ([ ]);
  static mapping by_proxy = ([ ]);
  static mapping by_identifier = ([ ]);
  static int synchronize_frequency = 30;

  /**
   * Get the synchronization frequency. Objects in the cache will synchronize
   * with data in the persistence layers on their next access when at least
   * this number of seconds have passed.
   *
   * @return the synchronization frequency (number of seconds), 0 means that
   *   objects will synchronize on every access (e.g. lookup).
   */
  int get_synchronize_frequency () {
    return synchronize_frequency;
  }

  /**
   * Set the synchronization frequency. Objects in the cache will synchronize
   * with data in the persistence layers on their next access when at least
   * this number of seconds have passed.
   *
   * @param nr_seconds the number of seconds after which an object is
   *   considered to need synchronization with the persistence layers. If you
   *   set this to 0, then objects will synchronize on each cache access
   *   (e.g. each lookup), which can be quite often and cause delays.
   */
  void set_synchronize_frequency ( int nr_seconds ) {
    synchronize_frequency = nr_seconds;
  }

  /**
   * Finds a cached object and returns its cache entry.
   * This does not touch the object (meaning that it won't update any of
   * its cache times).
   *
   * @param obj the object (or proxy) to look for in the cache
   * @return the ObjectCacheEntry of the cached object, or 0 if no object
   *   was found
   */
  object find_by_proxy ( object obj ) {
    return by_proxy[ obj->this() ];
  }

  /**
   * Finds a cached object by its object id and returns its cache entry.
   * This does not touch the object (meaning that it won't update any of
   * its cache times).
   *
   * @param id the object id of the object to look for in the cache
   * @return the ObjectCacheEntry of the cached object, or 0 if no object
   *   was found
   */
  object find_by_id ( int id ) {
    return by_id[ id ];
  }

  /**
   * Finds a cached object by its identifier. Since multiple objects might
   * have the same identifier, an array of cache entries will be returned,
   * even if there is only one result. If no object is found by that
   * identifier, then 0 will be returned.
   * This does not touch the object (meaning that it won't update any of
   * its cache times).
   *
   * @param id the object id of the object to look for in the cache
   * @return the ObjectCacheEntry of the cached object, or 0 if no object
   *   was found
   */
  array(object) find_by_identifier ( string identifier ) {
    return by_identifier[ identifier ];
  }

  /**
   * Fetches an object in the object cache. If the object was already cached,
   * then its "accessed" time is updated, otherwise it will be cached.
   * If the objects previous access time is older that the synchronization
   * frequency allows, then the object will synchronize with data in the
   * persistence layers. An object that wasn't cached before will always
   * synchronize with the persistence layers by default.
   *
   * @param obj the object (or proxy) to touch (or cache)
   * @param dont_synchronize if true (or != 0) then do not synchronize the
   *   object with the persistence layers, even if its cache age would
   *   require it to.
   * @return the cache entry (type ObjectCacheEntry) of the cached object, or 0
   *   if the object could not be cached (e.g. has no get_identifier() method).
   */
  object fetch ( object obj, bool dont_synchronize ) {
    if ( !objectp(obj) ) return 0;
    // check whether object already is cached:
    object cache_entry = by_proxy[ obj->this() ];
    if ( objectp(cache_entry) ) {
      if ( !dont_synchronize &&
           (time() - cache_entry->time_synchronized >= synchronize_frequency) ) {
        synchronize_object( obj );
        // check whether the object has been deleted by synchronization:
        if ( obj->status() == PSTAT_DELETED ) {
          drop( obj );
          return 0;
        }
        cache_entry->time_synchronized = time();
      }
      cache_entry->time_accessed = time();
      return cache_entry;
    }
    // need to add object to cache:
    if ( !functionp(obj->get_object_class) ||
         !functionp(obj->get_object_id) ||
         !functionp(obj->get_identifier) )
      return 0;
    int obj_class = obj->get_object_class();
    int obj_id = obj->get_object_id();
    string identifier = obj->get_identifier();

    cache_entry = ObjectCacheEntry();
    cache_entry->proxy = obj->this();
    cache_entry->obj_class = obj_class;
    cache_entry->obj_id = obj_id;
    cache_entry->identifier = identifier;
    cache_entry->time_accessed = time();

    by_proxy[ obj->this() ] = cache_entry;
    by_id[ obj_id ] = cache_entry;
    if ( arrayp(by_identifier[identifier]) )
      by_identifier[ identifier ] += ({ cache_entry });
    else
      by_identifier[ identifier ] = ({ cache_entry });
    
    if ( !dont_synchronize ) {
      synchronize_object( obj );
      cache_entry->time_synchronized = time();
    }

    return cache_entry;
  }

  /**
   * Drops a cache entry. If the object wasn't cached then nothing will happen.
   * Note: the object will only be removed from the object cache, it will
   * not be dropped from memory.
   *
   * @param obj the object (or proxy) to remove from the cache
   * @return 1 if the object was found in the cache and dropped, 0 if the
   *  object was not found in the cache
   */
  int drop ( object obj ) {
    if ( !objectp(obj) )
      return 0;
    object cache_entry = find_by_proxy( obj );
    if ( !objectp(cache_entry) )
      return 0;
    m_delete( by_proxy, cache_entry->proxy );
    m_delete( by_id, cache_entry->obj_id );
    array identifier_entry = by_identifier[ cache_entry->identifier ];
    if ( arrayp(identifier_entry) &&
         search( identifier_entry, cache_entry ) >= 0 ) {
      if ( sizeof( identifier_entry ) <= 1 )
        m_delete( by_identifier, cache_entry->identifier );
      else
        by_identifier[ cache_entry->identifier ] -= ({ cache_entry });
    }
    //TODO: really drop the object from memory (and document this)
    return 1;
  }
}


int uncache_object ( object obj ) {
  if ( !objectp( obj ) ) return 0;
  // drop from persistence layer caches:
  foreach( indices(namespaces), mixed idx ) {
    object handler = namespaces[idx];
    if ( functionp( handler["uncache_object"] ) ) {
      mixed err = catch( handler->uncache_object( obj ) );
      if ( err )
        FATAL( "Error while uncaching object %O from namespace %O: %s\n%O\n",
               obj, idx, err[0], err[1] );
    }
  }
  // drop from object cache:
  int res = object_cache->drop( obj );
  PDEBUG( (res ? "uncached" : "could not uncache") + " object %O", obj );
  return res;
}


/**
 * Drops a user from any caches, so that it will receive fresh data on the
 * next lookup. This can be useful if you know that user data has changed in
 * one of the persistence layers and you want the user object to update its
 * data accordingly (before the regular update after the cache times out).
 *
 * @param identifier the identifier (user's login name) of the user that shall
 *   be dropped from cache
 * @return 1 if the user was dropped from the object cache,
 *   0 if it wasn't found in the object cache (regardless of this return value,
 *   the user might have been dropped from any persistence layer caches)
 */
int uncache_user ( string identifier ) {
  // drop from persistence layer caches:
  foreach( indices(namespaces), mixed idx ) {
    object handler = namespaces[idx];
    if ( functionp( handler["uncache_user"] ) ) {
      mixed err = catch( handler->uncache_user( identifier ) );
      if ( err )
        FATAL( "Error while uncaching user %O from namespace %O: %s\n%O\n",
               identifier, idx, err[0], err[1] );
    }
  }
  // drop from object cache:
  array cache_entries = object_cache->find_by_identifier( identifier );
  if ( !arrayp(cache_entries) ) return 0;
  foreach ( cache_entries, object entry ) {
    if ( entry->obj_class & CLASS_USER )
      return uncache_object( entry->proxy );
  }
}


/**
 * Drops a group from any caches, so that it will receive fresh data on the
 * next lookup. This can be useful if you know that group data has changed in
 * one of the persistence layers and you want the group object to update its
 * data accordingly (before the regular update after the cache times out).
 *
 * @param identifier the identifier (full group name with parent groups
 *  separated by ".") of the group that shall be dropped from cache
 * @return 1 if the group was dropped from the object cache,
 *   0 if it wasn't found in the object cache (regardless of this return value,
 *   the group might have been dropped from any persistence layer caches)
 */
int uncache_group ( string identifier ) {
  // drop from persistence layer caches:
  foreach( indices(namespaces), mixed idx ) {
    object handler = namespaces[idx];
    if ( functionp( handler["uncache_group"] ) ) {
      mixed err = catch( handler->uncache_group( identifier ) );
      if ( err )
        FATAL( "Error while uncaching group %O from namespace %O: %s\n%O\n",
               identifier, idx, err[0], err[1] );
    }
  }
  // drop from object cache:
  array cache_entries = object_cache->find_by_identifier( identifier );
  if ( !arrayp(cache_entries) ) return 0;
  foreach ( cache_entries, object entry ) {
    if ( entry->obj_class & CLASS_GROUP )
      return uncache_object( entry->proxy );
  }
}


int is_storing_content_in_database () {
  return store_content_in_database;
}

int is_storing_content_in_filesystem () {
  return store_content_in_filesystem;
}


int get_save_size()
{
  return saveQueue->size();
}

static void create() 
{
  thread_create(save_demon);
}


mixed get_config () {
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may query the persistence config!", E_ACCESS );
  return config;
}


bool get_dont_create_exits () {
  return Config.bool_value(config["dont-create-exits"]);
}


string safe_lower_case ( string s ) {
  if ( !stringp(s) ) return s;
  if ( xml.utf8_check( s ) )
    return string_to_utf8( lower_case( utf8_to_string( s ) ) );
  else
    return lower_case( s );
}


/**
 * Sends an email to the maintainers of namespaces.
 *
 * @param namespace a namespace id or a list of namespace ids whose
 *   maintainers to send the mail to
 * @param subject the subject of the mail
 * @param message the message body
 * @param args arguments to the message body (works with the message body
 *   like sprintf or write)
 */
void mail_maintainer ( array|int namespace, string subject, string message, mixed ... args ) {
  array namespaces;
  if ( arrayp(namespace) ) namespaces = namespace;
  else if ( intp(namespace) ) namespaces = ({ namespace });
  else return;
  
  PDEBUG("Mailing maintainers of %O", namespace);

  string title = "(" + BRAND_NAME + ") " + subject;
  string body = sprintf( message, @args ) + "\n\n"
    + "* Server: " + _Server->get_server_name() + "\n"
    + "* Time: " + ctime(time()) + "\n";
  foreach ( namespaces, int nid ) {
    string namespace_type = search( namespace_types, nid );
    string maintainer = config["maintainer"];
    if ( mappingp(namespace_configs[nid]) )
      maintainer = namespace_configs[nid]["maintainer"];
    if ( !stringp(maintainer) )
      maintainer = config["maintainer"];
    if ( !stringp(maintainer) || sizeof(maintainer)<1 )
      return;  // no maintainer specified, don't send a mail
    array maintainers = Config.array_value( maintainer );
    if ( !arrayp(maintainers) || sizeof(maintainers)<1 )
      return;
    foreach ( maintainers, string maintainer ) {
      object user = USER( maintainer );
      if ( !objectp(user) ) continue;
      PDEBUG("* Mailing maintainer %s of namespace %O\n", user->get_identifier(), nid );
      user->mail( body + sprintf("* Persistence layer type: %O", namespace_type), title, 0, "text/plain" );
    }
  }
}


/** Prepends the namespace part to a given object id. May only be
 * called by namespaces (persistence layers).
 * @param small_oid the small object id (without namespace information)
 * @return the new (complete) object id (or 0 on error)
 */
int make_object_id (int small_oid)
{
  if ( ! is_namespace( CALLER ) ) {
    werror( "Persistence: make_object_id(): Caller is not a namespace: %O\n", CALLER );
    return 0;
  }
  if ( CALLER == __Database ) return small_oid & 0x7fffffff; // 32bit, first bit must be zero
  int nid = search( values(namespaces), CALLER );
  if ( nid < 0 ) {
    werror( "Persistence: make_object_id(): Caller is not registered as a namespace: %O\n", CALLER );
    return 0;
  }
  nid = indices(namespaces)[nid];
  int oid_length = (int)ceil( log( (float)small_oid ) / log( 2.0 ) );
  if ( (oid_length % 8) != 0 ) oid_length = oid_length + 8 - (oid_length % 8);
  oid_length /= 8;  // byte length, not bit length
  if ( oid_length > 0xfff ) {
    werror( "Persistence: make_object_id(): oid too long (%d bytes)\n", oid_length );
    return 0;
  }
  // build namespace part: 1[3bit-reserved][16bit-nid][12bit-oid_length]
  nid = ((0x80000000 | (nid & 0xffff)) << 12) | oid_length;
  // shift left to make room for oid:
  nid = nid << oid_length * 8;
  // cut object id to oid_length bits:
  nid = nid | small_oid;
  return nid;
}


/**
 * @return the namespace id of the persistence layer
 */
int register( string type_name, object handler )
{
  if ( !stringp(type_name) || sizeof(type_name)<1 ) {
    werror( "Namespace tried to register without a valid type name: %O\n", handler );
    return -1;
  }
  if ( !objectp(handler) ) {
    werror( "Namespace '%s' tried to register, but it is not an object: %O\n", type_name, handler );
    return -1;
  }
  if ( !objectp( __Database ) ) {
    if ( !objectp( master()->get_constant("_Database") ) ) {
      werror( "Namespace tried to register, but database hasn't registered, yet!\n");
      return -1;
    }

    __Database = master()->get_constant("_Database");
    namespaces[0] = __Database;
    namespace_types[type_name] = 0;
  }

  int nid = 0;
  if ( handler != __Database ) {
    nid = search( values(namespaces), handler );
    if ( nid >= 0 ) // already registered
      return nid;
    
    nid = 1;
    
    foreach( indices(namespaces), int tmp_nid )
      if ( nid <= tmp_nid ) nid = tmp_nid+1;
    namespaces[nid] = handler;

    if ( !zero_type(namespace_types[type_name]) )
      werror( "Warning: namespace type '%s' already registered for layer %O\n", type_name, namespace_types[type_name] );
    namespace_types[type_name] = nid;
  }

  if ( arrayp(config["layer"]) ) {
    foreach ( config["layer"], mixed layer ) {
      if ( !mappingp(layer) ) continue;
      if ( !stringp(layer["type"]) ) continue;
      if ( layer["type"] == type_name ) {
        namespace_configs[ nid ] = layer;
        break;
      }
    }
  }

  if ( nid != 0 && objectp(GROUP("admin")) ) {
    GROUP("admin")->unlock_attribute("namespaces");
    GROUP("admin")->set_attribute("namespaces", namespaces);
    GROUP("admin")->set_attribute("namespace_types", namespace_types);
    GROUP("admin")->lock_attribute("namespaces");
  }

  return nid;
}


static void save_demon()
{
}


void init ()
{
  config = Config.read_config_file( _Server.get_config_dir()+"/persistence.cfg", "persistence" );
  if ( !mappingp(config) ) {
    config = ([ ]);
    MESSAGE( "No persistence.cfg config file." );
  }
  PDEBUG( "persistence config is %O", config );
  if ( arrayp(Config.array_value(config["restricted-users"])) ) {
    restricted_users = ({ });
    foreach ( Config.array_value( config["restricted-users"] ), string user )
      restricted_users += ({ lower_case( user ) });
  }
  PDEBUG( "restricted users: %O", restricted_users );
  if ( arrayp(Config.array_value(config["restricted-groups"])) ) {
    restricted_groups = ({ });
    foreach ( Config.array_value( config["restricted-groups"] ), string group )
      restricted_groups += ({ lower_case( group ) });
  }
  PDEBUG( "restricted groups: %O", restricted_groups );
  if ( arrayp(Config.array_value(config["whitelist-users"])) ) {
    PDEBUG( "overriding whitelisted users by persistence.cfg" );
    whitelist_users = ({ });
    foreach ( Config.array_value( config["whitelist-users"] ), string user )
      whitelist_users += ({ lower_case( user ) });
  }
  if ( arrayp(Config.array_value(config["whitelist-groups"])) ) {
    PDEBUG( "overriding whitelisted groups by persistence.cfg" );
    whitelist_groups = ({ });
    foreach ( Config.array_value( config["whitelist-groups"] ), string group )
      whitelist_groups += ({ lower_case( group ) });
  }

  store_content_in_database = 1;
  if ( mappingp(config["content"]) ) {
    mixed db_content = config["content"]["database"];
    if ( stringp(db_content) ) {
      switch ( lower_case(db_content) ) {
        case "off":
        case "no":
        case "false":
        case "none":
          store_content_in_database = 0;
          MESSAGE( "Database content storage has been disabled" );
          break;
      }
    }
  }

  store_content_in_filesystem = 0;
  if ( mappingp(config["content"]) && mappingp(config["content"]["filesystem"]) ) {
    mapping server_config = Config.read_config_file( CONFIG_DIR + "/steam.cfg" );
    string content_path = server_config["sandbox"];
    if ( !stringp(content_path) || content_path == "" ) content_path = STEAM_DIR + "/tmp/content";
    else content_path += "/content";

    // check whether to use sandbox directly for content storage:
    if ( stringp(config["content"]["filesystem"]["sandbox"]) &&
         Config.bool_value( config["content"]["filesystem"]["sandbox"] ) ) {
      MESSAGE( "Sandbox content/ subdirectory will be used as content filesystem." );
      store_content_in_filesystem = 1;
    }
    // check whether to mount a filesystem for content storage:
    else if ( stringp(config["content"]["filesystem"]["mount"] ) ) {
      mixed content_dir = get_dir( content_path );
      if ( arrayp(content_dir) && sizeof(content_dir) > 0 ) {
        MESSAGE( "Content filesystem already mounted on %s", content_path );
        store_content_in_filesystem = 1;
      }
      else {
        string tmp_content_path;
        mixed err = catch( tmp_content_path = ContentFilesystem.mount() );
        if ( err )
          FATAL( err[0] );
        else if ( stringp(tmp_content_path) ) {
          MESSAGE( "Content filesystem mounted on %s", content_path );
          content_path = tmp_content_path;
          store_content_in_filesystem = 1;
        }
        // If tmp_content_path is no string but no exception occurred during mount,
        // then filesystem content storage was not enabled.
      }
    }
  }
  
  if ( store_content_in_database )
    MESSAGE( "Content will be stored in and read from database." );
  if ( store_content_in_filesystem )
    MESSAGE( "Content will be stored in and read from filesystem." );
  
  if ( !store_content_in_database && !store_content_in_filesystem )
    steam_error( "Neither database nor filesystem content storage enabled!" );
}

void post_init ()
{
  root_user = USER("root");
  if ( objectp(GROUP("admin")) ) {
    GROUP("admin")->unlock_attribute("namespaces");
    GROUP("admin")->set_attribute("namespaces",namespaces);
    GROUP("admin")->set_attribute("namespace_types",namespace_types);
    GROUP("admin")->lock_attribute("namespaces");
    if ( !arrayp(Config.array_value(config["whitelist-users"])) )
      whitelist_users = GROUP("admin")->query_attribute( "whitelist_users" );
    PDEBUG( "whitelisted users: %O", whitelist_users );
    if ( !arrayp(Config.array_value(config["whitelist-groups"])) )
      whitelist_groups = GROUP("admin")->query_attribute( "whitelist_groups" );
    PDEBUG( "whitelisted groups: %O", whitelist_groups );
  }
  else FATAL( "Could not get \"Admin\" group to store persistence namespace ids and whitelists." );
}


/**
 * @return array { nid, oid_length(bytes), oid }
 */
array split_object_id ( object|int p )
{
  int nid;
  int oid_length;
  int oid;
  if ( intp(p) ) oid = p;
  else if ( objectp(p) ) oid = p->get_object_id();
  else {
    werror("Persistence: split_object_id(): param is not int or object: %O\n", p);
    return UNDEFINED;
  }
  if ( oid < 0 ) return UNDEFINED;
  else if ( oid == 0 ) return ({ 0, 0, 0 });
  if ( (oid & 0x80000000) == 0 ) return ({ 0, 4, oid & 0xffffffff });
  oid_length = (((int)(log( (float)oid ) / log( 2.0 ))) - 31);
  nid = oid >> oid_length;
  oid = oid & ((1 << oid_length) - 1);
  return ({ nid, oid_length/8, oid });
}

object get_namespace(object|int p)
{
  mixed nid = split_object_id( p );
  if ( !arrayp(nid) ) return UNDEFINED;
  return namespaces[ nid[0] ];
}


array get_users_allowed () {
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may list allowed users!", E_ACCESS );
  return whitelist_users;
}


bool user_allowed ( string user )
{
  // restricted users are system users and should always be allowed:
  if ( user_restricted( user ) ) return true;
  // check whitelist:
  if ( arrayp(whitelist_users) && sizeof(whitelist_users) > 0 )
    return search( whitelist_users, safe_lower_case( user ) ) >= 0;
  return true;
}


void add_user_allowed ( string user )
{
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may add allowed users!", E_ACCESS );
  if ( arrayp(Config.array_value(config["whitelist-users"])) )
    return;  // overridden by config file
  if ( !arrayp(whitelist_users) ) whitelist_users = ({ });
  user = safe_lower_case( user );
  if ( search( whitelist_users, user ) < 0 ) whitelist_users += ({ user });
  GROUP("admin")->unlock_attribute( "whitelist_users" );
  GROUP("admin")->set_attribute( "whitelist_users", whitelist_users );
  GROUP("admin")->lock_attribute( "whitelist_users" );
}


void remove_user_allowed ( string user )
{
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may remove allowed users!", E_ACCESS );
  if ( arrayp(Config.array_value(config["whitelist-users"])) )
    return;  // overridden by config file
  if ( !arrayp(whitelist_users) ) return;
  user = safe_lower_case( user );
  whitelist_users -= ({ user });
  GROUP("admin")->unlock_attribute( "whitelist_users" );
  GROUP("admin")->set_attribute( "whitelist_users", whitelist_users );
  GROUP("admin")->lock_attribute( "whitelist_users" );
}


array get_groups_allowed () {
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may list allowed groups!", E_ACCESS );
  return whitelist_groups;
}


bool group_allowed ( string group )
{
  if ( group_restricted( group ) ) return true;
  if ( arrayp(whitelist_groups) && sizeof(whitelist_groups) > 0 )
    return search( whitelist_groups, safe_lower_case( group ) ) >= 0;
  return true;
}


void add_group_allowed ( string group )
{
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may add allowed groups!", E_ACCESS );
  if ( arrayp(Config.array_value(config["whitelist-groups"])) )
    return;  // overridden by config file
  if ( !arrayp(whitelist_groups) ) whitelist_groups = ({ });
  group = safe_lower_case( group );
  if ( search( whitelist_groups, group ) < 0 ) whitelist_groups += ({ group });
  GROUP("admin")->unlock_attribute( "whitelist_groups" );
  GROUP("admin")->set_attribute( "whitelist_groups", whitelist_groups );
  GROUP("admin")->lock_attribute( "whitelist_groups" );
}


void remove_group_allowed ( string group )
{
  if ( !GROUP("admin")->is_member( this_user() ) )
    THROW( "Only administrators may remove allowed groups!", E_ACCESS );
  if ( arrayp(Config.array_value(config["whitelist-groups"])) )
    return;  // overridden by config file
  if ( !arrayp(whitelist_groups) ) return;
  group = safe_lower_case( group );
  whitelist_groups -= ({ group });
  GROUP("admin")->unlock_attribute( "whitelist_groups" );
  GROUP("admin")->set_attribute( "whitelist_groups", whitelist_groups );
  GROUP("admin")->lock_attribute( "whitelist_groups" );
}


bool user_restricted ( string user )
{
  if ( !stringp(user) ) return false;
  // since no users and groups of the same name may exist, check both:
  if ( search( restricted_users | restricted_groups, safe_lower_case( user ) ) >= 0 )
    return true;
  else return false;
}

bool group_restricted ( string group )
{
  if ( !stringp(group) ) return false;
  // since no users and groups of the same name may exist, check both:
  if ( search( restricted_groups | restricted_users, safe_lower_case( group ) ) >= 0 )
    return true;
  else return false;
}

/**
 * creates a new persistent sTeam object.
 *
 * @param  string prog (the class to clone)
 * @return proxy and id for object
 *         note that proxy creation implies creation of associated object.
 * @see    kernel.proxy.create, register_user
 */
mixed new_object(mixed id)
{
  mixed    res;
  string prog_name = master()->describe_program(object_program(CALLER));
  object obj = CALLER;
  foreach(indices(namespaces), mixed idx ) {
    if ( idx == 0 ) 
      continue;
    object handler = namespaces[idx];
    if ( !functionp(handler->new_object) )
      continue;
    if ( res = handler->new_object(id, obj, prog_name) ) {
      return res;
    }
  }
  //TODO: use new_object(id,obj,program) api in database.pike, too
  return namespaces[0]->new_object(obj, prog_name);
}

mapping get_namespaces() 
{
  return namespaces;
}

int get_namespace_id (object ns)
{
  mixed index = search( values(namespaces), ns );
  if ( !intp(index) ) return -1;
  return indices(namespaces)[index];
}

int is_namespace(object ns)
{
  //TODO: ???
  return 1;
}

void set_proxy_status(object p, int status)
{
  if ( is_namespace(CALLER) )
    p->set_status(status);
}

bool delete_object(object p)
{
  if ( object_cache ) 
    object_cache->drop(p);

  object nid = get_namespace(p);
  if ( !objectp(nid) ) {
    werror( "delete_object: invalid namespace for %O\n", p->get_object_id() );
    return false;
  }
  if ( !functionp(nid->delete_object) )
    return false;
  return nid->delete_object(p);
}


/**
 * Synchronizes the object with data in the persistence layers.
 * Right now, this only reads data from the persistence layers and doesn't
 * write back changes.
 * @TODO update data in persistence layers if the object has changed
 *
 * @return true if data in the object has changed, false otherwise
 */
bool synchronize_object ( object obj ) {
  if ( !objectp(obj) || !functionp(obj->get_object_class) )
    return false;
  // prevent cyclic recursion (e.g. through cache lookups):
  if ( search( pending_synchronizations, obj ) >= 0 )
    return false;
  pending_synchronizations += ({ obj });
  // don't create users while synchronizing a user (this prevents
  // creation of other members of the user's groups by lookup):
  if ( obj->get_object_class() & CLASS_USER )
    dont_create_users = true;
  bool result = synchronize_object_internal( obj );
  if ( obj->get_object_class() & CLASS_USER )
    dont_create_users = false;
  pending_synchronizations -= ({ obj });
  return result;
}


/**
 * Used internally by synchronize_object() to prevent cyclic recursions.
 * @see synchronize_object
 */
static bool synchronize_object_internal ( object obj ) {
  if ( !objectp(obj) || !functionp(obj->status) )
    return false;
  int obj_status = obj->status();
  if ( (obj_status != PSTAT_SAVE_OK) && (obj_status != PSTAT_SAVE_PENDING) )
    return false;
  if ( !functionp(obj->get_object_class) || !functionp(obj->get_identifier) )
    return false;
  int obj_class = obj->get_object_class();
  string obj_class_name = "<unknown>";
  if ( objectp(_Server->get_factory( obj_class )) )
    obj_class_name = _Server->get_factory( obj_class )->get_class_name();
  string identifier = obj->get_identifier();
  if ( obj_class & CLASS_USER ) {
    if ( user_restricted( identifier ) ) return false;
  }
  else if ( obj_class & CLASS_GROUP ) {
    if ( group_restricted( identifier ) ) return false;
  }
  else {
    //TODO: right now only users and groups can be synchronized with persistence layers.
    // we will need a mechanism for objects that are restricted to local
    // persistence, or better yet, for objects that can explicitly be
    // synchronized with data from persistence layers...
    return false;
  }

  // prevent cyclic recursion (e.g. through cache lookups):
  pending_synchronizations += ({ obj });

  bool changes = false;
  int obj_namespace = get_namespace_id( get_namespace( obj ) );
  array(int) source_namespaces = ({ });
  array(int) ignore_namespaces = ({ });
  mapping data = ([ ]);
  mapping nonpersistent_attributes = ([ ]);
  array(string) collected_users = ({ });
  array(string) collected_groups = ({ });
  foreach(indices(namespaces), int nid ) {
    if ( nid == obj_namespace ) continue;  // don't load data from object's ns
    object handler = namespaces[nid];
    if ( functionp(handler->supported_classes) &&
         (( handler->supported_classes() & obj_class ) == 0) ) {
      ignore_namespaces += ({ nid });
      continue;
    }
    if ( functionp(handler->load_data) ) {
      mixed res = handler->load_data( obj );
      if ( intp(res) && res < 0 ) {
        // an error occurred, we cannot determine whether the object has data
        // in the namespace:
        ignore_namespaces += ({ nid });
      }
      else if ( mappingp(res) && (res["class"] == obj_class_name) ) {
        if ( !stringp(res["class"]) ) {
          PDEBUG("%s : no class entry in data from %s", identifier,
                 handler->get_identifier());
          continue;
        }
        if ( res["class"] != obj_class_name ) {
          PDEBUG("%s : wrong class '%s' data from %s for object of class '%s'",
                 identifier, res["class"], handler->get_identifier(),
                 obj_class_name);
          continue;
        }
        data |= res;
        if ( mappingp(res["nonpersistent-attributes"]) ) {
          foreach ( indices(res["nonpersistent-attributes"]), mixed nonattr) {
            nonpersistent_attributes[ nonattr ] = handler;
          }
        }
        if ( arrayp(data["users"]) ) {
          foreach( data["users"], string uname ) {
            uname = lower_case( uname );
            if ( search( collected_users, uname ) < 0 )
              collected_users += ({ uname });
          }
        }
        if ( arrayp(data["groups"]) ) {
          foreach( data["groups"], string gname ) {
            gname = lower_case( gname );
            if ( search( collected_groups, gname ) < 0 )
              collected_groups += ({ gname });
          }
        }
        source_namespaces += ({ nid });
      }
    }
  }

  // check if a user has been suspended:
  if ( obj_class & CLASS_USER ) {
    if ( !zero_type(data["suspend"]) ) {
      if ( data["suspend"] ) {
        object auth = get_module( "auth" );
        if ( ! auth->is_user_suspended( obj ) ) {
          auth->suspend_user( obj, true );
          PDEBUG( "suspended user %s", identifier );
        }
      }
      else {
        object auth = get_module( "auth" );
        if ( auth->is_user_suspended( obj ) ) {
          auth->suspend_user( obj, false );
          PDEBUG( "unsuspended user %s", identifier );
        }
      }
    }
  }

  // check appearance, disappearance or reappearance of object in namespaces:
  array old_namespaces = obj->query_attribute( OBJ_NAMESPACES );
  if ( !arrayp(old_namespaces) ) old_namespaces = ({ });
  array ex_namespaces = obj->query_attribute( OBJ_EX_NAMESPACES );
  if ( !arrayp(ex_namespaces) ) ex_namespaces = ({ });

  string obj_type = "object";
  if ( obj_class & CLASS_USER ) obj_type = "user";
  else if ( obj_class & CLASS_GROUP ) obj_type = "group";

  //TODO: check whether the object has appeared and wasn't in the namespace before (the action must be configurable, too), also in lookup!!!
  
  // check whether the object has been removed from namespaces:
  array diff_namespaces = old_namespaces - source_namespaces - ex_namespaces
    - ignore_namespaces;
  if ( arrayp(diff_namespaces) && sizeof( diff_namespaces ) > 0 ) {
    foreach ( diff_namespaces, int nid ) {
      array actions = Config.array_value( config[obj_type+"-disappeared"] );
      if ( mappingp(namespace_configs[nid]) ) {
        array tmp = Config.array_value(
            namespace_configs[nid][obj_type+"-disappeared"] );
        if ( arrayp(tmp) && sizeof(tmp)>0 ) actions = tmp;
      }
      if ( !arrayp(actions) ) actions = ({ });
      // only users can be deactivated:
      if ( (obj_class & CLASS_USER) == 0 ) actions -= ({ "deactivate" });
      actions = reverse( sort( actions ) );  // make sure "warn" comes first
      foreach ( actions, string action ) {
        switch ( action ) {
          case "warn" : {
            mail_maintainer( nid, obj_type + " disappeared",
                "The %s '%s' has disappeared from %O. The following actions"
                + "have been taken: %O", obj_type, identifier,
                namespaces[nid]->get_identifier(), actions );
          } break;
          case "delete" : {
            PDEBUG( "%s '%s' disappeared from namespace %O, deleting.",
                    obj_type, identifier, nid );
            mixed err = catch {
              int del_res = get_factory( CLASS_OBJECT )->delete_for_me( obj );
              PDEBUG( "deleted %s '%s' : %O", obj_type, identifier, del_res );
            };
            if ( err )
              FATAL( "Could not delete disappeared %s '%s': %s\n%O",
                     obj_type, identifier, err[0], err[1] );
            return true;
          } break;
          case "deactivate" :
          case "suspend" : {
            // only users can be deactivated:
            if ( (obj_class & CLASS_USER) == 0 ) break;
            changes = true;
            PDEBUG( "%s '%s' disappeared from namespace %O, suspending.",
                    obj_type, identifier, nid );
            get_module("auth")->suspend_user( obj, true );
          } break;
        }
      }
      ex_namespaces = obj->query_attribute( OBJ_EX_NAMESPACES );
      if ( !arrayp(ex_namespaces) ) ex_namespaces = ({ });
      ex_namespaces += ({ nid });
      obj->set_attribute( OBJ_EX_NAMESPACES, ex_namespaces );
    }
  }
  // check whether the object reappears in new namespaces:
  ex_namespaces = obj->query_attribute( OBJ_EX_NAMESPACES );
  if ( !arrayp(ex_namespaces) ) ex_namespaces = ({ });
  diff_namespaces = ex_namespaces & source_namespaces;
  if ( arrayp(diff_namespaces) && sizeof(diff_namespaces) > 0 ) {
    foreach ( diff_namespaces, mixed nid ) {
      array actions = Config.array_value( config[obj_type+"-reappeared"] );
      if ( mappingp(namespace_configs[nid]) ) {
        array tmp = Config.array_value(
            namespace_configs[nid][obj_type+"-reappeared"] );
        if ( arrayp(tmp) && sizeof(tmp)>0 ) actions = tmp;
      }
      if ( !arrayp(actions) ) actions = ({ });
      // only users can be reactivated:
      if ( (obj_class & CLASS_USER) == 0 ) actions -= ({ "reactivate" });
      actions = reverse( sort( actions ) );  // make sure "warn" comes first
      foreach ( actions, string action ) {
        switch ( action ) {
          case "warn" : {
            mail_maintainer( nid, obj_type + " reappeared",
                "The %s '%s' has reappeared from %O. The following actions"
                + "have been taken: %O", obj_type, identifier,
                namespaces[nid]->get_identifier(), actions );
          } break;
          case "reactivate" :
          case "unsuspend" : {
            changes = true;
            PDEBUG( "%s '%s' reappeared in namespace %O, unsuspending.",
                    obj_type, identifier, nid );
            get_module("auth")->suspend_user( obj, false );
          } break;
          case "delete" : {
            PDEBUG( "%s '%s' reappeared in namespace %O, deleting.",
                    obj_type, identifier, nid );
            obj->delete();
            return true;
          } break;
        }
        ex_namespaces = obj->query_attribute( OBJ_EX_NAMESPACES );
        if ( !arrayp(ex_namespaces) ) ex_namespaces = ({ });
        ex_namespaces -= ({ nid });
        obj->set_attribute( OBJ_EX_NAMESPACES, ex_namespaces );
      }
    }
  }
  
  // sync attributes:
  mixed attributes = data["attributes"];
  if ( mappingp(attributes) && sizeof(attributes) > 0 ) {
    // namespaces are treated separately:
    m_delete( attributes, OBJ_NAMESPACES );
    m_delete( attributes, OBJ_EX_NAMESPACES );
    mixed old_attributes = obj->query_attributes();
    foreach( indices( attributes ), mixed key ) {
      if ( attributes[key] == old_attributes[key] )
        m_delete( attributes, key );
    }
    obj->set_attributes( attributes );
    // email:
    if ( obj_class & CLASS_USER ) {
      mixed new_email = old_attributes[ USER_EMAIL ];
      mixed old_email = old_attributes[ USER_EMAIL ];
      object fwmod = get_module("forward");
      if ( stringp(new_email) && new_email != old_email && objectp(fwmod) ) {
        PDEBUG("updating forwards for %s (USER_EMAIL changed)", identifier);
        if ( stringp(old_email) ) {
          PDEBUG( "deleting old forward for %s : %s", identifier, old_email );
          fwmod->delete_forward( obj, old_email );
        }
        fwmod->add_forward( obj, new_email );
        PDEBUG( "adding new forward for %s : %s", identifier, new_email );
      }
    }
    changes = true;
  }

  // handle non-persistent attributes:
  if ( mappingp(nonpersistent_attributes) &&
       sizeof(nonpersistent_attributes) > 0 ) {
    foreach ( indices(nonpersistent_attributes), mixed nonattr ) {
      mixed nonattr_handler = nonpersistent_attributes[ nonattr ];
      if ( objectp(nonattr_handler) &&
           functionp(nonattr_handler->query_attribute) ) {
        obj->set_acquire_attribute( nonattr, nonattr_handler->this() );
      }
    }
  }
  
  // sync user options:
  if ( obj_class & CLASS_USER ) {
    PDEBUG("syncing user %s %O", identifier, obj );

    // sync password:
    if ( stringp(data["password"]) && sizeof(data["password"]) > 0 ) {
      call_storage_handler( obj->restore_user_data, data["password"],
                            "UserPassword" );
      changes = true;
    }

    // sync group membership:
    if ( arrayp(data["groups"]) ) {
      array groups = data["groups"];
      int crc32 = Gz.crc32( sort(groups) * "," );
      mixed old_crc32 = obj->query_attribute( USER_NAMESPACE_GROUPS_CRC );
      if ( zero_type(old_crc32) )
        old_crc32 = crc32 + 1;  // assume different crc32 by default
      // only sync if groups seem to have changed:
      if ( crc32 != old_crc32 ) {
        PDEBUG( "synchronizing groups of user %s : %O", identifier, groups );
        foreach ( obj->get_groups(), object group ) {
          string group_name = group->get_group_name();
          if ( search( groups, group_name ) >= 0 ) {
            groups -= ({ group_name });  // already member of group
          }
          else if ( lower_case( group_name ) != "steam" ) {
            array group_namespaces = group->query_attribute( OBJ_NAMESPACES );
            if ( ! arrayp(group_namespaces) || sizeof(group_namespaces) < 1 )
              continue;
            group_namespaces -= source_namespaces;
            // only remove user from group if they're from the same namespaces:
            if ( sizeof(group_namespaces) < 1 ) {
              remove_user_from_group( obj, group );
            }
          }
        }
        foreach ( groups, string group_name ) {
          object group = lookup_group( group_name );
          add_user_to_group( obj, group );
        }
        obj->set_attribute( USER_NAMESPACE_GROUPS_CRC, crc32 );
      }
      else
        PDEBUG( "crc32 check: user %s groups don't seem to have changed: %O",
                identifier, (groups * ",") );
    }
    
    // sync active group:
    if ( stringp(data["active_group"]) && sizeof(data["active_group"]) > 0 ) {
      object active_group = lookup_group( data["active_group"] );
      if ( objectp(active_group) &&
           (obj->get_active_group() != active_group) ) {
        if ( !active_group->is_member( obj ) )
          active_group->add_member( obj );
        if ( active_group->is_member( obj ) ) {
          obj->set_active_group( active_group );
          changes = true;
        }
      }
    }
  }

  // sync group options:
  else if ( obj_class & CLASS_GROUP ) {
    PDEBUG("syncing group %s %O", identifier, obj );

    // parent group:
    if ( stringp(data["parentgroup"]) ) {
      PDEBUG( "Group %s : name %O, parent %O\n",
              identifier, data["name"], data["parentgroup"] );
      object parent = obj->get_parent();
      if ( !objectp(parent) ||
           lower_case(parent->get_group_name()) != lower_case(data["parentgroup"]) ) {
        parent = lookup_group( data["parentgroup"] );
        if ( !objectp(parent) )
          FATAL( "Could not find parent group %s for group %s",
                 data["parentgroup"], obj->get_group_name() );
        else {
          PDEBUG("moving group %O to parent group %O", obj, parent);
          get_factory( CLASS_GROUP )->move_group( obj, parent );
        }
      }
    }

    // sync group memberships:
    mixed users = data["users"];
    if ( !arrayp(users) ) users = ({ });
    int crc32 = Gz.crc32( sort(users) * "," );
    mixed old_crc32 = obj->query_attribute( GROUP_NAMESPACE_USERS_CRC );
    if ( zero_type(old_crc32) )
      old_crc32 = crc32 + 1;  // assume different crc32 by default
    // only sync if users seem to have changed:
    if ( crc32 != old_crc32 ) {
      PDEBUG( "synchronizing members of group %s : %O", identifier, users );
      foreach ( obj->get_members(), object user ) {
        if ( !(user->get_object_class() & CLASS_GROUP) ) continue;
        string user_name = user->get_user_name();
        if ( search( users, user_name ) >= 0 ) {
          users -= ({ user_name });  // already member of group
        }
        else {
          array user_namespaces = user->query_attribute( OBJ_NAMESPACES );
          if ( ! arrayp(user_namespaces) || sizeof(user_namespaces) < 1 )
            continue;
          array tmp_namespaces = copy_value( source_namespaces );
          tmp_namespaces -= user_namespaces;
          // only remove user from group if they're from the same namespaces:
          if ( sizeof(tmp_namespaces) < 1 )
            remove_user_from_group( user, obj );
        }
      }
      foreach ( users, string user_name ) {
        object user = lookup_user( user_name );
        add_user_to_group( user, obj );
      }
      obj->set_attribute( GROUP_NAMESPACE_USERS_CRC, crc32 );
    }
    else PDEBUG( "crc32 check: group %s members don't seem to have " +
                 "changed: %O", identifier, users );

    // sync sub groups:
    mixed subgroups = data["groups"];
    if ( !arrayp(subgroups) ) subgroups = ({ });
    crc32 = Gz.crc32( sort(subgroups) * "," );
    old_crc32 = crc32 + 1;  // assume different crc32 by default
    if ( !zero_type(obj->query_attribute( GROUP_NAMESPACE_GROUPS_CRC )) )
      old_crc32 = obj->query_attribute( GROUP_NAMESPACE_GROUPS_CRC );
    // only sync if sub groups seem to have changed:
    if ( crc32 != old_crc32 ) {
      PDEBUG( "synchronizing sub groups of group %s", identifier );
      foreach ( obj->get_sub_groups(), object subgroup ) {
        if ( !(subgroup->get_object_class() & CLASS_GROUP) ) continue;
        string subgroup_name = subgroup->query_attribute( OBJ_NAME );
        if ( !stringp(subgroup_name) ) continue;
        subgroup_name = lower_case( subgroup_name );
        if ( search( subgroups, subgroup_name ) >= 0 ) {
          subgroups -= ({ subgroup_name });  // already sub group of group
        }
        else {
          array subgroup_namespaces = subgroup->query_attribute( OBJ_NAMESPACES );
          if ( ! arrayp(subgroup_namespaces) || sizeof(subgroup_namespaces) < 1 )
            continue;
          array tmp_namespaces = copy_value( source_namespaces );
          tmp_namespaces -= subgroup_namespaces;
          // only remove user from group if they're from the same namespaces:
          if ( sizeof(tmp_namespaces) < 1 ) {
            object privgroups = GROUP( "PrivGroups" );
            if ( objectp(privgroups) ) {
              PDEBUG( "removing sub group %s of group %s (moving to PrivGroups)", subgroup_name, identifier );
              get_factory( CLASS_GROUP )->move_group( subgroup, privgroups );
            }
            // what if we cannot move the group to privgroups?
          }
        }
      }
      foreach ( subgroups, string subgroup_name ) {
        object subgroup = lookup_group( subgroup_name );
        PDEBUG( "adding sub group %s to group %s", subgroup_name, identifier );
        if ( objectp(subgroup) )
          get_factory( CLASS_GROUP )->move_group( subgroup, obj );
      }
      obj->set_attribute( GROUP_NAMESPACE_GROUPS_CRC, crc32 );
    }
    else PDEBUG( "crc32 check: group %s sub groups don't seem to have " +
                 "changed: %O", identifier, subgroups );
  }
  
  // store namespaces that had data:
  mixed err = catch {
    if ( functionp(obj->set_attribute) )
      obj->set_attribute( OBJ_NAMESPACES, source_namespaces );
  };
  if ( err )
    werror( "persistence: synchronize_object() error when trying to store " +
            "source namespaces in %O: %O\n%O\n%O\n",
            obj->get_identifier(), obj, err[0], err[1] );

  if ( changes ) {
    //TODO: update data in the persistence layers if the object has changed
  }
  return changes;
}


int|object load_object(object proxy, int|object iOID)
{
  if ( object_program(CALLER) != (program)PROXY ) 
    error("Security Violation - caller not a proxy object !");
  
  object nid = get_namespace(iOID);
  if ( !objectp(nid) ) {
    werror("Namespace is not an object: %O (proxy: %O)\n", iOID, proxy );
    return UNDEFINED;
  }
  if ( !functionp(nid->load_object) ) return UNDEFINED;
  mixed obj = nid->load_object(proxy, iOID);
  if ( !objectp(obj) ) return obj;

  object cache_entry = object_cache->fetch( obj->this() );
  if ( objectp(cache_entry) )
    cache_entry->time_loaded = time();
  else
    PDEBUG( "could not cache object %O : %O", obj->get_identifier(), obj );

  return obj;
}

mapping get_storage_handlers(object o)
{
    if ( !objectp(o) )
      return ([ ]);
      
    mapping m;
    mixed err = catch {
      m = o->get_data_storage();
    };
    if ( err ) {
      FATAL("Error calling get_data_storage in %O ", o);
      FATAL("Error: %O\n%O", err[0], err[1]);
      return ([ ]);
    }
    return m;
}

mixed call_storage_handler(function f, mixed ... params)
{
  mixed res = namespaces[0]->call_storage_handler(f, @params);
  return res;
}


int check_read_attribute(object user, string attribute)
{
  mixed err = catch(user->check_read_attribute(attribute, 
					       geteuid()||this_user()));
  if ( err ) {
    if ( sizeof(err) == 3)
      return 0;
    FATAL("Error while checking for readable attribute %O of %O\n%O:%O",
	  attribute, user, err[0], err[1]);
  }
  return 1;
}

static int check_read_user(object user, mapping terms) 
{
  // check if user data are still ok ?!
  array attribute = ({ });
  foreach ( indices(terms), string key) {
    switch(key) {
    case "firstname": 
      attribute += ({ USER_FIRSTNAME });
      break;
    case "lastname":
      attribute += ({ USER_LASTNAME });
      break;
    case "login":
      attribute += ({ OBJ_NAME });
      break;
    case "email":
      attribute += ({ USER_EMAIL });
      break;
    }
  }
  if (sizeof(attribute)>0) {
    foreach(attribute, string a)
      if ( check_read_attribute(user, a) == 0 )
	return 0;
  }
  return 1;
}


int get_content_size ( int content_id ) {
  int content_size;

  if ( store_content_in_filesystem ) {
    content_size = Stdio.file_size( _Server->get_sandbox_path() + "/content/" +
                          ContentFilesystem.content_id_to_path( content_id ) );
    if ( content_size >= 0 ) return content_size;
  }

  if ( store_content_in_database ) {
    object oHandle = __Database->new_db_file_handle( content_id, "r" );
    content_size = oHandle->sizeof();
    destruct( oHandle );
  }

  return content_size;
}


string get_content ( int content_id, int|void length ) {
  string content;

  if ( store_content_in_filesystem ) {
    if ( length )
      content = Stdio.read_file( _Server->get_sandbox_path() + "/content/" +
             ContentFilesystem.content_id_to_path( content_id ), 0, length );
    else
      content = Stdio.read_file( _Server->get_sandbox_path() + "/content/" +
                        ContentFilesystem.content_id_to_path( content_id ) );
    if ( stringp(content) )
      return content;
  }

  if ( store_content_in_database ) {
    object db_handle = __Database->new_db_file_handle( content_id, "r" );
    content = db_handle->read( length );
    destruct( db_handle );
  }
  return content;
}


int set_content ( string content ) {
  object oHandle = __Database->new_db_file_handle( 0, "wct" );
  int content_id = oHandle->dbContID();

  if ( store_content_in_filesystem ) {
    string path = _Server->get_sandbox_path() + "/content/" +
      ContentFilesystem.content_id_to_path( content_id );
    Stdio.mkdirhier( dirname( path ) );
    Stdio.write_file( path, content );
  }
  
  if ( store_content_in_database )
    oHandle->write_now( content );

  oHandle->close();
  destruct( oHandle );
  return content_id;
}


void delete_content ( int content_id ) {
  if ( store_content_in_filesystem )
    rm( _Server->get_sandbox_path() + "/content/" +
        ContentFilesystem.content_id_to_path( content_id ) );

  if ( store_content_in_database ) {
    object oHandle = __Database->new_db_file_handle( content_id, "wct" );
    oHandle->close();
  }
}


/**
 * Open a file, return a file object or zero, called from get_content_file
 * in Document.pike
 *
 * @return an open Stdio.File
 */
object open_content_file(int content_id, string mode, void|mapping vars, void|string client)
{
  if ( store_content_in_filesystem ) {
    mixed err = catch {
      return Stdio.File( _Server->get_sandbox_path() + "/content/" +
                  ContentFilesystem.content_id_to_path( content_id ), mode );
    };
    if ( err ) PDEBUG( "Couldn't open content file: %s\n", err[0] );
  }
  return 0;
}


array(string) search_user_names ( mapping terms, bool any, string|void wildcard ) {
  array users = ({ });
  foreach ( indices(namespaces), mixed idx ) {
    object handler = namespaces[idx];
    if ( (handler->supported_classes() & CLASS_USER) == 0 )
      continue;
    if ( functionp(handler->search_users) ) {
      array a = handler->search_users( terms, any, wildcard );
      if ( !arrayp(a) || sizeof(a) < 1 ) continue;
      users += a;
    }
  }
  return Array.uniq( users );
}


/**
 * Searches for users in the persistence layers.
 *
 * @param terms a mapping ([ attrib : value ]) where attrib can be "firstname",
 *   "lastname", "login" or "email" and value is the text ot search for in the
 *   attribute. If the values contain wildcards, specify the wildcard character
 *   in the wildcard param.
 * @param any true: return all users that match at least one of the terms
 *   ("Or"), false: return all users that match all of the terms ("and").
 * @param wildcard a string containing the wildcard used in the search term
 *   values, or 0 (or unspecified) if no wildcards are used
 * @return an array of matching user objects
 */
array(object) lookup_users( mapping terms, bool any, string|void wildcard ) {
  array users = ({ });
  //foreach ( indices(namespaces), mixed idx ) {
  for ( mixed idx = 0; idx == 0; idx ++ ) {  // only search in database!!!
    object handler = namespaces[idx];
    if ( (handler->supported_classes() & CLASS_USER) == 0 )
      continue;
    if ( functionp(handler->search_users) ) {
      array a = handler->search_users( terms, any, wildcard );
      if ( arrayp(a) && sizeof(a) > 0 ) {
        foreach ( a, string name ) {
          object user = lookup_user( name );
          if ( objectp(user) && 
	       search( users, user ) < 0 && 
	       check_read_user(user, terms))
            users += ({ user });
        }
      }
    }
  }
  return users;
}


array(string) search_group_names ( mapping terms, bool any, string|void wildcard ) {
  array groups = ({ });
  foreach ( indices(namespaces), mixed idx ) {
    object handler = namespaces[idx];
    if ( (handler->supported_classes() & CLASS_GROUP) == 0 )
      continue;
    if ( functionp(handler->search_groups) ) {
      array a = handler->search_groups( terms, any, wildcard );
      if ( !arrayp(a) || sizeof(a) < 1 ) continue;
      groups += a;
    }
  }
  return Array.uniq( groups );
}


/**
 * Searches for groups in the persistence layers.
 *
 * @param terms a mapping ([ attrib : value ]) where attrib can be "name"
 *   and value is the text ot search for in the attribute.
 *   If the values contain wildcards, specify the wildcard character in the
 *   wildcard param.
 * @param any true: return all groups that match at least one of the terms
 *   ("or"), false: return all groups that match all of the terms ("and").
 * @param wildcard a string containing the wildcard used in the search term
 *   values, or 0 (or unspecified) if no wildcards are used
 * @return an array of matching group objects
 */
array(object) lookup_groups ( mapping terms, bool any, string|void wildcard ) {
  array groups = ({ });
  //foreach ( indices(namespaces), mixed idx ) {
  for ( mixed idx = 0; idx == 0; idx ++ ) {  // only search in database!!!
    object handler = namespaces[idx];
    if ( (handler->supported_classes() & CLASS_GROUP) == 0 )
      continue;
    if ( functionp(handler->search_groups) ) {
      array a = handler->search_groups( terms, any, wildcard );
      if ( arrayp(a) && sizeof(a) > 0 ) {
        foreach ( a, string name ) {
          object group = lookup_group( name );
          if ( objectp(group) && search( groups, group ) < 0 )
            groups += ({ group });
        }
      }
    }
  }
  return groups;
}


object lookup ( string identifier ) {
  if ( !stringp(identifier) || sizeof(identifier) < 1 ) return 0;
  if ( has_index( pending_objects, identifier ) ) {
    PDEBUG("pending object %s : %O", identifier, pending_objects[identifier]);
    return pending_objects[identifier];
  }
  return lookup_internal( identifier, CLASS_OBJECT );
}


object lookup_user ( string identifier, void|string password ) {
  if ( !stringp(identifier) || sizeof(identifier) < 1 ) return 0;
  if ( has_index( pending_users, identifier ) ) {
    PDEBUG("pending user %s : %O", identifier, pending_users[identifier]);
    return pending_users[identifier];
  }
  if ( user_restricted( identifier ) )
    return namespaces[0]->lookup_user( identifier );
  return lookup_internal( identifier, CLASS_USER, password );
}


object lookup_group ( string identifier ) {
  if ( !stringp(identifier) || sizeof(identifier) < 1 ) return 0;
  if ( has_index( pending_groups, identifier ) ) {
    PDEBUG("pending group %s : %O", identifier, pending_groups[identifier]);
    return pending_groups[identifier];
  }
  if ( group_restricted( identifier ) )
    return namespaces[0]->lookup_group( identifier );
  return lookup_internal( identifier, CLASS_GROUP );
}


static object lookup_internal ( string identifier, int obj_class, void|string password ) {
  // check whether object is cached:
  array cache_entries = object_cache->find_by_identifier( identifier );
  if ( arrayp(cache_entries) ) {
    foreach ( cache_entries, object entry ) {
      if ( entry->obj_class & obj_class ) {
        //TODO: check whether object is "fresh", otherwise don't use cache
        object_cache->fetch( entry->proxy );
        return entry->proxy;
      }
    }
  }

  // find object in persistence layers:
  mixed res = 0;
  foreach(indices(namespaces), mixed idx ) {
    object handler = namespaces[idx];
    if ( (handler->supported_classes() & obj_class) == 0 )
      continue;
    string lookup_func = "lookup";
    string lookup_data_func = "lookup_data";
    if ( obj_class & CLASS_USER ) {
      lookup_func = "lookup_user";
      lookup_data_func = "lookup_user_data";
    }
    else if ( obj_class & CLASS_GROUP ) {
      lookup_func = "lookup_group";
      lookup_data_func = "lookup_group_data";
    }
    if ( functionp(handler[lookup_func]) ) {
      mixed tmp_res = handler[lookup_func]( identifier );
      if ( objectp(tmp_res) ) {
        // only proxies are cached, not the objects themselves:
        res = tmp_res->this();
        // do a cache fetch so that the data can be updated if out of date:
        object_cache->fetch( res );
        return res;
      }
    }
    else if ( functionp( handler[lookup_data_func] ) ) {
      if ( !res ) res = handler[lookup_data_func]( identifier );
    }
    else PDEBUG( "No lookup methods in layer %O (%O)", idx, handler->get_identifier() );
  }

  mixed requested_identifier = identifier;
  if ( mappingp(res) && stringp(res["name"]) && sizeof(res["name"]) != 0 ) {
    if ( stringp(res["parentgroup"]) && sizeof(res["parentgroup"]) != 0 )
      identifier = res["parentgroup"] + "." + res["name"];
    else
      identifier = res["name"];
  }
  // if we found only partial data, then we need to create a new object:
  //TODO: make this configurable! You might not want to automatically create new objects in all layers!
  if ( dont_create_users && (obj_class == CLASS_USER) )
    return 0;
  if ( (obj_class == CLASS_USER) && !user_allowed( identifier ) ) {
    PDEBUG("lookup: user not allowed: %O", identifier);
    return 0;
  }
  if ( (obj_class == CLASS_GROUP) && !group_allowed( identifier ) ) {
    PDEBUG("lookup: group not allowed: %O", identifier);
    return 0;
  }
  if ( mappingp(res) ) {
    PDEBUG( "lookup: found data for %O, creating object %O",
            requested_identifier, identifier );
    object factory;
    if ( !stringp(res["class"]) ||
         !objectp(factory = get_factory(res["class"])) ) {
      werror( "persistence: cannot create object for %s : invalid class: %O\n",
              identifier, res["class"] );
      return 0;
    }
    mapping factory_params = ([ "name":identifier ]) | res;
    if ( (factory_params["class"] == CLASS_NAME_USER) &&
         !stringp(factory_params["pw"]) &&
         !stringp(factory_params["pw:crypt"]) )
      factory_params["pw:crypt"] = "{NOPASSWORD}";
    if ( (factory_params["class"] == CLASS_NAME_GROUP) &&
         stringp(factory_params["parentgroup"]) ) {
      factory_params["parentgroup"] = lookup_group( factory_params["parentgroup"] );
      if ( !objectp( factory_params["parentgroup"] ) )
        return 0;
    }
    if ( obj_class & CLASS_USER ) pending_users[identifier] = 0;
    else if ( obj_class & CLASS_GROUP ) pending_groups[identifier] = 0;
    else pending_objects[identifier] = 0;
    object obj = factory->execute( factory_params );
    if ( obj_class & CLASS_USER ) m_delete( pending_users, identifier );
    else if ( obj_class & CLASS_GROUP ) m_delete( pending_groups, identifier );
    else m_delete( pending_objects, identifier );
    if ( !objectp(obj) ) {
      werror( "persistence: failed to create object for %s\n", identifier );
      return UNDEFINED;
    }
    obj = obj->this();
    if ( obj_class & CLASS_USER )
      obj->activate_user( factory->get_activation() );
    if ( mappingp(res["attributes"]) )
      obj->set_attributes( res["attributes"] );
    // synchronize object for the first time:
    object_cache->fetch( obj );
    return obj;
  }

  if ( !objectp(res) )
    res = namespaces[0]->lookup(identifier);
  if ( objectp(res) )
    object_cache->fetch( res );
  return res;
}


static void add_user_to_group ( object user, object group )
{
  if ( !objectp(user) || !objectp(group) )
    return;

  PDEBUG( "adding user %s to group %s", user->get_identifier(),
          group->get_identifier() );
  group->add_member( user );

  object user_workroom = user->query_attribute(USER_WORKROOM);
  object group_workroom = group->query_attribute(GROUP_WORKROOM);
  if ( !objectp(user_workroom) || !objectp(group_workroom) )
    return;

  // add exit to the group workroom if it doesn't exist:
  if ( get_dont_create_exits() )
    return;  // configured not to create exits
  foreach ( user_workroom->get_inventory_by_class(CLASS_EXIT), object gate ) {
    if ( gate->get_exit() == group_workroom )
      return;  // exit already exists
  }
  object exit_factory = get_factory(CLASS_EXIT);
  if ( !objectp(exit_factory) ) {
    werror( "Persistence: Could not get ExitFactory.\n" );
    return;
  }
  object gate = exit_factory->execute( ([
                                         "name":group_workroom->get_identifier(),
                                         "exit_to":group_workroom
                                         ]) );
  if ( objectp(gate) )
    gate->move( user_workroom );
  else
    werror( "Persistence: Could not move exit to group workroom to users workarea:\nUser: %O, Group: %O\n", user, group );
}


static void remove_user_from_group ( object user, object group )
{
  if ( !objectp(user) || !objectp(group) )
    return;

  PDEBUG( "removing user %s from group %s", user->get_identifier(),
          group->get_identifier() );
  group->remove_member( user );  // not member of group anymore

  // check whether an exit to the group workroom needs to be removed:
  object user_workroom = user->query_attribute(USER_WORKROOM);
  object group_workroom = group->query_attribute(GROUP_WORKROOM);
  if ( !objectp(user_workroom) || !objectp(group_workroom) )
    return;
  foreach ( user_workroom->get_inventory_by_class(CLASS_EXIT), object gate ) {
    if ( gate->get_exit() == group_workroom )
      gate->delete();
  }
}


final object find_object(int|string iOID)
{
    object namespace;
    if ( stringp(iOID) )
	return namespaces[0]->find_object(iOID);
    namespace = get_namespace(iOID);
    if ( !objectp(namespace) || !functionp(namespace->find_object) )
        return UNDEFINED;
    return namespace->find_object(iOID);
}


// requires saving an object
void require_save(void|string ident, void|string index)
{
  object proxy = CALLER->this();
  object nid = get_namespace(proxy);
  if ( !objectp(nid) )
    werror( "require_save: invalid namespace\n" );
  if ( !functionp(nid->require_save) )
    return;
  nid->require_save(proxy, ident, index);
}


static void
save_object(object proxy, void|string ident, void|string index)
{
}

int change_object_class(object proxy, string newClass) 
{
    if ( !_Server->is_a_factory(CALLER) )
	steam_error("Illegal call to Persistence.change_object_class !");
    object nid = get_namespace(proxy);
    if ( !objectp(nid) )
      steam_error("Persistence.change_object_class failed: no namespace found!");
    if ( !functionp(nid->change_object_class) ) {
      FATAL("No function change_object_class in %O\n", nid);
      return false;
    }
    return nid->change_object_class(proxy, newClass);
}


void user_renamed ( object user, string old_name, string new_name ) {
  uncache_object( user );
  array errors = ({ });
  foreach ( indices(namespaces), mixed idx ) {
    if ( idx == 0 ) continue;
    object handler = namespaces[idx];
    if ( !functionp(handler->user_renamed) ) continue;
    handler->user_renamed( user, old_name, new_name );
  }
}


void group_renamed ( object group, string old_name, string new_name ) {
  uncache_object( group );
  foreach ( indices(namespaces), mixed idx ) {
    if ( idx == 0 ) continue;
    object handler = namespaces[idx];
    if ( !functionp(handler->group_renamed) ) continue;
    handler->group_renamed( group, old_name, new_name );
  }
}


string get_identifier() { return "PersistenceManager"; }
string describe() { return "PersistenceManager"; }
string _sprintf() { return "PersistenceManager"; }
