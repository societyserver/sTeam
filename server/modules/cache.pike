/**
 * cache module
 * @author: exodusd
 *
 * This module manages caches where data can be cached. You might want to use
 * this if you have to access data very frequently that takes a long time to
 * retrieve or creates cpu load or network traffic when retrieved. The data
 * will be taken from the cache if it is cached and if the cached value is
 * not too old.
 * There is a cache collector thread that will check each cache from time to
 * time and remove entries that have expired, so that you don't run out of
 * memory when caching many different items that you only need for a short
 * amount of time.
 *
 * Initialization: You call create_cache() and pass it a key by which to
 *   identify your cache (if a cache with this key already exists, then you get
 *   a 0 result). You also pass the time (in seconds) of how long items will
 *   remain cached. So, to create a cache that caches values for 60 seconds:
 *     object my_cache = _Server->get_module("cache")->create_cache( "MyCache", 60 );
 *
 * Usage: You usually just call the get() method, passing it the key by which
 *   the item will be cached, and a function by which to retrieve the value
 *   in case it is not cached or it's cache value has expired. You can use
 *   the lambda() syntax to wrap the retrieval code, since you don't want
 *   to actually execute if the value is in the cache:
 *     mixed value = my_cache->get( key, lambda(){ return get_some_value(); } );
 */

inherit "/kernel/module";

#include <classes.h>
#include <attributes.h>
#include <database.h>
#include <events.h>
#include <macros.h>

/** This is the time (in seconds) the cache collector waits between cache
 * checks. */
int cache_collector_time = 300;  // 300 = every 5 minutes
static mapping caches = ([ ]);
static object cache_collector_thread;

string get_identifier() { return "cache"; }

class Cache {
    static mixed _id;
    /** You usually don't need to access this variable directly, use get() instead.
     * The cache data. Each key in the mapping is assigned an array. The 
     * first element is the cached value, the second is the time() when it
     * was cached. */
    mapping data;
    /** The time (in seconds) before a cached value expires. This is usually
     * set up at creation time. */
    int time_to_live;
    /** The maximum number of entries in the cache (old values will be removed
     * from cache when this number is reached). This is usually set up at
     * creation time. */
    int max_nr_entries;
    
    /** Don't call this directly, use the module's create_cache() method
     * instead. That way, the cache will be registered with the cache module
     * and will be handled by the cache collector. */
    void create ( mixed id, void|int seconds_to_live, void|int max_entries ) {
	_id = id;
        if ( intp(seconds_to_live) )
          time_to_live = seconds_to_live;
        else
          time_to_live = 0;
        if ( intp(max_entries) )
          max_nr_entries = max_entries;
        else
          max_nr_entries = 0;
	data = ([ ]);
    }

    /** Returns the id/key/name you gave the cache when creating it.
     * @return the cache's id/key/name
     */
    mixed get_id () {
	return _id;
    }

  /** Returns the time to live for objects in this cache.
   * @return time (in seconds) to live for cached objects
   */
  int get_time_to_live () {
    return time_to_live;
  }

  /** Sets the time to live for objects in this cache.
   * @param seconds_to_live the time (in seconds) that objects will stay cached
   * @param cleanup if true, the cache will be checked and all objects that
   *   are older than the new time to live will be removed
   */
  void set_time_to_live ( int seconds_to_live, void|bool cleanup ) {
    time_to_live = seconds_to_live;
    if ( cleanup ) clean_up();
  }

  /** Returns the maximum number of objects this cache will hold.
   * @return maximum number of objects for cache
   */
  int get_max_nr_entries () {
    return max_nr_entries;
  }

  /** Sets the maximum number of objects this cache will hold.
   * @param max_entries maximum number of objects for cache
   * @param cleanup if true, the cache will be checked and the oldest objects
   *   will be removed until the maximum number of entries is reached.
   */
  void set_max_nr_entries ( int max_entries, void|bool cleanup ) {
    max_nr_entries = max_entries;
    if ( cleanup ) clean_up();
  }

  /** Cleans up the cache by checking all cached objects and testing them against
   * the time-to-live or the maximum number of cache elements.
   */
  void clean_up () {
    // remove objects that have passed their time to live:
    if ( time_to_live > 0 ) {
      foreach ( indices(data), mixed key ) {
        array entry = data[key];
        if ( arrayp(entry) && time() - entry[1] > time_to_live )
          m_delete( data, key );
      }
    }
    // remove the oldest entries if there are more entries than max_nr_entries:
    if ( max_nr_entries > 0 ) {
      int nr_to_remove = sizeof(data) - max_nr_entries;
      if ( nr_to_remove > 0 ) {
        object queue = PriorityQueue.PriorityQueue();
        int newest_time = time();
        // build up a priority-queue with the oldest entries:
        foreach ( indices(data), mixed key ) {
          array entry = data[key];
          if ( entry[1] < newest_time || queue->size() < nr_to_remove ) {
            queue->push( entry[1], ({ key, entry[1] }) );
            if ( queue->size() > nr_to_remove )
              queue->pop();
            newest_time = queue->peek()[1];
          }
        }
        // remove the oldest entries:
        while ( queue->size() > 0 ) {
          remove( queue->pop()[0] );
        }
      }
    }
  }

    /** Fetches a value by a given key. If the value is cached and hasn't
     * expired, then it will be taken from the cache. Otherwise the
     * retrieval_function will be called and its result will be cached and
     * returned. If no retrieval_function has been supplied and the value is
     * not cached, then 0 will be returned (and not cached of course).
     * @param key the key by which to look up the cached value
     * @param retrieval_function the function to execute to retrieve the
     *   value if it is not cached (or has expired). Use the lambda(){...}
     *   syntax if you want to write code here, so that it will only be
     *   executed when necessary.
     * @return the value (either from cache or freshly retrieved)
     */
    mixed get ( mixed key, void|function retrieval_function ) {
	array entry = data[key];
	if ( arrayp(entry) && time()- entry[1] <= time_to_live )
	    return entry[0];
	mixed value;
	if ( functionp(retrieval_function) )
	    value = retrieval_function();
	else
            value = ([ ])[0];  // make zero_type value
	if ( !zero_type(value) )
	    put( key, value );
	return value;
    }

    /** You can deliberately put data into the cache by using this method.
     * @param key the key by which to later look up the cached value
     * @param value the value to cache for that key
     */
    void put ( mixed key, mixed value ) {
	data[key] = ({ value, time() });
    }

    /**
     * This does the same as drop(). It is here only for compatibility reasons.
     * @see drop
     */
    void remove ( mixed key ) {
	m_delete( data, key );
    }

    /** You can deliberately remove a key and value from the cache by using
     * this method, although the cache collector will do that from time to time
     * anyway.
     * @param key the key of the value that will be removed from cache
     * @return 1 if the key was cached and dropped from cache,
     *   0 if the key was not cached
     */
    int drop ( mixed key ) {
      if ( !has_index( data, key ) )
        return 0;
      m_delete( data, key );
      return 1;
    }
}

/** This creates a new cache. You specify an id (or key, name, etc.) by which
 * you can later identify the cache. You can also specify how long data will
 * remain cached.
 * @param id the id/key/name by which to identify your cache
 * @param seconds_to_live cached data will expire after that many seconds
 *    (default value is 5 seconds)
 * @param max_entries maximum number of objects for the cache (default is 0,
 *    which means that the number of objects will not be limited)
 * @return the new cache object, or 0 if there already was a cache with that id
 *   (you can fetch that cache via the get_cache() method if you want to)
 */
object create_cache ( mixed id, void|int seconds_to_live, void|int max_entries ) {
    if ( ! zero_type(caches[id]) ) return 0;
    int time_to_live = 5;
    if ( ! zero_type(seconds_to_live) ) time_to_live = seconds_to_live;
    object cache;
    if ( ! zero_type(max_entries) )
      cache = Cache( id, time_to_live, max_entries );
    else
      cache = Cache( id, time_to_live );
    caches += ([ id : cache ]);
    return cache;
}

/** Fetches a cache by a given id/key/name.
 * @param id the id/key/name of the cache to fetch
 * @return the cache, or 0 if there is no cache by that id
 */
object get_cache ( mixed id ) {
    object cache = caches[id];
    return cache;
}

/** Fetches a cache by a given id/key/name or creates it if it doesn't exist.
 * @param id the id/key/name of the cache to fetch
 * @param seconds_to_live cached data will expire after that many seconds
 *    (default value is 5 seconds)
 * @return the cache or a newly created cache
 */
object get_or_create_cache ( mixed id, void|int seconds_to_live ) {
    object cache = get_cache( id );
    if ( objectp( cache ) ) return cache;
    int time_to_live = 5;
    if ( ! zero_type(seconds_to_live) ) time_to_live = seconds_to_live;
    return create_cache( id, time_to_live );
}

/** Destroys a cache by a given id/key/name.
 * @param id the id/key/name of the cache to destroy
 */
void remove_cache ( mixed id ) {
    m_delete( caches, id );
}

/** Returns an array of all caches registered by the cache module.
 * @return an array of all caches (objects of type Cache)
 */
array get_caches () {
    return values( caches );
}

static void cache_collector_func () {
  while ( true ) {
    foreach ( indices(caches), mixed cache_id ) {
      caches[cache_id]->clean_up();
    }
    sleep( cache_collector_time );
  }
}

void init_module () {
  cache_collector_thread = Thread( cache_collector_func );
}

mapping get_last_changed(array(object) objects) {
  mapping lastChanges = ([ ]);
  foreach(objects, object obj) {
    lastChanges[obj] = obj->query_attribute(OBJ_LAST_CHANGED);
  }
  return lastChanges;
}
