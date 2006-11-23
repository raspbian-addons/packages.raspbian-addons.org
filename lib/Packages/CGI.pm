package Packages::CGI;

use strict;
use warnings;

use Exporter;
use Packages::Config;

our @ISA = qw( Exporter );
our @EXPORT = qw( DEBUG debug fatal_error );
our @EXPORT_OK = qw( error hint msg note get_all_messages
		     make_url make_search_url );


# define this to 0 in production mode
use constant DEBUG => 1;
our $debug = 0;

our (@fatal_errors, @errors, @debug, @msgs, @hints, @notes);

sub reset {
    @fatal_errors = @errors = @debug = @msgs = @hints = @notes = ();
}

sub fatal_error {
    push @fatal_errors, $_[0];
}
sub error {
    push @errors, $_[0];
}
sub hint {
    push @hints, $_[0];
}
sub debug {
    my $lvl = $_[1] || 0;
    push(@debug, $_[0]) if $debug > $lvl;
}
sub msg {
    push @msgs, $_[0];
}
sub note {
    push @notes, [ @_ ];
}
sub get_errors { (@fatal_errors, @errors) }
sub get_debug {
    return unless $debug && @debug;
    return @debug;
}
sub get_msgs { @msgs };
sub get_hints { @hints };
sub get_notes { @notes };
sub get_all_messages {
    return {
	errors => [ @fatal_errors, @errors ],
	debugs => $debug ? \@debug : [],
	msgs => \@msgs,
	hints => \@hints,
	notes => \@notes,
    };
}

our $USE_PAGED_MODE = 1;
use constant DEFAULT_PAGE => 1;
use constant DEFAULT_RES_PER_PAGE => 50;
our %page_params = ( page => { default => DEFAULT_PAGE,
                               match => '(\d+)' },
                     number => { default => DEFAULT_RES_PER_PAGE,
                                 match => '(\d+)' } );

sub parse_params {
    my ( $cgi, $params_def, $opts ) = @_;

    my %params_ret = ( values => {}, errors => {} );
    my %params;
    if ($USE_PAGED_MODE) {
        debug( "Use PAGED_MODE", 2 ) if DEBUG;
        %params = %$params_def;
        foreach (keys %page_params) {
            delete $params{$_};
        }
        %params = ( %params, %page_params );
    } else {
        %params = %$params_def;
    }

    foreach my $param ( keys %params ) {
	
	debug( "Param <strong>$param</strong>", 2 ) if DEBUG;

	my $p_value_orig = $cgi->param($param);

	if (!defined($p_value_orig)
	    && defined $params_def->{$param}{alias}
	    && defined $cgi->param($params_def->{$param}{alias})) {
	    $p_value_orig = $cgi->param($params_def->{$param}{alias});
	    debug( "Used alias <strong>$params_def->{$param}{alias}</strong>",
		   2 );
	}

	my @p_value = ($p_value_orig);

	debug( "Value (Orig) ".($p_value_orig||""), 2 ) if DEBUG;

	if ($params_def->{$param}{array} && defined $p_value_orig) {
	    @p_value = split /$params_def->{$param}{array}/, $p_value_orig;
	    debug( "Value (Array Split) ". join('##',@p_value), 2 ) if DEBUG;
	}

	if ($params_def->{$param}{match} && defined $p_value_orig) {
	    @p_value = map
	    { $_ =~ m/$params_def->{$param}{match}/; $_ = $1 }
	    @p_value;
	}
	@p_value = grep { defined $_ } @p_value;

	debug( "Value (Match) ". join('##',@p_value), 2 ) if DEBUG;

	unless (@p_value) {
	    if (defined $params{$param}{default}) {
		@p_value = ($params{$param}{default});
	    } else {
		@p_value = undef;
		$params_ret{errors}{$param} = "undef";
		next;
	    }
	}

	debug( "Value (Default) ". join('##',@p_value), 2 ) if DEBUG;
	my @p_value_no_replace = @p_value;

	if ($params{$param}{replace} && @p_value) {
	    foreach my $pattern (keys %{$params{$param}{replace}}) {
		my @p_value_tmp = @p_value;
		@p_value = ();
		foreach (@p_value_tmp) {
		    if ($_ eq $pattern) {
			my $replacement = $params{$param}{replace}{$_};
			if (ref $replacement) {
			    push @p_value, @$replacement;
			} else {
			    push @p_value, $replacement;
			}
		    } else {
			push @p_value, $_;
		    }
		}
	    }
	}
	
	debug( "Value (Final) ". join('##',@p_value), 2 ) if DEBUG;

	if ($params_def->{$param}{array}) {
	    $params_ret{values}{$param} = {
		orig => $p_value_orig,
		no_replace => \@p_value_no_replace,
		final => \@p_value,
	    };
	    @{$params_def->{$param}{var}} = @p_value
		if $params_def->{$param}{var};
	} else {
	    $params_ret{values}{$param} = {
		orig => $p_value_orig,
		no_replace => $p_value_no_replace[0],
		final => $p_value[0],
	    };
	    ${$params_def->{$param}{var}} = $p_value[0]
		if $params_def->{$param}{var};
	}
	$opts->{$param} = $params_ret{values}{$param}{final} if $opts;
    }

    if ($USE_PAGED_MODE) {
        $cgi->delete( "page" );
        $cgi->delete( "number" );
    }

    return %params_ret;
}

sub start { 
    my $params = shift;

    my $page = $params->{values}{page}{final}
    || DEFAULT_PAGE;
    my $res_per_page = $params->{values}{number}{final}
    || DEFAULT_RES_PER_PAGE;

    return 1 if $res_per_page =~ /^all$/i;
    return $res_per_page * ($page - 1) + 1;
}

sub end {
    my $params = shift;

    use Data::Dumper;
    debug( "end: ".Dumper($params) ) if DEBUG;
    my $page = $params->{page}
    || DEFAULT_PAGE;
    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;

    return $page * $res_per_page;
}

sub indexline {
    my ($cgi, $params, $num_res) = @_;

    my $index_line = "";
    my $page = $params->{page}
    || DEFAULT_PAGE;
    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;
    my $numpages = ceil($num_res /
                        $res_per_page);
    for (my $i = 1; $i <= $numpages; $i++) {
        if ($i == $page) {
            $index_line .= $i;
        } else {
            $index_line .= "<a href=\"".encode_entities($cgi->self_url).
                "&amp;page=$i&amp;number=$res_per_page\">".
                "$i</a>";
        }
	if ($i < $numpages) {
	   $index_line .= " | ";
	}
    }
    return $index_line;
}

sub nextlink {
    my ($cgi, $params, $no_results ) = @_;

    my $page = $params->{page}
    || DEFAULT_PAGE;
    $page++;
    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;

    if ((($page-1)*$res_per_page + 1) > $no_results) {
        return "&gt;&gt;";
    }

    return "<a href=\"".encode_entities($cgi->self_url).
        "&amp;page=$page&amp;number=$res_per_page\">&gt;&gt;</a>";
}

sub prevlink {
    my ($cgi, $params ) = @_;

    my $page = $params->{page}
    || DEFAULT_PAGE;
    $page--;
    if (!$page) {
        return "&lt;&lt;";
    }

    my $res_per_page = $params->{number}
    || DEFAULT_RES_PER_PAGE;

    return "<a href=\"".encode_entities($cgi->self_url).
        "&amp;page=$page&amp;number=$res_per_page\">&lt;&lt;</a>";
}

sub resperpagelink {
    my ($cgi, $params, $res_per_page ) = @_;

    my $page;
    if ($res_per_page =~ /^all$/i) {
	$page = 1;
    } else {
	$page = ceil(start( $params ) / $res_per_page);
    }

    return "<a href=\"".encode_entities($cgi->self_url).
        "&amp;page=$page&amp;number=$res_per_page\">$res_per_page</a>";
}

sub printindexline {
    my ( $input, $no_results, $opts ) = @_;

    my $index_line;
    if ($no_results > $opts->{number}) {
	
	$index_line = prevlink( $input, $opts)." | ".
	    indexline( $input, $opts, $no_results)." | ".
	    nextlink( $input, $opts, $no_results);
	
	print "<p style=\"text-align:center\">$index_line</p>";
    }
}

#sub multipageheader {
#    my ( $input, $no_results, $opts ) = @_;
#
#    my ($start, $end);
#    if ($opts->{number} =~ /^all$/i) {
#	$start = 1;
#	$end = $no_results;
#	$opts->{number} = $no_results;
#	$opts->{number_all}++;
#    } else {
#	$start = Packages::Search::start( $opts );
#	$end = Packages::Search::end( $opts );
#	if ($end > $no_results) { $end = $no_results; }
#    }
#
#	print "<p>Found <em>$no_results</em> matching packages,";
#    if ($end == $start) {
#	print " displaying package $end.</p>";
#    } else {
#	print " displaying packages $start to $end.</p>";
#    }
#
#    printindexline( $input, $no_results, $opts );
#
#    if ($no_results > 100) {
#	print "<p>Results per page: ";
#	my @resperpagelinks;
#	for (50, 100, 200) {
#	    if ($opts->{number} == $_) {
#		push @resperpagelinks, $_;
#	    } else {
#		push @resperpagelinks, resperpagelink($input,$opts,$_);
#	    }
#	}
#	if ($opts->{number_all}) {
#	    push @resperpagelinks, "all";
#	} else {
#	    push @resperpagelinks, resperpagelink($input, $opts, "all");
#	}
#	print join( " | ", @resperpagelinks )."</p>";
#    }
#    return ( $start, $end );
#}

sub string2id {
    my $string = "@_";
    
    $string =~ s/[^\w]/_/g;
    return $string;
}

our ( %url_params, %query_params );

sub init_url {
    my ($input, $params, $opts) = @_;

    %url_params = ();
    %query_params = ();

    if ($params->{values}{lang}{orig} &&
	(my $l = $params->{values}{lang}{no_replace})) {
	$url_params{lang} = $l;
    }
    if ($params->{values}{source}{no_replace}) {
	$url_params{source} = 'source';
	$query_params{source} = 1;
    }
    foreach my $p (qw(suite arch)) {
	if ($params->{values}{$p}{orig}
	    && (ref $params->{values}{$p}{final} eq 'ARRAY')
	    && @{$params->{values}{$p}{final}}) {
	    if (@{$params->{values}{$p}{final}} == 1) {
		$url_params{$p} = $params->{values}{$p}{final}[0];
	    } else {
		$url_params{$p} =
		    join(",",@{$params->{values}{$p}{no_replace}});
	    }
	}
    }
    foreach my $p (qw(format searchon mode exact debug)) {
	if ($params->{values}{$p}{orig}
	    && (my $pv = $params->{values}{$p}{no_replace})) {
	    $url_params{$p} = $pv;
	}
    }

    use Data::Dumper;
    debug( join("\n",Dumper(\%url_params,\%query_params)), 2 ) if DEBUG;
}

sub make_url {
    my ($add_path, $add_query, @override) = @_;
    my (@path, @query_string) = ()x2;
    my $override = {};
    if (ref $override[0]) { 
	$override = $override[0];
    } elsif (@override) {
	$override = { @override };
    }

    push @path, $Packages::Config::ROOT;
    foreach my $p (qw(lang source suite archive arch)) {
	my $val = $url_params{$p};
	$val = $override->{$p} if exists $override->{$p};
	push @path, $val if $val;
    }
    foreach my $p (qw(format debug)) {
	my $val = $url_params{$p};
	$val = $query_params{$p} if exists $query_params{$p};
	$val = $override->{$p} if exists $override->{$p};
	push @query_string, "$p=$val" if $val;
    }
    push @path, $add_path if $add_path and $add_path ne '/';
    push @query_string, $add_query if $add_query;

    my $path = join( '/', @path );
    my $query_string = join( '&', @query_string );
    $path .= '/' if $add_path and $add_path eq '/';
    $path .= "?$query_string" if $query_string;

    return $path;
}

sub make_search_url {
    my ($add_path, $add_query, @override) = @_;
    my (@path, @query_string) = ()x2;
    my $override ||= {};
    if (ref $override[0]) { 
	$override = $override[0];
    } elsif (@override) {
	$override = { @override };
    }

    push @path, $Packages::Config::SEARCH_URL
	if $Packages::Config::SEARCH_URL;
    foreach my $p (qw(lang source suite archive section subsection
		      arch exact mode searchon format debug)) {
	my $val = $url_params{$p};
	$val = $query_params{$p} if exists $query_params{$p};
	$val = $override->{$p} if exists $override->{$p};
	push @query_string, "$p=$val" if $val;
    }
    push @path, $add_path if $add_path;
    push @query_string, $add_query if $add_query;

    my $path = join( '/', @path );
    my $query_string = join( '&amp;', @query_string );

    return "$path?$query_string";
}

1;
