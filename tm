#!/usr/bin/perl
#
#     o                                                   8      
#     8                                                   8      
#    o8P .oPYo. .oPYo. odYo. o    o ooYoYo. o    o .oPYo. 8oPYo. 
#     8  8oooo8 8oooo8 8' `8 8    8 8' 8  8 8    8 Yb..   8    8 
#     8  8.     8.     8   8 8    8 8  8  8 8    8   'Yb. 8    8 
#     8  `Yooo' `Yooo' 8   8 `YooP8 8  8  8 `YooP' `YooP' 8    8 
#                                 8
#                            'oooP'
#
#                A TinyMUSH like server written in perl*^
#
#
# * = No Frogs were harmed in the creation of this project.
# ^ = Do not attempt to compile with gcc or any other C compiler. 
#
use strict;
use IO::Select;
use IO::Socket;
use File::Basename;

#
#    Certain variables can not be re-loaded or the MUSH will forget about
# connected users, httpd, or websocket connections. To combat this,
# the code assumed that it would never reload the tm script, which
# contained the required variables. Starting with the single file
# version of TeenyMUSH, only those lines that don't contain a '#!#' will
# be reloaded. If a line does contain a '#!#', it will be replaced with
# an empty line during eval()ating as to preserve line number ordering.
#
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

# check to see if the URI::Escape module loads
eval {                                                                       
   require URI::Escape;                                                      
   import URI::Escape;                                               
};                                                                 
if($@) {                                                           
   printf("WARNING: Missing URI::Escape module, HTTPD disabled\n");
   @info{"conf.httpd"} = -1                                           
}
                                                                                
# check to see if the DBI module loads
eval {                                                             
   require DBI;                                                           
   import DBI;                                                       
};                                                                         
if($@) {                                                           
   printf("WARNING: Missing DBI module, MYSQLDB disabled\n");      
   @info{"conf.mysqldb"} = -1;                                     
}
                                                                                
# check to see if the Net::WebSocket::Server package loads
eval {                                                             
   # See https://metacpan.org/pod/Net::WebSocket::Server           
   require Net::WebSocket::Server;                                        
   import Net::WebSocket::Server;                                    
};
if($@) {                                                           
   printf("WARNING: Missing Net::WebSocket::Server module, WEBSOCKET disabled\n");
   @info{"conf.websocket"} = -1;                                                
}

#
# mysqldb
#    Return 0/1 if the MUSH is using mysql
#
sub mysqldb                                                                     
{                                                                               
   if(@info{"conf.mysqldb"} == 1 && @info{"conf.memorydb"} == 1) {              
      die("Only conf.mysqldb or conf.memorydb may be defined as 1");            
   } elsif(@info{"conf.mysqldb"} == 1) {                                        
      return 1;                                                                 
   } else {                                                                     
      return 0;                                                                 
   }                                                                            
}                                                                               
                                                                                
#
# memorydb 
#    Return 0/1 if the MUSH is using a memory based database . Default to 
#    memory db if neither is specified.
#
sub memorydb                                                                    
{                                                                               
   if(@info{"conf.mysqldb"} == 1  && @info{"conf.memorydb"} == 1) {             
      die("Only conf.mysqldb or conf.memorydb may be defined as 1");            
   } elsif(@info{"conf.mysqldb"} == 0  && @info{"conf.memorydb"} == 0) {
      return 1;
   } elsif(@info{"conf.memorydb"} == 1) {                                       
      return 1;                                                                 
   } else {                                                                     
      return 0;                                                                 
   }                                                                            
} 

#
# is_single
#    Return if TeenyMUSH is running as a single file or multiple
#    files. Currently we check to see if the initial script is
#    named teenymush.pl or not. Maybe the load_all_code function
#    could check to see if multiple files are loaded or not?
#
sub is_single
{
   return (basename(lc($0)) eq "teenymush.pl") ? 1 : 0;
}

#
# getfile
#    Load a file into memory and return the contents of that file.
#    Depending upon the extention, files are loaded from different
#    folders.
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
      # this preserves line numbers/file names  when stack traces are created
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
         printf("\n\nload_code fatal: '%s'\n",$@);
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
#    file has changed and reload it if it has.
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
         $file !~ /(backup|test)/) {
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

#
# read_config
#    Read the configuration file for TeenyMUSH. If an option is set to
#    -1, then don't reload that option. -1 Options are considered disabled
#    because of missing modules.
#
sub read_config
{
   my $flag = shift;
   my ($count,$fn)=(0,undef);

   if($0 =~ /\.([^\.]+)$/ && -e "$1.dat.dev") {
      $fn = "$1.dat.dev";
   } elsif($0 =~ /\.([^\.]+)$/ && -e "$1.dat") {
      $fn = "$1.dat";
   } elsif(-e "tm_conf.dat.dev") {
      $fn = "tm_conf.dat.dev";
   } else {
      $fn = "tm_conf.dat";
   }

   return if(!-e $fn);

   printf("Reading Config: $fn\n") if $flag;
   for my $line (split(/\n/,getfile($fn))) {
      $line =~ s/\r|\n//g;
      if($line =~/^\s*#/ || $line =~ /^\s*$/) {
         # comment or blank line, ignore
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*#(\d+)\s*$/) {
         @info{$1} = $2 if @info{$1} != -1
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*(.*?)\s*$/) {
         @info{$1} = $2 if @info{$1} != -1
      } else {
         printf("Invalid data in $fn:\n") if($count == 0);
         printf("    '%s'\n",$line);
         $count++;
      }
   }

   # i'd rather this be in read_attr_conf() but the database needs to be
   # read before we can pull attributes out of it.
   @info{"conf.mudname"} = "TeenyMUSH" if @info{"conf.mudname"} eq undef;
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
#    Prompt the user for database credentials, if needed.
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
  
   open($file,">> tm_config.dat") ||                # write to tm_config.dat
     die("Could not append to tm_config.dat");

   for my $key (keys %save) {                                   # save data
      printf($file "%s=%s\n",$key,@save{$key});
   }
   close($file);                                                     # done
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

#
# load_db_backup
#    A tm_backup.sql file was found, so mysql will be invoke to reload
#    the database from thsi file.
#
sub load_db_backup
{
   my $result;

   return if memorydb;
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
   if(!rename("tm_backup.sql","tm_backup.sql.loaded")) {
      printf("WARNING: Unable to rename tm_backup.sql, backup will be " .
             "reloaded upon next run unless the file is renamed/deleted.");
   }
}

$SIG{HUP} = sub {
  my $files = load_all_code(0,@info{filter});
  delete @info{engine};
  printf("HUP signal caught, reloading: %s\n",$files ? $files : "none");
};

$SIG{'INT'} = sub {  if(memorydb) {
                        printf("**** Program Exiting ******\n");
                        cmd_dump(obj(0),{},"CRASH");
                        @info{crash_dump_complete} = 1;
                        printf("**** Dump Complete Exiting ******\n");
                     }
                     exit(1);
                  };

@info{version} = "TeenyMUSH 0.9";
@info{filter} = "#!#";                                        #!# ALWAYS_LOAD

read_config(1);                                               #!# load once
get_credentials();

if(mysqldb) {
   load_code_in_file("tm_mysql.pl",1);
} else {
   load_code_in_file("tm_compat.pl",1);
}
load_all_code(1);                                      # initial load of code


load_new_db();                                        # optional new db load
load_db_backup();

initialize_functions();
initialize_commands();
server_start();                                          #!# start only once
