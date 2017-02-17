#!/usr/bin/perl
#
# ascii_engine
#    This file contains any functions required to handle the scheduling of
#    running of mush commands. The hope is to balance the need for socket
#    IO verses the need to run mush commands.
#


use Time::HiRes "ualarm";

sub mush_command
{
   my ($data,$cmd) = @_;
   my $match= 0;

   # look for any attributes in the same room as the player
   for my $hash (@{sql("select obj.obj_id, " .
                       "       substr(atr_value,2,instr(atr_value,':')-2) cmd,".
                       "       substr(atr_value,instr(atr_value,':')+1) txt,".
                       "       0 source " .
                       "  from object obj, attribute atr, content con " .
                       " where obj.obj_id = atr.obj_id " .
                       "   and obj.obj_id = con.obj_id " .
                       "   and ? like  " .
                "replace(substr(atr_value,1,instr(atr_value,':')-1),'*','%')" .
                       "   and con.con_source_id in ( ?, ? ) ",
                       "\$" . lc($cmd),
                       loc($user),
                       $$user{obj_id}
                      )
                }) {

      $$hash{cmd} =~ s/\*/\(.*\)/g;
      $$hash{txt} =~ s/\r\s*|\n\s*//g;
      if($cmd =~ /^$$hash{cmd}$/) {
         mushrun($hash,$$hash{txt},$1,$2,$3,$4,$5,$6,$7,$8,$9);
      } else {
         mushrun($hash,$$hash{txt});
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
sub mushrun
{
   my ($hash,$cmd,@wildcard) = @_;

   if(defined $$user{inattr}) {                               # handle inattr
      my $hash = $$user{inattr};
      my $stack = $$hash{content};
      if($cmd =~ /^\s*$/) {
         my $txt = "$$hash{attr} $$hash{object}=" . join("\r\n",@$stack);
         delete @$user{inattr};
         cmd_set2($txt);
         return;
      } else {
         my $stack = @{$$user{inattr}}{content};
         push(@$stack,$cmd);
         return;
      }
   } elsif(defined $$hash{child}) {                   # add as child process
      $prog = $$hash{child};
   } else {
      $prog = {                                      # add as parent process
         stack => [ ],
         enactor => $user,
         user => $hash,
         var => {},
         priority => priority($hash),
         calls => 0
      };

      @info{engine} = {} if not defined @info{engine}; # add to all programs
      @{@info{engine}}{++@info{pid}} = [ $prog ];
   };

    # copy over command(s)
    my $stack=$$prog{stack};
    if(defined $$hash{source} && $$hash{source} == 1) {
       unshift(@$stack,{ cmd => $cmd });
    } else {
       for my $i ( balanced_split($cmd,';',3) ) {
#       for my $i ( bannana_split($cmd,';',1) ) {
          my $stack = $$prog{stack};
          if(defined $$hash{child}) {                # child gets added to top
             unshift(@$stack,{ cmd => $i });
          } else {                               # all else goes on the bottom
             push(@$stack,{ cmd => $i });
          }
       }
    }

    if(!defined $$hash{child}) {
       for my $i (0 .. 9) {                              # copy over %0 .. %9
          if(defined @wildcard[$i]) {
             @{$$prog{var}}{$i} = @wildcard[$i];
          } else {
             @{$$prog{var}}{$i} = "";
          }
       }
    }
    delete @$hash{child};
    delete @$hash{source};
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
      ualarm(1_200_000);                                # die at 8 milliseconds

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
                     ualarm(0);
                     return;
                  }
               }
            }
         }
      }
   };
   ualarm(0);                                                 # cancel alarm
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
         echo($user,"%s",$msg);
         if($msg ne $$user{crash}) {
            echo_room($user,"%s",$msg);
            $$user{crash} = $msg;
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

   my ($tmp_user,$tmp_enactor) = ($user,$enactor);
   ($user,$enactor) = ($$prog{user},$$prog{enactor});
   ($$last{user},$$last{enactor},$$last{cmd}) = ($user,$enactor,$cmd);
   $$prog{cmd_last} = $cmd;

   $$cmd{cmd} =~ s/^\s*{//;

   if(!defined $$user{internal}) {
      $$user{internal} = {                                   # internal data
         cmd => $cmd,                                       # to pass around
         command => $command,
         user => $user,
         enactor => $enactor,
         prog => $prog
      };
   }

   if($$cmd{cmd} =~ /^\s*([^ ]+)(\s*)/) {
      my ($cmd_name,$arg) = lookup_command(\%command,$1,"$2$'",1);

      if(hasflag($user,"VERBOSE")) {
         if($arg eq undef) {
            echo(owner($user),"> %s",$cmd_name);
         } else {
            echo(owner($user),"> %s %s",$cmd_name,$arg);
         }
      }

      if($cmd_name ne "@@") {
         $$user{cmd_data} = $cmd;
         &{@{@command{$cmd_name}}{fun}}($arg,$prog);
      }
   }
   ($user,$enactor) = ($tmp_user,$tmp_enactor);
}

sub spin_done
{
    die("alarm");
}
