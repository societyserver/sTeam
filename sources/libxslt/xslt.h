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
 * $Id: xslt.h,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */



/* This allows execution of c-code that requires the Pike interpreter to 
 * be locked from the Sablotron callback functions.
 */
#if defined(PIKE_THREADS) && defined(_REENTRANT)
#define THREAD_SAFE_RUN(COMMAND)  do {\
  struct thread_state *state;\
 if((state = thread_state_for_id(th_self()))!=NULL) {\
    if(!state->swapped) {\
      COMMAND;\
    } else {\
      mt_lock(&interpreter_lock);\
      SWAP_IN_THREAD(state);\
      COMMAND;\
      SWAP_OUT_THREAD(state);\
      mt_unlock(&interpreter_lock);\
    }\
  }\
} while(0)
#else
#define THREAD_SAFE_RUN(COMMAND) COMMAND
#endif


static ptrdiff_t Stylesheet_storage_offset;

#define THIS ((xslt_storage *)Pike_interpreter.frame_pointer->current_storage)
#define THAT ((xslt_storage *)Pike_interpreter.frame_pointer->current_storage)

#ifndef ARG
/* Get argument # _n_ */
#define ARG(_n_) Pike_sp[-((args - _n_) + 1)]
#endif

typedef struct
{
    struct pike_string      *xml;
    xmlDocPtr                doc;
    struct pike_string *base_uri;
    struct pike_string *encoding;
    struct pike_string  *err_str;
    struct pike_string      *xsl;

    struct svalue* match_include;
    struct svalue*  open_include;
    struct svalue*  read_include;
    struct svalue* close_include;
    int iPosition; // position inside the current file
    struct object* file; // the object returned from pike
    
    xsltStylesheetPtr stylesheet;
    
    struct mapping *variables;  
    struct mapping *err;
    struct pike_string *language;
    char *content_type, *charset;
} xslt_storage;

typedef struct
{
    xsltStylesheetPtr stylesheet;
    struct pike_string *err_str;
    struct svalue* match_include;
    struct svalue*  open_include;
    struct svalue*  read_include;
    struct svalue* close_include;
    int iPosition; // position inside the current file
    struct object* file; // the object returned from pike
    struct pike_string *language;
} stylesheet_storage;

typedef struct 
{
    xmlDocPtr domDoc;
    xmlNodePtr rootNode;
} dom_storage;

typedef struct
{
    xmlNodePtr node;
} node_storage;

static struct program  *dom_program = NULL;
static struct program  *node_program = NULL;

#define OBJ2_NODE(_o) ((node_storage *)get_storage(_o, _o->prog))
#define OBJ2_DOM(_o) ((dom_storage *)get_storage(_o, _o->prog))
#define NEW_NODE() clone_object(node_program, 1)

#define CHECK_NODE(_o) do { char * _x; \
  _x  = get_storage(_o, _o->prog); \
  if ( _x == NULL ) Pike_error("bad argument: expected libxslt.Node");\
  } while ( 0 );

#define CHECK_DOM(_o) do { char * _x; \
  _x  = get_storage(_o, _o->prog); \
  if ( _x == NULL ) Pike_error("bad argument: expected libxslt.DOM");\
  } while ( 0 );

#define THISDOM ((dom_storage*)Pike_fp->current_storage)
#define THISNODE ((node_storage*)Pike_fp->current_storage)


#ifndef ADD_STORAGE
/* Pike 0.6 */
#define ADD_STORAGE(x) add_storage(sizeof(x))
#define MY_MAPPING_LOOP(md, COUNT, KEY) \
  for(COUNT=0;COUNT < md->hashsize; COUNT++ ) \
	for(KEY=md->hash[COUNT];KEY;KEY=KEY->next)
#else
/* Pike 7.x and newer */
#define MY_MAPPING_LOOP(md, COUNT, KEY) \
  for(COUNT=0;COUNT < md->data->hashsize; COUNT++ ) \
	for(KEY=md->data->hash[COUNT];KEY;KEY=KEY->next)
#endif

static void f_set_xml_data(INT32 args); 
static void f_set_xml_file(INT32 args); 
static void f_set_variables(INT32 args); 
static void f_set_base_uri(INT32 args); 
static void f_parse( INT32 args );
static void f_create( INT32 args );
static void f_create_stylesheets( INT32 args );
static void f_content_type( INT32 args );
static void f_charset( INT32 args );
static void f_set_include_callbacks( INT32 args );
void xml_error(void* ctx, const char* msg, ...);







