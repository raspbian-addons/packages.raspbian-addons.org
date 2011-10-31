#!/usr/bin/perl -T
# Packages::Dispatcher -- CGI interface for packages.debian.org
#
# Copyright (C) 2004-2008 Frank Lichtenheld
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 1 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Packages::Dispatcher;

use strict;
use warnings;

use CGI;
use POSIX;
use File::Basename;
use Template;
use DB_File;
use URI::Escape;
use Benchmark ':hireswallclock';
use I18N::AcceptLanguage;
use Date::Parse;

use Deb::Versions;
use Packages::Config qw( $DBDIR $ROOT $TEMPLATEDIR $CACHEDIR
			 @SUITES @SECTIONS @ARCHIVES @ARCHITECTURES @PRIORITIES
			 @LANGUAGES @DDTP_LANGUAGES );
use Packages::CGI qw( :DEFAULT error get_all_messages );
use Packages::DB;
use Packages::Search qw( :all );
use Packages::Template ();
use Packages::Sections;
use Packages::I18N::Locale;

use Packages::DoSearch;
use Packages::DoSearchContents;
use Packages::DoShow;
use Packages::DoIndex;
use Packages::DoNewPkg;
use Packages::DoDownload;
use Packages::DoFilelist;


sub do_dispatch {

    &Packages::CGI::reset;
    $Packages::Search::too_many_hits = 0;

    # clean up env
    $ENV{PATH} = "/bin:/usr/bin";
    delete $ENV{'LANGUAGE'};
    delete $ENV{'LANG'};
    delete $ENV{'LC_ALL'};
    delete $ENV{'LC_MESSAGES'};

    my %SUITES_ALIAS = ( oldstable => 'lenny',
			 stable => 'squeeze',
			 testing => 'wheezy',
			 unstable => 'sid',
			 'rc-buggy' => 'experimental',
			 '5.0' => 'lenny',
			 '6.0' => 'squeeze',
			 'oldstable-backports' => 'lenny-backports',
			 'stable-backports' => 'squeeze-backports' );

    # Read in all the variables set by the form
    my $input;
    if ($ARGV[0] && ($ARGV[0] eq 'php')) {
	$input = new CGI(\*STDIN);
    } else {
	$input = new CGI;
    }
    my $cgi_error = $input->cgi_error;
    if ($cgi_error) {
	fatal_error( "Error parsing the request", $cgi_error );
    }

    my $pet0 = new Benchmark;
    my $tet0 = new Benchmark;
    my $debug = DEBUG && $input->param("debug");
    $debug = 0 if !defined($debug) || $debug !~ /^\d+$/o;
    $Packages::CGI::debug = $debug;

    my $homedir = dirname($ENV{SCRIPT_FILENAME}).'/../';
    &Packages::Config::init( $homedir );
    &Packages::DB::init();
    my $last_modified = $Packages::DB::db_read_time;
    my $now = time;
    my $expires = $last_modified + (12*3600);
    $expires = $now + 3600 if $expires < $now;
    # allow some fudge, since the db mod time is not the end of
    # the cron job
    $last_modified = $now if $now - $last_modified < 3600;

    if ($input->http('If-Modified-Since') and
	(my $client_timestamp = str2time($input->http('If-Modified-Since'), 'UTC'))) {
	if ($client_timestamp > $last_modified) {
	    # we are not modified since asked -> return "304 Not Modified"
	    print $input->header(-status => 304);
	    exit;
	}
    }

    my %PO_LANGUAGES = map { $_ => 1 } @LANGUAGES;
    my %DDTP_LANGUAGES = map { $_ => 1 } @DDTP_LANGUAGES;
    my $acc = I18N::AcceptLanguage->new(defaultLanguage => 'en');
    my $ddtp_lang = $acc->accepts( $input->http("Accept-Language"),
				   \@DDTP_LANGUAGES );
    my $po_lang = $acc->accepts( $input->http("Accept-Language"),
				 \@LANGUAGES );
    debug( "LANGS=@LANGUAGES DDTP_LANGS=@DDTP_LANGUAGES header=".
	   ($input->http("Accept-Language")||'').
	   " po_lang=$po_lang ddtp_lang=$ddtp_lang", 1 ) if DEBUG;

    # backwards compatibility stuff
    debug( "SCRIPT_URL=$ENV{SCRIPT_URL} SCRIPT_URI=$ENV{SCRIPT_URI}" ) if DEBUG;

    if ($ENV{SCRIPT_URL} =~ m|^/cgi-bin/search_|) {
	error( "You reached this site over an old URL. ".
	       "Depending on the exact parameters your search might work or not." );
	# contents search changed a lot
	if ($ENV{SCRIPT_URL} =~ m|^/cgi-bin/search_contents|) {
	    $input->param('keywords',$input->param('word')) if $input->param('word');
	    $input->param('searchon','contents');
	    for ($input->param('searchmode')) {
		/^searchfiles/ && do {
		    $input->param('mode','filename');
		    last;
		};
		/^filelist/ && do {
		    $ENV{PATH_INFO} = '/'.join('/',($input->param('version')||'stable',
						    $input->param('keywords'),
						    $input->param('arch')||'i386',
						    'filelist' ));
		    $input->delete('searchon','version','keywords','arch');
		    last;
		};
	    }
	}
    }
    if ($ENV{is_reportbug}) {
	$input->param('exact', 1);
	debug( "reportbug detected, set paramater exact to '1'" ) if DEBUG;
    }

    my $what_to_do = 'show';
    my $source = 0;
    if (my $path = $ENV{'PATH_INFO'} || $input->param('PATH_INFO')) {
	my @components = grep { $_ } map { lc $_ } split /\/+/, $path;

	debug( "PATH_INFO=$path components=@components", 3) if DEBUG;

	push @components, 'index' if @components && $path =~ m,/$,;

	my %LANGUAGES = map { $_ => 1 } (@LANGUAGES, @DDTP_LANGUAGES);
	if (@components > 1 and $LANGUAGES{$components[0]}
	    and !$input->param('lang')) {
	    $input->param( 'lang', shift(@components) );
	}
	if (@components > 1 and $components[0] eq 'source') {
	    shift @components;
	    $input->param( 'source', 1 );
	}
	if (@components > 0 and $components[0] eq 'search') {
	    shift @components;
	    $what_to_do = 'search';
	    # Done
	    fatal_error( "search doesn't take any more path elements" )
		if @components;
	} elsif (@components == 0) {
	    fatal_error( "We're supposed to display the homepage here, instead of getting dispatch.pl" );
	} elsif (@components == 1) {
	    if ($components[0] eq 'index') {
		$what_to_do = 'homepage';
	    } else {
		$what_to_do = 'search';
	    }
	} else {

	    for ($components[-1]) {
		/^(index|allpackages|newpkg|changelog|copyright|download|filelist)$/ && do {
		    pop @components;
		    $what_to_do = $1;
		    last;
		};
	    }

	    my %SUITES = map { $_ => 1 } @SUITES;
	    my %SECTIONS = map { $_ => 1 } @SECTIONS;
	    my %ARCHIVES = map { $_ => 1 } @ARCHIVES;
	    my %ARCHITECTURES = map { $_ => 1 } (@ARCHITECTURES, 'all', 'any');
	    my %PRIORITIES = map { $_ => 1 } @PRIORITIES;
	    my %params_set;
	    sub set_param_once {
		my ($cgi, $params_set, $key, $val) = @_;
		debug("set_param_once key=$key val=$val",4) if DEBUG;
		if ($params_set->{$key}++) {
		    fatal_error( "$key set more than once in path" );
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
		} elsif (!$need_pkg && $sections_descs{$_}) {
		    set_param_once( $input, \%params_set, 'subsection', $_);
		} elsif (!$need_pkg && ($_ eq 'source')) {
		    set_param_once( $input, \%params_set, 'source', 1);
		} elsif ($ARCHITECTURES{$_}) {
		    set_param_once( $input, \%params_set, 'arch', $_)
			unless $_ eq 'any';
		} elsif (!$need_pkg && $ARCHIVES{$_}) {
		    set_param_once( $input, \%params_set, 'archive', $_);
		} elsif ($PRIORITIES{$_}) {
		    set_param_once( $input, \%params_set, 'priority', $_);
		} else {
		    push @pkg, $_;
		}
	    }
	    @components = @pkg;

	    if (@components > 1) {
		fatal_error( "two or more packages specified (@components)" );
	    }
	} # else if (@components == 1)

	if (@components) {
	    my $c = uri_unescape($components[0]);
	    $input->param( 'keywords', $c );
	    $input->param( 'package', $c );
	}
    }

    my ( $pkg, @suites, @sections, @subsections, @archives, @archs );

    my %params_def = ( keywords => { default => undef,
				     array => '\s+',
				     match => '^([-+\@\w\/.:]+)$',
				 },
		       'package' => { default => undef,
				      match => '^([\w.+-]+)$',
				      var => \$pkg },
		       suite => { default => 'default', match => '^([\w-]+)$',
				  array => ',', var => \@suites,
				  replace => { all => \@SUITES,
					       default => \@SUITES,
					       %SUITES_ALIAS } },
		       archive => { default => ($what_to_do eq 'search') ?
					'all' : 'default',
					match => '^([\w-]+)$',
					array => ',', var => \@archives,
					replace => { all => \@ARCHIVES,
						     default => \@ARCHIVES} },
		       exact => { default => 0, match => '^(\w+)$',  },
		       lang => { default => undef, match => '^([\w-]+)$',  },
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
		       priority => { default => 'default', match => '^([\w-]+)$',
				     array => ',',
				     replace => { default => [] } },
		       arch => { default => 'any', match => '^([\w-]+)$',
				 array => ',', var => \@archs, replace =>
				 { any => \@ARCHITECTURES } },
		       'format' => { default => 'html', match => '^([\w.]+)$',  },
		       mode => { default => '', match => '^(\w+)$',  },
		       sort_by => { default => 'file', match => '^(\w+)$', },
		       );
    my %opts;
    my %params = Packages::CGI::parse_params( $input, \%params_def, \%opts );
    Packages::CGI::init_url( $input, \%params, \%opts );

    if (defined($opts{lang})) {
	$opts{po_lang} = $PO_LANGUAGES{$opts{lang}} ? $opts{lang} : 'en';
	$opts{ddtp_lang} = $DDTP_LANGUAGES{$opts{lang}} ? $opts{lang} : 'en';
    } else {
	$opts{po_lang} = $po_lang;
	$opts{ddtp_lang} = $ddtp_lang;
    }
    my $charset = "UTF-8";
    my $cat = Packages::I18N::Locale->get_handle( $opts{po_lang}, 'en' )
	or die "get_handle failed for $opts{po_lang}";
    $opts{cat} = $cat;

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

    my $template = new Packages::Template( $TEMPLATEDIR, $opts{format},
					   { po_lang => $opts{po_lang}, ddtp_lang => $opts{ddtp_lang},
					     charset => $charset, cat => $cat,
					     debug => ( DEBUG ? $opts{debug} : 0 ) },
					   ( $CACHEDIR ? { COMPILE_DIR => $CACHEDIR } : {} ) );

    #FIXME: ugly hack
    unless (($what_to_do eq 'allpackages' and $opts{format} =~ /^(html|txt\.gz)/)
	    || ($what_to_do eq 'index' and $opts{format} eq 'html')
	    || -e "$TEMPLATEDIR/$opts{format}/${what_to_do}.tmpl") {
	fatal_error( $cat->g("requested format not available for this document"),
		     "406 requested format not available");
    }

    my (%page_content);
    unless (@Packages::CGI::fatal_errors) {
	no strict 'refs';
	&{"do_$what_to_do"}( \%params, \%opts, \%page_content );
    }

    $page_content{opts} = \%opts;
    $page_content{params} = \%params;

    unless (@Packages::CGI::fatal_errors) {
	print $input->header(-charset => $charset,
			     -type => get_mime($opts{format}),
			     -vary => 'negotiate,accept-language',
			     -last_modified => strftime("%a, %d %b %Y %T %z",
							localtime($last_modified)),
			     -expires => strftime("%a, %d %b %Y %T %z",
						  localtime($expires)),
			     );
	#use Data::Dumper;
	#print '<pre>'.Dumper(\%ENV, \%page_content, get_all_messages()).'</pre>';
	print $template->page( $what_to_do, { %page_content, %{ get_all_messages() } } );
    } elsif ($Packages::CGI::http_code && $Packages::CGI::http_code !~ /^2\d\d/) {
	print $input->header( -charset => $charset, -status => $Packages::CGI::http_code );
    } else {
	# We currently have only an error page in html
	# so no format support here
	print $input->header( -charset => $charset );
	print $template->error_page( get_all_messages() );
    }
}

1;
# vim: ts=8 sw=4
