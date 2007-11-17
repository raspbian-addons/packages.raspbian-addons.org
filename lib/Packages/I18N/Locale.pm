package Packages::I18N::Locale;

use strict;
use warnings;

use base 'Locale::Maketext';
use Locale::Maketext::Lexicon {
    'en' => [Gettext => '/home/djpig/debian/www.d.o/packages/po/pdo.pot',
	     Gettext => '/home/djpig/debian/www.d.o/packages/po/templates.pot',
	     Gettext => '/home/djpig/debian/www.d.o/packages/po/langs.pot',
	     Gettext => '/home/djpig/debian/www.d.o/packages/po/sections.pot',
	     Gettext => '/home/djpig/debian/www.d.o/packages/po/debtags.pot'],
    '*' => [Gettext => '/home/djpig/debian/www.d.o/packages/po/pdo.*.po',
	    Gettext => '/home/djpig/debian/www.d.o/packages/po/templates.*.po',
	    Gettext => '/home/djpig/debian/www.d.o/packages/po/langs.*.po',
	    Gettext => '/home/djpig/debian/www.d.o/packages/po/sections.*.po',
	    Gettext => '/home/djpig/debian/www.d.o/packages/po/debtags.*.po'],
    _auto   => 1,
    _style  => 'gettext',
};

use base 'Exporter';

our @EXPORT = qw( N_ );

sub N_ { return $_[0]; }

sub g {
    my ($self, $format, @args) = @_;
    my $result = $self->maketext($format, @args);
    return sprintf($result, @args) if $result =~ /%([su]|[.\d]*f)/;
    return $result;
}

1;
