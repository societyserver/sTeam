inherit "/kernel/module";

#include <macros.h>
#include <events.h>
#include <attributes.h>
#include <classes.h>
#include <database.h>
#include <configure.h>

string get_identifier() { return "persistence"; }


/**
 * Drop a user from all caches (including LDAP cache) to make sure it is
 * re-synchronized with it's persistence layers on the next lookup.
 *
 * @param identifier the user's login name
 * @return 1 if the user has been dropped from cache, 0 if it was not cached or
 *   could not be dropped from cache
 */
int uncache_user ( string identifier ) {
  return _Persistence->uncache_user( identifier );
}

/**
 * Drop a group from all caches (including LDAP cache) to make sure it is
 * re-synchronized with it's persistence layers on the next lookup.
 *
 * @param identifier the group's name (including parent groups separated by
 *   dots ".")
 * @return 1 if the group has been dropped from cache, 0 if it was not cached
 *   or could not be dropped from cache
 */
int uncache_group ( string identifier ) {
  return _Persistence->uncache_group( identifier );
}

/**
 * Returns 1 if content is stored in the database (it might also be stored
 * in the filesystem).
 *
 * @return 1 if content is stored in the database, 0 if not
 */
int get_store_content_in_database () {
  return _Persistence->is_storing_content_in_database();
}

/**
 * Returns 1 if content is stored in the filesystem (it might also be stored
 * in the database).
 *
 * @return 1 if content is stored in the filesystem, 0 if not
 */
int get_store_content_in_filesystem () {
  return _Persistence->is_storing_content_in_filesystem();
}

/**
 * Returns the file path to an object content if the content is stored in the
 * filesystem.
 *
 * @param content_id the content id of the content for which to return the path
 * @param full_path (optional) if 0 then return only the path as within the
 *   content filesystem (e.g. /0b/03019). If 1 then return a full path,
 *   including the path to the sandbox (e.g. /var/lib/steam/content/0b/03019).
 * @return the path to the content file, or 0 if the content is not stored in
 *   the filesystem
 */
string get_content_path ( int content_id, int|void full_path ) {
  if ( ! _Persistence->is_storing_content_in_database() )
    return UNDEFINED;
  string path = "/" + ContentFilesystem.content_id_to_path( content_id );
  if ( ! Stdio.exist( _Server->get_sandbox_path() + "/content" + path ) )
    return UNDEFINED;
  if ( ! full_path )
    return path;
  string sandbox = _Server->get_config( "sandbox" );
  if ( !stringp(sandbox) || sandbox == "" ) sandbox = STEAM_DIR + "/tmp";
  return sandbox + "/content" + path;
}

/**
 * Returns whether exits to group workrooms will be created in users'
 * workrooms when they are added to groups through persistence layer group
 * memberships.
 *
 * @return 0 if exits will be created (default), or 1 if no exits will be
 *   created
 */
int get_dont_create_exits () {
  return _Persistence->get_dont_create_exits();
}
