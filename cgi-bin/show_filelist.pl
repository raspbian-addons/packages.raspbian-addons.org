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
use lib '../lib';
use CGI qw( -oldstyle_urls );
use CGI::Carp qw( fatalsToBrowser );
use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark;

use Deb::Versions;
use Packages::Config qw( $DBDIR $ROOT @SUITES @ARCHIVES @SECTIONS
			 @ARCHITECTURES %FTP_SITES );
use Packages::CGI;
use Packages::DB;
use Packages::Search qw( :all );
use Packages::HTML;
use Packages::Page ();
use Packages::SrcPage ();

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

my ( $pkg, $suite, $arch );
my %params_def = ( package => { default => undef, match => '^([a-z0-9.+-]+)$',
				var => \$pkg },
		   suite => { default => undef, match => '^(\w+)$',
			      var => \$suite },
		   arch => { default => undef, match => '^([a-z0-9-]+)$',
			     var => \$arch }
		   );

my %opts;
my %params = Packages::Search::parse_params( $input, \%params_def, \%opts );

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

print $input->header( -charset => 'utf-8' );

print Packages::HTML::header( title => "Filelist of package $pkg in $suite of arch $arch",
			      lang => 'en',
			      #desc => $short_desc,
			      #keywords => "$suite, $archive, $section, $subsection, $version",
			      #title_tag => "Details of package $pkg in $suite",
			      );

print_errors();
print_hints();
print_msgs();
print_debug();
print_notes();

unless (@Packages::CGI::fatal_errors) {
    tie my %contents, 'DB_File', "$DBDIR/packages_contents_${suite}_${arch}.db",
	O_RDONLY, 0666, $DB_BTREE
	or die "couldn't tie DB $DBDIR/packages_contents_${suite}_${arch}.db: $!";

    my $cont = $contents{$pkg};
    print "No such package in this suite on this arch" if not exists $contents{$pkg};
    my @files = unpack "L/(CC/a)", $contents{$pkg};
    my $file = "";
    print "<pre>";
    for (my $i=0; $i<scalar @files;) {
	    $file = substr($file, 0, $files[$i++]).$files[$i++];
	    print "$file\n";
    }
    print "</pre>";
}

my $tet1 = new Benchmark;
my $tetd = timediff($tet1, $tet0);
print "Total page evaluation took ".timestr($tetd)."<br>"
    if $debug_allowed;

my $trailer = Packages::HTML::trailer( $ROOT );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e; #FIXME
print $trailer;

# vim: ts=8 sw=4
