package Packages::DoNewPkg;

use strict;
use warnings;

use POSIX;
use CGI ();
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_newpkg );

use Packages::Search qw( :all );
use Packages::CGI;
use Packages::DB;
use Packages::Config qw( $TOPDIR @SECTIONS $ROOT );

sub do_newpkg {
    my ($params, $opts, $page_content) = @_;
    my $cat = $opts->{cat};

    if ($params->{errors}{suite}) {
	fatal_error( $cat->g( "suite not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( $cat->g( "more than one suite specified for newpkg (%s)",
			      "@{$opts->{suite}}" ) );
    }

    my $sort_func = sub { $_[0][0] cmp $_[1][0] };
    $sort_func = sub { $_[0][1] <=> $_[1][1] or $_[0][0] cmp $_[1][0] }
	if $opts->{mode} eq 'byage';

    my $suite = $opts->{suite}[0];
    my $one_archive = @{$opts->{archive}} == 1 ?
	$opts->{archive}[0] : undef;
    my $one_section = @{$opts->{section}} == 1 ?
	$opts->{section}[0] : undef;

    my @new_pkgs;
    open NEWPKG, '<', "$TOPDIR/files/packages/newpkg_info_$suite"
	or do {
	    warn "can't read newpkg_info_$suite: $!";
	    fatal_error( $cat->g("no newpkg information found for suite %s",
				 $suite) );
	    return;
    };
    while (<NEWPKG>) {
	chomp;
	my @data = split /\s/, $_, 11;

	next unless $data[2]; #removed packages
	next unless $data[3] eq $suite;
	next if $one_archive and $data[2] ne $one_archive;
	next if $one_section and $data[5] ne $one_section;

	debug( "new pkg: @data", 1 ) if DEBUG;
	push @new_pkgs, \@data;
    }
    close NEWPKG;
    
    (my @date)= gmtime();
    #FIXME: compute in the template
    $page_content->{rss_timestamp} = strftime ("%Y-%m-%dT%H:%M+00:00", @date);

    if (@new_pkgs) {
	$page_content->{new_packages} = [ sort { &$sort_func($a,$b) } @new_pkgs ];
    }

    $page_content->{suite} = $suite;
    $page_content->{section} = $one_section if $one_section;
    $page_content->{archive} = $one_archive if $one_archive;
    $page_content->{sections} = \@SECTIONS;

}

1;
