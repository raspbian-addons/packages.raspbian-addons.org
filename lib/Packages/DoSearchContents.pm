package Packages::DoSearchContents;

use strict;
use warnings;

use Benchmark ':hireswallclock';
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
    if ($params->{errors}{suite}) {
	fatal_error( "suite not valid or not specified" );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( "more than one suite specified for contents search (@{$opts->{suite}})" );
    }

    $$menu = "";
    
    my $keyword = $opts->{keywords};
    my $searchon = $opts->{searchon};
    my $exact = $opts->{exact};
    my $suite = $opts->{suite}[0];
    my $archive = $opts->{archive}[0] ||'';
    $Packages::Search::too_many_hits = 0;

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
    my (@results);

    unless (@Packages::CGI::fatal_errors) {

	my $nres = 0;

	my $kw = lc $keyword;
	# full filename search is tricky
	my $ffn = $searchon eq 'filenames';

	my $reverses = tie my %reverses, 'DB_File', "$DBDIR/contents/reverse_$suite.db",
	    O_RDONLY, 0666, $DB_BTREE
	    or die "Failed opening reverse DB: $!";

	if ($ffn) {
	    open FILENAMES, '-|', 'fgrep', '--', $kw, "$DBDIR/contents/filenames_$suite.txt"
		or die "Failed opening filename table: $!";

	    error( "Exact and fullfilenamesearch don't go along" )
		if $ffn and $exact;

	    while (<FILENAMES>) {
		chomp;
		&searchfile(\@results, reverse($_)."/", \$nres, $reverses);
		last if $Packages::Search::too_many_hits;
	    }
	    close FILENAMES or warn "fgrep error: $!\n";
	} else {

	    $kw = reverse $kw;
	    
	    # exact filename searching follows trivially:
	    $kw = "$kw/" if $exact;

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
	error( "Your search was too wide so we will only display only the first about 100 matches. Please consider using a longer keyword or more keywords." );
    }
    
    if (!@Packages::CGI::fatal_errors && !@results) {
	error( "Nothing found" );
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

    $$page_content = '';
    if (@results) {
	$$page_content .= "<p>Found ".scalar(@results)." results</p>";
	$$page_content .= "<div  id=\"pcontentsres\"><table><colgroup><col><col></colgroup><tr><th>File</th><th>Packages</th></tr>";
	foreach my $result (sort { $a->[0] cmp $b->[0] } @results) {
	    my $file = shift @$result;
	    $$page_content .= "<tr><td class=\"file\">$file</td><td>";
	    my %pkgs;
	    foreach (@$result) {
		my ($pkg, $arch) = split /:/, $_;
		$pkgs{$pkg}{$arch}++;
	    }
	    $$page_content .= join( ", ", map { "<a href=\"$ROOT/$suite/$_\">$_</a>" } sort keys %pkgs);
	    $$page_content .= '</td>';
	}
	$$page_content .= '<tr><th>File</th><th>Packages</th></tr>' if @results > 20;
	$$page_content .= '</table></div>';
    }
} # sub do_search_contents

sub searchfile
{
    my ($results, $kw, $nres, $reverses) = @_;

    my ($key, $value) = ($kw, "");
    debug( "searchfile: kw=$kw", 1 );
    for (my $status = $reverses->seq($key, $value, R_CURSOR);
	$status == 0;
    	$status =  $reverses->seq( $key, $value, R_NEXT)) {

	# FIXME: what's the most efficient "is prefix of" thingy? We only want to know
	# whether $kw is or is not a prefix of $key
	last unless index($key, $kw) == 0;
	debug( "found $key", 2 );

	my @hits = split /\0/o, $value;
	push @$results, [ scalar reverse($key), @hits ];
	last if ($$nres)++ > 100;
    }

    $Packages::Search::too_many_hits += $$nres - 100 if $$nres > 100;
}


1;
