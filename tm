#!/usr/bin/perl

use strict;
use IO::Select;
use IO::Socket;
use File::Basename;


# Any variables that need to survive a reload of code should be placed
# here. Variables that need to be accessed in other files may need to be
# placed here as well.

my (%command,                  #!# commands for after player has connected
    %fun,                      #!# functions for players to use
    %offline,                  #!# commands for before player has connected
    %connected,                #!# connected socket information
    %connected_user,           #!# users connected
    %honey,                    #!# honeypot cmds
    $readable,                 #!# sockets to wait for input on
    $listener,                 #!# port details
    $web,                      #!# web port details
    $ws,                       #!# websocket server object
    $websock,                  #!# websocket listener
    %http,                     #!# http socket list
    %code,                     #!# loaded perl files w/mod times
    $db,                       #!# main database connection
    $log,                      #!# database connection for logs
    %info,                     #!# misc info storage
    $user,                     #!# current user details
    $enactor,                  #!# object who initated the action
    %cache,                    #!# cached data from sql database
    %c,                        #!#

    #----[memory database structures]---------------------------------------#
    %help,                     #!# online-help
    @db,                       #!# whole database
    @delta,                    #!# db changes storage
    %player,                   #!# player list for quick lookup
    @free,                     #!# free objects list
    %deleted,                  #!# deleted objects during backup
   );                          #!#

sub mysqldb
{
   if(@info{"conf.mysqldb"} && @info{"conf.memorydb"}) {
      die("Only conf.mysqldb or conf.memorydb may be defined as 1");
   } elsif(@info{"conf.mysqldb"}) {
      return 1;
   } else {
      return 0;
   }
}

sub memorydb
{
   if(@info{"conf.mysqldb"} && @info{"conf.memorydb"}) {
      die("Only conf.mysqldb or conf.memorydb may be defined as 1");
   } elsif(@info{"conf.memorydb"}) {
      return 1;
   } else {
      return 0;
   }
}

sub is_single
{
   return (basename(lc($0)) eq "teenymush.pl") ? 1 : 0;
}

#
# getfile
#    Load a file into memory and return the contents of that file
#
sub getfile
{
   my ($fn,$code,$filter) = @_;
   my($file, $out);

   if($fn =~ /^[^\\|\/]+\.(pl|dat|dev)$/i) {
      open($file,$fn) || return undef;                         # open pl file
   } elsif($fn =~ /^[^\\|\/]+$/i) {
      open($file,"txt\/$fn") || return undef;                 # open txt file
   } else {
      return undef;                                 # don't open file because
   }                                          # it doesn't follow conventions

   @{$$code{$fn}}{lines} = 0 if(ref($code) eq "HASH");
   while(<$file>) {                                           # read all data
      s/\r//g;
      @{$$code{$fn}}{lines}++ if(ref($code) eq "HASH");
      if($filter eq undef || $_ !~ /$filter/ || $_ =~ /$filter ALWAYS_LOAD/) {
         $out .= $_;
      } else {
         $out .= "#!#\n";                           # preserve line numbers?
      }
   }
   close($file); 
   $out =~ s/\r//g;
   $out =~ s/\n/\r\n/g;

   return $out;                                                 # return data
}

#
# load_code_in_file
#    Load perl code from a file and run it.
#
sub load_code_in_file
{
   my ($file,$verbose,$filter) = @_;

   if(is_single && basename(lc($0)) ne lc($file)) {
      # skip
   } elsif(!-e $file) {
      printf("Fatal: Could not find '%s' to load.\n",$file);
   } else {
      my $data = qq[#line 1 "$file"\n] . getfile($file,\%code,$filter);

      @{$code{$file}}{size} = length($data);
      @{$code{$file}}{mod}  = (stat($file))[9];

#      if($verbose) {                                  # show whats happening
         $| = 1;
         printf("Loading: %-30s",$file);
#      }

      $@ = '';
      eval($data);                                                # run code
 
      if($@) {                                         # report any failures
         if($file eq "tm_websock.pl") {
            @info{"conf.websock"} = 0;
            printf("    [ FAILED/websocket disabled ]\n");
            return 1;
         } elsif($file eq "tm_mysql.pl") {
            @info{"conf.memorydb"} = 1;
            @info{"conf.mysqldb"} = 0;
            printf("    [ FAILED/mysql disabled ]\n");
            return 1;
         } elsif($file eq "tm_httpd.pl") {
            @info{"conf.httpd"} = 0;
            printf("    [ FAILED/httpd disabled ]\n");
         } else {
            printf("\n\nload_code fatal: '%s'\n",$@);
         }
         return 0;
      } else {
         printf("\n");
      }
   }
   return 1;                                           # everything was good
}

#
# load_all_code
#    Check the current directory for any perl files to load. See if the
#    file has changed and reload it if it has. Exclude tm_main.pl
#    which should never be reloaded.
#
sub load_all_code
{
   my ($verbose,$filter) = @_;
   my ($dir, @file);

   opendir($dir,".") ||
      return "Could not open current directory for reading";

   for my $file (readdir($dir))  {
      if(($file =~ /^tm_.*.pl$/i || 
         (lc($file) eq "teenymush.pl" && $filter eq @info{filter})) &&
         $file !~ /(backup|test)/ && 
         $file !~ /^tm_(main).pl$/i) {
         my $current = (stat($file))[9];         # should be file be reloaded?
         if(!defined $code{$file} || 
            !defined  @{$code{$file}}{mod} ||
            @{$code{$file}}{mod} != $current) {
            @code{$file} = {} if not defined $code{$file};
            if(load_code_in_file($file,1,$filter)) {
               push(@file,$file);                  # show which files reloaded
               @{$code{$file}}{mod} = $current;
            } else {
               push(@file,"$file [err]");                  # show which failed
            }
         }
      }
   }
   closedir($dir);
   return join(', ',@file);                           # return succ/fail list
}

sub read_config
{
   my $flag = shift;
   my $count=0;
   my $fn = "tm_config.dat";

   # always use .dev version for easy setup of dev db.
   $fn .= ".dev" if(-e "$fn.dev");

   printf("Reading Config: $fn\n") if $flag;
   for my $line (split(/\n/,getfile($fn))) {
      $line =~ s/\r|\n//g;
      if($line =~/^\s*#/ || $line =~ /^\s*$/) {
         # comment or blank line, ignore
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*#(\d+)\s*$/) {
         @info{$1} = $2;
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*(.*?)\s*$/) {
         @info{$1} = $2;
      } else {
         printf("Invalid data in $fn:\n") if($count == 0);
         printf("    '%s'\n",$line);
         $count++;
      }
   }
}



#
# prompt
#    prompt the user for input
#
sub prompt
{
   my $txt = shift;
   my $result;

   $| = 1;                                        # set input to unbuffered

   while($result eq undef) {
      printf("%s ",$txt);                                     # show prompt
      $result = <STDIN>;                         # grab one line from stdin
      $result =~ s/^\s+|\s+$//g;
      $result =~ s/\n|\r//g;                 # strip leading spaces/returns
   }
   return $result;
}

#
# get_credentials
#    Get the database credentials if needed.
#
sub get_credentials
{
   my ($file,%save);

   return if memorydb;
   if($$db{user} =~ /^\s*$/) {
      $$db{user} = prompt("Enter database user: ");
      @save{user} = $$db{user};
   }
   if($$db{pass} =~ /^\s*$/) {
      $$db{pass} = prompt("Enter database password: ");
      @save{pass} = $$db{pass};
   }
   if($$db{database} =~ /^\s*$/) {
      $$db{database} = prompt("Enter database name: ");
      @save{database} = $$db{database};
   }
   if($$db{host} =~ /^\s*$/) {
      $$db{host} = prompt("Enter database host: ");
      @save{host} = $$db{host};
   }

   return if scalar keys %save == -1;
  
   open($file,">> tm_config.dat") ||
     die("Could not append to tm_config.dat");

   for my $key (keys %save) {
      printf($file "%s=%s\n",$key,@save{$key});
   }
   close($file);
}

#
# load_new_db
#    Check to see if there has been a database loaded, if not
#    prompt to load the default database
#
sub load_new_db
{
   my $result;

   return if(memorydb);
   return if(one_val("select count(*) value ".
                     "  from information_schema.tables  " .
                     " where table_name = 'object' " .
                     "   and table_schema = database()"
                    ) != 0);

   printf("##############################################################\n");
   printf("##                                                          ##\n");
   printf("##                  Empty database found                    ##\n");
   printf("##                                                          ##\n");
   printf("##############################################################\n");
   @info{no_db_found} = 1;

   printf("\nDatabase: %s@%s on %s\n\n",$$db{user},$$db{database},$$db{host});
   while($result ne "y" && $result ne "yes") {
       $result = prompt("No database found, load default database [yes/no]?");

       if($result eq "n" || $result eq "no") {
          return;
       }
   }
   printf("Default database creation log: tm_db_create.log");
   system("mysql -u $$db{user} -p$$db{pass} $$db{database} " .
          "< base_structure.sql >> tm_db_create.log");
   system("mysql -u $$db{user} -p$$db{pass} $$db{database} " .
          " < base_objects.sql >> tm_db_create.log");
   system("mysql -u $$db{user} -p$$db{pass} $$db{database} " .
          " < base_inserts.sql >> tm_db_create.log");
   delete @info{no_db_found};
}

sub load_db_backup
{
   my $result;

   return if(!defined @info{no_db_found} || arg("restore"));

   if(!-e "tm_backup.sql") {
      printf("\nLoading backup requires backup stored as tm_backup.sql\n\n");
      printf("tm_backup.sql file not found, aborting.\n");
      exit();
   }

   while($result ne "y" && $result ne "yes") {
       $result = prompt("Load database backup from tm_backup.sql [yes/no]? ");

       if($result eq "n" || $result eq "no") {
          exit();
          return;
       }
   }
   system("mysql -u $$db{user} -p$$db{pass} $$db{database} < " .
          "tm_backup.sql >> tm_db_load.log");
}

@info{version} = "TeenyMUSH 0.9";
read_config(1);                                               #!# load once
get_credentials();

@info{filter} = "#!#";                                        #!# ALWAYS_LOAD
if(mysqldb) {
   load_code_in_file("tm_mysql.pl",1);                     # only call of main
} else {
   load_code_in_file("tm_compat.pl",1);                     # only call of main
}
load_all_code(1);                                      # initial load of code


load_new_db();                                           # optional db load
load_db_backup();

load_code_in_file("tm_main.pl",1);                       # only call of main
initialize_functions();
initialize_commands();
server_start();                                          #!# start only once
