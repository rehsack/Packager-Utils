package Packager::Utils::Role::Packages::PkgSrc;

use Moo::Role;
use MooX::Options;

use v5.12;

use Alien::Packages::Pkg_Info::pkgsrc ();
use CPAN::Changes qw();
use Carp qw(carp croak);
use Carp::Assert qw(affirm);
use Cwd qw();
use File::Basename qw(dirname fileparse);
use File::Find::Rule qw(find);
use File::Slurp::Tiny qw(read_file);
use File::Spec qw();
use File::pushd;
use IO::CaptureOutput qw(capture_exec);
use List::MoreUtils qw(zip);
use Params::Util qw(_ARRAY _ARRAY0 _HASH _HASH0 _STRING);
use Text::Glob qw(match_glob);
use Text::Wrap qw(wrap);
use Unix::Statgrab qw();

# make it optional - with cache only ...
use File::Find::Rule::Age;

with "Packager::Utils::Role::Async", "MooX::Log::Any";

our $VERSION = '0.001';

option 'pkgsrc_base_dir' => (
    is     => "lazy",
    format => "s",
    coerce => sub {
        defined $_[0] or return;
        -d $_[0] or die "$_[0]: $!";
        my $bsd_pkg_mk = File::Spec->catfile( $_[0], "mk", "bsd.pkg.mk" );
        -f $bsd_pkg_mk or die "$bsd_pkg_mk: $!";
        return Cwd::abs_path( $_[0] );
    },
    doc      => "Specify base directory of pkgsrc",
    long_doc => "Can be used to specify or "
      . "override the base directory for "
      . "pkgsrc packages.\n\nExamples: "
      . "--pkgsrc-base-dir /home/user/pkgscr",
);

sub _build_pkgsrc_base_dir
{
    defined( $ENV{PKGSRCDIR} ) and return $ENV{PKGSRCDIR};

    my $self = $_[0];
    foreach my $dir (qw(. .. ../.. /usr/pkgsrc))
    {
        -d $dir
          and -f File::Spec->catfile( $dir, "mk", "bsd.pkg.mk" )
          and return $dir;
    }

    return;
}

# XXX guess that using Alien::Packags
option 'pkgsrc_prefix' => (
                            is        => "lazy",
                            format    => "s",
                            predicate => 1,
                            doc       => "Specify prefix directory of pkgsrc binaries",
                          );

sub _build_pkgsrc_prefix
{
    my $self = shift;
    my ( $name, $path, $suffix ) = fileparse( $self->pkg_info_cmd );
    dirname($path);
}

has pkg_info_cmd => (
                      is        => "lazy",
                      predicate => 1
                    );
has bmake_cmd => ( is => "lazy" );

sub _build_pkg_info_cmd
{
    my $self = shift;
    $self->has_pkgsrc_prefix
      and return File::Spec->catfile( $self->pkgsrc_prefix, "sbin", "pkg_info" );
    return Alien::Packages::Pkg_Info::pkgsrc::usable();
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
    defined $pkgsrc_base or return $packaged;
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
    my $max_procs = Unix::Statgrab::get_host_info()->ncpus(0) * 4;
    my $pds       = 0;

    foreach my $pkg_dir (@pkg_dirs)
    {
        # XXX File::Find::Rule extension ...
        -f File::Spec->catfile( $pkg_dir, "Makefile" ) or next;
        ++$pds;
        $self->_fetch_full_pkg_details(
            $pkg_dir,
            sub {
                my $pkg_det = shift;
                --$pds;
                _HASH($pkg_det) and $packaged->{pkgsrc}->{ $pkg_det->{PKG_LOCATION} } = $pkg_det;
            }
        );
        do
        {
            $self->loop->loop_once(0);
        } while ( $pds > $max_procs );
    }

    do
    {
        $self->loop->loop_once(undef);
    } while ($pds);

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
    my ( $self, $pkg_loc, $varnames, $cb ) = @_;
    $varnames or $varnames = $self->_pkg_var_names;
    my $varnames_str = join( " ", @$varnames );
    File::Spec->file_name_is_absolute($pkg_loc)
      or $pkg_loc = File::Spec->catdir( $self->pkgsrc_base_dir, $pkg_loc );

    my ( $stdout, $stderr );
    my %proc_cfg = (
        command => [ $self->bmake_cmd, "show-vars", "VARNAMES=$varnames_str" ],
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
            my @vals = split( "\n", $stdout );
            my %varnames = zip( @$varnames, @vals );
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
        my $last_dir = pushd($pkg_loc);
        $self->loop->loop_once(0);
        eval { $self->loop->add($process); };
    } while ($@);

    return;
}

sub _get_pkg_vars_s
{
    my ( $self, $pkg_loc, $varnames ) = @_;
    my %pkg_vars;
    _get_pkg_vars( $self, $pkg_loc, $varnames, sub { %pkg_vars = %{ $_[0] }; $self->loop->stop; } );
    return %pkg_vars;
}

sub _fetch_full_pkg_details
{
    my ( $self, $pkg_loc, $cb ) = @_;

    my $eval_pkg_vars = sub {
        my %pkg_vars;
        _HASH( $_[0] ) and %pkg_vars = %{ $_[0] };
        defined $pkg_vars{DISTNAME} or return $cb->();
        my %pkg_details;
        my $distver;
        if ( $pkg_vars{DISTNAME} =~ m/^(.*)-(v?[0-9].*?)$/ )
        {
            $pkg_vars{DISTNAME} = $1;
            $distver = $2;
        }

        my $pkgsrcdir = $self->pkgsrc_base_dir();

        # XXX slice_def_map
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

        $cb->( \%pkg_details );
    };

    return $self->_get_pkg_vars( $pkg_loc, $self->_pkg_var_names, $eval_pkg_vars );
}

sub _get_extra_pkg_details
{
    my ( $self, $pkg_loc, @patterns ) = @_;
    File::Spec->file_name_is_absolute($pkg_loc)
      or $pkg_loc = File::Spec->catdir( $self->pkgsrc_base_dir, $pkg_loc );
    my @lines = read_file( File::Spec->catfile( $pkg_loc, "Makefile" ), chomp => 1 );
    my @result;

    foreach my $pattern (@patterns)
    {
        _STRING($pattern) and $pattern = qr/^\Q$pattern\E/;
        my @match = grep { $_ =~ m/$pattern/ } @lines;
        push @result, \@match;
    }

    return @result;
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

my $add_commit_tpl = <<EOACM;
Adding new package for Perl module %s from CPAN distribution %s version %s into %s

%s
EOACM

my $updt_commit_tpl = <<EOUCM;
Updating package for Perl module %s from CPAN distribution %s from %s to %s in %s

PkgSrc changes:
Generate package using Packager::Utils %s

Upstream changes since %s:
%s
EOUCM

sub _create_pkgsrc_p5_package_info
{
    my ( $self, $minfo, $pkg_det ) = @_;

    my $pkgsrc_base = $self->pkgsrc_base_dir();
    $pkgsrc_base or return;
    my $pkg_tpl_vars =
      [qw(SVR4_PKGNAME CATEGORIES COMMENT HOMEPAGE LICENSE MAINTAINER CONFLICTS SUPERSEDES)];

          $pkg_det
      and $minfo->{PKG4MOD}
      and $pkg_det->{cpan}->{ $minfo->{PKG4MOD} }
      and $pkg_det = $pkg_det->{cpan}->{ $minfo->{PKG4MOD} }->[0];    # deref search result
    $pkg_det
      and $pkg_det->{PKG_LOCATION}
      and $pkg_det =
      { %$pkg_det, $self->_get_pkg_vars_s( $pkg_det->{PKG_LOCATION}, $pkg_tpl_vars ) };
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
              } @{ _ARRAY( $minfo->{PKG_LICENSE} ) // [ $minfo->{PKG_LICENSE} ] }
        ),
        HOMEPAGE   => 'https://metacpan.org/release/' . $minfo->{DIST},
        MAINTAINER => 'pkgsrc-users@NetBSD.org',
        COMMENT    => ucfirst( $minfo->{PKG_COMMENT} ),
        LOCALBASE  => $pkgsrc_base,
        PKG4MOD    => $minfo->{PKG4MOD},
                };

    _ARRAY( $pinfo->{CATEGORIES} ) or $pinfo->{CATEGORIES} = [qw(devel)];
    push @{ $pinfo->{CATEGORIES} }, qw(perl5)
      unless grep { "perl5" eq $_ } @{ $pinfo->{CATEGORIES} };

    foreach my $keepvar (qw(SVR4_PKGNAME PKG_LOCATION))
    {
        defined $pkg_det->{$keepvar} and $pinfo->{$keepvar} = $pkg_det->{$keepvar};
    }

    $minfo->{DIST_URL} =~ m|authors/id/(\w/\w\w/[^/]+)|
      and $pinfo->{MASTER_SITES} = '${MASTER_SITE_PERL_CPAN:=../../authors/id/' . $1 . '/}';
    $pkg_det
      and $pinfo->{PKG_LOCATION}
      and $pinfo->{ORIGIN} = File::Spec->catdir( $pkgsrc_base, $pinfo->{PKG_LOCATION} );

    $pinfo->{PKG_LOCATION} =
          File::Spec->catdir( $pinfo->{CATEGORIES}->[0], 'p5-' . $minfo->{DIST} )
      and $pinfo->{ORIGIN} = File::Spec->catdir( $pkgsrc_base, $pinfo->{PKG_LOCATION} )
      and $pinfo->{IS_ADDED} = $pinfo->{CATEGORIES}->[0]
      unless $pinfo->{ORIGIN};

    # XXX leave original untouched
    if ( $minfo->{PKG_DESCR} )
    {
        $minfo->{PKG_DESCR} =~ s/^(.*?)\n\n.*/$1/ms;
        $minfo->{PKG_DESCR} =~ s/\n/ /ms;
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

    $pinfo->{EXTRA_VARS}->{PERL5_PACKLIST} =
      File::Spec->catdir( 'auto', split( '-', $minfo->{DIST} ), '.packlist' );

    # XXX somehow a PKG_LOCATION proposal could be created???

    $minfo->{GENERATOR}
      and $minfo->{GENERATOR} eq 'Module::Build::Tiny'
      and $pinfo->{EXTRA_VARS}->{PERL5_MODULE_TYPE} = 'Module::Build::Tiny';

    $minfo->{GENERATOR}
      and $minfo->{GENERATOR} eq 'Module::Build'
      and $pinfo->{EXTRA_VARS}->{PERL5_MODULE_TYPE} = 'Module::Build';

    $minfo->{GENERATOR}
      and $minfo->{GENERATOR} eq 'Module::Install'
      and $pinfo->{EXTRA_VARS}->{PERL5_MODULE_TYPE} = 'Module::Install::Bundled';

    my ( %bldreq, %bldrec, %rtreq, %rtrec, %bldcon, %rtcon, @missing );
    foreach my $dep ( @{ $minfo->{PKG_PREREQ} } )
    {
        my $req;
        my $dep_dist = $self->get_distribution_for_module( $dep->{module}, $dep->{version} );
        "perl" eq $dep->{module}
          and push @{ $pinfo->{EXTRA_VARS}->{PERL5_REQD} },
          join( ".",
                grep { defined $_ and $_ }
                  ( map { $_ =~ s/^0*//; $_ } split( qr/\./, $dep->{version} ) ) )
          and next;

        if ( $dep_dist && $dep_dist->{cpan} && $dep_dist->{cpan}->{ $dep->{module} } )
        {
            my $dep_det = $dep_dist->{cpan}->{ $dep->{module} };
            $dep_det and @{$dep_det} == 1 and $dep_det->[0]->{PKG_NAME} ne "perl" and $req = {
                PKG_NAME => $dep_det->[0]->{PKG_NAME},
                REQ_VERSION => $dep->{version},    # XXX numify? -[0-9]*, size matters (see M::B)!
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
                                                                                             };
            $dep_det and @{$dep_det} == 1 and $dep_det->[0]->{PKG_NAME} eq "perl" and $req = {
                PKG_NAME  => $dep_det->[0]->{PKG_NAME},
                CORE_NAME => $dep_det->[0]->{PKG_NAME},
                CORE_VERSION => $dep->{version},    # XXX numify? -[0-9]*, size matters (see M::B)!
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
                (
                   defined $dep_det->[0]->{LAST_VERSION}
                   ? ( LAST_VERSION => $dep_det->[0]->{LAST_VERSION} )
                   : (),
                ),
                (
                   defined $dep_det->[0]->{DEPR_VERSION}
                   ? ( DEPR_VERSION => $dep_det->[0]->{DEPR_VERSION} )
                   : (),
                ),
            };

            $dep_det and @{$dep_det} > 1 and $req = {
                PKG_NAME => $dep_det->[0]->{PKG_NAME},
                REQ_VERSION => $dep->{version},    # XXX numify? -[0-9]*, size matters (see M::B)!
                CORE_NAME    => $dep_det->[1]->{PKG_NAME},    # XXX find lowest reqd. Perl5 version!
                CORE_VERSION => $dep_det->[1]->{DIST_VERSION}
                ,                                             # XXX find lowest reqd. Perl5 version!
                (
                   defined $dep_det->[1]->{LAST_VERSION}
                   ? ( LAST_VERSION => $dep_det->[1]->{LAST_VERSION} )
                   : (),
                ),
                (
                   defined $dep_det->[1]->{DEPR_VERSION}
                   ? ( DEPR_VERSION => $dep_det->[1]->{DEPR_VERSION} )
                   : (),
                ),
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
                                                    };
        }
        else
        {
            push @missing, $req = {
                                    PKG_NAME     => $dep->{module},
                                    REQ_VERSION  => $dep->{version},    # XXX numify? -[0-9]*
                                    PKG_LOCATION => 'n/a',
                                  };
            next;
        }

        my ( $ncver, $cvernm );
        defined $req->{CORE_NAME}
          and $ncver = scalar( split( qr/\./, $req->{CORE_VERSION} ) )
          and $cvernm =
          ( $ncver <= 2 ? $req->{CORE_VERSION} . ( ".0" x ( 3 - $ncver ) ) : $req->{CORE_VERSION} ),
          and version->parse($cvernm) <= version->parse($])
          and push @{ $pinfo->{EXTRA_VARS}->{PERL5_REQD} },
          "$req->{CORE_VERSION}	# $dep->{module} >= $dep->{version}"
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
                $dept =~ m/BUILD/
                  and $pinfo->{EXTRA_VARS}->{"BUILDLINK_DEPMETHOD.$depn"} = 'build';
            }
        }

        push( @{ $pinfo->{$dept} }, sort { $a->{PKG_NAME} cmp $b->{PKG_NAME} } values %$deps );
    }

    if ( $pinfo->{IS_ADDED} )
    {
        $pinfo->{COMMITMSG} = wrap(
                                    "", "",
                                    sprintf( $add_commit_tpl,
                                             $minfo->{PKG4MOD},  $minfo->{DIST},
                                             $minfo->{DIST_VER}, $pinfo->{PKG_LOCATION},
                                             $pinfo->{DESCRIPTION} )
                                  );
    }
    else
    {
        my @extra_keys = qw(USE_TOOLS USE_LANGUAGES PKGNAME .include);
        my @extra_details = $self->_get_extra_pkg_details( $pkg_det->{PKG_LOCATION}, @extra_keys );
        $pkg_det->{extra} = { zip @extra_keys, @extra_details };

        my $changes  = CPAN::Changes->load_string( $minfo->{PKG_CHANGES} );
        my $dv       = version->parse( $pkg_det->{DIST_VERSION} );
        my @releases = grep { $dv < $_->version } $changes->releases;
        $changes->{releases} = {};    # XXX clear_releases
        @releases and $changes->releases(@releases);
        $pinfo->{COMMITMSG} = wrap(
                                    "", "",
                                    sprintf( $updt_commit_tpl,
                                             $minfo->{PKG4MOD},        $minfo->{DIST},
                                             $pkg_det->{DIST_VERSION}, $minfo->{DIST_VER},
                                             $pinfo->{PKG_LOCATION},   $VERSION,
                                             $pkg_det->{DIST_VERSION}, $changes->serialize )
                                  );

        foreach my $ut ( @{ $pkg_det->{extra}->{USE_TOOLS} } )
        {
            ( my $tool = $ut ) =~ s/^\s*USE_TOOLS\W+(\w.*)$/$1/;
            push @{ $pinfo->{USE_TOOLS} }, $tool;
        }

        foreach my $ul ( @{ $pkg_det->{extra}->{USE_LANGUAGES} } )
        {
            ( my $lang = $ul ) =~ s/^\s*USE_LANGUAGES\W+(\w.*)$/$1/;
            push @{ $pinfo->{USE_LANGUAGES} }, $lang;
        }
        _ARRAY( $pinfo->{USE_LANGUAGES} ) or $pinfo->{USE_LANGUAGES} = ["# empty"];

        foreach my $il ( @{ $pkg_det->{extra}->{".include"} } )
        {
            ( my $inc = $il ) =~ s/^\s*\.include\s+"([^"]+)"$/$1/;
            $inc eq "../../lang/perl5/module.mk" and next;
            $inc eq "../../mk/bsd.pkg.mk"        and next;
            grep { $_ eq $inc } @{ $pinfo->{INCLUDES} } and next;
            push @{ $pinfo->{INCLUDES} }, $inc;
        }
    }

    push @{ $pinfo->{INCLUDES} }, "../../lang/perl5/module.mk";

    $pinfo->{GLOBAL} = {
                         MAKE            => $self->bmake_cmd,
                         PKGSRC_BASE_DIR => $self->pkgsrc_base_dir
                       };

    return $pinfo;
}

around "create_package_info" => sub {
    my $next  = shift;
    my $self  = shift;
    my $pinfo = $self->$next(@_);

    my ( $minfo, $pkg_det, $pkgsrc_pinfo ) = @_;
    defined $minfo->{cpan}
      and $pkgsrc_pinfo = $self->_create_pkgsrc_p5_package_info( $minfo->{cpan}, $pkg_det )
      and $pinfo->{pkgsrc} = $pkgsrc_pinfo;

    return $pinfo;
};

=head1 NAME

Packager::Utils::Role::Packages::PkgSrc - Support PkgSrc packagers

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-packager-utils at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Packager-Utils>.
I will be notified, and then you'll automatically be notified of progress
on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Packager::Utils

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Packager-Utils>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Packager-Utils>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Packager-Utils>

=item * Search CPAN

L<http://search.cpan.org/dist/Packager-Utils/>

=back

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013,2014 Jens Rehsack.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;
