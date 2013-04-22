/**
 * Class for persistence layers that can store steam objects. Layers that
 * do not store complete objects, but rather only some data, like certain
 * attributes, should use the persistence_partial module base instead.
 */

#include <macros.h>
#include <assert.h>
#include <attributes.h>
#include <config.h>
#include <classes.h>
#include <access.h>
#include <roles.h>
#include <events.h>
#include <exception.h>
#include <types.h>

inherit "/kernel/module";


/**
 * Return a bitmask of all object classes that this persistence layer supports.
 * See the classes.h include file for a list of constants (e.g. CLASS_USER).
 * Default is CLASS_ALL, meaning that the layer declares that it supports
 * all object classes.
 *
 * @return a bitmask of all object classes supported by this persistence layer
 */
int supported_classes () {
  return CLASS_ALL;
}


/**
 * @return the new object, or 0 if no new object was created, or -1 if an
 *   error occurred.
 */
mixed new_object ( string id, object obj, string program_name )
{
  return 0; // no new objects
}


object find_object ( int|string id )
{
  return 0;
}


int delete_object ( object obj )
{
  return 0;
}


/**
 * Called by the persistence manager if an object shall be explicitly dropped
 * from any caches, so that it receives new data on the next lookup.
 *
 * @param obj the object to drop from cache
 */
void uncache_object ( object obj )
{
}


/**
 * @return the loaded object, or 0 if no object could be loaded.
 */
int|object load_object ( object proxy, int|object oid )
{
  return 0;
}


static void save_object ( object proxy, void|string ident, string|void index )
{
}


/**
 * Retrieve all objects matching a given class, class name or program.
 * Mainly for maintainance reasons (requires ROLE_READ_ALL).
 * @param class (string|object|int) - the class to compare with
 * @return array(object) all objects found in the persistence layer
 * throws on access violation. (ROLE_READ_ALL required)
 */
final array(object) get_objects_by_class ( string|program|int mClass )
{
    string sClass;
    
    object security = _Server->get_module("security");
    if (security)
      ASSERTINFO( security->check_access( 0, this_user(), 0,
          ROLE_READ_ALL, false),
          "Illegal access on (persistence)get_all_objects" );

    if ( intp(mClass) ) {
      mixed factory = _Server->get_factory(mClass);
      if ( !objectp(factory) )
        return 0;
      if ( !stringp(CLASS_PATH) || !stringp(factory->get_class_name()) )
        return 0;
      mClass = CLASS_PATH + factory->get_class_name();
    }

    if (programp(mClass))
        sClass = master()->describe_program(mClass);
    else
        sClass = mClass;

    return get_objects_by_class_internal( sClass );
}


/** Override this for get_objects_by_class() to work.
 */
static array(object) get_objects_by_class_internal ( string mClass ) {
  return 0;
}


/**
 * Returns all objects from a persistence layer.
 * Mainly for maintainance reasons (requires ROLE_READ_ALL).
 * @return array(object) all objects found in the persistence layer
 * throws on access violation. (ROLE_READ_ALL required)
 */
final array(object) get_all_objects()
{
    if ( !_Server->is_a_factory(CALLER) )
        THROW("Illegal attempt to call database.get_all_objects !", E_ACCESS);
    
    return get_all_objects_internal();
}


/** Override this for get_all_objects() to work.
 */
static array(object) get_all_objects_internal () {
  return 0;
}


/** return either a user object or a mapping containing user data
 * from the persistence layer. User data are attributes (the mapping keys must
 * match the standard names, see the includes and factories), with some
 * additional non-attribute entries:
 * - "UserPassword" : password of user (usually encrypted)
 * - "Groups" : an array of group names (strings) of which the user is a member
 *   (a user will always be a member of the sTeam group, so this need not be added
 * - "ActiveGroup" : active (primary) group of the user (user must be member of that group)
 */
mixed lookup_user ( string identifier, void|string password )
{
  return 0;
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
}


/**
 * Called by the persistence manager if a user shall be explicitly dropped
 * from any caches, so that she receives new data on the next lookup.
 *
 * @param identifier the identifier (user name) of the user
 * @return 1 if the user was cached and dropped from cache in the persistence
 *   layer, 0 if the user was not cached in the persistence layer
 */
int uncache_user ( string identifier ) {
  return 0;
}


/** return either a group object or a mapping containing group data
 * from the persistence layer. Group data are attributes (the mapping keys must
 * match the standard names, see the includes and factories), with some
 * additional non-attribute entries:
 * - "Users" : an array of user names (strings) which are members of the group
 *   (these users are added to the group, all others removed. Users will never
 *   be removed from the sTeam group this way.)
 */
mixed lookup_group ( string identifier )
{
  return 0;
}


/**
 * Called by the persistence manager if a group has been renamed.
 * Overloading this function allows you to react on group name changes.
 *
 * @param user The group object that has been renamed
 * @param old_name The group's old name
 * @param new_name The group's new name
 */
void group_renamed ( object user, string old_name, string new_name ) {
}


/**
 * Called by the persistence manager if a group shall be explicitly dropped
 * from any caches, so that it receives new data on the next lookup.
 *
 * @param identifier the identifier (full group name with parents separated
 *   by ".") of the group
 * @return 1 if the group was cached and dropped from cache in the persistence
 *   layer, 0 if the group was not cached in the persistence layer
 */
int uncache_group ( string identifier ) {
  return 0;
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
  return 0;
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
  return 0;
}


/** check whether updates need to be performed
 * @param updates mapping of completed updates on the server
 * @return a mapping of updates that have been performed now, if no
 *   updates have been performed in this function call, return an
 *   empty mapping or UNDEFINED.
 */
mapping check_updates ( mapping updates ) {
  return 0;
}
