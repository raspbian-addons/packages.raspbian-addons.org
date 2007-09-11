# Taken from the webwml CVS tree (english/templates/language_names.wml)

package Packages::I18N::LanguageNames;

use strict;
use warnings;

use Exporter;
use Packages::I18N::Locale;

our @ISA = qw( Exporter );
our @EXPORT = qw( get_language_name get_all_languages );

my %ctrans = (
	ar    => N_("Arabic"),
	fi    => N_("Finnish"),
	hr    => N_("Croatian"),
	da    => N_("Danish"),
	nl    => N_("Dutch"),
	en    => N_("English"),
	fr    => N_("French"),
	de    => N_("German"),
	it    => N_("Italian"),
	ja    => N_("Japanese"),
	ko    => N_("Korean"),
	es    => N_("Spanish"),
	pt_BR => N_("Portuguese (Brasilia)"),
	pt_PT => N_("Portuguese (Portugal)"),
	zh    => N_("Chinese"),
	sv_SE => N_("Swedish"),
	pl    => N_("Polish"),
	'no'  => N_("Norwegian"),
	tr    => N_("Turkish"),
	ru    => N_("Russian"),
	cs    => N_("Czech"),
	eo    => N_("Esperanto"),
	hu    => N_("Hungarian"),
	ro    => N_("Romanian"),
	sk    => N_("Slovak"),
	el    => N_("Greek"),
  	ca    => N_("Catalan"),
	lt    => N_("Lithuanian"),
	sl    => N_("Slovene"),
	bg    => N_("Bulgarian"),
	uk    => N_("Ukrainian"),
);

sub get_language_name {
    return $ctrans{$_[0]};
}

sub get_all_languages {
    return %ctrans;
}

1;
