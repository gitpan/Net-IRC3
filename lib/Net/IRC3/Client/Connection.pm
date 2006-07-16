package Net::IRC3::Client::Connection;
use base Net::IRC3::Connection;

our $DEBUG = 0;

=head1 NAME

Net::IRC3::Client::Connection - A highlevel IRC connection

=head1 SYNOPSIS

   use Net::IRC3::Client;

   my $irc3 = new Net::IRC3::Client;

   my $con = $irc3->connect ("test.not.at.irc.net", 6667);

   $con->register ("fancybot", "fancybot", "Mr. Fancybot");

   ...

=head1 DESCRIPTION

L<Net::IRC3> itself is a simple building block for an IRC client.
It manages connections and parses and constructs IRC messages.

L<Net::IRC3> is I<very> simple, if you don't want to care about
all the other things that a client still has to do (like replying to
PINGs and remembering who is on a channel), I recommend to read
the L<Net::IRC3::Client> page instead.

=head1 METHODS

=over 4

=item B<register ($nick, $user, $real)>

This function registers all the callbacks it needs and
then sends the IRC registration commands NICK and USER.

=cut

sub register {
   my ($self, $nick, $user, $real) = @_;

   $self->reg_cb (irc_001     => \&welcome_cb);
   $self->reg_cb (irc_join    => \&join_cb);
   $self->reg_cb (irc_part    => \&part_cb);
   $self->reg_cb (irc_353     => \&namereply_cb);
   $self->reg_cb (irc_366     => \&endofnames_cb);
   $self->reg_cb (irc_ping    => \&ping_cb);

   $self->reg_cb (irc_privmsg => \&privmsg_cb);
   $self->reg_cb (irc_notice  => \&privmsg_cb);

   $self->reg_cb ('irc_*'     => \&debug_cb)
      if $DEBUG;
   $self->reg_cb ('irc_*'     => \&anymsg_cb);

   $self->send_msg (undef, "NICK", undef, $nick);
   $self->send_msg (undef, "USER", $real || $nick, $user || $nick, "*", "0");

   $self->{nick} = $nick;
   $self->{user} = $user;
   $self->{real} = $real;
}

=item B<nick ()>

Returns the current nickname, under which this connection
is registered at the IRC server. It might be different from the
one that was passed to C<register> as a nick-collision might happened
on login.

=cut

sub nick { $_[0]->{nick} }

=item B<channel_list ()>

This returns a key value list of all channels this connection is currently JOINed.
The keys are the channel name and the values are hash references.

=cut

sub channel_list {
   my ($self) = @_;
   return keys %{$self->{channels}};
}

=item B<send_srv (@ircmsg)>

This function sends an IRC message that is constructed by C<mk_msg (@ircmsg)> (see L<Net::IRC3>).
If the connection isn't yet registered (for example if the connection is slow) and hasn't got a
welcome (IRC command 001) from the server yet, the IRC message is queued until it gets a welcome.

=cut

sub send_srv {
   my ($self, @msg) = @_;

   if ($self->{connected}) {
      $self->send_msg (undef, @msg);

   } else {
      push @{$self->{con_queue}}, \@msg;
   }
}

=item B<clear_srv_queue>

Clears the server send queue.

=cut

sub clear_srv_queue {
   my ($self) = @_;
   $self->{con_queue} = [];
}

=item B<send_chan ($channel, @ircmsg)>

This function sends a message to server, like C<send_srv> only that it will queue the messages
if it hasn't joined the channel C<$channel> yet. The queued messages will be send once
the connection successfully joined the C<$channel>.

=cut

sub send_chan {
   my ($self, $chan, @msg) = @_;

   if ($self->{channels}->{$chan}) {
      $self->send_msg (undef, @msg);

   } else {
      push @{$self->{chan_queue}->{lc $chan}}, \@msg;
   }
}

=item B<clear_chan_queue ($channel)>

Clears the channel queue of the channel C<$channel>.

=cut

sub clear_chan_queue {
   my ($self, $chan) = @_;
   $self->{chan_queue}->{lc $chan} = [];
}

################################################################################
# Callbacks
################################################################################

sub anymsg_cb {
   my ($self, $msg) = @_;

   my $cmd = lc $msg->{command};

   if (    $cmd ne "privmsg" 
       and $cmd ne "notice"
       and $cmd ne "part"
       and $cmd ne "join"
      ) 
   {
      $self->event (statmsg => $msg);
   }

   1;
}

sub privmsg_cb {
   my ($self, $msg) = @_;

   if ($msg->{params}->[0] =~ m/^[#!]/) {
      $self->event (chanmsg => $msg->{params}->[0], $msg);

   } else {
      $self->event (querymsg => $msg->{params}->[0], $msg);
   }

   1;
}

sub welcome_cb {
   my ($self, $msg) = @_;

   $self->{connected} = 1;

   for (@{$self->{con_queue}}) {
      $self->send_msg (undef, @$_);
      $self->event (connected => $chan);
   }

   1;
}

sub ping_cb {
   my ($self, $msg) = @_;
   $self->send_srv ("PONG", $msg->{params}->[0]);
}

sub namereply_cb {
   my ($self, $msg) = @_;

}

sub endofnames_cb {
   my ($self, $msg) = @_;
}

sub join_cb {
   my ($self, $msg) = @_;

   my $chan = lc $msg->{params}->[0];

   $self->{channels}->{$chan} = {};

   if (lc Net::IRC3::prefix_nick ($msg) eq lc $self->{nick}) {

      for (@{$self->{chan_queue}->{$chan}}) {
         $self->send_msg (undef, @$_);
      }

      $self->event (join => Net::IRC3::prefix_nick ($msg), $chan, 1);

   } else {
      $self->event (join => Net::IRC3::prefix_nick ($msg), $chan, 0);
   }

   1;
}

sub part_cb {
   my ($self, $msg) = @_;

   my $chan = lc $msg->{params}->[0];
   my $nick = lc Net::IRC3::prefix_nick ($msg);

   if ($self->{nick} eq $nick) {

      delete $self->{chan_queue}->{$chan};
      delete $self->{channels}->{$chan};
      $self->event (part => Net::IRC3::prefix_nick ($msg), $chan, 1, $msg->{params}->[1]);

   } else {
      $self->event (part => Net::IRC3::prefix_nick ($msg), $chan, 0, $msg->{params}->[1]);
   }

   1;
}

sub debug_cb {
   my ($self, $msg) = @_;
   print "$self->{h}:$self->{p} > ";
   my $par = delete $msg->{params};
   print (join " ", map { $_ => $msg->{$_} } sort keys %$msg);
   print " params:";
   print (join ",", @$par);
   print "\n";
}

=back

=head1 EXAMPLES

See samples/netirc3cl and other samples in samples/ for some examples on how to use Net::IRC3::Client::Connection.

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<Net::IRC3>

L<Net::IRC3::Client>

L<Net::IRC3::Client::Connection>

RFC 2812 - Internet Relay Chat: Client Protocol

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robin Redker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
