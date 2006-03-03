package Packages::DoSearch;

use strict;
use warnings;

use Benchmark ':hireswallclock';
use DB_File;
use URI::Escape;
use HTML::Entities;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_search );

use Deb::Versions;
use Packages::I18N::Locale;
use Packages::Search qw( :all );
use Packages::CGI;
use Packages::DB;
use Packages::HTML qw(marker);
use Packages::Config qw( $DBDIR $SEARCH_URL $SEARCH_PAGE
			 @SUITES @ARCHIVES $ROOT );
use Packages::HTML;

sub do_search {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    $Params::Search::too_many_hits = 0;

    if ($params->{errors}{keywords}) {
	fatal_error( _g( "keyword not valid or missing" ) );
    } elsif (length($opts->{keywords}) < 2) {
	fatal_error( _g( "keyword too short (keywords need to have at least two characters)" ) );
    }

    $$menu = "";
    
    my @keywords = @{$opts->{keywords}};
    my $searchon = $opts->{searchon};

    # for URL construction
    my $keyword_esc = uri_escape( "@keywords" );
    $opts->{keywords_esc} = $keyword_esc;

    # for output
    my $keyword_enc = encode_entities "@keywords" || '';
    my $searchon_enc = encode_entities $searchon;
    my $suites_enc = encode_entities( join( ', ', @{$params->{values}{suite}{no_replace}} ) );
    my $sections_enc = encode_entities( join( ', ', @{$params->{values}{section}{no_replace}} ) );
    my $archs_enc = encode_entities( join( ', ',  @{$params->{values}{arch}{no_replace}} ) );
    
    my $st0 = new Benchmark;
    my (@results, @non_results);

    unless (@Packages::CGI::fatal_errors) {

	if ($searchon eq 'names') {
	    if ($opts->{source}) {
		do_names_search( \@keywords, \%sources, $sp_obj,
				 \&read_src_entry_all, $opts,
				 \@results, \@non_results );
	    } else {
		do_names_search( \@keywords, \%packages, $p_obj,
				 \&read_entry_all, $opts,
				 \@results, \@non_results );
	    }
	} else {
	    do_names_search( \@keywords, \%packages, $p_obj,
			     \&read_entry_all, $opts,
			     \@results, \@non_results );
	    do_fulltext_search( \@keywords, "$DBDIR/descriptions.txt",
				\%did2pkg, \%packages,
				\&read_entry_all, $opts,
				\@results, \@non_results );
	}
    }
    
#    use Data::Dumper;
#    debug( join( "", Dumper( \@results, \@non_results )) ) if DEBUG;
    my $st1 = new Benchmark;
    my $std = timediff($st1, $st0);
    debug( "Search took ".timestr($std) ) if DEBUG;
    
    my $suite_wording = $suites_enc =~ /^(default|all)$/ ? _g("all suites")
	: sprintf(_g("suite(s) <em>%s</em>", $suites_enc) );
    my $section_wording = $sections_enc eq 'all' ? _g("all sections")
	: sprintf(_g("section(s) <em>%s</em>", $sections_enc) );
    my $arch_wording = $archs_enc eq 'any' ? _g("all architectures")
	: sprintf(_g("architecture(s) <em>%s</em>", $archs_enc) );
    if ($searchon eq "names") {
	my $source_wording = $opts->{source} ? _g("source packages") : _g("packages");
	# sorry to all translators for that one... (patches welcome)
	msg( sprintf( _g( "You have searched for %s that names contain <em>%s</em> in %s, %s, and %s." ),
		      $source_wording, $keyword_enc,
		      $suite_wording, $section_wording, $arch_wording ) );
    } else {
	my $exact_wording = $opts->{exact} ? "" : _g(" (including subword matching)");
	msg( sprintf( _g( "You have searched for <em>%s</em> in packages names and descriptions in %s, %s, and %s%s." ),
		      $keyword_enc,
		      $suite_wording, $section_wording, $arch_wording,
		      $exact_wording ) );
    }

    if ($Packages::Search::too_many_hits) {
	error( sprintf( _g( "Your search was too wide so we will only display exact matches. At least <em>%s</em> results have been omitted and will not be displayed. Please consider using a longer keyword or more keywords." ), $Packages::Search::too_many_hits ) );
    }
    
    if (!@Packages::CGI::fatal_errors && !@results) {
	if ($searchon eq "names") {
	    unless (@non_results) {
		error( _g( "Can't find that package." ) );
	    } else {
		hint( _g( "Can't find that package." )." ".
		      sprintf( _g( '<a href="%s">%s</a>'.
		      " results have not been displayed due to the".
		      " search parameters." ), "$SEARCH_URL/$keyword_esc" ,
		      $#non_results+1 ) );
	    }
	    
	} else {
	    if (($suites_enc eq 'all')
		&& ($archs_enc eq 'any')
		&& ($sections_enc eq 'all')) {
		error( _g( "Can't find that string." ) );
	    } else {
		error( sprintf( _g( "Can't find that string, at least not in that suite (%s, section %s) and on that architecture (%s)." ),
				$suites_enc, $sections_enc, $archs_enc ) );
	    }
	    
	    if ($opts->{exact}) {
		hint( sprintf( _g( 'You have searched only for words exactly matching your keywords. You can try to search <a href="%s">allowing subword matching</a>.' ),
			       encode_entities(make_search_url('',"keywords=$keyword_esc",{exact => 0})) ) );
	    }
	}
	hint( sprintf( _g( 'You can try a different search on the <a href="%s">Packages search page</a>.' ), "$SEARCH_PAGE#search_packages" ) );
	
    }

    %$html_header = ( title => _g( 'Package Search Results' ) ,
		      lang => $opts->{lang},
		      title_tag => _g( 'Debian Package Search Results' ),
		      print_title => 1,
		      print_search_field => 'packages',
		      search_field_values => { 
			  keywords => $keyword_enc,
			  searchon => $opts->{searchon_form},
			  arch => $archs_enc,
			  suite => $suites_enc,
			  section => $sections_enc,
			  exact => $opts->{exact},
			  debug => $opts->{debug},
		      },
		      );

    $$page_content = '';
    if (@results) {
	my (%pkgs, %subsect, %sect, %archives, %desc, %binaries, %provided_by);

	unless ($opts->{source}) {
	    foreach (@results) {
		my ($pkg_t, $archive, $suite, $arch, $section, $subsection,
		    $priority, $version, $desc) = @$_;
		
		my ($pkg) = $pkg_t =~ m/^(.+)/; # untaint
		if ($arch ne 'virtual') {
		    $pkgs{$pkg}{$suite}{$version}{$arch} = 1;
		    $subsect{$pkg}{$suite}{$version} = $subsection;
		    $sect{$pkg}{$suite}{$version} = $section
			unless $section eq 'main';
		    $archives{$pkg}{$suite}{$version} ||= $archive;
		    
		    $desc{$pkg}{$suite}{$version} = $desc;
		} else {
		    $provided_by{$pkg}{$suite} = [ split /\s+/, $desc ];
		}
	    }

	    my %uniq_pkgs = map { $_ => 1 } (keys %pkgs, keys %provided_by);
	    my @pkgs = sort keys %uniq_pkgs;
	    $$page_content .= print_packages( \%pkgs, \@pkgs, $opts, \@keywords,
					      \&print_package, \%provided_by,
					      \%archives, \%sect, \%subsect,
					      \%desc );

	} else { # unless $opts->{source}
	    foreach (@results) {
		my ($pkg, $archive, $suite, $section, $subsection, $priority,
		    $version) = @$_;
		
		my $real_archive = '';
		if ($archive =~ /^(security|non-US)$/) {
		    $real_archive = $archive;
		    $archive = 'us';
		}
		if (($real_archive eq $archive) &&
		    $pkgs{$pkg}{$suite}{$archive} &&
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
	    $$page_content .= print_packages( \%pkgs, \@pkgs, $opts, \@keywords,
					      \&print_src_package, \%archives,
					      \%sect, \%subsect, \%binaries );
	} # else unless $opts->{source}
    } # if @results
} # sub do_search

sub print_packages {
    my ($pkgs, $pkgs_list, $opts, $keywords, $print_func, @func_args) = @_;

    #my ($start, $end) = multipageheader( $input, scalar @pkgs, \%opts );
    my $str = '<div id="psearchres">';
    $str .= "<p>".sprintf( _g( "Found <em>%s</em> matching packages." ),
			   scalar @$pkgs_list )."</p>";
    #my $count = 0;
    my $keyword;
    $keyword = $keywords->[0] if @$keywords == 1;
	    
    my $have_exact;
    if ($keyword && grep { $_ eq $keyword } @$pkgs_list) {
	$have_exact = 1;
	$str .= '<h2>'._g( "Exact hits" ).'</h2>';
	$str .= &$print_func( $keyword, $pkgs->{$keyword}||{},
			      map { $_->{$keyword}||{} } @func_args );
	@$pkgs_list = grep { $_ ne $keyword } @$pkgs_list;
    }
	    
    if (@$pkgs_list && (($opts->{searchon} ne 'names') || !$opts->{exact})) {
	$str .= '<h2>'._g( 'Other hits' ).'</h2>'
	    if $have_exact;
	
	foreach my $pkg (@$pkgs_list) {
	    #$count++;
	    #next if $count < $start or $count > $end;
	    $str .= &$print_func( $pkg, $pkgs->{$pkg}||{},
				  map { $_->{$pkg}||{} } @func_args );
	}
    } elsif (@$pkgs_list) {
	$str .= "<p>".sprintf( _g( '<a href="%s">%s</a> results have not been displayed because you requested only exact matches.' ),
			       encode_entities(make_search_url('',"keywords=$opts->{keyword_esc}",{exact => 0})),
			       scalar @$pkgs_list )."</p>";
    }
    $str .= '</div>';

    return $str;
}

sub print_package {
    my ($pkg, $pkgs, $provided_by, $archives, $sect, $subsect, $desc) = @_;

    my $str = '<h3>'.sprintf( _g( 'Package %s' ), $pkg ).'</h3>';
    $str .= '<ul>';
    foreach my $suite (@SUITES) {
	    my $override = { suite => $suite };
	    if (exists $pkgs->{$suite}) {
		my %archs_printed;
		my @versions = version_sort keys %{$pkgs->{$suite}};
		my $origin_str = "";
		if ($sect->{$suite}{$versions[0]}) {
		    $origin_str .= " ".marker($sect->{$suite}{$versions[0]});
		}
		$str .= sprintf( "<li><a href=\"%s\">%s</a> (%s): %s   %s\n",
				 make_url($pkg,'',$override), $suite, $subsect->{$suite}{$versions[0]},
				 $desc->{$suite}{$versions[0]}, $origin_str );
		
		foreach my $v (@versions) {
		    my $archive_str = "";
		    if ($archives->{$suite}{$v} ne 'us') {
			$archive_str .= " ".marker($archives->{$suite}{$v});
		    }
		    
		    my @archs_to_print = grep { !$archs_printed{$_} } sort keys %{$pkgs->{$suite}{$v}};
		    $str .= sprintf( "<br>%s$archive_str: %s\n",
				     $v, join (" ", @archs_to_print ))
			if @archs_to_print;
		    $archs_printed{$_}++ foreach @archs_to_print;
		}
		if (my $p =  $provided_by->{$suite}) {
		    $str .= '<br>'._g( 'also provided by: ' ).
			join( ', ', map { "<a href=\"".
					      make_url($_,'',$override)."\">$_</a>"  } @$p);
		}
		$str .= "</li>\n";
	    } elsif (my $p =  $provided_by->{$suite}) {
		$str .= sprintf( "<li><a href=\"%s\">%s</a>: "._g('Virtual package').'<br>',
				 make_url($pkg,'',$override), $suite );
		$str .= _g( 'provided by: ' ).
		    join( ', ', map { "<a href=\"".
					  make_url($_,'',$override)."\">$_</a>"  } @$p);
	    }
    }
    $str .= "</ul>\n";
    return $str;
}

sub print_src_package {
    my ($pkg, $pkgs, $archives, $sect, $subsect, $binaries) = @_;

    my $str = '<h3>'.sprintf( _g( 'Source package %s' ), $pkg ).'</h3>';
    $str .= "<ul>\n";
    foreach my $suite (@SUITES) {
	foreach my $archive (@ARCHIVES) {
	    if (exists $pkgs->{$suite}{$archive}) {
		my $origin_str = "";
		if ($sect->{$suite}{$archive}{source}) {
		    $origin_str .= " ".marker($sect->{$suite}{$archive}{source});
		}
		if ($archives->{$suite}{$archive}{source}) {
		    $origin_str .= " ".marker($archives->{$suite}{$archive}{source});
		}
		$str .= sprintf( "<li><a href=\"$ROOT/%s/source/%s\">%s</a> (%s): %s   %s",
				 $suite.(($archive ne 'us')?"/$archive":''), $pkg, $suite.(($archive ne 'us')?"/$archive":''), $subsect->{$suite}{$archive}{source},
				 $pkgs->{$suite}{$archive}, $origin_str );
		
		$str .= "<br>"._g( 'Binary packages: ' );
		my @bp_links;
		foreach my $bp (@{$binaries->{$suite}{$archive}}) {
		    my $bp_link = sprintf( "<a href=\"$ROOT/%s/%s\">%s</a>",
					   $suite.(($archive ne 'us')?"/$archive":''), uri_escape( $bp ),  $bp );
		    push @bp_links, $bp_link;
		}
		$str .= join( ", ", @bp_links );
		$str .= "</li>\n";
	    }
	}
    }
    $str .= "</ul>\n";
    return $str;
}

1;
