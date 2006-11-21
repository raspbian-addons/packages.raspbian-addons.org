package Packages::DoIndex;

use strict;
use warnings;

use CGI qw( :cgi );
use Exporter;

use Deb::Versions;
use Packages::Config qw( $TOPDIR );
use Packages::I18N::Locale;
use Packages::CGI;

our @ISA = qw( Exporter );
our @EXPORT = qw( do_index do_allpackages );

sub do_index {
    return send_file( 'index', @_ );
}
sub do_allpackages {
    return send_file( 'allpackages', @_ );
}

# no real need for more flexibility here, I think...
my %mime_types = (
		  txt => 'text/plain',
		  'txt.gz' => 'text/plain',
		  html => 'text/html',
		  );
my %encoding = (
		'txt.gz' => 'x-gzip',
		);
sub send_file {
    my ($file, $params, $opts, $html_header) = @_;

    if ($params->{errors}{suite}) {
	fatal_error( _g( "suite not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( sprintf( _g( "more than one suite specified for show_static (%s)" ), "@{$opts->{suite}}" ) );
    }
    if (@{$opts->{subsection}} > 1) {
	fatal_error( sprintf( _g( "more than one suite specified for show_static (%s)" ), "@{$opts->{suite}}" ) );
    }

    my $wwwdir = "$TOPDIR/www";
    my $path = "";
    $path .= "source/" if $opts->{source};
    $path .= "$opts->{suite}[0]/";
    $path .= "$opts->{archive}[0]/" if @{$opts->{archive}} == 1;
    $path .= "$opts->{subsection}[0]/" if @{$opts->{subsection}};
    $path .= "$opts->{priority}[0]/" if @{$opts->{priority}};
    # we don't have translated index pages for subsections yet
    $opts->{lang} = 'en' if @{$opts->{subsection}} or $file eq 'allpackages';
    $path .= "$file.$opts->{lang}.$opts->{format}";

    unless (@Packages::CGI::fatal_errors) {
	my $buffer;
	if (open( INDEX, '<', "$wwwdir/$path" )) {
	    my %headers;
	    $headers{'-charset'} = get_charset( $opts->{lang} );
	    $headers{'-type'} = $mime_types{$opts->{format}} || 'text/plain';
	    $headers{'-content-encoding'} = $encoding{$opts->{format}} if exists $encoding{$opts->{format}};
	    print header( %headers );

	    binmode INDEX;
	    while (read INDEX, $buffer, 4096) {
		print $buffer;
	    }
	    close INDEX;
	    exit;
	} else {
	    fatal_error( sprintf( _g( "couldn't read index file %s: %s" ),
				  $path, $! ) );
	}
    }
}

1;

