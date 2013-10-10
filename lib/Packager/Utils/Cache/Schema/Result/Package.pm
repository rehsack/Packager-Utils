package Packager::Utils::Cache::Schema::Result::Package;

use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use parent 'DBIx::Class::Core';

=head1 NAME

Packager::Utils::Cache::Schema::Result::Package

=head1 TABLE: C<PACKAGES>

=cut

__PACKAGE__->table("PACKAGES");

=head1 ACCESSORS

=head2 pkg_type_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 dist_id

  data_type: 'integer'
  is_nullable: 0
  is_foreign_key: 1

=head2 upstream_id

  data_type: 'integer'
  is_nullable: 1
  is_foreign_key: 1

=head2 pkg_name

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=head2 pkg_version

  data_type: 'varchar'
  is_nullable: 0
  size: 16

=head2 pkg_maintainer

  data_type: 'varchar'
  is_nullable: 0
  size: 256

=head2 pkg_installed

  data_type: 'varchar'
  is_nullable: 1
  size: 16

=head2 pkg_location

  data_type: 'varchar'
  is_nullable: 0
  size: 1024

=head2 pkg_homepage

  data_type: 'varchar'
  is_nullable: 1
  size: 1024

=head2 pkg_license

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=head2 pkg_master_sites

  data_type: 'varchar'
  is_nullable: 1
  size: 4096

=cut

__PACKAGE__->add_columns(
    "pkg_type_id",
    {
       data_type      => "integer",
       is_foreign_key => 1,
       is_nullable    => 0
    },
    "dist_id",
    {
       data_type      => "integer",
       is_nullable    => 0,
       is_foreign_key => 1,
    },
    "upstream_id",
    {
       data_type      => "integer",
       is_nullable    => 1,
       is_foreign_key => 1,
    },
    "pkg_name",
    {
       data_type   => "varchar",
       is_nullable => 0,
       size        => 64
    },
    "pkg_version",
    {
       data_type   => "varchar",
       is_nullable => 0,
       size        => 16
    },
    "pkg_maintainer",
    {
       data_type   => "varchar",
       is_nullable => 0,
       size        => 256
    },
    "pkg_installed",
    {
       data_type   => "varchar",
       is_nullable => 1,
       size        => 16
    },
    "pkg_location",
    {
       data_type   => "varchar",
       is_nullable => 0,
       size        => 1024
    },
    "pkg_homepage",
    {
       data_type   => "varchar",
       is_nullable => 1,
       size        => 1024
    },
    "pkg_license",
    {
       data_type   => "varchar",
       is_nullable => 1,
       size        => 256
    },
    "pkg_master_sites",
    {
       data_type   => "varchar",
       is_nullable => 1,
       size        => 4096

    },
);

=head1 PRIMARY KEY

=over 4

=item * L</pkg_location>

=back

=cut

__PACKAGE__->set_primary_key("pkg_location");

=head1 RELATIONS

=head2 package_types

Type: belongs_to

Related object: L<Packager::Utils::Cache::Schema::Result::Distribution>

=cut

__PACKAGE__->belongs_to(
                         "package_types",
                         "Packager::Utils::Cache::Schema::Result::PackageType",
                         { pkg_type_id => "pkg_type_id" },
                         {
                            is_deferrable => 0,
                            on_delete     => "NO ACTION",
                            on_update     => "NO ACTION"
                         },
                       );

=head2 distribution

Type: belongs_to

Related object: L<Packager::Utils::Cache::Schema::Result::Distribution>

=cut

__PACKAGE__->belongs_to(
                         "distribution",
                         "Packager::Utils::Cache::Schema::Result::Distribution",
                         { dist_id => "dist_id" },
                         {
                            is_deferrable => 0,
                            on_delete     => "NO ACTION",
                            on_update     => "NO ACTION"
                         },
                       );

=head2 upstream

Type: belongs_to

Related object: L<Packager::Utils::Cache::Schema::Result::Distribution>

=cut

__PACKAGE__->belongs_to(
                         "upstream",
                         "Packager::Utils::Cache::Schema::Result::Upstream",
                         { upstream_id => "upstream_id" },
                         {
                            is_deferrable => 0,
                            on_delete     => "NO ACTION",
                            on_update     => "NO ACTION"
                         },
                       );

1;
