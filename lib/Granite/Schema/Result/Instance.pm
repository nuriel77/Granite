use utf8;
package Granite::Schema::Result::Instance;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Granite::Schema::Result::Instance - Cloud Instances

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<instances>

=cut

__PACKAGE__->table("instances");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 hostname

  data_type: 'varchar'
  is_nullable: 0
  size: 42

=head2 alias

  data_type: 'varchar'
  is_nullable: 0
  size: 42

=head2 ipv4address

  data_type: 'varchar'
  is_nullable: 0
  size: 15

=head2 ipv6address

  data_type: 'varchar'
  is_nullable: 0
  size: 128

=head2 cloud_id

  data_type: 'varchar'
  is_nullable: 0
  size: 48

=head2 resource_id

  data_type: 'integer'
  is_nullable: 0

=head2 partition_id

  data_type: 'integer'
  is_nullable: 0

=head2 created

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 updated

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=head2 affinity

  data_type: 'integer'
  is_nullable: 0

=head2 memory

  data_type: 'integer'
  is_nullable: 0

=head2 disk

  data_type: 'integer'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "hostname",
  { data_type => "varchar", is_nullable => 0, size => 42 },
  "alias",
  { data_type => "varchar", is_nullable => 0, size => 42 },
  "ipv4address",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "ipv6address",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "cloud_id",
  { data_type => "varchar", is_nullable => 0, size => 48 },
  "resource_id",
  { data_type => "integer", is_nullable => 0 },
  "partition_id",
  { data_type => "integer", is_nullable => 0 },
  "created",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "updated",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "affinity",
  { data_type => "integer", is_nullable => 0 },
  "memory",
  { data_type => "integer", is_nullable => 0 },
  "disk",
  { data_type => "integer", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07039 @ 2014-02-10 12:32:08
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:5ISC0qWaRYPJ1x4bd6Jmvw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
