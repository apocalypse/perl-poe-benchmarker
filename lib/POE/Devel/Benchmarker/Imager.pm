# Declare our package
package POE::Devel::Benchmarker::Imager;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.04';

# auto-export the only sub we have
require Exporter;
use vars qw( @ISA @EXPORT );
@ISA = qw(Exporter);
@EXPORT = qw( imager );

# import the helper modules
use YAML::Tiny;
use Chart::Clicker;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;

# olds our data structure
my %data;

# debug or not?
my $debug = 0;

# starts the work of converting our data to images
sub imager {
	# should we debug?
	$debug = shift;
	if ( $debug ) {
		$debug = 1;
	} else {
		$debug = 0;
	}

	# some sanity tests
	if ( ! -d 'results' ) {
		die "The 'results' directory is not found in the working directory!";
	}
	if ( ! -d 'images' ) {
		die "The 'images' directory is not found in the working directory!";
	}

	if ( $debug ) {
		print "[IMAGER] Starting up...\n";
	}

	# parse all of our YAML modules!
	parse_yaml();

	# Do some processing of the data
	process_data();

	# generate the images!
	generate_images();

	return;
}

# starts the process of loading all of our YAML images
sub parse_yaml {
	# gather all the YAML dumps
	my @versions;
	if ( opendir( DUMPS, 'results' ) ) {
		foreach my $d ( readdir( DUMPS ) ) {
			if ( $d =~ /\.yml$/ ) {
				push( @versions, $d );
			}
		}
		closedir( DUMPS ) or die "[IMAGER] Unable to read from 'results' -> " . $!;
	} else {
		die "[IMAGER] Unable to open 'results' for reading -> " . $!;
	}

	# sanity
	if ( ! scalar @versions ) {
		die "[IMAGER] Unable to find any POE test result(s) in the 'results' directory!\n";
	}

	# Parse every one of them!
	foreach my $v ( @versions ) {
		load_yaml( "results/$v" );
	}

	return;
}

# loads the yaml of a specific file
sub load_yaml {
	my $file = shift;

	my $yaml = YAML::Tiny->read( $file );
	if ( ! defined $yaml ) {
		die "[IMAGER] Unable to load YAML file $file -> " . YAML::Tiny->errstr . "\n";
	} else {
		# store it in the global hash
		$data{ $file } = $yaml->[0];
	}

	return;
}

# mangles the data we've collected so far
sub process_data {
	# FIXME okay what should we do?

	return;
}

sub generate_images {
	# FIXME okay what should we do?

	return;
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::Imager - Automatically converts the benchmark data into images

=head1 SYNOPSIS

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker::Imager -e 'imager()'

=head1 ABSTRACT

This package automatically parses the benchmark data and generates pretty charts.

=head1 DESCRIPTION

This package uses the excellent L<Chart::Clicker> module to generate the images

=head2 imager

Normally you should pass nothing to this sub. However, if you want to debug the processing you should pass a true
value as the first argument.

	perl -MPOE::Devel::Benchmarker::Imager -e 'imager( 1 )'

=head1 EXPORT

Automatically exports the imager() sub

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

L<Chart::Clicker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

