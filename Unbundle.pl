#!perl
#
# Unbundle.pl  -  Unbundle the xml bundle to individual invoice xmls
# Craig fitzgerald
#

use warnings;
use strict;
use feature 'state';
use XML::Simple qw(XMLin XMLout);
use File::Basename;
use lib dirname(__FILE__);
use lib dirname(__FILE__) . "/lib";
use Gnu::SimpleDB;
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;
use Gnu::FileUtil qw(SlurpFile SpillFile);
use Common qw(Log);

my $templatecounts = {};

MAIN:
   $| = 1;
   ArgBuild("*^out= *^count *^type= *^nottype= ^help ^quiet");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIs("");
   UnBundle();
   exit(0);


sub UnBundle
   {
   my $count = 0;
   for (my $i=0; $i<ArgIs(); $i++)
      {
      map {$count += UnBundleFile($_)} (glob(ArgGet(undef, $i)));
      }
   print("\nInvoice Counts:\n---------------\n");
   foreach my $name (sort keys %{$templatecounts})
      {
      printf("%-32s: %4d\n", $name, $templatecounts->{$name});
      }
   printf("%-32s: %4d\n", "Total", $count);
   }


sub UnBundleFile
   {
   my ($infile) = @_;

   my $outdir = ArgGet("out") || ".";
   my $count = 0;
   my $matchcount = 0;
   my $xml = "";
   my $xmlname = "";
   my $xmltemplate = "";
   my $justcount = ArgIs("count");
   my $type = ArgGet("type") || "";
   my $nottype = ArgGet("nottype") || "";

   Log("Unpacking $infile to $outdir") unless $justcount;

   open (my $filehandle, "<", $infile) or die "can't open $infile";
   while (my $line = <$filehandle>)
      {
      if ($line =~ /<InvoiceDocument>/)
         {
         $xml = $line;
         next;
         }
      $xml .= $line;

      my ($name) = $line =~ /InvoiceNumber="(\d+)"/;
      $xmlname = $name if $name;

      my ($template) = $line =~ /DocumentTemplate="(\w+)"/;
      $xmltemplate = $template if $template;

      if ($line =~ /<\/InvoiceDocument>/)
         {
         $count++;
         #my $matches = !$type || $xmltemplate =~ /$type/i ||;
         my $matches = 1;
         $matches &&= !$type || $xmltemplate =~ /$type/i;
         $matches &&= !$nottype || $xmltemplate !~ /$nottype/i;

         $matchcount++ if $matches;

         $templatecounts->{$xmltemplate} = 0 unless exists $templatecounts->{$xmltemplate};
         $templatecounts->{$xmltemplate}++;

         if ($matches && !$justcount)
            {
            Log("writing: $outdir\\$xmlname.xml");
            SpillFile("$outdir\\$xmlname.xml", $xml);
            }
         }
      }
   close ($filehandle);

   print "found $matchcount of $count invoices matching '$type'\n"   if ($type && $justcount);
   print "wrote $matchcount of $count invoices matching '$type'\n"   if ($type && !$justcount);
   print "found $count invoices\n"                                   if (!$type && $justcount);
   print "wrote $count invoices\n"                                   if (!$type && !$justcount);
   return $count;
   }

__DATA__

[usage]
Unbundle.pl  -  Unbundle the xml bundle to individual invoice xmls

USAGE: Unbundle.pl [options] bundlefile

WHERE: [options] are 0 or more of:
   -out ........... Specify the output directory (default is current dir)
   -type=str ...... Only unbundle this type of invoice
   -nottype=str ... Dont unbundle this type of invoice
   -count ......... Dont unbundle, just count invoices in bundle
   -quiet ......... Be quiet about it
   -help .......... This help.
 
EXAMPLES: 
   Unbundle.pl *.xml -out=xmldir
   Unbundle.pl -type=GeorgiaIndividualBudgetInvoice -out=xmldir *.xml 
   Unbundle.pl IE_19122015444939_GAINV_PDF.xml
   Unbundle.pl IE_19122015444939_GAINV_PDF.xml -out=xml
   Unbundle.pl -count *.xml
   Unbundle.pl -count -type=FloridaIndividualInvoice *.xml

[fini]