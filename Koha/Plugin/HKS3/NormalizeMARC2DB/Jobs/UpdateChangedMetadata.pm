package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::UpdateChangedMetadata;

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

use C4::AuthoritiesMarc qw(GetAuthority);
use C4::Biblio qw(ModZebra);
use Koha::SearchEngine::Elasticsearch::Indexer;

use Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::Foregroundable;
use base 'Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::Foregroundable';

sub job_type {
    return 'plugin_marc2db_updatechangedmetadata';
}

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my $dbh = C4::Context->dbh;

    my $sth_records = $dbh->prepare('select id, type, biblionumber, authid from nm2db_records where changed = 1');
    $sth_records->execute;

    $self->set({ size => $sth_records->rows });

    my (@errors, @authids, @biblioids);

    while (my ($record_id, $type, $biblionumber, $authid) = $sth_records->fetchrow_array) {
        my $xml;
        try {
            $xml = Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->generate_marcxml($record_id);
        } catch {
            warn "Failed to generate MARCXML for record $record_id: $_";
            push @errors, { record => $record_id, message => "Failed to generate MARCXML $_" };
        };
        unless ($xml) {
            $self->step();
            next;
        }

        try {
            if ($type eq 'biblio') {
                $dbh->do('update biblio_metadata set metadata = ? where biblionumber = ?', {}, $xml, $biblionumber);
                push @biblioids, $biblionumber;
            } elsif ($type eq 'authority') {
                $dbh->do('update auth_header set marcxml = ? where authid = ?', {}, $xml, $authid);
                push @authids, $authid;
            }
            $dbh->do('update nm2db_records set changed = 0 where id = ?', {}, $record_id);
        } catch {
            warn "Failed to update MARCXML for record $record_id: $_";
            push @errors, { record => $record_id, message => "Failed to update MARCXML $_" };
        };

        $self->step();
    }

    $self->reindex(\@authids, \@biblioids);

    $self->finish({ messages => \@errors });
}

sub reindex {
    my ($self, $authids, $biblionumbers) = @_;

    if (C4::Context->preference('SearchEngine') eq 'Elasticsearch') {
        my $auth_index = Koha::SearchEngine::Elasticsearch::Indexer->new({ index => $Koha::SearchEngine::Elasticsearch::AUTHORITIES_INDEX });
        my $bib_index  = Koha::SearchEngine::Elasticsearch::Indexer->new({ index => $Koha::SearchEngine::Elasticsearch::BIBLIOS_INDEX });
        if (@$authids) {
            my @authrecords = map { GetAuthority($_) } @$authids;
            $auth_index->update_index($authids, \@authrecords);
        }
        if (@$biblionumbers) {
            my @bibliorecords = map { Koha::Biblios->find($_)->metadata->record({ embed_items => 1}) } @$biblionumbers;
            $bib_index->update_index($biblionumbers, \@bibliorecords);
        }
    } else {
        for my $authid (@$authids) {
            ModZebra($authid, 'specialUpdate', 'authorityserver');
        }
        for my $biblionumber (@$biblionumbers) {
            ModZebra($biblionumber, 'specialUpdate', 'biblioserver');
        }
    }
}

sub enqueue {
    my ( $self, $args ) = @_;

    $self->SUPER::enqueue(
        {
            job_size => 1,
            job_args => {},
        }
    );
}

unless (caller) {
    __PACKAGE__->process_in_foreground;
}

1;
