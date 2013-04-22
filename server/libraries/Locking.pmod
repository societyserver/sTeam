#include <macros.h>
#include <attributes.h>

class Lock {
    mapping data;
    void create(mapping lockdata) {
	data = lockdata;
	if ( !stringp(data->token) )
	    data->token = generate_token();
    }
    
    int get_depth() {
	return data->depth;
    }
    
    int get_time() {
	return data->locktime;
    }

    string get_owner() {
	return data->owner;
    }

    string get_scope() {
	return data->lockscope;
    }
    
    string get_token() {
	return data->token;
    }

    string get_timeout() {
	return data->timeout || "";
    }


    mapping serialize_coal() {
	return data;
    }
}

class ExclusiveWriteLock {
    inherit Lock;
    
    void create(object obj, object lockingUser, int timeout) {
	mapping data = ([ "lockscope": "exclusive",
			  "depth": 0,
			  "locktype": "write",
			  "owner": lockingUser->get_identifier(),
			  "timeout": "Second-" + timeout,
			  "locktime": time(),
			  "token": generate_token(obj),
			  ]);
	::create(data);
    }
}


/**
 * is_locked() - checks if resource is locked
 *  
 * @param object obj - check if this object is locked
 * @param void|string gottoken - try to get lock for this token
 * @return if the resource is locked (mapping or 0) or a lock for a token
 */
mapping is_locked(object obj, void|string gottoken) 
{
    if ( !objectp(obj) )
	return 0;
    // go through all locks
    mapping locks = obj->query_attribute(OBJ_LOCK) || ([ ]);
    foreach(indices(locks), string token) {
	mapping lockdata = locks[token];
	if ( mappingp(lockdata) ) {
	    int timeout = get_timeout_seconds(lockdata->timeout);
	    if ( lockdata->locktime > 0 && 
		 (time() - lockdata->locktime) < timeout )
	    {
		if ( !stringp(gottoken) || lockdata->token == gottoken )
		    return lockdata;
	    }
	}
    }

    // check if environment is locked - then return environments lockdata
    object env = obj->get_environment();
    mapping ldata = is_locked(env, gottoken);
    if ( mappingp(ldata) )
	return ldata;
    return 0;
}


string generate_token(void|object ctx) 
{
    int id = 0;
    
    if ( objectp(ctx) ) 
	id = ctx->get_object_id();
    
    string token = sprintf("%08x", random(time()));
    string ttoken = sprintf("%08x", time())  + sprintf("%08x", random(time())) + sprintf("%08x", random(time()));
    
    return "opaquelocktoken:" + token + "-" + 
	ttoken[0..3] + "-" + ttoken[4..7] + "-" + ttoken[8..11] + "-" +
	ttoken[12..];
}



int get_timeout_seconds(string timeout) 
{
    string measure;
    int t;

    sscanf(timeout, "%s-%d", measure, t);
    switch ( lower_case(measure) ) {
    case "second":
	return t;
    case "minute":
	return t*60;
    case "hour":
	return t*60*60;
    case "day":
	return t*60*60*24;
    }

    error("Locking.pmod: unable to determine time in seconds for " + 
	  measure);
    
    return 0;
}

