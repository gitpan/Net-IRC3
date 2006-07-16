#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Net::IRC3' );
}

diag( "Testing Net::IRC3 $Net::IRC3::VERSION, Perl $], $^X" );
