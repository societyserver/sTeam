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
 * $Id: functions.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _FUNC_H
#define _FUNC_H

#include <coal.h>

#define _FUNC_NUMPARAMS   0
#define _FUNC_SYNOPSIS    1
#define _FUNC_KEYWORDS    2
#define _FUNC_DESCRIPTION 3
#define _FUNC_PARAMS      4
#define _FUNC_ARGS        5

#define PARAM_INT (1<<CMD_TYPE_INT)
#define PARAM_FLOAT (1<<CMD_TYPE_FLOAT)
#define PARAM_STRING (1<<CMD_TYPE_STRING)
#define PARAM_OBJECT (1<<CMD_TYPE_OBJECT)
#define PARAM_ARRAY  (1<<CMD_TYPE_ARRAY)
#define PARAM_MAPPING (1<<CMD_TYPE_MAPPING)

#endif




