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

    my @errors;

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
            } elsif ($type eq 'authority') {
                $dbh->do('update auth_header set marcxml = ? where authid = ?', {}, $xml, $authid);
            }
            $dbh->do('update nm2db_records set changed = 0 where id = ?', {}, $record_id);
        } catch {
            warn "Failed to update MARCXML for record $record_id: $_";
            push @errors, { record => $record_id, message => "Failed to update MARCXML $_" };
        };

        $self->step();
    }

    $self->finish({ messages => \@errors });
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
