#!perl
use warnings;
use strict;
use feature 'state';
use XML::LibXML;
use List::Util qw(max);
use File::Basename;
use lib dirname(__FILE__);
use lib dirname(__FILE__) . "/lib";
use Gnu::Template qw(Template Usage);
use Gnu::ArgParse;
use Gnu::FileUtil qw(SlurpFile SpillFile);
use Gnu::DebugUtil qw(DumpHash DumpRef);
use Gnu::StringUtil qw(TrimList);
use Gnu::SimpleDB;
use Common qw(MSConnect SourceSQL ShowDates Log);

my $TOKENS = [];
my $TESTS  = {global => {macros => {}}};

MAIN:
   $| = 1;
   ArgBuild("*^db *^all *^allrecent *^recent *^date= *^since= *^market= *^test= **^maxresults= ^showdates *^text *^html *^debug *^help ?");

   ArgParse(@ARGV) or die ArgGetError();
   Usage() if ArgIs("help") || !ArgIsAny("", "db", "showdates");
   ShowDates(0,1) if ArgIs("showdates");
   LoadTests();
   DumpTests() if ArgIs("debug");
   ScanInvoices();
   GenOutput();
   Log("Done.");
   exit(0);


sub LoadTests
   {
   my $filespec = $0;
   $filespec =~ s/\.\w+$/\.cfg/;
   open (my $fh, "<", "$filespec") or die "can't find $filespec";

   my $key = "nada";
   my $order = 0;
   while (my $line = <$fh>)
      {
      chomp $line;
      next if $line =~ /^#/;
      my ($sectionname) = $line =~ /^\[(\S+)\]/;
      if ($sectionname)
         {
         $key = $sectionname;
         $TESTS->{$key} = NewTest($key, $order++);
         next;
         }
      my $test = $TESTS->{$key};
      my ($type, $data) = $line =~ /^\s*([^:]+)\s*:\s*(.+)\s*$/;
      next unless $type && $data;
      map {AddString($test, $_, $data) if $type =~ /$_/i} qw(label maxresults order ignore sort);
      AddCond  ($test, $data) if $type =~ /cond/i;
      AddShow  ($test, $data) if $type =~ /show/i;
      AddMatch ($test, $data) if $type =~ /match/i;
      AddMacro ($test, $data) if $type =~ /macro/i;
      }
   map {delete $TESTS->{$_} unless IncludeTest($_)} (keys %{$TESTS});
   }


sub AddString
   {
   my ($test, $type, $data) = @_;

   $test->{$type} = ResolveMacros($test, $data);
   }

sub AddCond
   {
   my ($test, $data) = @_;

   $test->{condexpr} = $data;
   $test->{cond} = ParseCondition($data);
   }

sub AddShow
   {
   my ($test, $data) = @_;

   $data = ResolveMacros($test, $data);
   my ($label, $xpath) = $data =~ /^\s*(\w+:)\s*(.*)$/;
   push(@{$test->{shows}}, {xpath=>$data, label=>""})      if (!defined $label);
   push(@{$test->{shows}}, {xpath=>$xpath, label=>$label}) if (defined $label);
   }


sub AddMatch
   {
   my ($test, $data) = @_;

   $data = ResolveMacros($test, $data);
   my ($xpath, $cond, $val) = TrimList($data =~ /^(.*),([^,]+),([^,]+)$/);
   $xpath = $data unless defined $val;

   push(@{$test->{matches}}, {xpath=>$xpath, cond=>$cond, val=>$val});
   }


sub AddMacro
   {
   my ($test, $data) = @_;

   my ($name, $val) = $data =~ /^\s*(\w+)\s*=\s*(.*)$/;
   $test->{macros}->{$name} = $val;
   }


sub ResolveMacros
   {
   my ($test, $data) = @_;

   my $macros = {%{$TESTS->{global}->{macros}}, %{$test->{macros}}};

   foreach my $i (0..10) # allow nested macro's
      {
      last unless $data =~ /\{/;
      $data =~ s{\{(\w+)\}}{exists $macros->{$1} ? $macros->{$1} : "$1"}gei;
      }
   return $data;
   }


sub NewTest
   {
   my ($key, $order) = @_;

   return {
      name       => $key  , 
      label      => ""    , 
      matches    => []    , 
      shows      => []    , 
      macros     => {}    ,
      sort       => ""    ,
      maxresults => 9999  , 
      results    => []    , 
      order      => $order};
   }


sub IncludeTest
   {
   my ($name) = @_;

   # not a real test or improperly formed
   return 0 unless $TESTS->{$name}->{label};
   my $testcount = ArgIs("test");
   # run all (non ignored) tests if no test is explicitly specified
   return !$TESTS->{$name}->{ignore} if !$testcount;
   # run tests that are specified on the cmdline
   for (my $i=0; $i<$testcount; $i++)
      {
      my $arg = ArgGet("test", $i);
      return 1 if $name =~ /$arg/;
      }
   return 0;
   }


sub ScanInvoices
   {
   return ArgIs("db") ? ScanDBInvoices() : ScanFileInvoices();
   }


sub ScanDBInvoices
   {
   Log("Looking at Invoices from the database...");

   #converted to fetchrow for memory considerations
   my $db = Connect("samples");
   my $sql = SourceSQL($db);
   my $sth = $db->prepare ($sql) or die "error preparing sql statement";

   $sth->{'LongReadLen'} = 50000; # sqlserver specific requirement
   $sth->execute ();

   my $count = 0;
   while (my $row = $sth->fetchrow_hashref())
      {
      ScanInvoice($row->{HM_XML});
      $count++;
      }
   $sth->finish();
   Log("Scanned $count invoices.");
   }


sub ScanFileInvoices
   {
   Log("Looking at invoice files...");
   my $count = ArgIs();
   for (my $i=0; $i<$count; $i++)
      {
      map {ScanInvoice(SlurpFile($_))} (glob(ArgGet(undef, $i)));
      }
   }


sub ScanInvoice
   {
   my ($xml) = @_;

   print "." unless ArgIs("html");

   $xml =~ s/\x{00a2}/c/mg;
   $xml =~ s/\r//mg;
   $xml =~ s/[^[:print:]]+//mg;
   $xml =~ s/([\x00-\x09]+)|([\x0B-\x1F]+)//mg;
   my $dom = XML::LibXML->load_xml(string => $xml);

   map {Test($dom, $TESTS->{$_})} keys (%{$TESTS});
   }


sub Test
   {
   my ($dom, $test) = @_;

   if (my $market = ArgGet("market")) # filter by market first?
      {
      my ($curr) = $dom->find('//DocumentInfo/@DocumentLanguageMarket') =~ /\w+-(\w+)/;
      return unless $market =~ /$curr/i;
      }
   return unless Passes($dom, $test);

   my $result = 
      {invnum=> $dom->find('//InvoiceDetails/@InvoiceNumber'),
       env   => CompToEnv($dom->find('//Message[contains(@Type, "ComputerName")]/@Description')),
       shows => [map{$dom->find($_->{xpath})} @{$test->{shows}}],
       sort  => SortVal($dom, $test->{sort})};
   push (@{$test->{results}}, $result);
   }


sub Passes
   {
   my ($dom, $test) = @_;

   my $matches    = [];
   my $matchesall = 1;

   foreach my $match (@{$test->{matches}})
      {
      my $pass = Matches($dom, $match);
      push (@{$matches}, $pass);
      $matchesall &= $pass;
      }
   return $matchesall unless $test->{cond};
   return EvalCondition($test->{cond}, $matches);
   }


sub Matches
   {
   my ($dom, $match) = @_;

   my ($xpath, $cond, $val) = @{$match}{"xpath", "cond", "val"};
   if (!$cond)
      {
      my @nodes = $dom->findnodes($xpath);
      return scalar @nodes;
      }
   my $res = $dom->find($xpath);
   $res = $res->string_value() if ref $res eq "XML::LibXML::NodeList";
   #$res = $res->value()       if ref $res eq "XML::LibXML::Number";
   #Log("$xpath => ($res  $cond  $val)") if ArgIs("debug");

   return
      $cond eq "=" ? ($res||0) == $val  :
      $cond eq "<" ? ($res||0) <  $val  :
      $cond eq ">" ? ($res||0) >  $val  :
      $cond eq "~" ? $res     =~ /$val/ :
         die "unknown condition: $cond\n";
   }


sub CompToEnv
   {
   my ($comp) = @_;

   $comp ||= "";
   return $comp =~ /GN00LTND8R/i  ? "int"     :
          $comp =~ /TEST-BILLER/i ? "preprod" :
                                    "prod"    ;
   }


sub SortVal
   {
   my ($dom, $xpath) = @_;

   return "" unless $xpath;
   my $res = $dom->find($xpath);
   return ref $res eq "XML::LibXML::NodeList" ? $res->string_value() : 
          ref $res eq "XML::LibXML::Number"   ? $res->value()        :
                                                $res                 ;
   }


sub GenOutput
   {
   SortTestResults();
   return ArgIs("html") ? GenHtmlOutput() : GenTextOutput();
   }


sub SortTestResults
   {
   foreach my $test (values %{$TESTS})
      {
      next unless $test->{sort};
      $test->{results} = [sort {compare($b->{sort}, $a->{sort})} @{$test->{results}}];
      }                              
   }

sub compare
   {
   return $_[0] <=> $_[1] if $_[0] =~ /^[\d\.\-]*$/ && $_[1] =~ /^[\d\.\-]*$/;
   return $_[0] cmp $_[1];
   }


#############################################################################
#
# Condition expression parser
#

sub ParseCondition
   {
   my ($expr) = @_;

   Tokenize($expr);
   return Parse0();
   }

sub Parse0
   {
   my $node = Parse1();
   return {type=>Eat("||"), left=>$node, right=>Parse0()} if Peek("||"); 
   return $node;
   }

sub Parse1
   {
   my $node = Parse2();
   return {type=>Eat("&&"), left=>$node, right=>Parse1()} if Peek("&&"); 
   return $node;
   }

sub Parse2
   {
   return {type=>Eat("!"), left=>Parse2()} if Peek("!");
   return Parse3();
   }

sub Parse3
   {
   return Parse4() unless (Peek("("));
   Eat("(");
   my $node = Parse0();
   Eat(")");
   return $node;
   }

sub Parse4
   {
   my ($val) = Eat("ident") =~ /^match(\d)$/;
   return {type=>"ident", index=>$val};
   }

sub Tokenize
   {
   my ($expr) = @_;

   my @tokens = ();
   while (length $expr)
      {
      my ($tok, $rest) = $expr =~ /^\s*(\|\||\&\&|\!|\(|\)|match\d)(.*)$/;
      die "Unparseable expr: '$expr'" unless $tok;
      push (@tokens, $tok);
      $expr = $rest;
      }
   $TOKENS = [@tokens];
   }

sub Peek
   {
   my ($expect) = @_;

   return 0 unless scalar @{$TOKENS};
   return $TOKENS->[0] eq $expect;
   }

sub Eat
   {
   my ($expect) = @_;

   my $tok = $TOKENS->[0];

   if ($expect =~ /ident/i)
      {
      die "Unexpected token '$tok'" unless $tok =~ /match\d/i;
      return shift @{$TOKENS};
      }
   die "Unexpected token '$tok'" unless Peek($expect);
   shift @{$TOKENS};
   }

#############################################################################
#
# Condition expression evaluator
#

sub EvalCondition
   {
   my ($ptree, $matches) = @_;

   return EvalNode($ptree, $matches);
   }

sub EvalNode
   {
   my ($node, $matches) = @_;

   my $type = $node->{type};

   my $val = $type eq "||"    ? EvalNode($node->{left}, $matches) || EvalNode($node->{right}, $matches) :
             $type eq "&&"    ? EvalNode($node->{left}, $matches) && EvalNode($node->{right}, $matches) :
             $type eq "!"     ? !EvalNode($node->{left}, $matches)                                      :
             $type eq "ident" ? $matches->[$node->{index} - 1]                                          :
                                die "Unknown node '$type'"                                              ;
   return $val || 0;
   }


#############################################################################
#
# Output
#

sub GenHtmlOutput
   {
   my $currtime = localtime();
   my $market = ArgIs("market") ? ' for market "' . ArgGet("market") . '"' : "";

   print Template("htmltop", currtime=>"Generated $currtime", market=>$market);
   foreach my $test (sort {$a->{order} <=> $b->{order}} values %{$TESTS})
      {
      if (scalar @{$test->{results}})
         {
         print Template("htmlsectiontop", %{$test});
         my $ct = 0;
         foreach my $result (@{$test->{results}})
            {
            last if $ct++ >= $test->{maxresults};
            my $acct = substr($result->{invnum}, 0, 10);
            print Template("htmlresulttop", %{$result}, acct=>$acct);
            map {print Template("htmlshow", show=>$_)} @{$result->{shows}};
            print Template("htmlresultbottom");
            }
         print Template("htmlsectionbottom", %{$test});
         }
      }
   print Template("htmlbottom");
   }


sub GenTextOutput
   {
   my $globalmax = ArgGet("maxresults") || 0;

   foreach my $name (sort {$TESTS->{$a}->{order} <=> $TESTS->{$b}->{order}} keys %{$TESTS})
      {
      my $test = $TESTS->{$name};
      if (scalar @{$test->{results}})
         {
         print "test:$name  $test->{label}\n";
         my $i=1;
         my $ct = 0;
         foreach my $result (@{$test->{results}})
            {
            last if $ct++ >= ($globalmax || $test->{maxresults});
            print "" . sprintf("%02d", $i++) . ": $result->{invnum}";
            map {print " [$_]"} @{$result->{shows}};
            print "\n";
            }
         print "\n";
         }
      }

   }


sub DumpTests
   {
   print "Dumping tests:\n";

   foreach my $test (sort {$a->{order} <=> $b->{order}} values %{$TESTS})
      {
      print "TEST: $test->{label} [$test->{order}]\n";
      map {print "macro: $_ = $test->{macros}->{$_}\n"} sort keys %{$test->{macros}};
      map {print "match: " . ($_->{cond} ? "   $_->{xpath}, $_->{cond}, $_->{val}\n" : "$_->{xpath}\n")} @{$test->{matches}};
      print "cond: $test->{condexpr}\n" if $test->{condexpr};
      print "\n";
      }
   }

__DATA__

[usage]
InvoiceScanner  -  Scan invoices for specfic conditions

USAGE: InvoiceScanner [options] files
   -or-
USAGE: InvoiceScanner [options] -db

This Utility can scan either the database or local files for matching invoices

Database specific options:
   -db .............. Use the local database (default is files)
   -all ............. Use all invoices
   -allrecent ....... Migrate newest invoice record from every available.
   -recent .......... Use invoices from the most recent date (default)
   -date=date ....... Use invoices generated on this date
   -since=date ...... Use invoices generated on this date or later
   -showdates ....... Show what generated dates are available to scan

Local file specific options:
   files ............ One or more files to scan. Wildcards ok

Common options:
   -market=GA ....... Only include invoices from this market
   -test=testname ... The test to run (default is all tests)
   -debug ........... Include debug output
   -html ............ Produce results in html formal (default is text)
   -text ............ Produce results in text formal (default)
   -help ............ This help

CONFIG:
   The file InvoiceScanner.cfg defines the tests. See the top of that
   file for documentation on defininmg tests

Examples if scanning local xml files:
   InvoiceScanner *.xml
   InvoiceScanner -market=FL -html *.xml > fl-scan.html
   InvoiceScanner -test=123 xml\*.xml
   InvoiceScanner -test=Advance -test:Test04 xml\*.xml
   InvoiceScanner -html xml\*.xml > scanindex.html

Examples if scanning invoices in the local database:
   InvoiceScanner -db
   InvoiceScanner -db -recent
   InvoiceScanner -db -date=2019-11-29 -test=DDDC
   InvoiceScanner -db -market=GA -html > scanindex.html
   InvoiceScanner -db -html > scanindex.html

[htmltop]
<!DOCTYPE html>
<html>
   <head>
      <meta charset="utf-8" />
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
      <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1" />
      <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate" />
      <meta http-equiv="Pragma" content="no-cache" />
      <meta http-equiv="Expires" content="0" />
      <link href="scan.css" rel="stylesheet">
      <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"></script>
      <script src="scan.js"></script>
      <title>Invoice Scan Results</title>
   </head>
   <body>
      <div class="header">
         <a href="/invoices">
            <div class="logo">
               <span class="I">I</span><span class="E">E</span>
            </div>
         </a>
         <h1>Invoice Scan Results</h1>
         <h2>Invoices matching search criteria $market</h2>
         <div class="doctemplate">$currtime</div>
      </div>
      <div class="content">
         <div class="left">
            <div class="card">
               <div class="showfeedback">
                  <input type="checkbox" name="all">Show Feedback
               </div>
               <div class="showall">
                  <input type="checkbox" name="all">Show All
               </div>
[htmlbottom]
            </div>
         </div>
         <div class="right">
            <iframe src="javascript:0;" />
         </div>
      </div>
   </body>
</html>
[htmlsectiontop]
            <div class="test" data-name="$name">
               <h2>test:$name  $label</h2>
[htmlsectionbottom0]
            </div>
[htmlsectionbottom]
               <div class="statusinfo">
                  <div class="statusinforow">
                     <span>Billing Dept:</span>
                     <input type="radio" name="billing_$name" value="0" checked> Unknown
                     <input type="radio" name="billing_$name" value="1">         OK
                     <input type="radio" name="billing_$name" value="2">         Problem
                  </div>
                  <div class="statusinforow">
                     <span>Marketing Dept:</span>
                     <input type="radio" name="marketing_$name" value="0" checked> Unknown
                     <input type="radio" name="marketing_$name" value="1">         OK
                     <input type="radio" name="marketing_$name" value="2">         Problem
                  </div>
                  <div class="statusinforow">
                     <span>Customer Care:</span>
                     <input type="radio" name="customer_$name" value="0" checked> Unknown
                     <input type="radio" name="customer_$name" value="1">         OK
                     <input type="radio" name="customer_$name" value="2">         Problem
                  </div>
                  <div class="statusinforow">
                     <span>Developers:</span>
                     <input type="radio" name="dev_$name" value="0" checked> Unknown
                     <input type="radio" name="dev_$name" value="1">         OK
                     <input type="radio" name="dev_$name" value="2">         Problem
                  </div>
                  <div class="statustext">
                     <textarea rows=5 placeholder="Enter notes here"></textarea>
                  </div>
               </div>
            </div>
[htmlresulttop]
               <div class="result">
                  <a href="https://adept.$env.gainesville.infiniteenergy.com/adept/accountmain.aspx?a=$acct" class="acct" target="_blank">$invnum</a>
                  <a href="/invoices/samples/$invnum.pdf" target="_blank">PDF</a>
                  <a href="/invoices/invoice.html?url=/cgi-bin/preview.pl/invoice/$invnum" target="_blank">Preview</a>
                  <a href="/cgi-bin/preview.pl/invoice/$invnum" target="_blank">XML</a>
[htmlresultbottom]
               </div>
[htmlshow]
                  <span>($show)</span>
[fini]
