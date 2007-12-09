package Packages::I18N::Locale;

use strict;
use warnings;

use base 'Locale::Maketext';
use Locale::Maketext::Lexicon;

use base 'Exporter';

our @EXPORT = qw( N_ );

sub load {
    my ($podir) = @_;

    Locale::Maketext::Lexicon->import( {
	'en' => [Gettext => "$podir/pdo.pot",
		 Gettext => "$podir/templates.pot",
		 Gettext => "$podir/langs.pot",
		 Gettext => "$podir/sections.pot",
		 Gettext => "$podir/debtags.pot"],
	'*' => [Gettext => "$podir/pdo.*.po",
		Gettext => "$podir/templates.*.po",
		Gettext => "$podir/langs.*.po",
		Gettext => "$podir/sections.*.po",
		Gettext => "$podir/debtags.*.po"],
	_auto   => 1,
	_style  => 'gettext',
				       } );
}

sub N_ { return $_[0]; }

sub g {
    my ($self, $format, @args) = @_;
    my $result = $self->maketext($format, @args);
    return sprintf($result, @args) if $result =~ /%([su]|[.\d]*f)/;
    return $result;
}

1;
