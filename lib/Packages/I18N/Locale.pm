package Packages::I18N::Locale;

use strict;
use warnings;

use Exporter;
use Locale::gettext;

our @ISA = qw( Exporter );
# the reason we have both _g and _ is simply that there
# seem to be some situations where Perl doesn't handle _
# correctly. If in doubt use _g
our @EXPORT = qw( get_locale get_charset _g N_ );

my %lang2loc = ( en => "en_US",
		 cs => "cs_CZ",
		 da => "da_DK",
		 ja => "ja_JP",
		 sv => "sv_SE",
		 uk => "uk_UA",
		 default => "en_US",
		 );

# this can probably be removed now that all locales are available in UTF-8
my %lang2charset = (
		    default => 'UTF-8',
		    );

sub get_locale {
    my $lang = shift;
    my $locale = $lang;

    return "$lang2loc{default}.".get_charset() unless $lang;

    if ( length($lang) == 2 ) {
	$locale = $lang2loc{$lang} || ( "${lang}_" . uc $lang );
    } elsif ( $lang !~ /^[a-z][a-z]_[A-Z][A-Z]$/ ) {
	warn "get_locale: couldn't determine locale\n";
	return;
    }
    $locale .= ".".get_charset($lang);
    return $locale;
}

sub get_charset {
    my $lang = shift;

    return $lang2charset{default} unless $lang;
    return $lang2charset{$lang} || $lang2charset{default};
}

sub tt_gettext {
    my ($str, @args) = @_;
    return dgettext( 'templates', $str ) unless @args;
    return sprintf(dgettext( 'templates', $str ), @args);
}
sub _g { return gettext( $_[0] ) }
sub N_ { return $_[0] }

1;
