package Koha::Plugin::HKS3::NormalizeMARC2DB::Jobs::Foregroundable;
use Modern::Perl;
use Data::Dumper;

use base 'Koha::BackgroundJob';

=pod

This overrides some of the Koha::BackgroundJob methods to allow the job to be ran without the job queue.

=cut

sub process_in_foreground {
    my $class = shift;

    my $self = bless {}, $class;
    $self->{in_foreground} = 1;
    $self->{properties} = {};
    $self->{progress} = 0;
    $self->process();
}

sub start {
    my ($self, @args) = shift;

    if ($self->{in_foreground}) {
        STDOUT->autoflush(1);
    } else {
        return $self->SUPER::start(@args);
    }
}

sub set {
    my ($self, $properties) = @_;
    if ($self->{in_foreground}) {
        $self->{properties} = {
            $self->{properties}->%*,
            %$properties,
        };
    } else {
        return $self->SUPER::set($properties);
    }
}

sub step {
    my $self = shift;

    if ($self->{in_foreground}) {
        $self->{progress}++;
        print "\r$self->{progress}/$self->{properties}{size}... ";
    } else {
        return $self->SUPER::step();
    }
}

sub finish {
    my ($self, $data) = @_;

    if ($self->{in_foreground}) {
        say "Job finished";
        warn Dumper $data;
    } else {
        return $self->SUPER::finish($data);
    }
}

1;

