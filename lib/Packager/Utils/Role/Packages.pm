package Packager::Utils::Role::Packages;

use Moo::Role;
use MooX::Options;

our $VERSION = '0.001';

option packages_pattern => (
                             is        => "ro",
                             predicate => 1,
                             doc       => "Shell pattern filtering packages",
                             format    => "s@",
                             long_doc  => "Shell pattern for restricting the "
                               . "packages to be evaluated during "
                               . "the \"scan for existing packages\" "
                               . "process.\n\n"
                               . "Examples: --packages-pattern \"p5-*\" "
                               . "--packages-pattern perl5",
                           );

# sub has_packages_pattern { defined $_[0]->packages_pattern and return 1; return; }

has "installed_packages" => ( is => "lazy" );

sub _build_installed_packages { {} }

has "packages" => ( is => "lazy" );

requires "cached_packages";

sub _build_packages { $_[0]->cached_packages }

sub create_package_info { {} }

use MooX::Roles::Pluggable search_path => __PACKAGE__;

1;
