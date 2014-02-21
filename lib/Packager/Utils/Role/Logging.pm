package Packager::Utils::Role::Logging;

use Moo::Role;
use MooX::Options;

use Class::Load qw(load_class);

with "MooX::Log::Any";

option log_adapter => (
                        is       => "ro",
                        required => 1,
                        trigger  => 1
                      );

sub _trigger_log_adapter
{
    my ( $self, $opts ) = @_;
    load_class("Log::Any::Adapter")->set( @{$opts} );
}

1;
