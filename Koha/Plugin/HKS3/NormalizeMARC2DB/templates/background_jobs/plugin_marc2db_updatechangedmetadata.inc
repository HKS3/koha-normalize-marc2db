[% USE Koha %]
[% USE To %]

[% SET report = job.decoded_data %]
[% BLOCK report %]
    [% IF job.status == 'finished' %]
        [% IF report %]
            <div class="dialog message">
                Job has finished.
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
                For biblio#[% error.biblionumber %]:
            [% ELSIF error.authid %]
                For of auth#[% error.authid %]:
            [% ELSE %]
                Error:
            [% END %]
            [% IF error.change %]
                Upcoming change:
                <pre>[% To.json(error.change) %]</pre>
                <br>
            [% END %]
            <pre>[% error.message | html %]</pre>
        </div>
    [% END %]
[% END %]

[% BLOCK js %]
[% END %]
