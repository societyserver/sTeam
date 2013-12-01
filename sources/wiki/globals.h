/*
 * globals.h
 *
 * program-wide variables for wiki2html
 */

#ifndef GLOBALS_H
#define GLOBALS_H

#include <stdio.h>
#include "interpret.h"
#include "global.h"
#include "stralloc.h"
#include "boolean.h"
#include "pike_macros.h"
#include "module_support.h"
#include "mapping.h"
#include "threads.h"


struct Global_options
{
    char *base_url;
    char *image_url;
    char *document_title;
    char *program_name;
    char *stylesheet;

    FILE *input_file;
    FILE *output_file;

} Global;

#define CALLBACK_API_SIZE 10
#define cb_annotation    0x00
#define cb_linkInternal  0x01
#define cb_image         0x02
#define cb_hyperlink     0x03
#define cb_barelink      0x04
#define cb_embed         0x05
#define cb_pike          0x06
#define cb_tag           0x07
#define cb_heading       0x08
#define cb_math          0x09


typedef struct 
{
  struct object *callbacks;
  int callbackOffsets[CALLBACK_API_SIZE];
  struct object               *obj;
  struct object                *fp;
  struct OutBlock*        outStart;
  struct OutBlock*      outCurrent;
  boolean bold;
  boolean italic;

} wiki_store;

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


#endif

