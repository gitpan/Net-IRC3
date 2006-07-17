package Net::IRC3::Connection;
use strict;
use AnyEvent;
use IO::Socket::INET;
use Net::IRC3::Util qw/mk_msg parse_irc_msg/;

=head1 NAME

Net::IRC3::Connection - An IRC connection abstraction

=head1 SYNOPSIS

   #...
   $con->send_msg (undef, "PRIVMSG", "Hello there!", "yournick");
   #...

=head1 DESCRIPTION

The connection class. Here the actual interesting stuff can be done,
such as sending and receiving IRC messages.

=head2 METHODS

=over 4

=cut

sub new
{
  my $this = shift;
  my $class = ref($this) || $this;

  my $self = {
     cbs  => {},
     heap => {}
  };

  bless $self, $class;

  return $self;
}

=item B<connect ($host, $port)>

Tries to open a socket to the host C<$host> and the port C<$port>.
If an error occured it will die (use eval to catch the exception).

=cut

sub connect {
   my ($self, $host, $port) = @_;

   $self->{socket}
      and return;

   my $sock = IO::Socket::INET->new (
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Blocking => 0
   ) or die "couldn't connect to irc server '$host:$port': $!\n";;

   $self->{socket} = $sock;
   $self->{host}   = $host;
   $self->{port}   = $port;

   $self->{rw} =
      AnyEvent->io (poll => 'r', fh => $sock, cb => sub {
         my $l = sysread $sock, my $data, 1024;

         $self->feed_irc_data ($data);

         unless ($l) {

            if (defined $l) {
               $self->disconnect ("EOF from IRC server '$host:$port'");
               return;

            } else {
               $self->disconnect ("Error while reading from IRC server '$host:$port': $!");
               return;
            }
         }
      });
}

=item B<disconnect ($reason)>

Unregisters the connection in the main Net::IRC3 object, closes
the sockets and send a 'disconnect' event with C<$reason> as argument.

=cut

sub disconnect {
   my ($self, $reason) = @_;

   $self->event (disconnect => $reason);

   delete $self->{rw};
   delete $self->{ww};

   eval { $self->{socket}->close };
   delete $self->{socket};
}

=item B<heap ()>

Returns a hash reference that is local to this connection object
that lets you store any information you want.

=cut

sub heap {
   my ($self) = @_;
   return $self->{heap};
}

=item B<send_msg (@ircmsg)>

This function sends a message to the server. C<@ircmsg> is the argumentlist
for C<Net::IRC3::Util::mk_msg>.

=cut

sub send_msg {
   my ($self, @msg) = @_;

   $self->event (sent => @msg);

   $self->{socket} or return;

   my $data = mk_msg (@msg);

   my ($host, $port) = ($self->{host}, $self->{port});
   $self->{outbuf} .= $data;

   unless (defined $self->{ww}) {
      my $sock = $self->{socket};
      $self->{ww} =
         AnyEvent->io (poll => 'w', fh => $sock, cb => sub {
            my $l = syswrite $sock, $self->{outbuf};

            substr $self->{outbuf}, 0, $l, "";

            if (length ($self->{outbuf}) == 0) { delete $self->{ww} }

            unless ($l) {
               # XXX: is this behaviour correct or ok?
               $self->disconnect ("Error while writing to IRC server '$self->{host}:$self->{port}': $!");
               return;
            }
         });
   }
}

=item B<reg_cb ($cmd, $cb)> or B<reg_cb ($cmd1, $cb1, $cmd2, $cb2, ..., $cmdN, $cbN)>

This registers a callback in the connection class.
These callbacks will be called by internal events and
by IRC protocol commands. You can also specify multiple callback registrations.

The first argument to the callbacks is always the connection object
itself.

If a callback returns a false value, it will be unregistered.

NOTE: I<A callback has to return true to stay alive>

If C<$cmd> starts with 'irc_' the callback C<$cb> will be registered
for a IRC protocol command. The command is the suffix of C<$cmd> then.
The second argument to the callback is the message hash reference
that has the layout that is returned by C<Net::IRC3::Util::parse_irc_msg>.

With the special C<$cmd> 'irc_*' the callback will be called on I<any>
IRC command that is received.

EXAMPLE:

   $con->reg_cb (irc_privmsg => \&privmsg_handler);
   # privmsg_handler will be called if an IRC message
   # with the command 'PRIVMSG' arrives.

If C<$cmd> is not prefixed with a 'irc_' it will be called when an event
with the name C<$cmd> is emitted. The arguments to the callback depend
on the event that is emitted (but remember: the first argument will always be the
connection object)

Following events are emitted by this module and shouldn't be emitted
from a module user call to C<event>.

=over 4

=item B<disconnect $reason>

This event will be generated if the connection is somehow terminated.
It will also be emitted when C<disconnect> is called.
The second argument to the callback is C<$reason>, a string that contains
a clue about why the connection terminated.

If you want to reestablish a connection, call C<connect> again.

=item B<sent @ircmsg>

Emitted when a message (C<@ircmsg>) was sent to the server.
C<@ircmsg> are the arguments to C<Net::IRC3::Util::mk_msg>.

=item B<'*' $msg>
=item B<read $msg>

Emitted when a message (C<$msg>) was read from the server.
C<$msg> is the hash reference returned by C<Net::IRC3::Util::parse_irc_msg>;

=back

=cut

sub reg_cb {
   my ($self, %regs) = @_;

   for my $cmd (keys %regs) {
      my $cb = $regs{$cmd};

      if ($cmd =~ m/^irc_(\S+)/i) {
         push @{$self->{cbs}->{lc $1}}, $cb;

      } else {
         push @{$self->{events}->{$cmd}}, $cb;
      }
   }

   1;
}

=item B<event ($event, @args)>

This function emits an event with the name C<$event> and the arguments C<@args>.
The registerd callback that has been registered with C<reg_cb> will be called
with the first argument being the connection object and the rest of the arguments
being C<@args>.

EXAMPLE

   $con->reg_cb (test_event => sub { print "Yay, i love $_[1]!!\n");
   $con->event (test_event => "IRC");

   # will print "Yay, i love IRC!!\n"

=cut

sub event {
   my ($self, $ev, @arg) = @_;

   my $nxt = [];

   for (@{$self->{events}->{lc $ev}}) {
      $_->($self, @arg) and push @$nxt, $_;
   }

   $self->{events}->{lc $ev} = $nxt;
}

# internal function, called by the read callbacks above.
sub feed_irc_data {
   my ($self, $data) = @_;

   $self->{buffer} .= $data;

   my @msg;
   while ($self->{buffer} =~ s/^([^\015\012]*)\015?\012//) {
      push @msg, $1;
   }

   for (@msg) {
      my $m = parse_irc_msg ($_);

      $self->event (read => $m);

      my $nxt = [];

      for (@{$self->{cbs}->{lc $m->{command}}}) {
         $_->($self, $m) and push @$nxt, $_;
      }

      $self->{cbs}->{lc $m->{command}} = $nxt;

      $nxt = [];

      for (@{$self->{cbs}->{'*'}}) {
         $_->($self, $m) and push @$nxt, $_;
      }

      $self->{cbs}->{'*'} = $nxt;
   }
}


=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<Net::IRC3>

L<Net::IRC3::Client::Connection>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
