# Packages::CommonCode - random utility functions
#
# Copyright (C) 2006  Jeroen van Wolffelaar <jeroen@wolffelaar.nl>
# Copyright (C) 2006-2007 Frank Lichtenheld
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 1 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Packages::CommonCode;

use strict;
use warnings;

use DB_File;
use File::Path;

use base 'Exporter';

our %EXPORT_TAGS = ( 'all' => [ qw(parse_control_par activate activate_dir mkdirp) ] );
our @EXPORT_OK = @{$EXPORT_TAGS{all}};

sub parse_control_par {
    local ($_) = @_;

    my %data = ();
    chomp;
    s/\n /\377/g;
    while (/^(\S+):\s*(.*)\s*$/mg) {
	my ($key, $value) = ($1, $2);
	$value =~ s/\377/\n /g;
	$key =~ tr [A-Z] [a-z];
	$data{$key} = $value;
    }

    return %data;
}

sub activate {
    my ($file) = @_;

    rename("${file}.new", $file);
}

sub activate_dir {
    my ($dir) = @_;

    my $tmp = "${dir}.old";
    rename($dir, $tmp);
    activate($dir);
    rmtree($tmp);
}

sub mkdirp {
    my ($dir) = @_;

    -d $dir || mkpath($dir);
}

1;
