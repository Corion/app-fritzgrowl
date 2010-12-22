package App::ImageStream::Config::DSL;
use strict;
use Path::Class;

=head1 NAME

App::ImageStream::Config::DSL - create a DSL from a config spec

=cut

sub parse_config {
    my ($package,$spec,$config_data,$config_source) = @_;
    $config_source ||= 'configuration';
    
    my $result = {};
    
    # XXX This should respect repeat counts
    
    my %handler;
    for my $item (values %$spec) {
        my $n = $item->{name};
        my $fetch;
        $result->{$n} = [];
        if (0 == $item->{arg_count}) {
            $fetch = sub() { push @{ $result->{$n}}, 1; };
        } elsif (1 == $item->{arg_count}) {
            $fetch = sub($) { push @{ $result->{$n} }, @_; };
        } elsif (2 == $item->{arg_count}) {
            $fetch = sub($$) { push @{ $result->{$n} }, [@_]; };
        } else {
            $fetch = sub($;) { push @{ $result->{$n}}, [@_]; };
        };
        $handler{$n} = $fetch;
    };

    my ($ok,$err);
    {
        my @handlers = keys %handler;
        my $cfg_str = "package " . __PACKAGE__ . ";\n#line $config_source#1\n$config_data\n;1";
        #warn $cfg_str;

        no strict 'refs';
        
        # We don't want to introduce another scope, as that will
        # negate the effect of the local:
        NEXT:
            my $n = shift @handlers;
            local *{$n} = $handler{ $n };
            goto NEXT
                if @handlers;
        
        $ok = eval $cfg_str;
        $err = $@;
    }

    if ($ok) {
        return $result
    } else {
        warn $err;
        return
    };
};

sub parse_config_file {
    my ($package,$spec,$fn) = @_;
    my $file = file($fn);
    my $content = $file->slurp;
    $package->parse_config($spec,$content,$fn);
};

1;

__END__

=head1 SEE ALSO

L<App::ImageStream::Config::Items> for the data structure

=cut