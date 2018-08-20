#!/bin/sh
# Update an OpenMandriva Lx 3.x system to Cooker
# (C) 2018 Bernhard Rosenkraenzer <bero@lindev.ch>
# Released under the GPLv3

if [ "$(id -u)" != '0' ]; then
	echo "Need root access..."
	sudo $0 "$@"
	exit 1
fi
TMPDIR="$(mktemp -d /tmp/upgradeXXXXXX)"
if ! [ -d "$TMPDIR" ]; then
	echo Install mktemp
	exit 1
fi
cd "$TMPDIR"

# Update 3.x branch and get it into shape...
urpmi --auto --auto-update
urpmi --auto curl wget db52-utils

# Get rid of stuff that will be replaced with alternatives
# that have different names...
urpme -a --auto --force perl-URPM perl-RPMBDB perl-MDV-Packdrakeng perl-MDV-Distribconf gurpmi genhdlist2

# Save list of installed packages for recovery purposes...
rpm -qa --qf '%{NAME}\n' >package.list

ARCH="$(uname -m)"
echo $ARCH |grep -qE "^arm" && ARCH=armv7hnl
echo $ARCH |grep -qE "i.86" && ARCH=i686
if echo $ARCH |grep -q 64; then
	LIB=lib64
else
	LIB=lib
fi
PKGS=http://abf-downloads.openmandriva.org/cooker/repository/$ARCH/main/release/
curl -s -L $PKGS |grep '^<a' |cut -d'"' -f2 >PACKAGES
PACKAGES="deltarpm distro-release-OpenMandriva distro-release-common dnf dnf-automatic dnf-conf dnf-yum dwz hawkey-man glibc ${LIB}comps0 ${LIB}createrepo_c0 ${LIB}crypto1.1 ${LIB}ssl1.1 ${LIB}curl4 ${LIB}db6.2 ${LIB}dnf2 ${LIB}idn2_0 ${LIB}gpgme11 ${LIB}gpgmepp6 ${LIB}repo0 ${LIB}rpm8 ${LIB}rpmbuild8 ${LIB}rpmsign8 ${LIB}solv0 ${LIB}solvext0 ${LIB}zstd1 ${LIB}lua5.3 libsolv openmandriva-repos openmandriva-repos-cooker openmandriva-repos-keys openmandriva-repos-pkgprefs ${LIB}python3.7m_1 ${LIB}stdc%2B%2B6 ${LIB}json-c4 ${LIB}yaml0_2 ${LIB}crypt1 python python-dnf python-dnf-plugin-leaves python-dnf-plugin-show-leaves python-dnf-plugin-versionlock python-dnf-plugins-core python-libdnf python-gi python-smartcols ${LIB}modulemd-gir1.0 ${LIB}modulemd1 ${LIB}glib2.0_0 ${LIB}gobject2.0_0 ${LIB}girepository1.0_1 ${LIB}glib-gir2.0 python-gpg python-hawkey python-iniparse python-libcomps python-librepo python-rpm python-six rpm rpm-openmandriva-setup rpm-plugin-ima rpm-plugin-syslog rpm-plugin-systemd-inhibit rpm-sign rpmlint rpmlint-distro-policy db62-utils"
for i in $PACKAGES; do
	P=`grep "^$i-[0-9].*" PACKAGES`
	if [ "$?" != "0" ]; then
		echo "Can't find cooker version of $i, please report"
		exit 1
	fi
	wget $PKGS/$P
done

cd /var/lib/rpm
mkdir -p /var/lib/RPMNEW
cp Packages /var/lib/RPMNEW/
mv alternatives /var/lib/RPMNEW/
mv filetriggers /var/lib/RPMNEW/
db52_dump Packages >../RPMNEW/Packages.dump

cd "$TMPDIR"
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
# After installing the necessary packages let's restore the original db because now we have the necessary libraries to convert it properly
cd /var/lib/rpm
tries=0
while [ "$tries" -lt 10 ]; do
	# There is some weird issue with rpm --rebuilddb
	# sometimes, but not always, wiping the rpmdb when
	# the Packages file comes from rpm 5.
	# Let's try until we're lucky.
	tries=$((tries+1)
	db62_load Packages <../RPMNEW/Packages.dump
	# Rebuild the rpmdb twice, first attempt likely fails but corrects the failure,
	# enabling the second run to succeed
	rpm --rebuilddb
	rpm --rebuilddb
	[ "$(rpm -qa |wc -l)" -ge 25 ] && break
done
if [ "$tries" = 10 ]; then
	echo "Restoring the rpm database after switching to rpm4 failed."
	echo "Please find the developers on #openmandriva-cooker on freenode."
	exit 1
fi

# Now we have a good db move back some useful files
mv /var/lib/RPMNEW/alternatives /var/lib/rpm/
mv /var/lib/RPMNEW/filetriggers /var/lib/rpm/
cd /var/lib
# Remove the backup directory
/bin/rm -rf /var/lib/RPMNEW
# Rebuild the rpmdb again
rpm --rebuilddb
rpm --rebuilddb

# This bit is important. Re-install the packages that we installed to allow us to update
# Now the db should be fully current
cd "$TMPDIR"
rpm -Uvh --justdb --force --oldpackage --nodeps *.rpm

rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-OpenMandriva
cp -f /etc/shadow /etc/gshadow /etc/passwd /etc/group .
# Workaround for dnf transaction error on perl-base, don't worry, perl
# automatically gets reinstalled by dnf (as a dependency of packages
# that are being updated)
rpm -e --nodeps perl
dnf -y --releasever=cooker --nogpgcheck --allowerasing --best distro-sync
# Workaround for a very weird problem: At some point during distro-sync, bash
# is erased from rpmdb (but the files remain on the system).
dnf -y --releasever=cooker --nogpgcheck --allowerasing install bash
# Repeat distro-sync to get stuff that failed due wrongfully
# thought to be missing bash
dnf -y --releasever=cooker --nogpgcheck --allowerasing --best distro-sync
# Make sure plasma is back if it got uninstalled by distro-sync
dnf -y --releasever=cooker --nogpgcheck --allowerasing --best install task-plasma-minimal
# And make sure other packages that have gone "missing" like bash (see workaround
# above) are reinstalled...
# ^lib.* is excluded because sonames change (and libraries anything depends on will
# be pulled in anyway).
dnf -y --releasever=cooker --nogpgcheck --allowerasing --best install $(sed -e '/kde4/d;/^lib.*/d;/.*qt4.*/d' package.list)
printf "%s\n" "You may wish to run the dnf upgrade --nogpgcheck as second time" "using the --allowerasing --exclude <package_name> flags" "these actions come with no guaratees!"
cp -f shadow gshadow passwd group /etc/
cd /
rm -rf "$TMPDIR"
rm -rf ./rpmold????
