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
use Common qw(Log);

MAIN:
   $| = 1;
   ArgBuild("*^out= ^help ^?");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || ArgIs("?") || !ArgIs("");
   Anonymize();
   exit(0);

sub Anonymize
   {
   my $count = 0;
   for (my $i=0; $i<ArgIs(); $i++)
      {
      map {$count += AnonymizeFile($_)} (glob(ArgGet(undef, $i)));
      }
   printf("%-32s: %4d\n", "Invoices anonymized", $count);
   }

sub MakeName      
   {
   state $names = LoadNames("firstnames.dat");
   state $ct    = scalar @{$names};

   return "John Q Smith" if !$ct;
   return Camelize($names->[int(rand($ct))]) . " Anonymized";
   }

sub LoadNames
   {
   my ($filespec) = @_;

   my $data = SlurpFile($filespec);
   return [split(/\n/, $data)];
   }

sub Camelize 
   {
   my ($s) = @_;

   $s =~ s{(\w+)}{($a=lc $1)=~ s<(^[a-z]|_[a-z])><($b=uc $1)=~ s/^_//;$b;>eg;$a;}eg;
   $s;
   }

sub Num
   {
   my ($size) = @_;

   my $num = "";
   for my $i (1..$size)
      {
      my $i = int(rand(10));
      $num .= "$i";
      }
   return $num;
   }

sub AnonymizeFile
   {
   my ($filespec) = @_;

   my $name       = MakeName();
   my $account    = Num(10);
   my $extaccount = Num(9);
   my $invoice    = $account . "2010";
   my $email      = "anonymized\@nowhere.com";
   my $addr1      = Num(4) . " Anonymous Street";
   my $addr2      = "Somewhere, GA 32608";
   my $addr0      = $addr1 . " " .$addr2;
   my $location   = "0" . Num(11);
   my $meternum   = "000" . Num(6);
   my $phone      = "(555)555-5555";
   my $zip        = "32608";

   open (my $fh, "<", "$filespec") or die "can't open $filespec";
   open (my $fh2, ">", "$filespec". "2") or die "can't open outfile";
   while (my $line = <$fh>)
      {
      my $extaccountb = Num(9);

      $line =~ s/( AccountNumber=\")\d+(\".*)/$1$account$2/;
      $line =~ s/( InvoiceNumber=\")\d+(\".*)/$1$invoice$2/;
      $line =~ s/( ExternalAccount=\")\d+(\".*)/$1$extaccountb$2/;
      $line =~ s/( ExternalVendorAccountNumber=\")\d+(\".*)/$1$extaccount$2/;
      $line =~ s/( InternalAccountNumber=\")\d+(\".*)/$1$2/;
      $line =~ s/( AccountName=\").*?(\".*)/$1$name$2/;
      $line =~ s/( EmailAddress=\").*?(\".*)/$1$email$2/;
      $line =~ s/( Phone=\").*?(\".*)/$1$phone$2/;
      $line =~ s/( Fax=\").*?(\".*)/$1$phone$2/;
      $line =~ s/( AddressLine1=\").*?(\".*)/$1$addr1$2/;
      $line =~ s/( AddressLine2=\").*?(\".*)/$1$addr2$2/;
      $line =~ s/( AddressLine3=\").*?(\".*)/$1$2/;
      $line =~ s/( ZipCode=\").*?(\".*)/$1$zip$2/;
      $line =~ s/( LocationIdentifier=\").*?(\".*)/$1$location$2/;
      $line =~ s/( MeterNumber=\").*?(\".*)/$1$meternum$2/;
      $line =~ s/( Address=\").*?(\".*)/$1$addr0$2/;

      print $fh2 $line;
      }
   close ($fh);
   close ($fh2);
   }

__DATA__

[usage]
todo