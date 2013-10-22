package Packager::Utils::Role::Packages::PkgSrc;

use Moo::Role;
use MooX::Options;

use Carp qw(carp croak);
use Carp::Assert qw(affirm);
use Cwd qw();
use File::Basename qw(fileparse);
use File::Spec qw();
use File::Find::Rule qw(find);
use File::pushd;
use IO::CaptureOutput qw(capture_exec);
use List::MoreUtils qw(zip);
use Text::Glob qw(match_glob);
use Text::Wrap qw(wrap);

# make it optional - with cache only ...
use File::Find::Rule::Age;

our $VERSION = '0.001';

option 'pkgsrc_base_dir' => (
                              is     => "lazy",
                              format => "s",
                              doc    => "Specify base directory of pkgsrc",
                            );

sub _build_pkgsrc_base_dir
{
    defined( $ENV{PKGSRCDIR} ) and return $ENV{PKGSRCDIR};

    my $self = $_[0];
    foreach my $dir (qw(. .. ../.. /usr/pkgsrc))
    {
        -d $dir
          and -f File::Spec->catfile( $dir, "mk", "bsd.pkg.mk" )
          and return Cwd::abs_path($dir);
    }

    return;
}

option 'pkgsrc_prefix' => (
    is     => "ro",                                            # XXX guess that using Alien::Packags
    format => "s",
    doc    => "Specify prefix directory of pkgsrc binaries",
                          );

has pkg_info_cmd => ( is => "lazy" );
has bmake_cmd    => ( is => "lazy" );

sub _build_pkg_info_cmd
{
    my $self = shift;
    File::Spec->catfile( $self->pkgsrc_prefix, "sbin", "pkg_info" );
}

sub _build_bmake_cmd
{
    my $self = shift;
    File::Spec->catfile( $self->pkgsrc_prefix, "bin", $^O eq "netbsd" ? "make" : "bmake" );
}

around "_build_installed_packages" => sub {
    my $next      = shift;
    my $self      = shift;
    my $installed = $self->$next(@_);

    -x $self->pkg_info_cmd or croak( "Can't exec " . $self->pkg_info_cmd . ": $!" );
    my ( $stdout, $stderr, $success, $exit_code ) = capture_exec( $self->pkg_info_cmd );
    $success or croak( "Error running " . $self->pkg_info_cmd . ": $stderr" );
    chomp $stdout;
    my @packages = split( "\n", $stdout );
    if ( $self->has_packages_pattern )
    {
        # XXX speed?
        my $rx_str =
          join( "|", map { Text::Glob::glob_to_regex_string($_) } @{ $self->packages_pattern } );
        @packages = grep { $_ =~ m/$rx_str/ } @packages;
    }
    my %havepkgs =
      map { $_ =~ m/^(.*)-(v?[0-9].*?)$/ ? ( $1 => $2 ) : ( $_ => 0E0 ) }
      map { ( split( m/\s+/, $_ ) )[0] } @packages;

    $installed->{pkgsrc} = \%havepkgs;

    return $installed;
};

around "_build_packages" => sub {
    my $next     = shift;
    my $self     = shift;
    my $packaged = $self->$next(@_);

    my $pkgsrc_base = $self->pkgsrc_base_dir();
    -d $pkgsrc_base or return $packaged;
    my %find_args = (
                      mindepth => 2,
                      maxdepth => 2
                    );

    if ( $self->cache_timestamp )
    {
        my $now      = time();
        my $duration = $now - $self->cache_timestamp;
        $find_args{age} = [ newer => "${duration}s" ];
    }

    $self->has_packages_pattern and $find_args{name} = $self->packages_pattern;

    my @pkg_dirs = find( directory => %find_args,
                         in        => $pkgsrc_base );

    @pkg_dirs or return $packaged;
    $self->cache_modified(time);

    foreach my $pkg_dir (@pkg_dirs)
    {
        # XXX File::Find::Rule extension ...
        -f File::Spec->catfile( $pkg_dir, "Makefile" ) or next;
        my $pkg_det = $self->_fetch_full_pkg_details($pkg_dir);
        $pkg_det or next;
        $packaged->{pkgsrc}->{ $pkg_det->{PKG_LOCATION} } = $pkg_det;
    }

    return $packaged;
};

has '_pkg_var_names' => (
    is      => 'ro',
    default => sub {
        return [
                 qw(DISTNAME DISTFILES),
                 qw(PKGNAME PKGVERSION MAINTAINER),
                 qw(HOMEPAGE LICENSE MASTER_SITES)
               ];
    },
    init_arg => undef
                        );

sub _get_pkg_vars
{
    my ( $self, $pkg_loc, $varnames ) = @_;
    $varnames or $varnames = $self->_pkg_var_names;
    my $varnames_str = join( " ", @$varnames );
    File::Spec->file_name_is_absolute($pkg_loc)
      or $pkg_loc = File::Spec->catdir( $self->pkgsrc_base_dir, $pkg_loc );
    my $last_dir = pushd($pkg_loc);
    my ( $stdout, $stderr, $success, $exit_code ) =
      capture_exec( $self->bmake_cmd, "show-vars", "VARNAMES=$varnames_str" );
    if ( $success and 0 == $exit_code )
    {
        chomp $stdout;
        my @vals = split( "\n", $stdout );
        return zip( @$varnames, @vals );
    }
    die $stderr;
}

sub _fetch_full_pkg_details
{
    my ( $self, $pkg_loc ) = @_;

    my %pkg_details;
    eval {
        my %pkg_vars = $self->_get_pkg_vars($pkg_loc);

        my $distver;
        if ( $pkg_vars{DISTNAME} =~ m/^(.*)-(v?[0-9].*?)$/ )
        {
            $pkg_vars{DISTNAME} = $1;
            $distver = $2;
        }

        my $pkgsrcdir = $self->pkgsrc_base_dir();

        $pkg_details{DIST_NAME}    = $pkg_vars{DISTNAME};
        $pkg_details{DIST_VERSION} = $distver;
        $pkg_details{DIST_FILE}    = $pkg_vars{DISTFILES};
        $pkg_details{PKG_NAME}     = $pkg_vars{PKGNAME};
        defined( $pkg_vars{PKGNAME} )
          and defined( $pkg_vars{PKGVERSION} )
          and $pkg_details{PKG_NAME} =~ s/-$pkg_vars{PKGVERSION}//;
        $pkg_details{PKG_VERSION}    = $pkg_vars{PKGVERSION};
        $pkg_details{PKG_MAINTAINER} = $pkg_vars{MAINTAINER};
        $pkg_details{PKG_INSTALLED} =
          defined( $self->installed_packages->{pkgsrc}->{ $pkg_details{PKG_NAME} } );
        ( $pkg_details{PKG_LOCATION} = $pkg_loc ) =~ s|$pkgsrcdir/||;
        $pkg_details{PKG_HOMEPAGE}     = $pkg_vars{HOMEPAGE};
        $pkg_details{PKG_LICENSE}      = $pkg_vars{LICENSE};
        $pkg_details{PKG_MASTER_SITES} = $pkg_vars{MASTER_SITES};
    };
    $@ and carp("$pkg_loc -- $@\n") and return;

    return \%pkg_details;
}

my %cpan2pkg_licenses = (
                          agpl_3      => 'gnu-agpl-v3',
                          apache_1_1  => 'apache-1.1',
                          apache_2_0  => 'apache-2.0',
                          artistic_1  => 'artistic',
                          artistic_2  => 'artistic-2.0',
                          bsd         => 'modified-bsd',
                          freebsd     => '2-clause-bsd',
                          gfdl_1_2    => 'gnu-fdl-v1.2',
                          gfdl_1_3    => 'gnu-fdl-v1.3',
                          gpl_1       => 'gnu-gpl-v1',
                          gpl_2       => 'gnu-gpl-v2',
                          gpl_3       => 'gnu-gpl-v3',
                          lgpl_2_1    => 'gnu-lgpl-v2.1',
                          lgpl_3_0    => 'gnu-lgpl-v3',
                          mit         => 'mit',
                          mozilla_1_0 => 'mpl-1.0',
                          mozilla_1_1 => 'mpl-1.1',
                          perl_5      => '${PERL5_LICENSE}',
                          qpl_1_0     => 'qpl-v1.0',
                          zlib        => 'zlib',
                        );

sub _create_pkgsrc_p5_package_info
{
    my ( $self, $minfo, $pkg_det ) = @_;

    my $pkgsrc_base = $self->pkgsrc_base_dir();
    my $pkg_tpl_vars = [
        qw(SVR4_PKGNAME CATEGORIES COMMENT HOMEPAGE LICENSE MAINTAINER CONFLICTS SUPERSEDES USE_LANGUAGES USE_TOOLS)
    ];
          $pkg_det
      and $minfo->{PKG4MOD}
      and $pkg_det->{cpan}->{ $minfo->{PKG4MOD} }
      and $pkg_det = $pkg_det->{cpan}->{ $minfo->{PKG4MOD} }->[0];    # deref search result
    $pkg_det
      and $pkg_det->{PKG_LOCATION}
      and $pkg_det = { %$pkg_det, $self->_get_pkg_vars( $pkg_det->{PKG_LOCATION}, $pkg_tpl_vars ) };
          $pkg_det
      and $pkg_det->{SVR4_PKGNAME}
      and index( $pkg_det->{SVR4_PKGNAME}, $pkg_det->{PKG_NAME} ) != -1
      and delete $pkg_det->{SVR4_PKGNAME};

    my $pinfo = {
        PKG_NAME   => "p5-\${DISTNAME}",
        DIST_NAME  => $minfo->{DIST_NAME},
        CATEGORIES => $minfo->{CATEGORIES},
        LICENSE    => join(
            " AND ",
            map {
                    $cpan2pkg_licenses{$_}
                  ? $cpan2pkg_licenses{$_}
                  : "unknown($_)"
              } @{ $minfo->{PKG_LICENSE} }
        ),
        HOMEPAGE   => 'https://metacpan.org/release/' . $minfo->{DIST},
        MAINTAINER => 'pkgsrc-users@NetBSD.org',
        COMMENT    => ucfirst( $minfo->{PKG_COMMENT} ),
        LOCALBASE  => $pkgsrc_base,
                };

    $pinfo->{CATEGORIES} = [qw(devel)]
      unless ( $pinfo->{CATEGORIES} and @{ $pinfo->{CATEGORIES} } );
    $minfo->{DIST_URL} =~ m|authors/id/(\w/\w\w/[^/]+)|
      and $pinfo->{MASTER_SITES} = '${MASTER_SITE_PERL_CPAN:=../../authors/id/' . $1 . '/}',
      $pkg_det
      and $pkg_det->{PKG_LOCATION}
      and $pinfo->{ORIGIN} = File::Spec->catdir( $pkgsrc_base, $pkg_det->{PKG_LOCATION} );
    $pinfo->{ORIGIN}
      or $pinfo->{ORIGIN} =
      File::Spec->catdir( $pkgsrc_base, $pinfo->{CATEGORIES}->[0], 'p5-' . $minfo->{DIST} );

    if ( $minfo->{PKG_DESCR} )
    {
        $pinfo->{DESCRIPTION} = wrap( "", "", $minfo->{PKG_DESCR} );
    }
    elsif ( $minfo->{PKG_COMMENT} )
    {
        $pinfo->{DESCRIPTION} = wrap( "", "", $minfo->{PKG_COMMENT} );
    }
    else
    {
        $pinfo->{DESCRIPTION} = "Perl module for " . $minfo->{PKG4MOD};
    }

    my ( $bn, $dir, $sfx ) = fileparse( $minfo->{DIST_FILE} );
    $sfx = substr( $bn, length( $minfo->{DIST_NAME} ) );
    $sfx ne ".tar.gz" and $pinfo->{EXTRACT_SUFX} = $sfx;

    # XXX check MAINTAINER / HOMEPAGE / CATEGORIES
    @{ $pinfo->{CATEGORIES} } or $pinfo->{CATEGORIES} = $pkg_det->{CATEGORIES} if ($pkg_det);

    foreach my $keepvar (qw(SVR4_PKGNAME USE_LANGUAGES USE_TOOLS PKG_LOCATION))
    {
        defined $pkg_det->{$keepvar} and $pinfo->{$keepvar} = $pkg_det->{$keepvar};
    }

    $pinfo->{EXTRA_VARS}->{PERL5_PACKLIST} =
      File::Spec->catdir( 'auto', split( '-', $minfo->{DIST} ), '.packlist' );

    # XXX somehow a PKG_LOCATION proposal could be created???

    my ( %bldreq, %bldrec, %rtreq, %rtrec, %bldcon, %rtcon );
    foreach my $dep ( @{ $minfo->{PKG_PREREQ} } )
    {
        my $req;
        my $dep_dist = $self->get_distribution_for_module( $dep->{module}, $dep->{version} );
        my $dep_det =
             $dep_dist
          && $dep_dist->{cpan}
          && $dep_dist->{cpan}->{ $dep->{module} } ? $dep_dist->{cpan}->{ $dep->{module} } : undef;
        $dep_det
          or $req = {
                      PKG_NAME     => $dep->{module},
                      REQ_VERSION  => $dep->{version},    # XXX numify? -[0-9]*
                      PKG_LOCATION => 'n/a',
                    };
        $dep_det and @{$dep_det} == 1 and $req = {
            PKG_NAME    => $dep_det->[0]->{PKG_NAME},
            REQ_VERSION => $dep->{version},          # XXX numify? -[0-9]*, size matters (see M::B)!
            PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
                                                 };
        $dep_det and @{$dep_det} > 1 and $req = {
            PKG_NAME    => $dep_det->[0]->{PKG_NAME},
            REQ_VERSION => $dep->{version},          # XXX numify? -[0-9]*, size matters (see M::B)!
            CORE_NAME   => 'perl',                   # XXX find lowest reqd. Perl5 version!
            CORE_VERSION => $dep_det->[1]->{DIST_VERSION},    # XXX find lowest reqd. Perl5 version!
            PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
                                                };

        $req->{PKG_NAME} eq 'perl' and next;                  # core only ...
        ( defined $req->{CORE_NAME} )
          and !$req->{REQ_VERSION}
          and next;    # -[0-9]* and in core means core is enough

        $minfo->{GENERATOR}
          and $minfo->{GENERATOR} eq 'Module::Build'
          and $pinfo->{EXTRA_VARS}->{PERL5_MODULE_TYPE} = 'Module::Build';

        $minfo->{GENERATOR}
          and $minfo->{GENERATOR} eq 'Module::Install'
          and $pinfo->{EXTRA_VARS}->{PERL5_MODULE_TYPE} = 'Module::Install::Bundled';

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
        $dep->{phase} eq 'develop'
          and $dep->{relationship} eq 'requires'
          and $bldreq{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'requires'
          and $bldreq{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'develop'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{ $req->{PKG_NAME} } = $req;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{ $req->{PKG_NAME} } = $req;
        $dep->{phase} eq 'develop'
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

    #while( my ($dept, $deps) = each %depdefs )
    foreach my $dept ( keys %depdefs )
    {
        my $deps = $depdefs{$dept};
        unless ( $dept =~ m/CONFLICT/ )
        {
            foreach my $depn ( keys %$deps )
            {
                -f File::Spec->catfile( $pkgsrc_base, $deps->{$depn}->{PKG_LOCATION},
                                        "buildlink3.mk" )
                  or next;
                my $dep = delete $deps->{$depn};
                push(
                      @{ $pinfo->{INCLUDES} },
                      File::Spec->catfile( "..", "..", $dep->{PKG_LOCATION}, "buildlink3.mk" )
                    );
                $dept =~ m/BUILD/ and $pinfo->{EXTRA_VARS}->{"BUILDLINK_DEPMETHOD.$depn"} = 'build';
            }
        }

        push( @{ $pinfo->{$dept} }, sort { $a->{PKG_NAME} cmp $b->{PKG_NAME} } values %$deps );
    }

    push( @{ $pinfo->{INCLUDES} }, "../../lang/perl5/module.mk" );

    return $pinfo;
}

around "create_package_info" => sub {
    my $next  = shift;
    my $self  = shift;
    my $pinfo = $self->$next(@_);

    my ( $minfo, $pkg_det ) = @_;
    defined $minfo->{cpan}
      and $pinfo->{pkgsrc} = $self->_create_pkgsrc_p5_package_info( $minfo->{cpan}, $pkg_det );

    return $pinfo;
};

=head1 NAME

Packager::Utils::Role::Packages::PkgSrc - Support PkgSrc packagers

=cut

1;
