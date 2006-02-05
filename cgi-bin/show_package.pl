#!/usr/bin/perl -wT
# $Id$
# show_package.pl -- CGI interface to show info about a package
#
# Copyright (C) 1998 James Treacy
# Copyright (C) 2000, 2001 Josip Rodin
# Copyright (C) 2001 Adam Heath
# Copyright (C) 2004 Martin Schulze
# Copyright (C) 2004-2006 Frank Lichtenheld
# Copyright (C) 2006 Jeroen van Wolffelaar
#
# use is allowed under the terms of the GNU Public License (GPL)                              
# see http://www.fsf.org/copyleft/gpl.html for a copy of the license

use strict;
use CGI qw( -oldstyle_urls );
use CGI::Carp qw( fatalsToBrowser );
use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark;

use Deb::Versions;
use Packages::CGI;
use Packages::Search qw( :all );
use Packages::HTML;
use Packages::Page ();

&Packages::CGI::reset;

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

# read the configuration
our $config_read_time ||= 0;
our $db_read_time ||= 0;
our ( $topdir, $ROOT, @SUITES, @SECTIONS, @ARCHIVES, @ARCHITECTURES,
      %FTP_SITES );

# FIXME: move to own module
my $modtime = (stat( "../config.sh" ))[9];
if ($modtime > $config_read_time) {
    if (!open (C, '<', "../config.sh")) {
	error( "Internal: Cannot open configuration file." );
    }
    while (<C>) {
	next if /^\s*\#/o;
	chomp;
	$topdir = $1 if /^\s*topdir="?([^\"]*)"?\s*$/o;
	$ROOT = $1 if /^\s*root="?([^\"]*)"?\s*$/o;
	$Packages::HTML::HOME = $1 if /^\s*home="?([^\"]*)"?\s*$/o;
	$Packages::HTML::SEARCH_CGI = $1 if /^\s*searchcgi="?([^\"]*)"?\s*$/o;
	$Packages::HTML::SEARCH_PAGE = $1 if /^\s*searchpage="?([^\"]*)"?\s*$/o;
	$Packages::HTML::WEBMASTER_MAIL = $1 if /^\s*webmaster="?([^\"]*)"?\s*$/o;
	$Packages::HTML::CONTACT_MAIL = $1 if /^\s*contact="?([^\"]*)"?\s*$/o;
	$Packages::HTML::BUG_URL = $1 if /^\s*bug_url="?([^\"]*)"?\s*$/o;
	$Packages::HTML::SRC_BUG_URL = $1 if /^\s*src_bug_url="?([^\"]*)"?\s*$/o;
	$Packages::HTML::QA_URL = $1 if /^\s*qa_url="?([^\"]*)"?\s*$/o;
	$FTP_SITES{us} = $1 if /^\s*ftpsite="?([^\"]*)"?\s*$/o;
	$FTP_SITES{$1} = $2 if /^\s*(\w+)_ftpsite="?([^\"]*)"?\s*$/o;
	@SUITES = split(/\s+/, $1) if /^\s*suites="?([^\"]*)"?\s*$/o;
	@SECTIONS = split(/\s+/, $1) if /^\s*sections="?([^\"]*)"?\s*$/o;
	@ARCHIVES = split(/\s+/, $1) if /^\s*archives="?([^\"]*)"?\s*$/o;
	@ARCHITECTURES = split(/\s+/, $1) if /^\s*architectures="?([^\"]*)"?\s*$/o;
    }
    close (C);
    debug( "read config ($modtime > $config_read_time)" );
    $config_read_time = $modtime;
}
my $DBDIR = $topdir . "/files/db";
my $thisscript = $Packages::HTML::SEARCH_CGI;

if (my $path = $input->param('path')) {
    my @components = map { lc $_ } split /\//, $path;

    my %SUITES = map { $_ => 1 } @SUITES;
    my %SECTIONS = map { $_ => 1 } @SECTIONS;
    my %ARCHIVES = map { $_ => 1 } @ARCHIVES;
    my %ARCHITECTURES = map { $_ => 1 } @ARCHITECTURES;

    foreach (@components) {
	if ($SUITES{$_}) {
	    $input->param('suite', $_);
	} elsif ($SECTIONS{$_}) {
	    $input->param('section', $_);
	} elsif ($ARCHIVES{$_}) {
	    $input->param('archive', $_);
	} elsif ($ARCHITECTURES{$_}) {
	    $input->param('arch', $_);
	}
    }
}

my ( $pkg, $suite, $format );
my %params_def = ( package => { default => undef, match => '^([a-z0-9.+-]+)$',
				var => \$pkg },
		   suite => { default => undef, match => '^(\w+)$',
			      var => \$suite },
		   format => { default => 'html', match => '^(\w+)$',
                               var => \$format }
		   );
my %opts;
my %params = Packages::Search::parse_params( $input, \%params_def, \%opts );

$opts{h_suites} =   { $suite => 1 };
$opts{h_archs} =    { map { $_ => 1 } @ARCHITECTURES };
$opts{h_sections} = { map { $_ => 1 } @SECTIONS };
$opts{h_archives} = { map { $_ => 1 } @ARCHIVES };

#XXX: Don't use alternative output formats yet
$format = 'html';
if ($format eq 'html') {
    print $input->header;
}

if ($params{errors}{package}) {
    fatal_error( "package not valid or not specified" );
}
if ($params{errors}{suite}) {
    fatal_error( "suite not valid or not specified" );
}

my $DL_URL = "$pkg/download";
my $FILELIST_URL = "$pkg/files";
my $DDPO_URL = "http://qa.debian.org/developer.php?email=";

our (%packages, %packages_all, %sources_all, %descriptions);
my (@results, @non_results);
my $page = new Packages::Page( $pkg );
my $package_page = "";
my ($short_desc, $version, $archive, $section, $subsection) = ("")x5;

sub gettext { return $_[0]; };

my $st0 = new Benchmark;
unless (@Packages::CGI::fatal_errors) {
    my $dbmodtime = (stat("$DBDIR/packages_small.db"))[9];
    if ($dbmodtime > $db_read_time) {
	tie %packages, 'DB_File', "$DBDIR/packages_small.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_small.db: $!";
	tie %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";
	tie %sources_all, 'DB_File', "$DBDIR/sources_all_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/sources_all_$suite.db: $!";
	tie %descriptions, 'DB_File', "$DBDIR/descriptions.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/descriptions.db: $!";

    	debug( "tied databases ($dbmodtime > $db_read_time)" );
	$db_read_time = $dbmodtime;
    }

    read_entry_all( \%packages, $pkg, \@results, \@non_results, \%opts );

    unless (@results || @non_results ) {
	fatal_error( "No such package".
		     "{insert link to search page with substring search}" );
    } else {
	unless (@results) {
	    fatal_error( "Package not available in this suite" );
	} else {
	    for my $entry (@results) {
		debug( join(":", @$entry), 1 );
		my (undef, $archive, undef, $arch, $section, $subsection,
		    $priority, $version) = @$entry;
		
		my $data = $packages_all{"$pkg $arch $version"};
		$page->merge_data($pkg, $version, $arch, $data) or debug( "Merging $pkg $arch $version FAILED", 2 );
	    }

	    $version = $page->{newest};
	    my $source = $page->get_newest( 'source' );
	    my $source_version = $page->get_newest( 'source-version' )
		|| $version;
	    my $src_data = $sources_all{"$source $source_version"};
	    unless ($src_data) { #fucking binNMUs
		my $versions = $page->get_versions;
		my $sources = $page->get_arch_field( 'source' );
		my $source_versions = $page->get_arch_field( 'source-version' );
		foreach (version_sort keys %$versions) {
		    $source = $sources->{$versions->{$_}[0]};
		    $source = $source_versions->{$versions->{$_}[0]}
		    || $version;
		    $src_data = $sources_all{"$source $source_version"};
		    last if $src_data;
		}
		error( "couldn't find source package" ) unless $src_data;
	    }
	    $page->add_src_data( $source, $source_version, $src_data );

	    my $st1 = new Benchmark;
	    my $std = timediff($st1, $st0);
	    debug( "Data search and merging took ".timestr($std) );

	    my $encodedpkg = uri_escape( $pkg );
	    my ($v_str, $v_str_arch, $v_str_arr) = $page->get_version_string();
	    my $did = $page->get_newest( 'description' );
	    $archive = $page->get_newest( 'archive' );
	    $section = $page->get_newest( 'section' );
	    $subsection = $page->get_newest( 'subsection' );
	    my $filenames = $page->get_arch_field( 'filename' );
	    my $file_md5sums = $page->get_arch_field( 'md5sum' );
	    my $archives = $page->get_arch_field( 'archive' );
	    my $sizes_inst = $page->get_arch_field( 'installed-size' );
	    my $sizes_deb = $page->get_arch_field( 'size' );
	    my @archs = sort $page->get_architectures;

	    # process description
 	    #
	    my $desc = $descriptions{$did};
	    $short_desc = encode_entities( $1, "<>&\"" )
		if $desc =~ s/^(.*)$//m;
	    my $long_desc = encode_entities( $desc, "<>&\"" );
	    
	    $long_desc =~ s,((ftp|http|https)://[\S~-]+?/?)((\&gt\;)?[)]?[']?[:.\,]?(\s|$)),<a href=\"$1\">$1</a>$3,go; # syntax highlighting -> '];
 	    $long_desc =~ s/\A //o;
 	    $long_desc =~ s/\n /\n/sgo;
 	    $long_desc =~ s/\n.\n/\n<p>\n/go;
 	    $long_desc =~ s/(((\n|\A) [^\n]*)+)/\n<pre>$1\n<\/pre>/sgo;
# 	    $long_desc = conv_desc( $lang, $long_desc );
# 	    $short_desc = conv_desc( $lang, $short_desc );

	    my %all_suites = map { $_->[2] => 1 } (@results, @non_results);
	    foreach (suites_sort(keys %all_suites)) {
		if ($suite eq $_) {
		    $package_page .= "[ <strong>$_</strong> ] ";
		} else {
		    $package_page .=
			"[ <a href=\"../$_/".uri_escape($pkg)."\">$_</a> ] ";
		}
	    }

 	    $package_page .= simple_menu( [ gettext( "Distribution:" ),
 					    gettext( "Overview over this suite" ),
 					    "/$suite/",
 					    $suite ],
 					  [ gettext( "Section:" ),
 					    gettext( "All packages in this section" ),
 					    "/$suite/$subsection/",
 					    $subsection ],
 					  );

 	    my $title .= sprintf( gettext( "Package: %s (%s)" ), $pkg, $v_str );
 	    $title .=  " ".marker( $archive ) if $archive ne 'us';
 	    $title .=  " ".marker( $section ) if $section ne 'main';
 	    $package_page .= title( $title );
	    
 	    $package_page .= "<h2>".gettext( "Versions:" )." $v_str_arch</h2>\n" 
 		unless $version eq $v_str;
	    
 	    if ($suite eq "experimental") {
 		$package_page .= note( gettext( "Experimental package"),
 				       gettext( "Warning: This package is from the <span class=\"pred\">experimental</span> distribution. That means it is likely unstable or buggy, and it may even cause data loss. If you ignore this warning and install it nevertheless, you do it on your own risk.")."</p><p>".
 				       gettext( "Users of experimental packages are encouraged to contact the package maintainers directly in case of problems." )
 				       );
 	    }
 	    if ($subsection eq "debian-installer") {
 		note( gettext( "debian-installer udeb package"),
		      gettext( "Warning: This package is intended for the use in building <a href=\"http://www.debian.org/devel/debian-installer\">debian-installer</a> images only. Do not install it on a normal Debian system." )
		      );
 	    }
 	    $package_page .= pdesc( $short_desc, $long_desc );

 	    #
 	    # display dependencies
 	    #
	    my $dep_list;
 	    $dep_list = print_deps( \%packages, \%opts, $pkg,
				       $page->get_dep_field('depends'),
				       'depends' );
 	    $dep_list .= print_deps( \%packages, \%opts, $pkg,
				       $page->get_dep_field('recommends'),
				       'recommends' );
 	    $dep_list .= print_deps( \%packages, \%opts, $pkg,
				       $page->get_dep_field('suggests'),
				       'suggests' );

 	    if ( $dep_list ) {
 		$package_page .= "<div id=\"pdeps\">\n";
 		$package_page .= sprintf( "<h2>".gettext( "Other Packages Related to %s" )."</h2>\n", $pkg );
 		if ($suite eq "experimental") {
 		    note( gettext( "Note that the \"<span class=\"pred\">experimental</span>\" distribution is not self-contained; missing dependencies are likely found in the \"<a href=\"/unstable/\">unstable</a>\" distribution." ) );
 		}
		
 		$package_page .= pdeplegend( [ 'dep',  gettext( 'depends' ) ],
 					     [ 'rec',  gettext( 'recommends' ) ],
 					     [ 'sug',  gettext( 'suggests' ) ], );
		
 		$package_page .= $dep_list;
		$package_page .= "</div> <!-- end pdeps -->\n";
	    }

	    #
	    # Download package
	    #
	    my $encodedpack = uri_escape( $pkg );
	    $package_page .= "<div id=\"pdownload\">";
	    $package_page .= sprintf( "<h2>".gettext( "Download %s\n" )."</h2>",
				      $pkg ) ;
	    $package_page .= "<table border=\"1\" summary=\"".gettext("The download table links to the download of the package and a file overview. In addition it gives information about the package size and the installed size.")."\">\n";
	    $package_page .= "<caption class=\"hidecss\">".gettext("Download for all available architectures")."</caption>\n";
	    $package_page .= "<tr>\n";
	    $package_page .= "<th>".gettext("Architecture")."</th><th>".gettext("Files")."</th><th>".gettext( "Package Size")."</th><th>".gettext("Installed Size")."</th></tr>\n";
	    foreach my $a ( @archs ) {
		$package_page .= "<tr>\n";
		$package_page .=  "<th><a href=\"$DL_URL?arch=$a";
		$package_page .=  "&amp;file=".uri_escape($filenames->{$a});
		$package_page .=  "&amp;md5sum=$file_md5sums->{$a}";
		$package_page .=  "&amp;arch=$a";
		# there was at least one package with two
		# different source packages on different
		# archs where one had a security update
		# and the other one not
		for ($archives->{$a}) {
		    /security/o &&  do {
			$package_page .=  "&amp;type=security"; last };
		    /volatile/o &&  do {
			$package_page .=  "&amp;type=volatile"; last };
		    /non-us/io  &&  do {
			$package_page .=  "&amp;type=nonus"; last };
		    $package_page .=  "&amp;type=main";
		}
		$package_page .=  "\">$a</a></th>\n";
		$package_page .= "<td>";
		if ( $suite ne "experimental" ) {
		    $package_page .= sprintf( "[<a href=\"%s\">".gettext( "list of files" )."</a>]\n", "$FILELIST_URL$encodedpkg&amp;version=$suite&amp;arch=$a", $pkg );
		} else {
		    $package_page .= gettext( "no current information" );
		}
		$package_page .= "</td>\n<td>";
		$package_page .=  floor(($sizes_deb->{$a}/102.4)+0.5)/10;
		$package_page .= "</td>\n<td>";
		$package_page .=  $sizes_inst->{$a};
		$package_page .= "</td>\n</tr>";
	    }
	    $package_page .= "</table><p>".gettext ( "Size is measured in kBytes." )."</p>\n";
	    $package_page .= "</div> <!-- end pdownload -->\n";
	    
	    #
	    # more information
	    #
	    $package_page .= pmoreinfo( name => $pkg, data => $page,
					env => \%FTP_SITES,
					bugreports => 1, sourcedownload => 1,
					changesandcopy => 1, maintainers => 1,
					search => 1 );
	}
    }
}

use Data::Dumper;
debug( "Final page object:\n".Dumper($page), 3 );

print Packages::HTML::header( title => "Details of package <em>$pkg</em> in $suite" ,
			      lang => 'en',
			      desc => $short_desc,
			      keywords => "$suite, $archive, $section, $subsection, $version",
			      title_tag => "Details of package $pkg in $suite",
			      );

print_errors();
print_hints();
print_msgs();
print_debug();
print_notes();

unless (@Packages::CGI::fatal_errors) {
    print $package_page;
}
my $tet1 = new Benchmark;
my $tetd = timediff($tet1, $tet0);
print "Total page evaluation took ".timestr($tetd)."<br>"
    if $debug_allowed;

my $trailer = Packages::HTML::trailer( $ROOT );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e; #FIXME
print $trailer;

# vim: ts=8 sw=4
