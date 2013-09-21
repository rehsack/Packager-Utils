use 5.012;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Packager::Utils',
    license             => 'Perl_5',
    dist_author         => q{Jens Rehsack <rehsack@cpan.org>},
    dist_version_from   => 'lib/Packager/Utils.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => '0.90',
    },
    configure_requires => {
        'Module::Build' => '0.38',
    },
    requires => {
        'perl' => 5.012,
	'CPAN' => 0,
	'CPAN::DistnameInfo' => 0,
	'Getopt::Long' => 0,
	'Module::CoreList' => 0,
	'File::Basename' => 0,
	'File::ConfigDir' => '0.004',
	'File::ShareDir' => '1.03',
	'File::Find::Rule' => '0.30',
	'File::Path' => '2.00',
	'File::Spec' => 0,
	'Template' => '2.20',
	'MooX::Cmd' => 0
    },
    auto_features => {
	pkgsrc_support => {
	    description => "pkgsrc Support",
	    requires => {
		'Carp::Assert' => 0,
		'Cwd' => 0,
		'IO::CaptureOutput' => 0,
		'File::pushd' => 0,
	    },
	},
	cache_support => {
	    description => "Cache enabling",
	    requires => {
		DBI => '1.628',
		'DBD::SQLite' => 0,
		'File::Find::Rule::Age' => 0,
	    },
	},
    },
    share_dir => { dist => [ 'share', ], },
    meta_merge => { resources => { repository => "https://github.com/rehsack/Packager-Utils", }, },
    test_files     => [ "t/*.t",           "xt/*.t" ],
    add_to_cleanup     => [ 'Packager-Utils-*' ],
);

$builder->create_build_script();
