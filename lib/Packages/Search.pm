#
# Packages::Search
#
# Copyright (C) 2004-2007 Frank Lichtenheld <frank@lichtenheld.de>
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
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
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

use POSIX;
use HTML::Entities;
use DB_File;
use Lingua::Stem v0.82;
use Search::Xapian qw(:ops);

use Deb::Versions;
use Packages::CGI;
use Exporter;

our @ISA = qw( Exporter );

our @EXPORT_OK = qw( read_entry read_entry_all read_entry_simple
		     read_src_entry read_src_entry_all find_binaries
		     do_names_search do_fulltext_search do_xapian_search
		     find_similar
		     );
our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

our $VERSION = 0.01;

our $too_many_hits = 0;

sub read_entry_all {
    my ($hash, $key, $results, $non_results, $opts) = @_;
    my ($virt, $result) = split /\000/o, $hash->{$key} || "-\01-", 2;

    my %virt = split /\01/o, $virt;
    while (my ($suite, $provides) = each %virt) {
	next if $suite eq '-';
	if ($opts->{h_suites}{$suite}) {
	    push @$results, [ $key, "-", $suite, 'virtual', 'v', 'v', 'v', 'v', 'v',
			      $provides];
	} else {
	    push @$non_results, [ $key, "-", $suite, 'virtual', 'v', 'v', 'v', 'v', 'v',
				  $provides];
	}
    }

    foreach (split(/\000/o, $result||'')) {
	my @data = split ( /\s/o, $_, 9 );
	debug( "Considering entry ".join( ':', @data), 2) if DEBUG;
	if ($opts->{h_suites}{$data[1]}
	    && ($opts->{h_archs}{$data[2]} || $data[2] eq 'all')
	    && $opts->{h_sections}{$data[3]}) {
	    debug( "Using entry ".join( ':', @data), 2) if DEBUG;
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

#FIXME: make configurable
my %fallback_suites = (
		       'etch-backports' => 'etch',
		       'etch-volatile' => 'etch',
		       'lenny-backports' => 'lenny',
		       'lenny-volatile' => 'lenny',
		       experimental => 'sid' );

sub read_entry_simple {
    my ($hash, $key, $archives, $suite) = @_;
    # FIXME: drop $archives

    my ($virt, $result) = split /\000/o, $hash->{$key} || "-\01-\0", 2;
    my %virt = split /\01/o, $virt; 
    debug( "read_entry_simple: key=$key, archives=".
	   join(" ",(keys %$archives)).", suite=$suite", 1) if DEBUG;
    debug( "read_entry_simple: virt=".join(" ",(%virt)), 2) if DEBUG;
    # FIXME: not all of the 2^4=16 combinations of empty(results),
    # empty(virt{suite}), empty(fb_result), empty(virt{fb_suite}) are dealt
    # with correctly, but it's adequate enough for now
    return [ $virt{$suite} ] unless defined $result;
    foreach (split /\000/o, $result) {
	my @data = split ( /\s/o, $_, 9 );
	debug( "use entry: @data", 2 ) if DEBUG && $data[1] eq $suite;
	return [ $virt{$suite}, @data ] if $data[1] eq $suite;
    }
    if (my $fb_suite = $fallback_suites{$suite}) {
	my $fb_result = read_entry_simple( $hash, $key, $archives, $fb_suite );
	my $fb_virt = shift(@$fb_result);
	$virt{$suite} .= $virt{$suite} ? " $fb_virt" : $fb_virt if $fb_virt;
	return [ $virt{$suite}, @$fb_result ] if @$fb_result;
    }
    return [ $virt{$suite} ];
}

sub read_src_entry_all {
    my ($hash, $key, $results, $non_results, $opts) = @_;
    my $result = $hash->{$key} || '';
    debug( "read_src_entry_all: key=$key", 1) if DEBUG;
    foreach (split /\000/o, $result) {
	my @data = split ( /\s/o, $_, 6 );
	debug( "Considering entry ".join( ':', @data), 2) if DEBUG;
	if ($opts->{h_archives}{$data[0]}
	    && $opts->{h_suites}{$data[1]}
	    && $opts->{h_sections}{$data[2]}) {
	    debug( "Using entry ".join( ':', @data), 2) if DEBUG;
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
    my ($keywords, $packages, $postfixes, $read_entry, $opts,
	$results, $non_results) = @_;

    my $first_keyword = lc shift @$keywords;
    @$keywords = map { lc $_ } @$keywords;

    my ($key, $prefixes) = ($first_keyword, '');
    my (%pkgs, %pkgs_min);
    $postfixes->seq( $key, $prefixes, R_CURSOR );
    while (index($key, $first_keyword) >= 0) {
	if ($prefixes =~ /^(\^)?\001(\d+)/o) {
	    debug("$key has too many hits", 2 ) if DEBUG;
	    $too_many_hits += $2;
	    if ($1) { # use the empty prefix
		foreach my $k (@$keywords) {
		    next unless $key =~ /\Q$k\E/;
		}
		debug("add key $key", 2) if DEBUG;
		$pkgs{$key}++;
		$pkgs_min{$key}++;
	    }
	} else {
	  PREFIX:
	    foreach (split /\000/o, $prefixes) {
		$_ = '' if $_ eq '^';
		my $word = "$_$key";
		foreach my $k (@$keywords) {
		    next PREFIX unless $word =~ /\Q$k\E/;
		}
		debug("add word $word", 2) if DEBUG;
		$pkgs{$word}++;
		$pkgs_min{$word}++ if $_ eq '';
	    }
	}
	last if $postfixes->seq( $key, $prefixes, R_NEXT ) != 0;
	last if keys %pkgs_min >= 100;
    }

    my $nr = keys %pkgs;
    my $min_nr = keys %pkgs_min;
    debug("nr=$nr min_nr=$min_nr too_many_hits=$too_many_hits", 1) if DEBUG;
    if ($nr >= 100) {
	$too_many_hits += $nr - $min_nr + 1;
	%pkgs = %pkgs_min;
    }
    foreach my $pkg (sort keys %pkgs) {
	&$read_entry( $packages, $pkg, $results, $non_results, $opts );
    }
}

sub do_xapian_search {
    my ($keywords, $dbpath, $did2pkg, $packages, $read_entry, $opts,
	$results, $non_results) = @_;

# NOTE: this needs to correspond with parse-packages!
    my @tmp;
    foreach my $keyword (@$keywords) {
	$keyword =~ s;[^\w/+]+; ;og;
	push @tmp, $keyword;
    }
    my $stemmer = Lingua::Stem->new();
    my @stemmed_keywords = grep { length($_) } @{$stemmer->stem( @tmp )};

    my $db = Search::Xapian::Database->new( $dbpath );
    my $enq = $db->enquire( OP_OR, @$keywords, @stemmed_keywords );
    debug( "Xapian Query was: ".$enq->get_query()->get_description(), 1) if DEBUG;
    my @matches = $enq->matches(0, 999);

    my (@order, %tmp_results);
    foreach my $match ( @matches ) {
	my $id = $match->get_docid();
	my $result = $did2pkg->{$id};

	foreach (split /\000/o, $result) {
	    my @data = split /\s/, $_, 3;
	    debug ("Considering $data[0], arch = $data[2], relevance=".$match->get_percent(), 3) if DEBUG;
#	    next unless $data[2] eq 'all' || $opts->{h_archs}{$data[2]};
#	    debug ("Ok", 3) if DEBUG;
	    unless ($tmp_results{$data[0]}++) {
		push @order, $data[0];
	    }
	}
	last if @order > 100;
    }
    undef $db;
    $too_many_hits++ if @order > 100;

    debug ("ORDER: @order", 2) if DEBUG;
    foreach my $pkg (@order) {
	&$read_entry( $packages, $pkg, $results, $non_results, $opts );
    }
}

sub find_similar {
    my ($pkg, $dbpath, $did2pkg) = @_;

    my $db = Search::Xapian::Database->new( $dbpath );
    my $enq = $db->enquire( "P$pkg" );
    debug( "Xapian Query was: ".$enq->get_query()->get_description(), 1) if DEBUG;
    my $first_match = ($enq->matches(0,1))[0]->get_document();

    my @terms;
    my $term_it = $first_match->termlist_begin();
    my $term_end = $first_match->termlist_end();

    for (; $term_it ne $term_end; $term_it++) {
	debug( "TERM: ".$term_it->get_termname(), 3);
	push @terms, $term_it->get_termname();
    }

    my $rel_enq = $db->enquire( OP_OR, @terms );
    debug( "Xapian Query was: ".$rel_enq->get_query()->get_description(), 1) if DEBUG;
    my @rel_pkg = $rel_enq->matches(2,20);

#    use Data::Dumper;
#    debug(Dumper(\@rel_pkg),1);

    my (@order, %tmp_results);
    foreach my $match ( @rel_pkg ) {
	my $id = $match->get_docid();
	my $result = $did2pkg->{$id};

	foreach (split /\000/o, $result) {
	    my @data = split /\s/, $_, 3;
	    debug ("Considering $data[0], arch = $data[2], relevance=".$match->get_percent(), 3) if DEBUG;
	    next if $data[0] eq $pkg;
	    unless ($tmp_results{$data[0]}++) {
		push @order, $data[0];
	    }
	}
    }
    undef $db;

    debug ("ORDER: @order", 2) if DEBUG;
    my $last = 10;
    $last = $#order if $#order < $last;
    return @order[0..$last];
}

sub find_binaries {
    my ($pkg, $archive, $suite, $src2bin) = @_;

    my $bins = $src2bin->{$pkg} || '';
    my %bins;
    foreach (split /\000/o, $bins) {
	my @data = split /\s/, $_, 5;

	debug( "find_binaries: considering @data", 3 ) if DEBUG;
	if (($data[0] eq $archive)
	    && ($data[1] eq $suite)) {
	    $bins{$data[2]}++;
	    debug( "find_binaries: using @data", 3 ) if DEBUG;
	}
    }

    return [ keys %bins ];
}


1;
