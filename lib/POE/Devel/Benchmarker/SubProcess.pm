# Declare our package
package POE::Devel::Benchmarker::SubProcess;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.05';

# set our compile-time stuff
BEGIN {
	# should we enable assertions?
	if ( defined $ARGV[1] and $ARGV[1] ) {
		## no critic
		eval "sub POE::Kernel::ASSERT_DEFAULT () { 1 }";
		eval "sub POE::Session::ASSERT_STATES () { 1 }";
		## use critic
	}

	# Compile a list of modules to hide
	my $hide = '';
	if ( defined $ARGV[0] ) {
		if ( $ARGV[0] ne 'XSPoll' ) {
			$hide .= ' POE/XS/Loop/Poll.pm';
		}
		if ( $ARGV[0] ne 'XSEPoll' ) {
			$hide .= ' POE/XS/Loop/EPoll.pm';
		}
	}

	# should we "hide" XS::Queue::Array?
	if ( defined $ARGV[3] and $ARGV[3] ) {
		$hide .= ' POE/XS/Queue/Array.pm';
	}

	# actually hide the modules!
	{
		## no critic
		eval "use Devel::Hide qw( $hide )";
		## use critic
	}
}

# Import Time::HiRes's time()
use Time::HiRes qw( time );

# load POE
use POE;
use POE::Session;
use POE::Wheel::SocketFactory;
use POE::Wheel::ReadWrite;
use POE::Filter::Line;
use POE::Driver::SysRW;

# autoflush, please!
use IO::Handle;
STDOUT->autoflush( 1 );

# import some stuff
use Socket qw( INADDR_ANY sockaddr_in );

# we need to compare versions
use version;

# load our utility stuff
use POE::Devel::Benchmarker::Utils qw( loop2realversion poeloop2load );

# init our global variables ( bad, haha )
# FIXME change this to a hash because it's becoming unwieldy with too many variables
my( $eventloop, $asserts, $lite_tests, $pocosession );
my( $post_limit, $alarm_limit, $alarm_add_limit, $session_limit, $select_limit, $through_limit, $call_limit, $start_limit, $sf_connects, $sf_stream );

# the main routine which will load everything + start
sub benchmark {
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

sub process_eventloop {
	# Get the desired mode
	$eventloop = $ARGV[0];

	# print out the loop info
	if ( ! defined $eventloop ) {
		die "Please supply an event loop!";
	} else {
		my $loop = poeloop2load( $eventloop );
		if ( ! defined $loop ) {
			$loop = $eventloop;
		}
		my $v = loop2realversion( $eventloop );
		if ( ! defined $v ) {
			$v = 'UNKNOWN';
		}
		print "Using master loop: $loop-$v\n";
	}

	return;
}

sub process_assertions {
	# Get the desired assert mode
	$asserts = $ARGV[1];

	if ( defined $asserts and $asserts ) {
		print "Using FULL Assertions!\n";
	} else {
		print "Using NO Assertions!\n";
	}

	return;
}

sub process_testmode {
	# get the desired test mode
	$lite_tests = $ARGV[2];

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
		$sf_connects		=  1_000;
		$sf_stream		=  1_000;
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
		$sf_connects		=  10_000;
		$sf_stream		=  10_000;
	}

	return;
}

sub process_xsqueue {
	# should we "hide" XS::Queue::Array?
	if ( defined $ARGV[3] and $ARGV[3] ) {
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
	# dump some misc info
	dump_perlinfo();
	dump_sysinfo();

	# run the startup test before we actually run POE
	bench_startup();

	# load the POE session + do the tests there
	bench_poe();

	# okay, dump our memory usage
	dump_pidinfo();

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
			'-Ipoedists/POE-' . $POE::VERSION,
			'-Ipoedists/POE-' . $POE::VERSION . '/lib',
			( defined $looploader ? "-M$looploader" : () ),
			'-MPOE',
			'-e',
			1,
		);
	}
	my @end_times = times();
	my $elapsed = time() - $start;
	printf( "\n\n% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $start_limit, 'startups', $elapsed, $start_limit/$elapsed );
	print "startups times: @start_times @end_times\n";

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

			'socketfactory'			=> \&poe_socketfactory,
			'socketfactory_start'		=> \&poe_socketfactory_start,
			'socketfactory_connects'	=> \&poe_socketfactory_connects,
			'socketfactory_stream'		=> \&poe_socketfactory_stream,
			'socketfactory_cleanup'		=> \&poe_socketfactory_cleanup,

			# misc states for test stuff
			'server_sf_connect'		=> \&poe_server_sf_connect,
			'server_sf_failure'		=> \&poe_server_sf_failure,
			'server_rw_input'		=> \&poe_server_rw_input,
			'server_rw_error'		=> \&poe_server_rw_error,

			'client_sf_connect'		=> \&poe_client_sf_connect,
			'client_sf_failure'		=> \&poe_client_sf_failure,
			'client_rw_input'		=> \&poe_client_rw_input,
			'client_rw_error'		=> \&poe_client_rw_error,
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
		print "SKIPPING br0ken alarm_adds because alarm_add() NOT SUPPORTED on this version of POE\n";
		print "SKIPPING br0ken alarm_clears because alarm_add() NOT SUPPORTED on this version of POE\n";
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
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $session_limit, 'session_creates', $elapsed, $session_limit/$elapsed );
	print "session_creates times: @start_times @end_times\n";

	$_[KERNEL]->yield( 'sessions_end' );
	$_[HEAP]->{start} = time();
	$_[HEAP]->{starttimes} = [ times() ];

	return;
}

sub poe_sessions_end {
	my $elapsed = time() - $_[HEAP]->{start};
	my @end_times = times();
	printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $session_limit, 'session_destroys', $elapsed, $session_limit/$elapsed );
	print "session_destroys times: " . join( " ", @{ $_[HEAP]->{starttimes} } ) . " @end_times\n";

	$_[KERNEL]->yield( 'stdin_read' );

	return;
}

# How many times can we select/unselect READ a from STDIN filehandle per second?
sub poe_stdin_read {
	# stupid, but we have to skip those tests
	if ( $eventloop eq 'Tk' or $eventloop eq 'Prima' ) {
		print "SKIPPING br0ken select_read_STDIN because eventloop doesn't work: $eventloop\n";
		print "SKIPPING br0ken select_write_STDIN because eventloop doesn't work: $eventloop\n";
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
		print "SKIPPING br0ken select_read_STDIN because FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_read_STDIN', $elapsed, $select_limit/$elapsed );
		print "select_read_STDIN times: @start_times @end_times\n";
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
		print "SKIPPING br0ken select_write_STDIN because FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_write_STDIN', $elapsed, $select_limit/$elapsed );
		print "select_write_STDIN times: @start_times @end_times\n";
	}

	$_[KERNEL]->yield( 'myfh_read' );

	return;
}

# How many times can we select/unselect READ a real filehandle?
sub poe_myfh_read {
	# stupid, but we have to skip those tests
	if ( $eventloop eq 'Event_Lib' or $eventloop eq 'Tk' or $eventloop eq 'Prima' ) {
		print "SKIPPING br0ken select_read_MYFH because eventloop doesn't work: $eventloop\n";
		print "SKIPPING br0ken select_write_MYFH because eventloop doesn't work: $eventloop\n";
		$_[KERNEL]->yield( 'calls' );
		return;
	}

	my $start = time();
	my @start_times = times();
	eval {
		open( my $fh, '+>', 'poebench' ) or die $!;
		for (my $i = 0; $i < $select_limit; $i++) {
			$_[KERNEL]->select_read( $fh, 'whee' );
			$_[KERNEL]->select_read( $fh );
		}
		close( $fh ) or die $!;
		unlink( 'poebench' ) or die $!;
	};
	if ( $@ ) {
		print "SKIPPING br0ken select_read_MYFH because FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_read_MYFH', $elapsed, $select_limit/$elapsed );
		print "select_read_MYFH times: @start_times @end_times\n";
	}

	$_[KERNEL]->yield( 'myfh_write' );

	return;
}

# How many times can we select/unselect WRITE a real filehandle?
sub poe_myfh_write {
	my $start = time();
	my @start_times = times();
	eval {
		open( my $fh, '+>', 'poebench' ) or die $!;
		for (my $i = 0; $i < $select_limit; $i++) {
			$_[KERNEL]->select_write( $fh, 'whee' );
			$_[KERNEL]->select_write( $fh );
		}
		close( $fh ) or die $!;
		unlink( 'poebench' ) or die $!;
	};
	if ( $@ ) {
		print "SKIPPING br0ken select_write_MYFH because FAILED: $@\n";
	} else {
		my $elapsed = time() - $start;
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $select_limit, 'select_write_MYFH', $elapsed, $select_limit/$elapsed );
		print "select_write_MYFH times: @start_times @end_times\n";
	}

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

		$_[KERNEL]->yield( 'socketfactory' );
	}

	return;
}

# tests socketfactory interactions
sub poe_socketfactory {
	# POE transitioned between Event to State on 0.19 for SocketFactory/ReadWrite
	# 0.20+ throws deprecation error :(
	$_[HEAP]->{'POE_naming'} = 'Event';
	if ( version->new( $POE::VERSION ) < version->new( '0.20' ) ) {
		$_[HEAP]->{'POE_naming'} = 'State';
	}

	# create the socketfactory server
	$_[HEAP]->{'SF'} = POE::Wheel::SocketFactory->new(
		'Port'		=> INADDR_ANY,
		'Address'	=> 'localhost',
		'Reuse'		=> 'yes',

		'Success' . $_[HEAP]->{'POE_naming'}	=> 'server_sf_connect',
		'Failure' . $_[HEAP]->{'POE_naming'}	=> 'server_sf_failure',
	);

	# be evil, and get the port for the client to connect to
	( $_[HEAP]->{'SF_port'}, undef ) = sockaddr_in( getsockname( $_[HEAP]->{'SF'}->[ POE::Wheel::SocketFactory::MY_SOCKET_HANDLE() ] ) );

	# start the connect tests
	$_[HEAP]->{'SF_counter'} = $sf_connects;
	$_[HEAP]->{'SF_mode'} = 'CONNECTS';
	$_[HEAP]->{'start'} = time();
	$_[HEAP]->{'starttimes'} = [ times() ];
	$_[KERNEL]->yield( 'socketfactory_connects' );

	return;
}

# handles SocketFactory connection
sub poe_server_sf_connect {
	# what test mode?
	if ( $_[HEAP]->{'SF_mode'} eq 'CONNECTS' ) {
		# simply discard this socket
	} elsif ( $_[HEAP]->{'SF_mode'} eq 'STREAM' ) {
		# convert it to ReadWrite
		my $wheel = POE::Wheel::ReadWrite->new(
			'Handle'	=> $_[ARG0],
			'Filter'	=> POE::Filter::Line->new,
			'Driver'	=> POE::Driver::SysRW->new,

			'Input' . $_[HEAP]->{'POE_naming'}	=> 'server_rw_input',
			'Error' . $_[HEAP]->{'POE_naming'}	=> 'server_rw_error',
		);

		# save it in our heap
		$_[HEAP]->{'RW'}->{ $wheel->ID } = $wheel;
	} else {
		die "unknown test mode";
	}

	return;
}

# handles SocketFactory errors
sub poe_server_sf_failure {
	# ARGH, we couldnt create listening socket
	print "SKIPPING br0ken socket_connects because we were unable to setup listening socket\n";
	print "SKIPPING br0ken socket_stream because we were unable to setup listening socket\n";

	$_[KERNEL]->yield( 'socketfactory_cleanup' );

	return;
}

# handles ReadWrite input
sub poe_server_rw_input {
	# what test mode?
	if ( $_[HEAP]->{'SF_mode'} eq 'CONNECTS' ) {
		# simply discard this data
	} elsif ( $_[HEAP]->{'SF_mode'} eq 'STREAM' ) {
		# send it back to the client!
		$_[HEAP]->{'RW'}->{ $_[ARG1] }->put( $_[ARG0] );
	} else {
		die "unknown test mode";
	}

	return;
}

# handles ReadWrite disconnects
sub poe_server_rw_error {
	# simply get rid of the wheel
	if ( exists $_[HEAP]->{'RW'}->{ $_[ARG3] } ) {
		# FIXME do we need this?
		eval {
			$_[HEAP]->{'RW'}->{ $_[ARG3] }->shutdown_input;
			$_[HEAP]->{'RW'}->{ $_[ARG3] }->shutdown_output;
		};

		delete $_[HEAP]->{'RW'}->{ $_[ARG3] };
	}

	return;
}

# starts the client connect tests
sub poe_socketfactory_connects {
	if (--$_[HEAP]->{'SF_counter'}) {
		# open a new client connection!
		$_[HEAP]->{'client_SF'} = POE::Wheel::SocketFactory->new(
			'RemoteAddress'	=> 'localhost',
			'RemotePort'	=> $_[HEAP]->{'SF_port'},

			'Success' . $_[HEAP]->{'POE_naming'}	=> 'client_sf_connect',
			'Failure' . $_[HEAP]->{'POE_naming'}	=> 'client_sf_failure',
		);
	} else {
		my $elapsed = time() - $_[HEAP]->{start};
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $sf_connects, 'socket_connects', $elapsed, $sf_connects/$elapsed );
		print "socket_connects times: " . join( " ", @{ $_[HEAP]->{starttimes} } ) . " @end_times\n";

		$_[KERNEL]->yield( 'socketfactory_stream' );
	}

	return;
}

# starts the client stream tests
sub poe_socketfactory_stream {
	# set the proper test mode
	$_[HEAP]->{'SF_mode'} = 'STREAM';

	# open a new client connection!
	$_[HEAP]->{'client_SF'} = POE::Wheel::SocketFactory->new(
		'RemoteAddress'	=> 'localhost',
		'RemotePort'	=> $_[HEAP]->{'SF_port'},

		'Success' . $_[HEAP]->{'POE_naming'}	=> 'client_sf_connect',
		'Failure' . $_[HEAP]->{'POE_naming'}	=> 'client_sf_failure',
	);

	return;
}

# the client connected to the server!
sub poe_client_sf_connect {
	# what test mode?
	if ( $_[HEAP]->{'SF_mode'} eq 'CONNECTS' ) {
		# simply discard this connection
		delete $_[HEAP]->{'client_SF'};

		# make another connection!
		$_[KERNEL]->yield( 'socketfactory_connects' );
	} elsif ( $_[HEAP]->{'SF_mode'} eq 'STREAM' ) {
		# convert it to ReadWrite
		my $wheel = POE::Wheel::ReadWrite->new(
			'Handle'	=> $_[ARG0],
			'Filter'	=> POE::Filter::Line->new,
			'Driver'	=> POE::Driver::SysRW->new,

			'Input' . $_[HEAP]->{'POE_naming'}	=> 'client_rw_input',
			'Error' . $_[HEAP]->{'POE_naming'}	=> 'client_rw_error',
		);

		# save it in our heap
		$_[HEAP]->{'client_RW'}->{ $wheel->ID } = $wheel;

		# begin the STREAM test!
		$_[HEAP]->{'SF_counter'} = $sf_stream;
		$_[HEAP]->{'SF_data'} = 'x' x ( $sf_stream / 10 );	# set a reasonable-sized chunk of data
		$_[HEAP]->{'start'} = time();
		$_[HEAP]->{'starttimes'} = [ times() ];

		$wheel->put( $_[HEAP]->{'SF_data'} );
	} else {
		die "unknown test mode";
	}

	return;
}

# handles SocketFactory errors
sub poe_client_sf_failure {
	# ARGH, we couldnt create connecting socket
	if ( $_[HEAP]->{'SF_mode'} eq 'CONNECTS' ) {
		print "SKIPPING br0ken socket_connects because we were unable to setup connecting socket\n";

		# go to stream test
		$_[KERNEL]->yield( 'socketfactory_stream' );
	} elsif ( $_[HEAP]->{'SF_mode'} eq 'STREAM' ) {
		print "SKIPPING br0ken socket_stream because we were unable to setup connecting socket\n";

		$_[KERNEL]->yield( 'socketfactory_cleanup' );
	}

	return;
}

# handles ReadWrite input
sub poe_client_rw_input {
	if (--$_[HEAP]->{'SF_counter'}) {
		# send it back to the server!
		$_[HEAP]->{'client_RW'}->{ $_[ARG1] }->put( $_[ARG0] );
	} else {
		my $elapsed = time() - $_[HEAP]->{start};
		my @end_times = times();
		printf( "% 9d %-20.20s in % 9.3f seconds (% 11.3f per second)\n", $sf_stream, 'socket_stream', $elapsed, $sf_stream/$elapsed );
		print "socket_stream times: " . join( " ", @{ $_[HEAP]->{starttimes} } ) . " @end_times\n";

		$_[KERNEL]->yield( 'socketfactory_cleanup' );

	}

	return;
}

# handles ReadWrite disconnect
sub poe_client_rw_error {
	# simply get rid of the wheel
	if ( exists $_[HEAP]->{'client_RW'}->{ $_[ARG3] } ) {
		# FIXME do we need this?
		eval {
			$_[HEAP]->{'client_RW'}->{ $_[ARG3] }->shutdown_input;
			$_[HEAP]->{'client_RW'}->{ $_[ARG3] }->shutdown_output;
		};

		delete $_[HEAP]->{'client_RW'}->{ $_[ARG3] };
	}

	return;
}

# all done with the socketfactory tests
sub poe_socketfactory_cleanup {
	# do cleanup
	delete $_[HEAP]->{'SF'} if exists $_[HEAP]->{'SF'};
	delete $_[HEAP]->{'RW'} if exists $_[HEAP]->{'RW'};
	delete $_[HEAP]->{'client_SF'} if exists $_[HEAP]->{'client_SF'};
	delete $_[HEAP]->{'client_RW'} if exists $_[HEAP]->{'client_RW'};

	# XXX all done with tests!
	return;
}

# Get the memory footprint
sub dump_pidinfo {
	my $ret = open( my $fh, '<', '/proc/self/status' );
	if ( defined $ret ) {
		while ( <$fh> ) {
			chomp;
			if ( $_ ne '' ) {
				print "pidinfo: $_\n";
			}
		}
		close( $fh ) or die $!;
	} else {
		print "UNABLE TO GET /proc/self/status\n";
	}

	return;
}

# print the local Perl info
sub dump_perlinfo {
	print "Running under perl binary: '" . $^X . "' v" . sprintf( "%vd", $^V ) . "\n";

	require Config;
	my $config = Config::myconfig();
	foreach my $l ( split( /\n/, $config ) ) {
		print "perlconfig: $l\n";
	}

	return;
}

# print the local system information
sub dump_sysinfo {
	print "Running under machine: " . `uname -a` . "\n";

	# get cpuinfo
	my $ret = open( my $fh, '<', '/proc/cpuinfo' );
	if ( defined $ret ) {
		while ( <$fh> ) {
			chomp;
			if ( $_ ne '' ) {
				print "cpuinfo: $_\n";
			}
		}
		close( $fh ) or die $!;
	} else {
		print "UNABLE TO GET /proc/cpuinfo\n";
	}

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

=head1 EXPORT

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

