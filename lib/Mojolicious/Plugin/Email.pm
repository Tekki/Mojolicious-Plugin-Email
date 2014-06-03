package Mojolicious::Plugin::Email;
use Mojo::Base 'Mojolicious::Plugin';

use strict;
use warnings;

use Email::MIME;
use Email::Sender::Simple;
use Email::Sender::Transport::Test;
use Mojo::Loader;

our $VERSION = '0.07';

my %mail_method = (
  sendmail => {
    module => 'Email::Sender::Transport::Sendmail',
    params => {sendmail => '/usr/sbin/sendmail'}
  },
  smtp =>
    {module => 'Email::Sender::Transport::SMTP', params => {port => 25},},
  ssl => {
    module   => 'Email::Sender::Transport::SMTP',
    params   => {port => 465, ssl => 1},
    username => 'sasl_username',
    password => 'sasl_password',
  },
  tls => {
    module   => 'Email::Sender::Transport::SMTP::TLS',
    params   => {port => 587},
    username => 'username',
    password => 'password',
  },
);

sub register {
  my ($self, $app, $conf) = @_;

  $conf->{transport} ||= &_get_transport($conf);

  $app->helper(
    email => sub {
      my $self = shift;
      my $args = @_ ? {@_} : return;


      my @data = @{$args->{data}};

      my $format = $args->{format} || 'email';
      my %attributes = (
        charset      => $args->{charset}      || 'UTF-8',
        content_type => $args->{content_type} || 'text/html',
        encoding     => $args->{encoding}     || 'quoted-printable',
      );
      my $body = $self->render_to_string(@data, format => $format,);

      my $transport = &_get_transport($args, $conf);
      my $send_args = {transport => $transport};

      my $header = {@{$args->{header}}};

      $header->{From} ||= $conf->{from};
      $header->{Subject} ||= $self->stash('title');
      unless ($header->{'Message-ID'}) {
        $header->{From} =~ /@([^>]*)/;
        $header->{'Message-ID'} = '<' . time . int(rand(1e16)) . "\@$1>";
      }

      if ($header->{BCC}) {
        my @to = (delete $header->{BCC});
        for (qw|To CC|) {
          push @to, $header->{$_} if $header->{$_};
        }
        $send_args->{to} = \@to;
      }

      my $email = Email::MIME->create(
        header_str => [%{$header}],
        attributes => \%attributes,
        body_str   => $body
      );

      return Email::Sender::Simple->try_to_send($email, $send_args)
        if $transport;

      my $emailer = Email::Sender::Transport::Test->new;
      $emailer->send_email($email,
        {to => [$header->{To}], from => $header->{From}});
      return unless $emailer->{deliveries}->[0]->{successes}->[0];

    }
  );

}

sub _get_transport {
  my $rv;
  for my $config (@_) {
    if ($config->{transport}) {

      # transport already defined
      $rv = $config->{transport};
      last;

    } elsif ($config->{host} || $config->{method}) {

      # smart host
      my $method = $config->{method} || 'smtp';
      my $def = $mail_method{$method}
        || die qq|Undefined mail method: $method|;

      # load module
      my $module = $def->{module};
      my $e      = Mojo::Loader->load($module);
      die qq|Loading "$module" failed: $e| if ref $e;

      my $server_params = {host => $config->{host}};

      # authentication
      if ($def->{username}) {
        for (qw|username password|) {
          my $fld = $def->{$_};
          $server_params->{$fld} = $config->{$_} || die "$_ missing";
        }
      }

      # other params
      for (keys $def->{params}) {
        $server_params->{$_} = $config->{$_} || $def->{params}->{$_};
      }

      # create transport
      $rv = $module->new($server_params);
      last;
    }
  }

  return $rv;
}

1;

__END__
