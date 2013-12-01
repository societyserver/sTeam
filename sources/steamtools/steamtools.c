#include "global.h"
#include "interpret.h"
#include "mapping.h"
#include "array.h"
#include "builtin_functions.h"
#include "module_support.h"
#include "yyexternals.h"
#include "steamtools.h"
#include "threads.h"
#include "bignum.h"
#include "constants.h"
#include <stdio.h>

typedef void* yyscan_t;
typedef struct yy_buffer_state* YY_BUFFER_STATE;
extern YY_BUFFER_STATE yy_scan_bytes(char*, int, yyscan_t);
extern void yy_delete_buffer(YY_BUFFER_STATE, yyscan_t);


char* yyinbuffer;
struct svalue objectFunc;


char* low_serialize(struct svalue* val);

#define MM_CHECK_REALLOC(y)\
    if ( y >= mm-l ) {\
      mm += (y>=256?y+1:256);\
      char* newbuf = malloc(mm);\
      strcpy(newbuf, buf);\
      free(buf);\
      buf = newbuf;\
    }


char* low_serialize_mapping(struct svalue* val)
{
  char                 *buf;
  int              i, mm, l;
  char*                nbuf;
  struct svalue  sind, sval;
  struct keypair       *key;


  mm = 256;
  buf = malloc(mm);
  l = 3;
  buf[0] = '[';
  buf[1] = '\0';
  for (i=0; i < val->u.mapping->data->hashsize; i++) {
    for(key=val->u.mapping->data->hash[i];key;key=key->next) {
      sind = key->ind;
      sval = key->val;
      nbuf = low_serialize(&sind);

      MM_CHECK_REALLOC(strlen(nbuf));
      strcat(buf, nbuf);
      strcat(buf, ":");
      l += strlen(nbuf)+1;
      free(nbuf);

      nbuf = low_serialize(&sval);
      MM_CHECK_REALLOC(strlen(nbuf));
      strcat(buf, nbuf);
      strcat(buf, ",");
      l += strlen(nbuf)+1;
      free(nbuf);
    }
  }
  strcat(buf, "]");
  return buf;
}

char* low_serialize_array(struct svalue* val)
{
  char      *buf;
  int   i, mm, l;
  char*     nbuf;

  mm = 256;
  buf = malloc(mm);
  l = 3;
  buf[0] = '{';
  buf[1] = '\0';

  for (i=0;i<val->u.array->size;i++) {
    nbuf = low_serialize(&val->u.array->item[i]);
    MM_CHECK_REALLOC(strlen(nbuf));
    strcat(buf, nbuf);
    strcat(buf, ",");
    l += strlen(nbuf)+1;
    free(nbuf);
  }
  strcat(buf, "}");
  return buf;
}

char* low_serialize(struct svalue* val)
{
  char *buf;

  switch(val->type) {
  case T_MAPPING: {
    buf = low_serialize_mapping(val);
    break;
  }
  case T_ARRAY: {
    buf = low_serialize_array(val);
    break;
  }
  case T_STRING: {
    int i, j, mm;
    
    mm = val->u.string->len*6 + 3;
    buf = malloc(mm);
    buf[0] = '"';
    for (i=0,j=1;i<val->u.string->len;i++) {
      if (val->u.string->str[i]=='"') {
	buf[j] = '\0';
	strcat(buf, "\\char34");
	j += 7;
      }
      else if (val->u.string->str[i] != '\0') {
	buf[j] = val->u.string->str[i];
	j++;
      }
    }
    buf[j] = '"';
    buf[j+1] = '\0';
    break;
  }
  case T_FLOAT: {
    char * result = malloc( sizeof(char) * 1024 );
    sprintf(result, "%f", val->u.float_number);
    buf = malloc(strlen(result)+1);
    strcpy(buf, result);
    free( result );
    break;
  }
  case T_OBJECT: {
    int id, l, i;
    i = find_identifier("get_object_id", val->u.object->prog);
    if ( i >= 0 ) {
      apply_low(val->u.object, i, 0);
      id = Pike_sp[-1].u.integer;
      pop_stack();
      if ( id == 0 )
        l = 0;
      else
        l = log10(id);
      buf = malloc(l+3);
      sprintf(buf, "%%%d", id);
    }
    else {
      if ( val->subtype == NUMBER_NUMBER ) {
        push_constant_text("%O");
        push_svalue(val);
        f_sprintf(2);
        buf = malloc(Pike_sp[-1].u.string->len+1);
        strcpy(buf, Pike_sp[-1].u.string->str);
      }
      else {
	buf = malloc(1);
	buf[0] = '\0';
	id = 0;
      }
    }
    break;
  }
  case T_FUNCTION: {
    int i, id, l;
    if(val->u.efun) {
      struct svalue func;
      struct object* o;

      assign_svalue_no_free(&func, val);
      push_svalue(&func);
      f_function_object(1);
      o = Pike_sp[-1].u.object;
      i = find_identifier("get_object_id", o->prog);
      if (i>=0) {
	apply_low(o, i, 0);
	id = Pike_sp[-1].u.integer;
	pop_stack();
      }
      else 
	id = 0;
      pop_stack(); // function object
      push_svalue(&func);
      f_function_name(1);

      if ( id == 0 )
        l = 0;
      else 
        l = log10(id);
      l += Pike_sp[-1].u.string->len;
      buf = malloc(l+4);
      sprintf(buf, "$%s %d", Pike_sp[-1].u.string->str, id);
      free_svalue(&func);
      pop_stack();
    }
    else {
      buf = malloc(1);
      buf[0] = '\0';
    }
    break;
  }
  case T_INT: {
    int l;

    if ( val->u.integer == 0 )
      l = 0;
    else
      l = log10((unsigned INT32)val->u.integer);

    buf = malloc(l+2);
    sprintf(buf, "%d", (unsigned INT32)val->u.integer);
    break;
  }
  default: {
    fprintf(stderr, "Failed to serialize type %d\n", val->type);
  }
  }
  return buf;
}

void f_serialize(INT32 args)
{
  // serialize args(0)
  char* result;
  THREADS_ALLOW();
  THREADS_DISALLOW();
  THREAD_SAFE_RUN(result = low_serialize(&Pike_sp[-1]));
  pop_n_elems(args);
  push_text(result);
  free(result);
}

void low_unserialize_string(char* buf, int len)
{
  char*              str;
  int               i, j;
  char *c34 = "\\char34";

  buf++;
  len -= 2;
  
  str = malloc(len+1);
  j = 0;
  i = 0;
  while ( i < len ) {
    if (strncmp(&buf[i], c34, 7)==0) {
      i+=7;
      str[j] = '\"';
    }
    else {
      str[j] = buf[i];
      i++;
    }
    j++;
  }
  push_string(make_shared_binary_string(str, j));
  free(str);
}

void low_unserialize_float(char* buf)
{
  float f;
  sscanf(buf, "%f", &f);
  push_float(f);
}

void low_unserialize_integer(char* buf)
{
  struct svalue result;
  push_text(buf);
  push_text("%d");
  f_sscanf(2);
  if ( Pike_sp[-1].type == T_ARRAY ) {
    if ( Pike_sp[-1].u.array->size == 1 ) {
      assign_svalue_no_free(&result, &Pike_sp[-1].u.array->item[0]);
      pop_stack();
      push_svalue(&result);
      free_svalue(&result);
      return;
    }
  }
  pop_stack();
  push_text(buf);
  fprintf(stderr, "Failed to unserialize %s\n", buf);
}

void low_unserialize_object(char* buf)
{
  unsigned int d;
  sscanf(buf, "%%%d", &d);
  push_int(d);
  apply_svalue(&objectFunc, 1);

  // object is on top of stack
}

void low_unserialize_function(char* buf)
{
  int d;
  struct svalue object;
  char fname[255];
  
  if (sscanf(buf, "$%s %d", &fname, &d) != 2) {
    push_int(0);
    return;
  }

  push_int(d);
  apply_svalue(&objectFunc, 1); // object is on top
  if ( Pike_sp[-1].type != T_OBJECT ) {
    pop_stack();
    push_int(0);
    return; // 0 returned
  }
  
  assign_svalue_no_free(&object, &Pike_sp[-1]);
  pop_stack(); // empty
  
  // this might load objects and change the current flex buffer
  push_text(fname);

  struct svalue findObject;
  assign_svalue_no_free(&findObject, &objectFunc);
  
  apply(object.u.object, "find_function", 1);
  // function is on top!
  free_svalue(&object);
  assign_svalue_no_free(&objectFunc, &findObject);
  free_svalue(&findObject);
}

void low_unserialize_nothing()
{
  push_int(0);
}

void low_unserialize_mapping(int num)
{
  if ((num%2)==0)
    f_aggregate_mapping(num);
  else {
    f_aggregate(num); // use an array, but make sure stack is fine!
    fprintf(stderr, "WARNING: Wrong number of arguments to low_unserialize_mapping %d\n", num);
    Pike_error("Invalid UNSERIALIZE, wrong number of arguments to mapping.\n");
  }
}

void low_unserialize_array(int num) 
{
  f_aggregate(num);
}

void low_unserialize(INT32 args)
{
  struct svalue result;
  struct svalue* funcAddr;

  if ( Pike_sp[-2].type != T_STRING || Pike_sp[-2].u.string->len == 0 ) {
    pop_n_elems(args);
    push_int(0);
    return;
  }
  char* buf = Pike_sp[-2].u.string->str;
  int len = Pike_sp[-2].u.string->len;

  if (len==1&&buf[0]=='0') {
    pop_n_elems(args);
    push_int(0);
    return;
  } else if (len==2) { 
    if (strcmp(buf,"[]") == 0) {
      pop_n_elems(args);
      f_aggregate_mapping(0);
      return;
    }
    else if (strcmp(buf,"{}") == 0) {
      pop_n_elems(args);
      f_aggregate(0);
      return;
    }
  }

  switch(buf[0]) {
  case '"':
    pop_n_elems(args);
    low_unserialize_string(buf, strlen(buf));
    break;
  case '%':
    funcAddr = &Pike_sp[-1];
    assign_svalue_no_free(&objectFunc, &Pike_sp[-1]);
    pop_n_elems(args);
    low_unserialize_object(buf);
    free_svalue(&objectFunc);
    break;
  case '$':
    funcAddr = &Pike_sp[-1];
    assign_svalue_no_free(&objectFunc, &Pike_sp[-1]);
    pop_n_elems(args);
    low_unserialize_function(buf);
    free_svalue(&objectFunc);
    break;
  case '{':
  case '[': {
    yyscan_t scanner;
    struct stackType myStack;
    myStack.depth = 0;

    funcAddr = &Pike_sp[-1];
    assign_svalue_no_free(&objectFunc, &Pike_sp[-1]);
    pop_n_elems(args);

    yylex_init(&scanner);
    yyset_extra(&myStack, scanner);
    YY_BUFFER_STATE bstate = yy_scan_bytes(buf, len, scanner);

    yylex(scanner);
    //yy_delete_buffer(bstate, scanner);
    yylex_destroy(scanner);
    // result is on stack!
    if ( funcAddr == &Pike_sp[-1] ) {
      free_svalue(&objectFunc);
      push_int(0);
      return;
    }
    free_svalue(&objectFunc);
    break;
  }
  default: {
    pop_n_elems(args);
    int a, b;
    if ( sscanf(buf, "%d.%d", &a, &b) == 2 )
      low_unserialize_float(buf);
    else
      low_unserialize_integer(buf);
  }
  }
}

void f_unserialize(INT32 args)
{  
  THREADS_ALLOW();
  THREADS_DISALLOW();
  THREAD_SAFE_RUN(low_unserialize(args));
}

void f_caller(INT32 args)
{
  struct Pike_interpreter *i = &Pike_interpreter;
  struct pike_frame *f;
  struct object* o = Pike_sp[-1].u.object;

  for (f = i->frame_pointer; f; f = f->next) {
    if ( f->current_object == o )
      break;
  }

  for (; f; f = f->next) {
    if ( f->current_object != o ) {
      pop_n_elems(args);
      ref_push_object(f->current_object);
      return;
    }
  }
  pop_n_elems(args);
  push_int(0);
  // otherwise CALLER == obj ?
}

PIKE_MODULE_INIT
{
  ADD_FUNCTION("unserialize", f_unserialize, tFunc(tString tFunc(tInt, tObj), tAny), 0);
  ADD_FUNCTION("serialize", f_serialize, tFunc(tAny, tString), 0);
  ADD_FUNCTION("get_caller", f_caller, tFunc(tObj, tObj), 0);
}

PIKE_MODULE_EXIT
{
}
