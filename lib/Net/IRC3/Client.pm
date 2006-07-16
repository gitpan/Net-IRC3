package Net::IRC3::Client;
use base Net::IRC3;
$Net::IRC3::ConnectionClass = 'Net::IRC3::Client::Connection';

=head1 NAME

Net::IRC3::Connection - An IRC connection abstraction

=head1 SYNOPSIS

   my $irccl = new Net::IRC3::Client;

   my $con = $irccl->connect ($host, $port);
   #...
   $con->send_msg (undef, "PRIVMSG", "Hello there!", "yournick");
   #...

=head1 DESCRIPTION

This is the highlevel IRC client module, that will do lot's of stuff
you don't want to do yourself. Actually the interesting stuff is done in
L<Net::IRC3::Client::Connection>. So look there for a explanation of what
interesting stuff you can actually do.

(To be honest: This is just a wrapper module that sets C<$Net::IRC3::ConnectionClass> to C<'Net::IRC3::Client::Connection'>).

=head2 METHODS

The following methods work I<exactly> like the same functions
in L<Net::IRC3>, only that they will return L<Net::IRC3::Client::Connection> objects:

=over 4

=item B<connect ($host, $port)>

=item B<connections ()>

=item B<connection ()>

=back

=head1 EXAMPLES

See samples/netirc3cl and other samples in samples/ for some examples on how to use Net::IRC3::Client.

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<Net::IRC3>

L<Net::IRC3::Connection>

L<Net::IRC3::Client::Connection>

RFC 2812 - Internet Relay Chat: Client Protocol

=head1 COPYRIGHT & LICENSE

Copyright 2006 Robin Redker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
