inherit "/kernel/module";

#include <classes.h>
#include <database.h>
#include <events.h>
#include <macros.h>


string get_identifier() { return "admin"; }

/**
 * Sets a server config setting.
 * @param setting the setting to change
 * @param value the new value for the setting
 * @return true on success, false if the setting could not be changed
 */
int set_config(mixed setting, mixed value)
{
  return _Server->set_config(setting, value);
}

/**
 * Queries whether a server config setting is changeable. Settings that
 * are specified in the config file are not changeable in the running
 * server.
 * @param setting the setting to check
 * @return true if the setting is changeable, false if it is not changeable
 */
int is_config_changeable(mixed setting)
{
  return _Server->is_config_changeable(setting);
}

/**
 * Returns a server config setting.
 * @param setting the setting to query
 * @return the value of the setting, or 0 (UNDEFINED) if it doesn't exist
 */
mixed get_config(mixed setting)
{
  return _Server->get_config(setting);
}

/**
 * Returns a mapping with all server config settings.
 * @return a mapping ([ setting : value ])
 */
mixed get_configs()
{
  return _Server->get_configs();
}

/**
 * Returns the server version as a string.
 * @return the server version
 */
string get_version()
{
  return _Server->get_version();
}

/**
 * Returns the (unix) time (seconds after 1.1.1970) of the last server restart.
 * @return unix time of the last server restart
 */
int get_last_reboot()
{
  return _Server->get_last_reboot();
}

/**
 * Returns the number of objects currently in memory on the server.
 * @return number of objects in memory
 */
int get_objects_in_memory()
{
  return master()->get_in_memory();
}

/**
 * Returns the number of swapped objects on the server.
 * @return number of swapped objects
 */
int get_objects_swapped()
{
  return master()->get_swapped();
}

/**
 * Returns the memory usage of the server as a mapping. The mapping contains
 * the memory usage and count of various data types (keys in the mapping are:
 * num_programs, program_bytes,
 * num_objects, object_bytes,
 * num_strings, string_bytes,
 * num_arrays, array_bytes,
 * num_mappings, mapping_bytes,
 * num_multisets, multiset_bytes,
 * num_frames, frame_bytes,
 * num_callbacks, callback_bytes.)
 * @return memory usage information of the server
 */
mapping get_memory()
{
  return _Server->debug_memory();
}

/**
 * Returns the current (unix) time (seconds since 1.Jan.1970) on the server.
 * @return current unix time on the server
 */
int get_server_time ()
{
  return time();
}
