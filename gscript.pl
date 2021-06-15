use warnings;
use strict;

use File::Basename;
use lib dirname(__FILE__) . "/../lib";
use Gnu::ArgParse;
use Gnu::Template qw(Template Usage);
use Gnu::FileUtil qw(SlurpFile);
use Gnu::Gscript  qw(:ALL);

MAIN:
   $| = 1;
   ArgBuild("*^call= *^echo *^help *^elevel= *^plevel= *^tlevel= *^echo");
   ArgParse(@ARGV) or die ArgGetError();

   SetTokenLogLevel(ArgGet("tlevel")) if ArgIs("tlevel");
   SetParseLogLevel(ArgGet("plevel")) if ArgIs("plevel");
   SetEvalLogLevel (ArgGet("elevel")) if ArgIs("elevel");
   Usage() if ArgIs("help") || !ArgIs();
   RunFile(ArgGet());
   exit(0);

sub RunFile
   {
   my ($spec) = @_;

   SetVars();
   SetFns();
   my $data = SlurpFile($spec);
   my $result = Eval($data);
   print GetError() . "\n" if IsError();
   if (ArgIs("call"))
      {
      my @args = split(",", ArgGet("call"));
      $result = CallFn(@args);
      print GetError() . "\n" if IsError();
      }
   exit($result);
   }

# add a few variables
sub SetVars
   {
   SetEvalVars({
      %{GetEvalVars()},
      test1 => 1     ,
      test2 => -124.6,
      echo  => ArgIs("echo"),
      });
   GetEvalVars()->{fuzzy} = "Wuzzy";
   }

# add a few script fn -> perl sub bindings
sub SetFns
   {
   SetEvalFns
      ({
      %{GetEvalFns()},
      Func1 => sub{$_[0]*5-2},
      Germ  => \&Germinate,
      });
   }

sub Germinate
   {
   my ($x, $y) = @_;
   return 2*$x*$y + $x*$x + $y*$y + $x + $y;
   }

__DATA__

[usage]
gscript.pl  -  Run a Gscript

USAGE: gscript.pl [options] scriptfile

WHERE: 
   scriptfile is a file containg gscript code
   [options] are 0 or more of:
      -call=fn,p1,p2 .. Call this fn with these params
      -elevel ......... Set logging level for Eval
      -plevel ......... Set logging level for Parser
      -tlevel ......... Set logging level for Tokenizer 
      -echo ........... echo lines of script file (passed to script)

EXAMPLES:
   gscript.pl samples.scr
   gscript.pl samples.scr -call=Germ,3,4
   gscript.pl samples.scr -call=S,24

   samples.scr contents:
      x = true ? 12 : 3
      a1 = 1
      a2 = 22
      a3 = 33
      a4 = a1 ? ++a2 : ++a3
      F1(x)=>{x**2/(x+x)}; F2(x)=>{F1(x)/3}; F2(5)
      S(x) => {x < 1 ? 1 : (x % 2 ? S(x-1)+S(x-2) : S(x-3)+S(x-4))}
      S(7)
      print(S(20) + F2(5))
