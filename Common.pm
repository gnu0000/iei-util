#
# Common.pm - common methods for the invoice utils
#
#
# ArgBuild("*^server= *^db= *^all *^allrecent *^recent *^date= *^test= *^text *^html *^showdates *^debug *^help ?");
#
# *^server= *^database= *^all *^allrecent *^recent *^date= *^showdates *^help ?
# *^server= *^database= *^all *^allrecent *^recent *^date= 

package Common;
require Exporter;
use strict;
use warnings;
use Gnu::ArgParse;
use Gnu::SimpleDB;

our $VERSION   = 1.0;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(MSConnect SourceSQL ShowDates Log);


# ArgIs use: server, database, (or none)
#
sub MSConnect
   {
   my ($server, $database) = @_;

   $server   ||= ArgGet("server"  ) || "adepttrunk"; #" test-babyadept";
   $database ||= ArgGet("database") || "Adept";

   my $db = ConnectMSSQL($server, $database) or die "Can't connect to MSSQL DB Server $server, DB $database";
   return $db;
   }


# ArgIs use: all, allrecent, recent, date, (or none)
#
sub SourceSQL
   {
   my ($db) = @_;

   if (ArgIs("all"))
      {
      Log("Fetching all InvoiceXML records...");
      return " SELECT *" .
             " FROM InvoiceXML" .
             " ORDER BY InvoiceNumber";
      }
   if (ArgIs("allrecent"))
      {
      Log("Fetching most recent record for all available invoices...");
      return " SELECT count(invoicexml.Id) FROM ( " .
             "    SELECT InvoiceNumber, MAX(GenDate) AS gendate " .
             "    FROM invoicexml " .
             "    GROUP BY InvoiceNumber " .
             " ) AS lastorder " .
             " INNER JOIN invoicexml " .
             " ON    invoicexml.InvoiceNumber = lastorder.InvoiceNumber " .
             " AND   invoicexml.gendate = lastorder.gendate ";
      }

   my $genDate = ArgIs("date" ) ? ArgGet("date" ) :
                 ArgIs("since") ? ArgGet("since") :
                                   GetLastDate($db);
   my $cmp = ArgIs("since") ? ">=" : "=";

   Log("Fetching InvoiceXML records with BillDate $genDate...");
   return " SELECT *" .
          " FROM InvoiceXML" .
          " WHERE GenDate $cmp '$genDate'" .
          " ORDER BY InvoiceNumber";
   }

sub ShowDates
   {
   my ($show_src, $show_dest) = @_;

   my $sql = "select GenDate as gd, count(*) as ct from InvoiceXML group by GenDate order by GenDate";

   if ($show_dest)
      {
      my $destdb = Connect("samples") or die "Can't connect to Local DB Server";
      my $migratedDates = FetchArray($destdb, $sql);
      print "Generated dates of invoices migrated to local DB:\n";
      map {print "  " . _dt($_->{gd}) . "  (".$_->{ct}.")\n"} @{$migratedDates};
      print "\n";
      }

   if ($show_src)
      {
      my $sourcedb = MSConnect();
      my $availableDates = FetchArray($sourcedb, $sql);
      print "Invoice generated dates available:\n";
      map {print "  " . _dt($_->{gd}) . "  (".$_->{ct}.")\n"} @{$availableDates};
      print "\n";
      }
   exit(0);
   }

sub GetLastDate
   {
   my ($db) = @_;
   return FetchColumn($db, "select max(distinct(GenDate)) from InvoiceXML");
   }

sub _dt 
   {
   my ($datetime) = @_;

   my ($dt) = split(" ", $datetime);
   return $dt;
   }

# $loglevel: 
#    0 - errors only
#    1 - above + normal output <- default
#    2 - above + wordy output
#    3 - above + debug
#
sub Log
   {
   my ($msg, $msglevel) = @_;

   $msglevel = 1 unless defined $msglevel;
   my $loglevel = ArgIs("loglevel") ? ArgGet("loglevel") : 1;
   return if $msglevel > $loglevel or ArgIs("quiet");

   print "$msg\n" unless ArgIs("html");
   }

1;
