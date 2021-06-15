#!perl
use warnings;
use strict;
use JSON;
use POSIX            qw(strftime);
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;


MAIN:
   $| = 1;
   ArgBuild("^help *^match=");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIs();

   my $date = ArgGet();
   GetBundles($date);
   exit(0);


sub GetBundles
   {
   my ($date) = @_;

   my $dir = '\\\trans1\C\DataFiles\To_Highmark\Archive';
   print "dir: $dir\n";
   print "date: $date\n";

   opendir(my $dh, $dir) or die ("\ncant open dir '$dir'!");
   my @all = readdir($dh);
   closedir($dh);
   my $count = 0;
   my $match = ArgGet("match");
   foreach my $file (@all)
      {
      my $spec = "$dir\\$file";
      next unless -f $spec;
      my ($size,$mtime) = (stat($spec))[7,9];
      my $filedate = strftime("%Y-%m-%d", localtime($mtime));
      next unless $filedate =~ /$date/i;
      next if $match && $file !~ /$match/i;
      print "$file\n";
      system ("copy \"$spec\" .");
      $count++;
      }
   print "Got $count files.\n"
   }

__DATA__

[usage]
GetProdBundles.pl  -  Get the bundles archived for a particular date

USAGE: GetProdBundles.pl [options] [date]

WHERE: options are 0 or more of:
   -match=-str ... Only get files that contain this string
   -help ......... This help

EXAMPLES:
   GetProdBundles.pl 2020-03-25
   GetProdBundles.pl 2020-03-25 -match=1304
[fini]