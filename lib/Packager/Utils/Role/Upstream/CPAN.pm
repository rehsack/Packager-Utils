package Packager::Utils::Role::Upstream::CPAN;

use Moo::Role;
use MooX::Options;

use MetaCPAN::API ();

use Carp qw/croak/;
use CPAN;
use CPAN::DistnameInfo;
use Module::CoreList;

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

    return 1;
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
        if (
             !defined( $versions->{$distname} )
             || ( defined( $versions->{$distname} )
                  && _is_gt( $distver, $versions->{$distname} ) )
           )
        {
            $versions->{$distname} = $distver;
        }
    }

    return $versions;
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

    return \%modsbydist;
}

around get_distribution_for_module => sub {
    my $next = shift;
    my $self = shift;

    my $found = $self->$next(@_);

    my $module      = shift;
    my $mod_version = shift;
    my @found;

    if ( $CPAN::META->exists( "CPAN::Module", $module ) )
    {
        my $pkgs = $self->packages;

        my $cpan_mod = $CPAN::META->instance( "CPAN::Module", $module );
        my $cpan_dist = CPAN::DistnameInfo->new( $cpan_mod->cpan_file() )->dist();

        foreach my $pkg_type ( keys %{$pkgs} )
        {
            push @found, grep { $_->{DIST_NAME} eq $cpan_dist } values %{ $pkgs->{$pkg_type} };
            my @mc_qry = ($module);
            defined $mod_version and $mod_version and push( @mc_qry, $mod_version );
            my $first_core = Module::CoreList->first_release(@mc_qry);
            $first_core or next;
            # XXX make 5.18.1 from 5.018001
            my ($perl_pkg) = grep { $_->{PKG_NAME} eq "perl" } values %{ $pkgs->{$pkg_type} };
            push @found, { %$perl_pkg, DIST_VERSION => $first_core };
        }
    }

    @found and return { ( $found ? %{$found} : () ), cpan => { $module => \@found } };
    $found and return $found;

    return;
};

sub _is_gt
{
    my $gt;
    defined( $_[0] ) and $_[0] =~ /^v/ and $_[1] !~ /^v/ and $_[1] = "v$_[1]";
    defined( $_[0] ) and $_[0] !~ /^v/ and $_[1] =~ /^v/ and $_[0] = "v$_[0]";
    eval { $gt = defined( $_[0] ) && ( version->parse( $_[0] ) > version->parse( $_[1] ) ); };
    if ($@)
    {
        $gt = defined( $_[0] ) && ( $_[0] gt $_[1] );
    }
    return $gt;
}

sub _is_ne
{
    my $ne;
    defined( $_[0] ) and $_[0] =~ /^v/ and $_[1] !~ /^v/ and $_[1] = "v$_[1]";
    defined( $_[0] ) and $_[0] !~ /^v/ and $_[1] =~ /^v/ and $_[0] = "v$_[0]";
    eval { $ne = defined( $_[0] )
          && ( version->parse( $_[0] ) != version->parse( $_[1] ) ); };
    if ($@)
    {
        $ne = defined( $_[0] ) && ( $_[0] ne $_[1] );
    }
    return $ne;
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
      and
      delete @{$pkg_details}{qw(UPSTREAM_VERSION UPSTREAM_NAME UPSTREAM_COMMENT UPSTREAM_STATE)};

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
        if ( _is_gt( $Module::CoreList::version{$]}->{$distmod}, $mod->cpan_version() ) )
        {
            $core_newer{$distmod} =
              [ $Module::CoreList::version{$]}->{$distmod}, $mod->cpan_version() ];
        }
    }

    if (%core_newer)
    {
        my $pfx = "$dist_name-$dist_version has newer modules in core:";
        my $cmp =
          join( ", ", map { "$_  " . join( " > ", @{ $core_newer{$_} } ) } keys %core_newer );
        $pkg_details->{UPSTREAM_COMMENT} = "$pfx $cmp";
        return $pkg_details->{UPSTREAM_STATE} = $self->STATE_NEWER_IN_CORE;
    }

    if ( !defined($cpan_version) )
    {
        return $pkg_details->{UPSTREAM_STATE} = $self->STATE_REMOVED_FROM_INDEX;
    }
    elsif ( _is_gt( $cpan_version, $dist_version ) )
    {
        return $pkg_details->{UPSTREAM_STATE} = $self->STATE_NEWER_UPSTREAM;
    }
    elsif ( _is_ne( $cpan_version, $dist_version ) )
    {
        return $pkg_details->{UPSTREAM_STATE} = $self->STATE_OUT_OF_SYNC;
    }

    return $pkg_details->{UPSTREAM_STATE} = $self->STATE_OK;
};

around "create_module_info" => sub {
    my $next  = shift;
    my $self  = shift;
    my $minfo = $self->$next(@_);

    my $module     = shift;
    my $categories = shift;

    my ( $mod, $dist );
    eval {
        my $mcpan = MetaCPAN::API->new();
        $mod = $mcpan->module($module);
        $dist = $mcpan->release( distribution => $mod->{distribution} );
    };
    $@ and return $minfo;

    defined $minfo or $minfo = {};

    $minfo->{cpan} = {
                       DIST_NAME   => $dist->{name},
                       DIST        => $dist->{distribution},
                       DIST_FILE   => $dist->{archive},
                       DIST_URL    => $dist->{download_url},
                       CATEGORIES  => $categories,
                       PKG_LICENSE => $dist->{license},
                       PKG_COMMENT => $dist->{abstract},
                       PKG_PREREQ  => $dist->{dependency},
                       PKG_DESCR   => $mod->{description},
                       PKG4MOD     => $module,
                     };

    $dist->{metadata}->{x_breaks} and $minfo->{CONFLICTS} = $dist->{metadata}->{x_breaks};
    $dist->{metadata}->{generated_by}
      and $dist->{metadata}->{generated_by} =~ m/^(.*) version/
      and $minfo->{GENERATOR} = $1;

    return $minfo;
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
