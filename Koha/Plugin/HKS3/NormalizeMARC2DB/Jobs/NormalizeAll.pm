package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use Try::Tiny qw(catch try);

use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::Foregroundable;
use base 'Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::Foregroundable';

use Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;

my $plugin_class = 'Koha::Plugin::HKS3::NormalizeMARC2DB';

sub job_type {
    return 'plugin_marc2db_normalizeall';
}

sub _limit {
    my ($limit) = @_;

    return unless defined $limit;

    die 'Limit must be a positive integer'
        unless $limit =~ /\A[1-9]\d*\z/;

    return $limit;
}

sub _record_ids {
    my ($dbh, $sql, $params, $limit) = @_;

    $sql .= " LIMIT $limit" if defined $limit;

    my $sth = $dbh->prepare($sql);
    $sth->execute($params->@*);

    my @ids;
    while (my ($id) = $sth->fetchrow_array) {
        push @ids, $id;
    }

    return \@ids;
}

sub _force_progress {
    my ($dbh) = @_;

    my $sth = $dbh->prepare(
        'SELECT plugin_key, plugin_value FROM plugin_data '
        . 'WHERE plugin_class = ? AND plugin_key IN (?, ?, ?)'
    );
    $sth->execute(
        $plugin_class,
        'force_normalize_phase',
        'force_normalize_biblionumber',
        'force_normalize_authid',
    );

    my %progress = (
        phase         => 'biblio',
        biblionumber  => 0,
        authid        => 0,
    );
    while (my $row = $sth->fetchrow_hashref) {
        if ($row->{plugin_key} eq 'force_normalize_phase') {
            $progress{phase} = $row->{plugin_value}
                if $row->{plugin_value} =~ /\A(?:biblio|authority|done)\z/;
        } elsif ($row->{plugin_key} eq 'force_normalize_biblionumber') {
            $progress{biblionumber} = $row->{plugin_value}
                if $row->{plugin_value} =~ /\A\d+\z/;
        } elsif ($row->{plugin_key} eq 'force_normalize_authid') {
            $progress{authid} = $row->{plugin_value}
                if $row->{plugin_value} =~ /\A\d+\z/;
        }
    }

    return \%progress;
}

sub _store_force_progress {
    my ($dbh, $progress) = @_;

    my $sth = $dbh->prepare(
        'REPLACE INTO plugin_data SET plugin_class = ?, plugin_key = ?, plugin_value = ?'
    );
    for my $key (qw(phase biblionumber authid)) {
        $sth->execute($plugin_class, "force_normalize_$key", $progress->{$key});
    }
}

sub process {
    my ( $self, $args ) = @_;

    $args //= {};

    $self->start;

    my $dbh = C4::Context->dbh;
    my $limit = _limit($args->{limit});
    my $force = $args->{force} ? 1 : 0;
    my $remaining = $limit;
    my $progress = $force ? _force_progress($dbh) : undef;

    my @biblionumbers;
    my $biblio_limit = $remaining;
    if (!$force || $progress->{phase} eq 'biblio') {
        my ($sql, $params);
        if ($force) {
            $sql = 'SELECT biblionumber FROM biblio WHERE biblionumber > ? ORDER BY biblionumber';
            $params = [$progress->{biblionumber}];
        } else {
            $sql = 'SELECT b.biblionumber FROM biblio b '
                . 'LEFT JOIN nm2db_records nr ON nr.biblionumber = b.biblionumber '
                . 'WHERE nr.id IS NULL ORDER BY b.biblionumber';
            $params = [];
        }
        @biblionumbers = _record_ids($dbh, $sql, $params, $biblio_limit)->@*;
        $remaining -= scalar @biblionumbers if defined $remaining;
    }

    my $biblio_exhausted = $force
        && ($progress->{phase} eq 'biblio')
        && (!defined $biblio_limit || @biblionumbers < $biblio_limit);
    my $normalize_authorities = !$args->{skip_authorities}
        && (!defined $remaining || $remaining > 0)
        && (!$force || $progress->{phase} eq 'authority' || $biblio_exhausted);

    my @authids;
    my $auth_limit = $remaining;
    if ($normalize_authorities) {
        my ($sql, $params);
        if ($force) {
            $sql = 'SELECT authid FROM auth_header WHERE authid > ? ORDER BY authid';
            $params = [$progress->{authid}];
        } else {
            $sql = 'SELECT ah.authid FROM auth_header ah '
                . 'LEFT JOIN nm2db_records nr ON nr.authid = ah.authid '
                . 'WHERE nr.id IS NULL ORDER BY ah.authid';
            $params = [];
        }
        @authids = _record_ids($dbh, $sql, $params, $auth_limit)->@*;
    }

    $self->set({ size => scalar @biblionumbers + scalar @authids });

    my @errors;
    my $last_biblionumber = $force ? $progress->{biblionumber} : undef;
    my $last_authid = $force ? $progress->{authid} : undef;
    my $biblio_can_advance = 1;
    my $auth_can_advance = 1;

    for my $biblionumber (@biblionumbers) {
        try {
            Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_biblio($biblionumber);
            $last_biblionumber = $biblionumber if $biblio_can_advance;
        }
        catch {
            warn "Error normalizing biblionumber $biblionumber: $_";
            push @errors, { biblionumber => $biblionumber, message => $_ };
            $biblio_can_advance = 0;
        };
        $self->step();
    }

    for my $authid (@authids) {
        try {
            Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_authority($authid);
            $last_authid = $authid if $auth_can_advance;
        }
        catch {
            warn "Error normalizing authority $authid: $_";
            push @errors, { authid => $authid, message => $_ };
            $auth_can_advance = 0;
        };
        $self->step();
    }

    if ($force) {
        $progress->{biblionumber} = $last_biblionumber;
        $progress->{authid} = $last_authid;

        if ($progress->{phase} eq 'biblio' && $biblio_exhausted && $biblio_can_advance) {
            $progress->{phase} = $args->{skip_authorities} ? 'done' : 'authority';
        }

        my $auth_exhausted = $normalize_authorities
            && (!defined $auth_limit || @authids < $auth_limit);
        if ($progress->{phase} eq 'authority' && $auth_exhausted && $auth_can_advance) {
            $progress->{phase} = 'done';
        }

        _store_force_progress($dbh, $progress);
    }

    # Update the current place if we aren't forcing reindex, but just indexing in batches        
    my $sql = 'SELECT MIN(b.biblionumber) FROM biblio b '
        . 'LEFT JOIN nm2db_records nr ON nr.biblionumber = b.biblionumber '
        . 'WHERE nr.id IS NULL';
    my ($last_unindexed_biblionumber) = $dbh->selectrow_array($sql,undef);
    $sql = 'SELECT MIN(ah.authid) FROM auth_header ah '
	. 'LEFT JOIN nm2db_records nr ON nr.authid = ah.authid '
	. 'WHERE nr.id IS NULL';
    my ($last_unindexed_authid) = $dbh->selectrow_array($sql,undef);
    my $sth = $dbh->prepare(
        'REPLACE INTO plugin_data SET plugin_class = ?, plugin_key = ?, plugin_value = ?'
    );
    $sth->execute($plugin_class, "lowest_unindexed_biblionumber", $last_unindexed_biblionumber);
    $sth->execute($plugin_class, "lowest_unindexed_authid", $last_unindexed_authid);


    $self->finish({ messages => \@errors });
}

sub enqueue {
    my ( $self, $args ) = @_;

    $self->SUPER::enqueue(
        {
            job_size => 1,
            job_args => $args,
            job_queue => 'long_tasks',
        }
    );
}

unless (caller) {
    __PACKAGE__->process_in_foreground;
}

1;
