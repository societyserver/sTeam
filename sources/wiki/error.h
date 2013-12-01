/*
 * error.h
 *
 * Error printing functions.
 *
 */


#ifndef ERROR_H
#define ERROR_H


/*
 * error()
 *
 * Print a warning message to stderr, but don't quit
 * Prints a \n at the end of the message.
 */
void error(char *fmt, ...);



/*
 * fatal_error()
 *
 * Print a message to stderr and exit(EXIT_FAILURE)
 * Prints a \n at the end of the message.
 */
void fatal_error(char *fmt, ...);


#endif
