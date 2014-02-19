package Packager::Utils::Role::Async;

use Moo::Role;
use MooX::Options;

use IO::Async;
use IO::Async::Loop;

use IO::Async::Handle;
use IO::Async::Process;
use IO::Async::Stream;
use IO::Async::Timer::Countdown;

has loop => ( is => "lazy" );

sub _build_loop
{
    return IO::Async::Loop->new();
}

1;
