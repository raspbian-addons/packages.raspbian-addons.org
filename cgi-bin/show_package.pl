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

use lib "../lib";

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::HTML ();

my $HOME = "http://www.debian.org";
my $ROOT = "";
my $SEARCHPAGE = "http://packages.debian.org/";
my @SUITES = qw( oldstable stable testing unstable experimental );
my @DISTS = @SUITES;
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
if ($ARGV[0] eq 'php') {
	$input = new CGI(\*STDIN);
} else {
	$input = new CGI;
}

my $pet0 = new Benchmark;
# use this to disable debugging in production mode completly
my $debug_allowed = 1;
my $debug = $debug_allowed && $input->param("debug");
$debug = 0 if not defined($debug);
$Search::Param::debug = 1 if $debug > 1;

# If you want, just print out a list of all of the variables and exit.
print $input->header if $debug;
# print $input->dump;
# exit;

my %params_def = ( package => { default => undef, match => '^([a-z0-9.+-]+)$' },
		   suite => { default => undef, match => '^(\w+)$' },
		   #format => { default => 'html', match => '^(\w+)$' }
		   );
my %params = Packages::Search::parse_params( $input, \%params_def );

my $format = $params{values}{format}{final};
#XXX: Don't use alternative output formats yet
$format = 'html';

if ($format eq 'html') {
    print $input->header;
} elsif ($format eq 'xml') {
#    print $input->header( -type=>'application/rdf+xml' );
    print $input->header( -type=>'text/plain' );
}

if ($params{errors}{package}) {
    print "Error: package not valid or not specified" if $format eq 'html';
    exit 0;
}
if ($params{errors}{suite}) {
    print "Error: package not valid or not specified" if $format eq 'html';
    exit 0;
}
my $package = $params{values}{package}{final};
my $suite = $params{values}{suite}{final};

# for output
if ($format eq 'html') {
print Packages::HTML::header( title => 'Package Details' ,
			      lang => 'en',
			      title_tag => 'Package Details',
			      print_title_above => 1
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

my $obj1 = tie my %packages, 'DB_File', "$DBDIR/packages_small.db", O_RDONLY, 0666, $DB_BTREE
    or die "couldn't tie DB $DBDIR/packages_small.db: $!";
my $obj2 = tie my %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db", O_RDONLY, 0666, $DB_BTREE
    or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";
my %allsuites = ();
my @results = ();

&read_entry( $package, \@results, \%allsuites );
for my $entry (@results) {
    print join ":", @$entry;
    print "<br>\n";
}

print "Available in ".(join ', ', keys %allsuites)."\n";

sub read_entry {
    my ($key, $results, $allsuites) = @_;
    my $result = $packages{$key};
    foreach (split /\000/, $result) {
	my @data = split ( /\s/, $_, 7 );
	print "DEBUG: Considering entry ".join( ':', @data)."<br>" if $debug > 2;
	if ($suite eq $data[0]) {
	    print "DEBUG: Using entry ".join( ':', @data)."<br>" if $debug > 2;
	    push @$results, [@data];
	}
	$allsuites->{$data[0]} = 1;
    }
}

# TODO: move to common lib:
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
