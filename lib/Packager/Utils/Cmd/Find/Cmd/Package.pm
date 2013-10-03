package Packager::Utils::Cmd::Find::Cmd::Package;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options;

sub execute
{
    my ( $self, $args_ref, $chain_ref ) = @_;

    exit 0;
}

1;
