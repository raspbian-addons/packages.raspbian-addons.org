package Packages::DoSearchContents;

use strict;
use warnings;

use Benchmark;
use DB_File;
use URI::Escape;
use HTML::Entities;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_search_contents );

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::CGI;
use Packages::DB;
use Packages::Config qw( $DBDIR $SEARCH_URL $SEARCH_CGI $SEARCH_PAGE
			 @SUITES @ARCHIVES $ROOT );

sub do_search_contents {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{keywords}) {
	fatal_error( "keyword not valid or missing" );
    } elsif (length($opts->{keywords}) < 2) {
	fatal_error( "keyword too short (keywords need to have at least two characters)" );
    }

    $$menu = "";
    
    my $keyword = $opts->{keywords};
    my $searchon = $opts->{searchon};
    my $exact = $opts->{exact};

    # for URL construction
    my $keyword_esc = uri_escape( $keyword );
    my $suites_param = join ',', @{$params->{values}{suite}{no_replace}};
    my $sections_param = join ',', @{$params->{values}{section}{no_replace}};
    my $archs_param = join ',', @{$params->{values}{arch}{no_replace}};

    # for output
    my $keyword_enc = encode_entities $keyword || '';
    my $searchon_enc = encode_entities $searchon;
    my $suites_enc = encode_entities( join( ', ', @{$params->{values}{suite}{no_replace}} ) );
    my $sections_enc = encode_entities( join( ', ', @{$params->{values}{section}{no_replace}} ) );
    my $archs_enc = encode_entities( join( ', ',  @{$params->{values}{arch}{no_replace}} ) );
    
    my $st0 = new Benchmark;
    my (@results, @non_results);

    unless (@Packages::CGI::fatal_errors) {

	my $nres = 0;

	my $kw = lc $keyword;
	# full filename search is tricky
	my $ffn = $searchon eq 'filenames';

	my $suite = 'stable'; #fixme

	my $reverses = tie my %reverses, 'DB_File', "$DBDIR/contents/reverse_$suite.db",
	    O_RDONLY, 0666, $DB_BTREE
	    or die "Failed opening reverse DB: $!";

	if ($ffn) {
	    open FILENAMES, '-|', 'fgrep', '--', "$kw", "$DBDIR/contents/filenames_$suite.txt"
		or die "Failed opening filename table: $!";
	    while (<FILENAMES>) {
		chomp;
		last unless &searchfile(\@results, reverse($_)."/", \$nres, $reverses);
	    }
	    close FILENAMES;
	} else {

	    $kw = reverse $kw;
	    
	    # exact filename searching follows trivially:
	    $kw = "$kw/" if $exact;

	    print "ERROR: Exact and fullfilenamesearch don't go along" if $ffn and $exact;

	    &searchfile(\@results, $kw, \$nres, $reverses);
	}
	$reverses = undef;
	untie %reverses;

    
	my $st1 = new Benchmark;
	my $std = timediff($st1, $st0);
	debug( "Search took ".timestr($std) );
    }
    
    my $suite_wording = $suites_enc eq "all" ? "all suites"
	: "suite(s) <em>$suites_enc</em>";
    my $section_wording = $sections_enc eq 'all' ? "all sections"
	: "section(s) <em>$sections_enc</em>";
    my $arch_wording = $archs_enc eq 'any' ? "all architectures"
	: "architecture(s) <em>$archs_enc</em>";
    my $wording = $opts->{exact} ? "exact filenames" : "filenames that contain";
    $wording = "paths that end with" if $searchon eq "contents";
    msg( "You have searched for ${wording} <em>$keyword_enc</em> in $suite_wording, $section_wording, and $arch_wording." );

    if ($Packages::Search::too_many_hits) {
	error( "Your search was too wide so we will only display exact matches. At least <em>$Packages::Search::too_many_hits</em> results have been omitted and will not be displayed. Please consider using a longer keyword or more keywords." );
    }
    
    $$page_content = '';
    if (!@Packages::CGI::fatal_errors && !@results) {
	$$page_content .= "No results";
    }

    %$html_header = ( title => 'Package Contents Search Results' ,
		      lang => 'en',
		      title_tag => 'Debian Package Contents Search Results',
		      print_title => 1,
		      print_search_field => 'packages',
		      search_field_values => { 
			  keywords => $keyword_enc,
			  searchon => 'contents',
			  arch => $archs_enc,
			  suite => $suites_enc,
			  section => $sections_enc,
			  exact => $opts->{exact},
			  debug => $opts->{debug},
		      },
		      );

    if (@results) {
	$$page_content .= scalar @results . " results displayed:<br>";
	foreach (@results) {
	    $$page_content .= "<tt>$_</tt><br>\n";
	}
    }
} # sub do_search_contents

sub searchfile
{
    my ($results, $kw, $nres, $reverses) = @_;

    my ($key, $value) = ($kw, "");
    for (my $status = $reverses->seq($key, $value, R_CURSOR);
	$status == 0;
    	$status =  $reverses->seq( $key, $value, R_NEXT)) {

	# FIXME: what's the most efficient "is prefix of" thingy? We only want to know
	# whether $kw is or is not a prefix of $key
	last unless index($key, $kw) == 0;

	my @hits = split /\0/o, $value;
	push @$results, reverse($key)." is found in @hits";
	last if ($$nres)++ > 100;
    }

# FIXME: use too_many_hits
    return $$nres<100;
}


1;
