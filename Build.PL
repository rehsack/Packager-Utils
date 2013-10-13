use 5.012;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name        => 'Packager::Utils',
    license            => 'perl',
    dist_author        => q{Jens Rehsack <rehsack@cpan.org>},
    dist_version_from  => 'lib/Packager/Utils.pm',
    release_status     => 'stable',
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
        'perl'                   => 5.012,
        'Module::CoreList'       => 0,
        'File::Basename'         => 0,
        'File::ShareDir'         => '1.03',
        'File::Find::Rule'       => '0.30',
        'File::Path'             => '2.00',
        'File::Spec'             => 0,
        'Hash::MoreUtils'        => '0.04',
        'List::MoreUtils'        => '0.04',
        'MooX::Cmd'              => 0,
        'MooX::Options'          => 0,
        'MooX::ConfigFromFile'   => 0,
        'MooX::Roles::Pluggable' => 0,
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
    share_dir => {
                   dist => [ 'share', ],
                 },
    meta_merge => {
                    resources => {
                                   repository => "https://github.com/rehsack/Packager-Utils",
                                 },
                  },
    test_files     => [ "t/*.t", "xt/*.t" ],
    add_to_cleanup => ['Packager-Utils-*'],
                                );

$builder->create_build_script();
