package Packager::Utils::Role::Packages;

use Moo::Role;
use MooX::Options;

our $VERSION = '0.001';

option packages_pattern => (
                             is        => "ro",
                             predicate => 1,
                             doc       => "Shell pattern filtering packages",
                             format    => "s@",
                             long_doc  => "Shell pattern for restricting the "
                               . "packages to be evaluated during "
                               . "the \"scan for existing packages\" "
                               . "process.\n\n"
                               . "Examples: --packages-pattern \"p5-*\" "
                               . "--packages-pattern perl5",
                           );

# sub has_packages_pattern { defined $_[0]->packages_pattern and return 1; return; }

has '_archive_extensions' => (
    is      => 'ro',
    default => sub {
        return [ map { "." . $_ } qw(tar tar.gz tar.bz2 tar.xz tgz tbz 7z zip rar) ];
    },
    init_arg => undef
                        );

has "installed_packages" => ( is => "lazy" );

sub _build_installed_packages { {} }

has "packages" => ( is => "lazy" );

requires "cached_packages";

sub _build_packages { $_[0]->cached_packages }

sub create_package_info { {} }

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
