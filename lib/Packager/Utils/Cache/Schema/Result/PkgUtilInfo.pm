package Packager::Utils::Cache::Schema::Result::PkgUtilInfo;

use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use parent 'DBIx::Class::Core';

=head1 NAME

Packager::Utils::Cache::Schema::Result::PkgUtilInfo

=head1 TABLE: C<PKG_UTIL_INFO>

=cut

__PACKAGE__->table("PKG_UTIL_INFO");

=head1 ACCESSORS

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 64

=head2 value

  data_type: 'varchar'
  is_nullable: 0
  size: 1024

=cut

__PACKAGE__->add_columns(
                          "name",
                          {
                             data_type   => "varchar",
                             is_nullable => 0,
                             size        => 64
                          },
                          "value",
                          {
                             data_type   => "varchar",
                             is_nullable => 0,
                             size        => 1024
                          },
                        );

=head1 PRIMARY KEY

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->set_primary_key("name");

1;

