#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;
use Module::Install::Catalyst; # Complain loudly if you don't have
                               # Catalyst::Devel installed or haven't said
                               # 'make dist' to create a standalone tarball.

name 'solGS';
all_from 'lib/solGS.pm';

requires 'Catalyst::Runtime' => '5.80032';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Action::RenderView';
requires 'Catalyst::Controller::HTML::FormFu';
requires 'CatalystX::GlobalContext' ;
requires 'Moose';
requires 'namespace::autoclean';
requires 'Bio::Chado::Schema' => '0.20000';
requires 'URI::FromHash';
requires 'HTML::FormFu';
requires 'Scalar::Util';
requires 'List::MoreUtils';
requires 'HTML::Mason';
requires 'YAML::Any';
requires 'List::Compare';
requires 'File::Temp';
requires 'File::Path';
requires 'File::Copy';
requires 'Cache::File';
requires 'Try::Tiny';
requires 'File::Spec::Functions';
requires 'File::Slurp';
requires 'JSON::Any';
requires 'JSON';
requires 'String::CRC';

requires 'Config::General'; # This should reflect the config file format you've chosen
                 # See Catalyst::Plugin::ConfigLoader for supported formats
test_requires 'Test::More' => '0.88';
catalyst;

install_script glob('script/*.pl');
auto_install;
WriteAll;
