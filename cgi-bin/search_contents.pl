#!/usr/bin/perl -wT
# $Id$
# search_packages.pl -- CGI interface to the Packages files on packages.debian.org
#
# Copyright (C) 1998 James Treacy
# Copyright (C) 2000, 2001 Josip Rodin
# Copyright (C) 2001 Adam Heath
# Copyright (C) 2004 Martin Schulze
# Copyright (C) 2004-2006 Frank Lichtenheld
#
# use is allowed under the terms of the GNU Public License (GPL)                              
# see http://www.fsf.org/copyleft/gpl.html for a copy of the license

sub contents() {

    my ($cgi) = @_;

    print "Extremely blunt ends-with search results:<br><pre>";
# only thing implemented yet: ends-with search
    my $kw = lc $cgi->param("keywords");
    $kw = reverse $kw;
# FIXME: ensure $suite is sanitized
    my $suite = 'stable';

    my $reverses = tie my %reverses, 'DB_File', "$DBDIR/contents/reverse_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	or die "Failed opening reverse DB: $!";
    
    my ($key, $rest) = ($kw, "");
    my $nres = 0;
    for (my $status = $reverses->seq($key, $value, R_CURSOR);
	$status == 0;
    	$status =  $reverses->seq( $key, $value, R_NEXT)) {

	# FIXME: what's the most efficient "is prefix of" thingy? We only want to know
	# whether $kw is or is not a prefix of $key
	last unless index($key, $kw) == 0;

	@hits = split /\0/o, $value;
	print reverse($key)." is found in @hits\n";
	last if $nres++ > 100;
    }

    $reverses = undef;
    untie %reverses;
    print "</pre>$nres results displayed";
}

1;
# vim: ts=8 sw=4
