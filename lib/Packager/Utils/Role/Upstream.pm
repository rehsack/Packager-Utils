package Packager::Utils::Role::Upstream;

use Moo::Role;

our $VERSION = '0.001';

=head1 NAME

Packager::Utils::Role::Upstream - role providing upstream distribution handling

=head1 DESCRIPTION

This role provides the API for dealing with upstream sites providing
distributions, like L<CPAN|http://www.metacpan.org/>,
L<CTAN|http://www.ctan.org/>, L<SourceForge|http://sourceforge.net/>
or alike. Surely, sites as L<GraphViz|http://www.graphviz.org/> housing
only one distribution shall be supported as well.

When loaded, at the end of API definition, all plugins for the role is loaded
via L<MooX::Roles::Pluggable>.

=head1 ATTRIBUTES

=head2 STATE_OK

This attribute represents a flag telling the package contains the most
up-to-date version compared to upstream information.

=cut

has STATE_OK => (
                  is       => "ro",
                  init_arg => undef,
                  default  => sub { 0 }
                );

=head2 STATE_NEWER_UPSTREAM

This attribute represents a flag telling the upstream site contains
newer distributions than the packaged one.

=cut

has STATE_NEWER_UPSTREAM => (
                              is       => "ro",
                              init_arg => undef,
                              default  => sub { 1 }
                            );

=head2 STATE_OUT_OF_SYNC

This attribute represents a flag telling the upstream site contains
either older distributions than the packaged one or the upstream site
does not know about the distribution at all. However, the package
and the uptream site are not synchronized.

=cut

has STATE_OUT_OF_SYNC => (
                           is       => "ro",
                           init_arg => undef,
                           default  => sub { 2 }
                         );

=head2 STATE_ERROR

This attribute represents a flag telling the package is erroneous (ECANTPARSE
or alike).

=cut

has STATE_ERROR => (
                     is       => "ro",
                     init_arg => undef,
                     default  => sub { 101 }
                   );


=head2 STATE_BASE

This attribute represents the lowest value plugins should use for their flags.
The final builder of a plugin should invoke the setter for this attribute to
ensure unique numeration over multiple plugins.

=cut

has STATE_BASE => (
                    is       => "rw",
                    init_arg => undef,
                    default  => sub { 3 }
                  );

=head2 state_remarks

Lazy attribute containing a textual representation for each of above flags.
Plugins should initialize their representations I<around> the builder of
I<state_remarks> after calling prior ones.

=cut

has state_remarks => ( is => "lazy" );

sub _build_state_remarks
{
    my @state_remarks = ( "fine", "needs update", "out of sync" );
    $state_remarks[101] = "";
    \@state_remarks;
}

=head2 state_cmpops

Lazy attribute containing the textual representation of the compare
operations (lower than, greater than ...)

=cut

has state_cmpops => ( is => "lazy" );

sub _build_state_cmpops
{
    my @state_cmpops = ( "==", "<", "!=" );
    \@state_cmpops;
}

=head1 METHODS

=head2 get_distribution_for_module

Depreciated - will be refactored soon.

=cut

sub get_distribution_for_module { return; } # XXX

=head2 init_upstream

Relic from non-Moo history containing lazy initializations. Needs to be refactored.

=cut

sub init_upstream { 1 } # XXX

=head2 upstream_up2date_state

Proves the upstream up-to-date state of a distribution.

=cut

sub upstream_up2date_state { return; }

=head2 prepare_distribution_info

Prepares information of a distribution to create packages from the it.

=cut

sub prepare_distribution_info { {} }

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
