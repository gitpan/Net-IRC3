package Net::IRC3::Client::Connection;
use base "Net::IRC3::Connection";
use Net::IRC3::Util qw/prefix_nick/;

our $DEBUG;

=head1 NAME

Net::IRC3::Client::Connection - A highlevel IRC connection

=head1 SYNOPSIS

   use AnyEvent;
   use Net::IRC3::Client::Connection;

   my $c = AnyEvent->condvar;

   my $timer;
   my $con = new Net::IRC3::Client::Connection;

   $con->reg_cb (registered => sub { print "I'm in!\n"; 0 });
   $con->reg_cb (disconnect => sub { print "I'm out!\n"; 0 });
   $con->reg_cb (
      sent => sub {
         if ($_[2] eq 'PRIVMSG') {
            print "Sent message!\n";
            $timer = AnyEvent->timer (after => 1, cb => sub { $c->broadcast });
         }
         1
      }
   );

   $con->send_srv (PRIVMSG => "Hello there i'm the cool Net::IRC3 test script!", 'elmex');

   $con->connect ("localhost", 6667);
   $con->register (qw/testbot testbot testbot/);

   $c->wait;
   undef $timer;

   $con->disconnect;

=head1 DESCRIPTION

L<Net::IRC3::Client::Connection> is a highlevel client connection,
that manages all the stuff that noone wants to implement again and again
when handling with IRC. For example it PONGs the server or keeps track
of the users on a channel.

=head1 EVENTS

The following events are emitted by L<Net::IRC3::Client::Connection>.
Use C<reg_cb> as described in L<Net::IRC3::Connection> to register to such an
event.

=over 4

=item B<registered>

Emitted when the connection got successfully registered.

=item B<channel_add $channel @nicks>

Emitted when C<@nicks> are added to the channel C<$channel>,
this happens for example when someone JOINs a channel or when you
get a RPL_NAMREPLY (see RFC2812).

=item B<channel_remove $channel @nicks>

Emitted when C<@nicks> are removed from the channel C<$channel>,
happens for example when they PART, QUIT or get KICKed.

=item B<join $nick $channel $is_myself>

Emitted when C<$nick> enters the channel C<$channel> by JOINing.
C<$is_myself> is true if youself are the one who JOINs.

=item B<part $nick $channel $is_myself $msg>

Emitted when C<$nick> PARTs the channel C<$channel>.
C<$is_myself> is true if youself are the one who PARTs.
C<$msg> is the PART message.

=item B<quit $nick $msg>

Emitted when the nickname C<$nick> QUITs with the message C<$msg>.

=item B<publicmsg $channel $ircmsg>

Emitted for NOTICE and PRIVMSG where the target C<$channel> is a channel.
C<$ircmsg> is the original IRC message hash like it is returned by C<parse_irc_msg>.

=item B<privatemsg $nick $ircmsg>

Emitted for NOTICE and PRIVMSG where the target C<$nick> (most of the time you) is a nick.
C<$ircmsg> is the original IRC message hash like it is returned by C<parse_irc_msg>.

=back

=head1 METHODS

=over 4

=cut

sub new {
   my $this = shift;
   my $class = ref($this) || $this;
   my $self = $class->SUPER::new (@_);
   $self->reg_cb (irc_001     => \&welcome_cb);
   $self->reg_cb (irc_join    => \&join_cb);
   $self->reg_cb (irc_part    => \&part_cb);
   $self->reg_cb (irc_kick    => \&kick_cb);
   $self->reg_cb (irc_quit    => \&quit_cb);
   $self->reg_cb (irc_353     => \&namereply_cb);
   $self->reg_cb (irc_366     => \&endofnames_cb);
   $self->reg_cb (irc_ping    => \&ping_cb);

   $self->reg_cb (irc_privmsg => \&privmsg_cb);
   $self->reg_cb (irc_notice  => \&privmsg_cb);

   $self->reg_cb ('irc_*'     => \&debug_cb)
      if $DEBUG;
   $self->reg_cb ('irc_*'     => \&anymsg_cb);

   $self->reg_cb (channel_remove => \&channel_remove_event);
   $self->reg_cb (channel_add    => \&channel_add_event);

   return $self;
}

=item B<register ($nick, $user, $real)>

Sends the IRC registration commands NICK and USER.

=cut

sub register {
   my ($self, $nick, $user, $real) = @_;

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

This returns a hash reference. The keys are the currently joined channels. The values
are hash references which contain the joined nicks as key.

=cut

sub channel_list {
   my ($self) = @_;
   return $self->{channels};
}

=item B<send_srv ($command, $trailing, @params)>

This function sends an IRC message that is constructed by C<mk_msg (undef, $command, $trailing, @params)> (see L<Net::IRC3::Util>).
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


=item B<send_chan ($channel, $command, $trailing, @params))>

This function sends a message (constructed by C<mk_msg (undef, $command, $trailing, @params)>
to the server, like C<send_srv> only that it will queue the messages if it hasn't joined the
channel C<$channel> yet. The queued messages will be send once the connection successfully
JOINed the C<$channel>.

=cut

sub send_chan {
   my ($self, $chan, @msg) = @_;

   if ($self->{channels}->{lc $chan}) {
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
# Private utility functions
################################################################################

sub _was_me {
   my ($self, $msg) = @_;
   lc prefix_nick ($msg) eq lc $self->nick ()
}

################################################################################
# Callbacks
################################################################################

sub channel_remove_event {
   my ($self, $chan, @nicks) = @_;

   $chan = lc $chan;
   for my $nick (@nicks) {
      $nick = lc $nick;

      if ($nick eq lc $self->nick ()) {
         delete $self->{chan_queue}->{$chan};
         delete $self->{channels}->{$chan};
         last;
      } else {
         delete $self->{channels}->{$chan}->{$nick};
      }
   }

   1;
}

sub channel_add_event {
   my ($self, $chan, @nicks) = @_;
   $chan = lc $chan;

   for my $nick (@nicks) {
      $nick = lc $nick;

      if ($nick eq lc $self->nick ()) {
         for (@{$self->{chan_queue}->{$chan}}) {
            $self->send_msg (undef, @$_);
         }
      }

      $self->{channels}->{$chan}->{$nick} = 1;
   }


   1;
}

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

   my $targ = $msg->{params}->[0];
   if ($targ =~ m/^(?:[#+&]|![A-Z0-9]{5})/) {
      $self->event (publicmsg => $targ, $msg);

   } else {
      $self->event (privatemsg => $targ, $msg);
   }

   1;
}

sub welcome_cb {
   my ($self, $msg) = @_;

   $self->{connected} = 1;

   $self->event ('registered');

   for (@{$self->{con_queue}}) {
      $self->send_msg (undef, @$_);
   }

   1;
}

sub ping_cb {
   my ($self, $msg) = @_;
   $self->send_srv ("PONG", $msg->{params}->[0]);

   1;
}

sub namereply_cb {
   my ($self, $msg) = @_;
   my @nicks = split / /, $msg->{trailing};
   push @{$self->{_tmp_namereply}}, @nicks;
}

sub endofnames_cb {
   my ($self, $msg) = @_;
   my $chan = lc $msg->{params}->[1];
   $self->event (channel_add => $chan, map { s/^[@\+]//; $_ } @{delete $self->{_tmp_namereply}});
}

sub join_cb {
   my ($self, $msg) = @_;
   my $chan = $msg->{params}->[0];
   my $nick = prefix_nick ($msg);

   $self->event (join        => $nick, $chan, $self->_was_me ($msg));
   $self->event (channel_add => $chan, $nick);

   1;
}

sub part_cb {
   my ($self, $msg) = @_;
   my $chan = $msg->{params}->[0];
   my $nick = prefix_nick ($msg);

   $self->event (part           => $nick, $chan, $self->_was_me ($msg), $msg->{params}->[1]);
   $self->event (channel_remove => $chan, $nick);

   1;
}

sub kick_cb {
   my ($self, $msg) = @_;
   my $chan        = $msg->{params}->[0];
   my $kicked_nick = $msg->{params}->[1];

   $self->event (channel_remove => $chan, $kicked_nick);

   1;
}

sub quit_cb {
   my ($self, $msg) = @_;
   my $nick = prefix_nick ($msg);

   $self->event (quit => $nick, $msg->{params}->[1]);

   for (keys %{$self->{channels}}) {
      $self->event (channel_remove => $_, $nick);
   }
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

L<Net::IRC3::Connection>

RFC 2812 - Internet Relay Chat: Client Protocol

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
