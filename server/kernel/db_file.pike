/* Copyright (C) 2000-2007  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 * $Id: db_file.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: db_file.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $";


/*
 * /kernel/db_file
 * this is the database file emulation, which stores a binary file
 * in a sequence of 64k blobs in a SQL database.
 */

#include <macros.h>

private int                         iID;
private static int          iNextRecNbr;     /* last current read */
private static int             iCurrPos;      /* current position */
private static int           iMaxRecNbr; /*  last rec_order block */
private static int           iMinRecNbr; /* first rec_order block */
private static string             sMode;            /* read/write */
private static string       sReadBuf="";    
private static string      sWriteBuf="";
private static int         iFileSize=-1; /* not set otherwise >=0 */
private static object        readRecord;
private static int        iStopReader=0;
private static int          iPrefetch=1;
private function                    fdb;
private static int          iLastAccess;

array get_database_handle(int id)
{
    return _Database->connect_db_file(id);
}

void create(int ID, string mode) {
    open(ID, mode);
}

#define READ_ONCE 100

/**
 * open a database content with given ID, if ID 0 is given a new ID
 * will be generated.
 *
 * @param   int ID      - (an Content ID | 0)
 * @param   string mode - 
 *               'r'  open file for reading  
 *               'w'  open file for writing  
 *               'a'  open file for append (use with 'w')  
 *               't'  truncate file at open (use with 'w')  
 *               'c'  create file if it doesn't exist (use with 'w')
 *		     'x'  fail if file already exist (use with 'c')
 *
 *          How must _always_ contain exactly one 'r' or 'w'.
 *          if no ID is given, mode 'wc' is assumed
 *          'w' assumes 'a' unless 't'
 *          't' overrules 'a'
 *
 * @return  On success the ID (>1) -- 0 otherwise
 * @see     Stdio.file
 * @author Ludger Merkens 
 */

int open(int ID, string mode) {
    sMode = mode;
    iID = ID;
    Sql.sql_result odbResult;    //	db = iID >> OID_BITS;
    
    if (!iID)
        sMode = "wc";
    [fdb, iID] = get_database_handle(iID);

    //    LOG("opened db_file for mode "+sMode+" with id "+iID);

    iCurrPos = 0;
    if (search(sMode, "r")!=-1)
    {
        odbResult =
            fdb()->big_query("select min(rec_order), max(rec_order) "+
                             "from doc_data where "+
                             "doc_id ="+iID);
        array res= odbResult->fetch_row();
        iMinRecNbr= (int) res[0];
        iMaxRecNbr= (int) res[1]; // both 0 if FileNotFound
        iNextRecNbr = iMinRecNbr;
        
        odbResult =
            fdb()->big_query("select rec_data from doc_data where doc_id="+iID+
                             " and rec_order="+iMinRecNbr);
        if (odbResult->num_rows()==1)
        {
            [sReadBuf] = odbResult->fetch_row();
	    sReadBuf = fdb()->unescape_blob(sReadBuf);
            if (strlen(sReadBuf)<MAX_BUFLEN) // we got the complete file
                iFileSize = strlen(sReadBuf);
            else
                iPrefetch = 1;               // otherwise assume prefetching
            iNextRecNbr++;
        }
        
        return ID;
    }
    if (search(sMode, "w")==-1) // neither read nor write mode given
        return 0;

    // Append to database, calculate next RecNbr
    odbResult = fdb()->big_query("select max(rec_order) from "+
                                "doc_data where doc_id = "+iID);
    if (!objectp(odbResult))
        iNextRecNbr = -1;
    else
        iNextRecNbr = ((int) odbResult->fetch_row()[0])+1;

    if (search(sMode, "c")!=-1)
    {
        if ((search(sMode,"x")!=-1) && (iNextRecNbr != -1))
            return 0;
	    
        if (iNextRecNbr == -1)
            iNextRecNbr = 0;
    }

    if (search(sMode, "t")!=-1)
    {
        if (iNextRecNbr!=-1)
            fdb()->big_query("delete from doc_data where doc_id = " + iID);
        iNextRecNbr = 1;
    }

    if (iNextRecNbr == -1) // 'w' without 'c' but file doesn't exist
        return 0;

    return iID;
}
    
private static void write_buf(string data) 
{
  _Database->write_into_database(iID, iNextRecNbr, data);
  iMaxRecNbr=iNextRecNbr;
  iNextRecNbr++;
  iFileSize=-1;
}

private static int write_buf_now(string data)
{
  iFileSize=-1;
  string line = "insert into doc_data values('"+
    fdb()->escape_blob(data)+"', "+ iID +", "+iNextRecNbr+")";
  iMaxRecNbr = iNextRecNbr;
  iNextRecNbr++;
  mixed err = catch{fdb()->big_query(line);};
  if (err) {
    FATAL("Fatal error while writting FILE into database: %O\n%O",err[0],err[1]);
  }
  return strlen(data);
}



void flush()
{
    if (search(sMode,"w")!=-1)
    {
      if (strlen(sWriteBuf) > 0)
	write_buf(sWriteBuf);
      iFileSize = (((iMaxRecNbr - iMinRecNbr)-1) * MAX_BUFLEN) +
	strlen(sWriteBuf);
    }
}
	
int close(void|function close_callback) 
{
  if (functionp(close_callback))
    _Database->write_into_database(iID, 0, close_callback);
  stop_reader();}


void destroy() {
    close();
}

static int sendByte = 0;    

int get_last_access() { return iLastAccess; }

static void check_status(object record)
{
    object mlock;
    mlock = record->fullMutex->lock();
    if ( functionp(record->restore) ) {
      record->restore(record);
      record->restore = 0;
    }
    destruct(mlock);

}

string read(int|void nbytes, int|void notall) 
{
    array(string) lbuf = ({});
    mixed                line;
    int               iSumLen;
    Sql.sql_result    odbData;


    if ( search(sMode,"r") == -1 )
      return 0;

    iLastAccess = time();

    
    if (!nbytes)               // all the stuff -> no queuing
    {
      odbData = fdb()->big_query("select rec_data from doc_data "+
				 "where doc_id="+iID+
				 " order by rec_order");
      while (line = odbData->fetch_row())
	lbuf += ({ fdb()->unescape_blob(line[0]) });
      return lbuf * "";
    } 
    else if ( !objectp(readRecord) && 
	      (iFileSize == -1 || iFileSize> MAX_BUFLEN ) && iPrefetch ) 
    {
	readRecord = _Database->read_from_database(iID, 
						   iNextRecNbr, 
						   iMaxRecNbr, 
						   this_object());
    }
    
    iSumLen = strlen(sReadBuf);
    lbuf = ({ sReadBuf });
    line = "";
    while ( iSumLen < nbytes && stringp(line) )
    {
        if  ( readRecord ) // check for Prefetched Content
        {
	  check_status(readRecord);
	  line = readRecord->contFifo->read();
        }
        else if (iNextRecNbr < iMaxRecNbr) // large files + seek
        {
            iPrefetch = 1;
	    readRecord = _Database->read_from_database(iID,
						       iNextRecNbr,
						       iMaxRecNbr, 
						       this_object());
	    check_status(readRecord);
            line = readRecord->contFifo->read();	
        }
        else
            line = 0; // small files
	
        if ( stringp(line) )
        {
            lbuf += ({ line });
            iSumLen += strlen(line);
        }
	else {
	  sMode = "";
	}
        if ( notall)
            break;
    }
    sReadBuf = lbuf * "";
    
    if (!strlen(sReadBuf))
        return 0;

    if (strlen(sReadBuf) <= nbytes)  // eof or notall
    {
        line = sReadBuf;
        sReadBuf = "";
        iCurrPos += strlen(line);
	sendByte += strlen(line);

        return line;
    }
    line = sReadBuf[..nbytes-1];
    sReadBuf = sReadBuf[nbytes..];
    iCurrPos += strlen(line);
    sendByte += strlen(line);
    return line;
}

int write_now(string data)
{
  int written = low_write(data, write_buf_now);
  written += write_buf_now(sWriteBuf);
  return written;
}

int write(string data)
{
  return low_write(data, write_buf);
}

static int low_write(string data, function write_buf) {
  int iWritten = 0;

  if (search(sMode, "w")==-1)
    return -1;

  sWriteBuf += data;
  while (strlen(sWriteBuf) >= MAX_BUFLEN)
  {
    write_buf(sWriteBuf[..MAX_BUFLEN-1]);
    sWriteBuf = sWriteBuf[MAX_BUFLEN..];
    iWritten += MAX_BUFLEN;
  }
  iCurrPos += iWritten;
  return iWritten;
}

object stat()
{
    object s = Stdio.Stat();
    s->size = sizeof();
    return s;
}

int sizeof() {

    if (iFileSize!=-1)  // already calculated
        return iFileSize;
	
    Sql.sql_result res;
    int  iLastChunkLen;

    if (search(sMode, "w")!=-1)
    {
        int erg;
        iLastChunkLen = strlen(sWriteBuf);

        erg = ((iMaxRecNbr-iMinRecNbr) * MAX_BUFLEN) + iLastChunkLen;
        return erg;
    }
    else
    {
        res = fdb()->big_query(
            "select length(rec_data) from doc_data "+
            "where doc_id ="+iID+" and rec_order="+iMaxRecNbr);
    
	mixed row = res->fetch_row();
	if ( arrayp(row) )
	  iLastChunkLen = ((int)row[0]);
	else
	  iLastChunkLen = 0;
    }

    iFileSize = ((iMaxRecNbr-iMinRecNbr) * MAX_BUFLEN) + iLastChunkLen;
    return iFileSize;
}

int dbContID() {
    return iID;
}


private static void stop_reader()
{
  if ( objectp(readRecord) ) {
    //werror("Trying to stop read operation on "+ readRecord->iID+"\n");
    readRecord->stopRead = 1;
  }
}

/**
 * seek in an already open database content to a specific offset
 * If pos is negative it will be relative to the start of the file,
 * otherwise it will be an absolute offset from the start of the file.
 * 
 * @param    int pos - the position as described above
 * @return   The absolute new offset or -1 on failure
 * @see      tell
 *
 * @caveats  The old syntax from Stdio.File->seek with blocks is not
 *           supported
 */

int seek(int pos)
{
    int SeekBlock;
    int SeekPos;
    Sql.sql_result odbResult;
    iPrefetch = 0;

    //werror("Seek(%d)\n", pos);

    if (pos<0)
        SeekPos = iCurrPos-SeekPos;
    else
        SeekPos = pos;
    SeekBlock = SeekPos / MAX_BUFLEN;
    SeekBlock += iMinRecNbr;

    stop_reader();  // discard prefetch and stop read_thread
    odbResult = fdb()->big_query("select rec_data from doc_data where doc_id="+
                                 iID+" and rec_order="+SeekBlock);
    if (odbResult->num_rows()==1)
    {
        [sReadBuf] = odbResult->fetch_row();
        sReadBuf = sReadBuf[(SeekPos % iMinRecNbr)..];
        iCurrPos = SeekPos;
        iNextRecNbr = SeekBlock+1;
        return iCurrPos;
    }
    return -1;
}

/**
 * tell the current offset in an already open database content
 * @return   The absolute offset
 */

int tell()
{
    return iCurrPos;
}

string _sprintf()
{
    return "kernel/db_file(id="+iID+", stopped="+iStopReader+")";
}
