#include "global.h"
#include "interpret.h"
#include "mapping.h"
#include "array.h"
#include "builtin_functions.h"
#include "module_support.h"

#include <stdio.h>

#define BEGINMASK 255
#define COAL_ARGOFF 18

#define CMD_TYPE_UNKNOWN   0
#define CMD_TYPE_INT       1
#define CMD_TYPE_FLOAT     2
#define CMD_TYPE_STRING    3
#define CMD_TYPE_OBJECT    4
#define CMD_TYPE_ARRAY     5
#define CMD_TYPE_MAPPING   6
#define CMD_TYPE_MAP_ENTRY 7
#define CMD_TYPE_PROGRAM   8
#define CMD_TYPE_TIME      9
#define CMD_TYPE_FUNCTION 10
#define CMD_TYPE_DATA     11

#define LOW_UNSERIALIZE_INT(buf,i) ( (((unsigned char)buf[i])<<24) + (((unsigned char)buf[i+1])<<16) + (((unsigned char)buf[i+2])<<8) + (((unsigned char)buf[i+3])))
#define LOW_UNSERIALIZE_SHORT(buf,i) ((((unsigned char)buf[i])<<8)+((unsigned char)buf[i+1]))

static int coal_low_unserialize_int(char* buf, int i)
{
  unsigned char b0, b1, b2, b3;
  b0 = buf[i];
  b1 = buf[i+1];
  b2 = buf[i+2];
  b3 = buf[i+3];

  int result = (b0<<24) + (b1<<16) + (b2<<8) + b3;
  return result;

  result = (int)*(&buf+i);
  b0 = result % 256;
  result = result / 256;
  b1 = result % 256;
  result = result / 256;
  b2 = result % 256;
  result = result / 256;
  b3 = result % 256;
  return (((b0*256+b1)*256+b2)*256+b3);
}

static void coal_low_compose_int(char* buf, int i)
{
  *(buf) = (i&0xff000000)>>24;
  *(buf+1) = (i&0x00ff0000)>>16;
  *(buf+2) = (i&0x0000ff00)>>8;
  *(buf+3) = i & 255;
}

static void coal_low_compose_short(char* buf, int i)
{
  *(buf) = (i&65280)>>8;
  *(buf+1) = i & 255;
}

static void coal_low_compose_object(char* buf, int oid, int classid)
{
  // use integer id 0 for unserializeable objects!
  *buf = CMD_TYPE_OBJECT;
  coal_low_compose_int(buf+1, oid);
  coal_low_compose_int(buf+5, classid); // class 0
}


static void f_coal_compose(INT32 args)
{
  int tid = Pike_sp[-4].u.integer;
  int cmd = Pike_sp[-3].u.integer;
  int oid = Pike_sp[-2].u.integer;
  int clid = Pike_sp[-1].u.integer;

  int s = 18;
  char* buf = malloc(sizeof(char)*s+1);
  *buf = BEGINMASK;
  *(buf+1) = ' ';
  *(buf+2) = ' ';
  *(buf+3) = ' ';
  *(buf+4) = ' ';
  coal_low_compose_int(buf+5, tid);
  *(buf+9) = cmd;
  coal_low_compose_int(buf+10, oid);
  coal_low_compose_int(buf+14, clid);

  pop_n_elems(args);
  push_string(make_shared_binary_string(buf, (size_t) s));
  free(buf);
}

static void f_compose_int(INT32 args)
{
  int id = Pike_sp[-1].u.integer;
  char* buf = malloc(sizeof(char)*4+1);
  coal_low_compose_int(buf, id);
 
  pop_n_elems(args);
  push_string(make_shared_binary_string(buf, (size_t)4));
  free(buf);
}

static int coal_low_count_length(struct svalue* val)
{
  struct svalue  sind, sval;
  struct svalue       *func;
  struct keypair       *key;
  int                len, i;
    
  switch(val->type) {
  case T_MAPPING:
    len = 3;
    
    for (i=0; i< val->u.mapping->data->hashsize;i++) {
      for(key=val->u.mapping->data->hash[i];key;key=key->next) {
	sind = key->ind;
	sval = key->val;
	len += coal_low_count_length(&sind) + coal_low_count_length(&sval);
      }
    }
    return len;
    break;
  case T_ARRAY:
    len = 3;
    for (i=0;i<val->u.array->size;i++) {
      len += coal_low_count_length(&val->u.array->item[i]);
    }
    return len;
  case T_STRING:
    return val->u.string->len + 5; // 4 bit length + type
  case T_OBJECT:
    i = find_identifier("serialize_coal", val->u.object->prog);
    if ( i >= 0 ) {
      apply_low(val->u.object, i, 0);

      // MAPPING on top of stack
      if (Pike_sp[-1].type == T_MAPPING ) {
	len = coal_low_count_length(&Pike_sp[-1]);
	pop_stack();
	return len;
      }
      pop_stack();
    }
    return 9;
  case T_FUNCTION: {
    struct pike_string* functionName;
    if (val->subtype == FUNCTION_BUILTIN) 
      return 5;
    struct object *o= val->u.object;

    if(o->prog == pike_trampoline_program) {
      struct pike_trampoline *t=((struct pike_trampoline *)o->storage);
      functionName = (ID_FROM_INT(o->prog, PTR_TO_INT(val->u.ptr))->name); 
    }
    else {
      functionName = (ID_FROM_INT(o->prog, val->subtype)->name); 
    }
    return functionName->len + 13;
  }
  case T_FLOAT:
  case T_INT:
    return 5;
    break;
  }
  return 0;
}

static int coal_get_object_id(struct object* obj) 
{
  int i = find_identifier("get_object_id", obj->prog);
  if ( i >= 0 ) {
    int status = find_identifier("status", obj->prog);
    if ( status >= 0 ) { // status checks!
      apply_low(obj, status, 0);
      if ( Pike_sp[-1].type != T_INT || 
	   Pike_sp[-1].u.integer < 0 ||
	   Pike_sp[-1].u.integer == 3 ) 
      {
	// status is not ok, 3 is deleted
	fprintf(stderr, "STATUS NOT OK!\n");
	pop_stack();
	return 0;
      }
      pop_stack();
    }
    apply_low(obj, i, 0); // get_object_id call
    int oid = Pike_sp[-1].u.integer;
    pop_stack();
    return oid;
  }
  fprintf(stderr, "OBJECT NOT FOUND!\n");
  return 0;
}

static int coal_low_serialize(char* buf, struct svalue* val)
{
  struct svalue sind, sval;
  struct keypair      *key;
  struct svalue      *func;
  int   entries, i, offset;
  switch(val->type) {
  case T_MAPPING:
    entries = 0;
    *buf = CMD_TYPE_MAPPING;
    offset = 3;
    for (i=0;i<val->u.mapping->data->hashsize;i++) {
      for(key=val->u.mapping->data->hash[i];key;key=key->next) {
	sind = key->ind;
	sval = key->val;
	offset += coal_low_serialize(buf+offset, &sind);
	offset += coal_low_serialize(buf+offset, &sval);
	entries++;
      }
    }
    coal_low_compose_short(buf+1, entries);
    return offset;
    break;
  case T_ARRAY:
    *buf = CMD_TYPE_ARRAY;
    coal_low_compose_short(buf+1, val->u.array->size);
    offset = 3;
    for (i=0;i<val->u.array->size;i++) {
      offset += coal_low_serialize(buf+offset, &val->u.array->item[i]);
    }
    return offset;
    break;
  case T_FUNCTION: {
    struct program *p;
    struct pike_string* functionName;

    if (val->subtype == FUNCTION_BUILTIN) {
      *buf = CMD_TYPE_INT;
      coal_low_compose_int(buf+1, 0);
      return 5;
    }

    *buf = CMD_TYPE_FUNCTION;
    struct object *o= val->u.object;

    if(o->prog == pike_trampoline_program) {
      struct pike_trampoline *t=((struct pike_trampoline *)o->storage);
      functionName = (ID_FROM_INT(o->prog, PTR_TO_INT(val->u.ptr))->name); 
    }
    else {
      functionName = (ID_FROM_INT(o->prog, val->subtype)->name); 
    }

    int oid = coal_get_object_id(o);
    coal_low_compose_object(buf+5, oid, 0);

    int len = functionName->len + 8; // 4 byte oid and 4 byte class
    memcpy(buf+13, functionName->str, functionName->len);
    coal_low_compose_int(buf+1, len);
    return len + 5; // type (1 byte) + length (4 byte)
    break;
  }
  case T_STRING:
    *buf = CMD_TYPE_STRING;
    coal_low_compose_int(buf+1, val->u.string->len);
    memcpy(buf+5, val->u.string->str, val->u.string->len);
    return val->u.string->len + 5; // 4 bit length + type
    break;
  case T_FLOAT: {
    float f = val->u.float_number;
    *buf = CMD_TYPE_FLOAT;
    push_constant_text("%4F");
    push_float(f);
    f_sprintf(2);
    memcpy(buf+1, Pike_sp[-1].u.string->str, Pike_sp[-1].u.string->len);
    if ( Pike_sp[-1].u.string->len != 4 )
      fprintf(stderr, "FATAL Error in serialize FLOAT, string length !=4\n");
    pop_stack();
    return 5;
    break;
  }
  case T_OBJECT: { // currently does not check status()
    int i = find_identifier("serialize_coal", val->u.object->prog);
    if ( i>= 0 ) {
      apply_low(val->u.object, i, 0);

      // MAPPING on top of stack
      if (Pike_sp[-1].type == T_MAPPING ) {
	//	struct svalue mapping;
	//assign_svalue_no_free(&mapping, &Pike_sp[-1]);

	offset = coal_low_serialize(buf, &Pike_sp[-1]);
	pop_stack(); // mapping gone

	return offset;
      }
      pop_stack();
    }
    
    i = find_identifier("get_object_id", val->u.object->prog);
    if ( i >= 0 ) {
      int status = find_identifier("status", val->u.object->prog);
      if ( status >= 0 ) { // status checks!
	apply_low(val->u.object, status, 0);
	if ( Pike_sp[-1].type != T_INT || 
	     Pike_sp[-1].u.integer < 0 ||
             Pike_sp[-1].u.integer == 3 ) 
        {
	  // status is not ok, 3 is deleted
	  pop_stack();
	  coal_low_compose_object(buf, 0, 0);
	  return 9;
	}
	pop_stack();
      }

      *buf = CMD_TYPE_OBJECT;
      apply_low(val->u.object, i, 0); // get_object_id call
      int oid = Pike_sp[-1].u.integer;

      coal_low_compose_int(buf+1, oid);
      pop_stack();
      if (oid > 0) {
	i = find_identifier("get_object_class", val->u.object->prog);
	if ( i>= 0 ) {
	  apply_low(val->u.object, i, 0);
	  if (Pike_sp[-1].u.integer == 0 ) {
	    coal_low_compose_object(buf, 0, 0);
	    fprintf(stderr, 
		    "While Serializing Object: class is zero in %d!\n", oid);
	  }
	  else
	    coal_low_compose_int(buf+5, Pike_sp[-1].u.integer);
	  pop_stack();
	} 
	else {
	  fprintf(stderr, "While Serializing Object: get_object_class not in %d found!\n", oid);
	  coal_low_compose_object(buf, 0, 0);
	}
      }
      else {
	// oid is 0 anyway
	coal_low_compose_object(buf, 0, 0);
      }
      return 9;
    } 
    coal_low_compose_object(buf, 0, 0);
    return 9;
    break;
  }
  case T_INT:
    *buf = CMD_TYPE_INT;
    coal_low_compose_int(buf+1, val->u.integer);
    return 5;
    break;
  }
  fprintf(stderr, "COAL: Failed to serialize: Type %d\n", val->type);
  *buf = CMD_TYPE_INT;
  coal_low_compose_int(buf+1, 0);
  return 5;
}

static void f_coal_serialize(INT32 args)
{
  struct svalue *sarr = &Pike_sp[-1];
  int len = coal_low_count_length(sarr);
  char *buf = malloc(sizeof(char)*len+1);

  coal_low_serialize(buf, sarr);
  
  pop_n_elems(args);

  push_string(make_shared_binary_string(buf, (size_t)len));
  free(buf);
}

static int coal_low_unserialize(char* buf, struct svalue* findObject)
{
  int i;

  switch(buf[0]) {
  case CMD_TYPE_INT: {
    push_int(LOW_UNSERIALIZE_INT(buf, 1));
    return 5;
  }
  case CMD_TYPE_FLOAT: {
    float f;
    struct pike_string* str = make_shared_binary_string(buf+1, 4);
    push_string(str);
    push_text("%4F");
    f_sscanf(2);
    if ( Pike_sp[-1].type == T_ARRAY ) {
      if ( Pike_sp[-1].u.array->size >= 1 ) {
	struct svalue* val = &Pike_sp[-1].u.array->item[0];
	if ( val->type == T_FLOAT ) {
	  f = val->u.float_number;
	}
      }
    }
    pop_stack();
    push_float(f);
    return 5;
  }
  case CMD_TYPE_FUNCTION: {
    int len = LOW_UNSERIALIZE_INT(buf, 1);
    struct pike_string* functionStr = make_shared_binary_string(buf+13, len-8);
    int objid = LOW_UNSERIALIZE_INT(buf, 5);
    push_int(objid);
    apply_svalue(findObject,1);
    if (Pike_sp[-1].type == T_OBJECT) {
      int func = find_identifier("find_function", Pike_sp[-1].u.object->prog);
      if (func!=-1) {
	struct object* obj = Pike_sp[-1].u.object;
	add_ref(obj);
	pop_stack(); // object weg
	push_string(functionStr); 
	apply_low(obj, func, 1);
	// functionp auf dem stack
      }
      else {
	pop_stack();
	push_int(0);
      }
    }
    else {
      pop_stack();
      push_int(0);
    }
    return len + 5;
  }
  case CMD_TYPE_OBJECT: {
    int oid = LOW_UNSERIALIZE_INT(buf, 1);
    push_int(oid);
    apply_svalue(findObject, 1);
    return 9; // class bits ignored
  }
  case CMD_TYPE_STRING: {
    int slen = LOW_UNSERIALIZE_INT(buf, 1);
    char *str = malloc(sizeof(char)*slen+1);
    memcpy(str, buf+5, slen);
    push_string(make_shared_binary_string(str, slen));
    free(str);
    return 5 + slen;
  }
  case CMD_TYPE_ARRAY: {
    int off = 3;
    int len = LOW_UNSERIALIZE_SHORT(buf, 1);
    for (i=0; i<len;i++) {
      off += coal_low_unserialize(buf+off, findObject);
    }
    f_aggregate(len);
    return off;
  }
  case CMD_TYPE_MAPPING: {
    int off = 3;
    int len = LOW_UNSERIALIZE_SHORT(buf, 1);
    for (i=0; i<len;i++) {
      // key and value
      off += coal_low_unserialize(buf+off, findObject);
      off += coal_low_unserialize(buf+off, findObject);
    }
    f_aggregate_mapping(len*2);
    return off;
  }
  }
  push_int((int)buf[0]);
  return 0;
}

static void f_coal_uncompose(INT32 args)
{
  char *buf = Pike_sp[-1].u.string->str;
  int slen  = Pike_sp[-1].u.string->len;
  int i, n, len, tid, cmd, id;

  pop_n_elems(args);
  
  if (slen==0) {
    push_int(-1);
    return;
  }
  for (n=0;n<slen-10;n++) {
    if (buf[n] == (char)BEGINMASK)
      break;
  }
  if (n>=slen-18) {
    push_int(-1);
    return;
  }
  len = LOW_UNSERIALIZE_INT(buf,n+1);

  if (len+n > slen || len < 12) {
    push_int(0);
    return;
  }
  tid = LOW_UNSERIALIZE_INT(buf,n+5);
  cmd = buf[n+9];
  id = LOW_UNSERIALIZE_INT(buf,n+10);

  push_int(tid);
  push_int(cmd);
  push_int(id);
  push_int(n);
  push_int(len);
  f_aggregate(5);
}

static void f_coal_unserialize(INT32 args)
{
  char *buf = Pike_sp[-3].u.string->str;
  int slen  = Pike_sp[-3].u.string->len;
  int offset = Pike_sp[-2].u.integer;
  struct svalue func;
  assign_svalue_no_free(&func, &Pike_sp[-1]);
  pop_n_elems(args);
  coal_low_unserialize(buf+offset, &func);  
  free_svalue(&func);
}

PIKE_MODULE_INIT
{
  ADD_FUNCTION("coal_compose", f_coal_compose, tFunc(tInt tInt tInt tInt, tString), 0);
  ADD_FUNCTION("coal_compose_int", f_compose_int, tFunc(tInt, tString), 0);
  ADD_FUNCTION("coal_serialize", f_coal_serialize, tFunc(tArray, tString), 0);
  ADD_FUNCTION("coal_uncompose", f_coal_uncompose, tFunc(tString, tOr(tArray,tInt)), 0);
  ADD_FUNCTION("coal_unserialize", f_coal_unserialize, tFunc(tString tInt tFunc(tInt,tObj), tArray), 0);
}

PIKE_MODULE_EXIT
{
}
