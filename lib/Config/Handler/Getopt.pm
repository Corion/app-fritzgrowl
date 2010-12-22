=head1 NAME

App::ImageStream::Config::Getopt - get command line options from a spec

=head1 SYNOPSIS

  use App::ImageStream::Config::Items;
  use App::ImageStream::Config::Getopt;
  App::ImageStream::Config::Getopt::get_options(
      \%App::ImageStream::Config::Items::items,
      @ARGV
  ) or die "Bad command line arguments";

=cut

sub get_options {
    my ($package,$spec,@options) = @_;
    
    my %handler;
    my $result;
    for my $item (values %$spec) {
        my $n = $item->{name};
        
        my ($opt,$fetch);
        $result->{$n} = [];
        
        if (0 == $item->{arg_count}) {
            $fetch = sub() { push @{ $result->{$n}}, 1; };
            $opt   = $n;
        } elsif (1 == $item->{arg_count}) {
            $fetch = $result->{$n};
            $opt   = "$n=s";
        } elsif (2 == $item->{arg_count}) {
            $fetch = $result->{$n};
            $opt   = "$n=s{$item->{arg_count}}";
        } else {
            warn "More than one argument is not supported by Getopt, got $item->{arg_count}"
        };
        push @options, $opt => $fetch;
    };
    return
        (GetOptions(@options), $result);
};

1;

__END__

=head1 SEE ALSO

L<App::ImageStream::Config::Items> for the data structure

=cut