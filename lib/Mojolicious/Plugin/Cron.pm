use strict;
use warnings;

package Mojolicious::Plugin::Cron;
use Mojo::Base 'Mojolicious::Plugin';
use File::Spec;
use Fcntl ':flock';
use Mojo::File 'path';
use Mojo::IOLoop;
use Algorithm::Cron;

use Carp 'croak';

our $VERSION = "0.013";
use constant CRON_DIR => 'mojo_cron_dir';
use constant CRON_WINDOW => 20;    # 20 segs window lock semaphore taken
my $crondir;

sub register {
  my ($self, $app, $cronhashes) = @_;
  croak "No schedules found" unless ref $cronhashes eq 'HASH';
  $crondir = path(File::Spec->tmpdir)->child(CRON_DIR, $app->mode);
  if (ref((values %$cronhashes)[0]) eq 'CODE') {

    # special case, plugin => 'mm hh dd ...' => sub {}
    $self->_cron($app->moniker,
      {crontab => (keys %$cronhashes)[0], code => (values %$cronhashes)[0]});
  }
  else {
    $self->_cron($_, $cronhashes->{$_}) for keys %$cronhashes;
  }
}

sub _cron {
  my ($self, $sckey, $cronhash) = @_;
  my $code     = delete $cronhash->{code};
  my $all_proc = delete $cronhash->{all_proc} // '';
  my $test_key
    = delete $cronhash->{__test_key};    # __test_key is for test case only
  $sckey = $test_key // $sckey;

  $cronhash->{base} //= 'local';

  ref $cronhash->{crontab} eq ''
    or croak "crontab parameter for schedule $sckey not a string";
  ref $code eq 'CODE' or croak "code parameter for schedule $sckey is not CODE";

  my $cron = Algorithm::Cron->new(%$cronhash);
  my $time = time;

  # $all_proc, $code, $cron, $sckey and $time will be part of the $task clojure
  my $task;
  $task = sub {
    my ($semaphore, $handle);
    $time = $cron->next_time($time);
    if (!$all_proc) {
      $semaphore = $crondir->make_path->child(qq{$time.$sckey.lock});
      $handle = $semaphore->open('>>') or croak "Cannot open semaphore file $!";
    }
    Mojo::IOLoop->timer(
      ($time - time) => sub {
        if ($all_proc || flock($handle, (LOCK_EX | LOCK_NB))) {
          Mojo::IOLoop->timer(
            CRON_WINDOW,
            sub {
              flock($handle, LOCK_UN) or croak "Cannot unlock semaphore - $!";
              close $handle or croak "Cannot close unlocked semaphore - $!";
              unlink $semaphore
                or croak "Cannot unlink unlocked semaphore - $!";
            }
          ) unless $all_proc;
          $code->();
        }
        else {
          close $handle or croak "Cannot close locked semaphore - $!";
        }
        $task->();
      }
    );
  };
  $task->();
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Cron - a Cron-like helper for Mojolicious and Mojolicious::Lite projects

=head1 SYNOPSIS

  # Execute some job every 5 minutes, from 9 to 5

  # Mojolicious::Lite

  plugin Cron( '*/5 9-17 * * *' => sub {
      # do someting non-blocking but useful
  });

  # Mojolicious

  $self->plugin(Cron => '*/5 9-17 * * *' => sub {
      # same here
  });

# More than one schedule, or more options requires extended syntax

  plugin Cron => (
  sched1 => {
    base    => 'utc', # not needed for local base
    crontab => '*/10 15 * * *', # every 10 minutes starting at minute 15, every hour
    code    => sub {
      # job 1 here
    }
  },
  sched2 => {
    crontab => '*/15 15 * * *', # every 15 minutes starting at minute 15, every hour
    code    => sub {
      # job 2 here
    }
  });

=head1 DESCRIPTION

L<Mojolicious::Plugin::Cron> is a L<Mojolicious> plugin that allows to schedule tasks
 directly from inside a Mojolicious application.
You should not consider it as a *nix cron replacement, but as a method to make a proof of
concept of a project.

=head1 BASICS

When using preforked servers (as applications running with hypnotoad), some coordination
is needed so jobs are not executed several times.
L<Mojolicious::Plugin::Cron> uses standard Fcntl functions for that coordination, to assure
a platform-independent behavior.

=head1 METHODS

L<Mojolicious::Plugin::Cron> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new, {Cron => '* * * * *' => sub {}});

Register plugin in L<Mojolicious> application.

=head1 WINDOWS INSTALLATION

To install in windows environments, you need to force-install module
Test::Mock::Time, or testings will fail.

=head1 AUTHOR

Daniel Mantovani, C<dmanto@cpan.org>

=head1 COPYRIGHT AND LICENCE

Copyright 2018, Daniel Mantovani.

This library is free software; you may redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<Mojolicious::Plugins>, L<Algorithm::Cron>

=cut
