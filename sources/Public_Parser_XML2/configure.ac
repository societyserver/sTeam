AC_INIT(xml2_config.h.in)

AC_CONFIG_HEADERS(xml2_config.h)

PKG_CHECK_MODULES(XML2, libxml-2.0)
PKG_CHECK_MODULES(XSLT, libxslt)

CPPFLAGS="${CPPFLAGS} ${XML2_CFLAGS} ${XSLT_CFLAGS}"
LDFLAGS="${LDFLAGS} ${XML2_LIBS} ${XSLT_LIBS}"

AC_CHECK_FUNCS(strlcpy)
AC_CHECK_FUNCS(memcpy)

AC_CHECK_HEADERS(libxml/parser.h)
AC_CHECK_HEADERS(libxml/xpath.h)
AC_CHECK_HEADERS(libxml/SAX2.h)
AC_CHECK_HEADERS(libxml/xmlreader.h)
AC_CHECK_HEADERS(libxml/relaxng.h)

AC_CHECK_HEADERS(libxslt/xslt.h)
AC_CHECK_HEADERS(libxslt/xsltInternals.h)
AC_CHECK_HEADERS(libxslt/transform.h)
AC_CHECK_HEADERS(libxslt/xsltutils.h)
AC_CHECK_HEADERS(libxslt/document.h)

AC_CHECK_LIB(xml2, xmlCleanupParser) 
AC_CHECK_LIB(xslt, xsltCleanupGlobals) 

AC_CHECK_FUNCS(xmlNewDocPI) 
AC_CHECK_FUNCS(xsltSetLoaderFunc) 
AC_CHECK_FUNCS(xmlTextReaderGetParserLineNumber)
AC_CHECK_FUNCS(xmlTextReaderGetParserColumnNumber)
AC_CHECK_FUNCS(xmlTextReaderIsNamespaceDecl)

AC_SUBST(XML2_CFLAGS) 
AC_SUBST(XML2_LIBS)

AC_SUBST(XSLT_CFLAGS) 
AC_SUBST(XSLT_LIBS)
AC_SUBST(PIKE_INCLUDE_PREFIX)
AC_SUBST(PIKE)
AC_SUBST(PIKE_VERSION)

pushdef([AC_CONFIG_HEADER],
[
  CONFIG_HEADERS="$1"
  popdef([AC_CONFIG_HEADER])
  AC_CONFIG_HEADER($1)
])

make_variables_in="$PIKE_INCLUDE_PREFIX/make_variables.in"
echo "Make Variables $make_variables_in"
AC_SUBST(make_variables_in)

AC_OUTPUT(Makefile)

