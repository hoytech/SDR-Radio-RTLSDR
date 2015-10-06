package SDR::Radio::RTLSDR;

our $VERSION = '0.100';

require XSLoader;
XSLoader::load('SDR::Radio::RTLSDR', $VERSION);

use common::sense;
use AnyEvent;
use AnyEvent::Util;


sub new {
  my ($class, %args) = @_;

  my $self = {};
  bless $self, $class;

  $self->{ctx} = new_context();
  $self->{state} = 'IDLE';

  ($self->{perl_side_signalling_fh}, $self->{c_side_signalling_fh}) = AnyEvent::Util::portable_socketpair();

  die "couldn't create signalling socketpair: $!" if !$self->{perl_side_signalling_fh};

  _set_signalling_fd($self->{ctx}, fileno($self->{c_side_signalling_fh}));

  if (!$args{dont_handle_sigint}) {
    $SIG{INT} = sub {
      $self->stop;
      exit;
    };
  }

  return $self;
}

sub tx {
  die "SDR::Radio::RTLSDR does not support transmitting";
}

sub rx {
  my ($self, $cb) = @_;

  die "already in $self->{state} state" if $self->{state} ne 'IDLE';
  $self->{state} = 'RX';

  $self->{pipe_watcher} = AE::io $self->{perl_side_signalling_fh}, 0, sub {
    sysread $self->{perl_side_signalling_fh}, my $junk, 1; ## FIXME: non-blocking

    my $buffer = _copy_from_buffer($self->{ctx});

    $cb->($buffer);

    syswrite $self->{perl_side_signalling_fh}, "\x00";
  };

  _start_rx($self->{ctx});
}


sub frequency {
  my ($self, $freq) = @_;

  die "getter not implemented yet" if !defined $freq;

  _set_freq($self->{ctx}, $freq);
}

sub sample_rate {
  my ($self, $sample_rate) = @_;

  die "getter not implemented yet" if !defined $sample_rate;

  _set_sample_rate($self->{ctx}, $sample_rate);
}


sub stop {
  my ($self) = @_;

  if ($self->{state} eq 'RX') {
    $self->_stop_callback();
    _stop_rx($self->{ctx});
  } else {
    warn "called stop but in state '$self->{state}'";
  }
}


sub _stop_callback {
  my ($self) = @_;

  _set_terminate_callback_flag($self->{ctx});

  $self->{state} = 'TERM';

  syswrite $self->{perl_side_signalling_fh}, "\x00";

  $self->{pipe_watcher} = AE::io $self->{perl_side_signalling_fh}, 0, sub {
    sysread $self->{perl_side_signalling_fh}, my $junk, 1; ## FIXME: non-blocking

    delete $self->{pipe_watcher};
    delete $self->{state};
  };
}



sub run {
  my ($self) = @_;

  $self->{cv} = AE::cv;

  $self->{cv}->recv;
}



1;



__END__

=encoding utf-8

=head1 NAME

SDR::Radio::RTLSDR - Control RTL software defined radio devices

=head1 SYNOPSIS

    my $radio = SDR::Radio::RTLSDR->new;

    $radio->frequency(104_500_000);
    $radio->sample_rate(1_000_000);

    $radio->rx(sub {
      my $buffer = shift;

      ## Do stuff with buffer
    });

    $radio->run;

=head1 DESCRIPTION

=head1 SEE ALSO

L<SDR-Radio-RTLSDR github repo|https://github.com/hoytech/SDR-Radio-RTLSDR>

=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2015 Doug Hoyte.

This module is licensed under the same terms as perl itself.
