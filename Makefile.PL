use strict;
use warnings;

use 5.012;

use ExtUtils::MakeMaker;
use File::ShareDir::Install 0.03;

install_share 'share';

my %RUN_DEPS = (
    'perl'                   => 5.012,
    'Alien::Packages'        => '0.003',
    'CPAN::Changes'          => 0,
    'Class::Load'            => 0,
    'Digest::MD5'            => 0,
    'File::Basename'         => 0,
    'File::ShareDir'         => '1.03',
    'File::Find::Rule'       => '0.30',
    'File::Path'             => '2.00',
    'File::Slurp::Tiny'      => 0,
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
);
my %CONFIGURE_DEPS = (
    'ExtUtils::MakeMaker' => 0,
    'File::ShareDir::Install' => '0.03'
);
my %BUILD_DEPS = (
    'File::ShareDir::Install' => '0.03'
    );

my %TEST_DEPS = (
    'Test::More' => 0.90,
);

WriteMakefile1(
    MIN_PERL_VERSION => '5.012',
    META_ADD         => {
        'meta-spec' => { version => 2 },
        resources   => {
                       repository => {
                                       url  => 'git://github.com/rehsack/Packager-Utils.git',
                                       web  => 'https://github.com/rehsack/Packager-Utils',
                                       type => 'git',
                                     },
            license    => 'http://dev.perl.org/licenses/',
        },
        prereqs => {
            develop => {
                requires => {
                    'Test::CPAN::Changes'                 => 0,
                    'Test::CheckManifest'                 => 0,
                    'Test::Pod'                           => 0,
                    'Test::Pod::Coverage'                 => 0,
                    'Test::Pod::Spelling::CommonMistakes' => 0,
                },
            },
            configure => {
                requires => {%CONFIGURE_DEPS},
            },
            build   => { requires => {%BUILD_DEPS} },
            test    => { requires => {%TEST_DEPS} },
            runtime => {
                requires => {
                    %RUN_DEPS,
                },
                recommends => {
                                'Log::Dispatch'               => 0,
                                'Log::Any::Adapter::Dispatch' => 0,
                              },
            },
        },
    },
    NAME           => 'Packager::Utils',
    VERSION_FROM   => 'lib/Packager/Utils.pm',
    ABSTRACT_FROM  => 'lib/Packager/Utils.pm',
    LICENSE        => 'perl',
    AUTHOR         => [ q{Jens Rehsack <rehsack@cpan.org>} ],
    PREREQ_PM      => \%RUN_DEPS,
    BUILD_REQUIRES => \%BUILD_DEPS,
    TEST_REQUIRES  => \%TEST_DEPS,
    test           => { TESTS => 't/*.t xt/*.t' },
);

sub WriteMakefile1
{    # originally written by Alexandr Ciornii, version 0.21. Added by eumm-upgrade.
    my %params       = @_;
    my $eumm_version = $ExtUtils::MakeMaker::VERSION;
    $eumm_version = eval $eumm_version;
    die "EXTRA_META is deprecated" if ( exists( $params{EXTRA_META} ) );
    die "License not specified"    if ( !exists( $params{LICENSE} ) );
    if ( $params{TEST_REQUIRES} and ( $eumm_version < 6.6303 ) )
    {
        if ( $params{BUILD_REQUIRES} )
        {
            $params{BUILD_REQUIRES} = { %{ $params{BUILD_REQUIRES} }, %{ $params{TEST_REQUIRES} } };
        }
        else
        {
            $params{BUILD_REQUIRES} = delete $params{TEST_REQUIRES};
        }
    }
    if ( $params{BUILD_REQUIRES} and ( $eumm_version < 6.5503 ) )
    {
        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM} = { %{ $params{PREREQ_PM} || {} }, %{ $params{BUILD_REQUIRES} } };
        delete $params{BUILD_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES}    if ( $eumm_version < 6.52 );
    delete $params{MIN_PERL_VERSION}      if ( $eumm_version < 6.48 );
    delete $params{META_MERGE}            if ( $eumm_version < 6.46 );
    delete $params{META_ADD}{prereqs}     if ( $eumm_version < 6.58 );
    delete $params{META_ADD}{'meta-spec'} if ( $eumm_version < 6.58 );
    delete $params{META_ADD}              if ( $eumm_version < 6.46 );
    delete $params{LICENSE}               if ( $eumm_version < 6.31 );
    delete $params{AUTHOR}                if ( $] < 5.005 );
    delete $params{ABSTRACT_FROM}         if ( $] < 5.005 );
    delete $params{BINARY_LOCATION}       if ( $] < 5.005 );

    # more or less taken from Moose' Makefile.PL
    if ( $params{CONFLICTS} )
    {
        my $ok = CheckConflicts(%params);
        exit(0) if ( $params{PREREQ_FATAL} and not $ok );
        my $cpan_smoker = grep { $_ =~ m/(?:CR_SMOKER|CPAN_REPORTER|AUTOMATED_TESTING)/ } keys %ENV;
        unless ( $cpan_smoker || $ENV{PERL_MM_USE_DEFAULT} )
        {
            sleep 4 unless ($ok);
        }
        delete $params{CONFLICTS};
    }

    WriteMakefile(%params);
}

package MY;

use File::ShareDir::Install qw(postamble);

1;
