package Data::FixedFormat;

use strict;
use vars qw($VERSION);

$VERSION    = "0.01";

1;

sub parse_fields {
    my $self = shift;
    my $i = shift;
    my $fmt = shift;
    foreach my $fld (@$fmt) {
	my ($name, $format, $count) = split ':',$fld;
	push @{$self->{Names}[$i]}, $name;
	push @{$self->{Count}[$i]}, $count;
	$self->{Format}[$i] .= $format x ($count || 1);
    }
}

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->{Names} = [];
    $self->{Count} = [];
    $self->{Format} = [];
    my $recfmt = shift;
    if (ref $recfmt eq "HASH") {
	my $i = 0;
	foreach my $fmt (@{$recfmt->{Formats}}) {
	    $self->parse_fields($i, $fmt);
	    $i++;
	}
	$self->{Chooser} = $recfmt->{Chooser};
    } else {
	$self->parse_fields(0, $recfmt);
    }
    return $self;
}

sub unformat {
    my $self = shift;
    my $frec = shift;
    my @flds = unpack $self->{Format}[0], $frec;
    my $i = 0;
    my $rec = {};
    foreach my $name (@{$self->{Names}[0]}) {
	if ($self->{Count}[0][$i]) {
	    @{$rec->{$name}} = splice @flds, 0, $self->{Count}[0][$i];
	} else {
	    $rec->{$name} = shift @flds;
	}
	$i++;
    }
    if ($self->{Chooser}) {
	my $w = &{$self->{Chooser}}($rec);
	if ($w) {
	    @flds = unpack $self->{Format}[$w], $frec;
    	    $i = 0;
    	    $rec = {};
    	    foreach my $name (@{$self->{Names}[$w]}) {
		if ($self->{Count}[$w][$i]) {
	    	    @{$rec->{$name}} = splice @flds, 0, $self->{Count}[$w][$i];
		} else {
	    	    $rec->{$name} = shift @flds;
		}
		$i++;
    	    }
	}
    }
    $rec;
}

sub format {
    my $self = shift;
    my $rec = shift;
    my @flds;
    my $i = 0;
    my $w = 0;
    if ($self->{Chooser}) {
	$w = &{$self->{Chooser}}($rec);
    }
    foreach my $name (@{$self->{Names}[$w]}) {
	if ($self->{Count}[$w][$i]) {
	    push @flds,@{$rec->{$name}};
	} else {
	    push @flds,$rec->{$name};
	}
    	$i++;
    }
    my $frec = pack $self->{Format}[$w], @flds;
    $frec;
}

=head1 NAME

Data::FixedFormat - converter between fixed-fields and hashes

=head1 SYNOPSIS

   use Data::FixedFormat;

   my $tarhdr = new Data::FixedFormat [ 'name:a100', 'mode:a8', 'uid:a8',
			        'gid:a8', 'size:a12', 'mtime:a12',
				'chksum:a8', 'typeflag:a1',
				'linkname:a100', 'magic:a6',
				'version:a2', 'uname:a32',
				'gname:a32', 'devmajor:a8',
				'devminor:a8', 'prefix:a155' ];
   my $buf;
   read TARFILE, $buf, 512;

   # create a hash from the buffer read from the file
   my $hdr = $tarhdr->unformat($buf);   # $hdr gets a hash ref

   # create a flat record from a hash reference
   my $buf = $tarhdr->format($hdr);     # $hdr is a hash ref

=head1 DESCRIPTION

B<Data::FixedFormat> can be used to convert between a buffer with fixed field
definitions and a hash with named entries for each field.

First, load the Data::FixedFormat module:

    use Data::FixedFormat;

To create a converter, invoke the B<new> method with a reference to an
array of field specifications:

    my $cvt = new Data::FixedFormat [ 'field-name:descriptor:count', ... ];

=over 4

=item field-name

This is the name of the field and will be used as the hash index.

=item descriptor

This describes the content and size of the field.  All of the
descriptors get strung together and passed to B<pack> and B<unpack> as
part of the template argument.  See B<perldoc -f pack> for information
on what can be specified here.

=item count

This specifies a repeat count for the field.  If not specified, it
defaults to 1.  If greater than 1, this field's entry in the resultant
hash will be an array reference instead of a scalar.

=back

To convert a buffer of data into a hash, pass the buffer to the
B<unformat> method:

    $hashref = $cvt->unformat($buf);

Data::FixedFormat applies the format to the buffer and creates a hash
containing an element for each field.  Fields can now be accessed by
name though the hash:

    print $hashref->{field-name};
    print $hashref->{array-field}[3];

To convert the hash back into a fixed-format buffer, pass the hash
reference to the B<format> method:

    $buf = $cvt->format($hashref);

Variant record formats are supported.  Instead of passing an array
reference to the B<new> method, pass a hash reference containing the
following elements:

=over 4

=item Chooser

When converting a buffer to a hash, this subroutine is invoked after
applying the first format to the buffer.  The hash reference is passed
to this routine.  Any field names specified in the first format are
available to be used in making a decision on which format to use to
decipher the buffer.  This routine should return the index of the
proper format specification.

When converting a hash to a buffer, this subroutine is invoked to
first to choose a packing format.  Since the same function is used for
both conversions, this function should restrict itself to field names
that exist in format 0 and those fields should exist in the same place
in all formats.

=item Formats

This is a reference to an array of references to formats.

=back

For example:

    my $cvt = new Data::FixedFormat {
        Chooser => sub { $_[0]->{RecordType} eq '0' ? 1 : 2 },
	Format => [ [ 'RecordType:A1' ],
		    [ 'RecordType:A1', 'FieldA:A6', 'FieldB:A4:4' ],
		    [ 'RecordType:A1', 'FieldC:A4', 'FieldD:A18' ] ]
        };
    my $rec0 = $cvt->unformat("0FieldAB[0]B[1]B[2]B[3]");
    my $rec1 = $cvt->unformat("1FldC<-----FieldD----->");

Each Data::FixedFormat instance also contains the following attributes:

=over 4

=item Names

Names contains a list of lists of field names indexed as [record
variant, field number].  For example, to find the third field name in
a non-variant record, use C<$cvt->{Names}[0][2]>.

=item Count

Count contains a list of list of occurrence counts.  This is used to
indicate which fields contain arrays.

=item Format

Format contains a list of template strings for the Perl B<pack> and
B<unpack> functions.

=back

=head1 AUTHOR

Data::FixedFormat was written by Thomas Pfau <pfau@eclipse.net>
http://www.eclipse.net/~pfau/.

=head1 COPYRIGHT

Copyright (C) 2000 Thomas Pfau.  All rights reserved.

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
