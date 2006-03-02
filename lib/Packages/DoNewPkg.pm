package Packages::DoNewPkg;

use strict;
use warnings;

use Benchmark ':hireswallclock';
use HTML::Entities;
use POSIX;
use XML::RSS;
use CGI ();
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( do_newpkg );

use Packages::I18N::Locale;
use Packages::Search qw( :all );
use Packages::CGI;
use Packages::DB;
use Packages::Config qw( $TOPDIR @SECTIONS $HOSTNAME $ROOT );

sub do_newpkg {
    my ($params, $opts, $html_header, $menu, $page_content) = @_;

    if ($params->{errors}{suite}) {
	fatal_error( _g( "suite not valid or not specified" ) );
    }
    if (@{$opts->{suite}} > 1) {
	fatal_error( sprintf( _g( "more than one suite specified for show (%s)" ), "@{$opts->{suite}}" ) );
    }

    my $sort_func = sub { $_[0][0] cmp $_[1][0] };
    $sort_func = sub { $_[0][1] <=> $_[1][1] or $_[0][0] cmp $_[1][0] }
    if $opts->{mode} eq 'byage';

    my $suite = $opts->{suite}[0];
    my $one_archive = @{$opts->{archive}} == 1 ?
	$opts->{archive}[0] : undef;
    my $one_section = @{$opts->{section}} == 1 ?
	$opts->{section}[0] : undef;

    my @full_path = ($HOSTNAME, $ROOT, $suite);
    push @full_path, $one_archive if $one_archive;
    my $full_path = join( '/', @full_path );

    my @new_pkgs;
    #FIXME: move to Packages::DB?
    open NEWPKG, '<', "$TOPDIR/files/packages/newpkg_info"
	or die "can't read newpkg_info file: $!";
    while (<NEWPKG>) {
	chomp;
	my @data = split /\s/, $_, 10;

	next unless $data[3] eq $suite;
	next if $one_archive and $data[2] ne $one_archive;
	next if $one_section and $data[5] ne $one_section;

	debug( "new pkg: @data", 1 ) if DEBUG;
	push @new_pkgs, \@data;
    }
    close NEWPKG;
    
    (my @date)= gmtime();
    my $now_time = strftime ("%B %d, %Y", @date);
    my $rss_time = strftime ("%Y-%m-%dT%H:%M+00:00", @date);

    unless ($opts->{format} eq 'rss') {
	my $title = sprintf( _g( "New Packages in \"%s\"" ), 
			     $suite );
	%$html_header = ( title => $title,
			  title_keywords => "debian, "._g('new packages').", $suite, @{$opts->{section}}",
			  meta => "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"RSS\" href=\"newpkg?format=rss\">",
			  lang => $opts->{lang},
			  print_title => 1 );
	
	$$page_content .= "<p>"
	    . sprintf(_g( "The following packages were added to suite <em>%s</em>%s in the Debian archive during the last 7 days."), $suite,
		      $one_section ? sprintf(_g(" (section %s)"),$one_section):'')."</p>"
	    . "<p>".sprintf( _g( "This information is also available as an <a href=\"%s\">RSS feed</a>." ), "newpkg?format=rss" )
	    ." <a href=\"newpkg?format=rss\"><img src=\"http://planet.debian.org/rss10.png\" alt=\"[RSS 1.0 Feed]\"></a></p>";

	if (@new_pkgs) {
	    $$page_content .= "\n<ul>\n";
	    
	    foreach my $pkg (sort { &$sort_func($a,$b) } @new_pkgs) {
		$$page_content .= sprintf ("<li><a href=\"%s\">%s</a>\n    -- %s%s",
					   $pkg->[0], $pkg->[0],
					   encode_entities($pkg->[-1], '"&<>'),
					   $pkg->[1] ?
					   sprintf(_g(" <em>(%s days old)</em>"),$pkg->[1]):
					   '');
	    }
	    $$page_content .= "\n</ul>\n" if @new_pkgs;
	}

 	my $slist = '';
	if ($one_section) {
	    foreach my $s (@SECTIONS) {
		$slist .= ", " if $slist;
		$slist .= $one_section eq $s ? $s :
		    "<a href=\"../$s/newpkg\">$s</a>";
	    }
	}

	$$page_content .= '<p class="psmallcenter"><a href="'.make_url('allpackages','').'" title="'.
	    _g( "List of all packages" ) ."\">".
	    _g( "All packages" ) ."</a><br>(<a href=\"".make_url('allpackages','',{format=>'txt.gz'})."\">".
	    _g( "compact compressed textlist" )."</a>)<br>".
	    ($slist ? sprintf(_g( "New packages in %s" ), $slist ):'').
	    "</p>\n";

    } else { # unless ($opts->{format} eq 'rss')
	my ( $rss_link, $rss_description, $rss_date );

	$rss_description = sprintf(_g( "The following packages were added to suite %s%s in the Debian archive during the last 7 days."), $suite,
				   $one_section ? sprintf(_g(" (section %s)"),$one_section):'');

	my $rss = new XML::RSS (version => '1.0');
	$rss_link = "$full_path".($one_section?"$one_section/":'')."/newpkg?format=rss";
	$rss->channel(
		      title        => _g("New Debian Packages"),
		      link         => $rss_link,
		      description  => $rss_description,
		      dc => {
			  date       => $rss_time,
			  publisher  => 'debian-www@lists.debian.org',
			  rights     => 'Copyright '.($date[5]+1900).', SPI Inc.',
			  language   => $opts->{lang},
		      },
		      syn => {
			  updatePeriod     => "daily",
			  updateFrequency  => "2",
#		      updateBase       => "1901-01-01T00:00+00:00",
		      } );

	foreach my $pkg (sort { &$sort_func($a,$b) } @new_pkgs) {
	    $rss->add_item(
			   title       => $pkg->[0],
			   link        => "$full_path/$pkg->[0]",
			   description => $pkg->[-1],
			   dc => {
			       subject  => $pkg->[6],
			   } );
	}
	my $charset = get_charset( $opts->{lang} );
	print &CGI::header( -type => 'application/rss+xml',
			    -charset => $charset );
	print $rss->as_string;
	exit;
    }
}

1;
