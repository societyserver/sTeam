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
 * $Id: DocumentFactory.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $
 */

constant cvs_version="$Id: DocumentFactory.pike,v 1.2 2009/08/07 15:22:36 nicke Exp $";

inherit "/factories/ObjectFactory";

#include <macros.h>
#include <attributes.h>
#include <database.h>
#include <events.h>
#include <types.h>
#include <classes.h>
#include <access.h>

/**
 * Initialization callback for the factory.
 *  
 */
static void init_factory()
{
    ::init_factory();
    init_class_attribute(DOC_LAST_MODIFIED, CMD_TYPE_TIME, 
			 "last modified", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, 0);
    init_class_attribute(DOC_USER_MODIFIED, CMD_TYPE_OBJECT,
			 "last modified by user",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, 0);
    init_class_attribute(DOC_LAST_ACCESSED, CMD_TYPE_TIME, 
			 "last accessed", 
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, 0);
    init_class_attribute(DOC_MIME_TYPE, CMD_TYPE_STRING, 
			 "for example text/html",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, "");
    init_class_attribute(DOC_VERSIONS, CMD_TYPE_MAPPING, 
			 "versioning of a document",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, ([ ]));
    init_class_attribute(DOC_TYPE, CMD_TYPE_STRING, 
			 "the document type/extension",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER,"");
    init_class_attribute(DOC_TIMES_READ, CMD_TYPE_INT, "how often read",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_SERVER, 0);
    init_class_attribute(DOC_AUTHORS, CMD_TYPE_ARRAY, "Names of Authors",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_USER, ({ }) );
    init_class_attribute(DOC_BIBTEX, CMD_TYPE_STRING, 
			 "Bibtex entry of a publication",
			 0, EVENT_ATTRIBUTES_CHANGE, 0,
			 CONTROL_ATTR_USER, "");
}

    
/**
 * Create a new instance of a document. The vars mapping should contain
 * the following entries:
 * url - the filename     or
 * name - the filename
 * mimetype - the mime type (optional)
 * externURL - content should be downloaded from the given URL.
 *  
 * @param mapping vars - some variables for the document creation.
 * @return the newly created document.
 * @author Thomas Bopp (astra@upb.de) 
 */
object execute(mapping vars)
{
    string ext, doc_class, fname, mimetype;
    array(string)                         tokens;
    object                             cont, obj;
    string                                folder;

    string url = vars["url"];
    if ( !stringp(url) ) {
	url = vars["name"];
	fname = url;
	folder = "";
    }
    else {
        fname  =  basename(url);
	folder = dirname(url);
	if ( strlen(folder) > 0 ) {
	    cont = get_module("filepath:tree")->path_to_object(folder, true);
	    if ( !objectp(cont) )
		steam_error("The Container " + folder + " was not found!");
	    if ( !(cont->get_object_class() & CLASS_CONTAINER) )
	      steam_error("The destination path is not a container !");
	}
	
    }

    try_event(EVENT_EXECUTE, CALLER, url);

    if (!mappingp(vars->attributes))
      vars->attributes = ([ ]);

    if ( stringp(vars["mimetype"]) ) 
      mimetype = vars["mimetype"];
    else if ( stringp(vars["attributes"][DOC_MIME_TYPE]) )
      mimetype = vars["attributes"][DOC_MIME_TYPE];

    if ( !stringp(mimetype) || 
	 mimetype == "auto-detect" ||
	 search(mimetype, "/") == -1 ) 
    {
	tokens = fname / ".";
	if ( sizeof(tokens) >= 2 ) {
	    ext = tokens[-1]; // last token ?
	    ext = lower_case(ext);
	}
	else {
	    ext = "";
	}
	mimetype = _TYPES->query_mime_type(ext);
	doc_class = _TYPES->query_document_class(ext);
    }
    else {
	ext = "";
	doc_class = _TYPES->query_document_class_mime(mimetype);
    }
    vars->attributes[DOC_MIME_TYPE] = mimetype;

    if ( vars->transient ) {
      if ( mappingp(vars->attributes) )
	vars->attributes[OBJ_TEMP] = 1;
      else
	vars->attributes = ([ OBJ_TEMP : 1 ]);
    }
    
    SECURITY_LOG("creating " + doc_class);
    if ( objectp(vars["move"]) ) {
	obj = object_create(fname, doc_class, vars["move"],
			    vars["attributes"],
			    vars["attributesAcquired"], 
			    vars["attributesLocked"],
			    vars["sanction"],
			    vars["sanctionMeta"]);
    }
    else if ( objectp(cont) )
    {
	// Object is created somewhere
	SECURITY_LOG("Creating new object in "+ folder);
	obj = object_create(fname, doc_class, cont,
			    vars["attributes"],
			    vars["attributesAcquired"], 
			    vars["attributesLocked"],
			    vars["sanction"],
			    vars["sanctionMeta"]);
    }
    else {
	SECURITY_LOG("Creating new object in void");
	obj = object_create(
	    fname, doc_class, 0, vars["attributes"],
	    vars["attributesAcquired"], vars["attributesLocked"],
	    vars["sanction"],
	    vars["sanctionMeta"]);
    }

    function obj_set_attribute = obj->get_function("do_set_attribute");

    if ( objectp(obj) ) {
        obj_set_attribute(DOC_TYPE, ext);
	obj_set_attribute(DOC_MIME_TYPE, mimetype);
    }
    if ( objectp(vars["acquire"]) )
	obj->set_acquire(vars["acquire"]);
    
    if ( objectp(vars["content_obj"]) ) {
      string content = vars["content_obj"]->get_content();
      if ( stringp(content) )
	obj->set_content(content);
    }
    if ( vars->content_id ) {
      object caller = CALLER;
      if ( !_SECURITY->valid_object(caller) )
	steam_error("Calling object tries to change content id - not authorized!");
      if ( caller->get_content_id() != vars->content_id )
	steam_error("Only versioning is able to reuse content ids (caller: %O)!", caller);
      obj->set_content_id(vars->content_id);
    }


    if ( stringp(vars["externURL"]) ) {
	string uri, r_vars;
	mapping va = ([ ]);

	if ( sscanf(vars->externURL, "%s?%s", uri, r_vars) == 2 ) {
	    string v, k;
	    array index = r_vars / "&";
	    if ( arrayp(index) ) {
		foreach(index, string zuweisung) {
		    sscanf(zuweisung, "%s=%s", k, v);
		    va[k] = v;
		}
	    }
	    else {
		sscanf(r_vars, "%s=%s", k, v);
		va[k] = v;
	    }
	}
	thread_create(download_url, obj, uri, va);
    }

    run_event(EVENT_EXECUTE, CALLER, url);
    return obj->this();
}

/**
 * Download content from an extern URL.
 *  
 * @param object doc - the document
 * @param string url - the URL to download from.
 * @author <a href="mailto:astra@upb.de">Thomas Bopp</a>) 
 */
static void download_url(object doc, string url, void|mapping vars)
{
    MESSAGE("Downloading url: %s, %O", url, vars);
    array res = Protocols.HTTP.get_url_nice(url, vars);
    if ( arrayp(res) ) {
      doc->set_content(res[1]);
      doc->set_attribute(DOC_MIME_TYPE, res[0]);
    }
    else
      FATAL("An error occured while trying to download %s", url);
}

int change_document_class(object doc) 
{
    // change class depending on mime type
    if ( !_SECURITY->access_write(0, doc, CALLER) )
	return 0;

    string mime = doc->query_attribute(DOC_MIME_TYPE);
    object typesModule = get_module("types");
    if ( !objectp(typesModule) )
	steam_error("Unable to find required types module !");
    string classname = typesModule->query_document_class_mime(mime);
    if ( classname != doc->get_class() ) {
	if ( _Persistence->change_object_class(doc, classname) ) {
	  MESSAGE("DocumentFactory: Changing class from " + 
		  doc->get_class() + " to " + classname);
          call(doc->drop, 0.0);
          return 1;
	}
	FATAL("DocumentFactory: Failed to change class from "+
		doc->get_class() + " to " + classname);
	return 0;
    }
    return 0;
}
string get_identifier() { return "Document.factory"; }
string get_class_name() { return "Document"; }
int get_class_id() { return CLASS_DOCUMENT; }


mixed test()
{
    object doc = execute( ([ "name" : "test it.jpg", ]) );
    Test.test( "image mimetype in .jpg document",
           ( search(doc->query_attribute(DOC_MIME_TYPE), "image/") == 0 ) );

    doc->delete();
    doc = execute ( ([ "name": "test.html", "mimetype":"text/html", ]) );
    Test.test( "text/html mimetype produces DocHTML class",
               (doc->get_object_class() & CLASS_DOCHTML) );
    Test.test( "got same mimetype as defined",
               ( doc->query_attribute(DOC_MIME_TYPE) == "text/html" ) );
    doc->set_content("test");
    
    Test.test("Content",
	      doc->get_content() == "test");

    object dup = doc->duplicate();
    Test.test("Duplicated Object", 
	      dup->get_object_class()==doc->get_object_class());
    Test.test("Duplicated Name",
	      dup->get_identifier() == doc->get_identifier());
    Test.test("Duplicated Content",
	      dup->get_content() == doc->get_content());

    doc->delete();
    dup->delete();

    doc = execute ( ([ "name": "test.test.html", ]) );
    Test.test( ".html ending produces DocHTML",
               (doc->get_object_class() & CLASS_DOCHTML) );
    Test.test( "got same mimetype as expected",
               ( doc->query_attribute(DOC_MIME_TYPE) == "text/html" ) );

    // try to switch document type
    doc->set_attribute(DOC_MIME_TYPE, "text/xsl");
    // document classes are changed, but never to 'Document',
    // because all derived classes only include some special functionality
    string mclass = get_module("types")->query_document_class_mime("text/xsl");
    
    Test.test( "text/xsl produces DocXSL",
               ( mclass == "DocXSL" ) );
    
    Test.test( "URL with folder submitted throws",
               catch( execute( ([ "url": "time/money" ]) ) ) );
    
    object test1 = execute( ([ "name" : "test", ]) );
    Test.test( "name test produces unknown mimetype",
               ( test1->query_attribute(DOC_MIME_TYPE) == MIMETYPE_UNKNOWN ) );
    // now rename
    test1->set_attribute(OBJ_NAME, "test.xsl");

    object script = execute( ([ "name": "test.pike", ]) );
    Test.test( ".pike provides DocLpc instance",
               ( script->get_class() == "DocLpc" ) );
    Test.start_test(script);

    object xsl = execute( ([ "name":"test.xsl" ]) );
    Test.start_test(xsl);

    object cont;
    cont = get_module("filepath:url")->path_to_object("/__test__");
    if ( objectp(cont) )
      cont->delete();
    
    cont = get_factory(CLASS_CONTAINER)->execute((["name":"test_container"]));
    cont->set_acquire(0);
    cont->set_attribute(OBJ_URL, "/__test__");
    cont->move(OBJ("/"));

    Test.test("container path",
	      _FILEPATH->object_to_filename(cont) == "/test_container",
	      "Wrong path for Container: "+_FILEPATH->object_to_filename(cont));
	      
    object file = execute( (["name":"test.txt"]) );
    file->set_content("Hello World!");
    file->move(cont);
    Test.test("path",
	      file->query_attribute(OBJ_PATH)=="/test_container/test.txt",
	      "False path for test.txt in test_container: "+
	      file->query_attribute(OBJ_PATH));
    doc->set_attribute(OBJ_NAME, "doc.xsl");
    doc->move(cont);
    cont->set_attribute(OBJ_NAME, "testcontainer");
    Test.test("renamed path",
	      file->query_attribute(OBJ_PATH)=="/testcontainer/test.txt",
	      "False path for test.txt in testcontainer: " +
	      file->query_attribute(OBJ_PATH));
    
    if ( objectp(doc) && objectp(test1) ) {
      // needs thread/call_out because Protocols.HTTP would block
      Test.add_test_function( test_more, 5, doc, test1, mclass, cont, 1 );
    }
    else
      Test.skipped( "additional tests", "test objects were not created" );

    return doc;
}

static void test_threaded(object cont, object doc, object test1)
{
  object user = this_user() || USER("root");
  
  Standards.URI url = Standards.URI("https://"+_Server->query_config("web_server") + "/create.xml");
  
  if ( objectp(OBJ("/documents/create.xml")) ) {
    url->user = "root";
    url->password = user->get_ticket(time()+600);
    Protocols.HTTP.put_url(url, CONTENTOF("/documents/create.xml"));
    Test.test( "uploading /create.xml to "+ url->get_path_query(),
               objectp(doc = _FILEPATH->path_to_object("/create.xml")) );
    Test.test( "correct creator of uploaded /create.xml",
               (objectp(doc) && doc->get_creator() == user ) );
    Test.test( "correct mimetype of uploaded /create.xml",
               (objectp(doc) && doc->query_attribute(DOC_MIME_TYPE) == "text/xml" ) );
  }
  else
    Test.skipped( "upload", "no create.xml installed" );

  mixed query;
  if ( stringp(_Server->query_config("web_server")) )
    query = Protocols.HTTP.get_url("http://"+_Server->query_config("web_server") + "/__test__/");
  if ( query ) {
    query = (mapping)query;
    Test.test( "fetching restricted container gives 401",
               ( query->status == 401 ), "fetch gave %O", query->status );
    query = (mapping)Protocols.HTTP.get_url("http://"+_Server->query_config("web_server") + "/__test__/test.txt");
    Test.test( "fetching restricted file gives 401",
               ( query->status == 401 ), "fetch gave %O\n  data: %O",
               query->status, query->data );
    query = (mapping)Protocols.HTTP.get_url("http://"+_Server->query_config("web_server") + "/__test__/doc.xsl");
    Test.test( "fetching restricted empty file gives 401",
               ( query->status == 401 ), "fetch gave %O", query->status );
    
    // open it
    url = Standards.URI("http://"+_Server->query_config("web_server") + "/__test__/test.txt");
    url->user = "root";
    url->password = user->get_ticket(time()+60);
    object test = cont->get_object_byname("test.txt");

    Test.test("looking for test.txt", objectp(test));
    if ( objectp(test) )
      test->sanction_object(GROUP("steam"), SANCTION_READ);

    query = (mapping)Protocols.HTTP.get_url(url);
    Test.test( "fetching published file gives 200",
               ( query->status == 200 ), "fetch gave %O", query->status );
  }
  else
    Test.skipped( "fetching restricted objects",
                  "no web_server defined" );

   if ( objectp(doc) ) doc->delete();
   if ( objectp(test1) ) test1->delete();
   if ( objectp(cont) ) cont->delete();

}

void test_more(object doc, object test1, string mclass, object cont, int nr_try )
{
  werror("DocumentFactory->test_more(%O,%O,%O,%O,%O)\n",
         doc, test1, mclass,cont,nr_try);
  if ( doc->status() != PSTAT_DISK || test1->status() != PSTAT_DISK ) {
    if ( nr_try > 10 ) {
      MESSAGE("DocumentFactory: test_more() failed to drop documents !");
      Test.skipped( "additional tests", "failed to drop documents, tried %d "
                    +"times", nr_try );
      return;
    }
    MESSAGE("DocumentFactory: test_more() waiting for drop of documents !");
    doc->drop();
    test1->drop();
    Test.add_test_function( test_more, 5, doc, test1, mclass, cont, nr_try+1 );
    return;
  }

  Test.test( "changing document class", ( doc->get_class() == mclass ), 
	     "class of %O is %O, should be DocXSL",
             doc, doc->get_class() );

  Test.add_test_function_thread( test_threaded, 0, cont, doc, test1 );
}

array(object) get_all_objects()
{
  array result = ({ });
  array classes = ({ "Document", "DocXSL", "DocLpc", "DocGraphics", "DocXML",
                     "DocHTML" });
  foreach(classes, string clname) {
    result += _Database->get_objects_by_class("/classes/"+clname);
  }
  return result;
}
