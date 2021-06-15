#!perl
use warnings;
use strict;
use feature 'state';
use List::Util qw(min);
use File::Basename;
use lib dirname(__FILE__);
use lib dirname(__FILE__) . "/lib";
use Gnu::ArgParse;
use Gnu::SimpleDB;
use Gnu::Template  qw(Template Usage);
use Gnu::DateTime  qw(DBDateToDateTimeObject NowToDateTimeObject);
use Gnu::DebugUtil qw(DumpRef);

my $STATE;

MAIN:
   $| = 1;
   ArgBuild("*^env= *^state= *^standard *^advance *^budget *^group *^unbill *^force *^help *^debug");
   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIs();

   GetAccounts();
   print "Done.\n";
   exit(0);


sub GetAccounts
   {
   my $env   = ArgGet("env") || "int";
   my $state = ArgGet("state") || "GA";
   my $count = ArgGet();
   my @accounts = map {GetAccount($env, $state)} (1..$count);
   (map {Unbill($env, $state, $_)} @accounts) if ArgIs("unbill");

   print "\nAccounts\n-----------\n";
   map {print "$_\n"} @accounts;
   }

sub GetAccount
   {
   my ($env, $state) = @_;

   return GetAdvanceAccount($env, $state) if ArgIs("advance");
   return GetBudgetAccount ($env, $state) if ArgIs("budget");
   return GetGroupAccount  ($env, $state) if ArgIs("group");
   return GetStdAccount    ($env, $state);
   }

sub GetStdAccount
   {
   my ($env, $state) = @_;

   print "getting $state standard account on $env...\n";
   my $cmd = 'curl -X GET "https://infrastructure-testdata.'. $env .'.gainesville.infiniteenergy.com/accounts?State=' . $state . '&Status=Active&IsVeteran=false&DueDate=Any" -H "accept: application/json"';
   Debug("CMD: ", $cmd);
   my $result = `$cmd 2>nul`;
   my ($acct) = $result =~ /"accountNumber":"(\d+)"/i;
   return $acct;
   }

sub GetAdvanceAccount
   {
   my ($env, $state) = @_;

   print "getting a $state InfiniteAdvance account on $env...\n";
   my $cmd = 'curl -X GET "https://infrastructure-testdata.'. $env .'.gainesville.infiniteenergy.com/accounts?State=' . $state . '&Status=Active&IsVeteran=false&DueDate=Any&IsInfiniteAdvance=true" -H "accept: application/json"';
   my $result = `$cmd 2>nul`;
   my ($acct) = $result =~ /"accountNumber":"(\d+)"/i;
   return $acct;
   }

sub GetBudgetAccount
   {
   my ($env, $state) = @_;

   state $rows;
   my $samplesize = 500;

   print "getting a $state Budget account in $env...\n";
   if (!$rows)
      {
      my $sql = " select top($samplesize) InvoiceNumber" .
                " from BudgetBillingInvoiceHistory ih" .
                " join serviceaddr sa on sa.ieinum = substring(ih.invoicenumber, 1, 10)" .
                " where SetId=128 and state='$state'" .
                " order by BillDate desc";
      Debug("SQL: ", $sql);
      $rows = FetchArray(GetDB($env, $state), $sql);
      }
   my $rowct = scalar @{$rows} || die "$state must not have Budget accounts";
   my $idx = int(min($rowct, rand($samplesize)));
   my $invNum = $rows->[$idx]->{InvoiceNumber};
   my ($acct) = $invNum =~ /^(\d+)\d{4}$/;
   return $acct;
   }

sub GetGroupAccount
   {
   my ($env, $state) = @_;

   state $rows;

   print "getting a $state Group account on $env...\n";
   if (!$rows)
      {
      my $sql = " SELECT distinct(GroupId)" .
                " FROM serviceaddr" .
                " WHERE status = 'Active'" .
                " AND GroupID is not null" .
                " AND DateAssigned > '2010-01-01'";

      Debug("SQL: ", $sql);
      $rows = FetchArray(GetDB($env, $state), $sql);
      }
   my $rowct = scalar @{$rows} || die "$state must not have group accounts";
   my $idx = int(rand($rowct));
   my $acct = $rows->[$idx]->{GroupId};

#print "acct=$acct\n";
#print DumpRef($rows->[$idx], "  ", 3);

   return $acct;
   }

sub Unbill
   {
   my ($env, $state, $acct) = @_;

   my ($invoiceNumber, $billDate) = GetLatestInvoice($env, $state, $acct);
   my $diff = NowToDateTimeObject()->epoch - DBDateToDateTimeObject($billDate, 'UTC')->epoch;
   return print "Last invoice is old.\n" if $diff/86400 > 30;
   UnbillInvoice($env, $invoiceNumber);
   }

sub GetLatestInvoice
   {
   my ($env, $state, $acct) = @_;

   my $sql = "SELECT top(1) InvoiceNumber, BillDate FROM InvoiceHistory" .
             " WHERE AccountNumber = '$acct' ORDER by BillDate desc";
   Debug("SQL: ", $sql);
   my $row = FetchRow(GetDB($env, $state), $sql);
   return ($row->{InvoiceNumber}, $row->{BillDate});
   }


# use curl and the shell
#
sub UnbillInvoice
   {
   my ($env, $invoiceNumber) = @_;

   my $username = "clfitzgerald-util";
   my $force = ArgIs("force") ? "true" : "false";
   my $baseurl = 'https://billing-invoice.' .$env. '.gainesville.infiniteenergy.com/invoices';
   my $queryparams = '?username=' .$username. '&forceUnbillPrintedInvoices=' .$force. '&batchSize=300';
   my $curlopts = '-H "accept: text/plain" -H "Content-Type: application/json-patch+json" ';
   my $cmd = 'curl -X DELETE "' .$baseurl . $queryparams. '" ' .$curlopts . ' -d "[ \"' .$invoiceNumber. '\"]"';

   print "unbilling invoice $invoiceNumber from $env...\n";
   Debug($cmd);
   my $result = `$cmd`;
   print "result = $result\n";
   }


sub GetDB
   {
   my ($env, $state) = @_;
   state $db;

   return $db if $db;
   my $server = $env =~ /preprod/ ? "test-babyadept" :
                $env =~ /prod/    ? "babyadept"      :
                                    "adepttrunk"     ;
   my $dbname = $state =~ /GA/i ? "Phase1" : "NY";

   $db = ConnectMSSQL($server, $dbname) or die "Can't connect to DB Server on $server";
   ExecSQL($db, "use $dbname") or die "Can't switch to DB $dbname";
   return $db;
   }

sub Debug
   {
   print @_, "\n" if ArgIs("debug");
   }

__DATA__

[usage]
GetAccounts.pl  -  Find some accounts

USAGE: GetAccounts.pl [options] number-to-get

WHERE: [options] are one or more of:
   -env=preprod . Specify env (int/preprod/prod, default=int)
   -state=GA  ... Specify the state (GA|FL|TX. default=GA)
   -standard .... Get standard accounts (the default)
   -advance ..... Get infinite advance accounts
   -budget ...... Get budget accounts
   -group ....... Get group accounts
   -unbill ...... Unbill last recent invoice for the accounts
   -force ....... Force unbill
   -help ........ This text

Examples:
   GetAccounts -unbill 10
   GetAccounts -state=FL -unbill -force -budget 5
   GetAccounts -env=preprod -state=TX -group 20
   GetAccounts -budget 5
