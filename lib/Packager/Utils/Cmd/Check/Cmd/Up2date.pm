package Packager::Utils::Cmd::Check::Cmd::Up2date;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options with_config_from_file => 1;

option 'output' => (
                     is        => "ro",
                     format    => "s@",
                     doc       => "Desired output templates",
                     autosplit => 1,
                     short     => "t",
                     required  => 1,
                   );

option 'target' => (
                     is     => "lazy",
                     format => "s",
                     doc    => "Desired target location for processed templates",
                     short  => "o",
                   );

with "Packager::Utils::Role::Upstream", "Packager::Utils::Role::Packages",
  "Packager::Utils::Role::Template", "Packager::Utils::Role::Cache";

sub _build_target
{
    eval "require File::HomeDir;";
    $@ and return $ENV{HOME};
    return File::HomeDir->my_home();
}

my @pkg_detail_keys = (
                        qw(DIST_NAME DIST_VERSION DIST_FILE PKG_NAME PKG_VERSION),
                        qw(PKG_MAINTAINER PKG_HOMEPAGE PKG_INSTALLED PKG_LOCATION),
                        qw(UPSTREAM_VERSION UPSTREAM_NAME UPSTREAM_STATE UPSTREAM_COMMENT)
                      );

sub execute
{
    my ( $self, $args_ref, $chain_ref ) = @_;

    $self->init_upstream();

    my $packages = $self->packages();
    foreach my $pkg_system ( keys %$packages )
    {
        my ( $up_to_date, $need_update, $need_check ) = (0) x 3;
        my @pkgs_in_state;

        my @pkglist = sort keys %{ $packages->{$pkg_system} };
        foreach my $pkg (@pkglist)
        {
            my $state   = $self->upstream_up2date_state( $packages->{$pkg_system}->{$pkg} );
            my $counter = \$up_to_date;
            if ($state)
            {
                my %pkg_details;
                @pkg_details{@pkg_detail_keys} =
                  @{ $packages->{$pkg_system}->{$pkg} }{@pkg_detail_keys};
                push( @pkgs_in_state, \%pkg_details );
                $counter =
                  $pkg_details{UPSTREAM_STATE} == $self->STATE_NEWER_UPSTREAM
                  ? \$need_update
                  : \$need_check;
            }

            ++${$counter};
        }

        my %vars = (
                     data          => \@pkgs_in_state,
                     STATE_REMARKS => $self->state_remarks,
                     STATE_CMPOPS  => $self->state_cmpops,
                     COUNT         => {
                                UP2DATE     => $up_to_date,
                                ENTIRE      => scalar(@pkglist),
                                NEED_UPDATE => $need_update,
                                NEED_CHECK  => $need_check
                              },
                   );

        $self->process_templates( $pkg_system, \%vars );
    }
    $self->cache_packages;

    exit 0;
}

1;
