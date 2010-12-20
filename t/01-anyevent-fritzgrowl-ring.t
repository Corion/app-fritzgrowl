#!perl -w
use strict;
use Test::More tests => 4;
use Data::Dumper;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::FritzBox;
use AnyEvent::Util;

# Fake a selectable filehandle, even on Windows
my ($r,$w) = portable_pipe();

# This is the FH we pass in to read from
# Live, this would be a socket
my $fh = AnyEvent::Handle->new(
    fh => $r,
    on_error => sub {
        warn __PACKAGE__ . " error: $_[2]";
        $_[0]->destroy;
    },
);

# This is the FH we use to pump data to our tested component
my $feeder = AnyEvent::Handle->new(
    fh => $w,
    on_error => sub {
        warn __PACKAGE__ . " error: $_[2]";
        $_[0]->destroy;
    },
);
$feeder->push_write($_) while (<DATA>);

my $inbound;
my $remote;
my $done;

my $signal_done = AnyEvent->condvar;
my $fb = AnyEvent::FritzBox->new( 
    handle => $fh,
    on_ring => sub {
        $inbound++;
        my ($self, %args) = @_;
        $remote = $args{ remote_number }
    },
    on_disconnect => sub {
        $done++;
        $signal_done->send;
    },
);
isa_ok $fb, 'AnyEvent::FritzBox';

$signal_done->recv;

is $inbound, 1, "One call was made";
is $remote, '069555555', "by 069555555";
is $done, 1, "One call was finished";

__DATA__
20.12.10 17:10:27;RING;0;069555555;666666;SIP2;
20.12.10 17:10:31;DISCONNECT;0;0;
