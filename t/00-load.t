#!perl -T
use 5.008003;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Packager::Utils' ) || print "Bail out!\n";
}

diag( "Testing Packager::Utils $Packager::Utils::VERSION, Perl $], $^X" );
