# Build.PL
use strict; use warnings;
use Module::Build;

my $build = Module::Build->new(
	# look up Module::Build::API for the info!
	'dynamic_config'	=> 0,
	'module_name'		=> 'POE::Devel::Benchmarker',
	'license'		=> 'perl',

	'dist_abstract'		=> "Benchmarking POE's performance ( acts more like a smoker )",
	'dist_author'		=> 'Apocalypse <APOCAL@cpan.org>',

	'create_packlist'	=> 1,
	'create_makefile_pl'	=> 'traditional',
	'create_readme'		=> 1,
	'create_license'	=> 1,
	'sign'			=> 0,

	'test_files'		=> 't/*.t',

	'add_to_cleanup'	=> [ 'META.yml', 'Makefile.PL', 'README', 'Makefile', 'LICENSE' ],	# automatically generated

	'requires'		=> {
		# POE Stuff
		'POE'				=> '1.001',	# for the POE_EVENT_LOOP env var which is so handy!
		'POE::Session::AttributeBased'	=> 0,

		# misc perl stuff
		'Time::HiRes'			=> 0,
		'version'			=> 0,
		'Devel::Hide'			=> 0,
		'File::Spec'			=> 0,

		# Analyzer reqs
		'YAML::Tiny'			=> 0,

		# GetPOEdists reqs
		'LWP::UserAgent'		=> 0,
		'HTML::LinkExtor'		=> 0,
		'URI::URL'			=> 0,
		'Archive::Tar'			=> 0,

		# Imager reqs
		'GD::Graph::lines'		=> 0,
		'GD::Graph::colour'		=> 0,
		'Class::Accessor::Fast'		=> 0,
		'Module::Pluggable'		=> 0,
		'Text::Table'			=> 0,

		# Test stuff
		'Test::More'			=> 0,

		# we need a recent perl
		'perl'				=> '5.008',
	},

	'recommends'		=> {
		# our POE loops!
		'POE::Loop::Event'		=> 0,
		'POE::Loop::Event_Lib'		=> 0,
		'POE::Loop::EV'			=> 0,
		'POE::Loop::Glib'		=> 0,
		'POE::Loop::Prima'		=> 0,
		'POE::Loop::Gtk'		=> 0,
		'POE::Loop::Wx'			=> 0,
		'POE::Loop::Kqueue'		=> 0,
		'POE::Loop::Tk'			=> 0,
		'POE::XS::Loop::Poll'		=> 0,
		'POE::XS::Loop::EPoll'		=> 0,

		# included in POE ( listed here for completeness )
		#'POE::Loop::Select'		=> 0,
		#'POE::Loop::IO_Poll'		=> 0,

		# our XS queue
		'POE::XS::Queue::Array'		=> 0,
	},

	# include the standard stuff in META.yml
	'meta_merge'	=> {
		'resources'	=> {
			'license'	=> 'http://dev.perl.org/licenses/',
			'homepage'	=> 'http://search.cpan.org/dist/POE-Devel-Benchmarker',
			'bugtracker'	=> 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Devel-Benchmarker',
			'repository'	=> 'http://github.com/apocalypse/perl-poe-benchmarker',
		},
	},
);

# all done!
$build->create_build_script;
