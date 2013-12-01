/* Copyright (C) 2000-2010  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: proxy.pike,v 1.6 2010/08/21 19:38:00 astra Exp $
 */

constant cvs_version="$Id: proxy.pike,v 1.6 2010/08/21 19:38:00 astra Exp $";

#include <macros.h>
#include <exception.h>
#include <database.h>
#include <events.h>

private static object oSteamObj;
public  object oNext, oPrev;
private static int iOID;
private static int iClassID;
private static int iTime;
private static mapping(string:object) mDecorationObjects;
private static array(object) aDecorationObjects;  // cache

private static int iStatus;
private static Thread.Mutex loadMutex = Thread.Mutex(); // save loading

/*
 * @function create
 *           create a proxy for a sTeam-Object
 * @returns  void (is a constructor)
 * @args     int _id     - the object ID of the associated object
 *           int init    - create proxy only, or create new object
 *           string prog - class for the associated object
 */
final void create(int _id, object|void oTrue, void|int _class)
{
    iStatus = PSTAT_DISK;
    iOID = _id;
    iClassID = _class;
    iTime = time();
    mDecorationObjects = ([ ]);
    aDecorationObjects = ({ });

    if (objectp(oTrue))
    {
	oSteamObj = oTrue;
	iStatus = PSTAT_SAVE_OK;
    }
    //    master()->append(this_object());
}

/**
 * @function get_object_id
 * @returns  int (the object id to the associated object)
 */
final int get_object_id()
{
    return iOID;
}

final int get_object_class() 
{
  if ( iClassID )
    return iClassID;
  
  function f = find_function("get_object_class");
  catch(iClassID = f());
  return iClassID;
}

final void set_steam_obj(object o)
{
    if ((CALLER == _Database || CALLER == _Persistence) && !objectp(oSteamObj))
	oSteamObj = o;
}


/**
 * set the status of the proxy. Changes can only be done by either server
 * or database object.
 *
 * @param int _status - new status to set
 * @see status
 * @author Ludger Merkens 
 */
final void set_status(int _status)
{
  object c = CALLER;
  if (c == _Database || c == _Server || c == _Persistence || c == oSteamObj)
    iStatus = _status;
}

private static int i_am_in_backtrace()
{
    foreach(backtrace(), mixed preceed)
    {
        if (function_object(preceed[2]) == oSteamObj) {
            return 1;
	}
    }
    return 0;
}

/**
 * Drop the corresponding steam object.
 *  
 * @return 0 or 1 depending if the drop is successfull.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
final int drop()
{
    if ( !objectp(oSteamObj) )
	return 1;
    else if ( iStatus == PSTAT_SAVE_PENDING)
    {
      call(drop, 2.0); // drop later
      return 0;
    }
    else if ( i_am_in_backtrace()) // don't drop an object wich is a caller
    {
      call(drop, 0.0);
      return 0;
    }
    object lock = loadMutex->trylock();
    if (!objectp(lock)) {
      call(drop, 2.0); // drop later
      return 0;
    }
      
    // the object should also be removed from memory ?!
    destruct(oSteamObj);
    oSteamObj = 0;
    master()->got_dropped(this_object());
    iClassID = 0;
    iStatus = PSTAT_DISK;
    destruct(lock);
    return 1;
}

/**
 * Find a function inside the proxy object.
 *  
 * @param string fun - the function to find
 * @return a functionp of the function or 0
 */
final function find_function (string fun)
{
  if ( !objectp(oSteamObj) ) 
    f_load_object();
  if ( !objectp(oSteamObj) )
    return 0;
  function f;

  if ( f = oSteamObj[fun] )
    return f;
  foreach ( aDecorationObjects, object decoration ) {
    if ( !objectp(decoration) ) continue;
    f = decoration->find_function( fun );
    if ( f ) return f;
  }
  return 0;
}

static void f_load_object()
{
  object loadLock = loadMutex->lock();
  if ( !objectp(oSteamObj) ) {
    iTime = time();
    mixed err = catch {
      switch(_Persistence->load_object(this_object(), iOID)) {
      case 1:
        iStatus = PSTAT_FAIL_COMPILE;
        break;
      case 0:
        iStatus = PSTAT_FAIL_DELETED;
	break;
      case 2:
        iStatus = PSTAT_FAIL_DELETED;
        break;
      case 3:
        iStatus = PSTAT_FAIL_UNSERIALIZE;
        break;
      default:
	if ( iStatus == PSTAT_DISK )
	  iStatus = PSTAT_SAVE_OK;
      }
      if (!objectp(oSteamObj)) {
        destruct(loadLock);
        return;
      }
      
      master()->got_loaded(this_object());
    };
    if ( err ) {
      destruct(loadLock);
      throw(err);
    }
  }
  destruct(loadLock);
}

mapping (string:mixed) fLocal = ([
    "get_object_class": get_object_class,
    "get_object_id" : get_object_id,
    "get_object_class": get_object_class,
    "set_status": set_status,
    "set_decoration_object": set_decoration_object,
    "drop" : drop,
    "find_function" : find_function,
    "swap": swap,
    "set_steam_obj": set_steam_obj,
    "destroy": destroy,
    "status" : status,
    "get_object" : get_object,
]);
    
/**
 * `->() The indexing operator is replaced in proxy.pike to redirect function
 * calls to the associated object.
 * @param  string func - the function to redirect
 * @return mixed - usually the function pointer to the function in question
 *                 __null() in case of error
 * @see    __null
 * @see    find_function
 */
final mixed `->(string func)
{
    function    f;

    if (!oSteamObj) {
      if ((f=fLocal[func]) && (func!="get_object") && (func!="find_function"))
	return f;
      // double check for loadlock due to performance reasons
      // usually loading is only called once and this way performance
      // is better when already loaded
      f_load_object();
      if (!objectp(oSteamObj)) 
	return __null;
    }
    
    if (iStatus<0)
      return __null;

    if (f = fLocal[func])
        return f;

    if ( !(f = oSteamObj[func]) ) {
      foreach ( aDecorationObjects, object decoration ) {
        if ( !objectp(decoration) ) continue;
        mixed deco_f = decoration->find_function( func );
        if ( deco_f ) return deco_f;
      }
      return __null;
    }

    if (func == "get_identifier")
        master()->front(this_object());
    iTime = time();
    return f;
}

/**
 * dummy function, replacing a broken function, in case of error
 * @param none
 * @return 0
 * @see   `->() 
 */
final mixed __null()
{
    return 0;
}


/**
 * forces to load the content of an object from the database
 * is this function used ? - astra
 *
 */
final int|object force_load()
{
    int x;
    object loadLock = loadMutex->lock();
    mixed err = catch {
	if (oSteamObj)
	{
	    x= _Persistence->load_object(this_object(), oSteamObj);
	    switch (x)
	    {
	    case 1: iStatus = PSTAT_FAIL_COMPILE;
		break;
	    case 0: iStatus = PSTAT_FAIL_DELETED;
		break;
	    case 2: iStatus = PSTAT_FAIL_COMPILE;
	        break;
	    }
	}
	else
	{
	    x=  _Persistence->load_object(this_object(), iOID);
	    switch (x)
	    {
	    case 1: iStatus = PSTAT_FAIL_COMPILE;
		break;
	    case 0: iStatus = PSTAT_FAIL_DELETED;
		break;
	    case 2: iStatus = PSTAT_FAIL_COMPILE;
	    }
	}
    };
    if ( err ) {
	throw(err);
	destruct(loadLock);
    }
    return x;
}

/**
 * get the associated Object from this proxy
 * @param   none
 * @return  object | 0
 * @see    set_steam_obj
 * @see    _Database.load_object
 * @author Ludger Merkens 
 */
final object get_object()
{
    return oSteamObj;
}

/**
 * Called when the object including the proxy are destructed.
 *  
 */
final void destroy()
{
    master()->remove(this_object());
}

/**
 * 
 * The function returns the status of the proxy, which is actually
 * the status of the corresponding object.
 *
 * @param  none
 * @return PSTAT_DISK             ( 0) - on disk
 *         PSTAT_SAVE_OK          ( 1) - in memory
 *         PSTAT_SAVE_PENDING     ( 2) - in memory, but dirty (not implemented)
 *         PSTAT_DELETED          ( 3) - deleted from database
 *         PSTAT_FAIL_COMPILE     (-1) - failed to load (compilation failure)
 *         PSTAT_FAIL_UNSERIALIZE (-2) - failed to load (serialization failure)
 *         PSTAT_FAIL_DELETED     (-3) - failed to load (deleted from database)
 * @see    database.h for PSTAT constants.
 * @author Ludger Merkens 
 */
final int status()
{
    if (iStatus <0)
	return iStatus;
    if (!objectp(oSteamObj))
	return 0;
    
    return iStatus;
}

string _sprintf()
{
    return "/kernel/proxy.pike("+iOID+"/"+
        ({ "PSTAT_FAIL_DELETED", "PSTAT_FAIL_UNSERIALIZE" ,
           "PSTAT_FAIL_COMPILE", "PSTAT_DISK", "PSTAT_SAVE_OK",
           "PSTAT_SAVE_PENDING", "PSTAT_DELETED" })[iStatus+3]+")";
}

void set_decoration_object ( string path, object|void decoration )
{
  if ( CALLER != oSteamObj )
    steam_error( "No access to set decoration instance in proxy !" );
  if ( objectp(decoration) )
    mDecorationObjects[ path ] = decoration;
  else
    m_delete( mDecorationObjects, path );
  aDecorationObjects = values( mDecorationObjects );  // refresh cache
}

public int swap(int minSwapTime) 
{
  if (time() - iTime > minSwapTime) {
    drop();
    return 1;
  }
  return 0;
}