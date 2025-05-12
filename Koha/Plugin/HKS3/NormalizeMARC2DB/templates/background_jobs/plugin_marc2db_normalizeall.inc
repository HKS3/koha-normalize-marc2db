[% USE Koha %]

[% SET report = job.decoded_data %]
[% BLOCK report %]
    [% IF job.status == 'finished' %]
        [% IF report %]
            <div class="dialog message">
                All records have been successfully normalized.
            </div>
        [% ELSE %]
            <div class="dialog message">
               Job data could not be read, see the logs for details
            </div>
        [% END %]
    [% ELSIF job.status == 'cancelled' %]
        <span>The job has been cancelled before it finished.</span>
    [% END %]
[% END %]

[% BLOCK detail %]
    [% IF job.status != 'finished' %]
        <div class="dialog message"> The job is still running, no details available yet. </div>
    [% ELSIF job.messages.size == 0 %]
        <div class="dialog message"> No details available. </div>
    [% END %]

    [% FOR error IN job.messages %]
        <div class="dialog message">
            <i class="fa fa-exclamation error"></i>
            [% IF error.biblionumber %]
                Error normalizing biblio#[% error.biblionumber %]:
            [% ELSIF error.authid %]
                Error normalizing auth#[% error.authid %]:
            [% ELSE %]
                Error:
            [% END %]
            <code> [% error.message %] </code>
        </div>
    [% END %]
[% END %]

[% BLOCK js %]
[% END %]
