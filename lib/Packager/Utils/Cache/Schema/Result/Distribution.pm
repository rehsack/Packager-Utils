package Packager::Utils::Cache::Schema::Result::Distribution;

use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use parent 'DBIx::Class::Core';

=head1 NAME

Packager::Utils::Cache::Schema::Result::Distribution

=head1 TABLE: C<PACKAGES>

=cut

__PACKAGE__->table("DISTRIBUTIONS");

=head1 ACCESSORS

=head2 dist_id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 dist_name

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=head2 dist_version

  data_type: 'varchar'
  is_nullable: 1
  size: 16

=head2 dist_file

  data_type: 'varchar'
  is_nullable: 1
  size: 1024

=cut

__PACKAGE__->add_columns(
                          "dist_id",
                          {
                             data_type         => "integer",
                             is_auto_increment => 1,
                             is_nullable       => 0
                          },
                          "dist_name",
                          {
                             data_type   => "varchar",
                             is_nullable => 0,
                             size        => 64
                          },
                          "dist_version",
                          {
                             data_type   => "varchar",
                             is_nullable => 1,
                             size        => 16
                          },
                          "dist_file",
                          {
                             data_type   => "varchar",
                             is_nullable => 1,
                             size        => 1024
                          },
                        );

=head1 PRIMARY KEY

=over 4

=item * L</dist_id>

=back

=cut

__PACKAGE__->set_primary_key("dist_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<dist_name_version_unique>

=over 4

=item * L</dist_name>

=item * L</dist_version>

=back

=cut

__PACKAGE__->add_unique_constraint( "dist_name_version_unique", [ "dist_name", "dist_version" ] );

=head1 RELATIONS

=head2 packages

Type: has_many

Related object: L<Packager::Utils::Cache::Schema::Result::Package>

=cut

__PACKAGE__->has_many(
                       "packages",
                       "Packager::Utils::Cache::Schema::Result::Package",
                       { "foreign.dist_id" => "self.dist_id" },
                       {
                          cascade_copy   => 0,
                          cascade_delete => 0
                       },
                     );

=head2 upstream

Type: has_many

Related object: L<Packager::Utils::Cache::Schema::Result::Upstream>

=cut

__PACKAGE__->has_many(
                       "upstream",
                       "Packager::Utils::Cache::Schema::Result::Upstream",
                       { "foreign.dist_id" => "self.dist_id" },
                       {
                          cascade_copy   => 0,
                          cascade_delete => 0
                       },
                     );

1;
