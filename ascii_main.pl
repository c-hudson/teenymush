#!/usr/bin/perl

# start the server.
#    This should be only called once.
#    It should only contain code that will never need to be reloaded.
#    Do not put anything in here?
#

$SIG{HUP} = sub {
  my $files = load_all_code();

  printf("HUP signal caught, reloading: %s\n",$files ? $files : "none");
};

#
# close the loop on connections that have start times but not end times
#
sql($db,"INSERT INTO connect (obj_id, " .
    "                     con_hostname, " .
    "                     con_timestamp, " .
    "                     con_type, " .
    "                     con_socket) " .
    "  SELECT obj_id, " .
    "         con_hostname, " .
    "         now(), " .
    "         2, " .
    "         con_socket " .
    "    FROM connect a " .
    "   WHERE     con_type = 1 " .
    "         AND NOT EXISTS " .
    "                (SELECT 1 " .
    "                   FROM connect b " .
    "                  WHERE b.con_socket = a.con_socket AND con_type = 2)");
commit($db);


server_start(4096);
