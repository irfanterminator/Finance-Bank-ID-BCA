
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  DISTNAME  => 'Finance-Bank-ID-BCA',
  NAME      => 'Finance::Bank::ID::BCA',
  AUTHOR    => "Steven\ Haryanto\ \<stevenharyanto\@gmail\.com\>",
  ABSTRACT  => "Check\ your\ BCA\ accounts\ from\ Perl",
  VERSION   => '0.04',
  EXE_FILES => [ qw() ],
  (eval { ExtUtils::MakeMaker->VERSION(6.31) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM    => {
    "Test::More" => '0',
    "DateTime" => '0',
    "WWW::Mechanize" => '0',
    "File::Slurp" => '0',
    "Log::Log4perl" => '0',
    "Moose" => '0',
  },
  test => {TESTS => 't/*.t'}
);

