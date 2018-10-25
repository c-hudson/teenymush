#!/usr/bin/perl

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
      tick_period => 1,
      on_connect => sub { my( $serv, $conn ) = @_;
                          $conn->on( ready =>      sub{ ws_login_screen(@_); },
                                     utf8  =>      sub{ ws_process( @_, 0 );},
                                     disconnect => sub { ws_disconnect(@_); },
                                   );
                        },  
   );
   $ws->{select_readable}->add($websock);
   $ws->{conns} = {};
}

sub ws_disconnect
{
    my ($conn, $code, $reason) = @_;

    my $sock = $conn->{socket};
    $ws->{select_readable}->remove( $conn->{socket} );
    server_disconnect( $conn->{socket} );
    $conn->disconnect();
    delete $ws->{conns}{$sock};
}

sub ws_login_screen
{
   my $conn = shift;

   ws_echo($conn->{socket}, @info{"conf.login"});
}

#
# ws_echo
#    The send might crash if the websocket has disconnected the evals should
#    probably be removed once this is more stable. With that in mind,
#    currently crash will be treated as a disconnect.
#
sub ws_echo
{
   my ($s, $msg) = @_;

   return if not defined @connected{$s};
   my $conn = @{@connected{$s}}{conn};
   # this might crash if the websocket dies, the evals should
   # probably be removed once this is more stable. With that in mind,
   # currently crash will be treated as a disconnect.
   eval {
      $conn->send('','t'.$msg);
   };

   if($@) {
       ws_disconnect($conn);
   }
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

      # attach the socket to the mush data structure 
      my $hash = { sock     => $sock,             # store connect details
                   conn     => $conn,
                   hostname => server_hostname($sock),
                   ip       => $sock->peerhost,
                   loggedin => 0,
                   raw      => 0,
                   start    => time(),
                   port     => get_free_port(),
                   type     => "WEBSOCKET"
                 };
      add_site_restriction($hash);
      @connected{$sock} = $hash;
   } elsif( $ws->{watch_readable}{$sock} ) {
      $ws->{watch_readable}{$sock}{cb}( $ws , $sock );
   } elsif( $ws->{conns}{$sock} ) {
      my $connmeta = $ws->{conns}{$sock};
      $connmeta->{lastrecv} = time;
      $connmeta->{conn}->recv();
   } else {
      warn "filehandle $sock became readable, but no handler took " .
           "responsibility for it; removing it";
      $ws->{select_readable}->remove( $sock );
   }

#   if( $ws->{watch_writable}{$sock} ) {
#      $ws->{watch_writable}{$sock}{cb}( $ws, $sock);
#   } else {
#      warn "filehandle $sock became writable, but no handler took ".
#           "responsibility for it; removing it";
#      $ws->{select_writable}->remove( $sock );
#   }

}

#
# ws_process
#    A message has come in via the websocket, hand it off to the MUSH
#    via the server_proces_line() function. The websocket client sends
#    a flag via the first character (text, html, and publeo, etc). 
#    Currently, that flag is just being stripped and ignored. Maybe
#    later?
#
sub ws_process {
   my( $conn, $msg, $ssl ) = @_;
   $msg =~ s/\r|\n//g;

   $ssl = $ssl ? ',SSL' : '';

   if($msg =~ /^#M# /) {
      printf("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$');
      @{$ws->{conns}{$conn->{socket}}}{type} = "NON_INTERACTIVE";
      my $self = fetch(@info{"conf.webuser"});

      my $prog = mushrun(self   => $self,
                         runas  => $self,
                         source => 0,
                         cmd    => $',
                         hint   => "WEBSOCKET",
                         sock   => $conn,
                         output => []
                        );
      $$prog{sock} = $conn;
   } else {
      printf("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$msg);
      $msg = substr($msg,1);
      server_process_line(@connected{$conn->{socket}},$msg);
   }
}


sub websock_wall
{
   my $txt = shift;

   my $hash = $ws->{conns};

   for my $key ( keys %$hash) {
      my $client = $$hash{$key}->{conn};

      if(@{$ws->{conns}{$client->{socket}}}{type} eq "NON_INTERACTIVE") {
         eval {
            $client->send_utf8("### Trigger ### $txt");
         };
         if($@) {
            ws_disconnect($client);
         }
      } else {
#         printf("Skipped $client\n");
      }
   }
}
