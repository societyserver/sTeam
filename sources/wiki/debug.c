/*
 * debug.c
 *
 * Debugging message printer.
 *
 * Prints if NDEBUG is NOT defined at compile time.
 *
 */

#ifndef NDEBUG

/* 
 * Included headers:
 *
 * globals: Program_Name
 * stdio: fprintf(), stderr, fputc()
 * stdarg: va_start(), va_end(), va_list, vfprintf()
 */
#include "globals.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>




/*
 * DEBUG()
 *
 * Print a debugging message to stderr
 */
void DEBUG(char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    fputs("<!--", Global.output_file);
    vfprintf(Global.output_file, fmt, args);
    fputs("-->\n", Global.output_file);
    
    va_end(args);
}


#else    /* If NDEBUG was defined at compile time */


/*
 * DEBUG()
 *
 * Don't do anything. Hopefully the compiler is smart enough
 * to optimize away the calls to this function.
 */
void DEBUG(char *fmt, ...)
{
}


#endif
