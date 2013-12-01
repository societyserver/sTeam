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
 * $Id: DocFile.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

constant cvs_version="$Id: DocFile.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $";

#include <classes.h>
#include <database.h>
#include <macros.h>

//#define DOC_DEBUG

#ifdef DOC_DEBUG 
#define DEBUG_DOC(s) werror(s+"\n")
#else
#define DEBUG_DOC
#endif

static object    steamObject;
static object        oCaller;
static string         buffer; // read (ahead) buffer
static int          position; // read position
static int      doc_position; // position inside document
static mixed           fstat;
static function  contentRead; // read content from this function
static function contentWrite; // write content to this function
static string      sProtocol;
static int     last_response;

int error = 0;

void 
create(object document, void|string type, void|mapping vars, void|string prot, void|string token)
{
    if ( !objectp(document) ) 
      steam_error("DocFile: cannot create - document is null !");

    steamObject = document;
    oCaller = CALLER;
    buffer = "";
    position = 0;
    doc_position = 0;
    last_response = time();
    if ( !stringp(type) )
	type = "r";

    if ( document->get_object_class() & CLASS_LINK )
      document = document->get_link_object();

    if ( search(type, "r") >= 0 && 
	 document->get_object_class() & CLASS_DOCUMENT ) 
    {
      if ( document->get_content_size() > 0 ) {
	contentRead = document->get_content_callback(vars);
	fill_buffer(65536);
      }
      else 
        _SECURITY->access_read(0, document, oCaller);

      fstat = document->stat();
    }
    else if ( search(type, "w") >= 0 ) {
      fstat = document->stat();
      contentWrite = steamObject->receive_content(0, token);
    }
    else
      fstat = document->stat();
    
    if ( !stringp(prot) )
      sProtocol = "ftp";
    else
      sProtocol = prot;
}

int is_file() { return steamObject->get_object_class() & CLASS_DOCUMENT; }
int is_dir() { return steamObject->get_object_class() & CLASS_CONTAINER; }
int get_last_response() { return last_response; }

int write(string data)
{
    last_response = time();
    if ( !functionp(contentWrite) )
	contentWrite = steamObject->receive_content(0);
    if ( !functionp(contentWrite) ) {
      steam_error("Unable to write data %O\n\n no receive Content in %O",
                  data, steamObject->get_object());
    }
    
    contentWrite(data);
    return strlen(data);
}

void close()
{
  if ( functionp(contentWrite) ) {
    catch(contentWrite(0));
  }

  if ( functionp(contentRead) ) {
      object obj = function_object(contentRead);
      if ( objectp(obj) )
	  catch(obj->close());
  }
  contentWrite = 0;
  position = 0;
  contentRead = 0;
  doc_position = 0;
}

void destroy()
{
  if ( functionp(contentWrite) ) {
    catch(contentWrite(0));
  }

  if ( functionp(contentRead) ) {
      object obj = function_object(contentRead);
      if ( objectp(obj) )
	  catch(obj->close());
  }
  contentWrite = 0;
  position = 0;
  contentRead = 0;
  doc_position = 0;
}

static int fill_buffer(int how_much)
{
    int buf_len = strlen(buffer);
    DEBUG_DOC("reading " + how_much + " bytes into buffer, previously "+
	      buf_len + " bytes.\n");
    while ( buf_len < how_much ) {
	string str = contentRead(doc_position);
	if ( !stringp(str) || strlen(str) == 0 )
	    return strlen(buffer);
	DEBUG_DOC("contentRead function returns " + strlen(str) + " bytes.\n");
	buffer += str;
	buf_len = strlen(buffer);
	doc_position += strlen(str);
    }
    return strlen(buffer);
}

void set_nonblocking() 
{
}

void set_blocking()
{
}

int _sizeof()
{
  // this should never happen: we already got more data
  // from the database than the documents content size ?!!
  if ( steamObject->get_content_size() < doc_position )
    return doc_position; // position inside the document

  return steamObject->get_content_size();
}

string read(void|int len, void|int not_all)
{
    last_response = time();
    if ( position == _sizeof() ) {
	position++;
	return "";
    }
    else if ( position > _sizeof() ) {
	return 0;
    }

    if ( !intp(len) ) {
	fill_buffer(steamObject->get_content_size());
	return buffer;
    }
    int _read = fill_buffer(len);
    string buf;
    if ( _read < len ) {
	buf = copy_value(buffer);
	buffer = "";
	position += _read;
	return buf;
    }
    buf =  buffer[..len-1];
    position += len;
    buffer = buffer[len..];
    fill_buffer(65536); // read ahead;
    return buf;
}

int seek(int pos)
{
  int offset = pos - position;

  //fill_buffer(_sizeof());
  fill_buffer(offset + 65536);
  // cut everything from current position
  buffer = buffer[offset..];
  position = pos;
  return position;
}

object dup()
{
  return ((program)"DocFile")(steamObject, "r");
}

object get_document()
{
  return steamObject;
}

final mixed `->(string func)
{
    return this_object()[func];
}

Stdio.Stat stat() 
{ 
    mixed res = fstat;
    if ( !arrayp(res) )
      res = steamObject->stat();
    Stdio.Stat st = Stdio.Stat();
    st->atime = res[4];
    st->mtime = res[3];
    st->ctime = res[2];
    st->gid   = res[5];
    st->mode  = res[0];
    st->size  = res[1];
    st->uid   = res[6];
    return st;
}

string describe() 
{ 
    return "DocFile("+
	_FILEPATH->object_to_filename(steamObject) + 
	"," + _sizeof() + " bytes,"+
	", at " + position + ", ahead "+ doc_position + ")";
}
	
	
object get_creator() { return this_user(); }
string get_identifier() { return "Document-File"; }
object get_object_id() { return steamObject->get_object_id(); }
int get_object_class() { return steamObject->get_object_class(); }

object this() 
{ 
  if ( IS_SOCKET(oCaller) )
    return oCaller->get_user_object();
  return oCaller->this(); 
}
string get_client_class() { return sProtocol; } // for compatibility


