use 5.012;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name       => 'Packager::Utils',
    license           => 'perl',
    dist_author       => q{Jens Rehsack <rehsack@cpan.org>},
    dist_version_from => 'lib/Packager/Utils.pm',
    release_status    => 'stable',
    share_dir         => {
                   dist => [ 'share', ],
                 },
    meta_merge => {
        'meta-spec' => { version => 2 },
        resources   => {
                       repository => {
                                       url  => 'git://github.com/rehsack/Packager-Utils.git',
                                       web  => 'https://github.com/rehsack/Packager-Utils',
                                       type => 'git',
                                     },
                     },
        prereqs => {
            test => {
                       requires => {
                                     'Test::More' => '0.90',
                                   },
                     },
            configure => {
                           requires => {
                                         'Module::Build' => '0.38',
                                       },
                         },
            develop => {
                         requires => {
                                       'Test::CPAN::Changes'                 => 0,
                                       'Test::CheckManifest'                 => 0,
                                       'Test::Pod'                           => 0,
                                       'Test::Pod::Coverage'                 => 0,
                                       'Test::Pod::Spelling::CommonMistakes' => 0,
                                     },
                       },
            runtime => {
                requires => {
                    'perl'                   => 5.012,
                    'Alien::Packages'        => '0.003',
		    'CPAN::Changes'          => 0,
                    'Class::Load'            => 0,
                    'File::Basename'         => 0,
                    'File::ShareDir'         => '1.03',
                    'File::Find::Rule'       => '0.30',
                    'File::Path'             => '2.00',
                    'File::Slurp'            => 0,
                    'File::Spec'             => 0,
                    'Hash::MoreUtils'        => '0.04',
                    'List::MoreUtils'        => '0.22',
                    'Log::Any::Adapter'      => 0,
                    'Module::CoreList'       => 0,         # must fit used perl version or better
                    'MooX::Cmd'              => '0.007',
                    'MooX::Log::Any'         => 0,
                    'MooX::ConfigFromFile'   => 0,
                    'MooX::Options'          => '4.000',
                    'MooX::Roles::Pluggable' => 0,
                    'Params::Util'           => '0.37',
		    'Pod::Select'            => 0,
		    'Pod::Text'              => 0,
                    # for general asynchronous operations
                    'IO::Async'      => '0.61',
                    'Unix::Statgrab' => '0.102',
                    # for deploying
                    'SQL::Translator' => 0,
                    # cache support (currently built-in!)
                    'DBI'                   => '1.628',
                    'DBD::SQLite'           => 0,
                    'File::Find::Rule::Age' => 0,
                    'DBIx::Class'           => '0.08250',
                    # cpan backend
                    'CPAN'               => 0,
                    'CPAN::DistnameInfo' => 0,
                    # pkgsrc backend
                    'Carp::Assert'      => 0,
                    'Cwd'               => 0,
                    'IO::CaptureOutput' => 0,
                    'File::pushd'       => 0,
                    # template role
                    'File::HomeDir' => '1.00',
                    'Template'      => '2.20',
                    # create/update package
                    'MetaCPAN::API' => 0,
                            },
                recommends => {
                                'Log::Dispatch'               => 0,
                                'Log::Any::Adapter::Dispatch' => 0,
                              },
                       }
                   },
                  },
    test_files => [
                    "t/*.t",
                    "xt/*.t"
                  ],
    add_to_cleanup => ['Packager-Utils-*'],
                                );

$builder->create_build_script();
