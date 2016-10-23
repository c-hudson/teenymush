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
   if(hasflag($user,"WIZARD") || hasflag($user,"GOD")) {
      return 10;
   } else {
      return 5;
   }
}

#
# mushrun
#    Add the command to the que of what to run. The command will be run
#    later.
#
sub mushrun
{
   my ($hash,$cmd,@wildcard) = @_;
   my $prog;

   if(defined $$hash{child}) {                        # add as child process
      $prog = $$hash{child};
      delete @$hash{child};
   } else {
      $prog = {                                      # add as parent process
         stack => [ ],
         enactor => $user,
         user => $hash,
         var => {},
         priority => priority()
      };

      @info{engine} = {} if not defined @info{engine}; # add to all programs
      @{@info{engine}}{++@info{pid}} = [ $prog ];
   };

    # copy over command(s)
    my $stack=$$prog{stack};
    if(defined $$hash{source} && $$hash{source} == 1) {
       unshift(@$stack,{ cmd => $cmd });
    } else {
       for my $i ( bannana_split($cmd,';',1) ) {
          my $stack=$$prog{stack};
          push(@$stack,{ cmd => $i });
       }
    }
    delete @$hash{source};

    for my $i (0 .. 9) {                              # copy over %0 .. %9
       if(defined @wildcard[$i]) {
          @{$$prog{var}}{$i} = @wildcard[$i];
       } else {
          delete @{$$prog{var}}{$i};
       }
    }
}

#
# spin
#    Run one command from each program that is running
#
sub spin
{
   my (%last);

   $SIG{ALRM} = \&spin_done;

   my $start = Time::HiRes::gettimeofday();

#   eval {
#      ualarm(800_000);                                # die at 8 milliseconds

      for my $pid (keys %{@info{engine}}) {
         my $thread = @{@info{engine}}{$pid};

         if($#$thread == -1) {                         # this program is done
            delete @{@info{engine}}{$pid};
         } else {
            my $program = @$thread[0];
         
            my $command = $$program{stack};

            if($#$command == -1) {                      # this thread is done
               shift(@$thread);
            } else {
               for(my $i=0;$#$command >= 0 && $i <= $$program{priority};$i++) {
                  my $cmd = shift(@$command);
                  spin_run(\%last,$program,$cmd);

                  # let the program decide if it is done (i.e. a loop)
                  if(defined $$program{still_running}) {
#                     echo($user,"## !DONE ##");
                     unshift(@$command,$cmd);
                     delete @$program{still_running};
                  } else {
#                     echo($user,"## DONE ##");
                  }
                                                      # stop at 4 milliseconds
                  if(Time::HiRes::gettimeofday() - $start > 0.4) {
                     printf("Time slice ran long, exiting correctly\n");
                     ualarm(0);
                     return;
                  }
               }
            }
         }
      }
#      ualarm(0);                                              # cancel alarm
#   };

   if($@) {
      printf("Time slice timed out (%2f) $@\n",Time::HiRes::gettimeofday() - 
         $start);
      if(defined @last{user} && defined @{@last{user}}{var}) {
         my $var = @{@last{user}}{var};
         printf("   #%s: %s (%s,%s,%s,%s,%s,%s,%s,%s,%s)\n",
            @{@last{user}}{obj_id},@last{cmd},$$var{0},$$var{1},$$var{2},
            $$var{3},$$var{4},$$var{5},$$var{6},$$var{7},$$var{8});
      } else {
         printf("   #%s: %s\n",@{@last{user}}{obj_id},@last{cmd});
      }
   }
}

#
# spin_run
#    A mush command has been found
#
sub spin_run
{
   my ($last,$prog,$cmd) = @_;

   my ($tmp_user,$tmp_enactor) = ($user,$enactor);
   ($user,$enactor) = ($$prog{user},$$prog{enactor});
   ($$last{user},$$last{enactor},$$last{cmd}) = ($user,$enactor,$cmd);
   $$user{cmd_data} = $cmd;

   if($$cmd{cmd} =~ /^\s*([^ ]+)(\s*)/) {
      my ($cmd_name,$arg) = lookup_command(\%command,$1,"$2$'",1);

      &{@{@command{$cmd_name}}{fun}}($arg,$prog);
   }
   ($user,$enactor) = ($tmp_user,$tmp_enactor);
}

sub spin_done
{
    die("alarm");
}
