package Packages::DBI::Debtags;

use strict;
use warnings;

use parent 'Packages::DBI';

__PACKAGE__->table('debtags');
__PACKAGE__->columns( All => qw(id descr) );

1;
