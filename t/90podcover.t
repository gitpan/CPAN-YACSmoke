#!/usr/bin/perl

use strict;
use Test::More;

eval "use Test::Pod::Coverage";

plan skip_all => "Test::Pod::Coverage required" if $@;

plan tests => 3;

pod_coverage_ok("CPAN::YACSmoke");
pod_coverage_ok("CPAN::YACSmoke::Plugin::Recent");
pod_coverage_ok("CPAN::YACSmoke::Plugin::SmokeDB");

