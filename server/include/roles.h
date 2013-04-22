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
 * $Id: roles.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _ROLES_H
#define _ROLES_H

#define ROLE_READ_ALL          1 // roles are related to sanction permissions
#define ROLE_EXECUTE_ALL       2
#define ROLE_MOVE_ALL          4
#define ROLE_WRITE_ALL         8
#define ROLE_INSERT_ALL        16
#define ROLE_ANNOTATE_ALL      32
#define ROLE_SANCTION_ALL      (1<<8)
#define ROLE_REBOOT            (1<<16) // here are sanction-permission 
#define ROLE_REGISTER_CLASSES  (1<<17) // independent roles(at negative rights)
#define ROLE_GIVE_ROLES        (1<<18)
#define ROLE_CHANGE_PWS        (1<<19)
#define ROLE_REGISTER_MODULES  (1<<20)
#define ROLE_CREATE_TOP_GROUPS (1<<21)

#define ROLE_ALL_ROLES       (1<<31)-1+(1<<30)

#endif
