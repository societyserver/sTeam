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
 * $Id: md5_pike.c,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#include "global.h"
#include "stralloc.h"
#include "interpret.h"
#include "svalue.h"
#include "constants.h"
#include "pike_macros.h"
#include "threads.h"
#include "object.h"
#include "interpret.h"


static void f_crypt_md5(INT32 args)
{
  char salt[8];
  char *ret, *saltp ="";
  char *choice =
    "cbhisjKlm4k65p7qrJfLMNQOPxwzyAaBDFgnoWXYCZ0123tvdHueEGISRTUV89./";
 
  if (args < 1)
    SIMPLE_TOO_FEW_ARGS_ERROR("crypt_md5", 1);

  if (Pike_sp[-args].type != T_STRING)
    SIMPLE_BAD_ARG_ERROR("crypt_md5", 1, "string");

  if (args > 1)
  {
    if (Pike_sp[1-args].type != T_STRING)
      SIMPLE_BAD_ARG_ERROR("crypt_md5", 2, "string");

    saltp = Pike_sp[1-args].u.string->str;
  } else {
    unsigned int i, r;
   for (i = 0; i < sizeof(salt); i++) 
    {
      r = my_rand();
      salt[i] = choice[r % (size_t) strlen(choice)];
    }
    saltp = salt;
  }

  ret = (char *)crypt_md5(Pike_sp[-args].u.string->str, saltp);

  pop_n_elems(args);
  push_string(make_shared_string(ret));
}


void
pike_module_init()
{
    ADD_FUNCTION("crypt_md5", f_crypt_md5,
		 tOr(tFunc(tStr,tStr), tFunc(tStr tStr,tStr)), 0);

}

void
pike_module_exit()
{
}

