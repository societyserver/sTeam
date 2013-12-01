/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 */
//inherit "/kernel/module";
//inherit "/kernel/secure_mapping.pike";
inherit "/kernel/persistence_partial.pike";

#include <macros.h>
#include <classes.h>
#include <database.h>
#include <exception.h>
#include <attributes.h>
#include <configure.h>

//#define LDAPPERSISTENCE_DEBUG 1

#ifdef LDAPPERSISTENCE_DEBUG
#define LDAPPERS_LOG(s, args...) werror("ldappersistence: "+s+"\n", args)
#else
#define LDAPPERS_LOG(s, args...)
#endif

#define DEPENDENCIES cache ldap

string get_identifier() { return "persistence:ldap"; }
object get_environment() { return 0; }

static object ldap;
static mapping    config;

static int persistence_id;
static int oid_length = 4;  // nr of bytes for object id

static object user_cache;
static object group_cache;
static int cache_time = 0;

static bool restrict_access = true;
static array valid_caller_objects = ({ });


int supported_classes () {
  // ldap only supports users and groups:
  return CLASS_USER | CLASS_GROUP;
}


bool check_access ( void|string identifier ) {
  if ( !restrict_access ) return true;
  // check objects:
  if ( search( valid_caller_objects, CALLER ) >= 0 ) return true;
  // an object (user/group) may request its own information:
  if ( stringp(identifier) && functionp(CALLER->get_identifier) &&
       CALLER->get_identifier() == identifier ) return true;
  // if caller is not valid, throw an exception:
  steam_error( sprintf("ldap may not be accessed by caller %O\n", CALLER) );
}


static void init_module()
{
  valid_caller_objects = ({ _Persistence });

  ldap = get_module("ldap");
  if ( !objectp(ldap) ) {
    MESSAGE("Could not get LDAP module.");
    FATAL("Could not get LDAP module.");
    return;
  }

  if ( !ldap->ldap_activated() ) {
    MESSAGE("LDAP deactivated.");
    return;  // ldap deactivated
  }

  config = ldap->get_config();
  if ( !mappingp(config) ) {
    MESSAGE("LDAP persistence not started - missing configuration !");
    return;
  }

  // restricted access:
  if ( !zero_type(config->restrictAccess) &&
       !Config.bool_value(config->restrictAccess) )
    restrict_access = false;
  else
    restrict_access = true;

  persistence_id = _Persistence->register( "ldap", this_object() );

  if ( intp(config->cacheTime) )
    cache_time = config->cacheTime;
  else if ( !stringp(config->cacheTime) || (sscanf(config->cacheTime, "%d", cache_time) < 1) )
    cache_time = 0;
  user_cache = get_module("cache")->create_cache( "ldappersistence:users", cache_time );
  group_cache = get_module("cache")->create_cache("ldappersistence:groups", cache_time );
}

int get_persistence_id ()
{
  return persistence_id;
}


mapping|int lookup_user_data ( string identifier, void|string password )
{
  check_access( identifier );
  if ( !objectp(ldap) || !ldap->ldap_activated() )
    return -1;

  LDAPPERS_LOG( "lookup_user_data(%s)", identifier );

  mixed data = ldap->fetch_user( identifier, password );

  if ( !mappingp(data) ) {
    if ( ldap->get_last_error() != 0 ) return -1;
    else return 0;
  }

  mixed exc = catch {

  mapping result = ([ "class":CLASS_NAME_USER ]);
  if ( stringp(config->userAttr) && stringp(data[config->userAttr]) &&
       sizeof(data[config->userAttr])>0 )
    result["name"] = data[config->userAttr];
  else
    result["name"] = identifier;
  if ( stringp(data[config->passwordAttr]) && sizeof(data[config->passwordAttr])>0 ) {
    if ( stringp(config->passwordPrefix) && sizeof(config->passwordPrefix)>0 )
      result["pw"] = config->passwordPrefix + data[config->passwordAttr];
    else
    result["pw"] = data[config->passwordAttr];
  }
  if ( stringp(data[config->emailAttr]) && sizeof(data[config->emailAttr])>0 )
    result["email"] = data[config->emailAttr];
  if ( stringp(data[config->fullnameAttr]) && sizeof(data[config->fullnameAttr])>0 )
    result["fullname"] = data[config->fullnameAttr];
  if ( stringp(data[config->nameAttr]) && sizeof(data[config->nameAttr])>0 )
    result["firstname"] = data[config->nameAttr];

  // check whether the user has been suspended:
  string suspend_attr = config->suspendAttr;
  if ( stringp(suspend_attr) && sizeof(suspend_attr) > 0 ) {
    array suspend_values = Config.array_value( config->suspendAttrValue );
    string value = data[suspend_attr];
    if ( value ) {
      if ( !arrayp(suspend_values) ||
           (search( suspend_values, value ) >= 0) )
        result["suspend"] = 1;
      else
        result["suspend"] = 0;
    }
    else if ( !zero_type(value) )
      result["suspend"] = 0;
  }

  return result;

  };
  if ( exc != 0 ) werror( "LDAP: lookup_user_data(\"%s\") : %O\n", identifier, exc );
}


mapping|int lookup_group_data ( string identifier )
{
  check_access( identifier );
  if ( !objectp(ldap) || !ldap->ldap_activated() )
    return -1;

  LDAPPERS_LOG( "lookup_group_data(%s)", identifier );

  if ( !stringp(config->groupAttr) || sizeof(config->groupAttr)<1 )
    return -1;

  mixed data = get_module("ldap")->fetch_group(identifier);
  if ( !mappingp(data) ) {
    LDAPPERS_LOG( "lookup_group_data: no data" );
    if ( ldap->get_last_error() != 0 ) return -1;
    else return 0;
  }

  mixed exc = catch {

    mapping result = ([ "class":CLASS_NAME_GROUP ]);
    if ( stringp(config->groupAttr) && stringp(data[config->groupAttr]) &&
         sizeof(data[config->groupAttr])>0 )
      result["name"] = data[config->groupAttr];
    else
      result["name"] = identifier;
    if ( config->subgroupMethod == "structural" ) {
      string full_name = dn_to_group_name( data->dn );
      if ( stringp(full_name) ) {
        array parts = full_name / ".";
        if ( sizeof(parts) > 1 )
          result["parentgroup"] = parts[0..(sizeof(parts)-2)] * ".";
        if ( sizeof(parts) > 0 )
          result["name"] = parts[-1];
        string check_name = result["name"] || "";
        if ( stringp(result["parentgroup"]) )
          check_name = result["parentgroup"] + "." + check_name;
        if ( lower_case(check_name) != lower_case(identifier) )
          return 0;
      }
    }
    else if ( config->subgroupMethod == "attribute" &&
         stringp(config->groupParentAttr) &&
         sizeof(config->groupParentAttr) > 0 ) {
      mixed parent = data[config->groupParentAttr];
      if ( stringp(parent) && sizeof(parent) > 0 ) {
        result["parentgroup"] = parent;
        if ( stringp(data[config->groupAttr]) &&
             sizeof(data[config->groupAttr]) > 0 )
          result["name"] = data[config->groupAttr];
	if ( lower_case(result["parentgroup"]+"."+result["name"]) != lower_case(identifier) )
	  return 0;
      }
    }
    LDAPPERS_LOG("lookup_group_data %s returns: %O", identifier, result );
    return result;

  };
  if ( exc != 0 ) werror( "LDAP: lookup_group_data(\"%s\") : %O\n", identifier, exc );
}



string dn_to_group_name ( string dn, void|int dont_strip_base_dc ) {
  if ( !objectp(ldap) ) return 0;
  return ldap->dn_to_group_name( dn, dont_strip_base_dc );
}


static string get_group_name ( mixed group_data ) {
  if ( !mappingp(group_data) || !stringp(config->groupAttr) ||
       sizeof(config->groupAttr)<1 || !stringp(group_data[config->groupAttr])
       || sizeof(group_data[config->groupAttr]) < 1 )
    return 0;
  string group_name = group_data[config->groupAttr];
  switch ( config->subgroupMethod ) {
    case "member" : {
    } break;
    case "attribute" : {
      if ( stringp(config->groupParentAttr) &&
           sizeof(config->groupParentAttr) > 0 &&
           stringp(group_data[config->groupParentAttr]) &&
           sizeof(group_data[config->groupParentAttr]) > 0 )
        group_name = group_data[config->groupParentAttr] + "." + group_name;
    } break;
    case "structural" :
    default: {
      string gname = dn_to_group_name( group_data["dn"] );
      if ( stringp(gname) && sizeof(gname)>0 ) group_name = gname;
    } break;
  }
  return group_name;
}


mapping|int load_data ( object obj ) {
  if ( !functionp(obj->get_identifier) ) return -1;
  string identifier = obj->get_identifier();
  check_access( identifier );
  if ( !objectp(ldap) || !ldap->ldap_activated() )
    return -1;

  // ***** user *****
  if ( obj->get_object_class() & CLASS_USER ) {
    LDAPPERS_LOG( "load_data: user %s", identifier );

    mixed cached = user_cache->get( identifier );
    if ( ! zero_type( cached ) ) {
      LDAPPERS_LOG( "user data from cache: %s", identifier );
      return cached;
    }

    mixed data = ldap->fetch_user( identifier );  //TODO: password ?

    if ( !mappingp(data) ) {
      if ( ldap->get_last_error() != 0 ) return -1;
      else return 0;
    }

    mixed exc = catch {
      mapping attributes = ([ ]);
      if ( mappingp(config["userAttributes"]) ) {
        mixed attrs = config["userAttributes"]->attribute;
        if ( mappingp(attrs) ) attrs = ({ attrs });
        if ( arrayp(attrs) ) {
          foreach ( attrs, mixed attr ) {
            if ( mappingp(attr) ) {
              if ( stringp(attr->steam) && stringp(attr->ldap) )
                attributes[ attr->steam ] = data[ attr->ldap ];
            }
          }
        }
      }
      else if ( arrayp(Config.array_value(config["userAttributes"])) ) {
        foreach ( Config.array_value(config["userAttributes"]), string attr ) {
          if ( has_index( data, attr ) ) attributes[attr] = data[attr];
        }
      }
      mapping attributes_nonpersistent = ([ ]);
      if ( mappingp(config["userAttributes-nonpersistent"]) ) {
        mixed attrs = config["userAttributes-nonpersistent"]->attribute;
        if ( mappingp(attrs) ) attrs = ({ attrs });
        if ( arrayp(attrs) ) {
          foreach ( attrs, mixed attr ) {
            if ( mappingp(attr) ) {
              if ( stringp(attr->steam) && stringp(attr->ldap) )
                attributes_nonpersistent[ attr->steam ] = data[ attr->ldap ];
            }
          }
        }
      }
      else if ( arrayp(Config.array_value(
                              config["userAttributes-nonpersistent"])) ) {
        foreach ( Config.array_value(config["userAttributes-nonpersistent"]),
                  string attr ) {
          if ( has_index( data, attr ) )
            attributes_nonpersistent[attr] = data[attr];
        }
      }
      attributes["ldap:dn"] = data["dn"];
      mapping result = ([ "class":CLASS_NAME_USER, "attributes":attributes,
                       "nonpersistent-attributes":attributes_nonpersistent ]);
      if ( stringp(data[config->passwordAttr]) && sizeof(data[config->passwordAttr])>0 ) {
        if ( stringp(config->passwordPrefix) && sizeof(config->passwordPrefix)>0 )
          result["password"] = config->passwordPrefix + data[config->passwordAttr];
        else
        result["password"] = data[config->passwordAttr];
      }
      if ( stringp(data[config->emailAttr]) && sizeof(data[config->emailAttr])>0 )
        attributes[USER_EMAIL] = data[config->emailAttr];
      if ( stringp(data[config->fullnameAttr]) && sizeof(data[config->fullnameAttr])>0 )
        attributes[USER_FULLNAME] = data[config->fullnameAttr];
      if ( stringp(data[config->nameAttr]) && sizeof(data[config->nameAttr])>0 )
        attributes[USER_FIRSTNAME] = data[config->nameAttr];
      if ( stringp(data[config->descriptionAttr]) && sizeof(data[config->descriptionAttr])>0 )
        attributes[OBJ_DESC] = data[config->descriptionAttr];

      if ( stringp(config->groupAttr) && sizeof(config->groupAttr)>0 ) {
        // primary group:
        if ( stringp(config->groupId) && stringp(data[config->groupId]) ) {
	  string searchstr = "(&(" + config->groupId + "=" + data[config->groupId] + ")"
            + "(objectClass=" + config->groupClass + "))";
	  mixed primary_group = get_module("ldap")->fetch( "", searchstr );
          string primary_group_name = get_group_name( primary_group );
          if ( stringp(primary_group_name) )
            result["active_group"] = primary_group_name;
        }
        // user's groups:
        if ( stringp(config->memberAttr) ) {
	  array groups = ({ });
          if ( stringp(config->userGroupDNAttr) &&
               sizeof(config->userGroupDNAttr) > 0 ) {
            array ldap_groups = data[config->userGroupDNAttr];
            if ( stringp(ldap_groups) ) ldap_groups = ({ ldap_groups });
            else if ( !arrayp(ldap_groups) ) ldap_groups = ({ });
            foreach ( ldap_groups, string ldap_group_dn ) {
              if ( !stringp(ldap_group_dn) ) continue;
              string ldap_group_name = dn_to_group_name( ldap_group_dn );
              if ( !stringp(ldap_group_name) ) continue;
              groups += ({ ldap_group_name });
            }
          }
          else {
            string searchstr = "(&(" + config->memberAttr + "=" + identifier + ")"
              + "(objectClass=" + config->groupClass + "))";
            mixed ldap_groups = get_module("ldap")->fetch( "", searchstr );
            if ( mappingp(ldap_groups) )  // single group, make an array out of it:
              ldap_groups = ({ ldap_groups });
            
            if ( arrayp(ldap_groups) ) {
              foreach ( ldap_groups, mixed ldap_group ) {
                string ldap_group_name = get_group_name( ldap_group );
                if ( !stringp(ldap_group_name) ) continue;
                groups += ({ ldap_group_name });
              }
            }
	  }
          if ( arrayp(groups) && sizeof(groups) > 0 )
            result["groups"] = groups + ({ "sTeam" });
        }
      }

      // check whether the user has been suspended:
      string suspend_attr = config->suspendAttr;
      if ( stringp(suspend_attr) && sizeof(suspend_attr) > 0 ) {
        array suspend_values = Config.array_value( config->suspendAttrValue );
        string value = data[suspend_attr];
        if ( value ) {
          if ( !arrayp(suspend_values) ||
               (search( suspend_values, value ) >= 0) )
            result["suspend"] = 1;
          else
            result["suspend"] = 0;
        }
        else if ( !zero_type(value) )
          result["suspend"] = 0;
      }

      // remember that the user has been looked up:
      user_cache->put( identifier, result );

      return result;

    };
    if ( exc != 0 ) werror( "LDAPPERS: load_object: user %s : %O\n", identifier, exc );
  }

  // ***** group *****
  else if ( obj->get_object_class() & CLASS_GROUP ) {
    LDAPPERS_LOG( "load_data: group %s", identifier );

    if ( !stringp(config->groupAttr) || sizeof(config->groupAttr)<1 )
      return -1;

    mixed cached = group_cache->get( identifier );
    if ( ! zero_type( cached ) ) {
      LDAPPERS_LOG( "group data from cache: %s", identifier );
      return cached;
    }

    mixed data = get_module("ldap")->fetch_group(identifier);
    if ( !mappingp(data) ) {
      if ( ldap->get_last_error() != 0 ) return -1;
      else return 0;
    }

    mixed exc = catch {
      mapping attributes = ([ ]);
      if ( mappingp(config["groupAttributes"]) ) {
        mixed attrs = config["groupAttributes"]->attribute;
        if ( mappingp(attrs) ) attrs = ({ attrs });
        if ( arrayp(attrs) ) {
          foreach ( attrs, mixed attr ) {
            if ( mappingp(attr) ) {
              if ( stringp(attr->steam) && stringp(attr->ldap) )
                attributes[ attr->steam ] = data[ attr->ldap ];
            }
          }
        }
      }
      else if ( arrayp(Config.array_value(config["groupAttributes"])) ) {
        foreach ( Config.array_value(config["groupAttributes"]),
                  string attr ) {
          if ( has_index( data, attr ) ) attributes[attr] = data[attr];
        }
      }
      mapping attributes_nonpersistent = ([ ]);
      if ( mappingp(config["groupAttributes-nonpersistent"]) ) {
        mixed attrs = config["groupAttributes-nonpersistent"]->attribute;
        if ( mappingp(attrs) ) attrs = ({ attrs });
        if ( arrayp(attrs) ) {
          foreach ( attrs, mixed attr ) {
            if ( mappingp(attr) ) {
              if ( stringp(attr->steam) && stringp(attr->ldap) )
                attributes_nonpersistent[ attr->steam ] = data[ attr->ldap ];
            }
          }
        }
      }
      else if ( arrayp(Config.array_value(
                              config["groupAttributes-nonpersistent"])) ) {
        foreach ( Config.array_value(config["groupAttributes-nonpersistent"]),
                  string attr ) {
          if ( has_index( data, attr ) )
            attributes_nonpersistent[attr] = data[attr];
        }
      }
      attributes["ldap:dn"] = data["dn"];
      if ( stringp(data[config->descriptionAttr]) && sizeof(data[config->descriptionAttr])>0 )
      attributes[OBJ_DESC] = data[config->descriptionAttr];
      mapping result = ([ "class":CLASS_NAME_GROUP, "attributes":attributes,
                       "nonpersistent-attributes":attributes_nonpersistent ]);
      // parent group and sub groups:
      array ldap_groups;
      if ( config->subgroupMethod == "structural" ) {
        string full_name = dn_to_group_name( data->dn );
        if ( stringp(full_name) ) {
          array parts = full_name / ".";
          if ( sizeof(parts) > 1 )
            result["parentgroup"] = parts[0..(sizeof(parts)-2)] * ".";
          if ( sizeof(parts) > 0 )
            result["name"] = parts[-1];
          string check_name = result["name"] || "";
          if ( stringp(result["parentgroup"]) )
            check_name = result["parentgroup"] + "." + check_name;
          if ( check_name != identifier )
            return 0;
        }
        // sub groups:
        if ( stringp(config->groupClass) && stringp(config->groupAttr) ) {
          mixed tmp_results = ldap->fetch_scope( data->dn, "(objectClass="+config->groupClass+")", 1 );
          if ( mappingp(tmp_results) ) tmp_results = ({ tmp_results });
          if ( !tmp_results ) tmp_results = ({ });
          if ( arrayp(tmp_results) ) {
            foreach ( tmp_results, mixed tmp_res ) {
              if ( !mappingp(tmp_res) ) continue;
              string group_name = tmp_res[config->groupAttr];
              if ( !stringp(group_name) ) continue;
              if ( !arrayp(ldap_groups) )
                ldap_groups = ({ group_name });
              else if ( search( ldap_groups, group_name ) < 0 )
                ldap_groups += ({ group_name });
            }
          }
        }        
      }
      else if ( config->subgroupMethod == "attribute" &&
                stringp(config->groupParentAttr) &&
                sizeof(config->groupParentAttr) > 0 ) {
        mixed parent = data[config->groupParentAttr];
        if ( stringp(parent) && sizeof(parent) > 0 ) {
          result["parentgroup"] = parent;
          if ( stringp(data[config->groupAttr]) &&
               sizeof(data[config->groupAttr]) > 0 )
            result["name"] = data[config->groupAttr];
          if ( result["parentgroup"]+"."+result["name"] != identifier )
            return 0;
        }
        // sub groups:
        mixed tmp_results = ldap->fetch( "", "("+config->groupParentAttr+"="+identifier+")" );
        if ( mappingp(tmp_results) ) tmp_results = ({ tmp_results });
        if ( !tmp_results ) tmp_results = ({ });
        if ( arrayp(tmp_results) ) {
          foreach ( tmp_results, mixed tmp_res ) {
            if ( !mappingp(tmp_res) ) continue;
            string group_name = tmp_res[config->groupAttr];
            if ( !stringp(group_name) ) continue;
            if ( !arrayp(ldap_groups) )
              ldap_groups = ({ group_name });
            else if ( search( ldap_groups, group_name ) < 0 )
              ldap_groups += ({ group_name });
          }
        }
      }
      if ( arrayp(ldap_groups) )
        result["groups"] = ldap_groups;

      // users (group members):
      if ( stringp(config->memberAttr) ) {
        mixed ldap_users;  // array of strings (login names)
        // structural members:
        if ( stringp(config->userClass) ) {
          mixed tmp_results = ldap->fetch_scope( data->dn, "(objectClass="+config->userClass+")", 1 );
          if ( mappingp(tmp_results) ) tmp_results = ({ tmp_results });
          if ( !tmp_results ) tmp_results = ({ });
          if ( arrayp(tmp_results) ) {
            foreach ( tmp_results, mixed tmp_res ) {
              if ( !mappingp(tmp_res) ) continue;
              string user_name = tmp_res[config->userAttr];
              if ( !stringp(user_name) ) continue;
              if ( !arrayp(ldap_users) )
                ldap_users = ({ user_name });
              else if ( search( ldap_users, user_name ) < 0 )
                ldap_users += ({ user_name });
            }
          }
        }
        // groupOfURLs needs to be parsed and searched:
        if ( lower_case(config->memberAttr) == "memberurl" &&
             stringp(config->userAttr) ) {
          mixed urls = data[config->memberAttr];
          if ( stringp(urls) ) urls = ({ urls });
          if ( arrayp(urls) ) {
            foreach ( urls, string url ) {
              string additional_filter;
              if ( stringp(config->userClass) )
                additional_filter = "(objectClass=" + config->userClass + ")";
              mixed tmp_results = ldap->fetch_url( url, additional_filter );
              if ( mappingp(tmp_results) ) tmp_results = ({ tmp_results });
              if ( !tmp_results ) tmp_results = ({ });
              foreach ( tmp_results, mixed tmp_res ) {
                if ( !mappingp(tmp_res) ) continue;
                string user_name = tmp_res[config->userAttr];
                if ( !stringp(user_name) ) continue;
                if ( !arrayp(ldap_users) )
                  ldap_users = ({ user_name });
                else if ( search( ldap_users, user_name ) < 0 )
                  ldap_users += ({ user_name });
              }
            }
          }
        }
        // direct member lists can be taken unmodified:
        else {
          mixed tmp_ldap_users = data[config->memberAttr];
          if ( stringp(tmp_ldap_users) )  // single user, make an array out of it:
            tmp_ldap_users = ({ tmp_ldap_users });
          if ( arrayp(tmp_ldap_users) ) {
            if ( !arrayp(ldap_users) ) ldap_users = tmp_ldap_users;
            else ldap_users += tmp_ldap_users;
          }
        }
        if ( arrayp(ldap_users) )
          result["users"] = ldap_users;
      }
      
      // remember that the group has been looked up:
      group_cache->put( identifier, result );

      return result;

    };
    if ( exc != 0 ) werror( "LDAPPERS: lookup_group_data(\"%s\") : %O\n", identifier, exc );
  }
  else return 0;  // LDAP only handles users and groups
}


/**
 * Searches for users in the persistence layer.
 *
 * @param terms a mapping ([ attrib : value ]) where attrib can be "firstname",
 *   "lastname", "login" or "email" and value is the text ot search for in the
 *   attribute. If the values contain wildcards, specify the wildcard character
 *   in the wildcard param.
 * @param any true: return all users that match at least one of the terms
 *   ("or"), false: return all users that match all of the terms ("and").
 * @param wildcard a string containing the wildcard used in the search term
 *   values, or 0 (or unspecified) if no wildcards are used
 * @return an array of user names (not objects) of matching users
 */
array(string) search_users ( mapping terms, bool any, string|void wildcard ) {
  check_access();
  if ( !objectp(ldap) || !ldap->ldap_activated() )
    return ({ });

  return ldap->search_users( terms, any );
}

/**
 * Searches for groups in the persistence layer.
 *
 * @param terms a mapping ([ attrib : value ]) where attrib can be "name"
 *   and value is the text ot search for in the attribute.
 *   If the values contain wildcards, specify the wildcard character in the
 *   wildcard param.
 * @param any true: return all groups that match at least one of the terms
 *   ("or"), false: return all groups that match all of the terms ("and").
 * @param wildcard a string containing the wildcard used in the search term
 *   values, or 0 (or unspecified) if no wildcards are used
 * @return an array of group names (not objects) of matching groups
 */
array(string) search_groups ( mapping terms, bool any, string|void wildcard ) {
  check_access();
  if ( !objectp(ldap) || !ldap->ldap_activated() )
    return ({ });

  return ldap->search_groups( terms, any );
}


/**
 * Called by the persistence manager if a user has been renamed.
 * Overloading this function allows you to react on user name changes.
 *
 * @param user The user object that has been renamed
 * @param old_name The user's old name
 * @param new_name The user's new name
 */
void user_renamed ( object user, string old_name, string new_name ) {
  uncache_user( old_name );
  uncache_user( new_name );
}


int uncache_user ( string identifier ) {
  int dropped = 1;
  if ( objectp(user_cache) ) dropped = user_cache->drop( identifier );
  return dropped & ldap->uncache_user( identifier );
}


/**
 * Called by the persistence manager if a group has been renamed.
 * Overloading this function allows you to react on group name changes.
 *
 * @param user The group object that has been renamed
 * @param old_name The group's old name
 * @param new_name The group's new name
 */
void group_renamed ( object group, string old_name, string new_name ) {
  uncache_group( old_name );
  uncache_group( new_name );
}


int uncache_group ( string identifier ) {
  int dropped = 1;
  if ( objectp(group_cache) ) dropped = group_cache->drop( identifier );
  return dropped & ldap->uncache_group( identifier );
}


/**
 * Returns a user or group object that should receive notifications about
 * noteworthy situations concerning the ldap persistence (e.g. conflicting
 * user entries).
 *
 * @return user or group object of the maintainer to notify
 */
object get_maintainer () {
  object maintainer;
  string maintainerStr = config["adminAccount"];
  if ( stringp(maintainerStr) ) {
    maintainer = USER( maintainerStr );
    if ( !objectp(maintainer) ) maintainer = GROUP( maintainerStr );
  }
  if ( !objectp(maintainer) ) maintainer = GROUP("admin");
  return maintainer;
}
