#!/usr/bin/perl

delete @command{keys %command};

@offline{connect}     = sub { return cmd_connect(@_);                    };
@offline{who}         = sub { return cmd_who(@_);                        };
@offline{create}      = sub { return cmd_create(@_);                     };
@offline{quit}        = sub { return cmd_quit(@_);                       };
@offline{huh}         = sub { return cmd_offline_huh(@_);                };
# ------------------------------------------------------------------------#
@command{say}        = { help => "Broadcast a message to everyone in the room",
                         fun  => sub { return &cmd_say(@_); }            };
@command{"\""}       = { help => @{@command{say}}{help},
                         fun  => sub { return &cmd_say(@_); },
                         nsp  => 1                                       };
@command{"`"}        = { help => "Direct a message to a person",
                         fun  => sub { return &cmd_to(@_); },
                         nsp  => 1                                       };
@command{"&"}        = { help => "Set an attribute on an object",
                         fun  => sub { return &cmd_set2(@_); },
                         nsp  => 1                                       };
@command{reload}     = { help => "Reload any changed perl code",
                         fun  => sub { return &cmd_reload_code(@_); }    };
@command{pose}       = { help => "Perform an action of your choosing",
                         fun  => sub { return &cmd_pose(@_); }           };
@command{":"}        = { help => @{@command{pose}}{help},
                         fun  => sub { return &cmd_pose(@_); },
                         nsp  => 1                                       };
@command{";"}        = { help => "Posing without a space after your name",
                         fun  => sub { return &cmd_pose(@_,1); },
                         nsp  => 1                                       };
@command{who}        = { help => "Display online users",
                         fun  => sub { return &cmd_who(@_); }            };
@command{whisper}    = { help => "Send a message to something nearby",
                         fun  => sub { return &cmd_whisper(@_); }        };
@command{doing}      = { help => "Display online users",
                         fun  => sub { return &cmd_who(@_,1); }          };
@command{"\@doing"}  = { help => "Set what your up to [visible in WHO]",
                         fun  => sub { return &cmd_doing(@_); }          };
@command{help}       = { help => "Help on internal commands",
                         fun  => sub { return &cmd_help(@_); }           };
@command{"\@dig"}    = { help => "Dig a room",
                         fun  => sub { return &cmd_dig(@_); }            };
@command{"look"}     = { help => "Look at an object or your current location",
                         fun  => sub { return &cmd_look(@_); }           };
@command{quit}       = { help => "Disconnect from the server",
                         fun  => sub { return cmd_quit(@_); }            };
@command{commit}     = { help => "Force a commit to mysql",
                         fun  => sub { return cmd_commit(@_); }          };
@command{"\@set"}    = { help => "Set attributes on an object",
                         fun  => sub { return cmd_set(@_); }             };
@command{"\@code"}   = { help => "Information on the current code base",
                         fun  => sub { return cmd_code(@_); }            };
@command{"\@cls"}    = { help => "Clear the console screen",
                         fun  => sub { return cmd_clear(@_); }           };
@command{"\@create"} = { help => "Create an object",
                         fun  => sub { return cmd_ATcreate(@_); }        };
@command{"print"}    = { help => "Print an internal variable",
                         fun  => sub { return cmd_print(@_); }           };
@command{"go"}       = { help => "Go through an exit",
                         fun  => sub { return cmd_go(@_); }              };
@command{"examine"}  = { help => "Examine an object in more detail",
                         fun  => sub { return cmd_ex(@_); }              };
@command{"\@last"}   = { help => "Information about your last connects",
                         fun  => sub { return cmd_last(@_); }            };
@command{"+time"}    = { help => "Returns the current time",
                         fun  => sub { cmd_time(@_); }};
@command{page}       = { help => "Send a message to people in other rooms",
                         fun  => sub { cmd_page(@_); }};
@command{take}       = { help => "Pick up an object",
                         fun  => sub { cmd_take(@_); }};
@command{drop}       = { help => "Drop an object you are carrying",
                         fun  => sub { cmd_drop(@_); }};
@command{"\@force"}  = { help => "Force an object/person to do something",
                         fun  => sub { cmd_force(@_); }};
@command{inventory}  = { help => "List what you are carrying",
                         fun  => sub { cmd_inventory(@_); }};
@command{enter}      = { help => "Enter an object",
                         fun  => sub { cmd_enter(@_); }};
@command{"\@name"}   = { help => "Change the name of an object",
                         fun  => sub { cmd_name(@_); }};
@command{"\@describe"}={ help => "Change the description of an object",
                         fun  => sub { cmd_describe(@_); }};
@command{"\@pemit"}  = { help => "Send a mesage to an object or person",
                         fun  => sub { cmd_pemit(@_); }};
@command{"think"}    = { help => "Send a mesage to just yourself",
                         fun  => sub { cmd_think(@_); }};
@command{"version"}  = { help => "Show the current version of the MUSH",
                         fun  => sub { cmd_version(@_); }};
@command{"\@link"}   = { help => "Set the destination location of an exit",
                         fun  => sub { cmd_link(@_); }};
@command{"\@teleport"}={ help => "Teleport an object somehwere else",
                         fun  => sub { cmd_teleport(@_); }};
@command{"\@open"}   = { help => "Open an exit to another room",
                         fun  => sub { cmd_open(@_); }};
@command{"\@exec"}   = { help => "Open an exit to another room",
                         fun  => sub { cmd_exec(@_); }};
@command{"\@uptime"} = { help => "Display the uptime of this server",
                         fun  => sub { cmd_uptime(@_); }};
@command{"\@destroy"}= { help => "Destroy an object",
                         fun  => sub { cmd_destroy(@_); }};
@command{"\@toad"} =   { help => "Destroy an player",
                         fun  => sub { cmd_toad(@_); }};
#@command{"\@update_hostname"} =   { help => "Perform hostname lookups on any connected player as needed",
#                         fun  => sub { cmd_update_hostname(@_); }};
@command{"\@list"}  =  { help => "List internal server data",
                         fun  => sub { cmd_list(@_); }};
@command{"score"}   =  { help => "Lists how many pennies you have",
                         fun  => sub { echo($user,"You have 0 pennies."); }};

@command{"\@recall"}=  { help => "Recall output sent to you",
                         fun  => sub { cmd_recall(@_); }};
@command{"\@socket "} ={ help => "open a connection to the internet",
                         fun  => sub { cmd_socket(@_); }};
@command{"\@password"}={ help => "Change your password",
                         fun  => sub { cmd_password(@_); }};
@command{"\@newpassword"}={ help => "Change someone else's password",
                         fun  => sub { cmd_newpassword(@_); }};
# --[ aliases ]-----------------------------------------------------------#

@command{"\@version"}= { fun  => sub { cmd_version(@_); }};
@command{e}          = { fun  => sub { cmd_ex(@_); }                     };
@command{p}          = { fun  => sub { cmd_page(@_); }                   };
@command{"huh"}      = { fun  => sub { return cmd_huh(@_); }             };
@command{w}          = { fun  => sub { return &cmd_whisper(@_); }        };
@command{i}          = { fun  => sub { return &cmd_inventory(@_); }      };
@command{"\@\@"}     = { fun  => sub { return;}                          };
 
# ------------------------------------------------------------------------#


sub cmd_huh         { echo($user,"Huh?  (Type \"help\" for help.)");     }
sub cmd_offline_huh { echo($user,getfile("login.txt"));                  }
sub cmd_version     { echo($user,"TeenyMUSH 0.1 [cmhudson\@gmail.com]"); }
sub cmd_exec        { echo($user,"Exec: '%s'\n",@_[1]); }

#
# BEGIN statement with including code, and most of socket_connect were
# copied from from: http://aspn.activestate.com/ASPN/Mail/Message/
# perl-win32-porters/1449297.
#
BEGIN {
   # This nonsense is needed in 5.6.1 and earlier -- I'm too lazy to
   # test if it's been fixed in 5.8.0.
   if( $^O eq 'MSWin32' ) {
      *EWOULDBLOCK = sub () { 10035 };
      *EINPROGRESS = sub () { 10036 };
      *IO::Socket::blocking = sub {
          my ($self, $blocking) = @_;
          my $nonblocking = $blocking ? "0" : "1";
          ioctl($self, 0x8004667e, $nonblocking);
      };
   } else {
      require Errno;
      import  Errno qw(EWOULDBLOCK EINPROGRESS);
   }
}

sub good_password
{
   my $txt = shift;

   if($txt !~ /^\s*.{8,999}\s*$/) {
      echo($user,"#-1 Passwords must be 8 characters or more");
      return 0;
   } elsif($txt !~ /[0-9]/) {
      echo($user,"#-1 Passwords must one digit [0-9]");
      return 0;
   } elsif($txt !~ /[A-Z]/) {
      echo($user,"#-1 Passwords must contain at least one upper case character");
      return 0;
   } elsif($txt !~ /[A-Z]/) {
      echo($user,"#-1 Passwords must contain at least one lower case character");
      return 0;
   } else {
      return 1;
   }
}

sub cmd_password
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {

      good_password($2) || return;

      if(one($db,"select obj_password ".
                 "  from object " .
                 " where obj_id = ? " .
                 "   and obj_password = password(?)",
                 $$user{obj_id},
                 $1
            )) {
        sql(e($db,1),
            "update object ".
            "   set obj_password = password(?) " . 
            " where obj_id = ?" ,
            $2,
            $$user{obj_id}
           );
        echo($user,"Your password has been updated.");
      } else {
        echo($user,"Invalid old password.");
      }
   } else {
      echo($user,"usage: \@password <old_password> = <new_password>");
   }
}

sub cmd_newpassword
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {

      my $player = locate_player($1) ||
         return err("Unknown player '%s' specified",$1);

      if(!controls($user,$player)) {
         return err("Permission denied.");
      }

      good_password($2) || return;

      sql(e($db,1),
          "update object ".
          "   set obj_password = password(?) " . 
          " where obj_id = ?" ,
          $2,
          $$player{obj_id}
         );
      echo($user,"The password for %s has been updated.",name($player));

   } else {
      echo($user,"usage: \@newpassword <player> = <new_password>");
   }
}


sub cmd_socket
{
   my $txt = shift;
   my $pending = 1;

   if(!hasflag($user,"SOCKET")) {
      return echo_room($user,"Permission Denied");
   } elsif($txt =~ /^\s*([^:]+)\s*:\s*(\d+)\s*$/ ||
           $txt =~ /^\s*([^:]+)\s* \s*(\d+)\s*$/) {
      my $addr = inet_aton($1) ||
         return echo_room($user,"Invalid hostname '%s' specified.",$1);
      my $sock = IO::Socket::INET->new(Proto=>'tcp') ||
         return echo_room($user,"Could not create socket");
      my $sockaddr = sockaddr_in($2, $addr) ||
         return echo_room($user,"Could not create SOCKET");
      $sock->connect($sockaddr) or                     # start connect to host
         $! == EWOULDBLOCK or $! == EINPROGRESS or         # and check status
         return echo_room($user,"Could not open connection");
      () = IO::Select->new($sock)->can_write(10)     # see if socket is pending
          or $pending = 2;
      defined($sock->blocking(1)) ||
         return echo_room($user,"Could not open a nonblocking connection");

      @connected{$sock} = {
         sock     => $sock,
         raw      => 1,
         hostname => $1,
         port     => $2, 
         loggedin => 0,
         owner    => $$user{obj_id}
      };

      $readable->add($sock);
      sql(e($db,1),
          "insert into socket " . 
          "(   obj_id, " .
          "    sck_start_time, " .
          "    sck_type, " . 
          "    sck_socket, " .
          "    sck_hostname, " .
          "    sck_port " .
          ") values ( ? , now(), ?, ?, ?, ? )",
               $$user{obj_id},
               2,
               $sock,
               $1,
               $2
         );
      echo_room($user,"Connection started to: %s:%s\n",$1,$2);
      printf($sock "QUIT\r\n");
   } else {
      echo_room($user,"usage: \@connect <hostname>:<port>");
   }
}

sub cmd_recall
{
    my $txt = shift;
    my ($qualifier,@args);

    @args[0] = $$user{obj_id};
    if($txt !~ /^\s*$/) {
       $qualifier = 'and lower(out_text) like ? ';
       @args[1] = lc('%' . $txt . '%');
    }

    echo_nolog($user,
               text("  select concat( " .
                    "            date_format(" .
                    "               out_timestamp, ".
                    "               '[%H:%s %m/%d/%y]  ' " .
                    "            ), " .
                    "            text " .
                    "         ) text ".
                    "    from (   select out_timestamp, " .
                    "                    out_text text " .
                    "               from output " .
                    "              where out_destination = ? " .
                    "                $qualifier " .
                    "           order by out_timestamp desc " .
                    "           limit 15 " .
                    "         ) tmp  " .
                    "order by out_timestamp",
                    @args
                   )
        );
}

sub cmd_uptime
{
    my $diff = time() - @info{server_start};
    my $days = int($diff / 86400);
    $diff -= $days * 86400;

    my $hours = int($diff / 3600);
    $diff -= $hours * 3600;

    my $minutes = int($diff / 60);

    echo($user,"Uptime: %s days, %s hours, %s minutes",$days,$hours,$minutes);
}

sub cmd_force
{
    my $txt = shift;

    if($txt =~ /^\s*([^ ]+)\s*=\s*/) {
      my $target = locate_object($user,$1,"LOCAL") ||
         return echo($user,"I can't find that");

      if(!controls($user,$target)) {
         return echo($user,"Permission Denied.");
      }

      my $result = force($target,$');

      if($result == -2) {
         return echo($user,"I don't see that.");
      } elsif($result == -3) {
         return echo($user,"Invalid command. Practice your Jedi mind tricks ".
                           "more.");
      } elsif($result == -4) {
         return echo($user,"Internal error. Unable to parse request");
      }
   } else {
      echo($user,"syntax: \@force <object> = <command>");
   }
}

sub cmd_list
{
   my $txt = shift;

   if($txt =~ /^\s*site.*$/) {
       echo($user,"%s",table("select ste_id Id, " .
                        "       ste_pattern Pattern, " .
                        "       vao_value Type,".
                        "       obj_name Creator, " .
                        "       ste_created_date Date" .
                        "  from site, object, valid_option " .
                        " where ste_created_by = obj_id " .
                        "   and vao_code = ste_type".
                        "   and vao_table = 'site'"
                       )
           );
   } else {
       echo($user,"Undefined option '%s' used.",$txt);
   }
}

sub cmd_destroy
{
   my $txt = shift;

   if($txt =~ /^\s*$/) {
       return echo($user,"syntax: \@destroy <object>");
   }

   my $target = locate_object($user,$txt,"LOCAL") ||
       return echo($user,"I can't find an object named '%s'",$txt);

   if(hasflag($target,"PLAYER")) {
      return echo($user,"Players are \@toaded not \@destroyed.");
   } elsif(!controls($user,$target)) {
      return echo($user,"Permission Denied.");
   }

   echo_room($target,"%s was destroyed.",name($target));
   echo_room($target,"%s has left.",name($target));
   sql($db,"delete from object where obj_id = ?",$$target{obj_id});

   if($$db{rows} != 1) {
      rollback;
      echo($user,"Internal error, object not deleted.");
   } else {
      echo($user,"Destroyed.");
      commit;
   }
}

sub cmd_toad
{
   my $txt = shift;

   if($txt =~ /^\s*$/) {
       return echo($user,"syntax: \@toad <object>");
   }

   my $target = locate_object($user,$txt,"LOCAL") ||
       return echo($user,"I can't find an object named '%s'",$txt);

   if(!hasflag($target,"PLAYER")) {
      return echo($user,"Only Players can be \@toaded");
   } elsif(!hasflag($user,"WIZARD")) {
      return echo($user,"Permission Denied.");
   }

   if(loc($target) ne loc($user)) {
      echo($user,"%s was \@toaded.",name($target));
   }

   echo_room($target,"%s was \@toaded.",name($target));
   echo_room($target,"%s has left.",name($target));
   sql($db,"delete from object where obj_id = ?",$$target{obj_id});

   if($$db{rows} != 1) {
      rollback;
      echo($user,"Internal error, object not deleted.");
   } else {
      commit;
   }
}



sub cmd_think
{
   my $txt = shift;

   echo($user,"%s",evaluate($txt));
}

sub cmd_pemit
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
      my $target = locate_object($user,$1,"local");
      if($target eq undef) {
         return echo($user,"I don't see that here");
      } 
      echo($target,"%s\n",evaluate($2));
   } else {
      echo($user,"syntax: \@pemit <object> = <message>");
   }
}

sub cmd_drop
{
   my $txt = shift;

   my $target = locate_object($user,$txt,"CONTENT") ||
      return echo($user,"I don't see that here.");

   move($target,fetch(loc($user))) ||
      return echo($user,"Internal error, unable to drop that object");

   # provide some visual feed back to the player
   echo_room($target,"%s dropped %s.",name($user),name($target));
   echo_room($target,"%s has arrived.",name($target));

   force($target,"look");
}

sub cmd_take
{
   my $txt = shift;

   my $target = locate_object($user,$txt,"LOCAL") ||
      return echo($user,"I don't see that here.");

   echo_room($target,"%s picks up %s.",name($user),name($target));
   echo_room($target,"%s has left.",name($target));

   move($target,$user) ||
      return echo($user,"Internal error, unable to pick up that object");

   # provide some visual feed back to the player
   echo_room($target,"%s picked up %s.",name($user),name($target));
   echo_room($target,"%s has arrived.",name($target));

   echo($target,"%s has picked you up.",name($user));
#   echo($user,"You have picked up %s.",name($target));
   force($target,"look");
}

sub cmd_name
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {
      my $target = locate_object($user,$1,"LOCAL") ||
         return echo($user,"I don't see that here.");
      my $name = trim($2);

      if(hasflag($target,"PLAYER") && inuse_player_name($2)) {
         return echo($user,"That name is already in use");
      } elsif($name =~ /^\s*(\#|\*)/) {
         return echo($user,"Invalid name. Names may not start with * or #");
      }

      sql($db,
          "update object " .
          "   set obj_name = ? " .
          " where obj_id = ?",
          $name,
          $$target{obj_id},
          );

      if($$db{rows} == 1) {
         echo_room($target,"%s is now known by %s\n",$2);
         echo($user,"Set.");
         $$target{obj_name} = $name;
         commit;
      } else {
         rollback;
         echo($user,"Internal error, name not updated.");
      }
   } else {
      echo($user,"syntax: \@name <object> = <new_name>");
   }
}

sub cmd_enter
{
   my $txt = shift;

   my $target = locate_object($user,$txt,"LOCAL") ||
      return echo($user,"I don't see that here.");

   echo_room($target,"%s enters %s.",name($user),name($target));
   echo_room($target,"%s has left.",name($user));

   move($user,$target) ||
      return echo($user,"Internal error, unable to pick up that object");

   # provide some visual feed back to the player
   echo_room($target,"%s entered %s.",name($user),name($target));
   echo_room($target,"%s has arrived.",name($user));

   echo($user,"You have entered %s.",name($target));
#   echo($user,"You have picked up %s.",name($target));
   force($user,"look");
}

sub cmd_time
{
   echo($user,"%s",scalar localtime());
}

sub cmd_to
{
    my $txt = shift;

    if($txt =~ /^\s*([^ ]+)\s*/) {
       my $tg = locate_object($user,$1,"LOCAL") ||
          return echo($user,"I don't see that here.");
       echo($user,"%s [to %s]: %s\n",$$user{obj_name},$$tg{obj_name},$');
       echo_room($user,"%s [to %s]: %s\n",$$user{obj_name},$$tg{obj_name},$');
    } else {
       echo($user,"syntax: `<person> <message>");
    }
}



sub whisper
{
   my ($target,$msg) = @_;

   my $obj = locate_object($user,$target,"LOCAL") ||
         return echo($user,"I don't see that here.");

   if($msg =~ /^\s*:/) {
      for my $con (connected_socket($obj)) {
         my $u = @connected{$con};
         echo($u,"You sense, %s %s",$$user{obj_name},trim($'));
      }
      echo($user,"%s senses, \"%s %s\"",$$obj{obj_name},
         $$user{obj_name},trim($'));
   } else {
      for my $con (connected_socket($obj)) {
         my $u = @connected{$con};
         echo($u,"%s whispers, \"%s\"",$$user{obj_name},trim($msg));
      }
      echo($user,"You whisper, \"%s\" to %s.",trim($msg),$$obj{obj_name});
   }
   $$user{last} = {} if(!defined $$user{last});
   @{$$user{last}}{whisper} = $$obj{obj_name};
}

#
# cmd_page
#    Person to person communication reguardless of location.
#
sub cmd_whisper
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*=/) {
      whisper($1,$');
   } elsif(defined $$user{last} && defined @{$$user{last}}{whisper}) {
      whisper(@{$$user{last}}{whisper},$txt);
   } else {                                                       # mistake
      echo($user,"usage: whisper <user> = <message>");
      echo($user,"       whisper <message>");
   }
}

sub page
{
   my ($target,$msg) = @_;

   my $target = locate_player($target,"online") ||
         return echo($user,"That player is not connected.");

   if($msg =~ /^\s*:/) {
      echo($target,"From afar, %s %s\n",$$user{obj_name},trim($'));
      echo($user,"Long distance to %s: %s %s",$$target{obj_name},
         $$user{obj_name},trim($'));
   } else {
      echo($target,"%s pages: %s\n",$$user{obj_name},trim($'));
      echo($user,"You paged %s with '%s'",$$target{obj_name},trim($msg));
   }

   $$user{last} = {} if(!defined $$user{last});
   @{$$user{last}}{page} = $$target{obj_name};
}

#
# cmd_page
#    Person to person communication reguardless of location.
#
sub cmd_page
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*=/) {                          # page pose
      page($1,$');
   } elsif(defined $$user{last} && defined @{$$user{last}}{page}) {
      page(@{$$user{last}}{page},$txt);
   } else {                                                       # mistake
      echo($user,"usage: page <user> = <message>");
      echo($user,"       page <message>");
   }
}

sub cmd_last
{
   my $txt = shift;
   my ($what,$extra, $hostname);

   # determine the target
   if($txt =~ /^\s*([^ ]+)\s*$/) {
      $what = locate_player($1,"anywhere") ||
         return echo($user,"Unknown player '%s'",$1);
      $what = $$what{obj_id};
   } else {
      $what = $$user{obj_id};
   }

   if($what eq $$user{obj_id} || hasflag($user,"WIZARD")) {
      $hostname = "con_hostname Hostname,";
   }

   # show target's total connections
   echo($user,"%s",
              table("  select obj_name Name, " .
                    "         $hostname " .
                    "         min(case " .
                    "                when con_type = 1 then " .
                    "                   con_timestamp " .
                    "         end) Connect, ".
                    "         min(case " .
                    "                when con_type = 2 then " .
                    "                   con_timestamp " .
                    "         end) Disconnect ".
                    "    from connect con, object obj, valid_option " .
                    "   where con.obj_id = obj.obj_id " .
                    "     and obj.obj_id = ? ".
                    "     and vao_table = 'connect' " .
                    "     and vao_code = con_type " .
                    "group by obj_name, con_hostname, con_socket ".
                    "order by con_timestamp desc " .
                    "   limit 10",
                    $what
                   )
        );
 
   if((my $val=one_val("select count(*) value " .
                       "  from connect " .
                       " where obj_id = ? " .
                       "   and con_type = 1 ",
                       $what
                      ))) {
      echo($user,"Total successful connects: %s\n",$val);
   } else {
      echo($user,"Total successful connects: N/A\n");
   }

   # show target's last 5 connection details
#   for my $hash (@{sql("    SELECT con.obj_id, " .
#                       "           con.con_timestamp con, " .
#                       "           con.con_hostname, " .
#                       "           ifnull(dis.con_timestamp,'N/A') dis " .
#                       "      FROM connect con " .
#                       " LEFT JOIN connect dis " .
#                       "        ON con.con_socket = dis.con_socket " .
#                       "       AND dis.con_type = 2 " .
#                       "     WHERE con.obj_id = ? AND con.con_type = 1 " .
#                       "  order by con.con_timestamp desc " .
#                       " limit 5",
#                       $what
#                )}) {
#      if($$hash{dis} eq 'N/A') {
#         echo($user,"   From: %s, On: %s for ** online **",
#            short_hn($$hash{con_hostname}),$$hash{con});
#      } else {
#         my $online = date_split(fuzzy($$hash{dis}) - fuzzy($$hash{con}));
#         if($$online{max_val} =~ /^(M|W|D)$/) {
#            $extra = sprintf("%s ",$$online{max_val} . $$online{max_val});
#         }
#    
#         echo($user,"   From: %s, On: %s for %s%02d:%02d\n",
#              short_hn($$hash{con_hostname}),
#              $$hash{con},
#              $extra,
#              $$online{h},
#              $$online{m}
#             );
#      }
#   }
}



#
# cmd_go
#    Move an object from one location to another via an exit.
#
sub cmd_go
{
   my $txt = shift;
   my ($hash,$dest);

   $txt =~ s/^\s+|\s+$//g;

   if($txt =~ /^\s*home\s*$/i) {
      echo($user,"There's no place like home...");
      echo($user,"There's no place like home...");
      echo($user,"There's no place like home...");
      echo_room($user,"%s goes home.",name($user));
      echo_room($user,"%s has left.",name($user));

      $dest = one("select obj2.* " .
                  "  from object obj1, " .
                  "       object obj2 " . 
                  " where obj1.obj_home = obj2.obj_id " .
                  "   and obj1.obj_id = ? " ,
                  $$user{obj_id});

      # default to room #0
      $dest = fetch(0) if($dest eq undef || !defined $$dest{obj_id});

   } else {
      # find the exit to go through
      $hash = locate_exit($txt) ||
         return echo($user,"I don't see an exit going %s.",$txt);
  
      # grab the destination object
      $dest = fetch($$hash{con_dest_id}) ||
         return echo($user,"That exit does not go anywhere");
      echo_room($user,"%s goes %s.",name($user),first($$hash{obj_name}));
      echo_room($user,"%s has left.",name($user),$$hash{obj_name});
   }

   # move it, move it, move it. I like to move it, move it.
   move($user,$dest) ||
      return echo($user,"Internal error, unable to go that direction");

   # provide some visual feed back to the player
   echo_room($user,"%s has arrived.",name($user));

   cmd_look();
}

sub cmd_teleport
{
   my $txt = shift;
   my ($target,$location);

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*/) {
      ($target,$location) = ($1,$2);
   } elsif($txt =~ /^\s*([^ ]+)\s*/) {
      ($target,$location) = ("#$$user{obj_id}",$1);
   } else {
      echo($user,"syntax: \@teleport <object> = <location>");
      echo($user,"        \@teleport <location>");
   }

   $target = locate_object($user,$target) ||
      return err("I don't see that object here.");

   $location = locate_object($user,$location) ||
      return err("I can't find that location");

   controls($user,$target) ||
      return err("Permission Denied.");

   controls($user,$location) ||
      return err("Permission Denied.");

   if(hasflag($location,"EXIT")) {
      if(loc($location) == loc($user) && loc($user) == loc($target)) {
         $location = fetch(destination($location));
      } else {
         return err("Permission Denied.");
      }
   }
   
   echo_room($user,"%s has left.",name($user));

   move($target,$location) ||
      return echo("Fatal error, unable to teleport to that location");

   echo_room($user,"%s has arrived.",name($user));

   force($target,"look");
}

#
# cmd_print
#    Provide some debuging information
#
sub cmd_print
{
   my $txt = shift;
   $txt =~ s/^\s+|\s+$//g;

   if(!hasflag($user,"WIZARD")) {
      echo($user,"Permission denied");
   } elsif($txt eq "connected") {
      echo($user,"%s",print_var(\%connected));
   } elsif($txt eq "connected_user") {
      echo($user,"%s",print_var(\%connected_user));
   } else {
      echo($user,"Invalid variable '%s' specified.",$txt);
   }
}

sub cmd_clear
{
   my $txt = shift;

   if($txt ne undef) {
      echo($user,"\@clear expect no arguments");
   } elsif(hasperm($user,"CLEAR")) {
      $| = 1;
      print "\033[2J";    #clear the screen
      print "\033[0;0H"; #jump to 0,0
      echo($user,"Done.");
   } else {
      echo($user,"Permission Denied.");
   }
}

sub cmd_code
{
   my ($tlines,$tsize);

   echo($user," %-30s    %8s   %8s","File","Bytes","Lines");
   echo($user," %s---%s---%s","-" x 32,"-" x 8,"-" x 8);
   for my $key (sort {@{@code{$a}}{size} <=> @{@code{$b}}{size}} keys %code) {
      echo($user,"| %-30s | %8s | %8s |\n",$key,@{@code{$key}}{size},
           @{@code{$key}}{lines});
      $tlines += @{@code{$key}}{lines};
      $tsize += @{@code{$key}}{size};
   }
   echo($user," %s+--%s+--%s|","-" x 32,"-" x 8,"-" x 8);
   echo($user," %-30s  | %8s | %8s |",undef,$tsize,$tlines);
   echo($user," %-30s   -%s---%s-",undef,"-" x 8,"-" x 8);
}

sub cmd_commit
{
   if(hasperm($user,"COMMIT")) {
      echo($user,"You force a commit to the database");
      commit($db);
   } else {
      commit($db);
      echo($user,"Permission Denied");
   }
}  

sub cmd_quit
{
   my $sock = $$user{sock};
   printf($sock "%s",getfile("logoff.txt"));
   server_disconnect($$user{sock});
}

sub cmd_help
{
   my $txt = shift;

   if($txt eq undef) {
      echo($user,"HELP\n\n");
      echo($user,"   This is the Ascii Server online help system\n\n");

      for my $key (sort keys %command) {
         if(defined @{@command{$key}}{help}) {
            echo($user,"   %-10s : %s\n",$key,@{@command{$key}}{help});
         }
      }
   } elsif(defined @command{trim(lc($txt))}) {
      echo($user,@{@command{trim(lc($txt))}}{help});
   } else {
      echo($user,"Unknown help item '%s' specified",trim(lc($txt)));
   }
}

sub cmd_create
{
   my $txt = shift;

   if($$user{site_restriction} == 3) {
      echo($user,"%s",getfile("registration.txt"));
   } elsif($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/) {
      if(inuse_player_name($1)) {
         echo($user,"That name is already in use");
      } else {
         $$user{obj_id} = create_object($1,$2,"PLAYER");
         $$user{obj_name} = $1;
         cmd_connect($txt);
      }
   } else {
      echo($user,"Invalid create command, try: create <user> <password>");
   }
}

sub create_exit
{
   my ($name,$in,$out,$verbose) = @_;

   my $exit = create_object($name,undef,"EXIT") ||
      return 0;

   move($exit,$in,1) || return 0;

   if($out ne undef) {
      link_exit($exit,$out,1) || return 0;
   }

   return $exit;
}


sub cmd_ATcreate
{
   my $txt = shift;

   if(quota_left($user) <= 0) {
      return err("You are out of QUOTA to create objects.");
   }

   my $dbref = create_object(trim($txt),undef,"OBJECT") ||
      return err("Unable to create object");

   echo($user,"Object created as: %s(#%sO)",trim($txt),$dbref);

   commit;
}

sub cmd_link
{
   my $txt = shift;
   my ($exit_name,$exit,$dest);

   if($txt =~ /^\s*([^ ]+)\s*=\s*here\s*$/i) {
      ($exit_name,$dest) = ($1,loc($user));
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*#(\d+)\s*$/) {
      ($exit_name,$dest) = ($1,$2);
   } else {
      echo($user,"syntax: \@link <exit> = <room_dbref>\n");
      echo($user,"        \@link <exit> = here\n");
   }

   my $loc = loc($user) ||
      return err("Unable to determine your location");

   my $exit = locate_object($user,$exit_name,"EXIT") ||
      return err("I don't see that here");

   if(!valid_dbref($exit)) {
      return err("%s not a valid object.",obj_name($exit,1));
   } elsif(!valid_dbref($dest)) {
      return err("%s not a valid object.",obj_name($exit,1));
   } elsif(!(controls($user,$loc) || hasflag($loc,"LINK_OK"))) {
      return err("You do not own this room and it is not LINK_OK");
   }
 
   $dest = fetch($dest);

   link_exit($exit,$dest) ||
      return err("Internal error while trying to link exit");

   echo($user,"Exit linked to %s#%d",$$dest{obj_name},$$dest{obj_id});
}


sub cmd_dig
{
   my $txt = shift;
   my ($room_name,$room,$in,$out);
  
   if($txt =~ /^\s*([^\=]+)\s*=\s*([^,]+)\s*,\s*(.+?)\s*$/ ||
      $txt =~ /^\s*([^=]+)\s*=\s*([^,]+)\s*$/ ||
      $txt =~ /^\s*([^=]+)\s*$/) {
      ($room_name,$in,$out) = ($1,$2,$3);
   } else {
      echo($user,"syntax: \@dig <RoomName> = <InExitName>,<OutExitName>");
      echo($user,"        \@dig <RoomName> = <InExitName>");
      echo($user,"        \@dig <RoomName>");
      return;
   }

   if($in ne undef && $out ne undef && quota_left($user) < 3) {
      return err("You need a quota of 3 or better to complete this \@dig");
   } elsif(($in ne undef || $out ne undef) && quota_left($user) < 2) {
      return err("You need a quota of 2 or better to complete this \@dig");
   } elsif($in eq undef && $out eq undef && quota_left($user) < 1) {
      return err("You are out of QUOTA to create objects");
   }

   !locate_exit($in,"EXACT") ||
      return err("Exit '%s' already exists in this location",$in);

   my $loc = loc($user) ||
      return err("Unable to determine your location");

   if(!(controls($user,$loc) || hasflag($loc,"LINK_OK"))) {
      return err("You do not own this room and it is not LINK_OK");
   }

   my $room = create_object($room_name,undef,"ROOM")||
      return err("Unable to create a new object");

   if($in ne undef || $out ne undef) {
      echo($user,"Room created as:         %s(#%sR)",$room_name,$room);
   } else {
      echo($user,"Room created as: %s(#%sR)",$room_name,$room);
   }

   my $loc = loc($user) ||
      return err("Unable to determine your location");

   if($in ne undef) {
      my $in_dbref = create_exit($in,$loc,$room);
 
      if($in_dbref eq undef) {
         return err("Unable to create exit '%s' going in to room",$in);
      }
      echo($user,"   In exit created as:   %s(#%sE)",$in,$in_dbref);
   }

   if($out ne undef) {
      my $out_dbref = create_exit($out,$room,$loc);
      if($out_dbref eq undef) {
         return err("Unable to create exit '%s' going out of room",$out);
      }
      echo($user,"   Out exit created as:  %s(#%sE)",$out,$out_dbref);
   }
   commit;
}

sub cmd_open
{
   my $txt = shift;
   my ($exit,$destination);
  
   if($txt =~ /^\s*([^=]+)\s*=\s*([^ ]+)\s*$/ ||
      $txt =~ /^\s*([^ ]+)\s*$/) {
      ($exit,$destination) = ($1,$2);
   } else {
      echo($user,"syntax: \@open <ExitName> = <destination>");
      echo($user,"        \@open <ExitName>");
      return;
   }

   if(quota_left($user) < 1) {
      return err("You are out of QUOTA to create objects");
   }

   !locate_exit($exit,"EXACT") ||
      return err("Exit '%s' already exists in this location",$exit);

   my $loc = loc($user) ||
      return err("Unable to determine your location");

   if(!(controls($user,$loc) || hasflag($loc,"ABODE"))) {
      return err("You do not own this room and it is not ABODE");
   }

   my $dest = locate_object($user,$destination) ||
      return err("I can't find that destination location");

   if(!(controls($user,$loc) || hasflag($loc,"LINK_OK"))) {
      return err("You do not own this room and it is not LINK_OK");
   }

   my $dbref = create_exit($exit,$loc,$dest) ||
      return err("Internal error, unable to create the exit");

   echo($user,"Exit created as %s(#%sE)",$exit,$dbref);

   commit;
}

#
# cmd_connect
#    Verify password, populate @connect / @connected_user hash. Allow player
#    to connected.
#
sub cmd_connect
{
   my $txt = shift;
   my $hash;
 
   if($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/) {              #parse player password
      if(($hash=one($db,"select * from object where lower(obj_name) = ?",$1))) {
         if(one($db,"select obj_password ".
                    "  from object " .
                    " where obj_id = ? " .
                    "   and obj_password = password(?)",
                    $$hash{obj_id},
                    $2
               )) {
            $$hash{connect_time} = time();
            for my $key (keys %$hash) {                # copy object structure
               $$user{$key} = $$hash{$key};
            }
            $$user{loggedin} = 1;
            if(!defined @connected_user{$$user{obj_id}}) {    # reverse lookup
               @connected_user{$$user{obj_id}} = {};                   # setup
            }
            @{@connected_user{$$user{obj_id}}}{$$user{sock}} = $$user{sock};

            sql(e($db,1),
                "insert into socket " .
                "( " . 
                "    obj_id, " . 
                "    sck_start_time, " .
                "    sck_hostname, " .
                "    sck_socket, " .
                "    sck_type " . 
                ") values ( ?, now(), ?, ?, ? ) ",
                     $$user{obj_id},
                     $$user{hostname},
                     $$user{sock},
                     1
               );

            sql(e($db,1),
                "insert into socket_history ".
                "( obj_id, " .
                "  sck_id, " .
                "  skh_hostname, " .
                "  skh_start_time, " .
                "  skh_success " .
                ") values ( " .
                "  ?, ?, ?, now(), 1 ".
                ")",
                $$user{obj_id},
                curval(),
                $$user{hostname}
               );

            commit($db);
            echo($user,getfile("motd.txt"));                       # show modt
            cmd_look();                                           # show room

            printf("    %s@%s\n",$$hash{obj_name},$$user{hostname});
            echo_room($user,"%s has connected.",name($user));          # users
         } else {
   printf("# got this far 1\n");
            sql(e($db,1),
                "insert into socket_history ".
                "( obj_id, " .
                "  skh_hostname, " .
                "  skh_start_time, " .
                "  skh_end_time, " .
                "  skh_success " .
                ") values ( " .
                "  ?, ?, now(), now(), 0 ".
                ")",
                $$hash{obj_id},
                $$user{hostname}
               );
            commit($db);

            echo($user,"Either that player does not exist, or has a " .
               "different password.");
         }
      } else {
         echo($$user{sock},"Either that player does not exist, or has a " .
              "different password.");
      }
   } else {
   printf("# got this far21\n");
      echo($user,"Invalid connect command, try: connect <user> <password>");
   }
}

#
# cmd_doing
#    Set the @doing that is visible from the WHO/Doing command
#
sub cmd_doing
{
   my $txt = shift;

   if($txt =~ /^\s*$/) {                            # no arguments provided
      sql(e($db,1),
          "update object " . 
          "   set obj_doing = NULL " .
          " where obj_id = ? ",
          $$user{obj_id}
         );
   } else {                                                # doing provided
      sql(e($db,1),
          "update object " . 
          "   set obj_doing = ? " .
          " where obj_id = ? ",
          $txt,
          $$user{obj_id}
         );
   }
   commit;
   echo($user,"Set.");
}


sub cmd_describe
{
   my $txt = shift;

   if($txt =~ /^\s*([^ \/]+)\s*=\s*(.*?)\s*$/) {
      cmd_set(trim($1) . "/DESCRIPTION=" . $2);
   } else {
      echo($user,"syntax: \@describe <object> = <Text of Description>");
   }
}

# @set object = wizard
# @set me/attribute
sub cmd_set
{
   my $txt = shift;
   my ($target,$attr,$value,$flag);

   if($txt =~ /^\s*([^ ]+)\/\s*([^ ]+)\s*=\s*(.*?)\s*$/) { # attribute
      ($target,$attr,$value) = (locate_object($user,$1),$2,$3);
      return echo($user,"Unknown object '%s'",$1) if !$target;
      controls($user,$target) || return echo($user,"Permission denied");
      set($target,$attr,$value);
      commit($db);
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) { # flag?
      ($target,$flag) = (locate_object($user,$1),$2);
      return echo($user,"Unknown object '%s'",$1) if !$target;
      controls($user,$target) || return echo($user,"Permission denied");

      echo($user,set_flag($target,$flag));
   } else {
      echo($user,"Usage: \@set <object>/<attribute> = <value>\n");
      return echo($user,"    or \@set <attribute> = <value>\n");
   }
}

sub cmd_ex
{
   my $txt = shift;
   my ($target,@exit,@content);

   if($txt =~ /^\s*(.+?)\s*$/) {
      $target = locate_object($user,$1) ||
         return echo($user,"I don't see that here.");
   } else {
      $target = loc_obj($user);
   }

   my $perm = controls($user,$target);

   echo($user,"%s",obj_name($target,$perm));
   my $owner = fetch(($$target{obj_owner} == -1) ? 0 : $$target{obj_owner});
   echo($user,"Owner: %s  Flags: %s",obj_name($owner,$perm),
      flag_list($target,1));

   if((my $desc = get($$target{obj_id},"DESCRIPTION"))) {
      echo($user,"%s",$desc) if $desc ne undef;
   }

   echo($user,"Created: %s\n",$$target{obj_created_date});

   if(hasflag($target,"PLAYER")) {
      if($perm) {
         echo($user,"Firstsite: %s\n",$$target{obj_created_by});
         echo($user,"Lastsite: %s\n",lastsite($$target{obj_id}));
      }
      echo($user,
           "Last: %s",
           one_val($db,
                   "select ifnull(max(con_timestamp),'N/A') value " .
                   "  from connect " .
                   " where obj_id = ?",
                   $$target{obj_id}
                  )
          );
   }

   if($perm) {
       for my $hash (@{sql($db,"select * from attribute atr " .
                               " where obj_id = ? ".
                               "  and atr_name not in ('DESCRIPTION') ".
                               " order by atr_name ",
                               $$target{obj_id}
                    )}) {
          echo($user,"%s: %s\n",$$hash{atr_name},$$hash{atr_value});
       }
   }

   for my $hash (@{sql($db," SELECT con.obj_id, obj_name " .
                           "    FROM content con, object obj, flag flg, " .
                           "         flag_definition fde " .
                           "   WHERE obj.obj_id = con.obj_id " .
                           "     AND flg.obj_id = obj.obj_id ".
                           "     AND fde.fde_flag_id = flg.fde_flag_id " .
                           "     AND con_source_id = ?  " .
                           "     AND fde.fde_name in ('PLAYER','OBJECT') " .
                           "ORDER BY con.con_created_date",
                           $$target{obj_id}
                          )}) {
      if($$user{obj_id} != $$hash{obj_id}) {
         push(@content,obj_name($hash,$perm));
      }
   }
   echo($user,"Contents:\n" . join("\n",@content)) if $#content > -1;

   if(hasflag($target,"EXIT")) {
      my $con = one("select * " . 
                    "  from content " .
                    " where obj_id = ?",
                    $$target{obj_id});
      if($con eq undef || $$con{con_source_id} eq undef) {
         echo($user,"Source: ** No where **");
      } else {
         my $src = fetch($$con{con_source_id});
         echo($user,"Source: %s",obj_name($src,$perm));
      }

      if($con eq undef || $$con{con_dest_id} eq undef) {
         echo($user,"Destination: ** No where **");
      } else {
         my $dst = fetch($$con{con_dest_id});
         echo($user,"Destination: %s",obj_name($dst,$perm));
      }
   }

   for my $hash (@{sql($db,"  SELECT obj_name, obj.obj_id " .
                           "    FROM content con, object obj, " . 
                           "         flag flg, flag_definition fde " .
                           "   WHERE con.obj_id = obj.obj_id " .
                           "     AND flg.obj_id = obj.obj_id " . 
                           "     AND fde.fde_flag_id = flg.fde_flag_id " .
                           "     AND con_source_id = ?  " .
                           "     AND fde.fde_name = 'EXIT' " .
                           "ORDER BY con_created_date",
                           $$target{obj_id}
                      )}) {
      push(@exit,obj_name($hash));
   }
   if($#exit >= 0) {
      echo($user,"Exits:");
      echo($user,join("\n",@exit));
   }

   if($perm && (hasflag($target,"PLAYER") || hasflag($target,"OBJECT"))) {
      echo($user,"Home: %s",obj_name(fetch($$target{obj_home}),$perm));
      echo($user,"Location: %s",obj_name(fetch(loc($target)),$perm));
   }
}

sub inventory
{
   my $obj = ($#_ == -1) ? $user : shift;
   my @result;
    my $perm = hasperm($user,"INVENTORY");

   for my $hash (@{sql($db,"  SELECT con.obj_id, obj_name " .
                           "    FROM content con, object obj, " .
                           "         flag flg, flag_definition fde ".
                           "   WHERE obj.obj_id = con.obj_id " .
                           "     AND flg.obj_id = obj.obj_id ".
                           "     AND flg.fde_flag_id = fde.fde_flag_id ".
                           "     AND con_source_id = ?  " .
                           "     AND fde.fde_name in ('OBJECT','PLAYER') " .
                           "ORDER BY con.con_created_date",
                           $$obj{obj_id}
                          )}) {
      if((loggedin($hash) && !same($user,$hash)) || !player($hash)) {
         push(@result,obj_name($hash,$perm));
      }
   }
   return \@result;
}

sub cmd_inventory
{
    my $inv = inventory();

    if($#$inv == -1) {
       echo($user,"You are not carrying anything.");
    } else {
       echo($user,"You are carrying:");
       for my $i (0 .. $#$inv) {
          echo($user,$$inv[$i]);
       }
    }
}

sub cmd_look
{
   my $txt = shift;
   my ($flag,$hash,@exit);

#   printf("%s",print_var($user));
   my $perm = hasperm($user,"LOOK");

   if($txt =~ /^\s*(.+?)\s*$/) {
      if(!($hash = locate_object($user,$1))) {
         return echo($user,"I don't see that here.");
      }
   } else {
      $hash = loc_obj($user);
   }

   echo($user,"%s",obj_name($hash,$perm));
   if((my $desc = get($$hash{obj_id},"DESCRIPTION"))) {
      echo($user,"%s",evaluate($desc)) if $desc ne undef;
   }

   for my $hash (@{sql($db,"  SELECT con.obj_id, obj_name " .
                           "    FROM content con, object obj, " .
                           "         flag flg, flag_definition fde ".
                           "   WHERE obj.obj_id = con.obj_id " .
                           "     AND flg.obj_id = obj.obj_id ".
                           "     AND flg.fde_flag_id = fde.fde_flag_id ".
                           "     AND con_source_id = ?  " .
                           "     AND fde.fde_name in ('OBJECT','PLAYER') " .
                           "ORDER BY con.con_created_date",
                           $$hash{obj_id}
                          )}) {
#      printf("WHO %s: loggedin='%s',same='%s',player='%s'\n",
#         $$hash{obj_name},loggedin($hash),!same($user,$hash),player($hash));
      if((loggedin($hash) && !same($user,$hash)) || !player($hash)) {
         if($flag eq undef) {
            echo($user,"Contents:");
            $flag = 1;
         }
         echo($user,obj_name($hash,$perm));
      }
   }
   for my $hash (@{sql($db,"  SELECT obj_name " .
                           "    FROM content con, object obj, " . 
                           "         flag flg, flag_definition fde ".
                           "   WHERE con.obj_id = obj.obj_id " .
                           "     AND flg.obj_id = obj.obj_id ".
                           "     AND flg.fde_flag_id = fde.fde_flag_id ".
                           "     AND con_source_id = ?  " .
                           "     AND fde.fde_name = 'EXIT' " .
                           "ORDER BY con_created_date",
                           $$hash{obj_id}
                      )}) {
      push(@exit,first($$hash{obj_name}));
   }
   if($#exit >= 0) {
      echo($user,"Exits:");
      echo($user,join("  ",@exit));
   }
   force($hash,get($hash,"ADESCRIBE"));
}

sub cmd_pose
{
   my ($txt,$flag) = evaluate(@_[0]),@_[1];

   echo($user,"%s%s%s",name($user),$flag ? "" : " ",$txt);
   echo_room($user,"%s %s",name($user),$txt);
}

sub cmd_set2
{
   my $txt = shift;

   if($txt =~ /^\s*([^ ]+)\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
      cmd_set("$2/$1=$3");
   } elsif($txt =~ /^\s*([^ ]+)\s*([^ ]+)\s*$/) {
      cmd_set("$2/$1=");
   } else {
      echo($user,"Unable to parse &attribute command");
   }
}

sub cmd_say
{
   my $txt = evaluate(shift);

   echo($user,"You say, \"%s\"",$txt);
   echo_room($user,"%s says, \"%s\"",name($user),$txt);
}

sub cmd_reload_code
{
   if(hasperm($user,"LOAD_CODE")) {
      my $result = load_all_code($user);

      if($result eq undef) {
         echo($user,"No code to load, no changes made.");
      } else {
         echo($user,"%s loads %s.\n",name($user),$result);
#         echo_room($user,"%s loads %s.\n",name($user),$result);
      }
   } else {
      echo($user,"Permission denied.");
   }
}


#Player Name        On For Idle  WHO WOULD MAKE THE BEST PRESIDENT?
#Thoran           3d 23:55   1h
#Finrod           4d 04:28  12h
#Dream            4d 09:59   4d  Groot
#Ivos             7d 14:03   2d
#Adrick          16d 18:35   0s
#RedWolf         63d 07:03   7h  The Who
#1234567890123451234567890
#6 Players logged in, 16 record, no maximum.

sub nvl
{
   return (@_[0] eq '') ? @_[1] : @_[0];
}

sub short_hn
{
   if(@_[0] =~ /[A-Za-z]/ && @_[0] =~ /\.([^\.]+)\.([^\.]+)$/) {
      return "*.$1.$2";
   } else {
      return @_[0];
   }
}

#
# cmd_who
#    Show the users who is conected. There is a priviledged version
#    and non-privileged version. The DOING command is just a non-priviledged
#    version of the WHO command.
#
sub cmd_who
{
   my ($txt,$flag) = @_;
   my ($max,@who,$idle,$count) = (2);
   my $hasperm = (hasperm($user,"WHO") && !$flag) ? 1 : 0;

   # query the database for connected user, location, and socket
   # details.
   for my $key (@{sql($db,
                    "select obj.*, " .
                    "       sck_start_time start_time, " .
                    "       sck_hostname, " .
                    "       sck_socket, " .
                    "       con_source_id " .
                    "  from socket sck, object obj, content con " .
                    " where sck_type = 1 " .
                    "   and sck.obj_id = obj.obj_id " .
                    "   and con.obj_id = obj.obj_id " .
                    " order by sck_start_time desc"
                   )}
               ) {
      if(length($$key{con_source_id}) > length($max)) {
         $max = length($$key{con_source_id});
      }
      push(@who,$key);
   }
      
   # show headers for normal / wiz who 
   if($hasperm) {
      echo($user,"%-15s%10s%5s %-*s %s","Player Name","On For","Idle",$max,
         "Loc","Hostname");
   } else {
      echo($user,"%-15s%10s%5s  %s","Player Name","On For","Idle","\@doing");
   }
   

   # generate detail for every connected user
   for my $hash (@who) {

      # determine idle details
      my $extra = @connected{$$hash{sck_socket}};
      if(defined $$extra{last}) {
         $idle = date_split(time() - @{$$extra{last}}{time});
      } else {
         $idle = { max_abr => 's' , max_val => 0 };
      }

      # determine connect time details
      my $online = date_split(time() - fuzzy($$hash{start_time}));
      if($$online{max_abr} =~ /^(M|w|d)$/) {
         $extra = sprintf("%4s",$$online{max_val} . $$online{max_abr});
      } else {
         $extra = "    ";
      } 

      # show connected user details
      if($hasperm) {
         echo($user,"%-15s%4s %02d:%02d %4s #%-*s %s",$$hash{obj_name},$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             $max,$$hash{con_source_id},
             short_hn($$hash{sck_hostname}));
      } else {
            echo($user,"%-14s%4s %02d:%02d  %4s  %s",name($hash),$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             $$hash{obj_doing});
      }
   }
   echo($user,"%d Players logged in",$#who+1);               # show totals
}



sub cmd_update_hostname
{
   echo($user,"Hostname Update: Started\n");
   for my $key (keys %connected) {
      my $who = @connected{$key};
      if($$who{hostname} =~ /^[\d\.]+$/) {
         my $orig = $$who{hostname};
         $$who{hostname} = server_hostname($$who{sock});
         echo($user,"Updating %s to %s\n",$orig,$$who{hostname});
      } else {
         echo($user,"%s is good.\n",$$who{hostname});
      }
   }
   echo($user,"Hostname Update: Done\n");
}

