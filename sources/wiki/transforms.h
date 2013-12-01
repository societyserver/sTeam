/*
 * transforms.h
 *
 * functions to turn wikitext into HTML
 */

#ifndef DEBUG_H
#define DEBUG_H


#include "boolean.h"

void math(char* formula);
void barelink(char *link);
void blank_line(void);
void bold(void);
void heading(int new_level, boolean start);
void hr(void);
void hyperlink(char *link);
void image(char *link);
void init_lexer(void);
void italic(void);
void make_list(char *list);
void paragraph(char *text);
void plaintext(char *text);
void head(char *text);
void preformat(void);
void wikilink(char *link);
void tag(char *tagstr);

void linkInternal(char *link);
void annotationInternal(char *ann);

typedef enum { blank, para, list, pre, done } status_t;


/* Define a lexer object, available or functions in this file */
typedef struct {
    status_t status;
} lexer_t;

typedef enum { start, end, next } list_t;

void prepare_status(status_t new);

#endif
