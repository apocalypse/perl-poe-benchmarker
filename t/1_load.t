#!/usr/bin/perl
use strict; use warnings;

my $numtests;
BEGIN {
	$numtests = 7;

	eval "use Test::NoWarnings";
	if ( ! $@ ) {
		# increment by one
		$numtests++;
	}
}

use Test::More tests => $numtests;

use_ok( 'POE::Devel::Benchmarker::SubProcess' );
use_ok( 'POE::Devel::Benchmarker::GetInstalledLoops' );
use_ok( 'POE::Devel::Benchmarker::GetPOEdists' );
use_ok( 'POE::Devel::Benchmarker::Utils' );
use_ok( 'POE::Devel::Benchmarker::Imager::BasicStatistics' );
use_ok( 'POE::Devel::Benchmarker::Imager' );
use_ok( 'POE::Devel::Benchmarker' );
