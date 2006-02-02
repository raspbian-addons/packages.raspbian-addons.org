#!/usr/bin/perl -wT
# $Id$
# show_package.pl -- CGI interface to show info about a package
#
# Copyright (C) 1998 James Treacy
# Copyright (C) 2000, 2001 Josip Rodin
# Copyright (C) 2001 Adam Heath
# Copyright (C) 2004 Martin Schulze
# Copyright (C) 2004-2006 Frank Lichtenheld
# Copyright (C) 2006 Jeroen van Wolffelaar
#
# use is allowed under the terms of the GNU Public License (GPL)                              
# see http://www.fsf.org/copyleft/gpl.html for a copy of the license

use strict;
use CGI qw( -oldstyle_urls );
use CGI::Carp qw( fatalsToBrowser );
use POSIX;
use URI::Escape;
use HTML::Entities;
use DB_File;
use Benchmark;

use lib "../lib";

use Deb::Versions;
use Packages::Search qw( :all );
use Packages::HTML ();
use Packages::Page ();

my $HOME = "http://www.debian.org";
my $ROOT = "";
my $SEARCHPAGE = "http://packages.debian.org/";
my @SUITES = qw( oldstable stable testing unstable experimental );
my @DISTS = @SUITES;
my @SECTIONS = qw( main contrib non-free );
my @ARCHIVES = qw( us security installer );
my @ARCHITECTURES = qw( alpha amd64 arm hppa hurd-i386 i386 ia64
			kfreebsd-i386 mips mipsel powerpc s390 sparc );
my %SUITES = map { $_ => 1 } @SUITES;
my %SECTIONS = map { $_ => 1 } @SECTIONS;
my %ARCHIVES = map { $_ => 1 } @ARCHIVES;
my %ARCHITECTURES = map { $_ => 1 } @ARCHITECTURES;


$ENV{PATH} = "/bin:/usr/bin";

# Read in all the variables set by the form
my $input;
if ($ARGV[0] eq 'php') {
	$input = new CGI(\*STDIN);
} else {
	$input = new CGI;
}

my $pet0 = new Benchmark;
# use this to disable debugging in production mode completly
my $debug_allowed = 1;
my $debug = $debug_allowed && $input->param("debug");
$debug = 0 if not defined($debug);
$Packages::Search::debug = 1 if $debug > 1;

# If you want, just print out a list of all of the variables and exit.
print $input->header if $debug;
# print $input->dump;
# exit;

my %params_def = ( package => { default => undef, match => '^([a-z0-9.+-]+)$' },
		   suite => { default => undef, match => '^(\w+)$' },
		   #format => { default => 'html', match => '^(\w+)$' }
		   );
my %params = Packages::Search::parse_params( $input, \%params_def );

my $format = $params{values}{format}{final};
#XXX: Don't use alternative output formats yet
$format = 'html';

if ($format eq 'html') {
    print $input->header;
} elsif ($format eq 'xml') {
#    print $input->header( -type=>'application/rdf+xml' );
    print $input->header( -type=>'text/plain' );
}

if ($params{errors}{package}) {
    print "Error: package not valid or not specified" if $format eq 'html';
    exit 0;
}
if ($params{errors}{suite}) {
    print "Error: package not valid or not specified" if $format eq 'html';
    exit 0;
}
my $package = $params{values}{package}{final};
my $suite = $params{values}{suite}{final};

# for output
if ($format eq 'html') {
print Packages::HTML::header( title => "Details of package <i>$package</i> in $suite" ,
			      lang => 'en',
			      title_tag => "Details of package $package in $suite",
			      print_title_above => 1
			      );
}

# read the configuration
my $topdir;
if (!open (C, "../config.sh")) {
    print "\nInternal Error: Cannot open configuration file.\n\n"
if $format eq 'html';
    exit 0;
}
while (<C>) {
    $topdir = $1 if (/^\s*topdir="?(.*)"?\s*$/);
    $ROOT = $1 if /^\s*root="?(.*)"?\s*$/;
}
close (C);

my $DBDIR = $topdir . "/files/db";
my $DL_URL = "$package/download";
my $FILELIST_URL = "$package/files";
my $DDPO_URL = "http://qa.debian.org/developer.php?email=";


my $obj1 = tie my %packages, 'DB_File', "$DBDIR/packages_small.db", O_RDONLY, 0666, $DB_BTREE
    or die "couldn't tie DB $DBDIR/packages_small.db: $!";
my $obj2 = tie my %packages_all, 'DB_File', "$DBDIR/packages_all_$suite.db", O_RDONLY, 0666, $DB_BTREE
    or die "couldn't tie DB $DBDIR/packages_all_$suite.db: $!";
my %allsuites = ();
my @results = ();


&read_entry( $package, \@results, \%allsuites );

if (keys %allsuites == 0) {
    print "No such package";
    print "{insert link to search page with substring search}";
    exit;
}

# sort is gross -- only fails for experimental though
for (sort keys %allsuites) {
    if ($suite eq $_) {
	print "<strong>$_</strong> | ";
    } else {
	print "<a href=\"../$_/".uri_escape($package)."\">$_</a> | ";
    }
}
print "<br>";
if (not exists $allsuites{$suite}) {
    print "Package not available in this suite";
    exit;
}

for my $entry (@results) {
    print join ":", @$entry;
    print "<br>\n";
    my ($foo, $arch, $section, $subsection,
	$priority, $version) = @$entry;
    print "<pre>".$packages_all{"$package $arch $version"}."</pre>";
}

&showpackage($package);

sub showpackage {
    my ( $pkg ) = @_;

    my $env;
    
    my $name = $pkg->get_name;
    
    if ( $pkg->is_virtual ) { 
	print_virt_pack( @_ ); 
	return;
    }
    
    my @all_archs = ( @{$env->{archs}}, 'all' );
    
    my $page = new Packages::Page( $name,
				   { architectures => $env->{archs} } );
    my $d = $page->set_data( $env->{db}, $pkg );
    
    my %versions = $pkg->get_arch_versions( $env->{archs} );
    my %subsuites   = $pkg->get_arch_fields( 'subdistribution', 
					     $env->{archs} );
    my %filenames   = $pkg->get_arch_fields( 'filename',
					     $env->{archs} );
    my %file_md5s   = $pkg->get_arch_fields( 'md5sum',
					     $env->{archs} );
    
    my $subsuite_kw = $d->{subsuite} || $env->{distribution};
    my $size_kw = exists $d->{sizes_deb}{i386} ? $d->{sizes_deb}{i386} : first_val($d->{sizes_deb});
    
    
    foreach my $lang (@{$env->{langs}}) {
	&Generated::Strings::string_lang($lang);
	
	my $dirname = "$env->{dest_dir}/$d->{subsection}";
	my $filename = "$dirname/$name.$lang.html";
	
	unless (( $lang eq 'en' ) 
		|| $env->{db}->is_translated( $name, $d->{version},
					      ${$versions{v2a}{$d->{version}}}[0],
					      $lang )) {
	    next;
	}
	progress() if $env->{opts}{progress};
	
	#
	# process description
	#
	my $short_desc = encode_entities( $env->{db}->get_short_desc( $d->{desc_md5},
								      $lang ), "<>&\"" );
	my $long_desc = encode_entities( $env->{db}->get_long_desc( $d->{desc_md5},
								    $lang ), "<>&\"" );
	
	$long_desc =~ s,((ftp|http|https)://[\S~-]+?/?)((\&gt\;)?[)]?[']?[:.\,]?(\s|$)),<a href=\"$1\">$1</a>$3,go; # syntax highlighting -> '];
	$long_desc =~ s/\A //o;
	$long_desc =~ s/\n /\n/sgo;
	$long_desc =~ s/\n.\n/\n<p>\n/go;
	$long_desc =~ s/(((\n|\A) [^\n]*)+)/\n<pre>$1\n<\/pre>/sgo;
	
	$long_desc = conv_desc( $lang, $long_desc );
	$short_desc = conv_desc( $lang, $short_desc );
	
	#
	# begin output
	#
	my $package_page = header( title => $name, lang => $lang,
				   desc => $short_desc,
				   keywords => "$env->{distribution}, $subsuite_kw, $d->{section}, $d->{subsection}, size:$size_kw $d->{version}" );
	$package_page .= simple_menu( [ gettext( "Distribution:" ),
					gettext( "Overview over this distribution" ),
					"../",
					$env->{distribution} ],
				      [ gettext( "Section:" ),
					gettext( "All packages in this section" ),
					"../$d->{subsection}/",
					$d->{subsection} ],
				      );
	
	my $title .= sprintf( gettext( "Package: %s (%s)" ), $name, $d->{v_str_simple} );
	$title .=  " ".marker( $d->{subsuite} ) if $d->{subsuite};
	$title .=  " ".marker( $d->{section} ) if $d->{section} ne 'main';
	$package_page .= title( $title );
	
	$package_page .= "<h2>".gettext( "Versions:" )." $d->{v_str_arch}</h2>\n" 
	    unless $d->{version} eq $d->{v_str_simple};
	
	if ($env->{distribution} eq "experimental") {
	    $package_page .= note( gettext( "Experimental package"),
				   gettext( "Warning: This package is from the <span class=\"pred\">experimental</span> distribution. That means it is likely unstable or buggy, and it may even cause data loss. If you ignore this warning and install it nevertheless, you do it on your own risk.")."</p><p>".
				   gettext( "Users of experimental packages are encouraged to contact the package maintainers directly in case of problems." )
				   );
	}
	if ($d->{section} eq "debian-installer") {
	    $package_page .= note( gettext( "debian-installer udeb package"),
				   gettext( "Warning: This package is intended for the use in building <a href=\"http://www.debian.org/devel/debian-installer\">debian-installer</a> images only. Do not install it on a normal Debian system." )
				   );
	}
	$package_page .= pdesc( $short_desc, $long_desc );
	
	#
	# display dependencies
	#
	my $dep_list = print_deps( $env, $lang, $pkg, $d->{depends},    'depends' );
	$dep_list   .= print_deps( $env, $lang, $pkg, $d->{recommends}, 'recommends' );
	$dep_list   .= print_deps( $env, $lang, $pkg, $d->{suggests},   'suggests' );
	
	if ( $dep_list ) {
	    $package_page .= "<div id=\"pdeps\">\n";
	    $package_page .= sprintf( "<h2>".gettext( "Other Packages Related to %s" )."</h2>\n", $name );
	    if ($env->{distribution} eq "experimental") {
		$package_page .= note( gettext( "Note that the \"<span class=\"pred\">experimental</span>\" distribution is not self-contained; missing dependencies are likely found in the \"<a href=\"../../unstable/\">unstable</a>\" distribution." ) );
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
	my $encodedpack = uri_escape( $name );
	$package_page .= "<div id=\"pdownload\">";
	$package_page .= sprintf( "<h2>".gettext( "Download %s\n" )."</h2>",
				  $name ) ;
	$package_page .= "<table border=\"1\" summary=\"".gettext("The download table links to the download of the package and a file overview. In addition it gives information about the package size and the installed size.")."\">\n";
	$package_page .= "<caption class=\"hidecss\">".gettext("Download for all available architectures")."</caption>\n";
	$package_page .= "<tr>\n";
	$package_page .= "<th>".gettext("Architecture")."</th><th>".gettext("Files")."</th><th>".gettext( "Package Size")."</th><th>".gettext("Installed Size")."</th></tr>\n";
	foreach my $a ( @all_archs ) {
	    if ( exists $versions{a2v}{$a} ) {
	        $package_page .= "<tr>\n";
		$package_page .=  "<th><a href=\"$DL_URL?arch=$a";
		# \&amp\;file=\" method=\"post\">\n<p>";
		$package_page .=  "&amp;file=".uri_escape($filenames{a2f}->{$a});
		$package_page .=  "&amp;md5sum=$file_md5s{a2f}->{$a}";
		$package_page .=  "&amp;arch=$a";
		# there was at least one package with two
		# different source packages on different
		# archs where one had a security update
		# and the other one not
		if ($subsuites{a2f}{$a}
		    && ($subsuites{a2f}{$a} =~ /security/o) ) {
		    $package_page .=  "&amp;type=security";
		} elsif ($subsuites{a2f}{$a}
			 && ($subsuites{a2f}{$a} =~ /volatile/o) ) {
		    $package_page .=  "&amp;type=volatile";
		} elsif ($d->{is_nonus}) {
		    $package_page .=  "&amp;type=nonus";
		} else {
		    $package_page .=  "&amp;type=main";
		}
		$package_page .=  "\">$a</a></th>\n";
		$package_page .= "<td>";
		if ( $env->{distribution} ne "experimental" ) {
		    $package_page .= sprintf( "[<a href=\"%s\">".gettext( "list of files" )."</a>]\n", "$FILELIST_URL$encodedpack&amp;version=$env->{distribution}&amp;arch=$a", $name );
		} else {
		    $package_page .= "no files";
		}
		$package_page .= "</td>\n<td>";
		my $size = $d->{sizes_deb}{$a};
		$package_page .=  "$size";
		$package_page .= "</td>\n<td>";
		my $inst_size = $d->{sizes_inst}{$a};
		$package_page .=  "$inst_size";
		$package_page .= "</td>\n</tr>";
	    }
	}
	$package_page .= "</table><p>".gettext ( "Size is measured in kBytes." )."</p>\n";
	$package_page .= "</div> <!-- end pdownload -->\n";
	
	#
	# more information
	#
	$package_page .= pmoreinfo( name => $name, env => $env, data => $d,
				    bugreports => 1, sourcedownload => 1,
				    changesandcopy => 1, maintainers => 1,
				    search => 1 );
	
	#
	# Trailer
	#
	my @tr_langs = ();
	foreach my $l (@{$env->{langs}}) {
	    next if $l eq $lang;
	    push @tr_langs, $l if ( $l eq 'en' ) 
		|| $env->{db}->is_translated( $name, $d->{version}, 
					      ${$versions{v2a}{$d->{version}}}[0],
					      $l );
	}
	$package_page .= trailer( '../..', $name, $lang, @tr_langs );
	
	#
	# create data sheet
	#
	if($lang eq 'en') {
	    my $data_sheet = header( title => "$name -- Data sheet",
				     lang => "en",
				     desc => $short_desc,
				     keywords => "$env->{distribution}, $subsuite_kw, $d->{section}, $d->{subsection}, size:$size_kw $d->{version}" );	    
	    
	    my $ds_title = $name;
	    if ( $d->{subsuite} ) {
		$ds_title .=  " ".marker( $d->{subsuite} );
	    }
	    if ( $d->{section} ne 'main' ) {
		$ds_title .=  " ".marker( $d->{section} );
	    }
	    $data_sheet .= title( $ds_title );

	    $data_sheet .= ds_begin;
	    $data_sheet .= ds_item(gettext( "Version" ), $d->{v_str_arch});
	    
	    my @uploaders = @{$d->{uploaders}};
	    my ( $maint_name, $maint_email ) = @{shift @uploaders};
	    $data_sheet .= ds_item(gettext( "Maintainer" ),
				   "<a href=\"$DDPO_URL".
				   uri_escape($maint_email).
				   "\">".encode_entities($maint_name, '&<>')."</a>" );
	    if (@uploaders) {
		my @uploaders_str;
		foreach (@uploaders) {
		    push @uploaders_str, "<a href=\"$DDPO_URL".uri_escape($_->[1])."\">".encode_entities($_->[0], '&<>')."</a>";
		}
		$data_sheet .= ds_item(gettext( "Uploaders" ),
				       join( ",\n ", @uploaders_str ));
	    }
	    $data_sheet .= ds_item(gettext( "Section" ),
				   "<a href=\"../$d->{subsection}/\">$d->{subsection}</a>");
	    $data_sheet .= ds_item(gettext( "Priority" ),
				   "<a href=\"../$d->{priority}\">$d->{priority}</a>");
	    $data_sheet .= ds_item(gettext( "Essential" ),
				   "<a href=\"../essential\">".
				   gettext("yes")."</a>")
		if $d->{essential} =~ /yes/i;
	    $data_sheet .= ds_item(gettext( "Source package" ),
				   "<a href=\"../source/$d->{src_name}\">$d->{src_name}</a>");
	    $data_sheet .= print_deps_ds( $env, $pkg, $d->{depends},    'Depends' );
	    $data_sheet .= print_deps_ds( $env, $pkg, $d->{recommends}, 'Recommends' );
	    $data_sheet .= print_deps_ds( $env, $pkg, $d->{suggests},   'Suggests' );
	    $data_sheet .= print_deps_ds( $env, $pkg, $d->{enhances},   'Enhances' );
	    $data_sheet .= print_deps_ds( $env, $pkg, $d->{conflicts},  'Conflicts' );
	    $data_sheet .= print_deps_ds( $env, $pkg, $d->{provides},   'Provides' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Depends' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Recommends' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Suggests' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Enhances' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Provides' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Conflicts' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Build-Depends' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Build-Depends-Indep' );
#	    $data_sheet .= print_reverse_rel_ds( $env, $pkg, \%versions, 'Build-Conflicts' );

#	    if ( $name eq 'libc6' ) {
#		use Data::Dumper;
#		print STDERR Dumper( $pkg );
#	    }

	    $data_sheet .= ds_end;
	    
	    $data_sheet .= trailer( '../..', $name );

	    my $ds_filename = "$dirname/ds_$name.$lang.html";
	    #
	    # write file
	    #
	    print $data_sheet;
	}
    }
}

&printfooter;

sub read_entry {
    my ($key, $results, $allsuites) = @_;
    my $result = $packages{$key};
    foreach (split /\000/, $result) {
	my @data = split ( /\s/, $_, 7 );
	print "DEBUG: Considering entry ".join( ':', @data)."<br>" if $debug > 2;
	if ($suite eq $data[0]) {
	    print "DEBUG: Using entry ".join( ':', @data)."<br>" if $debug > 2;
	    push @$results, [@data];
	}
	$allsuites->{$data[0]} = 1;
    }
}

# TODO: move to common lib:
sub printfooter {
    print <<END;
</div>

<hr class="hidecss">
<p style="text-align:right;font-size:small;font-stlye:italic"><a href="$SEARCHPAGE">Packages search page</a></p>

</div>
END

    my $pete = new Benchmark;
    my $petd = timediff($pete, $pet0);
    print "Total page evaluation took ".timestr($petd)."<br>"
	if $debug_allowed;

    print $input->end_html;
}

# vim: ts=8 sw=4
