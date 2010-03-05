# Declare our package
package POE::Devel::Benchmarker::Imager;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.06';

# auto-export the only sub we have
use base qw( Exporter );
our @EXPORT = qw( imager );

# import the helper modules
use YAML::Tiny;
use File::Spec;

# to silence Perl::Critic - # Three-argument form of open used at line 541, column 3.  Three-argument open is not available until perl 5.6.  (Severity: 5)
use 5.008;

# load our plugins!
use Module::Pluggable search_path => [ __PACKAGE__ ];

# load comparison stuff
use version;

# Get some stuff from Utils
use POE::Devel::Benchmarker::Utils qw( currentTestVersion );

# generate some accessors
use base qw( Class::Accessor::Fast );
__PACKAGE__->mk_ro_accessors( qw( poe_versions poe_versions_sorted poe_loops data
	noxsqueue noasserts litetests quiet type
) );

# autoflush, please!
use IO::Handle;
STDOUT->autoflush( 1 );

# starts the work of converting our data to images
sub imager {
	my $options = shift;

	# instantitate ourself
	my $self = __PACKAGE__->new( $options );

	# parse all of our YAML modules!
	$self->loadtests;

	# process some stats
	$self->process_data;

	# generate the images!
	$self->generate_images;

	return;
}

# creates a new instance
sub new {
	my $class = shift;
	my $opts = shift;

	# instantitate ourself
	my $self = {};
	bless $self, $class;

	# init the options
	$self->init_options( $opts );

	if ( ! $self->{'options'}->{'quiet'} ) {
		print "[IMAGER] Starting up...\n";
	}

	return $self;
}

sub init_options {
	my $self = shift;
	my $options = shift;

	# set defaults
	$self->{'quiet'} = 0;
	$self->{'litetests'} = 1;
	$self->{'noasserts'} = undef;
	$self->{'noxsqueue'} = undef;

	# process our options
	if ( defined $options and ref $options and ref( $options ) eq 'HASH' ) {
		## no critic ( ProhibitAccessOfPrivateData )

		# process quiet mode
		if ( exists $options->{'quiet'} ) {
			if ( $options->{'quiet'} ) {
				$self->{'quiet'} = 1;
			} else {
				$self->{'quiet'} = 0;
			}
		}

		# process the LITE/HEAVY
		if ( exists $options->{'litetests'} ) {
			if ( $options->{'litetests'} ) {
				$self->{'litetests'} = 1;
			} else {
				$self->{'litetests'} = 0;
			}
		}

		# process the noasserts to load
		if ( exists $options->{'noasserts'} ) {
			if ( $options->{'noasserts'} ) {
				$self->{'noasserts'} = 1;
			} else {
				$self->{'noasserts'} = 0;
			}
		}

		# process the noxsqueue to load
		if ( exists $options->{'noxsqueue'} ) {
			if ( $options->{'noxsqueue'} ) {
				$self->{'noxsqueue'} = 1;
			} else {
				$self->{'noxsqueue'} = 0;
			}
		}

		# process the plugins to load -> "type"
		if ( exists $options->{'type'} ) {
			my $forcetypes;
			if ( ! ref $options->{'type'} ) {
				# split it via CSV
				$forcetypes = [ split( /,/, $options->{'type'} ) ];
				foreach ( @$forcetypes ) {
					$_ =~ s/^\s+//; $_ =~ s/\s+$//;
				}
			} else {
				# treat it as array
				$forcetypes = $options->{'type'};
			}

			# check for !type modules
			my @notype;
			foreach my $l ( @$forcetypes ) {
				if ( $l =~ /^\!/ ) {
					push( @notype, __PACKAGE__ . '::' . substr( $l, 1 ) );
				}
			}
			if ( scalar @notype ) {
				# replace the forcetype with ALL known, then subtract notype from it
				my %bad;
				@bad{@notype} = () x @notype;
				@$forcetypes = grep { !exists $bad{$_} } $self->plugins;
			} else {
				# Add our package to the type
				@$forcetypes = map { __PACKAGE__ . '::' . $_ } @$forcetypes;
			}

			$self->{'type'} = $forcetypes;
		}

		# FIXME process the versions to load

		# FIXME process the loops to load
	}

	# some sanity tests
	if ( ! -d 'results' ) {
		die "The 'results' directory is not found in the working directory!";
	}
	if ( ! -d 'images' ) {
		die "The 'images' directory is not found in the working directory!";
	}

	return;
}

# starts the process of loading all of our YAML images
sub loadtests {
	my $self = shift;

	# gather all the YAML dumps
	if ( opendir( DUMPS, 'results' ) ) {
		foreach my $d ( readdir( DUMPS ) ) {
			# parse the file structure
			#  POE-1.0002-IO_Poll-LITE-assert-noxsqueue.yml
			if ( $d =~ /^POE\-([\d\.\_]+)\-(\w+?)\-(LITE|HEAVY)\-(noassert|assert)\-(noxsqueue|xsqueue)\.yml$/ ) {
				my( $ver, $loop, $lite, $assert, $xsqueue ) = ( $1, $2, $3, $4, $5 );

				# skip this file?
				if ( $self->noxsqueue ) {
					if ( $xsqueue eq 'xsqueue' ) { next }
				} else {
					if ( defined $self->noxsqueue ) {
						if ( $xsqueue eq 'noxsqueue' ) { next }
					}
				}
				if ( $self->noasserts ) {
					if ( $assert eq 'assert' ) { next }
				} else {
					if ( defined $self->noasserts ) {
						if ( $assert eq 'noassert' ) { next }
					}
				}
				if ( $self->litetests ) {
					if ( $lite eq 'HEAVY' ) { next }
				} else {
					if ( $lite eq 'LITE' ) { next }
				}

				# FIXME allow selective loading of tests, so we can control what to image, etc

				# actually load this file!
				$self->load_yaml( $d, $ver, $loop, $lite, $assert, $xsqueue );
			}
		}
		closedir( DUMPS ) or die "[IMAGER] Unable to read from 'results' -> " . $!;
	} else {
		die "[IMAGER] Unable to open 'results' for reading -> " . $!;
	}

	# sanity
	if ( ! exists $self->{'data'} ) {
		die "[IMAGER] Unable to find valid POE test result(s) in the 'results' directory!\n";
	}

	if ( ! $self->quiet ) {
		print "[IMAGER] Done with parsing the YAML files...\n";
	}

	return;
}

# loads the yaml of a specific file
sub load_yaml {
	my ( $self, $file, $ver, $loop, $lite, $assert, $xsqueue ) = @_;

	## no critic ( ProhibitAccessOfPrivateData )

	my $yaml = YAML::Tiny->read( File::Spec->catfile( 'results', $file ) );
	if ( ! defined $yaml ) {
		print "[IMAGER] Unable to load YAML file $file -> " . YAML::Tiny->errstr . "\n";
		return;
	} else {
		# inrospect it!
		my $isvalid = 0;
		eval {
			# simple sanity check: the "x_bench" param is at the end of the YML, so if it loads fine we know it's there
			if ( defined $yaml->[0] and exists $yaml->[0]->{'x_bench'} ) {
				# version must at least match us
				$isvalid = ( $yaml->[0]->{'x_bench'} eq currentTestVersion() ? 1 : 0 );
			} else {
				$isvalid = undef;
			}
		};
		if ( ! $isvalid or $@ ) {
			print "[IMAGER] Detected outdated/corrupt benchmark result: $file";
			return;
		} else {
			# reduce indirection
			$yaml = $yaml->[0];
		}
	}

	# store the POE version
	$self->{'poe_versions'}->{ $ver } = 1;

	# sanity check the loop master version ( which should always be our "installed" version, not per-POE )
	if ( exists $yaml->{'poe'}->{'loop_m'} ) {
		if ( ! defined $self->{'poe_loops'}->{ $loop } ) {
			$self->{'poe_loops'}->{ $loop } = $yaml->{'poe'}->{'loop_m'};
		} else {
			if ( $self->{'poe_loops'}->{ $loop } ne $yaml->{'poe'}->{'loop_m'} ) {
				die "[IMAGER] Detected POE::Loop master version inconsistency! $file reported '" . $yaml->{'poe'}->{'loop_m'} .
					"' while others had '" . $self->{'poe_loops'}->{ $loop } . "'";
			}
		}
	}

	# get the info we're interested in
	$self->{'data'}->{ $assert }->{ $xsqueue }->{ $ver }->{ $loop }->{'metrics'} = $yaml->{'metrics'};
	$self->{'data'}->{ $assert }->{ $xsqueue }->{ $ver }->{ $loop }->{'time'} = $yaml->{'t'};

	if ( exists $yaml->{'pid'} ) {
		$self->{'data'}->{ $assert }->{ $xsqueue }->{ $ver }->{ $loop }->{'pid'} = $yaml->{'pid'};
	}
	if ( exists $yaml->{'poe'}->{'modules'} ) {
		$self->{'data'}->{ $assert }->{ $xsqueue }->{ $ver }->{ $loop }->{'poe_modules'} = $yaml->{'poe'}->{'modules'};
	}

	# sanity check the perl stuff
	if ( exists $yaml->{'perl'}->{'binary'} ) {
		if ( ! exists $self->{'data'}->{'perlconfig'} ) {
			$self->{'data'}->{'perlconfig'}->{'binary'} = $yaml->{'perl'}->{'binary'};
			$self->{'data'}->{'perlconfig'}->{'version'} = $yaml->{'perl'}->{'v'};
		} else {
			if ( $self->{'data'}->{'perlconfig'}->{'binary'} ne $yaml->{'perl'}->{'binary'} ) {
				die "[IMAGER] Detected perl binary inconsistency! $file reported '" . $yaml->{'perl'}->{'binary'} .
					"' while others had '" . $self->{'data'}->{'perlconfig'}->{'binary'} . "'";
			}
			if ( $self->{'data'}->{'perlconfig'}->{'version'} ne $yaml->{'perl'}->{'v'} ) {
				die "[IMAGER] Detected perl version inconsistency! $file reported '" . $yaml->{'perl'}->{'v'} .
					"' while others had '" . $self->{'data'}->{'perlconfig'}->{'version'} . "'";
			}
		}
	}

	# sanity check the uname
	if ( exists $yaml->{'uname'} ) {
		if ( ! exists $self->{'data'}->{'uname'} ) {
			$self->{'data'}->{'uname'} = $yaml->{'uname'};
		} else {
			if ( $self->{'data'}->{'uname'} ne $yaml->{'uname'} ) {
				die "[IMAGER] Detected system inconsistency! $file reported '" . $yaml->{'uname'} .
					"' while others had '" . $self->{'data'}->{'uname'} . "'";
			}
		}
	}

	# sanity check the cpu name
	if ( exists $yaml->{'cpu'} ) {
		if ( ! exists $self->{'data'}->{'cpu'} ) {
			$self->{'data'}->{'cpu'} = $yaml->{'cpu'};
		} else {
			if ( $self->{'data'}->{'cpu'}->{'name'} ne $yaml->{'cpu'}->{'name'} ) {
				die "[IMAGER] Detected system/cpu inconsistency! $file reported '" . $yaml->{'cpu'}->{'name'} .
					"' while others had '" . $self->{'data'}->{'cpu'}->{'name'} . "'";
			}
		}
	}

	return;
}

sub process_data {
	my $self = shift;

	# sanitize the versions in an ordered loop
	$self->{'poe_versions_sorted'} = [ map { $_->stringify }
		sort { $b <=> $a }
		map { version->new($_) } keys %{ $self->poe_versions }
	];

	if ( ! $self->quiet ) {
		print "[IMAGER] Done with processing the benchmark statistics...\n";
	}

	return;
}

sub generate_images {
	my $self = shift;

	# load our plugins and let them have fun :)
	foreach my $plugin ( $self->plugins ) {
		# Do we want this plugin?
		if ( exists $self->{'type'} and ! grep { $_ eq $plugin } @{ $self->{'type'} } ) {
			if ( ! $self->quiet ) {
				print "[IMAGER] Skipping plugin $plugin\n";
			}

			next;
		}

		# actually load it!
		eval "require $plugin";		## no critic ( ProhibitStringyEval )
		if ( $@ ) {
			if ( ! $self->quiet ) {
				print "[IMAGER] Unable to load plugin $plugin -> $@\n";
				next;
			}
		}

		# sanity checks
		if ( $plugin->can( 'new' ) and $plugin->can( 'imager' ) ) {
			# create the plugin's home dir
			my $homedir = $plugin;
			if ( $homedir =~ /\:\:(\w+)$/ ) {
				$homedir = $1;
			} else {
				die "Unable to figure out plugin's homedir - $plugin";
			}
			$homedir = File::Spec->catdir( 'images', $homedir );
			if ( ! -d $homedir ) {
				# create it!
				if ( ! mkdir( $homedir ) ) {
					die "[IMAGER] Unable to create plugin directory: $homedir";
				}
			}

			# Okay, get this plugin!
			my $obj = $plugin->new( { 'dir' => $homedir } );

			if ( ! $self->quiet ) {
				print "[IMAGER] Processing the $plugin plugin...\n";
			}

			$obj->imager( $self );
		}
	}

	if ( ! $self->quiet ) {
		print "[IMAGER] Done with generating images...\n";
	}

	return;
}

1;
__END__

=for stopwords YAML litetests namespace noassert noxsqueue plugin xsqueue

=head1 NAME

POE::Devel::Benchmarker::Imager - Automatically converts the benchmark data into images

=head1 SYNOPSIS

	use POE::Devel::Benchmarker::Imager;
	imager();

=head1 ABSTRACT

This package automatically parses the benchmark data and generates pretty charts.

=head1 DESCRIPTION

It will parse the YAML output from the benchmark data and calls it's plugins to generate any charts necessary
and place them in the 'images' directory under the plugin's name. This module only does the high-level stuff, and leaves
the actual chart generation to the plugins.

Furthermore, we use Module::Pluggable to search all modules in the POE::Devel::Benchmarker::Imager::* namespace and
let them handle the generation of images. That way virtually unlimited combinations of images can be generated on the fly
from the data this module parses.

	apoc@apoc-x300:~$ cd poe-benchmarker
	apoc@apoc-x300:~/poe-benchmarker$ perl -MPOE::Devel::Benchmarker::Imager -e 'imager'

The way to use this module is by calling the imager() subroutine and let it do it's job. You can pass a hashref to it to
set various options. Here is a list of the valid options:

=over 4

=item quiet => boolean

This enables quiet mode which will not print anything to the console except for errors.

	imager( { 'quiet' => 1 } );

default: false

=item noxsqueue => boolean / undef

This will tell the Imager to not consider those tests for the output.

	imager( { noxsqueue => 1 } );

default: undef ( load both xsqueue and noxsqueue tests )

=item noasserts => boolean / undef

This will tell the Imager to not consider those tests for the output

	imager( { noasserts => 1 } );

default: undef ( load both assert and noassert tests )

=item litetests => boolean

This will tell the Imager to not consider those tests for the output

	imager( { litetests => 0 } );

default: true

=item type => csv list or array

This will tell the Imager to only process a specific plugin. Takes the same argument format as the main Benchmarker's poe + loop options.

There is some "magic" here where you can put a negative sign in front of a plugin and we will NOT run that.

	imager( { type => 'BasicStatistics' } );				# runs only the BasicStatistics plugin
	imager( { type => [ qw( BasicStatistics BenchmarkOutput ) ] } );	# runs those 2 plugins
	imager( { type => '-BasicStatistics' } );				# runs ALL plugins except BasicStatistics

=back

=head1 PLUGIN INTERFACE

For now, this is undocumented. Please look at L<POE::Devel::Benchmarker::Imager::BasicStatistics> for the general
concept on how it interacts with this module.

=head1 EXPORT

Automatically exports the imager() sub

=head1 SEE ALSO

L<POE::Devel::Benchmarker>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

