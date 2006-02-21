# Configuration for packages.debian.org
#

topdir=/org/packages.debian.org

tmpdir=${topdir}/tmp
bindir=${topdir}/bin
scriptdir=${topdir}/htmlscripts
libdir=${topdir}/lib
filesdir=${topdir}/files
htmldir=${topdir}/www
archivedir=${topdir}/archive
podir=${topdir}/po
localedir=${topdir}/locale
staticdir=${topdir}/static
configdir=${topdir}/conf

# unset this if packages.debian.org moves somewhere where the packages files
# cannot be obtained locally
#
localdir=/org/ftp.debian.org/ftp

# path to private ftp directory
ftproot=/org/ftp.root

ftpsite=http://ftp.debian.org/debian
nonus_ftpsite=http://ftp.uk.debian.org/debian-non-US
security_ftpsite=http://security.debian.org/debian-security
volatile_ftpsite=http://volatile.debian.net/debian-volatile
backports_ftpsite=http://backports.org/debian
amd64_ftpsite=http://amd64.debian.net/debian
kfreebsd_ftpsite=http://kfreebsd-gnu.debian.net/debian

root=""
search_page="http://packages.debian.net/"
search_url="/search"
webmaster=webmaster@debian.org
contact=debian-www@lists.debian.org
home="http://www.debian.org"
bug_url="http://bugs.debian.org/"
src_bug_url="http://bugs.debian.org/src:"
qa_url="http://packages.qa.debian.org/"
ddpo_url="http://qa.debian.org/developer.php?email="

# Architectures
#
polangs="de fi nl fr uk"
ddtplangs="de cs da eo es fi fr hu it ja nl pl pt_BR pt_PT ru sk sv_SE uk"
archives="us non-US security volatile backports"
sections="main contrib non-free"
parts="$sections"
suites="oldstable stable testing unstable experimental"
dists="$suites"
architectures="alpha amd64 arm hppa hurd-i386 i386 ia64 kfreebsd-i386 m68k mips mipsel powerpc s390 sparc"
arch_oldstable="alpha arm hppa i386 ia64 m68k mips mipsel powerpc s390 sparc"
arch_stable="${arch_oldstable} amd64"
arch_testing="${arch_stable}"
arch_unstable="${arch_stable} hurd-i386 kfreebsd-i386"
arch_experimental="${arch_unstable}"
arch_testing_proposed_updates="${arch_testing}"
arch_stable_proposed_updates="${arch_stable}"

# Miscellaneous
#
admin_email="djpig@debian.org,joey@infodrom.org"
