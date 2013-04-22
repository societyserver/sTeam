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

#include <configure.h>
#include <macros.h>


string content_id_to_path ( int content_id )
{
  if ( content_id == 0 ) return 0;
  string path = sprintf( "%05d", content_id );
  int tmp_id = content_id >> 8;
  do {
    path = sprintf( "%02x/", tmp_id & 0xff ) + path;
    tmp_id = tmp_id >> 8;
  } while ( tmp_id > 0 );
  return path;
}

string get_mount_command ()
{
  mapping persistence_config = Config.read_config_file( CONFIG_DIR +
                                           "/persistence.cfg", "persistence" );
  
  if ( !mappingp(persistence_config) ||
       !mappingp(persistence_config["content"]) )
    return 0;
  
  mixed fs_content = persistence_config["content"]["filesystem"];
  if ( !mappingp(fs_content) )
    return 0;
  
  mapping server_config = Config.read_config_file( CONFIG_DIR + "/steam.cfg" );
  string system_user = server_config["system_user"];
  if ( !stringp(system_user) || system_user == "" )
    system_user = "nobody";
  string sandbox_path = server_config["sandbox"];
  if ( !stringp(sandbox_path) || sandbox_path == "" )
    sandbox_path = STEAM_DIR + "/tmp";
  
  string mount = fs_content["mount"];
  if ( !stringp(mount) ) return 0;
  return replace( mount, ([ "$destdir" : sandbox_path + "/content",
                             "$user" : system_user ]) );
}

string get_unmount_command ()
{
  mapping persistence_config = Config.read_config_file( CONFIG_DIR +
                                           "/persistence.cfg", "persistence" );
  
  if ( !mappingp(persistence_config) ||
       !mappingp(persistence_config["content"]) )
    return 0;
  
  mixed fs_content = persistence_config["content"]["filesystem"];
  if ( !mappingp(fs_content) )
    return 0;
  
  mapping server_config = Config.read_config_file( CONFIG_DIR + "/steam.cfg" );
  string system_user = server_config["system_user"];
  if ( !stringp(system_user) || system_user == "" )
    system_user = "nobody";
  string sandbox_path = server_config["sandbox"];
  if ( !stringp(sandbox_path) || sandbox_path == "" )
    sandbox_path = STEAM_DIR + "/tmp";
  
  string unmount = fs_content["unmount"];
  if ( !stringp(unmount) ) return 0;
  return replace( unmount, ([ "$destdir" : sandbox_path + "/content",
                              "$user" : system_user ]) );
}

/**
 * @return path where the content filesystem has been mounted to
 */
string mount () {
  string mount_command = ContentFilesystem.get_mount_command();
  if ( !stringp(mount_command) )
    return 0;

  mapping server_config = Config.read_config_file( CONFIG_DIR + "/steam.cfg" );
  if ( !mappingp(server_config) )
    THROW( "Could not read server config from " + CONFIG_DIR + "/steam.cfg", E_ERROR );
  string sandbox_path = server_config["sandbox"];
  if ( !stringp(sandbox_path) || sandbox_path == "" )
    sandbox_path = STEAM_DIR + "/tmp";
  if ( ! Stdio.is_dir( sandbox_path + "/content" ) )
    mkdir( sandbox_path + "/content" );
  object p = Process.create_process( mount_command / " ", ([ ]) );
  if ( p->wait() )
    THROW( "Could not mount content filesystem! Command: " + mount_command, E_ERROR );
  return sandbox_path + "/content";
}

/**
 * @return 1 on success, 0 on failure or if no filesystem was mounted
 */
int unmount () {
  string unmount_command = get_unmount_command();
  if ( !stringp(unmount_command) )
    return 0;

  mixed err = catch {
    object p = Process.create_process( unmount_command / " ", ([ ]) );
    if ( p->wait() )
      THROW( "Could not unmount content filesystem. Command: " +
             unmount_command, E_ERROR );
    else
      return 1;
  };
  if ( err )
    THROW( "Could not unmount content filesystem: " + err[0], E_ERROR );
  return 0;
}
