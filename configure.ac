AC_INIT([steam],[2.7],[open-steam <info@open-steam.org>], [steam])

AM_INIT_AUTOMAKE

AM_CONFIG_HEADER(sources/_XML/xml_config.h)

# if you add anything to DIRS or SOURCES_DIRS, then you might also want to add
# corresponding Makefiles to AC_CONFIG_FILES at the bottom of this file, too:
DIRS="sources spm"
SOURCES_DIRS="steam libxslt _XML wiki coal steamtools"
AC_SUBST(DIRS)
AC_SUBST(SOURCES_DIRS)

if test "$prefix" = "NONE"; then
   prefix="/usr/local"
fi
echo "Installing into ${prefix}"

AC_SET_MAKE
AC_PROG_CC
AC_PROG_CPP
AC_PROG_INSTALL

AC_PROG_LEX
# Portable scanner, as suggested in the AC_PROG_LEX autoconf documentation:
if test "$LEX" != flex; then
   LEX="$SHELL $missing_dir/missing flex"
   AC_SUBST([LEX_OUTPUT_ROOT], [lex.yy])
   AC_SUBST([LEXLIB], [''])
fi

# *** Pike (PIKE, PIKE_VERSION, PIKE_VERSION_STR, PIKE_FULL_VERSION, ******
#           PIKE_INCLUDE_DIRS)

AC_ARG_WITH(pike, 
AC_HELP_STRING([--with-pike[=binary]],[Use the specified Pike.]),
[
    if test ! -z "$withval" -a "$withval" != "yes"; then 
		extpike="`type  $withval |sed "s:$withval is ::" 2>/dev/null`"
                if test "$extpike" != ""; then
                   withval="$extpike";
                fi
		if test -f "$withval" -a  ! -x "$withval" ; then
			echo "$withval is not an executable file"
 			exit 1
		elif test -x "$withval" -a -f "$withval"; then
			DEFPIKE="$withval"
		else
			echo "$withval doesn't exist or isn't an executable file."
 			exit 1
		fi
	fi
])

RESULT=no
AC_MSG_CHECKING(for a working Pike)

pathpike="`type  pike |sed 's/pike is//' 2>/dev/null`"
if test "$prefix" != "NONE"; then
  PREFIXPIKE="$prefix"
fi

for path in $DEFPIKE $PREFIXPIKE/bin/pike $pathpike/bin/pike /usr/local/bin/pike /opt/pike/bin/pike /opt/local/bin/pike /sw/bin/pike /sw/local/opt/local/bin/pike /usr/gnu/bin/pike /usr/bin/pike ; do
  if test  "x$PIKE" != "x" ; then
    break;
  fi
  a="`dirname ${path}`"
  a="`dirname ${a}`"
  AC_MSG_CHECKING(${a})
  if test -x $path; then
    PIKE="${path}"
    AC_MSG_RESULT("yes (Pike is $PIKE)")
    if $PIKE -e 'float v; int rel;sscanf(version(), "Pike v%f release %d", v, rel);v += rel/10000.0; if(v < 7.4) exit(1); exit(0);'; then
        PIKE_VERSION="`${PIKE} -e 'int v,sv;sscanf(version(),\"Pike v%d.%d %*s\", v, sv); write(v+\".\"+sv);exit(0);'`"
	PIKE_VERSION_STR="`${PIKE} -e 'write(version());exit(0);'`"
        PIKE_FULL_VERSION="`${PIKE} -e 'int v,sv,svv;sscanf(version(),\"Pike v%d.%d release %d %*s\", v, sv,svv); write(v+\".\"+sv+\".\"+svv);exit(0);'`"
        PIKE_MODULE_DIR="`$PIKE --show-paths 2>&1| grep -i 'module path'|head -1 | sed -e 's/.*: //'`"
        PIKE_INCLUDE_DIR="`$PIKE --show-paths 2>&1| grep -i 'include path'|head -1 | sed -e 's/.*: //'`"
        PIKE_INCLUDE_DIRS="-I${PIKE_INCLUDE_DIR} -I${PIKE_MODULE_DIR} -I`echo "$PIKE_MODULE_DIR" | sed -e 's,lib/pike/modules,include/pike,' -e 's,lib/modules,include/pike,'`"

	for b in include/pike pike/${PIKE_VERSION}/include/pike include/pike${PIKE_VERSION}/include include/pike${PIKE_VERSION} pike/${PIKE_FULL_VERSION}/include/pike include/pike/${PIKE_FULL_VERSION} include/pike/pike${PIKE_VERSION} lib/pike/${PIKE_FULL_VERSION}/include/pike; do
	    PIKE_C_INCLUDE=${a}/${b}
	    AC_MSG_CHECKING("C_INCLUDE_DIR=${PIKE_C_INCLUDE}")
	    if test -f $PIKE_C_INCLUDE/global.h; then
	       PIKE_INCLUDE_PREFIX="${PIKE_C_INCLUDE}"
               PIKE_INCLUDE_DIRS="$PIKE_INCLUDE_DIRS -I$PIKE_INCLUDE_PREFIX"
               AC_MSG_RESULT(yes)
               break
            else
               AC_MSG_RESULT(no)
	    fi
	 done
    fi
else
    AC_MSG_RESULT(no)
fi
export PIKE_INCLUDE_PREFIX PIKE_INCLUDE_DIRS PIKE PIKE_VERSION PIKE_VERSION_STR PIKE_FULL_VERSION
AC_SUBST(PIKE_INCLUDE_PREFIX)
AC_SUBST(PIKE_INCLUDE_DIRS)
AC_SUBST(PIKE)
AC_SUBST(PIKE_VERSION)
AC_SUBST(PIKE_VERSION_STR)
AC_SUBST(PIKE_FULL_VERSION)
done
if test "x$PIKE" = "x"; then
    AC_MSG_ERROR(Pike is required for sTeam to run)
fi


# *** open-sTeam brand (brand) ********************************************

brand=steam
AC_ARG_WITH(brand,
AC_HELP_STRING([--with-brand@<:@=brand_name@:>@],[Specify the name to use for the steam folders and database. Only alphanumeric characters are allowed, and the name must start with a letter, not a number. Also, don't use a name that you already use as a database name. This will be used as the folder name for configs, logs and server and as the database name, unless overridden. Default: steam]),
[
	echo "$withval ... trying..."
	brand="$withval"
])
AC_SUBST(brand)
export brand


# *** installation directory (installdir) *********************************

installdir=/
AC_ARG_WITH(installdir,
AC_HELP_STRING([--with-installdir@<:@=installdir@:>@],[Use the specified install dir. This will be prepended to the prefix variable. Default is: /.]),
[
	echo "$withval ... trying..."
	installdir="$withval"
])
installdir=`echo "$installdir" | sed 's,//*,/,g'`
AC_SUBST(installdir)
export installdir


# *** config directory (configdir) ****************************************

configdir=/etc/$brand
AC_ARG_WITH(configdir,
AC_HELP_STRING([--with-configdir@<:@=config-dir@:>@],[Use the specified dir for config files. Default: /etc/steam.]),
[
	echo "$withval ... trying..."
	configdir="$withval"
])
configdir=`echo "$configdir" | sed 's,//*,/,g'`
AC_SUBST(configdir)
export configdir


# *** logfile directory (logdir) ******************************************

logdir=/var/log/$brand
AC_ARG_WITH(logdir,
AC_HELP_STRING([--with-logdir@<:@=logdir@:>@],[Use the specified dir for log files. Default: /var/log/steam.]),
[
        echo "$withval ... trying..."
        logdir="$withval"
])
logdir=`echo "$logdir" | sed 's,//*,/,g'`
AC_SUBST(logdir)
export logdir


# *** open-sTeam server files directory (steamdir) ************************

steamdir=/$prefix/lib/$brand
AC_ARG_WITH(steamdir,
AC_HELP_STRING([--with-steamdir@<:@=steam-dir@:>@],[Use the specified dir for the steam server files. Default: /usr/local/lib/steam (or /usr/lib/steam, depending on your prefix).]),
[
	echo "$withval ... trying..."
	steamdir="$withval"
])
steamdir=`echo "$steamdir" | sed 's,//*,/,g'`
AC_SUBST(steamdir)
export steamdir


# *** open-sTeam binary (steambinary) *************************************

steambinary=$steamdir/bin/$brand
AC_SUBST(steambinary)
export steambinary


# *** Java home directory (javahome) **************************************

javahome=$JAVA_HOME
AC_ARG_WITH(javahome,
AC_HELP_STRING([--with-javahome@<:@=java_install_dir@:>@],[Specify the directory where java is installed (e.g. /usr/java/j2sdk_1.4.0). Default is: \$JAVA_HOME.]),
[
        echo "$withval ... trying..."
        javahome="$withval"
])
AC_SUBST(javahome)
export javahome


# *** libxml2, libxslt (LIBS, LIBDIR, LIBXSL_INCLUDE) *********************

AC_MSG_CHECKING(For libxml2 includes)
# check for libxml2 include directories.
AM_PATH_XML2(2.4.1, AC_DEFINE(HAVE_XML2, 1, [Define if you have XML2 installed]), AC_MSG_ERROR(Failed to find libxml2))
AC_MSG_RESULT($XML_CFLAGS)
export XML_CFLAGS
export CFLAGS

#check for libxslt include directories
AC_MSG_CHECKING(Looking for libxslt includes)
xslhdrdir=no
for a in /opt/local/include /sw/include /usr/include /usr/local/include /opt/include /opt/sfw/include; do
    if test -d ${a}; then
	LIBXSL_INCLUDES="${a}"
    AC_CHECK_HEADER(${a}/libxslt/xsltconfig.h,xslhdrdir=${a})
    fi
done

if test $xslhdrdir = no ; then
   AC_MSG_ERROR(Failed to find libxslt include directory)
fi
AC_MSG_RESULT(XSL includes in $xslhdrdir)

LIBXSL_INCLUDE="${xslhdrdir}"
AC_SUBST(LIBXSL_INCLUDE)

AC_MSG_CHECKING(for libxslt library)
xsllibdir=no
AC_ARG_WITH(xslt-libdir,
AC_HELP_STRING([--with-xslt-libdir[=xslt-dir]],[Use path for xslt library]),
[
		if test -f $withval/libxslt.so; then
		   xsllibdir=$withval;
		fi
])
if test $xsllibdir = no; then
  for a in /opt/local/lib64 /opt/local/lib /sw/lib64 /sw/lib /usr/lib64 /usr/lib /usr/local/lib64 /usr/local/lib /opt/lib64 /opt/lib /lib64 /lib /opt/sfw/lib64 /opt/sfw/lib /usr/sfw/lib64 /usr/sfw/lib; do
	if test -f ${a}/libxslt.so; then
	   xsllibdir=${a}
	   LIBS="-lxslt"
	fi
	if test -e ${a}/libxslt.dylib; then
	   echo "Found dylib...";
	   xsllibdir=${a}
	   echo $xsllibdir;
	   LIBS="-lxslt"
	fi
  done
fi
if test $xsllibdir = no; then
   AC_MSG_ERROR(Failed to find libxslt library.)
fi

AC_SUBST(LIBS)
AC_MSG_RESULT(Found libxslt library in $xsllibdir)

AC_MSG_CHECKING(Looking for libxml2 library)
xmllibdir=no
for a in /opt/local/lib64 /opt/local/lib /sw/lib64 /sw/lib /usr/lib64 /usr/lib /usr/local/lib64 /usr/local/lib /opt/lib64 /opt/lib /lib64 /lib /opt/sfw/lib64 /opt/sfw/lib /usr/sfw/lib64 /usr/sfw/lib; do
	if test -f ${a}/libxml2.so; then
	   xmllibdir=${a}
	fi
	if test -e ${a}/libxml2.dylib; then
	   xmllibdir=${a}
	fi
done
AC_MSG_RESULT(Found libxml2 library in $xmllibdir)
LIBDIR="${xsllibdir}:${xmllibdir}"
XSLLIBDIR="${xsllibdir}"
XMLLIBDIR="${xmllibdir}"
AC_SUBST(LIBDIR)

export LIBXML2_INCLUDE
export LIBXSL_INCLUDE
export XSLLIBDIR
export XMLLIBDIR
export LIBDIR
export LIBS

# *** system os, linker stuff (steam_sys_os, LDSHARED) ********************

#get system OS
AC_CACHE_VAL(steam_sys_os,
[
if test "$uname_prog" != "no"; then
  steam_sys_os="`uname`"

  case "$steam_sys_os" in
    SunOS)
      case "`uname -r`" in
        5.*) steam_sys_os="Solaris";
      esac
    ;;
    Monterey64)
      # According to the release notes, the string "Monterey64"
      # will be changed to "AIX" in the final release.
      # (Monterey 64 is also known as AIX 5L).
      steam_sys_os="AIX"
    ;;
  esac
else
  steam_sys_os="Not Solaris"
fi
])
AC_MSG_RESULT($steam_sys_os)
AC_SUBST(steam_sys_os)
echo $steam_sys_os
AC_PROG_CPP
# LDSHARED is the ld *command* used to create shared library
# -- "ld" on SunOS 4.x.x, "ld -G" on SunOS 5.x, "ld -shared" on IRIX 5
AC_MSG_CHECKING(LDSHARED)
if test -z "$LDSHARED" ; then
  case "$steam_sys_os" in
    AIX*)
      if test "$GCC" = yes ; then
        if test "`uname -r`" -ge 2 -a "`uname -v`" -ge 4 ; then
          LDSHARED="ld -G -bexpall"
	else if test "`uname -v`" -gt 4 ; then
	    # Extra forward compatibility...
	    # AIX 5+
	    LDSHARED="ld -G -bexpall"
	  else
	    # AIX 4.1 and earlier don't have/have unreliable
	    # handling of dlopen et al.
	    #
	    # Even AIX 4.2.1 has buggy dlopen -- NEVER attempt
	    # to dlopen a file that hasn't been linked with -G.
	    steam_sys_dynamic_loading=no
	    LDSHARED="ld"
	  fi
        fi
      else
        # Dynamic linking turned off for AIX-cc
	#
	# In addition, the dynamic loading test seems to
	# cause our RS/6000 to hang, which causes the
	# watchdog-timer to PANIC.
	steam_sys_dynamic_loading=no
        LDSHARED="ld"
      fi
    ;;
    IRIX*)
      if test "$GCC" = yes ; then
        # egcs defaults to building -n32 objects
        LDSHARED="ld -shared -n32"
      else
        LDSHARED="ld -shared"
      fi
      # -woff isn't understood by ld on Irix 5.
      if test "`uname -r`" -ge 6 ; then
        LDSHARED="$LDSHARED -woff 84,85,134"
      else :; fi
    ;;
    SunOS*) LDSHARED="ld";;
    Solaris) LDSHARED="/usr/ccs/bin/ld -G";;
    hp*|HP*) LDSHARED="ld -b";;
    OSF*) LDSHARED="ld -expect_unresolved '*' -shared -msym -O3";;
    DYNIX/ptx*) LDSHARED="ld -G";;
    next*) LDSHARED="$CC $CFLAGS -nostdlib -r";;
    Linux*) 
        LDSHARED="ld -E -shared"
	LDFLAGS=""
	;;
    GNU*) LDSHARED="ld -Bshareable";;
    FreeBSD*) 
	LDSHARED="$CC -Wl,-Bshareable"
	AC_DEFINE(RUNNING_BSD)
	;; 
    Darwin*)
	LDSHARED="gcc -bundle -bundle_loader ${PIKE} -bind_at_load"
	LDFLAGS="-L$xsllibdir -L$xmllibdir"
	AC_DEFINE(RUNNING_DARWIN)
	;;
    NetBSD*) 
	LDSHARED="ld -Bshareable"
	AC_DEFINE(RUNNING_BSD)
	;;
    OpenBSD*)
	LDSHARED="ld -Bshareable"
	AC_DEFINE(RUNNING_BSD)
	;;
    BSD/OS*) LDSHARED="shlicc -r";;
    SCO_SV*) LDSHARED="cc -G -KPIC -Wl,-Bexport";;
    UNIX_SV*) LDSHARED="ld -G";;
    UnixWare*)
      if test "$GCC" = yes ; then
        LDSHARED="ld -G"
      else
        LDSHARED="cc -G -KPIC -Wl,-Bexport"
      fi
    ;;
    Windows_NT*) LDSHARED="$CC -shared";;
    *) LDSHARED="ld";;
  esac
fi
AC_MSG_RESULT($LDSHARED)
AC_SUBST(LDSHARED)
export steam_sys_os

export LDSHARED
export LDFLAGS

echo "LDSHARED=${LDSHARED}"


# *** install script ******************************************************

AC_MSG_CHECKING(install Script)
installprg=none
for a in /sw/bin /usr/bin /usr/local/bin /opt/bin /bin /opt/sfw/bin /usr/sfw/bin; do
	if test -x ${a}/install; then
	    installprg=${a}/install
	fi
	if test -x ${a}/ginstall; then
	    installprg="${a}/ginstall"
	fi
done
AC_MSG_RESULT(Found $installprg)
AC_SUBST(installprg)
export installprg


# *** check for compiler options ******************************************

# check for -fPIC
AC_MSG_CHECKING(for compiler option -fPIC)
OLD_CFLAGS="$CFLAGS"
OLD_CPPFLAGS="$CPPFLAGS"
CFLAGS=-fPIC
CPPFLAGS=-fPIC
AC_LANG_C
AC_COMPILE_IFELSE([int main ( int argc, char ** argv ) { return 0; }],[
  AC_MSG_RESULT(supported)
  CFLAGS="$OLD_CFLAGS -fPIC"
  CPPFLAGS="$OLD_CPPFLAGS -fPIC"
],[
  AC_MSG_RESULT(not supported)
  CFLAGS="$OLD_CFLAGS"
  CPPFLAGS="$OLD_CPPFLAGS"
])

# check for -fno-stack-protector
AC_MSG_CHECKING(for compiler option -fno-stack-protector)
OLD_CFLAGS="$CFLAGS"
OLD_CPPFLAGS="$CPPFLAGS"
CFLAGS=-fno-stack-protector
CPPFLAGS=-fno-stack-protector
AC_LANG_C
AC_COMPILE_IFELSE([int main ( int argc, char ** argv ) { return 0; }],[
  AC_MSG_RESULT(supported)
  CFLAGS="$OLD_CFLAGS -fno-stack-protector"
  CPPFLAGS="$OLD_CPPFLAGS -fno-stack-protector"
],[
  AC_MSG_RESULT(not supported)
  CFLAGS="$OLD_CFLAGS"
  CPPFLAGS="$OLD_CPPFLAGS"
])

AC_SUBST(CFLAGS)
AC_SUBST(CPPFLAGS)


# *** source package specific stuff ***************************************

# sources/libxslt :
LIBXSLT_CFLAGS=-O3
AC_SUBST(LIBXSLT_CFLAGS)
export LIBXSLT_CFLAGS

# sources/wiki :
if test "$steam_sys_os" != "Darwin"; then
  WIKI_LDFLAGS="-R ${LIBDIR}"
else
  WIKI_LDFLAGS="-L${XSLLIBDIR}"
fi
AC_SUBST(WIKI_LDFLAGS)
export WIKI_LDFLAGS
AC_CHECK_FUNCS(xmlBufContent)


# *** Configure output ****************************************************

#AC_CONFIG_SUBDIRS() # all is handled by this top-level configure.ac now

AC_CONFIG_FILES(Makefile start setup version backup distrib/redhat/init.d/steam distrib/suse/init.d/steam distrib/generic-lsb/init.d/steam distrib/generic/init.d/steam tools/debug.pike tools/export tools/export_users tools/import tools/create_cert.pike server/include/configure.h sources/Makefile sources/_XML/Makefile sources/coal/Makefile sources/libxslt/Makefile sources/steam/Makefile sources/steamtools/Makefile sources/wiki/Makefile spm/Makefile spm/spm)

AC_OUTPUT

chmod 755 spm/spm
chmod +x distrib/redhat/init.d/steam
chmod +x distrib/suse/init.d/steam
chmod +x distrib/generic-lsb/init.d/steam
chmod +x distrib/generic/init.d/steam
