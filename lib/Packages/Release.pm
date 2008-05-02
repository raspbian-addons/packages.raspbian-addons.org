package Packages::Release;

use strict;
use warnings;

use Date::Parse;

sub new {
    my $classname = shift;
    my $config = shift || {};

    my $self = {};
    bless( $self, $classname );

    $self->{config} = $config;
    if ($config->{file}) {
	$self->parse;
    }

    return $self;
}

sub parse {
    my ($self, $file, $config) = @_;

    $self->config(%$config) if $config;

    $self->{config}{file} = $file if $file;
    return unless $self->{config}{file};

    local $/ = undef;

    open(my $rf, '<', $self->{config}{file})
	or die "$self->{config}{file}: $!\n";

    my @content = <$rf>;
    die "too many paragraphs in release file $self->{config}{file})"
	if @content > 1;
    return unless @content && $content[0] !~ /^\s*$/;

    my %data = ();
    $_ = $content[0];
    chomp;
    s/\n /\377/g;
    while (/^(\S+):\s*(.*)\s*$/mg) {
	my ($key, $value) = ($1, $2);
	$value =~ s/\377/\n /g;
	$key =~ tr [A-Z] [a-z];
	$data{$key} = $value;
    }

    $data{components} = [ split(/\s+/, $data{components}||'') ];
    $data{architectures} = [ split(/\s+/, $data{architectures}||'') ];
    $data{timestamp} = str2time($data{date}) if $data{date};

    read_files_field( \%data, 'md5sum' );
    read_files_field( \%data, 'sha1' );
    read_files_field( \%data, 'sha256' );

    $self->{data} = \%data;
}

sub read_files_field {
    my ($data, $fieldname) = @_;

    return unless $data->{$fieldname};
    my @lines = split /\n/, $data->{$fieldname};

    foreach (@lines) {
	next if /^\s*$/;
	chomp;
	s/^\s+//;

#	warn "line=$_ ";
	my ($checksum, $size, $name) = split /\s+/, $_, 3;
#	warn "($checksum, $size, $name)\n";

	(my $basename = $name) =~ s/\.(gz|bz2)$//o;
	my $ext = 'uncompressed';
	if ($basename ne $name) {
	    $ext = $1;
	}

	if ($data->{files}{$basename}{$ext}{size}
	    and $data->{files}{$basename}{$ext}{size} != $size) {
	    die "conflicting sizes for $name: $data->{files}{$basename}{$ext}{size} != $size\n";
	}
	$data->{files}{$basename}{$ext}{size} = $size;
	$data->{files}{$basename}{$ext}{$fieldname} = $checksum;

    }
    delete($data->{$fieldname});
}

sub check {
    my ($self, $base, $config) = @_;

    $self->config(%$config) if $config;

    return unless $self->{config}{file};
    $self->_v("checking Release file $self->{config}{file}\n");
    my $sigfile = "$self->{config}{file}.gpg";

    if ($self->{config}{keyring}) {
	$self->_v("\tchecking signature\n");

	die "$self->{config}{keyring} not readable\n"
	    unless -r $self->{config}{keyring};

	if (system('gpg',
		   '--trust-model', 'always', '--no-default-keyring',
		   '--keyring', $self->{config}{keyring}, '--verify',
		   $sigfile, $self->{config}{file})) {
	    die "signature check failed.\n";
	}
    }

    $self->{config}{base} = $base if $base;
    return unless $self->{config}{base};
    return unless -d $self->{config}{base};
    return unless $self->{data}{files};

    foreach my $f (sort keys %{$self->{data}{files}}) {
	$self->_v("checking file $f:\n");

	$self->_check_file($f);
	$self->_check_file($f, 'gz');
	$self->_check_file($f, 'bz2');
    }
}

sub _check_file {
    my ($self, $file, $ext) = @_;

    my $f = "$self->{config}{base}/$file";
    $f .= ".$ext" if $ext;
    $ext ||= 'uncompressed';

    return unless exists $self->{data}{files}{$file}{$ext};

    unless (-f $f) {
	warn "\t$f doesn't exist or is not a file\n"
	    unless $self->{config}{ignoremissing};
	return;
    }

    my $size = -s _;
    $self->_v("\t$ext: ");
    if ($size == $self->{data}{files}{$file}{$ext}{size}) {
	$self->_v('size ok');
    } else {
	$self->_ce("$f size NOT OK: $size != $self->{data}{files}{$file}{$ext}{size}");
	$self->{errors}{$file}{$ext}{size} = $size;
	return;
    }

    my %checksums = %{ get_checksums($f) };

    foreach (qw(md5sum sha1 sha256)) {
	$self->_v(' ');
	if (!exists $self->{data}{files}{$file}{$ext}{$_}) {
	    $self->_v("$_ not available");
	} elsif ($checksums{$_} eq $self->{data}{files}{$file}{$ext}{$_}) {
	    $self->_v("$_ ok");
	} else {
	    $self->_ce("$f $_ NOT OK: $checksums{$_} ne $self->{data}{files}{$file}{$ext}{$_}");
	    $self->{errors}{$file}{$ext}{$_} = $checksums{$_};
	    return;
	}
    }
    $self->_v("\n");
}

sub get_checksums {
    my ($file) = @_;

    my %checksums;

    $checksums{md5sum} = `md5sum $file 2>/dev/null`;
    $checksums{sha1} = `sha1sum $file 2>/dev/null`;
    $checksums{sha256} = `sha256sum $file 2>/dev/null`;

    foreach (qw(md5sum sha1 sha256)) {
	chomp $checksums{$_};
	$checksums{$_} = (split(/\s+/, $checksums{$_}, 2))[0];
    }

    return \%checksums;
}

sub _v {
    my ($self, @text) = @_;

    print(STDERR @text)  if $self->{config}{verbose};
}

sub _ce {
    my ($self, @text) = @_;

    if ($self->{config}{dieoncheckerror}) {
	die(@text,"\n");
    } else {
	warn(@text,"\n");
    }
}

sub config {
    my ($self, %config) = @_;

    while (my ($k, $v) = each %config) {
	$self->{config}{$k} = $v;

    }
}

1;
