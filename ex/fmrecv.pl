use common::sense;

use Radio::RTLSDR;

use PDL;
use PDL::Complex;
use PDL::Constants qw(PI);
use PDL::DSP::Fir::Simple;


my $freq = shift || 104.5;
$freq *= 1_000_000;


my $rf_sample_rate = 2_000_000;
my $audio_sample_rate = 50_000;


my $radio = Radio::RTLSDR->new(freq => $freq, sample_rate => $rf_sample_rate);


#open(my $audio_sink, '|-:raw', "play -t raw -r $audio_sample_rate -e float -b 32 -c 1 -")
open(my $audio_sink, '|-:raw', "pacat --stream-name fmrecv --format float32le --rate $audio_sample_rate --channels 1 --latency-msec 10")
  || die "couldn't run play (install sox): $!";


$radio->rx(sub {
  ## Prepare data

  my $data = pdl()->convert(byte)->reshape(length($_[0]));

  ${ $data->get_dataref } = $_[0];
  $data->upd_data();

  $data = $data->convert(float);

  $data -= 128;
  $data *= 1000000;

  my $I = $data->slice([0,-1,2]);
  my $Q = $data->slice([1,-1,2]);


  ## Decimate 4:1, 2000k -> 500k

  $I = PDL::DSP::Fir::Simple::filter($I, { fc => 0.12, N => 81, });
  $Q = PDL::DSP::Fir::Simple::filter($Q, { fc => 0.12, N => 81, });

  $I = $I->slice([0,-1,4]);
  $Q = $Q->slice([0,-1,4]);


  ## Demod

  my $prev = $I->slice([0, -2]) + (i * $Q->slice([0, -2]));
  my $curr = $I->slice([1, -1]) + (i * $Q->slice([1, -1]));

  my $deriv = ($prev->Cconj() * $curr)->Carg();

  $deriv = $deriv->append($deriv->at(-1)); ## FIXME: retain previous values


  ## Decimate 10:1, 500k -> 50k

  my $audio = PDL::DSP::Fir::Simple::filter($deriv, { fc => 0.4, N => 32 });

  $audio = $audio->slice([0,-1,10]);

  print $audio_sink ${ $audio->convert(float)->get_dataref };
});


$radio->run;
