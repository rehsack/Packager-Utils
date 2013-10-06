package Packager::Utils::Cmd::Find::Cmd::Package;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options with_config_from_file => 1;

option modules => (
		      is => "ro",
                      format    => 's@',
                      required  => 1,
                      autosplit => 1,
                      doc       => "Specify list of modules to resolve to distributions",
                    );

with "Packager::Utils::Role::Upstream", "Packager::Utils::Role::Packages",
  "Packager::Utils::Role::Template", "Packager::Utils::Role::Cache";

    use Data::Dumper;

sub execute
{
    my ( $self, $args_ref, $chain_ref ) = @_;

    $self->init_upstream();

    my $packages = $self->packages();

    my @distris;
    foreach my $module ( @{ $self->modules } )
    {
        push( @distris, $self->get_distribution_for_module($module) );
    }

    print Dumper \@distris;
    $self->cache_packages;

    exit 0;
}

1;
