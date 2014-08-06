package Packager::Utils::Role::Packages::Bitbake;

use strict;
use warnings;

use Digest::MD5 qw();
use Moo::Role;
use MooX::Options;
use File::pushd;
use File::Find::Rule;
use File::Basename;
use File::Slurp::Tiny 'read_file';
use Params::Util qw(_ARRAY _ARRAY0 _HASH _HASH0 _STRING);
use Text::Wrap qw(wrap);

# make it optional - with cache only ...
use File::Find::Rule::Age;
with "Packager::Utils::Role::Async", "MooX::Log::Any";

our $VERSION = '0.001';

option 'bspdir' => (
    is     => "ro",
    format => "s",
    coerce => sub {
        defined $_[0] or return;
        -d $_[0] or die "$_[0]: $!";
        return Cwd::abs_path( $_[0] );
    },
    doc      => "Specify base directory of bitbake",
    long_doc => "Must be used to specify"
      . " the base directory for "
      . "bspdir directory.\n\nExamples: "
      . "--bspdir /home/user/bsp",
);

option 'bitbake_bblayers_conf' => (
    is     => "ro",
    format => "s",
    coerce => sub {
        defined $_[0] or return;
        -f $_[0] or die "$_[0]: $!";
        return Cwd::abs_path( $_[0] );
    },
    doc      => "Specify base path of bblayers.conf file",
    long_doc => "Must be used to specify"
      . " the base directory for "
      . "bitbake source directory.\n\nExamples: "
      . "--bitbake_bblayers_conf /home/user/fsl-community-bsp/yocto/conf/bblayers.conf",
);

option yocto_build_dir => (
    is     => "lazy",
    format => "s",
    doc    => "Specify base path of bblayers.conf file",
);

sub _build_yocto_build_dir
{
    my $yoctodir = dirname( dirname( $_[0]->bitbake_bblayers_conf ) );
    -d $yoctodir or die "$!";
    return $yoctodir;
}

has bitbake_cmd => ( is => "lazy" );

sub _build_bitbake_cmd
{
    my $bb_cmd = IPC::Cmd::can_run("bitbake");
    return $bb_cmd;
}

has '_bb_var_names' => (
    is      => 'ro',
    default => sub {
        return [ qw(DISTRO_NAME SRC_URI DISTRO_VERSION), qw(PN PV PR FILE_DIRNAME MAINTAINER), qw(HOMEPAGE LICENSE) ];
    },
    init_arg => undef
);

sub _get_bb_vars
{
    my ( $self, $pkg_name, $varnames, $cb ) = @_;
    $varnames or $varnames = $self->_bb_var_names;
    my $yoctodir = $self->yocto_build_dir();

    my ( $stdout, $stderr );
    my %proc_cfg = (
        command => [ $self->bitbake_cmd, "-e", "$pkg_name" ],
        stdout  => {
            on_read => sub {
                my ( $stream, $buffref ) = @_;
                $stdout .= $$buffref;
                $$buffref = "";
                return 0;
            },
        },
        stderr => {
            on_read => sub {
                my ( $stream, $buffref ) = @_;
                $stderr .= $$buffref;
                $$buffref = "";
                return 0;
            },
        },
        on_finish => sub {
            my ( $proc, $exitcode ) = @_;
            if ( $exitcode != 0 )
            {
                $self->log->warning($stderr);
                return $cb->();
            }
            chomp $stdout;
            my @vals = grep { $_ !~ m/^#/ } split( "\n", $stdout );
            my %allvars = map { $_ =~ m/(\w+)="([^"]*)"/ ? ( $1, $2 ) : () } @vals;

            my %varnames;
            @varnames{@$varnames} = @allvars{@$varnames};
            $cb->( \%varnames );
        },
        on_exception => sub {
            my ( $exception, $errno, $exitcode ) = @_;
            $exception and die $exception;
            die $self->bmake_cmd . " died with (exit=$exitcode): " . $stderr;
        },
    );

    my $process = IO::Async::Process->new(%proc_cfg);
    do
    {
        my $last_dir = pushd($yoctodir);
        $self->loop->loop_once(0);
        eval { $self->loop->add($process); };
    } while ($@);

    return;
}

sub _fetch_full_bb_details
{
    my ( $self, $file, $cb ) = @_;

    my $bbfile;
    my $recipe = ( split( "_", $bbfile = fileparse( $file, qr/\.[^.]*/ ) ) )[0];
    $self->_get_bb_vars(
        $recipe,
        $self->_bb_var_names,
        sub {
            my %pkg_vars;
            _HASH( $_[0] ) and %pkg_vars = %{ $_[0] };

            my %pkg_details;

            #... mapping
            $pkg_details{DIST_NAME} = fileparse( ( split( /\s+/, $pkg_vars{SRC_URI} ) )[0], @{ $self->_archive_extensions } );
            $pkg_details{DIST_NAME} =~ m/^(.*)-(v?[0-9].*?)$/ and ( @pkg_details{qw(DIST_NAME DIST_VERSION)} ) = ( $1, $2 );
            defined $pkg_details{DIST_VERSION} or $pkg_details{DIST_VERSION} = $pkg_vars{PV};
            $pkg_details{DIST_FILE}      = ( fileparse( ( split( /\s+/, $pkg_vars{SRC_URI} ) )[0] ) )[0];
            $pkg_details{PKG_NAME}       = $pkg_vars{PN};
            $pkg_details{PKG_VERSION}    = defined $pkg_vars{PR} ? join( "-", @pkg_vars{ "PV", "PR" } ) : $pkg_vars{PV};
            $pkg_details{PKG_MAINTAINER} = $pkg_vars{MAINTAINER};
            $pkg_details{PKG_LOCATION}   = File::Spec->catfile( $pkg_vars{FILE_DIRNAME}, $bbfile );
            $pkg_details{PKG_HOMEPAGE}   = $pkg_vars{HOMEPAGE};
            $pkg_details{PKG_LICENSE}    = $pkg_vars{LICENSE};
            $pkg_details{PKG_MASTER_SITES} =
              ( fileparse( ( split( /\s+/, $pkg_vars{SRC_URI} ) )[0], @{ $self->_archive_extensions } ) )[1];

            $cb->( \%pkg_details );
        }
    );

    return;
}

around "_build_packages" => sub {
    my $next     = shift;
    my $self     = shift;
    my $packaged = $self->$next(@_);

    my $bspdir           = $self->bspdir();
    my $bitbake_bblayers = $self->bitbake_bblayers_conf();

    -d $bspdir or return $packaged;

    #get bblayers file
    my $layer_conf = read_file( $bitbake_bblayers, binmode => 'encoding(UTF-8)' );
    my $tag = "{BSPDIR}";

    my @src_paths;
    while ( $layer_conf =~ m/\Q$tag\E([^ ]+)/g )
    {
        push @src_paths, File::Spec->catdir( $bspdir, $1 );
    }

    my %find_args = (
        mindepth => 3,
        maxdepth => 3,
        name     => "*.bb",
    );

    if ( $self->cache_timestamp )
    {
        my $now      = time();
        my $duration = $now - $self->cache_timestamp;
        $find_args{age} = [ newer => "${duration}s" ];
    }

    $self->has_packages_pattern and $find_args{name} = $self->packages_pattern;

    my @files = find(
        file => %find_args,
        in   => \@src_paths
    );

    # my @files = File::Find::Rule->file()->name('*.bb')->maxdepth(3)->in(@src_paths);

    my $pds = 0;
    foreach my $file (@files)
    {
        ++$pds;
        $self->_fetch_full_bb_details(
            $file,
            sub {

                my $pkg_det = shift;
                --$pds;
                _HASH($pkg_det)
                  and $packaged->{bitbake}->{ $pkg_det->{PKG_LOCATION} } =
                  $pkg_det;    #aufrufen um dinge in die datenbank zu schreiben/cachen.
            }
        );
        do
        {
            $self->loop->loop_once(0);
        } while ( $pds > 0 );
    }

    @files and $self->cache_modified(time);

    return $packaged;
};

around "create_package_info" => sub {
    my $next  = shift;
    my $self  = shift;
    my $pinfo = $self->$next(@_);

    my ( $minfo, $pkg_det, $bitbake_pinfo ) = @_;
    defined $minfo->{cpan}
      and $bitbake_pinfo = $self->_create_bitbake_package_info( $minfo->{cpan}, $pkg_det )
      and $pinfo->{bitbake} = $bitbake_pinfo;

    return $pinfo;
};

my %cpan2bb_licenses = (
    agpl_3      => ['AGPL-3.0'],
    apache_1_1  => ['Apache-1.1'],
    apache_2_0  => ['Apache-2.0'],
    artistic_1  => ['Artistic-1.0'],
    artistic_2  => ['Artistic-2.0'],
    bsd         => ['BSD-3-Clause'],
    freebsd     => ['BSD-2-Clause'],
    gfdl_1_2    => ['GFDL-1.2'],
    gfdl_1_3    => ['GFDL-1.3'],
    gpl_1       => ['GPL-1.0'],
    gpl_2       => ['GPL-2.0'],
    gpl_3       => ['GPL-3.0'],
    lgpl_2_1    => ['LGPL-2.1'],
    lgpl_3_0    => ['LGPL-3.0'],
    mit         => ['MIT'],
    mozilla_1_0 => ['MPL-1.0'],
    mozilla_1_1 => ['MPL-1.1'],
    perl_5      => [ 'Artistic-1.0', 'GPL-2.0' ],
    qpl_1_0     => ['QPL-1.0'],
    zlib        => ['Zlib'],
);

my %known_md5s;

sub _create_bitbake_package_info
{
    my ( $self, $minfo, $pkg_det ) = @_;

    my $bspdir = $self->bspdir;
    $bspdir or return;

    my $pinfo = {
        DIST       => $minfo->{DIST},
        DIST_NAME  => $minfo->{DIST_NAME},
        CATEGORIES => $minfo->{CATEGORIES},
        LICENSE    => join( " | ",
            map { ( $cpan2bb_licenses{$_} ? @{ $cpan2bb_licenses{$_} } : ("unknown($_)") ) }
              @{ _ARRAY( $minfo->{PKG_LICENSE} ) // [ $minfo->{PKG_LICENSE} ] } ),
        HOMEPAGE     => 'https://metacpan.org/release/' . $minfo->{DIST},
        MAINTAINER   => 'Poky <poky@yoctoproject.org>',
        COMMENT      => ucfirst( $minfo->{PKG_COMMENT} ),
        LOCALBASE    => File::Spec->catdir( $bspdir, qw(sources meta-cpan) ),
        PKG4MOD      => $minfo->{PKG4MOD},
        DIST_URL     => $minfo->{DIST_URL},
        BUILDER_TYPE => "cpan",
    };

    $pinfo->{LICENSE_FILES} = join(
        " \\\n",
        map
        {
            (
                $cpan2bb_licenses{$_}
                ? (
                    map {
                        my $l = $_;
                        my $fqln = File::Spec->catfile( $self->bspdir, qw(sources poky meta files common-licenses), $l );
                        unless ( defined $known_md5s{$fqln} )
                        {
                            my $ctx = Digest::MD5->new();
                            my $data = read_file($fqln);
                            $ctx->add($data);
                            $known_md5s{$fqln} = $ctx->hexdigest;
                        }
                        "file://\${COMMON_LICENSE_DIR}/$l;md5=$known_md5s{$fqln}";
                    } @{ $cpan2bb_licenses{$_} }
                  )
                : ("unknown($_)")
              )
        } @{ _ARRAY( $minfo->{PKG_LICENSE} ) // [ $minfo->{PKG_LICENSE} ] }
    );

    #$minfo->{DIST_URL} =~ m|authors/id/(\w/\w\w/[^/]+/.*)|
    #  and $pinfo->{MASTER_SITES} = 'http://search.cpan.org/CPAN/authors/id/' . $1 . '/';
    #    $pkg_det
    #      and $pinfo->{PKG_LOCATION}
    #      and $pinfo->{ORIGIN} = File::Spec->catdir( $pinfo->{LOCALBASE}, $pinfo->{PKG_LOCATION} ); # bb-name can hacked in here XXX

    $pinfo->{PKG_LOCATION} = File::Spec->catdir( $pinfo->{CATEGORIES}->[0], lc( $minfo->{DIST} ) . "-perl" )
      and $pinfo->{ORIGIN} = File::Spec->catfile(
        $pinfo->{LOCALBASE},
        $pinfo->{PKG_LOCATION},
        join( "_", join( "-", lc( $minfo->{DIST} ), "perl" ), $minfo->{DIST_VER} )
      )
      and $pinfo->{IS_ADDED} = $pinfo->{CATEGORIES}->[0]
      unless $pinfo->{ORIGIN};

    if ( $minfo->{PKG_DESCR} )
    {
        $minfo->{PKG_DESCR} =~ s/^(.*?)\n\n.*/$1/ms;
        $minfo->{PKG_DESCR} =~ s/\n/ /ms;
        local $Text::Wrap::separator = " \\\n";
        local $Text::Wrap::columns   = 72;
        $pinfo->{DESCRIPTION} = wrap( "", "", $minfo->{PKG_DESCR} );
    }
    elsif ( $minfo->{PKG_COMMENT} )
    {
        local $Text::Wrap::separator = " \\\n";
        local $Text::Wrap::columns   = 72;
        $pinfo->{DESCRIPTION} = wrap( "", "", $minfo->{PKG_COMMENT} );
    }
    else
    {
        $pinfo->{DESCRIPTION} = "Perl module for " . $minfo->{PKG4MOD};
    }

    $minfo->{GENERATOR}
      and $minfo->{GENERATOR} eq 'Module::Build::Tiny'
      and $pinfo->{BUILDER_TYPE} = 'cpan_build';

    $minfo->{GENERATOR}
      and $minfo->{GENERATOR} eq 'Module::Build'
      and $pinfo->{BUILDER_TYPE} = 'cpan_build';

    $minfo->{GENERATOR}
      and $minfo->{GENERATOR} eq 'Module::Install'
      and $pinfo->{BUILDER_TYPE} = 'cpan';

    my ( %bldreq, %bldrec, %rtreq, %rtrec, %bldcon, %rtcon, @missing );
    foreach my $dep ( @{ $minfo->{PKG_PREREQ} } )
    {
        my $req;
        my $dep_dist = $self->get_distribution_for_module( $dep->{module}, $dep->{version} );
        "perl" eq $dep->{module}
          and push @{ $pinfo->{EXTRA_VARS}->{PERL5_REQD} },
          join( ".", grep { defined $_ and $_ } ( map { $_ =~ s/^0*//; $_ } split( qr/\./, $dep->{version} ) ) )
          and next;

        if ( $dep_dist && $dep_dist->{cpan} && $dep_dist->{cpan}->{ $dep->{module} } )
        {
            my $dep_det = $dep_dist->{cpan}->{ $dep->{module} };
            $dep_det and @{$dep_det} == 1 and $dep_det->[0]->{PKG_NAME} ne "perl" and $req = {
                PKG_NAME     => $dep_det->[0]->{PKG_NAME},
                REQ_VERSION  => $dep->{version},                 # XXX numify? -[0-9]*, size matters (see M::B)!
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
            };
            $dep_det and @{$dep_det} == 1 and $dep_det->[0]->{PKG_NAME} eq "perl" and $req = {
                PKG_NAME     => $dep_det->[0]->{PKG_NAME},
                CORE_NAME    => $dep_det->[0]->{PKG_NAME},
                CORE_VERSION => $dep->{version},                 # XXX numify? -[0-9]*, size matters (see M::B)!
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
                (
                    defined $dep_det->[0]->{LAST_VERSION} ? ( LAST_VERSION => $dep_det->[0]->{LAST_VERSION} )
                    : (),
                ),
                (
                    defined $dep_det->[0]->{DEPR_VERSION} ? ( DEPR_VERSION => $dep_det->[0]->{DEPR_VERSION} )
                    : (),
                ),
            };

            $dep_det and @{$dep_det} > 1 and $req = {
                PKG_NAME     => $dep_det->[0]->{PKG_NAME},
                REQ_VERSION  => $dep->{version},                  # XXX numify? -[0-9]*, size matters (see M::B)!
                CORE_NAME    => $dep_det->[1]->{PKG_NAME},        # XXX find lowest reqd. Perl5 version!
                CORE_VERSION => $dep_det->[1]->{DIST_VERSION},    # XXX find lowest reqd. Perl5 version!
                (
                    defined $dep_det->[1]->{LAST_VERSION} ? ( LAST_VERSION => $dep_det->[1]->{LAST_VERSION} )
                    : (),
                ),
                (
                    defined $dep_det->[1]->{DEPR_VERSION} ? ( DEPR_VERSION => $dep_det->[1]->{DEPR_VERSION} )
                    : (),
                ),
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
            };
        }
        else
        {
            $req = {
                PKG_NAME     => $dep->{module},
                REQ_VERSION  => $dep->{version},    # XXX numify? -[0-9]*
                PKG_LOCATION => 'n/a',
            };
            $dep->{relationship} =~ m/^(?:requires|recommends)$/
              and $dep->{phase} =~ m/^(?:configure|build|test|runtime)$/
              and push( @missing, $req );
            next;
        }

        my ( $ncver, $cvernm );
        defined $req->{CORE_NAME}
          and $ncver = scalar( split( qr/\./, $req->{CORE_VERSION} ) )
          and $cvernm = ( $ncver <= 2 ? $req->{CORE_VERSION} . ( ".0" x ( 3 - $ncver ) ) : $req->{CORE_VERSION} ),
          and version->parse($cvernm) <= version->parse($])
          and push @{ $pinfo->{EXTRA_VARS}->{PERL5_REQD} }, "$req->{CORE_VERSION}	# $dep->{module} >= $dep->{version}"
          and next
          unless ( $req->{LAST_VERSION} or $req->{DEPR_VERSION} );

              $req->{PKG_NAME} eq 'Module::Build'
          and $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'requires'
          and $req->{CORE_VERSION}
          and next;

              $req->{PKG_NAME} eq 'ExtUtils::MakeMaker'
          and $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'requires'
          and $req->{CORE_VERSION}
          and next;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'requires'
          and $bldreq{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'build'
          and $dep->{relationship} eq 'requires'
          and $bldreq{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'requires'
          and $bldreq{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'build'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'build'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'runtime'
          and $dep->{relationship} eq 'requires'
          and $rtreq{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'runtime'
          and $dep->{relationship} eq 'recommends'
          and $rtrec{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'runtime'
          and $dep->{relationship} eq 'conflicts'
          and $rtcon{ $req->{PKG_NAME} } = $req;
    }

    foreach my $req (@missing)
    {
        $self->log->error("Missing $req->{PKG_NAME} $req->{REQ_VERSION}");
    }

    foreach my $pkg ( keys %rtrec )
    {
        defined $rtreq{$pkg} and $rtreq{$pkg} = delete $rtrec{$pkg};
    }

    foreach my $pkg ( keys %bldrec )
    {
        defined $bldreq{$pkg} and $bldreq{$pkg} = delete $bldrec{$pkg};
    }

    foreach my $pkg ( keys %bldreq )
    {
        defined $rtreq{$pkg} and $rtreq{$pkg} = delete $bldreq{$pkg};
    }

    my %depdefs = (
        BUILD_REQUIRES   => \%bldreq,
        BUILD_RECOMMENDS => \%bldrec,
        BUILD_CONFLICTS  => \%bldcon,
        REQUIRES         => \%rtreq,
        RECOMMENDS       => \%rtrec,
        CONFLICTS        => \%rtcon,
    );

    foreach my $dept ( keys %depdefs )
    {
        my $deps = $depdefs{$dept};
        push( @{ $pinfo->{$dept} }, sort { $a->{PKG_NAME} cmp $b->{PKG_NAME} } values %$deps );
    }

    return $pinfo;
}

1;
