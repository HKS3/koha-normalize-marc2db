use strict;
use warnings;

use Test::More;
use Koha::Plugin::HKS3::NormalizeMARC2DB::Utils qw(argv_into_args);

is_deeply argv_into_args(), {};
is_deeply argv_into_args(qw(--dry-run 1)), { dry_run => 1 };
is_deeply argv_into_args(qw(--dry-run=1)), { dry_run => 1 };
is_deeply argv_into_args(qw(--dry-run)),   { dry_run => 1 };
is_deeply argv_into_args(qw(--dry-run --skip-authorities)), { dry_run => 1, skip_authorities => 1 };

is_deeply argv_into_args(qw(--a 7 --b)), { a => 7, b => 1 };

done_testing;
