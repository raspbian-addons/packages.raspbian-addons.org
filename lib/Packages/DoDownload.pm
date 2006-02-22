package Packages::DoDownload;

use strict;
use warnings;

use CGI ();
use DB_File;
use Benchmark ':hireswallclock';
use Exporter;

use Deb::Versions;
use Packages::I18N::Locale;
use Packages::HTML ();
use Packages::Search qw( :all );
use Packages::Config qw( $HOME $DBDIR @SUITES @ARCHIVES @SECTIONS @ARCHITECTURES $SEARCH_URL );
use Packages::CGI;
use Packages::DB;

our @ISA = qw( Exporter );
our @EXPORT = qw( do_download );

# TODO: find a way to get the U.S. mirror list from a more authoritive
# location automatically. might not be overly smart to automatize it
# completely, since I hand pick sites that are up-to-date, fast, and
# have HTTP on a reasonably short URL
#   -- Joy

# hint:
# grep-dctrl -F Site,Alias -e '(udel|bigfoot|kernel|crosslink|internap|cerias|lcs.mit|progeny)' Mirrors.masterlist | timestamps/archive_mirror_check.py
our @north_american_sites = (
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
our @european_sites = (
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
our @south_american_sites = (
	"ftp.br.debian.org/debian",
	"ftp.cl.debian.org/debian",
	);
our @australian_sites = (
	"ftp.au.debian.org/debian",
	"ftp.wa.au.debian.org/debian",
	"ftp.nz.debian.org/debian",
	);
our @asian_sites = (
	"ftp.jp.debian.org/debian",
#	"ftp.kr.debian.org/debian",
	"linux.csie.nctu.edu.tw/debian",
	"debian.linux.org.tw/debian",
	"linux.cdpa.nsysu.edu.tw/debian",
	); 

our @volatile_european_sites = (
        "volatile.debian.net/debian-volatile",
        "ftp2.de.debian.org/debian-volatile",
        "ftp.sk.debian.org/debian-volatile",
			       );
our @backports_european_sites = (
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
our @backports_asian_sites = (
        "backports.mithril-linux.org",
			     );
our @backports_australian_sites = (
        "mirror.linux.org.au/backports.org",
				  );
our @amd64_european_sites = (
        "amd64.debian.net/debian",
        "ftp.de.debian.org/debian-amd64/debian",
        "bach.hpc2n.umu.se/debian-amd64/debian",
        "bytekeeper.as28747.net/debian-amd64/debian",
	"mirror.switch.ch/debian-amd64/debian",
        "ftp.nl.debian.org/debian-amd64/debian",
			    );
our @amd64_asian_sites = (
        "hanzubon.jp/debian-amd64/debian",
			 );
our @amd64_north_american_sites = (
        "mirror.espri.arizona.edu/debian-amd64/debian",
				  );
our @kfreebsd_north_american_sites = (
	"www.gtlib.gatech.edu/pub/gnuab/debian",
				     );
our @kfreebsd_european_sites = (
        # master site, aka ftp.gnuab.org
        "kfreebsd-gnu.debian.net/debian",
        "ftp.easynet.be/ftp/gnuab/debian",
	"ftp.de.debian.org/debian-kfreebsd",
			       );
our @nonus_north_american_sites = (
#	"ftp.ca.debian.org/debian-non-US",
	"debian.yorku.ca/debian/non-US",
	"mirror.direct.ca/linux/debian-non-US",
	);
our @nonus_european_sites = (
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
our @nonus_australian_sites = (
	"ftp.au.debian.org/debian-non-US",
	"ftp.wa.au.debian.org/debian-non-US",
	"ftp.nz.debian.org/debian-non-US",
	);
our @nonus_asian_sites = (
	"ftp.jp.debian.org/debian-non-US",
#	"ftp.kr.debian.org/debian-non-US",
	"linux.csie.nctu.edu.tw/debian-non-US",
	"debian.linux.org.tw/debian-non-US",
	"linux.cdpa.nsysu.edu.tw/debian-non-US",
	);
our @nonus_south_american_sites = (
	"ftp.br.debian.org/debian-non-US",
	"ftp.cl.debian.org/debian-non-US",
	);

# list of architectures
our %arches = (
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

sub do_download {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{package}) {
	fatal_error( _g( "package not valid or not specified" ) );
    }
    if ($params->{errors}{suite}) {
	fatal_error( _g( "suite not valid or not specified" ) );
    }
    if ($params->{errors}{arch}) {
	fatal_error( _g( "architecture not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( sprintf( _g( "more than one suite specified for download (%s)" ), "@{$opts->{suite}}" ) );
    }
    if (@{$opts->{arch}} > 1) {
	fatal_error( sprintf( _g( "more than one architecture specified for download (%s)" ), "@{$opts->{arch}}" ) );
    }

    $opts->{h_sections} = { map { $_ => 1 } @SECTIONS };
    my $pkg = $opts->{package};
    my $suite = $opts->{suite}[0];
    my $arch = $opts->{arch}[0] ||'';

    our (%packages_all);
    my (@results);
    my ($final_result, $file, $filen, $md5sum, @file_components, $archive) = ("")x5;

    my $st0 = new Benchmark;
    unless (@Packages::CGI::fatal_errors) {
	tie %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";
	
	read_entry( \%packages, $pkg, \@results, $opts );

	unless (@results) {
	    fatal_error( _g( "No such package." )."<br>".
			 sprintf( _g( '<a href="%s">Search for the package</a>' ), "$SEARCH_URL/$pkg" ) );
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

    %$html_header = ( title => _g( "Package Download Selection" ),
		      lang => $opts->{lang},
		      print_title => 1 );

    if ($file) {
	if ($arch ne 'all') {
	    $$page_content .= '<h2>'.sprintf( _g('Download Page for <kbd>%s</kbd> on %s machines'), $filen, $arches{$arch} ).'</h2>';
	} else {
	    $$page_content .= '<h2>'.sprintf( _g('Download Page for <kbd>%s</kbd>'), $filen ).'</h2>';
	}
	my $directory = join( '/', @file_components).'/';
	if ($archive ne 'security' ) {
	    $$page_content .= "<p>".sprintf( _g( 'You can download the requested file from the <tt>%s</tt> subdirectory at any of these sites:' ), $directory )."</p>\n";
	} else {
	    $$page_content .= "<p>".sprintf( _g( 'You can download the requested file from the <tt>%s</tt> subdirectory at:' ), $directory )."</p>\n";
	}
	
	if ($archive eq 'security') {
	    
	    $$page_content .= "<ul><li><a href=\"http://security.debian.org/debian-security/$file\">security.debian.org/debian-security</a></li></ul>";
	    $$page_content .= '<p>'._g( 'Debian security updates are currently officially distributed only via <tt>security.debian.org</tt>.' ).'</p>';
	} elsif ($arch eq 'amd64') {

	    $$page_content .= print_links( _g( "North America" ), $file, @amd64_north_american_sites );
	    $$page_content .= print_links( _g( "Europe" ), $file, @amd64_european_sites );
#    $$page_content .= print_links( "Australia and New Zealand", $file,
#		 @nonus_australian_sites );
	    $$page_content .= print_links( _g( "Asia" ), $file, @amd64_asian_sites );
#    $$page_content .= print_links( "South America", $file, @nonus_south_american_sites );

	    $$page_content .= '<p>'._g( 'Note that AMD64 is not officialy included in the Debian archive yet, but the AMD64 porter group keeps their archive in sync with the official archive as close as possible. See the <a href="http://www.debian.org/ports/amd64/">AMD64 ports page</a> for current information.' ).'</p>';
	} elsif ($arch eq 'kfreebsd-i386') {

	    $$page_content .= print_links( _g( "North America" ), $file, @kfreebsd_north_american_sites );
	    $$page_content .= print_links( _g( "Europe" ), $file, @kfreebsd_european_sites );
#    $$page_content .= print_links( "Australia and New Zealand", $file,
#		 @nonus_australian_sites );
#    $$page_content .= print_links( "Asia", $file, @amd64_asian_sites );
#    $$page_content .= print_links( "South America", $file, @nonus_south_american_sites );
	
	    $$page_content .= '<p>'._g( 'Note that GNU/kFreeBSD is not officialy included in the Debian archive yet, but the GNU/kFreeBSD porter group keeps their archive in sync with the official archive as close as possible. See the <a href="http://www.debian.org/ports/kfreebsd-gnu/">GNU/kFreeBSD ports page</a> for current information.' ).'</p>';
	} elsif ($archive eq 'non-US') {

	    $$page_content .= print_links( _g( "North America" ), $file, @nonus_north_american_sites );
	    $$page_content .= print_links( _g( "Europe" ), $file, @nonus_european_sites );
	    $$page_content .= print_links( _g( "Australia and New Zealand" ), $file,
					   @nonus_australian_sites );
	    $$page_content .= print_links( _g( "Asia" ), $file, @nonus_asian_sites );
	    $$page_content .= print_links( _g( "South America" ), $file, @nonus_south_american_sites );
	    
	    $$page_content .= '<p>'.sprintf( _g('If none of the above sites are fast enough for you, please see our <a href="%s">complete mirror list</a>.' ), 'http://www.debian.org/mirror/list-non-US' ).'</p>';
	} elsif ($archive eq 'backports') {
	
#    $$page_content .= print_links( "North America", $file, @nonus_north_american_sites );
	    $$page_content .= '<div class="cardleft">';
	    $$page_content .= print_links( _g( "Europe" ), $file, @backports_european_sites );
	    $$page_content .= '</div><div class="cardright">';
	    $$page_content .= print_links( _g( "Australia and New Zealand" ), $file,
					   @backports_australian_sites );
	    $$page_content .= print_links( _g( "Asia" ), $file, @backports_asian_sites );
#    $$page_content .= print_links( "South America", $file, @nonus_south_american_sites );
	    $$page_content .= '</div>';
	    
	    $$page_content .= '<p style="clear:both">'.sprintf( _g( 'If none of the above sites are fast enough for you, please see our <a href="%s">complete mirror list</a>.'), 'http://www.backports.org/debian/README.mirrors.html' ).'</p>';
	} elsif ($archive eq 'volatile') {
	    
#    $$page_content .= print_links( "North America", $file, @nonus_north_american_sites );
	    $$page_content .= print_links( _g( "Europe" ), $file, @volatile_european_sites );
#    $$page_content .= print_links( "Australia and New Zealand", $file,
#		 @nonus_australian_sites );
#    $$page_content .= print_links( "Asia", $file, @nonus_asian_sites );
#    $$page_content .= print_links( "South America", $file, @nonus_south_american_sites );

	    $$page_content .= '<p>'.sprintf( _g( 'If none of the above sites are fast enough for you, please see our <a href="%s">complete mirror list</a>.' ), 'http://volatile.debian.net/mirrors.html' ).'</p>';
	} elsif ($archive eq 'us') {
	    
	    $$page_content .= '<div class="cardleft">';
	    $$page_content .= print_links( _g( "North America" ), $file, @north_american_sites );
	    $$page_content .= '</div><div class="cardright">';
	    $$page_content .= print_links( _g( "Europe" ), $file, @european_sites );
	    $$page_content .= '</div><div class="cardleft">';
	    $$page_content .= print_links( _g( "Australia and New Zealand" ), $file, @australian_sites );
	    $$page_content .= '</div><div class="cardright">';
	    $$page_content .= print_links( _g( "Asia" ), $file, @asian_sites );
	    $$page_content .= '</div><div class="cardleft">';
	    $$page_content .= print_links( _g( "South America" ), $file, @south_american_sites );
	    $$page_content .= '</div>';
	    
	    $$page_content .= '<p style="clear:both">'.sprintf( _g( 'If none of the above sites are fast enough for you, please see our <a href="%s">complete mirror list</a>.' ), 'http://www.debian.org/mirror/list' ).'</p>';
	}
    
    $$page_content .= '<p>'._g( 'Note that in some browsers you will need to tell your browser you want the file saved to a file. For example, in Firefox or Mozilla, you should hold the Shift key when you click on the URL.' ).'</p>';
    $$page_content .= "<p>".sprintf( _g( 'The MD5sum for <tt>%s</tt> is <strong>%s</strong>' ), $filen, $md5sum ).'</p>'
	if $md5sum;
    }
}

sub print_links {
    my ( $title, $file, @servers ) = @_;

    my $str = "<p><em>$title</em></p>";
    $str .= "<ul>";
    foreach (@servers) {
	$str .= "<li><a href=\"http://$_/$file\">$_</a></li>\n";
	# $str .= "<li><a href=\"ftp://$_/$file\">$_</a></li>\n";
    }
    $str .= "</ul>";

    return $str;
}

1;
