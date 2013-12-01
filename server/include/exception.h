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
 * $Id: exception.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef EXCEPTION_H
#define EXCEPTION_H
#define E_ERROR    (1<<0 ) // an error has occured
#define E_LOCAL    (1<<1 ) // local exception, user defined
#define E_MEMORY   (1<<2 )  // some memory messed up, uninitialized mapping,etc
#define E_EVENT    (1<<3 ) // some exception on an event
#define E_ACCESS   (1<<4 )
#define E_PASSWORD (1<<5 )
#define E_NOTEXIST (1<<6 )
#define E_FUNCTION (1<<7 )
#define E_FORMAT   (1<<8 )
#define E_OBJECT   (1<<9 )
#define E_TYPE     (1<<10 )
#define E_MOVE     (1<<11 )
#define E_LOOP     (1<<12 )
#define E_LOCK     (1<<13)
#define E_QUOTA    (1<<14)
#define E_TIMEOUT  (1<<15)
#define E_CONNECT  (1<<16)
#define E_UPLOAD   (1<<17)
#define E_DOWNLOAD (1<<18)
#define E_DELETED  (1<<19)
#define E_ERROR_PROTOCOL (1<<20)
#endif
