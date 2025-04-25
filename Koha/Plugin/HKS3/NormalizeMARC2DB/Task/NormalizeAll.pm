package Koha::Plugin::HKS3::NormalizeMARC2DB::Task::NormalizeAll;

use Modern::Perl;  
use Moo;
with 'Koha::BackgroundJob::Role';

=head2 description

A human-readable description shown in the UI when you schedule the job.

=cut
sub description {
    return 'Regenerate normalized MARC data for all biblios';
}

=head2 perform

Called by background_jobs_worker.pl when the task runs.

=cut
sub perform {
    my ($self, $args) = @_;

    # Instantiate your plugin
    my $plugin = Koha::Plugins::Base->instance('HKS3', 'NormalizeMARC2DB');

    # Delegate to the existing normalize_all job method
    $plugin->job_normalize_all();
}

1;

