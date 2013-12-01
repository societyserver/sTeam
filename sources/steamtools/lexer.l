%{

#include "steamtools.h"
#include "yyexternals.h"

extern char* yyinbuffer;
#define YY_INPUT(buf, result, max_size)\
{\
int n, len;\
len = strlen(yyinbuffer);\
result = len < max_size ? len : max_size;\
for ( n = 0; n < result; n++ )\
    buf[n] = yyinbuffer[n];\
yyinbuffer = &yyinbuffer[result];\
}
int          _strlen;
char*       _straddr;

%}

STRING      [\"]([^\"])*[\"]
FNAME       ([a-zA-Z0-9_])+
MAPPING     "["(.)*"]"
ARRAY       "{"(.)*"}"
BEGINMAP    "["
ENDMAP      "]"
BEGINARR    "{"
ENDARR      "}"
EMPTYMAP    ":,"
INTEGER     ("-")*[0-9]+
FLOAT       ({INTEGER}"."[0-9]+)
OBJECT      "%"{INTEGER}
FUNCTION    "$"{FNAME}" "{INTEGER}

%option noyywrap
%option reentrant

%%
<INITIAL>{STRING} { yyextra->stack[yyextra->depth]++; low_unserialize_string(yytext, yyleng);  }
<INITIAL>{INTEGER} { yyextra->stack[yyextra->depth]++; low_unserialize_integer(yytext); }
<INITIAL>{FLOAT} { yyextra->stack[yyextra->depth]++;low_unserialize_float(yytext); }
<INITIAL>{OBJECT} { yyextra->stack[yyextra->depth]++; low_unserialize_object(yytext); } 
<INITIAL>{FUNCTION} { yyextra->stack[yyextra->depth]++; low_unserialize_function(yytext); } 
<INITIAL>{EMPTYMAP} { yyextra->stack[yyextra->depth]++; low_unserialize_nothing(); }
<INITIAL>{BEGINMAP} {yyextra->depth++; yyextra->stack[yyextra->depth]=0; }
<INITIAL>{ENDMAP} { low_unserialize_mapping(yyextra->stack[yyextra->depth]); yyextra->stack[yyextra->depth]=0; yyextra->depth--; yyextra->stack[yyextra->depth]++; }
<INITIAL>{BEGINARR} {yyextra->depth++; yyextra->stack[yyextra->depth]=0; }
<INITIAL>{ENDARR} {low_unserialize_array(yyextra->stack[yyextra->depth]); yyextra->stack[yyextra->depth]=0; yyextra->depth--; yyextra->stack[yyextra->depth]++; }
<INITIAL>. {}
<<EOF>>  { int i; for (i=0;i<MAXSTACK;i++)yyextra->stack[i]=0;yyextra->depth=0;yyterminate();}
