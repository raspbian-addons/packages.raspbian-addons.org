package Packages::DBI::Descriptions;

use strict;
use warnings;

use parent 'Packages::DBI';

__PACKAGE__->table('descriptions');
__PACKAGE__->columns( Primary => qw(md5 lang) );
__PACKAGE__->columns( Essential  => qw(descr) );
__PACKAGE__->columns( Others => qw(stale) );

1;
