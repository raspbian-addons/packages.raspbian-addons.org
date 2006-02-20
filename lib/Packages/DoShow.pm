package Packages::DoShow;

use strict;

use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark;
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
our @EXPORT = qw( do_show );

sub do_show {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{package}) {
	fatal_error( "package not valid or not specified" );
    }
    if ($params->{errors}{suite}) {
	fatal_error( "suite not valid or not specified" );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( "more than one suite specified for show (@{$opts->{suite}})" );
    }

    my $pkg = $opts->{package};
    my $encodedpkg = uri_escape( $pkg );
    my $suite = $opts->{suite}[0];
    my $archive = $opts->{archive}[0] ||'';
    
    my $DL_URL = "$pkg/download";
    my $FILELIST_URL = "$pkg/files";

    our (%packages_all, %sources_all);
    my (@results, @non_results);
    my $page = $opts->{source} ?
	new Packages::SrcPage( $pkg ) :
	new Packages::Page( $pkg );
    my $package_page = "";
    my ($short_desc, $version, $section, $subsection) = ("")x5;
    
    sub gettext { return $_[0]; };

    my $st0 = new Benchmark;
    unless (@Packages::CGI::fatal_errors) {
	tie %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";
	tie %sources_all, 'DB_File', "$DBDIR/sources_all_$suite.db",
	O_RDONLY, 0666, $DB_BTREE
	    or die "couldn't tie DB $DBDIR/sources_all_$suite.db: $!";

	unless ($opts->{source}) {
	    read_entry_all( \%packages, $pkg, \@results, \@non_results, $opts );
	} else {
	    read_src_entry_all( \%sources, $pkg, \@results, \@non_results, $opts );
	}

	unless (@results || @non_results ) {
	    fatal_error( "No such package".
			 "{insert link to search page with substring search}" );
	} else {
	    my %all_suites;
	    foreach (@results, @non_results) {
		my $a = $_->[1];
		my $s = $_->[2];
		if ($a =~ /^(?:us|security|non-US)$/o) {
		    $all_suites{$s}++;
		} else {
		    $all_suites{"$s/$a"}++;
		}
	    }
	    foreach (suites_sort(keys %all_suites)) {
		if (("$suite/$archive" eq $_)
		    || (!$all_suites{"$suite/$archive"} && ($suite eq $_))) {
		    $$menu .= "[ <strong>$_</strong> ] ";
		} else {
		    $$menu .=
			"[ <a href=\"$ROOT/$_/$encodedpkg\">$_</a> ] ";
		}
	    }
	    $$menu .= '<br>';
	    
	    unless (@results) {
		fatal_error( "Package not available in this suite" );
	    } else {
		unless ($opts->{source}) {
		    for my $entry (@results) {
			debug( join(":", @$entry), 1 );
			my (undef, $archive, undef, $arch, $section, $subsection,
			    $priority, $version, $provided_by) = @$entry;
			
			if ($arch ne 'virtual') {
			    my %data = split /\000/, $packages_all{"$pkg $arch $version"};
			    $data{package} = $pkg;
			    $data{architecture} = $arch;
			    $data{version} = $version;
			    $page->merge_package(\%data) or debug( "Merging $pkg $arch $version FAILED", 2 );
			} else {
			    $page->add_provided_by([split /\s+/, $provided_by]);
			}
		    }
		    
		    unless ($page->is_virtual()) {
			$version = $page->{newest};
			my $source = $page->get_newest( 'source' );
			$archive = $page->get_newest( 'archive' );
			debug( "find source package: source=$source", 1);
			my $src_data = $sources_all{"$archive $suite $source"};
			$page->add_src_data( $source, $src_data )
			    if $src_data;

			my $st1 = new Benchmark;
			my $std = timediff($st1, $st0);
			debug( "Data search and merging took ".timestr($std) );

			my ($v_str, $v_str_arch, $v_str_arr) = $page->get_version_string();
			my $did = $page->get_newest( 'description' );
			$section = $page->get_newest( 'section' );
			$subsection = $page->get_newest( 'subsection' );
			my $filenames = $page->get_arch_field( 'filename' );
			my $file_md5sums = $page->get_arch_field( 'md5sum' );
			my $archives = $page->get_arch_field( 'archive' );
			my $sizes_inst = $page->get_arch_field( 'installed-size' );
			my $sizes_deb = $page->get_arch_field( 'size' );
			my @archs = sort $page->get_architectures;

			# process description
			#
			my $desc = $descriptions{$did};
			$short_desc = encode_entities( $1, "<>&\"" )
			    if $desc =~ s/^(.*)$//m;
			my $long_desc = encode_entities( $desc, "<>&\"" );
			
			$long_desc =~ s,((ftp|http|https)://[\S~-]+?/?)((\&gt\;)?[)]?[']?[:.\,]?(\s|$)),<a href=\"$1\">$1</a>$3,go; # syntax highlighting -> '];
			$long_desc =~ s/\A //o;
			$long_desc =~ s/\n /\n/sgo;
			$long_desc =~ s/\n.\n/\n<p>\n/go;
			$long_desc =~ s/(((\n|\A) [^\n]*)+)/\n<pre>$1\n<\/pre>/sgo;
# 	    $long_desc = conv_desc( $lang, $long_desc );
# 	    $short_desc = conv_desc( $lang, $short_desc );

			$$menu .= simple_menu( [ gettext( "Distribution:" ),
						 gettext( "Overview over this suite" ),
						 "$ROOT/$suite/",
						 $suite ],
					       [ gettext( "Section:" ),
						 gettext( "All packages in this section" ),
						 "$ROOT/$suite/$subsection/",
						 $subsection ],
					       );

			my $title .= sprintf( gettext( "Package: %s (%s)" ), $pkg, $v_str );
			$title .=  " ".marker( $archive ) if $archive ne 'us';
			$title .=  " ".marker( $subsection ) if $subsection eq 'non-US'
			    and $archive ne 'non-US'; # non-US/security
			$title .=  " ".marker( $section ) if $section ne 'main';
			$package_page .= title( $title );
			
			$package_page .= "<h2>".gettext( "Versions:" )." $v_str_arch</h2>\n" 
			    unless $version eq $v_str;
			if (my $provided_by = $page->{provided_by}) {
			    note( gettext( "This is also a virtual package provided by ").join( ', ', map { "<a href=\"$ROOT/$suite/$_\">$_</a>"  } @$provided_by) );
			}
			
			if ($suite eq "experimental") {
			    note( gettext( "Experimental package"),
				  gettext( "Warning: This package is from the <span class=\"pred\">experimental</span> distribution. That means it is likely unstable or buggy, and it may even cause data loss. If you ignore this warning and install it nevertheless, you do it on your own risk.")."</p><p>".
				  gettext( "Users of experimental packages are encouraged to contact the package maintainers directly in case of problems." )
				  );
			}
			if ($subsection eq "debian-installer") {
			    note( gettext( "debian-installer udeb package"),
				  gettext( "Warning: This package is intended for the use in building <a href=\"http://www.debian.org/devel/debian-installer\">debian-installer</a> images only. Do not install it on a normal Debian system." )
				  );
			}
			$package_page .= pdesc( $short_desc, $long_desc );

			#
			# display dependencies
			#
			my $dep_list;
			$dep_list = print_deps( \%packages, $opts, $pkg,
						$page->get_dep_field('depends'),
						'depends' );
			$dep_list .= print_deps( \%packages, $opts, $pkg,
						 $page->get_dep_field('recommends'),
						 'recommends' );
			$dep_list .= print_deps( \%packages, $opts, $pkg,
						 $page->get_dep_field('suggests'),
						 'suggests' );

			if ( $dep_list ) {
			    $package_page .= "<div id=\"pdeps\">\n";
			    $package_page .= sprintf( "<h2>".gettext( "Other Packages Related to %s" )."</h2>\n", $pkg );
			    if ($suite eq "experimental") {
				note( gettext( "Note that the \"<span class=\"pred\">experimental</span>\" distribution is not self-contained; missing dependencies are likely found in the \"<a href=\"/unstable/\">unstable</a>\" distribution." ) );
			    }
			    
			    $package_page .= pdeplegend( [ 'dep',  gettext( 'depends' ) ],
							 [ 'rec',  gettext( 'recommends' ) ],
							 [ 'sug',  gettext( 'suggests' ) ], );
			    
			    $package_page .= $dep_list;
			    $package_page .= "</div> <!-- end pdeps -->\n";
			}

			#
			# Download package
			#
			my $encodedpack = uri_escape( $pkg );
			$package_page .= "<div id=\"pdownload\">";
			$package_page .= sprintf( "<h2>".gettext( "Download %s\n" )."</h2>",
						  $pkg ) ;
			$package_page .= "<table border=\"1\" summary=\"".gettext("The download table links to the download of the package and a file overview. In addition it gives information about the package size and the installed size.")."\">\n";
			$package_page .= "<caption class=\"hidecss\">".gettext("Download for all available architectures")."</caption>\n";
			$package_page .= "<tr>\n";
			$package_page .= "<th>".gettext("Architecture")."</th><th>".gettext("Files")."</th><th>".gettext( "Package Size")."</th><th>".gettext("Installed Size")."</th></tr>\n";
			foreach my $a ( @archs ) {
			    $package_page .= "<tr>\n";
			    $package_page .=  "<th><a href=\"$ROOT/$suite/$encodedpkg/$a/download";
			    $package_page .=  "\">$a</a></th>\n";
			    $package_page .= "<td>";
			    if ( $suite ne "experimental" ) {
				$package_page .= sprintf( "[<a href=\"%s\">".gettext( "list of files" )."</a>]\n",
							  "$ROOT/$suite/$encodedpkg/$a/filelist", $pkg );
			    } else {
				$package_page .= gettext( "no current information" );
			    }
			    $package_page .= "</td>\n<td align=right>"; #FIXME: css
			    $package_page .=  floor(($sizes_deb->{$a}/102.4)+0.5)/10 . "&nbsp;kB";
			    $package_page .= "</td>\n<td align=right>"; #FIXME: css
			    $package_page .=  $sizes_inst->{$a} . "&nbsp;kB";
			    $package_page .= "</td>\n</tr>";
			}
			$package_page .= "</table>\n";
			$package_page .= "</div> <!-- end pdownload -->\n";
			
			#
			# more information
			#
			$package_page .= pmoreinfo( name => $pkg, data => $page,
						    opts => $opts,
						    env => \%FTP_SITES,
						    bugreports => 1, sourcedownload => 1,
						    changesandcopy => 1, maintainers => 1,
						    search => 1 );
		    } else { # unless $page->is_virtual
			$short_desc = gettext( "virtual package" );

			$$menu .= simple_menu( [ gettext( "Distribution:" ),
						 gettext( "Overview over this distribution" ),
						 "$ROOT/",
						 $suite ],
					       [ gettext( "Section:" ),
						 gettext( "All packages in this section" ),
						 "$ROOT/$suite/virtual/",
						 
						 'virtual' ], );

			$package_page .= title( sprintf( gettext( "Virtual Package: %s" ),
							 $pkg ) );

			my $policy_url = 'http://www.debian.org/doc/debian-policy/';
			note( sprintf( gettext( "This is a <em>virtual package</em>. See the <a href=\"%s\">Debian policy</a> for a <a href=\"%sch-binary.html#s-virtual_pkg\">definition of virtual packages</a>." ),
				       $policy_url, $policy_url ));

			$package_page .= sprintf( "<h2>".gettext( "Packages providing %s" )."</h2>",                              $pkg );
			my $provided_by = $page->{provided_by};
			$package_page .= pkg_list( \%packages, $opts, $provided_by, 'en');

		    } # else (unless $page->is_virtual)
		} else { # unless $opts->{source}
		    for my $entry (@results) {
			debug( join(":", @$entry), 1 );
			my (undef, $archive, undef, $section, $subsection,
			    $priority, $version) = @$entry;
			
			my $data = $sources_all{"$archive $suite $pkg"};
			$page->merge_data($pkg, $suite, $archive, $data)
			    or debug( "Merging $pkg $version FAILED", 2 );
		    }
		    $version = $page->{version};

		    my $st1 = new Benchmark;
		    my $std = timediff($st1, $st0);
		    debug( "Data search and merging took ".timestr($std) );

		    my ($v_str, $v_str_arr) = $page->get_version_string();
		    $archive = $page->get_newest( 'archive' );
		    $section = $page->get_newest( 'section' );
		    $subsection = $page->get_newest( 'subsection' );

		    $$menu .= simple_menu( [ gettext( "Distribution:" ),
					     gettext( "Overview over this suite" ),
					     "/$suite/",
					     $suite ],
					   [ gettext( "Section:" ),
					     gettext( "All packages in this section" ),
					     "/$suite/$subsection/",
					     $subsection ],
					   );
		    
		    my $title .= sprintf( gettext( "Source Package: %s (%s)" ),
					  $pkg, $v_str );
		    $title .=  " ".marker( $archive ) if $archive ne 'us';
		    $title .=  " ".marker( $subsection ) if $subsection eq 'non-US'
			and $archive ne 'non-US'; # non-US/security
		    $title .=  " ".marker( $section ) if $section ne 'main';
		    $package_page .= title( $title );
		    
		    if ($suite eq "experimental") {
			note( gettext( "Experimental package"),
			      gettext( "Warning: This package is from the <span class=\"pred\">experimental</span> distribution. That means it is likely unstable or buggy, and it may even cause data loss. If you ignore this warning and install it nevertheless, you do it on your own risk.")."</p><p>".
			      gettext( "Users of experimental packages are encouraged to contact the package maintainers directly in case of problems." )
			      );
		    }
		    if ($subsection eq "debian-installer") {
			note( gettext( "debian-installer udeb package"),
			      gettext( "Warning: This package is intended for the use in building <a href=\"http://www.debian.org/devel/debian-installer\">debian-installer</a> images only. Do not install it on a normal Debian system." )
			      );
		    }

		    my $binaries = find_binaries( $pkg, $archive, $suite, \%src2bin );
		    if ($binaries && @$binaries) {
			$package_page .= '<div class="pdesc">';
			$package_page .= gettext( "The following binary packages are built from this source package:" );
			$package_page .= pkg_list( \%packages, $opts, $binaries, 'en' );
			$package_page .= '</div> <!-- end pdesc -->';
		    }
		    
		    #
		    # display dependencies
		    #
		    my $dep_list;
		    $dep_list = print_deps( \%packages, $opts, $pkg,
					    $page->get_dep_field('build-depends'),
					    'build-depends' );
		    $dep_list .= print_deps( \%packages, $opts, $pkg,
					     $page->get_dep_field('build-depends-indep'),
					     'build-depends-indep' );

		    if ( $dep_list ) {
			$package_page .= "<div id=\"pdeps\">\n";
			$package_page .= sprintf( "<h2>".gettext( "Other Packages Related to %s" )."</h2>\n", $pkg );
			if ($suite eq "experimental") {
			    note( gettext( "Note that the \"<span class=\"pred\">experimental</span>\" distribution is not self-contained; missing dependencies are likely found in the \"<a href=\"/unstable/\">unstable</a>\" distribution." ) );
			}
			
			$package_page .= pdeplegend( [ 'adep',  gettext( 'build-depends' ) ],
						     [ 'idep',  gettext( 'build-depends-indep' ) ],
						     );
			
			$package_page .= $dep_list;
			$package_page .= "</div> <!-- end pdeps -->\n";
		    }

		    #
		    # Source package download
		    #
		    $package_page .= "<div id=\"pdownload\">\n";
		    $package_page .= sprintf( "<h2>".gettext( "Download %s" )."</h2>\n",
					      $pkg ) ;

		    my $source_files = $page->get_src( 'files' );
		    my $source_dir = $page->get_src( 'directory' );
		    
		    $package_page .= sprintf( "<table cellspacing=\"0\" cellpadding=\"2\" summary=\"Download information for the files of this source package\">\n"
					      ."<tr><th>%s</th><th>%s</th><th>%s</th>",
					      gettext("File"),
					      gettext("Size (in kB)"),
					      gettext("md5sum") );
		    foreach( @$source_files ) {
			my ($src_file_md5, $src_file_size, $src_file_name)
			    = split /\s+/, $_;
			my $src_url;
			for ($archive) {
			    /security/o &&  do {
				$src_url = $FTP_SITES{security}; last };
			    /volatile/o &&  do {
				$src_url = $FTP_SITES{volatile}; last };
			    /backports/o &&  do {
				$src_url = $FTP_SITES{backports}; last };
			    /non-us/io  &&  do {
				$src_url = $FTP_SITES{'non-US'}; last };
			    $src_url = $FTP_SITES{us};
			}
			$src_url .= "/$source_dir/$src_file_name";
			
			$package_page .= "<tr><td><a href=\"$src_url\">$src_file_name</a></td>\n"
			    ."<td class=\"dotalign\">".sprintf("%.1f", (floor(($src_file_size/102.4)+0.5)/10))."</td>\n"
			    ."<td>$src_file_md5</td></tr>";
		    }
		    $package_page .= "</table>\n";
		    $package_page .= "</div> <!-- end pdownload -->\n";

		    #
		    # more information
		    #
		    $package_page .= pmoreinfo( name => $pkg, data => $page,
						opts => $opts,
						env => \%FTP_SITES,
						bugreports => 1,
						changesandcopy => 1, maintainers => 1,
						search => 1, is_source => 1 );
		    
		} # else (unless $opts->{source})
	    } # else (unless @results)
	} # else (unless (@results || @non_results ))
    }

#    use Data::Dumper;
#    debug( "Final page object:\n".Dumper($page), 3 );

    my $title = $opts->{source} ?
	"Details of source package <em>$pkg</em> in $suite"  :
	"Details of package <em>$pkg</em> in $suite" ;
    my $title_tag = $opts->{source} ?
	"Details of source package $pkg in $suite"  :
	"Details of package $pkg in $suite" ;
    %$html_header = ( title => $title ,
		      lang => 'en',
		      desc => $short_desc,
		      keywords => "$suite, $archive, $section, $subsection, $version",
		      title_tag => "Details of package $pkg in $suite",
		      print_search_field => 'packages',
		      search_field_values => { 
			  keywords => '',
			  searchon => $opts->{source} ? 'sourcenames' : 'names',
			  arch => 'any',
			  suite => 'all',
			  section => 'all',
			  exact => 0,
			  debug => $opts->{debug},
		      },
		      );

    $$page_content = $package_page;
}

1;

