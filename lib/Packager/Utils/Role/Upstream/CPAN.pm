package Packager::Utils::Role::Upstream::CPAN;

use strict;
use warnings;

use 5.014;

use Moo::Role;
use MooX::Options;

use MetaCPAN::Client ();

use Carp qw/carp croak/;
use CPAN;
use CPAN::DistnameInfo;
use File::Basename qw(fileparse);
use File::Spec qw();
use HTTP::Tiny qw();
use Hash::MoreUtils qw(slice_def);
use Module::CoreList;
use Module::Runtime qw/require_module use_module module_notional_filename/;
use Params::Util qw(_ARRAY);
use Pod::Select qw();
use Pod::Text qw();

our $VERSION = '0.001';

has STATE_NEWER_IN_CORE => (
    is       => "lazy",
    init_arg => undef
);

sub _build_STATE_NEWER_IN_CORE
{
    my $state = $_[0]->STATE_BASE;
    $_[0]->STATE_BASE( $state + 1 );
    $state;
}

has STATE_REMOVED_FROM_INDEX => (
    is       => "lazy",
    init_arg => undef
);

sub _build_STATE_REMOVED_FROM_INDEX
{
    my $state = $_[0]->STATE_BASE;
    $_[0]->STATE_BASE( $state + 1 );
    $state;
}

around "_build_state_remarks" => sub {
    my $next          = shift;
    my $self          = shift;
    my $state_remarks = $self->$next(@_);
    $state_remarks->[ $self->STATE_NEWER_IN_CORE ]      = "newer in Core";
    $state_remarks->[ $self->STATE_REMOVED_FROM_INDEX ] = "not in CPAN index";
    $state_remarks;
};

option "cpan_home" => (
    is     => "ro",
    doc    => "Specify another cpan user directory than the default",
    format => "s",
);

option "update_cpan_index" => (
    is  => "ro",
    doc => "Specify to with (not) to update the having CPAN index",
);

around "init_upstream" => sub {
    my $next = shift;
    my $self = shift;
    $self->$next(@_) or return;

    my $cpan_home = $self->cpan_home;
    Module::CoreList->find_version($])
      or die "Module::CoreList needs to be updated to support Perl $]";

    if ( defined($cpan_home) and -e File::Spec->catfile( $cpan_home, 'CPAN', 'MyConfig.pm' ) )
    {
        my $file = File::Spec->catfile( $cpan_home, 'CPAN', 'MyConfig.pm' );

        # XXX taken from App:Cpan::_load_config()
        $CPAN::Config = {};
        delete $INC{'CPAN/Config.pm'};

        my $rc = eval { require $file };
        my $err_myconfig = $@;
        if ( $err_myconfig and $err_myconfig !~ m#locate \Q$file\E# )
        {
            croak "Error while requiring ${file}:\n$err_myconfig";
        }
        elsif ($err_myconfig)
        {
            CPAN::HandleConfig->load();
            defined( $INC{"CPAN/MyConfig.pm"} )
              and $CPAN::Config_loaded++;
            defined( $INC{"CPAN/Config.pm"} )
              and $CPAN::Config_loaded++;
        }
        else
        {
            # CPAN::HandleConfig::require_myconfig_or_config looks for this
            $INC{'CPAN/MyConfig.pm'} = 'fake out!';

            # CPAN::HandleConfig::load looks for this
            $CPAN::Config_loaded = 'fake out';
        }
    }
    else
    {
        CPAN::HandleConfig->load();
        defined( $INC{"CPAN/MyConfig.pm"} )
          and $CPAN::Config_loaded++;
        defined( $INC{"CPAN/Config.pm"} )
          and $CPAN::Config_loaded++;
        defined($cpan_home)
          and -d $cpan_home
          and $CPAN::Config{cpan_home} = $cpan_home;
    }

    $CPAN::Config_loaded
      or croak("Can't load CPAN::Config - please setup CPAN first");

    1;
};

has "cpan_versions" => (
    is => "lazy",
);

sub _build_cpan_versions
{
    my $self     = shift;
    my $versions = {};

    my $update_idx = $self->update_cpan_index;

    defined($update_idx)
      and $update_idx
      and $CPAN::Index::LAST_TIME = 0;
    CPAN::Index->reload( defined($update_idx) and $update_idx );
    $CPAN::Index::LAST_TIME
      or carp("Can't reload CPAN Index");

    my @all_dists = $CPAN::META->all_objects("CPAN::Distribution");

    foreach my $dist (@all_dists)
    {
        my $dinfo = CPAN::DistnameInfo->new( $dist->id() );
        my ( $distname, $distver ) = ( $dinfo->dist(), $dinfo->version() );
        defined($distname) or next;
        defined($distver)  or next;
        defined $versions->{$distname} and _is_gt( $distver, $versions->{$distname} ) and $versions->{$distname} = $distver;
        $versions->{$distname} //= $distver;
    }

    $versions;
}

has cpan_distributions => ( is => "lazy" );

sub _build_cpan_distributions
{
    my $self = shift;

    $self->cpan_versions();

    my @all_modules = $CPAN::META->all_objects("CPAN::Module");
    my %modsbydist;

    foreach my $module (@all_modules)
    {
        my $modname = $module->id();
        $module->cpan_version() or next;
        my $distfile = $module->cpan_file();
        my $dinfo    = CPAN::DistnameInfo->new($distfile);
        my ( $distname, $distver ) = ( $dinfo->dist(), $dinfo->version() );
        defined($distname) or next;
        defined($distver)  or next;
        $modsbydist{$distname} //= [];
        push( @{ $modsbydist{$distname} }, $modname );
    }

    \%modsbydist;
}

around get_distribution_for_module => sub {
    my $next = shift;
    my $self = shift;

    my $found = $self->$next(@_);

    my $module      = shift;
    my $mod_version = shift;
    my @found;

    my $pkgs = $self->packages;

    my $cpan_mod = $CPAN::META->instance( "CPAN::Module", $module );
    $cpan_mod and my $cpan_dist = CPAN::DistnameInfo->new( $cpan_mod->cpan_file() )->dist();

    foreach my $pkg_type ( keys %{$pkgs} )
    {
        $cpan_dist and push @found,
          grep { my $pt; $_->{DIST_NAME} eq $cpan_dist and $pt = $self->package_type($_,$pkg_type) and $pt eq "perl" } values %{ $pkgs->{$pkg_type} };
        my @mc_qry = ($module);
        defined $mod_version and $mod_version and push( @mc_qry, $mod_version );
        my $first_core = Module::CoreList->first_release(@mc_qry);
        $first_core or next;
        my ($perl_pkg) = grep { $_->{PKG_NAME} eq "perl" } values %{ $pkgs->{$pkg_type} };
        unless ($perl_pkg)
        {
            carp("No package found matching \"perl\" in $pkg_type");
            next;
        }
        my $last_core = Module::CoreList->removed_from($module);
        my $depr_core = Module::CoreList->deprecated_in($module);
        my %vers_info = slice_def(
            {
                DIST_VERSION => $first_core,
                LAST_VERSION => $last_core,
                DEPR_VERSION => $depr_core,
            }
        );

        foreach my $vin ( keys %vers_info )
        {
            ( my $v = version->parse( $vers_info{$vin} )->normal ) =~ s/^v//;
            $v = join( ".", grep { defined $_ and $_ } ( map { $_ =~ s/^0*//; $_ } split( qr/\./, $v ) ) );
            $vers_info{$vin} = $v;
        }
        push @found, { %$perl_pkg, %vers_info };
    }

    @found and $found = { ( $found ? %{$found} : () ), cpan => { $module => \@found } };
    $found and return $found;

    return;
};

sub _is_gt
{
    my $gt;
    defined( $_[0] ) and $_[0] =~ /^v/ and $_[1] !~ /^v/ and $_[1] = "v$_[1]";
    defined( $_[0] ) and $_[0] !~ /^v/ and $_[1] =~ /^v/ and $_[0] = "v$_[0]";
    eval { $gt = defined( $_[0] ) && ( version->parse( $_[0] ) > version->parse( $_[1] ) ); };
    $@ and $gt = defined( $_[0] ) && ( $_[0] gt $_[1] );
    $gt;
}

sub _is_ne
{
    my $ne;
    defined( $_[0] ) and $_[0] =~ /^v/ and $_[1] !~ /^v/ and $_[1] = "v$_[1]";
    defined( $_[0] ) and $_[0] !~ /^v/ and $_[1] =~ /^v/ and $_[0] = "v$_[0]";
    eval { $ne = defined( $_[0] )
          && ( version->parse( $_[0] ) != version->parse( $_[1] ) ); };
    $@ and $ne = defined( $_[0] ) && ( $_[0] ne $_[1] );
    $ne;
}

around "upstream_up2date_state" => sub {
    my $next  = shift;
    my $self  = shift;
    my $state = $self->$next(@_);
    defined $state and return $state;

    my $pkg_details = shift;

    # @result{@local_vars} = @{ $self->{pkg_details}->{$pkg_ident} }{@local_vars};

    my @pkg_det_keys = (qw(DIST_NAME DIST_VERSION PKG_VERSION PKG_MASTER_SITES));
    my ( $dist_name, $dist_version, $pkg_version, $master_sites ) = @{$pkg_details}{@pkg_det_keys};

    defined($master_sites) or return;    # we want cpan!
    defined($master_sites) and $master_sites !~ m/cpan/i and return;

    $self->cache_timestamp
      and $CPAN::Index::LAST_TIME > $self->cache_timestamp
      and delete @{$pkg_details}{qw(UPSTREAM_VERSION UPSTREAM_NAME UPSTREAM_COMMENT UPSTREAM_STATE)};

    defined $pkg_details->{UPSTREAM_VERSION}
      or $pkg_details->{UPSTREAM_VERSION} = $self->cpan_versions->{$dist_name};
    defined $pkg_details->{UPSTREAM_NAME} or $pkg_details->{UPSTREAM_NAME} = $dist_name;

    $self->has_cache_modified
      and $self->cache_modified < $CPAN::Index::LAST_TIME
      and $self->cache_modified($CPAN::Index::LAST_TIME);

    my $cpan_version = $pkg_details->{UPSTREAM_VERSION};

    unless ( defined($dist_name) and defined($dist_version) )
    {
        $pkg_details->{UPSTREAM_COMMENT} = 'Error getting distribution data';
        return $pkg_details->{UPSTREAM_STATE} = $self->STATE_ERROR;
    }

    $dist_name eq "perl"
      and $pkg_details->{PKG_NAME} ne "perl"
      and return $pkg_details->{UPSTREAM_STATE} = $self->STATE_OK;

    my %core_newer;
    foreach my $distmod ( @{ $self->cpan_distributions->{$dist_name} } )
    {
        defined( $Module::CoreList::version{$]}->{$distmod} ) or next;
        my $mod = $CPAN::META->instance( "CPAN::Module", $distmod );
        _is_gt( $Module::CoreList::version{$]}->{$distmod}, $mod->cpan_version() )
          and $core_newer{$distmod} = [ $Module::CoreList::version{$]}->{$distmod}, $mod->cpan_version() ];
    }

    if (%core_newer)
    {
        my $pfx = "$dist_name-$dist_version has newer modules in core:";
        my $cmp =
          join( ", ", map { "$_  " . join( " > ", @{ $core_newer{$_} } ) } keys %core_newer );
        $pkg_details->{UPSTREAM_COMMENT} = "$pfx $cmp";
        return $pkg_details->{UPSTREAM_STATE} = $self->STATE_NEWER_IN_CORE;
    }

    defined($cpan_version) or return $pkg_details->{UPSTREAM_STATE} = $self->STATE_REMOVED_FROM_INDEX;
    _is_gt( $cpan_version, $dist_version ) and return $pkg_details->{UPSTREAM_STATE} = $self->STATE_NEWER_UPSTREAM;
    _is_ne( $cpan_version, $dist_version ) and return $pkg_details->{UPSTREAM_STATE} = $self->STATE_OUT_OF_SYNC;

    $pkg_details->{UPSTREAM_STATE} = $self->STATE_OK;
};

my %parsed_checksums;
my %chksums;

sub _cpan_distfile_checksums
{
    my ( $self,     $uri )      = @_;
    my ( $uri_file, $uri_path ) = fileparse($uri);

    unless ( defined $parsed_checksums{$uri_path} )
    {
        my $chksum_path = "${uri_path}CHECKSUMS";
        my $response    = HTTP::Tiny->new->get($chksum_path);

        $self->log->emergency("$response->{status} $response->{reason}") and return unless $response->{success};
        my $cksum;
        eval "$response->{content}";
        $self->log->emergency($@) and return if $@;

        $parsed_checksums{$uri_path}++;
        %chksums = ( %chksums, %{$cksum} );
    }

    $chksums{$uri_file};
}

has chi_init => ( is => "lazy" );

sub _build_chi_init
{
    my %chi_args = (
        driver   => 'File',
        root_dir => '/tmp/metacpan-cache',
    );
    return \%chi_args;
}

has _meta_cpan => (
    is       => "lazy",
    init_arg => undef,
);

sub _build__meta_cpan
{
    my $self = shift;
    require_module("MetaCPAN::Client");
    my %ua;
    eval {
        use_module("CHI");
        use_module("WWW::Mechanize::Cached");
        use_module("HTTP::Tiny::Mech");
        %ua = (
            ua => HTTP::Tiny::Mech->new(
                mechua => WWW::Mechanize::Cached->new(
                    cache => CHI->new( %{ $self->chi_init } ),
                )
            )
        );
    };
    my $mcpan = MetaCPAN::Client->new(%ua);
    return $mcpan;
}

around "prepare_distribution_info" => sub {
    my $next  = shift;
    my $self  = shift;
    my $minfo = $self->$next(@_);

    my $module     = shift;
    my $categories = shift;

    my ( $mod, $dist, $release, $changes, $pod );
    eval {
        my $mcpan = $self->_meta_cpan;
        $mod     = $mcpan->module($module);
        $release = $mcpan->release( $mod->distribution );
        $dist    = $mcpan->distribution( $mod->distribution );
        $changes = $mcpan->fetch( "/changes/" . $mod->distribution );
        $pod     = $mcpan->pod($module)->x_pod;
    };
    $self->log->emergency("$@ for $module") and return $minfo if $@;

    defined $minfo or $minfo = {};
    # fetch -o - http://api.metacpan.org/v0/pod/Module::Build?content-type=text/x-pod | podselect -s DESCRIPTION | pod2text

    $minfo->{cpan} = {
        DIST_NAME   => $release->name,
        DIST        => $release->distribution,
        DIST_FILE   => $release->archive,
        DIST_URL    => $release->download_url,
        DIST_VER    => $release->version,
        CATEGORIES  => $categories,
        PKG_LICENSE => $release->license,
        PKG_COMMENT => $release->abstract,
        PKG_PREREQ  => $release->dependency,
        PKG_CHANGES => $changes->{content},
        PKG4MOD     => $module,
    };

    _ARRAY( $minfo->{cpan}->{PKG_LICENSE} ) or delete $minfo->{cpan}->{PKG_LICENSE};
    _ARRAY( $minfo->{cpan}->{PKG_LICENSE} )
      and $minfo->{cpan}->{PKG_LICENSE}->[0] =~ m/(?:unknown|unrestricted|open_source)/i
      and delete $minfo->{cpan}->{PKG_LICENSE};

    my %chksums = %{ $self->_cpan_distfile_checksums( $minfo->{cpan}->{DIST_URL} ) };
    @{ $minfo->{cpan}->{CHKSUM} }{qw(MD5 SHA256 SIZE)} = @chksums{qw(md5 sha256 size)};

    if ($pod)
    {
        my $ps = Pod::Select->new();
        $ps->select("DESCRIPTION");
        open( my $ifh, "<", \$pod );
        $minfo->{cpan}->{PKG_DESCR} = "";
        open( my $ofh, ">", \$minfo->{cpan}->{PKG_DESCR} );
        $ps->parse_from_filehandle( $ifh, $ofh );

        close($ifh);
        close($ofh);

        my $pod_selected = join( "\n", $minfo->{cpan}->{PKG_DESCR} );
        $minfo->{cpan}->{PKG_DESCR} = "";

        my $pt = Pod::Text->new(
            sentence => 0,
            width    => 76,
            indent   => 0
        );
        #$pt->parse_from_filehandle( $ifh, $ofh );
        $pt->output_string( \$minfo->{cpan}->{PKG_DESCR} );
        $pt->parse_string_document($pod_selected);

        $minfo->{cpan}->{PKG_DESCR} =~ s/^[^\n]+\n//;

        defined $minfo->{cpan}->{PKG_COMMENT} or $minfo->{cpan}->{PKG_COMMENT} = substr( $minfo->{cpan}->{PKG_DESCR}, 0, 76 );
    }

    if ( $pod and not $minfo->{cpan}->{PKG_LICENSE} )
    {
        my $ps = Pod::Select->new();
        $ps->select("COPYRIGHT.*|AUTHOR|LICENSE.*");
        open( my $ifh, "<", \$pod );
        my $license = "";
        open( my $ofh, ">", \$license );
        $ps->parse_from_filehandle( $ifh, $ofh );

        close($ifh);
        close($ofh);

        my $pod_selected = join( "\n", $license );
        $pod_selected =~ m/the same (terms?|licenses?) as Perl itself/i and $minfo->{cpan}->{PKG_LICENSE} = ['perl_5'];
    }

    $minfo->{cpan}->{PKG_LICENSE} or $minfo->{cpan}->{PKG_LICENSE} = $release->license;
    $minfo->{cpan}->{PKG_DESCR}   or $minfo->{cpan}->{PKG_DESCR}   = $mod->description;

    # XXX they seem to be missing via $mcpan->release call
    $release->{metadata}->{x_breaks} and $minfo->{CONFLICTS} = $release->{metadata}->{x_breaks};
    $release->{metadata}->{generated_by}
      and $release->{metadata}->{generated_by} =~ m/^(.*?) version/
      and $minfo->{cpan}->{GENERATOR} = $1;

    $minfo;
};

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
