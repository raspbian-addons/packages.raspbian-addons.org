#!/usr/bin/perl -wT
# $Id$
# search_packages.pl -- CGI interface to the Packages files on packages.debian.org
#
# Copyright (C) 1998 James Treacy
# Copyright (C) 2000, 2001 Josip Rodin
# Copyright (C) 2001 Adam Heath
# Copyright (C) 2004 Martin Schulze
# Copyright (C) 2004-2006 Frank Lichtenheld
#
# use is allowed under the terms of the GNU Public License (GPL)                              
# see http://www.fsf.org/copyleft/gpl.html for a copy of the license

use strict;
use lib '../lib';
use CGI qw( -oldstyle_urls );
use CGI::Carp qw( fatalsToBrowser );
use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark;

use Deb::Versions;
use Packages::Config qw( $DBDIR $ROOT $SEARCH_CGI $SEARCH_PAGE
			 @SUITES @SECTIONS @ARCHIVES @ARCHITECTURES );
use Packages::CGI;
use Packages::DB;
use Packages::Search qw( :all );
use Packages::HTML ();

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

&Packages::Config::init( '../' );
&Packages::DB::init();

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
	} elsif ($_ eq 'source') {
	    $input->param('searchon','sourcenames');
	}
    }
}

my ( $format, $keyword, $case, $subword, $exact, $searchon,
     @suites, @sections, @archives, @archs );

my %params_def = ( keywords => { default => undef,
				 match => '^\s*([-+\@\w\/.:]+)\s*$',
				 var => \$keyword },
		   suite => { default => 'stable', match => '^([\w-]+)$',
			      alias => 'version', array => ',',
			      var => \@suites,
			      replace => { all => \@SUITES } },
		   archive => { default => 'all', match => '^([\w-]+)$',
				array => ',', var => \@archives,
				replace => { all => \@ARCHIVES } },
		   case => { default => 'insensitive', match => '^(\w+)$',
			     var => \$case },
		   official => { default => 0, match => '^(\w+)$' },
		   subword => { default => 0, match => '^(\w+)$',
				var => \$subword },
		   exact => { default => undef, match => '^(\w+)$',
			      var => \$exact },
		   searchon => { default => 'all', match => '^(\w+)$',
				 var => \$searchon },
		   section => { default => 'all', match => '^([\w-]+)$',
				alias => 'release', array => ',',
				var => \@sections,
				replace => { all => \@SECTIONS } },
		   arch => { default => 'any', match => '^(\w+)$',
			     array => ',', var => \@archs, replace =>
			     { any => \@ARCHITECTURES } },
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

if ($params{errors}{keywords}) {
    fatal_error( "keyword not valid or missing" );
} elsif (length($keyword) < 2) {
    fatal_error( "keyword too short (keywords need to have at least two characters)" );
}

my $case_bool = ( $case !~ /insensitive/ );
$exact = !$subword unless defined $exact;
$opts{h_suites} = { map { $_ => 1 } @suites };
$opts{h_sections} = { map { $_ => 1 } @sections };
$opts{h_archives} = { map { $_ => 1 } @archives };
$opts{h_archs} = { map { $_ => 1 } @archs };

# for URL construction
my $suites_param = join ',', @{$params{values}{suite}{no_replace}};
my $sections_param = join ',', @{$params{values}{section}{no_replace}};
my $archs_param = join ',', @{$params{values}{arch}{no_replace}};

# for output
my $keyword_enc = encode_entities $keyword || '';
my $searchon_enc = encode_entities $searchon;
my $suites_enc = encode_entities join ', ', @{$params{values}{suite}{no_replace}};
my $sections_enc = encode_entities join ', ', @{$params{values}{section}{no_replace}};
my $archs_enc = encode_entities join ', ',  @{$params{values}{arch}{no_replace}};
my $pet1 = new Benchmark;
my $petd = timediff($pet1, $pet0);
debug( "Parameter evaluation took ".timestr($petd) );

my $st0 = new Benchmark;
my @results;

unless (@Packages::CGI::fatal_errors) {

    if ($searchon eq 'names') {
	push @results, @{ do_names_search( $keyword, \%packages,
					   $p_obj,
					   \&read_entry, \%opts ) };
    } elsif ($searchon eq 'sourcenames') {
	push @results, @{ do_names_search( $keyword, \%sources,
					   $sp_obj,
					   \&read_src_entry, \%opts ) };
    } elsif ($searchon eq 'contents') {
	require "./search_contents.pl";
	&contents(\$input);
	exit;
    } else {
	push @results, @{ do_names_search( $keyword, \%packages,
					   $p_obj,
					   \&read_entry, \%opts ) };
	push @results, @{ do_fulltext_search( $keyword, "$DBDIR/descriptions.txt",
					      \%did2pkg,
					      \%packages,
					      \&read_entry, \%opts ) };
    }
}

my $st1 = new Benchmark;
my $std = timediff($st1, $st0);
debug( "Search took ".timestr($std) );

if ($format eq 'html') {
    my $suite_wording = $suites_enc eq "all" ? "all suites"
	: "suite(s) <em>$suites_enc</em>";
    my $section_wording = $sections_enc eq 'all' ? "all sections"
	: "section(s) <em>$sections_enc</em>";
    my $arch_wording = $archs_enc eq 'any' ? "all architectures"
	: "architecture(s) <em>$archs_enc</em>";
    if (($searchon eq "names") || ($searchon eq 'sourcenames')) {
	my $source_wording = ( $searchon eq 'sourcenames' ) ? "source " : "";
	my $exact_wording = $exact ? "named" : "that names contain";
	msg( "You have searched for ${source_wording}packages $exact_wording <em>$keyword_enc</em> in $suite_wording, $section_wording, and $arch_wording." );
    } else {
	my $exact_wording = $exact ? "" : " (including subword matching)";
	msg( "You have searched for <em>$keyword_enc</em> in packages names and descriptions in $suite_wording, $section_wording, and $arch_wording$exact_wording." );
    }
}

if ($Packages::Search::too_many_hits) {
    error( "Your search was too wide so we will only display exact matches. At least <em>$Packages::Search::too_many_hits</em> results have been omitted and will not be displayed. Please consider using a longer keyword or more keywords." );
}

if (!@Packages::CGI::fatal_errors && !@results) {
    if ($format eq 'html') {
	my $keyword_esc = uri_escape( $keyword );
	my $printed = 0;
	if (($searchon eq "names") || ($searchon eq 'sourcenames')) {
	    if (($suites_enc eq 'all')
		&& ($archs_enc eq 'any')
		&& ($sections_enc eq 'all')) {
		error( "Can't find that package." );
	    } else {
		error( "Can't find that package, at least not in that suite ".
		    ( ( $searchon eq 'sourcenames' ) ? "" : " and on that architecture" ) )
	    }
	    
	    if ($exact) {
		$printed++;
		hint( "You have searched only for exact matches of the package name. You can try to search for <a href=\"$SEARCH_CGI?exact=0&amp;searchon=$searchon&amp;suite=$suites_param&amp;case=$case&amp;section=$sections_param&amp;keywords=$keyword_esc&amp;arch=$archs_param\">package names that contain your search string</a>." );
	    }
	} else {
	    if (($suites_enc eq 'all')
		&& ($archs_enc eq 'any')
		&& ($sections_enc eq 'all')) {
		error( "Can't find that string." );
	    } else {
		error( "Can't find that string, at least not in that suite ($suites_enc, section $sections_enc) and on that architecture ($archs_enc)." );
	    }
	    
	    unless ($subword) {
		$printed++;
		hint( "You have searched only for words exactly matching your keywords. You can try to search <a href=\"$SEARCH_CGI?subword=1&amp;searchon=$searchon&amp;suite=$suites_param&amp;case=$case&amp;section=$sections_param&amp;keywords=$keyword_esc&amp;arch=$archs_param\">allowing subword matching</a>." );
	    }
	}
	hint( ( $printed ? "Or you" : "You" )." can try a different search on the <a href=\"$SEARCH_PAGE#search_packages\">Packages search page</a>." );
	    
    }
}

print Packages::HTML::header( title => 'Package Search Results' ,
			      lang => 'en',
			      title_tag => 'Debian Package Search Results',
			      print_title_above => 1,
			      print_search_field => 'packages',
			      search_field_values => { 
				  keywords => $keyword_enc,
				  searchon => $searchon,
				  arch => $archs_enc,
				  suite => $suites_enc,
				  section => $sections_enc,
				  subword => $subword,
				  exact => $exact,
				  case => $case,
				  debug => $debug,
			      },
			      );
print_msgs();
print_errors();
print_hints();
print_debug();
if (@results) {
    my (%pkgs, %subsect, %sect, %desc, %binaries, %provided_by);

    unless ($opts{searchon} eq 'sourcenames') {
	foreach (@results) {
	    my ($pkg_t, $archive, $suite, $arch, $section, $subsection,
		$priority, $version, $desc) = @$_;
	
	    my ($pkg) = $pkg_t =~ m/^(.+)/; # untaint
	    if ($arch ne 'virtual') {
		$pkgs{$pkg}{$suite}{$archive}{$version}{$arch} = 1;
		$subsect{$pkg}{$suite}{$archive}{$version} = $subsection;
		$sect{$pkg}{$suite}{$archive}{$version} = $section
		    unless $section eq 'main';
		
		$desc{$pkg}{$suite}{$archive}{$version} = $desc;
	    } else {
		$provided_by{$pkg}{$suite}{$archive} = [ split /\s+/, $desc ];
	    }
	}

my @pkgs = sort(keys %pkgs, keys %provided_by);
	if ($opts{format} eq 'html') {
	    my ($start, $end) = multipageheader( $input, scalar @pkgs, \%opts );
	    my $count = 0;
	
	    foreach my $pkg (@pkgs) {
		$count++;
		next if $count < $start or $count > $end;
		printf "<h3>Package %s</h3>\n", $pkg;
		print "<ul>\n";
		foreach my $suite (@SUITES) {
		    foreach my $archive (@ARCHIVES) {
			my $path = $suite.(($archive ne 'us')?"/$archive":'');
			if (exists $pkgs{$pkg}{$suite}{$archive}) {
			    my @versions = version_sort keys %{$pkgs{$pkg}{$suite}{$archive}};
			    my $origin_str = "";
			    if ($sect{$pkg}{$suite}{$archive}{$versions[0]}) {
				$origin_str .= " [<span style=\"color:red\">$sect{$pkg}{$suite}{$archive}{$versions[0]}</span>]";
			    }
			    printf "<li><a href=\"$ROOT/%s/%s\">%s</a> (%s): %s   %s\n",
			    $path, $pkg, $path, $subsect{$pkg}{$suite}{$archive}{$versions[0]},
			    $desc{$pkg}{$suite}{$archive}{$versions[0]}, $origin_str;
			    
			    foreach my $v (@versions) {
				printf "<br>%s: %s\n",
				$v, join (" ", (sort keys %{$pkgs{$pkg}{$suite}{$archive}{$v}}) );
			    }
			    if (my $provided_by =  $provided_by{$pkg}{$suite}{$archive}) {
				print '<br>also provided by: ',
				join( ', ', map { "<a href=\"$ROOT/$path/$_\">$_</a>"  } @$provided_by);
			    }
			    print "</li>\n";
			} elsif (my $provided_by =  $provided_by{$pkg}{$suite}{$archive}) {
			    printf "<li><a href=\"$ROOT/%s/%s\">%s</a>: Virtual package<br>",
			    $path, $pkg, $path;
			    print 'provided by: ',
			    join( ', ', map { "<a href=\"$ROOT/$path/$_\">$_</a>"  } @$provided_by);
			}
		    }
		}
		print "</ul>\n";
	    }
	}
    } else {
	foreach (@results) {
	    my ($pkg, $archive, $suite, $section, $subsection, $priority,
		$version) = @$_;
	
	    $pkgs{$pkg}{$suite}{$archive} = $version;
	    $subsect{$pkg}{$suite}{$archive}{source} = $subsection;
	    $sect{$pkg}{$suite}{$archive}{source} = $section
		unless $section eq 'main';

	    $binaries{$pkg}{$suite}{$archive} = find_binaries( $pkg, $archive, $suite, \%src2bin );
	}

	if ($opts{format} eq 'html') {
	    my ($start, $end) = multipageheader( $input, scalar keys %pkgs, \%opts );
	    my $count = 0;
	    
	    foreach my $pkg (sort keys %pkgs) {
		$count++;
		next if ($count < $start) or ($count > $end);
		printf "<h3>Source package %s</h3>\n", $pkg;
		print "<ul>\n";
		foreach my $suite (@SUITES) {
		    foreach my $archive (@ARCHIVES) {
			if (exists $pkgs{$pkg}{$suite}{$archive}) {
			    my $origin_str = "";
			    if ($sect{$pkg}{$suite}{$archive}{source}) {
				$origin_str .= " [<span style=\"color:red\">$sect{$pkg}{$suite}{$archive}{source}</span>]";
			    }
			    printf( "<li><a href=\"$ROOT/%s/source/%s\">%s</a> (%s): %s   %s",
				    $suite.(($archive ne 'us')?"/$archive":''), $pkg, $suite.(($archive ne 'us')?"/$archive":''), $subsect{$pkg}{$suite}{$archive}{source},
				    $pkgs{$pkg}{$suite}{$archive}, $origin_str );
			    
			    print "<br>Binary packages: ";
			    my @bp_links;
			    foreach my $bp (@{$binaries{$pkg}{$suite}{$archive}}) {
				my $bp_link = sprintf( "<a href=\"$ROOT/%s/%s\">%s</a>",
						       $suite.(($archive ne 'us')?"/$archive":''), uri_escape( $bp ),  $bp );
				push @bp_links, $bp_link;
			    }
			    print join( ", ", @bp_links );
			    print "</li>\n";
			}
		    }
		}
		print "</ul>\n";
	    }
	}
    }
    printindexline( $input, scalar keys %pkgs, \%opts );
}
#print_results(\@results, \%opts) if @results;;
my $tet1 = new Benchmark;
my $tetd = timediff($tet1, $tet0);
print "Total page evaluation took ".timestr($tetd)."<br>"
    if $debug_allowed;

my $trailer = Packages::HTML::trailer( $ROOT );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e; #FIXME
print $trailer;

# vim: ts=8 sw=4
