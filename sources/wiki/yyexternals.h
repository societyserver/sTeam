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


/*
 * Variables used by the scanner
 *
 * yyin : file scanner reads from
 * yytext : text of the token the scanner just read
 * scanner_line_count : helps scanner keep track of line numbers
 */
extern FILE *yyin;
extern char *yytext;

#define yylex wiki_yylex

/* 
 * Function prototypes:
 * yylex : calls to the lexer
 */
int wiki_yylex( void );
void wiki_scan_buffer(char* buf);
 
#endif







