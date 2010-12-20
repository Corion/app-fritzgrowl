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
);
if (! defined $local_filter) {
    $local_filter = '';
};
$local_filter = qr/$local_filter/;

my $fb = AnyEvent::FritzBox->new(
    host => '192.168.1.104',
    on_ring => sub {
        my ($fb,%args) = @_;
        if ($args{ local_number } =~ /$local_filter/) {
            print "RING: $args{remote_number}\n";
            #print Dumper \%args;
            
            # Do the reverse lookup here to find a name
            # Also, have a timeout here - if we don't find the name after 2 seconds
            # (maybe due to connectivity problems), just display it as unknown
            
            my $clearname = "Unknown";
            $growl->notify("Incoming call", $args{ remote_number }, $clearname);
        };
    },
    on_call => sub {
        my ($fb,%args) = @_;
        print "CALL: $args{remote_number}\n";
        #print Dumper \%args;
    },
);

AnyEvent->condvar->recv;
