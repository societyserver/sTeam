/*
 * wiki.grammar
 *
 * This work is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This work is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software 
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
 * USA
 *
 * As a special exception, the copyright holders of this library give
 * you permission to link this library with independent modules to
 * produce an executable, regardless of the license terms of these
 * independent modules, and to copy and distribute the resulting
 * executable under terms of your choice, provided that you also meet,
 * for each linked independent module, the terms and conditions of the
 * license of that module. An independent module is a module which is
 * not derived from or based on this library. If you modify this
 * library, you may extend this exception to your version of the
 * library, but you are not obligated to do so. If you do not wish to
 * do so, delete this exception statement from your version.
 *
 * Copyright (c) 2004 Chris Holman. All rights reserved.
 */

%header%
GRAMMARTYPE = "LL"

DESCRIPTION = "A grammar for Wiki page content."

AUTHOR      = "Chris Holman <chris dot holman at awltux dot com>"
VERSION     = "1.0"
DATE        = "20040206"

LICENSE     = "Permission is granted to copy this document verbatim in any
               medium, provided that this copyright notice is left intact."

COPYRIGHT   = "Copyright (c) 2004 Chris Holman. All rights reserved."

%tokens%

//WIKI TAGS
H_RULE              = "----"
PLING               = "!"
BULLET              = "*"
NUMBER              = "#"
CENTRE_TAG          = "::"
BOLD                = "__"
ITALIC              = "''"
UNDERLINE           = "==="
LINK_START          = "["
LINK_END            = "]"
TABLE_TAG           = "||"
OPEN_SQUARE         = "[["
CLOSE_SQUARE        = "]]"
LT                  = "<<"
GT                  = ">>"
TAG_START           = "<"
TAG_END             = ">"
XML_COMMENT_START   = "!--"
XML_COMMENT_END     = "-->"

//GENERAL TAGS
LETTER              = <<[a-zA-Z]>>
DIGIT               = <<[0-9]>>
EOL                 = <<[\n][\r]?>>
WHITESPACE          = <<[ \t]+>>

//GENERAL TOKENS
COLON               = ":"
EQUALS              = "="
FW_SLASH            = "/"
DOT                 = "."
COMMA               = ","
QUOTE               = <<["]>>
S_QUOTE             = "'"
PERCENT             = "%"
HYPHEN              = "-"
UNDERSCORE          = "_"
AMPERSAND           = "@"
LEFT_PAREN          = "("
RIGHT_PAREN         = ")"
LEFT_BRACE          = "{"
RIGHT_BRACE         = "}"
QUESTION_MARK       = "?"
PLUS_SIGN           = "+"
SEMICOLON           = ";"
PIPE                = "|"
NO_CACHE            = "nocache"
CACHE_DEPTH         = "cachedepth"


%productions%
/* *********************************
 * WIKI PAGE
 * First line has to contain a WikiElement
 * followed by Zero or more WikiElements 
************************************ */
WikiPage = WikiElements (EOL+ (WikiElements)? )* ;


/* **********************************
 * WIKI ELEMENTS
 * Contains either:
 *   * A single line that can start 
*   with a formatting token.
* * An unformatted line
 *   * A multiline block
*********************************** */
WikiElements = WikiFormatted | WikiNotFormatted | WikiBlock ;

/* **********************************
 * WIKI FORMATTED
 * Can start with optional Formatting 
 * tokens followed by a WikiSentence
*********************************** */
WikiFormatted = (WikiFormatting)? ( WikiSentence)+ ;

/* **********************************
 * WIKI FORMATTING
 * Formatting tokens include:
 *   * WHITESPACE: Start Monospace font
*   then indent.
* * BULLET: Bulleted list items
* * NUMBER: Numbered list items
 *   * PLING : Make line a heading
*********************************** */
WikiFormatting = (WHITESPACE | (BULLET | NUMBER | PLING)+ WHITESPACE* )+ ;

/* **********************************
 * WIKI NOT FORMATTED
 * Some tokens must always be at the 
 * start of the line. 
*********************************** */
WikiNotFormatted = H_RULE ;

/* **********************************
 * WIKI BLOCK
 * Blocks include:
 *   * Tables
 * * Centred text 
*********************************** */
WikiBlock = ( WikiTable | WikiCentred )+ ;

/* **********************************
 * WIKI TABLE
 * Start and end tables with the 
 * double pipe/bar symbol.
 * A Table can contain many rows. 
 * Each row can define multiple 
 * columns using a pipe/bar symbol
*********************************** */
WikiTable = TABLE_TAG (WikiTableLine)* EOL TABLE_TAG ;
WikiTableLine = EOL+ WikiSentence WHITESPACE* (PIPE WHITESPACE* WikiSentence )* ;

/* **********************************
 * WIKI CENTRED
 * Start and end centred text with the 
 * double colon symbol.
 * Centred text can contain many rows. 
*********************************** */
WikiCentred = CENTRE_TAG (WikiCentredLine)* EOL CENTRE_TAG ;
WikiCentredLine = EOL+ WikiSentence ;

/* **********************************
 * WIKI SENTENCE
 * This is the basic construct of a 
 * wiki page. It can contain a mixture 
 * of markups. 
*********************************** */
WikiSentence = (( WikiString | BoldString | ItalicString | UnderlineString | WikiLink | XmlTag) WHITESPACE*)+ ;

/* **********************************
 * WIKI STRING
 * Basic text entries.
*********************************** */
WikiString = WikiCharacter (WikiCharacter | PLING | WHITESPACE)* ;
WikiCharacter = OPEN_SQUARE | CLOSE_SQUARE | LT | GT | LETTER | DIGIT | HYPHEN | DOT | COLON | UNDERSCORE | FW_SLASH | QUOTE | S_QUOTE | COMMA | LEFT_PAREN | RIGHT_PAREN | QUESTION_MARK ;

/* **********************************
 * BOLD STRING
 * Make contained text bold. Other 
 * markup is possible within a BOLD 
 * STRING, but recursive BOLD STRINGS
 * are excluded.
*********************************** */
BoldString = BOLD (WHITESPACE* ( WikiString | ItalicString | UnderlineString | WikiLink | XmlTag ))+ BOLD ;

/* **********************************
 * ITALIC STRING
 * Make contained text italic. Other 
 * markup is possible within an ITALIC
 * STRING, but recursive ITALIC STRINGS
 * are excluded.
*********************************** */
ItalicString = ITALIC (WHITESPACE* ( WikiString | BoldString | UnderlineString | WikiLink | XmlTag ))+ ITALIC ;

/* **********************************
 * UNDERLINE STRING
 * Make contained text underlined. Other 
 * markup is possible within an UNDERLINED 
 * STRING, but recursive UNDERLINED STRINGS
 * are excluded.
*********************************** */
UnderlineString = UNDERLINE (WHITESPACE* ( WikiString | BoldString | ItalicString | WikiLink | XmlTag ))+ UNDERLINE ;

/* **********************************
 * WIKI LINK
 * Define a link. Links are not parsed
 * so should be validated as either a
 *   * WikiName
 * * url
 * Optional information can be included:
 *   * Description: A pipe/bar symbol 
 *   followed by a descriptive passage. 
 * * Cache Control: A pipe/bar symbol 
 *   followed by:
 *   * nocache
 * * cachedepth <n>
*********************************** */
WikiLink    = LINK_START WHITESPACE* LinkName (PIPE LinkDescription)? (PIPE Cached WHITESPACE*)? LINK_END WHITESPACE*;
LinkDescription = WHITESPACE* WikiCharacter (WikiCharacter | WHITESPACE)* ;
LinkName = LETTER ( WHITESPACE | LETTER | DIGIT | DOT | HYPHEN | FW_SLASH | COLON | UNDERSCORE | PERCENT)* ;
Cached   = NO_CACHE | (CACHE_DEPTH WHITESPACE+ DIGIT+) ;

/* **********************************
 * XML/XHTML TAGS
 * XML and XHTLM tags can be used to 
 * include:
 *   * Hidden comments 
 *   * Wiki specific commands/plugins.
 * * Embedded XHTML
 * PROBABLY NEEDS MORE WORK!
*********************************** */
XmlTag     = TAG_START ( XmlComment | XmlCommand ) ;

XmlComment = XML_COMMENT_START ( EOL | WHITESPACE* WikiSentence )+ XML_COMMENT_END;

XmlCommand = WHITESPACE* FW_SLASH? XmlName WHITESPACE* XmlProperties* (FW_SLASH WHITESPACE*)?  TAG_END;
XmlName = LETTER (LETTER | DIGIT)* ;
XmlProperties = (XmlNameValuePair WHITESPACE* )+;
XmlNameValuePair = XmlName WHITESPACE* EQUALS WHITESPACE* XmlValue ; 
XmlValue = XmlSingleQuotedValue | XmlQuotedValue | XmlCharacter+ ;
XmlSingleQuotedValue = S_QUOTE ((XmlCharacter | FW_SLASH | WHITESPACE | QUOTE )+)? S_QUOTE ;
XmlQuotedValue = QUOTE ((XmlCharacter | FW_SLASH | WHITESPACE | S_QUOTE )+)? QUOTE ;
XmlCharacter = LETTER | DIGIT | DOT | HYPHEN | COLON | UNDERSCORE | PERCENT ;


