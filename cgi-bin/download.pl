#!/usr/bin/perl -T
#
# download.pl -- CGI interface for downloading files on packages.debian.org
#
# Copyright (C) 1998 (?) James Treacy
# Copyright (C) 2001 Josip Rodin
# Copyright (C) 2004 Frank Lichtenheld
#
# Licensed under the GPL or something.

use strict;
use warnings;

use CGI ();
use DB_File;
use Benchmark ':hireswallclock';

use lib "../lib";

use Deb::Versions;
use Packages::HTML ();
use Packages::Search qw( :all );
use Packages::Config qw( $HOME $DBDIR @SUITES @ARCHIVES @SECTIONS @ARCHITECTURES );
use Packages::CGI;
use Packages::DB;

&Packages::CGI::reset;

&Packages::Config::init( '../' );
&Packages::DB::init();

# TODO: find a way to get the U.S. mirror list from a more authoritive
# location automatically. might not be overly smart to automatize it
# completely, since I hand pick sites that are up-to-date, fast, and
# have HTTP on a reasonably short URL
#   -- Joy

# hint:
# grep-dctrl -F Site,Alias -e '(udel|bigfoot|kernel|crosslink|internap|cerias|lcs.mit|progeny)' Mirrors.masterlist | timestamps/archive_mirror_check.py
my @north_american_sites = (
	"ftp.us.debian.org/debian",
	"http.us.debian.org/debian",
	"ftp.debian.org/debian",
#	"ftp.ca.debian.org/debian",
	"ftp.egr.msu.edu/debian",
	"mirrors.kernel.org/debian",
	"archive.progeny.com/debian",
	"debian.crosslink.net/debian",
	"ftp-mirror.internap.com/pub/debian",
	"ftp.cerias.purdue.edu/pub/os/debian",
	"ftp.lug.udel.edu/debian",
	"debian.lcs.mit.edu/debian",
	"debian.teleglobe.net",
	"debian.rutgers.edu",
	"debian.oregonstate.edu/debian",
	);
my @european_sites = (
	"ftp.de.debian.org/debian",
	"ftp.at.debian.org/debian",
	"ftp.bg.debian.org/debian",
	"ftp.cz.debian.org/debian",
	"ftp.dk.debian.org/debian",
	"ftp.ee.debian.org/debian",
	"ftp.fi.debian.org/debian",
	"ftp.fr.debian.org/debian",
	"ftp.hr.debian.org/debian",
	"ftp.hu.debian.org/debian",
	"ftp.ie.debian.org/debian",
	"ftp.is.debian.org/debian",
	"ftp.it.debian.org/debian",
	"ftp.nl.debian.org/debian",
	"ftp.no.debian.org/debian",
	"ftp.pl.debian.org/debian",
	"ftp.si.debian.org/debian",
	"ftp.es.debian.org/debian",
	"ftp.se.debian.org/debian",
	"ftp.tr.debian.org/debian",
	"ftp.uk.debian.org/debian",
	);
my @south_american_sites = (
	"ftp.br.debian.org/debian",
	"ftp.cl.debian.org/debian",
	);
my @australian_sites = (
	"ftp.au.debian.org/debian",
	"ftp.wa.au.debian.org/debian",
	"ftp.nz.debian.org/debian",
	);
my @asian_sites = (
	"ftp.jp.debian.org/debian",
#	"ftp.kr.debian.org/debian",
	"linux.csie.nctu.edu.tw/debian",
	"debian.linux.org.tw/debian",
	"linux.cdpa.nsysu.edu.tw/debian",
	); 

my @volatile_european_sites = (
        "volatile.debian.net/debian-volatile",
        "ftp2.de.debian.org/debian-volatile",
        "ftp.sk.debian.org/debian-volatile",
			       );
my @backports_european_sites = (
        "www.backports.org/debian",
	"debian.sil.at/backports.org/",
        "backports.debian.or.at/backports.org",
        "mirror.realroute.net/backports.org",
        "backports.cisbg.com",
        "backports.linuxdediziert.de/backports.org",
        "debian.netcologne.de/debian-backports",
        "ftp.de.debian.org/backports.org",
        "mirror.buildd.net/backports.org",
        "ftp.estpak.ee/backports.org",
        "debian.acantho.net/backports.org",
        "backports.essentkabel.com/backports.org",
        "backports.sipo.nl",
        "ftp.tuke.sk",
			       );
my @backports_asian_sites = (
        "backports.mithril-linux.org",
			     );
my @backports_australian_sites = (
        "mirror.linux.org.au/backports.org",
				  );
my @amd64_european_sites = (
        "amd64.debian.net/debian",
        "ftp.de.debian.org/debian-amd64/debian",
        "bach.hpc2n.umu.se/debian-amd64/debian",
        "bytekeeper.as28747.net/debian-amd64/debian",
	"mirror.switch.ch/debian-amd64/debian",
        "ftp.nl.debian.org/debian-amd64/debian",
			    );
my @amd64_asian_sites = (
        "hanzubon.jp/debian-amd64/debian",
			 );
my @amd64_north_american_sites = (
        "mirror.espri.arizona.edu/debian-amd64/debian",
				  );
my @kfreebsd_north_american_sites = (
	"www.gtlib.gatech.edu/pub/gnuab/debian",
				     );
my @kfreebsd_european_sites = (
        # master site, aka ftp.gnuab.org
        "kfreebsd-gnu.debian.net/debian",
        "ftp.easynet.be/ftp/gnuab/debian",
	"ftp.de.debian.org/debian-kfreebsd",
			       );
my @nonus_north_american_sites = (
#	"ftp.ca.debian.org/debian-non-US",
	"debian.yorku.ca/debian/non-US",
	"mirror.direct.ca/linux/debian-non-US",
	);
my @nonus_european_sites = (
	"non-us.debian.org/debian-non-US",
	"ftp.de.debian.org/debian-non-US",
	"ftp.at.debian.org/debian-non-US",
	"ftp.bg.debian.org/debian-non-US",
	"ftp.cz.debian.org/debian-non-US",
	"ftp.fi.debian.org/debian-non-US",
	"ftp.fr.debian.org/debian-non-US",
	"ftp.hr.debian.org/debian-non-US",
	"ftp.hu.debian.org/debian-non-US",
	"ftp.ie.debian.org/debian-non-US",
	"ftp.is.debian.org/debian-non-US",
	"ftp.it.debian.org/debian-non-US",
	"ftp.nl.debian.org/debian-non-US",
	"ftp.no.debian.org/debian-non-US",
	"ftp.pl.debian.org/debian/non-US",
	"ftp.si.debian.org/debian-non-US",
	"ftp.es.debian.org/debian-non-US",
	"ftp.se.debian.org/debian-non-US",
	"ftp.tr.debian.org/debian-non-US",
	"ftp.uk.debian.org/debian/non-US",
	);
my @nonus_australian_sites = (
	"ftp.au.debian.org/debian-non-US",
	"ftp.wa.au.debian.org/debian-non-US",
	"ftp.nz.debian.org/debian-non-US",
	);
my @nonus_asian_sites = (
	"ftp.jp.debian.org/debian-non-US",
#	"ftp.kr.debian.org/debian-non-US",
	"linux.csie.nctu.edu.tw/debian-non-US",
	"debian.linux.org.tw/debian-non-US",
	"linux.cdpa.nsysu.edu.tw/debian-non-US",
	);
my @nonus_south_american_sites = (
	"ftp.br.debian.org/debian-non-US",
	"ftp.cl.debian.org/debian-non-US",
	);

# list of architectures
my %arches = (
        i386    => 'Intel x86',
        m68k    => 'Motorola 680x0',
        sparc   => 'SPARC',
        alpha   => 'Alpha',
        powerpc => 'PowerPC',
        arm     => 'ARM',
        hppa    => 'HP PA-RISC',
        ia64    => 'Intel IA-64',
        mips    => 'MIPS',
        mipsel  => 'MIPS (DEC)',
        s390    => 'IBM S/390',
	"hurd-i386" => 'Hurd (i386)',
	amd64   => 'AMD64',
	"kfreebsd-i386" => 'GNU/kFreeBSD (i386)'
);

$ENV{PATH} = "/bin:/usr/bin";
# Read in all the variables set by the form
my $input;
if ($ARGV[0] && ($ARGV[0] eq 'php')) {
	$input = new CGI(\*STDIN);
} else {
	$input = new CGI;
}

my $pet0 = new Benchmark;
my $tet0 = new Benchmark;
# use this to disable debugging in production mode completly
my $debug_allowed = 1;
my $debug = $debug_allowed && $input->param("debug");
$debug = 0 if !defined($debug) || $debug !~ /^\d+$/o;
$Packages::CGI::debug = $debug;

if (my $path = $input->param('path')) {
    my @components = map { lc $_ } split /\//, $path;

    my %SUITES = map { $_ => 1 } @SUITES;
    my %ARCHIVES = map { $_ => 1 } @ARCHIVES;
    my %ARCHITECTURES = map { $_ => 1 } @ARCHITECTURES;

    foreach (@components) {
	if ($SUITES{$_}) {
	    $input->param('suite', $_);
	} elsif ($ARCHIVES{$_}) {
	    $input->param('archive', $_);
	} elsif ($ARCHITECTURES{$_}) {
	    $input->param('arch', $_);
	} elsif ($_ eq 'source') {
	    $input->param('source', 1);
	}
    }
}

my ( $pkg, $suite, @sections, $arch, @archives, $format );
my %params_def = ( package => { default => undef, match => '^([a-z0-9.+-]+)$',
				var => \$pkg },
		   suite => { default => undef, match => '^(\w+)$',
			      var => \$suite },
		   archive => { default => 'all', match => '^(\w+)$',
				array => ', ', var => \@archives,
			    replace => { all => [qw(us security non-US)] } },
		   arch => { default => undef, match => '^(\w+)$',
			     var => \$arch },
		   format => { default => 'html', match => '^(\w+)$',
                               var => \$format },
		   );
my %opts;
my %params = Packages::Search::parse_params( $input, \%params_def, \%opts );

#XXX: Don't use alternative output formats yet
$format = 'html';
if ($format eq 'html') {
    print $input->header( -charset => 'utf-8' );
}

if ($params{errors}{package}) {
    fatal_error( "package not valid or not specified" );
    $pkg = '';
}
if ($params{errors}{suite}) {
    fatal_error( "suite not valid or not specified" );
    $suite = '';
}
if ($params{errors}{arch}) {
    fatal_error( "arch not valid or not specified" );
    $arch = '';
}

$opts{h_suites} =   { $suite => 1 };
$opts{h_archs} =    { $arch => 1 };
$opts{h_sections} = { map { $_ => 1 } @SECTIONS };
$opts{h_archives} = { map { $_ => 1 } @archives };

our (%packages_all);
my (@results);
my ($final_result, $file, $filen, $md5sum, @file_components, $archive) = ("")x5;

sub gettext { return $_[0]; };

my $st0 = new Benchmark;
unless (@Packages::CGI::fatal_errors) {
    tie %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db",
    O_RDONLY, 0666, $DB_BTREE
	or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";

    read_entry( \%packages, $pkg, \@results, \%opts );

    unless (@results) {
	fatal_error( "No such package".
		     "{insert link to search page with substring search}" );

    } else {
	my $final_result = shift @results;
	foreach (@results) {
	    if (version_cmp( $_->[7], $final_result->[7] ) > 0) {
		$final_result = $_;
	    }
	}
    
	$archive = $final_result->[1];
	my %data = split /\000/, $packages_all{"$pkg $arch $final_result->[7]"};
	$file = $data{filename};
	@file_components = split('/', $file);
	$filen = pop(@file_components);

	$md5sum = $data{md5sum};
    }
}

my $arch_string = $arch ne 'all' ? "on $arches{$arch} machines" : "";

print Packages::HTML::header( title => "Package Download Selection",
			      lang => "en",
			      print_title_above => 1 );

print_errors();
print_hints();
print_msgs();
print_debug();
print_notes();

if ($file) {
    print "<h2>Download Page for <kbd>$filen</kbd> $arch_string</h2>\n".
	"<p>You can download the requested file from the <tt>";
    print join( '/', @file_components).'/';
    print "</tt> subdirectory at";
    print $archive ne 'security' ? " any of these sites:" : ":";
    print "</p>\n";
    
    if ($archive eq 'security') {
	
	print <<END;
<ul>
    <li><a href="http://security.debian.org/debian-security/$file">security.debian.org/debian-security</a></li>
    </ul>
    
    <p>Debian security updates are currently officially distributed only via
    security.debian.org.</p>
END
;
    } elsif ($arch eq 'amd64') {
	
	print_links( "North America", $file, @amd64_north_american_sites );
	print_links( "Europe", $file, @amd64_european_sites );
#    print_links( "Australia and New Zealand", $file,
#		 @nonus_australian_sites );
	print_links( "Asia", $file, @amd64_asian_sites );
#    print_links( "South America", $file, @nonus_south_american_sites );

	print <<END;
<p>Note that AMD64 is not officialy included in the Debian archive
    yet, but the AMD64 porter group keeps their archive in sync with
    the official archive as close as possible. See the
    <a href="http://www.debian.org/ports/amd64/">AMD64 ports page</a> for
    current information.</p>
END
;
    } elsif ($arch eq 'kfreebsd-i386') {

	print_links( "North America", $file, @kfreebsd_north_american_sites );
	print_links( "Europe", $file, @kfreebsd_european_sites );
#    print_links( "Australia and New Zealand", $file,
#		 @nonus_australian_sites );
#    print_links( "Asia", $file, @amd64_asian_sites );
#    print_links( "South America", $file, @nonus_south_american_sites );
	
	print <<END;
<p>Note that GNU/kFreeBSD is not officialy included in the Debian archive
    yet, but the GNU/kFreeBSD porter group keeps their archive in sync with
    the official archive as close as possible. See the
    <a href="http://www.debian.org/ports/kfreebsd-gnu/">GNU/kFreeBSD ports page</a> for
    current information.</p>
END
;
    } elsif ($archive eq 'non-US') {

	print_links( "North America", $file, @nonus_north_american_sites );
	print_links( "Europe", $file, @nonus_european_sites );
	print_links( "Australia and New Zealand", $file,
		     @nonus_australian_sites );
	print_links( "Asia", $file, @nonus_asian_sites );
	print_links( "South America", $file, @nonus_south_american_sites );
	
	print <<END;
<p>If none of the above sites are fast enough for you, please see our
    <a href="http://www.debian.org/mirror/list-non-US">complete mirror list</a>.</p>
END
;
    } elsif ($archive eq 'backports') {
	
#    print_links( "North America", $file, @nonus_north_american_sites );
	print '<div class="cardleft">';
	print_links( "Europe", $file, @backports_european_sites );
	print '</div><div class="cardright">';
	print_links( "Australia and New Zealand", $file,
		     @backports_australian_sites );
	print_links( "Asia", $file, @backports_asian_sites );
#    print_links( "South America", $file, @nonus_south_american_sites );
	print '</div>';
	
	print <<END;
<p style="clear:both">If none of the above sites are fast enough for you, please see our
    <a href="http://www.backports.org/debian/README.mirrors.html">complete mirror list</a>.</p>
END
;
	} elsif ($archive eq 'volatile') {
	    
#    print_links( "North America", $file, @nonus_north_american_sites );
	    print_links( "Europe", $file, @volatile_european_sites );
#    print_links( "Australia and New Zealand", $file,
#		 @nonus_australian_sites );
#    print_links( "Asia", $file, @nonus_asian_sites );
#    print_links( "South America", $file, @nonus_south_american_sites );

	    print <<END;
<p>If none of the above sites are fast enough for you, please see our
    <a href="http://volatile.debian.net/mirrors.html">complete mirror list</a>.</p>
END
;
	} elsif ($archive eq 'us') {
	    
	    print '<div class="cardleft">';
	    print_links( "North America", $file, @north_american_sites );
	    print '</div><div class="cardright">';
	    print_links( "Europe", $file, @european_sites );
	    print '</div><div class="cardleft">';
	    print_links( "Australia and New Zealand", $file, @australian_sites );
	    print '</div><div class="cardright">';
	    print_links( "Asia", $file, @asian_sites );
	    print '</div><div class="cardleft">';
	    print_links( "South America", $file, @south_american_sites );
	    print '</div>';
	    
	    print <<END;
<p style="clear:both">If none of the above sites are fast enough for you, please see our
    <a href="http://www.debian.org/mirror/list">complete mirror list</a>.</p>
END
;
	}
    
    print <<END;
<p>Note that in some browsers you will need to tell your browser you want
    the file saved to a file. For example, in Netscape or Mozilla, you should
    hold the Shift key when you click on the URL.</p>
END
;
    print "<p>The MD5sum for <tt>$filen</tt> is <strong>$md5sum</strong></p>\n"
	if $md5sum;
}

my $trailer = Packages::HTML::trailer( ".." );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e;
print $trailer;

exit;

sub print_links {
    my ( $title, $file, @servers ) = @_;

    print "<p><em>$title</em></p>";
    print "<ul>";
    foreach (@servers) {
	print "<li><a href=\"http://$_/$file\">$_</a></li>\n";
	# print "<li><a href=\"ftp://$_/$file\">$_</a></li>\n";
    }
    print "</ul>";

}
