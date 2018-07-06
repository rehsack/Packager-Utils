package Packager::Utils::Role::Logging;

use Moo::Role;
use MooX::Options;

use Class::Load qw(load_class);

with "MooX::Log::Any";

has log_adapter => (
    is       => "ro",
    required => 1,
    trigger  => 1,
);

my $guard;

sub _trigger_log_adapter
{
    my ($self, $opts) = @_;
    $guard and return;
    load_class("Log::Any::Adapter")->set({lexically => \$guard}, @{$opts});
}
1;
