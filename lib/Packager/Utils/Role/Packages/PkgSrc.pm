package Packager::Utils::Role::Packages::PkgSrc;

use Moo::Role;
use MooX::Options;

use v5.12;

use Alien::Packages::Pkg_Info::pkgsrc ();
use Carp qw(carp croak);
use Carp::Assert qw(affirm);
use Cwd qw();
use File::Basename qw(dirname fileparse);
use File::Spec qw();
use File::Find::Rule qw(find);
use File::pushd;
use IO::CaptureOutput qw(capture_exec);
use List::MoreUtils qw(zip);
use Params::Util qw(_ARRAY _ARRAY0 _HASH _HASH0);
use Text::Glob qw(match_glob);
use Text::Wrap qw(wrap);
use Unix::Statgrab qw();

# make it optional - with cache only ...
use File::Find::Rule::Age;

with "Packager::Utils::Role::Async";

our $VERSION = '0.001';

option 'pkgsrc_base_dir' => (
    is     => "lazy",
    format => "s",
    coerce => sub {
        defined $_[0] or die "pkgsrc_base_dir must be defined";
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

    $self->options_usage( 1, "Unable to guess pkgsrc base dir" );

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
    my $pds = 0;

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
        do {
	    $self->loop->loop_once(0);
	} while($pds > $max_procs);
    }

    do
    {
        $self->loop->loop_once(undef);
    } while ( $pds );

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
    my $last_dir = pushd($pkg_loc);

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
                warn $stderr;
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
    do {
	$self->loop->loop_once(0);
	eval { $self->loop->add($process);};
    } while($@);

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
              } @{ _ARRAY($minfo->{PKG_LICENSE}) // [$minfo->{PKG_LICENSE}]}
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
          and $minfo->{GENERATOR} eq 'Module::Build::Tiny'
          and $pinfo->{EXTRA_VARS}->{PERL5_MODULE_TYPE} = 'Module::Build::Tiny';

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
