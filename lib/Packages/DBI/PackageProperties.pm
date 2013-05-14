package Packages::DBI::PackageProperties;

use strict;
use warnings;

use parent 'Packages::DBI';

__PACKAGE__->table('package_properties');
__PACKAGE__->columns( Primary => qw(package name) );
__PACKAGE__->columns( Essential => qw(value) );
__PACKAGE__->columns( Others => qw(stale) );

__PACKAGE__->has_a( package => 'Packages::DBI::Packages' );


1;
