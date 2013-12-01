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
 * $Id: access.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _ACCESS_H
#define _ACCESS_H

#define ACCESS_READ(o1,o2) (_Security->AccessReadObj(o1, o2))
#define ACCESS_WRITE(o1, o2) (_Security->AccessWriteObj(o1, o2))

#define FAIL           -1
#define ACCESS_DENIED   0
#define ACCESS_GRANTED  1
#define ACCESS_BLOCKED  2

#define SANCTION_READ          1
#define SANCTION_EXECUTE       2
#define SANCTION_MOVE          4
#define SANCTION_WRITE         8
#define SANCTION_INSERT       16
#define SANCTION_ANNOTATE     32

#define SANCTION_SANCTION    (1<<8)
#define SANCTION_LOCAL       (1<<9)
#define SANCTION_ALL         (1<<15)-1
#define SANCTION_SHIFT_DENY   16
#define SANCTION_COMPLETE    (0xffffffff)
#define SANCTION_POSITIVE    (0xffff0000)
#define SANCTION_NEGATIVE    (0x0000ffff)

#define SANCTION_READ_ROLE (SANCTION_READ|SANCTION_EXECUTE|SANCTION_ANNOTATE)

#endif
