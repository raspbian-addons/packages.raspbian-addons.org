package Packages::DoSearch;

use strict;
use warnings;

use Benchmark ':hireswallclock';
use DB_File;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_search );

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::CGI qw( :DEFAULT );
use Packages::DB;
use Packages::Config qw( $DBDIR @SUITES @ARCHIVES @ARCHITECTURES $ROOT );

sub do_search {
    my ($params, $opts, $page_content) = @_;
    my $cat = $opts->{cat};

    $Params::Search::too_many_hits = 0;

    if ($params->{errors}{keywords}) {
	fatal_error( $cat->g( "keyword not valid or missing" ) );
	$opts->{keywords} = [];
    } elsif (grep { length($_) < 2 } @{$opts->{keywords}}) {
	fatal_error( $cat->g( "keyword too short (keywords need to have at least two characters)" ) );
    }

    my @keywords = @{$opts->{keywords}};
    my $searchon = $opts->{searchon};
    $page_content->{search_keywords} = $opts->{keywords};
    $page_content->{all_architectures} = \@ARCHITECTURES;
    $page_content->{all_suites} = \@SUITES;
    $page_content->{search_architectures} = $opts->{arch};
    $page_content->{search_suites} = $opts->{suite};
    $page_content->{sections} = $opts->{section};

    my $st0 = new Benchmark;
    my (@results, @non_results);

    unless (@Packages::CGI::fatal_errors) {

	if ($searchon eq 'names') {
	    if ($opts->{source}) {
		do_names_search( [ @keywords ], \%sources, $sp_obj,
				 \&read_src_entry_all, $opts,
				 \@results, \@non_results );
	    } else {
		do_names_search( [ @keywords ], \%packages, $p_obj,
				 \&read_entry_all, $opts,
				 \@results, \@non_results );
	    }
	} else {
	    do_names_search( [ @keywords ], \%packages, $p_obj,
			     \&read_entry_all, $opts,
			     \@results, \@non_results );
	    my $fts1 = new Benchmark;
	    do_xapian_search( [ @keywords ], "$DBDIR/xapian/",
				\%did2pkg, \%packages,
				\&read_entry_all, $opts,
				\@results, \@non_results );
	    my $fts2 = new Benchmark;
	    my $fts_xapian = timediff($fts2,$fts1);
	    debug( "Fulltext search took ".timestr($fts_xapian) )
		if DEBUG;
	}
    }

#    use Data::Dumper;
#    debug( join( "", Dumper( \@results, \@non_results )) ) if DEBUG;
    my $st1 = new Benchmark;
    my $std = timediff($st1, $st0);
    debug( "Search took ".timestr($std) ) if DEBUG;

    $page_content->{too_many_hits} = $Packages::Search::too_many_hits;
    #FIXME: non_results can't be compared to results since it is
    # not normalized to unique packages
    $page_content->{non_results} = scalar @non_results;

    if (@results) {
	my (%pkgs, %subsect, %sect, %archives, %desc, %binaries, %provided_by);

	my %sort_by_relevance;
	for (1 ... scalar @results) {
#	    debug("$results[$_][0] => $_", 4) if DEBUG;
	    $sort_by_relevance{$results[$_-1][0]} = $_;
	}
#	use Data::Dumper;
#	debug( "sort_by_relevance=".Dumper(\%sort_by_relevance), 4);

	unless ($opts->{source}) {
	    foreach (@results) {
		my ($pkg_t, $archive, $suite, $arch, $section, $subsection,
		    $priority, $version, $desc_md5, $desc) = @$_;

		my ($pkg) = $pkg_t =~ m/^(.+)/; # untaint
		if ($arch ne 'virtual') {
		    $pkgs{$pkg}{$suite}{$version}{$arch} = 1;
		    $subsect{$pkg}{$suite}{$version} = $subsection;
		    $sect{$pkg}{$suite}{$version} = $section;
		    $archives{$pkg}{$suite}{$version} ||= $archive;

		    $desc{$pkg}{$suite}{$version} = [ $desc_md5, $desc ];
		} else {
		    $provided_by{$pkg}{$suite} = [ split /\s+/, $desc ];
		}
	    }

	    my %uniq_pkgs = map { $_ => 1 } (keys %pkgs, keys %provided_by);
	    my @pkgs;
	    if ($searchon eq 'names') {
		@pkgs = sort keys %uniq_pkgs;
	    } else {
		@pkgs = sort { $sort_by_relevance{$a} <=> $sort_by_relevance{$b} } keys %uniq_pkgs;
	    }
	    process_packages( $page_content, 'packages', \%pkgs, \@pkgs,
			      $opts, \@keywords,
			      \&process_package, \%provided_by,
			      \%archives, \%sect, \%subsect,
			      \%desc );

	} else { # unless $opts->{source}
	    foreach (@results) {
		my ($pkg, $archive, $suite, $section, $subsection, $priority,
		    $version) = @$_;

		my $real_archive = '';
		if ($archive eq 'security') {
		    $real_archive = $archive;
		    $archive = 'us';
		}
		if ($pkgs{$pkg}{$suite}{$archive} &&
		    (version_cmp( $pkgs{$pkg}{$suite}{$archive}, $version ) >= 0)) {
		    next;
		}
		$pkgs{$pkg}{$suite}{$archive} = $version;
		$subsect{$pkg}{$suite}{$archive}{source} = $subsection;
		$sect{$pkg}{$suite}{$archive}{source} = $section
		    unless $section eq 'main';
		$archives{$pkg}{$suite}{$archive}{source} = $real_archive
		    if $real_archive;

		$binaries{$pkg}{$suite}{$archive} = find_binaries( $pkg, $archive, $suite, \%src2bin );
	    }

	    my @pkgs = sort keys %pkgs;
	    process_packages( $page_content, 'src_packages', \%pkgs, \@pkgs,
			      $opts, \@keywords,
			      \&process_src_package, \%archives,
			      \%sect, \%subsect, \%binaries );
	} # else unless $opts->{source}
    } # if @results
} # sub do_search

sub process_packages {
    my ($content, $target, $pkgs, $pkgs_list, $opts, $keywords, $print_func, @func_args) = @_;

    my @categories;
    $content->{results} = scalar @$pkgs_list;

    my $keyword;
    $keyword = $keywords->[0] if @$keywords == 1;
	    
    my $have_exact;
    if ($keyword && grep { $_ eq $keyword } @$pkgs_list) {
	$have_exact = 1;
	$categories[0]{name} = $opts->{cat}->g( "Exact hits" );

	$categories[0]{$target} = [ &$print_func( $opts, $keyword,
						  $pkgs->{$keyword}||{},
						  map { $_->{$keyword}||{} } @func_args ) ];
	@$pkgs_list = grep { $_ ne $keyword } @$pkgs_list;
    }
	    
    if (@$pkgs_list && (($opts->{searchon} ne 'names') || !$opts->{exact})) {
	my %cat;
	$cat{name} = $opts->{cat}->g( 'Other hits' ) if $have_exact;
	
	$cat{packages} = [];
	foreach my $pkg (@$pkgs_list) {
	    push @{$cat{$target}}, &$print_func( $opts, $pkg, $pkgs->{$pkg}||{},
						 map { $_->{$pkg}||{} } @func_args );
	}
	push @categories, \%cat;
    } elsif (@$pkgs_list) {
	$content->{skipped} = scalar @$pkgs_list;
    }

    $content->{categories} = \@categories;
}

sub process_package {
    my ($opts, $pkg, $pkgs, $provided_by,
	$archives, $sect, $subsect, $desc) = @_;

    my %pkg = ( pkg => $pkg,
		suites => [] );

    foreach my $suite (@SUITES) {
	my %suite = ( suite => $suite );
	if (exists $pkgs->{$suite}) {
	    my %archs_printed;
	    my @versions = version_sort keys %{$pkgs->{$suite}};
	    $suite{section} = $sect->{$suite}{$versions[0]};
	    $suite{subsection} = $subsect->{$suite}{$versions[0]};
	    my $desc_md5 = $desc->{$suite}{$versions[0]}[0];
	    $suite{desc} = $desc->{$suite}{$versions[0]}[1];
	    $suite{versions} = [];

	    my $trans_desc = $desctrans{$desc_md5};
	    my %sdescs;
	    if ($trans_desc) {
		my %trans_desc = split /\000|\001/, $trans_desc;
		while (my ($l, $d) = each %trans_desc) {
		    $d =~ s/\n.*//os;

		    $sdescs{$l} = $d;
		}
		$suite{trans_desc} = \%sdescs;
	    }

	    foreach my $v (@versions) {
		my %version;
		$version{version} = $v;
		$version{archive} = $archives->{$suite}{$v};
		    
		$version{architectures} = [ grep { !$archs_printed{$_} } sort keys %{$pkgs->{$suite}{$v}} ];
		push @{$suite{versions}}, \%version if @{$version{architectures}};

		$archs_printed{$_}++ foreach @{$version{architectures}};
	    }
	    if (my $p =  $provided_by->{$suite}) {
		$suite{providers} = $p;
	    }
	} elsif (my $p =  $provided_by->{$suite}) {
	    $suite{desc} = $opts->{cat}->g('Virtual package');
	    $suite{providers} = $p;
	}
	push @{$pkg{suites}}, \%suite if $suite{versions} || $suite{providers};
    }

    return \%pkg;
}

sub process_src_package {
    my ($opts, $pkg, $pkgs, $archives, $sect, $subsect, $binaries) = @_;

    my %pkg = ( pkg => $pkg,
		origins => [] );

    foreach my $suite (@SUITES) {
	foreach my $archive (@ARCHIVES) {
	    if (exists $pkgs->{$suite}{$archive}) {
		my %origin;
		$origin{version} = $pkgs->{$suite}{$archive};
		$origin{suite} = $suite;
		$origin{archive} = $archive; 
		$origin{section} = $sect->{$suite}{$archive}{source};
		$origin{subsection} = $subsect->{$suite}{$archive}{source};
		$origin{real_archive} = $archives->{$suite}{$archive}{source};

		$origin{binaries} = $binaries->{$suite}{$archive};
		push @{$pkg{origins}}, \%origin;
	    }
	}
    }

    return \%pkg;
}

1;
