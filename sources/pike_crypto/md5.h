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
 * $Id: md5.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */


#include "crypto_types.h"

#define MD5_DATASIZE    64
#define MD5_DATALEN     16
#define MD5_DIGESTSIZE  16
#define MD5_DIGESTLEN    4

struct md5_ctx {
  unsigned INT32 digest[MD5_DIGESTLEN]; /* Digest */
  unsigned INT32 count_l, count_h;      /* Block count */
  unsigned INT8 block[MD5_DATASIZE];   /* One block buffer */
  int index;                            /* index into buffer */
};

void md5_init(struct md5_ctx *ctx);
void md5_update(struct md5_ctx *ctx, unsigned INT8 *buffer, unsigned INT32 len);
void md5_final(struct md5_ctx *ctx);
void md5_digest(struct md5_ctx *ctx, INT8 *s);
void md5_copy(struct md5_ctx *dest, struct md5_ctx *src);
