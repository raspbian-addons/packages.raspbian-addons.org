package Packages::DoFilelist;

use strict;
use warnings;

use POSIX;
use DB_File;
use Exporter;

use Deb::Versions;
use Packages::Config qw( $DBDIR $ROOT @SUITES @ARCHIVES @SECTIONS
			 @ARCHITECTURES %FTP_SITES );
use Packages::CGI;
use Packages::DB;
use Packages::Search qw( :all );
use Packages::Page ();
use Packages::SrcPage ();

our @ISA = qw( Exporter );
our @EXPORT = qw( do_filelist );

sub do_filelist {
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

    my $pkg = $opts->{package};
    my $suite = $opts->{suite}[0];
    my $arch = $opts->{arch}[0] ||'';
    $page_content->{pkg} = $pkg;
    $page_content->{suite} = $suite;
    $page_content->{arch} = $arch;

    unless (@Packages::CGI::fatal_errors) {
	if (tie my %contents, 'DB_File', "$DBDIR/contents/filelists_${suite}_${arch}.db",
	    O_RDONLY, 0666, $DB_BTREE) {

	    unless (exists $contents{$pkg}) {
		fatal_error( $cat->g( "No such package in this suite on this architecture." ) );
	    } else {
		my @files = unpack "L/(CC/a)", $contents{$pkg};
		my $file = '';

		$page_content->{files} = [];
		for (my $i=0; $i<scalar @files;) {
		    $file = substr($file, 0, $files[$i++]).$files[$i++];
		    push @{$page_content->{files}}, "/$file";
		}
	    }
	} else {
	    fatal_error( $cat->g( "Invalid suite/architecture combination" ) );
	}
    }
}

1;
