package HTML::Tabulate;

use 5.005;
use Carp;
use URI::Escape;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(&render);

$VERSION = '0.16';
my %DEFAULT_DEFN = (
    style => 'down', 
    table => {},
    field_attr => { -defaults => {}, },
);
my %VALID_ARG = (
    table => 'HASH/SCALAR',
    tr => 'HASH', 
    thtr => 'HASH',
    th => 'HASH',
    td => 'HASH',
    fields => 'ARRAY',
    fields_add => 'HASH',
    fields_omit => 'ARRAY',
    in_fields => 'ARRAY',
    labels => 'SCALAR/HASH',
    label_links => 'HASH',
    stripe => 'ARRAY/SCALAR/HASH',
    null => 'SCALAR',
    trim => 'SCALAR',
    style => 'SCALAR',
#   limit => 'SCALAR',
#   output => 'SCALAR',
#   first => 'SCALAR',
#   last => 'SCALAR',
    field_attr => 'HASH',
    # xhtml: boolean indicating whether to use xhtml-style tagging
    xhtml => 'SCALAR',
);
my %VALID_FIELDS = (
    -defaults => 'HASH',
);
my %FIELD_ATTR = (
    escape => 'SCALAR',
    value => 'SCALAR/CODE',
    format => 'SCALAR/CODE',
    link => 'SCALAR/CODE',
    label => 'SCALAR/CODE',
    label_link => 'SCALAR/CODE',
);
my $URI_ESCAPE_CHARS = "^A-Za-z0-9\-_.!~*'()?&;:/=";

# -------------------------------------------------------------------------
# Provided for subclassing
sub get_valid_arg
{
    return wantarray ? %VALID_ARG : \%VALID_ARG;
}

# Provided for subclassing
sub get_valid_fields
{
    return wantarray ? %VALID_FIELDS : \%VALID_FIELDS;
}

# Provided for subclassing
sub get_field_attributes
{
    return wantarray ? %FIELD_ATTR : \%FIELD_ATTR;
}

#
# Check $self->{defn} for invalid arguments or types
#
sub check_valid
{
    my ($self, $defn) = @_;

    # Check top-level args
    my %valid = $self->get_valid_arg();
    my (@invalid, @badtype);
    for (sort keys %$defn) {
        if (! exists $valid{$_}) {
            push @invalid, $_;
            next;
        }
        my $type = ref $defn->{$_};
        push @badtype, $_ 
            if $type && $type ne 'SCALAR' && $valid{$_} !~ m/$type/;
        push @badtype, $_ 
            if ! $type && $valid{$_} !~ m/SCALAR/;
    }
    croak "[check_valid] invalid argument found: " . join(',',@invalid) 
        if @invalid;
    croak "[check_valid] invalid types for argument: " . join(',',@badtype)
        if @badtype;

    # Check special fields
    %valid = $self->get_valid_fields();
    @invalid = ();
    @badtype = ();
    for (sort grep(/^-/, keys(%{$defn->{field_attr}})) ) {
        if (! exists $valid{$_}) {
            push @invalid, $_;
            next;
        }
        my $type = ref $defn->{field_attr}->{$_};
        push @badtype, $_ 
            if $type && $type ne 'SCALAR' && $valid{$_} !~ m/$type/;
        push @badtype, $_ 
            if ! $type && $valid{$_} !~ m/SCALAR/;
    }
    croak "[check_valid] invalid field argument found: " . join(',',@invalid) 
        if @invalid;
    croak "[check_valid] invalid types for field argument: " . join(',',@badtype)
        if @badtype;

    # Check field attributes
    $self->{field_attr} ||= $self->get_field_attributes();
    %valid = %{$self->{field_attr}};
    @badtype = ();
    for my $field (keys %{$defn->{field_attr}}) {
        croak "[check_valid] invalid field argument entry '$field': " . 
            $defn->{field_attr}->{$field} 
                if ref $defn->{field_attr}->{$field} ne 'HASH';
        for (sort keys %{$defn->{field_attr}->{$field}}) {
            next if ! exists $valid{$_};
            next if ! $valid{$_};
            my $type = ref $defn->{field_attr}->{$field}->{$_};
            if (! ref $valid{$_}) {
                push @badtype, $_ 
                    if $type && $type ne 'SCALAR' && $valid{$_} !~ m/$type/;
                push @badtype, $_ 
                    if ! $type && $valid{$_} !~ m/SCALAR/;
            }
            elsif (ref $valid{$_} eq 'ARRAY') {
                if ($type) {
                    push @badtype, $_;
                }
                else {
                    my $val = $defn->{field_attr}->{$field}->{$_};
                    push @badtype, "$_ ($val)" if ! grep /^$val$/, @{$valid{$_}};
                }
            }
            else {
                croak "[check_valid] invalid field attribute entry for '$_': " . 
                    ref $valid{$_};
            }
        }
        croak "[check_valid] invalid type for '$field' field attribute: " . 
            join(',',@badtype) if @badtype;
    }
}

#
# Merge $hash1 and $hash2 together, returning the result (or, in void 
#   context, merging into $self->{defn}). Performs a shallow (one-level deep)
#   hash merge unless the field is defined in the @recurse_keys array, in 
#   which case we do a full recursive merge.
#
sub merge
{
    my $self = shift;
    my $hash1 = shift || {};
    my $hash2 = shift;
    my $arg = shift;

    croak "[merge] invalid hash1 '$hash1'" if ref $hash1 ne 'HASH';
    croak "[merge] invalid hash2 '$hash2'" if $hash2 && ref $hash2 ne 'HASH';

    my $single_arg = ! $hash2;

    # Use $self->{defn} as $hash1 if only one argument
    if ($single_arg) {
        $hash2 = $hash1;
        $hash1 = $self->{defn};
    }

    # Check hash2 for valid args (except when recursive)
    my $sub = (caller(1))[3] || '';
    $self->check_valid($hash2) unless substr($sub, -7) eq '::merge';

    my $merge = $self->deepcopy($hash1);

    # Add hash2 to $merge 
    my @recurse_keys = qw(field_attr);
    for my $key (keys %$hash2) {
        # If this value is a hashref on both sides, do a shallow hash merge
        #   unless we need to do a proper recursive merge
        if (ref $hash2->{$key} eq 'HASH' && ref $merge->{$key} eq 'HASH') {
            # Recursive merge
            if (grep /^$key$/, @recurse_keys) {
                $merge->{$key} = $self->merge($hash1->{$key}, $hash2->{$key});
            }
            # Shallow hash merge
            else {
                @{$merge->{$key}}{ keys %{$hash1->{$key}}, keys %{$hash2->{$key}} } = (values %{$hash1->{$key}}, values %{$hash2->{$key}});
            }
        }
        # Otherwise (scalars, arrayrefs etc) just copy the value
        else {
            $merge->{$key} = $hash2->{$key};
        }
    }

    # In void context update $self->{defn}
    if (! defined wantarray) {
        $self->{defn} = $merge;
        # Must invalidate transient $self->{defn_t} when $self->{defn} changes
        delete $self->{defn_t} if exists $self->{defn_t};
    }
    else {
        return $merge 
    }
}

sub defn
{
    my $self = shift;
    return $self->{defn};
}

# Initialisation
sub init
{
    my $self = shift;
    my $defn = shift || {};
    croak "[init] invalid defn '$defn'" if $defn && ref $defn ne 'HASH';

    # Map $defn table => 1 to table => {} for cleaner merging
    $defn->{table} = {} if $defn->{table} && ! ref $defn->{table};

    # Initialise $self->{defn} by merging defaults and $defn
    $self->{defn} = $self->merge(\%DEFAULT_DEFN, $defn);

    return $self;
}

sub new 
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
}

# -------------------------------------------------------------------------
#
# If deriving field names, also derive labels (if not already defined)
#
sub derive_label
{
    my ($self, $field) = @_;
    $field =~ s/_+/ /g;
    $field = join ' ', map { ucfirst($_) } split(/\s+/, $field);
    $field =~ s/(Id)$/\U$1/;
    return $field;
}

#
# Try and derive a reasonable field list from $self->{defn_t} using the set data.
#   Croaks on failure.
#
sub derive_fields
{
    my ($self, $set) = @_;
    my $defn = $self->{defn_t};

    # For iterators, prefetch the first row and use its keys
    if (ref $set && UNIVERSAL::isa($set,'UNIVERSAL') &&
            $set->can('First') && $set->can('Next')) {
        my $row = $set->First;
        $self->{prefetch} = $row;
        $defn->{fields} = [ sort keys %$row ] if eval { keys %$row };
    }
    elsif (ref $set && UNIVERSAL::isa($set,'UNIVERSAL') &&
            $set->can('first') && $set->can('next')) {
        my $row = $set->first;
        $self->{prefetch} = $row;
        $defn->{fields} = [ sort keys %$row ] if eval { keys %$row };
    }
    # For arrays
    elsif (ref $set eq 'ARRAY') {
        if (! @$set) {
            $defn->{fields} = [];
            return;
        }
        my $obj = $set->[0];
        # Arrayref of hashrefs
        if (ref $obj eq 'HASH') {
            $defn->{fields} = [ sort keys %$obj ];
        }
        # Arrayref of arrayrefs - access via subscripts unless labels are defined
        elsif (ref $obj eq 'ARRAY') {
            if ($defn->{labels}) {
                croak "[derive_fields] no fields found and cannot derive fields from data arrayrefs";
            }
            # Arrayref of arrayrefs, labels off
            else {
                $defn->{fields} = [ 0 .. $#$obj ];
            }
        }
        # For Class::DBI objects, derive via columns groups
        elsif ($obj->isa('Class::DBI')) {
            my @col = $obj->columns('Tabulate');
            @col = ( $obj->columns('Essential'), $obj->columns('Others') ) 
                if ! @col && $obj->columns('Essential');
            @col = $obj->columns('All') if ! @col;
            $defn->{fields} = [ @col ] if @col;
        }
        # If all else fails, try treating as a hash
        unless (ref $defn->{fields} && @{$defn->{fields}}) {
            if (! defined eval { $defn->{fields} = [ sort keys %$obj ] }) {
                croak "[derive_fields] no fields found and initial object '$obj' is strange type";
            }
        }
    }
    # Else looks like a single object - check for Class::DBI
    elsif (ref $set && ref $set ne 'HASH' && $set->isa('Class::DBI')) {
        my @col = $set->columns('Tabulate');
        @col = ( $set->columns('Essential'), $set->columns('Others') ) 
            if ! @col && $set->columns('Essential');
        @col = $set->columns('All') if ! @col;
        $defn->{fields} = [ @col ] if @col;
    }
    # Otherwise try treating as a hash
    elsif (defined eval { keys %$set }) {
        my $first = (sort keys %$set)[0];
        # Check whether first value is reference
        if (my $ref = ref $set->{$first}) {
            # Hashref of hashrefs
            if ($ref eq 'HASH') {
                $defn->{fields} = [ sort keys %{$set->{$first}} ];
            }
            elsif (ref $set->[0] ne 'ARRAY') {
                croak "[derive_fields] no fields found and first row '" . $set->[0] . "' is strange type";
            }
            # Hashref of arrayrefs - fatal only if labels => 1
            elsif ($defn->{labels}) {
                croak "[derive_fields] no fields found and cannot derive fields from data arrayrefs";
            }
            # Hashref of arrayrefs, labels off
            else {
                $defn->{fields} = [ 0 .. $#{$set->[$first]} ];
            }
        }
        else {
            $defn->{fields} = [ sort keys %$set ];
        }
    }
    else {
        croak "[derive_fields] no fields found and set '$set' is strange type: $@";
    }
    
    croak sprintf "[derive_fields] field derivation failed (fields: %s)", 
            $defn->{fields} 
        unless ref $defn->{fields} eq 'ARRAY';
}

# Splice additional fields into the fields array
sub splice_fields
{
    my $self = shift;
    my $defn = $self->{defn_t};
    my $add = $defn->{fields_add};
    return unless ref $defn->{fields} eq 'ARRAY' && ref $add eq 'HASH';

    for (my $i = $#{$defn->{fields}}; $i >= 0; $i--) {
        my $f = $defn->{fields}->[$i];
        next unless $add->{$f};
        if (ref $add->{$f} eq 'ARRAY') {
            splice @{$defn->{fields}}, $i+1, 0, @{$add->{$f}};
        }
        else {
            splice @{$defn->{fields}}, $i+1, 0, $add->{$f};
        }
    }
}

# Omit/remove fields from the fields array
sub omit_fields
{
    my $self = shift;
    my $defn = $self->{defn_t};
    my %omit = map { $_ => 1 } @{$defn->{fields_omit}};
    $defn->{fields} = [ grep { ! exists $omit{$_} } @{$defn->{fields}} ];
}

#
# Deep copy routine, originally swiped from a Randal Schwartz column
#
sub deepcopy 
{
    my ($self, $this) = @_;
    if (! ref $this) {
        return $this;
    } elsif (ref $this eq "ARRAY") {
        return [map $self->deepcopy($_), @$this];
    } elsif (ref $this eq "HASH") {
        return {map { $_ => $self->deepcopy($this->{$_}) } keys %$this};
    } elsif (ref $this eq "CODE") {
        return $this;
    } elsif (sprintf $this) {
        # Object! As a last resort, try copying the stringification value
        return sprintf $this;
    } else {
        die "what type is $_? (" . ref($this) . ")";
    }
}

#
# Create a transient presentation definition (defn_t) by doing a set of one-off 
#   or dataset-specific mappings on the current table definition e.g. deriving 
#   a field list if none is set, setting up a field map for arrayref-of-
#   arrayref sets, and mapping top-level shortcuts into their field 
#   attribute equivalents.
#
sub prerender_munge
{
    my $self = shift;
    my ($set, $defn) = @_;

    # Use $self->{defn} if $defn not passed
    $defn ||= $self->{defn};

    # If already done, return unless we require any dataset-specific mappings
#   if ($self->{defn_t}) {
#       return unless 
#           ref $defn->{fields} ne 'ARRAY' || 
#           ! @{$defn->{fields}} ||
#           (ref $set eq 'ARRAY' && @$set && ref $set->[0] eq 'ARRAY');
#   }

    # Copy $defn to $self->{defn_t}
    $self->{defn_t} = $self->deepcopy($defn);
    my $defn_t = $self->{defn_t};

    # Try to derive field list if not set
    $self->derive_fields($set) 
        if ref $defn_t->{fields} ne 'ARRAY' || ! @{$defn_t->{fields}};

    # Set up a field map for arrayref-of-arrayref sets
    my $pos = 0;
    my $fields = ref $defn_t->{in_fields} eq 'ARRAY' ? $defn_t->{in_fields} : $defn_t->{fields};
    $defn_t->{field_map} = { map  { $_ => $pos++; } @$fields }
        if ref $set eq 'ARRAY' && @$set && ref $set->[0] eq 'ARRAY';

    # Splice any additional fields into the fields array
    $self->splice_fields if $defn_t->{fields_add};
    $self->omit_fields if $defn_t->{fields_omit};

    # Map top-level 'labels' and 'label_links' hashrefs into fields
    if (ref $defn_t->{labels} eq 'HASH') {
        for (keys %{$defn_t->{labels}}) {
            $defn_t->{field_attr}->{$_} ||= {};
            $defn_t->{field_attr}->{$_}->{label} = $defn_t->{labels}->{$_};
        }
    }
    if (ref $defn_t->{label_links} eq 'HASH') {
        for (keys %{$defn_t->{label_links}}) {
            $defn_t->{field_attr}->{$_} ||= {};
            $defn_t->{field_attr}->{$_}->{label_link} = $defn_t->{label_links}->{$_};
        }
    }

    # If style across, map top-level 'thtr' hashref into -defaults label_ attributes
    if ($self->{defn_t}->{style} eq 'across' && ref $defn_t->{thtr} eq 'HASH') {
        for (keys %{$defn_t->{thtr}}) {
            $defn_t->{field_attr}->{-defaults}->{"label_$_"} = $defn_t->{thtr}->{$_}
                if ! exists $defn_t->{field_attr}->{-defaults}->{"label_$_"};
        }
    }
    # Map top-level 'th' hashref into -defaults label_ attributes
    if (ref $defn_t->{th} eq 'HASH') {
        for (keys %{$defn_t->{th}}) {
            $defn_t->{field_attr}->{-defaults}->{"label_$_"} = $defn_t->{th}->{$_}
                if ! exists $defn_t->{field_attr}->{-defaults}->{"label_$_"};
        }
    }
    # Map top-level 'td' hashref into -defaults
    if (ref $defn_t->{td} eq 'HASH') {
        $defn_t->{field_attr}->{-defaults} = { %{$defn_t->{td}}, %{$defn_t->{field_attr}->{-defaults}} };
    }

    # Move regex field_attr definitions into a -regex hash
    $defn_t->{field_attr}->{-regex} = {};
    for (keys %{$defn_t->{field_attr}}) {
        # The following test is an ugly hack, but the regex is stringified now
        next unless m/^\(\?.*\)$/;
        $defn_t->{field_attr}->{-regex}->{$_} = $defn_t->{field_attr}->{$_};
        delete $defn_t->{field_attr}->{$_};
    }

    # Force a non-array stripe to be a binary array
    if ($defn_t->{stripe} && ref $defn_t->{stripe} ne 'ARRAY') {
        $defn_t->{stripe} = [ undef, $defn_t->{stripe} ];
    }
}

# -------------------------------------------------------------------------
#
# Return the given HTML $tag with attributes from the $attr hashref.
#   An attribute with a non-empty value (i.e. not '' or undef) is rendered
#   attr="value"; one with a value of '' is rendered as a 'bare' attribute
#   (i.e. no '='), or as attr="attr" if in xhtml mode; one with undef is 
#   simply ignored (allowing unset CGI parameters to be ignored).
#
sub start_tag
{
    my ($self, $tag, $attr, $close) = @_;
    my $xhtml = $self->{defn_t}->{xhtml};
    my $str = "<$tag";
    if (ref $attr eq 'HASH') {
        for my $a (sort keys %$attr) {
            if ($attr->{$a} ne '') {
                $str .= qq( $a="$attr->{$a}");
            }
            elsif (defined $attr->{$a}) {
                $str .= $xhtml ? qq( $a="$a") : qq( $a);
            }
        }
    }
    $str .= ' /' if $close && $xhtml;
    $str .= ">";
    return $str;
}

sub end_tag
{
    my ($self, $tag) = @_;
    return "</$tag>";
}

# Provided for subclassing
sub start_table 
{
    my ($self) = @_;
    return '' if exists $self->{defn_t}->{table} && ! $self->{defn_t}->{table};
    return $self->start_tag('table',$self->{defn_t}->{table}) . "\n";
}

# Provided for subclassing
sub end_table 
{
    my ($self) = @_;
    return '' if exists $self->{defn_t}->{table} && ! $self->{defn_t}->{table};
    return $self->end_tag('table') . "\n";
}

#
# Format the given data item using formatting field attributes (e.g. format, 
#   link, escape etc.)
#
sub cell_format
{
    my ($self, $data, $fattr, $row, $field) = @_;
    my $data_in = $data;

    # 'format' subroutine or sprintf pattern
    if ($fattr->{format}) {
        my $ref = ref $fattr->{format};
        croak "[cell_format] invalid '$field' format: $ref"
            if $ref && $ref ne 'CODE';
        $data = &{$fattr->{format}}($data, $row || {}) if $ref eq 'CODE';
        $data = sprintf $fattr->{format}, $data if ! $ref;
    }

    # 'escape' boolean for simple tag escaping (defaults to on)
    if ($fattr->{escape} || ! exists $fattr->{escape}) {
        $data =~ s/</&lt;/g;
        $data =~ s/>/&gt;/g;
    }

    # 'link' subroutine or sprintf pattern
    if ($fattr->{link}) {
        my $ldata;
        my $ref = ref $fattr->{link};
        croak "[cell_format] invalid '$field' link: $ref"
            if $ref && $ref ne 'CODE';
        $ldata = &{$fattr->{link}}($data_in, $row || {}) if $ref eq 'CODE';
        $ldata = sprintf $fattr->{link}, $data_in if ! $ref;
        $data = sprintf qq(<a href="%s">%s</a>), 
            uri_escape($ldata, $URI_ESCAPE_CHARS), $data;
    }

    return $data;
}

sub label
{
    my ($self, $label, $field) = @_;

    # Use first label if arrayref
    my $l;
    if (ref $label eq 'CODE') {
        $l = $label->($field);
    }
    else {
        $l = $label;
    }
    $l ||= $self->derive_label($field);
    return $l;
}

#
# Add in any extra (conditional) defaults for this field. 
# Provided for subclassing.
#
sub cell_merge_extras
{
    return ();
}

#
# Merge default and field attributes once each for labels and data
#
sub cell_merge_defaults
{
    my ($self, $row, $field) = @_;
    $self->{defn_t}->{field_attr}->{$field} ||= {};

    # Create a temp $fattr hash merging defaults, regexes, and field attrs
    my $fattr = { %{$self->{defn_t}->{field_attr}->{-defaults}},
                  $self->cell_merge_extras($row, $field) };
    for my $regex (sort keys %{$self->{defn_t}->{field_attr}->{-regex}}) {
        next unless $field =~ $regex;
        @$fattr{ keys %{$self->{defn_t}->{field_attr}->{-regex}->{$regex}} } = 
            values %{$self->{defn_t}->{field_attr}->{-regex}->{$regex}};
    }
    @$fattr{ keys %{$self->{defn_t}->{field_attr}->{$field}} } = 
        values %{$self->{defn_t}->{field_attr}->{$field}};
   
    # For labels, keep only label_ attributes
    if (! defined $row) {
        my $fattr_l = {};
        for (keys %$fattr) {
            next if substr($_,0,6) ne 'label_';
            $fattr_l->{substr($_,6)} = $fattr->{$_};
        }

        # Set 'value' from 'label'
        $fattr_l->{value} = $self->label($fattr->{label}, $field);
        # Update fattr
        $fattr = $fattr_l;
    }

    # For data, merge defaults and the field attributes, discarding label_ ones
    else {
        # Remove all label_ attributes
        for (keys %$fattr) { delete $fattr->{$_} if substr($_,0,6) eq 'label_'; }
    }

    # Create tx_attr by removing all $fattr attributes in $field_attr
    my %tx_attr = %$fattr;
    for (keys %tx_attr) { delete $tx_attr{$_} if exists $self->{field_attr}->{$_} }

    # If data, save for subsequent rows
    if ($row) {
        $fattr->{td_attr} = \%tx_attr;
        $self->{defn_t}->{field_attr}->{$field} = $fattr;
    }

    return ($fattr, \%tx_attr);
}

#
# Set and format the data for a single (data) cell or item
#
sub cell_content
{
    my ($self, $row, $field, $fattr) = @_;
    my $defn = $self->{defn_t};

    # Get value from $row
    my $value;
    if (ref $row eq 'ARRAY') {
        my $i = keys %{$defn->{field_map}} ? $defn->{field_map}->{$field} : $field;
        $value = $row->[ $i ] if defined $i;
    }
    elsif (ref $row) {
        $value = $row->{$field};
    }
    # 'value' literal or subref takes precedence over row
    if ($fattr->{value}) {
        my $ref = ref $fattr->{value};
        if (! $ref) {
            # $value = sprintf $fattr->{value}, $value;
            $value = $fattr->{value};
        }
        elsif ($ref eq 'CODE') {
            $value = &{$fattr->{value}}($value, $row);
        }
        else {
            croak "[cell_content] invalid '$field' value: $ref";
        };
    }

    # Format
    my $fvalue = $value;
    $fvalue = '' if ! defined $fvalue;
    $fvalue =~ s/^\s*(.*?)\s*$/$1/ if $defn->{trim};
    $fvalue = $self->cell_format($fvalue, $fattr, $row, $field) if $fvalue ne '';
    $fvalue = $defn->{null} 
        if defined $defn->{null} && $fvalue eq '';

    return wantarray ? ($fvalue, $value) : $fvalue;
}

#
# Wrap cell in <th> or <td> table tags
#
sub cell_tags 
{
    my ($self, $data, $row, $field, $tx_attr) = @_;

    my $tag = ! defined $row ? 'th' : 'td';
    return $self->start_tag($tag, $tx_attr) . $data . $self->end_tag($tag);
}

#
# Render a single table cell or item
#
sub cell 
{
    my ($self, $row, $field) = @_;
    my ($fattr, $tx_attr);

    # Merge default and field attributes first time through (labels + data)
    if (! defined $row || ! $self->{defn_t}->{field_attr}->{$field}->{td_attr}) {
        ($fattr, $tx_attr) = $self->cell_merge_defaults($row, $field);
    }
    else {
        $fattr = $self->{defn_t}->{field_attr}->{$field};
        $tx_attr = $self->{defn_t}->{field_attr}->{$field}->{td_attr};
    }

    # Generate output
    my $out = $self->cell_content($row, $field, $fattr);
    return $self->cell_tags($out, $row, $field, $tx_attr);
}

#
# Modify the $tr hashref for striping. If $type is 'SCALAR', the stripe is
#   a HTML colour string for a bgcolor attribute for the relevant row; if
#   $type is 'HASH' the stripe is a set of attributes to be merged.
#   $stripe has already been coerced to an arrayref if something else.
#
sub stripe
{
    my ($self, $tr, $rownum, $stripe, $type) = @_;
    return if $stripe eq '' || ref $tr ne 'HASH';
             
    my $r = int($rownum % scalar(@$stripe)) - 1;
    if (defined $stripe->[$r]) {
        if (! ref $stripe->[$r]) {
            # Set bgcolor to stripe (exception: header where bgcolor already set)
            $tr->{bgcolor} = $stripe->[$r]
                unless $rownum == 0 && exists $tr->{bgcolor};
        }
        elsif (ref $stripe->[$r] eq 'HASH') {
            # Existing attributes take precedence over stripe ones for header
            if ($rownum == 0) {
                for (keys %{$stripe->[$r]}) {
                    $tr->{$_} = $stripe->[$r]->{$_} unless exists $tr->{$_};
                }
            }
            # For non-header rows, merge attributes straight into $tr
            else {
                @$tr{keys %{$stripe->[$r]}} = values %{$stripe->[$r]};
            }
        }
        # Else silently ignore
    }
}

#
# Render a single table row (style 'down')
#
sub row_down 
{
    my ($self, $row, $rownum) = @_;
    my $defn_t = $self->{defn_t};

    # Table striping
    $defn_t->{tr} = {} unless ref $defn_t->{tr} eq 'HASH';
    my $tr;
    if ($rownum == 0) {
        $tr = $defn_t->{thtr};
        $tr = $self->deepcopy($defn_t->{tr_base})
            unless $tr;
    }
    else {
        $tr = $self->deepcopy($defn_t->{tr});
    }
    $self->stripe($tr, $rownum, $defn_t->{stripe}, $defn_t->{stripe_type}) 
        if $defn_t->{stripe};

    # Render row into $out
    my $out = '';
    $out .= $self->start_tag('tr', $tr);
    for my $f (@{$defn_t->{fields}}) {
        # Labels/headings
        if ($rownum == 0) {
            $out .= $self->cell(undef, $f);
        }
        # Data
        else {
            $out .= $self->cell($row, $f);
        }
    }
    $out .= $self->end_tag('tr');
    $out .= "\n";
}

#
# Render the table body with successive records down the page
#
sub body_down 
{
    my ($self, $set) = @_;
    my $body = '';

    # Labels/headings
    my @fields = @{$self->{defn_t}->{fields}} 
        if ref $self->{defn_t}->{fields} eq 'ARRAY';
    if ($self->{defn_t}->{labels} && @fields) {
        $body .= $self->row_down(undef, 0);
    }

    # Data
    my $r = 1;
    my $row;
    if (ref $set && UNIVERSAL::isa($set,'UNIVERSAL') &&
            $set->can('First') && $set->can('Next')) {
        $row = $self->{prefetch} || $set->First;
        do {
            $body .= $self->row_down($row, $r);
            $r++;
        } while ($row = $set->Next);
    }
    elsif (ref $set && UNIVERSAL::isa($set,'UNIVERSAL') &&
            $set->can('first') && $set->can('next')) {
        $row = $self->{prefetch} || $set->first;
        do {
            $body .= $self->row_down($row, $r);
            $r++;
        } while ($row = $set->next);
    }
    elsif (ref $set eq 'ARRAY') {
        for my $row (@$set) {
            $body .= $self->row_down($row, $r);
            $r++;
        }
    }
    elsif (ref $set eq 'HASH' || eval { keys %$set }) {
        # Check first value - drill down further unless non-reference
        my $k = $fields[0] || (sort keys %$set)[0];
        if (! ref $set->{$k}) {
            $body .= $self->row_down($set, $r);
            $r++;
        }
        else {
            for $k (sort keys %$set) {
                $body .= $self->row_down($set->{$k}, $r);
                $r++;
            }
        }
    }
    else {
        croak "invalid Tabulate data type '$set'";
    }

    return $body;
}

#
# Render a single table row (style 'across')
#
sub row_across
{
    my ($self, $data, $rownum, $field) = @_;
    my $defn_t = $self->{defn_t};
    my $tr = $defn_t->{tr} || {};

    # Begin row
    $self->stripe($tr, $rownum, $defn_t->{stripe}, $defn_t->{stripe_type}) 
        if $defn_t->{stripe};
    my $body = $self->start_tag('tr', $tr);

    # Label/heading
    $body .= $self->cell(undef, $field) if $defn_t->{labels};

    # Data
    for my $row (@$data) {
        $body .= $self->cell($row, $field);
    }

    # End row
    $rownum++;
    $body .= $self->end_tag('tr', $tr) . "\n";
}

#
# Render the table body with successive records across the page 
#   (i.e. fields down the page)
#
sub body_across 
{
    my ($self, $set) = @_;

    # Fetch the full data set
    my @data = ();
    if (ref $set && UNIVERSAL::isa($set,'UNIVERSAL') &&
            $set->can('First') && $set->can('Next')) {
        my $row = $set->First;
        if (ref $row) {
            do {
                push @data, $row;
            }
            while ($row = $set->Next);
        }
    }
    elsif (ref $set && UNIVERSAL::isa($set,'UNIVERSAL') &&
            $set->can('first') && $set->can('next')) {
        my $row = $set->first;
        if (ref $row) {
            do {
                push @data, $row;
            }
            while ($row = $set->next);
        }
    }
    elsif (ref $set eq 'ARRAY') {
        @data = @$set;
    }
    elsif (ref $set eq 'HASH' || eval { keys %$set }) {
        @data = ( $set );
    }
    else {
        croak "[body_across] invalid Tabulate data type '$set'";
    }

    # Iterate over fields
    my $rownum = 1;
    my $body = '';
    for my $field (@{$self->{defn_t}->{fields}}) {
        $body .= $self->row_across(\@data, $rownum, $field);
    }

    return $body;
}

# -------------------------------------------------------------------------
#
# Render the data set $set using the settings in $self->{defn} + $defn,
#   returning the resulting string.
#
sub render
{
    my ($self, $set, $defn) = @_;
    croak "[render] invalid set '$set'" if ! ref $set;

    # If $self is not blessed, this is a procedural call, $self is $set
    if (ref $self eq 'HASH' || ref $self eq 'ARRAY') {
      $defn = $set;
      $set = $self;
      $self = __PACKAGE__->new($defn);
      undef $defn;
    }

    # If $defn defined, merge with $self->{defn} for this render only
    if (ref $defn eq 'HASH' && keys %$defn) {
        $defn = $self->merge($self->{defn}, $defn);
        $self->prerender_munge($set, $defn);
    }
    else {
        $self->prerender_munge($set);
    }

    # Start table
    my $out = $self->start_table();

    # Style-specific bodies (default is 'down')
    if ($self->{defn_t}->{style} eq 'down') {
        $out .= $self->body_down($set);
    }
    elsif ($self->{defn_t}->{style} eq 'across') {
        $out .= $self->body_across($set);
    }
    else {
        croak "[render] invalid style '$self->{defn_t}->{style}'";
    }

    # End table
    $out .= $self->end_table();

    return $out;
}

1;

__END__

=head1 NAME

HTML::Tabulate - HTML table rendering class


=head1 SYNOPSIS

    use HTML::Tabulate qw(render);

    # Setup a simple table definition hashref
    $table_defn = { 
        table => { border => 0, cellpadding => 0, cellspacing => 3 },
        th => { class => 'foobar' },
        null => '&nbsp;',
        labels => 1,
        stripe => '#cccccc',
    };

    # Render a dataset using this table definition (procedural version)
    print render($dataset, $table_defn);

    # Object-oriented version
    $t = HTML::Tabulate->new($table_defn);
    print $t->render($dataset);

    # Setup some dataset specific settings
    $table_defn2 = {
        fields => [ qw(emp_id name title edit) ],
        field_attr => {
            # format employee ids, add a link to employee page
            emp_id => {
                format => '%-05d',
                link => "emp.html?id=%s",
                align => 'right',
            },
            # upper case employee names
            name => { format => sub { uc(shift) } },
        },
    };

    # Render the table using the original and additional settings
    print $t->render($data, $table_defn2);

=begin HIDE

            # fake an edit column that isn't actually in the data
            edit => {
                value => 'edit',
                link => sub { 
                   ($value, $rec) = @_; 
                   sprintf "edit.html?id=%s&type=%s, 
                     $rec->emp_id, $rec->emp_type;
                },
            },
        },
    };

    # Render the data with some different settings
    print $t->render($data, {
        fields => [ qw(emp_id name) ],
        emp_id => { format => '%-05d' },
        name => {
            value => sub {
                ($name, $rec) = shift;
                sprintf "%s (%s)", $name, $rec->title;
            },
        },
    });

=end HIDE


=head1 DESCRIPTION

HTML::Tabulate is used to render/display a given set of data in an 
HTML table. It takes a data set and a presentation definition and 
applies the presentation to the data set to produce the HTML table 
output. The presentation definition accepts arguments corresponding 
to HTML table tags ('table', 'tr', 'th', 'td' etc.), to define 
attributes for those tags, plus additional arguments for other 
aspects of the presentation. HTML::Tabulate supports advanced 
features like automatic striping, arbitrary cell formatting, 
link creation, etc.

Presentation definitions can be defined in multiple passes, which
are progressively merged, allowing general defaults to be defined
in common and then overridden by more specific requirements. 
Presentation definitions are stored in the current object, except
for those defined for a specific 'render', which are temporary.

Supported data sets include arrayrefs of arrayrefs (DBI 
selectall_arrayref, for example), arrayrefs of hashrefs, a simple 
hashref (producing single row tables), or iterator objects that
support first() and next() methods (like DBIx::Recordset objects or 
Class::DBI iterators). 

By default arrayref-based datasets are interpreted as containing 
successive table rows; a column-based interpretation can be forced 
using style => 'across'.

The primary interface is object-oriented, but a procedural
interface is also available where the extra flexibility of the OO
interface is not required.


=head2 PRESENTATION DEFINITION ARGUMENTS

=over 4

=item table 

Hashref. Elements become attributes on the <table> tag. e.g.
  
  table => { border => 0, cellpadding => 3, align => 'center' }


=item tr

Hashref. Elements become attributes on <tr> tags.


=item thtr

Hashref. Elements become attributes on the <tr> tag of the
label/heading row. (For 'across' style tabels, where labels are
displayed down the page, rather than in a row, thtr elements 
become attributes of the individual <th> tags.)


=item th

Hashref. Elements become attributes on the <th> tags used for 
labels/headings.


=item td

Hashref. Elements become attributes on <td> tags.


=item fields

Arrayref. Defines the order in which fields are to be output for this table,
using the field names from the dataset. e.g.

  fields => [ qw(emp_id emp_name emp_title emp_birth_dt) ]

If 'fields' is not defined at render time and the dataset is not array-based,
HTML::Tabulate will attempt to derive a useful default set from your data, and
croaks if it is not successful. 


=item fields_add

Hashref. Used to define additional fields to be included in the output to 
supplement a default field list, or fields derived from a data object itself.
The keys of the fields_add hashref are existing field names; the values are
scalar values or arrayref lists of values to be inserted into the field
list B<after> the key field. e.g.

  fields_add => {
    emp_name => [ 'emp_givenname', 'emp_surname' ],
    emp_birth_dt => 'edit',
  }

applied to a fields list qw(emp_id emp_name emp_title emp_birth_dt)
produces a composite field list containing:

  qw(emp_id emp_name emp_givenname emp_surname emp_title 
     emp_birth_dt edit)


=item fields_omit

Arrayref. Used to omit fields from the base field list. e.g.

  fields_omit => [ qw(emp_modify_ts emp_create_ts) ]


=item in_fields

Arrayref. Defines the order in which fields are defined in the dataset, if
different to the output order defined in 'fields' above. e.g.

  in_fields => [ qw(emp_id emp_title emp_birth_dt emp_title) ]

Using in_fields only makes sense if the dataset rows are arrayrefs. 


=item style

Scalar, either 'down' (the default), or 'across', to render data 'rows'
as table 'columns'.


=item labels

Scalar (boolean), or hashref (mapping field keys to label/heading values). 
Labels can also be defined using the 'label' attribute argument in per-field
attribute definitions (see 'label' below). e.g.

  # Turn labels on, derived from field names, or defined per-field
  labels => 1


=item label_links

Hashref, mapping field keys to URLs (full URLs or absolute or relative 
paths) to be used as the targets when making the label for that field into 
an HTML link. e.g.

  labels => { emp_id => 'Emp ID' }, 
  label_links => { emp_id => "me.html?order=%s" }

will create a label for the emp_id field of:

  <a href="me.html?order=emp_id">Emp ID</a> 


=item stripe

Scalar, arrayref, or hashref. A scalar or an arrayref of scalars should
be HTML color values. Single scalars are rendered as HTML 'bgcolor' values
on the <tr> tags of alternate rows (i.e. alternating with no bgcolor tag
rows), beginning with the label/header row, if one exists. Multiple 
scalars in an arrayref are rendered as HTML 'bgcolor' values on the <tr> 
tags of successive rows, cycling through the whole array before starting 
at the beginning again. e.g.

  # alternate grey and default bgcolor bands
  stripe => '#999999'             

  # successive red, green, and blue stripes
  stripe => [ '#cc0000', '#00cc00', '#0000cc' ]

Stripes that are hashrefs or an arrayref of hashrefs are rendered as
attributes to the <tr> tags on the rows to which they apply. Similarly
to scalars, single hashrefs are applied to every second <tr> tag, beginning
with the label/header row, while multiple hashrefs in an arrayref are applied
to successive rows, cycling though the array before beginning again. e.g.

  # alternate stripe and default rows
  stripe => { class => 'stripe' }

  # alternating between two stripe classes
  stripe => [ { class => 'stripe1' }, { class => 'stripe2' } ]


=item null

Scalar, defining a string to use in place of any empty data value (undef 
or eq ''). e.g.
  
  # Replace all empty fields with non-breaking spaces
  null => '&nbsp;'

=item trim

Scalar (boolean). If true, leading and trailing whitespace is removed
from data values.

=item field_attr

Hashref, defining per-field attribute definitions. Three kinds of keys are 
supported: the special value '-defaults', used to define defaults for all
fields; qr() regular expresssions, used as defaults if the regex matches
the field name; and simple field names. These are merged in the order
given, allowing defaults to be defined for all fields, overridden for fields
matching particular regexes, and then overridden further per-field. e.g.

  # Align all fields left except timestamps (*_ts)
  field_attr => {
    -defaults => { align => 'left' },
    qr/_ts$/ => { align = 'center' },
    emp_create_ts => { label => 'Created' },
  },

Field attribute arguments are discussed in the following section.

=back


=head2 FIELD ATTRIBUTE ARGUMENTS

=over 4

=item HTML attributes

Any field attribute that does not have a special meaning to HTML::Tabulate
(see the six remaining items in this section) is considered an HTML attribute
and is used with the <td> tag for table cells for this field. e.g.

  field_attr => {
    emp_id => {
      align => 'center',
      class => 'emp_id', 
      valign => 'top',
    }
  }

will cause emp_id table cells to be displayed as:

  <td align="center" class="emp_id" valign="top">

=item value

Scalar or subroutine reference. Used to override or modify the current
data value. If scalar is taken as a literal. If a subroutine reference
is called with two arguments, the data value itself, and the entire
data row. This allows the value to be modified or set either based on
an existing value, or on any other value in the row. e.g.

  # Derive emp_fname from first word of emp_name
  field_attr => {
    emp_fname => { 
      value => sub { 
        ($fn, $row) = @_; 
        if ($row->{emp_name} =~ m/^\s*(\w+)/) { return $1; }
        return '';
      },
    },
    edit => { value => 'edit' },
  }

=item format

Scalar or subroutine reference. Used to format the current data value.
If scalar, is taken as a sprintf pattern, with the current data value
as the single argument. If a subroutine reference, is called in the 
same way as the value subref above i.e. $format->($data_item, $row)

=item link

Scalar or subroutine reference. Used as the link target to make an
HTML link using the current data value. If scalar, the target is taken 
as a sprintf pattern, with the current data value as the single argument. 
If a subroutine reference, is called in the same way as the value subref 
described above i.e. $link->($data_item, $row) e.g.

  field_attr => {
    emp_id => {
      link => 'emp.html?id=%s',
      format => '%05d',
    }
  }

creates a link in the table cell like:

  <a href="emp.html?id=1">00001</a>

Note that links are not created for labels/headings - to do so use the 
separate label_link argument below.


=item label

Scalar or subroutine reference. Defines the label or heading to be used
for this field. If scalar, the value is taken as a literal (cf. 'value'
above). If a subroutine reference is called with the field name as the
only argument (typically only useful for -default or regex-based labels).
Entries in the top-level 'labels' hashref are mapped into per-field
label entries.


=item label_link

Scalar or subroutine reference. Equivalent to the general 'link'
argument above, but used to create link targets only for label/heading 
rows. Scalar values are taken as sprintf patterns; subroutine references
are called with the data item and the row as the two arguments.


=item escape

Boolean (default true). HTML-escapes '<' and '>' characters in data 
values.

=back


=head2 METHODS

HTML::Tabulate has three main public methods:

=over 4

=item new($table_defn)

Takes an optional presentation definition hashref for a table, sanity 
checks it (and croaks on failure), stores the definition, and returns 
a blessed HTML::Tabulate object.

=item merge($table_defn)

Checks the given presentation definition (croaking on failure), and
then merges it with its internal definition, storing the result. This
allows presentation definitions to be created in multiple passes, with
general defaults overridden by more specific requirements.

=item render($dataset, $table_defn)

Takes a dataset and an optional presentation definition, creates a
merged presentation definition from any prior definitions and the
render one, and uses that merged definition to render the given
dataset, returning the HTML table produced. The merged definition
is discarded after the render; only definitions stored by the new()
and merge() methods are persistent across renders.

render() can also be used procedurally if explicitly imported:

  use HTML::Tabulate qw(render);
  print render($dataset, $table_defn);

=back



=head2 DATASETS

HTML::Tabulate supports the following dataset types:

=over 4

=item Simple hashrefs

A simple hashref will generate a one-row table (or one column table 
if style is 'across'). Labels are derived from key names if not 
supplied.

=item Arrayrefs of arrayrefs

An arrayref of arrayrefs will generate a table with one row for 
each contained arrayref (or one column per arrayref if style
is 'across'). Labels cannot be derived from arrayrefs, so they 
must be supplied if required.

=item Arrayrefs of hashrefs

An arrayref of hashrefs will generate a table with one row for
each hashref (or one column per hashref if style is 'across').
Labels are derived from the key names of the first hashref if
not supplied.

=item Arrayrefs of objects

An arrayref containing hash-based objects (i.e. blessed hashrefs)
are treated just like unblessed hashrefs, generating a table with
one row per object. Labels are derived from the key names of the
first object if not supplied.

=item Iterators

Some kinds of iterators (pointer objects used to access the members
of a set) are also supported. If the iterator supports methods called
First() and Next() or first() and next() then HTML::Tabulate will use
those methods to walk the dataset. DBIx::Recordset objects and 
Class::DBI iterators definitely work; beyond those your kilometerage
may vary - please let me know your successes and failures.


=back


=head1 BUGS AND CAVEATS

Probably. Please let me know if you find something going awry.

Is now much bigger and more complicated than was originally envisaged.


=head1 AUTHOR

Gavin Carr <gavin@openfusion.com.au>


=head1 COPYRIGHT

Copyright 2003, Gavin Carr. All Rights Reserved.

This program is free software. You may copy or redistribute it under the 
same terms as perl itself.

=cut

