package Packager::Utils::Role::Packages;

use Moo::Role;
use MooX::Options;

our $VERSION = '0.001';

=head1 NAME

Packager::Utils::Role::Packages - role providing packager backends

=head1 DESCRIPTION

This role provides the API for dealing with different package management backends.
It doesn't care for frontends like PackageKit or pkgin - only for things like
L<PkgSrc|http://www.pkgsrc.org/>, L<Yocto's BitBake|https://www.yoctoproject.org/>
or alike.

When loaded, at the end of API definition, all plugins for the role is loaded
via L<MooX::Roles::Pluggable>.

=head1 ATTRIBUTES

=head2 packages_pattern

Attribute to allow restricting patterns to search for via command line.

=cut

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

has '_archive_extensions' => (
    is      => 'ro',
    default => sub {
        return [ map { "." . $_ } qw(tar tar.gz tar.bz2 tar.xz tgz tbz 7z zip rar) ];
    },
    init_arg => undef
                        );

=head2 installed_packages

Attribute containing per packages backend a hash of installed packages
with package name as key.

=cut

has "installed_packages" => ( is => "lazy" );

sub _build_installed_packages { {} }

=head2 packages

Attribute containing per packages backend a hash of available packages
with package name as key. Value should contain a hash with following keys:

=over 4

=item C<DIST_NAME>

This is a key for any specified I<master site> which unambiguously
identifies the distribution which is packaged. Usually ambigouos
distributions are distinguished by package name prefix or suffix.
Name spaces on master sites shall currently be part of the C<DIST_NAME>.

=item C<DIST_VERSION>

Version of the distribution packaged. Multiple versions of the same
distribution might be packaged (foo, foo-legacy, foo-devel, ...).

=item C<DIST_FILE>

Name of the archive (eg. tarball) for combination of C<DIST_NAME> and
C<DIST_VERSION>.

=item C<PKG_NAME>

Name of the package. This must be unique per packaging backend and version.
Sometimes the C<PKG_NAME> is derived from C<DIST_NAME> by pre-/appending
prefix and/or suffixes.

=item C<PKG_VERSION>

The version of the package. Usually it contains in addition to the
upstream specified C<DIST_VERSION> a package revision or a patch-level.

=item C<PKG_MAINTAINER>

Usually this field contains the mail address of the contact who's
responsible for fixes or updates of the package in the appropriate packaging
repository.

=item C<PKG_INSTALLED>

Contains a boolean value whether a package is installed or not. This is
a depreciated field and might be removed in future versions. It's
recommended for new backends not to support it anymore.

=item C<PKG_LOCATION>

Contains the relative location of the package against the packager's
repository.

=item C<PKG_HOMEPAGE>

Contains the homepage of the distribution for the package.

=item C<PKG_LICENSE>

Contains the license name(s) of the distribution.

=item C<PKG_MASTER_SITES>

Contains a list of URI's where the distribution files can be downloaded.

=back

=cut

has "packages" => ( is => "lazy" );

requires "cached_packages";

sub _build_packages { $_[0]->cached_packages }

=head1 methods

=head2 prepare_package_info

Prepares the information to process templates to do most of the job of
getting an upstream distribution into a package. This requires 
L<prepared information for distribution|Packager::Utils::Role::Upstream/prepare_distribution_info>.

=cut

sub prepare_package_info { {} }

=head2 package_type

=cut

sub package_type { }

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
