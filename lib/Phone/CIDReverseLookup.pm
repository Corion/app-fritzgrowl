package Phone::CIDReverseLookup;
use strict;
use AnyEvent;
use AnyEvent::HTTP;
use Encode qw(decode);
use HTTP::FirstResponse;
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
            # +16016841121 - time service
            url => 'http://www.yellowpages.com/phone?phone_search_terms=${arealocal}#phone-searchform',
            xpath => '//div[@id="results"]/div[1]//div[@class="info"][1]/h3/a[1]/text()',
        },
        # For persons
        anywho_person => {
            url => 'http://anywhoyp.yellowpages.com/findaperson/phone?fap_terms[phone]=${arealocal}&fap_terms[searchtype]=phone',
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
    $args{ fetch } ||= HTTP::FirstResponse->new();
    bless \%args => $class
};

sub lookup {
    my ($self,$args,%search_args) = @_;
    croak "No number given" unless $search_args{ number };
    
    my $lookup = $lookup{ fallback };
    for (@countrycodes) {
        if ($search_args{number} =~ /\Q$_/) {
            # We found a better match via the appropriate country prefix
            $lookup = $lookup{ $_ };
            $search_args{ countrycode } ||= $_;
            $search_args{ arealocal } ||= substr $search_args{number}, length $_, 1000;
        };
    };
    $args->{ services } = $lookup;
    
    my @passthrough = qw< on_timeout on_found on_notfound >;
    $self->{ fetch }->fetch(
        $args,
        %search_args,
    );
    
};

1;