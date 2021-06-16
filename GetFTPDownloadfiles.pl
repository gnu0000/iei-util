#!perl
#
# GetFTPDownloadFiles  -  Download the Highmark zips for a day
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


MAIN:
   $| = 1;
   ArgBuild("*^showfiles *^showlinks *^environment= ^help");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIs();

   my $date = ArgGet();
   ShowFiles($date) if ArgIs("showfiles") || ArgIs("showlinks");
   GetFiles($date);
   print "Done.\n";
   exit(0);


sub GetFileInfo
   {
   my ($date) = @_;

   my $env = ArgGet("environment") || "prod";
   my $ftpcmd = 'curl -X GET "https://ftp-downloads.' . $env . '.gainesville.infiniteenergy.com/sites/Highmark/files?FromDate=' . $date . '&ToDate=' . $date . '" -H "accept: text/plain"';
   my $result = `$ftpcmd`;
   my $meta = decode_json($result);
   my $info = [];

   foreach my $entry (@{$meta})
      {
      my ($filename) = $entry->{fileName} =~ /^.*\/([^\/]+\.zip)/;
      $entry->{fileName} = $filename;
      push(@{$info}, $entry) if $filename;
      }
   my $count = scalar @{$info};
   print "got $count files\n";

   return $info;
   }


sub ShowFiles
   {
   my ($date) = @_;

   my $info = GetFileInfo($date);

   #foreach my $entry (@{$info})
   #   {
   #   print "$entry->{fileName}\n" if ArgIs("showfiles");
   #   print "$entry->{blobUrl}\n" if ArgIs("showlinks");
   #   }
   map {print "$_->{fileName}\n"} @{$info} if ArgIs("showfiles");
   map {print "$_->{blobUrl}\n" } @{$info} if ArgIs("showlinks");

   exit(0);
   }

sub GetFiles
   {
   my ($date) = @_;

   my $info = GetFileInfo($date);

   foreach my $entry (@{$info})
      {
      print "$entry->{fileName}\n";
      $entry->{blobUrl} =~ s/&/^&/g;
      system("start $entry->{blobUrl}\n");
      sleep 1;
      }
   exit(0);
   }


# for whatever reason, curl is much slower than the browser at downloading, and is synchronous
#
sub GetFiles0
   {
   my ($date) = @_;

   my $info = GetFileInfo($date);
   foreach my $info (@{$info})
      {
      my $fcmd = "curl -X GET \"$info->{blobUrl}\" -H \"accept: text/plain\" -o $info->{fileName}";
      print "cmd: $fcmd\n";
      system($fcmd);
      }
   }

__DATA__

[usage]
GetFTPDownloadFiles  -  Download the Highmark zips for a day

USAGE: GetFTPDownloadFiles [options] date

WHERE: [options] is 0 or more of:
   -env ......... Set the environment (int,preprod,prod) default is prod
   -showfiles ... Show filenames & quit
   -showlinks ... Show file URIs & quit
   -help ........ This help

EXAMPLES:
   Download the files (using your browser)
      GetFTPDownloadFiles.pl 2020-03-02

   List the filenames and exit
      GetFTPDownloadFiles.pl -showfiles 2020-03-02

   List the file URLs and exit
      GetFTPDownloadFiles.pl -showlinks 2020-03-02
