package Packager::Utils::Role::Packages::Bitbake;

use strict;
use warnings;

use Moo::Role;
use MooX::Options;
use File::pushd;
use File::Find::Rule;
use File::Basename;
use File::Slurp::Tiny 'read_file';
use Params::Util qw(_ARRAY _ARRAY0 _HASH _HASH0 _STRING);

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
        return [ qw(DISTRO_NAME SRC_URI DISTRO_VERSION),
		 qw(PN PV PR FILE_DIRNAME MAINTAINER),
		 qw(HOMEPAGE LICENSE) ];
    },
    init_arg => undef
);

sub _get_bb_vars
{
    my ( $self, $pkg_name, $varnames, $cb ) = @_;
    $varnames or $varnames = $self->_bb_var_names;
    use DDP;
    p( $self->_bb_var_names );

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
                use DDP;
                $self->log->warning($stderr);
                return $cb->();
            }
            chomp $stdout;
            my @vals = grep { $_ !~ m/^#/ } split( "\n", $stdout );
            my %allvars = map { $_ =~ m/(\w+)="([^"]*)"/ ? ($1, $2) : () } @vals;

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

    use DDP;
    p(%proc_cfg);
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

            $pkg_details{DIST_NAME}      = $bbfile;
            $pkg_details{DIST_VERSION}   = $pkg_vars{PV};
            $pkg_details{DIST_FILE}      = $pkg_vars{SRC_URI};
            $pkg_details{PKG_NAME}       = $pkg_vars{PN};
            $pkg_details{PKG_VERSION}    = defined $pkg_vars{PR} ? join( "-", @pkg_vars{"PV", "PR"} ) : $pkg_vars{PV};
            $pkg_details{PKG_MAINTAINER} = $pkg_vars{MAINTAINER};
            $pkg_details{PKG_LOCATION}   = File::Spec->catfile( $pkg_vars{FILE_DIRNAME}, $bbfile );
            $pkg_details{PKG_HOMEPAGE}   = $pkg_vars{HOMEPAGE};
            $pkg_details{PKG_LICENSE}    = $pkg_vars{LICENSE};
            use DDP;
            p(%pkg_details);

            #... mapping
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

    use DDP;
    p($bitbake_bblayers);
    p($bspdir);

    -d $bspdir or return $packaged;

    #get bblayers file
    my $layer_conf = read_file( $bitbake_bblayers, binmode => 'encoding(UTF-8)' );
    my $tag = "{BSPDIR}";

    my @src_paths;
    while ( $layer_conf =~ m/\Q$tag\E([^ ]+)/g )
    {
        push @src_paths, File::Spec->catdir( $bspdir, $1 );
    }
    use DDP;
    p(@src_paths);

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

    my @files = find( file => %find_args,
		      in   => @src_paths );

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

1;
