#!perl -w
use strict;
use AnyEvent;
use AnyEvent::FritzBox;
use Data::Dumper;
use Growl::Any;

#my $growl = Growl::Any->new;
#$growl->register("FritzGrowl", ['Incoming call']);

my $fb = AnyEvent::FritzBox->new(
    host => '192.168.1.104',
    on_ring => sub {
        my ($fb,%args) = @_;
        #print "RING: $args{remote_number}\n";
        #print Dumper \%args;
        my $clearname = "Unknown";
        #$growl->notify("Incoming call", $args{ remote_number }, $clearname);
    },
    on_call => sub {
        my ($fb,%args) = @_;
        print "CALL: $args{remote_number}\n";
        #print Dumper \%args;
    },
);


AnyEvent->condvar->recv;
