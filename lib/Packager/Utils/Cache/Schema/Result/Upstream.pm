package Packager::Utils::Cache::Schema::Result::Upstream;

use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use parent 'DBIx::Class::Core';

=head1 NAME

Packager::Utils::Cache::Schema::Result::Upstream

=head1 TABLE: C<PACKAGES>

=cut

__PACKAGE__->table("UPSTREAMS");

=head1 ACCESSORS

=head2 dist_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 upstream_name

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=head2 upstream_version

  data_type: 'varchar'
  is_nullable: 1
  size: 16

=head2 upstream_state

  data_type: 'varchar'
  is_nullable: 1
  size: 64

=head2 upstream_comment

  data_type: 'varchar'
  is_nullable: 1
  size: 16

=cut

__PACKAGE__->add_columns(
                          "dist_id",
                          {
                             data_type      => "integer",
                             is_nullable    => 0,
                             is_foreign_key => 1,
                          },
                          "upstream_id",
                          {
                             data_type         => "integer",
                             is_auto_increment => 1,
                             is_nullable       => 0
                          },
                          "upstream_name",
                          {
                             data_type   => "varchar",
                             is_nullable => 0,
                             size        => 64
                          },
                          "upstream_version",
                          {
                             data_type   => "varchar",
                             is_nullable => 1,
                             size        => 16
                          },
                          "upstream_state",
                          {
                             data_type   => "integer",
                             is_nullable => 1,
                          },
                          "upstream_comment",
                          {
                             data_type   => "varchar",
                             is_nullable => 1,
                             size        => 1024
                          },
                        );

=head1 PRIMARY KEY

=over 4

=item * L</upstream_id>

=back

=cut

__PACKAGE__->set_primary_key("upstream_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<upstream_name_version_unique>

=over 4

=item * L</upstream_name>

=item * L</upstream_version>

=back

=cut

__PACKAGE__->add_unique_constraint( "upstream_name_version_unique",
                                    [ "upstream_name", "upstream_version" ] );

=head1 RELATIONS

=head2 dist_name

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

=head2 packages

Type: has_many

Related object: L<Packager::Utils::Cache::Schema::Result::Package>

=cut

__PACKAGE__->has_many(
                       "packages",
                       "Packager::Utils::Cache::Schema::Result::Package",
                       { "foreign.upstream_id" => "self.upstream_id" },
                       {
                          cascade_copy   => 0,
                          cascade_delete => 0
                       },
                     );

1;
