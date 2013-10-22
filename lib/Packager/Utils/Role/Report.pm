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
                     is        => "ro",
                     format    => "s@",
                     doc       => "Desired output templates",
                     autosplit => ",",
                     short     => "t",
                     required  => 1,
                   );

option 'target' => (
                     is     => "lazy",
                     format => "s",
                     doc    => "Desired target location for processed templates",
                     short  => "o",
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

1;
