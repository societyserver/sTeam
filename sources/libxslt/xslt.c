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
 * $Id: xslt.c,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#include <string.h>
#include <stdarg.h>
#include <libxml/xmlmemory.h>
#include <libxml/debugXML.h>
#include <libxml/HTMLtree.h>
#include <libxml/xmlIO.h>
#include <libxml/DOCBparser.h>
#include <libxml/xinclude.h>
#include <libxml/catalog.h>
#include <libxml/xmlversion.h>
#include <libxslt/xslt.h>
#include <libxslt/xsltInternals.h>
#include <libxslt/transform.h>
#include <libxslt/xsltutils.h>
#include <libxslt/xsltconfig.h>


#include "global.h"
#include "interpret.h"
#include "stralloc.h"
#include "pike_macros.h"
#include "module_support.h"
#include "mapping.h"
#include "threads.h"

#include <stdio.h>
#include <fcntl.h>

#include "xslt.h"
#include "xml_dom.h"

//#define XSLT_DEBUG 1

#ifdef XSLT_DEBUG
#define DEBUG_XSLT(d) fprintf(stderr, d)
#else
#define DEBUG_XSLT(d)
#endif

extern int xmlLoadExtDtdDefaultValue;
xmlExternalEntityLoader defaultLoader = NULL;

int xslWasInit;
struct program *xslt_program=NULL;
struct program *stylesheet_program=NULL;

//! Free the allocated xslt storage
//!
//!
static void free_xslt_storage(struct object *o)
{
    if(THIS->base_uri != NULL)  free_string(THIS->base_uri);
    if(THIS->variables != NULL) free_mapping(THIS->variables);
    if(THIS->xml != NULL)       free_string(THIS->xml);
    if(THIS->language != NULL)       free_string(THIS->language);
    if(THIS->charset)           free(THIS->charset);
    if(THIS->content_type)      free(THIS->content_type);
    if(THIS->stylesheet != NULL ) xsltFreeStylesheet(THIS->stylesheet);
    if(THIS->match_include != NULL ) free_svalue(THIS->match_include);
    if(THIS->open_include != NULL ) free_svalue(THIS->open_include);
    if(THIS->read_include != NULL ) free_svalue(THIS->read_include);
    if(THIS->close_include != NULL ) free_svalue(THIS->close_include);
    if(THIS->file != NULL ) free_object(THIS->file);

    MEMSET(THIS, 0, sizeof(xslt_storage));
}

//!
//! Free the stylesheet storage when the object is destructed
//!
static void free_stylesheet_storage(struct object *o)
{
    stylesheet_storage* store = (stylesheet_storage*)o->storage;
    
    MEMSET(store, 0, sizeof(stylesheet_storage));
}

//!
//! Initialization routine for the storage
//!
static void init_xslt_storage(struct object *o)
{
    MEMSET(o->storage, 0, sizeof(xslt_storage));
}

//!
//! Initialization for the stylesheet storage.
//!
static void init_stylesheet_storage(struct object *o)
{
    MEMSET(o->storage, 0, sizeof(stylesheet_storage));
}

//!
//! Creation function for the Parser object.
//!
void f_create(INT32 args)
{
    pop_n_elems(args);
}

//!
//! Set the xml Data for the transformation.
//!
void f_set_xml_data(INT32 args)
{
    struct pike_string* xml_data;

    if ( args != 1 )
	Pike_error("XSLT.Parser()->set_xml_data: Expected one argument.\n");

    if( THIS->xml != NULL ) 
	free_string(THIS->xml);
    if ( THIS->err_str != NULL ) {
	free_string(THIS->err_str);
	THIS->err_str = NULL;
    }
    THREADS_ALLOW();
    THREADS_DISALLOW();
    
    switch ( ARG(1).type ) {
    case T_STRING:
	xmlSetGenericErrorFunc(THIS, xml_error);
	xml_data = Pike_sp[-args].u.string;
	//add_ref(THIS->xml);
	THIS->doc = xmlParseMemory(xml_data->str, xml_data->len);
	if ( THIS->err_str != NULL ) {
	    // only free doc at this point
	    xmlFreeDoc(THIS->doc);
	    Pike_error(THIS->err_str->str);
	}
	break;
    case T_OBJECT:
	CHECK_DOM(Pike_sp[0-1].u.object);
	add_ref(Pike_sp[0-1].u.object);
	THIS->doc = OBJ2_DOM(Pike_sp[0-1].u.object)->domDoc;
	break;
    default:
	Pike_error("XSLT.Parser()->set_xml_data: Expected string|object.\n");
    }


    
    pop_n_elems(args);    
}


//!
//! Set the variables used for transformation.
//!
void f_set_variables(INT32 args)
{
    if ( args != 1 )
	Pike_error("XSLT.Parser()->set_variables: Expected one argument.\n");
    if ( Pike_sp[-args].type != T_MAPPING )
	Pike_error("XSLT.Parser()->set_variables: Expected Mapping\n");
    if ( THIS->variables != NULL )
	free_mapping(THIS->variables);
    THIS->variables = Pike_sp[-args].u.mapping;
    add_ref(THIS->variables);
    pop_n_elems(args);
}

//!
//! @param
//!
void xsl_error(void* ctx, const char* msg, ...) {
    va_list args;
    char buf[1024];
    char out[2048] = { 0 };
    xslt_storage* store = (xslt_storage*) ctx;


    DEBUG_XSLT("xsl_error()\n");
    if ( ctx == NULL ) {
	fprintf(stderr, "No error context, error: %s\n", msg);
	return;
    } 
    if ( msg == NULL ) {
      fprintf(stderr, "xsl_error() with no messages !");
      return;
    }
      
    va_start(args, msg);
    vfprintf(stderr, msg, args);
    va_end(args);

    THREADS_ALLOW();
    THREADS_DISALLOW();
    
    va_start(args, msg);
    vsnprintf(buf, 1023, msg, args);
    va_end(args);    
    buf[1023] = 0;

    if ( store->err_str != NULL ) {
	if ( strlen(buf) + strlen(store->err_str->str) < 2048 ) 
	    strcat(out, store->err_str->str);
	free_string(store->err_str);
    }
    strcat(out, buf);
 
    store->err_str = make_shared_string(&out[0]);
    add_ref(store->err_str);
    DEBUG_XSLT("leaving xsl_error() with:\n");
    DEBUG_XSLT(out);
    DEBUG_XSLT("----\n");
}

//!
//! Error function
//!
void xml_error(void* ctx, const char* msg, ...) {
    va_list args;
    char buf[1024];
    char out[2048] = { 0 };
    xslt_storage* store = (xslt_storage*) ctx;

    DEBUG_XSLT("xml_error()\n");
    DEBUG_XSLT(msg);
    if ( ctx == NULL ) {
	fprintf(stderr, "No error context, error: %s\n", msg);
	return;
    }
    THREADS_ALLOW();
    THREADS_DISALLOW();
    
    va_start(args, msg);
    vsnprintf(buf, 1023, msg, args);
    va_end(args);    
    buf[1023] = 0;

    if ( store->err_str != NULL ) {
	if ( strlen(buf) + strlen(store->err_str->str) < 2048 ) 
	    strcat(out, store->err_str->str);
	free_string(store->err_str);
    }
    strcat(out, buf);
    DEBUG_XSLT("leaving xml_error():\n");
    DEBUG_XSLT(out);
    store->err_str = make_shared_string(&out[0]);
    add_ref(store->err_str);
}

#define MAX_PARAMS 100

//!
//! @param
//!
static void f_run( INT32 args )
{
    xsltStylesheetPtr cur = NULL;
    xmlDocPtr           doc, res;
    char        *xmlstr, *xslstr;
    xmlOutputBufferPtr    xmlBuf;
    struct keypair            *k;
    int           success, count;
    char*           resultBuffer;
    int              varcount, i;
    xmlChar*               value;
    const xmlChar*           str;

    char **vars            = NULL; // variables
    xmlChar* params[MAX_PARAMS+1];
    
    if ( args != 1 || Pike_sp[-args].type != T_OBJECT )
	Pike_error("XSLT.Parser->run(): requires XSL Stylesheet parameter.\n");

    if ( THIS->doc == NULL ) {
	Pike_error("XML input not set correctly.\n");
    }
    if ( THIS->err_str != NULL ) {
	free_string(THIS->err_str);
	THIS->err_str = NULL;
    }
    THREADS_ALLOW();
    THREADS_DISALLOW();
    
    DEBUG_XSLT("Running XSL transformation\n");

#if 0
    xmlstr = THIS->xml->str;
    if ( THIS->xml->len == 0 ) {
	Pike_error("No XML code given - cannot transform.\n");
	return;
    }
#endif
    doc = THIS->doc;

    if ( doc == NULL ) {
	Pike_error("Unable to parse xml source.\n");
    }
    xmlSetGenericErrorFunc(NULL, NULL);
    
    xsltSetGenericErrorFunc(THIS, xsl_error);
    // top object!
    cur = ((xslt_storage*)Pike_sp[-args].u.object->storage)->stylesheet; 

    if ( THIS->variables != NULL ) 
    {
	struct svalue sind, sval;
	int             tmpint=0;
      
	varcount = 0;
	vars = malloc( sizeof(char *) * 
		       ( 1 + ((m_sizeof(THIS->variables)) * 2 )));
	MY_MAPPING_LOOP(THIS->variables, count, k)  {
	    sind = k->ind;
	    sval = k->val;
	    if(!(sind.type == T_STRING && sval.type == T_STRING)) {
		continue;
	    }
	    // index

	    str  = (const xmlChar *) sval.u.string->str;
	    if ( xmlStrstr(str, (xmlChar*) "\n") == NULL ) 
	    {
		if ( xmlStrchr(str, '"') ) {
		    if (xmlStrchr(str, '\'')) {
			xmlFreeDoc(doc);
			Pike_error("Param contains quote and double-quotes.");
			return;    
		    }
		    value = xmlStrdup((const xmlChar *)"'");
		    value = xmlStrcat(value, str);
		    value = xmlStrcat(value, (const xmlChar *)"'");
		} else {
		    value = xmlStrdup((const xmlChar *)"\"");
		    value = xmlStrcat(value, str);
		    value = xmlStrcat(value, (const xmlChar *)"\"");
		}
		
	    }
	    else {
		// param contains newlines
		value = xmlStrdup((const xmlChar *)"\"");
		value = xmlStrcat(value, (const xmlChar *)"\"");
	    }
	    
	    str = (const xmlChar*) sind.u.string->str;
	    // namespaces are bad
	    if ( xmlStrchr(str, ':') ) {
		Pike_error("Invalid Parameter %s in namespace format !",
			   str);
	    }
	    else {
		vars[tmpint++] = sind.u.string->str;
	    }
	    vars[tmpint++] = value;
	    params[varcount++] = value;
	    if ( varcount > MAX_PARAMS )
		Pike_error("Too many params !");
	}
	vars[tmpint] = NULL;
    }
    else {
	vars = malloc(sizeof(char *));
	vars[0] = NULL;
	varcount = 0;
    }
    DEBUG_XSLT("Applying stylesheet!\n");
    res = xsltApplyStylesheet(cur, doc, vars);
    if ( THIS->err_str != NULL ) {
	// only free doc at this point
	xmlFreeDoc(doc);
	Pike_error(THIS->err_str->str);
    }
    DEBUG_XSLT("Preparing output buffer !\n");
    
    // find out the encoding and use EncodingHandler
    if ( cur->encoding != NULL && strcmp(cur->encoding, "iso-8859-1") == 0 ) 
    {
      xmlBuf = xmlAllocOutputBuffer(
			  xmlGetCharEncodingHandler((xmlCharEncoding)10));
    }
    else
    {
      // utf-8 does not required a handler
      xmlBuf = xmlAllocOutputBuffer(NULL);
    }
    
    xsltSaveResultTo( xmlBuf, res, cur );


    if ( THIS->err_str != NULL ) {
	Pike_error(THIS->err_str->str);
    }
    else {
	pop_n_elems(args);
	if ( cur->encoding != NULL && strcmp(cur->encoding,"iso-8859-1") == 0 )
	{
#if HAVE_XMLBUFCONTENT
	  resultBuffer = malloc(strlen(xmlBufContent(xmlBuf->conv))+1);
	  strcpy(resultBuffer, xmlBufContent(xmlBuf->conv));
#else
	  resultBuffer = malloc(strlen(xmlBuf->conv->content)+1);
	  strcpy(resultBuffer, xmlBuf->conv->content);
#endif
	  push_text(resultBuffer);
	  free(resultBuffer);
	}
	else
#if HAVE_XMLBUFCONTENT
	  push_text(xmlBufContent(xmlBuf->conv));
#else
	  push_text(xmlBuf->buffer->content);
#endif
    }
    xmlOutputBufferClose(xmlBuf);
    xmlFreeDoc(res);
    xmlFreeDoc(doc);
    
    free(vars);
    for ( i = 0; i < varcount; i++ )
	xmlFree(params[i]);

    if ( THIS->variables != NULL ) {
	free_mapping(THIS->variables);
	THIS->variables = NULL;
    }
    xsltCleanupGlobals();
    xmlCleanupParser();
    xmlMemoryDump();
    DEBUG_XSLT("done...\n");
}

//!
//! Get the libxml2 Version-
//!
void f_get_version(INT32 args)
{
    char *result = malloc(200);
    
    sprintf(result, "libxml %s, libxslt %s", 
	    LIBXML_DOTTED_VERSION, LIBXSLT_DOTTED_VERSION);

    pop_n_elems(args);
    push_text(result);
}



//!
//! Create a new Stylesheet object and set the initial error function.
//!
void f_create_stylesheet(INT32 args)
{
    if ( THIS->err_str != NULL ) {
	free_string(THIS->err_str);
	THIS->err_str = NULL;
    }
    pop_n_elems(args);
}

int xmlInputRead(void* context, char* buffer, int len)
{
  
}


//!
//! Set the function to be called when parsing xsl:include tags.
//!
void f_set_include_callbacks(INT32 args)
{
  int i;
  if ( args != 4 )
    Pike_error("XSLT.Parser()->set_include_callbacks(): Expected four arguments (functions: match, open, read, close).\n");
  for ( i = 0; i < 4; i++ )
  if ( Pike_sp[-args+i].type != T_FUNCTION )
      Pike_error("Arguments must be function pointers !\n");
  

  if ( THIS->match_include != NULL )
    free_svalue(THIS->match_include);
  if ( THIS->open_include != NULL )
    free_svalue(THIS->open_include);
  if ( THIS->read_include != NULL )
    free_svalue(THIS->read_include);
  if ( THIS->close_include != NULL )
    free_svalue(THIS->close_include);

  THIS->match_include = malloc(sizeof(struct svalue));
  THIS->open_include = malloc(sizeof(struct svalue));
  THIS->read_include = malloc(sizeof(struct svalue));
  THIS->close_include = malloc(sizeof(struct svalue));
  
  assign_svalue_no_free(THIS->match_include, &Pike_sp[-4]);
  assign_svalue_no_free(THIS->open_include, &Pike_sp[-3]);
  assign_svalue_no_free(THIS->read_include, &Pike_sp[-2]);
  assign_svalue_no_free(THIS->close_include, &Pike_sp[-1]);
  pop_n_elems(args);
}

//!
//! Set a language for the Stylesheet.
//!
void f_set_language(INT32 args)
{
    struct pike_string* str;

    if ( args != 1 )
	Pike_error("XSLT.Stylesheeet->f_set_language(): Expected string.\n");
    if ( Pike_sp[-args].type != T_STRING )
	Pike_error("Argument must be the language string !\n");
    str = (struct pike_string*)Pike_sp[-args].u.string;
    THAT->language = str;
    add_ref(THAT->language);
    pop_n_elems(args);
    DEBUG_XSLT("Language set to ");
    DEBUG_XSLT(str->str);
    DEBUG_XSLT("\n");
}


//!
//! xsl:include callback registered to xslt. Only matches steam://
//!
int _include_match(const char* filename)
{
  int match;
  
  if ( THIS->match_include == NULL ) {
    DEBUG_XSLT("No include resolve callback !");
    return 0;
  }
  push_text(filename);
  apply_svalue(THIS->match_include, 1);
  
  if ( Pike_sp[-1].type != T_INT ) {
    pop_stack();
    return 0;
  }
  match = Pike_sp[-1].u.integer == 1;
  pop_stack();
  return match;
}

//!
//! Include open callback function.
//!
void * _include_open(const char* filename)
{
    struct object*    obj;

    if ( THIS->open_include == NULL )
      return 0;
    
    push_text(filename);
    apply_svalue(THIS->open_include, 1);

    if ( Pike_sp[-1].type == T_INT ) {
	pop_stack();
	return 0;
    }
    obj = Pike_sp[-1].u.object;

    if ( THIS->file != NULL )
	free_object(THIS->file);
    
    THIS->file = obj;
    add_ref(THIS->file);
    THIS->iPosition = 0;

    pop_stack();
    return THIS;
}

//!
//! Read from the opened include file. 
//!
int _include_read(void* context, char* buffer, int len)
{
    int result;
    THREAD_SAFE_RUN(result=f_include_read(context, buffer, len));
    return result;
}


//!
//! Read the content
//!
int f_include_read(void* context, char* buffer, int len)
{
    struct pike_string* str;


    if ( THIS->read_include == NULL )
	return 0;

    add_ref(THIS->file); // somehow the function call makes it loose refs
    push_object(THIS->file);
    if ( THAT->language == NULL )
	push_text("english");
    else {
	push_string(THAT->language);
	add_ref(THAT->language);
    }

    push_int(THIS->iPosition);
    apply_svalue(THIS->read_include, 3);
 
    if ( Pike_sp[-1].type == T_INT ) {
	pop_stack();
	return 0;
    }

    str = Pike_sp[-1].u.string;
    if ( str->len == 0 ) {
      pop_stack();
      return 0;
    }
    if ( str->len > len+THIS->iPosition ) {
	strncpy(buffer, &str->str[THIS->iPosition], len);
	THIS->iPosition += len;
    }
    else if ( str->len - THIS->iPosition >= 0 ) {
	strncpy(buffer, 
		&str->str[THIS->iPosition], 
		str->len-THIS->iPosition);
	buffer[str->len-THIS->iPosition] = '\0';
	len = str->len+1-THIS->iPosition;
    }
    else {
      fprintf(stdout, 
	      "Fatal error while reading include file-length mismatch!\n");
    }
    pop_stack();
    return len;
}

//!
//! @param
//!
int _include_close(void* context)
{
  struct pike_string* str;
  
  if ( THIS->close_include == NULL )
    return;
  add_ref(THIS->file);
  push_object(THIS->file);
  apply_svalue(THIS->close_include, 1);
  return 0;
}

xmlParserInputPtr
steamExternalEntityLoader(const char *URL, const char *ID,
			  xmlParserCtxtPtr ctxt) 
{
  xmlParserInputPtr   ret;
  struct pike_string* str;
  xmlChar*            buf;        
  

  push_text(URL);
  if ( THAT->language == NULL )
    push_text("english");
  else {
    push_string(THAT->language);
    add_ref(THAT->language);
  }
  
  push_int(0);
  apply_svalue(THIS->read_include, 3);
  
  if ( Pike_sp[-1].type == T_INT ) {
    fprintf(stderr, "Fatal error - empty string: include not found");
    pop_stack();
    return NULL;
  }
  
  str = Pike_sp[-1].u.string;
  if ( str->len == 0 ) {
    fprintf(stderr, "Fatal error - empty string: include not found");
    pop_stack();
    return NULL;
  }

  buf = xmlCharStrdup(str->str);
  ret = xmlNewStringInputStream(ctxt, buf);
  ret->length = str->len;
  return(ret);
}



void f_get_method(INT32 args)
{
    if ( THAT->stylesheet == NULL )
	Pike_error("XSLT.Stylesheet(): no stylesheet!");
    if ( THAT->stylesheet->method == NULL )
      Pike_error("XSLT.Stylesheet does not define a method!");

    push_text((char*)THAT->stylesheet->method);
}

void f_get_encoding(INT32 args)
{
    if ( THAT->stylesheet == NULL )
	Pike_error("XSLT.Stylesheet(): no stylesheet!");
    if ( THAT->stylesheet->encoding == NULL )
      Pike_error("XSLT.Stylesheet does not define a method!");

    push_text((char*)THAT->stylesheet->encoding);
}

//!
//! Set the content of the Stylesheet which will create the parse
//! xsltStylesheet structure and store it in the objects storage.
//!
void f_set_content(INT32 args)
{
    struct pike_string* str;
    xmlDocPtr           xsl;
    
    if(args != 1)
	Pike_error("XSLT.Stylesheet(): Expected content string.\n");
    if(Pike_sp[-args].type != T_STRING)
	Pike_error("XSLT.Stylesheet(): need xsl data for creation.\n");

    if ( THAT->open_include == NULL || THAT->match_include == NULL ||
	 THAT->read_include == NULL || THAT->close_include == NULL )
	Pike_error("XSLT.Stylesheet(): No callback functions defined.\n");
    if ( THAT->stylesheet != NULL ) 
	Pike_error("XSLT.Stylesheet(): stylesheet is not initialized correctly!\n");
    
    THREADS_ALLOW();
    THREADS_DISALLOW();
   
    str = (struct pike_string*)Pike_sp[-args].u.string;
    if ( str->len == 0 )
	Pike_error("XSLT.Stylesheet(): need content for stylesheet !\n");

    THAT->xsl = str;
    add_ref(THAT->xsl);
    pop_n_elems(args);

    xmlSetGenericErrorFunc(THAT, (xml_error));

    xsl = xmlParseMemory(str->str, str->len);

    if ( THAT->err_str != NULL ) {
	Pike_error(THAT->err_str->str);
	return;
    }
    xmlSetGenericErrorFunc(NULL, NULL);

    xsltSetGenericErrorFunc(THAT,(xsl_error));

    THAT->stylesheet = xsltParseStylesheetDoc(xsl);
    if ( THAT->err_str != NULL ) {
	Pike_error(THAT->err_str->str);
	return;
    }
    xsltSetGenericErrorFunc(NULL, NULL);
}

//!
//! Pike module initialization code. Offer two classes.
//!
void pike_module_init( void )
{
    xmlLoadExtDtdDefaultValue = 1;
    DEBUG_XSLT("RegisterInputCallbacks()");
    // old libxml (pre 2.6)

#if LIBXML_VERSION < 20600
    if ( xmlRegisterInputCallbacks(_include_match, _include_open, _include_read, _include_close) == -1 )
      fprintf(stderr, "Error registering input callbacks !");
#else
    defaultLoader = xmlGetExternalEntityLoader();
    xmlSetExternalEntityLoader(steamExternalEntityLoader);
    if ( xmlGetExternalEntityLoader() != steamExternalEntityLoader )
      fprintf(stderr, "XSLT: Failed to set external entity loader !\n");
#endif

    _init_xml_dom();

    start_new_program();
    ADD_STORAGE(xslt_storage);
    set_init_callback(init_xslt_storage);
    set_exit_callback(free_xslt_storage);
    ADD_FUNCTION2("create", f_create, tFunc(tNone,tVoid), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("set_xml_data", f_set_xml_data, tFunc(tOr(tStr, tObj), tVoid),0, OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("set_variables", f_set_variables, 
		 tFunc(tMapping,tVoid), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("run", f_run, tFunc(tObj,tStr), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("get_version", f_get_version, tFunc(tVoid,tStr), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);

    end_class("Parser", 0);

    start_new_program();
    ADD_STORAGE(xslt_storage);
    set_init_callback(init_xslt_storage);
    set_exit_callback(free_xslt_storage);

    ADD_FUNCTION2("create", f_create_stylesheet, tFunc(tNone,tVoid), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("set_include_callbacks", f_set_include_callbacks, 
		 tFunc(tFunc(tStr,tInt) tFunc(tStr,tObj) tFunc(tObj tStr tInt,tStr) tFunc(tObj,tVoid), tVoid), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("set_content", f_set_content, tFunc(tStr,tVoid), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("set_language", f_set_language, tFunc(tStr,tVoid), 0,
		 OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("get_method", f_get_method, tFunc(tVoid,tStr), 0,
		  OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    ADD_FUNCTION2("get_encoding", f_get_encoding, tFunc(tVoid,tStr), 0,
		  OPT_EXTERNAL_DEPEND|OPT_SIDE_EFFECT);
    end_class("Stylesheet", 0);
}

/* Restore and exit module */
void pike_module_exit( void )
{
    if ( xslt_program )
	free_program(xslt_program);
    if ( stylesheet_program )
	free_program(stylesheet_program);
}

 
