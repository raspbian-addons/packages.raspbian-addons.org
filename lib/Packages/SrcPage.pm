package Packages::SrcPage;

use strict;
use warnings;

use Data::Dumper;
use Deb::Versions;
use Packages::CGI;
use Packages::Page qw( :all );

our @ISA = qw( Packages::Page );

#FIXME: change parameters so that we can use the version from Packages::Page
sub merge_data {
    my ($self, $pkg, $suite, $archive, $data) = @_;

    my %data = split /\00/o, $data;
    $data{package} = $pkg;
    $data{suite} = $suite;
    $data{archive} = $archive;

    return $self->merge_package( \%data );
}

sub gettext { return $_[0]; }

our @DEP_FIELDS = qw( build-depends build-depends-indep
		      build-conflicts build-conflicts-indep);
sub merge_package {
    my ($self, $data) = @_;

    ($data->{package} && $data->{suite} && $data->{archive}) || return;
    $self->{package} ||= $data->{package};
    ($self->{package} eq $data->{package}) || return;
    debug( "merge package $data->{package}/$data->{version} into $self (".($self->{version}||'').")", 2 );

    if (!$self->{version}
	|| (version_cmp( $data->{version}, $self->{version} ) > 0)) {
	debug( "added package is newer, replacing old information" );

	$self->{data} = $data;

	my @uploaders;
	if ($data->{maintainer} ||= '') {
	    push @uploaders, [ split_name_mail( $data->{maintainer} ) ];
	}
	if ($data->{uploaders}) {
	    my @up_tmp = split( /\s*,\s*/,
				$data->{uploaders} );
	    foreach my $up (@up_tmp) {
		if ($up ne $data->{maintainer}) { # weed out duplicates
		    push @uploaders, [ split_name_mail( $up ) ];
		}
	    }
	}
	$self->{uploaders} = \@uploaders;

	if ($data->{files}) {
	    my @files = split /\01/so, $data->{files};
	    $self->{files} = \@files;
	}

	foreach (@DEP_FIELDS) {
	    $self->normalize_dependencies( $_, $data );
	}

	$self->{version} = $data->{version};
    }
}

#FIXME: should be mergable with the Packages::Page version
sub normalize_dependencies {
    my ($self, $dep_field, $data) = @_;

    my ($deps_norm, $deps) = parse_deps( $data->{$dep_field}||'' );
    $self->{dep_fields}{$dep_field} =
	[ $deps_norm, $deps ];
}

sub get_src {
    my ($self, $field) = @_;
    
    return $self->{$field} if exists $self->{$field};
    return $self->{data}{$field};
}

sub get_architectures {
    die "NOT SUPPORTED";
}

sub get_arch_field {
    my ($self, $field) = @_;

    return $self->{data}{$field};
}

sub get_versions {
    my ($self) = @_;

    return [ $self->{version} ];
}

sub get_version_string {
    my ($self) = @_;

    my $versions = $self->get_versions;

    return ($self->{version}, $versions);
}

sub get_dep_field {
    my ($self, $dep_field) = @_;

    return $self->{dep_fields}{$dep_field}[1];
}

1;
