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
if [ -e /usr/bin/curl ]; then
	curl -s -L $PKGS |grep '^<a' |cut -d'"' -f2 >PACKAGES
else
	wget -o /dev/null -O - $PKGS |grep '^<a' |cut -d'"' -f2 >PACKAGES
fi
PACKAGES="deltarpm distro-release-OpenMandriva distro-release-common dnf dnf-automatic dnf-conf dnf-yum dwz hawkey-man glibc ${LIB}comps0 ${LIB}createrepo_c0 ${LIB}crypto1.1 ${LIB}ssl1.1 ${LIB}curl4 ${LIB}db6.2 ${LIB}dnf2 ${LIB}idn2_0 ${LIB}gpgme11 ${LIB}gpgmepp6 ${LIB}repo0 ${LIB}rpm8 ${LIB}rpmbuild8 ${LIB}rpmsign8 ${LIB}solv0 ${LIB}solvext0 ${LIB}zstd1 ${LIB}lua5.3 libsolv openmandriva-repos openmandriva-repos-cooker openmandriva-repos-keys openmandriva-repos-pkgprefs ${LIB}python3.7m_1 ${LIB}stdc%2B%2B6 ${LIB}json-c4 ${LIB}crypt1 python python-dnf python-dnf-plugin-leaves python-dnf-plugin-show-leaves python-dnf-plugin-versionlock python-dnf-plugins-core python-libdnf python-gi python-smartcols ${LIB}modulemd-gir1.0 ${LIB}modulemd1 python-gpg python-hawkey python-iniparse python-libcomps python-librepo python-rpm python-six rpm rpm-openmandriva-setup rpm-plugin-ima rpm-plugin-syslog rpm-plugin-systemd-inhibit rpm-sign rpmlint rpmlint-distro-policy"
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
cd /var/lib/rpm
mkdir -p /var/lib/RPMNEW
cp ./Packages /var/lib/RPMNEW/
mv alternatives /var/lib/RPMNEW/
mv filetriggers /var/lib/RPMNEW/
cd "$TMPDIR"
# As soon as this is run the rpmdb will only contain the packages that are in the $TMPDIR
# Thus you end up with a db of about 10mB so dnf doesn't want to upgrad anything because there's very little there.
rpm -Uvh --force --oldpackage --nodeps *.rpm
# After installing the necessary packages let's restore the original db because now we have the necessary libraries to convert it properly
cp /var/lib/RPMNEW/Packages /var/lib/rpm/
cd -
rpm --rebuilddb
# Now we have a good db move back some useful files
mv /var/lib/RPMNEW/alternatives /var/lib/rpm/
mv /var/lib/RPMNEW/filetriggers /var/lib/rpm/
cd /var/lib
# Remove the backup directory
/bin/rm -R /var/lib/RPMNEW
# This bits important. Re-install the packages that we installed to allow us to update
# Now the db should be fully current
cd "$TMPDIR"
rpm -Uvh --force --oldpackage --nodeps *.rpm

rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-OpenMandriva
cp /etc/shadow /etc/gshadow /etc/passwd /etc/group .
dnf -y erase perl-URPM perl-RPMBDB perl-MDV-Packdrakeng perl-MDV-Distribconf
dnf --releasever=cooker upgrade --nogpgcheck --allowerasing --exclude gtksourceview --exclude akonadi-contacts
printf "%s\n" "You may wish to run the dnf upgrade --nogpgcheck as second time" "using the --allowerasing --exclude <package_name> flags" "these actions come with no guaratees!"
cp -f shadow gshadow passwd group /etc/
cd /
rm -rf "$TMPDIR"
rm -rf ./rpmold????
