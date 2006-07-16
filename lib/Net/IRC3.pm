package Net::IRC3;
use strict;
use AnyEvent;
use IO::Socket::INET;
use Exporter;
our @ISA = qw/Exporter/;
our @EXPORT_OK =
   qw(mk_msg parse_irc_msg split_prefix prefix_nick
      prefix_user prefix_host);

our $ConnectionClass = 'Net::IRC3::Connection';

=head1 NAME

Net::IRC3 - An IRC Protocol module which is event system independend

=head1 VERSION

Version 0.2

=cut

our $VERSION = '0.2';

=head1 SYNOPSIS

   use Net::IRC3;

   my $irc3 = new Net::IRC3;

   my $con = $irc3->connect ("test.not.at.irc.net", 6667);

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

=item B<new ()>

This just creates a L<Net::IRC3> object, which is a management
class for creating and managing connections.

=cut

sub new
{
  my $this = shift;
  my $class = ref($this) || $this;

  my $self = { };

  bless $self, $class;

  return $self;
}

=item B<connect ($host, $port)>

Tries to open a socket to the host C<$host> and the port C<$port>.
If successfull it will return a L<Net::IRC3::Connection> object.
If an error occured it will die (use eval to catch the exception).

=cut

sub connect {
   my ($self, $host, $port) = @_;

   defined $self->{connections}->{"$host:$port"}
      and return;

   my $sock = IO::Socket::INET->new (
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Blocking => 0
   ) or die "couldn't connect to irc server '$host:$port': $!\n";;

   eval "require $ConnectionClass";
   my $con = $ConnectionClass->new ($self, $sock, $host, $port);

   $con->{rw} =
      AnyEvent->io (poll => 'r', fh => $sock, cb => sub {
         my $l = sysread $sock, my $data, 1024;

         $con->feed_irc_data ($data);

         unless ($l) {

            if (defined $l) {
               $con->disconnect ("EOF from IRC server '$host:$port'");
               return;

            } else {
               $con->disconnect ("Error while reading from IRC server '$host:$port': $!");
               return;
            }
         }
      });

   return $con;
}

=item B<connections ()>

Returns a key value list, where the key is C<"$host:$port"> and the
value is the connection object. Only 'active' connections are returned.
That means, if a connection is terminated somehow, it will also disappear
from this list.

=cut

sub connections {
   my ($self) = @_;
   return %{$self->{connections}};
}

=item B<connection ($host, $port)> or B<connection ("$host:$port")>

Returns the L<Net::IRC3::Connection> object for the C<$host> C<$port>
pair. If no such connection exists, undef is returned.

=cut

sub connection {
   my ($self, $host, $port) = @_;
   if ($host =~ m/^[^:]+:(\d+)$/) {
      return $self->{connections}->{$host}
   } else {
      return $self->{connections}->{$host.':'.$port}
   }
}

=back

=head1 FUNCTIONS

These are some utility functions that might come in handy when
handling the IRC protocol.

You can export these with eg.:

   use Net::IRC3 qw/parse_irc_msg/;

=over 4

=item B<parse_irc_msg ($ircline)>

This method parses the C<$ircline>, which is one line of the IRC protocol
without the trailing "\015\012".

It returns a hash which has the following entrys:

=over 4

=item prefix

The message prefix.

=item command

The IRC command.

=item params

The parameters to the IRC command in a array reference,
this includes the trailing parameter (the one after the ':' or
the 14th parameter).

=item trailing

This is set if there was a trailing parameter (the one after the ':' or
the 14th parameter).

=back

=cut

sub parse_irc_msg {
  my ($msg) = @_;

  my $cmd;
  my $pref;
  my $t;
  my @a;

  my $p = $msg =~ s/^(:([^ ]+)[ ])?([A-Za-z]+|\d{3})//;
  $pref = $2;
  $cmd = $3;

  my $i = 0;

  while ($msg =~ s/^[ ]([^ :\015\012\0][^ \015\012\0]*)//) {

    push @a, $1 if defined $1;
    if (++$i > 13) { last; }
  }

  if ($i == 14) {

    if ($msg =~ s/^[ ]:?([^\015\012\0]*)//) {
      $t = $1 if $1 ne "";
    }

  } else {

    if ($msg =~ s/^[ ]:([^\015\012\0]*)//) {
      $t = $1 if $1 ne "";
    }
  }

  push @a, $t if defined $t;

  my $m = { prefix => $pref, command => $cmd, params => \@a, trailing => $t };
  return $p ? $m : undef;
}

=item B<mk_msg ($prefix, $command, $trailing, @params)>

This function assembles a IRC message. The generated
message will look like (pseudo code!)

   :<prefix> <command> <params> :<trail>

Please refer to RFC 2812 how IRC messages normally look like.

The prefix and the trailing string will be omitted if they are C<undef>.

EXAMPLES:

   mk_msg (undef, "PRIVMSG", "you suck!", "magnus");
   # will return: "PRIVMSG magnus :you suck!\015\012"

   mk_msg (undef, "JOIN", undef, "#test");
   # will return: "JOIN #magnus\015\012"

=cut

sub mk_msg {
  my ($prefix, $command, $trail, @params) = @_;
  my $msg = "";

  $msg .= defined $prefix ? ":$prefix " : "";
  $msg .= "$command";

  # FIXME: params must be counted, and if > 13 they have to be
  # concationated with $trail
  map { $msg .= " $_" } @params;

  $msg .= defined $trail ? " :$trail" : "";
  $msg .= "\015\012";

  return $msg;
}

=item B<split_prefix ($prefix)>

This function splits an IRC user prefix as described by RFC 2817
into the three parts: nickname, user and host. Which will be
returned as a list with that order.

C<$prefix> can also be a hash like it is returned by C<parse_irc_msg>.

=cut

sub split_prefix {
   my ($prfx) = @_;

   if (ref ($prfx) eq 'HASH') {
      $prfx = $prfx->{prefix};
   }

   $prfx =~ m/^\s*([^!]*)!([^@]*)@(.*?)\s*$/;
   return ($1, $2, $3);
}

=item B<prefix_nick ($prefix)>

A shortcut to extract the nickname from the C<$prefix>.

C<$prefix> can also be a hash like it is returned by C<parse_irc_msg>.

=cut

sub prefix_nick {
   my ($prfx) = @_;
   return (split_prefix ($prfx))[0];
}

=item B<prefix_user ($prefix)>

A shortcut to extract the username from the C<$prefix>.

C<$prefix> can also be a hash like it is returned by C<parse_irc_msg>.

=cut

sub prefix_user {
   my ($prfx) = @_;
   return (split_prefix ($prfx))[1];
}

=item B<prefix_host ($prefix)>

A shortcut to extract the hostname from the C<$prefix>.

C<$prefix> can also be a hash like it is returned by C<parse_irc_msg>.

=cut

sub prefix_host {
   my ($self, $prfx) = @_;
   return (split_prefix ($prfx))[2];
}

=back

=head1 EXAMPLES

See the samples/ directory for some examples on how to use Net::IRC3.

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<Net::IRC3::Connection>

L<Net::IRC3::Client>

RFC 2812 - Internet Relay Chat: Client Protocol

=head1 BUGS

Please report any bugs or feature requests to
C<bug-net-irc3 at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-IRC3>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::IRC3

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-IRC3>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-IRC3>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-IRC3>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-IRC3>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Marc Lehmann for the new AnyEvent module!

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robin Redker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
