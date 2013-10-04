package Packager::Utils::Cache::Schema;

use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use parent 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;

sub init
{
    my ($schema) = @_;
    my @init_info = ( [ "pkg_util_schema_version", "1" ], );
    $schema->populate( 'PkgUtilInfo', [ [qw(name value)], @init_info ] );
}

1;
