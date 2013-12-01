/*
 * debug.h
 *
 * A printf-like function to print debugging messages.
 * Output goes to stderr.
 *
 * By default, the debugging is enabled. To disable, compile with -DNDEBUG
 */

#ifndef DEBUG_H
#define DEBUG_H


/*
 * DEBUG()
 *
 * Prints debugging messages to stderr,
 * unless NDEBUG is defined at compile time.
 */
void DEBUG(char *fmt, ...);


#endif
