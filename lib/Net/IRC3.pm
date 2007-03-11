package Net::IRC3;
use strict;
use AnyEvent;
use IO::Socket::INET;

our $ConnectionClass = 'Net::IRC3::Connection';

=head1 NAME

Net::IRC3 - An event system independend IRC protocol module

=head1 VERSION

Version 0.5

=cut

our $VERSION = '0.5';

=head1 SYNOPSIS

Using the simplistic L<Net::IRC3::Connection>:

   use AnyEvent;
   use Net::IRC3::Connection;

   my $c = AnyEvent->condvar;

   my $con = new Net::IRC3::Connection;

   $con->connect ("localhost", 6667);

   $con->reg_cb (irc_001 => sub { print "$_[1]->{prefix} says i'm in the IRC: $_[1]->{trailing}!\n"; $c->broadcast; 0 });
   $con->send_msg (undef, NICK => undef, "testbot");
   $con->send_msg (undef, USER => 'testbot', "testbot", '*', '0');

   $c->wait;

Using the more sophisticatd L<Net::IRC3::Client::Connection>:

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

The L<Net::IRC3> module consists of L<Net::IRC3::Connection>, L<Net::IRC3::Client::Connection>
and L<Net::IRC3::Util>. L<Net::IRC3> only contains this documentation.
It manages connections and parses and constructs IRC messages.

L<Net::IRC3::Connection> is I<very> simple, if you don't want to care about
all the other things that a client still has to do (like replying to
PINGs and remembering who is on a channel), I recommend to read
the L<Net::IRC3::Client::Connection> page instead.

Note that the *::Connection module uses AnyEvent as it's IO event subsystem.
You can integrate them into any application with a event system
that AnyEvent has support for (eg. L<Gtk2> or L<Event>).

=head1 EXAMPLES

See the samples/ directory for some examples on how to use Net::IRC3.

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<Net::IRC3::Util>

L<Net::IRC3::Connection>

L<Net::IRC3::Client::Connection>

L<AnyEvent>

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

Copyright 2006 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
