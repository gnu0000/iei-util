#!perl
#
# Craig fitzgerald
#

use warnings;
use strict;
use File::Basename;
use lib dirname(__FILE__);
use lib dirname(__FILE__) . "/lib";
use Gnu::SimpleDB;

MAIN:
   $| = 1;
   Test();
   #AltTest();
   print "Done.\n";

sub Test
   {
   print "\n---Test1---\n";
   my $db = ConnectMSSQL("adepttrunk", "Phase1") or die "Can't connect to DB Server";
   ExecSQL($db, "use DataRouter") or die "Can't switch to DB 'DataRouter'";
   my $rows = FetchArray($db, "SELECT * FROM ChargeDetailGroup");
   map {print "Title: $_->{Title}\n"} @{$rows};

   print "\n---Test2---\n";
   my $db2 = ConnectMSSQL("adepttrunk", "Phase1") or die "Can't connect to DB Server";
   ExecSQL($db2, "use DataRouter") or die "Can't switch to DB 'DataRouter'";
   $rows = FetchArray($db2, "SELECT * FROM ChargeDetailGroup");
   map {print "Title: $_->{Title}\n"} @{$rows};


   print "\n---Test3---\n";
   my $db3 = ConnectMSSQL("test-babyadept", "Phase1") or die "Can't connect to DB Server";
   ExecSQL($db3, "use DataRouter") or die "Can't switch to DB 'DataRouter'";
   $rows = FetchArray($db3, "SELECT * FROM ChargeDetailGroup");
   map {print "Title: $_->{Title}\n"} @{$rows};
   }


sub AltTest
   {
   my $db = ConnectMSSQL("adepttrunk", "Adept");
   my $rows = FetchArray($db, "SELECT * FROM InvoiceXml");
   print "InvoiceXml has " . scalar @{$rows} . " rows\n";

   my $rows2 = FetchArray($db, 
      "with cte as (select invoicenumber, max(id) as maxid from invoicexml group by invoicenumber)" .
      " select * from InvoiceXML ix join cte on cte.maxid = ix.Id order by ix.InvoiceNumber"
   );
   print "InvoiceXml query has " . scalar @{$rows2} . " rows\n";
   }