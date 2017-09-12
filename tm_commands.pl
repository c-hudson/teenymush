#!/usr/bin/perl



delete @command{keys %command};
delete @offline{keys %offline};
delete @honey{keys %honey};

@offline{connect}     = sub { return cmd_connect(@_);                    };
@offline{who}         = sub { return cmd_who(@_);                        };
@offline{create}      = sub { return cmd_pcreate(@_);                     };
@offline{quit}        = sub { return cmd_quit(@_);                       };
@offline{huh}         = sub { return cmd_offline_huh(@_);                };
# ------------------------------------------------------------------------#
@honey{who}           = sub { return honey_who(@_);                      };
@honey{connect}       = sub { return honey_connect(@_);                  };
@honey{quit}          = sub { return cmd_quit(@_);                       };
@honey{honey_off}     = sub { return honey_off(@_);                      };
@honey{huh}           = sub { return honey_huh(@_);                      };
@honey{look}          = sub { return honey_look(@_);                     };
@honey{go}            = sub { return honey_go(@_);                       };
@honey{page}          = sub { return honey_page(@_);                     };
@honey{help}          = sub { return honey_help(@_);                     };
# ------------------------------------------------------------------------#
@command{"\@honey"}  = { help => "Put a user into the HoneyPot",
                         fun  => sub { return &cmd_honey(@_); }          };
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
                         fun  => sub { return &cmd_pose($_[0],$_[1],$_[2],1); },
                         nsp  => 1                                       };
@command{"emote"}    = { help => "Posing without a space after your name",
                         fun  => sub { return &cmd_pose($_[0],$_[1],$_[2],1); },
                         nsp  => 1                                       };
@command{who}        = { help => "Display online users",
                         fun  => sub { return &cmd_who(@_); }            };
@command{whisper}    = { help => "Send a message to something nearby",
                         fun  => sub { return &cmd_whisper(@_); }        };
@command{doing}      = { help => "Display online users",
                         fun  => sub { return &cmd_DOING(@_); }          };
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
@command{"\@commit"} = { help => "Force a commit to mysql",
                         fun  => sub { return cmd_commit(@_); }          };
@command{"\@set"}    = { help => "Set attributes on an object",
                         fun  => sub { return cmd_set(@_); }             };
@command{"\@code"}   = { help => "Information on the current code base",
                         fun  => sub { return cmd_code(@_); }            };
@command{"\@cls"}    = { help => "Clear the console screen",
                         fun  => sub { return cmd_clear(@_); }           };
@command{"\@create"} = { help => "Create an object",
                         fun  => sub { return cmd_create(@_); }        };
@command{"print"}    = { help => "Print an internal variable",
                         fun  => sub { return cmd_print(@_); }           };
@command{"go"}       = { help => "Go through an exit",
                         fun  => sub { return cmd_go(@_); }              };
@command{"examine"}  = { help => "Examine an object in more detail",
                         fun  => sub { return cmd_ex(@_); }              };
@command{"ex"}  =      { help => "Examine an object in more detail",
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
@command{leave}      = { help => "Leave an object",
                         fun  => sub { cmd_leave(@_); }};
@command{"\@name"}   = { help => "Change the name of an object",
                         fun  => sub { cmd_name(@_); }};
@command{"\@describe"}={ help => "Change the description of an object",
                         fun  => sub { cmd_describe(@_); }};
@command{"\@pemit"}  = { help => "Send a mesage to an object or person",
                         fun  => sub { cmd_pemit(@_); }};
@command{"\@emit"}   = { help => "Send a mesage to an object or person",
                         fun  => sub { cmd_emit(@_); }};
@command{"think"}    = { help => "Send a mesage to just yourself",
                         fun  => sub { cmd_think(@_); }};
@command{"version"}  = { help => "Show the current version of the MUSH",
                         fun  => sub { cmd_version(@_); }};
@command{"\@link"}   = { help => "Set the destination location of an exit",
                         fun  => sub { cmd_link(@_); }};
@command{"\@teleport"}={ help => "Teleport an object somewhere else",
                         fun  => sub { cmd_teleport(@_); }};
@command{"\@open"}   = { help => "Open an exit to another room",
                         fun  => sub { cmd_open(@_); }};
@command{"\@uptime"} = { help => "Display the uptime of this server",
                         fun  => sub { cmd_uptime(@_); }};
@command{"\@destroy"}= { help => "Destroy an object",
                         fun  => sub { cmd_destroy(@_); }};
@command{"\@toad"}   = { help => "Destroy an player",
                         fun  => sub { cmd_toad(@_); }};
@command{"\@sleep"}  = { help => "Pause the a program for X seconds",
                         fun  => sub { cmd_sleep(@_); }};
@command{"\@sweep"}  = { help => "Lists who/what is listening",
                         fun  => sub { cmd_sweep(@_); }};
@command{"\@list"}   = { help => "List internal server data",
                         fun  => sub { cmd_list(@_); }};
@command{"score"}    = { help => "Lists how many pennies you have",
                         fun  => sub { cmd_score(@_); }};
@command{"\@recall"} = { help => "Recall output sent to you",
                         fun  => sub { cmd_recall(@_); }};
@command{"\@telnet"} = { help => "open a connection to the internet",
                         fun  => sub { cmd_telnet(@_); }};
@command{"\@close"} = { help => "close a connection to the internet",
                         fun  => sub { cmd_close(@_); }};
@command{"\@reset"}  = { help => "Clear the telnet buffers",
                         fun  => sub { cmd_reset(@_); }};
@command{"\@send"}   = { help => "Send data to a connected socket",
                         fun  => sub { cmd_send(@_); }};
@command{"\@password"}={ help => "Change your password",
                         fun  => sub { cmd_password(@_); }};
@command{"\@newpassword"}={ help => "Change someone else's password",
                         fun  => sub { cmd_newpassword(@_); }};
@command{"\@switch"}  ={ help => "Compares strings then runs coresponding " .
                                 "commands",
                         fun  => sub { cmd_switch(@_); }};
@command{"\@select"}  ={ help => "Compares strings then runs coresponding " .
                                 "commands",
                         fun  => sub { cmd_switch(@_); }};
@command{"\@ps"}      ={ help => "Provide details about the engine queue",
                         fun  => sub { cmd_ps(@_); }};
@command{"\@kill"}    ={ help => "Kill a process",
                         fun  => sub { cmd_killpid(@_); }};
@command{"\@var"}     ={ help => "Set a local variable",
                         fun  => sub { cmd_var(@_); }};
@command{"\@dolist"}  ={ help => "Loop through a list of variables",
                         fun  => sub { cmd_dolist(@_); }};
@command{"\@while"}   ={ help => "Loop while an expression is true",
                         fun  => sub { cmd_while(@_); }};
@command{"\@crash"}   ={ help => "Crash the MUSH",
                         fun  => sub { my $foo; @{$$foo{crash}}; }};
@command{"\@\@"}     = { help => "A comment, will be ignored ",
                         fun  => sub { return;}                          };
@command{"\@lock"}   = { help => "Test Command",
                         fun  => sub { cmd_lock(@_);}                    };
@command{"\@boot"}   = { help => "Severs the player's connection to the game",
                         fun  => sub { cmd_boot(@_);}                    };
@command{"\@readcache"}={ help => "Re-reads the servers config file(s)",
                         fun  => sub { cmd_readcache(@_);}               };
@command{"\@halt"}   = { help => "Stops all your running programs.",
                         fun  => sub { cmd_halt(@_);}                    };
# --[ aliases ]-----------------------------------------------------------#

@command{"\@version"}= { fun  => sub { cmd_version(@_); },
                         alias=> 1                                       };
@command{e}          = { fun  => sub { cmd_ex(@_); },                       
                         alias=> 1                                       };
@command{p}          = { fun  => sub { cmd_page(@_); },
                         alias=> 1                                       };
@command{"huh"}      = { fun  => sub { return cmd_huh(@_); },
                         alias=> 1                                       };
@command{w}          = { fun  => sub { return &cmd_whisper(@_); },
                         alias=> 1                                       };
@command{i}          = { fun  => sub { return &cmd_inventory(@_); },
                         alias=> 1                                       };
@command{"\@tel"}    = { fun  => sub { return &cmd_teleport(@_); },
                         alias=> 1                                       };
@command{"l"}        = { fun  => sub { return &cmd_look(@_); },          
                         alias => 1                                      };
@command{"\@\@"}     = { fun  => sub { return;}                          };
@command{"\@split"}  = { fun  => sub { cmd_split(@_); }                  };

 
# ------------------------------------------------------------------------#


sub cmd_score
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You have 0 pennies." ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Score expects no arguments." ],
           );
   }
};

sub cmd_huh
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "Huh? (Type \"help\" for help.)" ]
        );
}
                  
sub cmd_offline_huh { my $sock = $$user{sock};
                      printf($sock "%s",getfile("login.txt"));           }
sub cmd_version
{
   my ($self,$prog) = @_;
                   
   my $ver = (@info{version} =~ /^TeenyMUSH ([\d\.]+)$/i) ? $1 : "N/A";

   necho(self   => $self,
         prog   => $prog,
         source => [ "TeenyMUSH :  Version %s [cmdhudson\@gmail.com]\n".
                     "   Source :  https://github.com/c-hudson/teenymush",
                     $ver
                   ]
        );
}

sub cmd_reset
{
   my ($self,$prog) = @_;

   if(!hasflag($self,"WIZARD")) {
     return err($self,$prog,"Permission Denied.");
   } else {
     delete @info{io};
     necho(self   => $self,
           prog   => $prog,
           source => [ "All telnet connections reset." ]
          );
  }
}

sub cmd_lock
{
   my ($self,$prog) = @_;

   echo($self,"---[start]----");
   for my $i (locked(@_[0])) {
      echo($self,"# '%s'",$i);
   }
   echo($self ,"---[ end ]----");
}

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

sub hecho
{
   my ($fmt,@args) = @_;
   my $sock = $$user{sock};
   my $txt = sprintf("$fmt",@args);

   $txt =~ s/\r\n/\n/g;
   $txt =~ s/\n/\r\n/g;

   if($txt =~ /\n$/) {
      printf($sock "%s",$txt);
   } else {
      printf($sock "%s\r\n",$txt);
   }
}

# ------------------------------------------------------------------------#
# HoneyPot Commands
#
#     You could ban someone, but why not have a little fun with them?
#
# ------------------------------------------------------------------------#


#
# honey_page
#    Put some words into the mouth of any poor soals who get honeypotted.
#
sub honey_page
{
   my $txt = shift;
   my $r = int(rand(5));

   if($txt =~ /^\s*([^ ]+)\s*=\s*/) {
      if($r == 1) {
         hecho("You page %s, \"How do I connect, please help\"");
         hecho("%s pages, \"You're already connected.\"",ucfirst(lc($1)));
      } elsif($r == 2) {
         hecho("You page %s, \"How do I get \@toaded?\"",$1);
      } elsif($r == 3) {
         hecho("You page %s, \"What is a HoneyPot?\"",$1);
      } elsif($r == 4) {
         hecho("You page %s, \"%s\"",$');
      } elsif($r == 0) {
         hecho("You page %s, \"\@TOAD ME \@TOAD ME \@TOAD ME!\"",$1);
         hecho("%s pages, \"Ookay!\"",ucfirst(lc($1)));
         cmd_quit();
      }
   } else {
      hecho("Usage: page <user> = <message>");
   }
}

#
# honey_off
#    Just for testing purposes?
#
sub honey_off
{
   $$user{site_restriction} = 4;
}

#
# honey_huh
#
#    Show the login screen or the huh message depending on if the
#    person is connected or not.
#
sub honey_huh
{
   my $sock = $$user{sock};
   if(!defined $$user{honey}) {
      hecho("%s",getfile("honey.txt"));
   } else {
      hecho("%s","Huh?  (Type \"help\" for help.)");
   }
}

#
# honey_connect
#
#    Let the honeypotted feel like they've connected.
#
sub honey_connect
{
   my $txt = shift;

   my $sock = $$user{sock};

   if($txt =~ /^\s*([^ ]+)/i) {
      $$user{honey} = $1;
   } else {
      $$user{honey} = "Honey";
   }

   printf($sock "%s\n",<<__EOF__);
   -----------------------------------------------------------------------

       Get your free HONEY. Page Adrick for details

   -----------------------------------------------------------------------
__EOF__
   honey_look();
}

sub honey_look
{
   if(defined $$user{honey}) {
   hecho("%s",<<__EOF__);
Honey Tree(#7439RJs)
   In an open place in the middle of the forest, and in the middle of this place is a large oak-tree, and from the top of the tree, there comes a loud buzzing-noise. The large tree is big enough for a small bear to climb. A branch leans over towards a Bee's nest.
   That buzzing-noise means something. You don't get a buzzing-noise like that, just buzzing and buzzing, without its meaning something. If there's a buzzing-noise, somebody's making a buzzing-noise, and the only reason for making a buzzing-noise that I know of is because you're a bee. And the only reason for being a bee that I know of is making honey!
Contents:
Magic Blue Ballon
Honey Pot
Obvious exits:
House
__EOF__
   } else {
      honey_huh();
   }
}

#
# honey_who
#    Simulate some connected people.
#
sub honey_who
{
   hecho("%s","Player Name        On For Idle  \@doing");

   if(defined $$user{honey}) {
      hecho("%-16s     0:03   0s  HoneyPot User",substr($$user{honey},0,16));
   }
   hecho("%s",<<__EOF__);
Phantom              0:11  11m  
Quartz               5:07   5h  Something that is better left unspoken.
Sorad                6:11   5h  
Rowex            1d 01:21   1m  
Swift            2d 10:38   2m  
Adrick           2d 16:47   0s                               
Wolf             3d 13:35   3d  
Tyr              4d 19:15   4d  
Paiige          11d 22:19   1d  
Rince           11d 22:19   1d  
draith          43d 17:11   1h  
feem            46d 21:09   5d  
Ian             53d 17:59   4w  
Draken-Korin    66d 23:46   2s  
Ambrosia        69d 01:41   2M  There is no cow level.
Brazil         128d 16:08   4m  
nails          138d 00:46   3M  
Oleo           157d 19:27  26m  Just a friendly butter-substitute Wiz
18 Players logged in, 73 record, no maximum.
__EOF__
}

#
# honey_go
#    Simulate the go command, but not very well
#
sub honey_go
{
   my $r = int(rand(5));

   if(defined $$user{honey}) {
      if($r == 0) {
         hecho("The door seems jammed, try it again.");
      } elsif($r == 1) {
         hecho("The door moves forward but stops, try it again.");
      } elsif($r == 2) {
         hecho("The door opens but slams shut, try it again.");
      } elsif($r == 3) {
         hecho("The door opens but you get bored and slam it shut.");
      } elsif($r == 4) {
         hecho("Thats not a exit, its a frog");
      }
   }
}

# ---[ End HoneyPot Commands ]--------------------------------------------#

sub cmd_honey
{
   my ($self,$prog,$txt) = @_;
   my $match = 0;
   my $name;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^ ]+)\s*$/) {
      for my $who (@{sql("select obj_name, sck_socket " .
                          "  from socket sck, object obj " .
                          " where obj.obj_id = sck.obj_id " .
                          "   and lower(obj.obj_name) = lower(?) ",
                          $txt)}) {
         @{@connected{$$who{sck_socket}}}{site_restriction} = 69;
         @{@connected{$$who{sck_socket}}}{honey} = $$who{obj_name};
         $match++;
         $name = $$who{obj_name};
      }
   }

   if($match == 0) {
      necho(self   => $self,
            prog   => $prog,
            source => ["I don't recognize '%s'", $txt],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%d connections have been HoneyPotted for %s",
                        $match, $name
                      ]
           );
   }
   
}

sub cmd_var
{
    my ($self,$prog,$txt) = @_;

    $$prog{var} = {} if !defined $$prog{var};
    if($txt =~ /^\s*([^ ]+)\+\+\s*$/) {
       @{$$prog{var}}{$1}++;
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set." ],
#            );
    } elsif($txt =~ /^\s*([^ ]+)\-\-\s*$/) {
       @{$$prog{var}}{$1}--;
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set." ],
#            );
    } elsif($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
       @{$$prog{var}}{$1} = evaluate($self,$prog,$2); 
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set. $1 = @{$$prog{var}}{$1}" ],
#            );
    } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "usage: \@var <variable> = <variables>" ],
            );
    }
}

sub cmd_boot
{
   my ($self,$prog,$txt,$switch) = @_;

   if(hasflag($self,"WIZARD")) {
   
      $txt =~ s/^\s+|\s+$//g;
      if(defined $$switch{port} && $txt !~ /^\d+$/) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Port numbers must be numeric." ]
              );
      }

      for my $key (keys %connected) {
         my $hash = @connected{$key};
   
         if((defined $$switch{port} && $$hash{port} == $txt) ||
            (!defined $$switch{port} && lc($$hash{obj_name}) eq lc($txt))) {

            necho(self   => $self,
                  target => $hash,
                  prog   => $prog,
                  target => [ $hash, "%s has \@booted you.", $$self{obj_name} ],
                  source => [ "You \@booted %s off!", obj_name($hash) ],
                  room   => [ $hash, "%s has been \@booted.",$$hash{obj_name} ],
                 );
         
            my $sock=$$hash{sock};
            printf($sock "%s",getfile("logoff.txt"));
            server_disconnect($sock);
            return;
         }
      }
      if(defined $$switch{port}) {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "Unknown port specified." ],
              );
      } else {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "Unknown person specified." ],
              );
      }
   } else {
      return err($self,$prog,"Permission Denied.");
   }
}

sub cmd_killpid
{
   my ($self,$prog,$txt) = @_;

   my $engine = @info{engine};

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*(\d+)\s*$/) {
      if(defined $$engine{$1}) {
         delete @$engine{$1};
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "PID '%s' has been killed", $1 ],
              );
      } else {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "PID '%s' does not exist.", $1 ],
              );
      }

   } else {
      necho(self   => $self,                           # target's room
            prog   => $prog,
            source => [ "Usage: \@kill <pid>", $1 ],
           );
   }
}

sub cmd_ps
{
   my ($self,$prog) = @_;
   my $engine = @info{engine};

   necho(self   => $self,                           # target's room
         prog   => $prog,
         source => [ "----[ Start ]----" ],
        );
   for my $key (keys %$engine) {
      my $data = @{$$engine{$key}}[0];
      for my $pid (@{$$engine{$key}}) {
         my $stack = $$pid{stack};

         if($#$stack >= 0) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "  PID: %s for %s",$key,
                              obj_name($self,$$data{user}) 
                            ]
                 );
#            for my $i (0 .. (($#$stack <= 10) ? $#$stack : 10)) {
            for my $i (0 .. $#$stack) {
               my $cmd = @{$$stack[$i]}{cmd};
               if(length($cmd) > 67) {
                  necho(self   => $self,
                        prog   => $prog,
                        source => [ "    Cmd: %s...", substr($cmd,0,64) ],
                       );
               } else {
                  necho(self   => $self,
                        prog   => $prog,
                        source => [ "    Cmd: %s ($#$stack)", $cmd ],
                       );
               }
            }
         }
      }
   }
   necho(self   => $self,                           # target's room
         prog   => $prog,
         source => [ "----[  End  ]----" ],
        );
}

sub cmd_halt
{
   my ($self,$prog) = @_;
   my $engine = @info{engine};

   for my $key (keys %$engine) {
      my $data = @{$$engine{$key}}[0];
      for my $pid (@{$$engine{$key}}) {
         my $stack = $$pid{stack};
         if(@{$$data{user}}{obj_id} eq $$self{obj_id}) {
            delete @$pid{stack};
            necho(self => $self,
                 prog => $prog,
                 source => [ "Pid %s stopped." , $key]
                );
         }
      }
   }
}

#
# tval
#    return an evaluated string suitable for test to use
#
sub tval
{
   my ($self,$prog,$txt) = @_;
   
   return lc(trim(evaluate($self,$prog,$txt)));
}

sub test
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ / <= /)     { 
      return (tval($self,$prog,$') <= tval($self,$prog,$`)) ? 1 : 0;
   } elsif($txt =~ / == /)  {
      return (tval($self,$prog,$') == tval($self,$prog,$`)) ? 1 : 0;
   } elsif($txt =~ / >= /)  {
      return (tval($self,$prog,$') >= tval($self,$prog,$`)) ? 1 : 0;
   } elsif($txt =~ / > /)   {
      return (tval($self,$prog,$') > tval($self,$prog,$`)) ? 1 : 0;
   } elsif($txt =~ / < /)   {
      return (tval($self,$prog,$') < tval($self,$prog,$`)) ? 1 : 0;
   } elsif($txt =~ / eq /)  {
      return (tval($self,$prog,$') eq tval($self,$prog,$`)) ? 1 : 0;
   } elsif($txt =~ / ne /)  {
      return (tval($self,$prog,$') ne tval($self,$prog,$`)) ? 1 : 0;
   } else {
      return 0;
   }
}

sub cmd_split
{
    my ($self,$prog,$txt) = @_;
    my $max = 10;
    my @stack;
   
    if($txt =~ /,/) {
       my $target = locate_object($self,$`,"LOCAL") ||
         return err($self,$prog,"I can't find that");
       my $txt = get($target,$');
       $txt =~ s/\r\s*|\n\s*//g;

      unshift(@stack,$txt);

      while($#stack > -1 && $max--) {
          necho(self => $self,
                prog => $prog,
                source => [ "! %s", @stack[0] ]
               );
          my $before = $#stack;
          my $item = shift(@stack);

          if($item =~ /;/) {
             for my $i (balanced_split($item,';',3,1)) {
                unshift(@stack,$i);
             }
          }
          if($before == $#stack) {
             necho(self => $self,
                   prog => $prog,
                   source => [ "# %s ($before==$#stack)", $item ]
                  );
          }
       }
    } else {
       err($self,$prog,"Usage: \@split <object>,<attribute>");
    }
}

# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
    my ($self,$prog,$txt) = @_;
    my (%last,$first);

    my $cmd = $$prog{cmd_last};

    if(!defined $$cmd{while_test}) {                 # initialize "loop"
        $first = 1;
        if($txt =~ /^\s*\(\s*(.*?)\s*\)\s*{\s*(.*?)\s*}\s*$/s) {
           ($$cmd{while_test},$$cmd{while_count}) = ($1,0);
           $$cmd{while_cmd} = [ balanced_split($2,";",3) ];
        } else {
           return err($self,$prog,"usage: while (<expression>) { commands }");
        }
    }
    $$cmd{while_count}++;

#    printf("WHILE: '%s' -> '%s' -> '%s'\n",
#           $$cmd{while_test},
#           evaluate($self,$prog,$$cmd{while_test}),
#           test($$cmd{while_test})
#          );

    if($$cmd{while_count} >= 1000) {
       printf("#*****# while exceeded maxium loop of 1000, stopped\n");
       return err($self,$prog,"while exceeded maxium loop of 1000, stopped");
    } elsif(test($self,$prog,$$cmd{while_test})) {

       signal_still_running($prog);

       my $commands = $$cmd{while_cmd};
       for my $i (0 .. $#$commands) {
          mushrun(self   => $self,
                  prog   => $prog,
                  runas  => $self,
                  source => 0,
                  cmd    => $$commands[$i],
                  child  => 1
                 );
       }
    }
}


sub max_args
{
   my ($count,$delim,@array) = @_;
   my @result;

   for my $i (0 .. $#array) {
      if($i <= $count-1) {
         @result[$i] = @array[$i];
      } elsif($i > $count-1) {
         @result[$count-1] .= $delim . @array[$i];
      }
   }
   return @result;
}

#
# cmd_dolist
#    Loop though a list running specified commands.
#
sub cmd_dolist
{
   my ($self,$prog,$txt) = @_;
   my $cmd = $$prog{cmd_last};
   my %last;

   if(!defined $$cmd{dolist_list}) {                       # initalize list
       my ($first,$second) = max_args(2,"=",balanced_split($txt,"=",3));

       $$cmd{dolist_cmd}   = [ balanced_split($second,";",3) ];
       $$cmd{dolist_list}  = [ split(' ',evaluate($self,$prog,$first)) ];
       $$cmd{dolist_count} = 0;
   }
   $$cmd{dolist_count}++;


   if($$cmd{dolist_count} > 500) {                  # force users to be nice
      return err($self,$prog,"dolist execeeded maxium count of 500, stopping");
   } elsif($#{$$cmd{dolist_list}} < 0) {
      return;                                                 # already done
   }

   my $list = $$cmd{dolist_cmd};                              # make shortcuts
   my $item = shift(@{$$cmd{dolist_list}});


   if( $#{$$cmd{dolist_list}} >= 0) {
       signal_still_running($prog);
   }
    
   for my $i (0 .. $#$list) {              # push commands into the q
      my $new = $$list[$i];
      $new =~ s/\#\#/$item/g;
      mushrun(self   => $self,
              prog   => $prog,
              runas  => $self,
              source => 0,
              cmd    => $new,
              child  => 1,
             );
   }
}

sub good_password
{
   my $txt = shift;

   if($txt !~ /^\s*.{8,999}\s*$/) {
      return "#-1 Passwords must be 8 characters or more";
   } elsif($txt !~ /[0-9]/) {
      return "#-1 Passwords must one digit [0-9]";
   } elsif($txt !~ /[A-Z]/) {
      "#-1 Passwords must contain at least one upper case character";
   } elsif($txt !~ /[A-Z]/) {
      return "#-1 Passwords must contain at least one lower case character";
   } else {
      return undef;
   }
}

sub cmd_password
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"PLAYER")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Non-players do not need passwords." ],
           );
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {

      my $result = good_password($2);

      if($result ne undef) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s", $result ],
                     );
      }

      if(one($db,"select obj_password ".
                 "  from object " .
                 " where obj_id = ? " .
                 "   and obj_password = password(?)",
                 $$self{obj_id},
                 $1
            )) {
         sql(e($db,1),
             "update object ".
             "   set obj_password = password(?) " . 
             " where obj_id = ?" ,
             $2,
             $$self{obj_id}
            );
         necho(self   => $self,
               prog   => $prog,
               source => [ "Your password has been updated." ],
              );
      } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Invalid old password." ],
              );
      }
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "usage: \@password <old_password> = <new_password>" ],
           );
   }
}

sub cmd_sleep
{
    my ($self,$prog,$txt) = @_;

    my $cmd = $$prog{cmd_last};

    if(!defined $$cmd{sleep}) {
       if($txt =~ /^\s*(\d+)\s*$/) {
          if($1 > 5400 || $1 < 1) {
             necho(self   => $self,
                   prog   => $prog,
                   source => [ "\@sleep range must be between 1 and 5400." ],
                  );
             return;
          } else {
             $$cmd{sleep} = time() + $1;
          }
       } else {
          necho(self   => $self,
                prog   => $prog,
                source => [ "usage: \@sleep <seconds>" ],
               );
          return;
       }
    }

    if($$cmd{sleep} >= time()) {
       signal_still_running($prog);
    }
}

sub cmd_readcache
{
   my ($self,$prog) = @_;

   if(!hasflag($self,"WIZARD")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ],
           );
   } else {
      read_config();
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done" ],
           );
   }
}

#
# get_segment
#    Get a single segment of a $delim delimited string. Strings can
#    be enclosed in "quotes" or {brackets} to avoid breaking apart the
#    string in the wrong location.
#
sub get_segment2
{
   my ($txt,$delim) = @_;

    if($txt =~ /^\s*"(.+?)(?<!(?<!\\)\\)"($delim|$)/s ||
       $txt =~ /^\s*{(.+?)(?<!(?<!\\)\\)}($delim|$)/s ||
       $txt =~ /^(.+?)($delim|$)/s) {
       return ($1,$');
    } else {
       return ($txt,undef);
    } 
}

#
# mush_split
#    Take a multiple segment string that is deliminted by $delim and
#    break it apart. Return the result as an array.
#
sub mush_split2
{
   my ($txt,$delim) = @_;
   my (@list,$seg);

   $delim = "," if $delim eq undef;

   while($txt) {
      ($seg,$txt) = (get_segment2($txt,$delim));
      push(@list,$seg);
   }
   return @list;
}

sub cmd_switch
{
    my ($self,$prog,@list) = (shift,shift,balanced_split(shift,',',3));
    my %last;

    my ($first,$second) = (get_segment2(shift(@list),"="));
    $first = evaluate($self,$prog,$first);
    $first =~ s/[\r\n]//g;
    unshift(@list,$second);

    while($#list >= 0) {
       if($#list >= 1) {
          my ($txt,$cmd) = (evaluate($self,$prog,shift(@list)),
                            evaluate($self,$prog,shift(@list)));
#          $txt =~ s/\*/\(.*\)/g;
          $txt =~ s/^\s+|\s+$//g;
          $first =~ s/\//#/g;

 
          if(match_glob(lc($txt),lc($first))) {
             return mushrun(self   => $self,
                            prog   => $prog,
                            runas  => $self,
                            source => 0,
                            cmd    => $cmd,
                            child  => 1
                           );
          } else {
#             printf("!match: '%s' != '%s'\n",$txt,$first);
#             printf("    '%s'\n",match_glob(lc($txt),lc($first)));
#             printf("    '%s'\n",glob_to_regex_string($txt));
          }
       } else {
          @list[0] = $1 if(@list[0] =~ /^\s*{(.*)}\s*$/);
          return mushrun(self   => $self,
                         prog   => $prog,
                         runas  => $self,
                         source => 0,
                         cmd    => @list[0],
                         child  => 1
                        );
       }
    }
}
      

sub cmd_newpassword
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"PLAYER")) {
     return err($self,$prog,"Permission Denied, non-players do not need " .
                "passwords.");
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {

      my $player = locate_player($1) ||
         return err($self,$prog,"Unknown player '%s' specified",$1);

      if(!controls($self,$player)) {
         return err($self,$prog,"Permission denied.");
      }

#      good_password($2) || return;

      sql(e($db,1),
          "update object ".
          "   set obj_password = password(?) " . 
          " where obj_id = ?" ,
          $2,
          $$player{obj_id}
         );
      necho(self   => $self,
            prog   => $prog,
            source => [ "The password for %s has been updated.",name($player) ],
           );

   } else {
      err($self,$prog,"usage: \@newpassword <player> = <new_password>");
   }
}

sub cmd_telnet
{
   my ($self,$prog,$txt) = @_;
   my $pending = 1;
#   return 0;

   return err($self,$prog,"PErmission Denied.") if(!hasflag($self,"WIZARD"));

   my $puppet = hasflag($self,"SOCKET_PUPPET");
   my $input = hasflag($self,"SOCKET_INPUT");

   if(!$input && !$puppet) {
      return err($self,$prog,"Permission DENIED.");
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*([^:]+)\s*:\s*(\d+)\s*$/ ||
           $txt =~ /^\s*([^ ]+)\s*=\s*([^:]+)\s* \s*(\d+)\s*$/) {
      my $count = one_val("select count(*) value " .
                          "  from socket " .
                          " where lower(sck_tag) = lower( ? )",
                          $1);
      if($count != 0) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Telnet socket '%s' already exists", $1 ],
                     );
      }
      my $addr = inet_aton($2) ||
         return err($self,$prog,"Invalid hostname '%s' specified.",$2);
      my $sock = IO::Socket::INET->new(Proto=>'tcp',blocking=>0) ||
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Could not create socket." ],
                     );
      $sock->blocking(0);
      my $sockaddr = sockaddr_in($3, $addr) ||
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Could not create socket." ],
                     );
      $sock->connect($sockaddr) or                     # start connect to host
         $! == EWOULDBLOCK or $! == EINPROGRESS or         # and check status
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Could not open connection." ],
                     );
      () = IO::Select->new($sock)->can_write(.2)     # see if socket is pending
          or $pending = 2;
      defined($sock->blocking(1)) ||
         return err($self,$prog,"Could not open a nonblocking connection");

      @connected{$sock} = {
         obj_id    => $$self{obj_id},
         sock      => $sock,
         raw       => 1,
         socket    => uc($1),
         hostname  => $2,
         port      => $3, 
         loggedin  => 0,
         opened    => time(),
         enactor   => $enactor,
         pending   => $pending,
      };
      if($puppet) {
         @{@connected{$sock}}{raw} = 1;
      } elsif($input) {
         @{@connected{$sock}}{raw} = 2;
      } else {                                          # shouldn't happen
         $sock->close;
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Internal error, could not open connection" ],
                     );
      }

      $readable->add($sock);
      sql(e($db,1),
          "insert into socket " . 
          "(   obj_id, " .
          "    sck_start_time, " .
          "    sck_type, " . 
          "    sck_socket, " .
          "    sck_tag, " .
          "    sck_hostname, " .
          "    sck_port " .
          ") values ( ? , now(), ?, ?, ?, ?, ? )",
               $$self{obj_id},
               2,
               $sock,
               uc($1),
               $2,
               $3
         );
        my_commit;
      @info{io} = {} if(!defined @info{io});
      @{@info{io}}{uc($1)} = {};                     # clear previous buffer
      @{@{@info{io}}{uc($1)}}{buffer} = [];                      # if exists
#      delete @{@info{io}}{uc($1)};

      necho(self   => $self,
            prog   => $prog,
            source => [ "Connection started to: %s:%s\n",$2,$3 ],
            debug  => 1,
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "usage: \@telnet <id>=<hostname>:<port> {$txt}" ],
           );
   }
}

sub cmd_send
{
    my ($self,$prog,$txt) = @_;

    if(!hasflag($self,"WIZARD")) {
       return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /^\s*([^ ]+)\s*=/) {
       my $hash = one($db,
                        "select * " .
                        "  from socket ".
                        " where lower(sck_tag) = lower(?) ",
                        $1
                   );

       if($hash eq undef) {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Unknown socket '%s' requested",$1 ],
               );
       } elsif(!defined @connected{$$hash{sck_socket}}) {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Socket '%s' has closed.",$1 ],
               );
       } else {
          my $sock=@{@connected{$$hash{sck_socket}}}{sock};
          my $txt = evaluate($self,$prog,$');
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "\@send: '%s'", $txt ]
#            );
          printf($sock "%s\n",evaluate($self,$prog,$'));
       }
    } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "Usage: \@send <socket>=<data>" ],
            );
    }
}

sub cmd_close
{
    my ($self,$prog,$txt) = @_;

    if(!hasflag($self,"WIZARD")) {
       return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /^\s*([^ ]+)\s*=/) {
       my $hash = one($db,
                        "select * " .
                        "  from socket ".
                        " where lower(sck_tag) = lower(?) ",
                        $1
                   );

       if($hash eq undef) {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Unknown socket '%s' requested",$1 ],
               );
       } elsif(!defined @connected{$$hash{sck_socket}}) {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Socket '%s' has closed.",$1 ],
               );
       } else {
          my $sock=@{@connected{$$hash{sck_socket}}}{sock};
          printf($sock "%s\r\n",evaluate($self,$prog,$'));
       }
    } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "Usage: \@send <socket>=<data>" ]
            );
    }
}

sub cmd_recall
{
    my ($self,$prog,$txt) = @_;
    my ($qualifier,@args);

    @args[0] = $$self{obj_id};
    if($txt !~ /^\s*$/) {
       $qualifier = 'and lower(out_text) like ? ';
       @args[1] = lc('%' . $txt . '%');
    }

    echo_nolog($self,
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
    my ($self,$prog) = @_;

    my $diff = time() - @info{server_start};
    my $days = int($diff / 86400);
    $diff -= $days * 86400;

    my $hours = int($diff / 3600);
    $diff -= $hours * 3600;

    my $minutes = int($diff / 60);

    necho(self   => $self,
          prog   => $prog,
          source => [ "Uptime: %s days, %s hours, %s minutes",
                      $days,$hours,$minutes ]
         );
}

sub cmd_force
{
    my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*([^ ]+)\s*=\s*/) {
       my $target = locate_object($self,$1,"LOCAL") ||
          return err($self,$prog,"I can't find that");

       if(!controls($self,$target)) {
          return err($self,$prog,"Permission Denied.");
       }

       mushrun(self   => $self,
               prog   => $prog,
               runas  => $target,
               source => 0,
               cmd    => $',
               hint   => "INTERNAL"
              );
   } else {
     err($self,$prog,"syntax: \@force <object> = <command>");
   }
}

sub cmd_list
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*site\s*$/i) {
       necho(self => $self,
             prog => $prog,
             source => [ "%s" ,
                         table("select ste_id Id, " .
                               "       ste_pattern Pattern, " .
                               "       vao_value Type,".
                               "       obj_name Creator, " .
                               "       ste_created_date Date" .
                               "  from site, object, valid_option " .
                               " where ste_created_by = obj_id " .
                               "   and vao_code = ste_type".
                               "   and vao_table = 'site'"
                              )
                       ]
            );
   } elsif($txt =~ /^\s*functions\s*$/i) {
       necho(self   => $self,
             prog   => $prog,
             source => [ "Functions: %s",uc(list_functions()) ],
            );
   } elsif($txt =~ /^\s*commands\s*$/i) {
       necho(self   => $self,
             prog   => $prog,
             source => [ "Commands: %s\n",uc(join(' ',sort keys %command)) ],
            );
   } elsif($txt =~ /^\s*buffers{0,1}\s*$/) {
       my $hash = @info{io};
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",print_var($hash) ],
            );
   } elsif($txt =~ /^\s*sockets\s*$/) {
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",
                         ,table("select obj_id, " .
                                "       sck_start_time start, " .
                                "       sck_hostname host, " .
                                "       sck_port port, " .
                                "       concat(sck_tag,':',sck_type) tag ".
                                "  from socket "
                               )
                       ]
            );
   } else {
       err($self,
           $prog,
           "syntax: \@list <option>\n\n",
           "        Options: site,functions,commands,sockets"
          );
   }
}

sub cmd_destroy
{
   my ($self,$prog,$txt) = @_;

   return err($self,$prog,"syntax: \@destroy <object>") if($txt =~ /^\s*$/);
   my $target = locate_object($self,$txt,"LOCAL") ||
       return err($self,$prog,"I can't find an object named '%s'",$txt);

   if(hasflag($target,"PLAYER")) {
      return err($self,$prog,"Players are \@toaded not \@destroyed.");
   } elsif(!controls($self,$target)) {
      return err($self,$prog,"Permission Denied.");
   }

   sql($db,"delete from object where obj_id = ?",$$target{obj_id});

   if($$db{rows} != 1) {
      my_rollback;
      necho(self   => $self,
            prog   => $prog,
            room    => [ $target, "%s was destroyed.",name($target) ],
            source  => [ "Internal error, object not destroyed." ],
           );
   } else {
      my_commit;
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s was destroyed.",obj_name($self,$target) ],
            room   => [ $target, "%s was destroyed.",name($target) ],
            room2  => [ $target, "%s has left.",name($target) ]
           );
   }
}

sub cmd_toad
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*$/) {
       return err($self,$prog,"syntax: \@toad <object>");
   }

   my $target = locate_object($self,$txt,"LOCAL") ||
       return err($self,$prog,"I can't find an object named '%s'",$txt);

   if(!hasflag($target,"PLAYER")) {
      return err($self,$prog,"Only Players can be \@toaded");
   }

   sql($db,"delete from object where obj_id = ?",$$target{obj_id});

   if($$db{rows} != 1) {
      my_rollback;
      necho(self   => $self,
            prog   => $prog,
            source => [ "Internal error, %s was not \@toaded.",
                        obj_name($self,$target)
                      ]
           );
   } elsif(loc($target) ne loc($self)) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s was \@toaded.",obj_name($self,$target) ],
            room   => [ $target, "%s was \@toaded.",name($target) ],
            room2  => [ $target, "%s has left.",name($target) ]
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            room   => [ $target, "%s was \@toaded.",name($target) ],
            room2  => [ $target, "%s has left.",name($target) ]
           );
   }

   my_commit;
}



sub cmd_think
{
   my ($self,$prog,$txt) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", evaluate($self,$prog,$txt) ],
        );
}

sub cmd_pemit
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ =]+)\s*=/s) {
      my $target = locate_object($self,evaluate($self,$prog,$1),"local");
      my $txt=$';

      if($target eq undef) {
         return err($self,$prog,"I don't see that here");
      } 

      my $txt = evaluate($self,$prog,$txt);

      if($txt !~ /^\s*$/) {
         necho(self   => $self,
               prog   => $prog,
               target => [ $target, "%s", $txt ],
              );
      }
   } else {
      err($self,$prog,"syntax: \@pemit <object> = <message>");
   }
}

sub cmd_emit
{
   my ($self,$prog,$txt) = @_;

   my $txt = evaluate($self,$prog,$txt);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", $txt ],
         room   => [ $self, "%s", $txt ]
        );
}

sub cmd_drop
{
   my ($self,$prog,$txt) = @_;

   my $target = locate_object($self,$txt,"CONTENT") ||
      return err($self,$prog,"I don't see that here.");

   move($self,$prog,$target,fetch(loc($self))) ||
      return err($self,$prog,"Internal error, unable to drop that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ "%s dropped %s", name($self),name($target) ],
         room2  => [ "%s has arrived.",name($target) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_leave
{
   my ($self,$prog,$txt) = @_;

   my $container = fetch(loc($self));

   if($container eq undef || hasflag($container,"ROOM")) {
      return err($self,$prog,"You can't leave.");
   }

   my $dest = fetch(loc($container));

   if($dest eq undef) {
      return err($self,$prog,"You can't leave.");
   }

   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s dropped %s", name($container),name($self) ],
         room2  => [ $self, "%s has left.",name($self) ]
        );

#   my ($self,$prog,$target,$dest,$type) = (obj($_[0]),obj($_[1]),obj($_[2]),$_[3]);

   printf("Move: '$dest'\n");
   move($self,$prog,$self,$dest) ||
      return err($self,$prog,"Internal error, unable to leave that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s dropped %s.", name($container),name($self) ],
         room2  => [ $self, "%s has arrived.",name($self) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_take
{
   my ($self,$prog,$txt) = @_;

   my $target = locate_object($self,$txt,"LOCAL") ||
      return err($self,$prog,"I don't see that here.");

   if(hasflag($target,"EXIT")) {
      return err($self,$prog,"You may not take exits.");
   } elsif($$target{obj_id} eq  $$self{obj_id}) {
      return err($self,$prog,"You cannot get yourself!");
   }

   controls($self,$target) ||
      return err($self,$prog,"Permission Denied.");

   necho(self   => $self,
         prog   => $prog,
         source => [ "You have picked up %s.", name($target) ],
         target => [ $target, "%s has picked you up.", name($self) ],
         room   => [ $target, "%s picks up %s.", name($self),name($target) ],
         room2  => [ $target, "%s has left.",name($target) ]
        );

   move($self,$prog,$target,$self) ||
      return err($self,$prog,"Internal error, unable to pick up that object");

   necho(self   => $self,
         prog   => $prog,
         room   => [ $target, "%s has arrived.",name($target) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_name
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {
      my $target = locate_object($self,$1,"LOCAL") ||
         return err($self,$prog,"I don't see that here.");
      my $name = trim($2);

      controls($self,$target) ||
         return err($self,$prog,"Permission Denied.");

      if($name =~ /^([^a-zA-Z\_\-0-9\.]+)$/) {
         return err($self,$prog,"Invalid names, names may only " .
                    "contain A-Z, 0-9, _, ., and -");
      }

      if(hasflag($target,"PLAYER") && inuse_player_name($2)) {
         return err($self,$prog,"That name is already in use");
      } elsif($name =~ /^\s*(\#|\*)/) {
         return err($self,$prog,"Names may not start with * or #");
      }

      sql($db,
          "update object " .
          "   set obj_name = ? " .
          " where obj_id = ?",
          $name,
          $$target{obj_id},
          );

      if($$db{rows} == 1) {

         necho(self   => $self,
               prog   => $prog,
               source => [ "Set." ],
               room   => [ $target, "%s is now known by %s\n",$1,$2 ]
              );

         $$target{obj_name} = $name;
         my_commit;
      } else {
         err($self,$prog,"Internal error, name not updated.");
      }
   } else {
      err($self,$prog,"syntax: \@name <object> = <new_name>");
   }
}

sub cmd_enter
{
   my ($self,$prog,$txt) = @_;

   my $target = locate_object($self,$txt,"LOCAL") ||
      return err($self,$prog,"I don't see that here.");

   controls($self,$target) ||
      return err($self,$prog,"Permission Denied.");

   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s enters %s.",name($self),name($target)],
         room2  => [ $self, "%s has left.", name($self) ]
        );

   move($self,$prog,$self,$target) ||
      return err($self,$prog,"Internal error, unable to pick up that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         source => [ "You have entered %s.",name($target) ],
         room   => [ $self, "%s entered %s.",name($self),name($target)],
         room2  => [ $self, "%s has arrived.", name($self) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_time
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", scalar localtime() ],
        );
}

sub cmd_to
{
    my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*([^ ]+)\s*/) {
       my $tg = locate_object($self,$1,"LOCAL") ||
          return err($self,$prog,"I don't see that here.");

       necho(self   => $self,
             prog   => $prog,
             source => [ "%s [to %s]: %s\n",name($self),name($tg) ],
             room   => [ $self, "%s [to %s]: %s\n",name($self),name($tg),$' ],
            );
    } else {
       err($self,$prog,"syntax: `<person> <message>");
    }
}



sub whisper
{
   my ($self,$prog,$target,$msg) = @_;

   my $obj = locate_object($self,$target,"LOCAL") ||

   return err($self,$prog,"I don't see that here.") if $obj eq undef;

   if($msg =~ /^\s*:/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s senses, \"%s %s\"",
                        name($obj),name($self),trim($') 
                      ],
            target => [ $obj, "You sense, %s %s",name($self),trim($') ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You whisper, \"%s\" to %s.",trim($msg),name($obj) ],
            target => [ $obj, "%s whispers, \"%s\"",name($self),trim($msg) ],
           );
   }

   if(hasflag($self,"PLAYER")) { 
      set($self,$prog,$self,"LAST_WHISPER","#$$obj{obj_id}",1);
   }
   return 1;
}

#
# cmd_page
#    Person to person communication reguardless of location.
#
sub cmd_whisper
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ ]+)\s*=/) {                           # standard whisper
      whisper($self,$prog,$1,$');
   } else {
      my $target = get($self,"LAST_WHISPER");               # no target whisper
      return whisper($self,$prog,$target,$txt) if($target ne undef);

      err($self,
          $prog,
          "usage: whisper <user> = <message>\n" .
          "       whisper <message>"
         );
   }
}

sub page
{
   my ($self,$prog,$target,$msg) = @_;

      necho(self   => $self,
            prog   => $prog,
            source => [ "target: $target" ], 
           );
   my $target = locate_player($target,"online") ||
       return err($self,$prog,"That player is not connected.");

   my $target = fetch($$target{obj_id});

   if($msg =~ /^\s*:/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Long distance to %s: %s %s",name($target),
                        name($self),trim($') 
                      ],
            target => [ $target, "From afar, %s %s\n",name($self),trim($') ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You paged %s with '%s'",name($target),trim($msg) ],
            target => [ $target, "%s pages: %s\n",name($self),trim($') ],
           );
   }
   
   if(hasflag($self,"PLAYER")) {
      set($self,$prog,$self,"LAST_PAGE","#$$target{obj_id}",1);
   }
}

#
# cmd_page
#    Person to person communication reguardless of location.
#
sub cmd_page
{
   my ($self,$prog,$txt) = @_;

   return page($self,$prog,$1,$') if($txt =~ /^\s*([^ ]+)\s*=/); # standard page

   my $target = get($self,"LAST_PAGE");                       # no target page
   return page($self,$prog,$target,$txt) if($target ne undef);

   err($self,
       $prog,
      "usage: page <user> = <message>\n       page <message>"
      );
}

sub cmd_last
{
   my ($self,$prog,$txt) = @_;
   my ($what,$extra, $hostname);

   # determine the target
   if($txt =~ /^\s*([^ ]+)\s*$/) {
      $what = locate_player($1,"anywhere") ||
         return err($self,$prog,"Unknown player '%s'",$1);
      $what = $$what{obj_id};
   } else {
      $what = $$self{obj_id};
   }

   if($what eq $$self{obj_id} || hasflag($self,"WIZARD")) {
      $hostname = "skh_hostname Hostname,";
   }

   # show target's total connections
   necho(self   => $self,
         prog   => $prog,
         source => [ "%s",
                     table("  select obj_name Name," .
                           "         $hostname " .
                           "         skh_start_time End," .
                           "         skh_end_time Start" .
                           "    from socket_history skh, " .
                           "         object obj " .
                           "   where skh_success = 1" .
                           "     and skh.obj_id = ? " .
                           "     and skh.obj_id = obj.obj_id " .
                           "order by skh_start_time desc " .
                           "limit 10",
                           $what
                          )
                   ]
        );
 
   if((my $val=one_val("select count(*) value " .
                       "  from connect " .
                       " where obj_id = ? " .
                       "   and con_type = 1 ",
                       $what
                      ))) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Total successful connects: %s\n", $val ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Total successful connects: N/A\n" ],
           );
   }
}



#
# cmd_go
#    Move an object from one location to another via an exit.
#
sub cmd_go
{
   my ($self,$prog,$txt) = @_;
   my ($hash,$dest);

   $txt =~ s/^\s+|\s+$//g;

   if($txt =~ /^\s*home\s*$/i) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "There's no place like home...\n" .
                        "There's no place like home...\n" . 
                        "There's no place like home..."  ],
            room   => [ $self, "%s goes home.",name($self) ],
            room2  => [ $self, "%s has left.",name($self) ],
           );

      $dest = one("select obj2.* " .
                  "  from object obj1, " .
                  "       object obj2 " . 
                  " where obj1.obj_home = obj2.obj_id " .
                  "   and obj1.obj_id = ? " ,
                  $$self{obj_id});

      # default to room #0
      $dest = fetch(0) if($dest eq undef || !defined $$dest{obj_id});

   } else {
      # find the exit to go through
      $hash = locate_exit($txt) ||
         return err($self,$prog,"You can't go that way.");
  
      # grab the destination object
      $dest = fetch($$hash{con_dest_id}) ||
         return err($self,$prog,"That exit does not go anywhere");
      necho(self   => $self,
            prog   => $prog,
            room   => [ $self, "%s goes %s.",name($self),
                        first($$hash{obj_name}) 
                      ],
            room2  => [ $self, "%s has left.",name($self) ],
           );
   }

   # move it, move it, move it. I like to move it, move it.
   move($self,$prog,$self,$dest) ||
      return err($self,$prog,"Internal error, unable to go that direction");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s has arrived.",name($self) ]
        );

   cmd_look($self,$prog);
}

sub cmd_teleport
{
   my ($self,$prog,$txt) = @_;
   my ($target,$location);

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*/) {
      ($target,$location) = ($1,$2);
   } elsif($txt =~ /^\s*([^ ]+)\s*/) {
      ($target,$location) = ("#$$self{obj_id}",$1);
   } else {
      err($self,
          $prog,
          "syntax: \@teleport <object> = <location>\n" .
          "        \@teleport <location>");
   }

   $target = locate_object($self,$target) ||
      return err($self,$prog,"I don't see that object here.");

   $location = locate_object($self,$location) ||
      return err($self,$prog,"I can't find that location");

   controls($self,$target) ||
      return err($self,$prog,"Permission Denied.");

   controls($self,$location) ||
      return err($self,$prog,"Permission Denied.");

   if(hasflag($location,"EXIT")) {
      if(loc($location) == loc($self) && loc($self) == loc($target)) {
         $location = fetch(destination($location));
      } else {
         return err($self,$prog,"Permission Denied.");
      }
   }
   
   necho(self   => $self,
         prog   => $prog,
         room   => [ $target, "%s has left.",name($target) ]
        );

   move($self,$prog,$target,$location) ||
      return err($self,$prog,"Unable to teleport to that location");

   necho(self   => $self,
         prog   => $prog,
         room   => [ $target, "%s has arrived.",name($target) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => "look"
          );
}

#
# cmd_print
#    Provide some debuging information
#
sub cmd_print
{
   my ($self,$prog,$txt) = @_;
   $txt =~ s/^\s+|\s+$//g;

   if(!hasflag($self,"WIZARD")) {
      err($self,$prog,"Permission denied.");
   } elsif($txt eq "connected") {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",print_var(\%connected) ]
           );
   } elsif($txt eq "connected_user") {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",print_var(\%connected_user) ]
           );
   } else {
      err($self,$prog,"Invalid variable '%s' specified.",$txt);
   }
}

sub cmd_clear
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      err($self,$prog,"Permission denied.");
   } elsif($txt ne undef) {
      err($self,$prog,"\@clear expect no arguments");
   } elsif(perm($self,"CLEAR")) {
      $| = 1;
      printf("%s\n%s\n%s\n","#" x 65,"-" x 65,"#" x 65);
      print "\033[2J";    #clear the screen
      print "\033[0;0H"; #jump to 0,0
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done." ]
           );
   } else {
      err($self,$prog,"Permission Denied.");
   }
}

# 
# cmd_code
#    display counts about the current size of the code
#
sub cmd_code
{
   my ($self,$prog)  = @_;

   my ($tlines,$tsize);

   necho(self   => $self,                                          # header
         prog   => $prog,
         source => [ " %-30s    %8s   %8s\n %s---%s---%s","File","Bytes",
                    "Lines","-" x 32,"-" x 8,"-" x 8 ]
        );
   for my $key (sort {@{@code{$a}}{size} <=> @{@code{$b}}{size}} keys %code) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "| %-30s | %8s | %8s |\n",$key,@{@code{$key}}{size},
                        @{@code{$key}}{lines}
                      ],
           );
      $tlines += @{@code{$key}}{lines};
      $tsize += @{@code{$key}}{size};
   }
   necho(self   => $self,                                          # trailer
         prog   => $prog,
         source => [ " %s+--%s+--%s|\n %-30s  | %8s | %8s |\n " .
                     "%-30s   -%s---%s-","-" x 32,"-" x 8,"-" x 8,
                     undef,$tsize,$tlines,undef,"-" x 8,"-" x 8 ],
        );
}

sub cmd_commit
{
   my ($self,$prog) = @_;

   if(hasflag($self,"WIZARD")) {
      necho(self   => $self,                                          # trailer
            prog   => $prog,
            source => [ "You force a commit to the database" ],
           );
      my_commit($db);
   } else {
      err($self,$prog,"Permission Denied");
   }
}  

sub cmd_quit
{
   my ($self,$prog) = @_;

   if(defined $$self{sock}) {
      my $sock = $$self{sock};
      printf($sock "%s",getfile("logoff.txt"));
      server_disconnect($sock);
   } else {
      err($self,$prog,"Permission denied [Non-players may not quit]");
   }
}

sub cmd_help
{
   my ($self,$prog,$txt) = @_;
   my %permalias = (
      '&' => 'set',
      '@cls' => 'clear'
   );


   if($txt eq undef) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "HELP\n\n" .
                        "   This is the Ascii Server online help system\n\n" ],
           );

      for my $key (sort keys %command) {
         if(defined @{@command{$key}}{alias}) {
            # ignore
         } elsif((defined @permalias{$key} &&
            perm($self,@permalias{$key})) ||
            (!defined @permalias{$key})) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "   %-10s : %s",$key,@{@command{$key}}{help} ]
                 );
         }
      }
   } elsif(defined @command{trim(lc($txt))}) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", @{@command{trim(lc($txt))}}{help} ],
           );
   } else {
      err($self,$prog,"Unknown help item '%s' specified",trim(lc($txt)));
   }
}

sub cmd_pcreate
{
   my ($self,$prog,$txt) = @_;

   if($$user{site_restriction} == 3) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", getfile("registration.txt") ],
           );
   } elsif($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/) {
      if(inuse_player_name($1)) {
         err($user,$prog,"That name is already in use.");
      } else {
         $$user{obj_id} = create_object($self,$prog,$1,$2,"PLAYER");
         $$user{obj_name} = $1;
         cmd_connect($prog,$self,$txt);
      }
   } else {
      err($user,$prog,"Invalid create command, try: create <user> <password>");
   }
}

sub create_exit
{
   my ($self,$prog,$name,$in,$out,$verbose) = @_;

   my $exit = create_object($self,$prog,$name,undef,"EXIT") ||
      return 0;

   if($out ne undef) {
      link_exit($self,$exit,$in,$out,1) || return 0;
   }

   return $exit;
}


sub cmd_create
{
   my ($self,$prog,$txt) = (@_[0],@_[1],trim(@_[2]));

   if(quota_left($self) <= 0) {
      return err($self,$prog,"You are out of QUOTA to create objects.");
   } if(length($txt) > 50) {
      return err($self,$prog,
                 "Object name may not be greater then 50 characters"
                );
   }

   my $dbref = create_object($self,$prog,$txt,undef,"OBJECT") ||
      return err($self,$prog,"Unable to create object");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Object created as: %s",obj_name($self,$dbref) ],
        );

   my_commit;
}

sub cmd_link
{
   my ($self,$prog,$txt) = @_;
   my ($exit_name,$exit,$dest);

   if($txt =~ /^\s*([^ ]+)\s*=\s*here\s*$/i) {
      ($exit_name,$dest) = ($1,loc($self));
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*#(\d+)\s*$/) {
      ($exit_name,$dest) = ($1,$2);
   } else {
      err($self,$prog,"syntax: \@link <exit> = <room_dbref>\n" .
                      "        \@link <exit> = here\n");
   }

   my $loc = loc($self) ||
      return err($self,$prog,"Unable to determine your location");

   my $exit = locate_object($self,$exit_name,"EXIT") ||
      return err($self,$prog,"I don't see that here");

   if(!valid_dbref($exit)) {
      return err($self,$prog,"%s not a valid object.",$exit);
   } elsif(!valid_dbref($dest)) {
      return err($self,$prog,"%s not a valid object.",$dest);
   } elsif(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
      return err($self,$prog,"You do not own this room and it is not LINK_OK");
   }
 
   $dest = fetch($dest);

   link_exit($self,$exit,undef,$dest) ||
      return err($self,$prog,"Internal error while trying to link exit");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Exit linked to %s",obj_name($self,$dest,1) ],
        );
}


sub cmd_dig
{
   my ($self,$prog,$txt) = @_;
   my ($loc,$room_name,$room,$in,$out);
  
   if($txt =~ /^\s*([^\=]+)\s*=\s*([^,]+)\s*,\s*(.+?)\s*$/ ||
      $txt =~ /^\s*([^=]+)\s*=\s*([^,]+)\s*$/ ||
      $txt =~ /^\s*([^=]+)\s*$/) {
      ($room_name,$in,$out) = ($1,$2,$3);
   } else {
      return err($self,
                 $prog,
                 "syntax: \@dig <RoomName> = <InExitName>,<OutExitName>\n".
                 "        \@dig <RoomName> = <InExitName>\n" .
                 "        \@dig <RoomName>");
   }

   if($in ne undef && $out ne undef && quota_left($self) < 3) {
      return err($self,$prog,"You need a quota of 3 or better to complete " .
                 "this \@dig"
                );
   } elsif(($in ne undef || $out ne undef) && quota_left($self) < 2) {
      return err($self,$prog,"You need a quota of 2 or better to complete " .
                 "this \@dig"
                );
   } elsif($in eq undef && $out eq undef && quota_left($self) < 1) {
      return err($self,$prog,"You are out of QUOTA to create objects");
   }


   if($in ne undef && !locate_exit($in,"EXACT")) {
      return err($self,$prog,"Exit '%s' already exists in this location",$in);
   }


   if($out ne undef) {
      $loc = loc($self) ||
         return err($self,$prog,"Unable to determine your location");

      if(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
         return err($self,
                    $prog,
                    "You do not own this room or it is not LINK_OK"
                   );
      }
   }

   my $room = create_object($self,$prog,$room_name,undef,"ROOM")||
      return err($self,$prog,"Unable to create a new object");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Room created as:         %s(#%sR)",$room_name,$room ],
        );

   if($in ne undef) {
      my $in_dbref = create_exit($self,$prog,$in,$loc,$room);
 
      if($in_dbref eq undef) {
         return err($self,$prog,"Unable to create exit '%s' going in to room",
                    $in
                   );
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "   In exit created as:   %s(#%sE)",$in,$in_dbref ],
           );
   }

   if($out ne undef) {
      my $out_dbref = create_exit($self,$prog,$out,$room,$loc);
      if($out_dbref eq undef) {
         return err($self,$prog,"Unable to create exit '%s' going out of room",
                    $out
                   );
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "   Out exit created as:  %s(#%sE)",$out,$out_dbref ],
           );
   }
   my_commit;
}

sub cmd_open
{
   my ($self,$prog,$txt) = @_;
   my ($exit,$destination);
  
   if($txt =~ /^\s*([^=]+)\s*=\s*([^ ]+)\s*$/ ||
      $txt =~ /^\s*([^ ]+)\s*$/) {
      ($exit,$destination) = ($1,$2);
   } else {
      return err($self,$prog,"syntax: \@open <ExitName> = <destination>\n" .
                             "        \@open <ExitName>");
   }

   if(quota_left($self) < 1) {
      return err($self,$prog,"You are out of QUOTA to create objects");
   }

   !locate_exit($exit,"EXACT") ||
      return err($self,$prog,"Exit '%s' already exists in this location",$exit);

   my $loc = loc($self) ||
      return err($self,$prog,"Unable to determine your location");

   if(!(controls($self,$loc) || hasflag($loc,"ABODE"))) {
      return err($self,$prog,"You do not own this room and it is not ABODE");
   }

   my $dest = locate_object($self,$destination) ||
      return err($self,$prog,"I can't find that destination location");

   if(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
      return err($self,$prog,"You do not own this room and it is not LINK_OK");
   }

   my $dbref = create_exit($self,$prog,$exit,$loc,$dest) ||
      return err($self,$prog,"Internal error, unable to create the exit");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Exit created as %s(#%sE)",$exit,$dbref ],
        );

   my_commit;
}

#
# cmd_connect
#    Verify password, populate @connect / @connected_user hash. Allow player
#    to connected.
#
sub cmd_connect
{
   my ($self,$prog,$txt) = @_;
   my $sock = @$user{sock};
   my $hash;
 
   if($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/ ||              #parse player password
      $txt =~ /^\s*([^ ]+)\s*$/) {
 
      if(($hash=one($db,"select * from object where lower(obj_name) = ?",$1))) {

         if(hasflag($hash,"GUEST") ||
            one($db,"select obj_password ".
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

            my_commit($db);
            necho(self   => $user,
                  prog   => prog($user,$user),
                  source => [ "%s", getfile("motd.txt") ]
                 );
            cmd_look($user,prog($user,$user));                    # show room

            printf("    %s@%s\n",$$hash{obj_name},$$user{hostname});
            necho(self   => $user,
                  prog   => prog($user,$user),
                  room   => [ $user , "%s has connected.",name($user) ],
                 );

            echo_flag($user,prog($user,$user),"CONNECTED,PLAYER,MONITOR",
                      "[Monitor] %s has connected.",name($user))
         } else {
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
            my_commit($db);

            printf($sock "Either that player does not exist, or has a " .
               "different password.\r\n");
         }
      } else {
         my $sock = @$user{sock};
         printf($sock "Either that player does not exist, or has a " .
              "different password.\r\n");
      }
   } else {
      printf($sock "Invalid connect command, " .
             "try: connect <user> <password>\r\n");
   }
}

#
# cmd_doing
#    Set the @doing that is visible from the WHO/Doing command
#
sub cmd_doing
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*$/) {                            # no arguments provided
      sql(e($db,1),
          "update object " . 
          "   set obj_doing = NULL " .
          " where obj_id = ? ",
          $$self{obj_id}
         );
   } else {                                                # doing provided
      sql(e($db,1),
          "update object " . 
          "   set obj_doing = ? " .
          " where obj_id = ? ",
          $txt,
          $$self{obj_id}
         );
   }
   my_commit;
   necho(self   => $self,
         prog   => $prog,
         source => [ "Set." ]
        );
}


sub cmd_describe
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ \/]+?)\s*=\s*(.*?)\s*$/) {
      cmd_set($self,$prog,trim($1) . "/DESCRIPTION=" . $2);
   } else {
      err($self,$prog,"syntax: \@describe <object> = <Text of Description>");
   }
}

# @set object = wizard
# @set me/attribute
sub cmd_set
{
   my ($self,$prog,$txt) = @_;
   my ($target,$attr,$value,$flag);

   if($txt =~ /^\s*([^ =]+?)\s*\/\s*([^ =]+?)\s*=(.*)$/s) { # attribute
      if(@{$$prog{cmd}}{source} == 1) {                          # user input
         ($target,$attr) = ($1,$2);
      } else {                                               # non-user input
         ($target,$attr) = (evaluate($self,$prog,$1),evaluate($self,$prog,$2));
      }
      ($target,$value) = (locate_object($self,$target),$3);

      return err($self,$prog,"Unknown object '%s'",$1) if !$target;
      controls($self,$target) || return err($self,$prog,"Permission denied");

      if(isatrflag($value)) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s", set_atr_flag($target,$attr,$value) ]
              );
      } else {

         if(@{$$prog{cmd}}{source} == 0) {                      # user input
            $value = evaluate($self,$prog,$value);
         }
         set($self,$prog,$target,evaluate($self,$prog,$attr),$value);
      }
      my_commit($db);

   } elsif($txt =~ /^\s*([^ =\\]+?)\s*= *(.*?) *$/s) { # flag?
      ($target,$flag) = (locate_object($self,$1),$2);
      return err($self,$prog,"Unknown object '%s'",$1) if !$target;
      controls($self,$target) || return err($self,$prog,"Permission denied");

      if($flag =~ /^\s*dark\s*$/i &&          # no dark flag for non-wizards
         hasflag($target,"PLAYER") && 
         !hasflag($self,"WIZARD")) {
         return err($self,$prog,"Permission denied");
      }
         

      necho(self   => $self,
            prog   => $prog,
            source => [ set_flag($self,$prog,$target,$flag) ]
           );
   } else {
      return err($self,$prog,
                 "Usage: \@set <object>/<attribute> = <value>\n" .
                 "    or \@set <attribute> = <value>\n");
   }
}

sub list_attr
{
   my ($obj,$atr) = @_;
   my ($query,@where,@result);

   $atr =~ s/\*/%/g;
   $atr =~ s/_/\\_/g;
   if($atr ne undef) {
      $query = "and lower(atr_name) like lower(?) ";
      push(@where,$atr);
   }

   for my $hash (@{sql($db,
       "   select atr_name, " .
       "          atr_value, " .
       "          group_concat(distinct fde_letter order by fde_order " .
       "             separator '') atr_flag " .
       "     from attribute atr left join ( " .
       "             select atr_id, fde_letter, fde_order " .
       "               from flag flg, flag_definition fde " .
       "              where flg.fde_flag_id = fde.fde_flag_id " .
       "                and fde_type = 2 " .
       "           ) flg on (atr.atr_id = flg.atr_id) " .
       "    where atr.obj_id = ? " .
       "      and atr_name != 'DESCRIPTION' " .
       "      $query " .
       " group by atr.atr_id, atr_name " .
       "order by atr.atr_name",
       $$obj{obj_id},
       @where
      )}) { 
       if($$hash{atr_flag} eq undef) {
          push(@result,sprintf("%s: %s",$$hash{atr_name},$$hash{atr_value}));
       } else {
          push(@result,sprintf("%s[%s]: %s",@$hash{atr_name},$$hash{atr_flag},
              $$hash{atr_value}));
       }
       if(uc($$hash{atr_name}) eq uc($atr)) {
          return @result[$#result];
       }
   }

   if($#result == -1 && $atr eq undef) {
      return;
   } elsif($#result == -1) {
      return "No matching attributes";
   } else {
      return join("\n",@result);
   }
}

sub cmd_ex
{
   my ($self,$prog,$txt) = @_;
   my ($target,$desc,@exit,@content,$atr,$out);

   ($txt,$atr) = ($`,$') if($txt =~ /\//);

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
   } elsif($txt =~ /^\s*(.+?)\s*$/) {
      $target = locate_object($self,$1) ||
         return err($self,$prog,"I don't see that here.");
   } else {
       return err($self,$prog,"I don't see that here.");
   }

   my $perm = controls($self,$target,1);

   if($atr ne undef) {
      if($perm) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s",list_attr($target,$atr)],
                     );
      }
      return err($self,$prog,"Permission denied.");
   }


   $out .= obj_name($self,$target,$perm);
   my $owner = fetch(($$target{obj_owner} == -1) ? 0 : $$target{obj_owner});
   $out .= "\nOwner: " . obj_name($self,$owner,$perm) . 
           "  Flags: " . flag_list($target,1);

   if(($desc = get($$target{obj_id},"DESCRIPTION")) && $desc ne undef) {
      $out .= "\n$desc";
   } else {
      $out .= "\nYou see nothing special.";
   }

   $out .= "\nCreated: $$target{obj_created_date}";
   if(hasflag($target,"PLAYER")) {
      if($perm) {
         $out .= "\nFirstsite: $$target{obj_created_by}\n" .
                 "Lastsite: " . lastsite($$target{obj_id});
      }
      my $last = one_val($db,
                         "select ifnull(max(skh_end_time), " .
                         "              max(skh_start_time) " .
                         "             ) value " .
                         "  from socket_history " .
                         " where obj_id = ? ",
                         $$target{obj_id}
                        );
       
      if($last eq undef) {
         $out .= "\nLast: N/A";
      } else {
         $out .= "\nLast: ". $last;
      }
   }

   if($perm) {                                             # show attributes
      my $attr = list_attr($target);
      $out .= "\n" . $attr if($attr ne undef);
   }


   for my $hash (@{sql($db," SELECT con.obj_id, obj_name " .
                           "    FROM content con, object obj, flag flg, " .
                           "         flag_definition fde " .
                           "   WHERE obj.obj_id = con.obj_id " .
                           "     AND flg.obj_id = obj.obj_id ".
                           "     AND fde.fde_flag_id = flg.fde_flag_id " .
                           "     AND con_source_id = ?  " .
                           "     AND fde.fde_name in ('PLAYER','OBJECT') " .
                           "     AND fde.fde_type = 1 " .
                           "     AND atr_id is null " .
                           "ORDER BY con.con_created_date",
                           $$target{obj_id}
                          )}) {
      if($$self{obj_id} != $$hash{obj_id}) {
         push(@content,obj_name($self,$hash,$perm));
      }
   }

   if($#content > -1) {
      $out .= "\nContents:\n" . join("\n",@content);
   }

   my $con = one("select * " . 
                 "  from content " .
                 " where obj_id = ?",
                 $$target{obj_id});

   if(hasflag($target,"EXIT")) {
      if($con eq undef || $$con{con_source_id} eq undef) {
         $out .= "\nSource: ** No where **";
      } else {
         my $src = fetch($$con{con_source_id});
         $out .= "\nSource: " . obj_name($self,$src,$perm);
      }

      if($con eq undef || $$con{con_dest_id} eq undef) {
         $out .= "\nDesination: ** No where **";
      } else {
         my $dst = fetch($$con{con_dest_id});
         $out .= "\nDestination: " . obj_name($self,$dst,$perm);
      }
   }

   for my $hash (@{sql($db,"  SELECT obj_name, obj.obj_id " .
                           "    FROM content con, object obj, " . 
                           "         flag flg, flag_definition fde " .
                           "   WHERE con.obj_id = obj.obj_id " .
                           "     AND flg.obj_id = obj.obj_id " . 
                           "     AND fde.fde_flag_id = flg.fde_flag_id " .
                           "     AND con_source_id = ?  " .
                           "     AND atr_id is null " .
                           "     and fde_type = 1 " .
                           "     AND fde.fde_name = 'EXIT' " .
                           "ORDER BY con_created_date",
                           $$target{obj_id}
                      )}) {
      push(@exit,obj_name($self,$hash));
   }
   if($#exit >= 0) {
      $out .= "\nExits:\n" . join("\n",@exit);
   }

   if($perm && (hasflag($target,"PLAYER") || hasflag($target,"OBJECT"))) {
      $out .= "\nHome: " . obj_name($self,fetch($$target{obj_home}),$perm) .
              "\nLocation: " . obj_name($self,$$con{con_source_id},$perm);
   }
   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", $out ]
        );
}

sub cmd_inventory
{
   my ($self,$prog,$txt) = @_;

   my $inv = [ lcon($self) ];

   if($#$inv == -1) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You are not carrying anything." ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You are carrying:" ],
           );
      for my $i (0 .. $#$inv) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s", obj_name($self,$$inv[$i]) ],
              );
      }
   }
}


#
# cmd_look
#
#    Show the player what is around it.
#
sub cmd_look
{
   my ($self,$prog,$txt) = @_;
   my ($flag,$desc,$target,@exit,$out);
   my $owner = owner_id($self);
   my $perm = hasflag($self,"WIZARD");

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
      return err($self,$prog,"I don't see that here.") if $target eq undef;
   } elsif(!($target = locate_object($self,$txt))) {
      return err($self,$prog,"I don't see that here.");
   }

   $out = obj_name($self,$target);
   if(($desc = get($$target{obj_id},"DESCRIPTION")) && $desc ne undef) {
      $out .= "\n" . evaluate($self,$prog,$desc);
   } else {
      $out .= "\nYou see nothing special.";
   }

   if(!hasflag($target,"ROOM") ||
      (hasflag($target,"ROOM") && !hasflag($target,"DARK"))) {
      for my $hash (@{sql($db,
          "select   group_concat(distinct fde_letter " .
          "                      order by fde_order " .
          "                      separator '') flags, " .
          "         obj.obj_id," .
          "         min(obj.obj_name) obj_name, " .
          "         min(" .
          "             case " .
          "                when fde_name in ('EXIT','OBJECT','PLAYER') then " .
          "                   fde_name  " .
          "             END " .
          "            ) obj_type, " .
          "         case  " .
          "            when min(sck.sck_socket) is null then " .
          "               'N' " .
          "            else " .
          "               'Y' " .
          "         END online," .
          "         min(obj.obj_owner) obj_owner ".
          "    from content con, " .
          "         (  select fde.fde_order, obj_id, fde_letter, fde_name " .
          "              from flag flg, flag_definition fde " .
          "             where fde.fde_flag_id = flg.fde_flag_id " .
          "               and flg.atr_id is null " .
          "               and fde_type = 1 " .
          "             union all " .
          "            select 999 fde_order, obj_id, 'c' fde_letter, " .
          "                   'CONNECTED' fde_name ".
          "              from socket sck " .
          "         ) flg, " .
          "         object obj left join (socket sck) " .
          "            on ( obj.obj_id = sck.obj_id)  " .
          "   where con.obj_id = obj.obj_id " .
          "     and flg.obj_id = con.obj_id " .
          "     and con.con_source_id = ? ".
          "     and con.obj_id != ? " .
          "group by con.obj_id, con_created_date " .
          "order by con_created_date",
          $$target{obj_id},
          $$self{obj_id}
         )}) {
   
          # skip non-connected players
          next if($$hash{obj_type} eq "PLAYER" && $$hash{online} eq "N");
   
          if($$hash{obj_type} eq "EXIT") {                   # store exits for
             if($$hash{flag} !~ /D/) {                                 # later
                push(@exit,first($$hash{obj_name}));
             }
          } elsif($$hash{obj_type} =~ /^(PLAYER|OBJECT)$/ && 
                 $$hash{flags} !~ /D/){
             $out .= "\nContents:" if(++$flag == 1);
             if($$hash{obj_owner} == $owner || $perm) {
                 $out .= "\n$$hash{obj_name}(#$$hash{obj_id}$$hash{flags})";
             } else {
                 $out .= "\n$$hash{obj_name}";
             }
          }
      }
   }
   $out .= "\nExits:\n" . join("   ",@exit) if($#exit >= 0);   # add any exits
   necho(self   => $self,
         prog   => $prog,
         source => ["%s",$out ]
        );

   if(($desc = get($target,"ADESCRIBE")) && $desc ne undef) {
      return mushrun(self   => $self,           # handle adesc
                     prog   => $prog,
                     runas  => $target,
                     source => 0,
                     cmd    => $desc
                     );
   }
}





sub cmd_pose
{
   my ($self,$prog,$txt,$switch,$flag) = @_;

   my $space = ($flag) ? "" : " ";
   my $pose = evaluate($self,$prog,$txt);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s%s%s",name($self),$space,$pose ],
         room   => [ $self, "%s%s%s",name($self),$space,$pose ],
        );
}

sub cmd_set2
{
   my ($self,$prog,$txt) = @_;
#   $txt =~ s/\r\n/<BR>/g;

   if($txt =~ /^\s*([^& =]+)\s+([^ =]+)\s*= *(.*?) *$/s) {
      cmd_set($self,$prog,"$2/$1=$3");
   } elsif($txt =~ /^\s*([^ =]+)\s+([^ =]+)\s*$/s) {
      cmd_set($self,$prog,"$2/$1=");
   } elsif($txt =~ /^\s*([^ =]+)\s*=/s) {
      err($self,$prog,"No object specified in &attribute command.");
   } else {
      err($self,$prog,"Unable to parse &attribute command");
   }
}

sub cmd_say
{
   my ($self,$prog,$txt) = @_;

   my $say = evaluate($self,$prog,$txt);

   my $start = time();
   necho(self   => $self,
         prog   => $prog,
         source => [ "You say, \"%s\"",$say ],
         room   => [ $self, "%s says, \"%s\"",name($self),$say ],
        );
}

sub cmd_reload_code
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"WIZARD")) {
      my $result = load_all_code($self);

      if($result eq undef) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "No code to load, no changes made." ]
              );
      } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s loads %s.\n",name($self),$result ]
              );
      }
   } else {
      err($self,$prog,"Permission denied.");
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
   if(@_[0] =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/) {
      return "$1.$2.*.*";
   } elsif(@_[0] =~ /^\s*([0-9\.]+)\s*$/) {

   } elsif(@_[0] =~ /[A-Za-z]/ && @_[0] =~ /\.([^\.]+)\.([^\.]+)$/) {
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
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self) ]
        );
}

sub cmd_DOING
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,1) ]
        );
}

sub who
{
   my ($self,$flag) = @_;
   my ($max,@who,$idle,$count,$out,$extra,$hasperm) = (2);

   if(ref($self) eq "HASH") {
      $hasperm = ($flag || !hasflag($self,"WIZARD")) ? 0 : 1;
   } else {
      $hasperm = 0;
   }


   # query the database for connected user, location, and socket
   # details.
   for my $key (keys %connected) {
      my $hash = @connected{$key};

      if(!defined $$hash{connect_time} && $$hash{raw} == 0) {
         push(@who,{ obj_name      => "[Connecting]",
                     sck_socket    => $$hash{sock},
                     start_time    => $$hash{start},
                     sck_hostname  => $$hash{hostname},
                     port          => $$hash{port} . "-foo",
                     con_source_id =>  " - ",
                   });
      }
   }
   for my $key (@{sql($db,
                    "select obj.*, " .
                    "       sck_start_time start_time, " .
                    "       sck_hostname, " .
                    "       sck_socket, " .
                    "       concat('#',con_source_id) con_source_id " .
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
      $out .= sprintf("%-15s%10s%5s %-*s %-4s %s\r\n","Player Name","On For",
                      "Idle",$max,"Loc","Port","Hostname");
   } else {
      $out .= sprintf("%-15s%10s%5s  %s\r\n","Player Name","On For","Idle",
                      "\@doing");
   }

   $max = 3 if($max < 3);

   # generate detail for every connected user
   for my $hash (@who) {
      # determine idle details
      my $extra_data = @connected{$$hash{sck_socket}};

#      next if($$extra_data{site_restriction} == 69);

      if(defined $$extra_data{last}) {
         $idle = date_split(time() - @{$$extra_data{last}}{time});
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
         $out .= sprintf("%-15s%4s %02d:%02d %4s %-*s %-4s %s%s\r\n",
             $$hash{obj_name},$extra,$$online{h},$$online{m},$$idle{max_val} .
             $$idle{max_abr},$max,$$hash{con_source_id},$$extra_data{port},
             short_hn($$hash{sck_hostname}),
             ($$extra_data{site_restriction} == 69) ? " [HoneyPoted]" : ""
            );
      } elsif($$extra_data{site_restriction} != 69) {
         $out .= sprintf("%-15s%4s %02d:%02d %4s  %s\r\n",name($hash),$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             $$hash{obj_doing});
      }
   }
   $out .= sprintf("%d Players logged in\r\n",$#who+1);        # show totals
   return $out;
}


sub cmd_sweep
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "Sweeping location..." ]
        );
   for my $obj (sql2("select obj.* " .
                    "  from content c1,  " .
                    "       content c2,  " .
                    "       flag flg, " .
                    "       flag_definition fde, " .
                    "       socket sck," .
                    "       object obj ". 
                    " where c1.con_source_id = c2.con_source_id " .
                    "   and obj.obj_id = c1.obj_id " .
                    "   and flg.obj_id = c1.obj_id " .
                    "   and flg.fde_flag_id = fde.fde_flag_id " .
                    "   and fde.fde_Name in ('LISTENER','PUPPET','PLAYER') " .
                    "   and ( sck.obj_id = c1.obj_id " .
                    "         or obj.obj_owner = sck.obj_id " .
                    "       ) " .
                    "   and c2.obj_id = ?",
                    $$self{obj_id}
                   )
               ) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "   #%s is listening.", object_name($$obj{obj_id}) ],
           );
    }
   necho(self   => $self,
         prog   => $prog,
         source => [ "Sweep complete." ]
        );
}
