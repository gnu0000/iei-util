#!perl
#
# unbill.pl  -  Unbill last Invoice for a given account
# todo: support invoice# as well as account#
# Craig fitzgerald
#

use warnings;
use strict;
use File::Basename;
use lib dirname(__FILE__);
use lib dirname(__FILE__) . "/lib";
use Gnu::SimpleDB;
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;
use Gnu::DateTime qw(DBDateToDisplayDate DBDateToDateTimeObject NowToDateTimeObject);

MAIN:
   $| = 1;
   ArgBuild("*db= *^state= *^env= *^force *^check *^recent *^show *^debug *^help ?");
   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();

   Usage() if ArgIs("help") || ArgIs("?") || !ArgIs();

   Unbill(ArgGet());
   print "Done.\n";
   exit(0);

sub Unbill
   {
   my ($acct) = @_;

   my ($invoiceNumber, $billDate) = GetLatestInvoice($acct);
   return print "no previous invoice for $acct\n" if !$billDate;

   my $isOld = (NowToDateTimeObject()->epoch - DBDateToDateTimeObject($billDate, 'UTC')->epoch)/86400 > 30;

   print $isOld ? "old invoice: $invoiceNumber\n" : "$invoiceNumber\n";
   exit(0) if ArgIs("show") || ($isOld && ArgIs("recent"));
   UnbillInvoice($invoiceNumber);
   }

sub GetLatestInvoice
   {
   my ($acct) = @_;

   my $state = ArgIs("state") ? ArgGet("state") : "GA";
   my $dbname = $state =~ /GA/i ? "Phase1" : "NY";
   $dbname = ArgGet("db") if ArgIs("db");

   my $db = ConnectMSSQL("Phase1") or die "Can't connect to DB Server";
   Debug("use $dbname");
   ExecSQL($db, "use $dbname") or die "Can't switch to DB $dbname";

   my $sql = 
      "SELECT top(1) InvoiceNumber, BillDate" .
      " FROM InvoiceHistory" .
      " where AccountNumber = '$acct'" .
      " order by BillDate desc";
   
   Debug($sql);
   my $row = FetchRow($db, $sql);

   return ($row->{InvoiceNumber}, $row->{BillDate});
   }

# use LWP - nope, we're using windows auth
#
# sub UnbillInvoice
#    {
#    my ($invoiceNumber) = @_;
# 
#    my $browser = LWP::UserAgent->new;
#    my $url = 'https://billing-invoice.int.gainesville.infiniteenergy.com/invoices?username=fred&forceUnbillPrintedInvoices=true&batchSize=10';
#    my @headers = ("accept" => "text/plain", "Content-Type" => "application/json-patch+json");
# 
#    my $req = HTTP::Request->new(DELETE => $url);
#    $req->content("[ \"123123123\"]");
#    my $response = $browser->request($req, @headers);
# 
#    print $response->is_success ? "success\n" : "fail\n";
#    print "err: $response->status_line , $!\n";
#    print "content:" . $response->content;
#    }

# use curl and the shell
#
sub UnbillInvoice
   {
   my ($invoiceNumber) = @_;

   my $env = ArgGet("env") || "int";

   print "unbilling invoice $invoiceNumber from $env...\n";
   my $username = "clfitzgerald-util";
   my $force = ArgIs("force") ? "true" : "false";
   my $baseurl = 'https://billing-invoice.' .$env. '.gainesville.infiniteenergy.com/invoices';
   my $queryparams  = '?username=' .$username. '&forceUnbillPrintedInvoices=' .$force. '&batchSize=300';
   my $curlopts = '-H "accept: text/plain" -H "Content-Type: application/json-patch+json" ';
   my $cmd = 'curl -X DELETE "' .$baseurl . $queryparams. '" ' .$curlopts . ' -d "[ \"' .$invoiceNumber. '\"]"';

   Debug($cmd);
   my $result = `$cmd`;
   print "result = $result\n";
   }

sub Debug
   {
   my ($msg) = @_;

   return unless ArgIs("debug");
   print "$msg\n";
   }

__DATA__

[usage]
unbill.pl  -  Unbill last Invoice for a given account

USAGE: unbill.pl [options] acct#

WHERE: [options] are one or more of:
   -state=st  ... Specify the State (GA)
   -env=str ......Specify the environment int/preprod/prod. default (int)
   -db=name  .... Specify the database (Phase1)
   -force ....... Force unbill (ignore wasprinted flag)
   -recent ...... Only unbill if last bill was <30 days ago
   -show ........ Show the last invoice for the account (dont unbill)
   -help ........ This text

Onle the -state= or the -db= needs to be specified. If neither,
the account is assumed to be for GA

EXAMPLES:
   unbill.pl 5363780956
   unbill.pl -state=FL 1234567890
   unbill.pl -db=Phase1 5363780956
   unbill.pl -db=NY 8460141725
   unbill.pl -env=preprod -db=NY 8460141725
