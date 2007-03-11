#!perl
use strict;
use warnings;
use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;

plan tests => 4;

pod_coverage_ok (
   'Net::IRC3', {
      private => [ ]
   }
);

pod_coverage_ok (
   'Net::IRC3::Util', {
      private => [ ]
   }
);

pod_coverage_ok (
   'Net::IRC3::Connection', {
      private => [ qr/^_/ ]
   }
);

pod_coverage_ok (
   'Net::IRC3::Client::Connection', {
      private => [ qr/^_/, qr/_cb$/ ]
   }
);
