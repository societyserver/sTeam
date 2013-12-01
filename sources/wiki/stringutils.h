/*
 * stringutils.h
 *
 * functions to manipulate cstrings
 */

#ifndef STRINGUTILS_H
#define STRINGUTILS_H


#include <string.h>
#include <stdlib.h>
#include "boolean.h"

char *strip_surrounding_chars(char *string, int num_chars);
char *new_cstring(int len);
char *duplicate_cstring(char *string);
boolean strings_equal(char *s1, char *s2);


#endif
