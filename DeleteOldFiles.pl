#!perl
#
# DeleteOldFiles.pl  -  Delete files older than a certain date
# Craig fitzgerald
#

use warnings;
use strict;
use JSON;
use POSIX            qw(strftime);
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;

my $DEL_COUNT = 0;

MAIN:
   $| = 1;
   ArgBuild("*^before= *^date= *^match= *^quiet *^show *^test ^help");

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIs();
   my $dir = ArgGet() || ".";
   DeleteOldFiles($dir);
   exit(0);


sub DeleteOldFiles
   {
   my ($dir) = @_;

   my $date   = NormalizeDate(ArgGet("date"));
   my $before = NormalizeDate(ArgGet("before"));
   my $match  = ArgGet("match");
   my $test   = ArgGet("test");

   print "dir   : $dir\n"    ;
   print "date  : $date\n"   if $date;
   print "before: $before\n" if $before;
   print "match : $match\n"  if $match;
   print "--test mode--\n"   if $test;

   opendir(my $dh, $dir) or die ("\ncant open dir '$dir'!");
   my @all = readdir($dh);
   closedir($dh);
   my $filecount = 0;
   my $range = {};
   foreach my $file (@all)
      {
      my $spec = "$dir\\$file";
      next unless -f $spec;
      my ($size,$mtime) = (stat($spec))[7,9];
      my $filedate = strftime("%Y-%m-%d", localtime($mtime));

      next if $match && $file !~ /$match/i;
      $filecount++;
      next if SetRange($range, $filedate);
      DeleteFile($spec, $file) if $date   && $filedate eq $date;
      DeleteFile($spec, $file) if $before && $filedate lt $before;
      }
   print "Date range: $range->{min} <==> $range->{max} in $filecount files.\n" if ArgIs("show");
   print "Deleted $DEL_COUNT of $filecount files.\n" unless ArgIs("show");
   }


sub SetRange
   {
   my ($range, $filedate) = @_;

   $range->{max} ||= $range->{min} ||= $filedate;
   $range->{max} = $filedate if ($filedate cmp $range->{max}) > 0;
   $range->{min} = $filedate if ($filedate cmp $range->{min}) < 0;
   return ArgIs("show");
   }


sub DeleteFile
   {
   my ($spec, $file) = @_;

   return print "would delete $file\n" if ArgIs("test");
   unlink $spec or return warn "Could not unlink $spec: $!";
   $DEL_COUNT++;
   return print "deleted $file\n" unless ArgIs("quiet");
   }


sub Test()
   {
   NormalizeDate("2020-01-01");
   NormalizeDate("2020-1-1");
   NormalizeDate("20-01-01");
   NormalizeDate("20-1-1");
   NormalizeDate("05/01/2020");
   NormalizeDate("05/01/20");
   NormalizeDate("5/1/20");
   NormalizeDate("2020");
   NormalizeDate("2020-01");
   NormalizeDate("2020-01/01");

   exitr(0);
   }

sub NormalizeDate
   {
   my ($in) = @_;

   return $in unless $in;

   my ($year,$month,$day) = $in =~ /^(\d+)-(\d+)-(\d+)$/;
   ($month,$day,$year) = $in =~ /^(\d+)\/(\d+)\/(\d+)$/ unless $year;

   die "Can't parse date '$in'\n" unless $year;
   $year  = "20". $year  if length $year == 2;
   $month = "0" . $month if length $month < 2;
   $day   = "0" . $day   if length $day   < 2;

   return "$year-$month-$day\n";
   }

__DATA__

[usage]
DeleteOldFiles.pl  -  Delete files older than a certain date

USAGE: DeleteOldFiles.pl [options] [dir]

WHERE: options are 0 or more of:
   -before=date ... Delete files older than this date
   -date=date ..... Delete files from this date
   -match=str ..... Filter to files containing this string
   -show .......... Show date range, dont delete
   -quiet ......... Do not show progress
   -test .......... Do not actually delete, just report
   -help .......... This help

EXAMPLES:
   DeleteOldFiles.pl -before=2020-03-25 .
   DeleteOldFiles.pl -date=2020-03-25  c:\hold
   DeleteOldFiles.pl -before=2020-03-25 -match=FL .
   DeleteOldFiles.pl -before=20-03-25 -quiet c:\proj\zzz
   DeleteOldFiles.pl -before=03/25/2020 -test .
   DeleteOldFiles.pl -before=03/25/20 .
[fini]