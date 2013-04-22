/* Copyright (C) 2000-2004  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: access.pike,v 1.2 2009/08/04 15:39:31 nicke Exp $
 */

constant cvs_version="$Id: access.pike,v 1.2 2009/08/04 15:39:31 nicke Exp $";

//!
//! basic access functions...
//! the permissions of other objects on this object are stored
//! inside mSanction mapping. Each Entry in the mapping is an integer
//! (32 bits) and each bit represents one permission for the sanctioned
//! object. The first 16 bits are reserved for the system and include
//! standard checks that are done inside system code. The other 16 bits
//! are free for users to use in their own code.

#include <assert.h>
#include <macros.h>
#include <attributes.h>
#include <access.h>
#include <roles.h>
#include <database.h>
#include <classes.h>
#include <events.h>

private static mapping       mSanction; /*the right i have for this object */
private static mapping   mMetaSanction; /*the meta rights-to give away rights*/
private static mapping    mDataStorage;

private static object              oCreator;
        static object|function     oAcquire;

object                this();
int       get_object_class();
object     get_environment();
string      get_identifier();
void           update_path();
static void   require_save(void|string ident, void|string index);

/**
 * Initialize the access mappings for object, set acquiring to 0 and
 * set the creator of this object.
 *  
 * @author Thomas Bopp 
 */
final void
init_access()
{
    mSanction     = ([ ]);
    mMetaSanction = ([ ]);
    mDataStorage  = ([ ]);

    oAcquire      = 0;
    oCreator = geteuid();
    if ( !objectp(oCreator) )
	oCreator = this_user();

    if ( objectp(oCreator) )
        mSanction = ([ oCreator : SANCTION_ALL ]);
}

/**
 * Set the object to acquire access from. That is not only the ACL of this
 * object is used, but also the ACL of the object acquired from is used
 * for access lookup.
 *  
 * @param o - the object that variables and access is acquired from
 * @author Thomas Bopp (astra@upb.de) 
 * @see get_acquire
 */
final bool
set_acquire(function|object acquire)
{
    object acq;
    
    if ( !_SECURITY->access_acquire(0, this_object(), CALLER, acquire) )
	return false;
    
    if ( functionp(acquire) ) 
	acq = acquire();
    else
	acq = acquire;

    while ( objectp(acq) ) {
	if ( functionp(acq->get_object) )
	    acq = acq->get_object();
	if ( acq == this_object() )
	    THROW("Acquire ended up in loop !", E_ERROR);
	acq = acq->get_acquire();
    }

    oAcquire = acquire;
    require_save(STORE_ACCESS);
    return true;
}

/**
 * Turn on access acquiring from the object's environment. You can turn this
 * off again by calling set_acquire(0);
 *
 * @see set_acquire
 * @see get_acquire
 *
 * @return 1 on success, 0 on failure
 */
final bool
set_acquire_from_environment()
{
  return set_acquire( this_object()->get_environment );
}

/**
 * Return the acquiring object or function. If acquiring is turned of for this
 * object it returns 0.
 *  
 * @return the object permissions and variables are acquired
 * @see set_acquire
 */
final object|function
get_acquire()
{
    return oAcquire;
}

/**
 * Return the acquiring object. If acquiring is turned of for this
 * object it returns 0.
 *  
 * @return the object permissions and variables are acquired
 * @see set_acquire
 */
final object
resolve_acquire()
{
    if ( functionp(oAcquire) )
      return oAcquire();
    return oAcquire;
}




/**
 * Get the sanction integer for a given object.
 *  
 * @param obj - the object 
 * @return the sanction status for obj
 * @author Thomas Bopp 
 * @see set_sanction
 */
final int
query_sanction(object obj)
{
    return mSanction[obj];
}

/**
 * Returns the sanction mapping of this object, if the caller is privileged
 * the pointer will be returned, otherwise a copy.
 *  
 * @return the sanction mapping
 * @author Thomas Bopp 
 * @see set_sanction
 */
final mapping
get_sanction()
{
    if ( _SECURITY->trust(CALLER) )
	return mSanction;
    return copy_value(mSanction);
}

/**
 * The indices of the sanction mapping are returned. The sanction map is
 * in the form ([ object: access-bits, ])
 *  
 * @return all objects in sanction array
 * @author Thomas Bopp 
 */
final array(mixed)
query_sanctioned_objs()
{
    return indices(mSanction);
}

/**
 * Get the meta-sanction mapping. Meta sanction contains access to
 * give access permissions to other users or groups.
 *  
 * @return copy of the meta sanction mapping
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 * @see query_meta_sanction
 */
final mapping 
get_meta_sanction()
{
    return copy_value(mMetaSanction);
}

/**
 * Return the meta sanction access bit for a given object (group or user).
 *  
 * @param obj - the possible sanctioned object
 * @return the meta sanction permissions of obj on this
 * @author Thomas Bopp 
 * @see set_meta_sanction
 */
final int
query_meta_sanction(object obj)
{
    return mMetaSanction[obj];
}

/**
 * Set the meta access permissions for a group or a user.
 *  
 * @param obj - the object to sanction
 * @param permission - meta sanction permissions
 * @author Thomas Bopp 
 * @see query_meta_sanction
 */
final static void
set_meta_sanction(object obj, int permission)
{
    mMetaSanction[obj] = permission;
    require_save(STORE_ACCESS);
}

/**
 * Set the access permissions for a given group or user to 'permission'.
 *  
 * @param obj - object to sanction
 * @param permission - new permissions for that object
 * @author Thomas Bopp 
 * @see get_sanction
 */
final static void
set_sanction(object obj, int permission)
{
    ASSERTINFO(_SECURITY->valid_proxy(obj), "set_sanction on invalid proxy!");
    ASSERTINFO(mappingp(mSanction), "Mapping not initialized....");

    if ( permission == 0 )
	m_delete(mSanction, obj);
    else
	mSanction[obj] = permission;
    require_save(STORE_ACCESS);
}

/**
 * This function returns whether a user or group has access permissions
 * for 'accessBit'. The function also follows the acquiring path and
 * calls try_access_object() in acquired objects too.
 *  
 * @param user - who wants to access the object (user or group)
 * @param accessBit - the Bit to check
 * @param bool meta - check for meta access ?
 * @return ACCESS_DENIED or ACCESS_GRANTED or event ACCESS_BLOCKED
 * @author Thomas Bopp 
 * @see try_access_object_group
 */
final int
try_access_object(object user, int accessBit, bool meta)
{
    object obj = 0;
    ASSERTINFO(_SECURITY->valid_proxy(user), "Access on non-proxy !");
    
    SECURITY_LOG("Sanction of user is:" + mSanction[user]+"(accBit="+accessBit+")");
    if ( mSanction[user] & (accessBit << SANCTION_SHIFT_DENY) ) {
	SECURITY_LOG("Access blocked !");
	return ACCESS_BLOCKED;
    }
    if ( user == oCreator ) 
      return ACCESS_GRANTED;

    if ( (user == this())||(mSanction[user] & accessBit) )
    {
	SECURITY_LOG("Sanction of user does match !");
	if ( !meta || (mMetaSanction[user] & accessBit) )
	    return ACCESS_GRANTED;
    }
    /* the object must not be sanctioned at all
     * if the acquiring object gives permission to the user -> ok */
    if ( objectp(oAcquire) )
	obj = oAcquire;
    else if ( functionp(oAcquire) )
	obj = oAcquire();
    /* it is not possible to block access from acquiring objects ! */
    if ( objectp(obj) ) {
	SECURITY_LOG("Using acquiring path to "+obj->get_object_id());
	return obj->try_access_object(user, accessBit, meta) == ACCESS_GRANTED?
	    ACCESS_GRANTED : ACCESS_DENIED;
    }
    
    return ACCESS_DENIED;
}

/**
 * Try to access the object by a group. The function recursively tries 
 * parent groups of the initial group. If one group succeeds, the call
 * returns ACCESS_GRANTED.
 *  
 * @param grp - the group that wants to write
 * @return if successfull or not
 * @author Thomas Bopp 
 * @see try_access_object
 */
final int
try_access_object_group(object grp, int accessBit, bool meta)
{
    object     obj = 0;
    int         result;

    SECURITY_LOG("Group ["+grp->get_identifier()+"] access ("+
		 accessBit+") on "+get_identifier()+": sanction is "+
		 mSanction[grp]);

    if ( mSanction[grp] & (accessBit << SANCTION_SHIFT_DENY) )
	return ACCESS_BLOCKED;
    
    if ( (mSanction[grp] & accessBit) )
    {
	if ( !meta || (mMetaSanction[grp] & accessBit) )
	    return ACCESS_GRANTED;
    }

    array(object) grp_groups = grp->get_groups();
    //    LOG("Indirect group checking ... ");
    if ( arrayp(grp_groups) ) {
	foreach( grp_groups, object member ) {
	    if ( objectp(member) && _SECURITY->valid_group(member) ) {
		LOG("Accessing with " + master()->describe_object(member));
		result = try_access_object_group(member, accessBit, meta);
		if ( result == ACCESS_GRANTED )
		    return ACCESS_GRANTED;
	    }
	}
    }

    if ( objectp(oAcquire) )
	obj = oAcquire;
    else if ( functionp(oAcquire) )
	obj = oAcquire();
    if ( objectp(obj) ) {
	return obj->try_access_object_group(grp, accessBit, meta); 
    }
    
    return ACCESS_DENIED;
}





/**
 * Return all owners of this object.
 * Owners are groups/users that have sanction permission to the
 * object, eg are able to give permissions to other objects.
 *  
 * @return a list of owners 
 * @author Thomas Bopp 
 */
final array(object)
query_owner()
{
    int         i;
    array(mixed)    ind;
    array(object) owner;

    ind    = indices(mSanction);
    for ( i = sizeof(ind) - 1, owner = ({ }); i >= 0; i-- ) {
	if ( mSanction[ind[i]] & SANCTION_SANCTION ) {
	    owner += ({ ind[i] });
	}
    }
    return owner;
}

/**
 * Set the creator of the object. This is usually only done when
 * the object was created, but for export functionality there is
 * the possibility to change the creator later on. Apart from that the
 * creator is the person calling the factory to create an instance.
 *  
 * @param cr - the creator
 * @author Thomas Bopp 
 * @see get_creator
 */
final void
set_creator(object cr)
{
    object caller = CALLER;
    if ( !objectp(caller) )
      caller = this_object();

    //! Remove second line - security hole: Only factories are able to set permissions
    if ( objectp(oCreator) && !_Server->is_a_factory(CALLER) )
      //!_SECURITY->access_set_creator(0, this_object(), caller) )
      THROW("Unauthorized call to set_creator() by " + 
	    master()->describe_object(caller)+" !", E_ACCESS);
    oCreator = cr;
    update_path();
    require_save(STORE_ACCESS);
}

/**
 * Get the creator of the object. If no creator is set the root user
 * is returned.
 *  
 * @return the creator of the object
 * @author Thomas Bopp 
 * @see set_creator
 */
final object
get_creator()
{
    if ( !objectp(oCreator) ) 
      return _ROOT;
    return oCreator;
}


/**
 * Add a functionpair for storage and retrieval of data. Database
 * uses this to call the functions on loading and saving the object.
 *  
 * @param retrieve_func - function to retrieve the object data
 * @param restore_func - function to be called in the object for restoring
 * @return false or true (failed or not)
 * @author Thomas Bopp (astra@upb.de) 
 * @see get_data_storage
 */
static bool 
add_data_storage(string ident, function retrieve_func,
                 function restore_func, int|void indexed)
{
    if ( !mappingp(mDataStorage) ) 
	THROW("Data Storage not initialized !", E_ERROR);
    if ( strlen(ident)>15)
        THROW("add_data_storage(): Illegal IDENT-Length > 15", E_ERROR);
    if ( stringp(mDataStorage[ident]) ) 
	THROW(sprintf("Data Storage %s already defined !",ident), E_ERROR);

    mDataStorage[ident] = ({ retrieve_func, restore_func, indexed });
    return true;
}

/**
 * Get the data storage mapping, but only the _Database object is able
 * to call this functions.
 *  
 * @return the storage functions pairs (mapping)
 * @author Thomas Bopp (astra@upb.de) 
 * @see add_data_storage
 */
final mapping get_data_storage()
{
    ASSERTINFO(CALLER == _Persistence,"Unauthorized call to get_data_storage()");
    return mDataStorage;
}

/**
 * The database object calls this function upon loading the object to 
 * restore the access data (ACLs)
 *  
 * @param str - serialized access string
 * @author Thomas Bopp (astra@upb.de) 
 * @see unserialize_data
 */
final void 
restore_access_data(mixed data, string|void index)
{
    ASSERTINFO(CALLER == _Database, "Invalid call to restore_access_data()");
    
    if (!zero_type(index))
    {
        switch(index) {
          case "Sanction" : mSanction = data; break;
          case "MetaSanction" : mMetaSanction = data; break;
          case "Creator" : oCreator = data; break;
          case "Acquire" : oAcquire = data; break;
        }
    }
    else {
      if ( mappingp(data->Sanction) )
        mSanction     = data["Sanction"];
      if ( mappingp(data->MetaSanction) )
        mMetaSanction = data["MetaSanction"];
      oCreator      = data["Creator"];
      oAcquire      = data["Acquire"];
    }
    //    require_save();???
}

/**
 * The function retrieves the relevant access data to be saved in database.
 * Only the _Database object is able to call this function.
 *  
 * @return array of access data to be saved
 * @author Thomas Bopp (astra@upb.de) 
 * @see restore_access_data
 */
final mixed
retrieve_access_data(string|void index)
{
    if ( CALLER != _Database )
	return 0;
    /* this data has to be stored */
    if (!zero_type(index))
    {
        switch(index) {
          case "Sanction" : return mSanction;
          case "MetaSanction" : return mMetaSanction;
          case "Creator" : return oCreator;
          case "Acquire" : return oAcquire;
        }
    }
    else
    {
        return ([
            "Sanction":mSanction, 
            "MetaSanction":mMetaSanction,
            "Creator":oCreator, 
            "Acquire":oAcquire, 
	]);
    }
}

