package Packages::Template;

use strict;
use warnings;

use Template;
use Locale::gettext;
use URI ();
use HTML::Entities ();
use URI::Escape ();
use Benchmark ':hireswallclock';

use Packages::CGI;
use Packages::Config qw( @LANGUAGES );
use Packages::I18N::Locale;
use Packages::I18N::Languages;
use Packages::I18N::LanguageNames;

our @ISA = qw( Exporter );
#our @EXPORT = qw( head );

use constant COMPILE => 1;

sub new {
    my ($classname, $include, $format, $vars, $options) = @_;
    $vars ||= {};
    $options ||= {};

    my $self = {};
    bless( $self, $classname );

    my @timestamp = gmtime;
    $vars->{timestamp} = {
	year => $timestamp[5]+1900,
	string => scalar gmtime() .' UTC',
    };
    $vars->{make_search_url} = sub { return &Packages::CGI::make_search_url(@_) };
    $vars->{make_url} = sub { return &Packages::CGI::make_url(@_) };
    $vars->{g} = sub { return &Packages::I18N::Locale::tt_gettext(@_) };
    $vars->{extract_host} = sub { my $uri = URI->new($_[0]);
				  my $host = $uri->host;
				  $host .= ':'.$uri->port if $uri->port != $uri->default_port;
				  return $host;
			      };
    # needed to work around the limitations of the the FILTER syntax
    $vars->{html_encode} = sub { return HTML::Entities::encode_entities(@_,'<>&"') };
    $vars->{uri_escape} = sub { return URI::Escape::uri_escape(@_) };
    $vars->{quotemeta} = sub { return quotemeta($_[0]) };
    $vars->{string2id} = sub { return &Packages::CGI::string2id(@_) };

    $self->{template} = Template->new( {
	PRE_PROCESS => [ 'config.tmpl' ],
	INCLUDE_PATH => $include,
	VARIABLES => $vars,
	COMPILE_EXT => '.ttc',
	%$options,
    } ) or die sprintf( "Initialization of Template Engine failed: %s", $Template::ERROR );
    $self->{format} = $format;
    $self->{vars} = $vars;

    return $self;
}

sub process {
    my $self = shift;
    return $self->{template}->process(@_);
}
sub error {
    my $self = shift;
    return $self->{template}->error(@_);
}

sub page {
    my ($self, $action, $page_content, $target) = @_;

    #use Data::Dumper;
    #die Dumper($self, $action, $page_content);
    $page_content->{used_langs} ||= \@LANGUAGES;
    $page_content->{langs} = languages( $page_content->{lang}
					|| $self->{vars}{lang} || 'en',
					@{$page_content->{used_langs}} );

    my $txt;
    if ($target) {
	$self->process("$self->{format}/$action.tmpl", $page_content, $target)
	    or die sprintf( "template error: %s", $self->error ); # too late for reporting on-line
    } else {
	$self->process("$self->{format}/$action.tmpl", $page_content, \$txt)
	    or die sprintf( "template error: %s", $self->error );
    }
    return $txt;
}

sub error_page {
    my ($self, $page_content) = @_;

#    use Data::Dumper;
#    warn Dumper($page_content);

    my $txt;
    $self->process("html/error.tmpl", $page_content, \$txt)
	or die sprintf( "template error: %s", $self->error ); # too late for reporting on-line

    return $txt;
}

sub languages {
    my ( $lang, @used_langs ) = @_;
    
    my @langs;

    if (@used_langs) {
	
	my @printed_langs = ();
	foreach (@used_langs) {
	    next if $_ eq $lang; # Never print the current language
	    unless (get_selfname($_)) { warn "missing language $_"; next } #DEBUG
	    push @printed_langs, $_;
	}
	return [] unless scalar @printed_langs;
	# Sort on uppercase to work with languages which use lowercase initial
	# letters.
	foreach my $cur_lang (sort langcmp @printed_langs) {
	    my %lang;
	    $lang{lang} = $cur_lang;
	    $lang{tooltip} = dgettext( "langs", get_language_name($cur_lang) );
            $lang{selfname} = get_selfname($cur_lang);
	    $lang{transliteration} = get_transliteration($cur_lang) if defined get_transliteration($cur_lang);
	    push @langs, \%lang;
	}
    }
    
    return \@langs;
}

1;
