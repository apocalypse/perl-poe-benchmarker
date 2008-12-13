# Declare our package
package POE::Devel::Benchmarker::SubProcess;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.01';

# Import Time::HiRes's time()
use Time::HiRes qw( time );

# FIXME UGLY HACK here
BEGIN {
	# should we enable assertions?
	if ( defined $ARGV[2] and $ARGV[2] ) {
		eval "sub POE::Kernel::ASSERT_DEFAULT () { 1 }";
		eval "sub POE::Session::ASSERT_STATES () { 1 }";
	}

	# should we "hide" XS::Queue::Array?
	if ( defined $ARGV[4] and $ARGV[4] ) {
		eval "use Devel::Hide qw( POE/XS/Queue/Array.pm )";
	}
}

# load POE
use POE;

# load our utility stuff
use POE::Devel::Benchmarker::Utils;

# autoflush our STDOUT for sanity
use FileHandle;
autoflush STDOUT 1;

# init our global variables ( bad, haha )
my( $version, $eventloop, $asserts, $lite_tests, $pocosession );
my( $post_limit, $alarm_limit, $alarm_add_limit, $session_limit, $select_limit, $through_limit, $call_limit, $start_limit );

# the main routine which will load everything + start
sub benchmark {
	# process the version
	process_version();

	# process the eventloop
	process_eventloop();

	# process the assertions
	process_assertions();

	# process the test mode
	process_testmode();

	# process the XS::Queue hiding
	process_xsqueue();

	# actually import POE!
	process_POE();

	# actually run the benchmarks!
	run_benchmarks();

	# all done!
	return;
}

sub process_version {
	# Get the desired POE version
	$version = $ARGV[0];

	# Decide what to do
	if ( ! defined $version ) {
		die "Please supply a version to test!";
	} elsif ( ! -d 'poedists/POE-' . $version ) {
		die "That specified version does not exist!";
	} else {
		# we're happy...
	}

	return;
}

sub process_eventloop {
	# Get the desired mode
	$eventloop = $ARGV[1];

	# print out the loop info
	if ( ! defined $eventloop ) {
		die "Please supply an event loop!";
	} else {
		my $v = loop2realversion( $eventloop ) || 'UNKNOWN';
		print "Using loop: $eventloop-$v\n";
	}

	return;
}

sub process_assertions {
	# Get the desired assert mode
	$asserts = $ARGV[2];

	if ( defined $asserts and $asserts ) {
		print "Using FULL Assertions!\n";
	} else {
		print "Using NO Assertions!\n";
	}

	return;
}

sub process_testmode {
	# get the desired test mode
	$lite_tests = $ARGV[3];
	if ( defined $lite_tests and $lite_tests ) {
		print "Using the LITE tests\n";

		$post_limit		= 10_000;
		$alarm_limit		= 10_000;
		$alarm_add_limit	= 10_000;
		$session_limit		=    500;
		$select_limit		= 10_000;
		$through_limit		= 10_000;
		$call_limit		= 10_000;
		$start_limit		=     10;
	} else {
		print "Using the HEAVY tests\n";

		$post_limit		= 100_000;
		$alarm_limit		= 100_000;
		$alarm_add_limit	= 100_000;
		$session_limit		=   5_000;
		$select_limit		= 100_000;
		$through_limit		= 100_000;
		$call_limit		= 100_000;
		$start_limit		=     100;
	}

	return;
}

sub process_xsqueue {
	# should we "hide" XS::Queue::Array?
	if ( defined $ARGV[4] and $ARGV[4] ) {
		print "DISABLING POE::XS::Queue::Array\n";
	} else {
		print "LETTING POE find POE::XS::Queue::Array\n";
	}

	return;
}

sub process_POE {
	# Print the POE info
	print "Using POE-" . $POE::VERSION . "\n";

	# Actually print what loop POE is using
	foreach my $m ( keys %INC ) {
		if ( $m =~ /^POE\/(?:Loop|XS|Queue)/ ) {
			# try to be smart and get version?
			my $module = $m;
			$module =~ s|/|::|g;
			$module =~ s/\.pm$//g;
			print "POE is using: $module ";
			if ( defined $module->VERSION ) {
				print "v" . $module->VERSION . "\n";
			} else {
				print "vUNKNOWN\n";
			}
		}
	}

	return;
}

sub run_benchmarks {
	# run the startup test before we actually run POE
	bench_startup();

	# load the POE session + do the tests there
	bench_poe();

	# dump some misc info
	dump_memory();
	dump_times();
	dump_perlinfo();
	dump_sysinfo();

	# all done!
	return;
}

sub bench_startup {
	# Add the eventloop?
	my $looploader = poeloop2load( $eventloop );

	my @start_times = times();
	my $start = time();
	for (my $i = 0; $i < $start_limit; $i++) {
		# FIXME should we add assertions?

		# finally, fire it up!
		CORE::system(
			$^X,
			'-Ipoedists/POE-' . $version,
			'-Ipoedists/POE-' . $version . '/lib',
			( defined $looploader ? "-M$looploader" : () ),
			'-MPOE',
			'-e',
			1,
		);
	}
	my @end_times = times();
	my $elapsed = time() - $start;
	printf( "\n\n% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $start_limit, 'startups', $elapsed, $start_limit/$elapsed );
	print "startup times: @start_times @end_times\n";

	return;
}

sub bench_poe {
	# figure out POE::Session->create or POE::Session->new or what?
	$pocosession = POE::Session->can( 'create' );
	if ( defined $pocosession ) {
		$pocosession = 'create';
	} else {
		$pocosession = POE::Session->can( 'spawn' );
		if ( defined $pocosession ) {
			$pocosession = 'spawn';
		} else {
			$pocosession = 'new';
		}
	}

	# create the master sesssion + run POE!
	POE::Session->$pocosession(
		'inline_states' =>	{
			# basic POE states
			'_start'	=> \&poe__start,
			'_default'	=> \&poe__default,
			'_stop'		=> \&poe__stop,
			'null'		=> \&poe_null,

			# our test states
			'posts'			=> \&poe_posts,
			'posts_start'		=> \&poe_posts_start,
			'posts_end'		=> \&poe_posts_end,
			'alarms'		=> \&poe_alarms,
			'manyalarms'		=> \&poe_manyalarms,
			'sessions'		=> \&poe_sessions,
			'sessions_end'		=> \&poe_sessions_end,
			'stdin_read'		=> \&poe_stdin_read,
			'stdin_write'		=> \&poe_stdin_write,
			'myfh_read'		=> \&poe_myfh_read,
			'myfh_write'		=> \&poe_myfh_write,
			'calls'			=> \&poe_calls,
			'eventsquirt'		=> \&poe_eventsquirt,
			'eventsquirt_done'	=> \&poe_eventsquirt_done,
		},
	);

	# start the kernel!
	POE::Kernel->run();

	return;
}

# inits our session
sub poe__start {
	# fire off the first test!
	$_[KERNEL]->yield( 'posts' );

	return;
}

sub poe__stop {
}

sub poe__default {
	return 0;
}

# a state that does nothing
sub poe_null {
	return 1;
}

# How many posts per second?  Post a bunch of events, keeping track of the time it takes.
sub poe_posts {
	$_[KERNEL]->yield( 'posts_start' );
	my $start = time();
	my @start_times = times();
	for (my $i = 0; $i < $post_limit; $i++) {
		$_[KERNEL]->yield( 'null' );
	}
	my @end_times = times();
	my $elapsed = time() - $start;
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $post_limit, 'posts', $elapsed, $post_limit/$elapsed );
	print "posts times: @start_times @end_times\n";
	$_[KERNEL]->yield( 'posts_end' );

	return;
}

sub poe_posts_start {
	$_[HEAP]->{start} = time();
	$_[HEAP]->{starttimes} = [ times() ];

	return;
}

sub poe_posts_end {
	my $elapsed = time() - $_[HEAP]->{start};
	my @end_times = times();
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $post_limit, 'dispatches', $elapsed, $post_limit/$elapsed );
	print "dispatches times: " . join( " ", @{ $_[HEAP]->{starttimes} } ) . " @end_times\n";
	$_[KERNEL]->yield( 'alarms' );

	return;
}

# How many alarms per second?  Set a bunch of alarms and find out.
sub poe_alarms {
	my $start = time();
	my @start_times = times();
	for (my $i = 0; $i < $alarm_limit; $i++) {
		$_[KERNEL]->alarm( whee => rand(1_000_000) );
	}
	my $elapsed = time() - $start;
	my @end_times = times();
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $alarm_limit, 'alarms', $elapsed, $alarm_limit/$elapsed );
	print "alarms times: @start_times @end_times\n";
	$_[KERNEL]->alarm( 'whee' => undef );
	$_[KERNEL]->yield( 'manyalarms' );

	return;
}

# How many repetitive alarms per second?  Set a bunch of
# additional alarms and find out.  Also see how quickly they can
# be cleared.
sub poe_manyalarms {
	# can this POE::Kernel support this?
	if ( $_[KERNEL]->can( 'alarm_add' ) ) {
		my $start = time();
		my @start_times = times();
		for (my $i = 0; $i < $alarm_add_limit; $i++) {
			$_[KERNEL]->alarm_add( whee => rand(1_000_000) );
		}
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $alarm_add_limit, 'alarm_adds', $elapsed, $alarm_add_limit/$elapsed );
		print "alarm_adds times: @start_times @end_times\n";

		$start = time();
		@start_times = times();
		$_[KERNEL]->alarm( whee => undef );
		$elapsed = time() - $start;
		@end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $alarm_add_limit, 'alarm_clears', $elapsed, $alarm_add_limit/$elapsed );
		print "alarm_clears times: @start_times @end_times\n";
	} else {
		print "this version of POE does not support alarm_add, skipping alarm_adds/alarm_clears tests!\n";
	}

	$_[KERNEL]->yield( 'sessions' );

	return;
}

# How many sessions can we create and destroy per second?
# Create a bunch of sessions, and track that time.  Let them
# self-destruct, and track that as well.
sub poe_sessions {
	my $start = time();
	my @start_times = times();
	for (my $i = 0; $i < $session_limit; $i++) {
		POE::Session->$pocosession( 'inline_states' => { _start => sub {}, _stop => sub {}, _default => sub { return 0 } } );
	}
	my $elapsed = time() - $start;
	my @end_times = times();
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $session_limit, 'session creates', $elapsed, $session_limit/$elapsed );
	print "session create times: @start_times @end_times\n";

	$_[KERNEL]->yield( 'sessions_end' );
	$_[HEAP]->{start} = time();
	$_[HEAP]->{starttimes} = [ times() ];

	return;
}

sub poe_sessions_end {
	my $elapsed = time() - $_[HEAP]->{start};
	my @end_times = times();
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $session_limit, 'session destroys', $elapsed, $session_limit/$elapsed );
	print "session destroys times: " . join( " ", @{ $_[HEAP]->{starttimes} } ) . " @end_times\n";

	$_[KERNEL]->yield( 'stdin_read' );

	return;
}

# How many times can we select/unselect READ a from STDIN filehandle per second?
sub poe_stdin_read {
	# stupid, but we have to skip those tests
	if ( $eventloop eq 'Tk' or $eventloop eq 'Prima' ) {
		print "SKIPPING STDIN tests on broken loop: $eventloop\n";
		$_[KERNEL]->yield( 'myfh_read' );
		return;
	}

	my $start = time();
	my @start_times = times();
	eval {
		for (my $i = 0; $i < $select_limit; $i++) {
			$_[KERNEL]->select_read( *STDIN, 'whee' );
			$_[KERNEL]->select_read( *STDIN );
		}
	};
	if ( $@ ) {
		print "filehandle select_read on *STDIN FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_read STDIN', $elapsed, $select_limit/$elapsed );
		print "select_read STDIN times: @start_times @end_times\n";
	}

	$_[KERNEL]->yield( 'stdin_write' );

	return;
}

# How many times can we select/unselect WRITE a from STDIN filehandle per second?
sub poe_stdin_write {
	my $start = time();
	my @start_times = times();
	eval {
		for (my $i = 0; $i < $select_limit; $i++) {
			$_[KERNEL]->select_write( *STDIN, 'whee' );
			$_[KERNEL]->select_write( *STDIN );
		}
	};
	if ( $@ ) {
		print "filehandle select_write on *STDIN FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_write STDIN', $elapsed, $select_limit/$elapsed );
		print "select_write STDIN times: @start_times @end_times\n";
	}

	$_[KERNEL]->yield( 'myfh_read' );

	return;
}

# How many times can we select/unselect READ a real filehandle?
sub poe_myfh_read {
	# stupid, but we have to skip those tests
	if ( $eventloop eq 'Event_Lib' or $eventloop eq 'Tk' or $eventloop eq 'Prima' ) {
		print "SKIPPING MYFH tests on broken loop: $eventloop\n";
		$_[KERNEL]->yield( 'calls' );
		return;
	}

	open( MYFH, '+>', 'poebench' ) or die $!;
	my $start = time();
	my @start_times = times();
	eval {
		for (my $i = 0; $i < $select_limit; $i++) {
			$_[KERNEL]->select_read( *MYFH, 'whee' );
			$_[KERNEL]->select_read( *MYFH );
		}
	};
	if ( $@ ) {
		print "filehandle select_read on *MYFH FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_read MYFH', $elapsed, $select_limit/$elapsed );
		print "select_read MYFH times: @start_times @end_times\n";
	}

	close( MYFH ) or die $!;
	unlink( 'poebench' ) or die $!;

	$_[KERNEL]->yield( 'myfh_write' );

	return;
}

# How many times can we select/unselect WRITE a real filehandle?
sub poe_myfh_write {
	open( MYFH, '+>', 'poebench' ) or die $!;
	my $start = time();
	my @start_times = times();
	eval {
		for (my $i = 0; $i < $select_limit; $i++) {
			$_[KERNEL]->select_write( *MYFH, 'whee' );
			$_[KERNEL]->select_write( *MYFH );
		}
	};
	if ( $@ ) {
		print "filehandle select_write on *MYFH FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_write MYFH', $elapsed, $select_limit/$elapsed );
		print "select_write MYFH times: @start_times @end_times\n";
	}

	close( MYFH ) or die $!;
	unlink( 'poebench' ) or die $!;

	$_[KERNEL]->yield( 'calls' );

	return;
}

# How many times can we call a state?
sub poe_calls {
	my $start = time();
	my @start_times = times();
	for (my $i = 0; $i < $call_limit; $i++) {
		$_[KERNEL]->call( $_[SESSION], 'null' );
	}
	my $elapsed = time() - $start;
	my @end_times = times();
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $call_limit, 'calls', $elapsed, $call_limit/$elapsed );
	print "calls times: @start_times @end_times\n";

	$_[KERNEL]->yield( 'eventsquirt' );

	return;
}

# How many events can we squirt through POE, one at a time?
sub poe_eventsquirt {
	$_[HEAP]->{start} = time();
	$_[HEAP]->{starttimes} = [ times() ];
	$_[HEAP]->{yield_count} = $through_limit;
	$_[KERNEL]->yield( 'eventsquirt_done' );

	return;
}

sub poe_eventsquirt_done {
	if (--$_[HEAP]->{yield_count}) {
		$_[KERNEL]->yield( 'eventsquirt_done' );
	} else {
		my $elapsed = time() - $_[HEAP]->{start};
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $through_limit, 'single_posts', $elapsed, $through_limit/$elapsed );
		print "single_posts times: " . join( " ", @{ $_[HEAP]->{starttimes} } ) . " @end_times\n";
	}

	# reached end of tests!
	return;
}

# Get the memory footprint
sub dump_memory {
	print "\n\nMemory footprint:\n";
	open( MEMORY, '/proc/self/status' ) or die $!;
	while ( <MEMORY> ) {
		print;
	}
	close( MEMORY ) or die $!;

	return;
}

# print the time it took to execute this program
sub dump_times {
	my ($wall, $user, $system, $cuser, $csystem) = ( (time-$^T), times() );
	printf( ( "\n\n--- times ---\n" .
		"wall : %9.3f\n" .
		"user : %9.3f  cuser: %9.3f\n" .
		"sys  : %9.3f  csys : %9.3f\n"
		),
		$wall, $user, $cuser, $system, $csystem,
	);

	return;
}

# print the local Perl info
sub dump_perlinfo {
	print "\n\nRunning under perl binary: " . $^X . "\n";

	require Config;
	print Config::myconfig();

	return;
}

# print the local system information
sub dump_sysinfo {
	print "Running under machine: " . `uname -a` . "\n";

	# get cpuinfo
	print "Running under CPU:\n";
	open( CPUINFO, '/proc/cpuinfo' ) or die $!;
	while ( <CPUINFO> ) {
		print;
	}
	close( CPUINFO ) or die $!;

	# get meminfo
	print "Running under meminfo:\n";
	open( MEMINFO, '/proc/meminfo' ) or die $!;
	while ( <MEMINFO> ) {
		print;
	}
	close( MEMINFO ) or die $!;

	return;
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::SubProcess - Implements the actual POE benchmarks

=head1 SYNOPSIS

	perl -MPOE::Devel::Benchmarker::SubProcess -e 'benchmark()'

=head1 ABSTRACT

This package is responsible for implementing the guts of the benchmarks, and timing them.

=head2 EXPORT

Nothing.

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

