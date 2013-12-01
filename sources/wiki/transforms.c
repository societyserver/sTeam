/*
 * transforms.c
 *
 * functions called by the lexer
 * to transform wikicode into HTML
 */

#include <string.h>
#include <stdlib.h>

#include "transforms.h"
#include "boolean.h"
#include "debug.h"
#include "globals.h"
#include "output.h"
#include "stringutils.h"



static lexer_t Lexer;
static char *current_list = NULL;
static int current_len = 0;

char *disambiguate(char *link_text);
void prepare_status(status_t new);
void close_tags(char *tags);
void list_tag(char c, list_t type);


/* A signal sent to make_list() */
#define CLOSE_TAGS "close tags"



void annotation(char* ann_text)
{
  char *full_text;
  char*      text;
  char*       ann;
  char*   end_ann;

  full_text = duplicate_cstring(ann_text);
  full_text = strip_surrounding_chars(full_text, 1);
  text = strstr(full_text, "[");
  end_ann = text;
  end_ann[0] = '\0';
  text = &text[1];
  text[strlen(text)-1] = '\0';
  ann = strstr(full_text, "@");
  output("<div id=\"%s\" class=\"annotation\">%s</div>", &ann[1], text);
  free(full_text);
}


/*
 * wikilinkwords()
 *
 * turns a wikilink into an HTML link.
 * Assumes string starts with capitalize and are joined Words, like WikiWiki
 *
 * Split the strings at the |
 * link_text gets the stuff to the left 
 * alt_text gets the stuff to the right
 */ 
void wikilinkwords(char *wiki_text)
{
    output( "<a class=\"internal\" href=\"%s.wiki\">%s</a>&nbsp;",
	    wiki_text, wiki_text);
}

/*
 * disambiguate()
 *
 * disambiguates a wikilink: placeholder for now
 */ 
char *disambiguate(char *link_text)
{
    DEBUG("disambiguate: yep");
    return link_text;
}

/*
 * heading()
 *
 * number of heading must be specified.
 *
 * If the heading is at the beginning of the line:
 *     close the old one (if it's open)
 *     and start the new one.
 *
 * If the heading is not at the beginning:
 *     close the matching one if it's open 
 *     print the leftover = signs
 *
 */
void heading(int new_level, boolean start)
{
    static int level = 0;
    int i;

    if (start) {
        if (level != 0) {
            output( "</h%d>\n", level);
        }
        output( "<h%d>", new_level);
        level = new_level;
    }
    else if (level < new_level) {
      for (i=0; i<new_level; ++i) {
	output("=");
      }
    }
    else {
      output( "</h%d>\n", level);
      for (i=0; i<level-new_level; ++i) {
	output("=");
      }
      level = 0;
    }
}




/*
 * paragraph()
 *
 * start a new paragraph if necessary, then print what we saw
 */
void paragraph(char *stuff)
{
    if (Lexer.status == para) {
        plaintext(stuff);
    }
    else if ( Lexer.status == list ) {
        output("<br/>");
        plaintext(stuff);
    }
    else {
	prepare_status(para);
        output( "<p>");
        Lexer.status = para;
        plaintext(stuff);
    }
}

void make_def(char* stuff)
{
  prepare_status(blank);
  output("<dt>");
  output(stuff);
  output("<dd>");
}

void force_br(void) 
{
  output("<br />");
}

/*
 * preformat()
 *
 * start a preformatted section
 * called when a line starts with a space
 */
void preformat(void)
{
    prepare_status(pre);

    if (Lexer.status != pre) {
        output("<pre>");
        Lexer.status = pre;
    }
}




/*
 * plaintext()
 *
 * dump the given string to the output file.
 */
void plaintext(char *text)
{
    output( "%s", text);
}




/*
 * hyperlink()
 *
 * turn [http://foo fubar] --> <a href="http://foo">fubar</a>
 */
void __hyperlink(char *link)
{
    char *link_text;
    char *alt_text;

    link_text = strip_surrounding_chars(link, 1);
    alt_text = strchr(link_text, ' ');
    if (alt_text) {
        *alt_text = '\0';
        alt_text = &alt_text[1];
        if (alt_text == '\0') {
            alt_text = "\"*\"";
        }
    }
    else {
        alt_text = link_text;
    }

    output( "<a class=\"extlink\" href=\"%s\">%s</a>", link_text, alt_text);

    free(link_text);
}

 


/*
 * image()
 *
 * turn [[image:foo.jpg|few]] --> <img src="foo.jpg" alt="few">
 */
void __image(char *link)
{
    char *link_text;
    char *alt_text;

    link_text = strip_surrounding_chars(link, 2);

    alt_text = strchr(link_text, '|');
    if (alt_text) {
        *alt_text = '\0';
        alt_text = &alt_text[1];
        if (alt_text == '\0') {
            alt_text = "\"*";
        }
    }
    else {
        alt_text = "image";
    }

    output( "<img src=\"%s/%s\" alt=\"[ %s ]\">",
            Global.image_url, &link_text[6], alt_text);
    free(link_text);
}


    

/*
 * hr()
 *
 * turn ----(...) --> <hr>
 */
void hr (void)
{
    prepare_status(blank);
    Lexer.status = blank;
    output( "\n<hr />\n");
}




/*
 * init_lexer()
 *
 * Set up all the variables to their initial values.
 * Currently it's only the status variable.
 */
void init_lexer(void)
{
    Lexer.status = blank;
    current_list = NULL;
    current_len = 0;
}




/*
 * prepare_status()
 *
 * print some closing tags, depending on the current and new status
 */
void prepare_status(status_t new)
{
    status_t current = Lexer.status;

    if (current != new) {
        switch (current)
        {
            case para:
                output( "</p>\n");
                break; 

            case pre:
                output( "</pre>\n");
                break; 

            case list:
                make_list(CLOSE_TAGS);
                break;

            case blank:
                break;

            default:
                error("prepare_status: unknown status: %d\n", Lexer.status);
                break;
        }
    }
}




/*
 * blank_line()
 *
 * saw a blank line, set the status
 */
void blank_line(void)
{
  prepare_status(blank);
  Lexer.status = blank;
}




/*
 * make_list()
 *
 * deal with list items
 * 
 * called when the lexer sees a * # or :
 * at the beginning of a line
 *
 * can handle nested/mixed lists
 */
void make_list(char *new)
{

    char *new_list;
    int new_len;

    int differ;
    int i;

    /* prepare_status sends this: close all open tags and bail */
    if (strings_equal(new, CLOSE_TAGS)) {
        close_tags(current_list);
        current_list = NULL;
        current_len = 0;
        return;
    }

    new_list = duplicate_cstring(new);
    new_len = strlen(new_list);

//    fprintf(stderr, "New list (%d) of %s (current=%s, %d)\n", new_len, new, current_list, current_len);
    
    prepare_status(list);
    Lexer.status = list;

    /* Find out where they differ */
    differ=0;
    while (differ < new_len
           && differ < current_len
           && current_list[differ] == new_list[differ])
    {
        ++differ;
    }
    /* If they are the same, make another list item */
    if (new_len == current_len  &&  differ == current_len) {
        list_tag(current_list[current_len-1], next);
    }
    else
    {
        /* Close up the different tags */
        if (differ < current_len  &&  current_list) {
            close_tags(&current_list[differ]);
        }

        if (new_len < current_len) {
            list_tag(new_list[new_len-1], next);
        }

        /* Start new lists */
        while (differ < new_len) {
            list_tag(new_list[differ], start);
            ++differ;
        }
    }

    free(current_list);
    current_list = new_list;
    current_len = new_len;
}

void make_listitem(int start)
{
    char *list_item;
    if ( current_list == NULL ) {
	return;
    }
    char c = current_list[current_len-1];

    list_item = (c == ':') ? "dd" : "li";
    if ( start == 1 )
	output("<%s>", list_item);
#if 0
    else if ( start == 2 )
	output("</%s>", list_item);
#endif
    else if ( start == 3 ) {
	output("</%s>", list_item);
	prepare_status(blank);
    }
}


/*
 * list_tag()
 *
 * take care of printing starting, ending, and list item tags
 * given a char one of * # or : print the corresponding tag
 * type is one of start, end, or next
 */
void list_tag(char c, list_t type)
{
    char *list_type;
    char *list_item;

    list_item = (c == ':') ? "dd" : "li";

    switch(c) {
        case ':': list_type = "dl"; break;
        case '*': list_type = "ul"; break;
        case '#': list_type = "ol"; break;
        default:
            fatal_error("list_tag: bad list char: %c", c);
            break;
    }

    switch (type) {
        case start: 
            output("<%s>", list_type);
            break;
    
        case end: 
            output("</%s>", list_item);
            output("</%s>", list_type);
            break;
    
        case next:
            output("</%s>", list_item);
            break;
    
        default:
            fatal_error("list_tag: bad list type: %d", type);
            break;
    }
}


void make_table(char *table)
{
    char* tdef;
    int   slen;
    char*  ptr;

    if ( strings_equal(table, "{|") ) {
	output("<table><tr>\n");
	return;
    }
    tdef = &table[2];
    output("<table %s><tr>\n", tdef); 
}

void make_tr(char *table)
{
    char*    tdef;
    int   i, slen;
    char*     ptr;
    
    if ( strings_equal(table, "|-") ) {
	output("</tr><tr>\n");
	return;
    }
    tdef = strstr(table, "=");
    if ( tdef == NULL ) {
	output("</tr><tr>\n");
	return;
    }
    slen = strlen(table);
    i = 1;
    while ( i < slen && table[i] == '-' )
	i++;
    
    if ( i >= slen - 1 )
	i = 0;
    output("</tr><tr %s>\n", &table[i]); 
}

/*
 * close_tags()
 *
 * Given a string of tag chars (* # or :)
 * Close up the different tags in reverse order
 */
void close_tags(char *tags)
{
    int tag;
    if ( tags == NULL )
	return;
    int len = strlen(tags);

    for (tag = len-1; tag >= 0; --tag) {
        list_tag(tags[tag], end);
    }
}

void eof()
{
  prepare_status(blank);
}



/*
 * barelink()
 *
 * turn a bare url into a hyperlink
 */
void __barelink(char *link)
{
    output("<a class=\"external\" href=\"%s\">%s</a>", link, link);
}

void table_cells(char* td)
{
    output("<td>");
    output(td);
    output("</td>");
}
