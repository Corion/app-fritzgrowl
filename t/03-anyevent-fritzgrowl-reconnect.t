#!perl -w
use strict;
use Test::More tests => 4;
use Data::Dumper;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket();

sub _postpone {
   my ($cb, @args) = (@_, $!);

   my $w; $w = AE::timer 0, 0, sub {
      undef $w;
      $! = pop @args;
      $cb->(@args);
   };
}
BEGIN { no warnings 'redefine';
  my $reconnected;
  *AnyEvent::Socket::tcp_connect = sub  ($$$;$){
        my ($host,$port,$connected) = @_;
        diag "Connecting to $host:$port";
        
        my ($r,$w) = portable_pipe();

        my $feeder;
        if ($reconnected++ < 2) {
            diag "Setting up another fail";
            $feeder = fail_handle($w);
        } else {
            diag "Setting up the connect";
            $feeder = success_handle($w);
        };

        # This is the FH we pass in to read from
        # Live, this would be a socket
        my $fh = AnyEvent::Handle->new(
            fh => $r,
        );
        _postpone sub { $connected->($fh) };
        1
    };
};

use AnyEvent::FritzBox;
use AnyEvent::Util;


my @fail = <DATA>;
sub fail_handle {
    my ($w) = @_;
    # This is the FH we use to pump data to our tested component
    my $feeder = AnyEvent::Handle->new(
        fh => $w,
        on_error => sub {
            diag __PACKAGE__ . " error: $_[2]";
            $_[0]->destroy;
        },
    );
    $feeder->push_write($_) for @fail;
    $feeder->push_shutdown; # Simulate an error
    $feeder
};

sub success_handle {
    my ($w) = @_;
    my $feeder = AnyEvent::Handle->new(
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
    $feeder
};

my $inbound;
my $remote;
my $done;

my $signal_done = AnyEvent->condvar;


my $fb = AnyEvent::FritzBox->new( 
    host => 'nohost.example', port => '666', # only used in error message
    log => sub { diag @_ },
    on_ring => sub {
        $inbound++;
        my ($self, %args) = @_;
        $remote = $args{ remote_number }
    },
    on_disconnect => sub {
        my ($self, %args) = @_;
        $signal_done->send;
    },
);
isa_ok $fb, 'AnyEvent::FritzBox';

$signal_done->recv;

is $fb->{current_reconnect}, undef, "We erased all information about reconnecting";
is $inbound, 3, "Five calls were registered";
is $remote, '069555555', "by 069555555";

__DATA__
20.12.10 17:10:27;RING;0;069555555;666666;SIP2;
