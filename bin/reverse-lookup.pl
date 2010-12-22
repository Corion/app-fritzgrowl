#!perl -w
use strict;
use AnyEvent;
use AnyEvent::CIDReverseLookup;
use Data::Dumper;

my $found = AnyEvent->condvar;

my $implicit_local_prefix = '69';
my $implicit_country_prefix = '+49';

my $l = AnyEvent::CIDReverseLookup->new(
    #engines => ['klicktel'],
);
my @results;
for my $number (@ARGV) {
    $number =~ s/^00/+/; # XXX well, this would be locale-specific
    if (length $number <= 8) {
        $number = "$implicit_country_prefix$implicit_local_prefix$number";
    } elsif ($number =~ s/^0/+/) {
        $number = "$implicit_country_prefix$number";
    };
    $found->begin(sub { shift->send(\@results) });

    $l->lookup(
        number => $number,
        on_found => sub {
            my ($info) = @_;
            push @results, "$info->{number} => $info->{name}\n";
            $found->end();
        },
        on_notfound => sub {
            my ($info) = @_;
            push @results, "$info->{number} <unknown>\n";
            $found->end;
        },
        on_timeout => sub {
            my ($info) = @_;
            push @results, "$info->{number} <unknown>\n";
            $found->end;
        },
    );
};

print for @{ $found->recv };
