/* Copyright (C) 2000-2006  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: Document.pike,v 1.3 2010/08/18 20:32:45 astra Exp $
 */

constant cvs_version="$Id: Document.pike,v 1.3 2010/08/18 20:32:45 astra Exp $";

//! A Document is an object with content (bytes). The content is stored
//! in the persistency layer of steam. When content is changed the
//! EVENT_UPLOAD and EVENT_DOWNLOAD events are trigered.

inherit "/classes/Object" :  __object;
inherit "/base/content"   : __content;

#include <attributes.h>
#include <classes.h>
#include <macros.h>
#include <events.h>
#include <types.h>
#include <config.h>
#include <database.h>


static void init_document() { }

/**
 * Init callback function.
 *  
 */
final static void
init()
{
    __object::init();
    __content::init_content();
    init_document();
}

/**
 * Called after the document was loaded by database.
 *  
 */
static void load_document()
{
}

/**
 * Called after the document was loaded by database.
 *
 */
static void load_object()
{
    load_document();
}

/**
 * Duplicate the Document and its content.
 *  
 * @return the duplicate of this document.
 */
mapping do_duplicate(void|mapping params)
{
  // DocumentFactory deals with content_obj variable
  if ( !mappingp(params) )
    params = ([ ]);
  
  params->content_obj = this();
  
  if ( params->content_id ) 
    params->content_obj = 0;
  
  params->mimetype = do_query_attribute(DOC_MIME_TYPE);
  // do not copy thumbnail attribute - thumbnails are
  // generated on the fly
  m_delete(params, DOC_IMAGE_THUMBNAIL);

  return ::do_duplicate( params );
}

/**
 * Destructor function of this object removes all references
 * and deletes the content.
 *  
 */
static void 
delete_object()
{
  mixed err = catch {
    if ( mappingp(mReferences) ) {
	foreach(indices(mReferences), object o) {
	    if ( !objectp(o) ) continue;
	    
	    o->removed_link();
	}
    }
    // delete all versions, try to make it as atomic as possible:
    mapping versions = do_query_attribute(DOC_VERSIONS);
    if ( mappingp(versions) ) {
      // gather all versions (recursively):
      array all_versions = ({ });
      foreach ( values(versions), object v ) {
        if ( !objectp(v) ) continue;
        mapping v_versions = v->query_attribute(DOC_VERSIONS);
        if ( !mappingp(v_versions) ) continue;
        foreach ( values(v_versions), object v2 ) {
          // add v's old version if it is valid and has not already been added:
          if ( !objectp(v2) ) continue;
          if ( search(all_versions, v2) >= 0 ) continue;
          all_versions |= ({ v2 });
        }
      }
      // check if there is any broken version reference:
      foreach ( all_versions, object v ) {
        if ( !objectp(v) || v->status() == PSTAT_DELETED )
          continue; // already deleted

        object v_versionof = v->query_attribute(OBJ_VERSIONOF);
        if ( !objectp(v_versionof) ) {
          steam_error( "Version mismatch: old version %O doesn't seem to be a "
                       "version of any object.", v );
          return;
        }
        if ( (v_versionof != this()) &&
             (search( all_versions, v_versionof ) < 0) ) 
          steam_error( "Version mismatch: old version %O is a version of a "
                       "different object: %O.", v, v_versionof );
      }
      // delete old versions, prevent recursions:
      foreach ( all_versions, object v ) {
        if ( !objectp(v) || v->status() == PSTAT_DELETED )
          continue; // already deleted

        v->set_attribute( DOC_VERSIONS, ([ ]) );
        v->set_attribute( OBJ_VERSIONOF, 0 );
        v->delete();
      }
    }
  };
  if (err) 
    FATAL("Error while deleting document %O\n%O", err[0], err[1]);
  err=catch(::delete_content());
  if (err) 
    FATAL("Error while deleting document content %O\n%O", err[0], err[1]);
  ::delete_object();
}

/**
 * Adding data storage is redirected to objects functionality.
 *  
 * @param function a - store function
 * @param function b - restore function
 * @return whether adding was successfull.
 */
static bool
add_data_storage(string a,function b, function c, int|void d)
{
    return __object::add_data_storage(a,b,c,d);
}

/**
 * Get the content size of this document.
 *  
 * @return the content size in bytes.
 */
int get_content_size()
{
    return __content::get_content_size();
}

/**
 * Returns the id of the content inside the Database.
 *  
 * @return the content-id inside database
 */
final int get_content_id()
{
  return __content::get_content_id();
}

/**
 * Callback function when a download has finished.
 *  
 */
static void download_finished()
{
    run_event(EVENT_DOWNLOAD_FINISHED, CALLER);
}

/**
 * give status of Document similar to file->stat()
 *
 * @param  none
 * @return ({ \o700, size, atime, mtime, ctime, uid, 0 })
 * @see    file_stat
 */
array stat()
{
    int creator_id = get_creator() ? get_creator()->get_object_id() : -1;
    
    return ({
	33279,  // -rwx------
	    get_content_size(),
	    do_query_attribute(OBJ_CREATION_TIME),
	    do_query_attribute(DOC_LAST_MODIFIED) || 
          do_query_attribute(OBJ_CREATION_TIME),
	    do_query_attribute(DOC_LAST_ACCESSED),
	    creator_id,
	    creator_id,
	    query_attribute(DOC_MIME_TYPE), // aditional, should not be a prob?
	    });
}

static void update_mimetype(string mime)
{
  object typeModule = get_module("types");
  if ( objectp(typeModule) ) {
    string classname = typeModule->query_document_class_mime(mime);
    // document classes are changed, but never to 'Document',
    // because all derived classes only include some special functionality
    if ( classname != get_class() && classname != "Document" ) {
      werror("updating mimetype for %s to %s (class=%s, new_class=%s\n", 
             get_identifier(), mime, get_class(), classname);
      get_factory(CLASS_DOCUMENT)->change_document_class(this());
    }
    object fulltext = get_module("fulltext");
    if (objectp(fulltext))
      fulltext->update_document(this());
  }
}

mixed set_attribute(string index, mixed data)
{
    mixed res = ::set_attribute(index, data);
#if 0
    object caller = CALLER;
    if ( functionp(caller->get_object_class) &&
	 caller->get_object_class() & CLASS_FACTORY )
	return res;
#endif
    if ( index == OBJ_NAME ) 
    {
      if ( do_query_attribute(DOC_MIME_TYPE) == MIMETYPE_UNKNOWN )
        {
          // try to find mimetype by new name ...
          object typeModule = get_module("types");
          if ( objectp(typeModule) && stringp(data) && strlen(data) > 0 ) 
          {
            string ext;
            sscanf(data, "%*s.%s", ext);
            string mime = typeModule->query_mime_type(ext);
            if ( mime != MIMETYPE_UNKNOWN )
            {
              do_set_attribute(DOC_MIME_TYPE, mime);
              update_mimetype(mime);
            }
          }
	}
    }
    else if ( index == DOC_MIME_TYPE ) {
      update_mimetype(data);
    }
    return res;
}

int get_object_class() { return ::get_object_class() | CLASS_DOCUMENT; }
final bool is_document() { return true; }

/**
 * content function used for download, this function really resides in
 * base/content and this overridden function just runs the appropriate event
 *  
 * @return the function for downloading (when socket has free space)
 * @see receive_content
 */
function get_content_callback(mapping vars)
{
    object obj = CALLER;

    if ( functionp(obj->get_user_object) && objectp(obj->get_user_object()) )
	obj = obj->get_user_object();

    check_lock("read");
    try_event(EVENT_DOWNLOAD, obj);

    do_set_attribute(DOC_LAST_ACCESSED, time());

    run_event(EVENT_DOWNLOAD, obj);

    return __content::get_content_callback(vars);
}

/**
 * Get the content of this document as a string.
 *  
 * @param int|void len - optional parameter length of content to return.
 * @return the content or the first len bytes of it.
 * @see get_content_callback
 */
string get_content(int|void len)
{
    string      content;
    object obj = CALLER;

    check_lock("read");
    
    try_event(EVENT_DOWNLOAD, obj);
    content = ::get_content(len);

    do_set_attribute(DOC_LAST_ACCESSED, time());

    run_event(EVENT_DOWNLOAD, obj);
    return content;
}

object get_content_file(string mode, mapping vars, string|void client) 
{
  return ((program)"/kernel/DocFile.pike")(this(), mode, vars, client);
}


void check_lock(string type, void|string lock)
{
    if ( type == "write" ) {
	// if lock is available and we get lock for token everything is fine
	if ( stringp(lock) )
	    if ( mappingp(Locking.is_locked(this(), lock)) )
		return;
	
	mapping locked = Locking.is_locked(this());
	if ( mappingp(locked) )
	    steam_error("Unable to write locked object, unlock first ! (#%d)",
			get_object_id());
    }
}


/**
 * Lock the content of this object.
 *  
 * @param object group - the locking group.
 * @param string type - the type of the lock, "read" or "write"
 * @return the content or the first len bytes of it.
 * @see get_content_callback
 */
mapping lock_content(object group, string type, int timeout)
{
    mapping data;
    try_event(EVENT_LOCK, CALLER, group, type, timeout);
    if ( type == "write" ) {
	if ( mappingp(Locking.is_locked(this()) ) )
	    steam_error("Cannot lock locked resources !");
	data = Locking.ExclusiveWriteLock(this(), group, timeout)->data;
	object locks = do_query_attribute(OBJ_LOCK) || ([ ]);
	locks[data->token] = data;
	do_set_attribute(OBJ_LOCK, locks);

    }
    run_event(EVENT_LOCK, CALLER, group, type, timeout);
    return data;
}

void unlock_content(void|string token) 
{
    try_event(EVENT_UNLOCK, CALLER);
    mapping locks = do_query_attribute(OBJ_LOCK) || ([ ]);
    if ( token ) {
	m_delete(locks, token);
    }
    else
	locks = ([ ]);
    do_set_attribute(OBJ_LOCK, locks);
    run_event(EVENT_UNLOCK, CALLER);
}


/**
 * Callback function called when upload is finished.
 *  
 */
static void content_finished()
{
  __content::content_finished();
  run_event(EVENT_UPLOAD, this_user(), get_content_size());
}

/**
 * content function used for upload, this function really resides in
 * base/content and this overridden function just runs the appropriate event
 *  
 * @return the function for uploading (called each time a chunk is received)
 * @see get_content_callback
 */
function receive_content(int content_size, void|string lock)
{
  prepare_upload(content_size, lock);
  return __content::receive_content(content_size);
}

static void prepare_upload(int content_size, void|string lock)
{
    object obj = CALLER;
    if ( objectp(obj) && 
	 (obj->get_object_class() & CLASS_USER) && 
	 (functionp(obj->get_user_object) ) &&
	 objectp(obj->get_user_object()) )
	obj = obj->get_user_object();
    
    check_lock("write", lock);

    try_event(EVENT_UPLOAD, obj, content_size);

    int version = do_query_attribute(DOC_VERSION);
    if ( !version )
      version = 1;
    else {
      seteuid(get_creator());
      
      mixed err = catch {
          object oldversion = duplicate( ([ "content_id": get_content_id(),
                                            "version_of": this() ])); 
	  oldversion->set_acquire(this());
	  oldversion->set_attribute(OBJ_VERSIONOF, this());
	  oldversion->set_attribute(DOC_VERSION, version);
	  oldversion->set_attribute(DOC_LAST_MODIFIED, do_query_attribute(DOC_LAST_MODIFIED));
	  oldversion->set_attribute(DOC_USER_MODIFIED, do_query_attribute(DOC_USER_MODIFIED));
	  oldversion->set_attribute(OBJ_CREATION_TIME, do_query_attribute(OBJ_CREATION_TIME));
	  mapping versions = do_query_attribute(DOC_VERSIONS);
	  oldversion->set_attribute(DOC_VERSIONS, copy_value(versions));
	  if ( !mappingp(versions) )
	  versions = ([ ]);
	  versions[version] = oldversion;
	  
	  version++;
	  do_set_attribute(DOC_VERSIONS, versions);
      };
      if ( err ) {
	  FATAL("Failed to create old version of document: %O\n%O",
		err[0], err[1]);
      }
      seteuid(0);
    }
    do_set_attribute(DOC_VERSION, version);
    
    set_attribute(DOC_LAST_MODIFIED, time());
    set_attribute(DOC_USER_MODIFIED, this_user());
}


/**
 * See whether the content is locked by someone or not.
 *  
 * @return the locking object.
 */
mapping is_locked()
{
    return Locking.is_locked(this());
}

object get_previous_version()
{
    mapping versions = do_query_attribute(DOC_VERSIONS);
    int version = do_query_attribute(DOC_VERSION);
    if ( objectp(versions[version-1]) )
	return versions[version-1];
    while ( version-- > 0 )
	if ( objectp(versions[version]) )
	    return versions[version];
    return 0;
}

string get_etag() 
{
  int lm = do_query_attribute(DOC_LAST_MODIFIED);
  string etag = sprintf("%018x",iObjectID + (lm<<64));
  if ( sizeof(etag) > 18 ) etag = etag[(sizeof(etag)-18)..];
  return etag[0..4]+"-"+etag[5..10]+"-"+etag[11..17];
}


string describe()
{
    return get_identifier()+"(#"+get_object_id()+","+
	master()->describe_program(object_program(this_object()))+","+
	get_object_class()+","+do_query_attribute(DOC_MIME_TYPE)+")";
}
