# Declare our package
package POE::Devel::Benchmarker::Utils;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.01';

# auto-export the only sub we have
require Exporter;
use vars qw( @ISA @EXPORT );
@ISA = qw(Exporter);
@EXPORT = qw( poeloop2load loop2realversion );

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

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::Utils - Various utility routines for POE::Devel::Benchmarker

=head1 SYNOPSIS

	perl -MPOE::Devel::Benchmarker::Utils -e 'print poeloop2load( "IO_Poll" )'

=head1 ABSTRACT

This package contains the utility routines and constants that POE::Devel::Benchmarker needs.

=head2 EXPORT

Automatically exports those subs:

=over
=item poeloop2load()

Returns the "parent" class to load for a specific loop. An example is:

	$real = poeloop2load( 'IO_Poll' );	# $real now contains "IO::Poll"

=item loop2realversion()

Returns the version of the "parent" class for a specific loop. An example is:

	$ver = loop2realversion( 'IO_Poll' );	# $ver now contains $IO::Poll::VERSION

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

