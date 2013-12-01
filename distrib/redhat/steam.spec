Name: steam
Version: 2.0.0
Release: 1

%define _prefix /usr/local
%define brand steam
%define _datadir %{_prefix}/share
%define steamdir %{_prefix}/lib/%{brand}
%define configdir %{_sysconfdir}/%{brand}
%define logdir /var/log/%{brand}

# build documentation?
%define do_build_docs 1
%{?with-docs: %define do_build_docs 1}
%{?without-docs: %define do_build_docs 0}

# You can use the %{version_underscore} var if you need the version number
# with dots converted to underscores, e.g.: 1_7_0
%{expand: %%define version_underscore `echo %%{version} | sed -e "s/\\./_/g"` }

Summary: sTeam - structuring information in a team
Vendor: University of Paderborn
#Distribution:
Packager: Robert Hinn <exodus@uni-paderborn.de>
URL: http://www.open-steam.org
License: GPL
#Copyright: GPL

Group: Applications/Productivity

Source0:	%{name}-%{version}.tar.bz2

BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-buildroot

Prefix:	%{_prefix}

Requires: pike
Requires: mysql, mysql-server
Requires: libxml2, libxslt
Requires: libpng, libjpeg
BuildRequires: pike
BuildRequires: autoconf >= 2.52
BuildRequires: mysql-devel
BuildRequires: libxml2-devel, libxslt-devel
BuildRequires: libpng-devel, libjpeg-devel
%if %{do_build_docs}
BuildRequires: graphviz
%endif

%description
sTeam is a client-server system providing a virtual learning/working environment.
The system consists of interconnected rooms, which contain different objects.
Objects can be users, documents or any type of references. Connections between
the objects allow users to structure the content according to their needs.


%if %{do_build_docs}
%package doc
Summary: Developer documentation for %{name}.
Group: Documentation
#Requires: %{name} = %{version}

%description doc
Developer documentation for %{name}.
%endif

%prep
%setup -q


%build
export CFLAGS="${CFLAGS:-%optflags}"
export CXXFLAGS="${CXXFLAGS:-%optflags}"
aclocal
#./configure \
./build \
	--build=%{_target_platform} \
	--prefix=%{_prefix} \
	--mandir=%{_mandir} \
	--infodir=%{_infodir} \
	--datadir=%{_datadir} \
	--sysconfdir=%{_sysconfdir} \
	--with-brand=%{brand} \
	--with-installdir=%{buildroot} \
	--with-steamdir=%{_prefix}/lib/%{brand} \
	--with-configdir=%{configdir} \
	--with-logdir=%{logdir}
# Make is already called by the ./build script:
#make
chmod u+xr setup
# Generate documentation:
%if %{do_build_docs}
pike doxygen.pike
%endif


%install
[ -z "%{buildroot}" -o "%{buildroot}" = "/" ] || rm -rf %{buildroot}
# Don't run ./install, it runs ./setup and that must be run on the target machine
# (in the post-install section).
#./install
make install
install -D -m755 redhat/init.d/steam %{buildroot}%{_sysconfdir}/init.d/steam


%clean
[ -z "%{buildroot}" -o "%{buildroot}" = "/" ] || rm -rf %{buildroot}


# The following script will be run before installing:
%pre


# The following script will be run after installing (a single command
# may be specified by the -p option):
%post -p /sbin/ldconfig
/sbin/install-info --info-dir=%{_infodir} %{_infodir}/%{name}.info
# Setup the sTeam server:
echo "The MySQL database must be running, I'm trying to start it..."
/sbin/service mysqld start
cd %{configdir} && pike %{steamdir}/tools/create_cert.pike
cd %{steamdir} && pike bin/setup
# Add sTeam server as a service:
chkconfig --add %{brand}

# The following script will be run before uninstalling:
%preun
# Unregister sTeam service
chkconfig --del %{brand}

# The following script will be run after uninstalling:
%postun -p /sbin/ldconfig
if [ "$1" = "0" ]
then
        /sbin/install-info --delete --info-dir=%{_infodir} %{name}
fi
# The "if" condition is necessary to prevent the script from being
# run during an update.

# The following script will be run on verify:
#%verifyscript


%files
%defattr(-,root,root)
%doc README.1st COPYING
# Just add everything:
%{_sysconfdir}/init.d/%{brand}
%{steamdir}
%{logdir}
## Configuration files:
%config(noreplace,missingok) %{configdir}/*
#%{_bindir}/*
#%{_libdir}/lib*.so.*
#%{_libdir}/lib*.so
#%{_mandir}/man?/*
#%{_datadir}/locale/*/LC_MESSAGES/*
#%{_infodir}/*.info*
#%{_datadir}/aclocal

%if %{do_build_docs}
%files doc
%defattr(-,root,root)
%doc docs
## Mark directory as documentation directory:
#%docdir /usr/lib/%{name}/doc
%endif

