use inc::Module::Install;

name     'Finance-Bank-ID-BCA';
all_from 'lib/Finance/Bank/ID/BCA.pm';
author   'Steven Haryanto <stevenharyanto@gmail.com>';
license  'perl';

build_requires 'Test::More';

test_requires 'File::Slurp';

requires 'DateTime';
requires 'Log::Log4perl';
requires 'Moose';
requires 'WWW::Mechanize';

auto_install;

WriteAll;
