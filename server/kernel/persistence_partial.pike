/**
 * Class for partial persistence layers, i.e. persistence layers that do
 * not store complete steam objects, but only certain data, e.g. a set of
 * attributes.
 * LDAP is an example, as it doesn't store complete steam users and groups,
 * but rather only some of the data, like user name, etc.
 *
 * Partial persistence layers don't have lookup(), lookup_user(),
 * lookup_group() or load_object() methods because they do not store objects.
 * They have lookup_data(), lookup_user_data(), lookup_group_data(), get_data()
 *  and set_data() methods instead, which can be used to find, get and set
 * object data in the layer.
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
 * Check whether data can be found by an identifier (e.g. user login).
 *
 * @see load_data
 *
 * @param identifier The identifier (e.g. user login) to look for
 * @return A mapping containing basic data for the object by that identifier.
 *   The data returned by this method should be a mapping containing
 *   entries for the execute method of the corresponding object factory
 *   as well as an entry "class" which specifies which object class the
 *   data belongs to (e.g. CLASS_NAME_USER). If you don't supply a "name"
 *   entry, then the identifier will be used by default.
 *   If no data was found for that identifier, then return 0. If an error
 *   occurred and you cannot determine whether the identifier has data or
 *   not then return -1.
 */
mapping|int lookup_data ( string identifier ) {
  return 0;
}


/**
 * Check whether user data can be found by an identifier (the user login).
 *
 * @see lookup_data
 *
 * @param identifier The identifier (user login) to look for
 * @return A mapping containing factory data for the user object by that
 *   identifier. The mapping should have an ([ "class":CLASS_NAME_USER ])
 *   entry and may contain additional data for the execute method of the
 *   user factory.
 *   If no data was found for that identifier, then return 0. If an error
 *   occurred and you cannot determine whether the identifier has data or
 *   not then return -1.
 */
mapping|int lookup_user_data ( string identifier ) {
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


/**
 * Check whether group data can be found by an identifier (the group name).
 *
 * @param identifier The identifier (group name) to look for
 * @return A mapping containing factory data for the group object by that
 *   identifier. The mapping should have an ([ "class":CLASS_NAME_GROUP ])
 *   entry and may contain additional data for the execute method of the
 *   group factory.
 *   If no data was found for that identifier, then return 0. If an error
 *   occurred and you cannot determine whether the identifier has data or
 *   not then return -1.
 */
mapping|int lookup_group_data ( string identifier ) {
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
 * Creates a new entry in the persistence layer that stores some data for a
 * steam object. This does not create an object, just an entry in the
 * persistence layer.
 *
 * @see delete_data
 * @see save_data
 *
 * @param obj The steam object of which to store some data in the layer.
 *   The persistence layer should fetch any data it wants to store directly
 *   from the steam object and return a mapping with the data it has stored.
 * @return A mapping containing the data that has been stored for the object
 *   (@see get_data), or 0 if no data was created, or -1 if an error occurred.
 */
mapping|int new_data ( object obj ) {
  return 0;
}


/**
 * Retrieves the data that has been stored for an object.
 *
 * @param obj The object for which to return the data
 * @return A mapping containing the data that is stored for the object.
 *   Attributes should be returned as a mapping by a key called "attributes",
 *   the object class (one of the CLASS_NAME_* constants) as a key "class",
 *   and further data depending on the object, e.g.:
 *   for users: ([ "class":CLASS_NAME_USER, "attributes":([...]),
 *                 "nonpersistent-attributes":([...]),
 *                 "password":"...(crypted)...",
 *                 "groups":({"groupname",...}), "active_group":"groupname" ])
 *   for groups: ([ "class":CLASS_NAME_GROUP, "attributes":([...]),
 *                  "nonpersistent-attributes":([...]),
 *                  "users":({"username",...}) ])
 *   If no data has been stored for the object, then return 0. If an error
 *   occurred and you cannot determine whether the object has data or
 *   not then return -1.
 */
mapping|int load_data ( object obj ) {
  return 0;
}


/**
 * Overridden, returns acquired attributes for objects that have
 * "nonpersistent-attributes" (see load_data()).
 *
 * @param key the key/name of a non-persistent attribute
 * @return the value of a non-persistent attribute for an object
 */
mixed query_attribute ( mixed key ) {
  if ( CALLER == _Persistence ) return ::query_attribute( key );
  mixed data = load_data( CALLER );
  if ( mappingp(data) && mappingp(data["nonpersistent-attributes"]) ) {
    mixed value = data["nonpersistent-attributes"][key];
    if ( value ) return value;
  }
  return ::query_attribute( key );
}


/**
 * Updates the data in the persistence layer for an object.
 *
 * @see load_data
 * @see delete_data
 *
 * @param obj The steam object of which to store some data in the layer.
 *   The persistence layer should fetch any data it wants to store directly
 *   from the steam object and return a mapping with the data it has stored.
 * @return A mapping containing the data that has been stored for the object
 *   (@see get_object). If the layer didn't store data for that object,
 *   then return 0. If an error occurred then return -1.
 */
mapping|int save_data ( object obj ) {
  return 0;
}


/**
 * Removes stored data for an object from the persistence layer. If successful,
 * a call to lookup_data() (or lookup_user_data() / lookup_group_data() if
 * the object was a user or group) should fail (return UNDEFINED) because the
 * data has been deleted.
 *
 * @param obj The object for which to remove data from the persistence layer
 * @return true on success (data was deleted), false on failure
 *   (data could not be deleted or could not be found).
 */
bool delete_data ( object obj ) {
  return false;
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


/**
 * Check whether updates need to be performed by the persistence layer,
 * e.g. create search indexes. This is the same as in normal persistence
 * layers.
 *
 * @param updates A mapping of completed updates on the server
 * @return A mapping of updates that have been performed now. If no updates
 *   have been performed in this function call, return an empty mapping or 0.
 */
mapping check_updates ( mapping updates ) {
  return 0;
}
