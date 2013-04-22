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
 * $Id: content.pike,v 1.6 2010/08/18 20:32:45 astra Exp $
 */

constant cvs_version="$Id: content.pike,v 1.6 2010/08/18 20:32:45 astra Exp $";

//! Basic class to support Objects with content (Documents). Content
//! is stored in the persistency layer of sTeam.


private static Thread.Mutex writeMutex = Thread.Mutex();;


#include <macros.h>
#include <config.h>
#include <assert.h>
#include <database.h>
#include <classes.h>

private static int              iContentID;
private static int       iContentSize = -1;

private static object           oLockWrite;
private static object            oLockRead;
private static int            iDownloads=0;

static bool add_data_storage(string s,function a, function b,int|void d);
static void download_finished();
static void require_save(string|void a, string|void b) { _Persistence->require_save(a,b); }
int get_object_id();

/**
 * This callback function is registered via add_data_storage to provide
 * necessary data for serialisation. The database object calls this function
 * to save the values inside the database.
 *
 * @param  none
 * @return a mixed value containing the new introduced persistent values
 *         for content
 * @see    restore_content_data
 * @see    add_data_storage
 */
mixed retrieve_content_data(string|void index)
{
    if ( CALLER != _Database )
	THROW("Illegal call to retrieve_content_data()", E_ACCESS);
    if (index) {
        switch(index) {
          case "CONTENT_SIZE": return iContentSize;
          case "CONTENT_ID": return iContentID;
        }
    }
    else
        return ([ "CONTENT_SIZE": iContentSize,
                  "CONTENT_ID": iContentID ]);
}

/**
 * This callback function is used to restore data previously read from
 * retrieve_content_data to restore the state of reading
 *
 * @param  a mixed value previously read via retrieve_content_data
 * @return void
 * @see    retrieve_content_data
 * @see    add_data_storage
 */
void restore_content_data(mixed data, string|void index)
{
    if ( CALLER != _Database )
	THROW("Illegal call to restore_content_data()", E_ACCESS);

    if (index) {
        switch (index) {
          case "CONTENT_SIZE" : iContentSize = data; break;
          case "CONTENT_ID": iContentID = data; break;
        }
    }
    else if (arrayp(data)) {
        [ iContentSize, iContentID ] = data;
    }
    else {
        iContentSize = data["CONTENT_SIZE"];
        iContentID = data["CONTENT_ID"];
    }
}


/**
 * Initialize the content. This function only sets the data storage
 * and retrieval functions.
 *  
 */
static void init_content()
{
    add_data_storage(STORE_CONTENT, retrieve_content_data,
                     restore_content_data, 1);
}


class DownloadHandler {
    object odbhandle;
    object ofilehandle;
    void create(object oDbHandle, object oFileHandle) {
        odbhandle = oDbHandle;
        ofilehandle = oFileHandle;
    }
    /**
     * This function gets called from the socket object associated with
     * a user downloads a chunk. It cannot be called directly - the
     * function get_content_callback() has to be used instead.
     *
     * @param  int startpos - the position
     * @return a chunk of data | 0 if no more data is present
     * @see    receive_content
     * @see    get_content_callback
     */
    string send_content(int startpos) {
        if ( !objectp(odbhandle) && !objectp(ofilehandle) )
            return 0;
        
        string buf;
        if ( _Persistence->is_storing_content_in_filesystem() &&
             objectp(ofilehandle) )
          buf = ofilehandle->read( DB_CHUNK_SIZE );
        else if ( _Persistence->is_storing_content_in_database() &&
                  objectp(odbhandle) )
          buf = odbhandle->read( DB_CHUNK_SIZE );

        if ( stringp(buf) )
	  return buf;

        if (objectp(odbhandle) || objectp(ofilehandle))
        {
            iDownloads--;
            if (iDownloads == 0)           // last download finished?
                destruct(oLockRead);      // release writing lock

            if ( objectp(ofilehandle) ) destruct(ofilehandle);
            if ( objectp(odbhandle) ) destruct(odbhandle);
        }
        // callback to notify about finished downloading
        download_finished();
        
        return 0;
    }

    void destroy() {
        if ( objectp(odbhandle) || objectp(ofilehandle) )
        {
            iDownloads --;
            if (iDownloads ==0)
                destruct(oLockRead);
            if ( objectp(odbhandle) ) destruct(odbhandle);
            if ( objectp(ofilehandle) ) destruct(ofilehandle);
        }
    }
    string _sprintf() { return "DownloadHandler"; }
    string describe() { return "DownloadHandler"; }
}


class UploadHandler {
    static object odbhandle;
    static object file;
    static int iWrittenSize;
    function content_finished;

    void create(object oDbHandle, function cfinished, object f) {
        odbhandle= oDbHandle;
	content_finished = cfinished;
	content_begin();
	file = f;
    }
    /**
     * save_chunk is passed from receive_content to a data storing process, 
     * to store one chunk of data to the database.
     *
     * @param   string chunk - the data to store
     * @param   int start    - start position of the chunk relative to complete
     *                         data to store.
     * @param   int end      - similar to start
     * @return  void
     * @see     receive_content
     */
    void save_chunk(string chunk) {
        if ( !stringp(chunk) )
        {
            local_content_finished();
            return;
        }
        if ( _Persistence->is_storing_content_in_database() )
          odbhandle->write(chunk);
	if ( _Persistence->is_storing_content_in_filesystem() && objectp(file) )
	  file->write(chunk);
	iWrittenSize += strlen(chunk);
    }
    
    /**
     * This function gets called, when an upload is finished. All locks
     * are removed and the object is marked for the database save demon
     * (require_save()).
     *  
     * @see save_chunk
     */
    void local_content_finished() {
        odbhandle->flush();
        int iWrittenID = odbhandle->dbContID();
	if ( objectp(file) )
	  file->close();

	// clean old content?
        iContentID = iWrittenID;
        iContentSize = iWrittenSize;
        require_save(STORE_CONTENT);
        odbhandle->close(remote_content_finished);
        return;
    }

    void remote_content_finished() {
      destruct(odbhandle);
      content_finished();
    }

    void destroy() {
        if (odbhandle)
            content_finished();
    }
    string _sprintf() { return "UploadHandler"; }
    string describe() { return "UploadHandler"; }
    
}

/**
 * The function returns the function to download the content. The
 * object is configured and locked for the download and the
 * returned function send_content has to be subsequently called
 * in order to get the data. 
 * 
 * @param  none
 * @return function "send_content" a function that returns the content
 *         of a given range.
 * @see    send_content
 */
function get_content_callback(mapping vars)
{
    if ( iContentID == 0 )
	LOG_DB("get_content_callback: missing ContentID");
    
    if (iDownloads == 0)
    {
	object lock = writeMutex->lock();      // wait for content_cleanup
	oLockRead = lock;
    }
    iDownloads++;

    object oDbDownloadHandle, oFileDownloadHandle;
    if ( _Persistence->is_storing_content_in_filesystem() )
      oFileDownloadHandle = _Persistence->open_content_file( iContentID, "r" );
    if ( _Persistence->is_storing_content_in_database() )
      oDbDownloadHandle = _Database->new_db_file_handle( iContentID, "r" );
    object oDownloadHandler =
      DownloadHandler( oDbDownloadHandle, oFileDownloadHandle );
    ASSERTINFO( objectp(oDbDownloadHandle) || objectp(oFileDownloadHandle),
                "No file handle found !" );
    if ( objectp(oDbDownloadHandle) )
      LOG( "db_file_handle() allocated, now sending...\n" );
    if ( objectp(oFileDownloadHandle) )
      LOG( "file_handle() allocated, now sending...\n" );
    return oDownloadHandler->send_content;
}

/**
 * This function gets called to initialize the download of a content.
 * The returned function has to be called subsequently to write data.
 * After the upload is finished the function has to be called with
 * the parameter 0.
 *
 * @param  int content_size -- the size of the content that will be
 *         passed in chunks to the function returned
 * @return a function, that will be used as call_back by the object
 *         calling receive_content to actually store the data.
 * @see    save_chunk
 * @see    send_content
 * @author Ludger Merkens 
 */
function receive_content(int content_size)
{
    object oHandle = _Database->new_db_file_handle(0,"wtc");
    if ( !iContentID )
      iContentID = oHandle->dbContID();
    object file = _Persistence->open_content_file( iContentID, "wct" );
    object oUploadHandler = UploadHandler(oHandle, content_finished, file);
    return oUploadHandler->save_chunk;
}

static void prepare_upload(int content_size, void|string lock)
{
}

object get_upload_handler(int content_size)
{
    object oHandle = _Database->new_db_file_handle(0,"wtc");
    if ( !iContentID )
      iContentID = oHandle->dbContID();
    object file = _Persistence->open_content_file( iContentID, "wct" );
    return UploadHandler(oHandle, content_finished, file);
}

/**
 * update_content_size - reread the content size from the database
 * this is a hot-fix function, to allow resyncing with the database tables,
 * this function definitively should be obsolete.
 *
 * @param none
 * @return nothing
 * @author Ludger Merkens
 */
void update_content_size()
{
  iContentSize = _Persistence->get_content_size( iContentID );
  require_save(STORE_CONTENT);
}

/**
 * evaluate the size of this content
 *
 * @param  none
 * @return int - size of content in byte
 * @author Ludger Merkens 
 */
int 
get_content_size()
{
    if (!iContentID) // no or unfinished upload
        return 0;
    
    if ( iContentSize <= 0 )
      update_content_size();
    
    return iContentSize;
}


/**
 * Get the ID of the content in the database.
 *  
 * @return the content id
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
int get_content_id()
{
    return iContentID;
}

// versioning
void set_content_id(int id)
{
  if ( CALLER != get_factory(CLASS_DOCUMENT) )
      steam_error("Unauthorized call to set_content_id() !");
  iContentID = id;
  require_save(STORE_CONTENT);
}

/**
 * Get the content of the object directly. For large amounts
 * of data the download function should be used. It is possible
 * to pass a len parameter to the function so only the first 'len' bytes
 * are being returned.
 *  
 * @param int|void len
 * @return the content
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static string
_get_content(int|void len)
{
    string buf;
    mixed cerr;
    LOG_DB("content.get_content() of " + iContentID);
    
    if (iDownloads == 0)
    {
        object lock;
	catch(lock = writeMutex->trylock());
	if ( !objectp(lock) )
	    THROW("no simultanous write access on content", E_ACCESS);
	oLockWrite = lock;
    }
    iDownloads++;

    cerr = catch {
      buf = _Persistence->get_content( iContentID, len );
    };

    iDownloads--;
    if (iDownloads == 0)
	destruct(oLockWrite);

    if (cerr)
	throw(cerr);
    
    return buf;
}

string get_content(int|void len)
{
    return _get_content(len);
}

/**
 * set_content, sets the content of this instance.
 *
 * @param  string cont - this will be the new content
 * @return int         - content size (or -1?)
 * @see    receive_content, save_content
 *
 */
int
set_content(string cont)
{
    if ( !stringp(cont) ) 
	error("set_content: no content given - needs string !");

    // save directly! (use receive content and upload functionality
    // for large amount of data)
    prepare_upload(strlen(cont));

    iContentID = _Persistence->set_content( cont );

    // store content id and size
    iContentSize = strlen(cont);
    require_save(STORE_CONTENT);

    // call myself - write_now() finishes writting directly
    content_finished();
    return strlen(cont);
}

/**
 * When the object is deleted its content has to be removed too.
 *  
 */
final static void 
delete_content()
{
    if (iContentID)
    {
        object lock = writeMutex->lock();
        _Persistence->delete_content( iContentID );
        destruct(lock);
    }
}


static void content_finished() {
    // call for compatibility reasons
}

static void content_begin() {
}
