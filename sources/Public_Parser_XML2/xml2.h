/*
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * $Id: xml2.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

/*
 * File licensing and authorship information block.
 *
 * Version: MPL 1.1/LGPL 2.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Initial Developer of the Original Code is
 *
 * Bill Welliver <hww3@riverweb.com>
 *
 * Portions created by the Initial Developer are Copyright (C) Bill Welliver
 * All Rights Reserved.
 *
 * Contributor(s):
 *
 * Alternatively, the contents of this file may be used under the terms of
 * the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of the LGPL, and not to allow others to use your version
 * of this file under the terms of the MPL, indicate your decision by
 * deleting the provisions above and replace them with the notice
 * and other provisions required by the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the MPL or the LGPL.
 *
 * Significant Contributors to this file are:
 *
 *
 */

#define _GNU_SOURCE

#include "xml2_config.h"
#include "util.h"

#ifdef HAVE_LIBXML2
#endif /* HAVE_XML2 */

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>

#ifdef HAVE_LIBXML_XMLREADER_H
#include <libxml/xmlreader.h>
#endif

#ifdef HAVE_LIBXML_PARSER_H
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#endif

#ifdef HAVE_LIBXML_TREE_H
#include <libxml/tree.h>
#endif

#ifdef HAVE_LIBXML_SAX2_H
#include <libxml/SAX2.h>
#endif

#ifdef HAVE_LIBXML_XPATH_H
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#endif

#ifdef HAVE_LIBXSLT_XSLT_H
#include <libxslt/xslt.h>
#endif

#ifdef HAVE_LIBXSLT_DOCUMENT_H
#include <libxslt/document.h>
#endif

#ifdef HAVE_LIBXSLT_XSLTINTERNALS_H
#include <libxslt/xsltInternals.h>
#endif

#ifdef HAVE_LIBXSLT_TRANSFORM_H
#include <libxslt/transform.h>
#endif

#ifdef HAVE_LIBXSLT_XSLTUTILS_H
#include <libxslt/xsltutils.h>
#endif

#define CB_INTERNALSUBSET 0
#define CB_ISSTANDALONE 1
#define CB_HASINTERNALSUBSET 2
#define CB_HASEXTERNALSUBSET 3
#define CB_RESOLVEENTITY 4
#define CB_GETENTITY 5
#define CB_ENTITYDECL 6
#define CB_NOTATIONDECL 7
#define CB_ATTRIBUTEDECL 8
#define CB_ELEMENTDECL 9
#define CB_UNPARSEDENTITYDECL 10
#define CB_SETDOCUMENTLOCATOR 11
#define CB_STARTDOCUMENT 12
#define CB_ENDDOCUMENT 13
#define CB_STARTELEMENT 14
#define CB_ENDELEMENT 15
#define CB_REFERENCE 16
#define CB_CHARACTERS 17
#define CB_IGNORABLEWHITESPACE 18
#define CB_PROCESSINGINSTRUCTION 19
#define CB_COMMENT 20
#define CB_WARNING 21
#define CB_ERROR 22
#define CB_FATALERROR 23
#define CB_GETPARAMETERENTITY 24
#define CB_CDATABLOCK 25
#define CB_EXTERNALSUBSET 26
#define CB_STARTELEMENTNS 27
#define CB_ENDELEMENTNS 28
#define CB_SERROR 29

/* a rather arbitrary limit on the number of xslt attributes we can supply */
#define MAX_PARAMS 100

void f_XMLReader_create(INT32 args);
void f_SAX_parse(INT32 args);
void f_parse_relaxng(INT32 args);
void f_parse_xslt(INT32 args);
void f_parse_xml(INT32 args);
void f_parse_html(INT32 args);
void f_parse_xslt(INT32 args);

void handle_parse_stylesheet();
void handle_parse_relaxng();

struct program * Node_program;

struct program * Stylesheet_program;
struct program * RelaxNG_program;

#ifndef THIS_IS_XML2_STYLESHEET
extern ptrdiff_t Stylesheet_storage_offset;
#endif

char** low_set_attributes(struct mapping * variables);
void low_apply_stylesheet(INT32 args, struct object * xml, const char ** atts);
void handle_parsed_tree(xmlDocPtr doc, INT32 args);
xmlExternalEntityLoader entity_loader;
xmlStructuredErrorFunc structured_handler;
xmlGenericErrorFunc generic_handler;
xmlRelaxNGValidityErrorFunc relaxng_error_handler;
xmlRelaxNGValidityWarningFunc relaxng_warning_handler;

  xmlEntityPtr my_getParameterEntity(void * ctx, const xmlChar * name); 
xmlEntityPtr my_xml_getent(void * ctx, const xmlChar * name);

  xmlEntityPtr my_getEntity(void * ctx, const xmlChar * name);

  xmlParserInputPtr my_resolveEntity(void * ctx, const xmlChar * publicId, 
    const xmlChar * systemId);

  void my_startElementNs(void * ctx, const xmlChar * localname, 
    const xmlChar * prefix, const xmlChar * uri, 
    int nb_namespaces, const xmlChar ** namespaces,
    int nb_attributes, int nb_defaulted,
    const xmlChar ** atts);

  void my_endElementNs(void * ctx, const xmlChar * localname,
    const xmlChar * prefix, const xmlChar * uri);

  void my_serror(void * ctx, xmlErrorPtr error);
  void my_entityDecl(void * ctx, const xmlChar * name, int type, const xmlChar * publicId, const xmlChar * systemId, xmlChar * content);
  void my_unparsedEntityDecl(void * ctx, const xmlChar * name, const xmlChar * publicId, const xmlChar * systemId, const xmlChar * notationName);
  void my_attributeDecl(void * ctx, const xmlChar * elem, const xmlChar* fullname, int type, int def, const xmlChar * defaultValue, xmlEnumerationPtr tree);
  void my_elementDecl(void * ctx, const xmlChar * name, int type, xmlElementContentPtr content);
  void my_startElement(void * ctx, const xmlChar * fullname, const xmlChar ** atts);
  void my_comment(void * ctx, const xmlChar * name);
  void my_characters(void * ctx, const xmlChar * ch, int len);
  void my_cdataBlock(void * ctx, const xmlChar * ch, int len);
  void my_ignorableWhitespace(void * ctx, const xmlChar * ch, int len);
  void my_processingInstruction(void * ctx, const xmlChar * target, const xmlChar * data);
  void my_internalSubset(void * ctx, const xmlChar * name, const xmlChar * ExternalID, const xmlChar * SystemID);
  void my_externalSubset(void * ctx, const xmlChar * name, const xmlChar * ExternalID, const xmlChar * SystemID);
  void my_notationDecl(void * ctx, const xmlChar * name, const xmlChar * publicId, const xmlChar * systemId);
  void my_reference(void * ctx, const xmlChar * name);
  void my_endElement(void * ctx, const xmlChar * name);
  int my_hasInternalSubset(void * data);
  int my_hasExternalSubset(void * data);
  void my_startDocument(void * data);
  void my_endDocument(void * data);
  int my_isStandalone(void * data);
  void  make_PSAX_handler();
  struct array * get_callback_data(struct object * o);
  struct svalue * get_callback_func(struct object * o);



  typedef struct
  {
    xmlSAXHandlerPtr sax;
    struct array * handlers;
    xmlParserCtxtPtr context;
    xmlParserOption options;
  } SAX_OBJECT_DATA;

  typedef struct
  {
    INT32 * refs;
    struct object * parser;
#ifdef HAVE_LIBXML_RELAXNG_H
    xmlRelaxNGPtr valid;
    xmlRelaxNGParserCtxtPtr context;
#endif /* HAVE_LIBXML_RELAXNG_H */
  } RELAXNG_OBJECT_DATA;

  typedef struct
  {
#ifdef HAVE_LIBXML_XMLREADER_H
    xmlTextReaderPtr reader;
#endif
    struct object * parser;
    struct pike_string * xml;
    int autoencode;
  } XMLREADER_OBJECT_DATA;

  typedef struct
  {
    int xml_parser_options;
    int html_parser_options;
    int auto_encode;
  } PARSER_OBJECT_DATA;

  typedef struct
  {
    xmlNodePtr node;
    int unlinked;
    int transient;
    struct object * parser;
    INT32 * refs;
  } NODE_OBJECT_DATA;

  typedef struct
  {
    xmlParserCtxtPtr ctxt;
    xmlNodePtr html;
  } HTML_OBJECT_DATA;

  typedef struct
  {
    xsltStylesheetPtr stylesheet;
    const char ** atts;
    struct object * parser;
    INT32 * refs;
  } STYLESHEET_OBJECT_DATA;

#ifndef THIS_IS_XML2_NODE

#define THIS_NODE ((struct Node_struct *)(Pike_interpreter.frame_pointer->current_storage))

struct Node_struct {
 NODE_OBJECT_DATA   *object_data;
};

#endif

#ifndef THIS_IS_XML2_STYLESHEET

#define THIS_STYLESHEET ((struct Stylesheet_struct *)(Pike_interpreter.frame_pointer->current_storage))

struct Stylesheet_struct {
 STYLESHEET_OBJECT_DATA   *object_data;
 struct object * node;
};

#endif

#ifndef THIS_IS_XML2_RELAXNG

#define THIS_RELAXNG ((struct RelaxNG_struct *)(Pike_interpreter.frame_pointer->current_storage))

struct RelaxNG_struct {
 RELAXNG_OBJECT_DATA   *object_data;
 struct object * node;
};

#endif

#ifndef THIS_IS_XML2_XMLREADER

struct XMLReader_struct {
XMLREADER_OBJECT_DATA   *object_data;
};

#define THIS_XMLREADER ((struct XMLReader_struct *)(Pike_interpreter.frame_pointer->current_storage))

#endif

#define mySAX THIS->object_data->sax

#define CHECK_NODE_PASSED(_X_) do { char * _Y_; \
  _Y_ = get_storage(_X_, Node_program); \
  if(_Y_ == NULL) Pike_error("bad argument: expected Node\n"); \
  } while (0)


#define MY_NODE (THIS->object_data->node)
#define MY_STYLESHEET (THIS->object_data->stylesheet)

#define OBJ2_(o) ((struct _struct *)(o->storage+_storage_offset))
#define OBJ2_NODE(o) ((struct Node_struct *)get_storage(o, Node_program))

#define OBJ2_STYLESHEET(o) ((struct Stylesheet_struct *)get_storage(o, Stylesheet_program))
#define OBJ2_RELAXNG(o) ((struct RelaxNG_struct *)get_storage(o, RelaxNG_program))

#define NEW_NODE_OBJ(_X_, _Y_) { apply(Pike_fp->current_object, "Node", 0); \
  OBJ2_NODE((Pike_sp[0-1].u.object))->object_data->node = _Y_; \
  _X_ = Pike_sp[0-1].u.object; pop_stack(); }
#define NEW_NODE_OBJ_REFS(o)    OBJ2_NODE(o)->object_data->refs = THIS->object_data->refs; \
    (* OBJ2_NODE(o)->object_data->refs) ++;

#define NEW_NODE() clone_object(Node_program, 0)
#define NEW_NODE_REFS(o)  OBJ2_NODE(o)->object_data->refs = THIS->object_data->refs; \
      (* OBJ2_NODE(o)->object_data->refs)++; 

#define push_text_len(T, L) do {                                        \
    const char *_ = (T);                                                \
    struct svalue *_sp_ = Pike_sp++;                                    \
    _sp_->subtype=0;                                                    \
    _sp_->u.string=make_shared_binary_string(_,L);              \
    debug_malloc_touch(_sp_->u.string);                                 \
    _sp_->type=PIKE_T_STRING;                                           \
  }while(0)

#define stack_swap_n(Q) do {                                               \
    struct svalue *_sp_ = Pike_sp;                                      \
    struct svalue _=_sp_[-1];                                           \
    _sp_[-1]=_sp_[0-Q];                                                  \
    _sp_[0-Q]=_;                                                         \
  } while(0)

