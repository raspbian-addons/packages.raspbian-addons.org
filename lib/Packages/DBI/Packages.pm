package Packages::DBI::Packages;

use strict;
use warnings;

use parent 'Packages::DBI';

__PACKAGE__->table('packages');
__PACKAGE__->columns( Primary => qw(id) );
__PACKAGE__->columns( Essential => qw(suite package architecture version stale) );

__PACKAGE__->has_many( properties => 'Packages::DBI::PackageProperties' );

use overload '""' => \&as_string;

sub as_string {
    my $self = shift;

    return join( '/',
        $self->suite, $self->package, $self->architecture, $self->version );
}

sub prop_value {
    my ( $self, $prop ) = @_;

    my $p = Packages::DBI::PackageProperties->retrieve(
        package => $self->id,
        name    => $prop
    );

    return $p ? $p->value : undef;
}

1;
