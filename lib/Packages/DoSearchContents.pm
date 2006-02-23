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
use Packages::I18N::Locale;
use Packages::Search qw( :all );
use Packages::CGI;
use Packages::DB;
use Packages::Config qw( $DBDIR $SEARCH_URL $SEARCH_PAGE
			 @SUITES @ARCHIVES $ROOT );

sub do_search_contents {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{keywords}) {
	fatal_error( _g( "keyword not valid or missing" ) );
    } elsif (length($opts->{keywords}) < 2) {
	fatal_error( _g( "keyword too short (keywords need to have at least two characters)" ) );
    }
    if ($params->{errors}{suite}) {
	fatal_error( _g( "suite not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( sprintf( _g( "more than one suite specified for contents search (%s)" ), "@{$opts->{suite}}" ) );
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

	    error( _g( "Exact and fullfilenamesearch don't go along" ) )
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
	debug( "Search took ".timestr($std) ) if DEBUG;
    }
    
    my $suite_wording = $suites_enc eq "all" ? _g("all suites")
	: sprintf(_g("suite(s) <em>%s</em>", $suites_enc) );
    my $section_wording = $sections_enc eq 'all' ? _g("all sections")
	: sprintf(_g("section(s) <em>%s</em>", $sections_enc) );
    my $arch_wording = $archs_enc eq 'any' ? _g("all architectures")
	: sprintf(_g("architecture(s) <em>%s</em>", $archs_enc) );
    my $wording = $opts->{exact} ? _g("exact filenames") : _g("filenames that contain");
    $wording = _g("paths that end with") if $searchon eq "contents";
    msg( sprintf( _g("You have searched for %s <em>%s</em> in %s, %s, and %s." ),
		  $wording, $keyword_enc,
		  $suite_wording, $section_wording, $arch_wording ) );

    if ($Packages::Search::too_many_hits) {
	error( _g( "Your search was too wide so we will only display only the first about 100 matches. Please consider using a longer keyword or more keywords." ) );
    }
    
    if (!@Packages::CGI::fatal_errors && !@results) {
	error( _g( "Nothing found" ) );
    }

    %$html_header = ( title => _g( 'Package Contents Search Results' ),
		      lang => $opts->{lang},
		      title_tag => _g( 'Debian Package Contents Search Results' ),
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
	$$page_content .= "<p>".sprintf( _g( 'Found %s results' ),
					 scalar @results )."</p>";
	$$page_content .= '<div
	id="pcontentsres"><table><colgroup><col><col></colgroup><tr><th>'._g('File').'</th><th>'._g('Packages')
	    .'</th></tr>';
	foreach my $result (sort { $a->[0] cmp $b->[0] } @results) {
	    my $file = shift @$result;
	    $$page_content .= "<tr><td class=\"file\">/$file</td><td>";
	    my %pkgs;
	    foreach (@$result) {
		my ($pkg, $arch) = split /:/, $_;
		$pkgs{$pkg}{$arch}++;
	    }
	    $$page_content .= join( ", ", map { "<a href=\"$ROOT/$suite/$_\">$_</a>" } sort keys %pkgs);
	    $$page_content .= '</td>';
	}
	$$page_content .= '<tr><th>'._g('File').'</th><th>'._g('Packages').'</th></tr>' if @results > 20;
	$$page_content .= '</table></div>';
    }
} # sub do_search_contents

sub searchfile
{
    my ($results, $kw, $nres, $reverses) = @_;

    my ($key, $value) = ($kw, "");
    debug( "searchfile: kw=$kw", 1 ) if DEBUG;
    for (my $status = $reverses->seq($key, $value, R_CURSOR);
	$status == 0;
    	$status =  $reverses->seq( $key, $value, R_NEXT)) {

	# FIXME: what's the most efficient "is prefix of" thingy? We only want to know
	# whether $kw is or is not a prefix of $key
	last unless index($key, $kw) == 0;
	debug( "found $key", 2 ) if DEBUG;

	my @hits = split /\0/o, $value;
	push @$results, [ scalar reverse($key), @hits ];
	last if ($$nres)++ > 100;
    }

    $Packages::Search::too_many_hits += $$nres - 100 if $$nres > 100;
}


1;
