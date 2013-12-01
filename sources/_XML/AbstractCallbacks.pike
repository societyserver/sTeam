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
 * $Id: AbstractCallbacks.pike,v 1.1 2008/03/31 13:39:57 exodusd Exp $
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

//! Callback on internal subset declaration.
//!
//! @param name
//!  The root element name
//!
//! @param externalID
//!  The external ID
//!
//! @param systemID
//!  The SYSTEM ID (e.g. filename or URL)
void internalSubsetSAX(object parser, string name, string externalID, string systemID, void|mixed userData)
{}

//! Is this document tagged standalone or not.
//!
//! @returns
//!   0 -- the document is not standalone, 1 -- the document is standalone
int isStandaloneSAX(object parser, void|mixed userData)
{
  return 0;
}

//! Does this document have an internal subset
//!
//! @returns
//!  0 -- internal subset is absent, 1 -- internal subset is present.
int hasInternalSubsetSAX(object parser, void|mixed userData)
{
  return 0;
}

//! Does this document have an external subset
//!
//! @returns
//!  0 -- external subset is absent, 1 -- external subset is present.
int hasExternalSubsetSAX(object parser, void|mixed userData)
{
  return 0;
}

string getEntitySAX(object parser, string name, void|mixed userData)
{
  return 0;
}

//! An entity definition has been parsed.
//!
//! @param name
//!  The entity name
//!
//! @param type
//!  The entity type
//!
//! @param publicId
//!  The public ID of the entity
//!
//! @param systemId
//!  The system ID of the entity
//!
//! @param content
//!  The entity value (unprocessed)
void entityDeclSAX(object parser, string name, int type, string publicId,
                   string systemId, string content, void|mixed userData)
{}

//! A notation declaration has been parsed.
//!
//! @param name
//!  The name of the notation
//!
//! @param publicId
//!  The public ID of the entity
//!
//! @param systemId
//!  The system ID of the entity
void notationDeclSAX(object parser, string name, string publicId, string systemId, void|mixed userData)
{}

//! An attribute definition has been parsed
//!
//! @param elem
//!  The name of the element
//!
//! @param fullname
//!  The attribute name
//!
//! @param type
//!  The attribute type
//!
//! @param def
//!  The type of default value
//!
//! @param defaultValue
//!  The default value of the attribute
//!
//! @param enumvals
//!  An array containing the enumerated value set for the attribute
void attributeDeclSAX(object parser, string elem, string fullname, int type, int def,
                      string defaultValue, array(string) enumvals, void|mixed userData)
{}

//! An element definition has been parsed
//!
//! @param name
//!  The element name
//!
//! @param type
//!  The element type
//!
//! @param content
//!  The element value tree represented as a mapping.
void elementDeclSAX(object parser, string name, int type, mapping(string:string|int) content,
                    void|mixed userData)
{}

//! An unparsed entity declaration was parsed
//!
//! @param name
//!  The name of the entity
//!
//! @param publicId
//!  The public ID of the entity
//!
//! @param systemId
//!  The system ID of the entity
//!
//! @param notationName
//!  The name of the notation
void unparsedEntityDeclSAX(object parser, string name, string publicId, string systemId, string notationName,
                           void|mixed userData)
{}

//! The start of the document was parsed
void startDocumentSAX(object parser, void|mixed userData)
{}

//! The end of the document was parsed
void endDocumentSAX(object parser, void|mixed userData)
{}

//! An opening tag has been parsed
//!
//! @param name
//!  The tag name
//!
//! @param ettrs
//!  A mapping with all the attributes parsed in the tag
void startElementSAX(object parser, string name, mapping(string:string) attrs, void|mixed userData)
{}

//! A closing tag has been parsed
//!
//! @param name
//!  The name of the tag.
void endElementSAX(object parser, string name, void|mixed userData)
{}

//! An entity reference has been parsed.
//!
//! @param name
//!  The entity name
void referenceSAX(object parser, string name, void|mixed userData)
{}

//! The parser returned some arbitrary characters.
//!
//! @param chars
//!  The parsed characters.
void charactersSAX(object parser, string chars, void|mixed userData)
{}

//! Some ignorable white space characters were parsed
//!
//! @param chars
//!  The parsed characters
void ignorableWhitespaceSAX(object parser, string chars, void|mixed userData)
{}

//! A processing instruction has been parsed
//!
//! @param target
//!  The target name
//!
//! @param data
//!  The PI data
void processingInstructionSAX(object parser, string target, string data, void|mixed userData)
{}

//! A comment has been parsed
//!
//! @param value
//!  The contents of the comment block
void commentSAX(object parser, string value, void|mixed userData)
{}

//! Parser warning callback.
//!
//! @param msg
//!  The warning text
void warningSAX(object parser, string msg, void|mixed userData)
{}

//! Parser error callback.
//!
//! @param msg
//!  The warning text
void errorSAX(object parser, string msg, void|mixed userData)
{}

//! Parser fatal error callback.
//!
//! @param msg
//!  The warning text
void fatalErrorSAX(object parser, string msg, void|mixed userData)
{}

void getParameterEntitySAX(object parser, void|mixed userData)
{}

//! A PCDATA block has been parsed
//!
//! @param value
//!  The contents of the block
void cdataBlockSAX(object parser, string value, void|mixed userData)
{}

//! An external subset declaration has been parsed
//!
//! @param name
//!  The root element name
//!
//! @param externalId
//!  The external ID
//!
//! @param systemId
//!  The system ID (e.g. a filename or URL)
void externalSubsetSAX(object parser, string name, string externalId, string systemId,
                       void|mixed userData)
{}











