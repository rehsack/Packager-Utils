package Packager::Utils::Cmd::Check::Cmd::Up2date;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options with_config_from_file => 1;

with "Packager::Utils::Role::Upstream", "Packager::Utils::Role::Packages",
  "Packager::Utils::Role::Report", "Packager::Utils::Role::Cache";

my @pkg_detail_keys = (
                        qw(DIST_NAME DIST_VERSION DIST_FILE PKG_NAME PKG_VERSION),
                        qw(PKG_MAINTAINER PKG_HOMEPAGE PKG_INSTALLED PKG_LOCATION),
                        qw(UPSTREAM_VERSION UPSTREAM_NAME UPSTREAM_STATE UPSTREAM_COMMENT)
                      );

sub execute
{
    my ( $self, $args_ref, $chain_ref ) = @_;

    $self->init_upstream();

    my $packages = $self->packages();
    foreach my $pkg_system ( keys %$packages )
    {
        my ( $up_to_date, $need_update, $need_check ) = (0) x 3;
        my @pkgs_in_state;

        my @pkglist = sort keys %{ $packages->{$pkg_system} };
        foreach my $pkg (@pkglist)
        {
            my $state   = $self->upstream_up2date_state( $packages->{$pkg_system}->{$pkg} );
            my $counter = \$up_to_date;
            if ($state)
            {
                my %pkg_details;
                @pkg_details{@pkg_detail_keys} =
                  @{ $packages->{$pkg_system}->{$pkg} }{@pkg_detail_keys};
                push( @pkgs_in_state, \%pkg_details );
                $counter =
                  $pkg_details{UPSTREAM_STATE} == $self->STATE_NEWER_UPSTREAM
                  ? \$need_update
                  : \$need_check;
            }

            ++${$counter};
        }

        my %vars = (
                     data          => \@pkgs_in_state,
                     STATE_REMARKS => $self->state_remarks,
                     STATE_CMPOPS  => $self->state_cmpops,
                     COUNT         => {
                                UP2DATE     => $up_to_date,
                                ENTIRE      => scalar(@pkglist),
                                NEED_UPDATE => $need_update,
                                NEED_CHECK  => $need_check
                              },
                   );

        $self->process_templates( $pkg_system, \%vars );
    }
    $self->cache_packages;

    exit 0;
}

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
