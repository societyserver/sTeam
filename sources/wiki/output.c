/*
 * output.c
 *
 * print to output file.
 */

/*
 * Included headers:
 *
 * output: interface to the rest of the world
 * globals: Program_Name
 * stdio: fprintf(), fputc(), stderr
 * stdarg: va_list, va_start(), va_end(), vfprintf()
 */
#include "output.h"
#include "globals.h"
#include <stdio.h>
#include <stdarg.h>

extern char* yyoutbuffer;

struct OutBlock* new_output()
{
  struct OutBlock *out;
  out = (struct OutBlock*)malloc(sizeof(struct OutBlock));
  out->nextBlock = NULL;
  out->addr = NULL;
  out->size = 0;
  return out;
}

char* get_output(struct OutBlock* o)
{
  char*  __out;
  struct OutBlock* ob;
  
  int sz = 0;
  ob = o;
  while ( ob != NULL ) {
    sz += ob->size;
    ob = ob->nextBlock;
  }
  __out = malloc(sz*sizeof(char)+1);
  __out[0] = '\0';
  
  while ( o != NULL ) {
    if ( o->addr != NULL ) {
      strcat(__out, o->addr);
      free(o->addr);
    }
    ob = o->nextBlock;
    free(o);
    o = ob;
  }
  strcat(__out, "\0");
  return __out;
}

#define THIS ((wiki_store*)Pike_fp->current_storage)

/*
 * output()
 *
 * print the given stuff to the output file
 */
void output(char *fmt, ...)
{
  va_list args;
  char* str;
  int size = strlen(fmt);
  char* argstr = fmt;

  va_start(args, fmt);
  while (*argstr) {
    switch(*argstr++) {
    case '%':
	str = va_arg(args, char*);
	size += strlen(str);
	break;
    default:
	size++;
	break;
    }
  }
  va_end(args);

  char* out = (char*)malloc(sizeof(char)*size);
  out[0] = '\0';

  va_start(args, fmt);
  
  vsprintf(out, fmt, args);
  
  va_end(args);

  THIS->outCurrent->addr = out;
  THIS->outCurrent->size = strlen(out);
  THIS->outCurrent->nextBlock = new_output();
  THIS->outCurrent = THIS->outCurrent->nextBlock;
}



/*
 * output()
 *
 * print the given stuff to the output file
 */
void output_cb(char *fmt, int len)
{
  char* out = (char*)malloc(sizeof(char)*len+1);
  strncpy(out, fmt, len);
  out[len] = '\0';

  THIS->outCurrent->addr = out;
  THIS->outCurrent->size = strlen(out);
  THIS->outCurrent->nextBlock = new_output();
  THIS->outCurrent = THIS->outCurrent->nextBlock;
}

