package AnyEvent::FritzBox;
use strict;
use List::MoreUtils qw( zip );
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;
use Scalar::Util qw(weaken blessed);

# Dial C<#96*5*> to enable the TCP call monitor

use vars qw< %indicator_map %field_map >;

%indicator_map = (
    CALL => 'on_call',
    RING => 'on_ring',
    CONNECT => 'on_connect',
    DISCONNECT => 'on_disconnect',
);

%field_map = (
    on_call       => [ qw[ date kind id local_id local_number remote_number provider ] ],
    on_ring       => [ qw[ date kind id remote_number local_number provider ] ],
    on_connect    => [ qw[ date kind id local_id remote_number ]],
    on_disconnect => [ qw[ date kind id seconds ]],
);

sub new {
    my ($class, %args) = @_;
    
    $args{ on_call } ||= sub {};
    $args{ on_ring } ||= sub {};
    $args{ on_disconnect } ||= sub {};
    $args{ on_connect_fail } ||= sub {};
    $args{ max_retries } ||= 10; # We always give up after 10 attempts to connect
    $args{ reconnect_cooldown } ||= 2; # Start value for the exponential falloff

    $args{ current_reconnect } = undef; # we are not (yet) reconnecting
    
    if ($args{ log } && !ref $args{ log }) {
        $args{ log } = sub { print "@_\n" };
    };
    
    my $self = bless \%args => $class;
    my $s = $self;
    my $connected = AnyEvent->condvar;
    my $have_handle = AnyEvent->condvar(cb => sub {
        $s->setup_handle($self->{ handle });
        #warn "Signalling we're done";
        $connected->send() if $connected;
        
        # This should be done more elegantly by
        # putting this into the callback of $connected
        #warn "Triggering 'on_connect'";
        unshift @_, $s;
        undef $s;
        goto &{ $s->{on_connect} }
           if $s->{on_connect};
    });
    
    if (! $self->{ handle }) {
        $self->{ host } ||= 'fritz.box';
        $self->{ port } ||= 1012;
        
        $self->connect( $self->{host}, $self->{port}, $have_handle);
    } else {        
        $have_handle->send();
    };
    
    # We are synchronous here in case there is no continuation passed in
    if ($self->{synchronous} or not $self->{on_connect}) {
        #warn "Waiting for connection";
        $connected->recv;
        #$self->{ handle }->start_read;# done anyway by the ->push_read
    };
    undef $connected; # clean up stuff held by closure

    $self
};

sub log {
    my $s = shift;
    my $l = $s->{log};
    goto &$l if $l;
};

sub connect {
    my ($self,$host,$port,$connected) = @_;
    if(! tcp_connect $host, $port, sub {
        my ($fh) = @_;
        if (! $fh) {
            $self->log("Couldn't connect to $host:$port");
            $self->timed_reconnect($host,$port,$connected); # launch reconnect timer
            return;
        };
        # we got a connection, reset our retry counters
        $self->{current_reconnect} = undef;
        $self->setup_handle($fh);
        
        $connected->send();
    }) {
        $self->log("Connect to $host:$port failed: $!");
        $self->timed_reconnect( $host, $port, $connected );
    };
};

sub timed_reconnect {
    my ($self,$host,$port) = @_;
    if (! $self->{current_reconnect}->{timer}) {
        if ($self->{current_reconnect}->{retried}++ < $self->{max_retries}) {
            # We add a fuzz delay of up to 2 seconds to prevent stampeding herds
            my $cooldown = $self->{reconnect_cooldown} ** $self->{current_reconnect}->{retried}
                         + rand(2);
            
            #$self->log( Dumper $self->{ current_reconnect });
            $self->log( "Reconnecting in $cooldown seconds" );
            
            $self->{current_reconnect}->{timer} ||= AnyEvent->timer(after => $cooldown, cb => sub {
                $self->log( "Reconnecting to $host:$port" );
                
                # Tell ourselves that our callback triggered
                delete $self->{current_reconnect}->{timer};
                my $connected = AnyEvent->condvar();
                $connected->cb(sub { $self->log( "Reconnected" )} );
                $self->connect($host, $port, $connected);
            });
        } else {
            $self->log("Maximum number of reconnects reached");
            $self->{on_connect_fail}->($host,$port);
            #die "No connection to $host:$port after $self->{max_retries}";
        };
    };
};

sub setup_handle {
    my ($self,$fh) = @_;
    if (not(blessed $fh and $fh->isa('AnyEvent::Handle'))) {
        $fh = AnyEvent::Handle->new(
            fh => $fh,
        );
    };
    $self->{handle} = $fh;
    
    $self->{ handle }->on_read(sub {
        my $h = $_[0];
        $h->push_read( line => sub {
            #warn "READ: @_";
            $self->dispatch_line(@_);
        });
    });
    
    #weaken $self;
    $self->{ handle }->on_error(sub {
        #warn "[" . __PACKAGE__ . "] socket error: $_[2]";
        $_[0]->destroy;
        # Try to reconnect here, after some timeout
        if ($self) {
            if ($self->{current_reconnect} && 
                $self->{current_reconnect}->{retried} >= $self->{max_retries}) {
                # Well, somebody could hear this, somewhere
                die "Maximum retries ($self->{max_retries}) reached trying to connect to $self->{host}:$self->{port}";
            };
            $self->timed_reconnect($self->{host}, $self->{port});
        };
    });
};

# Outbound calls: datum;CALL;ConnectionID;LocalExtension;usedNumber;calledNumber;
# Inbound calls: datum;RING;ConnectionID;callerId;localNumber;
# Connect: datum;CONNECT;ConnectionID;LocalExtension;Number;
# Disconnect: datum;DISCONNECT;ConnectionID;durationInSeconds;
sub dispatch_line {
    my ($self, $handle, $payload) = @_;
    $payload =~ s/\s+$//;
    return unless $payload;
    #warn "<<$payload>>";
    my @info = split /;/, $payload;
    my $arg_handler = $indicator_map{ $info[1] };
    #warn "Checking for \$self->{'$arg_handler'}";
    if (my $handler = $self->{ $arg_handler }) {
        #warn "Triggering '$arg_handler'";
        @_ = ($self, zip @{ $field_map{ $arg_handler } }, @info);
        goto &$handler;
    };
};

1;