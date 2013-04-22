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
 * $Id: decorateable.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: decorateable.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

//! The decoration features of a sTeam object are implemented in this file.
//! Object uses it so any object inside a sTeam server features a list 
//! of decorations. The functions to add and remove decorations are located
//! in Object and call the low level functions in this class.

#include <macros.h>
#include <exception.h>
#include <classes.h>
#include <access.h>
#include <database.h>
#include <roles.h>
#include <attributes.h>

static array(string) aDecorations; // list of decorations

string        get_identifier();
void             update_path();
object                  this();
static void     require_save(void|string ident, void|string index);

/**
 * Initialization of decorations on this object.
 *  
 * @see add_decoration
 * @see remove_decoration
 */
static void init_decorations()
{
    aDecorations = ({ });
}

/**
 * Add a decoration to this object. The decoration is identified by a path of
 * the form: "server:/path-in-server-sandbox" or "object:/object-path" or
 * "object:#object-id". An instance of the decoration will be provided and
 * attached to the proxy of this object.
 *  
 * @param string path the path to the decoration source code
 * @return true if the decoration could be successfully added, false if not
 * @see remove_decoration
 */
static bool add_decoration ( string path )
{
  if ( !stringp(path) || path == "" )
    THROW( "Trying to add decoration with empty path !", E_ERROR );
  LOG( "Adding decoration: " + path + " to "+ get_identifier() );
  return do_add_decoration( path );
}

static bool do_add_decoration ( string path )
{
  if ( search( aDecorations, path ) >= 0 )
    steam_error( "add_decoration: Decoration already on %O\n", get_identifier() );
  
  aDecorations += ({ path });
  
  require_save( STORE_DECORATIONS );
  return true;
}

static object load_decoration ( string path )
{
  string type, decoration_path, decorator_content;

  if ( ! stringp(path) )
    steam_error( "No decoration given!\n" );

  if (sscanf(path, "%s:%s", type, decoration_path) != 2) {
    decoration_path = path;
    type = "object";
  }

  if ( !stringp(decoration_path) || decoration_path == "" )
    steam_error( "No decoration given!\n" );

  switch ( lower_case( type ) ) {

    case "server":
      string sandbox_path = _Server->get_sandbox_path();
      decorator_content = Stdio.read_file( sandbox_path + decoration_path );
      if ( !stringp(decorator_content) )
        steam_error( "Failed to find decoration object in server dir (%s):" +
                     " %s\n", sandbox_path, decoration_path );
      break;

    case "file":
    case "object":
    default:
      if ( decoration_path[0] == '#' ) {
        int id = (int)(decoration_path[1..]);
        object co = find_object( id );
        if ( !objectp(co) )
          steam_error( "Failed to find decoration object with id %d\n", id );
        decorator_content = co->get_content();
      }
      else {
        object co = OBJ( decoration_path );
        if ( !objectp(co) )
          steam_error( "Failed to find decoration object in %s\n",
                       decoration_path );
        decorator_content = co->get_content();
      }
      break;
  }
  
  if ( !stringp(decorator_content) || sizeof(decorator_content) == 0 )
    steam_error( "Decoration has no content: %s\n", path );

  program p;
  mixed err = catch( p = compile_string( decorator_content ) );
  if ( err ) {
    werror( "Failed to compile decoration: %s\n", path );
    throw( err );
  }
  /*
  if ( ! Program.implements( p, pApi ) )
    steam_error( "Decoration program does not implement decoration api, " +
                 "should implement get_decoration_class() !\n" );
  */
  
  object decoration_obj = p( this() );
  if ( objectp(decoration_obj) )
    return decoration_obj;
  return 0;
}

/**
 * Removes a decoration from the object. This function just removes
 * the decoration path from the list of decorations.
 * 
 * @param string path the decoration path to remove
 * @return true if the decoration was successfully removed, false otherwise
 * @see add_decoration
 */
static bool remove_decoration ( string path )
{
  if ( search( aDecorations, path ) == -1 )
    THROW( "Decoration " + path + " not present on object !", E_ERROR );
  
  aDecorations -= ({ path });
  
  require_save( STORE_DECORATIONS );
  return true;
}

/**
 * This function returns a copied list of all decorations of this
 * object.
 * 
 * @return the array of decorations
 */
array(string) get_decorations ()
{
  return copy_value( aDecorations );
}

/**
 * Checks whether this object has a certain decoration.
 *
 * @param path the decoration path
 * @return true if the object has this decoration, false if not
 */
bool has_decoration ( string path )
{
  return search( aDecorations, path ) >= 0;
}

/**
 * Retrieve decorations for storing them in the database.
 * Only the global _Database object is able to call this function.
 * 
 * @return mapping of object data.
 * @see restore_decorations
 */
final mapping retrieve_decorations ()
{
  if ( CALLER != _Database )
    THROW( "Caller is not the database object !", E_ACCESS );
  
  return ([ "Decorations" : aDecorations ]);
}

/**
 * Called by database to restore the object data again upon loading.
 * 
 * @param mixed the object data
 * @see retrieve_decorations
 */
final void restore_decorations ( mixed data )
{
  if ( CALLER != _Database )
    THROW( "Caller is not the database object !", E_ACCESS );
  
  aDecorations = data[ "Decorations" ];
  if ( !arrayp(aDecorations) ) {
    aDecorations = ({ });
    require_save( STORE_DECORATIONS );
  }
}
