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
@command{"\@honey"}   = { help => "Put a user into the HoneyPot",
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
                         fun  => sub { return &cmd_pose(@_[0],@_[1],1); },
                         nsp  => 1                                       };
@command{"emote"}    = { help => "Posing without a space after your name",
                         fun  => sub { return &cmd_pose(@_[0],@_[1],1); },
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
@command{commit}     = { help => "Force a commit to mysql",
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
@command{"\@emit"}  = { help => "Send a mesage to an object or person",
                         fun  => sub { cmd_emit(@_); }};
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
@command{"\@sleep"} =   { help => "Destroy an player",
                         fun  => sub { cmd_sleep(@_); }};
#@command{"\@update_hostname"} =   { help => "Perform hostname lookups on any connected player as needed",
#                         fun  => sub { cmd_update_hostname(@_); }};
@command{"\@list"}  =  { help => "List internal server data",
                         fun  => sub { cmd_list(@_); }};
@command{"score"}   =  { help => "Lists how many pennies you have",
                         fun  => sub { echo($user,"You have 0 pennies."); }};

@command{"\@recall"}=  { help => "Recall output sent to you",
                         fun  => sub { cmd_recall(@_); }};
@command{"\@telnet"} ={ help => "open a connection to the internet",
                         fun  => sub { cmd_telnet(@_); }};
@command{"\@reset"}  = { help => "Clear the telnet buffers",
                         fun  => sub { cmd_reset(@_); }};
@command{"\@send"}    ={ help => "Send data to a connected socket",
                         fun  => sub { cmd_send(@_); }};
@command{"\@password"}={ help => "Change your password",
                         fun  => sub { cmd_password(@_); }};
@command{"\@newpassword"}={ help => "Change someone else's password",
                         fun  => sub { cmd_newpassword(@_); }};
@command{"\@switch"}  ={ help => "Compares strings then runs coresponding " .
                                 "commands",
                         fun  => sub { cmd_switch(@_); }};
@command{"\@ps"}      ={ help => "Provide details about the engine queue",
                         fun  => sub { cmd_ps(@_); }};
@command{"\@kill"}  ={ help => "Kill a process",
                         fun  => sub { cmd_kill(@_); }};
@command{"\@var"}     ={ help => "Set a local variable",
                         fun  => sub { cmd_var(@_); }};
@command{"\@dolist"}  ={ help => "Loop through a list of variables",
                         fun  => sub { cmd_dolist(@_); }};
@command{"\@while"}   ={ help => "Loop while an expression is true",
                         fun  => sub { cmd_while(@_); }};
@command{"\@crash"}   ={ help => "Crash the MUSH",
                         fun  => sub { my $foo; @{$$foo{crash}}; }};
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
sub cmd_offline_huh { my $sock = $$user{sock};
                      printf($sock "%s ",getfile("login.txt"));          }
sub cmd_version     { echo($user,"TeenyMUSH 0.1 [cmhudson\@gmail.com]"); }
sub cmd_exec        { echo($user,"Exec: '%s'\n",@_[1]); }

sub cmd_reset
{
   delete @info{io};
    echo($user,"Telenet connections reset.");
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
   my $txt = shift;
   my $match = 0;
   my $name;

   if($txt =~ /^\s*([^ ]+)\s*$/) {
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
      echo($user,"No one is connected by that name");
   } else {
      echo($user,"%d connections have been HoneyPotted for %s",$match,$name);
   }
   
}

sub cmd_var
{
    my ($txt,$prog) = @_;

    if($txt =~ /^\s*([^ ]+)\+\+\s*$/) {
       @{$$prog{var}}{$1}++;
    } elsif($txt =~ /^\s*([^ ]+)\-\-\s*$/) {
       @{$$prog{var}}{$1}--;
    } elsif($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
       $$prog{var} = {} if !defined $$prog{var};
       @{$$prog{var}}{$1} = evaluate($2,$prog); 
    } else {
       echo($user,"usage: \@var <variable> = <variables>");
    }
}

sub cmd_kill
{
   my ($txt,$prog) = @_;

   my $engine = @info{engine};

   if($txt =~ /^\s*(\d+)\s*$/) {
      if(defined $$engine{$1}) {
         delete @$engine{$1};
         echo($user,"PID '%s' has been killed",$1);
      } else {
         echo($user,"PID '%s' does not exist",$1);
      }

   } else {
      echo($user,"Usage: \@kill <pid>");
   }
}

sub cmd_ps
{
   my $engine = @info{engine};

   echo($user,"----[ Start ]----");
   for my $key (keys %$engine) {
      my $data = @{$$engine{$key}}[0];
      echo($user,"  PID: $key for %s",obj_name($$data{user},1));
      for my $pid (@{$$engine{$key}}) {
         my $stack = $$pid{stack};

         if($#$stack < 0) {
            echo($user,"    cmd: %s\n",@{$$user{last}}{cmd});
         } else {
#            for my $i (0 .. (($#$stack <= 10) ? $#$stack : 10)) {
            for my $i (0 .. $#$stack) {
               my $cmd = @{$$stack[$i]}{cmd};
               if(length($cmd) > 67) {
                  echo($user,"    Cmd: %s...",substr($cmd,0,64));
               } else {
                  echo($user,"    Cmd: %s ($#$stack)",$cmd);
               }
            }
         }
      }
   }
   echo($user,"----[  End  ]----");
}

sub test
{
   my $txt = shift;

   if($txt      =~ / <= /)    { return ($` <= $') ? 1 : 0;  }
   elsif($txt =~ / == /)      { 
#      echo($user,"Found '$`' == '$''");
      return ($` == $') ? 1 : 0;  }
   elsif($txt =~ / >= /)      { return ($` >= $') ? 1 : 0;  }
   elsif($txt =~ / > /)       { return ($` > $') ? 1 : 0;   }
   elsif($txt =~ / < /)       { return ($` < $') ? 1 : 0;   }
   elsif($txt =~ / eq /)      { return ($` eq $') ? 1 : 0;  }
   elsif($txt =~ / ne /)      { return ($` ne $') ? 1 : 0;  }
   else {
      return 0;
   }
}

#
# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
    my ($txt,$prog) = @_;
    my (%last,$first);

    my $cmd = $$user{cmd_data};
    my $command = $$user{command_data};
    if(!defined $$cmd{while_test}) {                 # initialize "loop"
        $first = 1;
        if($txt =~ /^\s*\(\s*(.*?)\s*\)\s*{\s*(.*?)\s*}\s*$/s) {
           ($$cmd{while_test},$$cmd{while_count}) = ($1,0);
           $$cmd{while_cmd} = [ bannana_split($2,";",1) ];
        } else {
           return err("usage: while (<expression>) { commands }");
        }
    } 
    $$cmd{while_count}++;
#    printf("%s\n",print_var($prog));

    if($$cmd{while_count} >= 500) {
       return err("while exceeded maxium loop of 500, stopped");
    } elsif(test(evaluate($$cmd{while_test},$prog))) {
       signal_still_running($prog);
       my $commands = $$cmd{while_cmd};
       for my $i (reverse 0 .. $#$commands) {
          $$user{child} = $prog;
          mushrun($user,$$commands[$i]);
       }
    }
}



#
# cmd_dolist
#    Loop though a list running specified commands.
#
sub cmd_dolist
{
    my ($txt,$prog) = @_;
    my %last;

    my $cmd = $$user{cmd_data};
    if(!defined $$cmd{dolist_list}) {                 # initialize "loop"
        my ($first,$second) = bannana_split($txt,"=",1,2);
        $$cmd{dolist_cmd} = [ bannana_split($second,";",1) ];
        $$cmd{dolist_list} = [ split(' ',$first) ];
        $$cmd{dolist_count} = 0;
    } 
    $$cmd{dolist_count}++;

    if($$cmd{dolist_count} > 500) {                       # no big @dolists
       return err("dolist execeeded maxium count of 500, stopping");
    }

    my $list = $$cmd{dolist_list};
    return 0 if($#$list < 0);                           # oops already done

    my $item = pop(@$list);                        # pull next ## off list

    my $commands = $$cmd{dolist_cmd};
    for my $i (0 .. $#$commands) {
        spin_run(\%last,$prog,{ "##" => $item, cmd => $$commands[$i]});
    }

    if($#$list < 0) {                                                # done
       return 0;
    } else {                                          # signal still running
       signal_still_running();
      
       return 1;
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

#
# signal_still_running
#
#    This command puts the currently running command back into the
#    queue of running commands. The assumption is that all commands
#    will be done after the first run... and therefor are removed
#    from the queue.. so we have to add it back in.
#    
sub signal_still_running
{
    my $prog = shift;

    my $stack = $$prog{stack};
    my $cmd = $$prog{cmd_last};

    unshift(@$stack,$cmd);


#    my $info = shift;
#    my $cmd = $$user{cmd_data};
#    my $command = $$user{command_data};
#    $$cmd{still_running} = 1;
#
#"WHILE - @{$$prog{cmd_last}}{cmd}");
#
#    if(defined $$user{internal} &&
#       defined @{$$user{internal}}{cmd} &&
#       defined @{$$user{internal}}{command}) {
#       my $stack = @{$$user{internal}}{command};
#       printf("SIGNAL[%s]: '%s'\n",$info,@{@{$$user{internal}}{cmd}}{cmd});
#       unshift(@$stack,@{$$user{internal}}{cmd});
#    }
}

sub cmd_sleep
{
    my ($txt,$prog) = @_;

    my $cmd = $$user{cmd_data};

    if(!defined $$cmd{sleep}) {
       if($txt =~ /^\s*(\d+)\s*$/) {
          if($1 > 5400 || $1 < 1) {
             echo($user,"\@sleep range must be between 1 and 5400 seconds");
             return;
          } else {
             $$cmd{sleep} = time() + $1;
          }
       } else {
          echo($user,"usage: \@sleep <seconds>");
          return;
       }
    }

    if($$cmd{sleep} >= time()) {
       signal_still_running();
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
    my (@list) = (bannana_split(shift,',',1));
    my $prog = shift;

    my ($first,$second) = (get_segment2(shift(@list),"="));
    $first = evaluate($first,$prog);
    $first =~ s/[\r\n]//g;
    unshift(@list,$second);

    while($#list >= 0) {
       if($#list >= 1) {
          my ($txt,$cmd) = (evaluate(shift(@list),$prog),
                            evaluate(shift(@list),$prog));
          $txt =~ s/\*/\(.*\)/g;
          $txt =~ s/^\s+|\s+$//g;

          $$user{child} = $prog;
#          if($first =~ /^\s*$txt\s*$/i) {
#             printf(" MATCH: %s == %s\n",$first,$txt);
#          } else {
#             printf("!MATCH: %s == %s\n",$first,$txt);
#          }
          return mushrun($user,$cmd) if($first =~ /^\s*$txt\s*$/i);
       } else {
          $$user{child} = $prog;
          return mushrun($user,@list[0]);
       }
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

#      good_password($2) || return;

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

sub cmd_telnet
{
   my $txt = shift;
   my $pending = 1;
#   return 0;

   if(!hasflag($user,"SOCKET") && !hasflag($user,"WIZARD")) {
      return echo($user,"* Permission Denied *");
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*([^:]+)\s*:\s*(\d+)\s*$/ ||
           $txt =~ /^\s*([^ ]+)\s*=\s*([^:]+)\s* \s*(\d+)\s*$/) {
      my $count = one_val("select count(*) value " .
                          "  from socket " .
                          " where lower(sck_tag) = lower( ? )",
                          $1);
      if($count != 0) {
         return echo($user,"Telnet socket '$1' already exists");
      }
      my $addr = inet_aton($2) ||
         return echo($user,"Invalid hostname '%s' specified.",$2);
      my $sock = IO::Socket::INET->new(Proto=>'tcp') ||
         return echo($user,"Could not create socket");
      my $sockaddr = sockaddr_in($3, $addr) ||
         return echo($user,"Could not create SOCKET");
      $sock->connect($sockaddr) or                     # start connect to host
         $! == EWOULDBLOCK or $! == EINPROGRESS or         # and check status
         return echo($user,"Could not open connection");
      () = IO::Select->new($sock)->can_write(10)     # see if socket is pending
          or $pending = 2;
      defined($sock->blocking(1)) ||
         return echo($user,"Could not open a nonblocking connection");

      @connected{$sock} = {
         obj_id    => $$user{obj_id},
         sock      => $sock,
         raw       => 1,
         socket    => $1,
         hostname  => $2,
         port      => $3, 
         loggedin  => 0,
         opened    => time()
      };

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
                $$user{obj_id},
                2,
                $sock,
                $1,
                $2,
                $3
          );
        commit;
      @info{io} = {} if(!defined @info{io});
      delete @{@info{io}}{$1};
      echo($user,"Connection started to: %s:%s\n",$2,$3);
#      printf($sock "QUIT\r\n");
   } else {
      echo($user,"usage: \@telnet <id>=<hostname>:<port>");
   }
}

sub cmd_send
{
    my ($txt,$prog) = @_;

    if($txt =~ /^\s*([^ ]+)\s*=/) {
       my $hash = one($db,
                        "select * " .
                        "  from socket ".
                        " where lower(sck_tag) = lower(?) ",
                        $1
                   );

       if($hash eq undef) {
          echo($user,"Unknown socket '%s' requested",$1);
       } elsif(!defined @connected{$$hash{sck_socket}}) {
          echo($user,"Socket '%s' has closed.",$1);
       } else {
          my $sock=@{@connected{$$hash{sck_socket}}}{sock};
          printf($sock "%s\r\n",evaluate($',$prog));
       }
    } else {
       echo($user,"Usage: \@send <socket>=<data>");
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
   my ($txt,$prog) = @_;

   echo($user,"%s",evaluate($txt,$prog));
}

sub cmd_pemit
{
   my ($txt,$prog) = @_;
   $prog = @{$$user{internal}}{prog} if($prog eq undef);

   if($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
      printf("TARGET: '$1'\n");
      my $target = locate_object($user,$1,"local");
      if($target eq undef) {
         return echo($user,"I don't see that here");
      } 

      echo($target,"%s\n",evaluate($2,$prog));
   } else {
      echo($user,"syntax: \@pemit <object> = <message>");
   }
}

sub cmd_emit
{
   my ($txt,$prog) = @_;

   my $txt = evaluate($txt,$prog);
   echo($user,"%s",$txt);
   echo_room($user,"%s",$txt);
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

      if(hasflag($target,"PLAYER") && inuse_player_name($2,$target)) {
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
         echo_room($target,"%s is now known by %s\n",$1,$2);
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

sub cmd_pcreate
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


sub cmd_create
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
   my $sock = @$user{sock};
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

   if($txt =~ /^\s*([^ ]+)\/\s*([^ ]+)\s*=\s*(.*?)\s*$/s) { # attribute
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
   my ($txt,$prog,$flag) = @_;
   my $space = ($flag) ? "" : " ";
   echo($user,"%s%s%s",name($user),$space,evaluate($txt,$prog));
   echo_room($user,"%s%s%s",name($user),$space,evaluate($txt,$prog));
}

sub cmd_set2
{
   my $txt = shift;
#   $txt =~ s/\r\n/<BR>/g;

   if($txt =~ /^\s*&([^& ]+)\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
      $$user{inattr} = {
         attr => $1,
         object => $2,
         content => [ $3 ]
      };
   } elsif($txt =~ /^\s*([^& ]+)\s*([^ ]+)\s*=\s*(.*?)\s*$/s) {
      cmd_set("$2/$1=$3");
   } elsif($txt =~ /^\s*([^ ]+)\s*([^ ]+)\s*$/) {
      cmd_set("$2/$1=");
   } else {
      echo($user,"Unable to parse &attribute command");
   }
}

sub cmd_say
{
   my $txt = evaluate(shift,shift);

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
    echo($user,who());
}

sub cmd_DOING
{
    echo($user,"%s",who(1));
}

sub who
{
   my $flag = shift;
   my ($max,@who,$idle,$count,$out) = (2);
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
      $out .= sprintf("%-15s%10s%5s %-*s %s\r\n","Player Name","On For","Idle",
                      $max,"Loc","Hostname");
   } else {
      $out .= sprintf("%-15s%10s%5s  %s\r\n","Player Name","On For","Idle",
                      "\@doing");
   }
   

   # generate detail for every connected user
   for my $hash (@who) {

      # determine idle details
      my $extra = @connected{$$hash{sck_socket}};

      next if($$extra{site_restriction} == 69);

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
         $out .= sprintf("%-15s%4s %02d:%02d %4s #%-*s %s\r\n",
             $$hash{obj_name},$extra,$$online{h},$$online{m},$$idle{max_val} .
             $$idle{max_abr},$max,$$hash{con_source_id},
             short_hn($$hash{sck_hostname}));
      } else {
         $out .= sprintf("%-14s%4s %02d:%02d  %4s  %s\r\n",name($hash),$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             $$hash{obj_doing});
      }
   }
   $out .= sprintf("%d Players logged in\r\n",$#who+1);        # show totals
   return $out;
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

