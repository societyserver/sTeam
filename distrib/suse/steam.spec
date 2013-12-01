#
# spec file for package steam (Version 2.8.2)
#
# Copyright (c) 2008 open-sTeam
# This file and all modifications and additions to the pristine
# package are under the same license as the package itself.
#
# Please submit bug fixes or comments via http://bugs.open-steam.org
#

# norootforbuild

Name: steam
Version: 2.9.4
Release: 1

Summary: Collaboration Server Based on Virtual Knowledge Spaces
Vendor: open-sTeam
Distribution: openSUSE
Packager: Robert Hinn <exodusd@gmx.de>
URL: http://www.open-steam.org
License: GPL

Group: Applications/Productivity/Networking/Web/Servers

Source0:	http://server.open-steam.org/Download/steam-%{version}.tar.gz

BuildRoot:	%{_tmppath}/%{name}-%{version}-build

Requires: gdbm, gmp, libxml2, libxslt, mysql-shared, pike = 7.6.86, pike-image = 7.6.86, pike-mysql = 7.6.86
BuildRequires: gdbm-devel, gmp-devel, flex, libxml2-devel, libxslt-devel, autoconf, automake, pike = 7.6.86, pike-image = 7.6.86, pike-mysql = 7.6.86, pike-devel = 7.6.86

%if 0%{?suse_version}
PreReq: %insserv_prereq, /usr/bin/sed
%else
PreReq: /usr/bin/sed
%endif

%description
Open-sTeam is an open source environment for the creation and maintainance of
virtual knowledge spaces. It provides various mechanisms supporting
communicative and collaborative learning and work processes.


#%package doc
#Summary: Developer documentation for %{name}.
#Group: Documentation
#Requires: %{name} = %{version}
#
#%description doc
#Developer documentation for %{name}.


%prep
%setup -q


%build
./configure --prefix=%{_prefix} --with-installdir=%{buildroot} \
    --with-config=/etc/steam --with-steamdir=%{_libdir}/steam
make


%install
[ -z "%{buildroot}" -o "%{buildroot}" = "/" ] || rm -rf %{buildroot}
make install
# set sandbox path in config to /var/lib/steam:
cp %{buildroot}/etc/steam/steam.cfg %{buildroot}/etc/steam/steam.cfg.tmp
cat %{buildroot}/etc/steam/steam.cfg.tmp | sed -e "s|#sandbox=.*|sandbox=/var/lib/steam|g" > %{buildroot}/etc/steam/steam.cfg
rm -f %{buildroot}/etc/steam/steam.cfg.tmp
mkdir -p %{buildroot}/var/lib/steam
# install init.d script and rc* link:
mkdir -p %{buildroot}/etc/init.d
cp distrib/suse/init.d/steam %{buildroot}/etc/init.d/steam
mkdir -p %{buildroot}/usr/sbin
ln -s /etc/init.d/steam %{buildroot}/usr/sbin/rcsteam
# provide links to the steam binaries/scripts:
mkdir -p %{buildroot}%{_bindir}
ln -s %{_libdir}/steam/bin/steam %{buildroot}%{_bindir}/steam
ln -s %{_libdir}/steam/bin/steam-shell %{buildroot}%{_bindir}/steam-shell
ln -s %{_libdir}/steam/bin/spm %{buildroot}%{_bindir}/spm


%clean
[ -z "%{buildroot}" -o "%{buildroot}" = "/" ] || rm -rf %{buildroot}


# The following script will be run before installing:
%pre

# The following script will be run after installing (a single command
# may be specified by the -p option):
%post
if [ "$1" -eq 1 ]; then # setup database on first time install
%{_libdir}/steam/bin/setup --quiet --ignore-existing-db
fi
%{insserv_force_if_yast steam}

# The following script will be run before uninstalling:
%preun
%stop_on_removal steam

# The following script will be run after uninstalling:
%postun
%restart_on_update steam
%insserv_cleanup

# The following script will be run on verify:
#%verifyscript


%files
%defattr(-,root,root)
%doc README README-INSTALL COPYING CHANGELOG
%config /etc/steam
%config /etc/init.d/steam
%config /usr/sbin/rcsteam
%{_bindir}/steam
%{_bindir}/spm
%{_bindir}/steam-shell
%{_libdir}/steam
/var/lib/steam

#%files doc
#%defattr(-,root,root)
#%doc refdoc
### Mark directory as documentation directory:
##%docdir /usr/lib/%{name}/doc




