package Data::FixedFormat;

use strict;
our $VERSION = "0.02";
1;

package Data::FixedFormat;

sub new {
    my ($class, $layout) = @_;
    my $self;
    if (ref $layout eq "HASH") {
	$self = new Data::FixedFormat::Variants $layout;
    } else {
	$self = { Names=>[], Count=>[], Format=>"" };
	bless $self, $class;
	$self->parse_fields($layout) if $layout;
    }
    return $self;
}

sub parse_fields {
    my ($self,$fmt) = @_;
    foreach my $fld (@$fmt) {
	my ($name, $format, $count) = split ':',$fld;
	push @{$self->{Names}}, $name;
	push @{$self->{Count}}, $count;
	$self->{Format} .= $format x ($count || 1);
    }
}

sub unformat {
    my ($self,$frec) = @_;
    my @flds = unpack $self->{Format}, $frec;
    my $i = 0;
    my $rec = {};
    foreach my $name (@{$self->{Names}}) {
	if ($self->{Count}[$i]) {
	    @{$rec->{$name}} = splice @flds, 0, $self->{Count}[$i];
	} else {
	    $rec->{$name} = shift @flds;
	}
	$i++;
    }
    return $rec;
}

sub format {
    my ($self,$rec) = @_;
    my @flds;
    my $i = 0;
    foreach my $name (@{$self->{Names}}) {
	if ($self->{Count}[$i]) {
	    push @flds,@{$rec->{$name}};
	} else {
	    push @flds,$rec->{$name};
	}
    	$i++;
    }
    my $frec = pack $self->{Format}, @flds;
    return $frec;
}

sub blank {
    my $self = shift;
    my $rec = $self->unformat(pack($self->{Format},
				   unpack($self->{Format},
					  '')));
    return $rec;
}

package Data::FixedFormat::Variants;

sub new {
    my ($class,$recfmt) = @_;
    my $self;
    $self = { Layouts=>[], Chooser=>$recfmt->{Chooser} };
    bless $self, $class;
    foreach my $fmt (@{$recfmt->{Formats}}) {
	push @{$self->{Layouts}},new Data::FixedFormat $fmt;
    }
    return $self;
}

sub unformat {
    my ($self,$frec) = @_;
    my $rec = $self->{Layouts}[0]->unformat($frec);
    if ($self->{Chooser}) {
	my $w = &{$self->{Chooser}}($rec);
	$rec = $self->{Layouts}[$w]->unformat($frec) if $w;
    }
    return $rec;
}

sub format {
    my ($self,$rec) = @_;
    my $w = 0;
    if ($self->{Chooser}) {
	$w = &{$self->{Chooser}}($rec);
    }
    my $frec = $self->{Layout}[$w]->format($rec);
    return $frec;
}

sub blank {
    my ($self,$w) = @_;
    $w = 0 unless $w;
    my $rec = $self->{Layout}[$w]->blank();
    return $rec;
}

=head1 NAME

Data::FixedFormat - convert between fixed-length fields and hashes

=head1 SYNOPSIS

   use Data::FixedFormat;

   my $tarhdr =
      new Data::FixedFormat [ qw(name:a100 mode:a8 uid:a8 gid:a8 size:a12
			         mtime:a12 chksum:a8 typeflag:a1 linkname:a100
				 magic:a6 version:a2 uname:a32 gname:a32
			         devmajor:a8 devminor:a8 prefix:a155) ];
   my $buf;
   read TARFILE, $buf, 512;

   # create a hash from the buffer read from the file
   my $hdr = $tarhdr->unformat($buf);   # $hdr gets a hash ref

   # create a flat record from a hash reference
   my $buf = $tarhdr->format($hdr);     # $hdr is a hash ref

   # create a hash for a new record
   my $newrec = $tarhdr->blank();

=head1 DESCRIPTION

B<Data::FixedFormat> can be used to convert between a buffer with
fixed-length field definitions and a hash with named entries for each
field.  The perl C<pack> and C<unpack> functions are used to perform
the conversions.  B<Data::FixedFormat> builds the format string by
concatenating the field descriptions and converts between the lists
used by C<pack> and C<unpack> and a hash that can be reference by
field name.

=head1 METHODS

B<Data::FixedFormat> provides the following methods.

=head2 new

To create a converter, invoke the B<new> method with a reference to a
list of field specifications.

    my $cvt =
        new Data::FixedFormat [ 'field-name:descriptor:count', ... ];

Field specifications contain the following information.

=over 4

=item field-name

This is the name of the field and will be used as the hash index.

=item descriptor

This describes the content and size of the field.  All of the
descriptors get strung together and passed to B<pack> and B<unpack> as
part of the template argument.  See B<perldoc -f pack> for information
on what can be specified here.

Don't use repeat counts in the descriptor except for string types
("a", "A", "h, "H", and "Z").  If you want to get an array out of the
buffer, use the C<count> argument.

=item count

This specifies a repeat count for the field.  If specified as a
non-zero value, this field's entry in the resultant hash will be an
array reference instead of a scalar.

=back

=head2 unformat

To convert a buffer of data into a hash, pass the buffer to the
B<unformat> method.

    $hashref = $cvt->unformat($buf);

Data::FixedFormat applies the constructed format to the buffer with
C<unpack> and maps the returned list of elements to hash entries.
Fields can now be accessed by name though the hash:

    print $hashref->{field-name};
    print $hashref->{array-field}[3];

=head2 format

To convert the hash back into a fixed-format buffer, pass the hash
reference to the B<format> method.

    $buf = $cvt->format($hashref);

=head2 blank


To get a hash that can be used to create a new record, call the
B<blank> method.

    $newrec = $cvt->blank();

=head1 VARIANT RECORDS

B<Data::FixedFormat> supports variant record formats.  To describe a
variant structure, pass a hash reference containing the following
elements to B<new>.  The object returned to handle variant records
will be a B<Data::FixedFormat::Variants>.

=over 4

=item Chooser

When converting a buffer to a hash, this subroutine is invoked after
applying the first format to the buffer.  The generated hash reference
is passed to this routine.  Any field names specified in the first
format are available to be used in making a decision on which format
to use to decipher the buffer.  This routine should return the index
of the proper format specification.

When converting a hash to a buffer, this subroutine is invoked first
to choose a packing format.  Since the same function is used for both
conversions, this function should restrict itself to field names that
exist in format 0 and those fields should exist in the same place in
all formats.

=item Formats

This is a reference to a list of formats.  Each format contains a list
of field specifications.

=back

For example:

    my $cvt = new Data::FixedFormat {
        Chooser => sub { my $rec=shift;
		         $rec->{RecordType} eq '0' ? 1 : 2
		       },
	Formats => [ [ 'RecordType:A1' ],
		     [ 'RecordType:A1', 'FieldA:A6', 'FieldB:A4:4' ],
		     [ 'RecordType:A1', 'FieldC:A4', 'FieldD:A18' ] ]
        };
    my $rec0 = $cvt->unformat("0FieldAB[0]B[1]B[2]B[3]");
    my $rec1 = $cvt->unformat("1FldC<-----FieldD----->");

In the above example, the C<Chooser> function looks at the contents of
the C<RecordType> field.  If it contains a '0', format 1 is used.
Otherwise, format 2 is used.

B<Data::FixedFormat::Variants> can be used is if it were a
B<Data::FixedFormat>.  The C<format> and C<unformat> methods will
determine which variant to use automatically.  The C<blank> method
requires an argument that specifies the variant number.

=head1 ATTRIBUTES

Each Data::FixedFormat instance contains the following attributes.

=over 4

=item Names

Names contains a list of the field names for this variant.

=item Count

Count contains a list of occurrence counts.  This is used to indicate
which fields contain arrays.

=item Format

Format contains the template string for the Perl B<pack> and B<unpack>
functions.

=back

B<Data::FixedFormat::Variants> is a class that handles variant
records.  It contains the following attributes.

=over 4

=item Layouts

Contains an array of Data::FixedFormat objects.  Each of these objects
is responsible for converting a single record format variant.

=item Chooser

This attribute contains the function that chooses which variant to
apply to the record.

=back

=head1 HISTORY

Version 0.02

This was a restructuring of the class.  The initial implementation
used a single package for variant and non-variant records.  All
attempts to format or unformat buffers resulted in checking for
variants.  Non-variant records can now skip this step and
should be faster.

In this version, B<Data::FixedFormat> was rewritten to handle a single
variant.  The C<new> method now returns a
B<Data::FixedFormat::Variants> if a variant record layout is
requested.  This class maintains a list of B<Data::FixedFormat>
objects to perform conversions.

This version also added the C<blank> method.

The documentation was updated and some corrections were made to the
examples.

Version 0.01

This was the initial release.

=head1 AUTHOR

Data::FixedFormat was written by Thomas Pfau <pfau@nbpfaus.net>
http://nbpfaus.net/~pfau/.

=head1 COPYRIGHT

Copyright (C) 2000,2002 Thomas Pfau.  All rights reserved.

This module is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at your
option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.

You should have received a copy of the GNU General Public License
along with this progam; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut
