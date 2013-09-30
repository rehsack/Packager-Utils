package Packager::Utils::Cmd::Find;

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
    my @chain = @{$chain_ref};

    die "Need to specify a sub-command!\n";
}

1;
