package Packager::Utils::Role::Packages;

use Moo::Role;

our $VERSION = '0.001';

has "installed_packages" => ( is => "lazy" );

sub _build_installed_packages { {} }

has "packaged_modules" => ( is => "lazy" );

sub _build_packaged_modules { {} }

use MooX::Roles::Pluggable search_path => __PACKAGE__;

1;
