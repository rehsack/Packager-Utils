package Packager::Utils::Role::Upstream;

use Moo::Role;

our $VERSION = '0.001';

has STATE_OK => (
                  is       => "ro",
                  init_arg => undef,
                  default  => sub { 0 }
                );
has STATE_NEWER_UPSTREAM => (
                              is       => "ro",
                              init_arg => undef,
                              default  => sub { 1 }
                            );
has STATE_OUT_OF_SYNC => (
                           is       => "ro",
                           init_arg => undef,
                           default  => sub { 2 }
                         );
has STATE_ERROR => (
                     is       => "ro",
                     init_arg => undef,
                     default  => sub { 101 }
                   );

has STATE_BASE => (
                    is       => "rw",
                    init_arg => undef,
                    default  => sub { 3 }
                  );

has state_remarks => ( is => "lazy" );

sub _build_state_remarks
{
    my @state_remarks = ( "fine", "needs update", "out of sync" );
    $state_remarks[101] = "";
    \@state_remarks;
}

has state_cmpops => ( is => "lazy" );

sub _build_state_cmpops
{
    my @state_cmpops = ( "==", "<", "!=" );
}

sub init_upstream { 1 }

sub upstream_up2date_state { return; }

use MooX::Roles::Pluggable search_path => __PACKAGE__;

1;
