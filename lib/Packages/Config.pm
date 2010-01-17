package Packages::Config;

use strict;
use warnings;

use Exporter;
use Packages::CGI qw( :DEFAULT error );

our @ISA = qw( Exporter );

our ( $TOPDIR, $DBDIR, $TEMPLATEDIR, $CACHEDIR, $ROOT, $SEARCH_URL,
      @LANGUAGES, @DDTP_LANGUAGES,
      @SUITES, @SECTIONS, @ARCHIVES, @ARCHITECTURES,
      @PRIORITIES, %FTP_SITES );
our @EXPORT_OK = qw( $TOPDIR $DBDIR $TEMPLATEDIR $CACHEDIR $ROOT $SEARCH_URL
		     @LANGUAGES @DDTP_LANGUAGES
		     @SUITES @SECTIONS @ARCHIVES @ARCHITECTURES
		     @PRIORITIES %FTP_SITES  );
our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

our $config_read_time;

sub init {
    my ($dir) = @_;
    my $modtime = (stat( "$dir/config.sh" ))[9] || 0;
    $config_read_time ||= 0;
    if ($modtime > $config_read_time) {
	if (!open (C, '<', "$dir/config.sh")) {
	    error( "Internal: Cannot open configuration file." );
	}
	while (<C>) {
	    next if /^\s*\#/o;
	    chomp;
	    $TOPDIR = $1 if /^\s*topdir="?([^\"]*)"?\s*$/o;
	    $TEMPLATEDIR = $1 if /^\s*templatedir="?([^\"]*)"?\s*$/o;
	    $CACHEDIR = $1 if /^\s*cachedir="?([^\"]*)"?\s*$/o;
	    $ROOT = $1 if /^\s*root="?([^\"]*)"?\s*$/o;
	    $SEARCH_URL = $1 if /^\s*search_url="?([^\"]*)"?\s*$/o;
	    $FTP_SITES{us} = $1 if /^\s*ftpsite="?([^\"]*)"?\s*$/o;
	    $FTP_SITES{$1} = $2 if /^\s*(\w+)_ftpsite="?([^\"]*)"?\s*$/o;
	    @LANGUAGES = split(/\s+/, $1) if /^\s*polangs="?([^\"]*)"?\s*$/o;
	    @DDTP_LANGUAGES = split(/\s+/, $1) if /^\s*ddtplangs="?([^\"]*)"?\s*$/o;
	    @SUITES = split(/\s+/, $1) if /^\s*suites="?([^\"]*)"?\s*$/o;
	    @SECTIONS = split(/\s+/, $1) if /^\s*sections="?([^\"]*)"?\s*$/o;
	    @ARCHIVES = split(/\s+/, $1) if /^\s*archives="?([^\"]*)"?\s*$/o;
	    @ARCHITECTURES = split(/\s+/, $1) if /^\s*architectures="?([^\"]*)"?\s*$/o;
	    @PRIORITIES = split(/\s+/, $1) if /^\s*priorities="?([^\"]*)"?\s*$/o;
	}
	foreach (($TEMPLATEDIR, $CACHEDIR)) {
	    s/\$\{?topdir\}?/$TOPDIR/g;
	}
	close (C);
	unshift @LANGUAGES, 'en';
	unshift @DDTP_LANGUAGES, 'en';
	debug( "read config ($modtime > $config_read_time)" ) if DEBUG;
	$config_read_time = $modtime;
    }
    $DBDIR = "$TOPDIR/files/db";
}

1;
