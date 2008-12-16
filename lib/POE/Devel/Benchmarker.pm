# Declare our package
package POE::Devel::Benchmarker;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.05';

# auto-export the only sub we have
use base qw( Exporter );
our @EXPORT = qw( benchmark );

# we need hires times
use Time::HiRes qw( time );

# Import what we need from the POE namespace
use POE qw( Session Filter::Line Wheel::Run );
use base 'POE::Session::AttributeBased';

# load comparison stuff
use version;

# use the power of YAML
use YAML::Tiny;

# Load our stuff
use POE::Devel::Benchmarker::GetInstalledLoops;
use POE::Devel::Benchmarker::Utils qw( poeloop2load knownloops generateTestfile );
use POE::Devel::Benchmarker::Analyzer;

# Actually run the tests!
sub benchmark {
	my $options = shift;

	# set default options
	my $lite_tests = 1;
	my $quiet_mode = 0;
	my $forceloops = undef;	# default to autoprobe all
	my $forcepoe = undef;	# default to all found POE versions in poedists/
	my $forcenoxsqueue = 0;	# default to try and load it
	my $forcenoasserts = 0;	# default is to run it
	my $freshstart = 0;	# always resume where we left off

	# process our options
	if ( defined $options and ref $options and ref( $options ) eq 'HASH' ) {
		# process YES for freshstart
		if ( exists $options->{'freshstart'} ) {
			if ( $options->{'freshstart'} ) {
				$freshstart = 1;
			}
			delete $options->{'freshstart'};
		}

		# process NO for XS::Queue::Array
		if ( exists $options->{'noxsqueue'} ) {
			if ( $options->{'noxsqueue'} ) {
				$forcenoxsqueue = 1;
			}
			delete $options->{'noxsqueue'};
		}

		# process NO for ASSERT
		if ( exists $options->{'noasserts'} ) {
			if ( $options->{'noasserts'} ) {
				$forcenoasserts = 1;
			}
			delete $options->{'noasserts'};
		}

		# process LITE tests
		if ( exists $options->{'litetests'} ) {
			if ( $options->{'litetests'} ) {
				$lite_tests = 1;
			} else {
				$lite_tests = 0;
			}
			delete $options->{'litetests'};
		}

		# process quiet mode
		if ( exists $options->{'quiet'} ) {
			if ( $options->{'quiet'} ) {
				$quiet_mode = 1;
			} else {
				$quiet_mode = 0;
			}
			delete $options->{'quiet'};
		}

		# process forceloops
		if ( exists $options->{'loop'} and defined $options->{'loop'} ) {
			if ( ! ref $options->{'loop'} ) {
				# split it via CSV
				$forceloops = [ split( /,/, $options->{'loop'} ) ];
				foreach ( @$forceloops ) {
					$_ =~ s/^\s+//; $_ =~ s/\s+$//;
				}
			} else {
				# treat it as array
				$forceloops = $options->{'loop'};
			}

			# check for !loop modules
			my @noloops;
			foreach my $l ( @$forceloops ) {
				if ( $l =~ /^\!/ ) {
					push( @noloops, substr( $l, 1 ) );
				}
			}
			if ( scalar @noloops ) {
				# replace the forceloops with ALL known, then subtract noloops from it
				my %bad;
				@bad{@noloops} = () x @noloops;
				@$forceloops = grep { !exists $bad{$_} } @{ knownloops() };
			}

			delete $options->{'loop'};
		}

		# process the poe versions
		if ( exists $options->{'poe'} and defined $options->{'poe'} ) {
			if ( ! ref $options->{'poe'} ) {
				# split it via CSV
				$forcepoe = [ split( /,/, $options->{'poe'} ) ];
				foreach ( @$forcepoe ) {
					$_ =~ s/^\s+//; $_ =~ s/\s+$//;
				}
			} else {
				# treat it as array
				$forcepoe = $options->{'poe'};
			}

			delete $options->{'poe'};
		}

		# unknown options!
		if ( scalar keys %$options ) {
			warn "[BENCHMARKER] Unknown options present in arguments: " . keys %$options;
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
			# misc stuff
			'quiet_mode'		=> $quiet_mode,

			# override our testing behavior
			'lite_tests'		=> $lite_tests,
			'forceloops'		=> $forceloops,
			'forcepoe'		=> $forcepoe,
			'forcenoxsqueue'	=> $forcenoxsqueue,
			'forcenoasserts'	=> $forcenoasserts,
			'freshstart'		=> $freshstart,
		},
	);

	# Fire 'er up!
	POE::Kernel->run();
	return;
}

# Starts up our session
sub _start : State {
	# okay, get all the dists we can!
	my @versions;
	if ( opendir( DISTS, 'poedists' ) ) {
		foreach my $d ( readdir( DISTS ) ) {
			if ( $d =~ /^POE\-(.+)$/ and $d !~ /\.tar\.gz$/ ) {
				# FIXME skip POE < 0.13 because I can't get it to work
				my $ver = version->new( $1 );
				if ( $ver > version->new( '0.12' ) ) {
					push( @versions, $ver );
				}
			}
		}
		closedir( DISTS ) or die $!;
	} else {
		print "[BENCHMARKER] Unable to open 'poedists' for reading: $!\n";
		return;
	}

	# should we munge the versions list?
	if ( defined $_[HEAP]->{'forcepoe'} ) {
		# check for !poe versions
		my @nopoe;
		foreach my $p ( @{ $_[HEAP]->{'forcepoe'} } ) {
			if ( $p =~ /^\!/ ) {
				push( @nopoe, substr( $p, 1 ) );
			}
		}
		if ( scalar @nopoe ) {
			# remove the nopoe versions from the found
			my %bad;
			@bad{@nopoe} = () x @nopoe;
			@versions = grep { !exists $bad{$_->stringify} } @versions;
		} else {
			# make sure the @versions contains only what we specified
			my %good;
			@good{ @{ $_[HEAP]->{'forcepoe'} } } = () x @{ $_[HEAP]->{'forcepoe'} };
			@versions = grep { exists $good{$_->stringify} } @versions;
		}
	}

	# sanity
	if ( ! scalar @versions ) {
		print "[BENCHMARKER] Unable to find any POE version in the 'poedists' directory!\n";
		return;
	}

	# set our alias
	$_[KERNEL]->alias_set( 'Benchmarker' );

	# sanely handle some signals
	$_[KERNEL]->sig( 'INT', 'handle_kill' );
	$_[KERNEL]->sig( 'TERM', 'handle_kill' );

	# okay, go through all the dists in version order ( from newest to oldest )
	@versions = sort { $b <=> $a } @versions;

	# Store the versions in our heap
	$_[HEAP]->{'VERSIONS'} = \@versions;

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Detected available POE versions -> " . join( " ", @versions ) . "\n";
	}

	# First of all, we need to find out what loop libraries are installed
	getPOEloops( $_[HEAP]->{'quiet_mode'}, $_[HEAP]->{'forceloops'} );

	return;
}

sub _stop : State {
	# tell the wheel to kill itself
	if ( defined $_[HEAP]->{'WHEEL'} ) {
		$_[HEAP]->{'WHEEL'}->kill( 9 );
		undef $_[HEAP]->{'WHEEL'};
	}

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "\n[BENCHMARKER] Shutting down...\n";
	}

	return;
}

# misc POE handlers
sub _child : State {
	return;
}
sub handle_kill : State {
	return;
}

# we received list of loops from GetInstalledLoops
sub found_loops : State {
	$_[HEAP]->{'installed_loops'} = [ sort { $a cmp $b } @{ $_[ARG0] } ];

	# sanity check
	if ( scalar @{ $_[HEAP]->{'installed_loops'} } == 0 ) {
		print "[BENCHMARKER] Detected no available POE::Loop, check your configuration?!?\n";
		return;
	}

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Detected available POE::Loops -> " . join( " ", @{ $_[HEAP]->{'installed_loops'} } ) . "\n";
	}

	# Okay, do we have XS::Queue installed?
	if ( ! $_[HEAP]->{'forcenoxsqueue'} ) {
		eval { require POE::XS::Queue::Array };
		if ( $@ ) {
			$_[HEAP]->{'forcenoxsqueue'} = 1;
		}
	}

	# Fire up the analyzer
	initAnalyzer( $_[HEAP]->{'quiet_mode'} );

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[BENCHMARKER] Starting the benchmarks!" .
			( $_[HEAP]->{'forcenoxsqueue'} ? ' Skipping XS::Queue Tests!' : '' ) .
			( $_[HEAP]->{'forcenoasserts'} ? ' Skipping ASSERT Tests!' : '' ) .
			"\n";
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
		if ( $_[HEAP]->{'forcenoasserts'} ) {
			$_[HEAP]->{'assertions'} = [ qw( 0 ) ];
		} else {
			$_[HEAP]->{'assertions'} = [ qw( 0 1 ) ];
		}
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
		if ( $_[HEAP]->{'forcenoxsqueue'} ) {
			$_[HEAP]->{'noxsqueue'} = [ qw( 1 ) ];
		} else {
			$_[HEAP]->{'noxsqueue'} = [ qw( 0 1 ) ];
		}
		$_[KERNEL]->yield( 'bench_xsqueue' );
	}

	return;
}

# runs test with or without xsqueue
sub bench_xsqueue : State {
	# select our current noxsqueue state
	$_[HEAP]->{'current_noxsqueue'} = shift @{ $_[HEAP]->{'noxsqueue'} };

	# are we done?
	if ( ! defined $_[HEAP]->{'current_noxsqueue'} ) {
		# yay, go back to the assert handler
		$_[KERNEL]->yield( 'bench_asserts' );
	} else {
		# do some careful analysis
		$_[KERNEL]->yield( 'bench_checkprevioustest' );
	}

	return;
}

# Checks to see if this test was run in the past
sub bench_checkprevioustest : State {
	# okay, do we need to check and see if we already did this test?
	if ( ! $_[HEAP]->{'freshstart'} ) {
		# determine the file used
		my $file = generateTestfile( $_[HEAP] );

		# does it exist?
		if ( -e "results/$file.yml" and -f _ and -s _ ) {
			# okay, sanity check it
			my $yaml = YAML::Tiny->read( "results/$file.yml" );
			if ( defined $yaml ) {
				# inrospect it!
				my $isvalid = 0;
				eval {
					# simple sanity check: the "x_bench" param is at the end of the YML, so if it loads fine we know it's there
					if ( exists $yaml->[0]->{'x_bench'} ) {
						# version must at least match us
						$isvalid = ( $yaml->[0]->{'x_bench'} eq $POE::Devel::Benchmarker::VERSION ? 1 : 0 );
					} else {
						$isvalid = undef;
					}
				};
				if ( $isvalid ) {
					# yay, this test is A-OK!
					$_[KERNEL]->yield( 'bench_xsqueue' );
					return;
				} else {
					# was it truncated?
					if ( ! defined $isvalid ) {
						if ( ! $_[HEAP]->{'quiet_mode'} ) {
							print "\n[BENCHMARKER] YAML file($file) from previous test was corrupt!\n";
						}
					}
				}
			} else {
				if ( ! $_[HEAP]->{'quiet_mode'} ) {
					print "\n[BENCHMARKER] Unable to load YAML file($file) from previous test run: " . YAML::Tiny->errstr . "\n";
				}
			}
		}
	}

	# could not find previous file or FRESHSTART, proceed normally
	$_[KERNEL]->yield( 'create_subprocess' );

	return;
}

# actually runs the subprocess
sub create_subprocess : State {
	# Okay, start testing this specific combo!
	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "\n Testing " . generateTestfile( $_[HEAP] ) . "...";
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
						$_[HEAP]->{'current_loop'},
						$_[HEAP]->{'current_assertions'},
						$_[HEAP]->{'lite_tests'},
						$_[HEAP]->{'current_noxsqueue'},
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
		# 5min timeout is 5x my average runs on a 1.2ghz core2duo so it should be good enough
		$_[HEAP]->{'TIMER'} = $_[KERNEL]->delay_set( 'test_timedout' => 60 * 5 );
	} else {
		# 30min timeout is 2x my average runs on a 1.2ghz core2duo so it should be good enough
		$_[HEAP]->{'TIMER'} = $_[KERNEL]->delay_set( 'test_timedout' => 60 * 30 );
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

	# skip empty lines
	if ( $input ne '' ) {
		# save it!
		$_[HEAP]->{'current_data'} .= '!STDERR: ' . $input . "\n";
	}
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
		print "\n[BENCHMARKER] Wheel::Run got an $operation error $errnum: $errstr\n";
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
		print " Test Timed Out!";
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
	my $file = generateTestfile( $_[HEAP] );
	if ( open( my $fh, '>', "results/$file" ) ) {
		print $fh "STARTTIME: " . $_[HEAP]->{'current_starttime'} . " -> TIMES " . join( " ", @{ $_[HEAP]->{'current_starttimes'} } ) . "\n";
		print $fh "$file\n";
		print $fh $_[HEAP]->{'current_data'} . "\n";
		if ( $_[HEAP]->{'test_timedout'} ) {
			print $fh "\nTEST TERMINATED DUE TO TIMEOUT\n";
		}
		print $fh "ENDTIME: " . $_[HEAP]->{'current_endtime'} . " -> TIMES " . join( " ", @{ $_[HEAP]->{'current_endtimes'} } ) . "\n";
		close( $fh ) or die $!;
	} else {
		print "\n[BENCHMARKER] Unable to open results/$file for writing -> $!\n";
	}

	# Send the data to the Analyzer to process
	$_[KERNEL]->post( 'Benchmarker::Analyzer', 'analyze', {
		'poe'		=> {
			'v'	=> $_[HEAP]->{'current_version'}->stringify,	# YAML::Tiny doesn't like version objects :(
			'loop'	=> 'POE::Loop::' . $_[HEAP]->{'current_loop'},
		},
		't'		=> {
			's_ts'	=> $_[HEAP]->{'current_starttime'},
			'e_ts'	=> $_[HEAP]->{'current_endtime'},
			'd'	=> $_[HEAP]->{'current_endtime'} - $_[HEAP]->{'current_starttime'},
			's_t'	=> [ @{ $_[HEAP]->{'current_starttimes'} } ],
			'e_t'	=> [ @{ $_[HEAP]->{'current_endtimes'} } ],
		},
		'raw'		=> $_[HEAP]->{'current_data'},
		'test'		=> $file,
		'x_bench'	=> $POE::Devel::Benchmarker::VERSION,
		( $_[HEAP]->{'test_timedout'} ? ( 'timedout' => 1 ) : () ),
		( $_[HEAP]->{'lite_tests'} ? ( 'litetests' => 1 ) : () ),
		( $_[HEAP]->{'current_assertions'} ? ( 'asserts' => 1 ) : () ),
		( $_[HEAP]->{'current_noxsqueue'} ? ( 'noxsqueue' => 1 ) : () ),
	} );

	# process the next test
	$_[KERNEL]->yield( 'bench_xsqueue' );

	return;
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker - Benchmarking POE's performance ( acts more like a smoker )

=head1 SYNOPSIS

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker -e 'benchmark()'

=head1 ABSTRACT

This package of tools is designed to benchmark POE's performace across different
configurations. The current "tests" are:

=over 4

=item Events

posts: This tests how long it takes to post() N times

dispatches: This tests how long it took to dispatch/deliver all the posts enqueued in the "posts" test

single_posts: This tests how long it took to yield() between 2 states for N times

calls: This tests how long it took to call() N times

=item Alarms

alarms: This tests how long it took to add N alarms via alarm(), overwriting each other

alarm_adds: This tests how long it took to add N alarms via alarm_add()

alarm_clears: This tests how long it took to clear all alarms set in the "alarm_adds" test

NOTE: alarm_add is not available on all versions of POE!

=item Sessions

session_creates: This tests how long it took to create N sessions

session_destroys: This tests how long it took to destroy all sessions created in the "session_creates" test

=item Filehandles

select_read_STDIN: This tests how long it took to toggle select_read N times on STDIN

select_write_STDIN: This tests how long it took to toggle select_write N times on STDIN

select_read_MYFH: This tests how long it took to toggle select_read N times on a real filehandle

select_write_MYFH: This tests how long it took to toggle select_write N times on a real filehandle

NOTE: The MYFH tests don't include the time it took to open()/close() the file :)

=item Sockets

socket_connects: This tests how long it took to connect+disconnect to a SocketFactory server via localhost

socket_stream: This tests how long it took to send N chunks of data in a "ping-pong" fashion between the server and client

=item POE startup time

startups: This tests how long it took to start + close N instances of POE+Loop without any sessions/etc via system()

=item POE Loops

This is actually a "super" test where all of the specific tests is ran against various POE::Loop::XYZ/FOO for comparison

=item POE Assertions

This is actually a "super" test where all of the specific tests is ran against POE with/without assertions enabled

NOTE: Not all versions of POE support assertions!

=item POE::XS::Queue::Array

This is actually a "super" test where all of the specific tests is ran against POE with XS goodness enabled/disabled

NOTE: Not all versions of POE support XS::Queue::Array!

=back

=head1 DESCRIPTION

This module is poorly documented now. Please give me some time to properly document it over time :)

=head2 INSTALLATION

Here's a simple outline to get you up to speed quickly. ( and smoking! )

=over 4

=item Install CPAN package + dependencies

Download+install the POE::Devel::Benchmarker package from CPAN

	apoc@apoc-x300:~$ cpanp -i POE::Devel::Benchmarker

=item Setup initial directories

Go anywhere, and create the "parent" directory where you'll be storing test results + stuff. For this example,
I have chosen to use ~/poe-benchmarker:

	apoc@apoc-x300:~$ mkdir poe-benchmarker
	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ mkdir poedists results images
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker::GetPOEdists -e 'getPOEdists( 1 )'

	( go get a coffee while it downloads if you're on a slow link, ha! )

=item Let 'er rip!

At this point you can start running the benchmark!

NOTE: the Benchmarker expects everything to be in the "local" directory!

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker -e 'benchmark()'

	( go sleep or something, this will take a while! )

=back

=head2 BENCHMARKING

On startup the Benchmarker will look in the "poedists" directory and load all the distributions it sees untarred there. Once
that is done it will begin autoprobing for available POE::Loop packages. Once it determines what's available, it will begin
the benchmarks.

As the Benchmarker goes through the combinations of POE + Eventloop + Assertions + XS::Queue it will dump data into
the results directory. The Analyzer module also dumps YAML output in the same place, with the suffix of ".yml"

This module exposes only one subroutine, the benchmark() one. You can pass a hashref to it to set various options. Here is
a list of the valid options:

=over 4

=item freshstart => boolean

This will tell the Benchmarker to ignore any previous test runs stored in the 'results' directory.

	benchmark( { freshstart => 1 } );

default: false

=item noxsqueue => boolean

This will tell the Benchmarker to force the unavailability of POE::XS::Queue::Array and skip those tests.

NOTE: The Benchmarker will set this automatically if it cannot load the module!

	benchmark( { noxsqueue => 1 } );

default: false

=item noasserts => boolean

This will tell the Benchmarker to not run the ASSERT tests.

	benchmark( { noasserts => 1 } );

default: false

=item litetests => boolean

This enables the "lite" tests which will not take up too much time.

	benchmark( { litetests => 0 } );

default: true

=item quiet => boolean

This enables quiet mode which will not print anything to the console except for errors.

	benchmark( { 'quiet' => 1 } );

default: false

=item loop => csv list or array

This overrides the built-in loop detection algorithm which searches for all known loops.

There is some "magic" here where you can put a negative sign in front of a loop and we will NOT run that.

NOTE: Capitalization is important!

	benchmark( { 'loop' => 'IO_Poll,Select' } );	# runs only IO::Poll and Select
	benchmark( { 'loop' => [ qw( Tk Gtk ) ] } );	# runs only Tk and Gtk
	benchmark( { 'loop' => '-Tk' } );		# runs all available loops EXCEPT for TK

Known loops: Event_Lib EV Glib Prima Gtk Kqueue Tk Select IO_Poll

=item poe => csv list or array

This overrides the built-in POE version detection algorithm which pulls the POE versions from the 'poedists' directory.

There is some "magic" here where you can put a negative sign in front of a version and we will NOT run that.

NOTE: The Benchmarker will ignore versions that wasn't found in the directory!

	benchmark( { 'poe' => '0.35,1.003' } );			# runs on 0.35 and 1.003
	benchmark( { 'poe' => [ qw( 0.3009 0.12 ) ] } );	# runs on 0.3009 and 0.12
	benchmark( { 'poe' => '-0.35' } );			# runs ALL tests except 0.35

=back

=head2 ANALYZING RESULTS

Please look at the pretty charts generated by the L<POE::Devel::Benchmarker::Imager> module.

=head1 EXPORT

Automatically exports the benchmark() subroutine.

=head1 TODO

=over 4

=item Perl version smoking

We should be able to run the benchmark over different Perl versions. This would require some fiddling with our
layout + logic. It's not that urgent because the workaround is to simply execute the benchmarker under a different
perl binary. It's smart enough to use $^X to be consistent across tests/subprocesses :)

=item Select the EV backend

	<Khisanth> and if you are benchmarking, try it with POE using EV with EV using Glib? :P
	<Apocalypse> I'm not sure how to configure the EV "backend" yet
	<Apocalypse> too much docs for me to read hah
	<Khisanth> Apocalypse: use EV::Glib; use Glib; use POE; :)

=item Be smarter in smoking timeouts

Currently we depend on the litetests option and hardcode some values including the timeout. If your machine is incredibly
slow, there's a chance that it could timeout unnecessarily. Please look at the outputs and check to see if there are unusual
failures, and inform me.

Also, some loops perform badly and take almost forever! /me glares at Gtk...

=item More benchmarks!

As usual, me and the crowd in #poe have plenty of ideas for tests. We'll be adding them over time, but if you have an idea please
drop me a line and let me know!

dngor said there was some benchmarks in the POE svn under trunk/queue...

Tapout contributed a script that tests HTTP performance, let's see if it deserves to be in the suite :)

I added the preliminary socket tests, we definitely should expand it seeing how many people use POE for networking...

=item Add SQLite/DBI/etc support to the Analyzer

It would be nice if we could have a local SQLite db to dump our stats into. This would make arbitrary reports much easier than
loading raw YAML files and trying to make sense of them, ha! Also, this means somebody can do the smoking and send the SQLite
db to another person to generate the graphs, cool!

=item Kqueue loop support

As I don't have access to a *BSD box, I cannot really test this. Furthermore, it isn't clear on how I can force/unload this
module from POE...

=item Wx loop support

I have Wx installed, but it doesn't work. Obviously I don't know how to use Wx ;)

If you have experience, please drop me a line on how to do the "right" thing to get Wx loaded under POE. Here's the error:

	Can't call method "MainLoop" on an undefined value at /usr/local/share/perl/5.8.8/POE/Loop/Wx.pm line 91.

=item XS::Loop support

The POE::XS::Loop::* modules theoretically could be tested too. However, they will only work in POE >= 1.003! This renders
the concept somewhat moot. Maybe, after POE has progressed some versions we can implement this...

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
