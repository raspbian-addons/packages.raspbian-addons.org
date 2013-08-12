#!/usr/bin/perl -T
# Simple Wrapper for Packages::Dispatcher;

use strict;
use warnings;

use lib '../lib';
use Packages::Dispatcher;

Packages::Dispatcher::fastcgi_dispatch();

# vim: ts=8 sw=4
