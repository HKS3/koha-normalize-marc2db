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

use base 'Koha::BackgroundJob';

use Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer;

sub job_type {
    return 'plugin_marc2db_normalizeall';
}

sub process {
    my ( $self, $args ) = @_;

    $self->start;

    my $dbh = C4::Context->dbh;
    my $sth_biblios = $dbh->prepare("SELECT biblionumber FROM biblio");
    $sth_biblios->execute;

    my $sth_authorities = $dbh->prepare("SELECT authid FROM auth_header");
    $sth_authorities->execute;

    $self->set({ size => $sth_biblios->rows + $sth_authorities->rows });

    my @errors;

    while (my ($biblionumber) = $sth_biblios->fetchrow_array) {
        try {
            Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_biblio($biblionumber);
        }
        catch {
            warn "Error normalizing biblionumber $biblionumber: $_";
            push @errors, { biblionumber => $biblionumber, message => $_ };
        };
        $self->step();
    }

    while (my ($authid) = $sth_authorities->fetchrow_array) {
        try {
            Koha::Plugin::HKS3::NormalizeMARC2DB::Normalizer->normalize_authority($authid);
        }
        catch {
            warn "Error normalizing authority $authid: $_";
            push @errors, { authid => $authid, message => $_ };
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
