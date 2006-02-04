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
use Packages::HTML ();
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
our ( $topdir, $ROOT, @SUITES, @SECTIONS, @ARCHIVES, @ARCHITECTURES );

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
	}# elsif ($SECTIONS{$_}) {
#	    $input->param('section', $_);
#	} elsif ($ARCHIVES{$_}) {
#	    $input->param('archive', $_);
#	} elsif ($ARCHITECTURES{$_}) {
#	    $input->param('arch', $_);
#	}
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

our (%packages, %packages_all);
my (@results, @non_results);

unless (@Packages::CGI::fatal_errors) {
    my $dbmodtime = (stat("$DBDIR/packages_small.db"))[9];
    if ($dbmodtime > $db_read_time) {
	tie %packages, 'DB_File', "$DBDIR/packages_small.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_small.db: $!";
	tie %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";
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
	}
    }
}

print Packages::HTML::header( title => "Details of package <em>$pkg</em> in $suite" ,
			      lang => 'en',
			      title_tag => "Details of package $pkg in $suite",
			      print_title_above => 1
			      );

print_errors();
print_hints();
print_msgs();
print_debug();

unless (@Packages::CGI::fatal_errors) {

my %all_suites = map { $_->[2] => 1 } (@results, @non_results);
    foreach (suites_sort(keys %all_suites)) {
	if ($suite eq $_) {
	    print "<strong>$_</strong> | ";
	} else {
	    print "<a href=\"../$_/".uri_escape($pkg)."\">$_</a> | ";
	}
    }
    print "<br>";
    
my $page = new Packages::Page( $pkg );

    for my $entry (@results) {
	print join ":", @$entry;
	print "<br>\n";
	my (undef, $archive, undef, $arch, $section, $subsection,
	    $priority, $version) = @$entry;
	print "<pre>".$packages_all{"$pkg $arch $version"}."</pre>";
    }
	
# 	my %versions = $pkg->get_arch_versions( $env->{archs} );
# 	my %subsuites   = $pkg->get_arch_fields( 'subdistribution', 
# 						 $env->{archs} );
# 	my %filenames   = $pkg->get_arch_fields( 'filename',
# 						 $env->{archs} );
# 	my %file_md5s   = $pkg->get_arch_fields( 'md5sum',
# 						 $env->{archs} );
	
# 	my $subsuite_kw = $d->{subsuite} || $env->{distribution};
# 	my $size_kw = exists $d->{sizes_deb}{i386} ? $d->{sizes_deb}{i386} : first_val($d->{sizes_deb});
	
	
# 	foreach my $lang (@{$env->{langs}}) {
# 	    &Generated::Strings::string_lang($lang);
	    
# 	    my $dirname = "$env->{dest_dir}/$d->{subsection}";
# 	    my $filename = "$dirname/$name.$lang.html";
	    
# 	    unless (( $lang eq 'en' ) 
# 		    || $env->{db}->is_translated( $name, $d->{version},
# 						  ${$versions{v2a}{$d->{version}}}[0],
# 						  $lang )) {
# 		next;
# 	    }
# 	    progress() if $env->{opts}{progress};
	    
# 	    #
# 	    # process description
# 	    #
# 	    my $short_desc = encode_entities( $env->{db}->get_short_desc( $d->{desc_md5},
# 									  $lang ), "<>&\"" );
# 	    my $long_desc = encode_entities( $env->{db}->get_long_desc( $d->{desc_md5},
# 									$lang ), "<>&\"" );
	    
# 	    $long_desc =~ s,((ftp|http|https)://[\S~-]+?/?)((\&gt\;)?[)]?[']?[:.\,]?(\s|$)),<a href=\"$1\">$1</a>$3,go; # syntax highlighting -> '];
# 	    $long_desc =~ s/\A //o;
# 	    $long_desc =~ s/\n /\n/sgo;
# 	    $long_desc =~ s/\n.\n/\n<p>\n/go;
# 	    $long_desc =~ s/(((\n|\A) [^\n]*)+)/\n<pre>$1\n<\/pre>/sgo;
	    
# 	    $long_desc = conv_desc( $lang, $long_desc );
# 	    $short_desc = conv_desc( $lang, $short_desc );
	    
# 	    #
# 	    # begin output
# 	    #
# 	    my $package_page = header( title => $name, lang => $lang,
# 				       desc => $short_desc,
# 				       keywords => "$env->{distribution}, $subsuite_kw, $d->{section}, $d->{subsection}, size:$size_kw $d->{version}" );
# 	    $package_page .= simple_menu( [ gettext( "Distribution:" ),
# 					    gettext( "Overview over this distribution" ),
# 					    "../",
# 					    $env->{distribution} ],
# 					  [ gettext( "Section:" ),
# 					    gettext( "All packages in this section" ),
# 					    "../$d->{subsection}/",
# 					    $d->{subsection} ],
# 					  );
	    
# 	    my $title .= sprintf( gettext( "Package: %s (%s)" ), $name, $d->{v_str_simple} );
# 	    $title .=  " ".marker( $d->{subsuite} ) if $d->{subsuite};
# 	    $title .=  " ".marker( $d->{section} ) if $d->{section} ne 'main';
# 	    $package_page .= title( $title );
	    
# 	    $package_page .= "<h2>".gettext( "Versions:" )." $d->{v_str_arch}</h2>\n" 
# 		unless $d->{version} eq $d->{v_str_simple};
	    
# 	    if ($env->{distribution} eq "experimental") {
# 		$package_page .= note( gettext( "Experimental package"),
# 				       gettext( "Warning: This package is from the <span class=\"pred\">experimental</span> distribution. That means it is likely unstable or buggy, and it may even cause data loss. If you ignore this warning and install it nevertheless, you do it on your own risk.")."</p><p>".
# 				       gettext( "Users of experimental packages are encouraged to contact the package maintainers directly in case of problems." )
# 				       );
# 	    }
# 	    if ($d->{section} eq "debian-installer") {
# 		$package_page .= note( gettext( "debian-installer udeb package"),
# 				       gettext( "Warning: This package is intended for the use in building <a href=\"http://www.debian.org/devel/debian-installer\">debian-installer</a> images only. Do not install it on a normal Debian system." )
# 				       );
# 	    }
# 	    $package_page .= pdesc( $short_desc, $long_desc );
	    
# 	    #
# 	    # display dependencies
# 	    #
# 	    my $dep_list = print_deps( $env, $lang, $pkg, $d->{depends},    'depends' );
# 	    $dep_list   .= print_deps( $env, $lang, $pkg, $d->{recommends}, 'recommends' );
# 	    $dep_list   .= print_deps( $env, $lang, $pkg, $d->{suggests},   'suggests' );
	    
# 	    if ( $dep_list ) {
# 		$package_page .= "<div id=\"pdeps\">\n";
# 		$package_page .= sprintf( "<h2>".gettext( "Other Packages Related to %s" )."</h2>\n", $name );
# 		if ($env->{distribution} eq "experimental") {
# 		    $package_page .= note( gettext( "Note that the \"<span class=\"pred\">experimental</span>\" distribution is not self-contained; missing dependencies are likely found in the \"<a href=\"../../unstable/\">unstable</a>\" distribution." ) );
# 		}
		
# 		$package_page .= pdeplegend( [ 'dep',  gettext( 'depends' ) ],
# 					     [ 'rec',  gettext( 'recommends' ) ],
# 					     [ 'sug',  gettext( 'suggests' ) ], );
		
# 		$package_page .= $dep_list;
# 		$package_page .= "</div> <!-- end pdeps -->\n";
# 	    }
	    
# 	    #
# 	    # Download package
# 	    #
# 	    my $encodedpack = uri_escape( $name );
# 	    $package_page .= "<div id=\"pdownload\">";
# 	    $package_page .= sprintf( "<h2>".gettext( "Download %s\n" )."</h2>",
# 				      $name ) ;
# 	    $package_page .= "<table border=\"1\" summary=\"".gettext("The download table links to the download of the package and a file overview. In addition it gives information about the package size and the installed size.")."\">\n";
# 	    $package_page .= "<caption class=\"hidecss\">".gettext("Download for all available architectures")."</caption>\n";
# 	    $package_page .= "<tr>\n";
# 	    $package_page .= "<th>".gettext("Architecture")."</th><th>".gettext("Files")."</th><th>".gettext( "Package Size")."</th><th>".gettext("Installed Size")."</th></tr>\n";
# 	    foreach my $a ( @all_archs ) {
# 		if ( exists $versions{a2v}{$a} ) {
# 		    $package_page .= "<tr>\n";
# 		    $package_page .=  "<th><a href=\"$DL_URL?arch=$a";
# 		    # \&amp\;file=\" method=\"post\">\n<p>";
# 		    $package_page .=  "&amp;file=".uri_escape($filenames{a2f}->{$a});
# 		    $package_page .=  "&amp;md5sum=$file_md5s{a2f}->{$a}";
# 		    $package_page .=  "&amp;arch=$a";
# 		    # there was at least one package with two
# 		    # different source packages on different
# 		    # archs where one had a security update
# 		    # and the other one not
# 		    if ($subsuites{a2f}{$a}
# 			&& ($subsuites{a2f}{$a} =~ /security/o) ) {
# 			$package_page .=  "&amp;type=security";
# 		    } elsif ($subsuites{a2f}{$a}
# 			     && ($subsuites{a2f}{$a} =~ /volatile/o) ) {
# 			$package_page .=  "&amp;type=volatile";
# 		    } elsif ($d->{is_nonus}) {
# 			$package_page .=  "&amp;type=nonus";
# 		    } else {
# 			$package_page .=  "&amp;type=main";
# 		    }
# 		    $package_page .=  "\">$a</a></th>\n";
# 		    $package_page .= "<td>";
# 		    if ( $env->{distribution} ne "experimental" ) {
# 			$package_page .= sprintf( "[<a href=\"%s\">".gettext( "list of files" )."</a>]\n", "$FILELIST_URL$encodedpack&amp;version=$env->{distribution}&amp;arch=$a", $name );
# 		    } else {
# 			$package_page .= "no files";
# 		    }
# 		    $package_page .= "</td>\n<td>";
# 		    my $size = $d->{sizes_deb}{$a};
# 		    $package_page .=  "$size";
# 		    $package_page .= "</td>\n<td>";
# 		    my $inst_size = $d->{sizes_inst}{$a};
# 		    $package_page .=  "$inst_size";
# 		    $package_page .= "</td>\n</tr>";
# 		}
# 	    }
# 	    $package_page .= "</table><p>".gettext ( "Size is measured in kBytes." )."</p>\n";
# 	    $package_page .= "</div> <!-- end pdownload -->\n";
	    
# 	    #
# 	    # more information
# 	    #
# 	    $package_page .= pmoreinfo( name => $name, env => $env, data => $d,
# 					bugreports => 1, sourcedownload => 1,
# 					changesandcopy => 1, maintainers => 1,
# 					search => 1 );
	    
# 	    #
# 	    # Trailer
# 	    #
# 	    my @tr_langs = ();
# 	    foreach my $l (@{$env->{langs}}) {
# 		next if $l eq $lang;
# 		push @tr_langs, $l if ( $l eq 'en' ) 
# 		    || $env->{db}->is_translated( $name, $d->{version}, 
# 						  ${$versions{v2a}{$d->{version}}}[0],
# 						  $l );
# 	    }
# 	    $package_page .= trailer( '../..', $name, $lang, @tr_langs );
# 	}
#     }
}
my $tet1 = new Benchmark;
my $tetd = timediff($tet1, $tet0);
print "Total page evaluation took ".timestr($tetd)."<br>"
    if $debug_allowed;

my $trailer = Packages::HTML::trailer( $ROOT );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e; #FIXME
print $trailer;

# vim: ts=8 sw=4
