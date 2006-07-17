package Net::IRC3::Util;
use strict;
use Exporter;
our @ISA = qw/Exporter/;
our @EXPORT_OK =
   qw(mk_msg parse_irc_msg split_prefix prefix_nick
      decode_ctcp prefix_user prefix_host);

=head1 NAME

Net::IRC3::Util - Common utilities that help with IRC protocol handling

=head1 SYNOPSIS

   use Net::IRC3 qw/parse_irc_msg mk_msg/;

   my $msgdata = mk_msg (undef, PRIVMSG 

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


=item B<decode_ctcp ($ircmsg)> or B<decode_ctcp ($line)>

=cut

sub decode_ctcp {
   my ($self, $msg) = @_;
   my $line = ref $msg ? $msg->{trailing} : $msg;
   my $msg = ref $msg ? $msg : { };

   if ($line =~ m/^\001(.*?)\001$/) {
      my $ctcpdata = $1;

      # XXX: implement!

   } else {
      return { trailing => $line };
   }


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

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

RFC 2812 - Internet Relay Chat: Client Protocol

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
