#!perl
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
use Common qw(MSConnect SourceSQL ShowDates Log);

MAIN:
   $| = 1;
   ArgBuild("*^db *^server= *^database= *^all *^allrecent *^recent *^date= *^since= *^showdates *^metadata= *^force *^strip *^out= *^max= ^help");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIsAny("", "db", "showdates");
   ShowDates(1) if ArgIs("showdates");
   MakeBundle();
   exit(0);


sub MakeBundle
   {
   my $fh = StartBundle();
   ArgIs("db") ? MakeDBBundle($fh) : MakeFileBundle($fh);
   EndBundle($fh);
   }

########################### db ##############################################
#
#sub MakeDBBundle
#   {
#   my ($fh) = @_;
#
#   my $db = MSConnect();
#   my $sql = SourceSQL($db);
#   my $sth = $db->prepare ($sql) or die "error preparing sql statement";
#
#   $sth->{'LongReadLen'} = 50000; # sqlserver specific requirement
#   $sth->execute ();
#   my $count = 0;
#   while (my $row = $sth->fetchrow_hashref())
#      {
#      my $xml = PrepXML($row->{HM_XML});
#      print $fh $xml;
#      print ".";
#      $count++;
#      }
#   $sth->finish();
#   Log("\nCreated bundle with $count invoices.");
#   }
#
########################### file ############################################

sub MakeFileBundle
   {
   my ($fh) = @_;

   my $count = 0;
   for (my $i=0; $i<ArgIs(); $i++)
      {
      map {$count += ProcessFile($fh, $_)} (glob(ArgGet(undef, $i)));
      }
   Log("\nCreated bundle with $count invoices.");
   }

sub ProcessFile
   {
   my ($fh, $filename) = @_;

   my $data = SlurpFile($filename);
   my $xml = PrepXML($data);
   print $fh $xml;
   print ".";
   return 1;
   }

########################### common ##########################################

sub StartBundle
   {
   my $filespec = ArgGet("out") || GetBundleName();
   Log("Creating bundle file $filespec...");
   open (my $fh, ">", $filespec) or die "Cannot open '$filespec' for writing.";
   print $fh Template("start_bundle");
   return $fh;
   }

sub EndBundle
   {
   my ($fh) = @_;

   print $fh Template("end_bundle");
   close $fh;
   }

sub PrepXML
   {
   my ($xml) = @_;

   $xml =~ s/\x{00a2}/c/mg;
   $xml =~ s/\x{00c2}//mg;
   $xml =~ s/\r//mg;
   $xml =~ s/([\x00-\x09]+)|([\x0B-\x1F]+)//mg;
   $xml =~ s/^/  /mg;

   my $metadata = GetMetadata();
   my ($hasmeta) = $xml =~ /<Metadata>.*<\/Metadata>/mis;

   $xml =~ s/<Metadata>.*<\/Metadata>/$metadata/mis if $hasmeta && ArgIs("force");
   $xml =~ s/(<DocumentInfo.+?>)/$1\n$metadata/mis unless $hasmeta;
   $xml =~ s/Safety Notice/Safety_Notice/mis;

   return $xml . "\n";
   }

sub GetBundleName
   {
   my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
   $year -= 100;
   $mon  = twod($mon ) + 1;
   $mday = twod($mday);
   $hour = twod($hour);
   $min  = twod($min );
   $sec  = twod($sec );
   return "IE_$year$mon$mday$hour$min$sec"."00_GAINV_PDF.xml";
   }

sub twod
   {
   return sprintf ("%02d", $_[0]);
   }

sub GetMetadata
   {
   state $gotMetdata = 0;
   state $metadata = "";

   return $metadata if $gotMetdata;
   $gotMetdata = 1;

   return $metadata = ArgIs("metadata") ? SlurpFile(ArgGet("metadata")) : Template("metadata");
   }

__DATA__

[usage]
MakeBundle  -  Create Invoice bundle from xml files

USAGE: MakeBundle [options] xmlfiles...

This utility also populates the metadata for each invoice unless the invoice
already has a metadata section.

   xmlfiles .......... One or more files to scan. Wildcards ok

OPTIONS are 0 or more of:
   -metadata=file ... Use the metadata xml snippet from this file.
   -force ........... Always use the supplied metadata, replacing any existing metadata.
   -out=file ........ The output file name (default: generated from datetime)
   -debug ........... Include debug output
   -help ............ This help

EXAMPLES:
   MakeBundle *.xml
   MakeBundle xmlfiles\*.xml extras\*.xml -metadata=metadata.xml 
   MakeBundle -recent -o:batch.out *.xml

[old-usage]
MakeBundle  -  Create Invoice bundle from xml files or the adept database.

USAGE: MakeBundle [options] xmlfiles...
   -or-
USAGE: MakeBundle [options] -db

This Utility can get invoices from either the database or local files

This utility also populates the metadata for each invoice unless the invoice
already has a metadata section.

Database specific options:
   -db .............. Use the adept database (default is files)
   -server=name ..... Identify MSSQL Server (test-babyadept)
   -database=name ... Identify MSSQL Database (Adept)
   -all ............. Use all invoices
   -allrecent ....... Use the most recent version of all invoices
   -recent .......... Use invoices from the most recent date (default)
   -date=date ....... Use invoices generated on this date
   -since=date ...... Use invoices generated on this date or newer
   -showdates ....... Show what generated dates are available to scan

Local file specific options:
   files ............ One or more files to scan. Wildcards ok

Common options:    
   -metadata=file ... Use the metadata xml snippet from this file.
   -force ........... Always use the supplied metadata, replacing any existing metadata.
   -out=file ........ The output file name (default: generated from datetime)
   -debug ........... Include debug output
   -help ............ This help

EXAMPLES:
   MakeBundle -db
   MakeBundle -db -allrecent
   MakeBundle -db -date:2019-12-04 -server=test-babyadept
   MakeBundle *.xml
   MakeBundle xmlfiles\*.xml extras\*.xml -metadata=metadata.xml 
   MakeBundle -recent -o:batch.out *.xml
   MakeBundle -date:2019-10-10 -metadata=metadata.xml *.xml
   MakeBundle -showdates

[start_bundle]
<?xml version="1.0" encoding="utf-8"?>
<InvoiceDocuments>
[metadata]
    <Metadata>
      <Inserts>
        <Insert value="" />
      </Inserts>
      <Onserts>
        <Onsert value="" />
      </Onserts>
      <WrapperEnvelopeId value="GA_IN" />
      <ForeignAddressFlag value="N" />
    </Metadata>
[end_bundle]
</InvoiceDocuments>
[blankcharge]
        <Charge ExternalAccount="" TierId="" ReadAmount="" PreviousReadAmount="" ReadSource="" PreviousReadSource="" ReadBeginDate="" ReadEndDate="" NumberOfDays="" UsageVolume="0.0" Usage="0.0" ConversionFactor="" Rate="" CommodityCharge="" DeliveryAmount="" DDDC="" CSFeeAmount="" DMSFee="" SourcingFee="" EnhancedServicesFee="" PassThroughCharge="" DACCharge="" FGTFuelCharge="" LDCFuelCharge="" TaxAmount="" AdjustmentAmount="" TotalAmount="" />
      </Account>
[blankhistory]
        <UsageHistoryDetail SortOrder="0" Quantity="" ServiceMonthAndYear="" />
      </UsageHistory>
[fini]