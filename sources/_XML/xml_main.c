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
 * $Id: xml_main.c,v 1.1 2008/03/31 13:39:57 exodusd Exp $
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

#ifdef fp
#undef fp
#endif

#include "xml_config.h"

#include "xml_sax.h"


#ifdef HAVE_XML2
#include <libxml/entities.h>

/*! @decl int substituteEntitiesDefault(int def)
 */
static void f_substituteEntitiesDefault(INT32 args)
{
  int   i;

  get_all_args("substituteEntitiesDefault", args, "%d", &i);
  i = i ? 1 : 0;

  pop_n_elems(args);
  push_int(xmlSubstituteEntitiesDefault(i));
}

/* @decl int keepBlanksDefault(int def)
 */
static void f_keepBlanksDefault(INT32 args)
{
  int   i;

  get_all_args("keepBlanksDefault", args, "%d", &i);
  i = i ? 1 : 0;

  pop_n_elems(args);
  push_int(xmlKeepBlanksDefault(i));
}

static void f_utf8ToHTML(INT32 args)
{
  char *html = NULL;
  struct pike_string *str = NULL;
  int outlen, inlen;

  str = Pike_sp[-args].u.string;

  outlen = str->len << 1;
  html = (char*)malloc(outlen + 1);
  if (!html)
    Pike_error("Out of memory");
  
  inlen = str->len;
  if ( UTF8ToHtml(html, &outlen, str->str, &inlen) < 0 ) {
    free(html);
    Pike_error("Cannot convert to html!");
  }
  html[outlen] = '\0';
  pop_n_elems(args);
  push_text(html);
  free(html);
}

static void f_utf8ToISO(INT32 args)
{
  char *html = NULL;
  struct pike_string *str = NULL;
  int outlen, inlen;

  str = Pike_sp[-args].u.string;

  outlen = str->len << 1;
  html = (char*)malloc(outlen + 1);
  if (!html)
    Pike_error("Out of memory");
  
  inlen = str->len;
  if ( UTF8Toisolat1(html, &outlen, str->str, &inlen) < 0 ) {
    free(html);
    Pike_error("Cannot convert to isolat1!");
  }
  html[outlen] = '\0';
  pop_n_elems(args);
  push_text(html);
  free(html);
}

static void f_utf8Check(INT32 args)
{
  struct pike_string *str = NULL;
  int result;

  if ( Pike_sp[-args].type != T_STRING ) 
    Pike_error("utf8_check(): Wrong argument 1 - needs string to check !\n");
    
  str = Pike_sp[-args].u.string;
  result = xmlCheckUTF8(str->str);
  pop_n_elems(args);
  push_int(result);
}

void pike_module_init(void)
{
#ifdef PEXTS_VERSION
  pexts_init();
#endif

  /* initialize the library */
  xmlInitParser();
  xmlLineNumbersDefault(1);
  xmlSubstituteEntitiesDefault(1);

  /* initialize the classes */
  if (!_init_xml_sax())
    Pike_error("Could not initialize the SAX class");


  /* global functions */
  ADD_FUNCTION("substituteEntitiesDefault", f_substituteEntitiesDefault,
               tFunc(tInt, tInt), 0);
  ADD_FUNCTION("keepBlanksDefault", f_keepBlanksDefault,
               tFunc(tInt, tInt), 0);
  ADD_FUNCTION("utf8_to_html", f_utf8ToHTML, tFunc(tString, tString), 0);
  ADD_FUNCTION("utf8_to_isolat1", f_utf8ToISO, tFunc(tString, tString), 0);
  ADD_FUNCTION("utf8_check", f_utf8Check, tFunc(tString, tInt), 0);
  
  /* some contstants */
  add_integer_constant("XML_INTERNAL_GENERAL_ENTITY", XML_INTERNAL_GENERAL_ENTITY, 0);
  add_integer_constant("XML_EXTERNAL_GENERAL_PARSED_ENTITY", XML_EXTERNAL_GENERAL_PARSED_ENTITY, 0);
  add_integer_constant("XML_EXTERNAL_GENERAL_UNPARSED_ENTITY", XML_EXTERNAL_GENERAL_UNPARSED_ENTITY, 0);
  add_integer_constant("XML_INTERNAL_PARAMETER_ENTITY", XML_INTERNAL_PARAMETER_ENTITY, 0);
  add_integer_constant("XML_EXTERNAL_PARAMETER_ENTITY", XML_EXTERNAL_PARAMETER_ENTITY, 0);
  add_integer_constant("XML_INTERNAL_PREDEFINED_ENTITY", XML_INTERNAL_PREDEFINED_ENTITY, 0);

  add_integer_constant("XML_ATTRIBUTE_CDATA", XML_ATTRIBUTE_CDATA, 0);
  add_integer_constant("XML_ATTRIBUTE_ID", XML_ATTRIBUTE_ID, 0);
  add_integer_constant("XML_ATTRIBUTE_IDREF", XML_ATTRIBUTE_IDREF, 0);
  add_integer_constant("XML_ATTRIBUTE_IDREFS", XML_ATTRIBUTE_IDREFS, 0);
  add_integer_constant("XML_ATTRIBUTE_ENTITY", XML_ATTRIBUTE_ENTITY, 0);
  add_integer_constant("XML_ATTRIBUTE_ENTITIES", XML_ATTRIBUTE_ENTITIES, 0);
  add_integer_constant("XML_ATTRIBUTE_NMTOKEN", XML_ATTRIBUTE_NMTOKEN, 0);
  add_integer_constant("XML_ATTRIBUTE_NMTOKENS", XML_ATTRIBUTE_NMTOKENS, 0);
  add_integer_constant("XML_ATTRIBUTE_ENUMERATION", XML_ATTRIBUTE_ENUMERATION, 0);
  add_integer_constant("XML_ATTRIBUTE_NOTATION", XML_ATTRIBUTE_NOTATION, 0);

  add_integer_constant("XML_ATTRIBUTE_NONE", XML_ATTRIBUTE_NONE, 0);
  add_integer_constant("XML_ATTRIBUTE_REQUIRED", XML_ATTRIBUTE_REQUIRED, 0);
  add_integer_constant("XML_ATTRIBUTE_IMPLIED", XML_ATTRIBUTE_IMPLIED, 0);
  add_integer_constant("XML_ATTRIBUTE_FIXED", XML_ATTRIBUTE_FIXED, 0);

  add_integer_constant("XML_ELEMENT_CONTENT_PCDATA", XML_ELEMENT_CONTENT_PCDATA, 0);
  add_integer_constant("XML_ELEMENT_CONTENT_ELEMENT", XML_ELEMENT_CONTENT_ELEMENT, 0);
  add_integer_constant("XML_ELEMENT_CONTENT_SEQ", XML_ELEMENT_CONTENT_SEQ, 0);
  add_integer_constant("XML_ELEMENT_CONTENT_OR", XML_ELEMENT_CONTENT_OR, 0);

  add_integer_constant("XML_ELEMENT_CONTENT_ONCE", XML_ELEMENT_CONTENT_ONCE, 0);
  add_integer_constant("XML_ELEMENT_CONTENT_OPT", XML_ELEMENT_CONTENT_OPT, 0);
  add_integer_constant("XML_ELEMENT_CONTENT_MULT", XML_ELEMENT_CONTENT_MULT, 0);
  add_integer_constant("XML_ELEMENT_CONTENT_PLUS", XML_ELEMENT_CONTENT_PLUS, 0);

  add_integer_constant("XML_ELEMENT_TYPE_UNDEFINED", XML_ELEMENT_TYPE_UNDEFINED, 0);
  add_integer_constant("XML_ELEMENT_TYPE_EMPTY", XML_ELEMENT_TYPE_EMPTY, 0);
  add_integer_constant("XML_ELEMENT_TYPE_ANY", XML_ELEMENT_TYPE_ANY, 0);
  add_integer_constant("XML_ELEMENT_TYPE_MIXED", XML_ELEMENT_TYPE_MIXED, 0);
  add_integer_constant("XML_ELEMENT_TYPE_ELEMENT", XML_ELEMENT_TYPE_ELEMENT, 0);
}

void pike_module_exit(void)
{
  _shutdown_xml_sax();
  xmlCleanupParser();
}
#else
void pike_module_init(void)
{
#ifdef PEXTS_VERSION
  pexts_init();
#endif
}

void pike_module_exit(void)
{}
#endif
