# Declare our package
package POE::Devel::Benchmarker::Imager::BenchmarkOutput;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.06';

# import some stuff
use File::Spec;
use POE::Devel::Benchmarker::Utils qw( currentMetrics metricSorting );
use Text::Table;

# to silence Perl::Critic - # Three-argument form of open used at line 541, column 3.  Three-argument open is not available until perl 5.6.  (Severity: 5)
use 5.008;

# creates a new instance
sub new {
	my $class = shift;
	my $opts = shift;

	# instantitate ourself
	my $self = {
		'opts'	=> $opts,
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
	#$self->generate_loopperf;

	# generate the loop assert/xsqueue ( 4 lines ) per metric
	#$self->generate_loopoptions;

	return;
}

# charts a single loop's progress over POE versions
sub generate_loopoptions {
	my $self = shift;

	if ( ! $self->{'imager'}->quiet ) {
		print "[BenchmarkOutput] Generating the Loop-Options tables...\n";
	}

	# go through all the loops we want
	foreach my $loop ( keys %{ $self->{'imager'}->poe_loops } ) {
		foreach my $metric ( @{ currentMetrics() } ) {
			my %data;

			# organize data by POE version
			foreach my $poe ( @{ $self->{'imager'}->poe_versions_sorted } ) {
				# go through the combo of assert/xsqueue
				foreach my $assert ( qw( assert noassert ) ) {
					if ( ! exists $self->{'imager'}->data->{ $assert } ) {
						next;
					}
					foreach my $xsqueue ( qw( xsqueue noxsqueue ) ) {
						if ( ! exists $self->{'imager'}->data->{ $assert }->{ $xsqueue } ) {
							next;
						}

						# sometimes we cannot test a metric
						if ( exists $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }
							and exists $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
							and defined $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
							) {
							push( @{ $data{ $assert . '_' . $xsqueue } }, $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'} );
						} else {
							push( @{ $data{ $assert . '_' . $xsqueue } }, 0 );
						}
					}
				}
			}

			use Data::Dumper;
			print Dumper( \%data );
			exit;


			# it's possible for us to do runs without assert/xsqueue
			if ( scalar keys %data > 0 ) {
				# transform %data into something GD likes
				my @data_for_gd;
				foreach my $m ( sort keys %data ) {
					push( @data_for_gd, $data{ $m } );
				}

				# send it to GD!
				$self->make_gdgraph(	'Options_' . $loop . '_' . $metric,
							[ sort keys %data ],
							\@data_for_gd,
				);
			}
		}
	}

	return;
}

# charts a single loop's progress over POE versions
sub generate_loopperf {
	my $self = shift;

	if ( ! $self->{'imager'}->quiet ) {
		print "[BenchmarkOutput] Generating the Loop-Performance tables...\n";
	}

	# go through all the loops we want
	foreach my $loop ( keys %{ $self->{'imager'}->poe_loops } ) {
		# go through the combo of assert/xsqueue
		foreach my $assert ( qw( assert noassert ) ) {
			if ( ! exists $self->{'imager'}->data->{ $assert } ) {
				next;
			}
			foreach my $xsqueue ( qw( xsqueue noxsqueue ) ) {
				if ( ! exists $self->{'imager'}->data->{ $assert }->{ $xsqueue } ) {
					next;
				}
				my %data;

				# organize data by POE version
				foreach my $poe ( @{ $self->{'imager'}->poe_versions_sorted } ) {
					foreach my $metric ( @{ currentMetrics() } ) {
						# sometimes we cannot test a metric
						if ( exists $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }
							and exists $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
							and defined $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
							) {
							push( @{ $data{ $metric } }, $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'} );
						} else {
							push( @{ $data{ $metric } }, 0 );
						}
					}
				}

				use Data::Dumper;
				print Dumper( $loop, $self->{'imager'}->poe_versions_sorted, \%data );

				# Actually make the table!
				$self->make_table(	"Loop Performance",
							$loop,
							$assert,
							$xsqueue,
							$self->{'imager'}->poe_versions_sorted,
							\%data,
				);
			}
		}
	}

	return;
}

# loop wars!
sub generate_loopwars {
	my $self = shift;

	if ( ! $self->{'imager'}->quiet ) {
		print "[BenchmarkOutput] Generating the LoopWars tables...\n";
	}

	# go through all the metrics we want
	foreach my $metric ( @{ currentMetrics() } ) {
		# go through the combo of assert/xsqueue
		foreach my $assert ( qw( assert noassert ) ) {
			if ( ! exists $self->{'imager'}->data->{ $assert } ) {
				next;
			}
			foreach my $xsqueue ( qw( xsqueue noxsqueue ) ) {
				if ( ! exists $self->{'imager'}->data->{ $assert }->{ $xsqueue } ) {
					next;
				}
				my %data;

				# organize data by POE version
				foreach my $poe ( @{ $self->{'imager'}->poe_versions_sorted } ) {
					foreach my $loop ( keys %{ $self->{'imager'}->poe_loops } ) {
						# sometimes we cannot test a metric
						if ( exists $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }
							and exists $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
							and defined $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'}
							) {
							push( @{ $data{ $loop } }, $self->{'imager'}->data->{ $assert }->{ $xsqueue }->{ $poe }->{ $loop }->{'metrics'}->{ $metric }->{'i'} );
						} else {
							push( @{ $data{ $loop } }, 0 );
						}
					}
				}

				# Actually make the table!
				$self->make_loopwar_table( $metric, $assert, $xsqueue, $self->{'imager'}->poe_versions_sorted, \%data );
			}
		}
	}

	return;
}

sub make_loopwar_table {
	my( $self, $metric, $assert, $xsqueue, $poeversions, $data ) = @_;
	my $metric_sorting = metricSorting( $metric );

	# Start the text with a header
	my $text = " LoopWars - Metric ( $metric/sec ) ";

	if ( $assert eq 'assert' ) {
		$text .= "ASSERT ";
	} else {
		$text .= "NO-ASSERT ";
	}

	if ( $xsqueue eq 'xsqueue' ) {
		$text .= "XSQUEUE";
	} else {
		$text .= "NO-XSQUEUE";
	}

	$text .= "\n\n";

	# Create the grid
	my @loops = sort keys %$data;
	my $tbl = Text::Table->new(
		# The POE version column
		{ title => "POE Version", align => 'center', align_title => 'center' },

		# The vertical separator
		\' | ',

		# The rest of the columns
		map { \' | ', { title => $_, align => 'center', align_title => 'center' } } @loops
	);

	# Fill in the data!
	foreach my $i ( 0 .. ( scalar @$poeversions - 1 ) ) {
		my @tmp = ( $poeversions->[ $i ] );

		# put << 234 >> around cells that are the "winner" of that metric
		my $best = undef;
		foreach my $l ( 0 .. ( scalar @loops - 1 ) ) {
			if ( ! defined $best ) {
				$best = $l;
			} else {
				# What is the sort order?
				if ( $metric_sorting eq 'B' ) {
					if ( $data->{ $loops[ $l ] }->[ $i ] > $data->{ $loops[ $best ] }->[ $i ] ) {
						$best = $l;
					}
				} elsif ( $metric_sorting eq 'S' ) {
					if ( $data->{ $loops[ $l ] }->[ $i ] < $data->{ $loops[ $best ] }->[ $i ] ) {
						$best = $l;
					}
				} else {
					die "Unknown metric sorting method: $metric_sorting";
				}
			}

			push( @tmp, $data->{ $loops[ $l ] }->[ $i ] );
		}

		# We found the best one...
		$tmp[ $best + 1 ] = "<< " . $tmp[ $best + 1 ] . " >>";

		$tbl->add( @tmp );
	}

	# Get the table, insert the horizontal divider, then print it out!
	$text .= $tbl->table( 0 );
	$text .= $tbl->rule( '-' );
	$text .= $tbl->table( 1, $tbl->n_cols() - 1 );
	$text .= $tbl->rule( '-' );

	# All done!
	print $text;
}

1;
__END__

=for stopwords backend

=head1 NAME

POE::Devel::Benchmarker::Imager::BenchmarkOutput - Plugin to generate output similar to Benchmark.pm

=head1 SYNOPSIS

	use POE::Devel::Benchmarker::Imager;
	imager( { type => 'BenchmarkOutput' } );

=head1 ABSTRACT

This plugin for Imager generates Benchmark.pm-alike output from the benchmark tests.

=head1 DESCRIPTION

This package generates some basic text tables from the statistics output. Since the POE::Loop::* modules really are responsible
for the backend logic of POE, it makes sense to measure all related metrics of a single loop across POE versions to see if
it performs differently.

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker::Imager -e 'imager( { type => "BenchmarkOutput" } )'

This will generate some types of tables:

=over 4

=item Loops against each other

Each metric will have a table for itself, showing how each loop compare against each other with the POE versions.

file: BenchmarkOutput/LoopWar_$metric_$lite_$assert_$xsqueue.txt

=item Single Loop over POE versions

Each Loop will have a table for itself, showing how each metric performs over POE versions.

file: BenchmarkOutput/Bench_$loop_$lite_$assert_$xsqueue.txt

=item Single Loop over POE versions with assert/xsqueue

Each Loop will have a table for itself, showing how each metric is affected by the assert/xsqueue options.

file: BenchmarkOutput/Options_$loop_$metric_$lite.txt

=back

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

L<POE::Devel::Benchmarker::Imager>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

