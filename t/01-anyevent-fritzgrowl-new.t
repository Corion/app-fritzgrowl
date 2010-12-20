#!perl -w
use strict;
use Test::More tests => 3;
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

my $outbound;
my $done;

my $signal_done = AnyEvent->condvar;
my $fb = AnyEvent::FritzBox->new( 
    handle => $fh,
    on_call => sub { $outbound++ },
    on_disconnect => sub {
        $done++;
        $signal_done->send;
    },
);
isa_ok $fb, 'AnyEvent::FritzBox';

$signal_done->recv;

is $outbound, 1, "One call was made";
is $done, 1, "One call was finished";

__DATA__
20.12.10 14:49:41;CALL;0;0;555555;555555;SIP2;
20.12.10 14:49:55;DISCONNECT;0;0;
