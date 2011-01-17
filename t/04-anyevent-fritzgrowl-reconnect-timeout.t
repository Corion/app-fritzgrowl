#!perl -w
use strict;
use Test::More tests => 2;
use Data::Dumper;
use Errno;

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

my $reconnected;
BEGIN { no warnings 'redefine';
    *AnyEvent::Socket::tcp_connect = sub  ($$$;$){
        my ($host,$port,$connected) = @_;
        diag "Failing to connect to $host:$port";
        $reconnected++;
        $! = Errno::ETIMEDOUT;
        undef
    };
};

use AnyEvent::FritzBox;
use AnyEvent::Util;

my $inbound;
my $remote;
my $done;

my $signal_done = AnyEvent->condvar;

my $fb = AnyEvent::FritzBox->new( 
    host => 'nohost.example', port => '666', # only used in error message
    max_retries => 3, # exponential growth is a bitch
    log => sub { diag @_ },
    on_ring => sub {
        $inbound++;
        my ($self, %args) = @_;
        $remote = $args{ remote_number }
    },
    on_connect => sub {},
    on_connect_fail => sub {
        diag "Stopping reconnect loop";
        $signal_done->send;
    },
    
);
isa_ok $fb, 'AnyEvent::FritzBox';

$signal_done->recv;

is $reconnected, 4, "Three attempts at reconnecting were made";

__DATA__
20.12.10 17:10:27;RING;0;069555555;666666;SIP2;
