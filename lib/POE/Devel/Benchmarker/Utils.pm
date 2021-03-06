# Declare our package
package POE::Devel::Benchmarker::Utils;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.06';

# set ourself up for exporting
use base qw( Exporter );
our @EXPORT_OK = qw( poeloop2load poeloop2dist loop2realversion knownloops
	beautify_times generateTestfile
	currentMetrics metricSorting currentTestVersion
);

# returns the current test output version
sub currentTestVersion {
	return '2';
}

# List our metrics
# TODO add metrics for pid, total testsuite wallclock, times, etc
my %metrics = (
	'startups'		=> 'B',
	'alarms'		=> 'B',
	'alarm_adds'		=> 'B',
	'alarm_clears'		=> 'B',
	'dispatches'		=> 'B',
	'posts'			=> 'B',
	'single_posts'		=> 'B',
	'session_creates'	=> 'B',
	'session_destroys'	=> 'B',
	'select_read_MYFH'	=> 'B',
	'select_write_MYFH'	=> 'B',
	'select_read_STDIN'	=> 'B',
	'select_write_STDIN'	=> 'B',
	'socket_connects'	=> 'B',
	'socket_stream'		=> 'B',
);

# returns the list of current metrics
sub currentMetrics {
	return [ sort keys %metrics ];
}

# Returns the sorting method for a metric
sub metricSorting {
	my $metric = shift;
	if ( exists $metrics{ $metric } ) {
		return $metrics{ $metric };
	} else {
		die "Unknown metric $metric";
	}
}

# returns the filename for a particular test
sub generateTestfile {
	my $heap = shift;

	## no critic ( ProhibitAccessOfPrivateData )

	return	'POE-' . $heap->{'current_version'} .
		'-' . $heap->{'current_loop'} .
		'-' . ( $heap->{'lite_tests'} ? 'LITE' : 'HEAVY' ) .
		'-' . ( $heap->{'current_assertions'} ? 'assert' : 'noassert' ) .
		'-' . ( $heap->{'current_noxsqueue'} ? 'noxsqueue' : 'xsqueue' );
}

# maintains the mapping of the loop <-> real module
my %poe2load = (
	'Event'		=> 'Event',
	'IO_Poll'	=> 'IO::Poll',
	'Event_Lib'	=> 'Event::Lib',
	'EV'		=> 'EV',
	'Glib'		=> 'Glib',
	'Tk'		=> 'Tk',
	'Gtk'		=> 'Gtk',
	'Prima'		=> 'Prima',
	'Wx'		=> 'Wx',
	'Kqueue'	=> undef,
	'Select'	=> undef,
	'XSPoll'	=> undef,
	'XSEPoll'	=> undef,
);

# maintains the mapping of the loop <-> actual dist name
my %loop2dist = (
	'Event'		=> 'POE::Loop::Event',
	'IO_Poll'	=> 'POE::Loop::IO_Poll',
	'Event_Lib'	=> 'POE::Loop::Event_Lib',
	'EV'		=> 'POE::Loop::EV',
	'Glib'		=> 'POE::Loop::Glib',
	'Tk'		=> 'POE::Loop::Tk',
	'Gtk'		=> 'POE::Loop::Gtk',
	'Prima'		=> 'POE::Loop::Prima',
	'Wx'		=> 'POE::Loop::Wx',
	'Kqueue'	=> 'POE::Loop::Kqueue',
	'Select'	=> 'POE::Loop::Select',
	'XSPoll'	=> 'POE::XS::Loop::Poll',
	'XSEPoll'	=> 'POE::XS::Loop::EPoll',
);

# returns the proper "load" stuff for a specific loop
sub poeloop2load {
	my $eventloop = shift;

	if ( exists $poe2load{ $eventloop } ) {
		return $poe2load{ $eventloop };
	} else {
		die "Unknown event loop!";
	}
}

# returns the full module name - useful to load a loop via POE_EVENT_LOOP
sub poeloop2dist {
	my $eventloop = shift;

	if ( exists $loop2dist{ $eventloop } ) {
		return $loop2dist{ $eventloop };
	} else {
		die "Unknown event loop!";
	}
}

# returns the version of the "real" installed module that the loop uses
sub loop2realversion {
	my $eventloop = shift;

	# Decide which event loop to use
	if ( ! defined $eventloop ) {
		return;
	} elsif ( $eventloop eq 'Event' ) {
		return $Event::VERSION;
	} elsif ( $eventloop eq 'IO_Poll' ) {
		return $IO::Poll::VERSION;
	} elsif ( $eventloop eq 'Event_Lib' ) {
		return $Event::Lib::VERSION;
	} elsif ( $eventloop eq 'EV' ) {
		return $EV::VERSION;
	} elsif ( $eventloop eq 'Glib' ) {
		return $Glib::VERSION;
	} elsif ( $eventloop eq 'Tk' ) {
		return $Tk::VERSION;
	} elsif ( $eventloop eq 'Gtk' ) {
		return $Gtk::VERSION;
	} elsif ( $eventloop eq 'Prima' ) {
		return $Prima::VERSION;
	} elsif ( $eventloop eq 'Wx' ) {
		return $Wx::VERSION;
	} elsif ( $eventloop eq 'Kqueue' ) {
		# POE::Loop::Kqueue doesn't rely on an external module...
		return $POE::Loop::Kqueue::VERSION;
	} elsif ( $eventloop eq 'Select' ) {
		return 'BUILTIN';
	} elsif ( $eventloop eq 'XSPoll' ) {
		return $POE::XS::Loop::Poll::VERSION;
	} elsif ( $eventloop eq 'XSEPoll' ) {
		return $POE::XS::Loop::EPoll::VERSION;
	} else {
		die "Unknown event loop!";
	}
}

# helper routine to parse times() output
sub beautify_times {
	my $string = shift;
	my $origdata = shift;

	# split it up
	$string =~ s/^\s+//; $string =~ s/\s+$//;
	my @times = split( /\s+/, $string );

	# make the data struct
	# ($user,$system,$cuser,$csystem) = times;
	my $data = {
		'u'		=> $times[4] - $times[0],
		's'		=> $times[5] - $times[1],
		'cu'		=> $times[6] - $times[2],
		'cs'		=> $times[7] - $times[3],
	};

	# add original data?
	if ( $origdata ) {
		## no critic ( ProhibitAccessOfPrivateData )

		$data->{'s_user'} = $times[0];
		$data->{'s_sys'} = $times[1];
		$data->{'s_cuser'} = $times[2];
		$data->{'s_csys'} = $times[3];
		$data->{'e_user'} = $times[4];
		$data->{'e_sys'} = $times[5];
		$data->{'e_cuser'} = $times[6];
		$data->{'e_csys'} = $times[7];
	}

	# send it back!
	return $data;
}

# returns a list of "known" POE loops
sub knownloops {
	return [ sort qw( Event Event_Lib EV Glib Prima Gtk Tk Select IO_Poll Wx Kqueue XSPoll XSEPoll ) ];
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::Utils - Various utility routines for POE::Devel::Benchmarker

=head1 SYNOPSIS

	use POE::Devel::Benchmarker::Utils qw( poeloop2load );
	print poeloop2load( "IO_Poll" );

=head1 ABSTRACT

This package contains the utility routines and constants that POE::Devel::Benchmarker needs.

=head1 EXPORT

This package exports those subs via @EXPORT_OK:

=over 4

=item currentTestVersion()

Returns the current test version, used to identify different versions of the test output

=item currentMetrics()

Returns an arrayref of the current benchmark "metrics" that we process

=item metricSorting( $metric )

Returns the sorting method for $metric. Current sorting methods:

	B	->	Biggest number
	S	-> 	Smallest number

=item knownloops()

Returns an arrayref of the "known" POE loops as of this version of the Benchmarker

=item poeloop2load( $loop )

Returns the "parent" class to load for a specific loop. An example is:

	$real = poeloop2load( 'IO_Poll' );	# $real now contains "IO::Poll"

=item poeloop2dist( $loop )

Returns the proper name of the loop to use in loading POE via $ENV{POE_EVENT_LOOP}. An example is:

	$real = poeloop2dist( 'XSPoll' );	# $real now contains "POE::XS::Loop::Poll"

=item loop2realversion( $loop )

Returns the version of the "parent" class for a specific loop. An example is:

	$ver = loop2realversion( 'IO_Poll' );	# $ver now contains $IO::Poll::VERSION

=item beautify_times( @times, @times2 )

Returns a hashref of data from parsing 2 consecutive times() structures in a string. You can pass an additional parameter
( boolean ) to include the original data. An example is:

	print Data::Dumper::Dumper( beautify_times( '0.1 0 0 0 0.1 0 0.76 0.09', 1 ) );
	{
		"sys" => 0,		# total system time
		"user" => 0,		# total user time
		"csys" => 0.76		# total children system time
		"cuser" => 0.08		# total children user time

		"e_csys" => "0.09",	# end children system time ( optional )
		"e_cuser" => "0.76",	# end children user time ( optional )
		"e_sys" => 0,		# end system time ( optional )
		"e_user" => "0.1",	# end user time ( optional )
		"s_csys" => 0,		# start children system time ( optional )
		"s_cuser" => 0,		# start children user time ( optional )
		"s_sys" => 0,		# start system time ( optional )
		"s_user" => "0.1"	# start user time ( optional )
	}

=item generateTestfile()

Internal method, accepts the POE HEAP as an argument and returns the filename of the test.

	my $file = generateTestfile( $_[HEAP] );

=back

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

