/*
 * Pike Extension Modules - A collection of modules for the Pike Language
 * Copyright © 2000-2003 The Caudium Group
 *
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
 * $Id: xml_sax.c,v 1.1 2008/03/31 13:39:57 exodusd Exp $
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
 * Marek Habersack <grendel@caudium.net>
 *
 * Portions created by the Initial Developer are Copyright (C) Marek Habersack
 * & The Caudium Group. All Rights Reserved.
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
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

//#define SAX_DEBUG 1

#include "global.h"
RCSID("$Id: xml_sax.c,v 1.1 2008/03/31 13:39:57 exodusd Exp $");

#ifdef fp
#undef fp
#endif

#include "xml_config.h"
#include "xml_sax.h"

#ifdef HAVE_XML2
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>
#include <limits.h>

#include <libxml/tree.h>
#include <libxml/SAX.h>
#include <libxml/entities.h>
#include <libxml/parserInternals.h>

#ifdef SAX_DEBUG

static unsigned int   __debug_indent;

#define DBG_FUNC_ENTER() do { fprintf(stderr, "%*cEnter: %s %s:%d\n", __debug_indent, ' ', __FUNCTION__, __FILE__, __LINE__); __debug_indent++; } while(0)
#define DBG_FUNC_LEAVE() do { fprintf(stderr, "%*cLeave: %s %s:%d\n", __debug_indent, ' ', __FUNCTION__, __FILE__, __LINE__); __debug_indent--; } while(0)
#else
#define DBG_FUNC_ENTER()
#define DBG_FUNC_LEAVE()
#endif

#define THIS ((sax_storage*)Pike_fp->current_storage)
#define CB_ABSENT(_idx_) (THIS->callbackOffsets[(_idx_)] == -1)
#define CB_API(_name_, _xmlAPI_) {#_name_, 1, offsetof(xmlSAXHandler,_xmlAPI_)}
#define CB_OPT_API(_name_, _xmlAPI_) {#_name_, 0, offsetof(xmlSAXHandler,_xmlAPI_)}
#define CB_CALL(_offset_, _args_) apply_low(THIS->callbacks, THIS->callbackOffsets[(_offset_)], (_args_))

#define safe_push_text(_txt_) if ((_txt_)) push_text((_txt_)); else push_int(0)

#define internalSubsetSAX 0x00
#define isStandaloneSAX 0x01
#define hasInternalSubsetSAX 0x02
#define hasExternalSubsetSAX 0x03
#define getEntitySAX 0x04
#define entityDeclSAX 0x05
#define notationDeclSAX 0x06
#define attributeDeclSAX 0x07
#define elementDeclSAX 0x08
#define unparsedEntityDeclSAX 0x09
#define startDocumentSAX 0x0A
#define endDocumentSAX 0x0B
#define startElementSAX 0x0C
#define endElementSAX 0x0D
#define referenceSAX 0x0E
#define charactersSAX 0x0F
#define ignorableWhitespaceSAX   0x10
#define processingInstructionSAX 0x11
#define commentSAX 0x12
#define warningSAX 0x13
#define errorSAX 0x14
#define fatalErrorSAX 0x15
#define getParameterEntitySAX 0x16
#define cdataBlockSAX 0x17
#define externalSubsetSAX 0x18
#define CB_API_SIZE 0x19

typedef enum {
  PARSE_PUSH_PARSER = 0x01,
  PARSE_MEMORY_PARSER = 0x02,
  PARSE_FILE_PARSER = 0x03
} xmlParsingMethod;

typedef struct
{
  char   *name;
  int     req;
  int     saxFunIdx;
} pikeCallbackAPI;

typedef struct 
{
  xmlParserCtxtPtr     ctxt;
  xmlSAXHandlerPtr     sax;
  xmlParsingMethod     parsing_method;
  int                  callbackOffsets[CB_API_SIZE];
  char                *filename;
  struct object       *callbacks;
  struct object       *file_obj;
  struct pike_string  *input_data;
  struct svalue        user_data;
} sax_storage;

static void pextsInternalSubset(void *ctx, const xmlChar *name, const xmlChar *externalID, const xmlChar *systemID);
static int pextsIsStandalone(void *ctx);
static int pextsHasInternalSubset(void *ctx);
static int pextsHasExternalSubset(void *ctx);
static xmlEntityPtr pextsGetEntity(void *ctx, const xmlChar *name);
static void pextsEntityDecl(void *ctx, const xmlChar *name, int type, const xmlChar *publicId,
                            const xmlChar *systemId, xmlChar *content);
static void pextsNotationDecl(void *ctx, const xmlChar *name, const xmlChar *publicId, const xmlChar *systemId);
static void pextsAttributeDecl(void *ctx, const xmlChar *elem, const xmlChar *fullname, int type, int def,
                               const xmlChar *defaultValue, xmlEnumerationPtr tree);
static void pextsElementDecl(void *ctx, const xmlChar *name, int type, xmlElementContentPtr content);
static void pextsUnparsedEntityDecl(void *ctx, const xmlChar *name, const xmlChar *publicId,
                                    const xmlChar *systemId, const xmlChar *notationName);
static void pextsSetDocumentLocator(void *ctx, xmlSAXLocatorPtr loc);
static void pextsStartDocument(void *ctx);
static void pextsEndDocument(void *ctx);
static void pextsStartElement(void *ctx, const xmlChar *name, const xmlChar **atts);
static void pextsEndElement(void *ctx, const xmlChar *name);
static void pextsReference(void *ctx, const xmlChar *name);
static void pextsCharacters(void *ctx, const xmlChar *ch, int len);
static void pextsIgnorableWhitespace(void *ctx, const xmlChar *ch, int len);
static void pextsProcessingInstruction(void *ctx, const xmlChar *target, const xmlChar *data);
static void pextsComment(void *ctx, const xmlChar *value);
static void pextsWarning(void *ctx, const char *msg, ...);
static void pextsError(void *ctx, const char *msg, ...);
static void pextsFatalError(void *ctx, const char *msg, ...);
static xmlEntityPtr pextsGetParameterEntity(void *ctx, const xmlChar *name);
static void pextsCdataBlock(void *ctx, const xmlChar *value, int len);
static void pextsExternalSubset(void *ctx, const xmlChar *name, const xmlChar *externalID, const xmlChar *systemID);
  
static struct program  *xml_program;
static struct program  *html_program;

static pikeCallbackAPI  callback_api[] =
{
  CB_OPT_API(internalSubsetSAX, internalSubset),
  CB_OPT_API(isStandaloneSAX, isStandalone),
  CB_OPT_API(hasInternalSubsetSAX, hasInternalSubset),
  CB_OPT_API(hasExternalSubsetSAX, hasExternalSubset),
  CB_OPT_API(getEntitySAX, getEntity),
  CB_OPT_API(entityDeclSAX, entityDecl),
  CB_OPT_API(notationDeclSAX, notationDecl),
  CB_OPT_API(attributeDeclSAX, attributeDecl),
  CB_OPT_API(elementDeclSAX, elementDecl),
  CB_OPT_API(unparsedEntityDeclSAX, unparsedEntityDecl),
  CB_API(startDocumentSAX, startDocument),
  CB_API(endDocumentSAX, endDocument),
  CB_API(startElementSAX, startElement),
  CB_API(endElementSAX, endElement),
  CB_OPT_API(referenceSAX, reference),
  CB_OPT_API(charactersSAX, characters),
  CB_OPT_API(ignorableWhitespaceSAX, ignorableWhitespace),
  CB_OPT_API(processingInstructionSAX, processingInstruction),
  CB_OPT_API(commentSAX, comment),
  CB_OPT_API(warningSAX, warning),
  CB_OPT_API(errorSAX, error),
  CB_OPT_API(fatalErrorSAX, fatalError),
  CB_OPT_API(getParameterEntitySAX, getParameterEntity),
  CB_OPT_API(cdataBlockSAX, cdataBlock),
  CB_OPT_API(externalSubsetSAX, externalSubset),
};

static xmlSAXHandler   pextsSAX = {
  .internalSubset = pextsInternalSubset,
  .isStandalone = pextsIsStandalone,
  .hasInternalSubset = pextsHasInternalSubset,
  .hasExternalSubset = pextsHasExternalSubset,
  .resolveEntity = NULL, /* we don't use it by default */
  .getEntity = pextsGetEntity,
  .entityDecl = pextsEntityDecl,
  .notationDecl = pextsNotationDecl,
  .attributeDecl = pextsAttributeDecl,
  .elementDecl = pextsElementDecl,
  .unparsedEntityDecl = pextsUnparsedEntityDecl,
  .setDocumentLocator = NULL, /* we don't use it here */
  .startDocument = pextsStartDocument,
  .endDocument = pextsEndDocument,
  .startElement = pextsStartElement,
  .endElement = pextsEndElement,
  .reference = pextsReference,
  .characters = pextsCharacters,
  .ignorableWhitespace = pextsIgnorableWhitespace,
  .processingInstruction = pextsProcessingInstruction,
  .comment = pextsComment,
  .warning = pextsWarning,
  .error = pextsError,
  .fatalError = pextsFatalError,
  .getParameterEntity = pextsGetParameterEntity,
  .cdataBlock = pextsCdataBlock,
  .externalSubset = pextsExternalSubset
};

static struct pike_string  *econtent_type;
static struct pike_string  *econtent_ocur;
static struct pike_string  *econtent_name;
static struct pike_string  *econtent_prefix;
static struct pike_string  *econtent_c1;
static struct pike_string  *econtent_c2;

/* Parser callbacks */

static void pextsInternalSubset(void *ctx, const xmlChar *name, const xmlChar *externalID, const xmlChar *systemID)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(internalSubsetSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  safe_push_text(externalID);
  safe_push_text(systemID);
  push_svalue(&THIS->user_data);
  
  CB_CALL(internalSubsetSAX, 5);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static int pextsIsStandalone(void *ctx)
{
  struct svalue   sv;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(isStandaloneSAX)) {
    DBG_FUNC_LEAVE();
    return 1;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  push_svalue(&THIS->user_data);
  CB_CALL(isStandaloneSAX, 2);
  stack_pop_to(&sv);
  
  DBG_FUNC_LEAVE();
  return sv.u.integer;
}

static int pextsHasInternalSubset(void *ctx)
{
  struct svalue   sv;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(hasInternalSubsetSAX)) {
    DBG_FUNC_LEAVE();
    return 0;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  push_svalue(&THIS->user_data);
  CB_CALL(hasInternalSubsetSAX, 2);
  stack_pop_to(&sv);
  
  DBG_FUNC_LEAVE();
  return sv.u.integer;
}

static int pextsHasExternalSubset(void *ctx)
{
  struct svalue   sv;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(hasExternalSubsetSAX)) {
    DBG_FUNC_LEAVE();
    return 0;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  push_svalue(&THIS->user_data);
  CB_CALL(hasExternalSubsetSAX, 2);
  stack_pop_to(&sv);
  
  DBG_FUNC_LEAVE();
  return sv.u.integer;
}

/* TODO: this one needs more thought... */
static xmlEntityPtr pextsGetEntity(void *ctx, const xmlChar *name)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(getEntitySAX)) {
    DBG_FUNC_LEAVE();
    return NULL;
  }
  DBG_FUNC_LEAVE();
  return xmlGetPredefinedEntity(name);
  return NULL;
}

static void pextsEntityDecl(void *ctx, const xmlChar *name, int type, const xmlChar *publicId,
                            const xmlChar *systemId, xmlChar *content)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(entityDeclSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  push_int(type);
  safe_push_text(publicId);
  safe_push_text(systemId);
  safe_push_text(content);
  push_svalue(&THIS->user_data);

  CB_CALL(entityDeclSAX, 7);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsNotationDecl(void *ctx, const xmlChar *name, const xmlChar *publicId, const xmlChar *systemId)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(notationDeclSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  safe_push_text(publicId);
  safe_push_text(systemId);
  push_svalue(&THIS->user_data);
  
  CB_CALL(notationDeclSAX, 5);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsAttributeDecl(void *ctx, const xmlChar *elem, const xmlChar *fullname, int type, int def,
                               const xmlChar *defaultValue, xmlEnumerationPtr tree)
{
  int  nenum;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(attributeDeclSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(elem);
  safe_push_text(fullname);
  push_int(type);
  push_int(def);
  safe_push_text(defaultValue);
  push_svalue(&THIS->user_data);
  
  if (tree) {
    xmlEnumerationPtr   tmp = tree;
    struct array      *arr;
    
    nenum = 0;
    while (tree) {
      safe_push_text(tmp->name);
      tmp = tmp->next;
      nenum++;
    }
    arr = aggregate_array(nenum);
    push_array(arr);
  } else
    push_int(0);

  CB_CALL(attributeDeclSAX, 8);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static struct mapping *tree2mapping(xmlElementContentPtr content)
{
  struct mapping *ret;
  struct svalue   sv;

  if (!content)
    return NULL;

  ret = allocate_mapping(12);
  sv.type = T_INT;
  sv.u.integer = content->type;
  mapping_string_insert(ret, econtent_type, &sv);
  
  sv.u.integer = content->ocur;
  mapping_string_insert(ret, econtent_ocur, &sv);
  
  mapping_string_insert_string(ret, econtent_name, make_shared_string(content->name));
  mapping_string_insert_string(ret, econtent_prefix, make_shared_string(content->prefix));

  if (content->c1) {
    sv.type = T_MAPPING;
    sv.u.mapping = tree2mapping(content->c1);
  } else
    sv.u.integer = 0;
  mapping_string_insert(ret, econtent_c1, &sv);

  if (content->c2) {
    sv.type = T_MAPPING;
    sv.u.mapping = tree2mapping(content->c2);
  } else {
    sv.type = T_INT;
    sv.u.integer = 0;
  }
  mapping_string_insert(ret, econtent_c2, &sv);

  return ret;
}

static void pextsElementDecl(void *ctx, const xmlChar *name, int type, xmlElementContentPtr content)
{
  struct mapping  *cmap;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(elementDeclSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  push_int(type);
  cmap = tree2mapping(content);
  if (cmap)
    push_mapping(cmap);
  else
    push_int(0);
  push_svalue(&THIS->user_data);
  
  CB_CALL(elementDeclSAX, 5);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsUnparsedEntityDecl(void *ctx, const xmlChar *name, const xmlChar *publicId,
                                    const xmlChar *systemId, const xmlChar *notationName)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(unparsedEntityDeclSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  safe_push_text(publicId);
  safe_push_text(systemId);
  safe_push_text(notationName);
  push_svalue(&THIS->user_data);
  
  CB_CALL(unparsedEntityDeclSAX, 6);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsStartDocument(void *ctx)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(startDocumentSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  push_svalue(&THIS->user_data);
  CB_CALL(startDocumentSAX, 2);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsEndDocument(void *ctx)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(endDocumentSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  push_svalue(&THIS->user_data);
  CB_CALL(endDocumentSAX, 2);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsStartElement(void *ctx, const xmlChar *name, const xmlChar **atts)
{
  int              npairs;
  const xmlChar  **tmp;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(startElementSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  if (atts) {
    npairs = 0;
    tmp = atts;
    while (tmp && *tmp) {
      safe_push_text(*tmp);
      tmp++;
      safe_push_text(*tmp);
      tmp++;
      npairs += 2;
    }
    f_aggregate_mapping(npairs);
  } else {
    push_int(0);
  }
  push_svalue(&THIS->user_data);
  
  CB_CALL(startElementSAX, 4);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsEndElement(void *ctx, const xmlChar *name)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(endElementSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  push_svalue(&THIS->user_data);
  CB_CALL(endElementSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsReference(void *ctx, const xmlChar *name)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(referenceSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  push_svalue(&THIS->user_data);
  CB_CALL(referenceSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsCharacters(void *ctx, const xmlChar *ch, int len)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(charactersSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  if (ch && len)
    push_string(make_shared_binary_string((const char*)ch, (size_t) len));
  else
    push_int(0);
  push_svalue(&THIS->user_data);
  CB_CALL(charactersSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsIgnorableWhitespace(void *ctx, const xmlChar *ch, int len)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(ignorableWhitespaceSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  if (ch && len)
    push_string(make_shared_binary_string((const char*)ch, (size_t) len));
  else
    push_int(0);
  push_svalue(&THIS->user_data);
  CB_CALL(ignorableWhitespaceSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsProcessingInstruction(void *ctx, const xmlChar *target, const xmlChar *data)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(processingInstructionSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(target);
  safe_push_text(data);
  push_svalue(&THIS->user_data);
  CB_CALL(processingInstructionSAX, 4);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsComment(void *ctx, const xmlChar *value)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(commentSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(value);
  push_svalue(&THIS->user_data);
  CB_CALL(commentSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsWarning(void *ctx, const char *msg, ...)
{
  char    *vmsg;
  va_list  ap;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(warningSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  /* I'm being lazy here :> */
  vmsg = NULL;
  va_start(ap, msg);
  if (vasprintf(&vmsg, msg, ap) < -1)
    push_int(0);
  else {
    push_text(vmsg);
    free(vmsg);
  }
  push_svalue(&THIS->user_data);
  CB_CALL(warningSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsError(void *ctx, const char *msg, ...)
{
  char    *vmsg;
  va_list  ap;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(errorSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  /* I'm being lazy here :> */
  vmsg = NULL;
  va_start(ap, msg);
  if (vasprintf(&vmsg, msg, ap) < -1)
    push_int(0);
  else {
    push_text(vmsg);
    free(vmsg);
  }
  push_svalue(&THIS->user_data);
  CB_CALL(errorSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsFatalError(void *ctx, const char *msg, ...)
{
  char    *vmsg;
  va_list  ap;
  
  DBG_FUNC_ENTER();
  if (CB_ABSENT(fatalErrorSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  /* I'm being lazy here :> */
  vmsg = NULL;
  va_start(ap, msg);
  if (vasprintf(&vmsg, msg, ap) < -1)
    push_int(0);
  else {
    push_text(vmsg);
    free(vmsg);
  }
  push_svalue(&THIS->user_data);
  CB_CALL(fatalErrorSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

/* TODO: this one needs more thought... */
static xmlEntityPtr pextsGetParameterEntity(void *ctx, const xmlChar *name)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(getParameterEntitySAX)) {
    DBG_FUNC_LEAVE();
    return NULL;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  DBG_FUNC_LEAVE();
  return NULL;
}

static void pextsCdataBlock(void *ctx, const xmlChar *value, int len)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(cdataBlockSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  if (value)
    push_string(make_shared_binary_string((const char*)value, (size_t) len));
  else
    push_int(0);
  push_svalue(&THIS->user_data);
  CB_CALL(cdataBlockSAX, 3);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

static void pextsExternalSubset(void *ctx, const xmlChar *name, const xmlChar *externalId, const xmlChar *systemId)
{
  DBG_FUNC_ENTER();
  if (CB_ABSENT(externalSubsetSAX)) {
    DBG_FUNC_LEAVE();
    return;
  }

  THIS->ctxt = (xmlParserCtxtPtr)ctx;
  
  push_object(this_object());
  safe_push_text(name);
  safe_push_text(externalId);
  safe_push_text(systemId);
  push_svalue(&THIS->user_data);
  CB_CALL(externalSubsetSAX, 5);
  pop_stack();
  
  DBG_FUNC_LEAVE();
}

/* To learn which callbacks are required take a look at the callbacks_api
 * array above.
 */
static int is_callback_ok(struct object *callbacks, char **missing_method)
{
  int                 ioff, i;
  struct identifier  *ident;
  void              **tmp;
  
  if (!callbacks)
    return 0;

  i = 0;

  if (missing_method)
    *missing_method = NULL;
  
  /*
   * walk the array of required methods, check whether each of them exists
   * in the passed object and is a method, then record its offset in our
   * storage so that the methods can be called later on.
   */
  while (i < CB_API_SIZE) {
    ioff = find_identifier(callback_api[i].name, callbacks->prog);
    if (ioff < 0 && callback_api[i].req) {
      if (missing_method)
        *missing_method = callback_api[i].name;
      return 0;
    } else if (ioff < 0) {
      THIS->callbackOffsets[i] = -1;
      i++;
      continue;
    }
    
    ident = ID_FROM_INT(callbacks->prog, ioff);
    if (!IDENTIFIER_IS_FUNCTION(ident->identifier_flags)) {
      if (missing_method)
        *missing_method = callback_api[i].name;
      return 0;
    }

    /* Put the offset in the callbacks array and initialize the SAX handler
     * structure with appropriate function pointer. The pointer arithmetic
     * is hairy, but it works :>
     */
    THIS->callbackOffsets[i] = ioff;
    tmp = (void**)((char*)THIS->sax + callback_api[i].saxFunIdx);
    *tmp = *((void**)((char*)(&pextsSAX) + callback_api[i].saxFunIdx));
    i++;
  }
  
  return 1;
}

/*! @decl int getLineNumber()
 */
static void f_getLineNumber(INT32 args)
{
  pop_n_elems(args);
  
  if (!THIS->ctxt)
    push_int(-1);
  else
    push_int(getLineNumber(THIS->ctxt));
}

/*! @decl int getColumnNumber()
 */
static void f_getColumnNumber(INT32 args)
{
  pop_n_elems(args);
  
  if (!THIS->ctxt)
    push_int(-1);
  else
    push_int(getColumnNumber(THIS->ctxt));
}

/*! @decl void create(string|object input, object callbacks, mapping|void  entities, mixed|void user_data, int|void input_is_data)
 */
static void f_create(INT32 args)
{
  struct object      *file_obj = NULL, *callbacks = NULL;
  char               *file_name = NULL;
  struct mapping     *entities = NULL;
  int                 input_is_data = 0;
  struct pike_string *input_data = NULL;
  struct svalue      *user_data = NULL;
  char               *missing_method = NULL;
  
  switch(args) {
      case 5:
        if (ARG(5).type != T_INT)
          Pike_error("Incorrect type for argument 4: expected an integer\n");
        input_is_data = ARG(5).u.integer != 0;
        /* fall through */

      case 4:
        user_data = &ARG(4);
        /* fall_through */
        
      case 3:
        if (ARG(3).type != T_MAPPING)
          Pike_error("Incorrect type for argument 3: expected a mapping\n");
        entities = ARG(3).u.mapping;
        /* fall through */

      case 2:
        if (ARG(2).type != T_OBJECT)
          Pike_error("Incorrect type for argument 2: expected an object\n");
        callbacks = ARG(2).u.object;
        add_ref(callbacks);
        /* fall through */

      case 1:
        if (ARG(1).type != T_OBJECT && ARG(1).type != T_STRING)
          Pike_error("Incorrect type for argument 1: expected a string or an object\n");
        if (ARG(1).type == T_OBJECT) {
          file_obj = ARG(1).u.object;
          add_ref(file_obj);
        } else
          input_data = ARG(1).u.string;
        break;

      default:
        Pike_error("Incorrect number of arguments: expected between 2 and 4\n");
  }
  
  /* check whether file_obj is Stdio.File or derived */
  if (file_obj && find_identifier("read", file_obj->prog) < 0)
    Pike_error("Passed file object is not Stdio.File or derived from it\n");

  /* The parser state is initialized so that no time is wasted for
   * callbacks that aren't used by the calling Pike code.
   */
  THIS->sax = (xmlSAXHandler*)calloc(1, sizeof(xmlSAXHandler));
  if (!THIS->sax)
    SIMPLE_OUT_OF_MEMORY_ERROR("create", sizeof(xmlSAXHandler));
  
  /* check whether the callbacks object contains all the required methods
   * */
  if (!is_callback_ok(callbacks, &missing_method)) 
    Pike_error("Passed callbacks object is not valid. The %s method is missing.\n",
               missing_method);
  
  /* choose the parsing method */
  if (file_obj)
    THIS->parsing_method = PARSE_PUSH_PARSER;
  else if (input_data && input_is_data)
    THIS->parsing_method = PARSE_MEMORY_PARSER;
  else if (input_data)
    THIS->parsing_method = PARSE_FILE_PARSER;
  else
    Pike_error("Cannot determine the parser type to use\n");

  pop_n_elems(args);
  
  /* initialize the parser and state */
  switch (THIS->parsing_method) {
      case PARSE_PUSH_PARSER:
        THIS->file_obj = file_obj;
        /* the context creation is delayed in this case */
        break;

      case PARSE_MEMORY_PARSER:
      case PARSE_FILE_PARSER:
        copy_shared_string(THIS->input_data, input_data);
        break;
  }

  THIS->callbacks = callbacks;

  if (user_data)
    assign_svalue_no_free(&THIS->user_data, user_data);
  else {
    THIS->user_data.type = PIKE_T_INT;
    THIS->user_data.u.integer = 0;
    THIS->user_data.subtype = 1;
  }
}

static void f_parse_xml(INT32 args)
{
  xmlDocPtr   doc = NULL;
  
  switch (THIS->parsing_method) {
      case PARSE_PUSH_PARSER:
        Pike_error("Push parser not implemented yet. Please bug grendel@caudium.net to implement it.");
        
      case PARSE_MEMORY_PARSER:
        doc = xmlSAXParseMemory(THIS->sax, THIS->input_data->str, THIS->input_data->len, 1);
        break;

      case PARSE_FILE_PARSER:
        doc = xmlSAXParseFileWithData(THIS->sax, THIS->input_data->str, 1, NULL);
        break;
  }
  if ( doc != NULL )
    xmlFreeDoc(doc);

  push_int(0);
}

static void f_parse_html(INT32 args)
{
  xmlDocPtr   doc = NULL;
  char * encoding = "utf-8";
  struct pike_string *encode_data = NULL;
  
  if ( args == 1 ) {
      if ( ARG(1).type != T_STRING ) 
	  Pike_error("Incorrect type for argument 0: expected string (encoding)\n");
      encode_data = ARG(1).u.string;
      encoding = encode_data->str;
  }
  // do nothing
  if ( THIS->input_data->len == 0 )
    push_int(0);

  switch (THIS->parsing_method) {
      case PARSE_PUSH_PARSER:
        Pike_error("Push parser not implemented yet. Please bug grendel@caudium.net to implement it.");
        
      case PARSE_MEMORY_PARSER:
        htmlHandleOmittedElem(1);
	doc=htmlSAXParseDoc(THIS->input_data->str, encoding, THIS->sax, NULL);
        break;

      case PARSE_FILE_PARSER:
        htmlHandleOmittedElem(1);
	doc=htmlSAXParseFile(THIS->input_data->str, "utf-8", THIS->sax, NULL);
	break;
  }
  if ( doc != NULL )
    xmlFreeDoc(doc);
  
  push_int(0);
}

static void init_sax(struct object *o)
{
  if (!THIS)
    return;

  THIS->ctxt = NULL;
  THIS->sax = NULL;
  THIS->filename = NULL;
  THIS->parsing_method = 0;
  THIS->callbacks = NULL;
  THIS->file_obj = NULL;
  THIS->input_data = NULL;

  econtent_type = make_shared_string("type");
  econtent_ocur = make_shared_string("ocur");
  econtent_name = make_shared_string("name");
  econtent_prefix = make_shared_string("prefix");
  econtent_c1 = make_shared_string("child1");
  econtent_c2 = make_shared_string("child2");
}

static void exit_sax(struct object *o)
{
  if (!THIS)
    return;

  if (THIS->filename)
    free(THIS->filename);

  if (econtent_type) free_string(econtent_type);
  if (econtent_ocur) free_string(econtent_ocur);
  if (econtent_name) free_string(econtent_name);
  if (econtent_prefix) free_string(econtent_prefix);
  if (econtent_c1) free_string(econtent_c1);
  if (econtent_c2) free_string(econtent_c2);
}

int _init_xml_sax(void)
{
  start_new_program();
  ADD_STORAGE(sax_storage);

  set_init_callback(init_sax);
  set_exit_callback(exit_sax);

  ADD_FUNCTION("create", f_create,
               tFunc(tOr(tString, tObj) tObj tOr(tMapping, tVoid) tOr(tMixed, tVoid) tOr(tInt, tVoid), tVoid), 0);
  ADD_FUNCTION("parse", f_parse_xml, tFunc(tVoid, tInt), 0);
  ADD_FUNCTION("getLineNumber", f_getLineNumber, tFunc(tVoid, tInt), 0);
  ADD_FUNCTION("getColumnNumber", f_getColumnNumber, tFunc(tVoid, tInt), 0);
  
  xml_program = end_program();
  add_program_constant("SAX", xml_program, 0);

  start_new_program();
  ADD_STORAGE(sax_storage);
  
  set_init_callback(init_sax);
  set_exit_callback(exit_sax);

  ADD_FUNCTION("create", f_create,
               tFunc(tOr(tString, tObj) tObj tOr(tMapping, tVoid) tOr(tMixed, tVoid) tOr(tInt, tVoid), tVoid), 0);
  ADD_FUNCTION("parse", f_parse_html, tFunc(tOr(tString,tVoid), tInt), 0);
  ADD_FUNCTION("getLineNumber", f_getLineNumber, tFunc(tVoid, tInt), 0);
  ADD_FUNCTION("getColumnNumber", f_getColumnNumber, tFunc(tVoid, tInt), 0);
  
  html_program = end_program();
  add_program_constant("HTML", html_program, 0);
  
  return 1;
}

int _shutdown_xml_sax(void)
{
  return 1;
}
#endif
