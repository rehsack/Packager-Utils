package Packager::Utils::Role::Report;

use Moo::Role;
use MooX::Options;

require File::Basename;
require File::ShareDir;
require File::Find::Rule;
require File::Spec;
use Template ();

our $VERSION = '0.001';

option 'output' => (
                     is       => "ro",
                     format   => "s@",
                     doc      => "Desired output templates",
                     long_doc => "Choose a template (or some more) for "
                       . "output. The template name usually becomes part of "
                       . "generated filename - usually as extension."
                       . "Another filename can be chosen per template by assigning "
                       . "a full qualified pathname to the output-target:\n\n"
                       . '--output html-installed=`date "+%Y-%m-%d"`-foo.html',
                     autosplit => ",",
                     short     => "o",
                     required  => 1,
                   );

option 'target' => (
                     is       => "lazy",
                     format   => "s",
                     doc      => "Desired target location for processed templates",
                     long_doc => "Choose a folder where output file(s) are generated.\n\n"
                       . "\t--target /data/reports # default: \${HOME}",
                     short => "t",
                   );

sub _build_target
{
    eval "require File::HomeDir;";
    $@ and return $ENV{HOME};
    return File::HomeDir->my_home();
}

sub target_file
{
    my ( $self, $pkg_system, $tgt ) = @_;

    my $target = $self->target;
    $tgt =~ m/^([^=]+)=(.*)$/ and ( $tgt, $target ) = ( $1, $2 );
    $self->templates->{$tgt} or return;

    my $tpl   = $self->templates->{$tgt};
    my $fn    = $pkg_system . "-" . $self->template_tool . "." . $tpl->{type};
    my $tgtfn = File::Spec->catfile( $target, $fn );

    return ( $tpl, $tgtfn );
}

with "Packager::Utils::Role::Template";

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
