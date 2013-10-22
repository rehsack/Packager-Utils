package Packager::Utils::Role::Template;

use Moo::Role;
use MooX::Options;

require File::Basename;
require File::ShareDir;
require File::Find::Rule;
require File::Spec;
use Template ();

our $VERSION = '0.001';

requires "output";
requires "target";

has template_tool => ( is => "lazy" );

sub _build_template_tool
{
    my ($self) = @_;
    ( my $tool = ref($self) ) =~ s/.*::([^:]+)$/$1/;
    $tool = lc $tool;

    return $tool;
}

has template_directories => ( is => "lazy" );

sub _build_template_directories
{
    my ($self) = @_;
    my $tool = $self->template_tool;

    my @tt_src_dirs =
      grep { -d $_ }
      map { ( $_, File::Spec->catdir( $_, $tool ) ) }
      grep { defined($_) } ( File::ShareDir::dist_dir("Packager-Utils") );

    return \@tt_src_dirs;
}

has templates => ( is => "lazy" );

sub _build_templates
{
    my ($self) = @_;

    my @tt_src_dirs = @{ $self->template_directories };
    my @templates   = File::Find::Rule->file()->name("*.tt2")->maxdepth(1)->in(@tt_src_dirs);

    my %templates = map {
        my $name = File::Basename::fileparse( $_, ".tt2" );
        ( my $type = $name ) =~ s/([^-]+).*/$1/;
        my $option;
        $name =~ m/^[^-]+-(.*)$/ and $option = $1;
        $name => {
                   fqpn   => $_,
                   type   => $type,
                   option => $option
                 }
    } @templates;

    return \%templates;
}

sub process_templates
{
    my ( $self, $pkg_system, $vars ) = @_;

    my $template = Template->new( INCLUDE_PATH => join( ":", @{ $self->template_directories } ),
                                  ABSOLUTE     => 1, );

    foreach my $tgt ( @{ $self->output } )
    {
        my ( $tpl, $tgtfn ) = $self->target_file( $pkg_system, $tgt );
        defined $tpl or next;    # XXX die ?

        $template->process( $tpl->{fqpn}, $vars, $tgtfn )
          or die $template->error();
    }
}

1;
