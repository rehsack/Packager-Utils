package Packager::Utils::Role::Packages;

use Moo::Role;

our $VERSION = '0.001';

has "installed_packages" => ( is => "lazy" );

sub _build_installed_packages { {} }

has "packages" => ( is => "lazy" );

requires "cached_packages";

sub _build_packages { $_[0]->cached_packages }

use MooX::Roles::Pluggable search_path => __PACKAGE__;

1;
