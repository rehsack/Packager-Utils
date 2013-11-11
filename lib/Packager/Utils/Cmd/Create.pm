package Packager::Utils::Cmd::Create;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options with_config_from_file => 1;

sub execute
{
    my ( $self ) = @_;

    die "Need to specify a sub-command: " . join(", ", sort keys %{$self->command_commands}) . "!\n";
}

1;
