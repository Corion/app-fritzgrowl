#!perl -w
use strict;
use AnyEvent;
use AnyEvent::FritzBox;
use Data::Dumper;
use Growl::Any;
use Getopt::Long;

my $growl = Growl::Any->new;
$growl->register("FritzGrowl", ['Incoming call']);

GetOptions(
    "filter|f:s" => \my $local_filter,
    "host|h:s"   => \my $host,
);
if (! defined $local_filter) {
    $local_filter = '';
};
$local_filter = qr/$local_filter/;

# some local default, until I get the universal
# config going
$host ||= '192.168.1.104';

sub lookup_number {
    my $found = AnyEvent->condvar;

    my $implicit_local_prefix = '69';
    my $implicit_country_prefix = '+49';

    my $l = Phone::CIDReverseLookup->new();
    my @results;
    for my $number (@_) {
        $number =~ s/^00/+/; # XXX well, this would be locale-specific
        if (length $number <= 8) {
            $number = "$implicit_country_prefix$implicit_local_prefix$number";
        } elsif ($number =~ s/^0/+/) {
            $number = "$implicit_country_prefix$number";
        };
        $found->begin(sub { shift->send(\@results) });

        $l->lookup(
            {
                on_found => sub {
                    my ($info) = @_;
                    push @results, $info->{result};
                    $found->end();
                },
                on_notfound => sub {
                    my ($info) = @_;
                    push @results, "<unknown>";
                    $found->end;
                },
                on_timeout => sub {
                    my ($info) = @_;
                    push @results, "<unknown>";
                    $found->end;
                },
            },
            number => $number,
        );
    };

    @{ $found->recv };
};

my $fb = AnyEvent::FritzBox->new(
    host => $host,
    on_ring => sub {
        my ($fb,%args) = @_;
        if ($args{ local_number } =~ /$local_filter/) {
            print "RING: $args{remote_number}\n";
            #print Dumper \%args;
            
            # Do the reverse lookup here to find a name
            # Also, have a timeout here - if we don't find the name after 2 seconds
            # (maybe due to connectivity problems), just display it as unknown
            
            my $clearname = lookup_number($args{remote_number});
            $growl->notify("Incoming call", $args{ remote_number }, $clearname);
        };
    },
    on_call => sub {
        my ($fb,%args) = @_;
        print "CALL: $args{remote_number}\n";
        #print Dumper \%args;
    },
)
or die "Couldn't connect to $host: $!";

print "Fritz!Growl listening on $host\n";
AnyEvent->condvar->recv;
