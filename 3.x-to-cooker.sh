#!/bin/sh
# Update an OpenMandriva Lx 3.x system to Cooker
# (C) 2018 Bernhard Rosenkraenzer <bero@lindev.ch>
# Released under the GPLv3

if [ "`id -u`" != "0" ]; then
	echo "Need root access..."
	sudo $0 "$@"
	exit 1
fi
TMPDIR="`mktemp -d /tmp/upgradeXXXXXX`"
if ! [ -d "$TMPDIR" ]; then
	echo Install mktemp
	exit 1
fi
cd "$TMPDIR"
ARCH=`uname -m`
echo $ARCH |grep -qE "^arm" && ARCH=armv7hl
echo $ARCH |grep -qE "i.86" && ARCH=i686
if echo $ARCH |grep -q 64; then
	LIB=lib64
else
	LIB=lib
fi
PKGS=http://abf-downloads.openmandriva.org/cooker/repository/$ARCH/main/release/
curl -s -L $PKGS |grep '^<a' |cut -d'"' -f2 >PACKAGES
PACKAGES="createrepo_c db52-utils db62-utils deltarpm distro-release-OpenMandriva distro-release-common dnf dnf-automatic dnf-conf dnf-yum dwz hawkey-man ${LIB}comps0 ${LIB}createrepo_c0 ${LIB}crypto1.1 ${LIB}ssl1.1 ${LIB}db6.2 ${LIB}dnf-gir1.0 ${LIB}dnf1 ${LIB}gpgme11 ${LIB}gpgmepp6 ${LIB}repo0 ${LIB}rpm8 ${LIB}rpmbuild8 ${LIB}rpmsign8 ${LIB}solv0 ${LIB}solvext0 libsolv openmandriva-repos openmandriva-repos-cooker openmandriva-repos-keys openmandriva-repos-pkgprefs ${LIB}python3.7m_1 python python-dnf python-dnf-plugin-leaves python-dnf-plugin-local python-dnf-plugin-show-leaves python-dnf-plugin-versionlock python-dnf-plugins-core python-gpg python-hawkey python-iniparse python-libcomps python-librepo python-rpm python-six rpm rpm-openmandriva-setup rpm-plugin-ima rpm-plugin-syslog rpm-plugin-systemd-inhibit rpm-sign rpmlint rpmlint-distro-policy"
for i in $PACKAGES; do
	P=`grep "^$i-[0-9].*" PACKAGES`
	if [ "$?" != "0" ]; then
		echo "Can't find cooker version of $i, please report"
		exit 1
	fi
	wget $PKGS/$P
done
# --oldpackage is to allow rpm to go from 5.x to 4.x without forcing an Epoch
# --force shouldn't be needed, but is there just in case someone manually
# installed a relevant cooker package before. That shouldn't make the rpm
# command fail.
# --nodeps is because rpm-build and friends may or may not be installed.
# If they're installed, they require the old version of rpm,
# causing -Uvh to fail with rpm-build etc. not being updated at the
# same time.
# If they're NOT installed and we include rpm-build in the package list,
# that'll fail because rpm-build has other dependencies that can't be
# fulfilled.
# So for now, update the minimal set of required packages and let dnf
# handle the rest.
rpm -Uvh --force --oldpackage --nodeps *.rpm
cd /var/lib/rpm
mkdir /var/lib/RPMNEW
mv Packages /var/lib/RPMNEW/
cd /var/lib/RPMNEW
/bin/rm -R /var/lib/rpm/*
db52_dump ./Packages | db62_load ./Packages.NEW
mv /var/lib/RPMNEW Packages.NEW  /var/lib/Packages
cd ../
/bin/rm -R /var/lib/RPMNEW
cd -
rpm --rebuilddb
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-OpenMandriva
cp /etc/shadow /etc/gshadow /etc/passwd /etc/group .
dnf upgrade --nogpgcheck
printf "%\n" "You may wish to run the dnf upgrade --nogpgcheck as second time" "using the --allowerase --exclude <package_name> flags" "these actions come with no guaratees!"
cp -f shadow gshadow passwd group /etc/
cd /
rm -rf "$TMPDIR"
