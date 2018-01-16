#!/usr/bin/perl



#
# add_last_info
#
#    Add details about when a user last did something.
#
sub add_last_info
{
   my $cmd = shift;

   # create structure to hold last info if needed
   $$user{last} = {} if(!defined $$user{last});

   # populate last hash with the info
   my $last = $$user{last};
   $$last{time} = time();
   $$last{cmd} = $cmd;
}

sub trim
{
   my $txt = shift;

   $txt =~ s/^\s+|\s+$//g;
   return $txt;
}

# ste_type
#
# -- 1   close connection as soon as possible
# -- 2   show banned.txt
# -- 3   registration
# -- 4   open
#
sub add_site_restriction 
{
   my $sock = shift;

   my $hash=one($db,
                "select ifnull(min(ste_type),4) ste_type" .
                "  from site ".
                " where (lower(?) like lower(ste_pattern) ".
                "    or lower(?) like lower(ste_pattern))" .
                "   and ifnull(ste_end_date,now()) >= now()",
                $$sock{ip},
                $$sock{hostname}
               );
   $$sock{site_restriction} = $$hash{ste_type};
}

#
# lookup_command
#    Try to find a internal command, exit, or mush command to run.
#
sub lookup_command
{
   my ($self,$hash,$cmd,$txt,$type,$debug) =
      ($_[0],$_[1],lc($_[2]),$_[3],$_[4],$_[5]);
   my $match;

   if(defined $$hash{$cmd}) {                       # match on internal cmd
      return ($cmd,trim($txt));
   } elsif(defined $$hash{substr($cmd,0,1)} &&             # one letter cmd
           (defined @{$$hash{substr($cmd,0,1)}}{nsp} ||  # w/wo space after
            substr($cmd,1,1) eq " " ||                            # command
            length($cmd) == 1
           )
          ) {
      return (substr($cmd,0,1),trim(substr($cmd,1) . $txt));
   } else {                                     # match on partial cmd name
      $txt =~ s/^\s+|\s+$//g;
      for my $key (keys %$hash) {              #  find partial unique match
         if(substr($key,0,length($cmd)) eq $cmd) {
            if($match eq undef) {
               $match = $key;
            } else {
               $match = undef;
               last;
            }
         }
      }
      if($match ne undef) {                                  # found match
         return ($match,trim($txt));
      } elsif($$user{site_restriction} == 69) {
         return ('huh',trim($txt));
      } elsif($txt =~ /^\s*$/ && $type && locate_exit($self,$cmd)) {  # exit?
         return ("go",$cmd);
      } elsif(mush_command($self,$hash,trim($cmd . " " . $txt,1))) { #mush cmd
         return ("\@\@",$cmd . " " . $txt);    
      } else {                                                  # no match
         return ('huh',trim($txt));
      }
   }
}


sub add_telnet_data
{
   my($data,$txt) = @_;

   @info{io} = {} if(!defined @info{io});
   my $io = @info{io};

   if(!defined $$io{$$data{socket}}) {
      $$io{$$data{socket}} = {
         obj_id => $$data{obj_id},
         buffer => []
      };
   }
   my $stack = @{$$io{$$data{socket}}}{buffer};
   push(@$stack,$txt);
}

#
# server_process_line
#
#    A line of text has finally come in, see if its a valid command and
#    run it. Commands differ for if the user is connected or not.
#    This is also where some server crashes are detected.
#
sub server_process_line
{

   my ($hash,$input) = @_;

#   if($input !~ /^\s*$/) {
#      printf("#%s# '%s'\n",((defined $$hash{obj_id}) ? obj_name($hash) : "?"),
#      $input);
#   }
   my $data = @connected{$$hash{sock}};

   if(defined $$data{raw} && $$data{raw} == 1) {
      handle_object_listener($data,"%s",$input);
   } elsif(defined $$data{raw} && $$data{raw} == 2) {
     add_telnet_data($data,$input);
   } else {
      eval {                                                  # catch errors
         local $SIG{__DIE__} = sub {
            printf("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            printf("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            if(defined @info{sql_last}) {
               printf("LastSQL: '%s'\n",@info{sql_last});
               printf("         '%s'\n",@info{sql_last_args});
               delete @info{sql_last};
               delete @info{sql_last_args};
            }
            printf("%s",code("long"));
         };

         if($input =~ /^\s*([^ ]+)/ || $input =~ /^\s*$/) {
            $user = $hash;
            if($$user{site_restriction} == 69) {
               my ($cmd,$arg) = lookup_command($data,\%honey,$1,$',0);
               &{@honey{$cmd}}($arg);                            # invoke cmd
            } elsif(loggedin($hash) || hasflag($hash,"OBJECT")) {
               add_last_info($input);                                   #logit
               return mushrun(self   => $user,
                              runas  => $user,
                              source => 1,
                              cmd    => $input,
                             );
            } else {
               my ($cmd,$arg) = lookup_command($data,\%offline,$1,$',0);
               &{@offline{$cmd}}($hash,prog($user,$user),$arg);  # invoke cmd
            }
         }
      };

      if($@) {                                # oops., you sunk my battle ship
#         printf("# %s crashed the server with: %s\n%s",name($hash),$_[1],$@); 
#         printf("LastSQL: '%s'\n",@info{sql_last});
#         printf("         '%s'\n",@info{sql_last_args});
#         printf("         '%s'\n",@info{sql_last_code});
         my_rollback($db);
   
         my $msg = sprintf("%s crashed the server with: %s",name($hash),$_[1]);
         necho(self   => $hash,
               prog   => prog($hash,$hash),
               source => [ "%s",$msg ]
              );
         if($msg ne $$user{crash}) {
            necho(self   => $hash,
                  prog   => prog($hash,$hash),
                  room   => [ $hash, "%s",$msg ]
                 );
            $$user{crash} = $msg;
         }
         delete @$hash{buf};
      }
   }
}


#
# server_hostname
#    lookup the hostname based upon the ip address
#
sub server_hostname
{
   my $sock = shift;
   my $ip = $sock->peerhost;                           # contains ip address

   my $name = gethostbyaddr(inet_aton($ip),AF_INET);

   if($name eq undef || $name =~ /in-addr\.arpa$/) {
      return $ip;                            # last resort, return ip address
   } else {
      return $name;                                         # return hostname
   }
}

sub get_free_port
{
   my ($i,%used);
   my $max = (scalar keys %connected) + 2;

   for my $key (keys %connected) {
      my $hash = @connected{$key};
      if(defined $$hash{port}) {
         @used{$$hash{port}} = 1;
      };
   }

   for($i=1;$i < $max;$i++) {
      return $i if(!defined @used{$i});
   }

   return $i;                                        # should never happen
}


#
# server_handle_sockets
#    Open Handle all incoming I/O and try to sleep frequently enough
#    so that all of the cpu is not being used up.
#
sub server_handle_sockets
{
   eval {
      # wait for IO or 1 second
      my ($sockets) = IO::Select->select($readable,undef,undef,.4);
      my $buf;

      if(!defined @info{server_start} || @info{server_start} =~ /^\s*$/) {
         @info{server_start} = time();
      }

      # process any IO
      foreach my $s (@$sockets) {      # loop through active sockets [if any]
         if($s == $web) {                                # new web connection
            http_accept($s);
         } elsif(defined @http{$s}) {
            http_io($s);
         } elsif($s == $websock || defined $ws->{conns}{$s}) {
            websock_io($s);
         } elsif($s == $listener) {                     # new mush connection
            my $new = $listener->accept();                        # accept it
            if($new) {                                        # valid connect
               $readable->add($new);               # add 2 watch list 4 input
               my $hash = { sock => $new,             # store connect details
                            hostname => server_hostname($new),
                            ip       => $new->peerhost,
                            loggedin => 0,
                            raw      => 0,
                            start    => time(),
                            port     => get_free_port()
                          };
               add_site_restriction($hash);
               @connected{$new} = $hash;

               printf("# Connect from: %s [%s]\n",$$hash{hostname},ts());
               if($$hash{site_restriction} <= 2) {                  # banned
                  printf("   BANNED   [Booted]\n");
                  if($$hash{site_restriction} == 2) {
                     printf($new "%s",@info{"conf.badsite"});
                  }
                  server_disconnect(@{@connected{$new}}{sock});
               } elsif($$hash{site_restriction} == 69) {
                  printf($new "%s",getfile("honey.txt"));
               } else {
                  printf($new "%s\r\n",@info{"conf.login"});    #  show login
               }
            }                                                        
         } elsif(sysread($s,$buf,1024) <= 0) {          # socket disconnected
            server_disconnect($s);
         } else {                                          # socket has input
            $buf =~ s/\r//g;                                 # remove returns
#            $buf =~ tr/\x80-\xFF//d;
            $buf =~ s/\e\[[\d;]*[a-zA-Z]//g;
            @{@connected{$s}}{buf} .= $buf;                     # store input
          
                                                         # breakapart by line
#            while(defined @connected{$s} && @{@connected{$s}}{buf} =~ /\n/) {
            while(@{@connected{$s}}{buf} =~ /\n/) {
               @{@connected{$s}}{buf} = $';                # store left overs
#               if(@{@connected{$s}}{raw} > 0) {
#                  printf("#%s# %s\n",@{@connected{$s}}{raw},$`);
#               }

               server_process_line(@connected{$s},$`);         # process line
            }
         }
      }

     spin();

   };
   if($@){
      printf("Server Crashed, minimal details [main_loop]\n");
      printf("LastSQL: '%s'\n",@info{sql_last});
      printf("         '%s'\n",@info{sql_last_args});
      printf("%s\n---[end]-------\n",$@);
   }
}

#
# server_disconnect
#    Either the user has QUIT or disconnected, so handle the disconnect
#    approprately.
#
sub server_disconnect
{
   my $id = shift;

   # notify connected users of disconnect
   if(defined @connected{$id}) {
      my $hash = @connected{$id};
      my $prog = prog($hash,$hash);

      if(defined $$hash{raw} && $$hash{raw} > 0) {             # MUSH Socket
         if($$hash{buf} !~ /^\s*$/) {
            server_process_line($hash,$$hash{buf});    # process pending line
         }                                                   # needed for www
         necho(self => $hash,
               prog => $prog,
               "[ Connection closed ]"
              );
         sql($db,                             # delete socket table row
             "delete from socket " .
             " where sck_socket = ? ",
             $id
            );
         my_commit($db);
      } elsif(defined $$hash{connect_time}) {                # Player Socket
         necho(self => $hash,
               prog => $prog,
               room => [ $hash, "%s has disconnected.",name($hash) ]
              );
         echo_flag($hash,$prog,"CONNECTED,PLAYER,MONITOR",
                   "[Monitor] %s has disconnected.",name($hash));


         my $key = connected_user($hash);
         delete @{@connected_user{$$hash{obj_id}}}{$key};
         if(scalar keys %{@connected_user{$$hash{obj_id}}} == 0) {
            delete @connected_user{$$hash{obj_id}};
         }

         my $sck_id = one_val($db,                           # find socket id
                              "select sck_id value " .
                              "  from socket " .
                              " where sck_socket = ?" ,
                              $id
                             );

         if($sck_id ne undef) {
             sql($db,                                  # log disconnect time
                 "update socket_history " .
                 "   set skh_end_time = now() " .
                 " where sck_id = ? ",
                  $sck_id
                );
   
             sql($db,                             # delete socket table row
                 "delete from socket " .
                 " where sck_id = ? ",
                 $sck_id
                );
             my_commit($db);
         }
         printf($id "%s",@info{"conf.logoff"});
      }
   }

   # remove user out of the loop
   $readable->remove($id);
   $id->close;
   delete @connected{$id};
}

#
# server_start
#
#    Start listening on the specified port for new connections.
#
sub server_start
{
   read_config();
   read_atr_config();
   read_config();

   my $count = 0;

   if(@info{port} !~ /^\s*\d+\s*$/) {
      printf("Invalid Port of '%s' defined in tm_config.dat\n",@info{port}); 
      exit();
   }  else {
      printf("TeenyMUSH listening on port @info{port}\n");
      $listener = IO::Socket::INET->new(LocalPort => @info{port},
                                        Listen    => 1,
                                        Reuse     => 1
                                       );
   }
 
   if(@info{"conf.httpd"} ne undef) {
      if(@info{"conf.httpd"} =~ /^\s*(\d+)\s*$/) {
         printf("HTTP listening on port %s\n",@info{"conf.httpd"});

         $web = IO::Socket::INET->new(LocalPort => @info{"conf.httpd"},
                                      Listen    =>1,
                                      Reuse=>1
                                     );
      } else {
         printf("Invalid httpd port number specified in #0/conf.httpd");
      }
   }

   if(@info{"conf.websocket"} ne undef) {
      if(@info{"conf.websocket"} =~ /^\s*(\d+)\s*$/) {
         printf("Websocket listening on port %s\n",@info{"conf.websocket"});
         websock_init();
      } else {
         printf("Invalid websocket port number specified in #0/conf.websocket");
      }
   }

   if($ws eq undef) {                             # emulate websocket listener
      $ws = {};                                              # when not in use
      $ws->{select_readable} = IO::Select->new();
   }

   $ws->{select_readable}->add($listener);

   if(@info{"conf.httpd"} ne undef) {
      $ws->{select_readable}->add($web);
   }
   $readable = $ws->{select_readable};

   # main loop;
   while(1) {
#      eval {
         server_handle_sockets();
#      };
      if($@){
         printf("Server Crashed, minimal details [main_loop]\n");
         printf("LastSQL: '%s'\n",@info{sql_last});
         printf("         '%s'\n",@info{sql_last_args});
         printf("%s\n---[end]-------\n",$@);
      }
   }
}

1;
