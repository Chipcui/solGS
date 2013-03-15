#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;
use Module::Install::Catalyst; # Complain loudly if you don't have
                               # Catalyst::Devel installed or haven't said
                               # 'make dist' to create a standalone tarball.

name 'solGS';
all_from 'lib/solGS.pm';
requires 'Bio::Chado::Schema' => '0.20000';
requires 'Catalyst::Runtime' => '5.80032';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Action::RenderView';
requires 'Catalyst::Controller::HTML::FormFu';
requires 'CatalystX::GlobalContext' ;
requires 'Cache::File';
requires 'Carp';
requires 'Cwd';

requires 'File::Spec';
requires 'File::Temp';
requires 'File::Path';
requires 'File::Copy';
requires 'File::Basename';
requires 'File::Spec::Functions';
requires 'File::Slurp';
requires 'HTML::FormFu';
requires 'HTML::Mason';
requires 'HTML::Mason::Interp';
requires 'JSON::Any';
requires 'JSON';
requires 'List::Compare';
requires 'List::MoreUtils';
requires 'Moose';
requires 'Moose::Role';
requires 'namespace::autoclean';
requires 'Path::Class';
requires 'Scalar::Util';
requires 'String::CRC';
requires 'Storable';
requires 'Try::Tiny';
requires 'Test::WWW::Mechanize::Catalyst';
requires 'Test::More';
requires 'URI';
requires 'URI::FromHash';
requires 'YAML::Any';

requires 'Config::General'; # This should reflect the config file format you've chosen
                 # See Catalyst::Plugin::ConfigLoader for supported formats
test_requires 'Test::More' => '0.88';
catalyst;

install_script glob('script/*.pl');
auto_install;
WriteAll;
