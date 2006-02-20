package Packages::DoSearch;

use strict;
use warnings;

use Benchmark;
use DB_File;
use URI::Escape;
use HTML::Entities;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_search );

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::CGI;
use Packages::DB;
use Packages::Config qw( $DBDIR $SEARCH_URL $SEARCH_CGI $SEARCH_PAGE
			 @SUITES @ARCHIVES $ROOT );

sub do_search {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{keywords}) {
	fatal_error( "keyword not valid or missing" );
    } elsif (length($opts->{keywords}) < 2) {
	fatal_error( "keyword too short (keywords need to have at least two characters)" );
    }

    $$menu = "";
    
    my $keyword = $opts->{keywords};
    my $searchon = $opts->{searchon};

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

	if ($searchon eq 'names') {
	    if ($opts->{source}) {
		do_names_search( $keyword, \%sources, $sp_obj,
				 \&read_src_entry_all, $opts,
				 \@results, \@non_results );
	    } else {
		do_names_search( $keyword, \%packages, $p_obj,
				 \&read_entry_all, $opts,
				 \@results, \@non_results );
	    }
#	} elsif ($searchon eq 'contents') {
#	    require "./search_contents.pl";
#	    &contents($input);
	} else {
	    do_names_search( $keyword, \%packages, $p_obj,
			     \&read_entry_all, $opts,
			     \@results, \@non_results );
	    do_fulltext_search( $keyword, "$DBDIR/descriptions.txt",
				\%did2pkg, \%packages,
				\&read_entry_all, $opts,
				\@results, \@non_results );
	}
    }
    
#    use Data::Dumper;
#    debug( join( "", Dumper( \@results, \@non_results )) );
    my $st1 = new Benchmark;
    my $std = timediff($st1, $st0);
    debug( "Search took ".timestr($std) );
    
    my $suite_wording = $suites_enc eq "all" ? "all suites"
	: "suite(s) <em>$suites_enc</em>";
    my $section_wording = $sections_enc eq 'all' ? "all sections"
	: "section(s) <em>$sections_enc</em>";
    my $arch_wording = $archs_enc eq 'any' ? "all architectures"
	: "architecture(s) <em>$archs_enc</em>";
    if ($searchon eq "names") {
	my $source_wording = $opts->{source} ? "source " : "";
	my $exact_wording = $opts->{exact} ? "named" : "that names contain";
	msg( "You have searched for ${source_wording}packages $exact_wording <em>$keyword_enc</em> in $suite_wording, $section_wording, and $arch_wording." );
    } else {
	my $exact_wording = $opts->{exact} ? "" : " (including subword matching)";
	msg( "You have searched for <em>$keyword_enc</em> in packages names and descriptions in $suite_wording, $section_wording, and $arch_wording$exact_wording." );
    }

    if ($Packages::Search::too_many_hits) {
	error( "Your search was too wide so we will only display exact matches. At least <em>$Packages::Search::too_many_hits</em> results have been omitted and will not be displayed. Please consider using a longer keyword or more keywords." );
    }
    
    if (!@Packages::CGI::fatal_errors && !@results) {
	my $printed = 0;
	if ($searchon eq "names") {
	    unless (@non_results) {
		error( "Can't find that package." );
	    } else {
		hint( "Can't find that package. ".
		      "<a href=\"$SEARCH_URL/$keyword_esc\">".
		      ($#non_results+1)."</a>".
		      " results have not been displayed due to the".
		      " search parameters." );
	    }
	    
	} else {
	    if (($suites_enc eq 'all')
		&& ($archs_enc eq 'any')
		&& ($sections_enc eq 'all')) {
		error( "Can't find that string." );
	    } else {
		error( "Can't find that string, at least not in that suite ($suites_enc, section $sections_enc) and on that architecture ($archs_enc)." );
	    }
	    
	    if ($opts->{exact}) {
		$printed++;
		hint( "You have searched only for words exactly matching your keywords. You can try to search <a href=\"$SEARCH_CGI?exact=0;searchon=$searchon;suite=$suites_param;section=$sections_param;keywords=$keyword_esc;arch=$archs_param\">allowing subword matching</a>." );
	    }
	}
	hint( ( $printed ? "Or you" : "You" )." can try a different search on the <a href=\"$SEARCH_PAGE#search_packages\">Packages search page</a>." );
	
    }

    %$html_header = ( title => 'Package Search Results' ,
		      lang => 'en',
		      title_tag => 'Debian Package Search Results',
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
		    my $real_archive;
		    if ($archive =~ /^(security|non-US)$/) {
			$real_archive = $archive;
			$archive = 'us';
		    }

		    $pkgs{$pkg}{$suite}{$archive}{$version}{$arch} = 1;
		    $subsect{$pkg}{$suite}{$archive}{$version} = $subsection;
		    $sect{$pkg}{$suite}{$archive}{$version} = $section
			unless $section eq 'main';
		    $archives{$pkg}{$suite}{$archive}{$version} = $real_archive
			if $real_archive;
		    
		    $desc{$pkg}{$suite}{$archive}{$version} = $desc;
		} else {
		    $provided_by{$pkg}{$suite}{$archive} = [ split /\s+/, $desc ];
		}
	    }

	    my @pkgs = sort(keys %pkgs, keys %provided_by);
	    $$page_content .= print_packages( \%pkgs, \@pkgs, $opts, $keyword,
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
	    $$page_content .= print_packages( \%pkgs, \@pkgs, $opts, $keyword,
					      \&print_src_package, \%archives,
					      \%sect, \%subsect, \%binaries );
	} # else unless $opts->{source}
    } # if @results
} # sub do_search

sub print_packages {
    my ($pkgs, $pkgs_list, $opts, $keyword, $print_func, @func_args) = @_;

    #my ($start, $end) = multipageheader( $input, scalar @pkgs, \%opts );
    my $str .= "<p>Found <em>".(scalar @$pkgs_list)."</em> matching packages.";
    #my $count = 0;
	    
    my $have_exact;
    if (grep { $_ eq $keyword } @$pkgs_list) {
	$have_exact = 1;
	$str .= '<h2 style="padding:.3em;border-top:solid grey thin;border-bottom:solid grey thin;background-color:#bdf">Exact hits</h2>';
	$str .= &$print_func( $keyword, $pkgs->{$keyword}||{},
			      map { $_->{$keyword}||{} } @func_args );
	@$pkgs_list = grep { $_ ne $keyword } @$pkgs_list;
    }
	    
    if (@$pkgs_list && (($opts->{searchon} ne 'names') || !$opts->{exact})) {
	$str .= '<h2 style="padding:.3em;border-top:solid grey thin;border-bottom:solid grey thin;background-color:#bdf">Other hits</h2>'
	    if $have_exact;
	
	foreach my $pkg (@$pkgs_list) {
	    #$count++;
	    #next if $count < $start or $count > $end;
	    $str .= &$print_func( $pkg, $pkgs->{$pkg}||{},
				  map { $_->{$pkg}||{} } @func_args );
	}
    } elsif (@$pkgs_list) {
	$str .= "<p><a href=\"$SEARCH_URL/FIXME\">".
	    ($#{$pkgs_list}+1)."</a> results have not been displayed because you requested only exact matches.</p>";
    }

    return $str;
}

sub print_package {
    my ($pkg, $pkgs, $provided_by, $archives, $sect, $subsect, $desc) = @_;

    my $str = sprintf "<h3>Package %s</h3>\n", $pkg;
    $str .= "<ul>\n";
    foreach my $suite (@SUITES) {
	foreach my $archive (@ARCHIVES) {
	    next if $archive eq 'security';
	    next if $archive eq 'non-US';
	    my $path = $suite.(($archive ne 'us')?"/$archive":'');
	    if (exists $pkgs->{$suite}{$archive}) {
		my %archs_printed;
		my @versions = version_sort keys %{$pkgs->{$suite}{$archive}};
		my $origin_str = "";
		if ($sect->{$suite}{$archive}{$versions[0]}) {
		    $origin_str .= " [<span style=\"color:red\">$sect->{$suite}{$archive}{$versions[0]}</span>]";
		}
		$str .= sprintf( "<li><a href=\"$ROOT/%s/%s\">%s</a> (%s): %s   %s\n",
				 $path, $pkg, $path, $subsect->{$suite}{$archive}{$versions[0]},
				 $desc->{$suite}{$archive}{$versions[0]}, $origin_str );
		
		foreach my $v (@versions) {
		    my $archive_str = "";
		    if ($archives->{$suite}{$archive}{$v}) {
			$archive_str .= " [<span style=\"color:red\">$archives->{$suite}{$archive}{$v}</span>]";
		    }
		    
		    my @archs_to_print = grep { !$archs_printed{$_} } sort keys %{$pkgs->{$suite}{$archive}{$v}};
		    $str .= sprintf( "<br>%s$archive_str: %s\n",
				     $v, join (" ", @archs_to_print ))
			if @archs_to_print;
		    $archs_printed{$_}++ foreach @archs_to_print;
		}
		if (my $p =  $provided_by->{$suite}{$archive}) {
		    $str .= '<br>also provided by: '.
			join( ', ', map { "<a href=\"$ROOT/$path/$_\">$_</a>"  } @$p);
		}
		$str .= "</li>\n";
	    } elsif (my $p =  $provided_by->{$suite}{$archive}) {
		$str .= sprintf( "<li><a href=\"$ROOT/%s/%s\">%s</a>: Virtual package<br>",
				 $path, $pkg, $path );
		$str .= 'provided by: '.
		    join( ', ', map { "<a href=\"$ROOT/$path/$_\">$_</a>"  } @$p);
	    }
	}
    }
    $str .= "</ul>\n";
    return $str;
}

sub print_src_package {
    my ($pkg, $pkgs, $archives, $sect, $subsect, $binaries) = @_;

    my $str = sprintf "<h3>Source package %s</h3>\n", $pkg;
    $str .= "<ul>\n";
    foreach my $suite (@SUITES) {
	foreach my $archive (@ARCHIVES) {
	    if (exists $pkgs->{$suite}{$archive}) {
		my $origin_str = "";
		if ($sect->{$suite}{$archive}{source}) {
		    $origin_str .= " [<span style=\"color:red\">$sect->{$suite}{$archive}{source}</span>]";
		}
		if ($archives->{$suite}{$archive}{source}) {
		    $origin_str .= " [<span style=\"color:red\">$archives->{$suite}{$archive}{source}</span>]";
		}
		$str .= sprintf( "<li><a href=\"$ROOT/%s/source/%s\">%s</a> (%s): %s   %s",
				 $suite.(($archive ne 'us')?"/$archive":''), $pkg, $suite.(($archive ne 'us')?"/$archive":''), $subsect->{$suite}{$archive}{source},
				 $pkgs->{$suite}{$archive}, $origin_str );
		
		$str .= "<br>Binary packages: ";
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
