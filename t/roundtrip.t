use strict;
use warnings;
use Test::More tests => 3;
use Data::Dumper;
$Data::Dumper::Terse = 1;

use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll;

my ($job, $data);

note "normalizing...";
$job = Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::NormalizeAll->new();
$job->set({ status => 'new' });
$job->process();
$data = $job->decoded_data();
# diag Dumper($data);
is_deeply $data, { messages => [] }, 'no errors when normalizing'; 

note "verifying...";
$job = Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::VerifyAll->new();
$job->set({ status => 'new' });
$job->process();
$data = $job->decoded_data();
# diag Dumper($data);
is scalar(@{$data->{messages}}), 1, '1 error as expected';
is $data->{messages}[0]{biblionumber}, 369, 'the deliberately-broken record breaks as expected'
