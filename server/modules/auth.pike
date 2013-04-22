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
 * $Id: auth.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

inherit "/kernel/module";

#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>

#define DEPENDENCIES users ldap

//#define DEBUG_AUTH 1

#ifdef DEBUG_AUTH
#define LOG_AUTH(s, args...) werror("auth: "+s+"\n", args)
#else
#define LOG_AUTH(s, args...)
#endif

static object usermod = get_module("users");
static object ldap = get_module("ldap");
static mapping config = ([ ]);
static array authentication_methods = ({ "database" });
static mapping suspended_users = ([ ]);


/**
 * Find a user object if the submitted password is sent correctly.
 *  
 * @param string name - the user name
 * @param string pass - the users password
 * @return the user object or 0, may throw an error if the password is wrong
 */
object authenticate ( string name, string pass ) {
  LOG_AUTH("authenticating user %s", name);
  if ( !_Persistence->user_allowed( name ) )
    return 0;
  object user = low_authenticate( name, pass );
  if ( !objectp(user) ) return user;

  // has the user been suspended?
  if ( has_index( suspended_users, user ) ) {
    string name = user->get_user_name();
    LOG_AUTH( "suspended user %s not authenticated", name );
    steam_user_error( "User "+name+" has been suspended." );
  }
  else return user;
}


static object low_authenticate(string name, string pass)
{
  object user = _Persistence->lookup_user( name, pass );
  if ( objectp(user) ) {
    // restricted users are always checked locally:
    if ( _Persistence->user_restricted( name ) ) {
      if ( user->check_user_password( pass ) ) {
        LOG_AUTH( "authenticated restricted user %s", name );
	return user;
      }
      else {
        LOG_AUTH( "failed to authenticate restricted user %s", name );
        return 0;
      }
    }

    // backdoor for root user?
    if ( Config.bool_value(config["root-backdoor"]) ) {
      if ( _ROOT->check_user_password(pass) ) {
        LOG_AUTH( "authenticated user %s via root-backdoor", name );
        return user;
      }
    }

    // check user activation:
    if ( user->get_activation() ) {
      LOG_AUTH( "user %s is not activated", name );
      steam_user_error("User "+name+" is not activated.");
    }

    foreach ( authentication_methods, string method ) {
      switch ( method ) {
        case "database" : {
          if ( user->check_user_password(pass) ) {
            LOG_AUTH( "authenticated user %s via database", name );
            return user;
          }
          else LOG_AUTH( "failed to authenticate user %s via database", name );
        } break;

        default :
          object module = get_module( method );
          if ( objectp(module) && functionp(module->authenticate_user) ) {
            if ( module->authenticate_user( user, pass ) ) {
              LOG_AUTH( "authenticated user %s via module %s", name, method );
              return user;
            }
            else LOG_AUTH( "failed to authenticate user %s via module %s",
                           name, method );
            break;
          }
          else
            werror( "Invalid authentication method: %s\n", method );
      }
    }
  }
  return 0;
}


array get_suspended_users () {
  if ( !GROUP("admin")->is_member( this_user() ) ) return 0;
  return indices( suspended_users );
}


bool is_user_suspended ( object user ) {
  return has_index( suspended_users, user );
}


mapping get_suspension_info ( object user ) {
  return suspended_users[ user ];
}


mapping set_suspension_info ( object user, mapping info ) {
  suspended_users[ user ] = info;
  require_save();
  return info;
}


mapping suspend_user ( object user, bool suspend ) {
  mapping info = suspended_users[ user ];
  if ( !suspend ) {
    m_delete( suspended_users, user );
    require_save();
    return info;
  }
  if ( mappingp(info) ) return info;
  info = ([ ]);
  suspended_users[ user ] = info;
  require_save();
  return info;
}


string get_ticket(object user)
{
  // try to get ticket from user and possible store inside ldap
}


string get_identifier() { return "auth"; }


mapping retrieve_auth () {
  if ( CALLER != _Database ) THROW( "Caller is not database !", E_ACCESS );
  return ([ "suspended_users" : suspended_users ]);
}


void restore_auth ( mapping data ) {
  if ( CALLER != _Database ) THROW( "Caller is not database !", E_ACCESS );
  suspended_users = data[ "suspended_users" ];
}


static void init_module ()
{
  add_data_storage( STORE_AUTH, retrieve_auth, restore_auth );
  config = Config.read_config_file( _Server.get_config_dir()+"/modules/auth.cfg" );
  if ( !mappingp(config) )
    config = ([ ]);
  if ( stringp(config["authenticate"]) ) {
    authentication_methods = ({ });
    array methods = config["authenticate"] / ",";
    foreach ( methods, string method ) {
      method = lower_case( String.trim_all_whites( method ) );
      if ( sizeof(method) > 0 )
        authentication_methods += ({ method });
    }
  }
  if ( !arrayp(authentication_methods) || sizeof(authentication_methods) < 1 )
    authentication_methods = ({ "database" });
}

int check_protocoll_access(object obj, object client)
{
    return 1;
}

bool allow_zero_passwords ()
{
  return Config.bool_value( config["allow-zero-passwords"] );
}
