package Packages::DoIndex;

use strict;
use warnings;

use CGI qw( :cgi );
use Exporter;

use Deb::Versions;
use Packages::Config qw( $TOPDIR );
use Packages::CGI;

our @ISA = qw( Exporter );
our @EXPORT = qw( do_index do_allpackages );

sub do_index {
    return send_file( 'index', @_ );
}
sub do_allpackages {
    return send_file( 'allpackages', @_ );
}

my %encoding = (
		'txt.gz' => 'x-gzip',
		);
sub send_file {
    my ($file, $params, $opts) = @_;
    my $cat = $opts->{cat};

    if ($params->{errors}{suite}) {
	fatal_error( $cat->g( "suite not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( $cat->g( "more than one suite specified for show_static (%s)",
			      "@{$opts->{suite}}" ) );
    }
    if (@{$opts->{subsection}} > 1) {
	fatal_error( $cat->g( "more than one subsection specified for show_static (%s)",
			      "@{$opts->{suite}}" ) );
    }

    if ($opts->{format} eq 'txt.gz') {
	$opts->{po_lang} = 'en';
    }
    my $wwwdir = "$TOPDIR/www";
    my $path = "";
    $path .= "source/" if $opts->{source};
    $path .= "$opts->{suite}[0]/";
#    $path .= "$opts->{archive}[0]/" if @{$opts->{archive}} == 1;
    $path .= "$opts->{subsection}[0]/" if @{$opts->{subsection}};
    $path .= "$opts->{priority}[0]/" if @{$opts->{priority}};
    $path .= "$file.$opts->{po_lang}.$opts->{format}";

    unless (@Packages::CGI::fatal_errors) {
	my $buffer;
	if (open( INDEX, '<', "$wwwdir/$path" )) {
	    my %headers;
	    $headers{'-charset'} = 'UTF-8';
	    $headers{'-type'} = get_mime( $opts->{format}, 'text/plain' );
	    $headers{'-content-encoding'} = $encoding{$opts->{format}} if exists $encoding{$opts->{format}};
	    my ($size,$mtime) = (stat("$wwwdir/$path"))[7,9];
	    $headers{'-content-length'} = $size;
	    $headers{'-last-modified'} = gmtime($mtime);
	    print header( %headers );

	    binmode INDEX;
	    while (read INDEX, $buffer, 4096) {
		print $buffer;
	    }
	    close INDEX;
	    exit;
	} else {
	    fatal_error( $cat->g( "couldn't read index file %s: %s",
				  $path, $! ) );
	}
    }
}

1;

