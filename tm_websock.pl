#!/usr/bin/perl

use Net::WebSocket::Server;   # See https://metacpan.org/pod/Net::WebSocket::Server

sub websock_init
{
   $websock = IO::Socket::INET->new( Listen    => 5,
                                     LocalPort => @info{"conf.websocket"},
                                     Proto     => 'tcp',
                                     Domain    => AF_INET,
                                     ReuseAddr => 1,
                                   )
   or die "failed to set up TCP listener: $!";

   $ws = Net::WebSocket::Server->new(
      listen => $websock,
      on_connect => sub { my( $serv, $conn ) = @_;
                          $conn->on( utf8 => sub{ processMessage( @_, 0 ) } );
                        },  
   );
   $ws->{select_readable}->add($websock);
   $ws->{conns} = {};
}

sub websock_io
{
   my $sock = shift;

   if( $sock == $ws->{listen} ) {
      my $sock = $ws->{listen}->accept;
      my $conn = new Net::WebSocket::Server::Connection(
                 socket => $sock, server => $ws );

      $ws->{conns}{$sock} = { conn     => $conn,
                              lastrecv => time,
                              ip       => server_hostname($sock)
                            };
      $ws->{select_readable}->add( $sock );
      $ws->{on_connect}($ws, $conn );
      @c{$conn} = $conn;
   } elsif( $ws->{watch_readable}{$sock} ) {
      $ws->{watch_readable}{$sock}{cb}( $ws , $sock );
   } elsif( $ws->{conns}{$sock} ) {
      my $connmeta = $ws->{conns}{$sock};
      $connmeta->{lastrecv} = time;
      $connmeta->{conn}->recv();
   } else {
      warn "filehandle $sock became readable, but no handler took " .
           "responsibility for it; removing it";
#      $ws->{select_readable}->remove( $sock );
   }

#   if( $ws->{watch_writable}{$sock} ) {
#      $ws->{watch_writable}{$sock}{cb}( $ws, $sock);
#   } else {
#      warn "filehandle $sock became writable, but no handler took ".
#           "responsibility for it; removing it";
#      $ws->{select_writable}->remove( $sock );
#   }

}

sub processMessage {
   my( $conn, $msg, $ssl ) = @_;

   $ssl = $ssl ? ',SSL' : '';
   my $from = 0;
   my $peeraddr = join( '.', unpack( 'C4', $conn->{socket}->peeraddr() ) );

   # Used to exit the script after 15min inactivity
   my $timeout = time;

   my $self = fetch(@info{"conf.webuser"});
   printf("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$msg);

   my $prog = mushrun(self   => $self,
                      runas  => $self,
                      source => 0,
                      cmd    => $msg,
                      hint   => "WEBSOCKET",
                      sock   => $conn,
                      output => []
                     );
   $$prog{sock} = $conn;
}


sub websock_wall
{
   my $txt = shift;

   my $hash = $ws->{conns};

   for my $key ( keys %$hash) {
      my $client = $$hash{$key}->{conn};
      $client->send_utf8("### Trigger ### $txt");
   }
}
