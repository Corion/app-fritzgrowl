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
        diag __PACKAGE__ . " error: $_[2]";
        $_[0]->destroy;
    },
);

# This is the FH we use to pump data to our tested component
my $feeder = AnyEvent::Handle->new(
    fh => $w,
    on_error => sub {
        diag __PACKAGE__ . " error: $_[2]";
        $_[0]->destroy;
    },
);
$feeder->push_write($_) while (<DATA>);
$feeder->push_shutdown; # Simulate an error

my $inbound;
my $remote;
my $done;

my $signal_done = AnyEvent->condvar;

{ no warnings 'redefine';
    *AnyEvent::FritzBox::connect = sub {
        my ($self,$host,$port,$connected) = @_;
        
        ($r,$w) = portable_pipe();

        $feeder = AnyEvent::Handle->new(
            fh => $w,
            on_error => sub {
                diag __PACKAGE__ . " error: $_[2]";
                $_[0]->destroy;
            },
        );
        for( split /(?<=;)\s+/,<<'RING' ) {
20.12.10 17:10:27;RING;0;069555555;666666;SIP2;
20.12.10 17:10:31;DISCONNECT;0;0;
RING
            $feeder->push_write("$_\n");
        };

        # This is the FH we pass in to read from
        # Live, this would be a socket
        my $fh = AnyEvent::Handle->new(
            fh => $r,
        );
        $self->setup_handle($fh);

        $connected->send();
    };
};

my $fb = AnyEvent::FritzBox->new( 
    handle => $fh,
    host => 'nohost.example', port => '666', # only used in error message
    on_ring => sub {
        $inbound++;
        my ($self, %args) = @_;
        $remote = $args{ remote_number }
    },
    on_disconnect => sub {
        $done++;
        my ($self, %args) = @_;
        $signal_done->send;
    },
);
isa_ok $fb, 'AnyEvent::FritzBox';

$signal_done->recv;

is $done, 1, "One call to ->connect() to reconnect was made";
is $inbound, 2, "Two calls were registered";
is $remote, '069555555', "by 069555555";

__DATA__
20.12.10 17:10:27;RING;0;069555555;666666;SIP2;
