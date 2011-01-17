#!perl -w
use strict;
use Test::More tests => 2;
use Data::Dumper;
use Errno;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket();

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

#my $signal_done = AnyEvent->condvar;

my $ok;
my $fb = AnyEvent::FritzBox->new( 
    host => 'nohost.example', port => '666', # only used in error message
    max_retries => 1, # exponential growth is a bitch
    log => sub { diag @_ },
    on_ring => sub {
        $inbound++;
        my ($self, %args) = @_;
        $remote = $args{ remote_number }
    },
   
) or $ok = 1;
is $fb, undef, 'No connect';
is $ok, 1;
