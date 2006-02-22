package Packages::Config;

use strict;
use warnings;

use Exporter;
use Packages::CGI;

our @ISA = qw( Exporter );

our ( $TOPDIR, $DBDIR, $ROOT, $HOME, $CONTACT_MAIL, $WEBMASTER_MAIL,
      $SEARCH_PAGE, $SEARCH_URL, @LANGUAGES, $LOCALES,
      $SRC_SEARCH_URL, $CONTENTS_SEARCH_CGI,
      $CN_HELP_URL, $BUG_URL, $SRC_BUG_URL, $QA_URL, $DDPO_URL,
      @SUITES, @SECTIONS, @ARCHIVES, @ARCHITECTURES,
      %FTP_SITES );
our @EXPORT_OK = qw( $TOPDIR $DBDIR $ROOT $HOME $CONTACT_MAIL
		     $WEBMASTER_MAIL @LANGUAGES $LOCALES
		     $SEARCH_PAGE $SEARCH_URL
		     $SRC_SEARCH_URL $CONTENTS_SEARCH_CGI
		     $CN_HELP_URL $BUG_URL $SRC_BUG_URL $QA_URL $DDPO_URL
		     @SUITES @SECTIONS @ARCHIVES @ARCHITECTURES
		     %FTP_SITES  );
our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

our $config_read_time;

sub init {
    my ($dir) = @_;
    my $modtime = (stat( "$dir/config.sh" ))[9];
    $config_read_time ||= 0;
    if ($modtime > $config_read_time) {
	if (!open (C, '<', "$dir/config.sh")) {
	    error( "Internal: Cannot open configuration file." );
	}
	while (<C>) {
	    next if /^\s*\#/o;
	    chomp;
	    $TOPDIR = $1 if /^\s*topdir="?([^\"]*)"?\s*$/o;
	    $ROOT = $1 if /^\s*root="?([^\"]*)"?\s*$/o;
	    $HOME = $1 if /^\s*home="?([^\"]*)"?\s*$/o;
	    $LOCALES = $1 if /^\s*localedir="?([^\"]*)"?\s*$/o;
#	    $SEARCH_CGI = $1 if /^\s*search_cgi="?([^\"]*)"?\s*$/o;
	    $SEARCH_PAGE = $1 if /^\s*search_page="?([^\"]*)"?\s*$/o;
	    $SEARCH_URL = $1 if /^\s*search_url="?([^\"]*)"?\s*$/o;
	    $SRC_SEARCH_URL = $1 if /^\s*search_src_url="?([^\"]*)"?\s*$/o;
	    $WEBMASTER_MAIL = $1 if /^\s*webmaster="?([^\"]*)"?\s*$/o;
	    $CONTACT_MAIL = $1 if /^\s*contact="?([^\"]*)"?\s*$/o;
	    $BUG_URL = $1 if /^\s*bug_url="?([^\"]*)"?\s*$/o;
	    $SRC_BUG_URL = $1 if /^\s*src_bug_url="?([^\"]*)"?\s*$/o;
	    $QA_URL = $1 if /^\s*qa_url="?([^\"]*)"?\s*$/o;
	    $DDPO_URL = $1 if /^\s*ddpo_url="?([^\"]*)"?\s*$/o;
	    $CN_HELP_URL = $1 if /^\s*cn_help_url="?([^\"]*)"?\s*$/o;
	    $FTP_SITES{us} = $1 if /^\s*ftpsite="?([^\"]*)"?\s*$/o;
	    $FTP_SITES{$1} = $2 if /^\s*(\w+)_ftpsite="?([^\"]*)"?\s*$/o;
	    @LANGUAGES = split(/\s+/, $1) if /^\s*polangs="?([^\"]*)"?\s*$/o;
	    @SUITES = split(/\s+/, $1) if /^\s*suites="?([^\"]*)"?\s*$/o;
	    @SECTIONS = split(/\s+/, $1) if /^\s*sections="?([^\"]*)"?\s*$/o;
	    @ARCHIVES = split(/\s+/, $1) if /^\s*archives="?([^\"]*)"?\s*$/o;
	    @ARCHITECTURES = split(/\s+/, $1) if /^\s*architectures="?([^\"]*)"?\s*$/o;
	}
	close (C);
	debug( "read config ($modtime > $config_read_time)" );
	$config_read_time = $modtime;
    }
    $DBDIR = "$TOPDIR/files/db";
    unshift @LANGUAGES, 'en';
}

1;
