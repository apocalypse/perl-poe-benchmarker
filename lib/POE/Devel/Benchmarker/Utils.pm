# Declare our package
package POE::Devel::Benchmarker::Utils;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.02';

# auto-export the only sub we have
require Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw(Exporter);
@EXPORT_OK = qw( poeloop2load loop2realversion beautify_times knownloops );

# returns the proper "load" stuff for a specific loop
sub poeloop2load {
	my $eventloop = shift;

	# Decide which event loop to use
	# Event_Lib EV Glib Prima Gtk Wx Kqueue Tk Select IO_Poll
	if ( $eventloop eq 'Event' ) {
		return 'Event';
	} elsif ( $eventloop eq 'IO_Poll' ) {
		return 'IO::Poll';
	} elsif ( $eventloop eq 'Event_Lib' ) {
		return 'Event::Lib';
	} elsif ( $eventloop eq 'EV' ) {
		return 'EV';
	} elsif ( $eventloop eq 'Glib' ) {
		return 'Glib';
	} elsif ( $eventloop eq 'Tk' ) {
		return 'Tk',
	} elsif ( $eventloop eq 'Gtk' ) {
		return 'Gtk';
	} elsif ( $eventloop eq 'Prima' ) {
		return 'Prima';
	} elsif ( $eventloop eq 'Wx' ) {
		return 'Wx';
	} elsif ( $eventloop eq 'Kqueue' ) {
		# FIXME dunno what to do here!
		return;
	} elsif ( $eventloop eq 'Select' ) {
		return;
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
		# FIXME how do I do this?
		return;
	} elsif ( $eventloop eq 'Select' ) {
		return 'BUILTIN';
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
		'user'		=> $times[4] - $times[0],
		'sys'		=> $times[5] - $times[1],
		'cuser'		=> $times[6] - $times[2],
		'csys'		=> $times[7] - $times[3],
	};

	# add original data?
	if ( $origdata ) {
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
	return [ qw( Event_Lib EV Glib Prima Gtk Wx Kqueue Tk Select IO_Poll ) ];
}

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::Utils - Various utility routines for POE::Devel::Benchmarker

=head1 SYNOPSIS

	perl -MPOE::Devel::Benchmarker::Utils -e 'print poeloop2load( "IO_Poll" )'

=head1 ABSTRACT

This package contains the utility routines and constants that POE::Devel::Benchmarker needs.

=head1 EXPORT

This package exports those subs via @EXPORT_OK:

=over 4

=item knownloops()

Returns an arrayref of the "known" POE loops as of this version of the Benchmarker

=item poeloop2load()

Returns the "parent" class to load for a specific loop. An example is:

	$real = poeloop2load( 'IO_Poll' );	# $real now contains "IO::Poll"

=item loop2realversion()

Returns the version of the "parent" class for a specific loop. An example is:

	$ver = loop2realversion( 'IO_Poll' );	# $ver now contains $IO::Poll::VERSION

=item beautify_times()

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

=back

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

