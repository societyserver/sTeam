/*
* lexer.l
*
* lexical analyzer for wikicode
*/

%{

#include "boolean.h"
#include "debug.h"
#include "error.h"
#include "globals.h"
#include "transforms.h"
#include "yyexternals.h"

extern char* yyinbuffer;
char* mathBuffer = NULL;
int mathLen = 0;
int table_state = 0;

#define YY_INPUT(buf, result, max_size)\
{\
int n, len;\
len = strlen(yyinbuffer);\
result = len < max_size ? len : max_size;\
for ( n = 0; n < result; n++ )\
    buf[n] = yyinbuffer[n];\
yyinbuffer = &yyinbuffer[result];\
}

#include "output.h"

#define MAX_BUFFERS 10

YY_BUFFER_STATE wikiBuffers[MAX_BUFFERS];
int currentBuffer = 0;

void wiki_scan_buffer(char* buf)
{
YY_BUFFER_STATE pbs = YY_CURRENT_BUFFER;
YY_BUFFER_STATE bs = yy_scan_string(buf);
yy_switch_to_buffer(bs);
yylex();
yy_switch_to_buffer(pbs);
yy_delete_buffer(bs);

}


%}


ALPHANUM    ([a-z]|[A-Z]|[0-9])
LINK_TEXT   [^\]]+
PIKE_CODE   [^\@]+
EMBED_TEXT  [^\}\n]+
SPACE       (\t|\n|" ")
NOT_SPECIAL [^\n\[=\*#\-\{@]
BLANKLINE   ^({SPACE}*)
BLANK       \r\n\r\n
UNQUOTE     [^\"]
TABS        (\t+)
ENDDEF      [^:]+
EOL         [^\n]+
TTYPE       ("box"|"above"|"below"|"hsides"|"vsides"|"lhs"|"rhs")
TRULES      ("none"|"rows"|"cols"|"groups"|"all")
ATTR        ({SPACE}*{ALPHANUM}+{SPACE}*"="{SPACE}*[\"']{UNQUOTE}+[\"']{SPACE}*)
TATTR       {ATTR}+

HYPERLINK   ("[http://"{LINK_TEXT}"]")|("[mailto:"{LINK_TEXT}"]")|("[local://"{LINK_TEXT}"]")
HYPERLINKS  "[https://"{LINK_TEXT}"]"
BARELINK    (((("https")|("http")|("ftp"))"://")|("mailto:"))[^[:blank:]\n]+
IMAGE       "[["[iI]"mage:"{LINK_TEXT}"]]"
WIKILINK    "[["{LINK_TEXT}"]]"{ALPHANUM}*
ANNOTATION  "["{LINK_TEXT}"["{LINK_TEXT}"]]"
EMBED       "{"[^\|\<]{EMBED_TEXT}"}"
HEADING     "=".+"="

WIKIPIKE    "@@"{PIKE_CODE}"@@"

BOLD        '''
EMPHS       __
ITALIC      ''
LBR         \\\\
H1_START    ^=
H2_START    ^==
H3_START    ^===
H4_START    ^====
H1          =
H2          ==
H3          ===
H4          ====
BULLET      ^\*
NUMBER      ^#
INDENT      ^\:
HR          ^"----"-*
LIST        ^[\*#:]+
PRE         ^" "/[^\n]
DEFINITION  ^(\t+){ENDDEF}:\t
MATH        ("<math>"(.)+"</math>")
BEGINMATH   "<math>"
ENDMATH     "</math>"
TAG         ("<"([^>])+">")

%option noyywrap
%x table
%x td
%x caption
%x html
%x th
%x formula
%x formulatable
%x quote
%x list

%%
<INITIAL>"{|"{TATTR}* { BEGIN(table); make_table(yytext); table_state=1; }
<table>^\|"-"+{TATTR}* {  make_tr(yytext); }
<table>\|{TATTR}\| { output("<td %s>", yytext); BEGIN(td); }
<table>\|/[^\|\n\}\-\\+] { output("<td>"); BEGIN(td); }
<table>\|\+ { BEGIN(caption); }
<table>!   { BEGIN(th); output("<th>"); }
<th>[\n\|!] { BEGIN(table); output("</th>"); }
<th>. { output(yytext); }
<caption>[^\n\|]* { output("<caption>%s</caption>", yytext); BEGIN(table); }
<td>[\|\n] { output("</td>\n"); BEGIN(table); }
<table>^"{|"{TATTR}* { BEGIN(table); output("<td>\n"); make_table(yytext); table_state++; }
<table,td>\|\}   { table_state--; if ( table_state == 0 ) BEGIN(INITIAL); else { BEGIN(table); output("</td>\n");} output("</tr></table>\n"); }
<quote>\" { BEGIN(INITIAL); preformat(); }
<quote>. { plaintext(yytext); }
<*><<EOF>> { BEGIN(INITIAL); yyterminate(); }
<INITIAL,td,list>{LIST}          { make_list(yytext); make_listitem(1); BEGIN(list); }
<list>^\n { make_listitem(3); BEGIN(INITIAL); }
<list>^\r\n { make_listitem(3); BEGIN(INITIAL); }
<INITIAL,table,td,caption,th,list>{BOLD}          { bold();            }
<INITIAL,table,td,caption,th,list>{EMPHS}         { bold();            }
<INITIAL,table,td,caption,th,list>{ITALIC}        { italic();          }
<INITIAL,quote,list>{BEGINMATH}           { BEGIN(formula); }
<td>{BEGINMATH}           { BEGIN(formulatable); }
<formula>{ENDMATH}                 { math(mathBuffer); free(mathBuffer); mathLen = 0; BEGIN(INITIAL);}
<formula,formulatable>.                         { if ( mathLen == 0 ) { mathLen = 100000; mathBuffer = malloc(mathLen+1); mathBuffer[0] = '\0'; } if ( strlen(mathBuffer) < mathLen-1 ) strcat(mathBuffer, yytext); } 
<formulatable>{ENDMATH}                 { math(mathBuffer); free(mathBuffer); mathLen = 0; BEGIN(td);}
<INITIAL,td,quote,list>{TAG}           { tag(yytext);       }
<INITIAL>{PRE}           { preformat(yytext); }
<INITIAL>^{HEADING}       { head(yytext); }
<INITIAL>{HR}            { hr();              }
<INITIAL,table,td,list>{BARELINK}      { barelink(yytext);  }
<INITIAL,table,td,list>{IMAGE}         { image(yytext);     }
<INITIAL,table,td,list>{WIKILINK}   { linkInternal(yytext);  }
<INITIAL,table,td,list>{ANNOTATION}    { annotationInternal(yytext); }
<INITIAL,table,td,list>{HYPERLINK}     { hyperlink(yytext); }
<INITIAL,table,td,list>{HYPERLINKS}    { hyperlink(yytext); }
<INITIAL,table,td,list>{DEFINITION}    { make_def(yytext); }
<INITIAL,table,td,list>{EMBED}         { embed(yytext); }
<INITIAL,table,td,list>{WIKIPIKE}      { pi_pike(yytext); }
<INITIAL,td,th,caption>^\n             { blank_line();      }
<INITIAL,td,th,caption>{BLANKLINE}     { blank_line();      }
<INITIAL,td,th,caption>{BLANK}         { blank_line();      }
<INITIAL,td,th,caption>{LBR}           { force_br();        }
<INITIAL>^{NOT_SPECIAL}  { paragraph(yytext); }
<INITIAL,td,list>{SPACE}         { plaintext(yytext); }
<INITIAL,td,list>.               { plaintext(yytext); }
