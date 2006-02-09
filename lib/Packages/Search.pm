#
# Packages::Search
#
# Copyright (C) 2004-2006 Frank Lichtenheld <frank@lichtenheld.de>
# 
# The code is based on the old search_packages.pl script that
# was:
#
# Copyright (C) 1998 James Treacy
# Copyright (C) 2000, 2001 Josip Rodin
# Copyright (C) 2001 Adam Heath
# Copyright (C) 2004 Martin Schulze
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
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

=head1 NAME

Packages::Search - 

=head1 SYNOPSIS

=head1 DESCRIPTION

=over 4

=cut

package Packages::Search;

use strict;
use warnings;

use CGI qw( -oldstyle_urls );
use POSIX;
use HTML::Entities;
use DB_File;

use Deb::Versions;
use Packages::CGI;
use Exporter;

our @ISA = qw( Exporter );

our @EXPORT_OK = qw( nextlink prevlink indexline
                     resperpagelink
		     read_entry read_entry_all read_entry_simple
		     read_src_entry read_src_entry_all find_binaries
		     do_names_search do_fulltext_search
		     printindexline multipageheader );
our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

our $VERSION = 0.01;

our $USE_PAGED_MODE = 1;
use constant DEFAULT_PAGE => 1;
use constant DEFAULT_RES_PER_PAGE => 50;
our %page_params = ( page => { default => DEFAULT_PAGE,
                               match => '(\d+)' },
                     number => { default => DEFAULT_RES_PER_PAGE,
                                 match => '(\d+)' } );

our $too_many_hits = 0;

sub parse_params {
    my ( $cgi, $params_def, $opts ) = @_;

    my %params_ret = ( values => {}, errors => {} );
    my %params;
    if ($USE_PAGED_MODE) {
        debug( "Use PAGED_MODE", 2 );
        %params = %$params_def;
        foreach (keys %page_params) {
            delete $params{$_};
        }
        %params = ( %params, %page_params );
    } else {
        %params = %$params_def;
    }

    foreach my $param ( keys %params ) {
	
	debug( "Param <strong>$param</strong>", 2 );

	my $p_value_orig = $cgi->param($param);

	if (!defined($p_value_orig)
	    && defined $params_def->{$param}{alias}
	    && defined $cgi->param($params_def->{$param}{alias})) {
	    $p_value_orig = $cgi->param($params_def->{$param}{alias});
	    debug( "Used alias <strong>$params_def->{$param}{alias}</strong>",
		   2 );
	}

	my @p_value = ($p_value_orig);

	debug( "Value (Orig) ".($p_value_orig||""), 2 );

	if ($params_def->{$param}{array} && defined $p_value_orig) {
	    @p_value = split /$params_def->{$param}{array}/, $p_value_orig;
	    debug( "Value (Array Split) ". join('##',@p_value), 2 );
	}

	if ($params_def->{$param}{match} && defined $p_value_orig) {
	    @p_value = map
	    { $_ =~ m/$params_def->{$param}{match}/; $_ = $1 }
	    @p_value;
	}
	@p_value = grep { defined $_ } @p_value;

	debug( "Value (Match) ". join('##',@p_value), 2 );

	unless (@p_value) {
	    if (defined $params{$param}{default}) {
		@p_value = ($params{$param}{default});
	    } else {
		@p_value = undef;
		$params_ret{errors}{$param} = "undef";
		next;
	    }
	}

	debug( "Value (Default) ". join('##',@p_value), 2 );
	my @p_value_no_replace = @p_value;

	if ($params{$param}{replace} && @p_value) {
	    @p_value = ();
	    foreach my $pattern (keys %{$params{$param}{replace}}) {
		foreach (@p_value_no_replace) {
		    if ($_ eq $pattern) {
			my $replacement = $params{$param}{replace}{$_};
			if (ref $replacement) {
			    push @p_value, @$replacement;
			} else {
			    push @p_value, $replacement;
			}
		    } else {
			push @p_value, $_;
		    }
		}
	    }
	}
	
	debug( "Value (Final) ". join('##',@p_value), 2 );

	if ($params_def->{$param}{array}) {
	    $params_ret{values}{$param} = {
		orig => $p_value_orig,
		no_replace => \@p_value_no_replace,
		final => \@p_value,
	    };
	    @{$params_def->{$param}{var}} = @p_value
		if $params_def->{$param}{var};
	} else {
	    $params_ret{values}{$param} = {
		orig => $p_value_orig,
		no_replace => $p_value_no_replace[0],
		final => $p_value[0],
	    };
	    ${$params_def->{$param}{var}} = $p_value[0]
		if $params_def->{$param}{var};
	}
	$opts->{$param} = $params_ret{values}{$param}{final} if $opts;
    }

    if ($USE_PAGED_MODE) {
        $cgi->delete( "page" );
        $cgi->delete( "number" );
    }

    return %params_ret;
}

sub start { 
    my $params = shift;

    my $page = $params->{values}{page}{final}
    || DEFAULT_PAGE;
    my $res_per_page = $params->{values}{number}{final}
    || DEFAULT_RES_PER_PAGE;

    return 1 if $res_per_page =~ /^all$/i;
    return $res_per_page * ($page - 1) + 1;
}

sub end {
    my $params = shift;

    use Data::Dumper;
    debug( "end: ".Dumper($params) );
    my $page = $params->{page}
    || DEFAULT_PAGE;
    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;

    return $page * $res_per_page;
}

sub indexline {
    my ($cgi, $params, $num_res) = @_;

    my $index_line = "";
    my $page = $params->{page}
    || DEFAULT_PAGE;
    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;
    my $numpages = ceil($num_res /
                        $res_per_page);
    for (my $i = 1; $i <= $numpages; $i++) {
        if ($i == $page) {
            $index_line .= $i;
        } else {
            $index_line .= "<a href=\"".encode_entities($cgi->self_url).
                "&amp;page=$i&amp;number=$res_per_page\">".
                "$i</a>";
        }
	if ($i < $numpages) {
	   $index_line .= " | ";
	}
    }
    return $index_line;
}

sub nextlink {
    my ($cgi, $params, $no_results ) = @_;

    my $page = $params->{page}
    || DEFAULT_PAGE;
    $page++;
    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;

    if ((($page-1)*$res_per_page + 1) > $no_results) {
        return "&gt;&gt;";
    }

    return "<a href=\"".encode_entities($cgi->self_url).
        "&amp;page=$page&amp;number=$res_per_page\">&gt;&gt;</a>";
}

sub prevlink {
    my ($cgi, $params ) = @_;

    my $page = $params->{page}
    || DEFAULT_PAGE;
    $page--;
    if (!$page) {
        return "&lt;&lt;";
    }

    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;

    return "<a href=\"".encode_entities($cgi->self_url).
        "&amp;page=$page&amp;number=$res_per_page\">&lt;&lt;</a>";
}

sub resperpagelink {
    my ($cgi, $params, $res_per_page ) = @_;

    my $page;
    if ($res_per_page =~ /^all$/i) {
	$page = 1;
    } else {
	$page = ceil(start( $params ) / $res_per_page);
    }

    return "<a href=\"".encode_entities($cgi->self_url).
        "&amp;page=$page&amp;number=$res_per_page\">$res_per_page</a>";
}

sub printindexline {
    my ( $input, $no_results, $opts ) = @_;

    my $index_line;
    if ($no_results > $opts->{number}) {
	
	$index_line = prevlink( $input, $opts)." | ".
	    indexline( $input, $opts, $no_results)." | ".
	    nextlink( $input, $opts, $no_results);
	
	print "<p style=\"text-align:center\">$index_line</p>";
    }
}

sub multipageheader {
    my ( $input, $no_results, $opts ) = @_;

    my ($start, $end);
    if ($opts->{number} =~ /^all$/i) {
	$start = 1;
	$end = $no_results;
	$opts->{number} = $no_results;
	$opts->{number_all}++;
    } else {
	$start = Packages::Search::start( $opts );
	$end = Packages::Search::end( $opts );
	if ($end > $no_results) { $end = $no_results; }
    }

    print "<p>Found <em>$no_results</em> matching packages,";
    if ($end == $start) {
	print " displaying package $end.</p>";
    } else {
	print " displaying packages $start to $end.</p>";
    }

    printindexline( $input, $no_results, $opts );

    if ($no_results > 100) {
	print "<p>Results per page: ";
	my @resperpagelinks;
	for (50, 100, 200) {
	    if ($opts->{number} == $_) {
		push @resperpagelinks, $_;
	    } else {
		push @resperpagelinks, resperpagelink($input,$opts,$_);
	    }
	}
	if ($opts->{number_all}) {
	    push @resperpagelinks, "all";
	} else {
	    push @resperpagelinks, resperpagelink($input, $opts, "all");
	}
	print join( " | ", @resperpagelinks )."</p>";
    }
    return ( $start, $end );
}

sub read_entry_all {
    my ($hash, $key, $results, $non_results, $opts) = @_;
    my $result = $hash->{$key} || '';
    foreach (split /\000/o, $result) {
	my @data = split ( /\s/o, $_, 8 );
	debug( "Considering entry ".join( ':', @data), 2);
	if ($opts->{h_archives}{$data[0]} && $opts->{h_suites}{$data[1]}
	    && ($opts->{h_archs}{$data[2]} || $data[2] eq 'all'
		|| $data[2] eq 'virtual')
	    && ($opts->{h_sections}{$data[3]} || $data[3] eq '-')) {
	    debug( "Using entry ".join( ':', @data), 2);
	    push @$results, [ $key, @data ];
	} else {
	    push @$non_results, [ $key, @data ];
	}
    }
}
sub read_entry {
    my ($hash, $key, $results, $opts) = @_;
    my @non_results;
    read_entry_all( $hash, $key, $results, \@non_results, $opts );
}
sub read_entry_simple {
    my ($hash, $key, $archives, $suite) = @_;
    my $result = $hash->{$key} || '';
    my @data_fuzzy;
    foreach (split /\000/o, $result) {
	my @data = split ( /\s/o, $_, 8 );
	debug( "Considering entry ".join( ':', @data), 2);
	if ($data[1] eq $suite) {
	    if ($archives->{$data[0]}) {
		debug( "Using entry ".join( ':', @data), 2);
		return \@data;
	    } elsif ($data[0] eq 'us') {
		debug( "Fuzzy entry ".join( ':', @data), 2);
		@data_fuzzy = @data;
	    }
	} 
    }
    return \@data_fuzzy;
}
sub read_src_entry_all {
    my ($hash, $key, $results, $non_results, $opts) = @_;
    my $result = $hash->{$key} || '';
    foreach (split /\000/o, $result) {
	my @data = split ( /\s/o, $_, 6 );
	debug( "Considering entry ".join( ':', @data), 2);
	if ($opts->{h_archives}{$data[0]}
	    && $opts->{h_suites}{$data[1]}
	    && $opts->{h_sections}{$data[2]}) {
	    debug( "Using entry ".join( ':', @data), 2);
	    push @$results, [ $key, @data ];
	} else {
	    push @$non_results, [ $key, @data ];
	}
    }
}
sub read_src_entry {
    my ($hash, $key, $results, $opts) = @_;
    my @non_results;
    read_src_entry_all( $hash, $key, $results, \@non_results, $opts );
}
sub do_names_search {
    my ($keyword, $packages, $postfixes, $read_entry, $opts) = @_;
    my @results;

    $keyword = lc $keyword unless $opts->{case_bool};
        
    if ($opts->{exact}) {
	&$read_entry( $packages, $keyword, \@results, $opts );
    } else {
	my ($key, $prefixes) = ($keyword, '');
	my %pkgs;
	$postfixes->seq( $key, $prefixes, R_CURSOR );
	while (index($key, $keyword) >= 0) {
            if ($prefixes =~ /^\001(\d+)/o) {
                $too_many_hits += $1;
            } else {
		foreach (split /\000/o, $prefixes) {
		    $_ = '' if $_ eq '^';
		    debug( "add word $_$key", 2);
		    $pkgs{$_.$key}++;
		}
	    }
	    last if $postfixes->seq( $key, $prefixes, R_NEXT ) != 0;
	    last if $too_many_hits or keys %pkgs >= 100;
	}
        
        my $no_results = keys %pkgs;
        if ($too_many_hits || ($no_results >= 100)) {
	    $too_many_hits += $no_results;
	    %pkgs = ( $keyword => 1 );
	}
	foreach my $pkg (sort keys %pkgs) {
	    &$read_entry( $packages, $pkg, \@results, $opts );
	}
    }
    return \@results;
}
sub do_fulltext_search {
    my ($keyword, $file, $did2pkg, $packages, $read_entry, $opts) = @_;
    my @results;

    my @lines;
    my $regex;
    if ($opts->{case_bool}) {
	if ($opts->{exact}) {
	    $regex = qr/\b\Q$keyword\E\b/o;
	} else {
	    $regex = qr/\Q$keyword\E/o;
	}
    } else {
	if ($opts->{exact}) {
	    $regex = qr/\b\Q$keyword\E\b/io;
	} else {
	    $regex = qr/\Q$keyword\E/io;
	}
    }

    open DESC, '<', "$file"
	or die "couldn't open $file: $!";
    while (<DESC>) {
	$_ =~ $regex or next;
	debug( "Matched line $.", 2);
	push @lines, $.;
    }
    close DESC;

    my %tmp_results;
    foreach my $l (@lines) {
	my $result = $did2pkg->{$l};
	foreach (split /\000/o, $result) {
	    my @data = split /\s/, $_, 3;
	    next unless $opts->{h_archs}{$data[2]};
	    $tmp_results{$data[0]}++;
	}
    }
    foreach my $pkg (keys %tmp_results) {
	&$read_entry( $packages, $pkg, \@results, $opts );
    }
    return \@results;
}

sub find_binaries {
    my ($pkg, $archive, $suite, $src2bin) = @_;

    my $bins = $src2bin->{$pkg} || '';
    my %bins;
    foreach (split /\000/o, $bins) {
	my @data = split /\s/, $_, 5;

	debug( "find_binaries: considering @data", 3 );
	if (($data[0] eq $archive)
	    && ($data[1] eq $suite)) {
	    $bins{$data[2]}++;
	    debug( "find_binaries: using @data", 3 );
	}
    }

    return [ keys %bins ];
}


1;
