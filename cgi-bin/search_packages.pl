#!/usr/bin/perl -wT
#
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
use CGI qw( -oldstyle_urls );
use CGI::Carp qw( fatalsToBrowser );
use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark;

use lib "../lib";

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::HTML ();

my $thisscript = $Packages::HTML::SEARCH_CGI;
my $HOME = "http://www.debian.org";
my $ROOT = "";
my $SEARCHPAGE = "http://packages.debian.org/";
my @SUITES = qw( oldstable stable testing unstable experimental );
my @SECTIONS = qw( main contrib non-free );
my @ARCHIVES = qw( us security installer );
my @ARCHITECTURES = qw( alpha amd64 arm hppa hurd-i386 i386 ia64
			kfreebsd-i386 mips mipsel powerpc s390 sparc );
my %SUITES = map { $_ => 1 } @SUITES;
my %SECTIONS = map { $_ => 1 } @SECTIONS;
my %ARCHIVES = map { $_ => 1 } @ARCHIVES;
my %ARCHITECTURES = map { $_ => 1 } @ARCHITECTURES;

$ENV{PATH} = "/bin:/usr/bin";

# Read in all the variables set by the form
my $input;
if ($ARGV[0] && ($ARGV[0] eq 'php')) {
	$input = new CGI(\*STDIN);
} else {
	$input = new CGI;
}

my $pet0 = new Benchmark;
# use this to disable debugging in production mode completly
my $debug_allowed = 1;
my $debug = $debug_allowed && $input->param("debug");
$debug = 0 if not defined($debug);
$Packages::Search::debug = 1 if $debug > 1;

# If you want, just print out a list of all of the variables and exit.
print $input->header if $debug;
# print $input->dump;
# exit;

if (my $path = $input->param('path')) {
    my @components = map { lc $_ } split /\//, $path;

    foreach (@components) {
	if ($SUITES{$_}) {
	    $input->param('suite', $_);
	} elsif ($SECTIONS{$_}) {
	    $input->param('section', $_);
	} elsif ($ARCHIVES{$_}) {
	    $input->param('archive', $_);
	}elsif ($ARCHITECTURES{$_}) {
	    $input->param('arch', $_);
	}
    }
}

my ( $format, $keyword, $case, $subword, $exact, $searchon,
     @suites, @sections, @archs );

my %params_def = ( keywords => { default => undef,
				 match => '^\s*([-+\@\w\/.:]+)\s*$',
				 var => \$keyword },
		   suite => { default => 'stable', match => '^(\w+)$',
			      alias => 'version', array => ',',
			      var => \@suites,
			      replace => { all => \@SUITES } },
		   case => { default => 'insensitive', match => '^(\w+)$',
			     var => \$case },
#		   official => { default => 0, match => '^(\w+)$' },
#		   use_cache => { default => 1, match => '^(\w+)$' },
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
		   archive => { default => 'all', match => '^(\w+)$',
				array => ',', replace =>
				{ all => \@ARCHIVES } },
		   format => { default => 'html', match => '^(\w+)$',
                               var => \$format },
		   );
my %opts;
my %params = Packages::Search::parse_params( $input, \%params_def, \%opts );

#XXX: Don't use alternative output formats yet
$format = 'html';

if ($format eq 'html') {
    print $input->header;
} elsif ($format eq 'xml') {
#    print $input->header( -type=>'application/rdf+xml' );
    print $input->header( -type=>'text/plain' );
}

if ($params{errors}{keywords}) {
    print "Error: keyword not valid or missing" if $format eq 'html';
    exit 0;
}

my $case_bool = ( $case !~ /insensitive/ );
$exact = !$subword unless defined $exact;
$opts{h_suites} = { map { $_ => 1 } @suites };
$opts{h_sections} = { map { $_ => 1 } @sections };
$opts{h_archs} = { map { $_ => 1 } @archs };

# for URL construction
my $suites_param = join ',', @{$params{values}{suite}{no_replace}};
my $sections_param = join ',', @{$params{values}{section}{no_replace}};
my $archs_param = join ',', @{$params{values}{arch}{no_replace}};

# for output
my $keyword_enc = encode_entities $keyword;
my $searchon_enc = encode_entities $searchon;
my $suites_enc = encode_entities join ', ', @{$params{values}{suite}{no_replace}};
my $sections_enc = encode_entities join ', ', @{$params{values}{section}{no_replace}};
my $archs_enc = encode_entities join ', ',  @{$params{values}{arch}{no_replace}};
my $pet1 = new Benchmark;
my $petd = timediff($pet1, $pet0);
print "DEBUG: Parameter evaluation took ".timestr($petd)."<br>" if $debug;

if ($format eq 'html') {
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
				  },
			      );
}

# read the configuration
my $topdir;
if (!open (C, "../config.sh")) {
    print "\nInternal Error: Cannot open configuration file.\n\n"
if $format eq 'html';
    exit 0;
}
while (<C>) {
    $topdir = $1 if (/^\s*topdir="?(.*)"?\s*$/);
}
close (C);

my $DBDIR = $topdir . "/files/db";
my $search_on_sources = 0;

my $st0 = new Benchmark;
my @results;
my $too_many_hits;
if ($searchon eq 'sourcenames') {
    $search_on_sources = 1;
}

sub read_entry {
    my ($hash, $key, $results, $opts) = @_;
    my $result = $hash->{$key} || '';
    foreach (split /\000/, $result) {
	my @data = split ( /\s/, $_, 7 );
	print "DEBUG: Considering entry ".join( ':', @data)."<br>" if $debug > 2;
	if ($opts->{h_suites}{$data[0]}
	    && ($opts->{h_archs}{$data[1]} || $data[1] eq 'all')
	    && $opts->{h_sections}{$data[2]}) {
	    print "DEBUG: Using entry ".join( ':', @data)."<br>" if $debug > 2;
	    push @$results, [ $key, @data ];
	}
    }
}
sub read_src_entry {
    my ($hash, $key, $results, $opts) = @_;
    my $result = $hash->{$key} || '';
    foreach (split /\000/, $result) {
	my @data = split ( /\s/, $_, 5 );
	print "DEBUG: Considering entry ".join( ':', @data)."<br>" if $debug > 2;
	if ($opts->{h_suites}{$data[0]} && $opts->{h_sections}{$data[1]}) {
	    print "DEBUG: Using entry ".join( ':', @data)."<br>" if $debug > 2;
	    push @$results, [ $key, @data ];
	}
    }
}
sub do_names_search {
    my ($keyword, $file, $postfix_file, $read_entry, $opts) = @_;
    my @results;

    $keyword = lc $keyword unless $opts->{case_bool};
    
    my $obj = tie my %packages, 'DB_File', "$DBDIR/$file", O_RDONLY, 0666, $DB_BTREE
	or die "couldn't tie DB $DBDIR/$file: $!";
    
    if ($opts->{exact}) {
	&$read_entry( \%packages, $keyword, \@results, $opts );
    } else {
	my ($key, $prefixes) = ($keyword, '');
	my %pkgs;
	my $p_obj = tie my %pref, 'DB_File', "$DBDIR/$postfix_file", O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie postfix db $DBDIR/$postfix_file: $!";
	$p_obj->seq( $key, $prefixes, R_CURSOR );
	while (index($key, $keyword) >= 0) {
            if ($prefixes =~ /^\001(\d+)/o) {
                $too_many_hits += $1;
            } else {
		foreach (split /\000/o, $prefixes) {
		    $_ = '' if $_ eq '^';
		    print "DEBUG: add word $_$key<br>" if $debug > 2;
		    $pkgs{$_.$key}++;
		}
	    }
	    last if $p_obj->seq( $key, $prefixes, R_NEXT ) != 0;
	    last if $too_many_hits or keys %pkgs >= 100;
	}
        
        my $no_results = keys %pkgs;
        if ($too_many_hits || ($no_results >= 100)) {
	    $too_many_hits += $no_results;
	    %pkgs = ( $keyword => 1 );
	}
	foreach my $pkg (sort keys %pkgs) {
	    &$read_entry( \%packages, $pkg, \@results, $opts );
	}
    }
    return \@results;
}
sub do_fulltext_search {
    my ($keword, $file, $mapping, $lookup, $read_entry, $opts) = @_;
    my @results;

    my @lines;
    my $regex;
    if ($opts->{case_bool}) {
	if ($opts->{exact}) {
	    $regex = qr/\b\Q$keyword\E\b/o;
	} else {
	    $regex = qr/\Q$keyword\E/o;
	}
    } else {
	if ($exact) {
	    $regex = qr/\b\Q$keyword\E\b/io;
	} else {
	    $regex = qr/\Q$keyword\E/io;
	}
    }

    open DESC, '<', "$DBDIR/$file"
	or die "couldn't open $DBDIR/$file: $!";
    while (<DESC>) {
	$_ =~ $regex or next;
	print "DEBUG: Matched line $.<br>" if $debug > 2;
	push @lines, $.;
    }
    close DESC;

    tie my %packages, 'DB_File', "$DBDIR/$lookup", O_RDONLY, 0666, $DB_BTREE
	or die "couldn't tie DB $DBDIR/$lookup: $!";
    tie my %did2pkg, 'DB_File', "$DBDIR/$mapping", O_RDONLY, 0666, $DB_BTREE
	or die "couldn't tie DB $DBDIR/$mapping: $!";

    my %tmp_results;
    foreach my $l (@lines) {
	my $result = $did2pkg{$l};
	foreach (split /\000/o, $result) {
	    my @data = split /\s/, $_, 3;
	    next unless $opts->{h_archs}{$data[2]};
	    $tmp_results{$data[0]}++;
	}
    }
    foreach my $pkg (keys %tmp_results) {
	&$read_entry( \%packages, $pkg, \@results, $opts );
    }
    return \@results;
}

sub find_binaries {
    my ($pkg, $suite) = @_;

    tie my %src2bin, 'DB_File', "$DBDIR/sources_packages.db", O_RDONLY, 0666, $DB_BTREE
	or die "couldn't open $DBDIR/sources_packages.db: $!";

    my $bins = $src2bin{$pkg} || '';
    my %bins;
    foreach (split /\000/o, $bins) {
	my @data = split /\s/, $_, 4;

	if ($data[0] eq $suite) {
	    $bins{$data[1]}++;
	}
    }

    return [ keys %bins ];
}

if ($searchon eq 'names') {
    push @results, @{ do_names_search( $keyword, 'packages_small.db',
				       'package_postfixes.db',
				       \&read_entry, \%opts ) };
} elsif ($searchon eq 'sourcenames') {
    push @results, @{ do_names_search( $keyword, 'sources_small.db',
				       'source_postfixes.db',
				       \&read_src_entry, \%opts ) };
} else {
    push @results, @{ do_names_search( $keyword, 'packages_small.db',
				       'package_postfixes.db',
				       \&read_entry, \%opts ) };
    push @results, @{ do_fulltext_search( $keyword, 'descriptions.txt',
					  'descriptions_packages.db',
					  'packages_small.db',
					  \&read_entry, \%opts ) };
}

my $st1 = new Benchmark;
my $std = timediff($st1, $st0);
print "DEBUG: Search took ".timestr($std)."<br>" if $debug;

if ($format eq 'html') {
    my $suite_wording = $suites_enc eq "all" ? "all suites"
	: "suite(s) <em>$suites_enc</em>";
    my $section_wording = $sections_enc eq 'all' ? "all sections"
	: "section(s) <em>$sections_enc</em>";
    my $arch_wording = $archs_enc eq 'any' ? "all architectures"
	: "architecture(s) <em>$archs_enc</em>";
    if (($searchon eq "names") || ($searchon eq 'sourcenames')) {
	my $source_wording = $search_on_sources ? "source " : "";
	my $exact_wording = $exact ? "named" : "that names contain";
	print "<p>You have searched for ${source_wording}packages $exact_wording <em>$keyword_enc</em> in $suite_wording, $section_wording, and $arch_wording.</p>";
    } else {
	my $exact_wording = $exact ? "" : " (including subword matching)";
	print "<p>You have searched for <em>$keyword_enc</em> in packages names and descriptions in $suite_wording, $section_wording, and $arch_wording$exact_wording.</p>";
    }
}

if ($too_many_hits) {
print "<p><strong>Your search was too wide so we will only display exact matches. At least <em>$too_many_hits</em> results have been omitted and will not be displayed. Please consider using a longer keyword or more keywords.</strong></p>";
}

if (!@results) {
    if ($format eq 'html') {
	my $keyword_esc = uri_escape( $keyword );
	my $printed = 0;
	if (($searchon eq "names") || ($searchon eq 'sourcenames')) {
	    if (($suites_enc eq 'all')
		&& ($archs_enc eq 'any')
		&& ($sections_enc eq 'all')) {
		print "<p><strong>Can't find that package.</strong></p>\n";
	    } else {
		print "<p><strong>Can't find that package, at least not in that suite ".
		    ( $search_on_sources ? "" : " and on that architecture" ).
		    ".</strong></p>\n";
	    }
	    
	    if ($exact) {
		$printed = 1;
		print "<p>You have searched only for exact matches of the package name. You can try to search for <a href=\"$thisscript?exact=0&amp;searchon=$searchon&amp;suite=$suites_param&amp;case=$case&amp;section=$sections_param&amp;keywords=$keyword_esc&amp;arch=$archs_param\">package names that contain your search string</a>.</p>";
	    }
	} else {
	    if (($suites_enc eq 'all')
		&& ($archs_enc eq 'any')
		&& ($sections_enc eq 'all')) {
		print "<p><strong>Can't find that string.</strong></p>\n";
	    } else {
		print "<p><strong>Can't find that string, at least not in that suite ($suites_enc, section $sections_enc) and on that architecture ($archs_enc).</strong></p>\n";
	    }
	    
	    unless ($subword) {
		$printed = 1;
		print "<p>You have searched only for words exactly matching your keywords. You can try to search <a href=\"$thisscript?subword=1&amp;searchon=$searchon&amp;suite=$suites_param&amp;case=$case&amp;section=$sections_param&amp;keywords=$keyword_esc&amp;arch=$archs_param\">allowing subword matching</a>.</p>";
	    }
	}
	print "<p>".( $printed ? "Or you" : "You" )." can try a different search on the <a href=\"$SEARCHPAGE#search_packages\">Packages search page</a>.</p>";
	
	&printfooter;
    }
    exit;
}

my (%pkgs, %sect, %part, %desc, %binaries);

unless ($search_on_sources) {
    foreach (@results) {
	my ($pkg_t, $suite, $arch, $section, $subsection,
            $priority, $version, $desc) = @$_;
	
	my ($package) = $pkg_t =~ m/^(.+)/; # untaint
	$pkgs{$package}{$suite}{$version}{$arch} = 1;
	$sect{$package}{$suite}{$version} = $subsection;
	$part{$package}{$suite}{$version} = $section unless $section eq 'main';
	
	$desc{$package}{$suite}{$version} = $desc;
    }

    if ($format eq 'html') {
	my ($start, $end) = multipageheader( scalar keys %pkgs );
	my $count = 0;
	
	foreach my $pkg (sort keys %pkgs) {
	    $count++;
	    next if $count < $start or $count > $end;
	    printf "<h3>Package %s</h3>\n", $pkg;
	    print "<ul>\n";
	    foreach my $ver (@SUITES) {
		if (exists $pkgs{$pkg}{$ver}) {
		    my @versions = version_sort keys %{$pkgs{$pkg}{$ver}};
		    my $part_str = "";
		    if ($part{$pkg}{$ver}{$versions[0]}) {
			$part_str = "[<span style=\"color:red\">$part{$pkg}{$ver}{$versions[0]}</span>]";
		    }
		    printf "<li><a href=\"$ROOT/%s/%s/%s\">%s</a> (%s): %s   %s\n",
		    $ver, $sect{$pkg}{$ver}{$versions[0]}, $pkg, $ver, $sect{$pkg}{$ver}{$versions[0]}, $desc{$pkg}{$ver}{$versions[0]}, $part_str;
		    
		    foreach my $v (@versions) {
			printf "<br>%s: %s\n",
			$v, join (" ", (sort keys %{$pkgs{$pkg}{$ver}{$v}}) );
		    }
		    print "</li>\n";
		}
	    }
	    print "</ul>\n";
	}
    } elsif ($format eq 'xml') {
	require RDF::Simple::Serialiser;
	my $rdf = new RDF::Simple::Serialiser;
	$rdf->addns( debpkg => 'http://packages.debian.org/xml/01-debian-packages-rdf' );
	my @triples;
	foreach my $pkg (sort keys %pkgs) {
	    foreach my $ver (@SUITES) {
		if (exists $pkgs{$pkg}{$ver}) {
		    my @versions = version_sort keys %{$pkgs{$pkg}{$ver}};
		    foreach my $version (@versions) {
			my $id = "$ROOT/$ver/$sect{$pkg}{$ver}{$version}/$pkg/$version";
			push @triples, [ $id, 'debpkg:package', $pkg ];
			push @triples, [ $id, 'debpkg:version', $version ];
			push @triples, [ $id, 'debpkg:section', $sect{$pkg}{$ver}{$version}, ];
			push @triples, [ $id, 'debpkg:suite', $ver ];
			push @triples, [ $id, 'debpkg:shortdesc', $desc{$pkg}{$ver}{$version} ];
			push @triples, [ $id, 'debpkg:part', $part{$pkg}{$ver}{$version} || 'main' ];
			foreach my $arch (sort keys %{$pkgs{$pkg}{$ver}{$version}}) {
			    push @triples, [ $id, 'debpkg:architecture', $arch ];
			}
		    }
		}
	    }
	}
	
	print $rdf->serialise(@triples);
    }
} else {
    foreach (@results) {
        my ($package, $suite, $section, $subsection, $priority,
            $version) = @$_;
	
	$pkgs{$package}{$suite} = $version;
	$sect{$package}{$suite}{source} = $subsection;
	$part{$package}{$suite}{source} = $section unless $section eq 'main';

	$binaries{$package}{$suite} = find_binaries( $package, $suite );
    }

    if ($format eq 'html') {
	my ($start, $end) = multipageheader( scalar keys %pkgs );
	my $count = 0;
	
	foreach my $pkg (sort keys %pkgs) {
	    $count++;
	    next if ($count < $start) or ($count > $end);
	    printf "<h3>Source package %s</h3>\n", $pkg;
	    print "<ul>\n";
	    foreach my $ver (@SUITES) {
		if (exists $pkgs{$pkg}{$ver}) {
		    my $part_str = "";
		    if ($part{$pkg}{$ver}{source}) {
			$part_str = "[<span style=\"color:red\">$part{$pkg}{$ver}{source}</span>]";
		    }
		    printf "<li><a href=\"$ROOT/%s/source/%s\">%s</a> (%s): %s   %s", $ver, $pkg, $ver, $sect{$pkg}{$ver}{source}, $pkgs{$pkg}{$ver}, $part_str;
		    
		    print "<br>Binary packages: ";
		    my @bp_links;
		    foreach my $bp (@{$binaries{$pkg}{$ver}}) {
			my $bp_link = sprintf( "<a href=\"$ROOT/%s/%s\">%s</a>",
					       $ver, uri_escape( $bp ),  $bp );
			push @bp_links, $bp_link;
		    }
		    print join( ", ", @bp_links );
		    print "</li>\n";
		}
	    }
	    print "</ul>\n";
	}
    } elsif ($format eq 'xml') {
	require RDF::Simple::Serialiser;
	my $rdf = new RDF::Simple::Serialiser;
	$rdf->addns( debpkg => 'http://packages.debian.org/xml/01-debian-packages-rdf' );
	my @triples;
	foreach my $pkg (sort keys %pkgs) {
	    foreach my $ver (@SUITES) {
		if (exists $pkgs{$pkg}{$ver}) {
		    my $id = "$ROOT/$ver/source/$pkg";

		    push @triples, [ $id, 'debpkg:package', $pkg ];
		    push @triples, [ $id, 'debpkg:type', 'source' ];
		    push @triples, [ $id, 'debpkg:section', $sect{$pkg}{$ver}{source} ];
		    push @triples, [ $id, 'debpkg:version', $pkgs{$pkg}{$ver} ];
		    push @triples, [ $id, 'debpkg:part', $part{$pkg}{$ver}{source} || 'main' ];
		    
		    foreach my $bp (@{$binaries{$pkg}{$ver}}) {
			push @triples, [ $id, 'debpkg:binary', $bp ];
		    }
		}
	    }
	}
	print $rdf->serialise(@triples);
    }
}

if ($format eq 'html') {
    &printindexline( scalar keys %pkgs );
    &printfooter;
}

exit;

sub printindexline {
    my $no_results = shift;

    my $index_line;
    if ($no_results > $opts{number}) {
	
	$index_line = prevlink($input,\%params)." | ".
	    indexline( $input, \%params, $no_results)." | ".
	    nextlink($input,\%params, $no_results);
	
	print "<p style=\"text-align:center\">$index_line</p>";
    }
}

sub multipageheader {
    my $no_results = shift;

    my ($start, $end);
    if ($opts{number} =~ /^all$/i) {
	$start = 1;
	$end = $no_results;
	$opts{number} = $no_results;
    } else {
	$start = Packages::Search::start( \%params );
	$end = Packages::Search::end( \%params );
	if ($end > $no_results) { $end = $no_results; }
    }

    print "<p>Found <em>$no_results</em> matching packages,";
    if ($end == $start) {
	print " displaying package $end.</p>";
    } else {
	print " displaying packages $start to $end.</p>";
    }

    printindexline( $no_results );

    if ($no_results > 100) {
	print "<p>Results per page: ";
	my @resperpagelinks;
	for (50, 100, 200) {
	    if ($opts{number} == $_) {
		push @resperpagelinks, $_;
	    } else {
		push @resperpagelinks, resperpagelink($input,\%params,$_);
	    }
	}
	if ($params{values}{number}{final} =~ /^all$/i) {
	    push @resperpagelinks, "all";
	} else {
	    push @resperpagelinks, resperpagelink($input, \%params,"all");
	}
	print join( " | ", @resperpagelinks )."</p>";
    }
    return ( $start, $end );
}

sub printfooter {
print <<END;
</div>

<hr class="hidecss">
<p style="text-align:right;font-size:small;font-stlye:italic"><a href="$SEARCHPAGE">Packages search page</a></p>

</div>
END

my $pete = new Benchmark;
my $petd = timediff($pete, $pet0);
print "Total page evaluation took ".timestr($petd)."<br>"
    if $debug_allowed;
print $input->end_html;
}

# vim: ts=8 sw=4
