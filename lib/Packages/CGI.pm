package Packages::CGI;

use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( fatal_error error hint debug msg note
		  print_errors print_hints print_debug print_msgs
		  print_notes );

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
sub print_errors {
    return unless @fatal_errors || @errors;
    print '<div style="margin:.2em;background-color:#F99;font-weight:bold;padding:0.5em;margin:0;">';
    foreach ((@fatal_errors, @errors)) {
	print "<p>ERROR: $_</p>";
    }
    print '</div>';
}
sub print_debug {
    return unless $debug && @debug;
    print '<div style="margin:.2em;font-size:80%;border:solid thin grey">';
    print '<h2>Debugging:</h2><pre>';
    foreach (@debug) {
	print "$_\n";
    }
    print '</pre></div>';
}
sub print_hints {
    return unless @hints;
    print '<div style="margin:.2em;">';
    foreach (@hints) {
	print "<p style=\"background-color:#FF9;padding:0.5em;margin:0\">$_</p>";
    }
    print '</div>';
}
sub print_msgs {
    foreach (@msgs) {
	print "<p>$_</p>";
    }
}
sub print_notes {
    foreach (@notes) {
	my ( $title, $note ) = @$_;

	print '<div style="margin:.2em;border: solid thin black; background-color: #bdf">';
	if ($note) {
	    print "<h2 class=\"pred\">$title</h2>";
	} else {
	    $note = $title;
	}
	print "<p>$note</p></div>";
    }
}

1;
