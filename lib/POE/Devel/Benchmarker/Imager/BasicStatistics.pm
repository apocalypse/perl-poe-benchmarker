# Declare our package
package POE::Devel::Benchmarker::Imager::BasicStatistics;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.04';

# the GD stuff
use GD::Graph::lines;

# creates a new instance
sub new {
	my $class = shift;
	my $opts = shift;

	# instantitate ourself
	my $self = {
		'opts' => $opts,
	};
	return bless $self, $class;
}

# actually generates the graphs!
sub imager {
	my $self = shift;
	$self->{'imager'} = shift;

	# generate the loops vs each other graphs
	$self->generate_loopwars;

	# generate the single loop performance
	$self->generate_loopperf;

	return;
}

# charts a single loop's progress over POE versions
sub generate_loopperf {
	my $self = shift;

	# go through all the loops we want
	foreach my $loop ( keys %{ $self->{'imager'}->poe_loops } ) {
		my %data;

		# organize data by POE version
		foreach my $poe ( @{ $self->{'imager'}->poe_versions_sorted } ) {
			foreach my $metric ( qw( alarms dispatches posts single_posts startups select_read_MYFH select_write_MYFH select_read_STDIN select_write_STDIN ) ) {
				if ( exists $self->{'imager'}->data->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
					and defined $self->{'imager'}->data->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
					) {
					push( @{ $data{ $metric } }, $self->{'imager'}->data->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'} );
				} else {
					push( @{ $data{ $metric } }, 0 );
				}
			}
		}

		# transform %data into something GD likes
		my @data_for_gd;
		foreach my $metric ( sort keys %data ) {
			push( @data_for_gd, $data{ $metric } );
		}

		# send it to GD!
		$self->make_gdgraph(	"Bench_$loop",
					[ sort keys %data ],
					'iterations/sec',
					\@data_for_gd,
		);
	}

	return;
}

# loop wars!
sub generate_loopwars {
	my $self = shift;

	# go through all the metrics we want
	foreach my $metric ( qw( alarms dispatches posts single_posts startups select_read_MYFH select_write_MYFH select_read_STDIN select_write_STDIN ) ) {
		my %data;

		# organize data by POE version
		foreach my $poe ( @{ $self->{'imager'}->poe_versions_sorted } ) {
			foreach my $loop ( keys %{ $self->{'imager'}->poe_loops } ) {
				if ( exists $self->{'imager'}->data->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
					and defined $self->{'imager'}->data->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
					) {
					push( @{ $data{ $loop } }, $self->{'imager'}->data->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'} );
				} else {
					push( @{ $data{ $loop } }, 0 );
				}
			}
		}

		# transform %data into something GD likes
		my @data_for_gd;
		foreach my $loop ( sort keys %data ) {
			push( @data_for_gd, $data{ $loop } );
		}

		# send it to GD!
		$self->make_gdgraph(	"LoopWar_$metric",
					[ sort keys %{ $self->{'imager'}->poe_loops } ],
					'iterations/sec',
					\@data_for_gd,
		);
	}

	return;
}

sub make_gdgraph {
	my $self = shift;
	my $metric = shift;
	my $legend = shift;
	my $ylabel = shift;
	my $data = shift;

	# Get the graph object
	my $graph = new GD::Graph::lines( 800, 600 );

	# Set some stuff
	$graph->set(
#		'x_label'		=>	'POE Versions',
		'title'			=>	$metric,
		'line_width'		=>	1,
		'boxclr'		=>	'black',
		'overwrite'		=>	0,
		'x_labels_vertical'	=>	1,
		'x_all_ticks'		=>	1,
		'legend_placement'	=>	'BL',
		'y_label'		=>	$ylabel,

		# 3d options only
		#'line_depth'		=>	2.5,
	) or die $graph->error;

	# Set the legend
	$graph->set_legend( @$legend );

	# Set Font stuff
	$graph->set_legend_font( GD::gdMediumBoldFont );
	$graph->set_x_axis_font( GD::gdMediumBoldFont );
	$graph->set_y_axis_font( GD::gdMediumBoldFont );
	$graph->set_y_label_font( GD::gdMediumBoldFont );
	$graph->set_title_font( GD::gdGiantFont );

	# Manufacture the data
	my $readydata = [
		[ map { 'POE-' . $_ } @{ $self->{'imager'}->poe_versions_sorted } ],
		@$data,
	];

	# Plot it!
	$graph->plot( $readydata ) or die $graph->error;

	# Print it!
	my $filename = $self->{'opts'}->{'dir'} . $metric . '_' .
		( $self->{'imager'}->litetests ? 'lite' : 'heavy' ) . '_' .
		( $self->{'imager'}->noasserts ? 'noasserts' : 'asserts' ) . '_' .
		( $self->{'imager'}->noxsqueue ? 'noxsqueue' : 'xsqueue' ) .
		'.png';
	open( my $fh, '>', $filename ) or die 'Cannot open graph file!';
	binmode( $fh );
	print $fh $graph->gd->png();
	close( $fh );

	return;
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::Imager::BasicStatistics - Plugin to generates basic statistics graphs

=head1 SYNOPSIS

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker::Imager -e 'imager( { type => "BasicStatistics" } )'

=head1 ABSTRACT

This plugin for Imager generates some kinds of graphs from the benchmark tests.

=head1 DESCRIPTION

This package generates some basic graphs from the statistics output. Since the POE::Loop::* modules really are responsible
for the backend logic of POE, it makes sense to graph all related metrics of a single loop across POE versions to see if
it performs differently. The related benchmark metrics are: events, alarms, filehandles, and startup.

This will generate 2 types of graphs:

=over 4

=item Loops against each other

Each metric will have a picture for itself, showing how each loop compare against each other with the POE versions.

file: BasicStatistics/$metric.png

=item Single Loop over POE versions

Each Loop will have a picture for itself, showing how each metric performs over POE versions.

file: BasicStatistics/$loop.png

=back

=head1 EXPORT

Nothing.

=head1 SEE ALSO

L<POE::Devel::Benchmarker::Imager>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

