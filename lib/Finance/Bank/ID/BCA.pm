package Finance::Bank::ID::BCA;
our $VERSION = '0.04';


# ABSTRACT: Check your BCA accounts from Perl


use Moose;
use DateTime;

extends 'Finance::Bank::ID::Base';


has _variant => (is => 'rw'); # bisnis or perorangan



sub BUILD {
    my ($self, $args) = @_;

    $self->site("https://ibank.klikbca.com") unless $self->site;
}


sub login {
    my ($self) = @_;
    my $s = $self->site;

    return 1 if $self->logged_in;
    die "400 Username not supplied" unless $self->username;
    die "400 Password not supplied" unless $self->password;

    $self->logger->debug('Logging in ...');
    $self->_req(get => [$s]);
    $self->_req(submit_form => [
                                form_number => 1,
                                fields => {'value(user_id)'=>$self->username,
                                           'value(pswd)'=>$self->password,
                                           },
                                button => 'value(Submit)',
                                ],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ /var err='(.+?)'/ and return $1;
                    $mech->content =~ /=logout"/ and return;
                    "unknown login result page";
                }
                                );
    $self->logged_in(1);
    $self->_req(get => ["$s/authentication.do?value(actions)=welcome"]);
    #$self->_req(get => ["$s/nav_bar_indo/menu_nav.htm"]); # failed?
}


sub logout {
    my ($self) = @_;

    return 1 unless $self->logged_in;
    $self->logger->debug('Logging out ...');
    $self->_req(get => [$self->site . "/authentication.do?value(actions)=logout"]);
    $self->logged_in(0);
}

sub _menu {
    my ($self) = @_;
    my $s = $self->site;
    $self->_req(get => ["$s/nav_bar_indo/account_information_menu.htm"]);
}


sub list_accounts {
    my ($self) = @_;
    $self->login;
    $self->logger->info("Listing accounts");
    map { $_->{account} } $self->_check_balances;
}

sub _check_balances {
    my ($self) = @_;
    my $s = $self->site;

    my $re = qr!
<tr>\s*
  <td[^>]+>\s*<div[^>]+>\s*<font[^>]+>\s*(\d+)\s*</font>\s*</div>\s*</td>\s*
  <td[^>]+>\s*<div[^>]+>\s*<font[^>]+>\s*([^<]*?)\s*</font>\s*</div>\s*</td>\s*
  <td[^>]+>\s*<div[^>]+>\s*<font[^>]+>\s*([A-Z]+)\s*</font>\s*</div>\s*</td>\s*
  <td[^>]+>\s*<div[^>]+>\s*<font[^>]+>\s*([0-9,.]+)\.(\d\d)\s*</font>\s*</div>\s*</td>
!x;

    $self->login;
    $self->_menu;
    $self->_req(post => ["$s/balanceinquiry.do"],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ $re or
                        return "can't find balances, maybe page layout changed?";
                    '';
                }
    );

    my @res;
    my $content = $self->mech->content;
    while ($content =~ m/$re/og) {
        push @res, { account => $1,
                     account_type => $2,
                     currency => $3,
                     balance => $self->_stripD($4) + 0.01*$5,
                 };
    }
    @res;
}


sub check_balance {
    my ($self, $account) = @_;
    my @bals = $self->_check_balances;
    return unless @bals;
    return $bals[0]{balance} if !$account;
    for (@bals) {
        return $_->{balance} if $_->{account} eq $account;
    }
    return;
}


sub get_statement {
    my ($self, %args) = @_;
    my $s = $self->site;
    my $max_days = 31;

    $self->login;
    $self->_menu;
    $self->logger->info("Getting statement for ".
        ($args{account} ? "account `$args{account}'" : "default account")." ...");
    $self->_req(post => ["$s/accountstmt.do?value(actions)=acct_stmt"],
                sub {
                    my ($mech) = @_;
                    $mech->content =~ /<form/i or
                        return "no form found, maybe we got logged out?";
                    '';
                });

    my $form = $self->mech->form_number(1);

    # in the site this is done by javascript onSubmit(), so we emulate it here
    $form->action("$s/accountstmt.do?value(actions)=acctstmtview");

    # in the case of the current date being a saturday/sunday/holiday, end
    # date will be forwarded 1 or more days from the current date by the site,
    # so we need to know end date and optionally forward start date when needed,
    # to avoid total number of days being > 31.

    my $today = DateTime->today;
    my $max_dt = DateTime->new(day   => $form->value("value(endDt)"),
                               month => $form->value("value(endMt)"),
                               year  => $form->value("value(endYr)"));
    my $cmp = DateTime->compare($today, $max_dt);
    my $delta_days = $cmp * $today->subtract_datetime($max_dt, $today)->days;
    if ($delta_days > 0) {
        $self->logger->warn("Something weird is going on, end date is being ".
                            "set less than today's date by the site (".
                            $self->_fmtdate($max_dt)."). ".
                            "Please check your computer's date setting. ".
                            "Continuing anyway.");
    }
    my $min_dt = $max_dt->clone->subtract(days => ($max_days-1));

    my $end_dt = $args{end_date} || $max_dt;
    my $start_dt = $args{start_date} ||
        $end_dt->clone->subtract(days => (($args{days} || $max_days)-1));
    if (DateTime->compare($start_dt, $min_dt) == -1) {
        $self->logger->warn("Start date ".$self->_fmtdate($start_dt)." is less than ".
                            "minimum date ".$self->_fmtdate($min_dt).". Setting to ".
                            "minimum date instead.");
        $start_dt = $min_dt;
    }
    if (DateTime->compare($start_dt, $max_dt) == 1) {
        $self->logger->warn("Start date ".$self->_fmtdate($start_dt)." is greater than ".
                            "maximum date ".$self->_fmtdate($max_dt).". Setting to ".
                            "maximum date instead.");
        $start_dt = $max_dt;
    }
    if (DateTime->compare($end_dt, $min_dt) == -1) {
        $self->logger->warn("End date ".$self->_fmtdate($end_dt)." is less than ".
                            "minimum date ".$self->_fmtdate($min_dt).". Setting to ".
                            "minimum date instead.");
        $end_dt = $min_dt;
    }
    if (DateTime->compare($end_dt, $max_dt) == 1) {
        $self->logger->warn("End date ".$self->_fmtdate($end_dt)." is greater than ".
                            "maximum date ".$self->_fmtdate($max_dt).". Setting to ".
                            "maximum date instead.");
        $end_dt = $max_dt;
    }
    if (DateTime->compare($start_dt, $end_dt) == 1) {
        $self->logger->warn("Start date ".$self->_fmtdate($start_dt)." is greater than ".
                            "end date ".$self->_fmtdate($end_dt).". Setting to ".
                            "end date instead.");
        $start_dt = $end_dt;
    }

    my $select = $form->find_input("value(D1)");
    my $d1 = $select->value;
    if ($args{account}) {
        my @d1 = $select->possible_values;
        my @accts = $select->value_names;
        for (0..$#accts) {
            if ($args{account} eq $accts[$_]) {
                $d1 = $d1[$_];
                last;
            }
        }
    }

    $self->_req(submit_form => [
                                form_number => 1,
                                fields => {
                                    "value(D1)" => $d1,
                                    "value(startDt)" => $start_dt->day,
                                    "value(startMt)" => $start_dt->month,
                                    "value(startYr)" => $start_dt->year,
                                    "value(endDt)" => $end_dt->day,
                                    "value(endMt)" => $end_dt->month,
                                    "value(endYr)" => $end_dt->year,
                                          },
                                ],
                sub {
                    my ($mech) = @_;
                    ''; # XXX check for error
                });
    my ($res, $h, $stmt) = $self->parse_statement($self->mech->content);
    return if $res != 200;
    $stmt;
}


sub _ps_detect {
    my ($self, $page) = @_;
    unless ($page =~ /(?:^\s*|&nbsp;)(?:INFORMASI REKENING - MUTASI REKENING|ACCOUNT INFORMATION - ACCOUNT STATEMENT)/mi) {
        return "No KlikBCA statement page signature found";
    }
    $self->_variant($page =~ /^(?:Kode Mata Uang|Currency)/m ? 'bisnis' : 'perorangan');
    "";
}

sub _ps_get_metadata {
    my ($self, $page, $stmt) = @_;

    unless ($page =~ /\s*(?:(?:Nomor|No\.) [Rr]ekening|Account Number)\s*(?:<[^>]+>\s*)*[:\t]\s*(?:<[^>]+>\s*)*([\d-]+)/m) {
        return "can't get account number";
    }
    $stmt->{account} = $self->_stripD($1);
    $stmt->{account} =~ s/\D+//g;

    my $adv1 = "probably the statement format changed, or input incomplete";

    unless ($page =~ m!(?:^\s*|>)(?:Periode|Period)\s*(?:<[^>]+>\s*)*[:\t]\s*(?:<[^>]+>\s*)*(\d\d)/(\d\d)/(\d\d\d\d) - (\d\d)/(\d\d)/(\d\d\d\d)!m) {
        return "can't get statement period, $adv1";
    }
    $stmt->{start_date} = DateTime->new(day=>$1, month=>$2, year=>$3);
    $stmt->{end_date}   = DateTime->new(day=>$4, month=>$5, year=>$6);

    unless ($page =~ /(?:^|>)(?:(?:Kode )?Mata Uang|Currency)\s*(?:<[^>]+>\s*)*[:\t]\s*(?:<[^>]+>\s*)*(Rp|[A-Z]+)/m) {
        return "can't get currency, $adv1";
    }
    $stmt->{currency} = ($1 eq 'Rp' ? 'IDR' : $1);

    unless ($page =~ /(?:^|>)(?:Nama|Name)\s*(?:<[^>]+>\s*)*[:\t]\s*(?:<[^>]+>\s*)*([^<\015\012]+)/m) {
        return "can't get account holder, $adv1";
    }
    $stmt->{account_holder} = $1;

    unless ($page =~ /(?:^|>)(?:Mutasi Kredit|Total Credits)\s*(?:<[^>]+>\s*)*[:\t]\s*(?:<[^>]+>\s*)*([0-9,.]+)\.(\d\d)(?:\s*\t\s*(\d+))?/m) {
        return "can't get total credit, $adv1";
    }
    $stmt->{_total_credit_in_stmt}  = $self->_stripD($1) + 0.01*$2;
    $stmt->{_num_credit_tx_in_stmt} = $3 if $3;

    unless ($page =~ /(?:^|>)(?:Mutasi Debet|Total Debits)\s*(?:<[^>]+>\s*)*[:\t]\s*(?:<[^>]+>\s*)*([0-9,.]+)\.(\d\d)(?:\s*\t\s*(\d+))?/m) {
        return "can't get total credit, $adv1";
    }
    $stmt->{_total_debit_in_stmt}  = $self->_stripD($1) + 0.01*$2;
    $stmt->{_num_debit_tx_in_stmt} = $3 if $3;
    "";
}

sub _ps_get_transactions {
    my ($self, $page, $stmt) = @_;

    my @e;
    # text version
    while ($page =~ m!^
(\d\d/\d\d|\s?PEND|\s?NEXT)
  (?:\s*\t\s*|\n)
((?:[^\t]|\n)*?)
  (?:\s*\t\s*|\n)
(\d{4})
  (?:\s*\t\s*|\n)
([0-9,]+)\.(\d\d)
  (?:\s*\t?\s*|\n)
(CR|DB)
  (?:\s*\t\s*|\n)
([0-9,]+)\.(\d\d)
    !mxg) {
        push @e, {date=>$1, desc=>$2, br=>$3, amt=>$4, amtf=>$5, crdb=>$6, bal=>$7, balf=>$8};
    }
    if (!@e) {
        # HTML version
        while ($page =~ m!^
<tr>\s*
  <td[^>]+>(?:<[^>]+>\s*)*  (\d\d/\d\d|\s?PEND|\s?NEXT)  (?:<[^>]+>\s*)*</td>\s*
  <td[^>]+>(?:<[^>]+>\s*)*  ((?:[^\t]|\n)*?)             (?:<[^>]+>\s*)*</td>\s*
  <td[^>]+>(?:<[^>]+>\s*)*  (\d{4})                      (?:<[^>]+>\s*)*</td>\s*
  <td[^>]+>(?:<[^>]+>\s*)*  ([0-9,]+)\.(\d\d)            (?:<[^>]+>\s*)*</td>\s*
  <td[^>]+>(?:<[^>]+>\s*)*  (CR|DB)                      (?:<[^>]+>\s*)*</td>\s*
  <td[^>]+>(?:<[^>]+>\s*)*  ([0-9,]+)\.(\d\d)            (?:<[^>]+>\s*)*</td>\s*
</tr>!smxg) {
            push @e, {date=>$1, desc=>$2, br=>$3, amt=>$4, amtf=>$5, crdb=>$6, bal=>$7, balf=>$8};
        }
        for (@e) { $_->{desc} =~ s!<br ?/?>!\n!ig }
    }

    my @tx;
    my $last_date;
    my $seq;
    my $i = 0;
    for my $e (@e) {
        $i++;
        my $tx = {};
        #$tx->{stmt_start_date} = $stmt->{start_date};

        if ($e->{date} =~ /NEXT/) {
            $tx->{date} = $stmt->{end_date};
            $tx->{is_next} = 1;
        } elsif ($e->{date} =~ /PEND/) {
            $tx->{date} = $stmt->{end_date};
            $tx->{is_pending} = 1;
        } else {
            my ($day, $mon) = split m!/!, $e->{date};
            my $last_nonpend_date = DateTime->new(
                                                  year => ($mon < $stmt->{start_date}->month ?
                                                           $stmt->{end_date}->year :
                                                           $stmt->{start_date}->year),
                                                  month => $mon,
                                                  day => $day);
            $tx->{date} = $last_nonpend_date;
            $tx->{is_pending} = 0;
        }

        $tx->{description} = $e->{desc};

        $tx->{branch} = $e->{br};

        $tx->{amount}  = ($e->{crdb} =~ /CR/ ? 1 : -1) * ($self->_stripD($e->{amt}) + 0.01*$e->{amtf});
        $tx->{balance} = ($self->_stripD($e->{bal}) + 0.01*$e->{balf});

        if (!$last_date || DateTime->compare($last_date, $tx->{date})) {
            $seq = 1;
            $last_date = $tx->{date};
        } else {
            $seq++;
        }
        $tx->{seq} = $seq;

        if ($self->_variant eq 'perorangan' &&
            $tx->{date}->dow =~ /6|7/ &&
            $tx->{description} !~ /^(BIAYA ADM|BUNGA|CR KOREKSI BUNGA|PAJAK BUNGA)$/) {
            return "check failed in tx#$i: In KlikBCA Perorangan, all ".
                "transactions must not be in Sat/Sun except for Interest and ".
                "Admin Fee";
            # note: in Tahapan perorangan, BIAYA ADM is set on
            # Fridays, but for Tapres (?) on last day of the month
        }

        if ($self->_variant eq 'bisnis' &&
            $tx->{date}->dow =~ /6|7/ &&
            $tx->{description} !~ /^(BIAYA ADM|BUNGA|CR KOREKSI BUNGA|PAJAK BUNGA)$/) {
            return "check failed in tx#$i: In KlikBCA Bisnis, all ".
                "transactions must not be in Sat/Sun except for Interest and ".
                "Admin Fee";
            # note: in KlikBCA bisnis, BIAYA ADM is set on the last day of the
            # month, regardless of whether it's Sat/Sun or not
        }

        push @tx, $tx;
    }
    $stmt->{transactions} = \@tx;
    "";
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

__END__
=pod

=head1 NAME

Finance::Bank::ID::BCA - Check your BCA accounts from Perl

=head1 VERSION

version 0.04

=head1 SYNOPSIS

    use Finance::Bank::ID::BCA;

    # FBI::BCA uses Log4perl. the easiest way to show logs is with these 2 lines:
    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    my $ibank = Finance::Bank::ID::BCA->new(
        username => 'ABCDEFGH1234', # optional if you're only using parse_statement()
        password => '123456',       # idem
    );

    eval {
        $ibank->login(); # dies on error

        my @accts = $ibank->list_accounts();

        my $bal = $ibank->check_balance($acct); # $acct is optional

        my $stmt = $ibank->get_statement(
            account    => ..., # opt, default account will be used if not specified
            days       => 31,  # opt
            start_date => DateTime->new(year=>2009, month=>10, day=>6),
                               # opt, takes precedence over 'days'
            end_date   => DateTime->today, # opt, takes precedence over 'days'
        );

        print "Transactions: ";
        for my $tx (@{ $stmt->{transactions} }) {
            print "$tx->{date} $tx->{amount} $tx->{description}\n";
        }
    };

    # remember to call this, otherwise you will have trouble logging in again
    # for some time
    if ($ibank->logged_in) { $ibank->logout() }

    # utility routines
    my $stmt = $ibank->parse_statement($html_or_copy_pasted_text);

Also see the examples/ subdirectory in the distribution for a sample script using
this module.

=head1 DESCRIPTION

This module provide a rudimentary interface to the web-based online banking
interface of the Indonesian B<Bank Central Asia> (BCA) at
https://ibank.klikbca.com. You will need either L<Crypt::SSLeay> or
L<IO::Socket::SSL> installed for HTTPS support to work. L<WWW::Mechanize> is
required but you can supply your own mech-like object.

This module can only login to the retail/personal version of the site (KlikBCA
perorangan) and not the corporate/business version (KlikBCA bisnis) as the later
requires VPN and token input on login. But this module can parse statement page
from both versions.

Warning: This module is neither offical nor is it tested to be 100% save!
Because of the nature of web-robots, everything may break from one day to the
other when the underlying web interface changes.

=head1 WARNING

This warning is from Simon Cozens' C<Finance::Bank::LloydsTSB>, and seems just
as apt here.

This is code for B<online banking>, and that means B<your money>, and that means
B<BE CAREFUL>. You are encouraged, nay, expected, to audit the source of this
module yourself to reassure yourself that I am not doing anything untoward with
your banking data. This software is useful to me, but is provided under B<NO
GUARANTEE>, explicit or implied.

=head1 ERROR HANDLING AND DEBUGGING

Most methods die() when encountering errors, so you can use eval() to trap them.

This module uses Log::Log4perl, so you can see more debugging statements on
your screen, log files, etc.

Full response headers and bodies are dumped to a separate logger. See
documentation on C<new()> below and the sample script in examples/ subdirectory
in the distribution.

=head1 ATTRIBUTES

=head1 METHODS

=head2 new(%args)

Create a new instance. %args keys:

=over

=item * username

Optional if you are just using utility methods like C<parse_statement()> and not
C<login()> etc.

=item * password

Optional if you are just using utility methods like C<parse_statement()> and not
C<login()> etc.

=item * mech

Optional. A L<WWW::Mechanize>-like object. By default this module instantiate a
new WWW::Mechanize object to retrieve web pages, but if you want to use a
custom/different one, you are allowed to do so here. Use cases include: you want
to retry and increase timeout due to slow/unreliable network connection (using
L<WWW::Mechanize::Plugin::Retry>), you want to slow things down using
L<WWW::Mechanize::Sleepy>, you want to use IE engine using
L<Win32::IE::Mechanize>, etc.

=item * logger

Optional. You can supply a L<Log::Log4perl>-like logger object here. If not
specified, this module will use a default logger
(C<Log::Log4perl->get_logger()>).

=item * logger_dump

Optional. You can supply a L<Log::Log4perl>-like logger object here. This is
just like C<logger> but this module will log contents of response here
instead of to C<logger_dump> for debugging purposes. You can configure
Log4perl with something like L<Log::Dispatch::Dir> to save web pages more
conveniently as separate files. If unspecified, the default logger is used:
C<Log::Log4perl->get_logger()>.

Note that response contents are logged using the TRACE level.

=back

=head2 login()

Login to the net banking site. You actually do not have to do this explicitly as
login() is called by other methods like C<check_balance()> or
C<get_statement()>.

If login is successful, C<logged_in> will be set to true and subsequent calls to
C<login()> will become a no-op until C<logout()> is called.

Dies on failure.

=head2 logout()

Logout from the net banking site. You need to call this at the end of your
program, otherwise the site will prevent you from re-logging in for some time
(e.g. 10 minutes).

If logout is successful, C<logged_in> will be set to false and subsequent calls
to C<logout()> will become a no-op until C<login()> is called.

Dies on failure.

=head2 list_accounts()

Return an array containing all account numbers that are associated with the
current net banking login.

=head2 check_balance([$account])

Return balance for specified account, or the default account if C<$account> is
not specified.

=head2 get_statement(%args)

Get account statement. %args keys:

=over

=item * account

Optional. Select the account to get statement of. If not specified, will use the
already selected account.

=item * days

Optional. Number of days between 1 and 31. If days is 1, then start date and end
date will be the same. Default is 31.

=item * start_date

Optional. Default is end_date - days.

=item * end_date

Optional. Default is today (or some 1+ days from today if today is a
Saturday/Sunday/holiday, depending on the default value set by the site's form).

=back

=head2 parse_statement($html_or_text, %opts)

Given the HTML/copy-pasted text of the account statement results page, parse it
into structured data:

 $stmt = {
    start_date     => $start_dt, # a DateTime object
    end_date       => $end_dt,   # a DateTime object
    account_holder => STRING,
    account        => STRING,    # account number
    currency       => STRING,    # 3-digit currency code
    transactions   => [
        # first transaction
        {
          date        => $dt, # a DateTime object, book date ("tanggal pembukuan")
          seq         => INT, # a number >= 1 which marks the sequence of transactions for the day
          amount      => REAL, # a real number, positive means credit (deposit), negative means debit (withdrawal)
          description => STRING,
          is_pending  => BOOL,
          branch      => STRING, # a 4-digit branch/ATM code
          balance     => REAL,
        },
        # second transaction
        ...
    ]
 }

If parsing failed, will return undef.

In list context, this method will return HTTP-style response instead:

 ($status, $err_details, $stmt)

C<$status> is 200 if successful or some other 3-digit code if parsing failed.
C<$stmt> is the result (structure as above, or undef if parsing failed).

=head1 AUTHOR

  Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2009 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

