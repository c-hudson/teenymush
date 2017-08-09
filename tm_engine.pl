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
   my ($self,$data,$cmd) = @_;
   my ($match,$questions,@where)= (0);
#   printf("MUSH_COMMAND: '%s'\n",print_var($data));

   (@where[0],@where[1]) = (loc($user),$$user{obj_id});
   if(defined @info{master_room}) {
      $questions = "?,?,?";
      push(@where,@info{master_room});
   } else {
      $questions = "?,?";
   }
#   printf("mush_command: '%s' '%s' '%s'\n%s\n",$self,$data,$cmd,code("long"));

   # look for any attributes in the same room as the player
   for my $hash (@{sql("select obj.*, " .
                       "       substr(atr_value,2,instr(atr_value,':')-2) cmd,".
                       "       substr(atr_value,instr(atr_value,':')+1) txt,".
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
      $$hash{txt} =~ s/\r\s*|\n\s*//g;
      if($cmd =~ /^$$hash{cmd}$/) {
         mushrun($self,$hash,$$hash{txt},0,$1,$2,$3,$4,$5,$6,$7,$8,$9);
      } else {
         mushrun($self,$hash,$$hash{txt},0);
      }
      $match=1;                                   # signal mush command found
   }
   return $match;
}


sub priority
{
   my $obj = shift;

   $obj = owner($obj) if(!hasflag($obj,"PLAYER"));

   return (perm($obj,"HIGH_PRORITY") ? 50 : 1);
}

#
# mushrun
#    Add the command to the que of what to run. The command will be run
#    later.
#
# $source (1 = direct user input, 0 = indirect user input)
sub mushrun
{
   my ($self,$obj,$cmd,$source,@wildcard) = @_;
   my ($prog,$txt);

   if(!defined $$user{inattr}) {
       if($cmd =~ /^\s*$/) {
          return;
       } elsif($cmd =~ /^\s*{(.*)}\s*$/s) {
          $cmd = $1;
       }
   }
      
   if(defined $$self{inattr}) {                               # handle inattr
      my $hash = $$self{inattr};
      my $stack = $$hash{content};
      if($cmd =~ /^\s*$/) {
         $txt = "$$hash{attr} $$hash{object}=" . join("\r\n",@$stack);
         delete @$self{inattr};
         cmd_set2($self,{},$txt);
         return;
      } else {
         my $stack = @{$$self{inattr}}{content};
         push(@$stack,$cmd);
         return;
      }
   } elsif(defined $$self{child}) {                   # add as child process
      $prog = $$self{child};
   } else {
      $prog = {                                      # add as parent process
         stack => [ ],
         enactor => $self,                                         # remove?
         user => $self,                                            # remove?
         created_by => $self,
         obj => $obj,
         var => {},
         priority => priority($self),
         calls => 0
      };

      @info{engine} = {} if not defined @info{engine}; # add to all programs
      @{@info{engine}}{++@info{pid}} = [ $prog ];
   };

    # copy over command(s)
    my $stack=$$prog{stack};
    if($source) {
       unshift(@$stack,{ cmd => $cmd, source => 1 });
    } else {
       for my $i ( balanced_split($cmd,';',3,1) ) {
          push(@$stack,{ cmd => $i, source => 0 });
       }
    }

    if(!defined $$self{child}) {
       set_digit_variables($self,$prog,@wildcard);       # copy over %0 .. %9
    }
    delete @$self{child};
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
            @{$$prog{var}}{$i} = evaluate($self,$prog,@var[$i]);
         } else {
            @{$$prog{var}}{$i} = @var[$i];
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
#      ualarm(800_000);                                # die at 8 milliseconds
#      ualarm(1_200_000);                                # die at 8 milliseconds

      for my $pid (keys %{@info{engine}}) {
         my $thread = @{@info{engine}}{$pid};

         if($#$thread == -1) {                         # this program is done
            delete @{@info{engine}}{$pid};
         } else {
            my $program = @$thread[0];
            my $command = $$program{stack};
            @info{program} = @$thread[0];

            if($#$command == -1) {                      # this thread is done
               my $prog = shift(@$thread);
#               printf("# Total calls: %s - %s\n",$$prog{calls},$$user{source});
            } else {
               for(my $i=0;$#$command >= 0 && $i <= $$program{priority};$i++) {
                  my $cmd = shift(@$command);
#                  printf("CMD: '%s'\n",join(',',@$cmd)) if(ref($cmd) eq "ARRAY");
                  $$user{cmd_data} = $cmd;
                  delete @$cmd{still_running};
                  spin_run(\%last,$program,$cmd,$command);
                  $count++;

                  #
                  # command is still running, probably a sleep? Skip to the
                  # next program as it won't finish any quicker by running
                  # it again.
                  #
                  next if($cmd eq @$command[0]);
                  $$program{calls}++;
                                                      # stop at 4 milliseconds
                  if(Time::HiRes::gettimeofday() - $start > .5) {
#                     printf("Time slice ran long, exiting correctly\n");
#                     ualarm(0);
                     return;
                  }
               }
            }
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
         printf("# %s CRASHED the server with: %s\n%s",name($user),
                @{@last{cmd}}{cmd},$@);
         printf("LastSQL: '%s'\n",@info{sql_last});
         printf("         '%s'\n",@info{sql_last_args});
         rollback($db);

         my $msg = sprintf("%s CRASHed the server with: %s",name($user),
             @{@last{cmd}}{cmd});
         necho(self => $user,
               prog => {},
               source => [ "%s", $msg ]
              );
         if($msg ne $$user{crash}) {
            necho(self => $user,
                  prog => {},
                  room => [ "%s", $msg ]
                 );
         }
      }
}

#
# spin_run
#    A mush command has been found
#
sub spin_run
{
   my ($last,$prog,$cmd,$command) = @_;

   my ($tmp_user,$tmp_enactor,$switch) = ($user,$enactor,{});
   ($user,$enactor) = ($$prog{user},$$prog{enactor});
   ($$last{user},$$last{enactor},$$last{cmd}) = ($user,$enactor,$cmd);
   $$prog{cmd_last} = $cmd;

   $$cmd{cmd} =~ s/^\s*{//;

#   if(!defined $$user{internal}) {
      $$user{internal} = {                                   # internal data
         cmd => $cmd,                                       # to pass around
         command => $command,
         user => $user,
         enactor => $enactor,
         prog => $prog
      };
#   }

   if($$cmd{cmd} =~ /^\s*([^ ]+)(\s*)/) {
      my ($cmd_name,$arg)=lookup_command($$prog{obj},\%command,$1,"$2$'",1);

      if(hasflag($user,"VERBOSE")) {
         if($arg eq undef) {
            necho(self => $user,
                  prog => $prog,
                  target => [ owner($user), "> %s",$cmd_name ]
                 );
         } else {
            necho(self => $user,
                  prog => $prog,
                  target => [ owner($user), "> %s",$cmd_name,$arg ]
                 );
         }
      }

      while($arg =~ /^\s*\/([^ =]+)( |$)/) {
         $$switch{lc($1)} = 1;
         $arg = $';
      }

      if($cmd_name ne "@@") {
         $$user{cmd_data} = $cmd;
         &{@{@command{$cmd_name}}{fun}}($$prog{obj},$prog,$arg,$switch);
      }
   }
   ($user,$enactor) = ($tmp_user,$tmp_enactor);
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
    my $prog = shift;

    my $cmd;

    if($#_ == 0) {
       $cmd = shift;
    } else {
       $cmd = $$prog{cmd_last};
    }

    push(@{$$prog{stack}},$cmd);
}
