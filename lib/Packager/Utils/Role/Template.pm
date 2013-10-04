package Packager::Utils::Role::Template;

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
                     autosplit => 1,
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

has template_directories => ( is => "lazy" );

sub _build_template_directories
{
    my ($self) = @_;
    ( my $tool = ref($self) ) =~ s/.*::([^:]+)$/$1/;
    $tool = lc $tool;

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
        ( my $ext = $name ) =~ s/([^-]+).*/$1/;
        $name => {
                   fqpn => $_,
                   ext  => $ext
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
        defined $self->templates->{$tgt} or next;    # XXX die ?
        my $tpl = $self->templates->{$tgt};
        my $tgtfn = File::Spec->catfile( $self->target, $pkg_system . "-up2date." . $tpl->{ext} );

        $template->process( $tpl->{fqpn}, $vars, $tgtfn )
          or die $template->error();
    }
}

1;
