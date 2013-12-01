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
 * $Id: doc.c,v 1.1 2008/03/31 13:39:57 exodusd Exp $
 */

#include "mem.c"
#include <mapping.h>

#define MODE_RETURNTYPE 2
#define MODE_COMMENT    1
#define MODE_NOCOMMENT  0
#define MODE_NOTHING    -1

struct ParameterDesc {
    char*                 description;
    struct ParameterDesc*        next;
};

struct Parameters {
    char*                 description;
    struct ParameterDesc*      params;
};

/**
 *
 *  
 * @param 
 * @return 
 * @author Thomas Bopp (astra@upb.de) 
 * @see 
 */
void 
parse_header(char* fname, char* synopsis, char* keywords, 
		   char* header, int len, struct svalue* callback)
{
    int      begin,  i, j, args;
    char*           description;
    struct mapping*     doc_map;
    struct array*           arr;
    char*                params;
    char*                  name;
    char*                 value;
    char*               context;
    struct svalue skey, sval, sarr;
    struct svalue*          res;


    description = _MALLOC(len);
    description[0] = '\0';
    /* first parse the function description */
    i = j = 0;
    while ( i < len && header[i] != '@' ) {
	if ( header[i] != '*' )
	    description[j++] = header[i];
	else 
	    description[j++] = ' ';
	i++;
    }
    while ( j > 0 && description[j] != '\n' ) j--;
    description[j] = '\0';

    push_svalue(callback);
    push_text(fname);
    push_text(synopsis);
    push_text(keywords);
    push_text(description);    

    begin = i;

    args = 0;
    doc_map = allocate_mapping(10);
    name = NULL;
    i-=2;
    while ( i < len ) {
	int nl, l;
	
	if ( strncmp(&header[i], " @", 2) == 0 || 
	     strncmp(&header[i], "\t@",2) == 0 ) 
	{
	    i+=1;
	    nl = 0;
	    j = i+1;
	    while ( j < len && 
		    ((header[j] >= 'a' && header[j] <= 'z') ||
		     (header[j] >= 'A' && header[j] <= 'Z') ) )
		j++;
	    name = create_string(name, &header[i+1], (j-i));
	    skey.u.string = make_shared_string(name);
	    skey.type = T_STRING;
	    i = j;
	    while ( i < len && (header[i] != '@' || !nl) && 
		    strncmp(&header[i], "*/",2) != 0 )  
	    {
		if ( header[i] == '\n' ) nl = 1;
		if ( header[i] == '*' ) header[i] = ' ';
		i++;
	    }
	    args++;
	    res = simple_mapping_string_lookup(doc_map, name);
	    value = create_string_strip_spaces(NULL, &header[j], i-j);
	    //fprintf(stderr, "Found argument to function %s,%s:%s\n",
	    //fname, name, value);
	    if ( res != NULL ) {
		
		if ( res->type == T_ARRAY ) {
		    arr = res->u.array;
		    arr = resize_array(arr, arr->size+1);
		    arr = array_insert(arr, &sval, arr->size-1);
		}
		else {
		    arr = allocate_array(2);
		    params = malloc(res->u.string->len+1);
		    strncpy(params,
			    res->u.string->str, 
			    res->u.string->len);
		    params[res->u.string->len] = '\0';
		    sval.u.string = make_shared_string(params);
		    arr = array_insert(arr, &sval, 0);
		    free_string(sval.u.string);

		    sval.u.string = make_shared_string(value);
		    sval.type = T_STRING;
		    arr = array_insert(arr, &sval, 1);
		    free_string(sval.u.string);
		}
		sarr.u.array = arr;
		sarr.type = T_ARRAY;
		mapping_insert(doc_map, &skey, &sarr);
	    }
	    else {
		sval.u.string = make_shared_string(value);
		sval.type = T_STRING;
		mapping_insert(doc_map, &skey, &sval);
		free_string(sval.u.string);
	    }
	    free_string(skey.u.string);
	    i -= 4;
	}
	i++;
    }
    push_mapping(doc_map);
    f_call_function(6);
    pop_stack();
    _FREE(description);
    _FREE(fname);
    _FREE(synopsis);
    _FREE(keywords);

}

void
parse_doc(char* source, struct svalue* callback)
{
    int         begin, i, len, end;
    int        mode = MODE_NOTHING;
    int                    f_begin;
    char*                   f_name;
    char*               f_keywords;
    char*               f_synopsis;
    char* keyw[11] ={"void","array","string","object","float","int","mixed","mapping", "bool","function","program"};

    len = strlen(source);
    i   = 0;
    
    while ( i < len ) {
	if ( mode == MODE_NOCOMMENT || mode == MODE_NOTHING ) {
	    if ( strncmp(&source[i], "/**", 3) == 0 && 
		 strncmp(&source[i], "/**/", 4) != 0 ) 
	    {
		mode = MODE_COMMENT;
		begin = i+4;
	    }
	}
	else if ( mode == MODE_COMMENT ) 
	{
	    if ( strncmp(&source[i], "*/", 2) == 0 ) {
		int brackets, keyword_start;

		end  = f_begin = i;

		while ( i < len && mode != MODE_RETURNTYPE ) {
		    int j;

		    for ( j = 0; j < 11; j++ ) {
			if ( strncmp(&source[i], keyw[j], strlen(keyw[j]))==0 )
			    mode = MODE_RETURNTYPE;
		    }
		    i++;
		}
		/* goto first space after function types and return value */
		brackets = 0;
		while ( i < len && (brackets != 0 || 
			(source[i] != ' ' && source[i] != '\n')) ) {
		    if ( source[i] == '(' ) brackets++;
		    else if ( source[i] == ')' ) brackets--;
		    i++;
		}
		while ( i < len && source[i] != '(' ) 
		{
		    if ( !( (source[i] >= 'a' && source[i] <='z') ||
			    (source[i] >= 'A' && source[i] <= 'Z') ||
			    (source[i] == '_')) )
			f_begin = i;
		    i++;
		}
		f_keywords = (char*)create_string(NULL, &source[end+3], 
							f_begin - end - 1);
		f_name = (char*)
		    create_string(NULL, &source[f_begin+1], i-f_begin);

                if ( strncmp(f_name, "ASSERTINFO", 10) == 0 ) {
		    fprintf(stderr,
			    "Error, assertinfo function found ?!\nContext:%s",
			    &source[begin]);
		}
		else if ( f_name[0] == '/' || f_name[1] == '/' ) {
                    fprintf(stderr,
			    "error: Wrong beginning of function?!\nContext:%s",
			    &source[begin]);
		}
		
		brackets++;
		i++;
                while ( i < len && brackets != 0 ) {
		    if ( source[i] == '(' ) brackets++;
                    if ( source[i] == ')' ) brackets--;
                    i++;
		}
		f_synopsis = (char*) create_string(NULL, &source[f_begin+1],
                                                   i-f_begin);
		parse_header(f_name, f_synopsis, f_keywords,
				      &source[begin], end-begin, callback);
		mode = MODE_NOCOMMENT;
	    }
	}
	i++;
    }
}


void
f_parse_functions(INT32 args)
{
    struct svalue* f;
    char*        buf;
    
    get_all_args("parse_functions", args, "%s%*", &buf, &f);
    parse_doc(buf, f);
    pop_n_elems(args);
}

void
pike_module_init()
{
    memory = NULL;
    add_function("parse_functions", f_parse_functions,
		 "function(string,function:void)", 0);
}

void
pike_module_exit()
{
}
