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
use URI            ();
use URI::Simple    ();
use Unix::Statgrab ();
use Text::Wrap qw(wrap);

# make it optional - with cache only ...
use File::Find::Rule::Age;
with "Packager::Utils::Role::Async", "MooX::Log::Any";

our $VERSION = '0.001';

option 'bspdir' => (
    is     => "lazy",
    format => "s",
    coerce => sub {
        defined $_[0] or return;
        -d $_[0] or die "$_[0]: $! - define BBPATH for proper automatism";
        return Cwd::abs_path($_[0]);
    },
    doc      => "Specify base directory of bitbake",
    long_doc => "Must be used to specify"
      . " the base directory for "
      . "bspdir directory.\n\nExamples: "
      . "--bspdir /home/user/bsp",
);

sub _build_bspdir
{
    my $self = shift;
    my $bspdir;
    my $bblayers_conf = $self->bitbake_bblayers_conf;
    $bblayers_conf or return;
    my $layer_conf = read_file($bblayers_conf, binmode => 'encoding(UTF-8)');
    $layer_conf =~ m/^BSPDIR := "\$\{\@os\.path\.abspath\(os\.path\.dirname\(d\.getVar\('FILE', True\)\) \+ '([^']+)'\)\}"/ms
      and $bspdir = Cwd::abs_path(File::Spec->catdir(dirname($self->bitbake_bblayers_conf), $1))
      and return $bspdir;
    return;
}

option 'bitbake_bblayers_conf' => (
    is     => "lazy",
    format => "s",
    coerce => sub {
        defined $_[0] or return;
        -f $_[0]
          or die "The BBPATH variable is not set and pkg_util did not find a conf/bblayers.conf file in the expected location.";
        return Cwd::abs_path($_[0]);
    },
    doc      => "Specify base path of bblayers.conf file",
    long_doc => "Must be used to specify"
      . " the base directory for "
      . "bitbake source directory.\n\nExamples: "
      . "--bitbake_bblayers_conf /home/user/fsl-community-bsp/yocto/conf/bblayers.conf",
    predicate => 1,
);

sub _build_bitbake_bblayers_conf
{
    my $self = shift;
    $self->yocto_build_dir or return;
    File::Spec->catfile($self->yocto_build_dir, qw(conf bblayers.conf));
}

option yocto_build_dir => (
    is     => "lazy",
    format => "s",
    coerce => sub {
        defined $_[0] or return;
        -d $_[0] or die "$_[0]: $!";
        return Cwd::abs_path($_[0]);
    },
    doc      => "Specify base path of conf/bblayers.conf file",
    long_doc => "Used by BitBake to locate .bbclass and configuration files.\n\n"
      . "\$ BBPATH = \"<build_directory>\" bitbake < target >",
);

sub _build_yocto_build_dir
{
    my $yoctodir;
    $ENV{BBPATH} and $yoctodir = $ENV{BBPATH};
    $yoctodir or $yoctodir = dirname(dirname($_[0]->bitbake_bblayers_conf)) if $_[0]->has_bitbake_bblayers_conf;
    return $yoctodir;
}

has bitbake_cmd => (is => "lazy");

sub _build_bitbake_cmd
{
    my $bb_cmd = IPC::Cmd::can_run("bitbake");
    # XXX use attribute for layer paths, find poky and search relative to that
    $bb_cmd or $bb_cmd = File::Spec->catfile($_[0]->bspdir, qw(sources poky bitbake bin bitbake));
    $bb_cmd;
}

has '_bb_var_names' => (
    is      => 'ro',
    default => sub {
        return [qw(PN PV PR FILE_DIRNAME MAINTAINER SRC_URI HOMEPAGE LICENSE)];
    },
    init_arg => undef
);

sub _get_bb_vars
{
    my ($self, $pkg_name, $varnames, $cb) = @_;
    $varnames or $varnames = $self->_bb_var_names;
    my $yoctodir = $self->yocto_build_dir();

    my ($stdout, $stderr);
    my %proc_cfg = (
        command => [$self->bitbake_cmd, "-e", "$pkg_name"],
        stdout  => {
            on_read => sub {
                my ($stream, $buffref) = @_;
                $stdout .= $$buffref;
                $$buffref = "";
                return 0;
            },
        },
        stderr => {
            on_read => sub {
                my ($stream, $buffref) = @_;
                $stderr .= $$buffref;
                $$buffref = "";
                return 0;
            },
        },
        on_finish => sub {
            my ($proc, $exitcode) = @_;
            if ($exitcode != 0)
            {
                $self->log->warning($stderr);
                return $cb->();
            }
            chomp $stdout;
            my @vals = grep { $_ !~ m/^#/ } split("\n", $stdout);
            my %allvars = map { $_ =~ m/(\w+)="([^"]*)"/ ? ($1, $2) : () } @vals;

            my %varnames;
            @varnames{@$varnames} = @allvars{@$varnames};
            $cb->(\%varnames);
        },
        on_exception => sub {
            my ($exception, $errno, $exitcode) = @_;
            $exception and die $exception;
            die $self->bitbake_cmd . " died with (exit=$exitcode): " . $stderr;
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
    my ($self, $file, $cb) = @_;

    my $bbfile;
    my $recipe = (split("_", $bbfile = fileparse($file, qr/\.[^.]*/)))[0];
    $self->_get_bb_vars(
        $recipe,
        $self->_bb_var_names,
        sub {
            my %pkg_vars;
            _HASH($_[0]) and %pkg_vars = %{$_[0]};
            defined $pkg_vars{SRC_URI} or return $cb->();
            length $pkg_vars{SRC_URI}  or return $cb->();

            my %pkg_details;

            #... mapping
            (my $src_uri = $pkg_vars{SRC_URI}) =~ s,file://,file:,g;
            $src_uri =~ s/^\s*//;
            $src_uri =~ s/\s+.*//;
            my $uri = URI::Simple->new($src_uri);
            my @parsed_path = fileparse($uri->{path}, @{$self->_archive_extensions});
            $pkg_details{DIST_NAME} = $parsed_path[0];
            $pkg_details{DIST_NAME} =~ m/^(.*)-(v?[0-9].*?)$/ and (@pkg_details{qw(DIST_NAME DIST_VERSION)}) = ($1, $2);
            defined $pkg_details{DIST_VERSION} or $pkg_details{DIST_VERSION} = $pkg_vars{PV};
            $pkg_details{DIST_FILE}        = (fileparse($uri->{path}))[0];
            $pkg_details{PKG_NAME}         = $pkg_vars{PN};
            $pkg_details{PKG_VERSION}      = defined $pkg_vars{PR} ? join("-", @pkg_vars{"PV", "PR"}) : $pkg_vars{PV};
            $pkg_details{PKG_MAINTAINER}   = $pkg_vars{MAINTAINER};
            $pkg_details{PKG_LOCATION}     = File::Spec->catfile($pkg_vars{FILE_DIRNAME}, $bbfile);
            $pkg_details{PKG_HOMEPAGE}     = $pkg_vars{HOMEPAGE};
            $pkg_details{PKG_LICENSE}      = $pkg_vars{LICENSE};
            $pkg_details{PKG_MASTER_SITES} = $uri->protocol . "://" . $uri->{authority} . $parsed_path[1];

            $cb->(\%pkg_details);
        }
    );

    return;
}

has oe_layers => (is => 'lazy');

sub _build_oe_layers
{
    my $self = shift;

    #get bblayers file
    my $bitbake_bblayers = $self->bitbake_bblayers_conf();
    my $layer_conf       = read_file($bitbake_bblayers, binmode => 'encoding(UTF-8)');
    my $tag              = "{BSPDIR}";
    my $bspdir           = $self->bspdir();

    # XXX extract into attribute
    my @layer_paths;
    my %layer_prios;
    while ($layer_conf =~ m/\Q$tag\E([^ ]+)/g)
    {
        my $layer_dir = File::Spec->catdir($bspdir, $1);

        my $layer_conf_path = File::Spec->catfile($layer_dir, qw(conf layer.conf));
        -f $layer_conf_path or next;

        my $layer_conf = read_file($layer_conf_path, binmode => 'encoding(UTF-8)');
        my $layer_name;
        $layer_conf =~ m/BBFILE_COLLECTIONS\s+\+=\s+"([^"]+)"/msx and $layer_name = $1;

        my $layer_prio;
        $layer_conf =~ m/BBFILE_PRIORITY_$layer_name\s+=\s+"(\d+)"/msx and $layer_prio = $1;
        $layer_prio or next;

        $layer_prios{$layer_dir} = $layer_prio;

        push @layer_paths, $layer_dir;
    }

    [sort { $layer_prios{$b} <=> $layer_prios{$a} } @layer_paths];
}

around "_build_packages" => sub {
    my $next     = shift;
    my $self     = shift;
    my $packaged = $self->$next(@_);

    my $bspdir = $self->bspdir() or return $packaged;

    -d $bspdir or return $packaged;

    # XXX extract into attribute
    my @src_paths = @{$self->oe_layers};

    my %find_args = (
        mindepth => 3,
        maxdepth => 3,
        name     => "*.bb",
    );

    if ($self->cache_timestamp)
    {
        my $now      = time();
        my $duration = $now - $self->cache_timestamp;
        $find_args{age} = [newer => "${duration}s"];
    }

    $self->has_packages_pattern and $find_args{name} = $self->packages_pattern;

    my @files = find(
        file => %find_args,
        in   => \@src_paths
    );

    # my @files = File::Find::Rule->file()->name('*.bb')->maxdepth(3)->in(@src_paths);
    my $max_procs = 0;    # int((Unix::Statgrab::get_host_info()->ncpus(0)-1) / 2)+1;

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
                  and $packaged->{bitbake}->{$pkg_det->{PKG_LOCATION}} =
                  $pkg_det;    #aufrufen um dinge in die datenbank zu schreiben/cachen.
            }
        );
        do
        {
            $self->loop->loop_once(0);
        } while ($pds > $max_procs);
    }

    @files and $self->cache_modified(time);

    return $packaged;
};

around "package_type" => sub {
    my $next         = shift;
    my $self         = shift;
    my $package_type = $self->$next(@_);
    $package_type and return $package_type;

    my $pkg     = shift;
    my $pkgtype = shift;

    $pkgtype eq "bitbake" and $pkg->{PKG_MASTER_SITES} =~ m/cpan/i and return "perl";

    return;
};

around "prepare_package_info" => sub {
    my $next  = shift;
    my $self  = shift;
    my $pinfo = $self->$next(@_);

    my ($minfo, $pkg_det, $bitbake_pinfo) = @_;
    defined $minfo->{cpan}
      and $bitbake_pinfo = $self->_prepare_bitbake_package_info($minfo->{cpan}, $pkg_det)
      and $pinfo->{bitbake} = $bitbake_pinfo;

    return $pinfo;
};

my %cpan2spdx_licenses = (
    agpl_3      => ['AGPLv3'],
    apache_1_1  => ['Apache-1.1'],
    apache_2_0  => ['Apachev2'],
    artistic_1  => ['Artisticv1'],
    artistic_2  => ['Artistic-2.0'],
    bsd         => ['BSD-3-Clause'],
    freebsd     => ['BSD-2-Clause'],
    gfdl_1_2    => ['GFDL-1.2'],
    gfdl_1_3    => ['GFDL-1.3'],
    gpl_1       => ['GPLv1'],
    gpl_2       => ['GPLv2'],
    gpl_3       => ['GPLv3'],
    lgpl_2_1    => ['LGPLv2.1'],
    lgpl_3_0    => ['LGPLv3'],
    mit         => ['MIT'],
    mozilla_1_0 => ['MPLv1'],
    mozilla_1_1 => ['MPLv1.1'],
    openssl     => ['OpenSSL'],
    perl_5      => ['Artisticv1', 'GPLv1+'],
    qpl_1_0     => ['QPL-1.0'],
    zlib        => ['Zlib'],
);

has spdx_license_map => (is => "lazy");

sub _build_spdx_license_map

{
    my $self = shift;

    my %spdx_license_map;

    my @src_paths = map { File::Spec->catdir($_, 'conf') } @{$self->oe_layers};
    my @lic_cnfs = find(
        file => name => "licenses.conf",
        in   => \@src_paths
    );

    foreach my $lic_cnf (@lic_cnfs)
    {
        my $lic_cnf_cnt = read_file($lic_cnf, binmode => 'encoding(UTF-8)');
        # SPDXLICENSEMAP[AGPL-3] = "AGPL-3.0"
        while ($lic_cnf_cnt =~ m/SPDXLICENSEMAP\[([^\]]+)\]\s+=\s+"([^"]+)"/msxg)
        {
            $spdx_license_map{$1} = $2;
        }
    }

    \%spdx_license_map;
}

my %known_md5s;

has oe_license_dirs => (is => "lazy");

sub _build_oe_license_dirs
{
    my $self = shift;
    # there will be more ...
    [File::Spec->catfile($self->bspdir, qw(sources poky meta files common-licenses))];
}

sub _oe_license_md5sum
{
    my $self    = shift;
    my $license = shift;

    $license =~ s/\+$//;
    unless (defined $known_md5s{$license})
    {
        defined $self->spdx_license_map->{$license} and $license = $self->spdx_license_map->{$license};

        my @src_paths = @{$self->oe_license_dirs};
        my ($lic_file) = find(
            file => name => $license,
            in   => \@src_paths
        );

        if ($lic_file && -f $lic_file)
        {
            my $ctx  = Digest::MD5->new();
            my $data = read_file($lic_file);
            $ctx->add($data);
            $known_md5s{$license} = "file://\${COMMON_LICENSE_DIR}/$license;md5=" . $ctx->hexdigest;
        }
        else
        {
            $known_md5s{$license} = "unknown($license)";
        }
    }

    $known_md5s{$license};
}

sub _prepare_bitbake_package_info
{
    my ($self, $minfo, $pkg_det) = @_;

    my $bspdir = $self->bspdir;
    $bspdir or return;

    defined $minfo->{PKG_COMMENT} or die "$minfo->{PKG4MOD}";

    my $pinfo = {
        DIST       => $minfo->{DIST},
        DIST_NAME  => $minfo->{DIST_NAME},
        CATEGORIES => $minfo->{CATEGORIES},
        LICENSE    => join(" | ",
            map { ($cpan2spdx_licenses{$_} ? @{$cpan2spdx_licenses{$_}} : ("unknown($_)")) }
              @{_ARRAY($minfo->{PKG_LICENSE}) // [$minfo->{PKG_LICENSE}]}),
        HOMEPAGE        => 'https://metacpan.org/release/' . $minfo->{DIST},
        MAINTAINER      => 'Poky <poky@yoctoproject.org>',
        COMMENT         => ucfirst($minfo->{PKG_COMMENT}),
        LOCALBASE       => File::Spec->catdir($bspdir, qw(sources meta-cpan)),
        PKG4MOD         => $minfo->{PKG4MOD},
        DIST_URL        => $minfo->{DIST_URL},
        DIST_URL_MD5    => $minfo->{CHKSUM}->{MD5},
        DIST_URL_SHA256 => $minfo->{CHKSUM}->{SHA256},
        BUILDER_TYPE    => "cpan",
    };

    $pinfo->{LICENSE_FILES} = join(
        " \\\n",
        map {
            $cpan2spdx_licenses{$_}
              ? (map { $self->_oe_license_md5sum($_) } @{$cpan2spdx_licenses{$_}})
              : ($self->_oe_license_md5sum($_))
        } @{_ARRAY($minfo->{PKG_LICENSE}) // [$minfo->{PKG_LICENSE}]}
    );

    #$minfo->{DIST_URL} =~ m|authors/id/(\w/\w\w/[^/]+/.*)|
    #  and $pinfo->{MASTER_SITES} = 'http://search.cpan.org/CPAN/authors/id/' . $1 . '/';
    #    $pkg_det
    #      and $pinfo->{PKG_LOCATION}
    #      and $pinfo->{ORIGIN} = File::Spec->catdir( $pinfo->{LOCALBASE}, $pinfo->{PKG_LOCATION} ); # bb-name can hacked in here XXX

    $pinfo->{PKG_LOCATION} = File::Spec->catdir($pinfo->{CATEGORIES}->[0], lc($minfo->{DIST}) . "-perl")
      and $pinfo->{ORIGIN} = File::Spec->catfile(
        $pinfo->{LOCALBASE},
        $pinfo->{PKG_LOCATION},
        join("_", join("-", lc($minfo->{DIST}), "perl"), $minfo->{DIST_VER})
      )
      and $pinfo->{IS_ADDED} = $pinfo->{CATEGORIES}->[0]
      unless $pinfo->{ORIGIN};

    if ($minfo->{PKG_DESCR})
    {
        $pinfo->{DESCRIPTION} = $minfo->{PKG_DESCR};
        $pinfo->{DESCRIPTION} =~ s/^(.*?)\n\n.*/$1/ms;
        $pinfo->{DESCRIPTION} =~ s/\n/ /ms;
    }
    elsif ($minfo->{PKG_COMMENT})
    {
        $pinfo->{DESCRIPTION} = $minfo->{PKG_COMMENT};
    }
    else
    {
        $pinfo->{DESCRIPTION} = "Perl module for " . $minfo->{PKG4MOD};
    }

    $pinfo->{DESCRIPTION} =~ s/(^|[^\\])([\\])/$1\\$2/g;
    $pinfo->{DESCRIPTION} =~ s/\n/ /msg;
    $pinfo->{DESCRIPTION} =~ s/(\w)\s+(\w)/$1 $2/msg;

    if (length($pinfo->{DESCRIPTION}) > 72)
    {
        local $Text::Wrap::separator = " \\\n";
        local $Text::Wrap::columns   = 76;
        $pinfo->{DESCRIPTION} = wrap("", "", $pinfo->{DESCRIPTION});
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

    my (%bldreq, %bldrec, %rtreq, %rtrec, %bldcon, %rtcon, @missing);
    foreach my $dep (@{$minfo->{PKG_PREREQ}})
    {
        my $req;
        my $dep_dist = $self->get_distribution_for_module($dep->{module}, $dep->{version});
        "perl" eq $dep->{module}
          and push @{$pinfo->{EXTRA_VARS}->{PERL5_REQD}},
          join(".", grep { defined $_ and $_ } (map { $_ =~ s/^0*//; $_ } split(qr/\./, $dep->{version})))
          and next;

        if ($dep_dist && $dep_dist->{cpan} && $dep_dist->{cpan}->{$dep->{module}})
        {
            my $dep_det = $dep_dist->{cpan}->{$dep->{module}};
            $dep_det and my ($in_core) = grep { exists $_->{FIRST_VERSION} } @$dep_det;
            $dep_det and not $in_core and $req = {
                PKG_NAME     => $dep_det->[0]->{PKG_NAME},
                REQ_VERSION  => $dep->{version},                 # XXX numify? -[0-9]*, size matters (see M::B)!
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
            };

            $dep_det and $in_core and $req = {
                PKG_NAME     => $dep_det->[0]->{PKG_NAME},
                REQ_VERSION  => $dep->{version},                 # XXX numify? -[0-9]*, size matters (see M::B)!
                CORE_NAME    => $in_core->{PKG_NAME},            # XXX find lowest reqd. Perl5 version!
                CORE_VERSION => $in_core->{FIRST_VERSION},       # XXX find lowest reqd. Perl5 version!
                (
                    defined $in_core->{LAST_VERSION} ? (LAST_VERSION => $in_core->{LAST_VERSION})
                    : (),
                ),
                (
                    defined $in_core->{DEPR_VERSION} ? (DEPR_VERSION => $in_core->{DEPR_VERSION})
                    : (),
                ),
                PKG_LOCATION => $dep_det->[0]->{PKG_LOCATION},
            };
        }
        else
        {
            $req = {
                PKG_NAME     => $dep->{module},
                REQ_VERSION  => $dep->{version},        # XXX numify? -[0-9]*
                PKG_LOCATION => 'n/a',
                RELATION     => $dep->{relationship},
                PHASE        => $dep->{phase},
            };
            $dep->{relationship} =~ m/^(?:requires|recommends)$/
              and $dep->{phase} =~ m/^(?:configure|build|test|runtime)$/
              and push(@missing, $req);
            next;
        }

        my ($ncver, $cvernm);
        defined $req->{CORE_NAME}
          and $ncver = scalar(split(qr/\./, $req->{CORE_VERSION}))
          and $cvernm = ($ncver <= 2 ? $req->{CORE_VERSION} . (".0" x (3 - $ncver)) : $req->{CORE_VERSION}),
          and version->parse($cvernm) <= version->parse($])
          and push @{$pinfo->{EXTRA_VARS}->{PERL5_REQD}}, "$req->{CORE_VERSION}	# $dep->{module} >= $dep->{version}"
          and next
          unless ($req->{LAST_VERSION} or $req->{DEPR_VERSION});

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

        # XXX add additional checks for configure/build phase for M::B(::T?) / EU::CB

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'requires'
          and $bldreq{$req->{PKG_NAME}} = $req;
        $dep->{phase} eq 'build'
          and $dep->{relationship} eq 'requires'
          and $bldreq{$req->{PKG_NAME}} = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'requires'
          and $bldreq{$req->{PKG_NAME}} = $req;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{$req->{PKG_NAME}} = $req;
        $dep->{phase} eq 'build'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{$req->{PKG_NAME}} = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'recommends'
          and $bldrec{$req->{PKG_NAME}} = $req;

        $dep->{phase} eq 'configure'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{$req->{PKG_NAME}} = $req;
        $dep->{phase} eq 'build'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{$req->{PKG_NAME}} = $req;
        $dep->{phase} eq 'test'
          and $dep->{relationship} eq 'conflicts'
          and $bldcon{$req->{PKG_NAME}} = $req;

        $dep->{phase} eq 'runtime'
          and $dep->{relationship} eq 'requires'
          and $rtreq{$req->{PKG_NAME}} = $req;

        $dep->{phase} eq 'runtime'
          and $dep->{relationship} eq 'recommends'
          and $rtrec{$req->{PKG_NAME}} = $req;

        $dep->{phase} eq 'runtime'
          and $dep->{relationship} eq 'conflicts'
          and $rtcon{$req->{PKG_NAME}} = $req;
    }

    foreach my $req (@missing)
    {
        $self->log->error("Missing $req->{PKG_NAME} $req->{REQ_VERSION} $req->{PHASE}-$req->{RELATION} by $pinfo->{PKG4MOD}");
    }

    foreach my $pkg (keys %rtrec)
    {
        defined $rtreq{$pkg} and $rtreq{$pkg} = delete $rtrec{$pkg};
    }

    foreach my $pkg (keys %bldrec)
    {
        defined $bldreq{$pkg} and $bldreq{$pkg} = delete $bldrec{$pkg};
    }

    foreach my $pkg (keys %bldreq)
    {
        defined $rtreq{$pkg} and $rtreq{$pkg} = delete $bldreq{$pkg};
    }

    %bldreq = map {
        my $k = $_;
        my $v = $bldreq{$k};
        $k =~ m/-perl$/ and $k .= "-native";
        $v->{PKG_NAME} =~ m/-perl$/ and $v->{PKG_NAME} .= "-native";
        ($k, $v);
    } keys %bldreq;

    %bldrec = map {
        my $k = $_;
        my $v = $bldrec{$k};
        $k =~ m/-perl$/ and $k .= "-native";
        $v->{PKG_NAME} =~ m/-perl$/ and $v->{PKG_NAME} .= "-native";
        ($k, $v);
    } keys %bldrec;

    my %depdefs = (
        BUILD_REQUIRES   => \%bldreq,
        BUILD_RECOMMENDS => \%bldrec,
        BUILD_CONFLICTS  => \%bldcon,
        REQUIRES         => \%rtreq,
        RECOMMENDS       => \%rtrec,
        CONFLICTS        => \%rtcon,
    );

    foreach my $dept (keys %depdefs)
    {
        my $deps = $depdefs{$dept};
        push(@{$pinfo->{$dept}}, sort { $a->{PKG_NAME} cmp $b->{PKG_NAME} } values %$deps);
    }

    return $pinfo;
}

1;
