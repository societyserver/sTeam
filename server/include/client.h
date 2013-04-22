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
 * $Id: client.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#ifndef _CLIENT_H
#define _CLIENT_H
#define CLIENT_FEATURES_CHAT      (1<<1)
#define CLIENT_FEATURES_AWARENESS (1<<2)
#define CLIENT_FEATURES_EVENTS    (1<<3)
#define CLIENT_FEATURES_MOVE      (1<<4)
#define CLIENT_FEATURES_ALL       (1<<30)-1
#define CLIENT_STATUS_CONNECTED   1
#define CLIENT_STATUS_ACTIVE(s) ((s & CLIENT_FEATURES_CHAT)||(s&CLIENT_FEATURES_AWARENESS))
#endif
