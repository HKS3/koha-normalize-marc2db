package Koha::Plugin::HKS3::NormalizeMARC2DB::Utils;
use Modern::Perl;

use Exporter 'import';
our @EXPORT_OK = qw(argv_into_args);

sub argv_into_args {
    my @argv = @_;

    my %args;

    while (@argv) {
        my $key = shift @argv;
        $key =~ s/^--//;
        # turn it from CLI-style to Perl-style (dry-run => dry_run),
        # since the Perlish API we're targetting is unlikely to use dashes in hash keys
        $key =~ s/-/_/g;
        my $value;
        if ($key =~ /.=./) {
            ($key, $value) = split '=', $key;
            $args{$key} = $value;
        }
        if (!@argv or $argv[0] =~ /^--/) {
            $value = 1;
        } else {
            $value = shift(@argv);
        }
        $args{$key} = $value;
    }

    return \%args;
}

1;
