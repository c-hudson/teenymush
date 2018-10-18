#!/usr/bin/perl


use Text::Wrap;
# use Devel::Size qw(size total_size);
use Digest::SHA qw(sha1 sha1_hex);

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
@command{"\@perl"}  = { help => "Run a perl command",
                         fun  => sub { return &cmd_perl(@_); }           };
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
                         fun  => sub { return &cmd_pose(@_[0..3],1); },
                         nsp  => 1                                       };
@command{"emote"}    = { help => "Posing without a space after your name",
                         fun  => sub { return &cmd_pose(@_[0..3],1);      },
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
@command{"\@trigger"} = { help => "Run commands in an attribute",
                         fun  => sub { return cmd_trigger(@_); }         };
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
@command{"\@crash"}   ={ help => "Crashes the server.",
                         fun  => sub { cmd_crash(@_); }};
@command{"\@\@"}     = { help => "A comment, will be ignored ",
                         fun  => sub { return;}                          };
@command{"\@lock"}   = { help => "Test Command",
                         fun  => sub { cmd_lock(@_);}                    };
@command{"\@boot"}   = { help => "Severs the player's connection to the game",
                         fun  => sub { cmd_boot(@_);}                    };
@command{"\@halt"}   = { help => "Stops all your running programs.",
                         fun  => sub { cmd_halt(@_);}                    };
@command{"\@sex"}    = { help => "Sets the gender for an object.",
                         fun  => sub { cmd_sex(@_);}                     };
@command{"\@read"}   = { help => "Reads various data for the MUSH",
                         fun  => sub { cmd_read(@_);}                    };
@command{"\@compile"}= { help => "Reads various data for the MUSH",
                         fun  => sub { cmd_compile(@_);}                 };
@command{"\@clean"}=   { help => "Cleans the Cache",
                         fun  => sub { cmd_clean(@_);}                   };
@command{"give"}=      { help => "Give money or objects",
                         fun  => sub { cmd_give(@_);}                    };
@command{"\@squish"} = { help => "Squish",
                         fun  => sub { cmd_squish(@_);}                  };
@command{"\@split"}  = { fun  => sub { cmd_split(@_); }                  };
@command{"\@websocket"}= { fun  => sub { cmd_websocket(@_); }            };
@command{"\@find"}   = { fun  => sub { cmd_find(@_); }                   };
@command{"\@sqldump"}= { fun  => sub { db_sql_dump(@_); }                };
@command{"\@dbread"} = { fun  => sub { fun_dbread(@_); }                 };
@command{"\@dump"}   = { fun  => sub { cmd_dump(@_); }                   };
# --[ aliases ]-----------------------------------------------------------#

@command{"\@poll"}  =  { fun => sub { cmd_doing(@_[0],@_[1],@_[2],
                                                { header=>1}); },
                         alias=> 1                                       };
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
 
# ------------------------------------------------------------------------#
# Generate Partial Commands                                               #
#    Instead of looping through all the commands every time, we'll just   #
#    populate the table with all possibilities.                           #
# ------------------------------------------------------------------------#
   for my $key (sort {length($a) <=> length($b)} keys %command) {
      for my $i (0 .. length($key)) {
         if(!defined @command{substr($key,0,$i)}) {
            @command{substr($key,0,$i)} = @command{$key};
         }
      }
   }
   delete @command{q};                                 # no alias for QUIT
   delete @command{qu};
   delete @command{qui};
# ------------------------------------------------------------------------#
sub atr_first
{
   my $txt = shift;

   if($txt  =~ /^([^ \(\)\[\]\{\}\*]+)/) {
      return $1;
   } else {
      return undef;
   }
}

sub cmd_dbread
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission denied.");
   } if($file eq undef) {
      return err($self,$prog,"Unable to find a dump file to read");
   } else {
      delete @db[0 .. $#db];
      my $file = newest_full(@info{"conf.mudname"} . ".FULL.DB");
      db_read(undef,undef,$file);
   }
}

#
# cmd_compile
#   This doesn't actually compile but generates the regexps that are
#   required by the user's code. Currently regexps are not supported inside
#   the mush, only globs... so they need to be converted.
#
sub cmd_compile
{
   my ($self,$prog,$txt) = @_;
   my $first;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(memorydb) {
      return err($self,$prog,"This command is not implimented for MemoryDB");
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Starting compiling of regexps from globs." ]
        );
   for my $hash (@{sql("select atr_id, atr_pattern " .
                       "  from attribute " .
                       " where atr_pattern_type != 0")}) {
   sql("update attribute ".
       "   set atr_regexp = ?,".
       "       atr_first = ? ".
       " where atr_id = ? ",
       glob2re($$hash{atr_pattern}),
       atr_first($$hash{atr_pattern}),
       $$hash{atr_id});

      if($$db{rows} != 1 ) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Could not compile %s", $$hash{atr_id} ]
              );
      }
   }
   my_commit;

   necho(self   => $self,
      prog   => $prog,
      source => [ "Finished compiling of regexps from globs." ]
     );
}

sub cmd_backupmode
{
   my ($self,$prog,$txt) = @_;
   @info{backup_mode} = 1;
   necho(self   => $self,
      prog   => $prog,
      source => [ "Backup mode enabled." ]
     );
}

sub cmd_delta
{
   my ($self,$prog,$txt) = @_;
   printf("%s\n",print_var(\@delta));
}

sub cmd_find
{
   my ($self,$prog,$txt) = @_;
   my @out;

   if(memorydb) {
      my $pat = glob2re("*$txt*");
      for(my $i=0;$i < $#db;$i++) {
         if(valid_dbref($i) && controls($self,$i) && name($i,1) =~ /$pat/i) {
            push(@out,obj_name($self,$i));
         }
      }
      push(@out,"**End of List**");
      necho(self   => $self,
            prog   => $prog,
            source => [ join("\n",@out) ]
        );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ table("select concat(obj_name, ".
                              "              '(#', ".
                              "              o.obj_id, ".
                              "              fde_letter, ".
                              "              ')' ".
                              "             ) object  ".
                              "  from object o,  ".
                              "       flag f,  ".
                              "       flag_definition fd  ".
                              " where o.obj_id = f.obj_id  ".
                              "   and f.fde_flag_id = fd.fde_flag_id  ".
                              "   and o.obj_owner = ?  ".
                              "   and CAST(fde_letter as binary) in " .
                              "       ('o','R','e','P')",
                              owner_id($self)
                             )
                      ]
           );
   }
}

sub cmd_perl
{
   my ($self,$prog,$txt) = @_;
   return;

   if(hasflag($self,"WIZARD")) {
      eval ( $txt );  
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done." ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission Denied." ],
           );
   }
}

#
# websocket
#    Instruct the client to sent a command to the server.
#
sub cmd_websocket
{
   my ($self,$prog,$txt) = @_;

   if(hasflag(owner($self),"WIZARD")) {
      websock_wall($txt); 
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission Denied." ],
           );
   }
}

sub cmd_sex
{
    my ($self,$prog,$txt) = @_;

    if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /=/) {
       cmd_set($self,$prog,"$`/sex=" . trim($'));
    } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "I don't know which one you mean!" ],
           );
    }
}

#
#  cmd_score
#     Tell the player how much money it has.
#
sub cmd_score
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You have %s.", money($self,1) ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Score expects no arguments." ],
           );
   }
};

sub cmd_give
{
   my ($self,$prog,$txt) = @_;


   if($txt =~ /=/) {
      my ($target,$what) = (find($self,$prog,$`),$');
      return err($self,$prog,"Give to whom?") if $target eq undef;

      if($what =~ /^\s*\-{0,1}(\d+)\s*$/) {
         $what = $1 . $2;
         if($what == 0) {
            return err($self,$prog,"You must specificy a positive amount of ".
                       "money.");
         } elsif(hasflag($self,"WIZARD")) {
            # can give money
         } elsif($what < 0) {
            return err($self,$prog,"You may not take away money.");
         } elsif($what > money($self)) {
            return err($self,$prog,"You don't have %s to give!",
               pennies($what));
         }

         if(!hasflag($self,"WIZARD") && !give_money($self,-$what)) {
            my_rollback();
            return err($self,$prog,"Internal error, unable to give money to ".
               "%s.",
               name($target));
         }

         if(!give_money($target,$what)) {
            my_rollback();
            return err($self,"Internal error, unable to give money to %s.",
               name($target));
         }

         my_commit;

         necho(self   => $self,
               prog   => $prog,
               source => [ "You give %s %s to %s.",
                           $what,
                           ($what == 1) ? @info{"conf.money_name_singular"} :
                                          @info{"conf.money_name_plural"},
                           name($target) ],
               target => [ $target, "%s gives you %s %s.",
                           name($self),
                           $what,
                           ($what == 1) ? @info{"conf.money_name_singular"} :
                                          @info{"conf.money_name_plural"} ]
              );
      } else {
        err($self,$prog,"You can only give money, right now.");
      }
   }
}

sub cmd_trigger
{
   my ($self,$prog,$txt) = @_;
   my (@wild,$last,$target,$attr,$name);

   if($txt =~ /^\s*([^\/]+)\s*\/\s*([^=]+)\s*={0,1}/ ||
      $txt =~ /^\s*([^\/]+)\s*/) {

      if($2 eq undef) {
         ($name,$target) = ($1,$self);
      } else {
         ($name,$target) = ($2,find($self,$prog,$1));
      }

      if($target eq undef) {
         return err($self,$prog,"No match.");
      } elsif(!controls($self,$target)) {                 # can modify object?
         return err($self,$prog,"Permission denied");
      }

      $attr = get($target,$name);

      if($attr eq undef) {
          return err($self,$prog,"No such attribute.");
      }

      for my $i (balanced_split($',',',2)) {             # split param list
         if($last eq undef) {
            $last = $i;
         } else {
            push(@wild,$i);
         }
      }
      push(@wild,$last) if($last ne undef);

      mushrun(self   => $self,
              prog   => $prog,
              runas  => $target,
              source => 0,
              cmd    => $attr,
              wild   => [ @wild ],
             );
   } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "usage: \@trigger <object>/<attr> [=<parm>]" ],
            );
   }
}

sub cmd_huh
{
   my ($self,$prog) = @_;

#   printf("HUH: '%s' -> '%s'\n",print_var($prog));
   necho(self   => $self,
         prog   => $prog,
         source => [ "Huh? (Type \"help\" for help.)" ]
        );
}
                  
sub cmd_offline_huh { my $sock = $$user{sock};
                      if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
                         ws_echo($sock,@info{"conf.login"});
                      } else {
                         printf($sock "%s\r\n",@info{"conf.login"});
                      }
                    };
sub cmd_version
{
   my ($self,$prog) = @_;
   my $src =  "https://github.com/c-hudson/teenymush";
                   
   my $ver = (@info{version} =~ /^TeenyMUSH ([\d\.]+)$/i) ? $1 : "N/A";

   $src = "<a href=$src>$src</a>" if($$prog{hint} eq "WEB");

   necho(self   => $self,
         prog   => $prog,
         source => [ "TeenyMUSH :  Version %s [cmdhudson\@gmail.com]\n".
                     "   Source :  %s",
                     $ver,$src
                   ]
        );
}

sub cmd_crash
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "You \@crash the server, yee haw.\n%s",code("long") ],
         room   => [ $self, "%s \@crashes the server.", name($self) ],
        );
   my $foo;
   @{$$foo{crash}};
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

#      my $eval = lock_eval($self,$prog,$self,$txt);
sub cmd_lock
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ ]+)\s*=\s*/) {

      my $target = find($self,$prog,$1);       # find target

      if($target eq undef) {                            # found invalid object
         return err($self,$prog,"I don't see that here.");
      } elsif(!controls($self,$target)) {                 # can modify object?
         return err($self,$prog,"Permission denied.");
      } else {                                              # set the lock
         my $lock = lock_compile($self,$prog,$self,$');

         if($$lock{error}) {                               # did lock compile?
            necho(self    => $self,
                  prog    => $prog,
                  source => [ "I don't understand that key, $$lock{errormsg}" ]
                 );
         } else {
            set($self,$prog,$target,"LOCK_DEFAULT",$$lock{lock});
         }
      }
   } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "usage: \@lock <object> = <key>" ],
            );
   }
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
       @{$$prog{var}}{evaluate($self,$prog,$1)}++;
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set." ],
#            );
    } elsif($txt =~ /^\s*([^ ]+)\-\-\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)}--;
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set." ],
#            );
    } elsif($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)} = evaluate($self,$prog,$2);
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

            if(!defined $$hash{obj_id}) {
               necho(self   => $self,
                     target => $hash,
                     prog   => $prog,
                     source => [ "You \@booted port %s off!", $$hash{port} ],
                    );
            } else {
               necho(self   => $self,
                     target => $hash,
                     prog   => $prog,
                     target => [ $hash, "%s has \@booted you.", name($self)],
                     source => [ "You \@booted %s off!", obj_name($self,$hash)],
                     room   => [ $hash, "%s has been \@booted.",name($hash) ],
                    );
            }
         
            my $sock=$$hash{sock};
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

#
# cmd_halt
#    Delete all processes owned by the object running the @halt command.
#
sub cmd_halt
{
   my ($self,$prog) = @_;
   my $engine = @info{engine};
   my %owner;                                            # cache owner calls
   my $obj = @{owner($self)}{obj_id};

   printf("--[ halt start ]------\n");
   for my $pid (keys %$engine) {                          # look at each pid
      #  peek to see who created the process [ick]
      my $creator = @{@{@{@$engine{$pid}}[0]}{created_by}}{obj_id};
      my $program = @{@$engine{$pid}}[0];

      # cache owner of object
      @owner{$obj} = @{owner($creator)}{obj_id} if(!defined @owner{$creator});

      if(@owner{$obj} == $obj) {                  # are the owners the same?
         close_telnet($$program{telnet_socket});
         delete @$engine{$pid};
         necho(self => $self,
               prog => $prog,
               source => [ "Pid %s stopped." , $pid ]
              );
      }
   }
   printf("--[ halt end   ]------\n");
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
      return (tval($self,$prog,$`) <= tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / == /)  {
      return (tval($self,$prog,$`) == tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / >= /)  {
      return (tval($self,$prog,$`) >= tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / > /)   {
      return (tval($self,$prog,$`) > tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / < /)   {
      return (tval($self,$prog,$`) < tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / eq /)  {
      return (tval($self,$prog,$`) eq tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / ne /)  {
      return (tval($self,$prog,$`) ne tval($self,$prog,$')) ? 1 : 0;
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
       my $target = find($self,$prog,$`) ||
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

#
# cmd_dump
#    Dump the database to a file in segments so that the mush doesn't
#    need to "pause" while writing out the database. Why hang the mush
#    for no reason? This also does not fork() off a second copy of the
#    database to background the database like standard MUSHes do.
#
sub cmd_dump
{
   my ($self,$prog,$type) = @_;
   my ($file,$start);

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@DUMP is not a valid command to use in RUN function");
      return;
   } elsif(!hasflag($self,"WIZARD") && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(mysqldb) {
      return err($self,$prog,"Mysql does not need to be \@dumped");
   }

   $type = "normal" if($type eq undef);

   #-----------------------------------------------------------------------#
   # initialize loop                                                       #
   #-----------------------------------------------------------------------#
   my $cmd = $$prog{cmd_last};
   if(!defined $$cmd{dump_pos}) {                      # initialize "loop"
      if(defined @info{backup_mode} && is_running(@info{backup_mode})) {
         return err($self,$prog,"Backup is already running.");
      }
      $$cmd{dump_pos} = 0;

      my ($sec,$min,$hour,$day,$mon,$yr,$wday,$yday,$isdst) =
                                                localtime(time);
      $mon++;
      $yr -= 100;
      my $fn = sprintf("dumps/%s.FULL.%02d%02d%02d_%02d%02d%02d.tdb",
                       @info{"conf.mudname"},
                       $yr,$mon,$day,$hour,$min,$sec);

      open($file,"> $fn") ||
        return err($self,$prog,"Unable to open $fn for writing");

      printf($file "server: %s, dbversion=%s, exported=%s, type=$type\n",
         @info{version},db_version(),scalar localtime());

      $$cmd{dump_file} = $file;
      @info{backup_mode} = $$prog{pid};
      @info{db_last_dump} = time();
      if($type ne "CRASH") {
         echo_flag($user,
                   prog($user,$user),
                   "CONNECTED,PLAYER,LOG",
                   "<LOG> Database backup started.",name($user)
                  );
      }
   } else {
      $file = $$cmd{dump_file};
   }

   my $start = $$cmd{dump_pos};

   #-----------------------------------------------------------------------#
   # write out the database in 50 object segments                          #
   #-----------------------------------------------------------------------#
   while($$cmd{dump_pos} <= $#db && 
       ($$cmd{dump_pos} - $start <= 50 || $type eq "CRASH")) {
       printf($file "%s", db_object($$cmd{dump_pos}));
       $$cmd{dump_pos}++;
   }

   #-----------------------------------------------------------------------#
   # handle dump clean up or notify still running                          #
   #-----------------------------------------------------------------------#
   if($$cmd{dump_pos} > $#db) {                                 # dump done
      if(defined @$cmd{dump_file}) {                    # should not happen?
         printf($file "** Dump Completed %s **\n", scalar localtime());
         close($file);
         delete @$cmd{dump_file};
      }

      # sync changes back into the database
      for(my $i=0;$i <= $#delta;$i++) {
         if(defined @delta[$i] && ref(@delta[$i]) eq "HASH") {
            @db[$i] = @delta[$i];
         }
      }
      delete @delta[0 .. $#delta];                        # empty the delta
      delete @info{backup_mode};                     # turn off backup mode

      if($type ne "CRASH") {
         echo_flag($user,
                   prog($user,$user),
                   "CONNECTED,PLAYER,LOG",
                   "<LOG> Database finished."
                  );
      }
      return;
   } else {
      return "RUNNING";                                       # still running
   }
}

   

# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
   my ($self,$prog,$txt) = @_;
   my (%last,$first);

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@WHILE is not a valid command to use in RUN function");
      return;
   }

   my $cmd = $$prog{cmd_last};

   if(!defined $$cmd{while_test}) {                 # initialize "loop"
        $first = 1;
        if($txt =~ /^\s*\(\s*(.*?)\s*\)\s*{\s*(.*?)\s*}\s*$/s) {
           ($$cmd{while_test},$$cmd{while_count}) = ($1,0);
           $$cmd{while_cmd} = $2;
        } else {
           return err($self,$prog,"usage: while (<expression>) { commands }");
        }
    }
    $$cmd{while_count}++;

    if($$cmd{while_count} >= 1000) {
       printf("#*****# while exceeded maxium loop of 1000, stopped\n");
       return err($self,$prog,"while exceeded maxium loop of 1000, stopped");
    } elsif(test($self,$prog,$$cmd{while_test})) {
       mushrun(self   => $self,
               prog   => $prog,
               runas  => $self,
               source => 0,
               cmd    => $$cmd{while_cmd},
               child  => 1
              );
       return "RUNNING";
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

sub out
{
   my ($prog,$fmt,@args) = @_;

   if(defined $$prog{output}) {
      my $stack = $$prog{output};
      push(@$stack,sprintf($fmt,@args));
   }
}

sub verify_switches
{
   my ($self,$prog,$switch,@switches) = @_;
   my %hash;

   for my $item (@switches) {
      @hash{lc($item)} = 1;
   }

   for my $key (keys %$switch) {
      if(!defined @hash{lc($key)}) {
         err($self,$prog,"Unrecognized switch '$key' found");
         return 0;
      }
   }
   return 1;
}


#
# cmd_dolist
#    Loop though a list running specified commands.
#
sub cmd_dolist
{
   my ($self,$prog,$txt,$switch) = @_;
   my $cmd = $$prog{cmd_last};
   my ($delim, %last);

   verify_switches($self,$prog,$switch,"delimit") || return;

   if(defined $$switch{delimit}) {
      if($txt =~ /^\s*([^ ]+)\s*/) {
         $txt = $';
         $delim = $1;
      } else {
         return err($self,$prog,"Could not determine delimiter");
      }
   } else {
      $delim = " ";
   }

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@DOLIST is not a valid command to use in RUN function");
      return;
   }

#safe_split($txt,($delim eq undef) ? " " : $delim))
   if(!defined $$cmd{dolist_list}) {                       # initalize list
       my ($first,$second) = max_args(2,"=",balanced_split($txt,"=",3));
       $$cmd{dolist_cmd}   = $second;
#       $$cmd{dolist_list}  = [ split(' ',evaluate($self,$prog,$first)) ];
       $$cmd{dolist_list} = [safe_split(evaluate($self,$prog,$first),$delim)];
       $$cmd{dolist_count} = 0;
   }
   $$cmd{dolist_count}++;

   if($$cmd{dolist_count} > 500) {                  # force users to be nice
      return err($self,$prog,"dolist execeeded maxium count of 500, stopping");
   } elsif($#{$$cmd{dolist_list}} < 0) {
      return;                                                 # already done
   }

   my $item = shift(@{$$cmd{dolist_list}});

   if($item !~ /^\s*$/) {
      my $cmds = $$cmd{dolist_cmd};
      $cmds =~ s/\#\#/$item/g;
      mushrun(self   => $self,
              prog   => $prog,
              runas  => $self,
              source => 0,
              cmd    => $cmds,
              child  => 1,
             );
   }
  
#   printf("Returning: '%s'\n",($#{$$cmd{dolist_list}} >= 0) ? "RUNNING" : "DONE"); 
   return ($#{$$cmd{dolist_list}} >= 0) ? "RUNNING" : "DONE"; 
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

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif(!hasflag($self,"PLAYER")) {
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

      if(memorydb) {
         if(mushhash($1) ne get($self,"obj_password")) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Invalid old password." ],
                 );
         } else {
            db_set($self,"password",mushhash($2));
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Passworld changed." ],
                 );
         }
      } else {                                                      # mysql
         if(one($db,"select obj_password ".              # verify old password
                    "  from object " .
                    " where obj_id = ? " .
                    "   and obj_password = password(?)",
                    $$self{obj_id},
                    $1
               )) {
            sql(e($db,1),                                 # verify succeeded
                "update object ".                   # update to new password
                "   set obj_password = password(?) " . 
                " where obj_id = ?" ,
                $2,
                $$self{obj_id}
               );
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Your password has been updated." ],
                 );
         } else {                                             # verify failed
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Invalid old password." ],
                 );
         }
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

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@SLEEP is not a valid command to use in RUN function");
      return;
   }

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
       $$prog{idle} = 1;
       return "RUNNING";
   }

#   if($$cmd{sleep} >= time()) {
#      signal_still_running($prog);
#   }
}

sub read_atr_config
{
   my ($self,$prog) = @_;

   my %default = (
      money_name_plural   => "Pennies",
      money_name_singular => "Penny",
      paycheck            => 50,
      starting_money      => 150,
      linkcost            => 1,
      digcost             => 10,
      createcost          => 10,
      backup_interval     => 3600,
      login               => "Welcome to @info{version}\r\n\r\n" .
                             "   Type the below command to customize this " .
                             "screen after loging in as God.\r\n\r\n" .
                             "    \@set #0/conf.login = Login screen\r\n\r\n"
   );

   my %updated;

   for my $atr (lattr(0)) {
      if($atr =~ /^conf\.(mysql|websock|httpd)/ && @info{"conf.$1"} == -1) {
         # skip
      } elsif($atr =~ /^conf\./i) {
         if(get(0,$atr) =~ /^\s*#(\d+)\s*$/) {
            @info{lc($atr)} = $1;
         } else {
            @info{lc($atr)} = get(0,$atr);
         }
         @updated{lc($atr)} = 1;
      }
   }
   
   for my $key (keys %default) {
      if(!defined @info{"conf.$key"}) {
         @info{"conf.$key"} = @default{$key};
      }
   }

   if(!defined @info{"conf.money_name_plural"}) {
      @info{"conf.money_name_plural"} = "pennies";
   } 
   if(!defined @info{"conf.money_name_plural"}) {
      @info{"conf.money_name_plural"} = "pennies";
   } 

   if($self eq undef) {
#      printf("%s\n", wrap("Updated: ",
#                          "         ",
#                          join(' ', keys %updated)
#                        )
#            );
   } else {
      $Text::Wrap::columns=75;
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",
                        wrap("Updated: ",
                             "         ",
                             join(' ', keys %updated)
                            )
                      ]
        );
   }
}

sub cmd_read
{
   my ($self,$prog,$txt) = @_;
   my ($file, $data, $name);
   my $count = 0;

   if(!hasflag($self,"WIZARD")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ],
           );
   } elsif($txt =~ /^\s*config\s*$/) {                # re-read config file
      read_config();
      read_atr_config($self,$prog);
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done" ],
           );
   } elsif($txt =~ /^\s*help\s*$/) {                     # import help data
      if(!open($file,"help.txt")) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Could not open help.txt for reading." ],
                     );
      }

      if(memorydb) {
         delete @help{keys %help};
      } else {
         sql("delete from help");
      }

      while(<$file>) {
         s/\r|\n//g;
         if(/^& /) {
            if($data ne undef) {
               $count++;
               $data =~ s/\n$//g;

               if(memorydb) {
                  @help{$name} = $data;
               } else {
                  sql("insert into help(hlp_name,hlp_data) " .
                      "values(?,?)",$name,$data);
               }
            }
            $name = $';
            $data = undef;
         } else {
            $data .= $_ . "\n";
         }
      }

      if($data ne undef) {
         $data =~ s/\n$//g;

         if(memorydb) {
            @help{$name} = $data;
         } else {
            sql("insert into help(hlp_name,hlp_data) " .
                "values(?,?)",$name,$data);
         }
         $count++;
      }
      my_commit if mysqldb;

      necho(self   => $self,
            prog   => $prog,
            source => [ "%s help items read containing %d lines of text.",
                        $count, $. ],
           );
      close($file);
   
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Unknown read item '%s' specified.", trim($txt) ],
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

    if($txt =~ /^\s*"(.*?)(?<!(?<!\\)\\)"($delim|$)/s ||
       $txt =~ /^\s*{(.*?)(?<!(?<!\\)\\)}($delim|$)/s ||
       $txt =~ /^(.*?)($delim|$)/s) {
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

sub cmd_squish
{
   my ($self,$prog,$txt) = @_;
   my ($obj,$atr,$out);

   if($txt =~ /[\/,]/) {
      ($obj,$atr) = ($`,$');
   } else {
      return err($self,$prog,"usage: \@squish <object>/<attribute");
   }

   my $target = find($self,$prog,evaluate($self,$prog,$obj));

   if($target eq undef ) {
      return err($self,$prog,"Unknown object '$obj'");
      return "#-1 Unknown object";
   } elsif(!controls($self,$target)) {
      return "#-1 Permission Denied $$self{obj_id} -> $$target{obj_id}";
   }

   for my $line (split(/\n/,get($target,$atr))) {
      $line =~ s/^\s+//;
      $out .= $line;
   }

   set($self,$prog,$target,$atr,$out);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s",$out ],
        );
}

sub cmd_switch
{
   
    my ($self,$prog,@list) = (shift,shift,balanced_split(shift,',',3));
    my %last;

    my ($first,$second) = (get_segment2(shift(@list),"="));
    $first = ansi_remove(evaluate($self,$prog,$first));
    $first =~ s/[\r\n]//g;
    $first =~ tr/\x80-\xFF//d;
    unshift(@list,$second);

    while($#list >= 0) {
       # ignore default place holder used for readability
       if($#list == 1 && @list[0] =~ /^\s*DEFAULT\s*$/) {
          shift(@list);
       }
       if($#list >= 1) {
          my ($txt,$cmd) = (evaluate($self,$prog,shift(@list)),shift(@list));
          $txt =~ s/^\s+|\s+$//g;
          my $pat = glob2re(ansi_remove($txt));

          if($first =~ /$pat/) {
             return mushrun(self   => $self,
                            prog   => $prog,
                            runas  => $self,
                            source => 0,
                            cmd    => $cmd,
                           );
          }
       } else {
          @list[0] = $1 if(@list[0] =~ /^\s*{(.*)}\s*$/);
          @list[0] =~ s/\r|\n//g;
          return mushrun(self   => $self,
                         prog   => $prog,
                         runas  => $self,
                         source => 0,
                         cmd    => @list[0],
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

      my $player = find_player($1) ||
         return err($self,$prog,"Unknown player '%s' specified",$1);

      if(!controls($self,$player)) {
         return err($self,$prog,"Permission denied.");
      }

#      good_password($2) || return;

      if(memorydb) {
         db_set($player,"password",mushhash($2));
      } else {
         sql(e($db,1),
             "update object ".
             "   set obj_password = password(?) " . 
             " where obj_id = ?" ,
             $2,
             $$player{obj_id}
            );
      }
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
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $txt = evaluate($self,$prog,shift);
   my $pending = 1;

   return err($self,$prog,"PErmission Denied.") if(!hasflag($self,"WIZARD"));

   my $puppet = hasflag($self,"SOCKET_PUPPET");
   my $input = hasflag($self,"SOCKET_INPUT");

   if(!$input && !$puppet) {
      return err($self,$prog,"Permission DENIED.");
   } elsif(defined $$prog{telnet_sock}) {
      return err($self,$prog,"A telnet connection is already open");
   } elsif($txt =~ /^\s*([^:]+)\s*[:| ]\s*(\d+)\s*$/) {
      my $addr = inet_aton($1) ||
         return err($self,$prog,"Invalid hostname '%s' specified.",$1);
      my $sock = IO::Socket::INET->new(Proto=>'tcp',
                                       blocking=>0,
                                       Timeout => 30) ||
         return err($self,$prog,"Could not create socket.");
      $sock->blocking(0);
      my $sockaddr = sockaddr_in($2, $addr) ||
         return err($self,$prog,"Could not resolve hostname");
      $sock->connect($sockaddr) or                     # start connect to host
         $! == EWOULDBLOCK or $! == EINPROGRESS or         # and check status
         return err($self,$prog,"Could not open connection.");
      () = IO::Select->new($sock)->can_write(.2)     # see if socket is pending
          or $pending = 2;
      defined($sock->blocking(1)) ||
         return err($self,$prog,"Could not open a nonblocking connection");

      $$prog{telnet_sock} = $sock;

      @connected{$sock} = {
         obj_id    => $$self{obj_id},
         sock      => $sock,
         raw       => 1,
         hostname  => $1,
         port      => $2, 
         loggedin  => 0,
         opened    => time(),
         enactor   => $enactor,
         pending   => $pending,
         prog      => $prog,
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

      if(mysqldb) {
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
                   "NONE",
                   $1,
                   $2
             );
            my_commit;
      }
      @info{io} = {} if(!defined @info{io});

      @info{io}->{$sock} = {};
      @info{io}->{$sock}->{buffer} = [];

      necho(self   => $self,
            prog   => $prog,
            source => [ "Connection started to: %s:%s\n",$1,$2 ],
            debug  => 1,
           );
      
         necho(self   => $self,
                      prog   => $prog,
                      source => [ 1  ],
                     );
      return 1;
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "usage: \@telnet <id>=<hostname>:<port> {$txt}" ],
           );
      return 0;
   }
}

#
# send data to a connected @telnet socket. If the socket is pending,
# the socket will "pause" the @send till it times out or connects.
#
sub cmd_send
{
    my ($self,$prog,$txt) = (obj(shift),shift);
    my $sock;

    if(!hasflag($self,"WIZARD")) {                            # wizard only
       return err($self,$prog,"Permission Denied.");
    } elsif(defined hasflag($self,"SOCKET_PUPPET")) {
       # search for socket if set SOCKET_PUPPET.
       #    1. only one socket per object allowed 
       #    2. for convenience sake, a socket "name" isn't required.
       #       So we search for it.
       if(defined hasflag($self,"SOCKET_PUPPET")) {
          for my $key (keys %connected) {
             if($$self{obj_id} eq @{@connected{$key}}{obj_id} &&
                defined @{@connected{$key}}{prog}) {
                $sock = @{@connected{$key}}{sock};
             }
          }
       }
    } elsif(hasflag($self,"SOCKET_INPUT") && defined $$prog{telnet_sock}) {
       $sock = $$prog{telnet_socket};
    }

    # socket has not connected, try again later
    if($sock eq undef) {
       return err($self,$prog,"Telnet connection needs to be opened first");
    } elsif(@{@connected{$sock}}{pending} == 2) {
       $$prog{idle} = 1;                   # socket pending, try again later
       return "RUNNING";
    } else {
       my $txt = evaluate($self,$prog,shift);
       my $switch = shift;
       $txt =~ s/\r|\n//g;

       if(defined $$switch{lf}) {
          printf($sock "%s\n",$txt);
       } elsif(defined $$switch{cr}) {
          printf($sock "%s\r",$txt);
       } elsif(defined $$switch{crlf}) {
          printf($sock "%s\r\n",$txt);
       } else {
          printf($sock "%s\r\n",$txt);
       }
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
       my $target = find($self,$prog,$1) ||
          return err($self,$prog,"I can't find that");

       if(!controls($self,$target)) {
          return err($self,$prog,"Permission Denied.");
       }

#       mushrun(self   => $target,
##               prog   => prog($target,$target$prog,
#               runas  => $target,
#               source => 0,
#               cmd    => evaluate($self,$prog,$'),
##               cmd    => $',
#               hint   => "INTERNAL"
#              );
       mushrun(self   => $target,
               prog   => $prog,
               runas  => $target,
               source => 0,
               cmd    => evaluate($self,$prog,$'),
               hint   => "INTERNAL"
              );
   } else {
     err($self,$prog,"syntax: \@force <object> = <command>");
   }
}

#   - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#   -------------------------------[ MOTD ]-------------------------------
#   ------------------------------[ MOTD ]------------------------------

sub motd_with_border
{
   my ($self,$prog,$txt) = @_;

   if($txt eq undef) {
      $txt = "   " . fun_center($self,$prog,"There is no MOTD today",70) .
             "\n   " .
             fun_center($self,
                        $prog,
                        "\@set #0/motd=<message> for your MOTD",
                        70
                       );
   }

   return "   " . ("-" x 31) . "[ MOTD ]" . ("-" x 31) . "\n\n".
             $txt . "\n\n   " . ("-" x 70) . "\n";
}

sub motd
{
   my ($self,$prog) = @_;
   
   my $atr = @info{"conf.motd"};
   return motd_with_border($self,$prog) if($atr eq undef);
   motd_with_border($self,$prog,evaluate(0,$prog,$atr));
}

sub cmd_list
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*motd\s*$/i) {
      necho(self => $self,
            prog => $prog,
            source => [ "%s", motd($self,$prog) ]
     );
   } elsif($txt =~ /^\s*cache\s*$/i) {
       my ($size,$atr,$age);
       for my $x (keys %cache) {
          if(ref($cache{$x}) eq "HASH") {
             for my $y (keys %{$cache{$x}}) {
                if(ref($cache{$x}->{$y}) eq "HASH") {
                   if(defined $cache{$x}->{$y}->{value} &&
                      defined $cache{$x}->{$y}->{ts}) {
                      $size += length($cache{$x}->{$y}->{value});
                      $age += time() - $cache{$x}->{$y}->{ts};
                      $atr++;
                   }
                } else {
#                   $size += length($cache{$x}->{$y});
#                   $atr++;
                }
             }
          } else {
#             $size += length($cache{$x});
#             $atr++;
          }
       }
       necho(self   => $self,
             prog   => $prog,
             source => [ "Internal Cache Sizes\n\n" ]
            );
       necho(self   => $self,
             prog   => $prog,
             source => [ "   Objects:     %s composed of %s items",
                         scalar keys %cache,$atr ]
            );
       necho(self   => $self,
             prog   => $prog,
             source => [ "   Size:        %s bytes",total_size(\%cache) ]
            );
       necho(self   => $self,
             prog   => $prog,
             source => [ "   Average Age: %d seconds",$age / $atr]
            );
   } elsif($txt =~ /^\s*functions\s*$/i) {
       $Text::Wrap::columns=75;
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",
                         wrap("Functions: ",
                              "           ",
                              uc(list_functions())
                             )
                       ]
            );
   } elsif($txt =~ /^\s*commands\s*$/i) {
       $Text::Wrap::columns=75;
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s\n",
                         wrap("Commands: ",
                              "          ",
                              uc(join(' ',sort keys %command))
                             )
                       ]
            );
   } elsif($txt =~ /^\s*flags{0,1}\s*$/) {
       necho(self => $self,
             prog => $prog,
             source => [ "%s" ,
                         table("  select fde_name flag, " .
                               "         fde_letter letter " .
                               "    from flag_definition " .
                               "order by fde_name"
                              )
                       ]
            );
   } elsif(!hasflag($self,"WIZARD")) {
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
   } elsif($txt =~ /^\s*buffers{0,1}\s*$/) {
       my $hash = @info{io};
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",print_var($hash) ],
            );
   } elsif($txt =~ /^\s*sockets\s*$/) {
      if(memorydb) {
         my $out;
         for my $key (keys %connected) {
            my $hash = @connected{$key};
            $out .= "\n$$hash{hostname}$$hash{start}$$hash{port}"
         }
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s",$out ],
              );
 
      } else {
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
      }
   } else {
       err($self,
           $prog,
           "syntax: \@list <option>\n\n",
           "        Options: site,functions,commands,sockets"
          );
   }
}


sub cmd_clean
{
   my ($self,$prog,$txt) = @_;
   my $del =0;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   }

   my $start = total_size(\%cache);

   delete @cache{keys %cache};

   for my $x (keys %cache) {                                       # object
      if(ref($cache{$x}) eq "HASH") {
         for my $y (keys %{$cache{$x}}) {                       # attribute
            if(ref($cache{$x}->{$y}) eq "HASH") {
               if(defined $cache{$x}->{$y}->{value} &&
                  defined $cache{$x}->{$y}->{ts}) {
                  if(time() - $cache{$x}->{$y}->{ts} > 3600) {
                    delete $cache{$x}->{$y};
                    $del++;
                    if($y eq "FLAG_WIZARD") {
                       remove_flag_cache($x,"FLAG_WIZARD");
                    }
                  }
               } else {
                  for my $z (keys %{$cache{$x}->{$y}}) {         # atr_flag
                     if(ref($cache{$x}-{$y}->{$z}) eq "HASH") {
                        if(defined $cache{$x}->{$y}->{$z}->{value} &&
                           defined $cache{$x}->{$y}->{$z}->{ts} &&
                           time() - $cache{$x}->{$y}->{$z}->{ts} > 3600) {
                           delete $cache{$x}->{$y}->{$z};
                           $del++;
                        }
                     }
                  }
               }
            }
         }
      }
   }
   necho(self   => $self,
         prog   => $prog,
         source  => [ "Cleared %d entries freeing %d bytes.", $del,
                      ($start - total_size(\%cache)) ],
        );
}

sub cmd_destroy
{
   my ($self,$prog,$txt) = @_;

   return err($self,$prog,"syntax: \@destroy <object>") if($txt =~ /^\s*$/);
   my $target = find($self,$prog,$txt) ||
       return err($self,$prog,"I can't find an object named '%s'",$txt);

   if(hasflag($target,"PLAYER")) {
      return err($self,$prog,"Players are \@toaded not \@destroyed.");
   } elsif(!controls($self,$target)) {
      return err($self,$prog,"Permission Denied.");
   }

   my $name = name($target);
   my $objname = obj_name($self,$target);
   my $loc = loc($target);

   if(!destroy_object($target)) {
      necho(self   => $self,
            prog   => $prog,
            source  => [ "Internal error, object not destroyed." ],
           );
   } else {
      necho(self      => $self,
            prog      => $prog,
            source    => [ "%s was destroyed.",$objname ],
            room      => [ $loc, "%s was destroyed.",$name  ],
            all_room  => [ $loc, "%s has left.",$name ]
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

   my $target = find($self,$prog,$txt) ||
       return err($self,$prog,"I can't find an object named '%s'",$txt);

   if(!hasflag($target,"PLAYER")) {
      return err($self,$prog,"Only Players can be \@toaded");
   }

   my $obj_name = obj_name($self,$target);
   my $name = name($target);

   cmd_boot($self,$prog,name($$target{obj_id}));

   if(!destroy_object($target)) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Internal error, %s was not \@toaded.",$obj_name
                      ]
           );
   } elsif(loc($target) ne loc($self)) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s was \@toaded.",$obj_name ],
            room   => [ $target, "%s was \@toaded.",$name ],
            room2  => [ $target, "%s has left.",$name ]
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            room   => [ $target, "%s was \@toaded.",$name ],
            room2  => [ $target, "%s has left.",$name ]
           );
   }
}



sub cmd_think
{
   my ($self,$prog,$txt) = @_;

   my $txt = evaluate($self,$prog,$txt);

   if($txt !~ /^\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $txt ],
           );
   }
}

sub cmd_pemit
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ =]+)\s*=/s) {
      my $target = find($self,$prog,evaluate($self,$prog,$1));
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

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   }
   my $target = find_content($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   if(hasflag($target,"ROOM") || hasflag($target,"EXIT")) {
      return err($self,$prog,"You may not drop exits or rooms.");
   } elsif($$target{obj_id} == $$self{obj_id}) {
      return err($self,$prog,"You may not drop yourself.");
   }

   move($self,$prog,$target,fetch(loc($self))) ||
      return err($self,$prog,"Internal error, unable to drop that object");

   # provide some visual feed back to the player
   necho(self    => $self,
         prog    => $prog,
         source  => [ "You have dropped %s.\n%s has arrived.", 
                      name($target), name($target)
                    ],
         room    => [ $self, "%s dropped %s.", name($self),name($target) ],
         room2   => [ $self, "%s has arrived.",name($target) ]
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
 
   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   }

   my $target = find($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   if(hasflag($target,"EXIT")) {
      return err($self,$prog,"You may not pick up exits.");
   } elsif(hasflag($target,"ROOM")) {
      return err($self,$prog,"You may not pick up rooms.");
   } elsif($$target{obj_id} eq  $$self{obj_id}) {
      return err($self,$prog,"You may not pick up yourself!");
   } elsif(loc($target) == $$self{obj_id}) {
      return err($self,$prog,"You already have that!");
   } elsif(loc($target) != loc($self)) {
      return err($self,$prog,"That object is to far away");
   }


   my $atr = get($target,"OBJ_LOCK_DEFAULT");

   if($atr ne undef) {
      my $lock = lock_eval($self,$prog,$target,$atr);

      if($$lock{error}) {
         return err($self,$prog,"Permission denied, the lock has broken.");
      } elsif(!$$lock{result}) {
         return err($self,$prog,"You can't pick that up.");
      }
   }
      
   necho(self   => $self,
         prog   => $prog,
         source => [ "You have picked up %s.", name($target) ],
         target => [ $target, "%s has picked you up.", name($self) ],
         room   => [ $self, "%s picks up %s.", name($self),name($target) ],
         room2  => [ $self, "%s has left.",name($target) ]
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

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^=]+?)\s*=\s*(.+?)\s*$/) {
      my $target = find($self,$prog,$1) ||
         return err($self,$prog,"I don't see that here.");
      my $cname = trim(evaluate($self,$prog,$2));
      my $name = ansi_remove($cname);
      my $old = name($target);

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

      if(memorydb) {
         delete @player{name($target,1)};
         db_set($target,"name",$name);
         db_set($target,"cname",$cname);
      } else {

         sql($db,
             "update object " .
             "   set obj_name = ?, " .
             "       obj_cname = ? " .
             " where obj_id = ?",
             $name,
             $cname,
             $$target{obj_id},
             );
    
         set_cache($target,"obj_name");

         if($$db{rows} != 1) {
            err($self,$prog,"Internal error, name not updated.");
         } else {
            my_commit;
         }
      }

      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ],
            room   => [ $target, "%s is now known by %s.\n",$old, $cname]
           );
   } else {
      err($self,$prog,"syntax: \@name <object> = <new_name>");
   }
}

sub cmd_enter
{
   my ($self,$prog,$txt) = @_;

   my $target = find($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   # must be owner or object enter_ok to enter it
   if(!controls($self,$target) && !hasflag($target,"ENTER_OK")) {
     return err($self,$prog,"Permission denied.");
   }

   # check to see if object can pass enter lock
   my $atr = get($target,"OBJ_LOCK_ENTER");

   if($atr ne undef) {
      my $lock = lock_eval($self,$prog,$target,$atr);

      if($$lock{error}) {
         return err($self,$prog,"Permission denied, the lock has broken.");
      } elsif(!$$lock{result}) {
         return err($self,$prog,"Permission denied.");
      }
   }

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

sub cmd_to
{
    my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*([^ ]+)\s*/) {
       my $tg = find($self,$prog,$1) ||
          return err($self,$prog,"I don't see that here.");

       necho(self   => $self,
             prog   => $prog,
             source => [ "%s [to %s]: %s\n",name($self),name($tg),$' ],
             room   => [ $self, "%s [to %s]: %s\n",name($self),name($tg),$' ],
            );
    } else {
       err($self,$prog,"syntax: `<person> <message>");
    }
}



sub whisper
{
   my ($self,$prog,$target,$msg) = @_;

   my $obj = find($self,$prog,$target);
   return err($self,$prog,"I don't see that here.") if $obj eq undef;

   if(hasflag($obj,"EXIT") || hasflag($obj,"ROOM")) {
      return err($self,$prog,"You may only whisper to objects or players");
   }

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
      my $target = get($self,"OBJ_LAST_WHISPER");          # no target whisper
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

   my $target = find_player($target,"online") ||
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

   my $target = get($self,"OBJ_LAST_PAGE");                    # no target page
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
      $what = find_player($1,"anywhere") ||
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
   my ($exit ,$dest);

   $txt =~ s/^\s+|\s+$//g;
   my $loc = loc($self);

   if($txt =~ /^\s*home\s*$/i) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "There's no place like home...\n" .
                        "There's no place like home...\n" . 
                        "There's no place like home..."  ],
            room   => [ $self, "%s goes home.",name($self) ],
            room2  => [ $self, "%s has left.",name($self) ],
           );

      $dest = home($self);

      necho(self   => $self,
            prog   => $prog,
            room   => [ $self, "%s goes home.", name($self) ],
            room2  => [ $self, "%s has left.",name($self) ],
           );

   } else {
      # find the exit to go through
      $exit = find_exit($self,$prog,$txt) ||
         return err($self,$prog,"You can't go that way.");
 
      $dest = dest($exit);
  
      # grab the destination object
      if(dest($exit) eq undef) {
         return err($self,$prog,"That exit does not go anywhere");
      }
      necho(self   => $self,
            prog   => $prog,
            room   => [ $self, "%s goes %s.",name($self),
                        first(name($exit))
                      ],
            room2  => [ $self, "%s has left.",name($self) ],
           );
   }

   # move it, move it, move it. I like to move it, move it.
   move($self,$prog,$self,$dest) ||
      return err($self,$prog,"Internal error, unable to go that direction");

   generic_action($self,$prog,"MOVE",$loc);

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

   $target = find($self,$prog,$target) ||
      return err($self,$prog,"I don't see that object here.");

   $location = find($self,$prog,$location) ||
      return err($self,$prog,"I can't find that location");

   controls($self,$target) ||
      return err($self,$prog,"Permission Denied.");

   controls($self,$location) ||
      return err($self,$prog,"Permission Denied.");

   if(hasflag($location,"EXIT")) {
      if((owner(loc($location)) == $$self{obj_id} &&
         loc($location) == loc($target)) ||
         hasflag($self,"WIZARD")) {
         $location = fetch(dest($location));

         if($location eq undef) {
            return err($self,$prog,"That exit does not go anywhere.");
         }
      } else {
         return err($self,$prog,"Permission Denied.");
      }
   }
   
   necho(self   => $self,
         prog   => $prog,
         all_room   => [ $target, "%s has left.",name($target) ]
        );

   move($self,$prog,$target,$location) ||
      return err($self,$prog,"Unable to teleport to that location");

   necho(self   => $self,
         prog   => $prog,
         all_room   => [ $target, "%s has arrived.",name($target) ]
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
      print "\033[0;0H";  #jump to 0,0
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

      if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
         ws_echo($sock,@info{"conf.logoff"});
      } else {
         printf($sock "%s",@info{"conf.logoff"});
      }
      server_disconnect($sock);
   } else {
      err($self,$prog,"Permission denied [Non-players may not quit]");
   }
}

sub cmd_help
{
   my ($self,$prog,$txt) = @_;

   $txt = "help" if($txt =~  /^\s*$/);
   my $help = one_val("select hlp_data value" .
                      "  from help " . 
                      " where hlp_name = ? ",
                      lc(trim($txt))
                     );
   if($help eq undef) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "No entry for '%s'", trim($txt) ]
           );
   } elsif($help =~ /^RUN: \s*(.*)\s*$/i) {
      mushrun(self   => $self,
              prog   => $prog,
              runas  => $self,
              source => 0,
              cmd    => $1
             );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $help  ]
           );
   }
}

sub cmd_help_old
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
            source => [ "%s", @info{"conf.registration"} ],
           );
   } elsif($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/) {
      if(inuse_player_name($1)) {
         err($user,$prog,"That name is already in use.");
      } else {
         $$user{obj_id} = create_object($self,$prog,$1,$2,"PLAYER");
         $$user{obj_name} = $1;
         cmd_connect($self,$prog,$txt);
      }
   } else {
      err($user,$prog,"Invalid create command, try: create <user> <password>");
   }
}

sub create_exit
{
   my ($self,$prog,$name,$in,$out,$verbose) = @_;

   my $exit = create_object($self,$prog,$name,undef,"EXIT") ||
      return undef;

   if(!link_exit($self,$exit,$in,$out,1)) {
      return undef;
   }

   return $exit;
}

sub cmd_create
{
   my ($self,$prog,$txt) = (@_[0],@_[1],trim(@_[2]));

   if(quota_left($self) <= 0) {
      return err($self,$prog,"You are out of QUOTA to create objects.");
   } elsif(length($txt) > 50) {
      return err($self,$prog,
                 "Object name may not be greater then 50 characters"
                );
   } elsif(money($self) < @info{"conf.createcost"}) {
      return err($self,$prog,"You need at least ".pennies("createcost").".");
   }

   my $dbref = create_object($self,$prog,$txt,undef,"OBJECT") ||
      return err($self,$prog,"Unable to create object");

   if(!give_money($self,"-" . @info{"conf.createcost"})) {
      return err($self,$prog,"Unable to deduct cost of object.");
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Object created as: %s",obj_name($self,$dbref) ],
        );

   my_commit if mysqldb;
}

sub cmd_link
{
   my ($self,$prog,$txt) = @_;
   my ($name,$target,$dest);

   if($txt =~ /^\s*([^ ]+)\s*=\s*here\s*$/i) {
      ($name,$dest) = ($1,"#" . loc($self));
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*#(\d+)\s*$/) {
      ($name,$dest) = ($1,"#" . $2);
   } else {
      err($self,$prog,"syntax: \@link <exit> = <room_dbref>\n" .
                      "        \@link <exit> = here\n");
   }

   my $loc = loc($self) ||
      return err($self,$prog,"Unable to determine your location");

   my $target = find_exit($self,$prog,$name) ||
      return err($self,$prog,"I don't see that here");

   my $d = find($self,$prog,$dest) ||
      return err($self,$prog,"I don't see $dest here");

   if(!valid_dbref($target)) {
      return err($self,$prog,"%s not a valid object.",$name);
   } elsif(!valid_dbref($dest)) {
      return err($self,$prog,"%s not a valid object.",$dest);
   } elsif(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
      return err($self,$prog,"You do not own this room and it is not LINK_OK");
   }


   if(hasflag($target,"EXIT")) { 
     
      necho(self   => $self,
            prog   => $prog,
            source => [ "DEST: $dest" ],
           );
      $dest = fetch($dest);

      link_exit($self,$target,undef,$dest) ||
         return err($self,$prog,"Internal error while trying to link exit");

      necho(self   => $self,
            prog   => $prog,
            source => [ "Exit linked to %s",obj_name($self,$dest,1) ],
           );
   } elsif(hasflag($target,"EXIT")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "That is not an object or room." ]
           );
   } elsif(controls($self,$target) || hasflag($target,"ABODE")) {

         if(memorydb) {
            db_set($target,"home",$$target{obj_id});
         } else {
            sql("update object " . 
                "   set obj_home = ? ".
                " where obj_id = ? ",
                $$d{obj_id},
                $$target{obj_id}
               );
            if($$db{rows} != 1) {
               return err($self,$prog,"Internal error, unable to set home");
            }
         }
         necho(self   => $self,
               prog   => $prog,
               source => [ "Home set to " . obj_name($self,$d) ]
              );
         my_commit;
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied" ]
           );
   
   }
}


sub cmd_dig
{
   my ($self,$prog,$txt) = @_;
   my ($loc,$room_name,$room,$in,$out,$cost);
     
   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied."); 
   } elsif($txt =~ /^\s*([^\=]+)\s*=\s*([^,]+)\s*,\s*(.+?)\s*$/ ||
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
   } elsif($in ne undef && $out ne undef) {
      $cost = @info{"conf.digcost"} + (@info{"conf.linkcost"} * 2);
   } elsif($in ne undef || $out ne undef) {
      $cost = @info{"conf.digcost"} + @info{"conf.linkcost"};
   } elsif($in eq undef && $out eq undef) { 
      $cost = @info{"conf.digcost"};
   }

   if($cost > money($self)) {
      return err($self,$prog,"You need at least " . pennies($cost));
   }

   if(!give_money($self,"-" . $cost)) {
      return err($self,$prog,"Internal error, couldn't debit " .
                 pennies($cost));
   }


   if($in ne undef && find_exit($self,$in)) {
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
   my ($exit,$destination,$dest);
  
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

   !find_exit($self,$exit,"EXACT") ||
      return err($self,$prog,"Exit '%s' already exists in this location",$exit);

   my $loc = loc($self) ||
      return err($self,$prog,"Unable to determine your location");

   if(!(controls($self,$loc) || hasflag($loc,"ABODE"))) {
      return err($self,$prog,"You do not own this room and it is not ABODE");
   }


   if($destination ne undef) {
      $dest = find($self,$prog,$destination) ||
         return err($self,$prog,"I can't find that destination location");

      if(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
         return err($self,$prog,"This is not your room and it is not LINK_OK");
      }
   }

   my $dbref = create_exit($self,$prog,$exit,$loc,$dest) ||
      return err($self,$prog,"Internal error, unable to create the exit");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Exit created as %s(#%sE)",$exit,$dbref ],
        );

   my_commit;
}

sub mushhash
{
   return "*" . uc(sha1_hex(sha1(shift)));
}

#
# invalid_player
#    Determine if the request is valid or not, provide feed back and log
#    if the attempt wasn't valid.
#
sub invalid_player
{
   my ($self,$name,$pass) = @_;

   if(memorydb()) {
       return 1 if(!defined @player{lc($name)});

       if(!valid_dbref(@player{lc($name)}) ||
          get(@player{lc($name)},"obj_password") ne mushhash($pass)) {
          return 1;
       } else {
          $$self{obj_id} = @player{lc($name)};
          return 0;
       }
   } else {
       my $id = one_val("select obj.obj_id value ".
                        "  from object obj, ".
                        "       flag flg, ".
                        "       flag_definition fde ".
                        " where lower(obj_name) = lower(?) " .
                        "   and obj.obj_id = flg.obj_id " .
                        "   and flg.fde_flag_id = fde.fde_flag_id " .
                        "   and fde.fde_name = 'PLAYER' " .
                        "   and obj_password = password(?)",
                        $name,
                        $pass
                       );

       if($id ne undef) {
          $$self{obj_id} = $id;
          return 0;
       } else {
          return 1;
       }
   }
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
   my ($atr,$player);
 
   if($txt =~ /^\s*([^ ]+)\s+([^ ]+)\s*$/ ||            #parse player password
      $txt =~ /^\s*([^ ]+)\s*$/) {
      my ($username,$pass) = ($1,$2);

      # --- Valid User ------------------------------------------------------#

      if(invalid_player($self,$username,$pass)) {
         if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
            ws_echo($sock,"Invalid command, try: connect <user> <password>");
         } else {
            printf($sock "Invalid command, try: connect <user> <password>\r\n");
         }
         return;
      }

      # --- Hook connected user up to local structures ----------------------#
      $$player{connect_time} = time();
      for my $key (keys %$player) {                 # copy object structure
         $$user{$key} = $$player{$key};
      }
      $$user{loggedin} = 1;

      if(!defined @connected_user{$$user{obj_id}}) {    # reverse lookup
          @connected_user{$$user{obj_id}} = {};                   # setup
      }
      @{@connected_user{$$user{obj_id}}}{$$user{sock}} = $$user{sock};

      # --- log connnect ----------------------------------------------------#
      if(mysqldb) {
         sql( "insert into socket " .
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
   
         # put the historical request in right away, no need to wait.
         sql("insert into socket_history ".
             "( obj_id, " .
             "  sck_id, " .
             "  skh_hostname, " .
             "  skh_start_time, " .
             "  skh_success, " .
             "  skh_type ".
             ") values ( " .
             "  ?, ?, ?, now(), 1, ? ".
             ")",
             $$user{obj_id},
             curval(),
             $$user{hostname},
             1
            );
   
         my_commit($db);
      }

      # --- Provide users visual feedback / MOTD --------------------------#

      necho(self   => $user,                 # show message of the day file
            prog   => prog($user,$user),
            source => [ "%s", motd() ]
           );

      cmd_look($user,prog($user,$user));                    # show room

      printf("    %s@%s\n",name($user),$$user{hostname});


      # notify users local and users with monitor flag
      necho(self   => $user,
            prog   => prog($user,$user),
            room   => [ $user , "%s has connected.",name($user) ],
           );

      echo_flag($user,
                prog($user,$user),
                "CONNECTED,PLAYER,MONITOR",
                "[Monitor] %s has connected.",name($user));

      # --- Handle @ACONNECTs on masteroom and players-----------------------#

      if(@info{"conf.master"} ne undef) {
         for my $obj (lcon(@info{"conf.master"}),$player) {
            if(($atr = get($obj,"ACONNECT")) && $atr ne undef){
               mushrun(self   => $self,                 # handle aconnect
                       runas  => $self,
                       source => 0,
                       cmd    => $atr
                      );
            }
         }
      }

   } else {
      # not sure this can actually happen
      if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
         ws_echo($sock,"Invalid command, try: connect <user> <password>");
      } else {
         printf($sock "Invalid command, try: connect <user> <password>\r\n");
      }
   }
}

#
# cmd_doing
#    Set the @doing that is visible from the WHO/Doing command
#
sub cmd_doing
{
   my ($self,$prog,$txt,$switch) = @_;

   if(!defined @connected{$$self{sock}}) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ]
           );
   } elsif(defined $$switch{header} && $txt =~ /^\s*$/) {
      if(!hasflag($self,"WIZARD")) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "Permission denied." ]
                      );
      }
      delete @info{"conf.doing_header"};
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "Removed." ]
                  );
   } elsif(defined $$switch{header}) {
      if(!hasflag($self,"WIZARD")) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "Permission denied." ]
                      );
      }
      @info{"conf.doing_header"} = $txt;
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "Set." ]
                  );
   } elsif($txt =~ /^\s*$/) {
      delete $connected{$$self{sock}}{obj_doing};
      necho(self   => $self,
            prog   => $prog,
            source => [ "Removed." ]
           );
   } else {
      $connected{$$self{sock}}{obj_doing} = trim($txt);
      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ]
           );
   }
}


sub cmd_describe
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^ \/]+?)\s*=\s*(.*?)\s*$/) {
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

    if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /^\s*([^ =]+?)\s*\/\s*([^ =]+?)\s*=(.*)$/s) { # attribute
      if(@{$$prog{cmd}}{source} == 1) {                          # user input
         ($target,$attr) = ($1,$2);
      } else {                                               # non-user input
         ($target,$attr) = (evaluate($self,$prog,$1),evaluate($self,$prog,$2));
      }
      ($target,$value) = (find($self,$prog,$target),$3);

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
      my_commit($db) if(mysqldb);

   } elsif($txt =~ /^\s*([^ =\\]+?)\s*= *(.*?) *$/s) { # flag?
      ($target,$flag) = (find($self,$prog,$1),$2);
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

sub reconstitute
{
   my ($name,$type,$pattern,$value,$flag,$raw) = @_;

   if($type eq undef) {
      if($flag eq undef) {
         return color("h",uc($name)) . ": $value" if($type eq undef);
      } else {
         return color("h",uc($name)) . "[$flag]: $value" if($type eq undef);
      }
   }

   if($type == 1) {
      $type = "\$";
   } elsif($type == 2) {
      $type = "^";
   } elsif($type == 3) {
      $type = "!";
   }

   # convert single line unreadable mushcode into hopefully readable
   # multiple line code
   if(!$raw &&
      length($value) > 78 &&
      $value !~ /\n/ &&
      ($pattern ne undef || $value  =~ /^\s*([\$|\[|^|!|@])/)) {
      if($1 eq "[") {
         $value = "\n" . function_print(3,single_line($value));
      } else {
         $value = "\n" . pretty(3,single_line($value));
      }
      $value =~ s/\n+$//;
   }

   if($flag ne undef) {
      return color("h",uc($name)) . "[$flag]: ".$type.$pattern . ":" . $value;
   } else {
      return color("h",uc($name)) . ": $type$pattern:" . $value;
   }
}

sub list_attr_flags
{
   my $attr = shift;
   my $result;

   for my $name (keys %{$$attr{flag}}) {
      $result .= flag_letter($name);
   }
   return $result;
}

sub list_attr
{
   my ($obj,$pattern,$switch) = @_;
   my (@out,$pat,$keys);

   $pat = glob2re($pattern) if($pattern ne undef);

   if(memorydb) {
      for my $name (lattr($obj)) {
         if($pat eq undef || $name =~ /$pat/) {
            if(!reserved($name) && lc($name) ne "description") {
                my $attr = mget($obj,$name);
                push(@out,reconstitute($name,
                                       $$attr{type},
                                       $$attr{glob},
                                       $$attr{value},
                                       list_attr_flags($attr),
                                       $$switch{raw}
                                      )
                    );
            }
         }
      }
   } else {
      for my $hash (@{sql($db,
          "   select atr_name, " .
          "          atr_value, " .
          "          atr_pattern, " .
          "          atr_pattern_type, ".
          "          group_concat(distinct fde_letter order by fde_order " .
          "             separator '') atr_flag " .
          "     from attribute atr left join ( " .
          "             select atr_id, fde_letter, fde_order " .
          "               from flag flg, flag_definition fde " .
          "              where flg.fde_flag_id = fde.fde_flag_id " .
          "                and fde_type = 2 " .
          "           ) flg on (atr.atr_id = flg.atr_id) " .
          "    where atr.obj_id = ? " .
          "      and atr_name not in ('DESCRIPTION', " .
          "                           'LOCK_DEFAULT', " . 
          "                           'LAST_WHISPER', " .
          "                           'LAST_PAGE') ".
          " group by atr.atr_id, atr_name " .
          " order by atr.atr_name",
          $$obj{obj_id},
         )}) { 

         if($pat eq undef || $$hash{atr_name} =~ /$pat/) {
            push(@out,reconstitute($$hash{atr_name},
                                   $$hash{atr_pattern_type},
                                   $$hash{atr_pattern},
                                   $$hash{atr_value},
                                   $$switch{raw}
                                  )
                );
         }
      }
   }


   if($#out == -1 && $pattern !~ /^\s*$/) {
      return "No matching attributes";
   } else {
      return join("\n",@out);
   }
}

sub cmd_ex
{
   my ($self,$prog,$txt,$switch) = @_;
#   my ($self,$prog,$txt) = @_;
   my ($target,$desc,@exit,@content,$atr,$out);

   validate_switches($self,$prog,$switch,"raw") || return;

   $txt = evaluate($self,$prog,$txt);

   ($txt,$atr) = ($`,$') if($txt =~ /\//);

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
   } elsif($txt =~ /^\s*(.+?)\s*$/) {
      $target = find($self,$prog,$1) ||
         return err($self,$prog,"I don't see that here.");
   } else {
       return err($self,$prog,"I don't see that here.");
   }


   my $perm = controls($self,$target,1);

   if($atr ne undef) {
      if($perm) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s",list_attr($target,$atr,$switch)],
                     );
      }
      return err($self,$prog,"Permission denied.");
   }

   $out .= obj_name($self,$target,$perm);
   my $flags = flag_list($target,1);

   if($flags =~ /(PLAYER|OBJECT|ROOM|EXIT)/i) {
      $out .= "\n" . color("h","Type") . ": $1  " . 
              color("h","Flags") . ": ";
      my $rest = trim($` . $');
      $rest =~ s/\s{2,99}/ /g;
      $out .= $rest;
   } else {
      $out .= "\n" . color("h","Type") . ": *UNKNOWN*  " . 
              color("h","Flags") . ": " . $flags;
   }

   $out .= "\n" . 
           nvl(get($$target{obj_id},"DESCRIPTION"),
               "You see nothing special."
              );

   my $owner = owner($target);
   $out .= "\n" . color("h","Owner") . ": " . obj_name($self,$owner,$perm) . 
           "  " . color("h","Key") . " : " . nvl(lock_uncompile($self,
                                          $prog,
                                          get($target,"OBJ_LOCK_DEFAULT")
                                         ),
                           "*UNLOCKED*"
                          ) .
           "  " . color("h",ucfirst(@info{"conf.money_name_plural"})) .
           ": ". money($target);

   $out .= "\n" . color("h","Created") . ": " . firsttime($target);
   if(hasflag($target,"PLAYER")) {
      if($perm) {
         $out .= "\n".color("h","Firstsite").": " . firstsite($target) . "\n" .
                 color("h","Lastsite") . ": " . lastsite($target);
      }
      my $last = lasttime($target);
       
      if($last eq undef) {
         $out .= "\nLast: N/A";
      } else {
         $out .= "\n" . color("h","Last") . ": ". $last;
      }
   }

   if($perm) {                                             # show attributes
      my $attr = list_attr($target,undef,$switch);
      $out .= "\n" . $attr if($attr ne undef);
   }


   for my $obj (lcon($target)) {
      push(@content,obj_name($self,$obj));
   }

   if($#content > -1) {
      $out .= "\n" . color("h","Contents") . ":\n" . join("\n",@content);
   }

   if(hasflag($target,"EXIT")) {
      $out .= "\nSource: " . nvl(obj_name($self,loc_obj($target)),"N/A");
      $out .= "\nDestination: " . nvl(obj_name(dest($target)),"*UNLINKED*");
   }

   for my $obj (lexits($target)) {
      push(@exit,obj_name($self,$obj)) if(!hasflag($obj,"DARK"));
   }

   if($#exit >= 0) {
      $out .= "\nExits:\n" . join("\n",@exit);
   }

   if($perm && (hasflag($target,"PLAYER") || hasflag($target,"OBJECT"))) {
      $out .= "\n" . color("h","Home") . ": " . 
              obj_name($self,home($target),$perm) .
              "\n" . color("h","Location") . ": " . 
              obj_name($self,loc_obj($target),$perm);
   }
   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", $out ]
        );
}

sub cmd_inventory
{
   my ($self,$prog,$txt) = @_;
   my $out;

   my $inv = [ lcon($self) ];

   if($#$inv == -1) {
      $out .= "You are not carrying anything.";
   } else {
      $out = "You are carrying:";
      for my $i (0 .. $#$inv) {
         $out .= "\n" . obj_name($self,$$inv[$i]);
      }
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s\nYou have %s", $out,pennies($self) ],
        );
  
}


#
# cmd_look
#
#    Show the player what is around it.
#
sub cmd_look
{
   my ($self,$prog,$txt) = @_;
   my ($flag,$desc,$target,@exit,$out,$name);
   my $owner = owner_id($self);
   my $perm = hasflag($self,"WIZARD");

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
      return err($self,$prog,"I don't see that here.") if $target eq undef;
   } elsif(!($target = find($self,$prog,evaluate($self,$prog,$txt)))) {
      return err($self,$prog,"I don't see that here.");
   }

   $out = obj_name($self,$target);
   if(($desc = get($$target{obj_id},"DESCRIPTION")) && $desc ne undef) {
      $out .= "\n" . evaluate($target,$prog,$desc);
   } else {
      $out .= "\nYou see nothing special.";
   }

   if(memorydb) {
      for my $obj (lcon($target)) { 
         if(!hasflag($obj,"DARK") &&
            ((hasflag($obj,"PLAYER") && hasflag($obj,"CONNECTED") ||
            !hasflag($obj,"PLAYER"))) &&
            $$obj{obj_id} ne $$self{obj_id}) {
            $out .= "\n" . color("h","Contents") . ":" if(++$flag == 1);
            if($$prog{hint} eq "WEB") {
                 $out .= "\n<a href=/look/$$obj{obj_id}/>" . 
                         obj_name($self,$obj,undef,1) . "</a>";
            } else {
               $out .= "\n" . obj_name($self,$obj);
            }
         }
      }
      for my $obj (lexits($target)) { 
         if($obj ne undef && !hasflag($obj,"DARK")) {
            if($$prog{hint} eq "WEB") {
                push(@exit,
                     "<a href=/look/" . dest($obj) . ">" . 
                     first(name($obj)) .
                     "</a>"
                    );
            } else {
               push(@exit,first(name($obj)));
            }
         }
      }
   } elsif(!hasflag($target,"ROOM") ||
      (hasflag($target,"ROOM") && !hasflag($target,"DARK"))) {
      for my $hash (@{sql($db,
          "select   group_concat(distinct fde_letter " .
          "                      order by fde_order " .
          "                      separator '') flags, " .
          "         obj.obj_id," .
          "         min(obj.obj_name) obj_name, " .
          "         min(obj.obj_cname) obj_cname, " .
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
          "         min(obj.obj_owner) obj_owner,".
          "         min(con.con_dest_id) con_dest_id ".
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
          "order by con_created_date desc",
          $$target{obj_id},
          $$self{obj_id}
         )}) {
   
          # skip non-connected players
          next if($$hash{obj_type} eq "PLAYER" && $$hash{online} eq "N");

          if($$hash{obj_cname} ne undef) {
             $$hash{obj_name} = $$hash{obj_cname};
          }
   
          if($$hash{obj_type} eq "EXIT") {                   # store exits for
             if($$hash{flag} !~ /D/) {                                 # later
                if($$prog{hint} eq "WEB") {
                   push(@exit,
                        "<a href=/look/$$hash{con_dest_id}>" . 
                        first($$hash{obj_name}) .
                        "</a>"
                       );
                } else {
                   push(@exit,first($$hash{obj_name}));
                }
             }
          } elsif($$hash{obj_type} =~ /^(PLAYER|OBJECT)$/ && 
                 $$hash{flags} !~ /D/){
             $out .= "\n" . color("h","Contents") . ":" if(++$flag == 1);

             if($$hash{obj_owner} == $owner || $perm) {
                 $name = "$$hash{obj_name}(#$$hash{obj_id}$$hash{flags})";
             } else {
                 $name = "$$hash{obj_name}";
             }
             if($$prog{hint} eq "WEB") {
                 $out .= "\n<a href=/look/$$hash{obj_id}/>$name</a>";
             } else {
                 $out .= "\n" . $name;
             }
          }
      }
   }
   $out .= "\n" . color("h","Exits") . ":\n" . 
            join("  ",@exit) if($#exit >= 0);  # add any exits

   necho(self   => $self,
         prog   => $prog,
         source => ["%s",$out ]
        );

   if(($desc = get($target,"ADESCRIBE")) && $desc ne undef) {
#      my $hint = $$prog{hint};
#      delete @$prog{hint};
      return mushrun(self   => $self,           # handle adesc
                     prog   => $prog,
                     runas  => $target,
                     source => 0,
                     cmd    => $desc
                     );
#      @$prog{hint} = $hint;
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

   if($txt =~ /^\s*([^& =]+)\s+([^ =]+)\s*=(.*?) *$/s) {
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

   return err($self,$prog,"Permission denied.") if(!hasflag($self,"WIZARD"));

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
   my ($self,$prog,$txt) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,$prog,$txt) ]
        );
}

sub cmd_DOING
{
   my ($self,$prog,$txt) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,$prog,$txt,1) ]
        );
}

sub who
{
   my ($self,$prog,$txt,$flag) = @_;
   my ($max,$online,@who,$idle,$count,$out,$extra,$hasperm,$name) = (2,0);

   if(ref($self) eq "HASH") {
      $hasperm = ($flag || !hasflag($self,"WIZARD")) ? 0 : 1;
   } else {
      $hasperm = 0;
   }

   # query the database for connected user, location, and socket
   # details.
   for my $key (sort {@{@connected{$b}}{start} <=> @{@connected{$a}}{start}} 
                keys %connected) {
      my $hash = @connected{$key};
      next if $$hash{raw} != 0;

      # only list users that start with provided text 
      if($$hash{obj_id} ne undef) {
         if(($txt ne undef && 
            lc(substr($$hash{obj_name},0,length($txt))) eq lc($txt)) ||
            $txt eq undef) {
            if(length(loc($hash)) > length($max)) {
               $max = length(loc($hash));
            }
            push(@who,$hash);
         }
         $online++;
      }
   }
      
   # show headers for normal / wiz who 
   if($hasperm) {
      $out .= sprintf("%-15s%10s%5s %-*s %-4s %s\r\n","Player Name","On For",
                      "Idle",$max,"Loc","Port","Hostname");
   } else {
      $out .= sprintf("%-15s%10s%5s  %s\r\n","Player Name","On For","Idle",
                      defined @info{"conf.doing_header"} ? 
                      @info{"conf.doing_header"} : "\@doing"
                     );
   }

   $max = 3 if($max < 3);

   # generate detail for every connected user
   for my $hash (@who) {
      # determine idle details

      if(defined $$hash{last}) {
         $idle = date_split(time() - @{$$hash{last}}{time});
      } else {
         $idle = { max_abr => 's' , max_val => 0 };
      }

      # determine connect time details
      
      my $online = date_split(time() - fuzzy($$hash{start}));
      if($$online{max_abr} =~ /^(M|w|d)$/) {
         $extra = sprintf("%4s",$$online{max_val} . $$online{max_abr});
      } else {
         $extra = "    ";
      } 
 
      if($$prog{hint} eq "WEB") {
         $name = name($hash);
         $name = "<a href=look/$$hash{obj_id}>$name</a>" .
                 (" " x (15 - ansi_length($name)));
      } else {
         $name = ansi_substr(name($hash),0,15);
         $name = $name . (" " x (15 - ansi_length($name)));
      }

      # show connected user details
      if($hasperm) {
         $out .= sprintf("%s%4s %02d:%02d %4s %-*s %-4s %s%s\r\n",
             $name,$extra,$$online{h},$$online{m},$$idle{max_val} .
             $$idle{max_abr},$max,"#" . loc($hash),$$hash{port},
             short_hn($$hash{hostname}),
             ($$hash{site_restriction} == 69) ? " [HoneyPoted]" : ""
            );
      } elsif($$hash{site_restriction} != 69) {
         $out .= sprintf("%s%4s %02d:%02d %4s  %s\r\n",$name,$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             $$hash{obj_doing});
      }
   }
   $out .= sprintf("%d Players logged in\r\n",$online);        # show totals
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
            source => [ "   %s is listening.", obj_name($self,$$obj{obj_id}) ],
           );
    }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Sweep complete." ]
        );
}
