# Title testing

use Test::More tests => 4;
use HTML::Tabulate 0.20;
use Data::Dumper;
use strict;

# Load result strings
my $test = 't13';
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
  title => 'Current Employees',
});
# print $table, "\n";
is($table, $result{title1}, "title scalar");

$table = $t->render($data, {
  title => { title => 'Current Employees', tag => 'h1', 
    class => 'foo', align => 'center', }
});
# print $table, "\n";
is($table, $result{title2}, "title hashref normal");

$table = $t->render($data, {
  title => { title => 'Current Employees', class => 'label' },
});
# print $table, "\n";
is($table, $result{title3}, "title hashref no tag");

# arch-tag: 4e2868a0-9bc5-415e-b340-ddae9dea4813
$table = $t->render($data, {
  title => { align => 'center', class => 'foo' },
});
# print $table, "\n";
is($table, $result{title4}, "title hashref no-title");

# arch-tag: 4e2868a0-9bc5-415e-b340-ddae9dea4813
