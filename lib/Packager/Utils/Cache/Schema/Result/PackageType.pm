package Packager::Utils::Cache::Schema::Result::PackageType;

use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use parent 'DBIx::Class::Core';

=head1 NAME

Packager::Utils::Cache::Schema::Result::PackageType

=head1 TABLE: C<PACKAGE_TYPES>

=cut

__PACKAGE__->table("PACKAGE_TYPES");

=head1 ACCESSORS

=head2 pkg_type_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 pkg_type_name

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=cut

__PACKAGE__->add_columns(
                          "pkg_type_id",
                          {
                             data_type         => "integer",
                             is_auto_increment => 1,
                             is_nullable       => 0
                          },
                          "pkg_type_name",
                          {
                             data_type   => "varchar",
                             is_nullable => 0,
                             size        => 64
                          },
                        );

=head1 PRIMARY KEY

=over 4

=item * L</pkg_type_id>

=back

=cut

__PACKAGE__->set_primary_key("pkg_type_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<pkg_type_name_unique>

=over 4

=item * L</pkg_type_name>

=back

=cut

__PACKAGE__->add_unique_constraint( "pkg_type_name_unique", ["pkg_type_name"] );

=head1 RELATIONS

=head2 packages

Type: has_many

Related object: L<Packager::Utils::Cache::Schema::Result::Package>

=cut

__PACKAGE__->has_many(
                       "packages",
                       "Packager::Utils::Cache::Schema::Result::Package",
                       { "foreign.pkg_type_id" => "self.pkg_type_id" },
                       {
                          cascade_copy   => 0,
                          cascade_delete => 0
                       },
                     );

1;
