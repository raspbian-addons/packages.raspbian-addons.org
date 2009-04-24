package Packages::DoSearchContents;

use strict;
use warnings;

use Benchmark ':hireswallclock';
use DB_File;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_search_contents );

use Deb::Versions;
use Packages::I18N::Locale;
use Packages::Search qw( :all );
use Packages::CGI qw( :DEFAULT error );
use Packages::DB;
use Packages::Config qw( $DBDIR @SUITES @ARCHIVES @ARCHITECTURES $ROOT );

sub do_search_contents {
    my ($params, $opts, $page_content) = @_;
    my $cat = $opts->{cat};

    if ($params->{errors}{keywords}) {
	fatal_error( $cat->g( "keyword not valid or missing" ) );
	$opts->{keywords} = [];
    } elsif (grep { length($_) < 2 } @{$opts->{keywords}}) {
	fatal_error( $cat->g( "keyword too short (keywords need to have at least two characters)" ) );
    }
    if ($params->{errors}{suite}) {
	fatal_error( $cat->g( "suite not valid or not specified" ) );
    }

    #FIXME: that's extremely hacky atm
    if ($params->{values}{suite}{no_replace}[0] eq 'default') {
	$params->{values}{suite}{no_replace} =
	    $params->{values}{suite}{final} = $opts->{suite} = [ 'jaunty' ];
    }

    if (@{$opts->{suite}} > 1) {
	fatal_error( $cat->g( "more than one suite specified for contents search (%s)",
			      "@{$opts->{suite}}" ) );
    }

    my @keywords = @{$opts->{keywords}};
    my $mode = $opts->{mode} || '';
    my $suite = $opts->{suite}[0];
    my $archive = $opts->{archive}[0] ||'';
    $Packages::Search::too_many_hits = 0;

    my $st0 = new Benchmark;
    my (@results);

    unless (@Packages::CGI::fatal_errors) {

	my $nres = 0;

	my $first_kw = lc shift @keywords;
	# full filename search is tricky
	my $ffn = $mode eq 'filename';

	unless (-e "$DBDIR/contents/reverse_$suite.db") {
	    fatal_error($cat->g("No contents information available for this suite"));
	    return;
	}
	my $reverses = tie my %reverses, 'DB_File', "$DBDIR/contents/reverse_$suite.db",
	    O_RDONLY, 0666, $DB_BTREE
	    or die "Failed opening reverse DB: $!";

	if ($ffn) {
	    open FILENAMES, '-|', 'fgrep', '--', $first_kw, "$DBDIR/contents/filenames_$suite.txt"
		or die "Failed opening filename table: $!";

	  FILENAME:
	    while (<FILENAMES>) {
		chomp;
		foreach my $kw (@keywords) {
		    next FILENAME unless /\Q$kw\E/;
		}
		&searchfile(\@results, reverse($_)."/", \$nres, $reverses);
		last if $Packages::Search::too_many_hits;
	    }
	    while (<FILENAMES>) {};
	    close FILENAMES or warn "fgrep error: $!\n";
	} else {

	    error($cat->g("The search mode you selected doesn't support more than one keyword."))
		if @keywords;

	    my $kw = reverse $first_kw;
	    $kw =~ s{/+$}{};

	    # exact filename searching follows trivially:
	    $kw = "$kw/" if $mode eq 'exactfilename';

	    &searchfile(\@results, $kw, \$nres, $reverses);
	}
	$reverses = undef;
	untie %reverses;


	my $st1 = new Benchmark;
	my $std = timediff($st1, $st0);
	debug( "Search took ".timestr($std) ) if DEBUG;
    }

    my (%results,%archs);
    foreach my $result (sort { $a->[0] cmp $b->[0] } @results) {
	my $file = shift @$result;
	my %pkgs;
	foreach (@$result) {
	    my ($pkg, $arch) = split m/:/, $_;
	    next unless $opts->{h_archs}{$arch};
	    $pkgs{$pkg}{$arch}++;
	    $archs{$arch}++ unless $arch eq 'all';
	}
	next unless keys %pkgs;
	$results{$file} = \%pkgs;
    }
    my @all_archs = sort keys %archs;
    @all_archs = sort @ARCHITECTURES unless @all_archs;
    $page_content->{suite} = $suite;
    $page_content->{archive} = $archive;
    $page_content->{all_architectures} = \@all_archs;
    $page_content->{all_suites} = [ grep { $_ !~ /-(updates|backports)$/ } @SUITES ];
    $page_content->{mode} = $mode;
    $page_content->{search_architectures} = $opts->{arch};
    $page_content->{search_keywords} = $opts->{keywords};
    $page_content->{sections} = $opts->{section};
    $page_content->{too_many_hits} = $Packages::Search::too_many_hits;

    debug( "all_archs = @all_archs", 1 ) if DEBUG;

    if (keys %results) {
	my $sort_func = sub { $_[0] cmp $_[1] };
	$sort_func = sub { (sort keys %{$results{$_[0]}})[0]
			   cmp
			   (sort keys %{$results{$_[1]}})[0]
			 } if $opts->{sort_by} eq 'pkg';

	$page_content->{results} = [];
	foreach my $file (sort {&$sort_func($a,$b)} keys %results) {
	    my %result;
	    $result{file} = "/$file";
	    $result{packages} = [];
	    foreach my $pkg (sort keys %{$results{$file}}) {
		my $arch_str = '';
		my @archs = keys %{$results{$file}{$pkg}};
		my $arch_neg = 0;
		unless ($results{$file}{$pkg}{all} ||
			(@archs == @all_archs)) {
		    if (@archs >= @all_archs/2) {
			@archs = grep { !$results{$file}{$pkg}{$_} } @all_archs;
			$arch_neg = 1;
		    }
		} else {
		    @archs = ();
		}
		push @{$result{packages}}, { pkg => $pkg, architectures => \@archs, architectures_are_rev => $arch_neg };
	    }
	    push @{$page_content->{results}}, \%result;
	}
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

	my @files = split /\001/o, $value;
	foreach my $f (@files) {
	    my @hits = split /\0/o, $f;
	    my $file = shift @hits;
	    if ($file eq '-') {
		$file = reverse($key);
	    }
	    push @$results, [ $file, @hits ];
	}
	last if ($$nres)++ > 100;
    }

    $Packages::Search::too_many_hits += $$nres - 100 if $$nres > 100;
}


1;
