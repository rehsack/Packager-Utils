package Packager::Utils::Cmd::Find::Cmd::Package;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options with_config_from_file => 1;

option modules => (
                    is        => "ro",
                    format    => 's@',
                    required  => 1,
                    autosplit => ",",
                    doc       => "Specify list of modules to resolve to distributions",
                    long_doc  => "Specify a list of modules to find the "
                      . "distribution for and package it. You can specify more "
                      . "than one by either using --modules several times or "
                      . "separating module names by ','.\n\n"
                      . "For example: Package::Stash,ogd,ExtUtils::MakeMaker",
                  );

with "Packager::Utils::Role::Upstream", "Packager::Utils::Role::Packages",
  "Packager::Utils::Role::Report", "Packager::Utils::Role::Cache";

use Data::Dumper;

sub _build_template_tool
{
    return qw(findpkg);
}

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
