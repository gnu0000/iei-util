#!perl
use warnings;
use strict;
use File::Basename;
use lib dirname(__FILE__) . "/lib";
use File::Copy;
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;

my $DEL_COUNT = 0;

MAIN:
   $| = 1;
   ArgBuild("*^blanks *^comments *^scomments *^help ?"); # start# end# preserve comments, etc...

   ArgParse(@ARGV) or die ArgGetError();
   ArgAddConfig() or die ArgGetError();
   Usage() if ArgIs("help") || ArgIs("?") || !ArgIs();
   RemoveDupes();
   exit(0);


sub RemoveDupes
   {
   my $isInline = ArgIs("") < 2;
   my $inspec   = ArgGet("");
   my $outspec  = $isInline ? $inspec . "._00_" : ArgGet("", 1);


#print "'$isInline'  '$inspec' ''" . ArgIs("", 1) . " - " . ArgIs("", 2) . "\n";
#
#
#   print "A: " . ArgIs(     ) . " - " . ArgGet(     ) . "\n";
#   print "B: " . ArgIs(""   ) . " - " . ArgGet(""   ) . "\n";
#   print "C: " . ArgIs("", 0) . " - " . ArgGet("", 0) . "\n";
#   print "D: " . ArgIs("", 1) . " - " . ArgGet("", 1) . "\n";
#   print "E: " . ArgIs("", 2) . " - " . ArgGet("", 2) . "\n";
# exit(0);


   my ($readct, $writect) = Filter($inspec, $outspec);

   if ($isInline) 
      {
      move($inspec , $inspec . ".old") 
         or die "can't rename '$inspec' to '$inspec" . ".old'";
      move($outspec, $inspec         ) 
         or die "can't rename '$outspec' '$inspec'";
      }
   printf "filtered '$inspec'. $readct -> $writect lines\n"      if $isInline;
   printf "'$inspec' -> '$outspec'. $readct -> $writect lines\n" unless $isInline;
   }


sub Filter
   {
   my ($inspec, $outspec) = @_;

   my $keepb = ArgIs("blanks"   );
   my $keepc = ArgIs("comments" );
   my $keeps = ArgIs("scomments");

                 
   open (my $in,  "<", "$inspec" ) or die "can't read '$inspec'";
   open (my $out, ">", "$outspec") or die "can't write '$outspec'";
   my ($lines, $readct, $writect) = ({}, 0, 0);

   while (my $line = <$in>)
      {
      $readct++;

      next unless
         $keepb && $line =~ /^[ \t\n]*$/ ||
         $keepc && $line =~ m[^#]        ||
         $keeps && $line =~ m[^//]       ||
         !exists $lines->{$line}         ;

      print $out $line;
      $lines->{$line} = 1;
      $writect++;
      }
   close($out);
   close($in);
   return ($readct, $writect);
   }


__DATA__

[usage]
RemoveDupes.pl  -  Remove duplicate lines from a text file

USAGE: RemoveDupes.pl [options] infile [outfile]

WHERE: options are 0 or more of:
   -help .......... This help
   -blanks ........
   -comments ........
   -scomments ........
   (more coming)

EXAMPLES:
   RemoveDupes.pl wordy.txt
   RemoveDupes.pl wordy.txt unwordy.txt
[fini]