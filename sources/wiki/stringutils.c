/*
 * stringutils.c
 *
 * functions to manipulate cstrings
 */

#include <string.h>
#include <stdlib.h>

#include "stringutils.h"
#include "debug.h"




/*
 * strings_equal()
 *
 * Return TRUE if strings are equal, FALSE if not
 */
boolean strings_equal(char *s1, char *s2)
{
    return (strcmp(s1,s2)) ? FALSE : TRUE; 
}




/*
 * strip_surrounding_chars()
 *
 * remove chars from the ends of a string.
 *
 * num_chars is the number of chars to be removed from ONE END
 * of the string. The same number will be removed from the other end.
 *
 * Returns a pointer to a new, shorter string.
 */
char *strip_surrounding_chars(char *string, int num_chars)
{
    char *new_string;
    int new_string_len;

    new_string_len = strlen(string) - 2*num_chars;

    if (new_string_len > 0  &&  string != NULL)
    {
        new_string = calloc(new_string_len +1, sizeof (char *));
        if (new_string == NULL) {
            fatal_error("strip_surrounding_chars: failed to allocate memory for new string");
        }
        strncpy(new_string, &string[num_chars], new_string_len);
    }
    else {
        fatal_error("strip_surrounding_chars: bad string: %s, end chars to remove: %d",
                string, num_chars);
    }

    return new_string;
}




/*
 * new_cstring
 *
 * allocate a char * array of len bytes
 * and return a pointer
 */
char *new_cstring(int len)
{
    char *string;
    
    if (len > 0) {
        string = malloc(sizeof (char*) * len);
        if (string == NULL) {
            fatal_error("new_cstring: failed to allocate %d chars", len);
        }
    }
    else {
        string = NULL;
    }

    return string;
}




/*
 * duplicate_cstring()
 *
 * allocate memory for a cstring the size of string
 * then copy the string and return a pointer
 */
char *duplicate_cstring(char *string)
{
    char *new;

    new = calloc(strlen(string) +1, sizeof (char *));
    if (new == NULL) {
        fatal_error("duplicate_cstring: failed to duplicate %s", string);
    }
    strncpy(new, string, strlen(string));

    return new;
}
