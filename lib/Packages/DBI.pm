# Copyright (C) 2013  Damyan Ivanov <dmn@debian.org>
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# base class for DB work

package Packages::DBI;

use parent 'Class::DBI';
use Carp qw(confess);

use Packages::Config qw($DB_NAME);

sub connection {
    my ($class, $opts) = ( shift, shift // {} );
    confess 'Synopsis: Packages::DBI->connection( [ \%opts ] )' if @_;

    my ( $user, $password );
    my %attr = ( AutoCommit => 1, RaiseError => 1, pg_enable_utf8 => 0 );
    $attr{AutoCommit} = 0 if $opts->{rw};

    $class->SUPER::connection( "dbi:Pg:db=$DB_NAME", undef, undef, \%attr );
}

1;
