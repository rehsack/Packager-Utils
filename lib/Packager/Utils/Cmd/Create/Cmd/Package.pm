package Packager::Utils::Cmd::Create::Cmd::Package;

use 5.008003;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Cmd;
use MooX::Options with_config_from_file => 1;

option modules => (
                    is        => "ro",
                    format    => 's@',
                    required  => 1,
                    autosplit => ",",
                    doc       => "Specify list of modules to create packages for",
                    long_doc  => "Specify a list of modules to find the "
                      . "distribution for and package it. You can specify more "
                      . "than one by either using --modules several times or "
                      . "separating module names by ','.\n\n"
                      . "For example: Package::Stash,ogd,ExtUtils::MakeMaker",
                  );

option categories => (
                     is        => "lazy",
                     format    => 's@',
                     required  => 0,
                     autosplit => ",",
                     doc       => "Specify list of categories",
                     long_doc  => "Specify list of categories where the packages "
                       . "should be created for. The first category is "
                       . "always the primary one.\n\n"
                       . "You can specify categories dedicate per module "
                       . "by putting the module name in brackets after the "
                       . "category name. Dedicated categories are always "
                       . "prepended.\n\n"
                       . "Example: --categories perl5 --modules Sys::Filesystem --categories "
                       . "\"sysutils(Sys::Filesystem),filesystems(Sys::Filesystem)\" --modules Moo "
                       . "\"devel(Moo)\"",
                     );

has output => ( is => "rw" );

has target => ( is => "rw" );

with "Packager::Utils::Role::Upstream", "Packager::Utils::Role::Packages",
  "Packager::Utils::Role::Template", "Packager::Utils::Role::Cache",
  "Packager::Utils::Role::Logging";

sub _build_categories { [] }

sub _build_template_tool
{
    return qw(createpkg);
}

sub target_file
{
    my ( $self, $pkg_system, $tgt ) = @_;

    my $target = $self->target;
    $self->templates->{$tgt} or return;
    my $tpl = $self->templates->{$tgt};
    $tpl->{type} eq $pkg_system or return;
    my $tgtfn = File::Spec->catfile( $target, $tpl->{option} );

    return ( $tpl, $tgtfn );
}

sub execute
{
    my ( $self, $args_ref, $chain_ref ) = @_;

    my @categories;
    my %categories;
    my $cat_add = sub {
	my ($mods, $cat) = @_;
	my @mods = split(", ", $mods);
	push( @{ $categories{$_} }, $cat ) for (@mods);
	1
    };
    foreach my $category ( @{ $self->categories } )
    {
        $category =~ m/^([^\(]+)\(([^\)]+)\)$/ and $cat_add->($2, $1) and next;
        push @categories, $category;
    }

    $self->init_upstream();
    my $packages = $self->packages();

    my @pkgs;
    foreach my $module ( @{ $self->modules } )
    {
        my $pkg_det = $self->get_distribution_for_module($module);
        my @mcat    = @categories;
        defined $categories{$module} and unshift( @mcat, @{ $categories{$module} } );
	# XXX known bug: when it's in core and not packaged, we update perl o.O
        my $minfo = $self->create_module_info( $module, \@mcat );
        my $pinfo = $self->create_package_info( $minfo, $pkg_det );
        push( @pkgs, $pinfo );
    }

    $self->output( [ keys %{ $self->templates } ] );
    foreach my $pkg (@pkgs)
    {
        while ( my ( $pkg_type, $pkg_info ) = each %$pkg )
        {
            $self->target( $pkg_info->{ORIGIN} );
            $self->process_templates( $pkg_type, $pkg_info );
        }
    }

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
