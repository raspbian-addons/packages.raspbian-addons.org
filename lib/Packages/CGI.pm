package Packages::CGI;

use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw( fatal_error error hint debug msg note
		  print_errors print_hints print_debug print_msgs
		  print_notes DEBUG );

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
sub print_errors {
    return unless @fatal_errors || @errors;
    print '<div class="perror">';
    foreach ((@fatal_errors, @errors)) {
	print "<p>ERROR: $_</p>";
    }
    print '</div>';
}
sub print_debug {
    return unless $debug && @debug;
    print '<div class="pdebug">';
    print '<h2>Debugging:</h2><pre>';
    foreach (@debug) {
	print "$_\n";
    }
    print '</pre></div>';
}
sub print_hints {
    return unless @hints;
    print '<div class="phints">';
    foreach (@hints) {
	print "<p>$_</p>";
    }
    print '</div>';
}
sub print_msgs {
    print '<div class="pmsgs">';
    foreach (@msgs) {
	print "<p>$_</p>";
    }
    print '</div>';
}
sub print_notes {
    foreach (@notes) {
	my ( $title, $note ) = @$_;

	print '<div class="pnotes">';
	if ($note) {
	    print "<h2>$title</h2>";
	} else {
	    $note = $title;
	}
	print "<p>$note</p></div>";
    }
}

1;
