package Packages::DoFilelist;

use strict;
use warnings;

use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark ':hireswallclock';
use Exporter;

use Deb::Versions;
use Packages::Config qw( $DBDIR $ROOT @SUITES @ARCHIVES @SECTIONS
			 @ARCHITECTURES %FTP_SITES );
use Packages::CGI;
use Packages::DB;
use Packages::Search qw( :all );
use Packages::HTML;
use Packages::Page ();
use Packages::SrcPage ();

our @ISA = qw( Exporter );
our @EXPORT = qw( do_filelist );

sub do_filelist {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{package}) {
	fatal_error( "package not valid or not specified" );
    }
    if ($params->{errors}{suite}) {
	fatal_error( "suite not valid or not specified" );
    }
    if ($params->{errors}{arch}) {
	fatal_error( "arch not valid or not specified" );
    }

    $$menu = '';
    my $pkg = $opts->{package};
    my $suite = $opts->{suite}[0];
    my $arch = $opts->{arch}[0] ||'';

    %$html_header = ( title => "Filelist of package <em>$pkg</em> in <em>$suite</em> of arch <em>$arch</em>",
		      title_tag => "Filelist of of package $pkg/$suite/$arch",
		      lang => 'en',
		      keywords => "debian, $suite, $arch, filelist",
		      print_title => 1,
		      );

    unless (@Packages::CGI::fatal_errors) {
	if (tie my %contents, 'DB_File', "$DBDIR/contents/filelists_${suite}_${arch}.db",
	    O_RDONLY, 0666, $DB_BTREE) {

	    unless (exists $contents{$pkg}) {
		fatal_error( "No such package in this suite on this arch" );
	    } else {
		my @files = unpack "L/(CC/a)", $contents{$pkg};
		my $file = "";
		$$page_content .= '<pre style="border-top:solid #BFC3DC thin;padding:.5em;">';
		for (my $i=0; $i<scalar @files;) {
		    $file = substr($file, 0, $files[$i++]).$files[$i++];
		    $$page_content .= "$file\n";
		}
		$$page_content .= "</pre>";
	    }
	} else {
	    fatal_error( "Invalid suite/arch combination" );
	}
    }
}

1;
