#!/usr/bin/perl -T
# $Id: search_packages.pl 91 2006-02-10 22:18:31Z jeroen $
# dispatcher.pl -- CGI interface for packages.debian.org
#
# Copyright (C) 2004-2006 Frank Lichtenheld
#
# use is allowed under the terms of the GNU Public License (GPL)                              
# see http://www.fsf.org/copyleft/gpl.html for a copy of the license

use strict;
use warnings;

use lib '../lib';
use CGI;
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
use Packages::Sections;

use Packages::DoSearch;
use Packages::DoShow;
use Packages::DoDownload;
use Packages::DoFilelist;

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

my $what_to_do = 'show';
my $source = 0;
if (my $path = $input->path_info()) {
    my @components = grep { $_ } map { lc $_ } split /\/+/, $path;

    debug( "components[0]=$components[0]", 2 );
    if ($components[0] eq 'search') {
	shift @components;
	$what_to_do = 'search';
    }
    if ($components[0] eq 'source') {
	shift @components;
	$input->param( 'source', 1 );
    }
    if (@components == 0) {
	# we just hope we get the information through our parameters...
    } elsif (@components == 1) {
	$what_to_do = 'search';
    } else {

	for ($components[-1]) {
	    /^(changelog|copyright|download|filelist)$/ && do {
		pop @components;
		$what_to_do = $1;
		last;
	    };
	}

	my %SUITES = map { $_ => 1 } @SUITES;
	my %SUITES_ALIAS = ( woody => 'oldstable',
			     sarge => 'stable',
			     etch => 'testing',
			     sid => 'unstable', );
	my %SECTIONS = map { $_ => 1 } @SECTIONS;
	my %ARCHIVES = map { $_ => 1 } @ARCHIVES;
	my %ARCHITECTURES = map { $_ => 1 } (@ARCHITECTURES, 'all');
	my %params_set;
	sub set_param_once {
	    my ($cgi, $params_set, $key, $val) = @_;
	    if ($params_set->{$key}++) {
		fatal_error( "$key set more than once in path" );
	    } else {
		$cgi->param( $key, $val );
	    }
	}

	my @tmp;
	foreach (@components) {
	    if ($SUITES{$_}) {
		set_param_once( $input, \%params_set, 'suite', $_);
#possible conflicts with package names
#	    } elsif (my $s = $SUITES_ALIAS{$_}) {
#		set_param_once( $input, \%params_set, 'suite', $s);
	    } elsif ($SECTIONS{$_}) {
		set_param_once( $input, \%params_set, 'section', $_);
	    } elsif ($ARCHIVES{$_}) {
		set_param_once( $input, \%params_set, 'archive', $_);
	    } elsif ($ARCHITECTURES{$_}) {
		set_param_once( $input, \%params_set, 'arch', $_);
	    } elsif ($sections_descs{$_}) {
		set_param_once( $input, \%params_set, 'subsection', $_);
	    } elsif ($_ eq 'source') {
		set_param_once( $input, \%params_set, 'source', 1);
	    } else {
		push @tmp, $_;
	    }
	}
	@components = @tmp;

	if (@components > 1) {
	    fatal_error( "two or more packages specified (@components)" );
	}
    } # else if (@components == 1)
    
    if (@components) {
	$input->param( 'keywords', $components[0] );
	$input->param( 'package', $components[0] );
    }
}

my ( $pkg, @suites, @sections, @subsections, @archives, @archs );

my %params_def = ( keywords => { default => undef,
				 match => '^\s*([-+\@\s\w\/.:]+)\s*$',
			     },
		   package => { default => undef,
				match => '^([\w.+-]+)$',
				var => \$pkg },
		   suite => { default => 'all', match => '^([\w-]+)$',
			      array => ',', var => \@suites,
			      replace => { all => \@SUITES } },
		   archive => { default => ($what_to_do eq 'search') ?
				    'all' : 'default',
				    match => '^([\w-]+)$',
				    array => ',', var => \@archives,
				    replace => { all => \@ARCHIVES,
					     default => [qw(us security non-US)]} },
		   exact => { default => 0, match => '^(\w+)$',  },
		   source => { default => 0, match => '^(\d+)$',  },
		   searchon => { default => 'names', match => '^(\w+)$', },
		   section => { default => 'all', match => '^([\w-]+)$',
				alias => 'release', array => ',',
				var => \@sections,
				replace => { all => \@SECTIONS } },
		   subsection => { default => 'default', match => '^([\w-]+)$',
				   array => ',', var => \@subsections,
				   replace => { default => [] } },
		   arch => { default => 'any', match => '^(\w+)$',
			     array => ',', var => \@archs, replace =>
			     { any => \@ARCHITECTURES } },
		   );
my %opts;
my %params = Packages::Search::parse_params( $input, \%params_def, \%opts );

$opts{h_suites} = { map { $_ => 1 } @suites };
$opts{h_sections} = { map { $_ => 1 } @sections };
$opts{h_archives} = { map { $_ => 1 } @archives };
$opts{h_archs} = { map { $_ => 1 } @archs };

if ((($opts{searchon} eq 'names') && $opts{source}) ||
    ($opts{searchon} eq 'sourcenames')) {
    $opts{source} = 1;
    $opts{searchon} = 'names',
    $opts{searchon_form} = 'sourcenames';
} else {
    $opts{searchon_form} = $opts{searchon};
}

my $pet1 = new Benchmark;
my $petd = timediff($pet1, $pet0);
debug( "Parameter evaluation took ".timestr($petd) );

print $input->header( -charset => 'utf-8' );

my (%html_header, $menu, $page_content);
unless (@Packages::CGI::fatal_errors) {
    no strict 'refs';
    &{"do_$what_to_do"}( \%params, \%opts, \%html_header,
			 \$menu, \$page_content );
} else {
    %html_header = ( title => 'Error',
		     lang => 'en',
		     print_title => 1,
		     print_search_field => 'packages',
		     search_field_values => { 
			 keywords => 'search for a package',
			 searchon => 'default',
			 arch => 'any',
			 suite => 'all',
			 section => 'all',
			 exact => 1,
			 debug => $debug,
		     },
		     );
}

print Packages::HTML::header( %html_header );

print $menu||'';
print_errors();
print_hints();
print_msgs();
print_debug();
print_notes();

unless (@Packages::CGI::fatal_errors) {
    print $page_content;
}

my $tet1 = new Benchmark;
my $tetd = timediff($tet1, $tet0);
print "Total page evaluation took ".timestr($tetd)."<br>"
    if $debug_allowed;

my $trailer = Packages::HTML::trailer( $ROOT );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e; #FIXME
print $trailer;

# vim: ts=8 sw=4

