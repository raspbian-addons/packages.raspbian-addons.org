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

our @DEP_FIELDS = qw( build-depends build-depends-indep
		      build-conflicts build-conflicts-indep);
sub merge_package {
    my ($self, $data) = @_;

    ($data->{package} && $data->{suite} && $data->{archive}) || return;
    $self->{package} ||= $data->{package};
    ($self->{package} eq $data->{package}) || return;
    debug( "merge package $data->{package}/$data->{version} into $self (".($self->{version}||'').")", 2 ) if DEBUG;

    if (!$self->{version}
	|| (version_cmp( $data->{version}, $self->{version} ) > 0)) {
	debug( "added package is newer, replacing old information" ) if DEBUG;

	$self->{data} = $data;

	my ($uploaders, $orig_uploaders) = handle_maintainer_fields($data);
	$self->{uploaders} = $uploaders;
	$self->{orig_uploaders} = $orig_uploaders if @$orig_uploaders;

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

    my @deps;
    foreach my $dep (@{$self->{dep_fields}{$dep_field}[1]}) {
	my @or_deps;
	foreach my $or_dep ( @$dep ) {
	    my $p_name = $or_dep->[0];
	    my $p_version = $or_dep->[1] ? "$or_dep->[1] $or_dep->[2]" : undef;
	    my $arch_neg;
	    my $arch_str = '';
	    if ($or_dep->[3] && @{$or_dep->[3]}) {
		# as either all or no archs have to be prepended with
		# exlamation marks, use the first and delete the others
		if ($or_dep->[3][0] =~ /^!/) {
		    $arch_neg = 1;
		    foreach (@{$or_dep->[3]}) {
			$_ =~ s/^!//go;
		    }
		}
		$arch_str = join(" ",sort(@{$or_dep->[3]}));
	    }

	    push @or_deps, [ $p_name, $p_version, $arch_neg, $arch_str ];
	}
	push @deps, [ 0, @or_deps ];
    }
    return \@deps;
}

1;
