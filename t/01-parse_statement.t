#!perl -Tw

use strict;
use Test::More tests => (1 + 4*15 + 1*15);
use DateTime;
use File::Slurp;
use FindBin '$Bin';
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init($ERROR);

BEGIN {
    use_ok('Finance::Bank::ID::BCA');
}

my $ibank = Finance::Bank::ID::BCA->new();

for my $f (
    ["stmt1.html", "personal, html"],
    ["stmt1.opera10linux.txt", "personal, txt, opera10linux"],
    ["stmt1.ff35linux.txt", "personal, txt, ff35linux"],
    ["stmt1-en.opera10linux.txt", "personal (en), txt, opera10linux"],
) {
    my ($status, $error, $stmt) = $ibank->parse_statement(scalar read_file("$Bin/data/$f->[0]"));
    #print "status=$status, error=$error\n";

    # metadata
    is($stmt->{account}, "1234567890", "$f->[1] (account)");
    is($stmt->{account_holder}, "STEVEN HARYANTO", "$f->[1] (account_holder)");
    is(DateTime->compare($stmt->{start_date},
                         DateTime->new(year=>2009, month=>9, day=>14)),
       0, "$f->[1] (start_date)");
    is(DateTime->compare($stmt->{end_date},
                         DateTime->new(year=>2009, month=>10, day=>14)),
       0, "$f->[1] (end_date)");
    is($stmt->{currency}, "IDR", "$f->[1] (currency)");

    # transactions
    is(scalar(@{ $stmt->{transactions} }), 17, "$f->[1] (num tx)");
    is(DateTime->compare($stmt->{transactions}[0]{date},
                         DateTime->new(year=>2009, month=>9, day=>15)),
       0, "$f->[1] (tx0 date)");
    is($stmt->{transactions}[0]{branch}, "0000", "$f->[1] (tx0 branch)");
    is($stmt->{transactions}[0]{amount}, -1000000, "$f->[1] (tx0 amount)");
    is($stmt->{transactions}[0]{balance}, 12023039.77, "$f->[1] (tx0 balance)");
    is($stmt->{transactions}[0]{is_pending}, 0, "$f->[1] (tx0 is_pending)");
    is($stmt->{transactions}[0]{seq}, 1, "$f->[1] (tx0 seq)");

    is($stmt->{transactions}[5]{amount}, 500000, "$f->[1] (credit)");

    is($stmt->{transactions}[2]{seq}, 3, "$f->[1] (seq 1)");
    is($stmt->{transactions}[3]{seq}, 1, "$f->[1] (seq 2)");
}

for my $f (
    ["stmt2.txt", "bisnis, txt"],) {
    my ($status, $error, $stmt) = $ibank->parse_statement(scalar read_file("$Bin/data/$f->[0]"));
    #print "status=$status, error=$error\n";

    # metadata
    is($stmt->{account}, "1234567890", "$f->[1] (account)");
    is($stmt->{account_holder}, "MAJU MUNDUR PT", "$f->[1] (account_holder)");
    is(DateTime->compare($stmt->{start_date},
                         DateTime->new(year=>2009, month=>8, day=>11)),
       0, "$f->[1] (start_date)");
    is(DateTime->compare($stmt->{end_date},
                         DateTime->new(year=>2009, month=>8, day=>11)),
       0, "$f->[1] (end_date)");
    is($stmt->{currency}, "IDR", "$f->[1] (currency)");

    # transactions
    is(scalar(@{ $stmt->{transactions} }), 3, "$f->[1] (num tx)");
    is(DateTime->compare($stmt->{transactions}[0]{date},
                         DateTime->new(year=>2009, month=>8, day=>11)),
       0, "$f->[1] (tx0 date)");
    is($stmt->{transactions}[0]{branch}, "0065", "$f->[1] (tx0 branch)");
    is($stmt->{transactions}[0]{amount}, 239850, "$f->[1] (tx0 amount)");
    is($stmt->{transactions}[0]{balance}, 4802989.39, "$f->[1] (tx0 balance)");
    is($stmt->{transactions}[0]{is_pending}, 0, "$f->[1] (tx0 is_pending)");
    is($stmt->{transactions}[0]{seq}, 1, "$f->[1] (tx0 seq)");

    is($stmt->{transactions}[2]{amount}, -65137, "$f->[1] (debit)");

    is($stmt->{transactions}[1]{seq}, 2, "$f->[1] (seq 1)");
    is($stmt->{transactions}[2]{seq}, 3, "$f->[1] (seq 2)");
}
