# fields_add testing

use Test::More tests => 1;
use HTML::Tabulate 0.15;
use Data::Dumper;
use strict;

# Load result strings
my $test = 't11';
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

# Render1
my $data = [ [ '123', 'Fred Flintstone', 'CEO', '19710430', ], 
             [ '456', 'Barney Rubble', 'Lackey', '19750808', ],
             [ '789', 'Dino', 'Pet' ] ];
my $t = HTML::Tabulate->new;
my $table = $t->render($data, {
  labels => 1,
  null => '-',
  fields => [ qw(emp_id emp_name emp_title emp_birth_dt) ],
  fields_add => {
    emp_birth_dt => 'edit',
    emp_name => [ qw(emp_givenname emp_surname) ],
  },
  field_attr => {
    emp_surname => {
      value => sub { my ($x,$r) = @_; my $name = $r->[1]; $name =~ s/^\s*\w+\s*//; $name }
    },
    emp_givenname => {
      value => sub { my ($x,$r) = @_; my $name = $r->[1]; $name =~ s/\s.*//; $name }
    },
    edit => {
      value => 'edit',
      link => sub { my ($x,$r) = @_; sprintf 'edit.html?emp_id=%s', $r->[0] },
    }
  },
});
# print $table, "\n";
is($table, $result{render1}, "render1 result ok");

# arch-tag: 78e0b59e-9d03-4472-85bb-39dd445d78dd
