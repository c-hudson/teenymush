#!/usr/bin/perl

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
       enactor => $user,
       obj => $hash,
       var => {},
    };

    for my $i (0 .. $#wildcard) {
       @{$$prog{var}}{$i+1} = @wildcard[$i];
    }

    for my $i (0 .. $#{$$prog{stack}}) {
       echo($user,"   %s",@{$$prog{stack}}[$i]);
    }

    @info{engine} = {} if not defined @info{engine};
    @{@info{engine}}{++@info{pid}} = [ $prog ];
}

#
# spin
#    Run one command from each program that is running
#
sub spin
{


   $SIG{ALRM} = \&spin_done;

   my $start = Time::HiRes::gettimeofday();

   eval {
      ualarm(400_000);                                # die at 4 milliseconds

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
               my $cmd  = shift(@$command);
               spin_run($program,$cmd);
                                                      # stop at 2 milliseconds
               if(Time::HiRes::gettimeofday() - $start > 0.2) {
                  printf("Time slice ran long, exiting correctly\n");
                  last;
               }
            }
         }
      }
      ualarm(0);                                              # cancel alarm
   };

   if($@) {
      printf("Time slice timed out (%2f)\n",Time::HiRes::gettimeofday() - 
         $start);
   }
}

#
# spin_run
#    A mush command has been found
#
sub spin_run
{
   my ($prog,$cmd) = @_;

   my $tmp_user = $user;
   my $tmp_enactor = $enactor;

   if($cmd =~ /^\s*([^ ]+)(\s*)/) {
      my ($cmd_name,$arg) = lookup_command(\%command,$1,"$2$'",1);

      &{@{@command{$cmd_name}}{fun}}($arg,$prog);
   }

   $user = $tmp_user;
   $enactor = $tmp_enactor;
}

sub spin_done
{
    die("alarm");
}
