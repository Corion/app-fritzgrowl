package AnyEvent::CIDReverseLookup;
use strict;
use AnyEvent;
use AnyEvent::HTTP;
use Encode qw(decode);
use HTML::TreeBuilder::XPath;
use Carp qw(croak);

use vars qw(%lookup @countrycodes);

# Prefix-hash
%lookup = (
    '+49' => {
        klicktel => {
            url => 'http://www.klicktel.de/inverssuche/index/search?method=searchSimple&_dvform_posted=1&phoneNumber=${number}',
            xpath => '//a[@class="namelink"]//*[@class="fn"]/text()',
        },
        dasoertliche => {
            url => 'http://dasoertliche.de/Controller?kgs=&buab=&zbuab=&zvo_ok=0&js=no&districtfilter=&la=&choose=true&page=0&context=0&action=43&buc=&topKw=0&form_name=search_nat&kw=${number}&ci=&image=+',
            xpath => '//div[@id="entry_0"]//a[@class="preview"]/text()',
        },
    },
    '+1' => {
        # For people
        anywho_business => {
            url => 'http://www.yellowpages.com/phone?phone_search_terms=${arealocal}#phone-searchform',
            xpath => '//div[@id="results"]/div[1]//div[@class="info"][1]/h3/a[1]/text()',
        },
        # For persons
        anywho => {
            #url => 'http://anywhoyp.yellowpages.com/phone?phone_search_terms=${number}',
            url => 'http://anywhoyp.yellowpages.com/findaperson/phone?fap_terms[phone]=${arealocal}&fap_terms[searchtype]=phone',
            # +16016841121 - time service
            # +1212-568-7776 - "Betty Miller"
            xpath => '//ul[@id="results-list"]/li[1]/address/a/text()',
        },
    },
    'fallback' => {
        klicktel => {
            url => 'http://www.klicktel.de/inverssuche/index/search?method=searchSimple&_dvform_posted=1&phoneNumber=${number}',
            xpath => '//a[@class="namelink"]//*[@class="fn"]/text()',
        },
    },        
);

@countrycodes = reverse sort keys %lookup;

sub new {
    my ($class,%args) = @_;
    $args{ timeout } ||= 5; # seconds
    bless \%args => $class
};

sub lookup {
    my ($self,%args) = @_;
    croak "No number given" unless $args{ number };
    
    my $lookup = $lookup{ fallback };
    for (@countrycodes) {
        if ($args{number} =~ /\Q$_/) {
            # We found a better match via the appropriate country prefix
            $lookup = $lookup{ $_ };
            $args{ countrycode } = $_;
            $args{ arealocal } = substr $args{number}, length $_, 1000;
        };
    };
    
    # You need to only specify one of timeout / notfound
    $args{ on_notfound } ||= $args{ on_timeout } ||= $args{ on_notfound };
    
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
            #warn "Timeout";
            if ($args{on_timeout}) {
                $args{on_timeout}->({
                    number => $args{number},
                });
            };
            $cleanup->();
        });
    
    
    for my $engine (keys %$lookup) {
        my $info = $lookup->{ $engine };
        $notfound->begin( sub {
            #warn "Not found";
            if ($args{ on_notfound }) {
                $args{on_notfound}->({
                    number => $args{ number },
                });
            }
            $cleanup->();
        });
        
        (my $url = $info->{ url }) =~ s/(\$\{(\w+)\})/exists $args{$2} ? $args{ $2 } : $1 /ge;
        #warn "Retrieving <$url>";
        
        push @requests, http_get $url => sub {
            #warn "Retrieved <$url>";
            if (! $result) {
                # Look at the headers to potentially upgrade the HTML
                # to utf8 if needed
                use Data::Dumper;
                #warn Dumper $_[1]->{"content-type"};
                my $encoding = 'utf-8'; # wild guess
                $encoding = $1
                    if $_[1]->{"content-type"} =~ /charset=(.*)/i;
                my $html = decode( $encoding, $_[0] );
                
                $result ||= $self->extract_info($args{number}, $info, $html);
                if ($result) {
                    #warn "Found <$result> via $engine";
                    if ($args{on_found}) {
                        #warn "Calling 'on_found'";
                        $args{on_found}->({
                            name => $result,
                            number => $args{number},
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
    my ($self, $number, $info, $html) = @_;
    my $tree = HTML::TreeBuilder::XPath->new_from_content($html);
    #warn $info->{xpath};
    my $result = $tree->findvalue($info->{xpath});
    #warn $html;
    #warn $result;
    $result
};

1;