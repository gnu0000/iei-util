#!perl
#
# GetBundles  -  Download the Highmark bundles for a day, or the bundle names
# Craig fitzgerald
#

use warnings;
use strict;
use JSON;
use URI::Encode qw(uri_encode uri_decode);
use Gnu::SimpleDB;
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;
use Gnu::DateTime qw(DBDateToDisplayDate DBDateToDateTimeObject NowToDateTimeObject);
use Gnu::DebugUtil qw(DumpRef);
use Gnu::FileUtil qw(SpillFile);


MAIN:
   $| = 1;
   ArgBuild("*^names *^files *^environment= ^help ^debug");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !(ArgIs("names") || ArgIs("files"));
   my $names = ArgIs("") ? NewGetBundleNames() : GetBundleNames();
   GetFiles($names) if ArgIs("files");
   ShowNames($names) unless ArgIs("files");

   print "Done.\n";
   exit(0);

sub GetBundleNames
   {
   my $env = ArgGet("environment") || "prod";
   my $ftpcmd = 'curl -X GET "https://highmark-gateway.' . $env . '.gainesville.infiniteenergy.com/Bundles/bundles-today" -H "accept: text/plain"';
#   my $ftpcmd = 'curl -X GET "https://highmark-gateway.' . $env . '.gainesville.infiniteenergy.com/Bundles/bundle-today" -H "accept: text/plain"';
   print "$ftpcmd\n" if ArgIs("debug");
   my $result = `$ftpcmd`;
   my $meta = decode_json($result);
   my $names = [];

   print "Environment: $env\n";
   foreach my $entry (@{$meta})
      {
      push(@{$names}, $entry->{bundleName});
      }
   return $names;
   }

# Waiting for the new /Bundles/bundles-info endpoint (and maybeDate becomes date)
#
sub NewGetBundleNames
   {
   my $env = ArgGet("environment") || "prod";
   my $date = ArgGet();
   my $ftpcmd = 'curl -X GET "https://highmark-gateway.' . $env . '.gainesville.infiniteenergy.com/Bundles/bundles-info?maybeDate='. $date .'" -H "accept: text/plain"';
   print "$ftpcmd\n" if ArgIs("debug");
   my $result = `$ftpcmd`;
   my $meta = decode_json($result);
   my $names = [];

   print "Environment: $env\n";
   foreach my $entry (@{$meta})
      {
      push(@{$names}, $entry->{bundleName});
      }
   return $names;
   }

sub ShowNames
   {
   my ($names) = @_;

   map{print "   $_\n"} (@{$names});
   }

sub GetFiles
   {
   map{GetFile($_)} (@{$names});
   }

sub GetFile
   {
   my ($name) = @_;

   my $env = ArgGet("environment") || "prod";
   my $ftpcmd = 'curl -X GET "https://highmark-gateway.' . $env . '.gainesville.infiniteenergy.com/Bundles/' . $name . '/concatenated" -H "accept: application/json"';
   print "$ftpcmd\n" if ArgIs("debug");
   my $result = `$ftpcmd`;

   print "   writing: $name\n";
   SpillFile("$name.xml", $result);
   }

__DATA__

[usage]
GetBundles  -  Download the Highmark bundles for a day, or the bundle names

USAGE: GetBundles [options] date

WHERE: [options] is 0 or more of:
   -env ..... Set the environment (int,preprod,prod) default is prod
   -files ... Get the bundle files
   -names ... Show the bundle filenames
   -debug ... Show the curl cmds
   -help .... This help

EXAMPLES:
   Download the files (using your browser)
      GetBundles.pl -files 2020-03-02

   List the filenames
      GetBundles.pl -names 2020-10-01
