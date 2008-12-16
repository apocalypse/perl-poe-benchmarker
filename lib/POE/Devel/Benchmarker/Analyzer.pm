# Declare our package
package POE::Devel::Benchmarker::Analyzer;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.05';

# auto-export the only sub we have
use base qw( Exporter );
our @EXPORT = qw( initAnalyzer );

# Import what we need from the POE namespace
use POE qw( Session );
use base 'POE::Session::AttributeBased';

# use the power of YAML
use YAML::Tiny qw( Dump );

# Load the utils
use POE::Devel::Benchmarker::Utils qw( beautify_times );

# fires up the engine
sub initAnalyzer {
	my $quiet_mode = shift;

	# create our session!
	POE::Session->create(
		__PACKAGE__->inline_states(),
		'heap'	=>	{
			'quiet_mode'	=> $quiet_mode,
		},
	);
}

# Starts up our session
sub _start : State {
	# set our alias
	$_[KERNEL]->alias_set( 'Benchmarker::Analyzer' );

	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[ANALYZER] Starting up...\n";
	}

	return;
}

sub _stop : State {
	if ( ! $_[HEAP]->{'quiet_mode'} ) {
		print "[ANALYZER] Shutting down...\n";
	}

	return;
}
sub _child : State {
	return;
}

sub analyze : State {
	# get the data
	my $test = $_[ARG0];

	# clean up the times() stuff
	$test->{'t'}->{'t'} = beautify_times(
		join( " ", @{ delete $test->{'t'}->{'s_t'} } ) .
		" " .
		join( " ", @{ delete $test->{'t'}->{'e_t'} } )
	);

	# setup the perl version
	$test->{'perl'}->{'v'} = sprintf( "%vd", $^V );

	# Okay, break it down into our data struct
	$test->{'metrics'} = {};
	my $d = $test->{'metrics'};
	my @unknown;
	foreach my $l ( split( /(?:\n|\r)/, $test->{'raw'} ) ) {
		# skip empty lines
		if ( $l eq '' ) { next }

		# usual test benchmark output
		#        10 startups             in     0.885 seconds (     11.302 per second)
		#     10000 posts                in     0.497 seconds (  20101.112 per second)
		if ( $l =~ /^\s+\d+\s+(\w+)\s+in\s+([\d\.]+)\s+seconds\s+\(\s+([\d\.]+)\s+per\s+second\)$/ ) {
			$d->{ $1 }->{'d'} = $2;		# duration in seconds
			$d->{ $1 }->{'i'} = $3;		# iterations per second

		# usual test benchmark times output
		# startup times: 0.1 0 0 0 0.1 0 0.76 0.09
		} elsif ( $l =~ /^(\w+)\s+times:\s+(.+)$/ ) {
			$d->{ $1 }->{'t'} = beautify_times( $2 );	# the times hash

		# parse the memory footprint stuff
		} elsif ( $l =~ /^pidinfo:\s+(.+)$/ ) {
			# what should we analyze?
			my $pidinfo = $1;

			# VmPeak:	   16172 kB
			if ( $pidinfo =~ /^VmPeak:\s+(.+)$/ ) {
				$test->{'pid'}->{'vmpeak'} = $1;

			# voluntary_ctxt_switches:	10
			} elsif ( $pidinfo =~ /^voluntary_ctxt_switches:\s+(.+)$/ ) {
				$test->{'pid'}->{'vol_ctxt'} = $1;

			# nonvoluntary_ctxt_switches:	1221
			} elsif ( $pidinfo =~ /^nonvoluntary_ctxt_switches:\s+(.+)$/ ) {
				$test->{'pid'}->{'nonvol_ctxt'} = $1;

			} else {
				# ignore the rest of the fluff
			}
		# parse the perl binary stuff
		} elsif ( $l =~ /^perlconfig:\s+(.+)$/ ) {
			# what should we analyze?
			my $perlconfig = $1;

			# ignore the fluff ( not needed now... )

		# parse the CPU info
		} elsif ( $l =~ /^cpuinfo:\s+(.+)$/ ) {
			# what should we analyze?
			my $cpuinfo = $1;

			# FIXME if this is on a multiproc system, we will overwrite the data per processor ( harmless? )

			# cpu MHz		: 1201.000
			if ( $cpuinfo =~ /^cpu\s+MHz\s+:\s+(.+)$/ ) {
				$test->{'cpu'}->{'mhz'} = $1;

			# model name	: Intel(R) Core(TM)2 Duo CPU     L7100  @ 1.20GHz
			} elsif ( $cpuinfo =~ /^model\s+name\s+:\s+(.+)$/ ) {
				$test->{'cpu'}->{'name'} = $1;

			# bogomips	: 2397.58
			} elsif ( $cpuinfo =~ /^bogomips\s+:\s+(.+)$/ ) {
				$test->{'cpu'}->{'bogo'} = $1;

			} else {
				# ignore the rest of the fluff
			}

		# data that we can safely throw away
		} elsif ( 	$l eq 'Using NO Assertions!' or
				$l eq 'Using FULL Assertions!' or
				$l eq 'Using the LITE tests' or
				$l eq 'Using the HEAVY tests' or
				$l eq 'DISABLING POE::XS::Queue::Array' or
				$l eq '!STDERR: Devel::Hide hides POE/XS/Queue/Array.pm' or
				$l eq 'LETTING POE find POE::XS::Queue::Array' or
				$l eq 'UNABLE TO GET /proc/self/status' or
				$l eq 'UNABLE TO GET /proc/cpuinfo' or
				$l eq '!STDERR: POE::Kernel\'s run() method was never called.' or	# to ignore old POEs that threw this warning
				$l eq 'TEST TERMINATED DUE TO TIMEOUT' ) {
			# ignore them

		# parse the perl binary stuff
		} elsif ( $l =~ /^Running\s+under\s+perl\s+binary:\s+(.+)$/ ) {
			$test->{'perl'}->{'binary'} = $1;

		# the master loop version ( what the POE::Loop::XYZ actually uses )
		# Using loop: EV-3.49
		} elsif ( $l =~ /^Using\s+master\s+loop:\s+(.+)$/ ) {
			$test->{'poe'}->{'loop_m'} = $1;

		# the real POE version that was loaded
		# Using POE-1.001
		} elsif ( $l =~ /^Using\s+POE-(.+)$/ ) {
			$test->{'poe'}->{'v_real'} = $1;

		# the various queue/loop modules we loaded
		# POE is using: POE::XS::Queue::Array v0.005
		# POE is using: POE::Queue v1.2328
		# POE is using: POE::Loop::EV v0.06
		} elsif ( $l =~ /^POE\s+is\s+using:\s+([^\s]+)\s+v(.+)$/ ) {
			$test->{'poe'}->{'modules'}->{ $1 } = $2;

		# get the uname info
		# Running under machine: Linux apoc-x300 2.6.24-21-generic #1 SMP Tue Oct 21 23:43:45 UTC 2008 i686 GNU/Linux
		} elsif ( $l =~ /^Running\s+under\s+machine:\s+(.+)$/ ) {
			$test->{'uname'} = $1;

		# parse the SKIP tests
		# SKIPPING MYFH tests on broken loop: Event_Lib
		# SKIPPING STDIN tests on broken loop: Tk
		} elsif ( $l =~ /^SKIPPING\s+(\w+)\s+tests\s+on\s+broken/ ) {
			my $fh = $1;

			# nullify the data struct for that
			foreach my $type ( qw( select_read select_write ) ) {
				$d->{ $type . $fh }->{'d'} = undef;
				$d->{ $type . $fh }->{'t'} = undef;
				$d->{ $type . $fh }->{'i'} = undef;
			}

		# parse the FH/STDIN failures
		# filehandle select_read on STDIN FAILED: error
		# filehandle select_write on MYFH FAILED: foo
		} elsif ( $l =~ /^filehandle\s+(\w+)\s+on\s+(\w+)\s+FAILED:/ ) {
			my( $mode, $type ) = ( $1, $2 );

			# nullify the data struct for that
			$d->{ $mode . $type }->{'d'} = undef;
			$d->{ $mode . $type }->{'t'} = undef;
			$d->{ $mode . $type }->{'i'} = undef;

		# parse the alarm_add skip
		# alarm_add NOT SUPPORTED on this version of POE, skipping alarm_adds/alarm_clears tests!
		} elsif ( $l =~ /^alarm_add\s+NOT\s+SUPPORTED\s+on/ ) {
			# nullify the data struct for that
			foreach my $type ( qw( alarm_adds alarm_clears ) ) {
				$d->{ $type }->{'d'} = undef;
				$d->{ $type }->{'t'} = undef;
				$d->{ $type }->{'i'} = undef;
			}

		# parse any STDERR output
		# !STDERR: unable to foo
		} elsif ( $l =~ /^\!STDERR:\s+(.+)$/ ) {
			push( @{ $test->{'stderr'} }, $1 );

		} else {
			# unknown line :(
			push( @unknown, $l );
		}
	}

	# Get rid of the rawdata
	delete $test->{'raw'};

	# Dump the unknowns
	if ( @unknown ) {
		print "[ANALYZER] Unknown output from benchmark -> " . Dump( \@unknown );
	}

	# Dump the data struct we have to the file.yml
	my $yaml_file = 'results/' . delete $test->{'test'};
	$yaml_file .= '.yml';
	my $ret = open( my $fh, '>', $yaml_file );
	if ( defined $ret ) {
		print $fh Dump( $test );
		if ( ! close( $fh ) ) {
			print "[ANALYZER] Unable to close $yaml_file -> " . $! . "\n";
		}
	} else {
		print "[ANALYZER] Unable to open $yaml_file for writing -> " . $! . "\n";
	}

	# all done!
	return;
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::Analyzer - Analyzes the output from the benchmarks

=head1 SYNOPSIS

	Don't use this module directly. Please see L<POE::Devel::Benchmarker>

=head1 ABSTRACT

This package implements the guts of converting the raw data into a machine-readable format. Furthermore, it dumps the data
in YAML format.

=head1 DESCRIPTION

I promise you that once I've stabilized the YAML format I'll have it documented here :)

=head1 EXPORT

Automatically exports the initAnalyzer() sub

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# sample test output ( from SubProcess v0.02 )
STARTTIME: 1229232743.49131 -> TIMES 0.24 0.01 11.2 0.32
POE-1.003-Select-LITE-assert-xsqueue
Using master loop: Select-BUILTIN
Using FULL Assertions!
Using the LITE tests
LETTING POE find POE::XS::Queue::Array
Using POE-1.003
POE is using: POE::Loop::Select v1.2355
POE is using: POE::XS::Queue::Array v0.005
POE is using: POE::Queue v1.2328
POE is using: POE::Loop::PerlSignals v1.2329


       10 startups             in     0.853 seconds (     11.723 per second)
startups times: 0.09 0 0 0 0.09 0 0.73 0.11
    10000 posts                in     0.495 seconds (  20211.935 per second)
posts times: 0.1 0 0.73 0.11 0.53 0.06 0.73 0.11
    10000 dispatches           in     1.113 seconds (   8984.775 per second)
dispatches times: 0.53 0.06 0.73 0.11 1.64 0.06 0.73 0.11
    10000 alarms               in     1.017 seconds (   9829.874 per second)
alarms times: 1.64 0.06 0.73 0.11 2.66 0.06 0.73 0.11
    10000 alarm_adds           in     0.523 seconds (  19102.416 per second)
alarm_adds times: 2.66 0.06 0.73 0.11 3.18 0.06 0.73 0.11
    10000 alarm_clears         in     0.377 seconds (  26540.332 per second)
alarm_clears times: 3.18 0.06 0.73 0.11 3.55 0.07 0.73 0.11
      500 session_creates      in     0.130 seconds (   3858.918 per second)
session_creates times: 3.55 0.07 0.73 0.11 3.68 0.08 0.73 0.11
      500 session_destroys     in     0.172 seconds (   2901.191 per second)
session_destroys times: 3.68 0.08 0.73 0.11 3.85 0.08 0.73 0.11
    10000 select_read_STDIN    in     1.823 seconds (   5485.878 per second)
select_read_STDIN times: 3.85 0.08 0.73 0.11 5.66 0.08 0.73 0.11
    10000 select_write_STDIN   in     1.827 seconds (   5472.283 per second)
select_write_STDIN times: 5.66 0.08 0.73 0.11 7.47 0.08 0.73 0.11
    10000 select_read_MYFH     in     1.662 seconds (   6016.387 per second)
select_read_MYFH times: 7.47 0.08 0.73 0.11 9.12 0.1 0.73 0.11
    10000 select_write_MYFH    in     1.704 seconds (   5868.537 per second)
select_write_MYFH times: 9.12 0.1 0.73 0.11 10.78 0.11 0.73 0.11
    10000 calls                in     0.222 seconds (  45038.974 per second)
calls times: 10.78 0.11 0.73 0.11 11 0.11 0.73 0.11
    10000 single_posts         in     1.999 seconds (   5003.473 per second)
single_posts times: 11 0.11 0.73 0.11 12.86 0.22 0.73 0.11
pidinfo: Name:	perl
pidinfo: State:	R (running)
pidinfo: Tgid:	16643
pidinfo: Pid:	16643
pidinfo: PPid:	16600
pidinfo: TracerPid:	0
pidinfo: Uid:	1000	1000	1000	1000
pidinfo: Gid:	1000	1000	1000	1000
pidinfo: FDSize:	32
pidinfo: Groups:	4 20 24 25 29 30 44 46 107 109 115 127 1000 1001
pidinfo: VmPeak:	   14376 kB
pidinfo: VmSize:	   14216 kB
pidinfo: VmLck:	       0 kB
pidinfo: VmHWM:	   11440 kB
pidinfo: VmRSS:	   11292 kB
pidinfo: VmData:	    9908 kB
pidinfo: VmStk:	      84 kB
pidinfo: VmExe:	    1044 kB
pidinfo: VmLib:	    1872 kB
pidinfo: VmPTE:	      24 kB
pidinfo: Threads:	1
pidinfo: SigQ:	0/16182
pidinfo: SigPnd:	0000000000000000
pidinfo: ShdPnd:	0000000000000000
pidinfo: SigBlk:	0000000000000000
pidinfo: SigIgn:	0000000000001000
pidinfo: SigCgt:	0000000180000000
pidinfo: CapInh:	0000000000000000
pidinfo: CapPrm:	0000000000000000
pidinfo: CapEff:	0000000000000000
pidinfo: Cpus_allowed:	03
pidinfo: Mems_allowed:	1
pidinfo: voluntary_ctxt_switches:	10
pidinfo: nonvoluntary_ctxt_switches:	512
Running under perl binary: /usr/bin/perl
perlconfig: Summary of my perl5 (revision 5 version 8 subversion 8) configuration:
perlconfig:   Platform:
perlconfig:     osname=linux, osvers=2.6.15.7, archname=i486-linux-gnu-thread-multi
perlconfig:     uname='linux palmer 2.6.15.7 #1 smp thu sep 7 19:42:20 utc 2006 i686 gnulinux '
perlconfig:     config_args='-Dusethreads -Duselargefiles -Dccflags=-DDEBIAN -Dcccdlflags=-fPIC -Darchname=i486-linux-gnu -Dprefix=/usr -Dprivlib=/usr/share/perl/5.8 -Darchlib=/usr/lib/perl/5.8 -Dvendorprefix=/usr -Dvendorlib=/usr/share/perl5 -Dvendorarch=/usr/lib/perl5 -Dsiteprefix=/usr/local -Dsitelib=/usr/local/share/perl/5.8.8 -Dsitearch=/usr/local/lib/perl/5.8.8 -Dman1dir=/usr/share/man/man1 -Dman3dir=/usr/share/man/man3 -Dsiteman1dir=/usr/local/man/man1 -Dsiteman3dir=/usr/local/man/man3 -Dman1ext=1 -Dman3ext=3perl -Dpager=/usr/bin/sensible-pager -Uafs -Ud_csh -Ud_ualarm -Uusesfio -Uusenm -Duseshrplib -Dlibperl=libperl.so.5.8.8 -Dd_dosuid -des'
perlconfig:     hint=recommended, useposix=true, d_sigaction=define
perlconfig:     usethreads=define use5005threads=undef useithreads=define usemultiplicity=define
perlconfig:     useperlio=define d_sfio=undef uselargefiles=define usesocks=undef
perlconfig:     use64bitint=undef use64bitall=undef uselongdouble=undef
perlconfig:     usemymalloc=n, bincompat5005=undef
perlconfig:   Compiler:
perlconfig:     cc='cc', ccflags ='-D_REENTRANT -D_GNU_SOURCE -DTHREADS_HAVE_PIDS -DDEBIAN -fno-strict-aliasing -pipe -I/usr/local/include -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64',
perlconfig:     optimize='-O2',
perlconfig:     cppflags='-D_REENTRANT -D_GNU_SOURCE -DTHREADS_HAVE_PIDS -DDEBIAN -fno-strict-aliasing -pipe -I/usr/local/include'
perlconfig:     ccversion='', gccversion='4.2.3 20071123 (prerelease) (Ubuntu 4.2.2-3ubuntu4)', gccosandvers=''
perlconfig:     intsize=4, longsize=4, ptrsize=4, doublesize=8, byteorder=1234
perlconfig:     d_longlong=define, longlongsize=8, d_longdbl=define, longdblsize=12
perlconfig:     ivtype='long', ivsize=4, nvtype='double', nvsize=8, Off_t='off_t', lseeksize=8
perlconfig:     alignbytes=4, prototype=define
perlconfig:   Linker and Libraries:
perlconfig:     ld='cc', ldflags =' -L/usr/local/lib'
perlconfig:     libpth=/usr/local/lib /lib /usr/lib
perlconfig:     libs=-lgdbm -lgdbm_compat -ldb -ldl -lm -lpthread -lc -lcrypt
perlconfig:     perllibs=-ldl -lm -lpthread -lc -lcrypt
perlconfig:     libc=/lib/libc-2.6.1.so, so=so, useshrplib=true, libperl=libperl.so.5.8.8
perlconfig:     gnulibc_version='2.6.1'
perlconfig:   Dynamic Linking:
perlconfig:     dlsrc=dl_dlopen.xs, dlext=so, d_dlsymun=undef, ccdlflags='-Wl,-E'
perlconfig:     cccdlflags='-fPIC', lddlflags='-shared -L/usr/local/lib'
Running under machine: Linux apoc-x300 2.6.24-21-generic #1 SMP Tue Oct 21 23:43:45 UTC 2008 i686 GNU/Linux

cpuinfo: processor	: 0
cpuinfo: vendor_id	: GenuineIntel
cpuinfo: cpu family	: 6
cpuinfo: model		: 15
cpuinfo: model name	: Intel(R) Core(TM)2 Duo CPU     L7100  @ 1.20GHz
cpuinfo: stepping	: 11
cpuinfo: cpu MHz		: 1201.000
cpuinfo: cache size	: 4096 KB
cpuinfo: physical id	: 0
cpuinfo: siblings	: 2
cpuinfo: core id		: 0
cpuinfo: cpu cores	: 2
cpuinfo: fdiv_bug	: no
cpuinfo: hlt_bug		: no
cpuinfo: f00f_bug	: no
cpuinfo: coma_bug	: no
cpuinfo: fpu		: yes
cpuinfo: fpu_exception	: yes
cpuinfo: cpuid level	: 10
cpuinfo: wp		: yes
cpuinfo: flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe nx lm constant_tsc arch_perfmon pebs bts pni monitor ds_cpl vmx est tm2 ssse3 cx16 xtpr lahf_lm ida
cpuinfo: bogomips	: 2397.58
cpuinfo: clflush size	: 64
cpuinfo: processor	: 1
cpuinfo: vendor_id	: GenuineIntel
cpuinfo: cpu family	: 6
cpuinfo: model		: 15
cpuinfo: model name	: Intel(R) Core(TM)2 Duo CPU     L7100  @ 1.20GHz
cpuinfo: stepping	: 11
cpuinfo: cpu MHz		: 1201.000
cpuinfo: cache size	: 4096 KB
cpuinfo: physical id	: 0
cpuinfo: siblings	: 2
cpuinfo: core id		: 1
cpuinfo: cpu cores	: 2
cpuinfo: fdiv_bug	: no
cpuinfo: hlt_bug		: no
cpuinfo: f00f_bug	: no
cpuinfo: coma_bug	: no
cpuinfo: fpu		: yes
cpuinfo: fpu_exception	: yes
cpuinfo: cpuid level	: 10
cpuinfo: wp		: yes
cpuinfo: flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe nx lm constant_tsc arch_perfmon pebs bts pni monitor ds_cpl vmx est tm2 ssse3 cx16 xtpr lahf_lm ida
cpuinfo: bogomips	: 2394.02
cpuinfo: clflush size	: 64

ENDTIME: 1229232757.53804 -> TIMES 0.27 0.01 23.1 0.62
