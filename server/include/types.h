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
 * $Id: types.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _TYPES_H
#define _TYPES_H

#define CMD_TYPE_UNKNOWN   0
#define CMD_TYPE_INT       1 
#define CMD_TYPE_FLOAT     2
#define CMD_TYPE_STRING    3
#define CMD_TYPE_OBJECT    4
#define CMD_TYPE_ARRAY     5
#define CMD_TYPE_MAPPING   6
#define CMD_TYPE_MAP_ENTRY 7
#define CMD_TYPE_PROGRAM   8
#define CMD_TYPE_TIME      9
#define CMD_TYPE_FUNCTION 10
#define CMD_TYPE_DATA     11

#define XML_NORMAL  (1<<0)
#define XML_SIZE    (1<<1)
#define XML_OBJECTS (1<<2)
#define XML_TIME    (1<<3)
#define XML_OBJECT  (1<<4)

#define XML_TYPE_MASK   (0x0000000f)
#define XML_DISPLAY     (1<<8)

#define XML_ATTRIBUTES  (1<<8)
#define XML_ANNOTATIONS (1<<9)
#define XML_ACCESS      (1<<10)
#define XML_INVENTORY   (1<<11)
#define XML_BASIC       (1<<12)
#define XML_STYLESHEETS (1<<13)
#define XML_DETAILS     (1<<16)

#define XML_ALWAYS (XML_ATTRIBUTES|XML_ANNOTATIONS|XML_ACCESS|XML_INVENTORY|XML_BASIC|XML_DETAILS)

#endif
