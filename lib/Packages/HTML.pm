package Packages::HTML;

use strict;
use warnings;

use URI::Escape;
use HTML::Entities;

use Packages::CGI;
use Packages::Search qw( read_entry_simple );
use Packages::Config qw( :all );

#use Packages::Util;
#use Packages::I18N::Locale;
#use Packages::I18N::Languages;
#use Packages::I18N::LanguageNames;
#use Generated::Strings qw( gettext dgettext );

# dummy routines
sub get_charset { return "utf-8" };
sub gettext { return $_[0]; };

our @ISA = qw( Exporter );
our @EXPORT = qw( header title trailer file_changed time_stamp
		  read_md5_hash write_md5_hash simple_menu
		  ds_begin ds_item ds_end note title marker pdesc
		  pdeplegend pkg_list pmoreinfo print_deps print_src_deps );

our $CHANGELOG_URL = '/changelogs';

sub img {
    my ( $root, $url, $src, $alt, %attr ) = @_; 
    my @attr;

    foreach my $a ( keys %attr ) {
	push @attr, "$a=\"$attr{$a}\"";
    }

    return "<a href=\"$root$url\"><img src=\"$root$src\" alt=\"$alt\" @attr></a>";
}

sub simple_menu {
    my $str = "";
    foreach my $entry (@_) {
	$str .= "[&nbsp;$entry->[0] <a title=\"$entry->[1]\" href=\"$entry->[2]\">$entry->[3]</a>&nbsp;]\n";
    }
    return $str;
}

sub title {
    return "<h1>$_[0]</h1>\n";
}

sub marker {
    return "[<span class=\"pred\">$_[0]</span>]";
}

sub pdesc {
    my ( $short_desc, $long_desc ) = @_;
    my $str = "";

    $str .= "<div id=\"pdesc\">\n";
    $str .= "<h2>$short_desc</h2>\n";

    $str .= "<p>$long_desc\n";
    $str .= "</div> <!-- end pdesc -->\n";

    return $str;
}

sub pdeplegend {
    my $str = "<table border=\"1\" summary=\"legend\"><tr>\n";

    foreach my $entry (@_) {
	$str .= "<td><img src=\"$ROOT/Pics/$entry->[0].gif\" alt=\"[$entry->[0]]\" width=\"16\" height=\"16\">= $entry->[1]</td>";
    }

    $str .= "\n</tr></table>\n";
    return $str;
}

sub pkg_list {
    my ( $packages, $opts, $pkgs, $lang ) = @_;
    my $suite = $opts->{suite}[0];

    my $str = "";
    foreach my $p ( @$pkgs ) {

	my $short_desc = (read_entry_simple( $packages, $p, $opts->{h_archives}, $suite))->[-1];

	if ( $short_desc ) {
	    $str .= "<dt><a href=\"$ROOT/$suite/$p\">$p</a></dt>\n".
		    "\t<dd>$short_desc</dd>\n";
	} else {
	    $str .= "<dt>$p</dt>\n\t<dd>".gettext("Not available")."</dd>\n";
	}
    }
    if ($str) {
	$str = "<dl>$str</dl>\n";
    }

    return $str;
}

sub pmoreinfo {
    my %info = @_;
    
    my $name = $info{name} or return;
    my $env = $info{env} or return;
    my $opts = $info{opts} or return;
    my $page = $info{data} or return;
    my $is_source = $info{is_source};
    my $suite = $opts->{suite}[0];

    my $str = "<div id=\"pmoreinfo\">";
    $str .= sprintf( "<h2>".gettext( "More Information on %s" )."</h2>",
		     $name );
    
    if ($info{bugreports}) {
	my $bug_url = $is_source ? $SRC_BUG_URL : $BUG_URL; 
	$str .= "<p>\n".sprintf( gettext( "Check for <a href=\"%s\">Bug Reports</a> about %s." )."<br>\n",
			 $bug_url.$name, $name );
    }
	
    my $source = $page->get_src( 'package' );
    my $source_version = $page->get_src( 'version' );
    my $src_dir = $page->get_src('directory');
    if ($info{sourcedownload}) {
	my $files = $page->get_src( 'files' );
	my $path = (@{$opts->{archive}} >1) ?
	    $suite :
	    "$suite/$opts->{archive}[0]";
	$str .= gettext( "Source Package:" );
	$str .= " <a href=\"$ROOT/$path/source/$source\">$source</a>, ".
	    gettext( "Download" ).":\n";

	unless (defined($files) and @$files) {
	    $str .= gettext( "Not found" );
	} else {
	    foreach( @$files ) {
		my ($src_file_md5, $src_file_size, $src_file_name) = split /\s/o, $_;
		for ($page->get_newest('archive')) {
		    /security/o && do {
			$str .= "<a href=\"$env->{security}/$src_dir/$src_file_name\">["; last };
		    /volatile/o && do {
			$str .= "<a href=\"$env->{volatile}/$src_dir/$src_file_name\">["; last };
		    /backports/o && do {
			$str .= "<a href=\"$env->{backports}/$src_dir/$src_file_name\">["; last };
		    /non-us/io && do {
			$str .= "<a href=\"$env->{nonus_site}/$src_dir/$src_file_name\">["; last };
 		    $str .= "<a href=\"$env->{us}/$src_dir/$src_file_name\">[";
 		}
		if ($src_file_name =~ /dsc$/) {
		    $str .= "dsc";
		} else {
		    $str .= $src_file_name;
		}
		$str .= "]</a>\n";
	    }
	}
#	    $package_page .= sprintf( gettext( " (These sources are for version %s)\n" ), $src_version )
#		if ($src_version ne $version) && !$src_version_given_in_control;
    }

    if ($info{changesandcopy}) {
	if ( $src_dir ) {
	    (my $src_basename = $source_version) =~ s,^\d+:,,; # strip epoche
	    $src_basename = "${source}_$src_basename";
	    $src_dir =~ s,pool/updates,pool,o;
	    $src_dir =~ s,pool/non-US,pool,o;
	    $str .= "<br>".sprintf( gettext( "View the <a href=\"%s\">Debian changelog</a>" ),
				    "$CHANGELOG_URL/$src_dir/$src_basename/changelog" )."<br>\n";
	    my $copyright_url = "$CHANGELOG_URL/$src_dir/$src_basename/";
	    $copyright_url .= ( $is_source ? 'copyright' : "$name.copyright" );

	    $str .= sprintf( gettext( "View the <a href=\"%s\">copyright file</a>" ),
			     $copyright_url )."</p>";
	}
   }

    if ($info{maintainers}) {
	my $uploaders = $page->get_src( 'uploaders' );
	if ($uploaders && @$uploaders) {
	    foreach (@$uploaders) {
		$_->[0] = encode_entities( $_->[0], '&<>' );
	    }
	    my ($maint_name, $maint_mail) = @{shift @$uploaders}; 
	    unless (@$uploaders) {
		$str .= "<p>\n".sprintf( gettext( "%s is responsible for this Debian package." ).
					 "\n",
					 "<a href=\"mailto:$maint_mail\">$maint_name</a>" 
					 );
	    } else {
		my $up_str = "<a href=\"mailto:$maint_mail\">$maint_name</a>";
		my @uploaders_str;
		foreach (@$uploaders) {
		    push @uploaders_str, "<a href=\"mailto:$_->[1]\">$_->[0]</a>";
		}
		my $last_up = pop @uploaders_str;
		$up_str .= ", ".join ", ", @uploaders_str if @uploaders_str;
		$up_str .= sprintf( gettext( " and %s are responsible for this Debian package." ), $last_up );
		$str .= "<p>\n$up_str ";
	    }
	}

	$str .= sprintf( gettext( "See the <a href=\"%s\">developer information for %s</a>." )."</p>", $QA_URL.$source, $name ) if $source;
    }

    if ($info{search}) {
	my $encodedname = uri_escape( $name );
	my $search_url = $is_source ? "$ROOT/source" : $ROOT;
	$str .= "<p>".sprintf( gettext( "Search for <a href=\"%s\">other versions of %s</a>" ),
	    "$search_url/$encodedname", $name )."</p>\n";
    }

    $str .= "</div> <!-- end pmoreinfo -->\n";
    return $str;
}

sub dep_item {
    my ( $link, $name, $info, $desc ) = @_;
    my $post_link = '';
    if ($link) {
	$link = "<a href=\"$link\">";
	$post_link = '</a>';
    } else {
	$link = '';
    }
    if ($info) {
	$info = " $info";
    } else {
	$info = '';
    }
    if ($desc) {
	$desc = "</dt><dd>$desc</dd>";
    } else {
	$desc = '</dt>';
    }

    return "$link$name$post_link$info$desc";
} # end dep_item

sub print_deps {
    my ( $packages, $opts, $pkg, $relations, $type) = @_;
    my %dep_type = ('depends' => 'dep', 'recommends' => 'rec', 
		    'suggests' => 'sug', 'build-depends' => 'adep',
		    'build-depends-indep' => 'idep' );
    my $res = "<ul class=\"ul$dep_type{$type}\">\n";
    my $first = 1;
    my $suite = $opts->{suite}[0];
    my $one_archive = @{$opts->{archive}} > 1 ? '': $opts->{archive}[0];

#    use Data::Dumper;
#    debug( "print_deps called:\n".Dumper( $pkg, $relations, \$type ), 3 );

    foreach my $rel (@$relations) {
	my $is_old_pkgs = $rel->[0];
	my @res_pkgs = ();

	if ($is_old_pkgs)  {
	    $res .= "<dt>";
	} else {
	    if ($first) {
		$res .= "<li>";
		$first = 0;
	    } else {
		$res .= "</dl></li>\n<li>";
	    }
	    $res .= "<dl><dt><img class=\"hidecss\" src=\"$ROOT/Pics/$dep_type{$type}.gif\" alt=\"[$dep_type{$type}]\"> ";
	}

	foreach my $rel_alt ( @$rel ) {
	    next unless ref($rel_alt);
	    my ( $p_name, $pkg_version, $arch_neg,
		 $arch_str, $subsection, $available ) = @$rel_alt;

	    if ($arch_str ||= '') {
		if ($arch_neg) {
		    $arch_str = " [".gettext("not")." $arch_str]";
		} else {
		    $arch_str = " [$arch_str]";
		}
	    }
	    $pkg_version = "($pkg_version)" if $pkg_version ||= '';
	    
	    my @results;
	    my %entries;
	    my $entry = $entries{$p_name} ||
		read_entry_simple( $packages, $p_name, $opts->{h_archives}, $suite);
	    my $short_desc = $entry->[-1];
	    my $arch = $entry->[2];
	    my $archive = $entry->[0];
	    if ( $short_desc ) {
		my $path = $one_archive eq $archive ? "$suite/$archive" :
		    $suite;
		if ( $is_old_pkgs ) {
		    push @res_pkgs, dep_item( "$ROOT/$path/$p_name",
					      $p_name, "$pkg_version$arch_str" );
		} elsif ($arch eq 'virtual') {
		    $short_desc = "virtual package";
		    push @res_pkgs, dep_item( "$ROOT/$path/$p_name",
					      $p_name, "$pkg_version$arch_str", $short_desc );
		} else {
		    $entries{$p_name} ||= $entry;
		    $short_desc = encode_entities( $short_desc, "<>&\"" );
		    push @res_pkgs, dep_item( "$ROOT/$path/$p_name",
					      $p_name, "$pkg_version$arch_str", $short_desc );
		}
	    } elsif ( $is_old_pkgs ) {
		push @res_pkgs, dep_item( undef, $p_name, "$pkg_version$arch_str" );
	    } else {
		my $short_desc = gettext( "Package not available" );
		push @res_pkgs, dep_item( undef, $p_name, "$pkg_version$arch_str", $short_desc );
	    }
	    
	}
	
	$res .= "\n".join( "<dt>".gettext( "or" )." ", @res_pkgs )."\n";
    }
    if (@$relations) {
	$res .= "</dl></li>\n";
	$res .= "</ul>\n";
    } else {
	$res = "";
    }
    return $res;
} # end print_deps

my $ds_begin = '<dl>';
my $ds_item_desc  = '<dt>';
my $ds_item = ':</dt><dd>';
my $ds_item_end = '</dd>';
my $ds_end = '</dl>';
#	    my $ds_begin = '<table><tbody>';
#	    my $ds_item_desc  = '<tr><td>';
#	    my $ds_item = '</td><td>';
#	    my $ds_item_end = '</td></tr>';
#	    my $ds_end = '</tbody></table>';

sub ds_begin {
    return $ds_begin;
}
sub ds_item {
    return "$ds_item_desc$_[0]$ds_item$_[1]$ds_item_end\n";
}
sub ds_end {
    return $ds_end;
}

sub header {
    my (%params) = @_;

    my $DESC_LINE;
    if (defined $params{desc}) {
	$DESC_LINE = "<meta name=\"Description\" content=\"$params{desc}\">";
    }
    else {
	$DESC_LINE = '';
    }

    my $title_keywords = $params{title_keywords} || $params{title} || '';
    my $title_tag = $params{title_tag} || $params{title} || '';
    my $title_in_header = $params{page_title} || $params{title} || '';
    my $page_title = $params{page_title} || $params{title} || '';
    my $meta = $params{meta} || '';

    my $search_in_header = '';
    $params{print_search_field} ||= "";
    if ($params{print_search_field} eq 'packages') {
	my %values = %{$params{search_field_values}};
	my %checked_searchon = ( names => "",
				 all => "",
				 sourcenames => "",
				 contents => "");
	$checked_searchon{$params{searchon}} = "checked=\"checked\"";
	$checked_searchon{names} = "checked=\"checked\""
		if $params{searchon} eq 'default';
	$search_in_header = <<MENU;
<form method="GET" action="$SEARCH_CGI">
<div id="hpacketsearch">
<input type="hidden" name="debug" value="$values{debug}">
<input type="hidden" name="suite" value="$values{suite}">
<input type="hidden" name="exact" value="$values{exact}">
<input type="hidden" name="arch" value="$values{arch}">
<input type="hidden" name="section" value="$values{section}">
<input type="text" size="30" name="keywords" value="$values{keywords}" id="kw">
<input type="submit" value="Search">
<span style="font-size: 60%"><a href="$SEARCH_PAGE#search_packages">Full options</a></span>
<br>
<div style="font-size: 80%">Search on:
<input type="radio" name="searchon" value="names" id="onlynames" $checked_searchon{names}>
<label for="onlynames">Package names</label>&nbsp;&nbsp;
<input type="radio" name="searchon" value="all" id="descs" $checked_searchon{all}>
<label for="descs">Descriptions</label>
<br>
<input type="radio" name="searchon" value="sourcenames" id="src" $checked_searchon{sourcenames}>
<label for="src">Source package names</label>
<input type="radio" name="searchon" value="contents" id="conts" $checked_searchon{contents}>
<label for="conts">Package contents</label>
</div>
</div> <!-- end hpacketsearch -->
</form>
MENU
;
    } elsif ($params{print_search_field} eq 'contents') {
	my %values = %{$params{search_field_values}};
	my %checked_searchmode = ( searchfiles => "",
				   searchfilesanddirs => "",
				   searchword => "",
				   filelist => "", );
	$checked_searchmode{$values{searchmode}} = "checked=\"checked\"";
	$search_in_header = <<MENU;
<form method="GET" action="$CONTENTS_SEARCH_CGI">
<div id="hpacketsearch">
<input type="hidden" name="debug" value="$values{debug}" />
<input type="hidden" name="version" value="$values{version}" />
<input type="hidden" name="arch" value="$values{arch}" />
<input type="hidden" name="case" value="$values{case}" />
<input type="text" size="30" name="word" id="keyword" value="$values{keyword}">&nbsp;
<input type="submit" value="Search">
<span style="font-size: 60%"><a href="$SEARCH_PAGE#search_contents">Full options</a></span>
<br>
<div style="font-size: 80%">Display:
<input type=radio name="searchmode" value="searchfiles" id="searchfiles" $checked_searchmode{searchfiles}>
<label for="searchfiles">files</label>
<input type=radio name="searchmode" value="searchfilesanddirs" id="searchfilesanddirs" $checked_searchmode{searchfilesanddirs}>
<label for="searchfilesanddirs">files &amp; directories</label>
<br>
<input type=radio name="searchmode" value="searchword" id="searchword" $checked_searchmode{searchword}>
<label for="searchword">subword matching</label>
<input type=radio name="searchmode" value="filelist" id="filelist" $checked_searchmode{filelist}>
<label for="filelist">content list</label>
</div>
</div> <!-- end hpacketsearch -->
</form>
MENU
;
    }

    my $keywords = $params{keywords} || '';
    my $KEYWORDS_LINE = "<meta name=\"Keywords\" content=\"debian, $keywords $title_keywords\">";
    
    my $LANG = $params{lang};
    my $charset = get_charset($LANG);
    my $txt = <<HEAD;
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html lang="$LANG">
<head>
<title>Debian -- $title_tag</title>
<link rev="made" href="mailto:$WEBMASTER_MAIL">
<meta http-equiv="Content-Type" content="text/html; charset=$charset">
<meta name="Author" content="Debian Webmaster, $WEBMASTER_MAIL">
$KEYWORDS_LINE
$DESC_LINE
$meta
<link href="$ROOT/debian.css" rel="stylesheet" type="text/css" media="all">
</head>
<body>
<div id="header">
   <div id="upperheader">
   <div id="logo">
  <a href="$HOME/"><img src="$HOME/logos/openlogo-nd-50.png" alt="" /></a>
HEAD
;

    $txt .= img( "$HOME/", "", "Pics/debian.png", gettext( "Debian Project" ),
		 width => 179, height => 61 );
    $txt .= <<HEADEND;

</div> <!-- end logo -->
HEADEND
;

    $txt .= <<NAVBEGIN;
$search_in_header
</div> <!-- end upperheader -->

NAVBEGIN
;
    $txt .= "<p class=\"hidecss\"><a href=\"\#inner\">" . gettext("Skip Site Navigation")."</a></p>\n";
    $txt .= "<div id=\"navbar\">\n<ul>".
	"<li><a href=\"$HOME/intro/about\">".gettext( "About&nbsp;Debian" )."</a></li>\n".
	"<li><a href=\"$HOME/News/\">".gettext( "News" )."</a></li>\n".
	"<li><a href=\"$HOME/distrib/\">".gettext( "Getting&nbsp;Debian" )."</a></li>\n".
	"<li><a href=\"$HOME/support\">".gettext( "Support" )."</a></li>\n".
	"<li><a href=\"$HOME/devel/\">".gettext( "Development" )."</a></li>\n".
	"<li><a href=\"$HOME/sitemap\">".gettext( "Site map" )."</a></li>\n".
	"<li><a href=\"http://search.debian.org/\">".gettext( "Search" )."</a></li>\n";
    $txt .= "</ul>\n";
    $txt .= <<ENDNAV;
</div> <!-- end navbar -->
</div> <!-- end header -->
ENDNAV
;
    $txt .= <<BEGINCONTENT;
<div id="outer">
<div id="inner">

BEGINCONTENT
;
    if ($params{print_title}) {
	$txt .= "<h1>$page_title</h1>\n";
    }

    return $txt;
}

sub trailer {
    my ($ROOT, $NAME, $LANG, @USED_LANGS) = @_;
    my $txt = "</div> <!-- end inner -->\n<div id=\"footer\">\n";
    my $langs = languages( $NAME, $LANG, @USED_LANGS );
    my $bl_class = $langs ? ' class="bordertop"' : "";
    $txt .=
	$langs.
	"\n<hr class=\"hidecss\">\n" .
	"<p$bl_class>".
	sprintf( gettext( "Back to: <a href=\"%s/\">Debian Project homepage</a> || <a href=\"%s/\">Packages search page</a>" ), $HOME, $ROOT ).
	"</p>\n<hr class=\"hidecss\">\n".
	"<div id=\"fineprint\" class=\"bordertop\"><p>".
	sprintf( gettext( "To report a problem with the web site, e-mail <a href=\"mailto:%s\">%s</a>. For other contact information, see the Debian <a href=\"%s/contact\">contact page</a>." ), $CONTACT_MAIL, $CONTACT_MAIL, $HOME).
	"</p>\n".
	"<p>". gettext( "Last Modified: " ). "LAST_MODIFIED_DATE".
	"<br>\n".
	sprintf( gettext( "Copyright &copy; 1997-2005 <a href=\"http://www.spi-inc.org\">SPI</a>; See <a href=\"%s/license\">license terms</a>." ), "$HOME/" )."<br>\n".
	gettext( "Debian is a registered trademark of Software in the Public Interest, Inc." ).
	"</div> <!-- end fineprint -->\n".
	"</div> <!-- end footer -->\n".
	"</div> <!-- end outer -->\n".
	"</body>\n</html>\n";

    return $txt;
}

sub languages {
    my ( $name, $lang, @used_langs ) = @_;
    
    my $str = "";
    
    if (@used_langs) {
	$str .= "<hr class=\"hidecss\">\n";
	$str .= "<!--UdmComment-->\n<p>\n";
	$str .= gettext( "This page is also available in the following languages:\n" );
	$str .= "</p><p class=\"navpara\">\n";
	
	my @printed_langs = ();
	foreach (@used_langs) {
	    next if $_ eq $lang; # Never print the current language
	    unless (get_selfname($_)) { warn "missing language $_"; next } #DEBUG
	    push @printed_langs, $_;
	}
	return "" unless scalar @printed_langs;
	# Sort on uppercase to work with languages which use lowercase initial
	# letters.
	foreach my $cur_lang (sort langcmp @printed_langs) {
	    my $tooltip = dgettext( "langs", get_language_name($cur_lang) );
	    $str .= "<a href=\"$name.$cur_lang.html\" title=\"$tooltip\" hreflang=\"$cur_lang\" lang=\"$cur_lang\" rel=\"alternate\">".get_selfname($cur_lang);
	    $str .= " (".get_transliteration($cur_lang).")" if defined get_transliteration($cur_lang);
	    $str .= "</a>\n";
	}
	$str .= "\n</p><p>\n";
	$str .= sprintf( gettext( "How to set <a href=\"%s\">the default document language</a></p>" ), $CN_HELP_URL );
	$str .= "\n<!--/UdmComment-->\n";
    }
    
    return $str;
}

1;
