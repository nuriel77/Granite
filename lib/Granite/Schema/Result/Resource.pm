use utf8;
package Granite::Schema::Result::Resource;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Granite::Schema::Result::Resource - Resources

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

=head1 TABLE: C<resources>

=cut

__PACKAGE__->table("resources");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 cpuload

  data_type: 'decimal'
  extra: {unsigned => 1}
  is_nullable: 0
  size: [3,1]

=head2 hostname

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

=head2 sockets

  data_type: 'tinyint'
  is_nullable: 0

=head2 cores_per_socket

  data_type: 'smallint'
  is_nullable: 0

=head2 threads_per_core

  data_type: 'smallint'
  is_nullable: 0

=head2 os

  data_type: 'tinytext'
  is_nullable: 0

=head2 real_memory

  data_type: 'mediumint'
  is_nullable: 0

=head2 alloc_memory

  data_type: 'mediumint'
  is_nullable: 0

=head2 alloc_cores

  data_type: 'bigint'
  is_nullable: 0

=head2 diskspace_free

  data_type: 'mediumint'
  is_nullable: 0

=head2 tmpdiskspace_free

  data_type: 'mediumint'
  is_nullable: 0

=head2 weight

  data_type: 'smallint'
  is_nullable: 0

=head2 boottime

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 last_watts_reading

  data_type: 'smallint'
  is_nullable: 0

=head2 last_temp_reading

  data_type: 'integer'
  is_nullable: 0

=head2 updated

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=head2 notes

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "cpuload",
  {
    data_type => "decimal",
    extra => { unsigned => 1 },
    is_nullable => 0,
    size => [3, 1],
  },
  "hostname",
  { data_type => "varchar", is_nullable => 0, size => 42 },
  "ipv4address",
  { data_type => "varchar", is_nullable => 0, size => 15 },
  "ipv6address",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "sockets",
  { data_type => "tinyint", is_nullable => 0 },
  "cores_per_socket",
  { data_type => "smallint", is_nullable => 0 },
  "threads_per_core",
  { data_type => "smallint", is_nullable => 0 },
  "os",
  { data_type => "tinytext", is_nullable => 0 },
  "real_memory",
  { data_type => "mediumint", is_nullable => 0 },
  "alloc_memory",
  { data_type => "mediumint", is_nullable => 0 },
  "alloc_cores",
  { data_type => "bigint", is_nullable => 0 },
  "diskspace_free",
  { data_type => "mediumint", is_nullable => 0 },
  "tmpdiskspace_free",
  { data_type => "mediumint", is_nullable => 0 },
  "weight",
  { data_type => "smallint", is_nullable => 0 },
  "boottime",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "last_watts_reading",
  { data_type => "smallint", is_nullable => 0 },
  "last_temp_reading",
  { data_type => "integer", is_nullable => 0 },
  "updated",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "notes",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<hostname>

=over 4

=item * L</hostname>

=item * L</ipv4address>

=item * L</ipv6address>

=back

=cut

__PACKAGE__->add_unique_constraint("hostname", ["hostname", "ipv4address", "ipv6address"]);


# Created by DBIx::Class::Schema::Loader v0.07039 @ 2014-02-12 00:04:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:YixtX9kCtMdKrc6sXzbGAQ

__PACKAGE__->load_components("InflateColumn::DateTime","EncodedColumn","TimeStamp");

__PACKAGE__->add_columns(
   updated => { data_type => 'datetime',   set_on_create => 1 },
);

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
