package HTTP::FirstResponse;
use strict;
use AnyEvent;
use AnyEvent::HTTP;
use Encode qw(decode);
use Carp qw(croak);
use HTML::TreeBuilder::XPath;
use URI::Escape;

sub new {
    my ($class,%args) = @_;
    $args{ timeout } ||= 5; # seconds
    bless \%args => $class
};

sub fetch {
    my ($self,$args,%search_args) = @_;
    my $services = $args->{ services };
    
    # You need to only specify one of timeout / notfound
    $args->{ on_notfound } ||= $args->{ on_timeout } ||= $args->{ on_notfound };
    $args->{ on_progress } ||= sub {};
    
    my $result;
    my @requests;
    my $notfound = AnyEvent->condvar;
    my $timeout;
    
    my $cleanup; $cleanup = sub {
        # Clean out all outstanding requests
        @requests = ();
        # Cleanup closed-over variables
        undef $self;
        undef $timeout;
        undef $notfound;
        undef $cleanup;
    };
    
    $timeout = AnyEvent->timer(
        after => $self->{timeout},
        cb => sub {
            $args->{ on_progress }->($self, "Timeout");
            if ($args->{on_timeout}) {
                $args->{on_timeout}->(\%search_args, $self);
            };
            $cleanup->();
        });
    
    
    for my $engine (keys %$services) {
        my $info = $services->{ $engine };
        $notfound->begin( sub {
            $args->{ on_progress }->($self, "Not found");
            if ($args->{ on_notfound }) {
                $args->{on_notfound}->(\%search_args, $self);
            }
            $cleanup->();
        });
        
        # Replace our tiny template language
        (my $url = $info->{ url }) =~ s/(\$\{(\w+)\})/exists $search_args{$2} ? uri_escape $search_args{ $2 } : $1 /ge;
        $args->{ on_progress }->($self, "Retrieving <$url>", $info);
        
        push @requests, http_get $url => sub {
            $args->{ on_progress }->($self, "Retrieved <$url>");
            if (! $result) {
                # Look at the headers to potentially upgrade the HTML
                # to utf8 if needed
                my $encoding = 'utf-8'; # wild guess
                $encoding = $1
                    if $_[1]->{"content-type"} =~ /charset=(.*)/i;
                my $html = decode( $encoding, $_[0] );
                
                if ($info->{ extract }) {
                    $result = $info->{ extract }->($info, \%search_args, $html);
                } elsif ($info->{ xpath }) {
                    $result = $self->extract_info($info, \%search_args, $html);
                };
                if ($result) {
                    $args->{ on_progress }->($self, "Found <$result> via $engine", $info, $result);
                    if ($args->{on_found}) {
                        #warn "Calling 'on_found'";
                        $args->{on_found}->({
                            result => $result,
                            search => \%search_args,
                            engine => $info
                        });
                    };
                    $cleanup->();
                } else {
                    $notfound->end;
                };
            };
        };
    };
};

sub extract_info {
    my ($self, $info, $search, $html) = @_;
    my $tree = HTML::TreeBuilder::XPath->new_from_content($html);
    my $result = $tree->findvalue($info->{xpath});
    $result
};

1;