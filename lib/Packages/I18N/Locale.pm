package Packages::I18N::Locale;

use strict;
use warnings;

use base 'Locale::Maketext';
use Locale::Maketext::Lexicon {
    '*' => [Gettext => '/home/djpig/debian/www.d.o/packages/po/pdo.*.po',
	    Gettext => '/home/djpig/debian/www.d.o/packages/po/templates.*.po',
	    Gettext => '/home/djpig/debian/www.d.o/packages/po/langs.*.po'],
    _auto   => 1,
    _style  => 'gettext',
};

use base 'Exporter';

our @EXPORT = qw( _g N_ );

sub _g { return $_[0]; }
sub N_ { return $_[0]; }

sub g {
    my ($self, $format, @args) = @_;
    my $result = $self->maketext($format, @args);
    return sprintf($result, @args) if $result =~ /%[su]/;
    return $result;
}

1;
