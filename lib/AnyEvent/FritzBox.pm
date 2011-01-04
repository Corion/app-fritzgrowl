package AnyEvent::FritzBox;
use strict;
use List::MoreUtils qw( zip );
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;
use Scalar::Util qw(weaken);

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
    $args{ max_retries } ||= 10; # We always give up after 10 attempts to connect
    $args{ reconnect_cooldown } ||= 1; # Start value for the exponential falloff
    
    my $self = bless \%args => $class;
    my $s = $self;
    my $connected = AnyEvent->condvar;
    my $have_handle = AnyEvent->condvar(cb => sub {
        $s->setup_readline();
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
        #$self->{ handle }->stop_read;
        $have_handle->send();
    };
    
    # We are synchronous here in case there is no continuation passed in
    if ($self->{synchronous} or not $self->{on_connect}) {
        #warn "Waiting for connection";
        $connected->recv;
        #$self->{ handle }->start_read;# done anyway by the ->push_read
    };
    undef $connected; # clean up stuff held by closure
    #warn "Constructed";

    $self
};

sub setup_readline {
    my ($self) = @_;
    #warn "Setting up handle for $self";
    $self->{ handle }->on_read(sub {
        my $h = $_[0];
        $h->push_read( line => sub {
            #warn "READ: @_";
            $self->dispatch_line(@_);
        });
    });
};

sub connect {
    my ($self,$host,$port,$connected) = @_;
    tcp_connect $host, $port, sub {
        my ($fh) = @_;
        undef $self->{reconnect};
        if (! $fh) {
            #warn "Couldn't connect to $args{ host }:$args{ port }: $!";
            return;
        };
        $self->{current_reconnect_timeout} = 0;
        $self->{handle} = $self->setup_handle($fh);
        $self->{retried} = 0; # we got a connection
        $connected->send();
    };    
};

sub setup_handle {
    my ($s,$fh) = @_;
    weaken $s; # Create a weak self-ref for the closure
    $s->{handle} = AnyEvent::Handle->new(
        fh => $fh,
        on_error => sub {
            warn __PACKAGE__ . " error: $_[2]";
            $_[0]->destroy;
            # Try to reconnect here, after some timeout
            if ($s) {
                if ($s->{retried} >= $s->{max_retries}) {
                    # Well, somebody could hear this, somewhere
                    die "Maximum retries ($s->{max_retries}) reached trying to connect to $s->{host}:$s->{port}";
                };
                if (! $s->{reconnect} and $s->{retried}++ < $s->{max_retries}) {
                    $s->{current_reconnect_cooldown} = (($s->{current_reconnect_cooldown}||0) * 2)
                                                       || $s->{reconnect_cooldown};
                    warn "Reconnecting in $s->{current_reconnect_cooldown} seconds";
                    $s->{reconnect} ||= AnyEvent->timer(after => $s->{current_reconnect_cooldown}+rand(5), cb => sub {
                        warn "Reconnecting to $s->{host}:$s->{port}";
                        my $connected = AnyEvent->condvar();
                        $connected->cb(sub { warn "Reconnected" });
                        $s->connect($s->{host}, $s->{port}, $connected);
                    });
                };
            };
        },
    );
};

# Outbound calls: datum;CALL;ConnectionID;Nebenstelle;GenutzteNummer;AngerufeneNummer;
# Inbound calls: datum;RING;ConnectionID;Anrufer-Nr;Angerufene-Nummer;
# Connect: datum;CONNECT;ConnectionID;Nebenstelle;Nummer;
# Disconnect: datum;DISCONNECT;ConnectionID;dauerInSekunden;
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