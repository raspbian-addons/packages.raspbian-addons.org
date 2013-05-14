package Packages::DoDownload;

use strict;
use warnings;

use POSIX;
use CGI ();
use Benchmark ':hireswallclock';
use Exporter;

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::Config qw( $DBDIR @SUITES @ARCHIVES @SECTIONS @ARCHITECTURES );
use Packages::CGI;
use Packages::DB;
use Packages::DBI::Packages;

our @ISA = qw( Exporter );
our @EXPORT = qw( do_download );


sub do_download {
    my ($params, $opts, $page_content) = @_;
    my $cat = $opts->{cat};

    if ($params->{errors}{package}) {
	fatal_error( $cat->g( "package not valid or not specified" ) );
    }
    if ($params->{errors}{suite}) {
	fatal_error( $cat->g( "suite not valid or not specified" ) );
    }
    if ($params->{errors}{arch}) {
	fatal_error( $cat->g( "architecture not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( $cat->g( "more than one suite specified for download (%s)",
			      "@{$opts->{suite}}" ) );
    }
    if (@{$opts->{arch}} > 1) {
	fatal_error( $cat->g( "more than one architecture specified for download (%s)",
			      "@{$opts->{arch}}" ) );
    }

    $opts->{h_sections} = { map { $_ => 1 } @SECTIONS };
    my $pkg = $opts->{package};
    my $suite = $opts->{suite}[0];
    my $arch = $opts->{arch}[0] ||'';

    my (@results);
    my ($final_result, $filename, $directory, @file_components, $archive) = ("")x5;

    my $st0 = new Benchmark;
    unless (@Packages::CGI::fatal_errors) {
	read_entry( \%packages, $pkg, \@results, $opts );

	@results = grep { $_->[7] ne 'v' } @results;
	unless (@results) {
#	    fatal_error( _g( "No such package." )."<br>".
#			 sprintf( _g( '<a href="%s">Search for the package</a>' ), "$SEARCH_URL/$pkg" ) );
	} else {
	    my $final_result = shift @results;
	    foreach (@results) {
		if (version_cmp( $_->[7], $final_result->[7] ) > 0) {
		    $final_result = $_;
		}
	    }
	    
	    debug( "final_result=@$final_result", 1 );
	    $archive = $final_result->[1];
            my $p = Packages::DBI::Packages->retrieve(
                suite        => $suite,
                package      => $pkg,
                architecture => $arch,
                version      => $final_result->[7]
            );
	    if (!$p && $arch ne 'all' && $final_result->[3] eq 'all') {
                $p = Packages::DBI::Packages->retrieve(
                    suite        => $suite,
                    package      => $pkg,
                    architecture => 'all',
                    version      => $final_result->[7]
                );
		debug( "choosing arch 'all' instead of requested arch $arch", 1 );
		$arch = 'all';
#		fatal_error( _g( "No such package." )."<br>".
#			     sprintf( _g( '<a href="%s">Search for the package</a>' ), "$SEARCH_URL/$pkg" ) ) unless %data;
	    }
            @file_components = split( '/', $p->prop_value('filename') );
	    $filename = pop(@file_components);
	    $directory = join( '/', @file_components).'/';

	    $page_content->{archive} = $archive;
	    $page_content->{suite} = $suite;
	    $page_content->{pkg} = $pkg;
	    my $pkgsize = floor(($p->prop_value('size')/102.4)+0.5)/10;
	    if ($pkgsize < 1024) {
		$page_content->{pkgsize} = $pkgsize;
		$page_content->{pkgsize_unit} = $cat->g( 'kByte' );
	    } else {
		$page_content->{pkgsize} = floor(($p->prop_value('size')/(102.4*102.4))+0.5)/100;
		$page_content->{pkgsize_unit} = $cat->g( 'MByte' );
	    }
	    $page_content->{architecture} = $arch;
	    foreach ($p->properties) {
		$page_content->{$_->name} = $_->value;
	    }
	    $page_content->{filename} = { file => $filename,
					  directory => $directory,
				          full => $p->prop_value('filename'),
				      };

	}
    }
	
}

1;
