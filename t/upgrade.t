use strict;
use warnings;
use Test::More;

our $dbh;

BEGIN {
    $INC{'Koha/Plugins/Base.pm'} = 1;
    package Koha::Plugins::Base;
    sub new { return bless {}, shift }
    sub retrieve_data { return $main::dbh->{plugin_data}{ $_[1] } }
    sub store_data {
        my ($self, $data) = @_;
        $main::dbh->{plugin_data}{$_} = $data->{$_} for keys %$data;
    }
    sub mbf_read {
        my ($self, $file) = @_;
        open my $fh, '<', "Koha/Plugin/HKS3/NormalizeMARC2DB/$file" or die $!;
        local $/;
        return <$fh>;
    }

    $INC{'C4/Context.pm'} = 1;
    package C4::Context;
    sub dbh { return $main::dbh }

    $INC{'MARC/Record.pm'} = 1;
    package MARC::Record;

    $INC{'MARC/Field.pm'} = 1;
    package MARC::Field;

    $INC{'MARC/File/XML.pm'} = 1;
    package MARC::File::XML;
    sub import { }

    $INC{'XML/Twig.pm'} = 1;
    package XML::Twig;

    $INC{'Koha/Logger.pm'} = 1;
    package Koha::Logger;

    $INC{'Koha/Plugin/HKS3/NormalizeMARC2DB/Normalizer.pm'} = 1;
    package Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;

    $INC{'Koha/Plugin/HKS3/NormalizeMARC2DB/Jobs/NormalizeAll.pm'} = 1;
    package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll;

    $INC{'Koha/Plugin/HKS3/NormalizeMARC2DB/Jobs/UpdateChangedMetadata.pm'} = 1;
    package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata;

    $INC{'Koha/Plugin/HKS3/NormalizeMARC2DB/Jobs/VerifyAll.pm'} = 1;
    package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll;
}

require 'Koha/Plugin/HKS3/NormalizeMARC2DB.pm';

{
    package TestDB;

    sub new {
        return bless {
            collations => {
                nm2db_records   => 'latin1_swedish_ci',
                nm2db_fields    => 'latin1_swedish_ci',
                nm2db_subfields => 'latin1_swedish_ci',
            },
            value_index_prefix => 3072,
            sql                => [],
            plugin_data        => {},
            legacy_columns     => {},
            changed            => { 1 => 1, 2 => 0 },
            queue              => { 1 => 'existing timestamp' },
            has_changed        => 1,
            has_view           => 0,
            locked             => 0,
        }, shift;
    }

    sub selectrow_array {
        my ($self, $sql, undef, @params) = @_;

        if ($sql =~ /GET_LOCK/) {
            return 0 if $self->{locked};
            $self->{locked} = 1;
            return 1;
        }
        if ($sql =~ /RELEASE_LOCK/) {
            $self->{locked} = 0;
            return 1;
        }
        if ($sql =~ /information_schema\.COLUMNS/) {
            return $self->{has_changed} if $sql =~ /COLUMN_NAME = 'changed'/;
            return $self->{legacy_columns}{ $params[0] } || 0;
        }
        if ($sql =~ /nm2db_v_record/) {
            return $self->{has_view};
        }
        if ($sql =~ /information_schema\.TABLES/) {
            return $self->{collations}{ $params[0] };
        }
        if ($sql =~ /information_schema\.STATISTICS/) {
            return defined $self->{value_index_prefix}
                ? ($self->{value_index_prefix}, 1)
                : (undef, undef);
        }
        die "Unexpected SQL: $sql";
    }

    sub do {
        my ($self, $sql) = @_;
        push $self->{sql}->@*, $sql;

        if ($self->{fail_at} && $sql =~ /\Q$self->{fail_at}\E/) {
            die 'Simulated database failure' if $self->{RaiseError};
            return undef;
        }

        if ($sql =~ /ALTER TABLE (nm2db_\w+) CONVERT TO CHARACTER SET utf8mb4/) {
            $self->{collations}{$1} = 'utf8mb4_unicode_ci';
            delete $self->{legacy_columns}{$1};
        } elsif ($sql =~ /DROP INDEX nm2db_subfields_value_ind/) {
            $self->{value_index_prefix} = undef;
        } elsif ($sql =~ /ADD INDEX nm2db_subfields_value_ind \(value\(768\)\)/) {
            $self->{value_index_prefix} = 768;
        } elsif ($sql =~ /CREATE TABLE IF NOT EXISTS nm2db_change_queue/) {
            $self->{queue} ||= {};
        } elsif ($sql =~ /INSERT INTO nm2db_change_queue/) {
            for my $id (keys $self->{changed}->%*) {
                $self->{queue}{$id} = 'migrated timestamp'
                    if $self->{changed}{$id} && !exists $self->{queue}{$id};
            }
        } elsif ($sql =~ /CREATE OR REPLACE VIEW nm2db_v_record/) {
            $self->{has_view} = 1;
        } else {
            die "Unexpected SQL: $sql";
        }
        return 1;
    }
}

$dbh = TestDB->new;
my $plugin = bless {}, 'Koha::Plugin::HKS3::NormalizeMARC2DB';

ok($plugin->upgrade, 'upgrade succeeds for legacy latin1 tables');
is_deeply(
    $dbh->{collations},
    {
        nm2db_records   => 'utf8mb4_unicode_ci',
        nm2db_fields    => 'utf8mb4_unicode_ci',
        nm2db_subfields => 'utf8mb4_unicode_ci',
    },
    'upgrade converts all normalized tables to utf8mb4',
);
is($dbh->{value_index_prefix}, 768, 'upgrade replaces the legacy value index with the utf8mb4-safe prefix');
is_deeply(
    [grep { /^ALTER TABLE/ } $dbh->{sql}->@*],
    [
        'ALTER TABLE nm2db_subfields DROP INDEX nm2db_subfields_value_ind',
        'ALTER TABLE nm2db_records CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
        'ALTER TABLE nm2db_fields CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
        'ALTER TABLE nm2db_subfields CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
        'ALTER TABLE nm2db_subfields ADD INDEX nm2db_subfields_value_ind (value(768))',
    ],
    'legacy index is dropped before conversion and rebuilt afterwards',
);
is($dbh->{queue}{1}, 'existing timestamp', 'existing queued edit retains its timestamp');
ok(!exists $dbh->{queue}{2}, 'unchanged legacy record is not queued');
ok($dbh->{has_view}, 'missing view is installed');
is($dbh->{plugin_data}{schema_version}, '1.0.5', 'schema version is recorded after success');
ok(!$dbh->{locked}, 'upgrade releases the advisory lock');

$dbh->{sql} = [];
ok($plugin->upgrade, 'upgrade can be retried after a completed migration');
is_deeply([grep { /^ALTER TABLE/ } $dbh->{sql}->@*], [], 'completed migration performs no further table rebuilds');
ok(!grep(/INSERT INTO nm2db_change_queue/, $dbh->{sql}->@*), 'legacy flags are not replayed after a completed upgrade');

$dbh->{value_index_prefix} = undef;
$dbh->{sql} = [];
ok($plugin->upgrade, 'upgrade repairs a missing value index after an interrupted migration');
is_deeply(
    [grep { /^ALTER TABLE/ } $dbh->{sql}->@*],
    ['ALTER TABLE nm2db_subfields ADD INDEX nm2db_subfields_value_ind (value(768))'],
    'interrupted migration only restores the missing value index',
);

$dbh = TestDB->new;
$dbh->{collations}{$_} = 'utf8mb3_general_ci' for keys $dbh->{collations}->%*;
$dbh->{value_index_prefix} = 1024;
delete $dbh->{queue};
ok($plugin->upgrade, 'HKS3 0.97 utf8mb3 schema upgrades successfully');
is($dbh->{value_index_prefix}, 768, '1024-character index is replaced');
is_deeply($dbh->{queue}, { 1 => 'migrated timestamp' }, 'missing queue receives pending legacy changes');

$dbh = TestDB->new;
$dbh->{fail_at} = 'nm2db_fields CONVERT';
eval { $plugin->upgrade };
like($@, qr/Simulated database failure/, 'SQL errors abort the upgrade even with RaiseError originally disabled');
ok(!$dbh->{plugin_data}{schema_version}, 'failed migration is not recorded as complete');
ok(!$dbh->{locked}, 'failure releases the advisory lock');
delete $dbh->{fail_at};
ok($plugin->upgrade, 'migration resumes after a partial DDL failure');
is($dbh->{value_index_prefix}, 768, 'resumed migration restores the index');

$dbh->{collations}{nm2db_fields} = 'utf8mb4_unicode_ci';
$dbh->{legacy_columns}{nm2db_fields} = 1;
$dbh->{sql} = [];
ok($plugin->upgrade, 'legacy character column is detected despite correct table default');
ok(grep(/nm2db_fields CONVERT/, $dbh->{sql}->@*), 'table with a legacy character column is converted');

$dbh = TestDB->new;
delete $dbh->{collations}{nm2db_fields};
eval { $plugin->upgrade };
like($@, qr/table nm2db_fields is missing/, 'missing core table aborts with a clear error');
is_deeply($dbh->{sql}, [], 'missing core table causes no DDL changes');
ok(!$dbh->{locked}, 'preflight failure releases the advisory lock');

$dbh = TestDB->new;
$dbh->{locked} = 1;
eval { $plugin->upgrade };
like($@, qr/another upgrade is running/, 'concurrent upgrade is refused');
is_deeply($dbh->{sql}, [], 'concurrent upgrade causes no DDL changes');

done_testing;
