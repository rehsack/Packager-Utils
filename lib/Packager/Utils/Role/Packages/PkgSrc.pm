package Packager::Utils::Role::Packages::PkgSrc;

use Moo::Role;
use MooX::Options;

use Carp qw(carp croak);
use Carp::Assert qw(affirm);
use Cwd qw();
use File::Basename qw();
use File::Spec qw();
use File::Find::Rule qw(find);
use File::pushd;
use IO::CaptureOutput qw(capture_exec);
use List::MoreUtils qw(zip);

# make it optional - with cache only ...
use DateTime;
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
                              is     => "ro", # XXX guess that using Alien::Packags
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
    my %havepkgs =
      map { $_ =~ m/^(.*)-(v?[0-9].*?)$/ ? ( $1 => $2 ) : ( $_ => 0E0 ) }
      map { ( split( m/\s+/, $_ ) )[0] } grep { 0 == index( $_, 'p5-' ) } split( "\n", $stdout );

    $installed->{pkgsrc} = \%havepkgs;

    return $installed;
};

around "_build_packaged_modules" => sub {
    my $next     = shift;
    my $self     = shift;
    my $packaged = $self->$next(@_);

    my $pkgsrc_base = $self->pkgsrc_base_dir();
    -d $pkgsrc_base or return $packaged;
    my %age_args = (mindepth => 2, maxdepth => 2);

    #    if ($last_state)
    #    {
    #        my $now      = time();
    #        my $duration = $now - $last_state;
    #        %age_args = ( age => [ newer => "${duration}s" ] );
    #    }

    my @pkg_dirs = find(
                         directory => name => "p5-*",
                         %age_args,
                         in => $pkgsrc_base
                       );

    $packaged->{pkgsrc} = { map { $_ => $self->_fetch_full_pkg_details($_) } @pkg_dirs };

    return $packaged;
};

has '_pkg_var_names' => (
    is      => 'ro',
    default => sub {
        return [
                 qw(DISTNAME DISTFILES EXTRACT_SUFX),
                 qw(PKGNAME PKGVERSION MAINTAINER),
                 qw(HOMEPAGE LICENSE MASTER_SITES)
               ];
    },
    init_arg => undef
                        );

sub _get_pkg_vars
{
    my ( $self, $pkg_loc ) = @_;
    my $varnames     = $self->_pkg_var_names;
    my $varnames_str = join( " ", @$varnames );
    my $last_dir     = pushd($pkg_loc);
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
          defined( $self->installed_packages->{ $pkg_details{PKG_NAME} } );
        ( $pkg_details{PKG_LOCATION} = $pkg_loc ) =~ s|$pkgsrcdir/||;
        $pkg_details{PKG_HOMEPAGE}     = $pkg_vars{HOMEPAGE};
        $pkg_details{PKG_LICENSE}      = $pkg_vars{LICENSE};
        $pkg_details{PKG_MASTER_SITES} = $pkg_vars{MASTER_SITES};
    };
    $@ and print("$pkg_loc -- $@\n");

    return \%pkg_details;
}

=head1 NAME

Packager::Utils::Role::Packages::PkgSrc - Support PkgSrc packagers

=cut

1;