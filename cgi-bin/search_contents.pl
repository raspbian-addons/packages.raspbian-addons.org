#!/usr/bin/perl -wT
# $Id$
# search_contents.pl -- CGI interface to the Contents files on packages.debian.org
#
# Copyright (C) 2006 Jeroen van Wolffelaar
#
# use is allowed under the terms of the GNU Public License (GPL)                              
# see http://www.fsf.org/copyleft/gpl.html for a copy of the license

sub contents() {
    my $nres = 0;

    my ($cgi) = @_;

    print "Extremely blunt ends-with search results:<br><pre>";
# only thing implemented yet: ends-with search
    my $kw = lc $cgi->param("keywords");
    # full filename search is tricky
    my $ffn = $cgi->param("fullfilename");
    $ffn = $ffn ? 1 : 0;


my $suite = 'stable'; #fixme

    # fixme: I should open $reverses only once per search
    my $reverses = tie my %reverses, 'DB_File', "$DBDIR/contents/reverse_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	or die "Failed opening reverse DB: $!";

    if ($ffn) {
	open FILENAMES, "$DBDIR/contents/filenames_$suite.txt"
	    or die "Failed opening filename table";
	while (<FILENAMES>) {
	    next if index($_, $kw)<0;
	    chomp;
	    last unless &dosearch(reverse($_)."/", \$nres, $reverses);
	}
	close FILENAMES;
    } else {

	$kw = reverse $kw;
	
	# exact filename searching follows trivially:
	my $exact = $cgi->param("exact");
	$kw = "$kw/" if $exact;

	print "ERROR: Exact and fullfilenamesearch don't go along" if $ffn and $exact;

	&dosearch($kw, \$nres, $reverses);
    }
    print "</pre>$nres results displayed";
    $reverses = undef;
    untie %reverses;

}

sub dosearch
{
    my ($kw, $nres, $reverses) = @_;

    my ($key, $rest) = ($kw, "");
    for (my $status = $reverses->seq($key, $value, R_CURSOR);
	$status == 0;
    	$status =  $reverses->seq( $key, $value, R_NEXT)) {

	# FIXME: what's the most efficient "is prefix of" thingy? We only want to know
	# whether $kw is or is not a prefix of $key
	last unless index($key, $kw) == 0;

	@hits = split /\0/o, $value;
	print reverse($key)." is found in @hits\n";
	last if ($$nres)++ > 100;
    }

    return $$nres<100;
}

1;
# vim: ts=8 sw=4
