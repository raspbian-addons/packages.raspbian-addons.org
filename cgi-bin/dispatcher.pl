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
use Benchmark ':hireswallclock';
use I18N::AcceptLanguage;
use Locale::gettext;

use Deb::Versions;
use Packages::Config qw( $DBDIR $ROOT @SUITES @SECTIONS @ARCHIVES @ARCHITECTURES @LANGUAGES $LOCALES );
use Packages::CGI;
use Packages::DB;
use Packages::Search qw( :all );
use Packages::HTML ();
use Packages::Sections;
use Packages::I18N::Locale;

use Packages::DoSearch;
use Packages::DoSearchContents;
use Packages::DoShow;
use Packages::DoIndex;
use Packages::DoNewPkg;
use Packages::DoDownload;
use Packages::DoFilelist;

&Packages::CGI::reset;

# clean up env
$ENV{PATH} = "/bin:/usr/bin";
delete $ENV{'LANGUAGE'};
delete $ENV{'LANG'};
delete $ENV{'LC_ALL'};
delete $ENV{'LC_MESSAGES'};

# Read in all the variables set by the form
my $input;
if ($ARGV[0] && ($ARGV[0] eq 'php')) {
	$input = new CGI(\*STDIN);
} else {
	$input = new CGI;
}

my $pet0 = new Benchmark;
my $tet0 = new Benchmark;
my $debug = DEBUG && $input->param("debug");
$debug = 0 if !defined($debug) || $debug !~ /^\d+$/o;
$Packages::CGI::debug = $debug;

&Packages::Config::init( '../' );
&Packages::DB::init();

my $acc = I18N::AcceptLanguage->new();
my $http_lang = $acc->accepts( $input->http("Accept-Language"),
			       \@LANGUAGES ) || 'en';
debug( "LANGUAGES=@LANGUAGES header=".
       ($input->http("Accept-Language")||'').
       " http_lang=$http_lang", 2 ) if DEBUG;
bindtextdomain ( 'pdo', $LOCALES );
textdomain( 'pdo' );

my $what_to_do = 'show';
my $source = 0;
if (my $path = $input->path_info() || $input->param('PATH_INFO')) {
    my @components = grep { $_ } map { lc $_ } split /\/+/, $path;

    push @components, 'index' if $path =~ m,/$,;

    my %LANGUAGES = map { $_ => 1 } @LANGUAGES;
    if (@components > 0 and $LANGUAGES{$components[0]}) {
	$input->param( 'lang', shift(@components) );
    }
    if (@components > 0 and $components[0] eq 'source') {
	shift @components;
	$input->param( 'source', 1 );
    }
    if (@components > 0 and $components[0] eq 'search') {
	shift @components;
	$what_to_do = 'search';
	# Done
	fatal_error( _g( "search doesn't take any more path elements" ) )
	    if @components;
    } elsif (@components == 0) {
	fatal_error( _g( "We're supposed to display the homepage here, instead of getting dispatch.pl" ) );
    } elsif (@components == 1) {
	$what_to_do = 'search';
    } else {

	for ($components[-1]) {
	    /^(index|allpackages|newpkg|changelog|copyright|download|filelist)$/ && do {
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
	    debug("set_param_once key=$key val=$val",4) if DEBUG;
	    if ($params_set->{$key}++) {
		fatal_error( sprintf( _g( "%s set more than once in path" ), $key ) );
	    } else {
		$cgi->param( $key, $val );
	    }
	}

	my (@pkg, $need_pkg);
	foreach (reverse @components) {
	    $need_pkg = !@pkg
		&& ($what_to_do !~ /^(index|allpackages|newpkg)$/);
	    debug("need_pkg=$need_pkg component=$_",4) if DEBUG;
	    if (!$need_pkg && $SUITES{$_}) {
		set_param_once( $input, \%params_set, 'suite', $_);
	    } elsif (!$need_pkg && (my $s = $SUITES_ALIAS{$_})) {
		set_param_once( $input, \%params_set, 'suite', $s);
	    } elsif (!$need_pkg && $SECTIONS{$_}) {
		set_param_once( $input, \%params_set, 'section', $_);
	    } elsif (!$need_pkg && $ARCHIVES{$_}) {
		set_param_once( $input, \%params_set, 'archive', $_);
	    } elsif (!$need_pkg && $sections_descs{$_}) {
		set_param_once( $input, \%params_set, 'subsection', $_);
	    } elsif (!$need_pkg && ($_ eq 'non-us')) { # non-US hack
		set_param_once( $input, \%params_set, 'subsection', 'non-US');
	    } elsif (!$need_pkg && ($_ eq 'source')) {
		set_param_once( $input, \%params_set, 'source', 1);
	    } elsif ($ARCHITECTURES{$_}) {
		set_param_once( $input, \%params_set, 'arch', $_);
	    } else {
		push @pkg, $_;
	    }
	}
	@components = @pkg;

	if (@components > 1) {
	    fatal_error( sprintf( _g( "two or more packages specified (%s)" ), "@components" ) );
	}
    } # else if (@components == 1)
    
    if (@components) {
	$input->param( 'keywords', $components[0] );
	$input->param( 'package', $components[0] );
    }
}

my ( $pkg, @suites, @sections, @subsections, @archives, @archs );

my %params_def = ( keywords => { default => undef,
				 array => '\s+',
				 match => '^([-+\@\w\/.:]+)$',
			     },
		   package => { default => undef,
				match => '^([\w.+-]+)$',
				var => \$pkg },
		   suite => { default => 'default', match => '^([\w-]+)$',
			      array => ',', var => \@suites,
			      replace => { all => \@SUITES,
					   default => \@SUITES } },
		   archive => { default => ($what_to_do eq 'search') ?
				    'all' : 'default',
				    match => '^([\w-]+)$',
				    array => ',', var => \@archives,
				    replace => { all => \@ARCHIVES,
						 default => \@ARCHIVES} },
		   exact => { default => 0, match => '^(\w+)$',  },
		   lang => { default => $http_lang, match => '^(\w+)$',  },
		   source => { default => 0, match => '^(\d+)$',  },
		   debug => { default => 0, match => '^(\d+)$',  },
		   searchon => { default => 'names', match => '^(\w+)$', },
		   section => { default => 'all', match => '^([\w-]+)$',
				alias => 'release', array => ',',
				var => \@sections,
				replace => { all => \@SECTIONS } },
		   subsection => { default => 'default', match => '^([\w-]+)$',
				   array => ',', var => \@subsections,
				   replace => { default => [] } },
		   arch => { default => 'any', match => '^([\w-]+)$',
			     array => ',', var => \@archs, replace =>
			     { any => \@ARCHITECTURES } },
		   format => { default => 'html', match => '^([\w.]+)$',  },
		   mode => { default => undef, match => '^(\w+)$',  },
		   );
my %opts;
my %params = Packages::CGI::parse_params( $input, \%params_def, \%opts );
Packages::CGI::init_url( $input, \%params, \%opts );

my $locale = get_locale($opts{lang});
my $charset = get_charset($opts{lang});
setlocale ( LC_ALL, $locale )
    or do { debug( "couldn't set locale $locale, using default" ) if DEBUG;
	    setlocale( LC_ALL, get_locale() )
		or do {
		    debug( "couldn't set default locale either" ) if DEBUG;
		    setlocale( LC_ALL, "C" );
		};
	};
debug( "locale=$locale charset=$charset", 2 ) if DEBUG;

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
if ($opts{searchon} eq 'contents' or $opts{searchon} eq 'filenames') {
    $what_to_do = 'search_contents';
}

my $pet1 = new Benchmark;
my $petd = timediff($pet1, $pet0);
debug( "Parameter evaluation took ".timestr($petd) ) if DEBUG;

my (%html_header, $menu, $page_content);
unless (@Packages::CGI::fatal_errors) {
    no strict 'refs';
    &{"do_$what_to_do"}( \%params, \%opts, \%html_header,
			 \$menu, \$page_content );
} else {
    %html_header = ( title => _g('Error'),
		     lang => $opts{lang},
		     print_title => 1,
		     print_search_field => 'packages',
		     search_field_values => { 
			 keywords => _g('search for a package'),
			 searchon => 'default',
			 arch => 'any',
			 suite => 'all',
			 section => 'all',
			 exact => 1,
			 debug => $debug,
		     },
		     );
}

print $input->header( -charset => $charset );

print Packages::HTML::header( %html_header );

print $menu||'';
print_errors();
print_hints();
print_msgs();
print_debug() if DEBUG;
print_notes();

unless (@Packages::CGI::fatal_errors) {
    print $page_content;
}

my $tet1 = new Benchmark;
my $tetd = timediff($tet1, $tet0);
print "Total page evaluation took ".timestr($tetd)."<br>"
    if DEBUG;

my $trailer = Packages::HTML::trailer( $ROOT );
$trailer =~ s/LAST_MODIFIED_DATE/gmtime()/e; #FIXME
print $trailer;

# vim: ts=8 sw=4

