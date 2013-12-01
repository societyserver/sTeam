/* Copyright (C) 2000-2005  Thomas Bopp, Thorsten Hampel, Ludger Merkens
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
 */
#include <stdio.h>
#include <stdlib.h>

#include "globals.h"
#include "output.h"
#include "transforms.h"
#include "yyexternals.h"

static struct program  *wiki_program;
extern lexer_t Lexer;


#define safe_push_text(_txt_) if ((_txt_)) push_text((_txt_)); else push_int(0)
#define THIS ((wiki_store*)Pike_fp->current_storage)
#define CB_ABSENT(_idx_) (THIS->callbackOffsets[(_idx_)] == -1)

#define CB_CALL(_offset_, _args_) apply_low(THIS->callbacks, THIS->callbackOffsets[(_offset_)], (_args_))
#define CB_OUT_RESULT()   if ( Pike_sp[-1].type == T_STRING ) {output_cb(Pike_sp[-1].u.string->str, Pike_sp[-1].u.string->len); }\
  pop_stack();

#ifndef ARG
/* Get argument # _n_ */
#define ARG(_n_) Pike_sp[-((args - _n_) + 1)]
#endif


char *yyinbuffer, *yyoutbuffer;


static char* callback_api[] =
{
  "annotationWiki", "linkInternalWiki", "imageWiki", "hyperlinkWiki",
  "barelinkWiki", "embedWiki", "pikeWiki", "tagWiki", "headingWiki", "mathWiki",
};

void head(char* heading)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(heading);
  CB_CALL(cb_heading, 3);
  CB_OUT_RESULT();
}

void bold(void)
{
  if ( THIS->bold ) {
    output( "</strong>");
    THIS->bold = FALSE;
  }
  else {
    output( "<strong>");
    THIS->bold = TRUE;
  }
}

/*
 * italic()
 *
 * convert ''text'' into <i>text</i>
 */
void italic(void)
{
    if ( THIS->italic ) { 
       output( "</em>");
       THIS->italic = FALSE;
    }
    else {
       output( "<em>");
       THIS->italic = TRUE;
    }
}

void tag(char* stuff)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(stuff);
  CB_CALL(cb_tag, 3);
  CB_OUT_RESULT();
}

void math(char* stuff)
{
    add_ref(THIS->obj);
    push_object(THIS->obj);
    add_ref(THIS->fp);
    push_object(THIS->fp);
    
    push_text(stuff);
    CB_CALL(cb_math, 3);
    CB_OUT_RESULT();
}

void annotationInternal(char* ann_text)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(ann_text);
  CB_CALL(cb_annotation, 3);
  CB_OUT_RESULT();
}


void hyperlink(char* link)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(link);
  CB_CALL(cb_hyperlink, 3);
  CB_OUT_RESULT();
}

void barelink(char* link)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(link);
  CB_CALL(cb_barelink, 3);
  CB_OUT_RESULT();
}

void image(char* link)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);

  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(link);
  CB_CALL(cb_image, 3);
  CB_OUT_RESULT();
}

void embed(char* link)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);

  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(link);
  CB_CALL(cb_embed, 3);
  CB_OUT_RESULT();
}

void pi_pike(char* code)
{
  add_ref(THIS->obj);
  push_object(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->fp);

  push_text(code);
  CB_CALL(cb_pike, 3);
  CB_OUT_RESULT();
}


/*
 * linkInternal
 *
 * turns a wikilink into an HTML link.
 * Assumes string starts with capitalize and are joined Words, like WikiWiki
 *
 * Split the strings at the |
 * link_text gets the stuff to the left 
 * alt_text gets the stuff to the right
 */ 
void linkInternal(char *wiki_text)
{
  add_ref(THIS->obj);
  add_ref(THIS->fp);
  push_object(THIS->obj);
  push_object(THIS->fp);
  push_text(wiki_text);
  CB_CALL(cb_linkInternal, 3);
  CB_OUT_RESULT();
}

static int get_callbacks(struct object *callbacks, wiki_store* storage)
{
  int               ioff, i;
  struct identifier  *ident;
  void                **tmp;

  if (!callbacks)
    return 0;

  if ( storage == NULL )
      Pike_error("Failed to initialize - no storage !");

  i = 0;
  while (i < CALLBACK_API_SIZE) {
    ioff = find_identifier(callback_api[i], callbacks->prog);
    if ( ioff < 0 ) {
      Pike_error("Function %s not found \n", callback_api[i]);
      storage->callbackOffsets[i] = -1;
    }
    else {
      ident = ID_FROM_INT(callbacks->prog, ioff);
      if (IDENTIFIER_IS_FUNCTION(ident->identifier_flags)) {
	/* Put the offset in the callbacks array and initialize the SAX handler
	 * structure with appropriate function pointer. The pointer arithmetic
	 * is hairy, but it works :>
	 */
	 storage->callbackOffsets[i] = ioff;
      }
    }
    i++;
  }
  return 1;
}

void f_create(INT32 args)
{   
  struct object *callbacks = NULL;
  wiki_store* storage;

  if ( Pike_sp[-args].type != T_OBJECT )
    Pike_error("Incorrect type for argument 1: expected an object\n");

  storage = THIS;
  callbacks = Pike_sp[-args].u.object;
  add_ref(callbacks);
  get_callbacks(callbacks, storage);
  THIS->callbacks = callbacks;
  pop_n_elems(args);
}

char* low_parse(char* str, struct object* obj, struct object* fp)
{
  add_ref(fp);
  THIS->fp = fp;

  add_ref(obj);
  THIS->obj = obj;
  THIS->bold = FALSE;
  THIS->italic = FALSE;


  THIS->outStart = new_output();
  THIS->outCurrent = THIS->outStart;
  
  yyinbuffer = str;

  init_lexer();
  yyin = NULL;
  yylex();
  prepare_status(blank);

  return get_output(THIS->outStart);

}


void f_parse(INT32 args)
{
  char *html = NULL;
  struct pike_string *str = NULL;
  struct object* obj;
  struct object*  fp;

  THREADS_ALLOW();
  THREADS_DISALLOW();

  if ( ARG(1).type != T_OBJECT )
    Pike_error("Incorrect type for argument 1: expected object\n");
  if ( ARG(2).type != T_OBJECT )
    Pike_error("Incorrect type for argument 2: expected object\n");
  if ( ARG(3).type != T_STRING )
    Pike_error("Incorrect type for argument 3: expected string\n");
  
  obj = ARG(1).u.object;
  fp = ARG(2).u.object;
  str = ARG(3).u.string;

  THREAD_SAFE_RUN(html=low_parse(str->str, obj, fp));
  pop_n_elems(args);

  push_string( make_shared_string( html ) );
  /*push_text(html);*/
  free(html);  
}



void f_parse_buffer(INT32 args)
{
  struct pike_string *str = NULL;
  
  if ( ARG(1).type != T_STRING )
    Pike_error("Incorrect type for argument 1: expected string\n");
  str = ARG(1).u.string;
  wiki_scan_buffer(str->str);
}

void init_wiki(struct object *o)
{
  if (!THIS)
    return;
  THIS->callbacks = NULL;
}

void exit_wiki(struct object *o)
{
}



PIKE_MODULE_INIT
{
  start_new_program();
  ADD_STORAGE(wiki_store);
  set_init_callback(init_wiki);
  set_exit_callback(exit_wiki);

  ADD_FUNCTION("create", f_create, tFunc(tObj, tVoid), 0);
  ADD_FUNCTION("parse", f_parse, tFunc(tObj tObj tString, tString),0);
  ADD_FUNCTION("parse_buffer", f_parse_buffer, tFunc(tString, tVoid), 0);
  wiki_program = end_program();
  add_program_constant("Parser", wiki_program, 0);
}

PIKE_MODULE_EXIT
{
}
