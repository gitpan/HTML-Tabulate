# 'caption' testing

use Test::More tests => 6;
use HTML::Tabulate 0.20;
use Data::Dumper;
use strict;

# Load result strings
my $test = 't15';
my %result = ();
$test = "t/$test" if -d "t/$test";
die "missing data dir $test" unless -d $test;
opendir DATADIR, $test or die "can't open directory $test";
for (readdir DATADIR) {
  next if m/^\./;
  open FILE, "<$test/$_" or die "can't read $test/$_";
  { 
    local $/ = undef;
    $result{$_} = <FILE>;
  }
  close FILE;
}
close DATADIR;

my $data = [ [ '123', 'Fred Flintstone', 'CEO', '19710430', ], 
             [ '456', 'Barney Rubble', 'Lackey', '19750808', ],
             [ '789', 'Dino', 'Pet' ] ];
my $t = HTML::Tabulate->new({ 
  fields => [ qw(emp_id emp_name emp_title emp_birth_dt) ],
});
my $table = $t->render($data, {
  caption => 'As at April 2004',
});
# print $table, "\n";
is($table, $result{caption1}, "caption bare");

$table = $t->render($data, {
  caption => 'As at <b>April 2004</b>',
});
# print $table, "\n";
is($table, $result{caption2}, "caption with partial markup");

$table = $t->render($data, {
  caption => '<p>As at April 2004</p>',
});
# print $table, "\n";
is($table, $result{caption1}, "caption tag-wrapped");

$table = $t->render($data, {
  caption => "As at April 2004\n(multiple lines)\nBlah blah blah",
});
# print $table, "\n";
is($table, $result{caption3}, "caption multiline bare");

$table = $t->render($data, {
  caption => "<p>As at April 2004</p>\n<p>(multiple lines)</p>\n",
});
# print $table, "\n";
is($table, $result{caption4}, "caption multiline tag-wrapped");

$table = $t->render($data, {
  title => 'Current Employees',
  text => "One two three four",
  caption => "<p>As at April 2004</p>\n<p>(multiple lines)</p>\n",
});
# print $table, "\n";
is($table, $result{caption5}, "title, text, caption");


# arch-tag: 86e4cb67-7ad2-4d5b-a1a4-2bad8eae6f7f

