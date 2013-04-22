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
 * $Id: types.pike,v 1.2 2009/08/07 16:14:56 nicke Exp $
 */

constant cvs_version="$Id: types.pike,v 1.2 2009/08/07 16:14:56 nicke Exp $";

inherit "/kernel/module";
inherit "/base/xml_parser";
inherit "/base/xml_data";

#include <macros.h>
#include <database.h>
#include <classes.h>
#include <assert.h>
#include <config.h>

//! This module reads some configuration files located in the
//! servers config/ directory and stores information about all
//! mime types and what sTeam class to create for a specific mime type.

#define MIME_FILE _Server->query_config("config-dir")+"mimetypes.txt"
#define CLASS_FILE _Server->query_config("config-dir")+"classtypes.txt"

#define DATA_TYPE 0
#define DATA_MIME 1
#define DATA_DESC 2
#define DATA_PRIO 3
#define DATA_EXT  4

private static mapping mMime;
private static mapping mExts;
private static array asDefaults = ({ "text/plain", "text/html", "text/wiki", "application/msword", "application/vnd.ms-powerpoint", "image/gif", "image/jpeg", "image/png", "application/pdf" });

private static mapping mClasses = ([ ]);
				 
array(string) get_classes() { return indices(mClasses); }

static void init_module()
{
    init_mime();
}

/**
 * Register a new class with a filename to create and a mimetype.
 * This will change the content of the CLASS_FILE.
 *  
 * @param string cl - the class to register
 * @param string doc_class - the class to clone
 * @param string mime - the mimetype
 * @param string desc - the description for this document class.
 * @author Thomas Bopp (astra@upb.de) 
 */
static void 
register_class(string cl, string doc_class, string mime, string desc)
{
    if ( !_SECURITY->access_register_class(0, 0, CALLER) )
	return;
    mMime[cl] = ({ doc_class, mime, desc });
    Stdio.File f = Stdio.File(CLASS_FILE, "wct");
    f->write("<classes>\n");
    foreach(indices(mMime), string ext) {
	f->write("\t<type>\n\t\t<ext>"+ext+"</ext>\n\t\t<class>"+
		 mMime[ext][DATA_TYPE]+"</class>\n\t\t<desc>"+
		 mMime[ext][DATA_DESC]+"</desc>\n\t</type>\n");
    }
    f->write("</classes>\n");
    f->close();
}

/**
 * query_document_type, returns an array of document type information 
 * depending on the given filename.
 *  
 * @param filename - the filename
 * @return the document-type of that file (depends only on extension)
 * @author Thomas Bopp 
 * @see query_mime_type
 */
array(string)
query_document_type(string filename)
{
    string base_type, file_extension;
    array(string)             ploder;
    int                            i;

    LOG("query_document_type()");
    if ( !mappingp(mMime) )
	init_mime();
    
    /* initialization */
    base_type      = "";
    file_extension = "";
    
    ploder = filename / "."; /* explode, hmm */
    if ( !sizeof(ploder) )
	return ({ "Document", "gen" });

    file_extension = ploder[sizeof(ploder)-1];

    for ( i = strlen(file_extension) - 1; i >= 0; i-- )
	if ( file_extension[i] >= 'A' && file_extension[i] <= 'Z' )
	    file_extension[i] -= ('A' - 'a');
    file_extension = lower_case(file_extension);
    LOG("File Extension:" + file_extension);
    if ( arrayp(mMime[file_extension]) )
    {
	return ({ mMime[file_extension][DATA_TYPE], 
		      file_extension });
    }

    return ({ "Document", file_extension });
}

/**
 * Returns the documents extensions for a given mimetype.
 *  
 * @param string mtype - the mimetype
 * @return array of extensions for this mime type with information
 */
array query_document_type_mime(string mtype)
{
    if ( arrayp(mExts[mtype]) )
	return ({ mExts[mtype][DATA_TYPE], "" });
    else
	return ({ "Document", "" });
}

/**
 * Return the array of possible extensions for the given mimetype.
 *  
 * @param string mtype - the mimetype
 * @return array of extensions for mtype
 */
array query_mimetype_extensions(string mtype)
{
    array extensions = ({ });
    if ( !arrayp(mExts[mtype]) )
	return extensions;

    foreach( mExts[mtype], mixed ext ) {
	extensions += ({ ext[DATA_EXT] });
    }
    return extensions;
}

void 
register_extensions(string mtype, string desc, array extensions, void|int def)
{
    int i = 0;
    if ( mExts[mtype] )
	error("Cannot reregister extension !");
    mExts[mtype] = extensions;

    foreach(extensions, string ext) {
	i++;
	mMime[ext] = ({ "Document", mtype, desc, i, ext });
    }
    if ( def && search(asDefaults, mtype) == -1 )
	asDefaults += ({ mtype });
}

array(string) get_default_mimetypes()
{
    return copy_value(asDefaults);
}

/**
 * Return the mimetype for a given extension.
 *  
 * @param doc - the document extension
 * @return the mime-type of the document
 * @author Thomas Bopp 
 * @see query_document_type
 */
string
query_mime_type(string doc)
{
    if ( ! stringp( doc ) )
        return MIMETYPE_UNKNOWN;

    array(mixed) data;

    if ( !mappingp(mMime) )
	init_mime();

    data = mMime[lower_case(doc)];
    if ( !arrayp(data) )
	return MIMETYPE_UNKNOWN;
    
    if ( !stringp(data[DATA_MIME]) )
      steam_error("Failure in types: Non-string value for mimetype "+doc);
    if ( data[DATA_MIME] == "" )
      steam_error("Failure in types: Empty string value for mimetype "+doc);

    return data[DATA_MIME];
}

/**
 * Return the mime description for an extension.
 *  
 * @param doc - the document extension
 * @return the description of the mime-type
 * @author Thomas Bopp 
 * @see query_mime_type
 */
string
query_mime_desc(string doc)
{
    array(mixed) data;

    if ( !mappingp(mMime) )
	init_mime();

    data = mMime[lower_case(doc)];
    if ( !arrayp(data) )
	return "Generic";
    
    return data[DATA_DESC];
}

/**
 * init_mime
 *  
 * @author Thomas Bopp 
 * @see query_types
 */
nomask void
init_mime()
{
    array(string)                   lines;
    array(string)                  tokens;
    string                            buf;
    int                  start, i, j, len;
    mixed                            data;

    buf = Stdio.read_file(CLASS_FILE);

    ASSERTINFO(stringp(buf),
	       "Initialization error: class file missing ["+CLASS_FILE+"]\n");

    //lines = buf / "\n";
    mMime = ([ ]);
    NodeXML n = parse_data(buf);
    string classname;
    foreach(n->children, NodeXML type) {
	NodeXML t = type->get_node("ext");
        classname = type->get_node("class")->data;
        if ( stringp(classname) )
            mClasses[classname] = 1;
        mMime[t->data] = ({ classname,
			    MIMETYPE_UNKNOWN,
			    type->get_node("desc")->data, 0 });
        }

    // read the mimetypes.txt 
    buf = Stdio.read_file(MIME_FILE);
    if ( !stringp(buf) ) {
	FATAL("Initialization error: mime file missing! ["+MIME_FILE +"]\n");
	return;
    }
    lines = buf / "\n";
    
    for ( i = sizeof(lines) - 1; i >= 0; i-- ) {
	len = strlen(lines[i]);
	if ( len == 0 || lines[i][0] == '#' )
	    continue;
	j = 0; start = -1; tokens = ({ });
	while ( j < len ) {
	    if ( lines[i][j] == ' ' || lines[i][j] == '\t' ) {
		if ( start != -1 ) {
		    tokens += ({ lines[i][start..j-1] });
		}
		start = -1;
	    }
	    else if ( start == -1 ) {
		start = j;
	    }
	    j++;
	}
	if ( start != -1 )
	    tokens += ({ lines[i][start..] });

	if ( sizeof(tokens) > 1 ) {
	    for ( j = sizeof(tokens) - 1; j >= 1; j-- ) {
		data = mMime[tokens[j]];
		
		if ( arrayp(data) ) {
		    // remember the priority of extensions
		    // html htm wiki, then html should have priority (lowest j)
		    mMime[tokens[j]][DATA_MIME] = tokens[0];
		    mMime[tokens[j]][DATA_PRIO] = j;
		}
		else
		    mMime[tokens[j]] = 
			({ "Document", tokens[0], "Generic", j });
	    }
	}
    }
    mExts = ([ ]);
    foreach ( indices(mMime), string ext ) {
        // mExts mapping holds mimetype:data
	if ( arrayp(mExts[mMime[ext][DATA_MIME]]) )
	    mExts[mMime[ext][DATA_MIME]] += ({ mMime[ext]+({ ext }) });
	else {
	    mExts[mMime[ext][DATA_MIME]]  = ({ mMime[ext]+({ ext })  });
	}
    }
    foreach ( indices(mExts), string mtype ) {
	if ( sizeof(mExts[mtype]) > 1 ) {
	    array sorter = ({ });
	    foreach(mExts[mtype], mixed ext)
		sorter += ({ ext[DATA_PRIO] });
	    sort(mExts[mtype], sorter);
	}
    }
}

/**
 * Return the whole mapping of saved types. The mapping contains
 * file extension: informations (array)
 *  
 * @return the mapping with all type definitions
 * @author Thomas Bopp 
 * @see init_mime
 */
mapping
query_types()
{
    return copy_value(mMime);
}


/**
 * return the class for a doctype (extension of a file).
 *  
 * @param doc - the doctype (or extension)
 * @return the class
 * @author Thomas Bopp (astra@upb.de) 
 */
string query_document_class(string doc)
{
    mixed data;

    data = mMime[doc];
    if ( !arrayp(data) )
	return CLASS_NAME_DOCUMENT;
    LOG("class is " + data[DATA_TYPE]);
    return data[DATA_TYPE];
}

/**
 * Return the document class for the given mimetype.
 * The class can be found in the classes/ Folder of sTeam.
 *  
 * @param string mtype - the mimetype
 * @return string of class type used
 */
string query_document_class_mime(string mtype)
{
    if ( arrayp(mExts[mtype]) )
	return mExts[mtype][0][DATA_TYPE];
    else
	return CLASS_NAME_DOCUMENT;
}


string get_identifier() { return "types"; }
