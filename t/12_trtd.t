# tr/td coderef testing

use Test::More tests => 2;
use HTML::Tabulate 0.19;
use Data::Dumper;
use strict;

# Load result strings
my $test = 't12';
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

# tr1
my $data = [ [ '123', 'Fred Flintstone', 'CEO', '19710430', ], 
             [ '456', 'Barney Rubble', 'Lackey', '19750808', ],
             [ '789', 'Dino', 'Pet' ] ];
my $t = HTML::Tabulate->new;
my $table = $t->render($data, {
  fields => [ qw(emp_id emp_name emp_title emp_birth_dt) ],
  tr => sub { my $r = shift; my $name = lc $r->[1]; $name =~ s! .*!!; { class => $name } },
});
# print $table, "\n";
is($table, $result{tr1}, "tr sub");

# td1
$table = $t->render($data, {
  fields => [ qw(emp_id emp_name emp_title emp_birth_dt) ],
  td => { class => 'td' },
  field_attr => {
    emp_id => { class => sub { my $r = shift; reverse $r->[0] } },
    emp_name => { class => sub { my $r = shift; lc $r->[2] eq 'ceo' ? 'red' : 'green' } },
  },
});
# print $table, "\n";
is($table, $result{td1}, "td sub");

# arch-tag: f26ad97a-f2aa-4e19-b5d1-f970146c5038
