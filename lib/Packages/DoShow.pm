package Packages::DoShow;

use strict;
use warnings;

use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark ':hireswallclock';
use Exporter;

use Deb::Versions;
use Packages::Config qw( $DBDIR @SUITES @ARCHIVES @SECTIONS
			 @ARCHITECTURES %FTP_SITES );
use Packages::I18N::Locale;
use Packages::CGI qw( :DEFAULT make_url make_search_url note );
use Packages::DB;
use Packages::Search qw( :all );
use Packages::Page ();
use Packages::SrcPage ();

our @ISA = qw( Exporter );
our @EXPORT = qw( do_show );

sub do_show {
    my ($params, $opts, $html_header, $page_contents) = @_;

    if ($params->{errors}{package}) {
	fatal_error( _g( "package not valid or not specified" ) );
    }
    if ($params->{errors}{suite}) {
	fatal_error( _g( "suite not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( sprintf( _g( "more than one suite specified for show (%s)" ), "@{$opts->{suite}}" ) );
    }

    my %contents;
    $contents{make_url} = sub { return &Packages::CGI::make_url(@_) };

    my $pkg = $opts->{package};
    $contents{pkg} = $pkg;
    my $suite = $opts->{suite}[0];
    $contents{suite} = $suite;
    my $archive = $opts->{archive}[0] ||'';
    
    our (%packages_all, %sources_all);
    my (@results, @non_results);
    my $page = $opts->{source} ?
	new Packages::SrcPage( $pkg ) :
	new Packages::Page( $pkg );
    my ($short_desc, $version, $section, $subsection) = ("")x5;
    
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
	    fatal_error( _g( "No such package." )."<br>".
			 sprintf( _g( '<a href="%s">Search for the package</a>' ), make_search_url('','keywords='.uri_escape($pkg)) ) );
	} else {
	    my %all_suites;
	    foreach (@results, @non_results) {
		my $a = $_->[1];
		my $s = $_->[2];
		$all_suites{$s}++;
	    }
	    $contents{suites} = [ suites_sort(keys %all_suites) ];

	    unless (@results) {
		fatal_error( _g( "Package not available in this suite." ) );
	    } else {
		$contents{page} = $page;
		unless ($opts->{source}) {

		    for my $entry (@results) {
			debug( join(":", @$entry), 1 ) if DEBUG;
			my (undef, $archive, undef, $arch, $section, $subsection,
			    $priority, $version, $provided_by) = @$entry;
			
			if ($arch ne 'virtual') {
			    my %data = split /\000/, $packages_all{"$pkg $arch $version"};
			    $data{package} = $pkg;
			    $data{architecture} = $arch;
			    $data{version} = $version;
			    $page->merge_package(\%data)
				or debug( "Merging $pkg $arch $version FAILED", 2 ) if DEBUG;
			} else {
			    $page->add_provided_by([split /\s+/, $provided_by]);
			}
		    }

		    unless ($page->is_virtual()) {
			$version = $page->{newest};
			$contents{version} = $version;
			my $source = $page->get_newest( 'source' );
			$archive = $page->get_newest( 'archive' );
			$contents{archive} = $archive;

			debug( "find source package: source=$source", 1) if DEBUG;
			my $src_data = $sources_all{"$archive $suite $source"};
			$page->add_src_data( $source, $src_data )
			    if $src_data;

			my $st1 = new Benchmark;
			my $std = timediff($st1, $st0);
			debug( "Data search and merging took ".timestr($std) ) if DEBUG;

			my $did = $page->get_newest( 'description' );
			my @complete_tags = split(/, /, $page->get_newest( 'tag' ));
			my @tags;
			foreach (@complete_tags) {
			    my ($facet, $tag) = split( /::/, $_, 2);
			    # handle tags like devel::{lang:c,lang:c++}
			    if ($tag =~ s/^\{(.+)\}$/$1/) {
				foreach (split( /,/, $tag )) {
				    next if $tag =~ /^special:/;
				    push @tags, [ $facet, $_ ];
				}
			    } else {
				next if $tag =~ /^special:/;
				push @tags, [ $facet, $tag ];
			    }
			}

			$contents{tags} = \@tags;
			$contents{debtags_voc} = \%debtags;

			$section = $page->get_newest( 'section' );
			$contents{section} = $section;
			$subsection = $page->get_newest( 'subsection' );
			$contents{subsection} = $subsection;

			my $archives = $page->get_arch_field( 'archive' );
			my $versions = $page->get_arch_field( 'version' );
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

			$contents{desc} = { short => $short_desc,
					    long => $long_desc, };

			my $v_str = $version;
			my $multiple_versions = grep { $_ ne $version } values %$versions;
			$v_str .= _g(" and others") if $multiple_versions;
			$contents{versions} = { short => $v_str,
						multiple => $multiple_versions };

			my $provided_by = $page->{provided_by};
			$contents{providers} = [];
			pkg_list( \%packages, $opts, $provided_by, 'en', $contents{providers} ) if $provided_by;

			#
			# display dependencies
			#
			build_deps( \%packages, $opts, $pkg,
				    $page->get_dep_field('pre-depends'),
				    'depends', \%contents );
			build_deps( \%packages, $opts, $pkg,
				    $page->get_dep_field('depends'),
				    'depends', \%contents );
			build_deps( \%packages, $opts, $pkg,
				    $page->get_dep_field('recommends'),
				    'recommends', \%contents );
			build_deps( \%packages, $opts, $pkg,
				    $page->get_dep_field('suggests'),
				    'suggests', \%contents );

			#
			# Download package
			#
			my @downloads;
			foreach my $a ( @archs ) {
			    my %d = ( arch => $a,
				      pkgsize => sprintf( '%.1f', floor(($sizes_deb->{$a}/102.4)+0.5)/10 ),
				      instsize => $sizes_inst->{$a}, );

			    $d{version} = $versions->{$a} if $multiple_versions;
			    $d{archive} = $archives->{$a};
			    if ( ($suite ne "experimental")
				 && ($subsection ne 'debian-installer')) {
				$d{contents_avail} = 1;
			    }
			    push @downloads, \%d;
			}
			$contents{downloads} = \@downloads;

			#
			# more information
			#
			moreinfo( name => $pkg, data => $page, vars => \%contents,
				  opts => $opts,
				  env => \%FTP_SITES,
				  bugreports => 1, sourcedownload => 1,
				  changesandcopy => 1, maintainers => 1,
				  search => 1 );
		    } else { # unless $page->is_virtual
			$contents{is_virtual} = 1;
			$contents{desc}{short} = _g( "virtual package" );
			$contents{subsection} = 'virtual';

			my $provided_by = $page->{provided_by};
			$contents{providers} = [];
			pkg_list( \%packages, $opts, $provided_by, 'en', $contents{providers} );

		    } # else (unless $page->is_virtual)
		} else { # unless $opts->{source}
		    $contents{is_source} = 1;

		    for my $entry (@results) {
			debug( join(":", @$entry), 1 ) if DEBUG;
			my (undef, $archive, undef, $section, $subsection,
			    $priority, $version) = @$entry;

			my $data = $sources_all{"$archive $suite $pkg"};
			$page->merge_data($pkg, $suite, $archive, $data)
			    or debug( "Merging $pkg $version FAILED", 2 ) if DEBUG;
		    }
		    $version = $page->{version};
		    $contents{version} = $version;

		    my $st1 = new Benchmark;
		    my $std = timediff($st1, $st0);
		    debug( "Data search and merging took ".timestr($std) ) if DEBUG;

		    $archive = $page->get_newest( 'archive' );
		    $contents{archive} = $archive;
		    $section = $page->get_newest( 'section' );
		    $contents{section} = $section;
		    $subsection = $page->get_newest( 'subsection' );
		    $contents{subsection} = $subsection;

		    my $binaries = find_binaries( $pkg, $archive, $suite, \%src2bin );
		    if ($binaries && @$binaries) {
			$contents{binaries} = [];
			pkg_list( \%packages, $opts, $binaries, 'en', $contents{binaries} );
		    }

		    #
		    # display dependencies
		    #
		    build_deps( \%packages, $opts, $pkg,
				$page->get_dep_field('build-depends'),
				'build-depends', \%contents );
		    build_deps( \%packages, $opts, $pkg,
				$page->get_dep_field('build-depends-indep'),
				'build-depends-indep', \%contents );

		    #
		    # Source package download
		    #
		    my $source_files = $page->get_src( 'files' );
		    my $source_dir = $page->get_src( 'directory' );

		    $contents{srcfiles} = [];
		    foreach( @$source_files ) {
			my ($src_file_md5, $src_file_size, $src_file_name)
			    = split /\s+/, $_;
			(my $server = lc $archive) =~ s/-//go; # non-US hack
			$server = $FTP_SITES{$server}
			    || $FTP_SITES{us};
			my $path = "/$source_dir/$src_file_name";

			push @{$contents{srcfiles}}, { server => $server, path => $path, filename => $src_file_name,
						       size => sprintf("%.1f", (floor(($src_file_size/102.4)+0.5)/10)),
						       md5sum => $src_file_md5 };
		    }

		    #
		    # more information
		    #
		    moreinfo( name => $pkg, data => $page, vars => \%contents,
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
#    debug( "Final page object:\n".Dumper(\%contents), 3 ) if DEBUG;

    %$page_contents = %contents;
}

sub moreinfo {
    my %info = @_;
    
    my $name = $info{name} or return;
    my $env = $info{env} or return;
    my $opts = $info{opts} or return;
    my $page = $info{data} or return;
    my $contents = $info{vars} or return;
    my $is_source = $info{is_source};
    my $suite = $opts->{suite}[0];

    my $source = $page->get_src( 'package' );
    my $source_version = $page->get_src( 'version' );
    my $src_dir = $page->get_src('directory');
    if ($info{sourcedownload}) {
	$contents->{src}{url} = make_url($source,'',{source=>'source'});
	$contents->{src}{pkg} = $source;

	my @downloads;
	my $files = $page->get_src( 'files' );
	if (defined($files) and @$files) {
	    foreach( @$files ) {
		my ($src_file_md5, $src_file_size, $src_file_name) = split /\s/o, $_;
		my ($name, $server, $path);
		# non-US hack
		($server = lc $page->get_newest('archive')) =~ s/-//go;
		$server = $env->{$server}||$env->{us};
		$path = "/$src_dir/$src_file_name";
		if ($src_file_name =~ /dsc$/) {
		    $name = 'dsc'
		} else {
		    $name = $src_file_name;
		}
		push @downloads, { name => $name, server => $server, path => $path };
	    }
	}
	$contents->{src}{downloads} = \@downloads;
    }

    if ($info{changesandcopy}) {
	if ( $src_dir ) {
	    (my $src_basename = $source_version) =~ s,^\d+:,,; # strip epoche
	    $src_basename = "${source}_$src_basename";
	    $src_dir =~ s,pool/updates,pool,o;
	    $src_dir =~ s,pool/non-US,pool,o;

	    $contents->{files}{changelog}{path} = "$src_dir/$src_basename/changelog";
	    $contents->{files}{copyright}{path} = "$src_dir/$src_basename/".( $is_source ? 'copyright' : "$name.copyright" );
	}
   }

    if ($info{maintainers}) {
	my $uploaders = $page->get_src( 'uploaders' );
	if ($uploaders && @$uploaders) {
	    my @maintainers = map { { name => $_->[0], mail => $_->[1] } } @$uploaders;
	    $contents->{maintainers} = \@maintainers;
	}
    }

}

sub providers {
    my ($suite, $entry, $also) = @_;
    my %tmp = map { $_ => 1 } split /\s/, $entry;
    my @provided_by = keys %tmp; # weed out duplicates
    my %out = ( also => $also,
		pkgs => \@provided_by );
    return \%out;
}

sub build_deps {
    my ( $packages, $opts, $pkg, $relations, $type, $contents) = @_;
    my %dep_type = ('depends' => 'dep', 'recommends' => 'rec', 
		    'suggests' => 'sug', 'build-depends' => 'adep',
		    'build-depends-indep' => 'idep' );
    my $suite = $opts->{suite}[0];

    my %out = ( id => $dep_type{$type}, terms => [] );

#    use Data::Dumper;
#    debug( "print_deps called:\n".Dumper( $pkg, $relations, \$type ), 3 ) if DEBUG;

    foreach my $rel (@$relations) {
	my %rel_out;
	$rel_out{is_old_pkgs} = $rel->[0];
	$rel_out{alternatives} = [];

	foreach my $rel_alt ( @$rel ) {
	    next unless ref($rel_alt);
	    my ( $p_name, $pkg_version, $arch_neg,
		 $arch_str, $subsection, $available ) = @$rel_alt;

	    if ($arch_str ||= '') {
		if ($arch_neg) {
		    $arch_str = _g("not")." $arch_str";
		} else {
		    $arch_str = $arch_str;
		}
	    }

	    my %rel_alt_out = ( name => $p_name,
				version => $pkg_version,
				arch_str => $arch_str,
				arch_neg => $arch_neg );
			     
	    my @results;
	    my %entries;
	    my $entry = $entries{$p_name} ||
		read_entry_simple( $packages, $p_name, $opts->{h_archives}, $suite);
	    my $short_desc = $entry->[-1];
	    my $arch = $entry->[3];
	    my $archive = $entry->[1];
	    my $p_suite = $entry->[2];
	    if ( $short_desc ) {
		$rel_alt_out{desc} = $short_desc;
		$rel_alt_out{suite} = $p_suite;
		if ( $rel_out{is_old_pkgs} ) {
		} elsif (defined $entry->[1]) {
		    $entries{$p_name} ||= $entry;
		    $rel_alt_out{providers} = providers( $p_suite,
							$entry->[0],
							1 ) if defined $entry->[0];
		} elsif (defined $entry->[0]) {
                    $rel_alt_out{desc} = undef;
		    $rel_alt_out{providers} = providers( $p_suite,
							$entry->[0] );
		    #FIXME: we don't handle virtual packages from
		    # the fallback suite correctly here
		    $rel_alt_out{suite} = $suite;
		}
	    } elsif ( $rel_out{is_old_pkgs} ) {
	    } else {
		$rel_alt_out{desc} = _g( "Package not available" );
		$rel_alt_out{suite} = '';
	    }
	    push @{$rel_out{alternatives}}, \%rel_alt_out;
	}

	push @{$out{terms}}, \%rel_out;
    }

    $contents->{relations} ||= [];
    push @{$contents->{relations}}, \%out if @{$out{terms}};
} # end print_deps

sub pkg_list {
    my ( $packages, $opts, $pkgs, $lang, $list ) = @_;
    my $suite = $opts->{suite}[0];

    foreach my $p ( sort @$pkgs ) {

	# we don't deal with virtual packages here because for the
	# current uses of this function this isn't needed
	my $short_desc = (read_entry_simple( $packages, $p, $opts->{h_archives}, $suite))->[-1];

	if ( $short_desc ) {
	    push @$list, { name => $p, desc => $short_desc, available => 1 };
	} else {
	    push @$list, { name => $p, desc => _g("Not available") };
	}
    }
}


1;

