/*
 * error.c
 *
 * Error printing functions.
 */



/*
 * Included headers:
 *
 * error: interface to the rest of the world
 * globals: Program_Name
 * stdio: fprintf(), fputc(), stderr
 * stdlib: EXIT_FAILURE
 * stdarg: va_list, va_start(), va_end(), vfprintf()
 */
#include "error.h"
#include "globals.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>




/*
 * error()
 *
 * Print a warning message to stderr, but don't quit
 */
void error(char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    fprintf (stderr, "%s: ", Global.program_name);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);
    
    va_end(args);
}




/*
 * fatal_error()
 *
 * Print a message to stderr and exit(EXIT_FAILURE)
 */
void fatal_error(char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    fprintf (stderr, "%s: FATAL ERROR: ", Global.program_name);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);

    va_end(args);

    exit(EXIT_FAILURE);
}
