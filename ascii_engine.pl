#!/usr/bin/perl
#
# ascii_engine
#    This file contains any functions required to handle the scheduling of
#    running of mush commands. The hope is to balance the need for socket
#    IO verses the need to run mush commands.
#



use Time::HiRes "ualarm";
#
# mushrun
#    Add the command to the que of what to run. The command will be run
#    later.
#
sub mushrun
{
    my ($hash,$cmd,@wildcard) = @_;
    delete @info{engine};

    my $prog = {
       stack => [ mush_split($cmd,';') ],
       enactor => $enactor,
       user => $user,
       obj => $hash,
       var => {}
    };


    if(hasflag($user,"WIZARD") || hasflag($user,"GOD")) {
       $$prog{priority} = 10;
    } else {
       $$prog{priority} = 5;
    }
 
    for my $i (0 .. $#wildcard) {
       @{$$prog{var}}{$i+1} = @wildcard[$i];
    }

#    for my $i (0 .. $#{$$prog{stack}}) {
#       echo($user,"   %s",@{$$prog{stack}}[$i]);
#    }

    @info{engine} = {} if not defined @info{engine};
    @{@info{engine}}{++@info{pid}} = [ $prog ];
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

   eval {
      ualarm(800_000);                                # die at 8 milliseconds

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
                  my $cmd  = shift(@$command);
                  spin_run(\%last,$program,$cmd);
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
      ualarm(0);                                              # cancel alarm
   };

   if($@) {
      printf("Time slice timed out (%2f)\n",Time::HiRes::gettimeofday() - 
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

   if($cmd =~ /^\s*([^ ]+)(\s*)/) {
      my ($cmd_name,$arg) = lookup_command(\%command,$1,"$2$'",1);

      &{@{@command{$cmd_name}}{fun}}($arg,$prog);
   }
   ($user,$enactor) = ($tmp_user,$tmp_enactor);
}

sub spin_done
{
    die("alarm");
}
