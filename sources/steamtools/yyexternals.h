/*
 * yyexternals.h
 *
 * external functions and variables needed by the lexer
 */

#ifndef YYEXTERNALS_H
#define YYEXTERNALS_H


/* yyin is an external FILE* */
#include <stdio.h>

/* Scanner end-of-file marker */
#define YYEOF 0
#define MAXSTACK 100

struct stackType {
  int depth;
  int stack[MAXSTACK];
  void* objectFunc;
} stack_type;

#define YY_EXTRA_TYPE struct stackType*

/*
 * Variables used by the scanner
 *
 * yyin : file scanner reads from
 * yytext : text of the token the scanner just read
 * scanner_line_count : helps scanner keep track of line numbers
 */
#define yylex serialize_yylex
int serialize_yylex(void*);

#endif
