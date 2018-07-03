#!/usr/bin/perl

# start the server.
#    This should be only called once.
#    It should only contain code that will never need to be reloaded.
#    Do not put anything in here?
#

$SIG{HUP} = sub {
  my $files = load_all_code();
  delete @info{engine};
  printf("HUP signal caught, reloading: %s\n",$files ? $files : "none");
};

#
# close the loop on connections that have start times but not end times
#
sql($db,"delete from socket");
sql($db,"update socket_history " .
        "   set skh_end_time = skh_start_time " .
        " where skh_end_time is null");
my_commit($db);

for (@Addon::EXPORT) {
  print "$_\n";
}

# server_start();
