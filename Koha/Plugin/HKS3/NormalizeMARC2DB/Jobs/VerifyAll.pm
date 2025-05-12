package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll;

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

use base 'Koha::BackgroundJob';

sub job_type {
    return 'plugin_marc2db_verifyall';
}

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    # Try this in runtime since it's not part of the stock Koha install
    my $failed;
    try {
        require 'XML/SemanticDiff.pm'; ## no critic
    } catch {
        $self->finish({ messages => [{ message => "Required module XML::SemanticDiff not installed" }] });
        $failed = 1;
    };
    return if $failed;

    my $dbh = C4::Context->dbh;
    my $sth_biblios = $dbh->prepare('select biblionumber, metadata from biblio_metadata');
    $sth_biblios->execute;

    my $sth_authorities = $dbh->prepare('select authid, marcxml from auth_header');
    $sth_authorities->execute;

    $self->set({ size => $sth_biblios->rows + $sth_authorities->rows });

    my @errors;
    my $diff = XML::SemanticDiff->new;

    while (my ($biblionumber, $metadata) = $sth_biblios->fetchrow_array) {
        my $xml;
        try {
            my ($record_id) = $dbh->selectrow_array('select id from nm2db_records where biblionumber = ?', undef, $biblionumber);
            $xml = Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->generate_marcxml($record_id);
            foreach my $change ($diff->compare($xml, $metadata)) {
                push @errors, { biblionumber => $biblionumber, message => "$change->{message} in context $change->{context}" };
            }
        }
        catch {
            warn "Failed to generate MARCXML for $biblionumber: $_";
            push @errors, { biblionumber => $biblionumber, message => "Failed to generate MARCXML $_" };
        };

        $self->step();
    }

    while (my ($authid, $metadata) = $sth_authorities->fetchrow_array) {
        my $xml;
        try {
            my ($record_id) = $dbh->selectrow_array('select id from nm2db_records where authid = ?', undef, $authid);
            $xml = Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->generate_marcxml($record_id);
            foreach my $change ($diff->compare($xml, $metadata)) {
                push @errors, { authid => $authid, message => "$change->{message} in context $change->{context}" };
            }
        }
        catch {
            warn "Failed to generate MARCXML for $authid: $_";
            push @errors, { authid => $authid, message => "Failed to generate MARCXML $_" };
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
    my $id = __PACKAGE__->new->enqueue();
    print "Queued " . __PACKAGE__ . ", job ID: $id\n";
}

1;
