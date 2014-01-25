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
    \@state_cmpops;
}

sub get_distribution_for_module { return; }

sub init_upstream { 1 }

sub upstream_up2date_state { return; }

sub create_module_info { {} }

use MooX::Roles::Pluggable search_path => __PACKAGE__;

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-packager-utils at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Packager-Utils>.
I will be notified, and then you'll automatically be notified of progress
on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Packager::Utils

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Packager-Utils>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Packager-Utils>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Packager-Utils>

=item * Search CPAN

L<http://search.cpan.org/dist/Packager-Utils/>

=back

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013,2014 Jens Rehsack.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1;
