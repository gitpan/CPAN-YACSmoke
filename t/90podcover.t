#!/usr/bin/perl

use strict;
use Test::More tests => 3;

eval "use Test::Pod::Coverage";

plan skip_all => "Test::Pod::Coverage required" if $@;

pod_coverage_ok("CPAN::YACSmoke");
pod_coverage_ok("CPAN::YACSmoke::Plugin::Recent");
pod_coverage_ok("CPAN::YACSmoke::Plugin::SmokeDB");

