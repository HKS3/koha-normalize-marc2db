use strict;
use warnings;
use Test::More;

our $dbh;
our (@biblio_calls, @authority_calls);

BEGIN {
    $INC{'Koha/Plugin/HKS3/NormalizeMARC2DB/Jobs/Foregroundable.pm'} = 1;
    package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::Foregroundable;
    sub start { }
    sub set { $_[0]->{properties} = $_[1] }
    sub step { }
    sub finish { $_[0]->{data} = $_[1] }

    $INC{'Koha/Plugin/HKS3/NormalizeMARC2DB/Normalizer.pm'} = 1;
    package Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;
    sub normalize_biblio {
        my (undef, $biblionumber) = @_;
        push @main::biblio_calls, $biblionumber;
        $main::dbh->{normalized_biblios}{$biblionumber} = 1;
    }
    sub normalize_authority {
        my (undef, $authid) = @_;
        push @main::authority_calls, $authid;
        $main::dbh->{normalized_authorities}{$authid} = 1;
    }

    $INC{'C4/Context.pm'} = 1;
    package C4::Context;
    sub dbh { return $main::dbh }
}

require 'Koha/Plugin/HKS3/NormalizeMARC2DB/Jobs/NormalizeAll.pm';

{
    package TestDB;

    sub new {
        return bless {
            biblios                => [1, 2, 3],
            authorities            => [10],
            normalized_biblios     => { 2 => 1 },
            normalized_authorities => {},
            plugin_data            => {},
        }, shift;
    }

    sub prepare {
        my ($self, $sql) = @_;
        return bless { dbh => $self, sql => $sql }, 'TestSTH';
    }

    sub selectrow_array {
        my ($self, $sql) = @_;

        if ($sql =~ /SELECT MIN\(b\.biblionumber\) FROM biblio b/) {
            my @missing = sort { $a <=> $b }
                grep { !$self->{normalized_biblios}{$_} } $self->{biblios}->@*;
            return $missing[0];
        }
        if ($sql =~ /SELECT MIN\(ah\.authid\) FROM auth_header ah/) {
            my @missing = sort { $a <=> $b }
                grep { !$self->{normalized_authorities}{$_} } $self->{authorities}->@*;
            return $missing[0];
        }
        die "Unexpected SQL: $sql";
    }
}

{
    package TestSTH;

    sub execute {
        my ($self, @params) = @_;
        my $dbh = $self->{dbh};
        my $sql = $self->{sql};

        if ($sql =~ /SELECT plugin_key, plugin_value FROM plugin_data/) {
            $self->{rows} = [
                map { [$_, $dbh->{plugin_data}{$_}] }
                grep { exists $dbh->{plugin_data}{$_} }
                qw(force_normalize_phase force_normalize_biblionumber force_normalize_authid)
            ];
        } elsif ($sql =~ /REPLACE INTO plugin_data/) {
            $dbh->{plugin_data}{$params[1]} = $params[2];
            $self->{rows} = [];
        } elsif ($sql =~ /SELECT biblionumber FROM biblio WHERE biblionumber >/) {
            $self->{rows} = [ map { [$_] } grep { $_ > $params[0] } $dbh->{biblios}->@* ];
        } elsif ($sql =~ /SELECT b\.biblionumber FROM biblio b/) {
            $self->{rows} = [
                map { [$_] }
                grep { !$dbh->{normalized_biblios}{$_} }
                $dbh->{biblios}->@*
            ];
        } elsif ($sql =~ /SELECT authid FROM auth_header WHERE authid >/) {
            $self->{rows} = [ map { [$_] } grep { $_ > $params[0] } $dbh->{authorities}->@* ];
        } elsif ($sql =~ /SELECT ah\.authid FROM auth_header ah/) {
            $self->{rows} = [
                map { [$_] }
                grep { !$dbh->{normalized_authorities}{$_} }
                $dbh->{authorities}->@*
            ];
        } else {
            die "Unexpected SQL: $sql";
        }

        if ($sql =~ /LIMIT (\d+)/) {
            splice $self->{rows}->@*, $1;
        }
        return 1;
    }

    sub fetchrow_array {
        my ($self) = @_;
        my $row = shift $self->{rows}->@*;
        return unless $row;
        return $row->@*;
    }

    sub fetchrow_hashref {
        my ($self) = @_;
        my $row = shift $self->{rows}->@*;
        return unless $row;
        return { plugin_key => $row->[0], plugin_value => $row->[1] };
    }
}

$dbh = TestDB->new;
my $job = bless {}, 'Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll';

$job->process({ limit => 2 });
is_deeply(\@biblio_calls, [1, 3], 'first normal batch processes only missing biblios');
is_deeply(\@authority_calls, [], 'first normal batch respects the total limit');
is($dbh->{plugin_data}{lowest_unindexed_biblionumber}, undef, 'no missing biblio ID remains after the first batch');
is($dbh->{plugin_data}{lowest_unindexed_authid}, 10, 'first batch records the still-missing authority ID');

$job->process({ limit => 2 });
is_deeply(\@authority_calls, [10], 'next normal batch processes the remaining authority');
is($dbh->{plugin_data}{lowest_unindexed_authid}, undef, 'missing authority status is cleared after normalization');

@biblio_calls = ();
@authority_calls = ();
$job->process({ limit => 2, force => 1 });
is_deeply(\@biblio_calls, [1, 2], 'first forced batch starts at the first biblio');
is($dbh->{plugin_data}{force_normalize_biblionumber}, 2, 'first forced batch stores its biblio cursor');

$job->process({ limit => 2, force => 1 });
is_deeply(\@biblio_calls, [1, 2, 3], 'second forced batch continues with the next biblio');
is_deeply(\@authority_calls, [10], 'second forced batch uses remaining capacity for authorities');

$job->process({ limit => 2, force => 1 });
is($dbh->{plugin_data}{force_normalize_phase}, 'done', 'forced reindex records completion');

$dbh = TestDB->new;
@biblio_calls = ();
@authority_calls = ();
$job->process({ limit => 1 });
is($dbh->{plugin_data}{lowest_unindexed_biblionumber}, 3, 'partial batch records the next missing biblio ID');
is($dbh->{plugin_data}{lowest_unindexed_authid}, 10, 'partial batch records the next missing authority ID');

$job->process({ limit => 2, force => 1, skip_authorities => 1 });
is_deeply(\@biblio_calls, [1, 1, 2], 'forced batch still respects its record limit');
is_deeply(\@authority_calls, [], 'status queries do not normalize skipped authorities');
is($dbh->{plugin_data}{lowest_unindexed_biblionumber}, 3, 'forced batch stores the missing biblio status');
is($dbh->{plugin_data}{lowest_unindexed_authid}, 10, 'skipped authority remains visible in the status');

done_testing;
