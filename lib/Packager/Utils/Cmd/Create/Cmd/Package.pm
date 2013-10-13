package Packager::Utils::Cmd::Create::Cmd::Package;

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
                    autosplit => 1,
                    doc       => "Specify list of modules to create packages for",
                  );

option categories => (
                       is        => "ro",
                       format    => 's@',
                       required  => 0,
                       autosplit => 1,
                       doc       => "Specify list of categories",
                     );

with "Packager::Utils::Role::Upstream", "Packager::Utils::Role::Packages",
  "Packager::Utils::Role::Template", "Packager::Utils::Role::Cache";

sub execute
{
    my ( $self, $args_ref, $chain_ref ) = @_;

    $self->init_upstream();
    my $packages = $self->packages();

    my @categories;
    my %categories;
    foreach my $category ( @{ $self->categories } )
    {
        $category =~ m/^([^\(]+)\(([^\)]+)\)$/ and push( @{ $categories{$2} }, $1 ) and next;
        push @categories, $category;
    }

    my @pkgs;
    foreach my $module ( @{ $self->modules } )
    {
        my $pkg_det = $self->get_distribution_for_module($module);
        my @mcat    = @categories;
        defined $categories{$module} and unshift( @mcat, @{ $categories{$module} } );
        my $minfo = $self->create_module_info( $module, \@mcat );
        my $pinfo = $self->create_package_info( $minfo, $pkg_det );
        push( @pkgs, $pinfo );
    }

    use Data::Dumper;
    print( Dumper( \@pkgs ) );

    exit 0;
}

1;
