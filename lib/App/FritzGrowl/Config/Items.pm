package App::FritzGrowl::Config::Items;
use strict;
use Config::Spec::FromPod qw(parse_pod_config);

=head1 NAME

App::FritzGrowl::Config::Items - metadata on config items

=head1 SYNOPSIS

  use App::FritzGrowl::Config::Items;
  use App::FritzGrowl::Config::Getopt;
  App::FritzGrowl::Config::Getopt::get_options(
      \%App::FritzGrowl::Config::Items::items,
      @ARGV
  ) or die "Bad command line arguments";

=cut

use vars qw(%items $config_raw);

$config_raw = <<'=cut';

=head1 CONFIGURATION

=head2 C<< fritzbox HOST >>

=for config
    repeat  => 1,
    default => 'fritz.box',

FritzBox hostname/IP address

Specifies the hostname or IP address of your Fritz!Box.

Example:

  fritzbox 'fritz.box';

=head2 C<< growl_to HOST >>

=for config
    repeat  => 1,
    default => 'localhost',

Target hostname/IP address 

Specifies the hostname or IP address of the machine
that will listen for Growl messages. Defaults to the same machine
that this program is run on.

Example:

  growl_to 'my_desk';

=head2 C<< filter NUMBER >>

Local number filter

Specifies the filter for which local numbers you want notifications.
This filter is a regular expression. Leaving it empty will show
notifications on calls for all numbers.

Example:

  filter '55512[13]';
  # Notify on 555121 and 555123
  # 5551232 is a fax number

May appear only once.

=for config
    repeat  => 1,
    default => '',

=head2 C<< countrycode >>

=for config
    repeat  => 1,
    default => '+49',

The implicit country code, for incoming numbers without it.
The default is C<+49>, for Germany.

=head2 C<< areacode >>

=for config
    repeat  => 1,
    default => '69',

The implicit area code, for incoming numbers without it,
without a leading zero.
The default is C<69>, for Frankfurt.

=cut

# Parse the config items from the documentation
%items = parse_pod_config( $config_raw );

1;