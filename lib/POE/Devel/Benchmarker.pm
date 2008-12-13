# Declare our package
package POE::Devel::Benchmarker;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.01';

# auto-export the only sub we have
BEGIN {
	require Exporter;
	use vars qw( @ISA @EXPORT );
	@ISA = qw(Exporter);
	@EXPORT = qw( benchmark );
}

# Import what we need from the POE namespace
use POE qw( Session Filter::Line Wheel::Run );
use base 'POE::Session::AttributeBased';

# we need hires times
use Time::HiRes qw( time );

# load comparison stuff
use version;

# Load our stuff
use POE::Devel::Benchmarker::GetInstalledLoops;
use POE::Devel::Benchmarker::Utils;

# Actually run the tests!
sub benchmark {
	my $options = shift;

	# set default options
	my $lite_tests = 1;
	my $quiet_mode = 0;

	# process our options
	if ( defined $options and ref $options and ref( $options ) eq 'HASH' ) {
		# process LITE tests
		if ( exists $options->{'litetests'} ) {
			if ( $options->{'litetests'} ) {
				$lite_tests = 1;
			} else {
				$lite_tests = 0;
			}
		}

		# process quiet mode
		if ( exists $options->{'quiet'} ) {
			if ( $options->{'quiet'} ) {
				$quiet_mode = 1;
			} else {
				$quiet_mode = 0;
			}
		}
	}

	# do some sanity checks
	if ( ! -d 'poedists' ) {
		die "The 'poedists' directory is not found in the working directory!";
	}
	if ( ! -d 'results' ) {
		die "The 'results' directory is not found in the working directory!";
	}

	if ( ! $quiet_mode ) {
		print "[BENCHMARKER] Starting up...\n";
	}

	# Create our session
	POE::Session->create(
		__PACKAGE__->inline_states(),
		'heap'	=>	{
			'lite_tests'	=> $lite_tests,
			'quiet_mode'	=> $quiet_mode,
		},
	);

	# Fire 'er up!
	POE::Kernel->run();
	return;
}

# Starts up our session
sub _start : State {
	# set our alias
	$_[KERNEL]->alias_set( 'Benchmarker' );

	# sanely handle some signals
	$_[KERNEL]->sig( 'INT', 'handle_kill' );
	$_[KERNEL]->sig( 'TERM', 'handle_kill' );

	# okay, get all the dists we can!
	my @versions;
	opendir( DISTS, 'poedists' ) or die $!;
	foreach my $d ( readdir( DISTS ) ) {
		if ( $d =~ /^POE\-(.+)$/ and $d !~ /\.tar\.gz$/ ) {
			push( @versions, $1 );
		}
	}
	closedir( DISTS ) or die $!;

	# okay, go through all the dists in version order
	@versions =	sort { $b <=> $a }
			map { version->new( $_ ) } @versions;

	# Store the versions in our heap
	$_[HEAP]->{'VERSIONS'} = \@versions;

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Detected available POE versions -> " . join( " ", @versions ) . "\n";
	}

	# First of all, we need to find out what loop libraries are installed
	getPOEloops( $_[HEAP]->{'quiet_mode'} );

	return;
}

sub _stop : State {
	# tell the wheel to kill itself
	if ( defined $_[HEAP]->{'WHEEL'} ) {
		$_[HEAP]->{'WHEEL'}->kill( 9 );
		undef $_[HEAP]->{'WHEEL'};
	}

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Shutting down...\n";
	}

	return;
}

# we received list of loops from GetInstalledLoops
sub found_loops : State {
	$_[HEAP]->{'installed_loops'} = [ sort { $a eq $b } @{ $_[ARG0] } ];

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Detected available POE::Loops -> " . join( " ", @{ $_[HEAP]->{'installed_loops'} } ) . "\n";
	}

	# start the benchmark!
	$_[KERNEL]->yield( 'run_benchmark' );
	return;
}

# Runs one benchmark
sub run_benchmark : State {
	# Grab the version from the top of the array
	$_[HEAP]->{'current_version'} = shift @{ $_[HEAP]->{'VERSIONS'} };

	# did we run out of versions?
	if ( ! defined $_[HEAP]->{'current_version'} ) {
		# We're done, let POE die...
		$_[KERNEL]->alias_remove( 'Benchmarker' );
	} else {
		$_[HEAP]->{'loops'} = [ @{ $_[HEAP]->{'installed_loops'} } ];

		# okay, fire off the first loop
		$_[KERNEL]->yield( 'bench_loop' );
	}

	return;
}

# runs one loop
sub bench_loop : State {
	# select our current loop
	$_[HEAP]->{'current_loop'} = shift @{ $_[HEAP]->{'loops'} };

	# are we done with all loops?
	if ( ! defined $_[HEAP]->{'current_loop'} ) {
		# yay, go back to the main handler
		$_[KERNEL]->yield( 'run_benchmark' );
	} else {
		# Start the assert test
		$_[HEAP]->{'assertions'} = [ qw( 0 1 ) ];
		$_[KERNEL]->yield( 'bench_asserts' );
	}

	return;
}

# runs an assertion
sub bench_asserts : State {
	# select our current assert state
	$_[HEAP]->{'current_assertions'} = shift @{ $_[HEAP]->{'assertions'} };

	# are we done?
	if ( ! defined $_[HEAP]->{'current_assertions'} ) {
		# yay, go back to the loop handler
		$_[KERNEL]->yield( 'bench_loop' );
	} else {
		# Start the xsqueue test
		$_[HEAP]->{'xsqueue'} = [ qw( 0 1 ) ];
		$_[KERNEL]->yield( 'bench_xsqueue' );
	}

	return;
}

# runs test with or without xsqueue
sub bench_xsqueue : State {
	# select our current xsqueue state
	$_[HEAP]->{'current_xsqueue'} = shift @{ $_[HEAP]->{'xsqueue'} };

	# are we done?
	if ( ! defined $_[HEAP]->{'current_xsqueue'} ) {
		# yay, go back to the assert handler
		$_[KERNEL]->yield( 'bench_asserts' );
	} else {
		# actually fire off the subprocess, ha!
		$_[KERNEL]->yield( 'create_subprocess' );
	}

	return;
}

# actually runs the subprocess
sub create_subprocess : State {
	# Okay, start testing this specific combo!
	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "Testing POE v" . $_[HEAP]->{'current_version'} .
			" loop(" . $_[HEAP]->{'current_loop'} . ')' .
			" assertions(" . ( $_[HEAP]->{'current_assertions'} ? 'ENABLED' : 'DISABLED' ) . ')' .
			" xsqueue(" . ( $_[HEAP]->{'current_xsqueue'} ? 'ENABLED' : 'DISABLED' ) . ')' .
			"\n";
	}

	# save the starttime
	$_[HEAP]->{'current_starttime'} = time();
	$_[HEAP]->{'current_starttimes'} = [ times() ];

	# Okay, create the wheel::run to handle this
	my $looploader = poeloop2load( $_[HEAP]->{'current_loop'} );
	$_[HEAP]->{'WHEEL'} = POE::Wheel::Run->new(
		'Program'	=>	$^X,
		'ProgramArgs'	=>	[	'-Ipoedists/POE-' . $_[HEAP]->{'current_version'},
						'-Ipoedists/POE-' . $_[HEAP]->{'current_version'} . '/lib',
						( defined $looploader ? "-M$looploader" : () ),
						'-MPOE::Devel::Benchmarker::SubProcess',
						'-e',
						'POE::Devel::Benchmarker::SubProcess::benchmark',
						$_[HEAP]->{'current_version'},
						$_[HEAP]->{'current_loop'},
						$_[HEAP]->{'current_assertions'},
						$_[HEAP]->{'lite_tests'},
						$_[HEAP]->{'current_xsqueue'},
					],

		# Kill off existing FD's
		'CloseOnCall'	=>	1,

		# setup our data handlers
		'StdoutEvent'	=>	'Got_STDOUT',
		'StderrEvent'	=>	'Got_STDERR',

		# the error handler
		'ErrorEvent'	=>	'Got_ERROR',
		'CloseEvent'	=>	'Got_CLOSED',

		# set our filters
		'StderrFilter'	=>	POE::Filter::Line->new(),
		'StdoutFilter'	=>	POE::Filter::Line->new(),
	);
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		die 'Unable to create a new wheel!';
	} else {
		# smart CHLD handling
		if ( $_[KERNEL]->can( "sig_child" ) ) {
			$_[KERNEL]->sig_child( $_[HEAP]->{'WHEEL'}->PID => 'Got_CHLD' );
		} else {
			$_[KERNEL]->sig( 'CHLD', 'Got_CHLD' );
		}
	}

	# setup our data we received from the subprocess
	$_[HEAP]->{'current_data'} = '';

	# Okay, we timeout this test after some time for sanity
	$_[HEAP]->{'test_timedout'} = 0;
	if ( $_[HEAP]->{'lite_tests'} ) {
		# on my core2duo 1.2ghz laptop, running Gtk+LITE+assert+noxsqueue takes approx 45s
		$_[HEAP]->{'TIMER'} = $_[KERNEL]->delay_set( 'test_timedout' => 60 * 2 );
	} else {
		# on my core2duo 1.2ghz laptop, running Gtk+HEAVY+assert+noxsqueue takes all day long :(
		$_[HEAP]->{'TIMER'} = $_[KERNEL]->delay_set( 'test_timedout' => 60 * 15 );
	}

	return;
}

# Got a CHLD event!
sub Got_CHLD : State {
	$_[KERNEL]->sig_handled();
	return;
}

# Handles child STDERR output
sub Got_STDERR : State {
	my $input = $_[ARG0];

	# save it!
	$_[HEAP]->{'current_data'} .= '!STDERR: ' . $input . "\n";
	return;
}

# Handles child STDOUT output
sub Got_STDOUT : State {
	my $input = $_[ARG0];

	# save it!
	$_[HEAP]->{'current_data'} .= $input . "\n";
	return;
}

# Handles child error
sub Got_ERROR : State {
	# Copied from POE::Wheel::Run manpage
	my ( $operation, $errnum, $errstr ) = @_[ ARG0 .. ARG2 ];

	# ignore exit 0 errors
	if ( $errnum != 0 ) {
		warn "Wheel::Run got an $operation error $errnum: $errstr\n";
	}

	return;
}

# Handles child DIE'ing
sub Got_CLOSED : State {
	# Get rid of the wheel
	undef $_[HEAP]->{'WHEEL'};

	# get rid of the delay
	$_[KERNEL]->alarm_remove( $_[HEAP]->{'TIMER'} );
	undef $_[HEAP]->{'TIMER'};

	# wrap up this test
	$_[KERNEL]->yield( 'wrapup_test' );
	return;
}

# a test timed out, unfortunately!
sub test_timedout : State {
	# tell the wheel to kill itself
	$_[HEAP]->{'WHEEL'}->kill( 9 );
	undef $_[HEAP]->{'WHEEL'};

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Test TimedOut!\n";
	}

	$_[HEAP]->{'test_timedout'} = 1;

	# wrap up this test
	$_[KERNEL]->yield( 'wrapup_test' );
	return;
}

# finalizes a test
sub wrapup_test : State {
	# we're done with this benchmark!
	$_[HEAP]->{'current_endtime'} = time();
	$_[HEAP]->{'current_endtimes'} = [ times() ];

	# store the data
	my $file = 'POE-' . $_[HEAP]->{'current_version'} .
		'-' . $_[HEAP]->{'current_loop'} .
		( $_[HEAP]->{'current_assertions'} ? '-assert' : '-noassert' ) .
		( $_[HEAP]->{'current_xsqueue'} ? '-xsqueue' : '-noxsqueue' );

	open( RESULT, '>', "results/$file" ) or die $!;
	print RESULT "STARTTIME: " . $_[HEAP]->{'current_starttime'} . " -> TIMES " . join( " ", @{ $_[HEAP]->{'current_starttimes'} } ) . "\n";
	print RESULT "$file\n\n";
	print RESULT $_[HEAP]->{'current_data'} . "\n";
	if ( $_[HEAP]->{'test_timedout'} ) {
		print RESULT "\nTEST TERMINATED DUE TO TIMEOUT\n";
	}
	print RESULT "ENDTIME: " . $_[HEAP]->{'current_endtime'} . " -> TIMES " . join( " ", @{ $_[HEAP]->{'current_endtimes'} } ) . "\n";
	close( RESULT ) or die $!;

	# process the next test
	$_[KERNEL]->yield( 'bench_xsqueue' );
	return;
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker - Benchmarking POE's performance ( acts more like a smoker )

=head1 SYNOPSIS

	perl -MPOE::Devel::Benchmarker -e 'benchmark()'

=head1 ABSTRACT

This package of tools is designed to benchmark POE's performace across different
configurations. The current "tests" are:

=over
=item posts
=item calls
=item alarm_adds
=item session creation
=item session destruction
=item select_read toggles
=item select_write toggles
=item POE startup time
=back

=head1 DESCRIPTION

This module is poorly documented now. Please give me some time to properly document it over time :)

=head2 INSTALLATION

Here's a simple outline to get you up to speed quickly. ( and smoking! )

=over
=item Install CPAN package + dependencies

Download+install the POE::Devel::Benchmarker package from CPAN

	apoc@apoc-x300:~$ cpanp -i POE::Devel::Benchmarker

=item Setup initial directories

Go anywhere, and create the "parent" directory where you'll be storing test results + stuff. For this example,
I have chosen to use ~/poe-benchmarker:

	apoc@apoc-x300:~$ mkdir poe-benchmarker
	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ mkdir poedists
	apoc@apoc-x300:~/poe-benchmarker$ cd poedists/
	apoc@apoc-x300:~/poe-benchmarker/poedists$ perl -MPOE::Devel::Benchmarker::GetPOEdists -e 'getPOEdists( 1 )'

	( go get a coffee while it downloads if you're on a slow link, ha! )

	apoc@apoc-x300:~/poe-benchmarker/poedists$ cd..
	apoc@apoc-x300:~/poe-benchmarker$ mkdir results

=item Let 'er rip!

At this point you can start running the benchmark!

NOTE: the Benchmarker expects everything to be in the "local" directory!

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker -e 'benchmark()'

=back

=head2 ANALYZING RESULTS

This part of the documentation is woefully incomplete. Please look at the L<POE::Devel::Benchmarker::Analyzer> module.

=head2 SUBROUTINES

This module exposes only one subroutine, the benchmark() one. You can pass a hashref to it to set various options. Here is
a list of the valid options:

=over
=item litetests => boolean

This enables the "lite" tests which will not take up too much time.

default: false

=item quiet => boolean

This enables quiet mode which will not print anything to the console except for errors.

default: false

=back

=head2 EXPORT

Automatically exports the benchmark() subroutine.

=head1 TODO

=over
=item Perl version smoking

We should be able to run the benchmark over different Perl versions. This would require some fiddling with our
layout + logic. It's not that urgent because the workaround is to simply execute the smoke suite under a different
perl binary. It's smart enough to use $^X to be consistent across tests :)

=item Select the EV backend

<Khisanth> and if you are benchmarking, try it with POE using EV with EV using Glib? :P
<Apocalypse> I'm not sure how to configure the EV "backend" yet
<Apocalypse> too much docs for me to read hah
<Khisanth> Apocalypse: use EV::Glib; use Glib; use POE; :)

=item Disable POE::XS::Queue::Array tests if not found

Currently we blindly move on and test with/without this. We should be smarter and not waste one extra test per iteration
if it isn't installed!

=item Be more smarter in smoking timeouts

Currently we depend on the lite_tests option and hardcode some values including the timeout. If your machine is incredibly
slow, there's a chance that it could timeout unnecessarily. Please look at the outputs and check to see if there are unusual
failures, and inform me.

=back

=head1 SEE ALSO

L<POE>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

BIG THANKS goes to Rocco Caputo E<lt>rcaputo@cpan.orgE<gt> for the first benchmarks!

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
