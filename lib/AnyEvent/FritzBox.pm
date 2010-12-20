package AnyEvent::FritzBox;
use strict;
use List::MoreUtils qw( zip );
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Data::Dumper;

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
    
    if (! $args{ handle }) {
        $args{ host } ||= 'fritz.box';
        $args{ port } ||= 1012;
        
        tcp_connect $args{ host }, $args{ port }, sub {
            my ($fh) = @_
                or die "Couldn't connect to $self->{host}:$self->{port}: $!";
            $self->{handle} = AnyEvent::Handle->new(
                fh => $fh,
                on_error => sub {
                    warn __PACKAGE__ . " error: $_[2]";
                    $_[0]->destroy;
                },
            );
            $have_handle->send();
        };
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


# Outbound calls: datum;CALL;ConnectionID;Nebenstelle;GenutzteNummer;AngerufeneNummer;
# Inbound calls: datum;RING;ConnectionID;Anrufer-Nr;Angerufene-Nummer;
# Connect: datum;CONNECT;ConnectionID;Nebenstelle;Nummer;
# Disconnect: datum;DISCONNECT;ConnectionID;dauerInSekunden;
sub dispatch_line {
    my ($self, $handle, $payload) = @_;
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