# Declare our package
package POE::Devel::Benchmarker::GetInstalledLoops::SubProcess;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.06';

# Do some dummy things
use POE;
POE::Kernel->run;

1;
__END__
=head1 NAME

POE::Devel::Benchmarker::GetInstalledLoops::SubProcess - Automatically detects the installed POE loops

=head1 SYNOPSIS

	die "Don't use this module directly. Please use POE::Devel::Benchmarker instead.";

=head1 ABSTRACT

This package implements the guts of searching for POE loops via fork/exec.

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
