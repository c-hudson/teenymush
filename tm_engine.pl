#!/usr/bin/perl
#
# tm_engine
#    This file contains any functions required to handle the scheduling of
#    running of mush commands. The hope is to balance the need for socket
#    IO verses the need to run mush commands.
#





use Time::HiRes "ualarm";

sub mush_command
{
   my ($self,$prog,$runas,$cmd) = @_;
   my ($match,$questions,@where)= (0);

   ($where[0],$where[1]) = (loc($self),$$self{obj_id});
   if(defined $info{master_room}) {
      $questions = "?,?,?";
      push(@where,$info{master_room});
   } else {
      $questions = "?,?";
   }

   # look for any attributes in the same room as the player
   for my $hash (@{sql("select obj.*, " .
                       "       substr(atr_value,2,instr(atr_value,':')-2) cmd,".
                       "       substr(atr_value,instr(atr_value,':')+1) txt,".
                       "       atr_name, ".
                       "       0 source " .
                       "  from object obj, attribute atr, content con " .
                       " where obj.obj_id = atr.obj_id " .
                       "   and obj.obj_id = con.obj_id " .
                       "   and ? like  " .
                       "         replace(replace(substr(atr_value,1," .
                       "         instr(atr_value,':')-1),'*','%'),'?','_')" .
                       "   and con.con_source_id in ( $questions ) ",
                       "\$" . lc($cmd),
                       @where
                      )
                }) {
      $$hash{cmd} =~ s/\*/\(.*\)/g;
      $$hash{cmd} =~ s/\?/(.{1})/g;
      $$hash{cmd} =~ s/\+/\\+/g;
      $$hash{cmd} =~ s/\$/\\\$/g;
      $$hash{txt} =~ s/\r\s*|\n\s*//g;
      if($cmd =~ /^$$hash{cmd}$/) {
         mushrun(self   => $self,
                 prog   => $prog,
                 runas  => $hash,
                 source => 0,
                 cmd    => $$hash{txt},
                 wild   => [ $1,$2,$3,$4,$5,$6,$7,$8,$9 ],
                 from   => "ATTR"
                );
      } else {
         mushrun(self   => $self,
                 prog   => $prog,
                 runas  => $hash,
                 source => 0,
                 cmd    => $$hash{txt},
                 from   => "ATTR"
                );
      }
      $match=1;                                   # signal mush command found
   }
   return $match;
}


sub priority
{
   my $obj = shift;

   return 100;

   $obj = owner($obj) if(!hasflag($obj,"PLAYER"));

   return (perm($obj,"HIGH_PRORITY") ? 50 : 1);
}

sub inattr
{
   my ($self,$source) = @_;

   if(ref($self) ne "HASH" ||
      !defined $$self{sock} ||
      !defined @connected{$$self{sock}} ||
      ref(@connected{$$self{sock}}) ne "HASH" ||
      !defined @{@connected{$$self{sock}}}{inattr}) {
      return undef;
   } else {
      return @{@connected{$$self{sock}}}{inattr};
   }
}

sub prog
{
   my ($self,$runas) = @_;

   return {
      stack => [ ],
      enactor => $self,
      created_by => $self,
      user => 
      var => {},
      priority => priority($self),
      calls => 0
   };
}

#
# mushrun
#    Add the command to the que of what to run. The command will be run
#    later.
#
# $source (1 = direct user input, 0 = indirect user input)
sub mushrun
{
   my %arg = @_;
   my $multi = inattr($arg{self},$arg{source});

   if(!$multi) {
       return if($arg{cmd} =~ /^\s*$/);                        # empty command
       @arg{cmd} = $1 if($arg{cmd} =~ /^\s*{(.*)}\s*$/s);       # strip braces
   }

   if(!defined $arg{prog}) {                                     # new program
      @arg{prog} = prog($arg{self},$arg{runas});
      @info{engine} = {} if not defined $info{engine}; # add to all programs
      @{$info{engine}}{++$info{pid}} = [ $arg{prog} ];
   }


   # prevent RUN() from adding commands to the queue
   if(defined @{@arg{prog}}{output} &&
      defined @{@arg{prog}}{nomushrun} && @{@arg{prog}}{nomushrun}) {
      my $stack = @{@arg{prog}}{output};
      push(@$stack,"#-1 Not a valid command inside RUN function");
      return;
   }

   if(defined $arg{from}) {
      @{@arg{prog}}{from} = $arg{from} if(!defined @{@arg{prog}}{from});
   }

   if(!defined @{@arg{prog}}{hint}) {
      @{@arg{prog}}{hint} = ($arg{hint} eq undef) ? "PLAYER" : $arg{hint};
   }

   if(defined @arg{output} && !defined @{@arg{prog}}{output}) {
      @{@arg{prog}}{output} = @arg{output};
   }

   if(defined @arg{sock} && !defined @{@arg{prog}}{sock}) {
      @{@arg{prog}}{sock} = @arg{sock};
   }

   # handle multi-line && command
   if($arg{source} == 1 && $multi eq undef) {
      if($arg{cmd} =~ /^\s*&&([^& =]+)\s+([^ =]+)\s*= *(.*?) *$/) {
         @{@connected{@{$arg{self}}{sock}}}{inattr} = {
            attr    => $1,
            object  => $2,
            content => ($3 eq undef) ? [] : [ $3 ],
            prog    => $arg{prog},
         };
         return;
      }
   } elsif($arg{source} == 1 && $multi ne undef) {
         my $stack = $$multi{content};
      if($arg{cmd} =~ /^\s*$/) {                                # attr is done
         @arg{cmd} = "&$$multi{attr} $$multi{object}=" . join("\r\n",@$stack);
         delete @{$connected{@{$arg{self}}{sock}}}{inattr};
      } elsif($arg{cmd} eq ".") {                                # blank line
         push(@$stack,"");
         return;
      } else {                                          # another line of atr
         push(@$stack,$arg{cmd});
         return;
      }
   };

    # copy over command(s)
    my $stack=@{$arg{prog}}{stack};
    if($arg{source}) {
       unshift(@$stack,{ runas => $arg{runas}, cmd => $arg{cmd}, source => 1 });
    } else {
       for my $i ( balanced_split($arg{cmd},';',3,1) ) {
          $i =~ s/^\s+|\s+$//g;
          if($i ne undef) {
             if(defined $arg{child} && $arg{child}) {
#                push(@$stack,{runas => $arg{runas},cmd => $i,source => 0});
                unshift(@$stack,{runas => $arg{runas},cmd => $i,source => 0});
             } else {
                push(@$stack,{runas => $arg{runas}, cmd => $i, source => 0 });
             }
          }
       }
    }

    if(defined $arg{wild}) {
       set_digit_variables($arg{self},$arg{prog},@{$arg{wild}}); # copy %0..%9
    }
    
    delete @{$arg{self}}{child};
    return @arg{prog};
}

sub set_digit_variables
{
   my ($self,$prog) = (shift,shift);

   if(ref($_[0]) eq "HASH") {
      my $new = shift;
      for my $i (0 .. 9) {
         if($self ne undef) {
            @{$$prog{var}}{$i} = evaluate($self,$prog,$$new{$i});
         } else {
            @{$$prog{var}}{$i} = $$new{$i};
         }
      }
   } else {
      my @var = @_;

      for my $i (0 .. 9 ) {
         if($self ne undef) {
            @{$$prog{var}}{$i} = evaluate($self,$prog,$var[$i]);
         } else {
            @{$$prog{var}}{$i} = $var[$i];
         }
      }
   }
}

sub get_digit_variables
{
    my $prog = shift;
    my $result = {};
  
    for my $i (0 .. 9) {
       $$result{$i} =  @{$$prog{var}}{$i};
    }
    return $result;
}

#
# spin
#    Run one command from each program that is running
#
sub spin
{
   my (%last);
   my $count = 0;

   $SIG{ALRM} = \&spin_done;

   my $start = Time::HiRes::gettimeofday();
   @info{engine} = {} if(!defined @info{engine});

   eval {
       local $SIG{__DIE__} = sub {
          printf("----- [ Crash Report@ %s ]-----\n",scalar localtime());
          printf("User:     %s\nCmd:      %s\n",name($user),
              @{@last{cmd}}{cmd});
          if(defined @info{sql_last}) {
             printf("LastSQL: '%s'\n",@info{sql_last});
             printf("         '%s'\n",@info{sql_last_args});
             delete @info{sql_last};
             delete @info{sql_last_args};
          }
          printf("%s",code("long"));
       };

#      ualarm(800_000);                                # die at 8 milliseconds
#      ualarm(1_200_000);                                # die at 8 milliseconds

#      printf("PIDS: '%s'\n",join(',',keys %{@info{engine}}));
      for my $pid (sort { $a cmp $b } keys %{@info{engine}}) {
         my $thread = @{@info{engine}}{$pid};
         my $program = @$thread[0];
         my $command = $$program{stack};
         @info{program} = @$thread[0];

         my $sc = $$program{calls};
         for(my $i=0;$#$command >= 0 && $$program{calls} - $sc <= 100;$i++) {
            my $cmd = @$command[0];


            #
            # if any command envoke mushrun(), it becomes difficult to ensure
            # the execution order. The way around this is to hide the current
            # stack and add back commands added by mushrun to the original
            # stack. This could be avoided if each command delt with the
            # stack better. For ease of coding, i choose to fix it here
            # instead of a billion other places.
            #
            my $tmp = $$program{stack};                 # hide original stack
            $$program{stack} = [];                          # and add new one
            my $stack = $$program{stack};

            my $result = spin_run(\%last,$program,$cmd,$command);   # run cmd

            shift(@$command) if($result ne "RUNNING");

            my $stack = $$program{stack};            # copy back new commands
            while($#$stack >= 0) {
               unshift(@$command,pop(@$stack));
            }
            $$program{stack} = $tmp;                  # unhide original stack

            next if $result eq "RUNNING";            # command still running,
                                                        # don't remove it and 
                                                        # move to next thread

            $$program{calls}++;
            $count++;

                                                # stop at 7 milliseconds
            if(Time::HiRes::gettimeofday() - $start > .7) {
                printf("Time slice ran long, exiting correctly\n");
                ualarm(0);
               return;
            }
         }
         if($#$command == -1) { # program is done 
            my $prog = shift(@$thread);
            if($$prog{hint} eq "WEBSOCKET") {
               my $msg = join("",@{@$prog{output}});
               $prog->{sock}->send_utf8( $msg);
            } elsif($$prog{hint} eq "WEB") {
               if(defined $$prog{output}) {
                  http_reply($$prog{sock},join("",@{@$prog{output}}));
               } else {
                  http_reply($$prog{sock},"No data returned");
               }
            }
            delete @{@info{engine}}{$pid};
#            printf("# $pid Total calls: %s\n",$$prog{calls});
         }
      }
   };
#   ualarm(0);                                                 # cancel alarm
#   printf("Count: $count\n");

   if($@ =~ /alaerm/i) {
      printf("Time slice timed out (%2f w/%s cmd) $@\n",
         Time::HiRes::gettimeofday() - $start,$count);
      if(defined @last{user} && defined @{@last{user}}{var}) {
         my $var = @{@last{user}}{var};
         printf("   #%s: %s (%s,%s,%s,%s,%s,%s,%s,%s,%s)\n",
            @{@last{user}}{obj_id},@last{cmd},$$var{0},$$var{1},$$var{2},
            $$var{3},$$var{4},$$var{5},$$var{6},$$var{7},$$var{8});
      } else {
         printf("   #%s: %s\n",@{@last{user}}{obj_id},@{@last{cmd}}{cmd});
      }
   } elsif($@) {                               # oops., you sunk my battle ship
      my_rollback($db);

      my $msg = sprintf("%s CRASHed the server with: %s",name($user),
          @{@last{cmd}}{cmd});
      delete @info{engine};
      necho(self => $user,
            prog => prog($user,$user),
            source => [ "%s", $msg ]
           );
   }
}

#
# run_internal
#    Handle all switches and call the internal mush command
#
sub run_internal
{
   my ($hash,$cmd,$command,$prog,$arg,$type) = @_;
   my %switch;

   $$prog{cmd} = $command;
   while($arg =~ /^\s*\/([^ =]+)( |$)/) {                  # find switches
      @switch{lc($1)} = 1;
      $arg = $';
   }

#   if($type) {
#      printf("RUN: '%s%s'\n",$cmd,$arg);
#   } else {
#      printf("RUN: '%s %s'\n",$cmd,$arg);
#   }
#   printf("RUN(%s->%s): '%s%s'\n",@{$$prog{created_by}}{obj_id},@{$$command{runas}}{obj_id},$cmd,$arg);

 
   return &{@{$$hash{$cmd}}{fun}}($$command{runas},$prog,$arg,\%switch);
}

sub spin_run
{
   my ($last,$prog,$command,$foo) = @_;
   my $self = $$command{runas};
   my ($cmd,$hash,$arg,%switch);
   ($$last{user},$$last{enactor},$$last{cmd}) = ($self,$self,$command);
   $$prog{cmd_last} = $command;

# find command set to use
   if($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET") {
      if(defined $$prog{from} && $$prog{from} eq "ATTR") {
         $hash = \%command;
      } else {
         $hash = \%switch;                                      # no commands
      }
   } elsif($$prog{hint} eq "INTERNAL" || $$prog{hint} eq "WEB") {
      $hash = \%command;
#      delete @$prog{hint};
   } elsif(!loggedin($self) && hasflag($self,"PLAYER")) { 
      $hash = \%offline;                                     # offline users
   } elsif(defined $$self{site_restriction} && $$self{site_restriction} == 69) {
      $hash = \%honey;                                   # honeypotted users
   } else {
      $hash = \%command;                                    # connected users
   }

   if($$command{cmd} =~ /^\s*([^ \/]+)(\s*)/) {         # split cmd from args
      ($cmd,$arg) = (lc($1),$'); 
   } else {
      return;                                                 # only spaces
   }
   if(defined $$hash{$cmd}) {                                  # internal cmd
      return run_internal($hash,$cmd,$command,$prog,$arg);
  } elsif(defined $$hash{substr($cmd,0,1)} &&
     (defined $$hash{substr($cmd,0,1)}{nsp} ||
      substr($cmd,1,1) eq " " ||
      length($cmd) == 1
     )) {
      run_internal($hash,substr($cmd,0,1),
                   $command,
                   $prog,
                   substr(trim($$command{cmd}),1),
                   \%switch,
                   1
                  );
   } elsif(locate_exit($$command{cmd})) {            # handle exit as command
      return &{@{$$hash{"go"}}{fun}}($$command{runas},$prog,$$command{cmd});
   } elsif(mush_command($self,$prog,$$command{runas},$$command{cmd})) {
      return 1;                                   # mush_command runs command
   } else {
      my $match;

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

      if($match ne undef) {                                     # found match
         return run_internal($hash,$match,$command,$prog,$arg);
      } else {                                                     # no match
         necho(self   => $self,
               prog   => $prog,
               source => [ "Huh? (Type \"help\" for help.)" ]
              );
      }
   }
   return 1;
}



sub spin_done
{
    die("alarm");
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
    my ($prog,$pending) = @_;

    my $cmd = $$prog{cmd_last};
    $$cmd{pending} = $pending;
    $$cmd{still_running} = 1;

    unshift(@{$$prog{stack}},$cmd);
}
