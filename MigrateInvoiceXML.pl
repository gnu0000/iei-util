#!perl
use warnings;
use strict;
use POSIX       qw(strftime);
use XML::Simple qw(XMLin XMLout);
use File::Basename;
use lib dirname(__FILE__);
use lib dirname(__FILE__) . "/lib";
use Gnu::SimpleDB;
use Gnu::FileUtil qw(SlurpFile SpillFile);
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;
use Gnu::DebugUtil qw(DumpHash DumpRef);
use Common qw(MSConnect SourceSQL ShowDates Log);

my $SAMPLE_DIR = 'c:\Apache\htdocs\invoices\samples';

MAIN:
   $| = 1;
   ArgBuild("*^db *^server= *^database= " .
            "*^all *^allrecent *^recent *^date= *^since= *^truncate *^clean= " .
            "*^removesamples *^matches= *^showdates *^test ^help");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIsAny("", "db", "truncate", "clean", "showdates");

   ShowDates(0,1) if ArgIs("showdates");
   Truncate ()    if ArgIs("truncate");
   Clean    ()    if ArgIs("clean");
   Migrate  ();
   print "Done.\n";
   exit(0);


sub Truncate
   {
   my $db = Connect("samples") or die "Can't connect to Local DB Server";
   Log("Truncating local invoice data...");
   ExecSQL($db, "truncate invoicexml");
   exit(0);
   }

sub Clean
   {
   my $db = Connect("samples") or die "Can't connect to Local DB Server";
   my $date = ArgGet("clean");
   Log("Removing local invoice data for invoices generated on $date...");
   ExecSQL($db, "delete from invoicexml where GenDate = ?", $date);

   RemoveSamples($date) if ArgIs("removesamples");
   exit(0);
   }

sub RemoveSamples
   {
   my ($date) = @_;

   my $dir = $SAMPLE_DIR;
   opendir(my $dh, $dir) or die ("\ncant open dir '$dir'!");
   my @all = readdir($dh);
   closedir($dh);
   foreach my $file (@all)
      {
      my $spec = "$dir\\$file";
      next unless -f $spec;
      my ($size,$mtime) = (stat($spec))[7,9];
      my $filedate      = strftime("%Y-%m-%d", localtime($mtime));

      next unless $filedate =~ /$date/i;
      print "deleting $spec\n";
      unlink($spec) or warn "could not delete $spec : $!\n";
      }
   }

sub Migrate
   {
   # ArgIs("db") ? MigrateFromDB() : MigrateFromFiles();
   MigrateFromFiles();
   }

########################### db ##############################################
#
#
#sub MigrateFromDB
#   {
#   my $sourcedb = MSConnect();
#   my $destdb = Connect("samples") or die "Can't connect to Local DB Server";
#
#   my $sourcesql = SourceSQL($sourcedb);
#   my $destsql = "INSERT INTO invoicexml " . 
#                 "(InvoiceNumber, IE_XML, HM_XML, GenDate, BillDate, Market, BillType, Language, InvoiceAccountID, BalanceForward, CurrentCharges, TotalDue, Therms, ChargeCount, Arrangement)" .
#                 "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
#   my $sourcesth = $sourcedb->prepare ($sourcesql) or die "error 1";
#   my $deststh = $destdb->prepare ($destsql) or die "error 2";
#
#   print "Migrating from DB\n";
#   my $matches = LoadMatches();
#
#   $sourcesth->{'LongReadLen'} = 50000; # sqlserver specific requirement
#   $sourcesth->execute ();
#   my ($count, $skip) = (0, 0);
#   while (my $row = $sourcesth->fetchrow_hashref())
#      {
#      #print "$row->{InvoiceNumber}\n";
#      if ($matches && !$matches->{$row->{InvoiceNumber}})
#         {
#         print "-";
#         $skip++;
#         next;
#         }
#      $deststh->execute(RowData($row)) or die $deststh->errstr;
#      print ".";
#      $count++;
#      }
#   $deststh->finish();
#   $sourcesth->finish();
#
#   Log("\nMigrated $count records.");
#   Log("Skipped $skip records.") if $skip;
#   }
#
#sub RowData
#   {
#   my ($row) = @_;
#
#   my $doc = XMLin($row->{HM_XML});
#   my $ias = $doc->{Invoice}->{InvoiceAmountsInfo}->{InvoiceAmountSections};
#   my $balance_forward = $ias->{BalanceForward}->{Amount};
#   my $current_charges = $ias->{CurrentCharges}->{Amount};
#   my $total_amount_due = $ias->{TotalAmountDue}->{Amount};
#
#   my $usage = $doc->{Invoice}->{ConstituentAccounts}->{Account}->{Usage};
#   my $charge = $doc->{Invoice}->{ConstituentAccounts}->{Account}->{Charge};
#   my ($arrangement) = $doc->{Invoice}->{InvoiceAccountInfo}->{Account}->{Standing} =~ /PaymentArrangement/i;
#   my $chargecount = ref($charge) =~ /HASH/i  ? 1
#                   : ref($charge) =~ /ARRAY/i ? scalar @{$charge}
#                   : 0;
#
#   return (
#      $row->{InvoiceNumber}, 
#      $row->{IE_XML}, 
#      $row->{HM_XML}, 
#      $row->{GenDate}, 
#      $row->{BillDate}, 
#      $row->{Market}, 
#      $row->{BillType}, 
#      $row->{Language}, 
#      $row->{InvoiceAccountID},
#      $balance_forward, 
#      $current_charges, 
#      $total_amount_due, 
#      $usage, 
#      $chargecount, 
#      $arrangement);
#   }
#
#sub What
#   {
#   my ($label, $var) = @_;
#
#   my $type;
#   $type = !(defined $var) ? "*null*" : ref($var);
#   print "what? $label is $type\n";
#   }
#
#sub LoadMatches
#   {
#   return undef unless ArgIs("matches");
#   print "Loading match files...\n";
#   my $matches = {};
#   foreach my $filespec (glob(ArgGet("matches")))
#      {
#      my ($invnum) = $filespec =~ /(\d+)\.pdf/;
#      $matches->{$invnum} = 1;
#      }
#   return $matches;
#   }


########################### file ############################################

sub MigrateFromFiles
   {
   my $destdb = Connect("samples") or die "Can't connect to Local DB Server";
   my $destsql = "INSERT INTO invoicexml " . 
                 "(InvoiceNumber, IE_XML, HM_XML, GenDate, BillDate, Market, BillType, Language, ComputerName, InvoiceAccountID, BalanceForward, CurrentCharges, TotalDue, Therms, ChargeCount, Arrangement)" .
                 "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
   my $deststh = $destdb->prepare ($destsql) or die "error 2";

   print "Migrating from Files\n";

   my $count = 0;
   for (my $i=0; $i<ArgIs(); $i++)
      {
      map {$count += MigrateFile($deststh, $_)} (glob(ArgGet(undef, $i)));
      }
   $deststh->finish();
   print "\nMigrated $count invoices.\n";
   }

sub MigrateFile
   {
   my ($deststh, $filename) = @_;                                                                           

   my $xml = SlurpFile($filename);
   $xml =~ s/\x{00a2}/c/mg;
   $xml =~ s/\r//mg;
   $xml =~ s/([\x00-\x09]+)|([\x0B-\x1F]+)//mg;
   $xml =~ s/^/  /mg;
   $xml =~ s/[^[:print:]]+//g;

   # support bundles as well as individual invoices
   my $count = 0;
   while($xml =~ /(<InvoiceDocument>.*?<\/InvoiceDocument>)/sg)
      {
      my $row = XmlData($1);
      ($deststh->execute(@{$row}) or die $deststh->errstr) unless ArgIs("test");
      $count++;
      print ".";
      }
   return $count;
   }

sub XmlData
   {
   my ($xml) = @_;

   my $doc = XMLin($xml);
   my $ias = $doc->{Invoice}->{InvoiceAmountsInfo}->{InvoiceAmountSections};
   my $accounts = $doc->{Invoice}->{ConstituentAccounts}->{Account};
   my $account = ref($accounts) =~ /HASH/i ? $accounts : @{$accounts}[0];
   my $charges = $account->{Charge};
   my $charge = ref($charges) =~ /HASH/i ? $charges : ref($charges) =~ /ARRAY/i ? @{$charges}[0] : {};
   my $gendate = PrepDate($doc->{DocumentInfo}->{DocumentGeneratedDate});
   my $billdate = PrepDate($doc->{Invoice}->{InvoiceInfo}->{InvoiceDetails}->{BillDate});
   my $chargecount = ref($charges) =~ /HASH/i ? 1 : ref($charge) =~ /ARRAY/i ? scalar @{$charge} : 0;
   my ($arrangement) = $doc->{Invoice}->{InvoiceAccountInfo}->{Account}->{Standing} =~ /PaymentArrangement/i;
   my ($market) = $doc->{DocumentInfo}->{DocumentLanguageMarket} =~ /\-(.*)$/;
   my $computername = GetComputerName($doc);
   my $ammtfield = $doc->{DocumentInfo}->{DocumentTemplate} =~ /Budget/i ? "LevelAmount" : "Amount";

   return 
      [
      $doc->{Invoice}->{InvoiceInfo}->{InvoiceDetails}->{InvoiceNumber}, #  InvoiceNumber
      "",                                                                #  IE_XML
      $xml,                                                              #  HM_XML
      $gendate,                                                          #  GenDate
      $billdate,                                                         #  BillDate
      $market,                                                           #  Market
      $doc->{DocumentInfo}->{DocumentTemplate},                          #  BillType
      $doc->{DocumentInfo}->{DocumentLanguage},                          #  Language
      $computername,                                                     #  ComputerName
      $doc->{Invoice}->{InvoiceAccountInfo}->{Account}->{AccountNumber}, #  InvoiceAccountID
      $ias->{BalanceForward}->{$ammtfield},                              #  BalanceForward
      $ias->{CurrentCharges}->{$ammtfield},                              #  CurrentCharges
      $ias->{TotalAmountDue}->{$ammtfield},                              #  TotalDue
      $account->{Usage},                                                 #  Therms
      $chargecount,                                                      #  ChargeCount
      $arrangement                                                       #  Arrangement
      ]
   }

sub PrepDate
   {
   my ($date) = @_;

   my ($m, $d, $y) = $date =~ /^(\d+)\/(\d+)\/(\d+)$/;
   $y += 2000 if $y < 2000;
   return "$y-$m-$d";
   }

sub GetComputerName
   {
   my ($doc) = @_;

   my $messages = $doc->{Invoice}->{InvoiceMessages}->{Message};
   foreach my $message (@{$messages})
      {
      return $message->{Description} if $message->{Type} =~ /ComputerName/i;
      }
   return "";
   }

__DATA__

[usage]
MigrateInvoiceXML.pl  -  Migrate invoice files to a local db, or show migrated info

USAGE:  MigrateInvoiceXML.pl [options] xmlfiles

NOTE: This Utility can get load both individual invoice and bundle xmls

WHERE:
   xmlfiles ......... One or more files to load. Wildcards ok

   [options] are 0 or more of:
   -truncate ........ Truncate all invoices from the LOCAL database
   -clean=date ...... remove the LOCAL invoices generated on this date
   -showdates ....... Show what generated dates are available to migrate
   -help ............ This help
   -matches=files.... Filter records to ones that go with the files in this dir

EXAMPLES:
   MigrateInvoiceXML.pl -showdates
   MigrateInvoiceXML.pl -clean=2020-04-04
   MigrateInvoiceXML.pl -truncate
   MigrateInvoiceXML.pl xml\*.xml

[old-usage]
MigrateInvoiceXML.pl  -  Migrate test invoices to a local db

USAGE:  MigrateInvoiceXML.pl [options] -db
   -or-
USAGE:  MigrateInvoiceXML.pl [options] xmlfiles

This Utility can get invoices from either the database or local files
This Utility can get load both individual invoice and bundle xmls

***Database migration is deprecated***
Database specific options:
   -db .............. Use the adept database (default is files)
   -server=name ..... Identify MSSQL Server (test-babyadept)
   -all ............. Migrate all data
   -allrecent ....... Migrate newest invoice record from every available invoice.
   -recent .......... Migrate data from the most recent date
   -date=date ....... Migrate invoices generated on this date
   -since=date ...... Migrate invoices generated on this dateor newer
   -truncate ........ Truncate all invoices from the LOCAL database
   -clean=date ...... remove the LOCAL invoices for this date
   -showdates ....... Show what generated dates are available to migrate
   -help ............ This help

Local file specific options:
   -matches=files.... Filter records to ones that go with the files in this dir
   xmlfiles ......... One or more files to scan. Wildcards ok

EXAMPLES:
   MigrateInvoiceXML.pl -db -recent
   MigrateInvoiceXML.pl -db -date=2019-10-05
   MigrateInvoiceXML.pl -db -all
   MigrateInvoiceXML.pl -showdates
   MigrateInvoiceXML.pl -truncate
   MigrateInvoiceXML.pl -server=test-babyadept -showdates
   MigrateInvoiceXML.pl -db -recent -matches=xml\*.
   MigrateInvoiceXML.pl -db -allrecent -matches:uat\11-26\pdf\*
   MigrateInvoiceXML.pl xml\*.xml
[fini]
