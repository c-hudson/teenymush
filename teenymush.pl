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
#                A TinyMUSH like server written in perl?*^
#                    [ Yep, impossible but true. ]
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
	#   require DBI;                                                           
	#   import DBI;                                                       
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
      if($filter eq undef || ($_ =~ /ALWAYS_LOAD/ || $_ !~ /$filter/)) {
         $out .= $_;
      } else {
         $out .= "#!#\n";                # preserve line numbers? ALWAYS_LOAD
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
      $data =~ s/\r\n/\n/g;

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
	 write_to_file("teenymush.reload_fatal.txt",$@);
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
   } elsif(-e "tm_config.dat.dev") {
      $fn = "tm_config.dat.dev";
   } else {
      $fn = "tm_config.dat";
   }

   if(!-e $fn) {
      @info{"conf.mudname"} = "TeenyMUSH" if @info{"conf.mudname"} eq undef;
      return;
   }

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

sub write_to_file
{
   my ($fn,$data,$flag) = @_;
   my $file;

   if($flag && -e $fn) {
      die("Source file $fn already exists, not over-writing");
   }
 
   printf("Writing out: %s\n",$fn);

   open($file,"> $fn") ||
      die("Could not open $fn for writing");
 
   if(ref($data) eq "ARRAY") {
      printf($file "%s",join("\n",@$data));
   } else {
      printf($file "%s",$data);
   }

   close($file);
}

sub simple_getfile
{
   my $fn = shift;
   my $file;

   open($file,$fn) || die("Unable to read file '$fn'");
 
   return join('',<$file>);
}

sub split_source_into_multiple
{
   my ($file,$buf,$name);

   open($file,$0) ||
      die("Could not open $0 for reading");

   while(<$file>) {
      if(/^#!\// && $. < 5) {
         $name = "tm";
      } elsif(/^#!\// && $name ne undef) {
         write_to_file($name,$buf,1) if($buf ne undef && $name ne undef);
         $name = undef;
         $buf = undef;
      } elsif($name eq undef && /^#\s+tm_(.*).pl\s*$/) {
         $name = "tm_$1\.pl";
      }
      $buf .= $_;
      
   }
   close($file);

   write_to_file($name,$buf,1) if($buf ne undef && $name ne undef);
}

sub combine_source_into_single
{
   my $out;

   $out .= simple_getfile("tm");
   $out .= simple_getfile("tm_compat.pl");
   $out .= simple_getfile("tm_commands.pl");
   $out .= simple_getfile("tm_cache.pl");
   $out .= simple_getfile("tm_ansi.pl");
   $out .= simple_getfile("tm_db.pl");
   $out .= simple_getfile("tm_engine.pl");
   $out .= simple_getfile("tm_find.pl");
   $out .= simple_getfile("tm_format.pl");
   $out .= simple_getfile("tm_functions.pl");
   $out .= simple_getfile("tm_httpd.pl");
   $out .= simple_getfile("tm_internal.pl");
   $out .= simple_getfile("tm_lock.pl");
   $out .= simple_getfile("tm_mysql.pl");
   $out .= simple_getfile("tm_sockets.pl");
   $out .= simple_getfile("tm_websock.pl");
   $out =~ s/\r\n/\n/g;

   write_to_file("teenymush.pl",$out,1);
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

sub arg
{
   my $txt = shift;

   for my $i (0 .. $#ARGV) {
      return 1 if(@ARGV[$i] eq $txt || @ARGV[$i] eq "--$txt")
   }
   return 0;
}

$SIG{HUP} = sub {
  my $files = load_all_code(0,@info{filter});
  delete @info{engine};
  printf("HUP signal caught, reloading: %s\n",$files ? $files : "none");
};

$SIG{'INT'} = sub {  if(memorydb && $#db > -1) {
                        printf("**** Program Exiting ******\n");
                        cmd_dump(obj(0),{},"CRASH");
                        @info{crash_dump_complete} = 1;
                        printf("**** Dump Complete Exiting ******\n");
                     }
                     exit(1);
                  };

if(arg("split")) {
   split_source_into_multiple();
   exit(0);
} elsif(arg("single")) {
   combine_source_into_single();
   exit(0);
}

@info{version} = "TeenyMUSH 0.9";
@info{filter} = "#!#";                                        #!# ALWAYS_LOAD

read_config(1);                                               #!# load once
get_credentials();

if(mysqldb) {                                        #!#
   load_code_in_file("tm_mysql.pl",1);               #!#
} else {                                             #!#
   load_code_in_file("tm_compat.pl",1);              #!#
}                                                    #!#
load_all_code(1);                                    #!# initial load of code


load_new_db();                                       #!# optional new db load
load_db_backup();                                    #!#

initialize_functions();                              #!#
initialize_commands();                               #!#
server_start();                                      #!# start only once

# #!/usr/bin/perl
#
# tm_compat.pl
#    Any code required for compatiblity when a file/module does not load.
#


sub my_commit   
{        
   return;
}

sub my_rollback
{        
   return;
}       
# #!/usr/bin/perl
#
# tm_commands.pl
#    All user commands should be stored here, except for those which are
#    not. Check tm_putitsomewherelese.pl if it isn't here.
#


use Text::Wrap;
# use Devel::Size qw(size total_size);
use Digest::SHA qw(sha1 sha1_hex);

#
# initialize_commands
#    Populate the HASH table of commands. This could be defined when %command
#    is defined but we'd loose the ability to change the variable on the fly,
#    or we'd have to have two lists.
#
sub initialize_commands
{
   delete @command{keys %command};
   delete @offline{keys %offline};
   delete @honey{keys %honey};

   @offline{connect}     = sub { return cmd_connect(@_);                    };
   @offline{who}         = sub { return cmd_who(@_);                        };
   @offline{create}      = sub { return cmd_pcreate(@_);                    };
   @offline{quit}        = sub { return cmd_quit(@_);                       };
   @offline{huh}         = sub { return cmd_offline_huh(@_);                };
   # ------------------------------------------------------------------------#
   @honey{who}           = sub { return honey_who(@_);                      };
   @honey{connect}       = sub { return honey_connect(@_);                  };
   @honey{quit}          = sub { return cmd_quit(@_);                       };
   @honey{honey_off}     = sub { return honey_off(@_);                      };
   @honey{huh}           = sub { return honey_huh(@_);                      };
   @honey{look}          = sub { return honey_look(@_);                     };
   @honey{go}            = sub { return honey_go(@_);                       };
   @honey{page}          = sub { return honey_page(@_);                     };
   @honey{help}          = sub { return honey_help(@_);                     };
   # ------------------------------------------------------------------------#
   @command{"\@perl"}  = { help => "Run a perl command",
                            fun  => sub { return &cmd_perl(@_); }           };
   @command{"\@honey"}  = { help => "Put a user into the HoneyPot",
                            fun  => sub { return &cmd_honey(@_); }          };
   @command{say}        = { help => "Sends a message to everyone in the room",
                            fun  => sub { return &cmd_say(@_); }            };
   @command{"\""}       = { help => @{@command{say}}{help},
                            fun  => sub { return &cmd_say(@_); },
                            nsp  => 1                                       };
   @command{"`"}        = { help => "Direct a message to a person",
                            fun  => sub { return &cmd_to(@_); },
                            nsp  => 1                                       };
   @command{"&"}        = { help => "Set an attribute on an object",
                            fun  => sub { return &cmd_set2(@_); },
                            nsp  => 1                                       };
   @command{"\@reload"} = { help => "Reload any changed perl code",
                            fun  => sub { return &cmd_reload_code(@_); }    };
   @command{pose}       = { help => "Perform an action of your choosing",
                            fun  => sub { return &cmd_pose(@_); }           };
   @command{":"}        = { help => @{@command{pose}}{help},
                            fun  => sub { return &cmd_pose(@_); },
                            nsp  => 1                                       };
   @command{";"}        = { help => "Posing without a space after your name",
                            fun  => sub { return &cmd_pose(@_[0..3],1); },
                            nsp  => 1                                       };
   @command{"emote"}    = { help => "Posing without a space after your name",
                            fun  => sub { return &cmd_pose(@_[0..3],1);      },
                            nsp  => 1                                       };
   @command{who}        = { help => "Display online users",
                            fun  => sub { return &cmd_who(@_); }            };
   @command{whisper}    = { help => "Send a message to something nearby",
                            fun  => sub { return &cmd_whisper(@_); }        };
   @command{doing}      = { help => "Display online users",
                            fun  => sub { return &cmd_DOING(@_); }          };
   @command{"\@doing"}  = { help => "Set what your up to [visible in WHO]",
                            fun  => sub { return &cmd_doing(@_); }          };
   @command{help}       = { help => "Help on internal commands",
                            fun  => sub { return &cmd_help(@_); }           };
   @command{"\@dig"}    = { help => "Dig a room",
                            fun  => sub { return &cmd_dig(@_); }            };
   @command{"look"}     = { help => "Look at an object or your current location",
                            fun  => sub { return &cmd_look(@_); }           };
   @command{quit}       = { help => "Disconnect from the server",
                            fun  => sub { return cmd_quit(@_); }            };
   @command{"\@trigger"} = { help => "Run commands in an attribute",
                            fun  => sub { return cmd_trigger(@_); }         };
   @command{"\@commit"} = { help => "Force a commit to mysql",
                            fun  => sub { return cmd_commit(@_); }          };
   @command{"\@set"}    = { help => "Set attributes on an object",
                            fun  => sub { return cmd_set(@_); }             };
   @command{"\@cls"}    = { help => "Clear the console screen",
                            fun  => sub { return cmd_clear(@_); }           };
   @command{"\@create"} = { help => "Create an object",
                            fun  => sub { return cmd_create(@_); }        };
   @command{"print"}    = { help => "Print an internal variable",
                            fun  => sub { return cmd_print(@_); }           };
   @command{"go"}       = { help => "Go through an exit",
                            fun  => sub { return cmd_go(@_); }              };
   @command{"home"}       = { help => "Go home",
                            fun  => sub { return cmd_go($_[0],$_[1],"home");}};
   @command{"examine"}  = { help => "Examine an object in more detail",
                            fun  => sub { return cmd_ex(@_); }              };
   @command{"ex"}  =      { help => "Examine an object in more detail",
                            fun  => sub { return cmd_ex(@_); }              };
   @command{"\@last"}   = { help => "Information about your last connects",
                            fun  => sub { return cmd_last(@_); }            };
   @command{page}       = { help => "Send a message to people in other rooms",
                            fun  => sub { cmd_page(@_); }};
   @command{take}       = { help => "Pick up an object",
                            fun  => sub { cmd_take(@_); }};
   @command{drop}       = { help => "Drop an object you are carrying",
                            fun  => sub { cmd_drop(@_); }};
   @command{"\@force"}  = { help => "Force an object/person to do something",
                            fun  => sub { cmd_force(@_); }};
   @command{inventory}  = { help => "List what you are carrying",
                            fun  => sub { cmd_inventory(@_); }};
   @command{enter}      = { help => "Enter an object",
                            fun  => sub { cmd_enter(@_); }};
   @command{leave}      = { help => "Leave an object",
                            fun  => sub { cmd_leave(@_); }};
   @command{"\@name"}   = { help => "Change the name of an object",
                            fun  => sub { cmd_name(@_); }};
   @command{"\@describe"}={ help => "Change the description of an object",
                            fun  => sub { cmd_describe(@_); }};
   @command{"\@pemit"}  = { help => "Send a mesage to an object or person",
                            fun  => sub { cmd_pemit(@_); }};
   @command{"\@emit"}   = { help => "Send a mesage to an object or person",
                            fun  => sub { cmd_emit(@_); }};
   @command{"think"}    = { help => "Send a mesage to just yourself",
                            fun  => sub { cmd_think(@_); }};
   @command{"version"}  = { help => "Show the current version of the MUSH",
                            fun  => sub { cmd_version(@_); }};
   @command{"\@link"}   = { help => "Set the destination location of an exit",
                            fun  => sub { cmd_link(@_); }};
   @command{"\@teleport"}={ help => "Teleport an object somewhere else",
                            fun  => sub { cmd_teleport(@_); }};
   @command{"\@open"}   = { help => "Open an exit to another room",
                            fun  => sub { cmd_open(@_); }};
   @command{"\@uptime"} = { help => "Display the uptime of this server",
                            fun  => sub { cmd_uptime(@_); }};
   @command{"\@destroy"}= { help => "Destroy an object",
                            fun  => sub { cmd_destroy(@_); }};
   @command{"\@toad"}   = { help => "Destroy an player",
                            fun  => sub { cmd_toad(@_); }};
   @command{"\@sleep"}  = { help => "Pause the a program for X seconds",
                            fun  => sub { cmd_sleep(@_); }};
   @command{"\@wait"}   = { help => "Pause the a program for X seconds",
                            fun  => sub { cmd_sleep(@_); }};
   @command{"\@sweep"}  = { help => "Lists who/what is listening",
                            fun  => sub { cmd_sweep(@_); }};
   @command{"\@list"}   = { help => "List internal server data",
                            fun  => sub { cmd_list(@_); }};
   @command{"\@mail"}   = { help => "Send mail between users",
                            fun  => sub { cmd_mail(@_); }};
   @command{"score"}    = { help => "Lists how many pennies you have",
                            fun  => sub { cmd_score(@_); }};
   @command{"\@recall"} = { help => "Recall output sent to you",
                            fun  => sub { cmd_recall(@_); }};
   @command{"\@telnet"} = { help => "open a connection to the internet",
                            fun  => sub { cmd_telnet(@_); }};
   @command{"\@close"} = { help => "close a connection to the internet",
                            fun  => sub { cmd_close(@_); }};
   @command{"\@reset"}  = { help => "Clear the telnet buffers",
                            fun  => sub { cmd_reset(@_); }};
   @command{"\@send"}   = { help => "Send data to a connected socket",
                            fun  => sub { cmd_send(@_); }};
   @command{"\@password"}={ help => "Change your password",
                            fun  => sub { cmd_password(@_); }};
   @command{"\@newpassword"}={ help => "Change someone else's password",
                            fun  => sub { cmd_newpassword(@_); }};
   @command{"\@switch"}  ={ help => "Compares strings then runs coresponding " .
                                    "commands",
                            fun  => sub { cmd_switch(@_); }};
   @command{"\@select"}  ={ help => "Compares strings then runs coresponding " .
                                    "commands",
                            fun  => sub { cmd_switch(@_); }};
   @command{"\@ps"}      ={ help => "Provide details about the engine queue",
                            fun  => sub { cmd_ps(@_); }};
   @command{"\@kill"}    ={ help => "Kill a process",
                            fun  => sub { cmd_killpid(@_); }};
   @command{"\@var"}     ={ help => "Set a local variable",
                            fun  => sub { cmd_var(@_); }};
   @command{"\@dolist"}  ={ help => "Loop through a list of variables",
                            fun  => sub { cmd_dolist(@_); }};
   @command{"\@while"}   ={ help => "Loop while an expression is true",
                            fun  => sub { cmd_while(@_); }};
   @command{"\@crash"}   ={ help => "Crashes the server.",
                            fun  => sub { cmd_crash(@_); }};
   @command{"\@\@"}     = { help => "A comment, will be ignored ",
                            fun  => sub { return;}                          };
   @command{"\@lock"}   = { help => "Test Command",
                            fun  => sub { cmd_lock(@_);}                    };
   @command{"\@boot"}   = { help => "Kicks the player off the game.",
                            fun  => sub { cmd_boot(@_);}                    };
   @command{"\@halt"}   = { help => "Stops all your running programs.",
                            fun  => sub { cmd_halt(@_);}                    };
   @command{"\@sex"}    = { help => "Sets the gender for an object.",
                            fun  => sub { cmd_sex(@_);}                     };
   @command{"\@read"}   = { help => "Reads various data for the MUSH",
                            fun  => sub { cmd_read(@_);}                    };
   @command{"\@compile"}= { help => "Reads various data for the MUSH",
                            fun  => sub { cmd_compile(@_);}                 };
   @command{"\@clean"}=   { help => "Cleans the Cache",
                            fun  => sub { cmd_clean(@_);}                   };
   @command{"give"}=      { help => "Give money or objects",
                            fun  => sub { cmd_give(@_);}                    };
   @command{"\@squish"} = { help => "Squish",
                            fun  => sub { cmd_squish(@_);}                  };
   @command{"\@split"}  = { fun  => sub { cmd_split(@_); }                  };
   @command{"\@websocket"}= { fun  => sub { cmd_websocket(@_); }            };
   @command{"\@find"}   = { fun  => sub { cmd_find(@_); }                   };
   @command{"\@sqldump"}= { fun  => sub { db_sql_dump(@_); }                };
   @command{"\@dbread"} = { fun  => sub { fun_dbread(@_); }                 };
   @command{"\@dump"}   = { fun  => sub { cmd_dump(@_); }                   };
   @command{"\@freefind"}={ fun  => sub { cmd_freefind(@_); }               };
   # --[ aliases ]-----------------------------------------------------------#
   
   @command{"\@poll"}  =  { fun => sub { cmd_doing(@_[0],@_[1],@_[2],
                                                   { header=>1}); },
                            alias=> 1                                       };
   @command{"\@version"}= { fun  => sub { cmd_version(@_); },
                            alias=> 1                                       };
   @command{e}          = { fun  => sub { cmd_ex(@_); },                       
                            alias=> 1                                       };
   @command{p}          = { fun  => sub { cmd_page(@_); },
                            alias=> 1                                       };
   @command{"huh"}      = { fun  => sub { return cmd_huh(@_); },
                            alias=> 1                                       };
   @command{w}          = { fun  => sub { return &cmd_whisper(@_); },
                            alias=> 1                                       };
   @command{i}          = { fun  => sub { return &cmd_inventory(@_); },
                            alias=> 1                                       };
   @command{"\@tel"}    = { fun  => sub { return &cmd_teleport(@_); },
                            alias=> 1                                       };
   @command{"l"}        = { fun  => sub { return &cmd_look(@_); },          
                            alias => 1                                      };
   @command{"\@\@"}     = { fun  => sub { return;}                          };
}
 
initialize_commands() if is_single;

# ------------------------------------------------------------------------#
# Generate Partial Commands                                               #
#    Instead of looping through all the commands every time, we'll just   #
#    populate the table with all possibilities.                           #
# ------------------------------------------------------------------------#
   for my $key (sort {length($a) <=> length($b)} keys %command) {
      for my $i (0 .. length($key)) {
         if(!defined @{@command{$key}}{full}) {
            @{@command{$key}}{full} = $key;
         }
         if(!defined @command{substr($key,0,$i)}) {
            @command{substr($key,0,$i)} = @command{$key};
         }
      }
   }
   delete @command{q};                                 # no alias for QUIT
   delete @command{qu};
   delete @command{qui};
# ------------------------------------------------------------------------#
sub atr_first
{
   my $txt = shift;

   if($txt  =~ /^([^ \(\)\[\]\{\}\*]+)/) {
      return $1;
   } else {
      return undef;
   }
}

sub get_mail
{
   my ($self,$num) = @_;

   my $list = mget($self,"obj_mail");

   if($num !~ /^\s*(\d+)\s*$/ || $num <= 0) {
      return "MAIL: Invalid message number.";
   } elsif(scalar keys %{$$list{value}} < $num) {
      return "MAIL: You don't have that many messages.";
   }

   # pull attribute name from index list
   my $attr = (sort {substr($a,9) <=> substr($b,9)} keys %{$$list{value}})[$num-1];

   if($attr eq undef) {
      return "MAIL: Internal error, unknown mail message.";
   } elsif($attr =~ /^obj_mail_/) {                 # timestamp in attr name
      my $sent = $';
      my $mail = get($self,$attr);

      # seperate sender,new, and message
      if($mail ne undef && $mail =~ /^\s*(\d+)\s*,\s*(\d+)\s*,/) {
         return { sent => $sent,
                  from => $1,
                  new => $2,
                  msg => $',
                  sub => "Not implimented yet.",
                  attr => $attr,
                  num => trim($num)
         };
      } else {
         return { attr => $attr, err => 1 };
      }
   }
}

sub cmd_mail
{
   my ($self,$prog,$txt,$switch) = @_;
   my ($count,$out) = (0,undef);

   if(mysqldb) {
      return err($self,$prog,"MAIL: Not written for mysql db yet.");
   } elsif(!hasflag($self,"PLAYER")) {
      return err($self,$prog,"MAIL: Only players may send/recieve mail.");
   }

   if($$switch{delete}) {                                     # delete email
      my $mail = get_mail($self,$txt);

      if(ref($mail) ne "HASH") {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s", $mail ]
              );
      } else {
         db_set($self,$$mail{attr});                            # remove email
         db_remove_list($self,"obj_mail",$$mail{attr});    # remove from index
         necho(self   => $self,
               prog   => $prog,
               source => [ "MAIL: Message %s deleted", $$mail{num} ]
              );
      }
   } elsif($txt =~ /^\s*short\s*/) {                       # show short list
      my ($list,$count) = (mget($self,"obj_mail"),undef);

      if($list eq undef || scalar keys %{$$list{value}} == 0) {
         $count = "no mail";
      } elsif(scalar keys %{$$list{value}} == 1) {
         $count = "1 message";
      } else {
         $count = (scalar keys %{$$list{value}}) . " messages";
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "MAIL: You have %s", $count ]
           );
   } elsif($txt =~ /^\s*$/) {                           # show mail headers
      my $list = mget($self,"obj_mail");

      if($list ne undef) {
         for my $num ( 1 .. (scalar keys %{$$list{value}}) ) {
            my $mail = get_mail($self,$num);

            if($mail eq undef || ref($mail) ne "HASH") { 
               # ooops?
            } elsif($$mail{err}) {                             # corrupt index
               db_set($self,$$mail{attr});                  # delete attribute
               db_remove_list($self,"obj_mail",$$mail{attr}); # rm index entry
            } else {
               my $name = ansi_substr(name($$mail{from}),0,15);
               my ($sec,$min,$hr,$day,$mon,$yr) = localtime($$mail{sent});
               my $mynum=$num;
               if(length($num) == 1) {
                  $mynum = " $num ";
               } elsif(length($num) == 2) {
                  $mynum = "$num ";
               }
               $out .= sprintf("%3s|%4s | %02d:%02d %02d:%02d/%02d | %s%s " .
                               "| %s\n",
                               $mynum,
                               $$mail{new} ? "Yes" : "",
                               $hr,$min,$mon+1,$day,$yr%100,$name,
                               (" " x (15 - ansi_length($name))),
                               (ansi_length($$mail{msg}) > 29) ? 
                                    (ansi_substr($$mail{msg},0,26) . "...") :
                                    $$mail{msg}
                              );
            }
         }
      }
      $out .= "           * No email *\n" if $out eq undef;

      necho(self   => $self,
            prog   => $prog,
            source => [ " # | New | Sent           | Sender          |" .
                           " Message\n" .
                        "---|-----|----------------|" . ("-"x17) ."|" . 
                            ("-" x30)."\n" .
                        $out .
                        "---|-----|----------------|" . ("-"x17) ."|" . 
                            ("-" x30) . "\n"
                      ]
           );
   } elsif($txt =~ /^\s*(\d+)\s*$/) {                       # display 1 email
      my $mail = get_mail($self,$1);                            # build email

      if(ref($mail) ne "HASH") {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s", $mail ]
              );
      }
      $out .= ("-" x 75) . "\n";
      $out .= sprintf("From:    %-46s At: %s\n",
                      name($$mail{from}),
                      scalar localtime($$mail{sent})
                     );
#      $out .= sprintf("Subject: %s\n",$$mail{sub});
      $out .= ("-" x 75) . "\n";
      $out .= "$$mail{msg}\n";
      $out .= ("-" x 75) . "\n";
      db_set($self,$$mail{attr},"$$mail{from},0,$$mail{msg}");   # set read flag

      necho(self   => $self,                                  # show results
            prog   => $prog,
            source => [ "%s", $out  ]
           );
   } elsif($txt =~ /^\s*([^=]+)\s*=\s*/) {                     # send message
      my $target = find_player($self,$prog,$1) ||
         return err($self,$prog,"Unknown player.");

      my $attr = "obj_mail_" . time();
      db_set_list($target,"obj_mail",$attr);                   # add to index
      db_set($target,$attr,"$$self{obj_id},1,".
             evaluate($self,$prog,$'));              # add message

      necho(self   => $self,
            prog   => $prog,
            source => [ "MAIL: You sent your message to %s.", name($target)]
           );
      if(hasflag($target,"CONNECTED")) {
         necho(self   => $target,
               prog   => $prog,
               source => [ "MAIL: You have a new message from %s.",name($self)]
              );
      }
   }
}

sub cmd_dbread
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission denied.");
   } else {
      delete @db[0 .. $#db];
      my $file = newest_full(@info{"conf.mudname"} . ".FULL.DB");
      db_read(undef,undef,$file);
   }
}

#
# cmd_compile
#   This doesn't actually compile but generates the regexps that are
#   required by the user's code. Currently regexps are not supported inside
#   the mush, only globs... so they need to be converted.
#
sub cmd_compile
{
   my ($self,$prog,$txt) = @_;
   my $first;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(memorydb) {
      return err($self,$prog,"This command is not implimented for MemoryDB");
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Starting compiling of regexps from globs." ]
        );
   for my $hash (@{sql("select atr_id, atr_pattern " .
                       "  from attribute " .
                       " where atr_pattern_type != 0")}) {
   sql("update attribute ".
       "   set atr_regexp = ?,".
       "       atr_first = ? ".
       " where atr_id = ? ",
       glob2re($$hash{atr_pattern}),
       atr_first($$hash{atr_pattern}),
       $$hash{atr_id});

      if($$db{rows} != 1 ) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Could not compile %s", $$hash{atr_id} ]
              );
      }
   }
   my_commit;

   necho(self   => $self,
      prog   => $prog,
      source => [ "Finished compiling of regexps from globs." ]
     );
}

sub cmd_backupmode
{
   my ($self,$prog,$txt) = @_;
   @info{backup_mode} = 1;
   necho(self   => $self,
      prog   => $prog,
      source => [ "Backup mode enabled." ]
     );
}

sub cmd_delta
{
   my ($self,$prog,$txt) = @_;
   printf("%s\n",print_var(\@delta));
}

# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
   my ($self,$prog,$txt) = @_;
   my (%last,$first);

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@WHILE is not a valid command to use in RUN function");
      return;
   }

   my $cmd = $$prog{cmd_last};

   if(!defined $$cmd{while_test}) {                 # initialize "loop"
        $first = 1;
        if($txt =~ /^\s*\(\s*(.*?)\s*\)\s*{\s*(.*?)\s*}\s*$/s) {
           ($$cmd{while_test},$$cmd{while_count}) = ($1,0);
           $$cmd{while_cmd} = $2;
        } else {
           return err($self,$prog,"usage: while (<expression>) { commands }");
        }
    }
    $$cmd{while_count}++;

    if($$cmd{while_count} >= 1000) {
       printf("#*****# while exceeded maxium loop of 1000, stopped\n");
       return err($self,$prog,"while exceeded maxium loop of 1000, stopped");
    } elsif(test($self,$prog,$$cmd{while_test})) {
       mushrun(self   => $self,
               prog   => $prog,
               runas  => $self,
               source => 0,
               cmd    => $$cmd{while_cmd},
               child  => 1
              );
       return "RUNNING";
    }
}


#
# cmd_find
#    Search the entire database for objects. When using a memory database,
#    search in 100 object segments.
#
sub cmd_find
{
   my ($self,$prog,$txt) = @_;
   my ($start,@out);

   if(memorydb) {
      if(defined $$prog{nomushrun}) {
         out($prog,"#-1 \@WHILE is not a valid command to use in RUN function");
         return;
      }

      my $cmd = $$prog{cmd_last};

      if(!defined $$cmd{find_pos}) {               # initialize "loop"
         $$cmd{find_pos} = 0;
         $$cmd{find_pat} = glob2re("*$txt*");
         $$cmd{find_owner} = owner_id($self);
      }

      for($start=$$cmd{find_pos};                   # loop for 100 objects
             $$cmd{find_pos} < $#db &&
             $$cmd{find_pos} - $start < 100;
             $$cmd{find_pos}++) {
         if(valid_dbref($$cmd{find_pos}) &&             # does object match?
            owner_id($$cmd{find_pos}) == $$cmd{find_owner} && 
            name($$cmd{find_pos},1) =~ /$$cmd{find_pat}/i) {
            push(@out,obj_name($self,$$cmd{find_pos}));
         }
      }

      if($$cmd{find_pos} >= $#db) {                       # search is done
         push(@out,"***End of List***");
         necho(self   => $self,
               prog   => $prog,
               source => [ join("\n",@out) ]
           );
         delete $$cmd{find_pos};                                 # clean up
         delete $$cmd{find_pat};
         delete $$cmd{find_owner};
      } else {
         if($#out >= -1) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ join("\n",@out) ]
              );
         }
         return "RUNNING";                                     # more to do
      }
   } else {
      necho(self   => $self,                              # search database
            prog   => $prog,
            source => [ table("select concat(obj_name, ".
                              "              '(#', ".
                              "              o.obj_id, ".
                              "              fde_letter, ".
                              "              ')' ".
                              "             ) object  ".
                              "  from object o,  ".
                              "       flag f,  ".
                              "       flag_definition fd  ".
                              " where o.obj_id = f.obj_id  ".
                              "   and f.fde_flag_id = fd.fde_flag_id  ".
                              "   and o.obj_owner = ?  ".
                              "   and CAST(fde_letter as binary) in " .
                              "       ('o','R','e','P')",
                              owner_id($self)
                             )
                      ]
           );
   }
}

sub cmd_perl
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"WIZARD")) {
      eval ( $txt );  
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done." ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission Denied." ],
           );
   }
}

#
# websocket
#    Instruct the client to sent a command to the server.
#
sub cmd_websocket
{
   my ($self,$prog,$txt) = @_;

   if(hasflag(owner($self),"WIZARD")) {
      websock_wall($txt); 
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission Denied." ],
           );
   }
}

sub cmd_sex
{
    my ($self,$prog,$txt) = @_;

    if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /=/) {
       cmd_set($self,$prog,"$`/sex=" . trim($'));
    } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "I don't know which one you mean!" ],
           );
    }
}

#
#  cmd_score
#     Tell the player how much money it has.
#
sub cmd_score
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You have %s.", money($self,1) ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Score expects no arguments." ],
           );
   }
};

sub cmd_give
{
   my ($self,$prog,$txt) = @_;


   if($txt =~ /=/) {
      my ($target,$what) = (find($self,$prog,$`),$');
      return err($self,$prog,"Give to whom?") if $target eq undef;

      if($what =~ /^\s*\-{0,1}(\d+)\s*$/) {
         $what = $1 . $2;
         if($what == 0) {
            return err($self,$prog,"You must specificy a positive amount of ".
                       "money.");
         } elsif(hasflag($self,"WIZARD")) {
            # can give money
         } elsif($what < 0) {
            return err($self,$prog,"You may not take away money.");
         } elsif($what > money($self)) {
            return err($self,$prog,"You don't have %s to give!",
               pennies($what));
         }

         if(!hasflag($self,"WIZARD") && !give_money($self,-$what)) {
            my_rollback();
            return err($self,$prog,"Internal error, unable to give money to ".
               "%s.",
               name($target));
         }

         if(!give_money($target,$what)) {
            my_rollback();
            return err($self,"Internal error, unable to give money to %s.",
               name($target));
         }

         my_commit;

         necho(self   => $self,
               prog   => $prog,
               source => [ "You give %s %s to %s.",
                           $what,
                           ($what == 1) ? @info{"conf.money_name_singular"} :
                                          @info{"conf.money_name_plural"},
                           name($target) ],
               target => [ $target, "%s gives you %s %s.",
                           name($self),
                           $what,
                           ($what == 1) ? @info{"conf.money_name_singular"} :
                                          @info{"conf.money_name_plural"} ]
              );
      } else {
        err($self,$prog,"You can only give money, right now.");
      }
   }
}

sub cmd_trigger
{
   my ($self,$prog,$txt) = @_;
   my (@wild,$last,$target,$attr,$name);

   if($txt =~ /^\s*([^\/]+)\s*\/\s*([^=]+)\s*={0,1}/ ||
      $txt =~ /^\s*([^\/]+)\s*/) {

      if($2 eq undef) {
         ($name,$target) = ($1,$self);
      } else {
         ($name,$target) = ($2,find($self,$prog,$1));
      }

      if($target eq undef) {
         return err($self,$prog,"No match.");
      } elsif(!controls($self,$target)) {                 # can modify object?
         return err($self,$prog,"Permission denied");
      }

      $attr = get($target,$name);

      if($attr eq undef) {
          return err($self,$prog,"No such attribute.");
      }

      for my $i (balanced_split($',',',2)) {             # split param list
         if($last eq undef) {
            $last = $i;
         } else {
            push(@wild,$i);
         }
      }
      push(@wild,$last) if($last ne undef);

      mushrun(self   => $self,
              prog   => $prog,
              runas  => $target,
              source => 0,
              cmd    => $attr,
              wild   => [ @wild ],
             );
   } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "usage: \@trigger <object>/<attr> [=<parm>]" ],
            );
   }
}

sub cmd_huh
{
   my ($self,$prog) = @_;

#   printf("HUH: '%s' -> '%s'\n",print_var($prog));
   necho(self   => $self,
         prog   => $prog,
         source => [ "Huh? (Type \"help\" for help.)" ]
        );
}
                  
sub cmd_offline_huh { my $sock = $$user{sock};
                      if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
                         ws_echo($sock,@info{"conf.login"});
                      } else {
                         printf($sock "%s\r\n",@info{"conf.login"});
                      }
                    };
sub cmd_version
{
   my ($self,$prog) = @_;
   my $src =  "https://github.com/c-hudson/teenymush";
                   
   my $ver = (@info{version} =~ /^TeenyMUSH ([\d\.]+)$/i) ? $1 : "N/A";

   $src = "<a href=$src>$src</a>" if($$prog{hint} eq "WEB");

   necho(self   => $self,
         prog   => $prog,
         source => [ "TeenyMUSH :  Version %s [cmdhudson\@gmail.com]\n".
                     "   Source :  %s",
                     $ver,$src
                   ]
        );
}

sub cmd_crash
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "You \@crash the server, yee haw.\n%s",code("long") ],
         room   => [ $self, "%s \@crashes the server.", name($self) ],
        );
   my $foo;
   @{$$foo{crash}};
}


sub cmd_reset
{
   my ($self,$prog) = @_;

   if(!hasflag($self,"WIZARD")) {
     return err($self,$prog,"Permission Denied.");
   } else {
     delete @info{io};
     necho(self   => $self,
           prog   => $prog,
           source => [ "All telnet connections reset." ]
          );
  }
}

#      my $eval = lock_eval($self,$prog,$self,$txt);
sub cmd_lock
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ ]+)\s*=\s*/) {

      my $target = find($self,$prog,$1);       # find target

      if($target eq undef) {                            # found invalid object
         return err($self,$prog,"I don't see that here.");
      } elsif(!controls($self,$target)) {                 # can modify object?
         return err($self,$prog,"Permission denied.");
      } else {                                              # set the lock
         my $lock = lock_compile($self,$prog,$self,$');

         if($$lock{error}) {                               # did lock compile?
            necho(self    => $self,
                  prog    => $prog,
                  source => [ "I don't understand that key, $$lock{errormsg}" ]
                 );
         } else {
            set($self,$prog,$target,"LOCK_DEFAULT",$$lock{lock});
         }
      }
   } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "usage: \@lock <object> = <key>" ],
            );
   }
}

#
# BEGIN statement with including code, and most of socket_connect were
# copied from from: http://aspn.activestate.com/ASPN/Mail/Message/
# perl-win32-porters/1449297.
#
BEGIN {
   # This nonsense is needed in 5.6.1 and earlier -- I'm too lazy to
   # test if it's been fixed in 5.8.0.
   if( $^O eq 'MSWin32' ) {
      *EWOULDBLOCK = sub () { 10035 };
      *EINPROGRESS = sub () { 10036 };
      *IO::Socket::blocking = sub {
          my ($self, $blocking) = @_;
          my $nonblocking = $blocking ? "0" : "1";
          ioctl($self, 0x8004667e, $nonblocking);
      };
   } else {
      require Errno;
      import  Errno qw(EWOULDBLOCK EINPROGRESS);
   }
}

sub hecho
{
   my ($fmt,@args) = @_;
   my $sock = $$user{sock};
   my $txt = sprintf("$fmt",@args);

   $txt =~ s/\r\n/\n/g;
   $txt =~ s/\n/\r\n/g;

   if($txt =~ /\n$/) {
      printf($sock "%s",$txt);
   } else {
      printf($sock "%s\r\n",$txt);
   }
}

# ------------------------------------------------------------------------#
# HoneyPot Commands
#
#     You could ban someone, but why not have a little fun with them?
#
# ------------------------------------------------------------------------#


#
# honey_page
#    Put some words into the mouth of any poor soals who get honeypotted.
#
sub honey_page
{
   my $txt = shift;
   my $r = int(rand(5));

   if($txt =~ /^\s*([^ ]+)\s*=\s*/) {
      if($r == 1) {
         hecho("You page %s, \"How do I connect, please help\"");
         hecho("%s pages, \"You're already connected.\"",ucfirst(lc($1)));
      } elsif($r == 2) {
         hecho("You page %s, \"How do I get \@toaded?\"",$1);
      } elsif($r == 3) {
         hecho("You page %s, \"What is a HoneyPot?\"",$1);
      } elsif($r == 4) {
         hecho("You page %s, \"%s\"",$');
      } elsif($r == 0) {
         hecho("You page %s, \"\@TOAD ME \@TOAD ME \@TOAD ME!\"",$1);
         hecho("%s pages, \"Ookay!\"",ucfirst(lc($1)));
         cmd_quit();
      }
   } else {
      hecho("Usage: page <user> = <message>");
   }
}

#
# honey_off
#    Just for testing purposes?
#
sub honey_off
{
   $$user{site_restriction} = 4;
}

#
# honey_huh
#
#    Show the login screen or the huh message depending on if the
#    person is connected or not.
#
sub honey_huh
{
   my $sock = $$user{sock};
   if(!defined $$user{honey}) {
      hecho("%s",getfile("honey.txt"));
   } else {
      hecho("%s","Huh?  (Type \"help\" for help.)");
   }
}

#
# honey_connect
#
#    Let the honeypotted feel like they've connected.
#
sub honey_connect
{
   my $txt = shift;

   my $sock = $$user{sock};

   if($txt =~ /^\s*([^ ]+)/i) {
      $$user{honey} = $1;
   } else {
      $$user{honey} = "Honey";
   }

   printf($sock "%s\n",<<__EOF__);
   -----------------------------------------------------------------------

       Get your free HONEY. Page Adrick for details

   -----------------------------------------------------------------------
__EOF__
   honey_look();
}

sub honey_look
{
   if(defined $$user{honey}) {
   hecho("%s",<<__EOF__);
Honey Tree(#7439RJs)
   In an open place in the middle of the forest, and in the middle of this place is a large oak-tree, and from the top of the tree, there comes a loud buzzing-noise. The large tree is big enough for a small bear to climb. A branch leans over towards a Bee's nest.
   That buzzing-noise means something. You don't get a buzzing-noise like that, just buzzing and buzzing, without its meaning something. If there's a buzzing-noise, somebody's making a buzzing-noise, and the only reason for making a buzzing-noise that I know of is because you're a bee. And the only reason for being a bee that I know of is making honey!
Contents:
Magic Blue Ballon
Honey Pot
Obvious exits:
House
__EOF__
   } else {
      honey_huh();
   }
}

#
# honey_who
#    Simulate some connected people.
#
sub honey_who
{
   hecho("%s","Player Name        On For Idle  \@doing");

   if(defined $$user{honey}) {
      hecho("%-16s     0:03   0s  HoneyPot User",substr($$user{honey},0,16));
   }
   hecho("%s",<<__EOF__);
Phantom              0:11  11m  
Quartz               5:07   5h  Something that is better left unspoken.
Sorad                6:11   5h  
Rowex            1d 01:21   1m  
Swift            2d 10:38   2m  
Adrick           2d 16:47   0s                               
Wolf             3d 13:35   3d  
Tyr              4d 19:15   4d  
Paiige          11d 22:19   1d  
Rince           11d 22:19   1d  
draith          43d 17:11   1h  
feem            46d 21:09   5d  
Ian             53d 17:59   4w  
Draken-Korin    66d 23:46   2s  
Ambrosia        69d 01:41   2M  There is no cow level.
Brazil         128d 16:08   4m  
nails          138d 00:46   3M  
Oleo           157d 19:27  26m  Just a friendly butter-substitute Wiz
18 Players logged in, 73 record, no maximum.
__EOF__
}

#
# honey_go
#    Simulate the go command, but not very well
#
sub honey_go
{
   my $r = int(rand(5));

   if(defined $$user{honey}) {
      if($r == 0) {
         hecho("The door seems jammed, try it again.");
      } elsif($r == 1) {
         hecho("The door moves forward but stops, try it again.");
      } elsif($r == 2) {
         hecho("The door opens but slams shut, try it again.");
      } elsif($r == 3) {
         hecho("The door opens but you get bored and slam it shut.");
      } elsif($r == 4) {
         hecho("Thats not a exit, its a frog");
      }
   }
}

# ---[ End HoneyPot Commands ]--------------------------------------------#

sub cmd_honey
{
   my ($self,$prog,$txt) = @_;
   my $match = 0;
   my $name;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^ ]+)\s*$/) {
      for my $who (@{sql("select obj_name, sck_socket " .
                          "  from socket sck, object obj " .
                          " where obj.obj_id = sck.obj_id " .
                          "   and lower(obj.obj_name) = lower(?) ",
                          $txt)}) {
         @{@connected{$$who{sck_socket}}}{site_restriction} = 69;
         @{@connected{$$who{sck_socket}}}{honey} = $$who{obj_name};
         $match++;
         $name = $$who{obj_name};
      }
   }

   if($match == 0) {
      necho(self   => $self,
            prog   => $prog,
            source => ["I don't recognize '%s'", $txt],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%d connections have been HoneyPotted for %s",
                        $match, $name
                      ]
           );
   }
   
}

sub cmd_var
{
    my ($self,$prog,$txt) = @_;

    $$prog{var} = {} if !defined $$prog{var};
    if($txt =~ /^\s*([^ ]+)\+\+\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)}++;
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set." ],
#            );
    } elsif($txt =~ /^\s*([^ ]+)\-\-\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)}--;
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set." ],
#            );
    } elsif($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)} = evaluate($self,$prog,$2);
#       necho(self   => $self,
#             prog   => $prog,
#             source => [ "Set. $1 = @{$$prog{var}}{$1}" ],
#            );
    } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "usage: \@var <variable> = <variables>" ],
            );
    }
} 
sub cmd_boot
{
   my ($self,$prog,$txt,$switch) = @_;

   if(hasflag($self,"WIZARD")) {
   
      $txt =~ s/^\s+|\s+$//g;
      if(defined $$switch{port} && $txt !~ /^\d+$/) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Port numbers must be numeric." ]
              );
      }

      for my $key (keys %connected) {
         my $hash = @connected{$key};
   
         if((defined $$switch{port} && $$hash{port} == $txt) ||
            (!defined $$switch{port} && lc($$hash{obj_name}) eq lc($txt))) {

            if(!defined $$hash{obj_id}) {
               necho(self   => $self,
                     target => $hash,
                     prog   => $prog,
                     source => [ "You \@booted port %s off!", $$hash{port} ],
                    );
            } else {
               necho(self   => $self,
                     target => $hash,
                     prog   => $prog,
                     target => [ $hash, "%s has \@booted you.", name($self)],
                     source => [ "You \@booted %s off!", obj_name($self,$hash)],
                     room   => [ $hash, "%s has been \@booted.",name($hash) ],
                    );
            }
         
            my $sock=$$hash{sock};
            server_disconnect($sock);
            return;
         }
      }
      if(defined $$switch{port}) {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "Unknown port specified." ],
              );
      } else {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "Unknown person specified." ],
              );
      }
   } else {
      return err($self,$prog,"Permission Denied.");
   }
}

sub cmd_killpid
{
   my ($self,$prog,$txt) = @_;

   my $engine = @info{engine};

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*(\d+)\s*$/) {
      if(defined $$engine{$1}) {
         delete @$engine{$1};
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "PID '%s' has been killed", $1 ],
              );
      } else {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "PID '%s' does not exist.", $1 ],
              );
      }

   } else {
      necho(self   => $self,                           # target's room
            prog   => $prog,
            source => [ "Usage: \@kill <pid>", $1 ],
           );
   }
}

sub cmd_ps
{
   my ($self,$prog) = @_;
   my $engine = @info{engine};

   necho(self   => $self,                           # target's room
         prog   => $prog,
         source => [ "----[ Start ]----" ],
        );
   for my $key (keys %$engine) {
      my $data = @{$$engine{$key}}[0];
      for my $pid (@{$$engine{$key}}) {
         my $stack = $$pid{stack};

         if($#$stack >= 0) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "  PID: %s for %s",$key,
                              obj_name($self,$$data{user}) 
                            ]
                 );
            for my $i (0 .. $#$stack) {
               my $cmd = @{$$stack[$i]}{cmd};
               if(length($cmd) > 67) {
                  necho(self   => $self,
                        prog   => $prog,
                        source => [ "    Cmd: %s...", substr($cmd,0,64) ],
                       );
               } else {
                  necho(self   => $self,
                        prog   => $prog,
                        source => [ "    Cmd: %s ($#$stack)", $cmd ],
                       );
               }
            }
         }
      }
   }
   necho(self   => $self,                           # target's room
         prog   => $prog,
         source => [ "----[  End  ]----" ],
        );
}

#
# cmd_halt
#    Delete all processes owned by the object running the @halt command.
#
sub cmd_halt
{
   my ($self,$prog) = @_;
   my $engine = @info{engine};
   my %owner;                                            # cache owner calls
   my $obj = @{owner($self)}{obj_id};

   printf("--[ halt start ]------\n");
   for my $pid (keys %$engine) {                          # look at each pid
      #  peek to see who created the process [ick]
      my $creator = @{@{@{@$engine{$pid}}[0]}{created_by}}{obj_id};
      my $program = @{@$engine{$pid}}[0];

      # cache owner of object
      @owner{$obj} = @{owner($creator)}{obj_id} if(!defined @owner{$creator});

      if(@owner{$obj} == $obj) {                  # are the owners the same?
         close_telnet($$program{telnet_socket});
         delete @$engine{$pid};
         necho(self => $self,
               prog => $prog,
               source => [ "Pid %s stopped." , $pid ]
              );
      }
   }
   printf("--[ halt end   ]------\n");
}
         

#
# tval
#    return an evaluated string suitable for test to use
#
sub tval
{
   my ($self,$prog,$txt) = @_;
   
   return lc(trim(evaluate($self,$prog,$txt)));
}

sub test
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ / <= /)     { 
      return (tval($self,$prog,$`) <= tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / == /)  {
      return (tval($self,$prog,$`) == tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / >= /)  {
      return (tval($self,$prog,$`) >= tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / > /)   {
      return (tval($self,$prog,$`) > tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / < /)   {
      return (tval($self,$prog,$`) < tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / eq /)  {
      return (tval($self,$prog,$`) eq tval($self,$prog,$')) ? 1 : 0;
   } elsif($txt =~ / ne /)  {
      return (tval($self,$prog,$`) ne tval($self,$prog,$')) ? 1 : 0;
   } else {
      return 0;
   }
}

sub cmd_split
{
    my ($self,$prog,$txt) = @_;
    my $max = 10;
    my @stack;
   
    if($txt =~ /,/) {
       my $target = find($self,$prog,$`) ||
         return err($self,$prog,"I can't find that");
       my $txt = get($target,$');
       $txt =~ s/\r\s*|\n\s*//g;

      unshift(@stack,$txt);

      while($#stack > -1 && $max--) {
          necho(self => $self,
                prog => $prog,
                source => [ "! %s", @stack[0] ]
               );
          my $before = $#stack;
          my $item = shift(@stack);

          if($item =~ /;/) {
             for my $i (balanced_split($item,';',3,1)) {
                unshift(@stack,$i);
             }
          }
          if($before == $#stack) {
             necho(self => $self,
                   prog => $prog,
                   source => [ "# %s ($before==$#stack)", $item ]
                  );
          }
       }
    } else {
       err($self,$prog,"Usage: \@split <object>,<attribute>");
    }
}

#
# cmd_find_deleted
#
sub cmd_freefind
{
   my ($self,$prog,$type) = @_;
   my ($file,$start);

   if(defined $$prog{nomushrun}) {
      return out($prog,"#-1 \@freefind can not be run in RUN function");
   } elsif(!hasflag($self,"WIZARD") && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(mysqldb) {
      return err($self,$prog,"Mysql does not need \@freefind");
   }

   $type = "normal" if($type eq undef);

   #-----------------------------------------------------------------------#
   # initialize loop                                                       #
   #-----------------------------------------------------------------------#
   my $cmd = $$prog{cmd_last};
   if(!defined $$cmd{find_pos}) {                      # initialize "loop"
      $$cmd{find_pos} = 0;
      @info{freefind_last} = time();
      delete @free[0 .. $#free];
   }

   my $start = $$cmd{find_pos};
   while($$cmd{find_pos} <= $#db && $$cmd{find_pos} - $start <= 50 ) {
      if(!defined @db[$$cmd{find_pos}]) {
         push(@free,$$cmd{find_pos});
      }
      $$cmd{find_pos}++;
   }

   if($$cmd{find_pos} <= $#db) {
      return "RUNNING";                                       # still running
   }
}


#
# cmd_dump
#    Dump the database to a file in segments so that the mush doesn't
#    need to "pause" while writing out the database. Why hang the mush
#    for no reason? This also does not fork() off a second copy of the
#    database to background the database like standard MUSHes do.
#
sub cmd_dump
{
   my ($self,$prog,$type) = @_;
   my ($file,$start);

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@DUMP is not a valid command to use in RUN function");
      return;
   } elsif(!hasflag($self,"WIZARD") && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(mysqldb) {
      return err($self,$prog,"Mysql does not need to be \@dumped");
   }

   $type = "normal" if($type eq undef);

   #-----------------------------------------------------------------------#
   # initialize loop                                                       #
   #-----------------------------------------------------------------------#
   my $cmd = $$prog{cmd_last};
   if(!defined $$cmd{dump_pos}) {                      # initialize "loop"
      if(defined @info{backup_mode} && is_running(@info{backup_mode})) {
         return err($self,$prog,"Backup is already running.");
      }
      $$cmd{dump_pos} = 0;

      my ($sec,$min,$hour,$day,$mon,$yr,$wday,$yday,$isdst) =
                                                localtime(time);
      $mon++;
      $yr -= 100;
      my $fn = sprintf("dumps/%s.FULL.%02d%02d%02d_%02d%02d%02d.tdb",
                       @info{"conf.mudname"},
                       $yr,$mon,$day,$hour,$min,$sec);

      open($file,"> $fn") ||
        return err($self,$prog,"Unable to open $fn for writing");

      printf($file "server: %s, dbversion=%s, exported=%s, type=$type\n",
         @info{version},db_version(),scalar localtime());

      $$cmd{dump_file} = $file;
      @info{backup_mode} = $$prog{pid};
      @info{db_last_dump} = time();
      if($type ne "CRASH") {
         echo_flag($user,
                   prog($user,$user),
                   "CONNECTED,PLAYER,LOG",
                   "<LOG> Database backup started.",name($user)
                  );
      }
   } else {
      $file = $$cmd{dump_file};
   }

   my $start = $$cmd{dump_pos};

   #-----------------------------------------------------------------------#
   # write out the database in 50 object segments                          #
   #-----------------------------------------------------------------------#
   while($$cmd{dump_pos} <= $#db && 
       ($$cmd{dump_pos} - $start <= 50 || $type eq "CRASH")) {
       printf($file "%s", db_object($$cmd{dump_pos}));
       $$cmd{dump_pos}++;
   }

   #-----------------------------------------------------------------------#
   # handle dump clean up or notify still running                          #
   #-----------------------------------------------------------------------#
   if($$cmd{dump_pos} > $#db) {                                 # dump done
      if(defined @$cmd{dump_file}) {                    # should not happen?
         printf($file "** Dump Completed %s **\n", scalar localtime());
         close($file);
         delete @$cmd{dump_file};
      }

      # sync changes back into the database
      for(my $i=0;$i <= $#delta;$i++) {
         if(defined @delta[$i] && ref(@delta[$i]) eq "HASH") {
            @db[$i] = @delta[$i];
         }
      }
      delete @delta[0 .. $#delta];                        # empty the delta
      delete @info{backup_mode};                     # turn off backup mode

      if($type ne "CRASH") {
         echo_flag($user,
                   prog($user,$user),
                   "CONNECTED,PLAYER,LOG",
                   "<LOG> Database finished."
                  );
         prune_dumps("dumps",@info{"conf.mudname"} . "\..*\.tdb");
      }
      return;
   } else {
      return "RUNNING";                                       # still running
   }
}

   

# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
   my ($self,$prog,$txt) = @_;
   my (%last,$first);

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@WHILE is not a valid command to use in RUN function");
      return;
   }

   my $cmd = $$prog{cmd_last};

   if(!defined $$cmd{while_test}) {                 # initialize "loop"
        $first = 1;
        if($txt =~ /^\s*\(\s*(.*?)\s*\)\s*{\s*(.*?)\s*}\s*$/s) {
           ($$cmd{while_test},$$cmd{while_count}) = ($1,0);
           $$cmd{while_cmd} = $2;
        } else {
           return err($self,$prog,"usage: while (<expression>) { commands }");
        }
    }
    $$cmd{while_count}++;

    if($$cmd{while_count} >= 1000) {
       printf("#*****# while exceeded maxium loop of 1000, stopped\n");
       return err($self,$prog,"while exceeded maxium loop of 1000, stopped");
    } elsif(test($self,$prog,$$cmd{while_test})) {
       mushrun(self   => $self,
               prog   => $prog,
               runas  => $self,
               source => 0,
               cmd    => $$cmd{while_cmd},
               child  => 1
              );
       return "RUNNING";
    }
}



sub max_args
{
   my ($count,$delim,@array) = @_;
   my @result;

   for my $i (0 .. $#array) {
      if($i <= $count-1) {
         @result[$i] = @array[$i];
      } elsif($i > $count-1) {
         @result[$count-1] .= $delim . @array[$i];
      }
   }
   return @result;
}

sub out
{
   my ($prog,$fmt,@args) = @_;

   if(defined $$prog{output}) {
      my $stack = $$prog{output};
      push(@$stack,sprintf($fmt,@args));
   }
}

sub verify_switches
{
   my ($self,$prog,$switch,@switches) = @_;
   my %hash;

   for my $item (@switches) {
      @hash{lc($item)} = 1;
   }

   for my $key (keys %$switch) {
      if(!defined @hash{lc($key)}) {
         err($self,$prog,"Unrecognized switch '$key' found");
         return 0;
      }
   }
   return 1;
}


#
# cmd_dolist
#    Loop though a list running specified commands.
#
sub cmd_dolist
{
   my ($self,$prog,$txt,$switch) = @_;
   my $cmd = $$prog{cmd_last};
   my ($delim, %last);

   verify_switches($self,$prog,$switch,"delimit") || return;

   if(defined $$switch{delimit}) {
      if($txt =~ /^\s*([^ ]+)\s*/) {
         $txt = $';
         $delim = $1;
      } else {
         return err($self,$prog,"Could not determine delimiter");
      }
   } else {
      $delim = " ";
   }

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@DOLIST is not a valid command to use in RUN function");
      return;
   }

#safe_split($txt,($delim eq undef) ? " " : $delim))
   if(!defined $$cmd{dolist_list}) {                       # initalize list
       my ($first,$second) = max_args(2,"=",balanced_split($txt,"=",3));
       $$cmd{dolist_cmd}   = $second;
#       $$cmd{dolist_list}  = [ split(' ',evaluate($self,$prog,$first)) ];
       $$cmd{dolist_list} = [safe_split(evaluate($self,$prog,$first),$delim)];
       $$cmd{dolist_count} = 0;
   }
   $$cmd{dolist_count}++;

   if($$cmd{dolist_count} > 500) {                  # force users to be nice
      return err($self,$prog,"dolist execeeded maxium count of 500, stopping");
   } elsif($#{$$cmd{dolist_list}} < 0) {
      return;                                                 # already done
   }

   my $item = shift(@{$$cmd{dolist_list}});

   if($item !~ /^\s*$/) {
      my $cmds = $$cmd{dolist_cmd};
      $cmds =~ s/\#\#/$item/g;
      mushrun(self   => $self,
              prog   => $prog,
              runas  => $self,
              source => 0,
              cmd    => $cmds,
              child  => 1,
             );
   }
  
#   printf("Returning: '%s'\n",($#{$$cmd{dolist_list}} >= 0) ? "RUNNING" : "DONE"); 
   return ($#{$$cmd{dolist_list}} >= 0) ? "RUNNING" : "DONE"; 
}

sub good_password
{
   my $txt = shift;

   if($txt !~ /^\s*.{8,999}\s*$/) {
      return "#-1 Passwords must be 8 characters or more";
   } elsif($txt !~ /[0-9]/) {
      return "#-1 Passwords must one digit [0-9]";
   } elsif($txt !~ /[A-Z]/) {
      "#-1 Passwords must contain at least one upper case character";
   } elsif($txt !~ /[A-Z]/) {
      return "#-1 Passwords must contain at least one lower case character";
   } else {
      return undef;
   }
}

sub cmd_password
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif(!hasflag($self,"PLAYER")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Non-players do not need passwords." ],
           );
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {

      my $result = good_password($2);

      if($result ne undef) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s", $result ],
                     );
      }

      if(memorydb) {
         if(mushhash($1) ne get($self,"obj_password")) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Invalid old password." ],
                 );
         } else {
            db_set($self,"obj_password",mushhash($2));
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Passworld changed." ],
                 );
         }
      } else {                                                      # mysql
         if(one($db,"select obj_password ".              # verify old password
                    "  from object " .
                    " where obj_id = ? " .
                    "   and obj_password = password(?)",
                    $$self{obj_id},
                    $1
               )) {
            sql(e($db,1),                                 # verify succeeded
                "update object ".                   # update to new password
                "   set obj_password = password(?) " . 
                " where obj_id = ?" ,
                $2,
                $$self{obj_id}
               );
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Your password has been updated." ],
                 );
         } else {                                             # verify failed
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "Invalid old password." ],
                 );
         }
      }
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "usage: \@password <old_password> = <new_password>" ],
           );
   }
}

sub cmd_sleep
{
   my ($self,$prog,$txt) = @_;

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@SLEEP is not a valid command to use in RUN function");
      return;
   }

   my $cmd = $$prog{cmd_last};

   if(!defined $$cmd{sleep}) {
      if($txt =~ /^\s*(\d+)\s*$/) {
         if($1 > 5400 || $1 < 1) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "\@sleep range must be between 1 and 5400." ],
                );
            return;
         } else {
            $$cmd{sleep} = time() + $1;
         }
      } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "usage: \@sleep <seconds>" ],
              );
         return;
      }
   }

   if($$cmd{sleep} >= time()) {
       $$prog{idle} = 1;
       return "RUNNING";
   }

#   if($$cmd{sleep} >= time()) {
#      signal_still_running($prog);
#   }
}

sub read_atr_config
{
   my ($self,$prog) = @_;

   my %default = (
      money_name_plural    => "Pennies",
      money_name_singular  => "Penny",
      paycheck             => 50,
      starting_money       => 150,
      linkcost             => 1,
      digcost              => 10,
      createcost           => 10,
      backup_interval      => 3600,                          # once an hour
      freefind_interval    => 84600,                           # once a day
      login                => "Welcome to @info{version}\r\n\r\n" .
                              "   Type the below command to customize this " .
                              "screen after loging in as God.\r\n\r\n" .
                              "    \@set #0/conf.login = Login screen\r\n\r\n",
      badsite              => "Your site has been banned.",
      httpd_template       => "<pre>",
      mudname              => "TeenyMUSH"
   );

   my %updated;

   for my $atr (lattr(0)) {
      if($atr =~ /^conf\./i) {
         if(@info{lc($atr)} == -1) {
            # skipped, turned off by missing modules? 
         } elsif(get(0,$atr) =~ /^\s*#(\d+)\s*$/) {
            @info{lc($atr)} = $1;
         } else {
            @info{lc($atr)} = get(0,$atr);
         }
         @updated{lc($atr)} = 1;
      }
   }
   
   for my $key (keys %default) {
      if(!defined @info{"conf.$key"}) {
         @info{"conf.$key"} = @default{$key};
      }
   }

   if(!defined @info{"conf.money_name_plural"}) {
      @info{"conf.money_name_plural"} = "pennies";
   } 
   if(!defined @info{"conf.money_name_plural"}) {
      @info{"conf.money_name_plural"} = "pennies";
   } 

   if($self eq undef) {
#      printf("%s\n", wrap("Updated: ",
#                          "         ",
#                          join(' ', keys %updated)
#                        )
#            );
   } else {
      $Text::Wrap::columns=75;
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",
                        wrap("Updated: ",
                             "         ",
                             join(' ', keys %updated)
                            )
                      ]
        );
   }
}

sub cmd_read
{
   my ($self,$prog,$txt) = @_;
   my ($file, $data, $name);
   my $count = 0;

   if(!hasflag($self,"WIZARD")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ],
           );
   } elsif($txt =~ /^\s*config\s*$/) {                # re-read config file
      read_config();
      read_atr_config($self,$prog);
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done" ],
           );
   } elsif($txt =~ /^\s*help\s*$/) {                     # import help data
      if(!open($file,"txt/help.txt")) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Could not open help.txt for reading." ],
                     );
      }

      if(memorydb) {
         delete @help{keys %help};
      } else {
         sql("delete from help");
      }

      while(<$file>) {
         s/\r|\n//g;
         if(/^& /) {
            if($data ne undef) {
               $count++;
               $data =~ s/\n$//g;

               if(memorydb) {
                  @help{$name} = $data;
               } else {
                  sql("insert into help(hlp_name,hlp_data) " .
                      "values(?,?)",$name,$data);
               }
            }
            $name = $';
            $data = undef;
         } else {
            $data .= $_ . "\n";
         }
      }

      if($data ne undef) {
         $data =~ s/\n$//g;

         if(memorydb) {
            @help{$name} = $data;
         } else {
            sql("insert into help(hlp_name,hlp_data) " .
                "values(?,?)",$name,$data);
         }
         $count++;
      }
      my_commit if mysqldb;

      necho(self   => $self,
            prog   => $prog,
            source => [ "%s help items read containing %d lines of text.",
                        $count, $. ],
           );
      close($file);
   
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Unknown read item '%s' specified.", trim($txt) ],
           );
   }
}

#
# get_segment
#    Get a single segment of a $delim delimited string. Strings can
#    be enclosed in "quotes" or {brackets} to avoid breaking apart the
#    string in the wrong location.
#
sub get_segment2
{
   my ($txt,$delim) = @_;

    if($txt =~ /^\s*"(.*?)(?<!(?<!\\)\\)"($delim|$)/s ||
       $txt =~ /^\s*{(.*?)(?<!(?<!\\)\\)}($delim|$)/s ||
       $txt =~ /^(.*?)($delim|$)/s) {
       return ($1,$');
    } else {
       return ($txt,undef);
    } 
}

#
# mush_split
#    Take a multiple segment string that is deliminted by $delim and
#    break it apart. Return the result as an array.
#
sub mush_split2
{
   my ($txt,$delim) = @_;
   my (@list,$seg);

   $delim = "," if $delim eq undef;

   while($txt) {
      ($seg,$txt) = (get_segment2($txt,$delim));
      push(@list,$seg);
   }
   return @list;
}

sub cmd_squish
{
   my ($self,$prog,$txt) = @_;
   my ($obj,$atr,$out);

   if($txt =~ /[\/,]/) {
      ($obj,$atr) = ($`,$');
   } else {
      return err($self,$prog,"usage: \@squish <object>/<attribute");
   }

   my $target = find($self,$prog,evaluate($self,$prog,$obj));

   if($target eq undef ) {
      return err($self,$prog,"Unknown object '$obj'");
      return "#-1 Unknown object";
   } elsif(!controls($self,$target)) {
      return "#-1 Permission Denied $$self{obj_id} -> $$target{obj_id}";
   }

   for my $line (split(/\n/,get($target,$atr))) {
      $line =~ s/^\s+//;
      $out .= $line;
   }

   set($self,$prog,$target,$atr,$out);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s",$out ],
        );
}

sub cmd_switch
{
   
    my ($self,$prog,@list) = (shift,shift,balanced_split(shift,',',3));
    my %last;

    my ($first,$second) = (get_segment2(shift(@list),"="));
    $first = trim(ansi_remove(evaluate($self,$prog,$first)));
    $first =~ s/[\r\n]//g;
    $first =~ tr/\x80-\xFF//d;
    unshift(@list,$second);

    while($#list >= 0) {
       # ignore default place holder used for readability
       if($#list == 1 && @list[0] =~ /^\s*DEFAULT\s*$/) {
          shift(@list);
       }
       if($#list >= 1) {
          my ($txt,$cmd) = (evaluate($self,$prog,shift(@list)),shift(@list));
          $txt =~ s/^\s+|\s+$//g;
          my $pat = glob2re(ansi_remove($txt));

          if($first =~ /$pat/) {
             return mushrun(self   => $self,
                            prog   => $prog,
                            runas  => $self,
                            source => 0,
                            cmd    => $cmd,
                           );
          }
       } else {
          @list[0] = $1 if(@list[0] =~ /^\s*{(.*)}\s*$/);
          @list[0] =~ s/\r|\n//g;
          return mushrun(self   => $self,
                         prog   => $prog,
                         runas  => $self,
                         source => 0,
                         cmd    => @list[0],
                        );
       }
    }
}
      

sub cmd_newpassword
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"PLAYER")) {
     return err($self,$prog,"Permission Denied, non-players do not need " .
                "passwords.");
   } elsif($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*$/) {

      my $player = find_player($self,$prog,$1) ||
         return err($self,$prog,"Unknown player '%s' specified",$1);

      if(!controls($self,$player)) {
         return err($self,$prog,"Permission denied.");
      }

#      good_password($2) || return;

      if(memorydb) {
         db_set($player,"obj_password",mushhash($2));
      } else {
         sql(e($db,1),
             "update object ".
             "   set obj_password = password(?) " . 
             " where obj_id = ?" ,
             $2,
             $$player{obj_id}
            );
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "The password for %s has been updated.",name($player) ],
           );

   } else {
      err($self,$prog,"usage: \@newpassword <player> = <new_password>");
   }
}

sub cmd_telnet
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $txt = evaluate($self,$prog,shift);
   my $pending = 1;

   return err($self,$prog,"PErmission Denied.") if(!hasflag($self,"WIZARD"));

   my $puppet = hasflag($self,"SOCKET_PUPPET");
   my $input = hasflag($self,"SOCKET_INPUT");

   if(!$input && !$puppet) {
      return err($self,$prog,"Permission DENIED.");
   } elsif(defined $$prog{telnet_sock}) {
      return err($self,$prog,"A telnet connection is already open");
   } elsif($txt =~ /^\s*([^:]+)\s*[:| ]\s*(\d+)\s*$/) {
      my $addr = inet_aton($1) ||
         return err($self,$prog,"Invalid hostname '%s' specified.",$1);
      my $sock = IO::Socket::INET->new(Proto=>'tcp',
                                       blocking=>0,
                                       Timeout => 30) ||
         return err($self,$prog,"Could not create socket.");
      $sock->blocking(0);
      my $sockaddr = sockaddr_in($2, $addr) ||
         return err($self,$prog,"Could not resolve hostname");
      $sock->connect($sockaddr) or                     # start connect to host
         $! == EWOULDBLOCK or $! == EINPROGRESS or         # and check status
         return err($self,$prog,"Could not open connection.");
      () = IO::Select->new($sock)->can_write(.2)     # see if socket is pending
          or $pending = 2;
      defined($sock->blocking(1)) ||
         return err($self,$prog,"Could not open a nonblocking connection");

      $$prog{telnet_sock} = $sock;

      @connected{$sock} = {
         obj_id    => $$self{obj_id},
         sock      => $sock,
         raw       => 1,
         hostname  => $1,
         port      => $2, 
         loggedin  => 0,
         opened    => time(),
         enactor   => $enactor,
         pending   => $pending,
         prog      => $prog,
      };

      if($puppet) {
         @{@connected{$sock}}{raw} = 1;
      } elsif($input) {
         @{@connected{$sock}}{raw} = 2;
      } else {                                          # shouldn't happen
         $sock->close;
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Internal error, could not open connection" ],
                     );
      }

      $readable->add($sock);

      if(mysqldb) {
          sql(e($db,1),
              "insert into socket " . 
              "(   obj_id, " .
              "    sck_start_time, " .
              "    sck_type, " . 
              "    sck_socket, " .
              "    sck_tag, " .
              "    sck_hostname, " .
              "    sck_port " .
              ") values ( ? , now(), ?, ?, ?, ?, ? )",
                   $$self{obj_id},
                   2,
                   $sock,
                   "NONE",
                   $1,
                   $2
             );
            my_commit;
      }
      @info{io} = {} if(!defined @info{io});

      @info{io}->{$sock} = {};
      @info{io}->{$sock}->{buffer} = [];

      necho(self   => $self,
            prog   => $prog,
            source => [ "Connection started to: %s:%s\n",$1,$2 ],
            debug  => 1,
           );
      
         necho(self   => $self,
                      prog   => $prog,
                      source => [ 1  ],
                     );
      return 1;
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "usage: \@telnet <id>=<hostname>:<port> {$txt}" ],
           );
      return 0;
   }
}

#
# send data to a connected @telnet socket. If the socket is pending,
# the socket will "pause" the @send till it times out or connects.
#
sub cmd_send
{
    my ($self,$prog,$txt) = (obj(shift),shift);
    my $sock;

    if(!hasflag($self,"WIZARD")) {                            # wizard only
       return err($self,$prog,"Permission Denied.");
    } elsif(defined hasflag($self,"SOCKET_PUPPET")) {
       # search for socket if set SOCKET_PUPPET.
       #    1. only one socket per object allowed 
       #    2. for convenience sake, a socket "name" isn't required.
       #       So we search for it.
       if(defined hasflag($self,"SOCKET_PUPPET")) {
          for my $key (keys %connected) {
             if($$self{obj_id} eq @{@connected{$key}}{obj_id} &&
                defined @{@connected{$key}}{prog}) {
                $sock = @{@connected{$key}}{sock};
             }
          }
       }
    } elsif(hasflag($self,"SOCKET_INPUT") && defined $$prog{telnet_sock}) {
       $sock = $$prog{telnet_socket};
    }

    # socket has not connected, try again later
    if($sock eq undef) {
       return err($self,$prog,"Telnet connection needs to be opened first");
    } elsif(@{@connected{$sock}}{pending} == 2) {
       $$prog{idle} = 1;                   # socket pending, try again later
       return "RUNNING";
    } else {
       my $txt = evaluate($self,$prog,shift);
       my $switch = shift;
       $txt =~ s/\r|\n//g;

       if(defined $$switch{lf}) {
          printf($sock "%s\n",$txt);
       } elsif(defined $$switch{cr}) {
          printf($sock "%s\r",$txt);
       } elsif(defined $$switch{crlf}) {
          printf($sock "%s\r\n",$txt);
       } else {
          printf($sock "%s\r\n",$txt);
       }
    }
}

sub cmd_close
{
    my ($self,$prog,$txt) = @_;

    if(!hasflag($self,"WIZARD")) {
       return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /^\s*([^ ]+)\s*=/) {
       my $hash = one($db,
                        "select * " .
                        "  from socket ".
                        " where lower(sck_tag) = lower(?) ",
                        $1
                   );

       if($hash eq undef) {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Unknown socket '%s' requested",$1 ],
               );
       } elsif(!defined @connected{$$hash{sck_socket}}) {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Socket '%s' has closed.",$1 ],
               );
       } else {
          my $sock=@{@connected{$$hash{sck_socket}}}{sock};
          printf($sock "%s\r\n",evaluate($self,$prog,$'));
       }
    } else {
       necho(self   => $self,
             prog   => $prog,
             source => [ "Usage: \@send <socket>=<data>" ]
            );
    }
}

sub cmd_recall
{
    my ($self,$prog,$txt) = @_;
    my ($qualifier,@args);

    if(memorydb) {
       return err($self,$prog,"\@recall is only supported under mysql");
    }
 
    if($txt !~ /^\s*$/) {
       $qualifier = 'and lower(out_text) like ? ';
       @args[1] = lc('%' . $txt . '%');
    }

    echo_nolog($self,
               text("  select concat( " .
                    "            date_format(" .
                    "               out_timestamp, ".
                    "               '[%H:%s %m/%d/%y]  ' " .
                    "            ), " .
                    "            text " .
                    "         ) text ".
                    "    from (   select out_timestamp, " .
                    "                    out_text text " .
                    "               from output " .
                    "              where out_destination = ? " .
                    "                $qualifier " .
                    "           order by out_timestamp desc " .
                    "           limit 15 " .
                    "         ) tmp  " .
                    "order by out_timestamp",
                    @args
                   )
        );
}

sub cmd_uptime
{
    my ($self,$prog) = @_;

    my $diff = time() - @info{server_start};
    my $days = int($diff / 86400);
    $diff -= $days * 86400;

    my $hours = int($diff / 3600);
    $diff -= $hours * 3600;

    my $minutes = int($diff / 60);

    necho(self   => $self,
          prog   => $prog,
          source => [ "Uptime: %s days, %s hours, %s minutes",
                      $days,$hours,$minutes ]
         );
}

sub cmd_force
{
    my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*([^ ]+)\s*=\s*/) {
       my $target = find($self,$prog,$1) ||
          return err($self,$prog,"I can't find that");

       if(!controls($self,$target)) {
          return err($self,$prog,"Permission Denied.");
       }

#       mushrun(self   => $target,
##               prog   => prog($target,$target$prog,
#               runas  => $target,
#               source => 0,
#               cmd    => evaluate($self,$prog,$'),
##               cmd    => $',
#               hint   => "INTERNAL"
#              );
       mushrun(self   => $target,
               prog   => $prog,
               runas  => $target,
               source => 0,
               cmd    => evaluate($self,$prog,$'),
               hint   => "INTERNAL"
              );
   } else {
     err($self,$prog,"syntax: \@force <object> = <command>");
   }
}

#   - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#   -------------------------------[ MOTD ]-------------------------------
#   ------------------------------[ MOTD ]------------------------------

sub motd_with_border
{
   my ($self,$prog,$txt) = @_;

   if($txt eq undef) {
      $txt = "   " . fun_center($self,$prog,"There is no MOTD today",70) .
             "\n   " .
             fun_center($self,
                        $prog,
                        "\@set #0/motd=<message> for your MOTD",
                        70
                       );
   }

   return "   " . ("-" x 31) . "[ MOTD ]" . ("-" x 31) . "\n\n".
             $txt . "\n\n   " . ("-" x 70) . "\n";
}

sub motd
{
   my ($self,$prog) = @_;
   
   my $atr = @info{"conf.motd"};
   return motd_with_border($self,$prog) if($atr eq undef);
   motd_with_border($self,$prog,evaluate(0,$prog,$atr));
}

sub cmd_list
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*motd\s*$/i) {
      necho(self => $self,
            prog => $prog,
            source => [ "%s", motd($self,$prog) ]
     );
   } elsif($txt =~ /^\s*cache\s*$/i) {
       my ($size,$atr,$age);
       for my $x (keys %cache) {
          if(ref($cache{$x}) eq "HASH") {
             for my $y (keys %{$cache{$x}}) {
                if(ref($cache{$x}->{$y}) eq "HASH") {
                   if(defined $cache{$x}->{$y}->{value} &&
                      defined $cache{$x}->{$y}->{ts}) {
                      $size += length($cache{$x}->{$y}->{value});
                      $age += time() - $cache{$x}->{$y}->{ts};
                      $atr++;
                   }
                } else {
#                   $size += length($cache{$x}->{$y});
#                   $atr++;
                }
             }
          } else {
#             $size += length($cache{$x});
#             $atr++;
          }
       }
       necho(self   => $self,
             prog   => $prog,
             source => [ "Internal Cache Sizes\n\n" ]
            );
       necho(self   => $self,
             prog   => $prog,
             source => [ "   Objects:     %s composed of %s items",
                         scalar keys %cache,$atr ]
            );
       necho(self   => $self,
             prog   => $prog,
             source => [ "   Size:        %s bytes",total_size(\%cache) ]
            );
       necho(self   => $self,
             prog   => $prog,
             source => [ "   Average Age: %d seconds",$age / $atr]
            );
   } elsif($txt =~ /^\s*functions\s*$/i) {
       $Text::Wrap::columns=75;
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",
                         wrap("Functions: ",
                              "           ",
                              uc(list_functions())
                             )
                       ]
            );
   } elsif($txt =~ /^\s*commands\s*$/i) {
      my %short;
 
      for my $key (keys %command) {
         if(defined @{@command{$key}}{full}) {
            @short{@{@command{$key}}{full}} = 1;
         }
      }

      $Text::Wrap::columns=75;
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s\n",
                        wrap("Commands: ",
                             "          ",
                             uc(join(' ',sort keys %short))
                            )
                      ]
           );
   } elsif($txt =~ /^\s*flags{0,1}\s*$/) {
       necho(self => $self,
             prog => $prog,
             source => [ "%s" ,
                         table("  select fde_name flag, " .
                               "         fde_letter letter " .
                               "    from flag_definition " .
                               "order by fde_name"
                              )
                       ]
            );
   } elsif(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*site\s*$/i) {
       necho(self => $self,
             prog => $prog,
             source => [ "%s" ,
                         table("select ste_id Id, " .
                               "       ste_pattern Pattern, " .
                               "       vao_value Type,".
                               "       obj_name Creator, " .
                               "       ste_created_date Date" .
                               "  from site, object, valid_option " .
                               " where ste_created_by = obj_id " .
                               "   and vao_code = ste_type".
                               "   and vao_table = 'site'"
                              )
                       ]
            );
   } elsif($txt =~ /^\s*buffers{0,1}\s*$/) {
       my $hash = @info{io};
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",print_var($hash) ],
            );
   } elsif($txt =~ /^\s*sockets\s*$/) {
      if(memorydb) {
         my $out;
         for my $key (keys %connected) {
            my $hash = @connected{$key};
            $out .= "\n$$hash{hostname}$$hash{start}$$hash{port}"
         }
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s",$out ],
              );
 
      } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s",
                           ,table("select obj_id, " .
                                  "       sck_start_time start, " .
                                  "       sck_hostname host, " .
                                  "       sck_port port, " .
                                  "       concat(sck_tag,':',sck_type) tag ".
                                  "  from socket "
                                 )
                         ]
              );
      }
   } elsif($txt =~ /^\s*(conf|config|configuration)\s*$/) {
      my $out;
      for my $key (sort grep {/^conf\./} keys %info) {
         if(length(@info{$key}) > 40) {
            $out .= sprintf("%-30s : %s...\n",$key,
                            substr(single_line(@info{$key}),0,37));
         } else {
            $out .= sprintf("%-30s : %s\n",$key,single_line(@info{$key}));
         }
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $out ]
           );

   } else {
       err($self,
           $prog,
           "syntax: \@list <option>\n\n",
           "        Options: site,functions,commands,sockets"
          );
   }
}


sub cmd_clean
{
   my ($self,$prog,$txt) = @_;
   my $del =0;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   }

   my $start = total_size(\%cache);

   delete @cache{keys %cache};

   for my $x (keys %cache) {                                       # object
      if(ref($cache{$x}) eq "HASH") {
         for my $y (keys %{$cache{$x}}) {                       # attribute
            if(ref($cache{$x}->{$y}) eq "HASH") {
               if(defined $cache{$x}->{$y}->{value} &&
                  defined $cache{$x}->{$y}->{ts}) {
                  if(time() - $cache{$x}->{$y}->{ts} > 3600) {
                    delete $cache{$x}->{$y};
                    $del++;
                    if($y eq "FLAG_WIZARD") {
                       remove_flag_cache($x,"FLAG_WIZARD");
                    }
                  }
               } else {
                  for my $z (keys %{$cache{$x}->{$y}}) {         # atr_flag
                     if(ref($cache{$x}-{$y}->{$z}) eq "HASH") {
                        if(defined $cache{$x}->{$y}->{$z}->{value} &&
                           defined $cache{$x}->{$y}->{$z}->{ts} &&
                           time() - $cache{$x}->{$y}->{$z}->{ts} > 3600) {
                           delete $cache{$x}->{$y}->{$z};
                           $del++;
                        }
                     }
                  }
               }
            }
         }
      }
   }
   necho(self   => $self,
         prog   => $prog,
         source  => [ "Cleared %d entries freeing %d bytes.", $del,
                      ($start - total_size(\%cache)) ],
        );
}

sub cmd_destroy
{
   my ($self,$prog,$txt) = @_;

   return err($self,$prog,"syntax: \@destroy <object>") if($txt =~ /^\s*$/);
   my $target = find($self,$prog,$txt) ||
       return err($self,$prog,"I can't find an object named '%s'",$txt);

   if(hasflag($target,"PLAYER")) {
      return err($self,$prog,"Players are \@toaded not \@destroyed.");
   } elsif(!controls($self,$target)) {
      return err($self,$prog,"Permission Denied.");
   }

   my $name = name($target);
   my $objname = obj_name($self,$target);
   my $loc = loc($target);

   if(!destroy_object($target)) {
      necho(self   => $self,
            prog   => $prog,
            source  => [ "Internal error, object not destroyed." ],
           );
   } else {
      necho(self      => $self,
            prog      => $prog,
            source    => [ "%s was destroyed.",$objname ],
            room      => [ $loc, "%s was destroyed.",$name  ],
            all_room  => [ $loc, "%s has left.",$name ]
           );
   }
}

sub cmd_toad
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*$/) {
       return err($self,$prog,"syntax: \@toad <object>");
   }

   my $target = find($self,$prog,$txt) ||
       return err($self,$prog,"I can't find an object named '%s'",$txt);

   if(!hasflag($target,"PLAYER")) {
      return err($self,$prog,"Only Players can be \@toaded");
   }

   my $obj_name = obj_name($self,$target);
   my $name = name($target);

   cmd_boot($self,$prog,name($$target{obj_id}));

   if(!destroy_object($target)) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Internal error, %s was not \@toaded.",$obj_name
                      ]
           );
   } elsif(loc($target) ne loc($self)) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s was \@toaded.",$obj_name ],
            room   => [ $target, "%s was \@toaded.",$name ],
            room2  => [ $target, "%s has left.",$name ]
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            room   => [ $target, "%s was \@toaded.",$name ],
            room2  => [ $target, "%s has left.",$name ]
           );
   }
}



sub cmd_think
{
   my ($self,$prog,$txt) = @_;

   my $txt = evaluate($self,$prog,$txt);

   if($txt !~ /^\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $txt ],
           );
   }
}

sub cmd_pemit
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ =]+)\s*=/s) {
      my $target = find($self,$prog,evaluate($self,$prog,$1));
      my $txt=$';

      if($target eq undef) {
         return err($self,$prog,"I don't see that here");
      } 

      my $txt = evaluate($self,$prog,$txt);

      if($txt !~ /^\s*$/) {
         necho(self   => $self,
               prog   => $prog,
               target => [ $target, "%s", $txt ],
              );
      }
   } else {
      err($self,$prog,"syntax: \@pemit <object> = <message>");
   }
}

sub cmd_emit
{
   my ($self,$prog,$txt) = @_;

   my $txt = evaluate($self,$prog,$txt);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", $txt ],
         room   => [ $self, "%s", $txt ]
        );
}

sub cmd_drop
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   }
   my $target = find_content($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   if(hasflag($target,"ROOM") || hasflag($target,"EXIT")) {
      return err($self,$prog,"You may not drop exits or rooms.");
   } elsif($$target{obj_id} == $$self{obj_id}) {
      return err($self,$prog,"You may not drop yourself.");
   }

   move($self,$prog,$target,fetch(loc($self))) ||
      return err($self,$prog,"Internal error, unable to drop that object");

   # provide some visual feed back to the player
   necho(self    => $self,
         prog    => $prog,
         source  => [ "You have dropped %s.\n%s has arrived.", 
                      name($target), name($target)
                    ],
         room    => [ $self, "%s dropped %s.", name($self),name($target) ],
         room2   => [ $self, "%s has arrived.",name($target) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_leave
{
   my ($self,$prog,$txt) = @_;

   my $container = fetch(loc($self));

   if($container eq undef || hasflag($container,"ROOM")) {
      return err($self,$prog,"You can't leave.");
   }

   my $dest = fetch(loc($container));

   if($dest eq undef) {
      return err($self,$prog,"You can't leave.");
   }

   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s dropped %s", name($container),name($self) ],
         room2  => [ $self, "%s has left.",name($self) ]
        );

#   my ($self,$prog,$target,$dest,$type) = (obj($_[0]),obj($_[1]),obj($_[2]),$_[3]);

   move($self,$prog,$self,$dest) ||
      return err($self,$prog,"Internal error, unable to leave that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s dropped %s.", name($container),name($self) ],
         room2  => [ $self, "%s has arrived.",name($self) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_take
{
   my ($self,$prog,$txt) = @_;
 
   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   }

   my $target = find($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   if(hasflag($target,"EXIT")) {
      return err($self,$prog,"You may not pick up exits.");
   } elsif(hasflag($target,"ROOM")) {
      return err($self,$prog,"You may not pick up rooms.");
   } elsif($$target{obj_id} eq  $$self{obj_id}) {
      return err($self,$prog,"You may not pick up yourself!");
   } elsif(loc($target) == $$self{obj_id}) {
      return err($self,$prog,"You already have that!");
   } elsif(loc($target) != loc($self)) {
      return err($self,$prog,"That object is to far away");
   }


   my $atr = get($target,"OBJ_LOCK_DEFAULT");

   if($atr ne undef) {
      my $lock = lock_eval($self,$prog,$target,$atr);

      if($$lock{error}) {
         return err($self,$prog,"Permission denied, the lock has broken.");
      } elsif(!$$lock{result}) {
         return err($self,$prog,"You can't pick that up.");
      }
   }
      
   necho(self   => $self,
         prog   => $prog,
         source => [ "You have picked up %s.", name($target) ],
         target => [ $target, "%s has picked you up.", name($self) ],
         room   => [ $self, "%s picks up %s.", name($self),name($target) ],
         room2  => [ $self, "%s has left.",name($target) ]
        );

   move($self,$prog,$target,$self) ||
      return err($self,$prog,"Internal error, unable to pick up that object");

   necho(self   => $self,
         prog   => $prog,
         room   => [ $target, "%s has arrived.",name($target) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_name
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^=]+?)\s*=\s*(.+?)\s*$/) {
      my $target = find($self,$prog,$1) ||
         return err($self,$prog,"I don't see that here.");
      my $cname = trim(evaluate($self,$prog,$2));
      my $name = ansi_remove($cname);
      my $old = name($target);

      controls($self,$target) ||
         return err($self,$prog,"Permission Denied.");

      if($name =~ /^([^a-zA-Z\_\-0-9\.]+)$/) {
         return err($self,$prog,"Invalid names, names may only " .
                    "contain A-Z, 0-9, _, ., and -");
      }

      if(hasflag($target,"PLAYER") && inuse_player_name($2)) {
         return err($self,$prog,"That name is already in use");
      } elsif($name =~ /^\s*(\#|\*)/) {
         return err($self,$prog,"Names may not start with * or #");
      }

      if(memorydb) {
         delete @player{name($target,1)};
         db_set($target,"name",$name);
         db_set($target,"cname",$cname);
      } else {

         sql($db,
             "update object " .
             "   set obj_name = ?, " .
             "       obj_cname = ? " .
             " where obj_id = ?",
             $name,
             $cname,
             $$target{obj_id},
             );
    
         set_cache($target,"obj_name");

         if($$db{rows} != 1) {
            err($self,$prog,"Internal error, name not updated.");
         } else {
            my_commit;
         }
      }

      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ],
            room   => [ $target, "%s is now known by %s.\n",$old, $cname]
           );
   } else {
      err($self,$prog,"syntax: \@name <object> = <new_name>");
   }
}

sub cmd_enter
{
   my ($self,$prog,$txt) = @_;

   my $target = find($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   # must be owner or object enter_ok to enter it
   if(!controls($self,$target) && !hasflag($target,"ENTER_OK")) {
     return err($self,$prog,"Permission denied.");
   }

   # check to see if object can pass enter lock
   my $atr = get($target,"OBJ_LOCK_ENTER");

   if($atr ne undef) {
      my $lock = lock_eval($self,$prog,$target,$atr);

      if($$lock{error}) {
         return err($self,$prog,"Permission denied, the lock has broken.");
      } elsif(!$$lock{result}) {
         return err($self,$prog,"Permission denied.");
      }
   }

   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s enters %s.",name($self),name($target)],
         room2  => [ $self, "%s has left.", name($self) ]
        );

   move($self,$prog,$self,$target) ||
      return err($self,$prog,"Internal error, unable to pick up that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         source => [ "You have entered %s.",name($target) ],
         room   => [ $self, "%s entered %s.",name($self),name($target)],
         room2  => [ $self, "%s has arrived.", name($self) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => "look"
          );
}

sub cmd_to
{
    my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*([^ ]+)\s*/) {
       my $tg = find($self,$prog,$1) ||
          return err($self,$prog,"I don't see that here.");

       necho(self   => $self,
             prog   => $prog,
             source => [ "%s [to %s]: %s\n",name($self),name($tg),$' ],
             room   => [ $self, "%s [to %s]: %s\n",name($self),name($tg),$' ],
            );
    } else {
       err($self,$prog,"syntax: `<person> <message>");
    }
}



sub whisper
{
   my ($self,$prog,$target,$msg) = @_;

   my $obj = find($self,$prog,$target);
   return err($self,$prog,"I don't see that here.") if $obj eq undef;

   if(hasflag($obj,"EXIT") || hasflag($obj,"ROOM")) {
      return err($self,$prog,"You may only whisper to objects or players");
   }

   if($msg =~ /^\s*:/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s senses, \"%s %s\"",
                        name($obj),name($self),trim($') 
                      ],
            target => [ $obj, "You sense, %s %s",name($self),trim($') ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You whisper, \"%s\" to %s.",trim($msg),name($obj) ],
            target => [ $obj, "%s whispers, \"%s\"",name($self),trim($msg) ],
           );
   }

   if(hasflag($self,"PLAYER")) { 
      set($self,$prog,$self,"OBJ_LAST_WHISPER","#$$obj{obj_id}",1);
   }
   return 1;
}

#
# cmd_page
#    Person to person communication reguardless of location.
#
sub cmd_whisper
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ ]+)\s*=/) {                           # standard whisper
      whisper($self,$prog,$1,$');
   } else {
      my $target = get($self,"OBJ_LAST_WHISPER");          # no target whisper
      return whisper($self,$prog,$target,$txt) if($target ne undef);

      err($self,
          $prog,
          "usage: whisper <user> = <message>\n" .
          "       whisper <message>"
         );
   }
}

sub page
{
   my ($self,$prog,$name,$msg) = @_;

   my $target = find_player($self,$prog,$name) ||
       return err($self,$prog,"I don't recognize '%s'",trim($name));

   if(!hasflag($target,"CONNECTED")) {
       return err($self,$prog,"Sorry, %s is not connected.",name($target));
   }

#   my $target = fetch($$target{obj_id});

   if($msg =~ /^\s*:/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Long distance to %s: %s %s",name($target),
                        name($self),trim($')
                      ],
            target => [ $target, "From afar, %s %s\n",name($self),trim($') ],
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "You paged %s with '%s'",name($target),trim($msg) ],
            target => [ $target, "%s pages: %s\n",name($self),trim($') ],
           );
   }

   if(hasflag($self,"PLAYER")) {
      set($self,$prog,$self,"OBJ_LAST_PAGE","#$$target{obj_id}",1);
   }
}

#
# cmd_page
#    Person to person communication reguardless of location.
#
sub cmd_page
{
   my ($self,$prog,$txt) = @_;

   return page($self,$prog,$1,$') if($txt =~ /^\s*([^ ]+)\s*=/); # standard page

   my $target = get($self,"OBJ_LAST_PAGE");                    # no target page
   return page($self,$prog,$target,$txt) if($target ne undef);

   err($self,
       $prog,
      "usage: page <user> = <message>\n       page <message>"
      );
}

sub cmd_last
{
   my ($self,$prog,$txt) = @_;
   my ($target,$extra, $hostname, $count,$out);

   if($txt =~ /^\s*$/) {
      if(hasflag($self,"PLAYER")) {
         $target = $self;
      } else {
         return err($self,$prog,"Only players may use this command.");
      }
   } else {
      $target = find_player($self,$prog,$txt) ||
         return err($self,$prog,"I couldn't find that player.");
   }

   if(memorydb) {
      my $attr = mget($target,"obj_lastsite");
 
      if($attr eq undef || !defined $$attr{value} || 
         ref($$attr{value}) ne "HASH") {
         return err($self,$prog,"Internal error, unable to continue");
      }
      $out .= "Site:                         Connection Start  | " .
              "Connection End\n";
      $out .= "----------------------------|-------------------|" .
              ("-" x 18) . "\n";

      for my $key (sort {$b <=> $a} keys %{$$attr{value}}) {
         last if($count++ > 6);
         if(@{$$attr{value}}{$key} =~ /^([^,]+)\,([^,]+)\,/) {
            $out .= sprintf("%-27s | %s | %s\n",short_hn($'),minits($key),
               minits($1));
         }
      }

      $out .= "----------------------------|-------------------|" .
              ("-" x 18) . "\n";

      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $out ],
           );
   } else {
      if(owner($target) eq owner($self) || hasflag($self,"WIZARD")) {
         $hostname = "skh_hostname Hostname,";      # optionally add hostname
      }

      # show target's total connections
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",
                        table("  select obj_name Name," .
                              "         $hostname " .
                              "         skh_start_time End," .
                              "         skh_end_time Start" .
                              "    from socket_history skh, " .
                              "         object obj " .
                              "   where skh_success = 1" .
                              "     and skh.obj_id = ? " .
                              "     and skh.obj_id = obj.obj_id " .
                              "order by skh_start_time desc " .
                              "limit 10",
                              $$target{obj_id}
                             )
                      ]
           );
    
      if((my $val=one_val("select count(*) value " .
                          "  from connect " .
                          " where obj_id = ? " .
                          "   and con_type = 1 ",
                          $$target{obj_id}
                         ))) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Total successful connects: %s\n", $val ],
              );
      } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Total successful connects: N/A\n" ],
              );
      }
   }
}



#
# cmd_go
#    Move an object from one location to another via an exit.
#
sub cmd_go
{
   my ($self,$prog,$txt) = @_;
   my ($exit ,$dest);

   $txt =~ s/^\s+|\s+$//g;
   my $loc = loc($self);

   if($txt =~ /^\s*home\s*$/i) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "There's no place like home...\n" .
                        "There's no place like home...\n" . 
                        "There's no place like home..."  ],
            room   => [ $self, "%s goes home.",name($self) ],
            room2  => [ $self, "%s has left.",name($self) ],
           );

      $dest = home($self);

      necho(self   => $self,
            prog   => $prog,
            room   => [ $self, "%s goes home.", name($self) ],
            room2  => [ $self, "%s has left.",name($self) ],
           );

   } else {
      # find the exit to go through
      $exit = find_exit($self,$prog,$txt) ||
         return err($self,$prog,"You can't go that way.");
 
      $dest = dest($exit);
  
      # grab the destination object
      if(dest($exit) eq undef) {
         return err($self,$prog,"That exit does not go anywhere");
      }
      necho(self   => $self,
            prog   => $prog,
            room   => [ $self, "%s goes %s.",name($self),
                        first(name($exit))
                      ],
            room2  => [ $self, "%s has left.",name($self) ],
           );
   }

   # move it, move it, move it. I like to move it, move it.
   move($self,$prog,$self,$dest) ||
      return err($self,$prog,"Internal error, unable to go that direction");

   generic_action($self,$prog,"MOVE",$loc);

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s has arrived.",name($self) ]
        );

   cmd_look($self,$prog);
}

sub cmd_teleport
{
   my ($self,$prog,$txt) = @_;
   my ($target,$location);

   if($txt =~ /^\s*([^ ]+)\s*=\s*([^ ]+)\s*/) {
      ($target,$location) = ($1,$2);
   } elsif($txt =~ /^\s*([^ ]+)\s*/) {
      ($target,$location) = ("#$$self{obj_id}",$1);
   } else {
      err($self,
          $prog,
          "syntax: \@teleport <object> = <location>\n" .
          "        \@teleport <location>");
   }

   $target = find($self,$prog,$target) ||
      return err($self,$prog,"I don't see that object here.");

   $location = find($self,$prog,$location) ||
      return err($self,$prog,"I can't find that location");

   controls($self,$target) ||
      return err($self,$prog,"Permission Denied.");

   controls($self,$location) ||
      return err($self,$prog,"Permission Denied.");

   if(hasflag($location,"EXIT")) {
      if((owner(loc($location)) == $$self{obj_id} &&
         loc($location) == loc($target)) ||
         hasflag($self,"WIZARD")) {
         $location = fetch(dest($location));

         if($location eq undef) {
            return err($self,$prog,"That exit does not go anywhere.");
         }
      } else {
         return err($self,$prog,"Permission Denied.");
      }
   }
   
   necho(self   => $self,
         prog   => $prog,
         all_room   => [ $target, "%s has left.",name($target) ]
        );

   move($self,$prog,$target,$location) ||
      return err($self,$prog,"Unable to teleport to that location");

   necho(self   => $self,
         prog   => $prog,
         all_room   => [ $target, "%s has arrived.",name($target) ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => "look"
          );
}

#
# cmd_print
#    Provide some debuging information
#
sub cmd_print
{
   my ($self,$prog,$txt) = @_;
   $txt =~ s/^\s+|\s+$//g;

   if(!hasflag($self,"WIZARD")) {
      err($self,$prog,"Permission denied.");
   } elsif($txt eq "connected") {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",print_var(\%connected) ]
           );
   } elsif($txt eq "connected_user") {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s",print_var(\%connected_user) ]
           );
   } else {
      err($self,$prog,"Invalid variable '%s' specified.",$txt);
   }
}

sub cmd_clear
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      err($self,$prog,"Permission denied.");
   } elsif($txt ne undef) {
      err($self,$prog,"\@clear expect no arguments");
   } elsif(perm($self,"CLEAR")) {
      $| = 1;
      printf("%s\n%s\n%s\n","#" x 65,"-" x 65,"#" x 65);
      print "\033[2J";    #clear the screen
      print "\033[0;0H";  #jump to 0,0
      necho(self   => $self,
            prog   => $prog,
            source => [ "Done." ]
           );
   } else {
      err($self,$prog,"Permission Denied.");
   }
}

sub cmd_commit
{
   my ($self,$prog) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied");
   } elsif(memorydb) {
      return err($self,$prog,"\@commit is only for mysql databases");
   } else {
      my_commit($db);
      necho(self   => $self,
            prog   => $prog,
            source => [ "You force a commit to the database" ],
           );
   }
}

sub cmd_quit
{
   my ($self,$prog) = @_;

   if(defined $$self{sock}) {
      my $sock = $$self{sock};

      if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
         ws_echo($sock,@info{"conf.logoff"});
      } else {
         printf($sock "%s",@info{"conf.logoff"});
      }
      server_disconnect($sock);
   } else {
      err($self,$prog,"Permission denied [Non-players may not quit]");
   }
}

sub cmd_help
{
   my ($self,$prog,$txt) = @_;

   $txt = "help" if($txt =~  /^\s*$/);
   my $help;

   if(memorydb) {
      # initalize help variable if needed
      cmd_read($self,$prog,"help") if(scalar keys %help == 0);
      $help = @help{lc(trim($txt))};
   } else {
      $help = one_val("select hlp_data value" .
                         "  from help " . 
                         " where hlp_name = ? ",
                         lc(trim($txt))
                        );
   }
   if($help eq undef) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "No entry for '%s'", trim($txt) ]
           );
   } elsif($help =~ /^RUN: \s*(.*)\s*$/i) {
      mushrun(self   => $self,
              prog   => $prog,
              runas  => $self,
              source => 0,
              cmd    => $1
             );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $help  ]
           );
   }
}

sub cmd_help_old
{
   my ($self,$prog,$txt) = @_;
   my %permalias = (
      '&' => 'set',
      '@cls' => 'clear'
   );


   if($txt eq undef) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "HELP\n\n" .
                        "   This is the Ascii Server online help system\n\n" ],
           );

      for my $key (sort keys %command) {
         if(defined @{@command{$key}}{alias}) {
            # ignore
         } elsif((defined @permalias{$key} &&
            perm($self,@permalias{$key})) ||
            (!defined @permalias{$key})) {
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "   %-10s : %s",$key,@{@command{$key}}{help} ]
                 );
         }
      }
   } elsif(defined @command{trim(lc($txt))}) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", @{@command{trim(lc($txt))}}{help} ],
           );
   } else {
      err($self,$prog,"Unknown help item '%s' specified",trim(lc($txt)));
   }
}

sub cmd_pcreate
{
   my ($self,$prog,$txt) = @_;

   if($$user{site_restriction} == 3) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", @info{"conf.registration"} ],
           );
   } elsif($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/) {
      if(inuse_player_name($1)) {
         err($user,$prog,"That name is already in use.");
      } else {
         $$user{obj_id} = create_object($self,$prog,$1,$2,"PLAYER");
         $$user{obj_name} = $1;
         cmd_connect($self,$prog,$txt);
      }
   } else {
      err($user,$prog,"Invalid create command, try: create <user> <password> [$txt]");
   }
}

sub create_exit
{
   my ($self,$prog,$name,$in,$out,$verbose) = @_;

   my $exit = create_object($self,$prog,$name,undef,"EXIT") ||
      return undef;

   if(!link_exit($self,$exit,$in,$out,1)) {
      return undef;
   }

   return $exit;
}

sub cmd_create
{
   my ($self,$prog,$txt) = (@_[0],@_[1],trim(@_[2]));

   if(quota_left($self) <= 0) {
      return err($self,$prog,"You are out of QUOTA to create objects.");
   } elsif(length($txt) > 50) {
      return err($self,$prog,
                 "Object name may not be greater then 50 characters"
                );
   } elsif(money($self) < @info{"conf.createcost"}) {
      return err($self,$prog,"You need at least ".pennies("createcost").".");
   }

   my $dbref = create_object($self,$prog,$txt,undef,"OBJECT") ||
      return err($self,$prog,"Unable to create object");

   if(!give_money($self,"-" . @info{"conf.createcost"})) {
      return err($self,$prog,"Unable to deduct cost of object.");
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Object created as: %s",obj_name($self,$dbref) ],
        );

   my_commit if mysqldb;
}

sub cmd_link
{
   my ($self,$prog,$txt) = @_;
   my ($name,$target,$destination);

   if($txt =~ /^\s*([^=]+)\s*=\s*(.+?)\s*$/) {
      ($name,$destination) = ($1,$2);
   } else {
      return err($self,$prog,"syntax: \@link <exit> = <room_dbref>\n" .
                      "        \@link <exit> = here\n");
   }

   my $target = find($self,$prog,$name) ||
      return err($self,$prog,"I don't see '$name' here");

   my $dest = find($self,$prog,$destination) ||
      err($self,$prog,"I don't see '$destination' here.");
    
   if(hasflag($target,"EXIT") &&
      (controls($self,$dest)  || hasflag($dest,"LINK_OK"))) {
      link_exit($self,$target,undef,$dest) ||
         return err($self,$prog,"Internal error while trying to link exit");
      necho(self   => $self, prog   => $prog, source => [ "set." ],);
   } elsif(!hasflag($target,"EXIT") &&
      (controls($self,$dest)  || hasflag($dest,"ABODE"))) {
      set_home($self,$prog,$target,$dest) ||
         return err($self,$prog,"Internal error while trying to link exit");
      necho(self   => $self, prog   => $prog, source => [ "set." ],);
   } else {
      return err($self,$prog,"Permission denied");
   }
}

sub cmd_dig
{
   my ($self,$prog,$txt) = @_;
   my ($loc,$room_name,$room,$in,$out,$cost);
     
   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied."); 
   } elsif($txt =~ /^\s*([^\=]+)\s*=\s*([^,]+)\s*,\s*(.+?)\s*$/ ||
      $txt =~ /^\s*([^=]+)\s*=\s*([^,]+)\s*$/ ||
      $txt =~ /^\s*([^=]+)\s*$/) {
      ($room_name,$in,$out) = ($1,$2,$3);
   } else {
      return err($self,
                 $prog,
                 "syntax: \@dig <RoomName> = <InExitName>,<OutExitName>\n".
                 "        \@dig <RoomName> = <InExitName>\n" .
                 "        \@dig <RoomName>");
   }

   if($in ne undef && $out ne undef && quota_left($self) < 3) {
      return err($self,$prog,"You need a quota of 3 or better to complete " .
                 "this \@dig"
                );
   } elsif(($in ne undef || $out ne undef) && quota_left($self) < 2) {
      return err($self,$prog,"You need a quota of 2 or better to complete " .
                 "this \@dig"
                );
   } elsif($in eq undef && $out eq undef && quota_left($self) < 1) {
      return err($self,$prog,"You are out of QUOTA to create objects");
   } elsif($in ne undef && $out ne undef) {
      $cost = @info{"conf.digcost"} + (@info{"conf.linkcost"} * 2);
   } elsif($in ne undef || $out ne undef) {
      $cost = @info{"conf.digcost"} + @info{"conf.linkcost"};
   } elsif($in eq undef && $out eq undef) { 
      $cost = @info{"conf.digcost"};
   }

   if($cost > money($self)) {
      return err($self,$prog,"You need at least " . pennies($cost));
   }

   if(!give_money($self,"-" . $cost)) {
      return err($self,$prog,"Internal error, couldn't debit " .
                 pennies($cost));
   }


   if($in ne undef && find_exit($self,$in)) {
      return err($self,$prog,"Exit '%s' already exists in this location",$in);
   }


   if($out ne undef) {
      $loc = loc($self) ||
         return err($self,$prog,"Unable to determine your location");

      if(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
         return err($self,
                    $prog,
                    "You do not own this room or it is not LINK_OK"
                   );
      }
   }

   my $room = create_object($self,$prog,$room_name,undef,"ROOM")||
      return err($self,$prog,"Unable to create a new object");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Room created as:         %s(#%sR)",$room_name,$room ],
        );

   if($in ne undef) {
      my $in_dbref = create_exit($self,$prog,$in,$loc,$room);
 
      if($in_dbref eq undef) {
         return err($self,$prog,"Unable to create exit '%s' going in to room",
                    $in
                   );
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "   In exit created as:   %s(#%sE)",$in,$in_dbref ],
           );
   }

   if($out ne undef) {
      my $out_dbref = create_exit($self,$prog,$out,$room,$loc);
      if($out_dbref eq undef) {
         return err($self,$prog,"Unable to create exit '%s' going out of room",
                    $out
                   );
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "   Out exit created as:  %s(#%sE)",$out,$out_dbref ],
           );
   }
   my_commit;
}

sub cmd_open
{
   my ($self,$prog,$txt) = @_;
   my ($exit,$destination,$dest);
  
   if($txt =~ /^\s*([^=]+)\s*=\s*([^ ]+)\s*$/ ||
      $txt =~ /^\s*([^ ]+)\s*$/) {
      ($exit,$destination) = ($1,$2);
   } else {
      return err($self,$prog,"syntax: \@open <ExitName> = <destination>\n" .
                             "        \@open <ExitName>");
   }

   if(quota_left($self) < 1) {
      return err($self,$prog,"You are out of QUOTA to create objects");
   }

   !find_exit($self,$exit,"EXACT") ||
      return err($self,$prog,"Exit '%s' already exists in this location",$exit);

   my $loc = loc($self) ||
      return err($self,$prog,"Unable to determine your location");

   if(!(controls($self,$loc) || hasflag($loc,"ABODE"))) {
      return err($self,$prog,"You do not own this room and it is not ABODE");
   }


   if($destination ne undef) {
      $dest = find($self,$prog,$destination) ||
         return err($self,$prog,"I can't find that destination location");

      if(!(controls($self,$loc) || hasflag($loc,"LINK_OK"))) {
         return err($self,$prog,"This is not your room and it is not LINK_OK");
      }
   }

   my $dbref = create_exit($self,$prog,$exit,$loc,$dest) ||
      return err($self,$prog,"Internal error, unable to create the exit");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Exit created as %s(#%sE)",$exit,$dbref ],
        );

   my_commit;
}

sub mushhash
{
   return "*" . uc(sha1_hex(sha1(shift)));
}

#
# invalid_player
#    Determine if the request is valid or not, provide feed back and log
#    if the attempt wasn't valid.
#
sub invalid_player
{
   my ($self,$name,$pass) = @_;

   if(memorydb()) {
       return 1 if(!defined @player{lc($name)});

       if(lc($name) eq "guest") {                  # any password for guest
          $$self{obj_id} = @player{lc($name)};
          return 0;
       } elsif(!valid_dbref(@player{lc($name)}) ||
          get(@player{lc($name)},"obj_password") ne mushhash($pass)) {
          return 1;
       } else {
          $$self{obj_id} = @player{lc($name)};
          return 0;
       }
   } else {
       my $hash = one("select obj.obj_id, ".
                      "       obj_password " .
                      "  from object obj, ".
                      "       flag flg, ".
                      "       flag_definition fde ".
                      " where lower(obj_name) = lower(?) " .
                      "   and obj.obj_id = flg.obj_id " .
                      "   and flg.fde_flag_id = fde.fde_flag_id " .
                      "   and fde.fde_name = 'PLAYER' ",
                      $name
                   );

       if(lc($name) eq "guest" && defined $$hash{obj_id}) { # don't worry 
          $$self{obj_id} = $$hash{obj_id};                  # about guest's
          return 0;                                         # password
       } elsif(mushhash($pass) eq $$hash{obj_password}) {
          $$self{obj_id} = $$hash{obj_id};
          return 0;
       } else {
          return 1;
       }
   }
}


#
# cmd_connect
#    Verify password, populate @connect / @connected_user hash. Allow player
#    to connected.
#
sub cmd_connect
{
   my ($self,$prog,$txt) = @_;
   my $sock = @$user{sock};
   my ($atr,$player);
 
   if($txt =~ /^\s*([^ ]+)\s+([^ ]+)\s*$/ ||            #parse player password
      $txt =~ /^\s*([^ ]+)\s*$/) {
      my ($username,$pass) = ($1,$2);

      # --- Valid User ------------------------------------------------------#

      if(invalid_player($self,$username,$pass)) {
         if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
            ws_echo($sock,"Either that player does not exist, or has a different password.");
         } else {
            printf($sock "Either that player does not exist, or has a different password.");
         }
         return;
      }

      # --- Hook connected user up to local structures ----------------------#
      $$player{connect_time} = time();
      for my $key (keys %$player) {                 # copy object structure
         $$user{$key} = $$player{$key};
      }
      $$user{loggedin} = 1;

      if(!defined @connected_user{$$user{obj_id}}) {    # reverse lookup
          @connected_user{$$user{obj_id}} = {};                   # setup
      }
      @{@connected_user{$$user{obj_id}}}{$$user{sock}} = $$user{sock};

      # --- log connnect ----------------------------------------------------#
      if(memorydb) {
         db_set_hash($$user{obj_id},
                     "obj_lastsite",
                     time(),
                     time() . ",1,$$user{hostname}"
                    );
      } else {
         sql( "insert into socket " .
             "( " . 
             "    obj_id, " . 
             "    sck_start_time, " .
             "    sck_hostname, " .
             "    sck_socket, " .
             "    sck_type " . 
             ") values ( ?, now(), ?, ?, ? ) ",
                  $$user{obj_id},
                  $$user{hostname},
                  $$user{sock},
                  1
            );
   
         # put the historical request in right away, no need to wait.
         sql("insert into socket_history ".
             "( obj_id, " .
             "  sck_id, " .
             "  skh_hostname, " .
             "  skh_start_time, " .
             "  skh_success, " .
             "  skh_type ".
             ") values ( " .
             "  ?, ?, ?, now(), 1, ? ".
             ")",
             $$user{obj_id},
             curval(),
             $$user{hostname},
             1
            );
   
         my_commit($db);
      }

      # --- Provide users visual feedback / MOTD --------------------------#

      necho(self   => $user,                 # show message of the day file
            prog   => prog($user,$user),
            source => [ "%s\n", motd() ]
           );

      cmd_mail($user,prog($user,$user),"short");

      necho(self   => $user,                 # show message of the day file
            prog   => prog($user,$user),
            source => [ "\n" ]
           );

      cmd_look($user,prog($user,$user));                    # show room

      printf("    %s@%s\n",name($user),$$user{hostname});


      # notify users local and users with monitor flag
      necho(self   => $user,
            prog   => prog($user,$user),
            room   => [ $user , "%s has connected.",name($user) ],
           );

      echo_flag($user,
                prog($user,$user),
                "CONNECTED,PLAYER,MONITOR",
                "[Monitor] %s has connected.",name($user));

      # --- Handle @ACONNECTs on masteroom and players-----------------------#

      if(@info{"conf.master"} ne undef) {
         for my $obj (lcon(@info{"conf.master"}),$player) {
            if(($atr = get($obj,"ACONNECT")) && $atr ne undef){
               mushrun(self   => $self,                 # handle aconnect
                       runas  => $self,
                       source => 0,
                       cmd    => $atr
                      );
            }
         }
      }

   } else {
      # not sure this can actually happen
      if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
         ws_echo($sock,"Invalid command, try: Connect <user> <password>");
      } else {
         printf($sock "Invalid command, try: cOnnect <user> <password>\r\n");
      }
   }
}

#
# cmd_doing
#    Set the @doing that is visible from the WHO/Doing command
#
sub cmd_doing
{
   my ($self,$prog,$txt,$switch) = @_;

   if(!defined @connected{$$self{sock}}) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ]
           );
   } elsif(defined $$switch{header} && $txt =~ /^\s*$/) {
      if(!hasflag($self,"WIZARD")) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "Permission denied." ]
                      );
      }
      delete @info{"conf.doing_header"};
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "Removed." ]
                  );
   } elsif(defined $$switch{header}) {
      if(!hasflag($self,"WIZARD")) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "Permission denied." ]
                      );
      }
      @info{"conf.doing_header"} = $txt;
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "Set." ]
                  );
   } elsif($txt =~ /^\s*$/) {
      delete $connected{$$self{sock}}{obj_doing};
      necho(self   => $self,
            prog   => $prog,
            source => [ "Removed." ]
           );
   } else {
      $connected{$$self{sock}}{obj_doing} = trim($txt);
      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ]
           );
   }
}


sub cmd_describe
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^ \/]+?)\s*=\s*(.*?)\s*$/) {
      cmd_set($self,$prog,trim($1) . "/DESCRIPTION=" . $2);
   } else {
      err($self,$prog,"syntax: \@describe <object> = <Text of Description>");
   }
}

# @set object = wizard
# @set me/attribute
sub cmd_set
{
   my ($self,$prog,$txt) = @_;
   my ($target,$attr,$value,$flag);

    if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
    } elsif($txt =~ /^\s*([^ =]+?)\s*\/\s*([^ =]+?)\s*=(.*)$/s) { # attribute
      if(@{$$prog{cmd}}{source} == 1) {                          # user input
         ($target,$attr) = ($1,$2);
      } else {                                               # non-user input
         ($target,$attr) = (evaluate($self,$prog,$1),evaluate($self,$prog,$2));
      }
      ($target,$value) = (find($self,$prog,$target),$3);

      return err($self,$prog,"Unknown object '%s'",$1) if !$target;
      controls($self,$target) || return err($self,$prog,"Permission denied");

      if(isatrflag($value)) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s", set_atr_flag($target,$attr,$value) ]
              );
      } else {

         if(@{$$prog{cmd}}{source} == 0) {                      # user input
            $value = evaluate($self,$prog,$value);
         }
         set($self,$prog,$target,evaluate($self,$prog,$attr),$value);
      }
      my_commit($db) if(mysqldb);

   } elsif($txt =~ /^\s*([^ =\\]+?)\s*= *(.*?) *$/s) { # flag?
      ($target,$flag) = (find($self,$prog,$1),$2);
      return err($self,$prog,"Unknown object '%s'",$1) if !$target;
      controls($self,$target) || return err($self,$prog,"Permission denied");

      if($flag =~ /^\s*dark\s*$/i &&          # no dark flag for non-wizards
         hasflag($target,"PLAYER") && 
         !hasflag($self,"WIZARD")) {
         return err($self,$prog,"Permission denied");
      }
         

      necho(self   => $self,
            prog   => $prog,
            source => [ set_flag($self,$prog,$target,$flag) ]
           );
   } else {
      return err($self,$prog,
                 "Usage: \@set <object>/<attribute> = <value>\n" .
                 "    or \@set <attribute> = <value>\n");
   }
}

sub reconstitute
{
   my ($name,$type,$pattern,$value,$flag,$raw) = @_;

   if($type eq undef) {
      if($flag eq undef) {
         return color("h",uc($name)) . ": $value" if($type eq undef);
      } else {
         return color("h",uc($name)) . "[$flag]: $value" if($type eq undef);
      }
   }

   if($type == 1) {                       # memorydb / mysql don't agree on
      $type = "\$";                               # how the type is defined
   } elsif($type == 2) {
      $type = "^";
   } elsif($type == 3) {
      $type = "!";
   }

   # convert single line unreadable mushcode into hopefully readable
   # multiple line code
   if(!$raw &&
      length($value) > 78 &&
      $value !~ /\n/ &&
      ($pattern ne undef || $value  =~ /^\s*([\$|\[|^|!|@])/)) {
      if($1 eq "[") {
         $value = "\n" . function_print(3,single_line($value));
      } else {
         $value = "\n" . pretty(3,single_line($value));
      }
      $value =~ s/\n+$//;
   }

   if($flag ne undef) {
      return color("h",uc($name)) . "[$flag]: ".$type.$pattern . ":" . $value;
   } else {
      return color("h",uc($name)) . ": $type$pattern:" . $value;
   }
}

sub list_attr_flags
{
   my $attr = shift;
   my $result;

   for my $name (keys %{$$attr{flag}}) {
      $result .= flag_letter($name);
   }
   return $result;
}

sub list_attr
{
   my ($obj,$pattern,$switch) = @_;
   my (@out,$pat,$keys);

   $pat = glob2re($pattern) if($pattern ne undef);

   if(memorydb) {
      for my $name (lattr($obj)) {
         if($pat eq undef || $name =~ /$pat/) {
            if(!reserved($name) && lc($name) ne "description" &&
               ($pat ne undef || !($$obj{obj_id} == 0 && $name =~ /^conf./))) {
                my $attr = mget($obj,$name);
                push(@out,reconstitute($name,
                                       $$attr{type},
                                       $$attr{glob},
                                       $$attr{value},
                                       list_attr_flags($attr),
                                       $$switch{raw}
                                      )
                    );
            }
         }
      }
   } else {
      for my $hash (@{sql($db,
          "   select atr_name, " .
          "          atr_value, " .
          "          atr_pattern, " .
          "          atr_pattern_type, ".
          "          group_concat(distinct fde_letter order by fde_order " .
          "             separator '') atr_flag " .
          "     from attribute atr left join ( " .
          "             select atr_id, fde_letter, fde_order " .
          "               from flag flg, flag_definition fde " .
          "              where flg.fde_flag_id = fde.fde_flag_id " .
          "                and fde_type = 2 " .
          "           ) flg on (atr.atr_id = flg.atr_id) " .
          "    where atr.obj_id = ? " .
          "      and atr_name not in ('DESCRIPTION', " .
          "                           'LOCK_DEFAULT', " . 
          "                           'LAST_WHISPER', " .
          "                           'LAST_PAGE') ".
          " group by atr.atr_id, atr_name " .
          " order by atr.atr_name",
          $$obj{obj_id},
         )}) { 

         if($pat eq undef || $$hash{atr_name} =~ /$pat/) {
            push(@out,reconstitute($$hash{atr_name},
                                   $$hash{atr_pattern_type},
                                   $$hash{atr_pattern},
                                   $$hash{atr_value},
                                   $$switch{raw}
                                  )
                );
         }
      }
   }


   if($#out == -1 && $pattern !~ /^\s*$/) {
      return "No matching attributes";
   } else {
      return join("\n",@out);
   }
}


sub cmd_ex
{
   my ($self,$prog,$txt,$switch) = @_;
#   my ($self,$prog,$txt) = @_;
   my ($target,$desc,@exit,@content,$atr,$out);

   validate_switches($self,$prog,$switch,"raw") || return;

   $txt = evaluate($self,$prog,$txt);

   ($txt,$atr) = ($`,$') if($txt =~ /\//);

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
   } elsif($txt =~ /^\s*(.+?)\s*$/) {
      $target = find($self,$prog,$1) ||
         return err($self,$prog,"I don't see that here.");
   } else {
       return err($self,$prog,"I don't see that here.");
   }


   my $perm = controls($self,$target,1);

   if($atr ne undef) {
      if($perm) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s",list_attr($target,$atr,$switch)],
                     );
      }
      return err($self,$prog,"Permission denied.");
   }

   $out .= obj_name($self,$target,$perm);
   my $flags = flag_list($target,1);

   if($flags =~ /(PLAYER|OBJECT|ROOM|EXIT)/i) {
      $out .= "\n" . color("h","Type") . ": $1  " .
              color("h","Flags") . ": ";
      my $rest = trim($` . $');
      $rest =~ s/\s{2,99}/ /g;
      $out .= $rest;
   } else {
      $out .= "\n" . color("h","Type") . ": *UNKNOWN*  " .
              color("h","Flags") . ": " . $flags;
   }

   $out .= "\n" .
           nvl(get($$target{obj_id},"DESCRIPTION"),
               "You see nothing special."
              );

   my $owner = owner($target);
   $out .= "\n" . color("h","Owner") . ": " . obj_name($self,$owner,$perm) .
           "  " . color("h","Key") . " : " . nvl(lock_uncompile($self,
                                          $prog,
                                          get($target,"OBJ_LOCK_DEFAULT")
                                         ),
                           "*UNLOCKED*"
                          ) .
           "  " . color("h",ucfirst(@info{"conf.money_name_plural"})) .
           ": ". money($target);

   $out .= "\n" . color("h","Created") . ": " . firsttime($target);
   if(hasflag($target,"PLAYER")) {
      if($perm) {
         $out .= "\n".color("h","Firstsite").": " . 
                 short_hn(firstsite($target)) . "\n" .
                 color("h","Lastsite") . ": " . 
                 short_hn(lastsite($target));
      }
      my $last = lasttime($target);

      if($last eq undef) {
         $out .= "\nLast: N/A";
      } else {
         $out .= "\n" . color("h","Last") . ": ". $last;
      }
   }

   if($perm) {                                             # show attributes
      my $attr = list_attr($target,undef,$switch);
      $out .= "\n" . $attr if($attr ne undef);
   }


   for my $obj (lcon($target)) {
      push(@content,obj_name($self,$obj));
   }

   if($#content > -1) {
      $out .= "\n" . color("h","Contents") . ":\n" . join("\n",@content);
   }

   if(hasflag($target,"EXIT")) {
      $out .= "\nSource: " . nvl(obj_name($self,loc_obj($target)),"N/A");
      $out .= "\nDestination: " . nvl(obj_name($self,dest($target)),"*UNLINKED*");
   }

   for my $obj (lexits($target)) {
      push(@exit,obj_name($self,$obj)) if(!hasflag($obj,"DARK"));
   }

   if($#exit >= 0) {
      $out .= "\nExits:\n" . join("\n",@exit);
   }

   if($perm && (hasflag($target,"PLAYER") || hasflag($target,"OBJECT"))) {
      $out .= "\n" . color("h","Home") . ": " .
              obj_name($self,home($target),$perm) .
              "\n" . color("h","Location") . ": " .
              obj_name($self,loc_obj($target),$perm);
   }
   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", $out ]
        );
}



sub cmd_inventory
{
   my ($self,$prog,$txt) = @_;
   my $out;

   my $inv = [ lcon($self) ];

   if($#$inv == -1) {
      $out .= "You are not carrying anything.";
   } else {
      $out = "You are carrying:";
      for my $i (0 .. $#$inv) {
         $out .= "\n" . obj_name($self,$$inv[$i]);
      }
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s\nYou have %s", $out,pennies($self) ],
        );
  
}


#
# cmd_look
#
#    Show the player what is around it.
#
sub cmd_look
{
   my ($self,$prog,$txt) = @_;
   my ($flag,$desc,$target,@exit,$out,$name);
   my $owner = owner_id($self);
   my $perm = hasflag($self,"WIZARD");

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
      return err($self,$prog,"I don't see that here.") if $target eq undef;
   } elsif(!($target = find($self,$prog,evaluate($self,$prog,$txt)))) {
      return err($self,$prog,"I don't see that here.");
   }

   $out = obj_name($self,$target);
   if(($desc = get($$target{obj_id},"DESCRIPTION")) && $desc ne undef) {
      $out .= "\n" . evaluate($target,$prog,$desc);
   } else {
      $out .= "\nYou see nothing special.";
   }

   if(memorydb) {
      for my $obj (lcon($target)) { 
         if(!hasflag($obj,"DARK") &&
            ((hasflag($obj,"PLAYER") && hasflag($obj,"CONNECTED") ||
            !hasflag($obj,"PLAYER"))) &&
            $$obj{obj_id} ne $$self{obj_id}) {

            if(!defined @db[$$obj{obj_id}]) {          # corrupt list, fix
               db_remove_list($target,"obj_content",$$obj{obj_id});
            } else {
               $out .= "\n" . color("h","Contents") . ":" if(++$flag == 1);
               if($$prog{hint} eq "WEB") {
                    $out .= "\n<a href=/look/$$obj{obj_id}/>" . 
                            obj_name($self,$obj,undef,1) . "</a>";
               } else {
                  $out .= "\n" . obj_name($self,$obj);
               }
            }
         }
      }
      for my $obj (lexits($target)) { 
         if($obj ne undef && !hasflag($obj,"DARK")) {
            if($$prog{hint} eq "WEB") {
                push(@exit,
                     "<a href=/look/" . dest($obj) . ">" . 
                     first(name($obj)) .
                     "</a>"
                    );
            } else {
               push(@exit,first(name($obj)));
            }
         }
      }
   } elsif(!hasflag($target,"ROOM") ||
      (hasflag($target,"ROOM") && !hasflag($target,"DARK"))) {
      for my $hash (@{sql($db,
          "select   group_concat(distinct fde_letter " .
          "                      order by fde_order " .
          "                      separator '') flags, " .
          "         obj.obj_id," .
          "         min(obj.obj_name) obj_name, " .
          "         min(obj.obj_cname) obj_cname, " .
          "         min(" .
          "             case " .
          "                when fde_name in ('EXIT','OBJECT','PLAYER') then " .
          "                   fde_name  " .
          "             END " .
          "            ) obj_type, " .
          "         case  " .
          "            when min(sck.sck_socket) is null then " .
          "               'N' " .
          "            else " .
          "               'Y' " .
          "         END online," .
          "         min(obj.obj_owner) obj_owner,".
          "         min(con.con_dest_id) con_dest_id ".
          "    from content con, " .
          "         (  select fde.fde_order, obj_id, fde_letter, fde_name " .
          "              from flag flg, flag_definition fde " .
          "             where fde.fde_flag_id = flg.fde_flag_id " .
          "               and flg.atr_id is null " .
          "               and fde_type = 1 " .
          "             union all " .
          "            select 999 fde_order, obj_id, 'c' fde_letter, " .
          "                   'CONNECTED' fde_name ".
          "              from socket sck " .
          "         ) flg, " .
          "         object obj left join (socket sck) " .
          "            on ( obj.obj_id = sck.obj_id)  " .
          "   where con.obj_id = obj.obj_id " .
          "     and flg.obj_id = con.obj_id " .
          "     and con.con_source_id = ? ".
          "     and con.obj_id != ? " .
          "group by con.obj_id, con_created_date " .
          "order by con_created_date desc",
          $$target{obj_id},
          $$self{obj_id}
         )}) {
   
          # skip non-connected players
          next if($$hash{obj_type} eq "PLAYER" && $$hash{online} eq "N");

          if($$hash{obj_cname} ne undef) {
             $$hash{obj_name} = $$hash{obj_cname};
          }
   
          if($$hash{obj_type} eq "EXIT") {                   # store exits for
             if($$hash{flag} !~ /D/) {                                 # later
                if($$prog{hint} eq "WEB") {
                   push(@exit,
                        "<a href=/look/$$hash{con_dest_id}>" . 
                        first($$hash{obj_name}) .
                        "</a>"
                       );
                } else {
                   push(@exit,first($$hash{obj_name}));
                }
             }
          } elsif($$hash{obj_type} =~ /^(PLAYER|OBJECT)$/ && 
                 $$hash{flags} !~ /D/){
             $out .= "\n" . color("h","Contents") . ":" if(++$flag == 1);

             if($$hash{obj_owner} == $owner || $perm) {
                 $name = "$$hash{obj_name}(#$$hash{obj_id}$$hash{flags})";
             } else {
                 $name = "$$hash{obj_name}";
             }
             if($$prog{hint} eq "WEB") {
                 $out .= "\n<a href=/look/$$hash{obj_id}/>$name</a>";
             } else {
                 $out .= "\n" . $name;
             }
          }
      }
   }
   $out .= "\n" . color("h","Exits") . ":\n" . 
            join("  ",@exit) if($#exit >= 0);  # add any exits

   necho(self   => $self,
         prog   => $prog,
         source => ["%s",$out ]
        );

   if(($desc = get($target,"ADESCRIBE")) && $desc ne undef) {
#      my $hint = $$prog{hint};
#      delete @$prog{hint};
      return mushrun(self   => $self,           # handle adesc
                     prog   => $prog,
                     runas  => $target,
                     source => 0,
                     cmd    => $desc
                     );
#      @$prog{hint} = $hint;
   }
}





sub cmd_pose
{
   my ($self,$prog,$txt,$switch,$flag) = @_;

   my $space = ($flag) ? "" : " ";
   my $pose = evaluate($self,$prog,$txt);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s%s%s",name($self),$space,$pose ],
         room   => [ $self, "%s%s%s",name($self),$space,$pose ],
        );
}

sub cmd_set2
{
   my ($self,$prog,$txt) = @_;
#   $txt =~ s/\r\n/<BR>/g;

   if($txt =~ /^\s*([^& =]+)\s+([^ =]+)\s*=(.*?) *$/s) {
      cmd_set($self,$prog,"$2/$1=$3");
   } elsif($txt =~ /^\s*([^ =]+)\s+([^ =]+)\s*$/s) {
      cmd_set($self,$prog,"$2/$1=");
   } elsif($txt =~ /^\s*([^ =]+)\s*=/s) {
      err($self,$prog,"No object specified in &attribute command.");
   } else {
      err($self,$prog,"Unable to parse &attribute command");
   }
}

sub cmd_say
{
   my ($self,$prog,$txt) = @_;

   my $say = evaluate($self,$prog,$txt);

   my $start = time();
   necho(self   => $self,
         prog   => $prog,
         source => [ "You say, \"%s\"",$say ],
         room   => [ $self, "%s says, \"%s\"",name($self),$say ],
        );
}

sub cmd_reload_code
{
   my ($self,$prog,$txt) = @_;

   return err($self,$prog,"Permission denied.") if(!hasflag($self,"WIZARD"));

   my $result = load_all_code(1,@info{filter});
   initialize_functions();
   initialize_commands();

   if($result eq undef) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "No code to load, no changes made." ]
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s loads %s.\n",name($self),$result ]
           );
   }
}


#Player Name        On For Idle  WHO WOULD MAKE THE BEST PRESIDENT?
#Thoran           3d 23:55   1h
#Finrod           4d 04:28  12h
#Dream            4d 09:59   4d  Groot
#Ivos             7d 14:03   2d
#Adrick          16d 18:35   0s
#RedWolf         63d 07:03   7h  The Who
#1234567890123451234567890
#6 Players logged in, 16 record, no maximum.

sub nvl
{
   return (@_[0] eq '') ? @_[1] : @_[0];
}

sub short_hn
{
   my $addr = shift;

   if($addr =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/) {
      return "$1.$2.*.*";
   } elsif($addr =~ /[A-Za-z]/ && $addr  =~ /\.([^\.]+)\.([^\.]+)$/) {
      return "*.$1.$2";
   } else {
      return $addr;
   }
}


#
# cmd_who
#    Show the users who is conected. There is a priviledged version
#    and non-privileged version. The DOING command is just a non-priviledged
#    version of the WHO command.
#
sub cmd_who
{
   my ($self,$prog,$txt) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,$prog,$txt) ]
        );
}

sub cmd_DOING
{
   my ($self,$prog,$txt) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,$prog,$txt,1) ]
        );
}

sub who
{
   my ($self,$prog,$txt,$flag) = @_;
   my ($max,$online,@who,$idle,$count,$out,$extra,$hasperm,$name) = (2,0);

   if(ref($self) eq "HASH") {
      $hasperm = ($flag || !hasflag($self,"WIZARD")) ? 0 : 1;
   } else {
      $hasperm = 0;
   }

   # query the database for connected user, location, and socket
   # details.
   for my $key (sort {@{@connected{$b}}{start} <=> @{@connected{$a}}{start}} 
                keys %connected) {
      my $hash = @connected{$key};
      next if $$hash{raw} != 0;

      # only list users that start with provided text 
      if($$hash{obj_id} ne undef) {
         if(($txt ne undef && 
            lc(substr(name($hash,1),0,length($txt))) eq lc($txt)) ||
            $txt eq undef) {
            if(length(loc($hash)) > length($max)) {
               $max = length(loc($hash));
            }
            push(@who,$hash);
         }
         $online++;
      }
   }
      
   # show headers for normal / wiz who 
   if($hasperm) {
      $out .= sprintf("%-15s%10s%5s %-*s %-4s %s\r\n","Player Name","On For",
                      "Idle",$max,"Loc","Port","Hostname");
   } else {
      $out .= sprintf("%-15s%10s%5s  %s\r\n","Player Name","On For","Idle",
                      defined @info{"conf.doing_header"} ? 
                      @info{"conf.doing_header"} : "\@doing"
                     );
   }

   $max = 3 if($max < 3);

   # generate detail for every connected user
   for my $hash (@who) {
      # determine idle details

      if(defined $$hash{last}) {
         $idle = date_split(time() - @{$$hash{last}}{time});
      } else {
         $idle = { max_abr => 's' , max_val => 0 };
      }

      # determine connect time details
      
      my $online = date_split(time() - fuzzy($$hash{start}));
      if($$online{max_abr} =~ /^(M|w|d)$/) {
         $extra = sprintf("%4s",$$online{max_val} . $$online{max_abr});
      } else {
         $extra = "    ";
      } 
 
      if($$prog{hint} eq "WEB") {
         $name = name($hash);
         $name = "<a href=look/$$hash{obj_id}>$name</a>" .
                 (" " x (15 - ansi_length($name)));
      } else {
         $name = ansi_substr(name($hash),0,15);
         $name = $name . (" " x (15 - ansi_length($name)));
      }

      # show connected user details
      if($hasperm) {
         $out .= sprintf("%s%4s %02d:%02d %4s %-*s %-4s %s%s\r\n",
             $name,$extra,$$online{h},$$online{m},$$idle{max_val} .
             $$idle{max_abr},$max,"#" . loc($hash),$$hash{port},
             short_hn($$hash{hostname}),
             ($$hash{site_restriction} == 69) ? " [HoneyPoted]" : ""
            );
      } elsif($$hash{site_restriction} != 69) {
         $out .= sprintf("%s%4s %02d:%02d %4s  %s\r\n",$name,$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             $$hash{obj_doing});
      }
   }
   $out .= sprintf("%d Players logged in\r\n",$online);        # show totals
   return $out;
}


sub cmd_sweep
{
   my ($self,$prog) = @_;

   necho(self   => $self,
         prog   => $prog,
         source => [ "Sweeping location..." ]
        );
   for my $obj (sql2("select obj.* " .
                    "  from content c1,  " .
                    "       content c2,  " .
                    "       flag flg, " .
                    "       flag_definition fde, " .
                    "       socket sck," .
                    "       object obj ". 
                    " where c1.con_source_id = c2.con_source_id " .
                    "   and obj.obj_id = c1.obj_id " .
                    "   and flg.obj_id = c1.obj_id " .
                    "   and flg.fde_flag_id = fde.fde_flag_id " .
                    "   and fde.fde_Name in ('LISTENER','PUPPET','PLAYER') " .
                    "   and ( sck.obj_id = c1.obj_id " .
                    "         or obj.obj_owner = sck.obj_id " .
                    "       ) " .
                    "   and c2.obj_id = ?",
                    $$self{obj_id}
                   )
               ) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "   %s is listening.", obj_name($self,$$obj{obj_id}) ],
           );
    }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Sweep complete." ]
        );
}
# #!/usr/bin/perl
# 
# tm_cache.pl
#    Routines which directly impliment/modify the cache. All functions
#    need to keep track of when they were last modified to drtermine if
#    the data is old and can be removed.
#

use strict;

#
# incache
#    Determine in the specified item is in the cache or not
#
sub incache
{
   my ($obj,$item) = (obj(shift),trim(uc(shift)));

   return undef if(!defined $cache{$$obj{obj_id}});
   return (defined $cache{$$obj{obj_id}}->{$item}->{value}) ? 1 : 0;
}

#
# set_cache
#    Store the value in the cache for later use
#
sub set_cache
{
   my ($obj,$item,$val) = (obj(shift),trim(uc(shift)),shift);

   if($val eq undef) {
      delete $cache{$$obj{obj_id}}->{$item} if(defined $cache{$$obj{obj_id}});
   } else {
      $cache{$$obj{obj_id}}->{$item}->{ts} = time();
      $cache{$$obj{obj_id}}->{$item}->{value} = $val;
   }
}

#
# cache
#    Return the cached value
#
sub cache
{
   my ($obj,$item) = (obj(shift),trim(uc(shift)));

   $cache{$$obj{obj_id}}->{$item}->{ts} = time();
   return $cache{$$obj{obj_id}}->{$item}->{value};
}

#
# incache_atrflag
#    Determine if an atr flag is in the cache or not. This has an additional
#    level, so it can't be handled by the standard cache functions.
#
sub incache_atrflag
{
   my ($obj,$atr,$flag) = (obj(shift),trim(uc(shift)),shift);

   return undef if(!defined $cache{$$obj{obj_id}});
   return (defined $cache{$$obj{obj_id}}->{$atr}->{$flag}->{value}) ? 1 : 0;
}

sub set_cache_atrflag
{
   my ($obj,$atr,$flag,$val)=(obj(shift),trim(uc(shift)),shift,shift);

   if($val eq undef) {
      delete $cache{$$obj{obj_id}}->{$atr}->{$flag};
   } else {
      $cache{$$obj{obj_id}}->{$atr}->{$flag}->{ts} = time();
      $cache{$$obj{obj_id}}->{$atr}->{$flag}->{value} = $val;
   }
}

sub remove_flag_cache
{
   my ($object, $flag) = (obj(shift),uc(shift));

   set_cache($object,"FLAG_$flag");
   set_cache($object,"FLAG_LIST_0");
   set_cache($object,"FLAG_LIST_1");

   if($flag eq "WIZARD") {
      my $owner = owner($object);
      for my $obj (keys %{$cache{$owner}->{FLAG_DEPENDANCY}}) {
         delete @cache{$obj};
      }
      delete $cache{$$object{obj_id}}->{FLAG_DEPENDANCY};
   }
}

sub cache_atrflag
{
   my ($obj,$atr,$flag) = (obj(shift),trim(uc(shift)),trim(uc(shift)));

   $cache{$$obj{obj_id}}->{$atr}->{$flag}->{ts} = time();
   return $cache{$$obj{obj_id}}->{$atr}->{$flag}->{value}
}


sub atr_case
{
   my ($obj,$atr) = (obj(shift),shift);

   if(ref($obj) ne "HASH" || !defined $$obj{obj_id}) {
     return undef;
   } elsif(memorydb) {
      my $attr = mget($obj,$atr);
      if(!defined $$attr{flag} || !defined @{$$attr{flag}}{case}) {
         return 0;
      } else {
         return 1;
      }
   } elsif(!incache_atrflag($obj,$atr,"CASE")) {
      my $val = one_val("select count(*) value " .
                        "  from attribute atr, " .
                        "       flag flg, " .
                        "       flag_definition fde " .
                        " where atr.obj_id = flg.obj_id ".
                        "   and fde.fde_flag_id = flg.fde_flag_id ".
                        "   and fde_name = 'CASE' ".
                        "   and fde_type = 2 ".
                        "   and atr_name = ? " .
                        "   and atr.atr_id = flg.atr_id " .
                        "   and atr.obj_id = ? ",
                        $atr,
                        $$obj{obj_id}
                       );
      set_cache_atrflag($obj,$atr,"CASE",$val);
   }
   return cache_atrflag($obj,$atr,"CASE");
}

sub latr_regexp
{
   my ($obj,$type) = (obj(shift),shift);
   my @result;

   if(memorydb) {
      return undef if !valid_dbref($obj);
      for my $name ( lattr($obj) ) {
         my $attr = mget($obj,$name);
         if(defined $$attr{type} && defined $$attr{regexp}) {
            if(($type == 1 && $$attr{type} eq "\$")  ||
               ($type == 2 && $$attr{type} eq "^")  ||
               ($type == 3 && $$attr{type} eq "!")) { 
               push(@result,{ atr_regexp => $$attr{regexp},
                              atr_value  => $$attr{value},
                              atr_name   => $name
                            }
                   );
            }
         }
      }
      return @result;
   } elsif(!incache($obj,"latr_regexp_$type")) {
      for my $atr (@{sql("select atr_name, atr_regexp, atr_value ".
                         "  from attribute atr ".
                         " where obj_id = ? ".
                         "   and atr_regexp is not null ".
                         "   and atr_pattern_type = $type ",
                         $$obj{obj_id}
                        )
                   }) { 
         push(@result, { atr_regexp => $$atr{atr_regexp},
                         atr_value  => $$atr{atr_value},
                         atr_name   => $$atr{atr_name}
                       }
             );
      }
      set_cache($obj,"latr_regexp_$type",\@result);
   }

   return @{cache($obj,"latr_regexp_$type")};
}


sub lcon
{
   my $object = obj(shift);
   my @result;


   if(memorydb) {
      my $attr = mget($object,"obj_content");

      if($attr eq undef) {
         return @result;
      } else {
         for my $id ( keys %{$$attr{value}} ) {
            push(@result,obj($id));
         }
         return @result;
      }
   } elsif(!incache($object,"lcon")) {
       my @list;
       for my $obj (@{sql($db,
                          "select con.obj_id " .
                          "  from content con, " .
                          "       flag flg, ".
                          "       flag_definition fde " .
                          " where con.obj_id = flg.obj_id " .
                          "   and flg.fde_flag_id = fde.fde_flag_id ".
                          "   and fde.fde_name in ('PLAYER','OBJECT') ".
                          "   and con_source_id = ? ",
                          $$object{obj_id},
                    )}) {
          push(@list,{ obj_id => $$obj{obj_id}});
       } 
       set_cache($object,"lcon",\@list);
   }
   return @{ cache($object,"lcon") };
}

sub lexits
{
   my $object = obj(shift);
   my @result;

   if(memorydb) {
      my $attr = mget($object,"obj_exits");

      if($attr eq undef) {
         return @result;
      } else {
         for my $id ( keys %{$$attr{value}} ) {
            push(@result,obj($id));
         }
         return @result;
      }
   } elsif(!incache($object,"lexits")) {
       my @list;
       for my $obj (@{sql($db,
                          "select con.obj_id " .
                          "  from content con, " .
                          "       flag flg, ".
                          "       flag_definition fde " .
                          " where con.obj_id = flg.obj_id " .
                          "   and flg.fde_flag_id = fde.fde_flag_id ".
                          "   and fde.fde_name = 'EXIT' ".
                          "   and con_source_id = ? ",
                          $$object{obj_id},
                    )}) { 
          push(@list,obj($$obj{obj_id}));
       }
       set_cache($object,"lexits",\@list);
   }
   return @{ cache($object,"lexits") };
}


sub money
{
   my ($target,$flag) = (obj(shift),shift);

   my $owner = owner($target);

   if(memorydb) {
      return get($owner,"obj_money");
   } elsif(!incache($owner,"obj_money")) {
      my $money = one_val("select obj_money value ".
                          "  from object ".
                          " where obj_id = ? ",
                          $$owner{obj_id}
                         );
      $money = 0 if $money eq undef;
      set_cache($owner,"obj_money",$money);
   }

   if($flag) {
      if(cache($owner,"obj_money") == 1) {
         return "1 " . @info{"conf.money_name_singular"};
      } else {
         return cache($owner,"obj_money") .
                " " .
                @info{"conf.money_name_plural"};
      }  
   } else {
      return cache($owner,"obj_money");
   }
}

#
# name
#    Return the name of the object from the database if it hasn't already
#    been pulled.
#
sub name
{
   my ($target,$flag) = (obj(shift),shift);

   if(memorydb) {
      if($flag) {
         return get($target,"obj_name");
      } elsif(get($target,"obj_cname") ne undef) {
         return get($target,"obj_cname");
      } else {
         return get($target,"obj_name");
      }
   } elsif(!incache($target,"obj_name")) {
      my $hash = one("select obj_name, obj_cname ".
                     "  from object ".
                     " where obj_id = ? ",
                     $$target{obj_id}
                    );

      if($flag && $$hash{obj_name} eq undef) {
         return "[<UNKNOWN>]";
      } elsif($flag && $$hash{obj_name} ne undef) {
         return $$hash{obj_name};
      } elsif($$hash{obj_cname} eq undef &&
         $$hash{obj_name} eq undef) {
         return "[<UNKNOWN>]";
      } elsif($$hash{obj_cname} eq undef) {
         set_cache($target,"obj_name",$$hash{obj_name});
      } else {
         set_cache($target,"obj_name",$$hash{obj_cname});
      }
   }
   return cache($target,"obj_name");
}


sub flag_list
{
   my ($obj,$flag) = (obj($_[0]),uc($_[1]));
   my (@list,$array,$connected);
   $flag = 0 if !$flag;

   if(memorydb) {
      my $attr = mget($obj,"obj_flag");

      if($attr eq undef) {
         return undef;
      } else {
         my $hash = $$attr{value};

         # connected really isn't a flag, but should be
         if(defined $$hash{player} && defined @connected_user{$$obj{obj_id}}) {
            push(@list,$flag ? "CONNECTED" : 'C');
         }

         for my $key (keys %$hash) {
            push(@list,$flag ? uc($key) : flag_letter($key));
         }
         return join($flag ? ' ' : '',sort @list);
      }
   } elsif(!incache($obj,"FLAG_LIST_$flag")) {
      my (@list,$array);
      for my $hash (@{sql($db,"select * from ( " .
                              "select fde_name, fde_letter, fde_order" .
                              "  from flag flg, flag_definition fde " .
                              " where flg.fde_flag_id = fde.fde_flag_id " .
                              "   and obj_id = ? " .
                              "   and flg.atr_id is null " .
                              "   and fde_type = 1 " .
                              " union all " .
                              "select distinct 'CONNECTED' fde_name, " .
                              "       'c' fde_letter, " .
                              "       999 fde_order " .
                              "  from socket sck " .
                              " where obj_id = ?) foo " .
                               "order by fde_order",
                              $$obj{obj_id},
                              $$obj{obj_id}
                             )}) {
         push(@list,$$hash{$flag ? "fde_name" : "fde_letter"});
      }

      set_cache($obj,"FLAG_LIST_$flag",join($flag ? " " : "",@list));
   }
   return cache($obj,"FLAG_LIST_$flag");
}

#
# owner
#    Return the owner of an object. Players own themselves for coding
#    purposes but are displayed as being owned by #1.
#
sub owner
{
   my $obj = obj(shift);
   my $owner;

   if(memorydb()) {
      if(!valid_dbref($obj)) {
         return undef;
      } elsif(hasflag($obj,"PLAYER")) {
         return $obj;
      } else {
         return obj(get($obj,"obj_owner"));
      }
   } else {
      if(!incache($$obj{obj_id},"OWNER")) {
         $owner = one_val("select obj_owner value" .
                          "  from object" .
                          " where obj_id = ?",
                          $$obj{obj_id}
                         );
   
         if($owner ne undef) {
            set_cache($$obj{obj_id},"OWNER",$owner);
         } else {
            return undef;
         }
      }
      return obj(cache($$obj{obj_id},"OWNER"));
   }
}

#
# hasflag
#    Return if an object has a flag or not
#
sub hasflag
{
   my ($target,$flag) = (obj(shift),uc(shift));
   my $val;

   if($flag eq "CONNECTED") {                  # not in db, no need to cache
      return (defined @connected_user{$$target{obj_id}}) ? 1 : 0;
   } elsif(!valid_dbref($target)) {
      return 0;
   } elsif(memorydb) {
      $target = owner($target) if($flag eq "WIZARD");

      my $attr = mget($target,"obj_flag");

      if(!defined $$attr{value} || !defined @{$$attr{value}}{lc($flag)}) {
         return 0;
      } else {
         return 1;
      }
   } elsif(memorydb) {
      return 0;
   } elsif(!incache($target,"FLAG_$flag")) {
      if($flag eq "WIZARD") {
         my $owner = owner_id($target);
         $val = one_val($db,"select if(count(*) > 0,1,0) value " .  
                            "  from flag flg, flag_definition fde " .  
                            " where flg.fde_flag_id = fde.fde_flag_id " .
                            "   and atr_id is null ".
                            "   and fde_type = 1 " .
                            "   and obj_id = ? " .
                            "   and fde_name = ? ",
                            $owner,
                            $flag);
         # let owner cache object know its value was used for this object
         $cache{$owner}->{FLAG_DEPENDANCY}->{$$target{obj_id}} = 1;
      } else {
         $val = one_val($db,"select if(count(*) > 0,1,0) value " .
                            "  from flag flg, flag_definition fde " .
                            " where flg.fde_flag_id = fde.fde_flag_id " .
                            "   and atr_id is null ".
                            "   and fde_type = 1 " .
                            "   and obj_id = ? " .
                            "   and fde_name = ? ",
                            $$target{obj_id},
                            $flag);
      }
      set_cache($target,"FLAG_$flag",$val);
   }
   return cache($target,"FLAG_$flag");
}

sub dest
{
    my $obj = obj(shift);

   if(memorydb) {
      return get($obj,"obj_destination");
   } elsif(!incache($obj,"con_dest_id")) {
      my $val = one_val("select con_dest_id value ".
                        "  from content ".
                        " where obj_id = ?",
                        $$obj{obj_id}
                       );
      return undef if $val eq undef;
      set_cache($obj,"con_dest_id",$val);
   }
   return cache($obj,"con_dest_id");
}

sub home
{
   my $obj = obj(shift);

   if(memorydb) {
      return get($obj,"obj_home");
   } elsif(!incache($obj,"home")) {
      my $val = one_val("select obj_home value".
                        "  from object " .
                        " where obj_id = ?",
                        $$obj{obj_id}
                       );
      if($val eq undef) {
         if(defined @info{"conf.starting_room"}) {
            return @info{"conf.starting_room"};
         } else {                          # default to first room created
            $val = one_val("  select obj.obj_id value " .
                           "    from object obj, " .
                           "         flag flg, " .
                           "         flag_definition fde ".
                           "   where obj.obj_id = flg.obj_id " .
                           "     and flg.fde_flag_id = fde.fde_flag_id ".
                           "     and fde.fde_name = 'ROOM' " .
                           "order by obj.obj_id limit 1"
                          );
         }
      }
      set_cache($obj,"home",$val);
   }
   return cache($obj,"home");
}

sub loc_obj
{
   my $obj = obj(shift);

   if(memorydb) {
      my $loc = get($obj,"obj_location");
      return ($loc eq undef) ? undef : obj($loc);
   } elsif(!incache($obj,"con_source_id")) {
      my $val = one_val("select con_source_id value " .
                        "  from content " .
                        " where obj_id = ?",
                        $$obj{obj_id}
                       );
      set_cache($obj,"con_source_id",$val);
   }

   if(cache($obj,"con_source_id") eq undef) {
      return undef;
   } else {
      return { obj_id => cache($obj,"con_source_id") };
   }
}

sub lattr
{
   my $obj = obj(shift);

   if(mysqldb) {
      my @result;
      for my $atr (@{sql("select atr_name ".
                         "  from attribute ".
                         " where obj_id = ? ",
                         $$obj{obj_id})}) {
         push(@result,$$atr{atr_name});
      }
      return @result;
   } elsif(memorydb) {
      return () if(!valid_dbref($obj));
      my $hash = dbref($obj);
      return ($hash eq undef) ? undef : (keys %$hash);
   } else {
      return ();
   }
}
# #!/usr/bin/perl
#
# tm_ansi.pl
#    Any routines for handling the limited support for ansi characters
#    within TeenyMUSH.
#
use strict;
use MIME::Base64;

#
# conversion table for letters to numbers used in escape codes as defined
# by TinyMUSH, or maybe TinyMUX.
#
my %ansi = (
   x => 30, X => 40,
   r => 31, R => 41,
   g => 32, G => 42,
   y => 33, Y => 43,
   b => 34, B => 44,
   m => 35, M => 45,
   c => 36, C => 46,
   w => 37, W => 47,
   u => 4,  i => 7,
   h => 1
);

#
# ansi_debug
#    Convert an ansi string into something more readable.
#
sub ansi_debug
{
    my $txt = shift;

    $txt =~ s/\e/<ESC>/g;
    return $txt;
}
#
# ansi_add
#   Add a character or escape code to the data array. Every add of a
#   character results in a new element, escape codes are added to existing
#   elements as long as a character has not been added yet. The ansi state
#   is also kept track of here.
#
sub ansi_add
{
   my ($data,$type,$txt) = @_;

   if(ref($data) ne "HASH"   ||                           # insanity check
      !defined $$data{ch}    ||
      !defined $$data{state} ||
      !defined $$data{code}  ||
      !defined $$data{ch}) {
      croak("Invalid data structure provided");
   }

   my $ch   = $$data{ch};                      # make things more readable
   my $code = $$data{code};
   my $snap = $$data{snap};

   # $ch will be the controlling array
   if($#$ch == -1 || $$ch[$#$ch] ne undef) {
      $$ch[$#$ch+1] = undef;
      $$code[$#$ch] = [];
      $$snap[$#$ch] = [];
   }
   
   if(!$type) {                                           # add escape code
      push(@{$$code[$#$ch]}, $txt);

      if(substr($txt,1,3) eq "[0m") {
         $$data{state} = [];
      } else {
         push(@{$$data{state}},$txt);            # keep track of current state
      }
   } else {                                                 # add character
      $$ch[$#$ch] = $txt;
      $$snap[$#$ch] = [ @{@$data{state}} ];  # copy current state to char
   }
   return length($txt);
}

#
# ansi_init
#    Read in a string and convert it into a data structure that can be
#    easily parsed / modified, i hope. 
#
#     {
#       code => [ [ array of arrays containing escape codes ] ]
#       ch   => [ Array containing each character one by one ]
#       snap => [ [ array of arrays containing all active escape codes 
#                   at the time the character was encountered ] ]
#       state=> [ internal, current state of active escape does ]
#     }
#
sub ansi_init
{
   my $str = shift;
   my $data = {
      ch     => [],
      code   => [],
      state  => [],
      snap   => []
   };

   for(my ($len,$i)=(length($str),0);$i < $len;) {
       if(ord(substr($str,$i,1)) eq 27) {                      # found escape
          my $sub = substr($str,$i+1);

          # parse known escape sequences
          if($sub =~ /^\[([\d;]*)([a-zA-Z])/) {
             $i += ansi_add($data,0,chr(27) . "[" . $1 . $2);
          } elsif($sub =~ /^([#O\(\)])([a-z0-9])/i) {
             $i += ansi_add($data,0,chr(27) . $1 . $2);
          } elsif($sub =~ /^(\[{0,1})([\?0-9]*);([0-9]*)([a-z])/i) {
             $i += ansi_add($data,0,chr(27) . $1 . $2 . ";" . $3 . $4);
          } elsif($sub =~ /^(\[{0,1})([\?0-9]*)([a-z])/i) {
             $i += ansi_add($data,0,chr(27) . $1 . $2 . $3);
          } elsif($sub =~ /^([\<\=\>78])/) {
             $i += ansi_add($data,0,chr(27) . $1);
          } elsif($sub =~ /^\/Z/i) {
             $i += ansi_add($data,0,chr(27) . "\/Z");
          } else {
             $i++;                   # else ignore non-known escape codes
          }
      } else {
         $i += ansi_add($data,1,substr($str,$i,1));          # non-escape code
      }
   }
   return $data;
}

#sub ansi_debug
#{
#   my @array = @_;
#   my $result;
#
#   for my $i (0 .. $#array) {
#      $result .= "<ESC>" . substr(@array[$i],1);
#   }
#   return $result;
#}

#
# ansi_string
#    Take ansi data structure and return 
#        type => 0 : everything but the escape codes
#        type => 1 : original string [including escape codes]
#
sub ansi_string
{
   my ($data,$type) = @_;
   my $buf;

   for my $i (0 .. $#{$$data{ch}}) {
      $buf .= join('', @{@{$$data{code}}[$i]}) if($type);
      $buf .= @{$$data{ch}}[$i];
   }
   return $buf;
}

#
# ansi_substr
#    Do a substr on a string while preserving the escape codes.
#
sub ansi_substr
{
   my ($txt,$start,$count) = @_;
   my ($result,$data,$last);

   $start = 0 if($start !~ /^\s*\d+\s*$/);                  # sanity checks
   if($count !~ /^\s*\d+\s*$/) {
      $count = $start;
   } else {
      $count += $start;
   }
   return undef if($start < 0);                         # no starting point


   if(ref($txt) eq "HASH") {
      $data = $txt;
   } else {
      $data = ansi_init($txt);
   }

   # loop through each "character" w/attached ansi codes
   for(my $i = $start;$i < $count && $i <= $#{$$data{ch}};$i++) {

      my $code=join('',@{@{$$data{($i == $start) ? "snap" : "code"}}[$i]});
      $result .= $code . @{$$data{ch}}[$i];
      $last = $#{@{$$data{snap}}[$i]};
   }

   # are attributes turned on on last character? if so, reset them.
   return $result . (($last == -1) ? "" : (chr(27) . "[0m"));
}

#
# ansi_length
#    Return the length of a string without counting all those pesky escape
#    codes.
#
sub ansi_length
{
   my $txt = shift;

   my $data = ansi_init($txt);

   if($#{$$data{ch}} == -1) {                                       # empty
      return 0;
   } elsif(@{$$data{ch}}[-1] eq undef) {               # last char pos empty?
      return $#{$$data{ch}};
   } else {
      return $#{$$data{ch}} + 1;                        # last char populated
   }
}

sub color
{
   my ($codes,$txt) = @_;
   my $pre;

   for my $ch (split(//,$codes)) {
      if(defined @ansi{$ch}) {
         $pre .= "\e[@ansi{$ch};1m";
      } elsif(defined @ansi{$ch}) {
         $pre .= "\e[@ansi{$ch}m";
      }
   }
   return $pre . $txt . "\e[0m";
}


#
# ansi_remove
#    remove any escape codes from the string
#
sub ansi_remove
{
#   my $txt = ansi_init(shift);
#   return ansi_print($txt,0);

   my $txt = shift;
   $txt =~ s/\e\[[\d;]*[a-zA-Z]//g;
   return $txt;
}

sub space_scan
{
   my ( $data, $start )= @_;

   for my $i ( $start .. $#{$$data{ch}}) {
      return $i if(@{$$data{ch}}[$i] ne " ");
   }
   return $#{$$data{ch}};
}

sub ansi_wrap
{
   my $rules = {
      max_x => 79,
      max_word => 25,
   };

   my $txt = ansi_init(shift);
   my $str = $$txt{ch};
   my ($start,$word_end,$i,$out) = (0,0,0,undef);

   while($i < $#$str) {
      if($i - $start >= $$rules{max_x}) {
         if($i - $word_end >= $$rules{max_word}) {       # split at screen
            $out .= ansi_substr($txt,$start,$i-$start) . "\n";
            $i = space_scan($txt,$i);
            $start = $i;
         } else {                                             # split at word
            $out .= ansi_substr($txt,$start,$word_end-$start) . "\n";
            $i = space_scan($txt,$word_end + 1);
            $start = $i;
         }
         $word_end = $start + 1;
      } elsif($$str[$i] eq " " && ($i == 0 || $$str[$i-1] ne " ")) {
         $word_end = $i;
         $i++;
      }  else {
         $i++;
      }
   }

   if($start < $#$str) {
      $out .= ansi_substr($txt,$start,$#$str);
   }

   return $out;
}

sub lord
{
   my $txt = shift;

   $txt =~ s/\e/<ESC>/g;
   return $txt;
}

# open(FILE,"iweb") ||
#    die("Could not open file iweb for reading");
#  
# while(<FILE>) {
#    s/\r|\n//g;
# #   if(/This/) {
#      printf("%s\n",ansi_wrap($_));
# #   }
# }
# close(FILE);


#my $str = "[32;1m|[0m [1m[34;1m<*>[0m [32;1m|[0m [31;1mA[0m[31ms[0m[31mh[0m[31me[0m[31mn[0m[33;1m-[0m[31;1mS[0m[31mh[0m[31mu[0m[31mg[0m[31mar[0m                   [32;1m|[0m Meetme(#260V)                        [32;1m|[0m";

#for my $i (0 .. 78) {
#   printf("%0d : '%s'\n",$i,ansi_length(ansi_substr($str,$i,7)));
#}

#my $str = decode_base64("CiAgICAtLS0tLS0tLS0tLS0tLS0gICAgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQogMSB8LnwufC58LnwufC58LnwufCAgfCAgICAgICBUYW86IFRoaXMgQWluJ3QgT3RoZWxsbyAgICAgICB8CiAyIHwufC58T3xPfC58LnwufC58ICB8ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHwKIDMgfC58I3xPfE98I3xPfC58LnwgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfAogNCB8LnwufCN8T3xPfC58LnwufCAgfCAgIzogV2ViT2JqZWN0ICAgICAgICBoYXMgIDYgcGllY2VzICB8CiA1IHwufCN8T3xPfE98T3wufC58ICB8ICBPOiAbWzM0bUFkcmljaxtbMG0bW20gICAgICAgICAgIGhhcyAxMSBwaWVjZXMgIHwKIDYgfC58LnwufCN8LnwjfC58LnwgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfAogNyB8LnwufC58LnwufC58LnwufCAgfCAgICoqKiBJdCBpcyBXZWJPYmplY3QncyB0dXJuICoqKiAgICB8CiA4IHwufC58LnwufC58LnwufC58ICB8ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHwKICAgIC0tLS0tLS0tLS0tLS0tLSAgICAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tCiAgICAxIDIgMyA0IDUgNiA3IDhd");



# printf("%s\n",ansi_debug($str));
#my $a = ansi_init($str);
#printf("%s\n",$str);
#printf("%s\n",lord(ansi_string($a,1)));
#printf("SUB:%s\n",ansi_substr($a,11,1));

# #!/usr/bin/perl
#
# tm_db.pl
#    Code specific to the memory database. The only mysql database code
#    in here should be specific to conversion from one format to the
#    other.
#
#    flag definitions are loaded here since they're stored inside the
#    mysql database. They probably should be removed from the database
#    since we don't need two versions of the same thing.


use Compress::Zlib;
use strict;
use MIME::Base64;
use Storable qw(dclone);

# flag definitions
#    flag name, 1 character flag name, who can set it, if its an 
#    attribute flag (2), or an object flag (1).
#
my %flag = (
   ANYONE         => { letter => "+",                   type => 1 },
   GOD            => { letter => "G", perm => "GOD",    type => 1 },
   WIZARD         => { letter => "W", perm => "GOD",    type => 1 },
   PLAYER         => { letter => "P", perm => "GOD",    type => 1 },
   ROOM           => { letter => "R", perm => "GOD",    type => 1 },
   EXIT           => { letter => "e", perm => "GOD",    type => 1 },
   OBJECT         => { letter => "o", perm => "GOD",    type => 1 },
   LISTENER       => { letter => "M", perm => "!GUEST", type => 1 },
   SOCKET_PUPPET  => { letter => "S", perm => "WIZARD", type => 1 },
   PUPPET         => { letter => "p", perm => "!GUEST", type => 1 },
   GUEST          => { letter => "g", perm => "WIZARD", type => 1 },
   SOCKET_INPUT   => { letter => "I", perm => "WIZARD", type => 1 },
   DARK           => { letter => "D", perm => "!GUEST", type => 1 },
   CASE           => { letter => "C", perm => "!GUEST", type => 2 },
   NOSPOOF        => { letter => "N", perm => "!GUEST", type => 1 },
   VERBOSE        => { letter => "v", perm => "!GUEST", type => 1 },
   MONITOR        => { letter => "M", perm => "WIZARD", type => 1 },
   SQL            => { letter => "Q", perm => "WIZARD", type => 1 },
   ABODE          => { letter => "A", perm => "!GUEST", type => 1 },
   LINK_OK        => { letter => "L", perm => "!GUEST", type => 1 },
   ENTER_OK       => { letter => "E", perm => "!GUEST", type => 1 },
   VISUAL         => { letter => "V", perm => "!GUEST", type => 1 },
   ANSI           => { letter => "X", perm => "!GUEST", type => 1 },
   LOG            => { letter => "l", perm => "WIZARD", type => 1 },
);

#
# db_version
#    Define which version of the database the mush is dumping. This
#    should be incremented when anything changes.
#
sub db_version
{
   return "1.0";
}


#
# mget
#    Get a record from the memory database. This will return the hash that
#    contains the data. You'll need to look at the value hash item for the
#    actual contents of the attribute. The attribute flag(s) are also
#    accessible here.
#   
#    This function also honors the backup mode and @deleted by grabbing
#    the data from either @delta (contains any changes) or @db (actual
#    database). @deleted defines if the object was deleted while the
#    database was in backup mode.
#
sub mget
{
   my ($obj,$attr) = (obj(shift),shift);
   my $data;

   # handle if object exists
   if(defined @info{backup_mode} && @info{backup_mode}) {
      if(defined @deleted{$$obj{obj_id}}) {                # obj was deleted
         return undef;
      } elsif(defined @delta[$$obj{obj_id}]) {   # obj changed during backup
         $data = @delta[$$obj{obj_id}];
      } elsif(defined @db[$$obj{obj_id}]) {                   # in actual db
         $data = @db[$$obj{obj_id}];
      } else {                                           # obj doesn't exist
         return undef;
      }
   } elsif(defined @db[$$obj{obj_id}]) {            # non-backup mode object
      $data = @db[$$obj{obj_id}];
   } else {
      return undef;                                      # obj doesn't exist
   }

   # handle if attribute exits on object
   if(!defined $$data{lc($attr)}) {              # check if attribute exists
      return undef;                                                   # nope
   } else {
      return $$data{lc($attr)};                                     # exists
   }
}

#
# db_delete
#    Clean up an object if needed. This could cause problems if
#    used to delete an object but currently it is only used to 
#    clean up an object. This means there will always be a new
#    object in @delta... or the code crashed and burned and its
#    okay to use @db.
#
sub db_delete
{
   my $id = obj(shift);
  
   if(defined @info{backup_mode} && @info{backup_mode}) {  # in backup mode
      delete @delta[$id] if(defined @delta[$id]);
      @deleted{$id} = 1;
   } elsif(defined @db[$id]) {                       # non-backup mode delete
      delete @db[$id];
   }
}

#
# dbref_mutate
#    Get an object's hash table reference and make a copy of it in @delta
#    if it already hasn't. This should only be called if the object is
#    going to be changed.
#    
sub dbref_mutate
{
   my $obj = obj(shift);

   if($$obj{obj_id} =~ /^hash/i) {
      printf("BAD!\n");
   }
   if(defined @info{backup_mode} && @info{backup_mode}) {
      if(defined @deleted{$$obj{obj_id}}) {
         return undef;
      } elsif(defined @delta[$$obj{obj_id}] && 
              ref(@delta[$$obj{obj_id}]) eq "HASH") {
         return @delta[$$obj{obj_id}];
      } elsif(defined @db[$$obj{obj_id}] && ref(@db[$$obj{obj_id}]) eq "HASH") {
         @delta[$$obj{obj_id}] = dclone(@db[$$obj{obj_id}]);
         return @delta[$$obj{obj_id}];
      } else {
         return undef;
      }
   } elsif(defined @db[$$obj{obj_id}] && ref(@db[$$obj{obj_id}]) eq "HASH") {
      return @db[$$obj{obj_id}];
   } else {
      @db[$$obj{obj_id}] = {};
      return @db[$$obj{obj_id}];
   }
}

#
# dbref
#    Return the hash table entry for an object. The code should not be
#    making changes to this data.
#
sub dbref
{
   my $obj = obj(shift);

   if(defined @info{backup_mode} && @info{backup_mode}) {
      if(defined @deleted{$$obj{obj_id}}) {
         return undef;
      } elsif(defined @delta[$$obj{obj_id}] && 
              ref(@delta[$$obj{obj_id}]) eq "HASH") {
         return @delta[$$obj{obj_id}];
      } elsif(defined @db[$$obj{obj_id}] && ref(@db[$$obj{obj_id}]) eq "HASH") {
         return @db[$$obj{obj_id}];
      } else {
         return undef;
      }
   } elsif(defined @db[$$obj{obj_id}] && ref(@db[$$obj{obj_id}]) eq "HASH") {
      return @db[$$obj{obj_id}];
   } else {
      return undef;
   }
}

#
# get_next_object
#   return the dbref of the next free object. The assumption is searching the
#    entire db would be bad.
#   
sub get_next_dbref
{

   if($#free > -1) {                        # prefetched list of free objects
      return pop(@free);
   } elsif(defined @info{backup_mode} && @info{backup_mode}) { # in backupmode
      if($#delta > $#db) {                  # return the largest next number
         return $#delta + 1;                # in @delt or @db
      } else {
         return $#db + 1;
      }
   } else {                                      # return next number in @db
      return $#db + 1;
   }
}

#
# can_set_flag
#    Return if an object can set the flag in question
#
sub can_set_flag
{
   my ($self,$obj,$flag) = @_;

   $flag = trim($') if($flag =~ /^\s*!/);

   if(!defined @flag{uc($flag)}) {                          # not a flag
      return 0;
   } 

   my $hash = @flag{uc($flag)};

   if($$hash{perm} =~ /^!/) {       # can't have this perm flag and set flag
      return (!hasflag($self,$')) ? 1 : 0;
   } else {                              # has to have this flag to set flag
      return (hasflag($self,$$hash{perm})) ? 1 : 0;
   }
}

#
# flag_letter
#    Return the single letter associated with the flag. Does this need a
#    function? only when TeenyMUSH is using multiple files because of how
#    code is reloaded. I.e. variables are not exposed to other files but
#    functions are.
#
sub flag_letter
{
   my $txt = shift;

   if(defined @flag{uc($txt)}) {
      return @{@flag{uc($txt)}}{letter};
   } else {
      return undef;
   }
}

#
# flag
#    Is the flag actually a valid object flag or not.
#
sub flag
{
   my $txt = shift;

   if(defined @flag{lc($txt)} && @{@flag{lc($txt)}}{type} == 1) {
      return 1;
   } else {
      return 0;
   }
}

#
# flag_attr
#    Is the flag actually a valid attribute flag or not.
#
sub flag_attr
{
   my $txt = shift;

   if(defined @flag{lc($txt)} && @{@flag{lc($txt)}}{type} == 2) {
      return 1;
   } else {
      return 0;
   }
}

#
# serialize
#    This converts an attribute into a database safe string. Attributes are
#    also reconstituted from multiple segments into one segment as the
#    $commands are pre-parsed.
#
#    This code probably should just handle the very limited number of
#    characters that are problematic. Instead if it finds a character of
#    concern, the whole string is mime encoded... which introduces a bit
#    of overhead. Putting a compress() around the string could be done
#    as well... but I havn'e gotten myself to pull the trigger on that
#    one for concerns over speed.
#
sub serialize
{
   my ($name,$attr) = @_;
   my ($txt,$flag);

   if(defined $$attr{regexp}) {
      $txt = "$$attr{type}$$attr{glob}:$$attr{value}";
   } else {
      $txt = $$attr{value};
   }

   if(defined $$attr{flag} && ref($$attr{flag}) eq "HASH") {
      $flag = lc(join(',',keys %{$$attr{flag}}));
   }

   if($txt =~ /\r/) { 
      $txt = encode_base64($txt);
      $txt =~ s/\n|\s+//g;
      return "$name:$flag:M:$txt";
   } else {
      return "$name:$flag:A:$txt";
   }
}

sub hash_serialize
{
   my $attr = shift;
   my $out;

   return undef if ref($attr) ne "HASH";

   for my $key (keys %$attr) {
      $out .= ";" if($out ne undef);
      if($$attr{$key} =~ /;/) {
         $out .= "$key:M:" . encode_base64($$attr{$key});
      } else {
         $out .= "$key:A:$$attr{$key}";
      }
   }
   return $out;
}

sub reserved
{
   my $attr = shift;

   if($attr =~ /^obj_/i ||
      $attr =~ /^flag_/i ||
      $attr =~ /^lock_/i) {
      return 1;
   } else {
      return 0;
   }
}


sub db_set
{
   my ($id,$key,$value) = (obj(shift),lc(shift),shift);

   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);

   if($value eq undef) {
      delete @$obj{$key};
      return;
   }

   $$obj{$key} = {} if(!defined $$obj{$key});       # create attr if needed

   my $attr = $$obj{$key};

   # listen/command
   if(!reserved($attr) && $value =~ /([\$\^\!])(.+?)(?<![\\])([:])/) {
      my ($type,$pat,$seg) = ($1,$2,$');
      $pat =~ s/\\:/:/g;
      $$attr{type} = $type;
      $$attr{glob} = $pat;
      $$attr{regexp} = glob2re($pat);
      $$attr{value} = $seg;
   } else {                                                # non-listen/command
      $$attr{value} = $value;                             # set attribute value
   }
}

sub db_set_flag
{
   my ($id,$key,$flag) = (obj(shift),lc(shift),shift);

   return if $flag eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);
   $id = $$id{obj_id} if(ref($id) eq "HASH");

   my $obj = dbref_mutate($id);

   $$obj{$key} = {} if(!defined $$obj{$key});       # create attr if needed

   my $attr = $$obj{$key};

   $$attr{flag} = {} if(!defined $$attr{flag});

   @{$$attr{flag}}{$flag} = 1;
}

sub db_set_list
{
   my ($id,$key,$value) = (obj(shift),lc(shift),lc(shift));

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);

   $$obj{$key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};
   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "list";

   @{$$attr{value}}{$value} = 1;
}

sub db_remove_list
{
   my ($id,$key,$value) = (obj(shift),lc(shift),lc(shift));

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);
   $$obj{key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};
   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "list";

   delete @{$$attr{value}}{$value};
}

sub db_set_hash
{
   my ($id,$key,$value,$sub) = (obj(shift),lc(shift),lc(shift),shift);

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);

   $$obj{$key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};
   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "hash";

   @{$$attr{value}}{$value} = $sub;
}

sub db_remove_hash
{
   my ($id,$key,$value) = (obj(shift),lc(shift),lc(shift));

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);

   $$obj{$key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};
   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "hash";

   delete @{$$attr{value}}{$value};
}


sub db_sql_dump
{
   for my $rec (@{sql("select * from object")}) {
      db_set($$rec{obj_id},"name",$$rec{obj_name});
      db_set($$rec{obj_id},"cname",$$rec{obj_cname});
      db_set($$rec{obj_id},"password",$$rec{obj_password});
      db_set($$rec{obj_id},"owner",$$rec{obj_owner});
      db_set($$rec{obj_id},"created_date",$$rec{obj_created_date});
      db_set($$rec{obj_id},"created_by",$$rec{obj_created_by});
      db_set($$rec{obj_id},"home",$$rec{obj_home});
      db_set($$rec{obj_id},"quota",$$rec{obj_quota});
      db_set($$rec{obj_id},"money",$$rec{obj_money});
   }

   for my $rec (@{sql("select * from attribute")}) {
      my $value;
      if($$rec{atr_pattern_type} == 1) {
         $value = "\$$$rec{atr_pattern}:$$rec{atr_value}";
      } elsif($$rec{atr_pattern_type} == 2) {
         $value = "^$$rec{atr_pattern}:$$rec{atr_value}";
      } elsif($$rec{atr_pattern_type} == 2) {
         $value = "!$$rec{atr_pattern}:$$rec{atr_value}";
      } else {
         $value = $$rec{atr_value};
      }
      db_set($$rec{obj_id},$$rec{atr_name},$value);
   }

   for my $rec (@{sql("select obj_id, " .
                      "       skh_hostname, ".
                      "       skh_start_time, ".
                      "       skh_end_time, ".
                      "       skh_success ".
                      "  from socket_history skh, " .
                      "       object obj " .
                      " where obj.obj_id = skh.obj_id " .
                      "       obj_id >= 0"
               )}) {
      db_set_hash($$rec{obj_id},
                  "lastsite",
                  fuzzy($$rec{skh_start_time}),
                  fuzzy($$rec{skh_end_time}) .
                  ",$$rec{skh_success},$$rec{skh_hostname}"
                 );
   }

                
   for my $rec (@{sql("select obj_id, fde_name, fde_type " .
                      "  from flag flg, flag_definition fde" .
                      " where flg.fde_flag_id=fde.fde_flag_id" .
                      "   and fde_type = 1"
                      )}) {
      
      db_set_list($$rec{obj_id},"flag",$$rec{fde_name});
   }

   for my $rec (@{sql("select atr.obj_id," .
                         "       atr_name, " .
                         "       fde_name " .
                         "  from attribute atr, " .
                         "       flag flg, " .
                         "       flag_definition fde " .
                         " where atr.atr_id = flg.atr_id " .
                         "   and flg.fde_flag_id = fde.fde_flag_id " .
                         "   and fde_type = 2"
                   )}) {
      db_set_flag($$rec{obj_id},$$rec{atr_name},$$rec{fde_name});
   }

   for my $rec (@{sql("select * from content")}) {
      db_set($$rec{obj_id},"obj_location",$$rec{con_source_id});
      if(hasflag($rec,"EXIT")) {
         db_set_list($$rec{con_source_id},"exits",$$rec{obj_id});
         if($$rec{con_dest_id} ne undef) {
            db_set($$rec{obj_id},"obj_destination",$$rec{con_dest_id});
         }
      } else {
         db_set_list($$rec{con_source_id},"obj_content",$$rec{obj_id});
      }
   }

   open(FILE,"> json.txt") ||
      return printf("Could not open json.txt for writing");

   printf(FILE "server: %s, dbversion=%s, exported=%s\n",
      @info{version},@info{dbversion},scalar localtime());
   
   for(my $i=0;$i <= $#db;$i++) {
      printf(FILE "%s",db_object($i));
   }
   close(FILE);
}

sub db_object
{
   my $i = shift;
   my $out;

   if(defined @db[$i]) {
      $out = "obj[$i] {\n";
      my $obj = @db[$i];
      for my $name ( sort keys %$obj ) {
         my $attr = $$obj{$name};
         
         if(reserved($name) && defined $$attr{value} &&
            $$attr{type} eq "list") {
            $out .= "   $name\::L:" . join(',',keys %{$$attr{value}}) . "\n";
         } elsif(reserved($name) && defined $$attr{value} &&
            $$attr{type} eq "hash") {
            $out .= "   $name\::H:" . hash_serialize($$attr{value})."\n";
         } else {
            $out .= "   " . serialize($name,$attr) . "\n";
         }
      }
      $out .= "}\n";
   }
   return $out;
}

sub db_process_line
{
   my ($state,$line) = @_;

   $line =~ s/\r|\n//g;
   $$state{chars} += length($_);
   if($$state{obj} eq undef &&  $line =~
      /^server: ([^,]+), dbversion=([^,]+), exported=([^,]+), type=/) {
      $$state{ver} = $2;
      # header
   } elsif($line =~ /^\*\* Dump Completed (.*) \*\*$/) {
      $$state{complete} = 1;
   } elsif($$state{obj} eq undef && $line =~ /^obj\[(\d+)]\s*{\s*$/) {
      $$state{obj} = $1;
   } elsif($$state{obj} ne undef && $line =~ /^\s*([^ \/:]+):([^:]*):M:/) {
      db_set($$state{obj},$1,decode_base64($'));
      db_set_flag($$state{obj},$1,$2) if($2 ne undef);
   } elsif($$state{obj} ne undef && $line =~ /^\s*([^ \/:]+):([^:]*):A:/) {
      db_set($$state{obj},$1,$');
      db_set_flag($$state{obj},$1,$2) if($2 ne undef);
      $$state{loc} = $' if($1 eq "obj_location");
   } elsif($$state{obj} ne undef && $line =~ /^\s*([^ \/:]+):([^:]*):L:/) {
      my ($attr,$list) = ($1,$');
      for my $item (split(/,/,$list)) {
         db_set_list($$state{obj},$attr,$item);
         if($attr eq "obj_flag" && $item =~ /^\s*(PLAYER|EXIT)\s*$/i) {
            $$state{type} = uc($1);
         }
      }
   } elsif($$state{obj} ne undef && $line =~ /^\s*([^ \/:]+):([^:]*):H:/) {
      my ($attr,$list) = ($1,$');
      for my $item (split(/;/,$list)) {
         if($item =~ /^([^:]+):A:([^;]+)/) {
            db_set_hash($$state{obj},$attr,$1,$2);
         } elsif($item =~ /^([^:]+):M:([^;]+)/) {
            db_set_hash($$state{obj},$attr,$1,decode_base64($2));
         }
      }
   } elsif($$state{obj} ne undef && $line =~ /^\s*}\s*$/) {
      if($$state{type} eq "PLAYER") {
         @player{lc(@{@{@db[$$state{obj}]}{obj_name}}{value})} = $$state{obj};
      }
      delete @$state{obj};
      delete @$state{type};
      delete @$state{loc};
   } else {
      printf("Unable to parse[$$state{obj}]: '%s'\n",$line);
   }
}

sub db_read_string
{
   my ($data) = @_;
   my $state = {};

   return if($#db >= 0);                       # don't re-read the database

   for my $line (split(/\n/,$data)) {
      db_process_line($state,$line);
   }
}

sub db_read
{
   my ($self,$prog,$name) = @_;
   my ($state,$file) = {};

   return if($#db >= 0);                        # don't re-read the database

   open($file,"< $name") ||
      printf("Unable to read file '$name'\n");

   printf("Opening database file: %s\n",$name);

   while(<$file>) {
      db_process_line($state,$_);
   }

   if(!$$state{complete} && arg("forceload")) {
      printf("\n### File %s is not complete, aborting ###\n\n",$name);
      exit(1);
   }
   printf("    Database Version %s -- %s bytes read\n",
          $$state{ver},
          $$state{chars}
         );
   close($file);
}

$SIG{'INT'} = sub {  if(memorydb) {
                        printf("**** Program Exiting ******\n"); 
                        cmd_dump(obj(0),{},"CRASH");
                        @info{crash_dump_complete} = 1;
                        printf("**** Dump Complete Exiting ******\n");
                     }
                     printf("CALLED\n");
                     exit(1);
                  };

END {
   if(memorydb && !defined @info{crash_dump_complete} && $#db > -1) {
      printf("**** Program EXITING ******\n");
      cmd_dump(obj(0),{},"CRASH");
      printf("**** Dump Complete Exiting 2 ******\n");
   }
}

# object {
#    attr {
#       value => 
#       flag => 
#       owner => 
#    }
# }
# #!/usr/bin/perl
#
# tm_engine.pl
#    This file contains any functions required to handle the scheduling of
#    running of mush commands. The hope is to balance the need for socket
#    IO verses the need to run mush commands.
#


use Time::HiRes "ualarm";

sub single_line
{
   my $txt = shift;

   $txt =~ s/\r\s*|\n\s*//g;
   return $txt;
}

sub run_container_commands
{
   my ($self,$prog,$runas,$container,$cmd) = @_;
   my $match = 0;

   for my $obj (lcon($container)) {
      for my $hash (latr_regexp($obj,1)) {
         if($cmd =~ /$$hash{atr_regexp}/i) {
            mushrun(self   => $self,
                    prog   => $prog,
                    runas  => $obj,
                    source => 0,
                    cmd    => single_line($$hash{atr_value}),
                    wild   => [ $1,$2,$3,$4,$5,$6,$7,$8,$9 ],
                    from   => "ATTR"
                   );
            $match=1;                             # signal mush command found
         }
      }
   }
   return $match;
}

#
# mush_command
#   Search Order  is objects you carry, objects around you, and objects in
#   the master room.
#
sub mush_command
{
   my ($self,$prog,$runas,$cmd) = @_;
   my $i =  0;

   for my $obj ($self,loc($self),@info{"conf.master"}) {
      $i += run_container_commands($self,$prog,$runas,$obj,$cmd);
   }
 
   return ($i > 0) ? 1 : 0;
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
      created_by => $self,
      user => $runas,
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
      $arg{pid} = $info{pid};
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
      } elsif($arg{cmd} =~  /^\s*\.\s*$/) {                       # blank line
         push(@$stack,"");
         return;
      } else {                                          # another line of atr
         push(@$stack,$arg{cmd});
         return;
      }
   };

    # copy over command(s)
    my $stack=@{$arg{prog}}{stack};

    if((defined @arg{source} && $arg{source}) || $arg{hint} eq "WEB") {
       $arg{cmd} =~ s/^\s+|\s+$//g;        # no split & add to front of list
       unshift(@$stack,{ runas  => $arg{runas},
                         cmd    => $arg{cmd}, 
                         source => ($arg{hint} eq "WEB") ? 0 : 1,
                         multi  => ($multi eq undef) ? 0 : 1
                       }
              );

#       my %last;
#       my $result = spin_run(\%last,
#                             $arg{prog},
#                             { runas  => $arg{runas},
#                               cmd    => $arg{cmd}, 
#                               source => ($arg{hint} eq "WEB") ? 0 : 1,
#                               multi  => ($multi eq undef) ? 0 : 1
#                             }
#                            );   # run cmd
    } elsif(defined $arg{child} && $arg{child}) {    # add to front of list
       for my $i ( reverse balanced_split($arg{cmd},";",3,1) ) {
          $i  =~ s/^\s+|\s+$//g;
          unshift(@$stack,{runas  => $arg{runas},
                           cmd    => $i,
                           source => 0,
                           multi  => ($multi eq undef) ? 0 : 1
                          }
                 );
       }
   } else {                                             # add to end of list
       for my $i ( balanced_split($arg{cmd},";",3,1) ) {
          $i  =~ s/^\s+|\s+$//g;
          push(@$stack,{runas  => $arg{runas},
                           cmd    => $i,
                           source => 0,
                           multi  => ($multi eq undef) ? 0 : 1
                          }
                 );
        }
    }

    if(defined $arg{wild}) {
       set_digit_variables($arg{self},$arg{prog},@{$arg{wild}}); # copy %0..%9
    }
    
    delete @{$arg{self}}{child};
    return @arg{prog};
}

#
# it was assumed that variables going into %0 - %9 should be
# evaluated. This seems to be not true, so evaluation is currently 
# disabled at this level. The commented code can be removed if it doesn't
# impact things after testing.
#

sub set_digit_variables
{
   my ($self,$prog) = (shift,shift);
   my $hash;


   if(ref($_[0]) eq "HASH") {
      my $new = shift;
      for my $i (0 .. 9) {
#         if($self ne undef) {
#            @{$$prog{var}}{$i} = evaluate($self,$prog,$$new{$i});
#         } else {
            @{$$prog{var}}{$i} = $$new{$i};
#         }
      }
   } else {
      my @var = @_;

      for my $i (0 .. 9 ) {
#         if($self ne undef) {
#            @{$$prog{var}}{$i} = evaluate($self,$prog,$var[$i]);
#         } else {
            @{$$prog{var}}{$i} = $var[$i];
#         }
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
# is_running
#    Return if a program is still running or not
#
sub is_running
{
   my $pid = shift;

   if(!defined @info{engine}) {
      return 0;
   } elsif(defined @{@info{engine}}{$pid}) {
      return 1;
   } else {
      return 0;
   }
}

#
# spin
#    Run one command from each program that is running
#
sub spin
{
   my (%last);
   my $count = 0;

   my $total = 0;
   $SIG{ALRM} = \&spin_done;

   my $start = Time::HiRes::gettimeofday();
   @info{engine} = {} if(!defined @info{engine});

   if(memorydb) {
      if(time()-@info{db_last_dump} > @info{"conf.backup_interval"}) {
          @info{db_last_dump} = time();
          my $self = obj(0);
          mushrun(self   => $self,
                  runas  => $self,
                  source => 0,
                  cmd    => "\@dump",
                  from   => "ATTR",
                  hint   => "ALWAYS_RUN"
                 );
      } elsif(time() - @info{"conf.freefind_last"} > 
              @info{"conf.freefind_interval"}) {
         @info{"conf.freefind_last"} = time();
         if(!defined @info{"conf.freefind_interval"}) {
            @info{"conf.freefind_interval"} = 86400;
         }
         my $self = obj(0);
         mushrun(self   => $self,
                 runas  => $self,
                 source => 0,
                 cmd    => "\@freefind",
                 from   => "ATTR",
                 hint   => "ALWAYS_RUN"
                );
      }
   }

   eval {
       local $SIG{__DIE__} = sub {
          printf("----- [ Crash REPORT@ %s ]-----\n",scalar localtime());
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
       ualarm(30_000_000);                              # die at 8 milliseconds

#      printf("PIDS: '%s'\n",join(',',keys %{@info{engine}}));
      for my $pid (sort { $a cmp $b } keys %{@info{engine}}) {
         my $thread = @{@info{engine}}{$pid};
         my $program = @$thread[0];
         my $command = $$program{stack};
         @info{program} = @$thread[0];
         $$program{pid} = $pid;

         my $sc = $$program{calls};
         $$program{cycles}++;
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

            ualarm(30_000_000);                        # die at 8 milliseconds
            my $result = spin_run(\%last,$program,$cmd,$command);   # run cmd
            ualarm(0);

            shift(@$command) if($result ne "RUNNING");

            my $stack = $$program{stack};            # copy back new commands
            while($#$stack >= 0) {
               unshift(@$command,pop(@$stack));
            }
            $$program{stack} = $tmp;                  # unhide original stack


            # input() returned that there was no data. In a loop, the process
            # probably will waste time checking for more no data. Because of
            # this, we skip to the next program and hope there will be data
            # later.
            if($result eq "RUNNING" && defined $$program{idle}) {
               delete @$program{idle};                # don't remove it and 
               last;
            }
            

            $$program{calls}++;
            $count++;

                                                # stop at 7 milliseconds
            if(Time::HiRes::gettimeofday() - $start >= 1) {
                printf("   Time slice ran long, exiting correctly [%d cmds]\n",
                       $count);
               return;
            }
         }
         if($#$command == -1) { # program is done 
            my $prog = shift(@$thread);
            if($$prog{hint} eq "WEBSOCKET") {
               my $msg = join("",@{@$prog{output}});
               $prog->{sock}->send_utf8(ansi_remove($msg));
           } elsif($$prog{hint} eq "WEB") {
               if(defined $$prog{output}) {
                  http_reply($$prog{sock},join("",@{@$prog{output}}));
               } else {
                  http_reply($$prog{sock},"No data returned");
               }
            }
            close_telnet($prog);
            delete @{@info{engine}}{$pid};
#            printf("# $pid Total calls: %s\n",$$prog{calls});
         }
      }
   };
#   printf("Count: $count\n");
#   printf("Spin: finish -> $count\n");
   printf("Spin: finish -> %s [%s]\n",$count,Time::HiRes::gettimeofday() - $start) if $count > 1;
#   printf("      total: '%s'\n",$total) if $count > 1;


   if($@ =~ /alarm/i) {
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

   # The player is probably disconnected but there are commands in the queue.
   # These orphaned commands are being run against the not logged in commands
   #  set which will crash this function. These commands should just be ignored.
   return if($$hash{cmd} =~ /^CODE\(.*\)$/);

   $$prog{cmd} = $command;
   if(length($cmd) ne 1) {
      while($arg =~ /^\/([^ =]+)( |$)/) {                  # find switches
         @switch{lc($1)} = 1;
         $arg = $';
      }
   }

#   if($type) {
#      printf("RUN: '%s%s'\n",$cmd,$arg);
#   } else {
#      printf("RUN: '%s %s (%s)'\n",$$hash{$cmd},$arg,code());
#   }
#   printf("RUN(%s->%s): '%s%s'\n",@{$$prog{created_by}}{obj_id},@{$$command{runas}}{obj_id},$cmd,$arg);

 
   if(hasflag($$command{runas},"VERBOSE")) {
      my $owner= owner($$command{runas});
      necho(self   => $owner,
            prog   => $prog,
            target => [ $owner,
                        "%s] %s%s", 
                        name($$command{runas}),
                        $cmd,
                        (($arg eq undef) ? "" : " " . $arg) 
                      ]
           );
   }
   
   my $result = &{@{$$hash{$cmd}}{fun}}($$command{runas},$prog,trim($arg),\%switch);
   return $result;
   return &{@{$$hash{$cmd}}{fun}}($$command{runas},$prog,trim($arg),\%switch);
}

sub spin_run
{
   my ($last,$prog,$command,$foo) = @_;
   my $self = $$command{runas};
   my ($cmd,$hash,$arg,%switch);
   ($$last{user},$$last{cmd}) = ($self,$command);
   $$prog{cmd_last} = $command;

# find command set to use
   if($$prog{hint} eq "ALWAYS_RUN") {
      $hash = \%command;                                    # connected users
   } elsif($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET") {
      if(defined $$prog{from} && $$prog{from} eq "ATTR") {
         $hash = \%command;
      } else {
         $hash = \%switch;                                      # no commands
      }
   } elsif($$prog{hint} eq "INTERNAL" || $$prog{hint} eq "WEB") {
      $hash = \%command;
#      delete @$prog{hint};
   } elsif(hasflag($self,"PLAYER") && !loggedin($self)) {
      printf("LOGGEDIN: '%s'\n",$$self{obj_id},loggedin($self));
      printf("%s\n",print_var($self));
      $hash = \%offline;                                     # offline users
   } elsif(defined $$self{site_restriction} && $$self{site_restriction} == 69) {
      $hash = \%honey;                                   # honeypotted users
   } else {
      $hash = \%command;                                    # connected users
   }

   if($$command{cmd} =~ /^\s*([^ \/]+)/) {         # split cmd from args
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
      return run_internal($hash,substr($cmd,0,1),
                          $command,
                          $prog,
                          substr($$command{cmd},1),
                          \%switch,
                          1
                         );
   } elsif(find_exit($self,$prog,$$command{cmd})) {   # handle exit as command
      return &{@{$$hash{"go"}}{fun}}($$command{runas},$prog,$$command{cmd});
   } elsif(mush_command($self,$prog,$$command{runas},$$command{cmd})) {
      return 1;                                   # mush_command runs command
   } else {
      my $match;

#      for my $key (keys %$hash) {              #  find partial unique match
#         if(substr($key,0,length($cmd)) eq $cmd) {
#            if($match eq undef) {
#               $match = $key;
#            } else {
#               $match = undef;
#               last;
#            }
#         }
#      }

      if($match ne undef && lc($cmd) ne "q") {                  # found match
         return run_internal($hash,$match,$command,$prog,$arg);
      } else {                                                     # no match
         return &{@{@command{"huh"}}{fun}}($$command{runas},$prog,$$command{cmd});
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
# #!/usr/bin/perl
#
# tm_find.pl
#    Generic routines to find objects from a player's perspective.
#

sub find_in_list
{
   my ($thing,@list) = @_;
   my ($partial,$dup);

   for my $obj (@list) {
      if(lc(name($obj,1)) eq $thing) {
         return obj($obj);
      } elsif(lc(substr(name($obj,1),0,length($thing))) eq $thing) {
         if($partial eq undef) {
            $partial = $obj;
         } else {
            $dup = 1;
         }
      }
   }

   if($dup) {
      return undef;
   }  elsif($partial ne undef) {
      return obj($partial);
   } else {
      return undef;
   }
}

#
# find
#    Find something in
sub find
{
   my ($self,$prog,$thing) = (shift,shift,trim(lc(shift)));
   my ($partial, $dup);

   if($thing =~ /^\s*#(\d+)\s*$/) {
      return valid_dbref($1) ? obj($1) : undef;
   } elsif($thing =~ /^\s*here\s*$/) {
      return loc_obj($self);
   } elsif($thing =~ /^\s*%#\s*$/) {
      return $$prog{created_by};
   } elsif($thing =~ /^\s*me\s*$/) {
      return $self;
   } elsif($thing =~ /^\s*\*/) {
       my $player = lc(trim($'));
       if(defined @player{$player}) {
          return obj(@player{$player});
       } else {
          return undef
       }
   }

   # search in contents of object
   my $obj = find_in_list($thing,lcon($self));
   return $obj if($obj ne undef);

   # search around object
   my $obj = find_in_list($thing,lcon(loc($self)));
   return $obj if($obj ne undef);

   # search exits around object
   return find_exit($self,$prog,$thing);
}

sub find_exit
{
   my ($self,$prog,$thing) = (obj(shift),shift,trim(lc(shift)));
   my ($partial,$dup);

   if($thing =~ /^\s*#(\d+)\s*$/) {
      return hasflag($1,"EXIT") ? obj($1) : undef;
   }

   for my $obj (lexits(loc($self))) {
      for my $partial (split(';',name($obj,1))) {
         my $part = trim($partial);

         if(lc($part) eq $thing) {
            return obj($obj);
         } elsif(lc(substr($part,0,length($thing))) eq $thing) {
            if($partial eq undef) {
               $partial = $obj;
            } elsif($dup) {
               $dup = 1;
            }
         }
      }
   }
}

sub find_content
{
   my ($self,$prog,$thing) = (obj(shift),shift,trim(lc(shift)));

   if($thing =~ /^\s*#(\d+)\s*$/) {
      return (loc($self) == loc($1)) ? obj($1) : undef;
   }

   my $obj = find_in_list($thing,lcon($self));
   return $obj;
}

sub find_player
{
   my ($self,$prog,$thing) = (obj(shift),shift,trim(lc(shift)));
   my ($partial,$dup);

   if($thing =~ /^\s*#(\d+)\s*$/) {
      return hasflag($1,"PLAYER") ? obj($1) : undef;
   } elsif($thing =~ /^\s*me\s*$/ ) {
      return hasflag($self,"PLAYER") ? $self : undef;
   } elsif($thing =~ /^\s*%#\s*$/) {
      return $$prog{created_by};
   } elsif($thing =~ /^\s*\*/) {
       my $player = lc(trim($'));
       if(defined @player{$player}) {
          return obj(@player{$player});
       } else {
          return undef
       }
   }

   if(memorydb) {
      if(defined @player{lc($thing)}) {
         return obj(@player{lc($thing)});
      } else {
         return find_in_list($thing,values %player);
      }
      return obj($partial);
   } else {
      for my $rec (@{sql("select obj_id, obj_name " .
                         "  from object obj, flag flg, flag_definition fde " .
                         " where obj.obj_id = flg.obj_id " .
                         "   and flg.fde_flag_id = fde.fde_flag_id " .
                         "   and fde.fde_name = 'PLAYER' " .
                         "   and flg.atr_id is null " .
                         "   and fde_type = 1 " .
                         "   and upper(substr(obj_name,1,?)) = ? ",
                         length($thing),
                         uc($thing)
                   )}) {;
         if(lc($$rec{obj_name}) eq lc($thing)) {
            return obj($$rec{obj_id});
         } elsif($partial eq undef) {
            $partial = $$rec{obj_id};
         } else {
            $dup = 1;
         }
      }
      return !$dup ? undef : obj($partial);
   }
}
# #!/usr/bin/perl
#
# tm_format.pl
#    This is a mini mush parser similar to what is used in the main part
#    of TeenyMUSH. The purpose of this parser is to format MUSH code
#    into something more readable.
#

use strict;
use Carp;
use Text::Wrap;
$Text::Wrap::huge = 'overflow';
my $max = 78;

sub code
{
   my $type = shift;
   my @stack;

#   if(Carp::shortmess =~ /#!\/usr\/bin\/perl/) {

   if(!$type || $type eq "short") {
      for my $line (split(/\n/,Carp::shortmess)) {
         if($line =~ /at ([^ ]+) line (\d+)\s*$/) {
            push(@stack,"$2");
         }
      }
      return join(',',@stack);
   } else {
      return Carp::shortmess;
   }
}

#
# these commands are handled differently then other commands.
#
my %fmt_cmd = (
    '@switch' => sub { fmt_switch(@_); },
    '@select' => sub { fmt_switch(@_); },
    '@dolist' => sub { fmt_dolist(@_); },
    '&'       => sub { fmt_amper(@_);  },
    '@while'  => sub { fmt_while(@_);  },
);


#
# balanced_split
#    Split apart a string but allow the string to have "",{},()s
#    that keep segments together... but only if they have a matching
#    pair.
#
sub fmt_balanced_split
{
   my ($txt,$delim,$type,$debug) = @_;
   my ($last,$i,@stack,@depth,$ch,$buf) = (0,-1);

   my $size = length($txt);
   while(++$i < $size) {
      $ch = substr($txt,$i,1);

      if($ch eq "\\") {
         $buf .= substr($txt,$i++,2);
         next;
      } else {
         if($ch eq "(" || $ch eq "{") {                  # start of segment
            $buf .= $ch;
            push(@depth,{ ch    => $ch,
                          last  => $last,
                          i     => $i,
                          stack => $#stack+1,
                          buf   => $buf
                        });
         } elsif($#depth >= 0) {
            $buf .= $ch;
            if($ch eq ")" && @{@depth[$#depth]}{ch} eq "(") {
               pop(@depth);
            } elsif($ch eq "}" && @{@depth[$#depth]}{ch} eq "{") {
               pop(@depth);
            }
         } elsif($#depth == -1) {
            if($ch eq $delim) {    # delim at right depth
               push(@stack,$buf . $delim);
               $last = $i+1;
               $buf = undef;
            } elsif($type <= 2 && $ch eq ")") {                   # func end
               push(@stack,$buf);
               $last = $i;
               $i = $size;
               $buf = undef;
               last;                                      # jump out of loop
            } else {
               $buf .= $ch;
            }
         } else {
            $buf .= $ch;
         }
      }
      if($i +1 >= $size && $#depth != -1) {   # parse error, start unrolling
         my $hash = pop(@depth);
         $i = $$hash{i};
         delete @stack[$$hash{stack} .. $#stack];
         $last = $$hash{last};
         $buf = $$hash{buf};
      }
   }

   if($type == 3) {
      push(@stack,substr($txt,$last));
      return @stack;
   } else {
      unshift(@stack,substr($txt,$last));
      return ($#depth != -1) ? undef : @stack;
   }
}
sub trim
{
   my $txt = shift;

   $txt =~ s/^\s*|\s*$//g;
   return $txt;
}

#
# dprint
#    Return a string that is at the proper "depth". Some generic mush
#    formating is also done here.
#
sub dprint
{
    my ($depth,$fmt,@args) = @_;
    my $out;

    my $txt = sprintf($fmt,@args);

    if($depth + length($txt) < $max) {                # short, copy it as is.
#        $out .= sprintf("%s%s [%s]\n"," " x $depth,$txt,code());
        $out .= sprintf("%s%s\n"," " x $depth,$txt);
                                         # Text enclosed in {}, split apart?
    } elsif($txt =~ /^\s*{\s*(.+?)}\s*([;,]{0,1})\s*$/s) {
        my ($grouped,$ending) = ($1,$2);
        $txt = pretty($depth+3,$grouped);
        $txt =~ s/^\s+//;
        $out .= sprintf("%s{  %s"," " x $depth,$txt);
        $out .= sprintf("%s}%s\n"," " x $depth,$ending);
    } else {                                    # generic text, wrapping it
       # $out .= sprintf("%s%s\n"," " x $depth,$txt);
       $out .= wrap(" " x $depth," " x ($depth+3),$txt) . "\n";
    }
    return $out;
}

#
# fmt_dolist
#    Handle formating for @dolist like
#
#    @dolist list = 
#        @commands
#
sub fmt_dolist
{
    my ($depth,$cmd,$txt) = @_;
    my $out;

    # to short, don't seperate
    if($depth + length($cmd . " " . $txt) < $max) {
       return dprint($depth,$cmd . " " . $txt);
    }

                                               # find '=' at the right depth
    my @array = fmt_balanced_split($txt,"=",3);

    $out .= dprint($depth,"%s %s",$cmd,trim(@array[0]));    # show cmd + list

    if($#array >= 0) {                                 # show commands to run
       $out .= pretty($depth+3,join('',@array[1 .. $#array]));
    }
    return $out;
}

sub fmt_while
{
   my ($depth,$cmd,$txt) = @_;
   my $out;

   if($txt =~ /^\s*\(\s*(.*?)\s*\)\s*{\s*(.*?)\s*}\s*(;{0,1})\s*$/s) {
      $out .= dprint($depth,"%s ( %s ) {",$cmd,$1);
      $out .= pretty($depth+3,$2);
      $out .= dprint($depth,"}%s",$3);
      return $out;
   } else {
      return dprint($depth,"%s",$cmd . " " . $txt);
   }
}

#
# fmt_switch
#   Handle formating for @switch/select
#
#   @select value =
#       text,
#          commands,
#       text,
#          commands
#
sub fmt_switch
{
    my ($depth,$cmd,$txt) = @_;
    my $out;

    # to small, do nothing
    return dprint($depth,"%s %s",$cmd,$txt) if(length($txt)+$depth + 3 < $max);

    # split up command by ','
    my @list = fmt_balanced_split($txt,',',3);
  
    # split up first segment again by "="
    my ($first,$second) = fmt_balanced_split(shift(@list),'=',3);


    my $len = $depth + length($cmd) + 1;                  # first subsegment
    if($len + length($first)  > $max) {                        # multilined
        $first =~ s/=\s*$//g;
       $out .= dprint($depth,
                      "%s %s=",
                      $cmd,
                      substr(noret(function_print($len-3,trim($first))),$len)
                     );
    } else {                                                  # single lined
       $out .= dprint($depth,"%s %s",$cmd,trim($first),code());
    }


    $out .= dprint($depth+3,"%s",$second);               # second subsegment

    # show the rest of the segments at alternating depths
    for my $i (0 .. $#list) {
       my $indent = ($i % 2 == 0) ? 6 : 3;

       if($i % 2 == 1) {
          if($i == $#list) {                        # default test condition
             $out .= dprint($depth+3,"DEFAULT" . ","); 
             $out .= dprint($depth+6,"%s",@list[$i]);
          } else {                                          # test condition
             $out .= dprint($depth+3,"%s",@list[$i]);
          }
       } elsif($depth + $indent + length(@list[$i]) > $max ||     # long cmd
               @list[$i] =~ /^\s*{.*}\s*;{0,1}\s*$/) {
          $out .= pretty($depth+6,@list[$i]);
       } else {                                                  # short cmd
          $out .= dprint($depth + 6,"%s",@list[$i]);
       }
    }

    return $out;
}

sub fmt_amper
{
   my ($depth,$cmd,$txt) = @_;
   my $out;

   if($txt =~ /^([^ ]+)\s+([^=]+)\s*=/) {
      my ($atr,$obj,$val) = ($1,$2,$');

      if(length($val) + $depth < $max) {
         $out .= dprint($depth,"$cmd$txt");
      } elsif($val =~ /^\s*\[.*\]\s*(;{0,1})\s*$/) {
         $out .= dprint($depth,"&$atr $obj=");
         $out .= function_print($depth+3,$val);
      } else {
         $out .= dprint($depth,"%s",$cmd . $txt);
      }       
   }

   return $out;
}

#
# noret
#    Strip the ending return from a string of text.
sub noret
{
   my $txt = shift;
   $txt =~ s/\n$//;
   return $txt;
}

#
# function_print_segment
#    Maybe this function should be called function_print as this
#    function is really just printing out the function.
#
sub function_print_segment
{
   my ($depth,$left,$function,$arguments,$right,$type) = @_;
   my ($mleft,$mright) = (quotemeta($left),quotemeta($right));
   my $len = length("$function.$left( ");
   my $out;

   my @array = fmt_balanced_split($arguments,",",2);
   $function =~ s/^\s+//;                             # strip leading spaces

   #
   # if function is short enough, so leave it alone. However, but it unkown
   # how much of the text to leave alone since there could be more then one
   # function in $arguments. @array has the left over bits and what should 
   # be skipped over... the only downfall is we have to reconstruct the
   # skipped over parts. 
   #
   # FYI This comparison is slighytly wrong, but close
   if($depth + length("$left$function($arguments)$right") - length(@array[0]) < $max) {
      if($mright ne undef) {                 # does the function end right?
         if(@array[0] =~ /^\s*\)$mright/) {
            @array[0] = $';                                          # yes
         } else {
            return (undef, undef, 1);                   # no, umatched "]"
         }
      }

      return (dprint($depth,                    # put together and return it
                     "%s",
                     "$left$function(" . 
                        join('',@array[1 .. $#array])  
                        . ")$right"
                    ),
              "@array[0]",
              0
             );
   }

   $out .= dprint($depth,"%s","$left$function( " . @array[1]);

   my $ident = length("$left$function( ") + $depth;
   for my $i (2 .. $#array) {                      # show function arguments
      $out .= noret(function_print($ident,"@array[$i]")) . "\n";
   }

   $out .= dprint($depth,"%s",")$right");                    # show ending )

   if($mright ne undef) {
      if(@array[0] =~ /^\s*\)$mright/) {
          return ($out,$',0);
      } else {
          return (undef,undef,2);
      }
   } elsif(@array[0] =~ /\s*\)\s*(,)/) {
      return ($out,"$1$'",0);
   } else {
      return (undef,undef,3);
   }
}

# function_print
#    Print out a function as is if short enough, or split it apart
#    into multiple lines.
#
sub function_print
{  
   my ($depth,$txt) = @_;
   my $out;

   if($depth + length($txt) < $max) {                              # too small
      return dprint($depth,"%s",$txt);
   }

   while($txt =~ /^(\s*)([a-zA-Z_]+)\(/s) {
      my ($fmt,$left,$err) = function_print_segment($depth,
                                                 '',
                                                 $2,
                                                 $',
                                                 '',
                                                 2
                                                );
      if($err) {
         return $txt;
      } else {
         $out .= $1 . $fmt;
         $txt = $left;
      }
   }
   return $out if($out ne undef and $txt =~ /^\s*$/);

   @info{debug_count} = 0;

   while($txt =~ /([\\]*)\[([a-zA-Z_]+)\(/s) {
      my ($esc,$before,$after,$unmod) = ($1,$`,$',$2);

      if(length($esc) % 2 == 0) {
          my ($fmt,$left,$err) = function_print_segment($depth,
                                                     '[',
                                                     $unmod,
                                                     $after,
                                                     ']',
                                                     1
                                                    );
          if($err) {
             $out .= $before ."[$unmod(";
             $txt = $after;
          } else {
             $out .= $fmt;
             $txt = $left;
          }
      } else {
          $out .= "[$unmod(";
          $txt = $after; 
      }
   }

   if($txt ne undef) {
      $out =~  s/\n$//;
      return $out . "$txt\n";
   } else {
      return $out . "$txt";
   }

#   } elsif($txt =~ /^\s*\[([a-zA-Z0-9_]+)\((.*)\)(\s*)\]\s*(;{0,1})\s*$/) {
#      $out .= function_print_segment($depth+3,'[',$1,"$2)$3$4",']',1);
#                                                                  # function()
#   } elsif($txt =~  /^\s*([a-zA-Z0-9_]+)\((.*)\)(\s*)(,{0,1})(\s*)$/) {
#      $out .= function_print_segment($depth+3,'',$1,"$2)$3$4$5",'',2);
#   } else {                                                         # no idea?
#      $out .= dprint($depth,"%s",$txt);
#   }
#   return $out;
}

#
# split_commmand
#    Determine what the possible cmd and arguements are.
#
sub split_command
{
    my $txt = shift;

    if($txt =~ /^\s*&/) {
       return ('&',$');
    } elsif($txt =~ /^\s*([^ \/=]+)/) {
       return ($1,$');
    } else {
       return $txt;
    }
}

sub pretty
{
    my ($depth,$txt) = @_;
    my $out;

    if($depth + length($txt) < $max) {
        return (" " x $depth) . $txt;
    }

    for my $txt ( fmt_balanced_split($txt,';',3,1) ) {
       my ($cmd,$arg) = split_command($txt);
       if(defined @fmt_cmd{$cmd}) {
          $out =~ s/\s+$//g;
          $out .= "\n" if $out ne undef;
          $out .= &{@fmt_cmd{$cmd}}($depth,$cmd,$arg);
          $out =~ s/\n+$//g if($depth==3);
       } elsif(defined @fmt_cmd{lc($cmd)}) {
          $out .= &{@fmt_cmd{lc($cmd)}}($depth,$cmd,$arg);
          $out =~ s/\n+$//g if($depth==3);
       } else {
          $out .= dprint($depth,"%s",$txt);
       }
    }

   
    if($depth == 0) {
       return noret($out);
    } else {
       return $out;
    }
}

#
# test code for use outside the mush
#
# my $code = '@select 0=[not(eq(words(first(v(won))),1))],{@pemit %#=Connect 4: Game over, [name(first(v(won)))] has won.},[match(v(who),%#|*)],{@pemit %#=Connect 4: Sorry, Your not playing right now.},[match(first(v(who)),%#|*)],{@pemit %#=Connect 4: Sorry, its [name(before(first(v(who)),|))] turn right now.},[and(isnum(%0),gt(%0,0),lt(%0,9))],{@pemit %#=Connect 4: That is not a valid move, try again.},[not(gte(strlen(v(c[first(%0)])),8))],{@pemit %#=Connect 4: Sorry, that column is filled to the max.},{&who me=[rest(v(who))] [first(v(who))];&won me=[switch(1,u(fnd,%0,add(1,strlen(v(c[first(%0)]))),after(rest(v(who)),|)),%#)];&c[first(%0)] me=[v(c[first(%0)])][after(rest(v(who)),|)];@pemit %#=[u(board,{%n played in column [first(%0)]})];@pemit [before(first(v(who)),|)]=[u(board,{%n played in column [first(%0)]})];@switch [web()]=0,@websocket connect}';
# my $code = '@select 0=[member(type(num(%1)),PLAYER)],@pemit %#=Connect 4: Sorry I dont see that person here.,{&won me=;&who me=%#|# [num(%1)]|O;"%N has challenged [name(num(%1))].;&c1 me=;&c2 me=;&c3 me=;&c4 me=;&c5 me=;&c6 me=;&c7 me=;&c8 me=;@pemit %#=[u(board)];@pemit [num(%1)]=[u(board)]}';
# 
# my $code='&list me=[u(fnd,%0,%1,after(first(v(who)),|))];@select 0=[match(v(who),%#|*)],{@pemit %#=Tao: Sorry, Your not playing right now.},[match(first(v(who)),%#|*)],{@pemit %#=Tao: Sorry, its [name(before(first(v(who)),|))] turn right now.},[u(isval,%0,%1,.)],{@pemit %#=Tao: That is not a valid move, try again.},[words(v(list))],{@pemit %#=Tao: Sorry, that move does not result in a capture.},{&who me=[rest(v(who))] [first(v(who))];@dolist [first(%0)]|[first(%1)] [v(list)] END=@select ##=END,{@pemit %#=[u(board,{%n played [first(%0)],[first(%1)]})];@pemit [before(first(v(who)),|)]=[u(board,{%n played [first(%0)],[first(%1)]})]},{&c[before(##,|)] me=[replace(v(c[before(##,|)]),after(##,|),after(rest(v(who)),|),|)]}}';
# my $code='[setq(0,iter(u(num,3),[u(ck,2,%2,add(%0,##),add(%1,##))][u(ck,3,%2,add(%0,##),%1)][u(ck,4,%2,add(%0,##),add(%1,-##))][u(ck,5,%2,%0,add(%1,-##))][u(ck,6,%2,add(%0,-##),add(%1,-##))][u(ck,7,%2,add(%0,-##),%1)][u(ck,8,%2,add(%0,-##),add(%1,##))]))]';
# my $code='@switch [t(match(get(#5/hangout_list),%1))][match(bus cab bike motorcycle car walk boomtube,%0)]=0*,@pemit %#=Double-check the DB Number. That does not seem to be a viable option.,11,{@tel %#=%1;@wait 1=@remit [loc(%#)]=A bus pulls up to the local stop. %N steps out.},12,{@tel %#=%1;@wait 1=@remit [loc(%#)]=A big yellow taxi arrives. A figure inside pays the tab%, then steps out and is revealed to be %N.},13,{@tel %#=%1;@wait 1=@remit [loc(%#)]=%N arrives in the area%, pedaling %p bicycle.},14,{@tel %#=%1;@wait 1=@remit [loc(%#)]=%N pulls up on %p motorcycle%, kicking the stand and stepping off.},15,{@tel %#=%1;@wait 1=@remit [loc(%#)]=%N pulls up in %p car%, parking and then getting out.},16,{@tel %#=%1;@wait 1=@remit %N walks down the street in this direction.=<an emit>},17,{@tel %#=%1;@wait 1=@remit [loc(%#)]=A boomtube opens%, creating a spiraling rift in the air. After a moment%, %N steps out.},@pemit %#=That method of travel does not seem to exist.';
#my $code ='&won me=[switch(1,u(fnd,%0,add(1,strlen(v(c[first(%0)]))),after(rest(v(who)),|)),%#)]';
#my $code = '[setq(1,)][setq(2,)][setq(3,)][setq(4,)][setq(5,)][setq(6,)][setq(7,)][setq(8,)][setq(9,)][setq(0,)]';
# my $code = '@switch 0=run(@telnet wttr.in 80),say Weather is temporarly unavailible.,{  @var listen=off;@send GET /@%1?0?T HTTP/1.1;@send Host: wttr.in;@send Connection: close;@send User-Agent: curl/7.52.1;@send Accept: */*;@send ;@while ( telnet_open(%{input}) eq 1 ) {@var input = [input()];@switch on-done-%{input}=on-%{listen}-*,@@ ignore,on-done-*out of queries*,{say Weather Website is down [out of queries];@var listen=done},on-done-ERROR*,{say Unknown Location: %1;@var listen=done},on-done-#-1 *,@@ ignore,on-done-Weather report:*,{@var listen=on;@emit %{input}},%{listen}-done-,@@ ignore,%{listen}-done-*,@emit > [decode_entities(%{input})]}';

# 
# 
# printf("%s\n",pretty(3,$code));
# printf("%s\n",function_print(3,$code));
# #!/usr/bin/perl
#
# tm_functions.pl
#    Contains all functions that can be called from within the mush by
#    users.
#
use strict;
use Carp;
use Scalar::Util qw(looks_like_number);
use Math::BigInt;
use POSIX;
use Compress::Zlib;

#
# define which function's arguements should not be evaluated before
# executing the function. The sub-hash defines exactly which argument
# should be not evaluated ( starts at 1 not 0 )
#
my %exclude = 
(
   iter      => { 2 => 1 },
   parse     => { 2 => 1 },
   setq      => { 2 => 1 },
   switch    => { all => 1 },
#   u         => { 2 => 1, 3 => 1, 4 => 1, 5 => 1, 6 => 1, 7 => 1, 8 => 1,
#                  9 => 1, 10 => 1 },
);

sub initialize_functions
{
   @fun{ansi}      = sub { return &color($_[2],$_[3]);             };
   @fun{ansi_debug}= sub { return &ansi_debug($_[2]);              };
   @fun{substr}    = sub { return &fun_substr(@_);                 };
   @fun{cat}       = sub { return &fun_cat(@_);                    };
   @fun{space}     = sub { return &fun_space(@_);                  };
   @fun{repeat}    = sub { return &fun_repeat(@_);                 };
   @fun{time}      = sub { return &fun_time(@_);                   };
   @fun{timezone}  = sub { return &fun_timezone(@_);               };
   @fun{flags}     = sub { return &fun_flags(@_);                  };
   @fun{quota}     = sub { return &fun_quota_left(@_);             };
   @fun{sql}       = sub { return &fun_sql(@_);                    };
   @fun{input}     = sub { return &fun_input(@_);                  };
   @fun{has_input} = sub { return &fun_has_input(@_);              };
   @fun{strlen}    = sub { return &fun_strlen(@_);                 };
   @fun{right}     = sub { return &fun_right(@_);                  };
   @fun{left}      = sub { return &fun_left(@_);                   };
   @fun{lattr}     = sub { return &fun_lattr(@_);                  };
   @fun{iter}      = sub { return &fun_iter(@_);                   };
   @fun{parse}     = sub { return &fun_iter(@_);                   };
   @fun{huh}       = sub { return "#-1 Undefined function";        };
   @fun{ljust}     = sub { return &fun_ljust(@_);                  };
   @fun{rjust}     = sub { return &fun_rjust(@_);                  };
   @fun{loc}       = sub { return &fun_loc(@_);                    };
   @fun{extract}   = sub { return &fun_extract(@_);                };
   @fun{lwho}      = sub { return &fun_lwho(@_);                   };
   @fun{remove}    = sub { return &fun_remove(@_);                 };
   @fun{get}       = sub { return &fun_get(@_);                    };
   @fun{edit}      = sub { return &fun_edit(@_);                   };
   @fun{add}       = sub { return &fun_add(@_);                    };
   @fun{sub}       = sub { return &fun_sub(@_);                    };
   @fun{div}       = sub { return &fun_div(@_);                    };
   @fun{secs}      = sub { return &fun_secs(@_);                   };
   @fun{loadavg}   = sub { return &fun_loadavg(@_);                };
   @fun{after}     = sub { return &fun_after(@_);                  };
   @fun{before}    = sub { return &fun_before(@_);                 };
   @fun{member}    = sub { return &fun_member(@_);                 };
   @fun{index}     = sub { return &fun_index(@_);                  };
   @fun{replace}   = sub { return &fun_replace(@_);                };
   @fun{num}       = sub { return &fun_num(@_);                    };
   @fun{lnum}      = sub { return &fun_lnum(@_);                   };
   @fun{name}      = sub { return &fun_name(@_);                   };
   @fun{type}      = sub { return &fun_type(@_);                   };
   @fun{u}         = sub { return &fun_u(@_);                      };
   @fun{v}         = sub { return &fun_v(@_);                      };
   @fun{r}         = sub { return &fun_r(@_);                      };
   @fun{setq}      = sub { return &fun_setq(@_);                   };
   @fun{mid}       = sub { return &fun_substr(@_);                 };
   @fun{center}    = sub { return &fun_center(@_);                 };
   @fun{rest}      = sub { return &fun_rest(@_);                   };
   @fun{first}     = sub { return &fun_first(@_);                  };
   @fun{last}      = sub { return &fun_last(@_);                   };
   @fun{switch}    = sub { return &fun_switch(@_);                 };
   @fun{words}     = sub { return &fun_words(@_);                  };
   @fun{eq}        = sub { return &fun_eq(@_);                     };
   @fun{not}       = sub { return &fun_not(@_);                    };
   @fun{match}     = sub { return &fun_match(@_);                  };
   @fun{isnum}     = sub { return &fun_isnum(@_);                  };
   @fun{gt}        = sub { return &fun_gt(@_);                     };
   @fun{gte}       = sub { return &fun_gte(@_);                    };
   @fun{lt}        = sub { return &fun_lt(@_);                     };
   @fun{lte}       = sub { return &fun_lte(@_);                    };
   @fun{or}        = sub { return &fun_or(@_);                     };
   @fun{owner}     = sub { return &fun_owner(@_);                  };
   @fun{and}       = sub { return &fun_and(@_);                    };
   @fun{hasflag}   = sub { return &fun_hasflag(@_);                };
   @fun{squish}    = sub { return &fun_squish(@_);                 };
   @fun{capstr}    = sub { return &fun_capstr(@_);                 };
   @fun{lcstr}     = sub { return &fun_lcstr(@_);                  };
   @fun{ucstr}     = sub { return &fun_ucstr(@_);                  };
   @fun{setinter}  = sub { return &fun_setinter(@_);               };
   @fun{sort}      = sub { return &fun_sort(@_);                   };
   @fun{mudname}   = sub { return &fun_mudname(@_);                };
   @fun{version}   = sub { return &fun_version(@_);                };
   @fun{inuse}     = sub { return &inuse_player_name(@_);          };
   @fun{web}       = sub { return &fun_web(@_);                    };
   @fun{run}       = sub { return &fun_run(@_);                    };
   @fun{graph}     = sub { return &fun_graph(@_);                  };
   @fun{lexits}    = sub { return &fun_lexits(@_);                 };
   @fun{home}      = sub { return &fun_home(@_);                   };
   @fun{rand}      = sub { return &fun_rand(@_);                   };
   @fun{reverse}   = sub { return &fun_reverse(@_);                };
   @fun{base64}    = sub { return &fun_base64(@_);                 };
   @fun{compress}  = sub { return &fun_compress(@_);               };
   @fun{uncompress}  = sub { return &fun_uncompress(@_);           };
   @fun{revwords}  = sub { return &fun_revwords(@_);               };
   @fun{idle}      = sub { return &fun_idle(@_);                   };
   @fun{fold}      = sub { return &fun_fold(@_);                   };
   @fun{telnet_open}= sub { return &fun_telnet(@_);                };
   @fun{min}        = sub { return &fun_min(@_);                   };
   @fun{find}       = sub { return &fun_find(@_);                  };
   @fun{convsecs}   = sub { return &fun_convsecs(@_);              };
}

initialize_functions if is_single;

sub fun_convsecs
{
    my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*(\d+)\s*$/) {
       return scalar localtime($1);
    } else {
       return "#-1 Invalid seconds";
    }
}

sub fun_find
{
    my ($self,$prog,$txt) = @_;

    my $obj = find($self,$prog,$txt);

    printf("FUN_FIND: '%s'\n",$obj);
    if($obj ne undef) {
       return $$obj{obj_id};
    } else {
       return "UNFOUND";
    }
}
# starting point
sub fun_ansi
{
   my ($self,$prog,$codes,$txt) = (obj(shift),shift,shift,shift);
   my ($hilite,$pre);

   my %ansi = (
      x => 30, X => 40,
      r => 31, R => 41,
      g => 32, G => 42,
      y => 33, Y => 43,
      b => 34, B => 44,
      m => 35, M => 45,
      c => 36, C => 46,
      w => 37, W => 47,
      u => 4,  i => 7,
      h => 1
   );

   $txt =~ s/ //g;
#   $hilite = 1 if($codes =~ /h/);

   for my $ch (split(//,$codes)) {
      if(defined @ansi{$ch} && $hilite) {
         $pre .= "\e[@ansi{$ch};1m";
      } elsif(defined @ansi{$ch} && !$hilite) {
         $pre .= "\e[@ansi{$ch}m";
      }
   }
   return $pre . $txt . "\e[0m";
}


sub fun_min
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $min;

   good_args($#_,1 .. 100) ||
     return "#-1 FUNCTION (MIN) EXPECTS 1 AND 100 ARGUMENTS";

   while($#_ >= 0) {
      if($_[0] !~ /^\s*-{0,1}\d+\s*$/) {           # emulate mush behavior
         $min = 0 if ($min > 0 || $min eq undef);
         shift;
      } elsif($min eq undef || $min > $_[0]) {
         $min = shift;
      } else {
         shift;
      }
   }
   return $min;
}

sub fun_fold
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my ($count,$atr,$last,$zero,$one);

   good_args($#_,2,3,4) ||
     return "#-1 FUNCTION (FOLD) EXPECTS 2 TO 3 ARGUMENTS $#_";
   my ($atr,$list,$base,$idelim) = (shift,shift,shift);

   my $prev = get_digit_variables($prog);

   my $atr = fun_get($self,$prog,$atr);
   return $atr if($atr eq undef || $atr =~ /^#-1 /);

   my (@list) = safe_split(evaluate($self,$prog,$list),$idelim);
   while($#list >= 0) {
      if($count eq undef && $base ne undef) {
         ($zero,$one) = ($base,shift(@list));
      } elsif($count eq undef) {
         ($zero,$one) = (shift(@list),shift(@list));
      } else {
         ($zero,$one) = ($last,shift(@list));
      }

      set_digit_variables($self,$prog,$zero,$one);
      $last  = evaluate($self,$prog,$atr);
      $count++;
   }

   set_digit_variables($self,$prog,$prev);

   return $last;
}


sub fun_idle
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $idle;

   good_args($#_,1) ||
     return "#-1 FUNCTION (IDLE) EXPECTS 1 ARGUMENT";

   my $name = shift;

   my $player = find_player($self,$prog,$name) ||
     return -2;

   if(!defined @connected_user{$$player{obj_id}}) {
      return -3;
   } else {
      # search all connections
      for my $con (keys %{@connected_user{$$player{obj_id}}}) {
         if(defined @{@connected{$con}}{last}) {
            my $last = @{@connected{$con}}{last};

            # find least idle connection
            if($idle eq undef || $idle > time() - $$last{time}) {
                $idle = time() - $$last{time};
            }
         }
      }

      return ($idle eq undef) ? -1 : $idle;
   }
}

#
# lowercase the provided string(s)
#
sub fun_ucstr
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $result;

   my $str = ansi_init(join(',',@_));
   for my $i (0 .. $#{$$str{ch}}) {
      @{$$str{ch}}[$i] = uc(@{$$str{ch}}[$i]);
   }

   return ansi_string($str,1);
}

sub fun_sort
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   return join(' ',sort split(" ",shift));
}

sub fun_base64
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (BASE64) EXPECTS 2 ARGUMENT ($#_)";

   my ($type,$txt) = (shift, evaluate($self,$prog,shift));

   if(length($type) == 0) {
      return "#-1 FIRST ARGUMENT MUST BE Encode OR DECODE";
   } elsif(lc($type) eq substr("encode",0,length($type))) {
      my $txt = encode_base64($txt);
      $txt =~ s/\r|\n//g;
      return $txt;
   } elsif(lc($type) eq substr("decode",0,length($type))) {
      return decode_base64($txt);
   } else {
      return "#-1 FIRST ARGUMENT MUST BE ENCODE OR DECODE-",lc($type);
   }
}

sub fun_compress
{
   my ($self,$prog) = (obj(shift),shift);

   hasflag($self,"WIZARD") ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 WIZARD FLAG";
   
   good_args($#_,1) ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 ARGUMENT";

   my $txt = evaluate($self,$prog,shift);

   return compress($txt);
}

sub fun_uncompress
{
   my ($self,$prog) = (obj(shift),shift);

   hasflag($self,"WIZARD") ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 WIZARD FLAG";

   good_args($#_,1) ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 ARGUMENT";

   my $txt = valuate($self,$prog,shift);

   return uncompress($txt);
}

sub fun_reverse
{
   my ($self,$prog,$txt) = @_;

   return reverse $txt;
}

sub fun_revwords
{
   my ($self,$prog,$txt) = @_;

   return join(' ',reverse split(/\s+/,$txt));
}

sub fun_telnet
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $txt = evaluate($self,$prog,shift);

   if($txt =~ /^#-1 Connection Closed$/i ||
      $txt =~ /^#-1 Unknown Socket /) {
      return 0;
   } else {
      return 1;
   }
}


sub fun_rand
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*(\d+)\s*$/) {
      if($1 < 1) {
         return "#-1 ARGUEMENT MUST BE GREATER OR EQUAL TO 1";
      } else {
         return sprintf("%d",rand($1));
      }
   } else {
      return "#-1 ARGUEMENT MUST BE INTEGER";
   }
}


sub var_backup
{
   my ($dst,$src,%new_data) = @_;

   for my $key (keys %new_data) {                              # backup to dst
      $$dst{$key} = $$src{$key};
   }

   for my $key (keys %new_data) {
      $$src{$key} = @new_data{$key};
   }
}

sub var_restore
{
   my ($dst,$src) = @_;

   for my $key (keys %$src) {
      $$dst{$key} = $$src{$key};
   }
}


sub fun_lexits
{
   my ($self,$prog,$txt) = @_;
   my @result;

   my $target = find($self,$prog,$txt);
   return "#-1 NOT FOUND" if($target eq undef);

   for my $exit (lexits($target)) {
      push(@result,"#" . $$exit{obj_id});
   }
   return join(' ',@result);
}

sub fun_graph
{
   my ($self,$prog,$txt,$x,$y) = @_;

   if(mysqldb) {
      if($txt =~ /^\s*(mush|web)\s*$/i) {
         return "Specify Connected";
         return graph_connected(lc($1),$x,$y);
      } else {
         return "Specify Connected";
      }
   } else {
      return "Not written for MemoryDB";
   }
}

sub range
{
   my ($begin,$end) = @_;
   my ($start,$stop,@result);

   $start = fuzzy($begin);
   $stop = ($end eq undef) ? time() : fuzzy($end);
   return undef if($start > $stop);

   while($start < $stop) {
      push(@result,$start);
      $start += 86400;
      return $start = $stop if($#result > 50);
   }

   my ($emday,$emon,$eyear) = (localtime($end))[3,4,5];
   my ($cmday,$cmon,$cyear) = (localtime($start))[3,4,5];

   if($emday == $cmday && $emon == $cmon && $eyear == $cyear) {
      push(@result,$start);
   }

   return @result;
}

sub age
{
   my $date = shift;

   return sprintf("%d",(time() - $date) / 86400);
}

sub graph_connected
{
   my ($type,$size_x,$size_y) = @_;
   my (%all, %usage,$max,$val,$min,@out);

   $size_y = 8 if($size_y eq undef || $size_y < 8);

   if($type eq "MUSH") {
      $type = 1; 
   } elsif($type eq "WEB") {
      $type = 2;
   } else {
      $type = 1;
   }

   # find and group connects by user by day, this way if a user connects 
   # 320 times per day, it only counts as one hit.
   for my $rec (@{sql("select obj_id," .
                      "       skh_start_time start," .
                      "       skh_end_time end".
                      "  from socket_history  " .
                      " where skh_type = ? " .
                      "   and skh_start_time >= " .
                      "               date(now() - INTERVAL ($size_y+2) day)",
                      $type
                     )}) {
       for my $i (range($$rec{start},$$rec{end})) {
          @usage{$$rec{obj_id}} = {} if !defined @usage{$$rec{obj_id}};
          @{@usage{$$rec{obj_id}}}{age($i)}=1;
       }
    }

    # now combine all the data grouped by user into one group.
    # count min and max numbers while we're at it.
    for my $id (keys %usage) {
       my $hash = @usage{$id}; # 
       for my $dt (keys %$hash) {
          @all{$dt}++;
          $max = @all{$dt} if($max < @all{$dt});
          $min = @all{$dt} if ($min eq undef || $min > @all{$dt});
       }
    }
  
    # build the graph from the data within @all
    for my $x ( 1 .. $size_x ){
       if($x == 1) {
          $val = $max;
       } elsif($x == $size_x) {
          $val = $min;
      } else {
          $val = sprintf("%d",int($max-($x *($max/$size_x))+1.5));
       }
       @out[$x-1] = sprintf("%*d|",length($max),$val);
       for my $y ( 0  .. ($size_y-1)) {
          if($val <= @all{$y}) {
             @out[$x-1] .= "#|";
          } elsif($x == $size_x && @all{$y} > 0) {
             @out[$x-1] .= "*|";
          } else {
             @out[$x-1] .= " |";
          }
       }
    }

    my $start = $#out+1;
    @out[$start] = " " x (length($max)+1);
    @out[$start+1] = " " x (length($max)+1);
    my $inter = $size_y / 4;
    for my $y ( 0  .. ($size_y-1)) {
       my $dy = (localtime(time() - ($y * 86400)))[3];
       
       if($y != 0 && substr(sprintf("%2d",$dy),1,1) =~ /^[0|5]$/) {
          @out[$start] .= substr(sprintf("%02d",$dy),0,1) . "]";
       } elsif(substr(sprintf("%2d",$dy-1),1,1) =~ /^[0|5]$/ &&
               $y != $size_y-1) {
          @out[$start] .= "=[";
       } else {
          @out[$start] .= "==";
       }
       @out[$start+1] .= substr(sprintf("%2d",$dy),1,1) . "|";
    }
    return join("\n",@out);
}


sub fun_run
{
   my ($self,$prog,$txt) = @_;
   my (%none, $hash, %tmp, $match, $cmd,$arg);

   my $command = { runas => $self };
   if($txt  =~ /^\s*([^ \/]+)(\s*)/) {        # split cmd from args
      ($cmd,$arg) = (lc($1),$');
   } else {  
      return #-1 No command given to run;                       # only spaces
   }

   if($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCK") {
      if(defined $$prog{from} && $$prog{from} eq "ATTR") {
         $hash = \%command;
      } else {
         $hash = \%none;
      }
   } elsif(!loggedin($self) && hasflag($self,"PLAYER")) {
      $hash = \%offline;                                     # offline users
   } elsif(defined $$self{site_restriction} && $$self{site_restriction} == 69) {
      $hash = \%honey;                                   # honeypotted users
   } else {
      $hash = \%command;
   }

   if(defined $$hash{$cmd}) {
      var_backup(\%tmp,$prog,output => [], nomushrun => 1);
      my $result = run_internal($hash,$cmd,$command,$prog,$arg);
      if($result ne undef) {
         var_restore($prog,\%tmp);
         return $result;
      }
      my $output = join(',',@{$$prog{output}});
      $output =~ s/\n$//g;
      var_restore($prog,\%tmp);
      return $output;
   } else {
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
         var_backup(\%tmp,$prog,output => [], nomushrun => 1);
         my $result = run_internal($hash,$match,$command,$prog,$arg);

         if($result ne undef) {
            var_restore($prog,\%tmp);
            return $result;
         }
         my $output = join(',',$$prog{output});
         $output =~ s/\n$//g;
         var_restore($prog,\%tmp);
         return $output;
      } else {                                                     # no match
         return "#-1 Unknown command $cmd";
      }
   }
}

sub safe_split
{
    my ($txt,$delim) = @_;

    if($delim =~ /^\s*\n\s*/m) {
       $delim = "\n";
    } else {
       $delim =~ s/^\s+|\s+$//g;
 
       if($delim eq " " || $delim eq undef) {
          $txt =~ s/\s+/ /g;
          $txt =~ s/^\s+|\s+$//g;
          $delim = " ";
       }
    }

    my ($start,$pos,$size,$dsize,@result) = (0,0,length($txt),length($delim));

    for($pos=0;$pos < $size;$pos++) {
       if(substr($txt,$pos,$dsize) eq $delim) {
          push(@result,substr($txt,$start,$pos-$start));
          $result[$#result] =~ s/^\s+|\s+$//g if($delim eq " ");
          $start = $pos + $dsize;
       }
    }

    push(@result,substr($txt,$start)) if($start < $size);
    return @result;
}

sub list_functions
{
    return join(' ',sort keys %fun);
}

sub good_args
{
   my ($count,@possible) = @_;
   $count++;

   for my $i (0 .. $#possible) {
      return 1 if($count eq $possible[$i]);
   }
   return 0;
}

sub quota
{
   my $self = shift;

   return quota_left($self);
}

sub fun_mudname
{
   my ($self,$prog) = (shift,shift);

   my $name = @info{"conf.mudname"};

   return ($name eq undef) ? "TeenyMUSH" : $name;
}

sub fun_version
{
   my ($self,$prog) = (shift,shift);

   if(defined @info{version}) {
      return @info{version};
   } else {
      return "TeenyMUSH";
   }
}

#
# fun_web
#   Returns if the current session is coming from a web
#   connection or a normal mush connection
#
sub fun_web
{
   my ($self,$prog) = @_;

   return ($$prog{hint} eq "WEB") ? 1 : 0;
}

#
# fun_setinter
#    Return any matching item in both lists
#
sub fun_setinter
{
   my ($self,$prog) = (shift,shift);
   my (%list, %out);

   for my $i (split(/ /,@_[0])) {
       $i =~ s/^\s+|\s+$//g;
       @list{$i} = 1;
   }

   for my $i (split(/ /,@_[1])) {
      $i =~ s/^\s+|\s+$//g;
      @out{$i} = 1 if(defined @list{$i});
  }
  return join(' ',sort keys %out);
}


sub fun_lwho
{
   my ($self,$prog) = (shift,shift);
   my @who;

   for my $key (keys %connected) {
      my $hash = @connected{$key};
      if($$hash{raw} != 0||!defined $$hash{obj_id}||$$hash{obj_id} eq undef) {
         next;
      }
      push(@who,"#" . @{@connected{$key}}{obj_id});
   }
   return join(' ',@who);
}


sub fun_lcstr
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (LCSTR) EXPECTS 1 ARGUMENT ($#_)";

   my $str = ansi_init(join(',',@_));

   for my $i (0 .. $#{$$str{ch}}) {
      @{$$str{ch}}[$i] = lc(@{$$str{ch}}[$i]);
   }

   return ansi_string($str,1);
}

sub fun_home
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,0,1) ||
      return "#-1 FUNCTION (HOME) EXPECT 0 OR 1 ARGUMENT";

   my $target = find($self,$prog,shift);
   return "#-1 NOT FOUND" if($target eq undef);

   return "#" . home($target);
}

#
# capitalize the provided string
#
sub fun_capstr
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (SQUISH) EXPECTS 1 ARGUMENT ($#_)";

    return ucfirst(shift);
}

#
# fun_squish
#     1. Convert multiple spaces into a single space,
#     2. remove any leading or ending spaces
#
sub fun_squish
{
   my ($self,$prog) = (shift,shift);
   my $txt = @_[0];

   good_args($#_,1) ||
     return "#-1 FUNCTION (SQUISH) EXPECTS 1 ARGUMENT ($#_)";

   $txt =~ s/^\s+|\s+$//g;
   $txt =~ s/\s+/ /g;
   return $txt;
}

sub fun_eq
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (EQ) EXPECTS 2 ARGUMENTS";

   my ($one,$two) = @_;

   $one =~ s/^\s+|\s+$//g;
   $two =~ s/^\s+|\s+$//g;
   return ($one eq $two) ? 1 : 0;
}

sub fun_loc
{
   my ($self,$prog,$txt) = @_;

   my $target = find($self,$prog,$txt);

   if($target eq undef) {
      return "#-1 NOT FOUND";
   } elsif($txt =~ /^\s*here\s*/) {
      return "#" . $$target{obj_id};
   } else {
      return "#" . loc($target);
   }
}

sub fun_hasflag
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (HASFLAG) EXPECTS 2 ARGUMENTS";

   if((my $target = find($self,$prog,$_[0])) ne undef) {
      return hasflag($target,$_[1]);
   } else {
      return "#-1 Unknown Object";
   }
}

sub fun_gt
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (GT) EXPECTS 2 ARGUMENTS";
   return (@_[0] > @_[1]) ? 1 : 0;
}

sub fun_gte
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (GTE) EXPECTS 2 ARGUMENTS";
   return (@_[0] >= @_[1]) ? 1 : 0;
}

sub fun_lt
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (LT) EXPECTS 2 ARGUMENTS";
   return (@_[0] < @_[1]) ? 1 : 0;
}

sub fun_lte
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (LT) EXPECTS 2 ARGUMENTS";
   return (@_[0] <= @_[1]) ? 1 : 0;
}

sub fun_or
{
   my ($self,$prog) = (shift,shift);

   for my $i (0 .. $#_) {
      return 1 if($_[$i]);
   }
   return 0;
}


sub fun_isnum
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (ISNUM) EXPECTS 1 ARGUMENT";

   return looks_like_number(ansi_remove($_[0])) ? 1 : 0;
}

sub fun_lnum
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (LNUM) EXPECTS 1 ARGUMENT";

   return "#-1 ARGUMENT MUST BE NUMBER" if(!looks_like_number($_[0]));

   return join(' ',0 .. ($_[0]-1));
}

sub fun_and
{
   my ($self,$prog) = (shift,shift);

   for my $i (0 .. $#_) {
      return 0 if($_[$i] eq 0);
   }
   return 1;
}

sub fun_not
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NOT) EXPECTS 1 ARGUMENTS";

   return (! $_[0] ) ? 1 : 0;
}


sub fun_words
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$delim) = @_;

   good_args($#_,1,2) ||
      return "#-1 FUNCTION (WORDS) EXPECTS 1 OR 2 ARGUMENTS";

   return scalar(safe_split(ansi_remove($txt),
                            ($delim eq undef) ? " " : $delim
                           )
                );
}

sub fun_match
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$pat,$delim) = ($_[0],ansi_remove($_[1]),$_);
   my $count = 1;

   good_args($#_,1,2,3) ||
      return "#-1 FUNCTION (MATCH) EXPECTS 1, 2 OR 3 ARGUMENTS";

   $delim = " " if $delim eq undef; 
   $pat = glob2re($pat);

   for my $word (safe_split(ansi_remove($txt),$delim)) {
      return $count if($word =~ /$pat/);
      $count++;
   }
   return 0;
}

sub fun_center
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$size) = @_;

   if(!good_args($#_,2)) {
      return "#-1 FUNCTION (MEMBER) EXPECTS 2 ARGUMENTS";
   } elsif($size !~ /^\s*\d+\s*$/) {
      return "#-1 SECOND ARGUMENT MUST BE NUMERIC";
   } elsif($size eq 0) { 
      return "#-1 SECOND ARGUMENT MUST NOT BE ZERO";
   }

   $txt = ansi_substr($txt,0,$size);

   my $len = ansi_length($txt);

   my $lpad = " " x (($size - $len) / 2);

   my $rpad = " " x ($size - length($lpad) - $len);
   
   return $lpad . $txt . $rpad;
}

sub fun_switch
{
   my ($self,$prog) = (shift,shift);

   my $first = ansi_remove(evaluate($self,$prog,shift));

   while($#_ >= 0) {
      if($#_ >= 1) {
         my $txt = ansi_remove(evaluate($self,$prog,shift));
         my $pat = glob2re($txt);
         if($first =~ /$pat/) {
            return evaluate($self,$prog,@_[0]);
         } else {
            shift;
         }
      } else {
         return evaluate($self,$prog,shift);
      }
   }
}

sub fun_member
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$word,$delim) = @_;
   my $i = 1;

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (MEMBER) EXPECTS 2 OR 3 ARGUMENTS";

   return 1 if($txt =~ /^\s*$/ && $word =~ /^\s*$/);
   $delim = " " if $delim eq undef;

   for my $x (safe_split($txt,$delim)) {
      return $i if($x eq $word);
      $i++;
   }
   return 0;
}

sub fun_index
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$delim,$first,$size) = @_;
   my $i = 1;

   if(!good_args($#_,4)) {
      return "#-1 FUNCTION (INDEX) EXPECTS 4 ARGUMENTS";
   } elsif(!looks_like_number($first)) {
      return "#-1 THIRD ARGUMENT MUST BE A NUMERIC VALUE";
   } elsif(!looks_like_number($size)) {
      return "#-1 THIRD ARGUMENT MUST BE A NUMERIC VALUE";
   } elsif($txt =~ /^\s*$/) {
      return undef;
   }

   $first--;
   $size--;
   $delim = " " if $delim eq undef;
   return join($delim,(safe_split($txt,$delim))[$first .. ($size+$first)]);
}

sub fun_replace
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$positions,$word,$idelim,$odelim) = @_;
   my $i = 1;

   if(!good_args($#_,3,4,5)) {
      return "#-1 FUNCTION (REPLACE) EXPECTS 3, 4 or 5 ARGUMENTS";
   }
   $txt =~ s/^\s+|\s+$//g;
   $positions=~ s/^\s+|\s+$//g;
   $word =~ s/^\s+|\s+$//g;
   $idelim =~ s/^\s+|\s+$//g;
   $odelim =~ s/^\s+|\s+$//g;

   $idelim = ' ' if($idelim eq undef);
   $odelim = $idelim if($odelim eq undef);

   my @array  = safe_split($txt,$idelim);
   for my $i (split(' ',$positions)) {
      @array[$i-1] = $word if(defined @array[$i-1]);
   }
   return join($odelim,@array);
}



sub fun_after
{
   my ($self,$prog) = (shift,shift);

   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (AFTER) EXPECTS 1 or 2 ARGUMENTS";
   }

   my $loc = index(@_[0],@_[1]);
   if($loc == -1) {
      return undef;
   } else {
      my $result = substr(evaluate($self,$prog,@_[0]),$loc + length(@_[1]));
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_rest
{
   my ($self,$prog,$txt,$delim) = @_;

   if($#_ != 2 && $#_ != 3) {
      return "#-1 Function (REST) EXPECTS 1 or 2 ARGUMENTS";
   }

   $delim = " " if($delim eq undef);
   my $loc = index(evaluate($self,$prog,$txt),$delim);

   if($loc == -1) {
      return $txt;
   } else {
      my $result = substr($txt,$loc + length($delim));
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_first
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$delim) = @_;
   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (FIRST) EXPECTS 1 or 2 ARGUMENTS";
   }

   if($delim eq undef || $delim eq " ") {
      $txt =~ s/^\s+|\s+$//g;
      $txt =~ s/\s+/ /g;
      $delim = " ";
   }
   my $loc = index(evaluate($self,$prog,$txt),$delim);

   if($loc == -1) {
      return $txt;
   } else {
      my $result = substr($txt,0,$loc);
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_last
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$delim) = @_;
   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (FIRST) EXPECTS 1 or 2 ARGUMENTS";
   }

   if($delim eq undef || $delim eq " ") {
      $txt =~ s/^\s+|\s+$//g;
      $txt =~ s/\s+/ /g;
      $delim = " ";
   }
   my $loc = rindex(evaluate($self,$prog,$txt),$delim);

   if($loc == -1) {
      return $txt;
   } else {
      my $result = substr($txt,$loc+1);
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_before
{
   my ($self,$prog,$txt,$delim) = @_;

   if($#_ != 3 && $#_ != 3) {
      return "#-1 Function (BEFORE) EXPECTS 1 or 2 ARGUMENTS";
   }
 
   my $loc = index($txt,$delim);

   if($loc == -1) {
      return undef;
   } else {
      my $result = substr(evaluate($self,$prog,$txt),0,$loc);
      $result =~ s/\s+$//;
      return $result;
   }
}


sub fun_loadavg
{
   my ($self,$prog) = (shift,shift);
   my $file;

   if(-e "/proc/loadavg") {
      open($file,"/proc/loadavg") ||
         return "#-1 Unable to determine load average";
      while(<$file>) {
         if(/^\s*([0-9\.]+)\s+([0-9\.]+)\s+([0-9\.]+)\s+/) {
            close($file);
            return "$1 $2 $3";
         }
      }
      close($file);
      return "#-1 Unable to determine load average";
   } else {
      return "#-1 Unable to determine load average";
   }
}
#
# fun_secs
#    Return the current epoch time
#
sub fun_secs
{
   my ($self,$prog) = (shift,shift);

   return time();
}

#
# fun_div
#    Divide a number
#
sub fun_div
{
   my ($self,$prog) = (shift,shift);

   return "#-1 Add requires at least two arguments" if $#_ < 1;

   if($_[1] eq 0) {
      return "#-1 DIVIDE BY ZERO";
   } else {
      return int(@_[0] / @_[1]);
   }
}

#
# fun_add
#    Add multiple numbers together
#
sub fun_add
{
   my ($self,$prog) = (shift,shift);

   my $result = 0;

   return "#-1 Add requires at least one argument" if $#_ < 0;

   for my $i (0 .. $#_) {
      $result += @_[$i];
   }
   return $result;
}

sub fun_sub
{
   my ($self,$prog) = (shift,shift);

   my $result = @_[0];

   return "#-1 Sub requires at least one argument" if $#_ < 0;

   for my $i (1 .. $#_) {
      $result -= @_[$i];
   }
   return $result;
}

sub lord
{
   my $txt = shift;
   $txt =~ s/\e/<ESC>/g;
   return $txt;
}

sub fun_edit
{
   my ($self,$prog) = (shift,shift);
   my ($start,$out);

   good_args($#_,3) ||
      return "#-1 FUNCTION (EDIT) EXPECTS 3 ARGUMENTS";

   my $txt  = ansi_init(evaluate($self,$prog,shift));
   my $from = ansi_remove(evaluate($self,$prog,shift));
   my $to   = evaluate($self,$prog,shift);
   my $size = ansi_length($from);
   my $size = length($from);

   for(my $i = 0, $start=0;$i <= $#{$$txt{ch}};$i++) {
      if(ansi_substr($txt,$i,$size) eq $from) {
#         printf("MAT[$size]: '%s' -> '%s'  *MATCH*\n",ansi_substr($txt,$i,$size),$from);
         if($start ne undef or $i != $start) {
            $out .= ansi_substr($txt,$start,$i - $start);
         }
         $out .= $to;
         $i += $size;
         $start = $i;
      } else {
#         printf("MAT: '%s' -> '%s' [%s -> %s]\n",ansi_substr($txt,$i,$size),$from,lord(ansi_substr($txt,$i,$size)),lord($from));
      }
   }

   if($start ne undef or $start >= $#{$$txt{ch}}) {       # add left over chars
      $out .= ansi_substr($txt,$start,$#{$$txt{ch}} - $start + 1);
   }
   return $out;
}

# sub fun_edit
# {
#    my ($self,$prog) = (shift,shift);
# 
#    good_args($#_,3) ||
#       return "#-1 FUNCTION (EDIT) EXPECTS 3 ARGUMENTS";
# 
#    my $txt = evaluate($self,$prog,shift);
#    my $from = quotemeta(evaluate($self,$prog,shift));
#    my $to= evaluate($self,$prog,shift);
#    $txt =~ s/$from/$to/ig;
#    return $txt;
# }

sub fun_num
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NUM) EXPECTS 1 ARGUMENT";

   my $result = find($self,$prog,$_[0]);
 
   if($result eq undef) {
      return "#-1";
   } else {
      return "#$$result{obj_id}";
   }
}

sub fun_owner
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (OWNER) EXPECTS 1 ARGUMENT";

   my $owner = owner(obj(shift));

   return ($owner eq undef) ? "#-1" : ("#" . $$owner{obj_id});
}

sub fun_name
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NAME) EXPECTS 1 ARGUMENT";

   my $result = find($self,$prog,$_[0]);
 
   if($result eq undef) {
      return "#-1";
   } else {
     return name($result);
   }
}

sub fun_type
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (TYPE) EXPECTS 1 ARGUMENT";

   if((my $target= find($self,$prog,$_[0])) ne undef) {
      if(hasflag($target,"PLAYER")) {
         return "PLAYER";
      } elsif(hasflag($target,"OBJECT")) {
         return "OBJECT";
      } elsif(hasflag($target,"EXIT")) {
         return "EXIT";
      } elsif(hasflag($target,"ROOM")) {
         return "ROOM";
      } else {
         return "TYPELESS";
      }
   } else {
      return "#-1 Unknown Object";
   }
}

sub fun_u
{
   my ($self,$prog) = (shift,shift);

   my $txt = shift;
   my ($obj,$attr);

   my $prev = get_digit_variables($prog);                   # save %0 .. %9
   set_digit_variables($self,$prog,@_);              # update to new values

   if($txt =~ /\//) {                    # input in object/attribute format?
      ($obj,$attr) = (find($self,$prog,$`,"LOCAL"),$');
   } else {                                  # nope, just contains attribute
      ($obj,$attr) = ($self,$txt);
   }
   my $foo = $$obj{obj_name};

   if($obj eq undef) {
      return "#-1 Unknown object";
   } elsif(!controls($self,$obj)) {
      return "#-1 PerMISSion Denied";
   }

   my $data = get($obj,$attr);
   $data =~ s/^\s+|\s+$//gm;
   $data =~ s/\n|\r//g;

   my $result = evaluate($self,$prog,$data);
   set_digit_variables($self,$prog,$prev);                # restore %0 .. %9
   return $result;
}


sub fun_get
{
   my ($self,$prog) = (shift,shift);

   my $txt = $_[0];
   my ($obj,$atr);

   if($txt =~ /\//) {
      ($obj,$atr) = ($`,$');
   } else {
      ($obj,$atr) = ($txt,@_[0]);
   }

   my $target = find($self,$prog,evaluate($self,$prog,$obj));

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!controls($self,$target) && !hasflag($target,"VISUAL")) {
      return "#-1 Permission Denied $$self{obj_id} -> $$target{obj_id}";
   } 

   if(lc($atr) eq "lastsite") {
      return lastsite($target);
   } else {
      return get($target,$atr);
   }
}


sub fun_v
{
   my ($self,$prog,$txt) = (shift,shift,shift);

   return evaluate($self,$prog,get($self,$txt));
}

sub fun_setq
{
   my ($self,$prog) = (shift,shift);

   my ($register,$value) = @_;

   good_args($#_,2) ||
      return "#-1 FUNCTION (SETQ) EXPECTS 2 ARGUMENTS";

   $register =~ s/^\s+|\s+$//g;
   $value =~ s/^\s+|\s+$//g;

   my $result = evaluate($self,$prog,$value);
   @{$$prog{var}}{"setq_$register"} = $result;
   return undef;
}

sub fun_r
{
   my ($self,$prog) = (shift,shift);

   my ($register) = @_;

   good_args($#_,1) ||
      return "#-1 FUNCTION (R) EXPECTS 1 ARGUMENTS";

   $register =~ s/^\s+|\s+$//g;
   
   if(defined @{$$prog{var}}{"setq_$register"}) {
      return @{$$prog{var}}{"setq_$register"};
   } else {
      return undef;
   }
}

sub fun_extract
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$first,$length,$idelim,$odelim) = @_;
   my (@list,$last);
   $idelim = " " if($idelim eq undef);
   $odelim = " " if($odelim eq undef);
   return if $first == 0;

   if($first !~ /^\s*\d+\s*$/) {
      return "#-1 EXTRACT EXPECTS NUMERIC VALUE FOR SECOND ARGUMENT";
   } elsif($length !~ /^\s*\d+\s*$/) {
      return "#-1 EXTRACT EXPECTS NUMERIC VALUE FOR THIRD ARGUMENT";
   } 
   $first--;

   my $text = $txt;
   $text =~ s/\r|\n//g;
   $text =~ s/\n/<RETURN>/g;
   @list = safe_split($text,$idelim);
   return join($odelim,@list[$first .. ($first+$last)]);
}

sub fun_remove
{
   my ($self,$prog) = (shift,shift);

   my ($list,$words,$delim) = @_;
   my (%remove, @result);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (REMOVE) EXPECTS 2 OR 3 ARGUMENTS";

   if($delim eq undef || $delim eq " ") {
      $list =~ s/^\s+|\s+$//g;
      $list =~ s/\s+/ /g;
      $words =~ s/^\s+|\s+$//g;
      $words =~ s/\s+/ /g;
      $delim = " ";
   }

   for my $word (safe_split($words,$delim)) {
      @remove{$word} = 1;
   }

   for my $word (safe_split($list,$delim)) {
      if(defined @remove{$word}) {
         delete @remove{$word};                       # only remove once
      } else {
         push(@result,$word);
      }
   }

   return join($delim,@result);
}

sub fun_rjust
{
   my ($self,$prog,$txt,$size,$fill) = @_;

   $fill = " " if($fill =~ /^$/);

   if($size =~ /^\s*$/) {
      return $txt;
   } elsif($size !~ /^\s*(\d+)\s*$/) {
      return "#-1 rjust expects a numeric value for the second argument";
   } else {
      return ($fill x ($size - length(substr($txt,0,$size)))) .
             substr($txt,0,$size);
   }
}

sub fun_ljust
{
   my ($self,$prog,$txt,$size,$fill) = @_;

   $fill = " " if($fill =~ /^$/);

   if($size =~ /^\s*$/) {
      return $txt;
   } elsif($size !~ /^\s*(\d+)\s*$/) {
      return "#-1 ljust expects a numeric value for the second argument";
   } else {
      my $sub = ansi_substr($txt,0,$size);
      return $sub . ($fill x ($size - ansi_length($sub)));
   }
}

sub fun_strlen
{
   my ($self,$prog) = (shift,shift);

   return ansi_length(evaluate($self,$prog,shift));
}

sub fun_sql
{
   my ($self,$prog,$type) = (shift,shift,shift);
   my $result;

   if(hasflag($self,"WIZARD") || hasflag($self,"SQL")) {
      my (@txt) = @_;

      my $sql = join(',',@txt);
#      $sql =~ s/\_/%/g;
#      necho(self => $self,
#            prog => $prog,
#            source => [ "Sql: '%s'\n",$type],
#           );
      if(lc($type) eq "text") {
         $result = text(evaluate($self,$prog,$sql));
      } else {
         $result = table(evaluate($self,$prog,$sql));
      }

      $result =~ s/\n$//;
      return $result;
   } else {
      return "#-1 Permission Denied";
   }
}

#
# fun_substr
#   substring function
#
sub fun_substr
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$start,$end) = @_; 

   if(!($#_ == 2 || $#_ == 3)) {
      return "#-1 Substr expects 2 - 3 arguments but found " . ($#_+1);
   } elsif($start !~ /^\s*\d+\s*/) {
      return "#-1 Substr expects a numeric value for second argument";
   } elsif($end !~ /^\s*\d+\s*/) {
      return "#-1 Substr expects a numeric value for third argument";
   }

   return ansi_substr($txt,$start,$end);
}


sub fun_right
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT";

   my ($txt,$size) = (shift,shift);

   if($size !~ /^\s*\d+\s*/) {
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT TO BE NUMERIC";
   }

   return substr($txt,length($txt) - $size);
}

sub fun_left
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT";

   my ($txt,$size) = (shift,shift);

   if($size !~ /^\s*\d+\s*/) {
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT TO BE NUMERIC";
   }

   return substr($txt,0,$size);
}

#
# get_socket
#    Return the socket associated for a named mush socket
#    
sub get_socket
{
   my $txt = trim(uc(shift));

   for my $key (keys %connected) {
      if(defined $connected{$key}->{sock} &&
         @connected{$key}->{socket} eq $txt) {
         return @connected{$key}->{sock};
      }
   }

   return undef;
}

#
# fun_input
#    Check to see if there is any input in the specified input buffer
#    variable. If there is, return the data or return #-1 No Data Found
# 
sub fun_input
{
   my ($self,$prog) = (obj(shift),shift);
   my $txt = evaluate($self,$prog,shift);

   
    if(!defined $$prog{telnet_sock} && !defined $$prog{socket_buffer}) {
       return "#-1 Connection Closed";
    } elsif(defined $$prog{telnet_sock} && !defined $$prog{socket_buffer}) {
       $$prog{idle} = 1;                                    # hint to queue
       return "#-1 No data found";
    }

    my $input = $$prog{socket_buffer};

    # check if there is any buffered data and return it.
    # if not, the socket could have closed
    if($#$input == -1) { 
       if(defined $$prog{telnet_sock} &&
          defined @connected{$$prog{telnet_sock}}) {
          $$prog{idle} = 1;                                 # hint to queue
          return "#-1 No data found";                  # wait for more data?
       } else {
          return "#-1 Connection closed";                    # socket closed
       }
    } else {
       my $data = shift(@$input);                # return buffered data
#       $data =~ s/\\/\\\\/g;
#       $data =~ s/\//\\\//g;
       $data =~ s/’/'/g;
       $data =~ s/―/-/g;
       $data =~ s/`/`/g;
       $data =~ s/‘/`/g;
       $data =~ s/‚/,/g;
       $data =~ s/⚡/`/g;
       $data =~ s/↑ /N /g;
       $data =~ s/↓ /S /g;
       $data =~ s/↘ /SE /g;
       $data =~ s/→ /E /g;
       my $ch = chr(226) . chr(134) . chr(152);
       $data =~ s/$ch/SE/g;
       my $ch = chr(226) . chr(134) . chr(147);
       $data =~ s/$ch/S/g;
       my $ch = chr(226) . chr(134) . chr(145);
       $data =~ s/$ch/N/g;
       my $ch = chr(226) . chr(134) . chr(146);
       $data =~ s/$ch/E/g;
       my $ch = chr(226) . chr(134) . chr(151);
       $data =~ s/$ch/NE/g;
       my $ch = chr(226) . chr(134) . chr(150);
       $data =~ s/$ch/NW/g;
 
       return $data;
    }
}

sub fun_flags
{
   my ($self,$prog,$txt) = @_;

   # verify arguments
   return "#-1" if($txt =~ /^\s*$/);

   # find object
   my $target = find($self,$prog,$txt);
   return "#-1" if($target eq undef);

   # return results
   return flag_list($target);
}

#
# fun_space
#
sub fun_space
{
    my ($self,$prog,$count) = @_;

    if($count =~ /^\s*$/) {
       $count = 1;
    } elsif($#_ != 1 && $#_ != 2) {
       return "#-1 Space expects 0 or 1 numeric value but found " . ($#_ +1);
    } elsif($count !~ /^\s*\d+\s*/) {
       return undef;
    }
    return " " x $count ;
}

# [repeat(^'+.\,.+',6)]

#
# fun_repeat
#
sub fun_repeat
{
   my ($self,$prog) = (shift,shift);

    my ($txt,$count) = @_;

    if($#_ != 1) {
       return "#-1 Repeat expects 2 arguments but found " . ($#_ +1);
    } elsif($count !~ /^\s*\d+\s*/) {
       return "#-1 Repeat expects numeric value for the second arguement";
    }
    return $txt x $count;
}

#
# fun_time
#
sub fun_time
{
   my ($self,$prog) = (shift,shift);

    if($#_ != -1 && $#_ != 0) {
       return "#-1 Time expects no arguments but found " . ($#_ +1);
    }
    return scalar localtime(); # . " " . strftime("%Z",localtime());
}

#
# fun_timezone
#
sub fun_timezone
{
   my ($self,$prog) = (shift,shift);

    if($#_ != -1 && $#_ != 0) {
       return "#-1 Timezone expects no arguments but found " . ($#_ +1);
    }
    return scalar strftime("%Z",localtime());
}

#
# fun_cat
#   Concatination function
#
sub fun_cat
{
   my ($self,$prog) = (shift,shift);

   my @data = @_;
   my $out;

   for my $i (0 .. $#data) {
      if($i == 0) {
         $out .= @data[$i];
      } else {
         $out .= " " . @data[$i];
      }
   }
   return $out;
}


sub mysql_pattern
{
   my $txt = shift;

   $txt =~ s/^\s+|\s+$//g;
   $txt =~ tr/\x80-\xFF//d;
   $txt =~ s/[\;\%\/\\]//g;
   $txt =~ s/\*/\%/g;
   $txt =~ s/_/\\_/g;
   return $txt;
}

#
# fun_lattr
#    Return a list of attributes on an object or the enactor.
#
sub fun_lattr
{
   my ($self,$prog) = (shift,shift);
   my $txt = shift;
   my ($obj,$atr,@list);

   if($txt =~ /\s*\/\s*/) {                               # input has a slash 
      ($obj,$atr) = ($`, $');
   } elsif($txt =~ /^\s*$/) {                                      # no input
      return "#-1 FUNCTION (LATTR) EXPECTS 1 ARGUMENTS";
   } else {
      $obj = $txt;                                        # only obj provided
   }

   my $target = find($self,$prog,$obj);
   return "#-1 Unknown object" if $target eq undef;  # oops, can't find object

   if(!controls($self,$target) && !hasflag($target,"VISUAL")) {
      return err($self,$prog,"#-1 Permission Denied.");
   }

   if(memorydb) {
      my $pat = ($atr eq undef) ? undef : glob2re($atr);

      for my $attr (lattr($target)) {
         push(@list,uc($attr)) if($pat eq undef || $attr =~ /$pat/i);
      }
   } else {
      for my $attr (@{sql($db,                  # query db for attribute names
                          "  select atr_name " .
                          "    from attribute " .
                          "   where obj_id = ? " .
                          "     and atr_name like upper(?) " .
                          "order by atr_name",
                          $$target{obj_id},
                          mysql_pattern($atr)
                         )}) {
         push(@list,$$attr{atr_name});
      }
   }
   return join(' ',@list);
}

#
# fun_iter
#
sub fun_iter
{
   my ($self,$prog,$values,$txt,$idelim,$odelim) = @_;
   my @result;

   for my $item (safe_split(evaluate($self,$prog,$values),$idelim)) {
       my $new = $txt; 
       $new =~ s/##/$item/g;
       push(@result,evaluate($self,$prog,$new));
   }

   return join(($odelim eq undef) ? " " : $odelim,@result);
}

#
# escaped
#    Determine if the current position is escaped or not by
#    counting backwards to see if the number of slashes are
#    odd or even.
#
sub escaped
{
   my ($array,$pos) = @_;
   my $count = 0;
   my $p = $pos;

   # count number of escape characters
   for($pos--;$pos > -1 && $$array[$pos] eq "\\";$pos--) {
      $count++;
   }

   # if odd, the current position is escape. If even its not.
   return ($count % 2 == 0) ? 0 : 1;
}

#
# fun_lookup
#    See if the function exists or not. Return "huh" if only to be
#    consistent with the command lookup
#
sub fun_lookup
{
   my ($self,$prog) = (shift,shift);

   if(!defined @fun{lc($_[0])}) {
      printf("undefined function '%s'\n",@_[0]);
      printf("%s",code("long"));
   }
   return (defined @fun{lc($_[0])}) ? lc($_[0]) : "huh";
}


#
# function_walk
#    Traverse the string till the end of the function is reached.
#    Keep track of the depth of {}[]"s so that the function is
#    not split in the wrong place.
#
sub parse_function 
{
   my ($self,$prog,$fun,$txt,$type) = @_;

   my @array = balanced_split($txt,",",$type);
   return undef if($#array == -1);

   # type 1: expect ending ]
   # type 2: expect ending ) and nothing else
   if(($type == 1 && @array[0] =~ /^ *]/) ||
      ($type == 2 && @array[0] =~ /^\s*$/)) {
      @array[0] = $';                              # strip ending ] if there
      for my $i (1 .. $#array) {                            # eval arguments
         # evaluate args before passing them to function

         if(!(defined @exclude{$fun} && (defined @{@exclude{$fun}}{$i} ||
            defined @{@exclude{$fun}}{all}))) {
            @array[$i] = evaluate($self,$prog,@array[$i]);
#            @array[$i] = @array[$i];
         }
      }
      return \@array;
   } else {
      return undef;
   }
}


#
# balanced_split
#    Split apart a string but allow the string to have "",{},()s
#    that keep segments together... but only if they have a matching
#    pair.
#
sub balanced_split
{
   my ($txt,$delim,$type,$debug) = @_;
   my ($last,$i,@stack,@depth,$ch,$buf) = (0,-1);

   my $size = length($txt);
   while(++$i < $size) {
      $ch = substr($txt,$i,1);

      if($ch eq "\\") {
#         $buf .= substr($txt,++$i,1);
         $buf .= substr($txt,$i++,2); # CHANGE
         next;
      } else {
         if($ch eq "(" || $ch eq "{") {                  # start of segment
            $buf .= $ch;
            push(@depth,{ ch    => $ch,
                          last  => $last,
                          i     => $i,
                          stack => $#stack+1,
                          buf   => $buf
                        });
         } elsif($#depth >= 0) {
            $buf .= $ch;
            if($ch eq ")" && @{@depth[$#depth]}{ch} eq "(") {
               pop(@depth);
            } elsif($ch eq "}" && @{@depth[$#depth]}{ch} eq "{") {
               pop(@depth);
            }
         } elsif($#depth == -1) {
            if($ch eq $delim) {    # delim at right depth
               push(@stack,$buf);
               $last = $i+1;
               $buf = undef;
            } elsif($type <= 2 && $ch eq ")") {                   # func end
               push(@stack,$buf);
               $last = $i+1;
               $i = $size;
               $buf = undef;
               last;                                      # jump out of loop
            } else {
               $buf .= $ch;
            }
         } else {
            $buf .= $ch;
         }
      }
      if($i +1 >= $size && $#depth != -1) {   # parse error, start unrolling
         my $hash = pop(@depth);
         $i = $$hash{i};
         delete @stack[$$hash{stack} .. $#stack];
         $last = $$hash{last};
         $buf = $$hash{buf};
      }
   }

   if($type == 3) {
      push(@stack,substr($txt,$last));
      return @stack;
   } else {
      unshift(@stack,substr($txt,$last));
      return ($#depth != -1) ? undef : @stack;
   }
}


#
# script
#    Create some output that can be tested against another mush
#
sub script
{
   my ($fun,$args,$result) = @_;

#   if($result =~ /^\s*$/) {
#      printf("FUN: '%s(%s) returned undef\n",$fun,$args);
#   }
#   return;
#   if($args !~ /(v|u|get|r)\(/i && $fun !~ /^(v|u|get|r)$/) {
#      printf("think [switch(%s(%s),%s,,{WRONG %s(%s) -> %s})]\n",
#          $fun,$args,$result,$fun,$args,$result);
#   }
}

#
# evaluate_string
#    Take a string and parse/run any functions in the string.
#
sub evaluate
{
   my ($self,$prog,$txt) = @_;
   my $out;

   #
   # handle string containing a single non []'ed function
   #
   if($txt =~ /^\s*([a-zA-Z_0-9]+)\((.*)\)\s*$/s) {
      my $fun = fun_lookup($self,$prog,$1,$txt);
      if($fun ne "huh") {                   # not a function, do not evaluate
         my $result = parse_function($self,$prog,$fun,"$2)",2);
         if($result ne undef) {
            shift(@$result);
            printf("undefined function: '%s'\n",$fun) if($fun eq "huh");
            my $r=&{@fun{$fun}}($self,$prog,@$result);
            
            script($fun,join(',',@$result),$r);

            return $r;
         }
      }
   }

   if($txt =~ /^\s*{\s*(.*)\s*}\s*$/) {                # mush strips these
      $txt = $1;
   }

   #
   # pick functions out of string when enclosed in []'s 
   #
   while($txt =~ /([\\]*)\[([a-zA-Z_0-9]+)\(/s) {
      my ($esc,$before,$after,$unmod) = ($1,$`,$',$2);
      my $fun = fun_lookup($self,$prog,$unmod,$txt);
      $out .= evaluate_substitutions($self,$prog,$before);
      $out .= "\\" x (length($esc) / 2);

#      printf("FUN: '%s'\n",$txt);
      if(length($esc) % 2 == 0) {
         my $result = parse_function($self,$prog,$fun,$',1);

         if($result eq undef) {
            $txt = $after;
            $out .= "[$fun(";
         } else {                                    # good function, run it
            $txt = shift(@$result);
            my $r = &{@fun{$fun}}($self,$prog,@$result);
            script($fun,join(',',@$result),$r);
            $out .= "$r";
         }
      } else {                                # start of function escaped out
         $out .= "[$unmod(";
         $txt = $after;
      }
   }

   if($txt ne undef) {                         # return results + leftovers
      return $out . evaluate_substitutions($self,$prog,$txt);
   } else {
      return $out;
   }
}
# #!/usr/bin/perl

#
# tm_httpd.pl
#    Handle the incoming data and look for disconnects.
#
sub http_io
{
   my $s = shift;
   my $buf;

   if(sysread($s,$buf,1024) <= 0) {                      # oops socket died
      http_disconnect($s);
   } else {
      $buf =~ s/\r//g;
      @{@http{$s}}{buf} .= $buf;                         # store new input

      while(defined @http{$s} && @{@http{$s}}{buf} =~ /\n/){ 
         @{@http{$s}}{buf} = $';                  # process any full lines
         http_process_line($s,$`);
      }
   }
}

#
# http_accept
#    The listener has detected a new socket
#
sub http_accept
{
   my $s = shift;

   my $new = $web->accept();

   $readable->add($new);

   @http{$new} = { sock => $new,
                    data => {},
                    ip   => server_hostname($new),
                  };
#   printf("   %s\@web Connect\n",@{@http{$new}}{ip});
}

sub http_disconnect
{
   my $s = shift;

   delete @http{$s};
   $readable->remove($s);
   $s->close;

}

sub http_error
{
   my ($s,$fmt,@args) = @_;

   http_out($s,"HTTP/1.1 404 Not Found");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,"<style>");
   http_out($s,".big {");
   http_out($s,"   line-height: 0;");
   http_out($s,"   font-size: 100pt;");
   http_out($s,"}");
   http_out($s,"</style>");
   http_out($s,"<center><h1 class=big>404</h1><hr>#-1 Page Not Found</center>");
   http_out($s,"<center>$fmt</center>",@args);
   http_disconnect($s);
}

sub http_reply
{
   my ($s,$fmt,@args) = @_;

   my $msg = sprintf($fmt,@args);

   if($msg =~ /^Huh\? \(Type \"help\" for help\.\)/) {
      return http_error($s,$fmt,@args);
   }

   http_out($s,"HTTP/1.1 200 Default Request");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,"%s\n",@info{"conf.httpd_template"});
   http_out($s,"<body>\n");
   http_out($s,"<div id=\"Content\">\n");
   http_out($s,"<pre>%s\n</pre>\n",ansi_remove($msg));
   http_out($s,"</div>\n");
   http_out($s,"</body>\n");
   http_disconnect($s);
}

sub http_reply_simple
{
   my ($s,$type,$fmt,@args) = @_;

   my $msg = sprintf($fmt,@args);

   http_out($s,"HTTP/1.1 200 Default Request");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/$type; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,$fmt,@args);
   http_disconnect($s);
}

sub http_out
{
   my ($s,$fmt,@args) = @_;

   printf({@{@http{$s}}{sock}} "$fmt\r\n", @args) if(defined @http{$s});
}

#
# http_process_line
#
#    A line of data has been found, store the information for later
#    use if the request is not done.
#
sub http_process_line
{
   my ($s,$txt) = @_;

   my $data = @{@http{$s}}{data};

   if($txt =~ /^GET (.*) HTTP\/([\d\.]+)$/i) {              # record details
#      printf("      %s\@web %s\n",@{@http{$s}}{ip},$1);
      $$data{get} = $1;
   } elsif($txt =~ /^([\w\-]+): /) {
      $$data{lc($1)} = $';
   } elsif($txt =~ /^\s*$/) {                               # end of request
      my $msg =  uri_unescape($$data{get});

      if($msg eq undef) {
         http_error($s,"Malformed Request");
      } else {
         my $id = @info{"conf.webuser"};
         my $self = obj(@info{"conf.webuser"});

         my $msg =  uri_unescape($$data{get});
#         $msg = $' if($msg =~ /^\s*\/+/);
         $msg =~ s/\// /g;

         # run the $default mush command as the default webpage.
         $msg = "default" if($msg =~ /^\s*$/);

         my $addr = @{@http{$s}}{hostname};
         $addr = @{@http{$s}}{ip} if($addr =~ /^\s*$/);
         $addr = $s->peerhost if($addr =~ /^\s*$/);
         return http_error($s,"Malformed Request or IP") if($addr =~ /^\s*$/);

         printf("   %s\@web [%s]\n",$addr,$msg);

         if(mysqldb && $msg !~ /^\s*favicon\.ico\s*$/i) {
            sql(e($db,1),
                "insert into socket_history ".
                "( obj_id, " .
                "  skh_hostname, " .
                "  skh_start_time, " .
                "  skh_end_time, " .
                "  skh_success, " .
                "  skh_detail, " .
                "  skh_type " .
                ") values ( " .
                "  ?, ?, now(), now(), 0, ?, ? ".
                ")",
                @info{"conf.webuser"},
                $addr,
                substr($msg,0,254),
                2
               );
         }

         # html/js/css should be a static file, so just return the file
         if($msg =~ /\.(html|js|css)$/i && -e "txt/" . trim($msg)) {
            http_reply_simple($s,$1,"%s",getfile(trim($msg)));
         } else {                                          # mush command
            my $prog = mushrun(self   => $self,
                               runas  => $self,
                               source => 0,
                               cmd    => $msg,
                               hint   => "WEB",
                               sock   => $s,
                               output => [],
                               nosplit => 1,
                              );
         }
      }
   } else {
      http_error($s,"Malformed Request");
   }
}
# #!/usr/bin/perl
#
# tm_internal.pl
#    Various misc functions that are not related to anything in particular.
#    This is generally code that supports other bits and peices. Maybe this
#    should be renamed to tm_misc.pl
#

use strict;
use IO::Select;
use IO::Socket;
use Time::Local;
use Carp;
use Fcntl qw( SEEK_END SEEK_SET);

my %months = (
   jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6,
   jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12,
);

my %days = (
   mon => 1, tue => 2, wed => 3, thu => 4, fri => 5, sat => 6, sun => 7,
);

#
# dump_complete
#    Determine if a dump file is complete by looking at the last 45
#    characters in the file for a dump complete message
#
sub dump_complete
{
   my $filename = shift;
   my ($buf,$fh);

   return 1 if(arg("forceload"));
   open($fh,$filename) || return 0;

   my $eof = sysseek($fh,0,SEEK_END);          # seek to end to determine size
   seek($fh,$eof - 46,SEEK_SET);                        # backup 46 characters
   sysread($fh,$buf,45);                                  # read 45 characters
   close($fh);
 
   if($buf =~ /^\*\* Dump Completed (.*) \*\*$/) {        # verify if complete
      return 1;
   } else {
      return 0;
   }
}

#
# prune_dumps
#    Delete old backups but still keep enough to resolve any issues that
#    may accure.
#
#    Current rules are:
#        Keep last 5 files,
#        Keep any backups less then 12 hours old
#        Keep one backup per day for a week
#        Keep one backup per week for a month
#        Keep one backup per month for a month
#
sub prune_dumps
{
   my ($name,$filter) = @_;
   my ($prev,$last,$dir,%data);
   my $count = 0;

   opendir($dir,$name) ||
      die("Unable to find directory $dir");

   # sort by filename instead of timestamp
   for my $file (readdir($dir)) {
      if($file =~ /$filter/ && $file !~ /\.BAD$/i) {
         if(!dump_complete("$name/$file")) {
            move("$name/$file","$name/$file.BAD");     # rename but don't fail
         } elsif($file =~ /(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/) {
             my $ts = timelocal($6,$5,$4,$3,$2-1,$1);
             @data{$ts} = { day => $3, fn  => $file };
         }
      }
   }
   closedir($dir);

   for my $file (sort {$b <=> $a} keys %data) {
      my $hash = @data{$file};
      if(# at least the last 5 files
         $count++ < 5 ||

         #file once per hour for a day
#         time() - $file <  43200 ||

         # file once per day for a week
#         (time() - $file > 43200 && time() - $file < 604800 &&
#          $$hash{day} != $prev) ||

         # file at least once per week for a month
#         (time() - $file > 604800 && time() - $file < 4687200 &&
#          $last - $file >= 604800) ||

         # file at least once per month
#         (time() - $file > 4687200 && $last - $file >= 4687200)
 
          $last - $file >= 604800
        ) {
         $last = $file;
      } else {
         if(!unlink("$name/$$hash{fn}")) {
            printf("Delete file dumps/$$hash{fn} during cleanup FAILED.");
         } else {
		 #            printf("# Deleting $$hash{fn} as part of db backup cleanup\n");
         }
      }
      $prev = $$hash{day};
   }
}



#
# newest_full
#    Search for the newest dump file.
#
sub newest_full
{
    my (%list, $fh,$dir);
    my %list;

    if(!-d "dumps") {
      mkdir("dumps") ||
         die("Unable to create directory 'dumps'.");
    }

    opendir($dir,"dumps") ||
       die("Unable to find dumps directory");

    for my $file (readdir($dir)) {
       if($file =~ /^@info{"conf.mudname"}.FULL\.([\d_]+)\.tdb$/i && 
          dump_complete("dumps/$file")) {
          @list{"dumps/$file"} = (stat("dumps/$file"))[9];
       }
    }
    closedir($dir);

    return (sort { @list{$b} <=> @list{$a}}  keys %list)[0];
}

sub generic_action
{
   my ($self,$prog,$action,$src) = @_;

   if((my $atr = get($self,$action)) ne undef) {
         necho(self => $self,
               prog => $prog,
               room => [ $src, "%s %s", name($self), $atr  ],
         );
   }

   if((my $atr = get($self,"A$action")) ne undef) {
      mushrun(self   => $self,
              runas  => $self,
              cmd    => $atr,
              source => 0,
              from   => "ATTR",
             );
   }

   if((my $atr = get($self,"o$action")) ne undef) {
         necho(self => $self,
               prog => $prog,
               room => [ $self, "%s %s", name($self), $atr  ],
         );
   }
}

#
# glob2re
#    Convert a global pattern into a regular expression
#
sub glob2re {
    my ($pat) = ansi_remove(shift);

    return "^\s*\$" if $pat eq undef;
    $pat =~ s{(\W)}{
        $1 eq '?' ? '(.)' : 
        $1 eq '*' ? '(*PRUNE)(.*?)' :
        '\\' . $1
    }eg;

    $pat =~ s/\\\(.\)/?/g;

#    return "(?mnsx:\\A$pat\\z)";
    return "(?msix:\\A$pat\\z)";
}

#
# io
#    This function logs all input and output.
#
sub io
{
   return if memorydb;
   my ($self,$type,$data) = @_;

   return if($$self{obj_id} eq undef);

   my $tmp = $$db{rows};
   sql("insert into io" .
       "(" .
       "   io_type, ".
       "   io_data, " .
       "   io_src_obj_id, ".
       "   io_src_loc ".
       ") values ( ".
       "   ?, " .
       "   ?, " .
       "   ?, " .
       "   ? " .
       ")",
       $type,
       $data,
       $$self{obj_id},
       loc($self)
      );
   $$db{rows} = $tmp;
   my_commit;
}

#
# the mush program has finished, so clean up any telnet connections.
#
sub close_telnet
{
   my $prog = shift;

   if(!defined $$prog{telnet_sock}) {
      return;
   } elsif(!defined @connected{$$prog{telnet_sock}}) {
      return;
   } elsif(hasflag(@{@connected{$$prog{telnet_sock}}}{obj_id},
                   "SOCKET_PUPPET"
                  )
          ) {
         return;
   } else {
      my $hash = @connected{$$prog{telnet_sock}};
      # delete any pending input
      printf("Closed orphaned mush telnet socket to %s:%s\n",
          $$hash{hostname},$$hash{port});
      server_disconnect($$prog{telnet_sock});
      delete @$prog{telnet_sock};
   }
}

sub validate_switches
{
   my ($self,$prog,$switch,@switches) = @_;
   my (%hash,$name);

   @hash{@switches} = (0 .. $#switches);

   for my $key (keys %$switch) {
      if(!defined @hash{$key}) {
         if(@{$$prog{cmd}}{cmd} =~ /^\s*([^ \/]+)/) {
            $name = $1;
         } else {
            $name = "N/A";
         }
         necho(self => $self,
               prog => $prog,
               source => [ "Unrecognized switch '%s' for command '%s'",
                           $key,$name ],
         );
         return 0;
      }
   }
   return 1;
}


#
# err
#    Show the user a the provided message. These could be logged
#    eventually too.
#
sub err
{
   my ($self,$prog,$fmt,@args) = @_;

   necho(self => $self,
         prog => $prog,
         source => [ $fmt,@args ],
        );

   my_rollback if mysqldb;

   return 0;
#   return sprintf($fmt,@args);
   # insert log entry? 
}

sub first
{
   my ($txt,$delim) = @_;

   $delim = ';' if $delim eq undef;

   return (split($delim,$txt))[0];
}

sub pennies
{
   my $what = shift;
   my $amount;

   if(ref($what) eq "HASH" && defined $$what{obj_id}) {
      $amount = money($what);
   } elsif($what !~ /^\s*\-{0,1}(\d+)\s*$/) {
      $amount = @info{"conf.$what"};
   } else {
      $amount = $what;
   }

   if($amount == 1) {
      return $amount . " " . @info{"conf.money_name_singular"} . ".";
   } else {
      return $amount . " " . @info{"conf.money_name_plural"} . ".";
   }
}

sub code
{
   my $type = shift;
   my @stack;

#   if(Carp::shortmess =~ /#!\/usr\/bin\/perl/) {

   if(!$type || $type eq "short") {
      for my $line (split(/\n/,Carp::shortmess)) {
         if($line =~ /at ([^ ]+) line (\d+)\s*$/) {
            push(@stack,"$1:$2");
         }
      }
      return join(',',@stack);
   } else {
      return Carp::shortmess;
   }
}


sub string_escaped
{
   my $txt = shift;

   if($txt =~ /(\\+)$/) {
      return (length($1) % 2 == 0) ? 0 : 1;
   } else {
      return 0;
   }
}

#
# evaluate
#    Take a string and evaluate any functions, and mush variables
#
sub evaluate_substitutions
{
   my ($self,$prog,$t) = @_;
   my ($out,$seq);

   while($t =~ /(\\|%[brtn#0-9]|%v[0-9]|%w[0-9]|%=<[^>]+>|%\{[^}]+\})/i) {
      ($seq,$t)=($1,$');                                   # store variables
      $out .= $`;

      if($seq eq "\\") {                               # skip over next char
         $out .= substr($t,0,1);
         $t = substr($t,1);
      } elsif($seq eq "%b") {                                        # space
         $out .= " ";
      } elsif($seq eq "%r") {                                       # return
         $out .= "\n";
      } elsif($seq eq "%t") {                                          # tab
         $out .= "\t";
      } elsif($seq eq "%#") {                                # current dbref
         $out .= "#" . @{$$prog{created_by}}{obj_id};
      } elsif(lc($seq) eq "%n") {                          # current dbref
         $out .= name($$prog{created_by});
      } elsif($seq =~ /^%([0-9])$/ || $seq =~ /^%\{([^}]+)\}$/) {  # temp vars
         if($1 eq "hostname") {
            $out .= $$user{raw_hostname};
         } elsif($1 eq "socket") {
            $out .= $$user{raw_socket};
         } else {
            $out .= @{$$prog{var}}{$1} if(defined $$prog{var});
         }
      } elsif($seq =~ /^%(v|w)[0-9]$/ || $seq =~ /^%=<([^>]+)>$/) {  # attrs
         $out .= get($user,$1);
      }
   }

   return $out . $t;
}


#
# text
#    Generic function to return the results of a single column query.
#    Column needs to be aliased to text.
#
sub text
{
   my ($sql,@args) = @_;
   my $out; # = "---[ Start ]---\n";                              # add header

   for my $hash (@{sql($db,$sql,@args)}) {                      # run query
      $out .= $$hash{text} . "\n";                             # add output
   }
   # $out .= "---[  End  ]---";                                  # add footer
   return $out;
}

#
# table
#    Generic function to resturn the results of a multiple column
#    query. The results will be put into a nice text-based table
#    with column the columns sorted similar to the provided sql.
#
sub table
{
   my ($sql,@args) = @_;
   my ($out, @data, @line, @header, @keys, %order, %max,$count,@pos);

   if(memorydb) {
      return "Not supported in MemoryDB";
   }
   # determine column order from the original sql
   if($sql =~ /^\s*select (.+?) from/) {
      for my $field (split(/\s*,\s*/,$1)) {
         if($field =~ / ([^ ]+)\s*$/) {
            @order{lc(trim($1))} = ++$count;
         } else {
            @order{lc(trim($field))} = ++$count;
         }
      }
   }

   # determine the max column length for each column, and store the
   # output of the sql so it doesn't have to be run twice.
#   echo($user,"%s",$sql);
   for my $hash (@{sql($db,$sql,@args)}) {
      push(@data,$hash);                                     # store results
      for my $key (keys %$hash) {
         if(length($$hash{$key}) > $max{$key}) {         # determine  if max
             @max{$key} = length($$hash{$key});
         }
                             # make max minium size that of the column name
         @max{$key} = length($key) if(length($key) > $max{$key});
      }
   }

   return "No data found" if($#data == -1);

   for my $i (0 .. $#data) {                        # cycle through each row
      my $hash = $data[$i];
      delete @line[0 .. $#line];

      if($#pos == -1) {                            # create sort order once
         @pos = (sort {@order{lc($a)} <=> @order{lc($b)}} keys %$hash);
      }
      for my $key (@pos) {                       # cycle through each column
         if($i == 0) {
            push(@header,"-" x $max{$key});        # add first row of header
            push(@keys,sprintf("%-*s",$max{$key},$key));
         }
         push(@line,sprintf("%-*s",$max{$key},$$hash{$key}));   # add column
      }
      if($i == 0) {                          # add second/third row of header
         $out .= join(" | ",@keys) . "\n"; # add 
         $out .= join("-|-",@header) .  "\n";
      }
      $out .= join(" | ",@line) . "\n"; # add pre-generated column to output
   }
   $out .= join("- -",@header) . "\n";                          # add footer
   return $out;
}


#
# controls
#    Does the $enactor control the $target?
#
sub controls
{
   my ($enactor,$target,$flag) = (obj(shift),obj(shift),shift);

   if($$enactor{obj_id} eq @info{"conf.godlike"}) {
      return 1;
   } elsif($$target{obj_id} == 0 && $$enactor{obj_id} != 0) {
      return 0;
   } elsif(owner_id($enactor) == owner_id($target)) {
      return 1; 
   } elsif(hasflag($enactor,"WIZARD")) {
      return 1;
   } else {
      return 0;
   }
}

sub handle_object_listener
{
   my ($target,$txt,@args) = @_;
   my $msg = sprintf($txt,@args);
   my $count;

   $msg =~ s/(%|\\)/\\$1/g;
   for my $hash (latr_regexp($target,3)) {
      if($msg =~ /$$hash{atr_regexp}/i) {
         mushrun(self   => $target,
                 runas  => $target,
                 cmd    => single_line($$hash{atr_value}),
                 wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                 source => 0,
                 from   => "ATTR",
                );
         $count++;
      }
   }
}

sub handle_listener
{
   my ($self,$prog,$runas,$txt,@args) = @_;
   my $match = 0;

   my $msg = sprintf($txt,@args);
   for my $obj (lcon(loc($self))) {

      # don't listen to one self, or doesn't have listener flag
      next if($$obj{obj_id} eq $$self{obj_id} || !hasflag($obj,"LISTENER"));

      for my $hash (latr_regexp($obj,2)) {
         if(atr_case($obj,$$hash{atr_name})) {
            if($msg =~ /$$hash{atr_regexp}/) {
               mushrun(self   => $self,
                       runas => $obj,
                       cmd    => $$hash{atr_value},
                       wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                       source => 0,
                      );
                $match=1;
            }
         } elsif($msg =~ /$$hash{atr_regexp}/i) {
            mushrun(self   => $self,
                    runas => $obj,
                    cmd    => $$hash{atr_value},
                    wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                    source => 0,
                   );
             $match=1;
         }
      }
   }
   return $match;
}

sub nospoof
{
   my ($self,$prog,$dest) = (obj($_[0]),obj($_[1]),obj($_[2]));

   if(hasflag($dest,"NOSPOOF")) {
#      printf("%s\n",code("long"));
      return "[" . obj_name($self,$$prog{created_by},1) . "] ";
   }
   return undef;
}

sub ts
{
   my $time = shift;

   $time = time() if $time eq undef;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime($time);
   $mon++;

   return sprintf("%02d:%02d@%02d/%02d",$hour,$min,$mon,$mday);
}

sub minits
{
   my $time = shift;

   $time = time() if $time eq undef;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime($time);
   $mon++;

   return sprintf("%02d:%02d:%02d %02d/%02d/%02d",
                  $hour,$min,$sec,$mon,$mday,$year % 100);
}

sub filter_chars
{
   my $txt = shift;
   $txt .= "\n" if($txt !~ /\n$/);                # add return if none exists
   $txt =~ s/\n/\r\n/g if($txt !~ /\r/);                      # add linefeeds
   $txt =~ tr/\x80-\xFF//d;                             # strip control chars

   return $txt;
}



# echo(self   => $self,
#      prog   => $prog,
#      room   => [ $target, "msg", @args ],
#      source => [ "msg", @args ],
#      target => [ $target, "msg", @args ]
# )


sub log_output
{
   my ($src,$dst,$loc,$txt) = (obj(shift),obj(shift),shift,shift);

   return if memorydb;
   return if($$src{obj_id} eq undef);

   $txt =~ s/([\r\n]+)$//g;

   my $tmp = $$db{rows}; # its easy to try to necho() data before testing
                         # against $$db{rows}, which  will clear $$db{rows}.
                         # so we'll revert it after the below sql() call.

   sql($db,                                     #store output in output table
       "insert into io" .
       "(" .
       "   io_data, " .
       "   io_type, ".
       "   io_src_obj_id, ".
       "   io_src_loc, ".
       "   io_dst_obj_id, ".
       "   io_dst_loc ".
       ") values ( ".
       "   ?, " .
       "   ?, " .
       "   ?, " .
       "   ?," .
       "   ?, " .
       "   ? " .
       ")",
       substr($txt,0,63999),
       2,
       $$src{obj_id},
       loc($src),
       $$dst{obj_id},
       loc($dst),
      );
#    sql($db,                                     #store output in output table
#        "insert into output" .
#        "(" .
#        "   out_text, " .
#        "   out_source, ".
#        "   out_location, ".
#        "   out_destination ".
#        ") values ( ".
#        "   ?, " .
#        "   ?, " .
#        "   ?, " .
#        "   ? " .
#        ")",
#        substr($txt,0,63999),
#        $$src{obj_id},
#        $loc,
#        $$dst{obj_id}
#       );
   $$db{rows} = $tmp;
   my_commit;
}


sub echo_socket
{
   my ($obj,$prog,$fmt,@args) = (obj(shift),shift,shift,@_);

   my $msg = sprintf($fmt,@args);
   if(defined @connected_user{$$obj{obj_id}}) {
      my $list = @connected_user{$$obj{obj_id}};

      for my $socket (keys %$list) {
         my $s = $$list{$socket};

         if(@{@connected{$s}}{type} eq "WEBSOCKET" && !hasflag($obj,"ANSI")) {
             ws_echo($s,ansi_remove($msg));
         } elsif(@{@connected{$s}}{type} eq "WEBSOCKET") {
             ws_echo($s,$msg);
         } elsif(!hasflag($obj,"ANSI")) {
             printf($s "%s",ansi_remove($msg));
         } else {
            printf($s "%s",$msg);
         }
      }
   } elsif(hasflag($obj,"PUPPET") && !hasflag($obj,"PLAYER")) {
      my $owner = owner($obj);
      if(defined @connected_user{$$owner{obj_id}}) {
         my $list = @connected_user{$$owner{obj_id}};

         for my $socket (keys %$list) {
            my $s = $$list{$socket};
   
            if(@{@connected{$s}}{type} eq "WEBSOCKET" && hasflag($obj,"ANSI")) {
                ws_echo($s,name($obj) . "> " .$msg);
            } elsif(@{@connected{$s}}{type} eq "WEBSOCKET") {
                ws_echo($s,name($obj) . "> " . ansi_remove($msg));
            } elsif(!hasflag($obj,"ANSI")) {
               printf($s "%s> %s",name($obj),ansi_remove($msg));
            } else {
               printf($s "%s> %s",name($obj),$msg);
            }
         }
      }
   } elsif(defined $$obj{sock}) {
      if(defined @connected{$$obj{sock}} && 
         @{@connected{$$obj{sock}}}{type} eq "WEBSOCKET") {
         ws_echo($$obj{sock},ansi_remove($msg));
      } else {
         my $s = $$obj{sock};
         printf($s "%s", ansi_remove($msg));
      }
   }
}


sub necho
{
   my %arg = @_;
   my $prog = $arg{prog};
   my $self = $arg{self};
   my $loc;

   if($arg{self} eq undef) {
      printf("%s\n",print_var(\%arg));
      printf("%s\n",code("long"));
   }

   if(loggedin($self)) {
      # skip checks for non-connected players
   } elsif(!defined $arg{self}) {             # checked passed in arguments
      err($self,$prog,"Echo expects a self argument passed in");
   } elsif(!defined $arg{prog}) {
      err($self,$prog,"Echo expects a prog argument passed in");
   } elsif(defined $arg{room}) {
      if(ref($arg{room}) ne "ARRAY") {
         err($self,$prog,"Echo expects a room argument expects array data");
      } elsif(ref(@{$arg{room}}[0]) ne "HASH") {
         err($self,$prog,"Echo expects first room argument to be HASH " .
             "data '%s'",@{$arg{room}}[0]);
      }
   }

   for my $type ("room", "room2","all_room","all_room2") {  # handle room echos
      if(defined $arg{$type}) {
         my $array = $arg{$type};
         my $target = obj(shift(@$array));
         my $fmt = shift(@$array);
         my $msg = filter_chars(sprintf($fmt,@{$arg{$type}}));
         $target = loc($target) if(!hasflag($target,"ROOM"));

         for my $obj ( lcon($target) ) {
            if($$self{obj_id} != $$obj{obj_id} || $type =~ /^all_/) {
               echo_socket($obj,
                           @arg{prog},
                           "%s%s",
                           nospoof($self,$prog,$obj),
                           $msg
                          );
            }
         }
         handle_listener($self,$prog,$target,$fmt,@$array);
      }
   }
 
   unshift(@{$arg{source}},$self) if(defined $arg{source});

   for my $type ("source", "target") {
      next if !defined $arg{$type};

      if(ref($arg{$type}) ne "ARRAY") {
         return err($self,$prog,"Argument $type is not an array");
      }

      my ($target,$fmt) = (shift(@{$arg{$type}}), shift(@{$arg{$type}}));
      my $msg = filter_chars(sprintf($fmt,@{$arg{$type}}));


      # output needs to be saved for use by http, websocket, or run()
      if(defined $$prog{output} && 
         (@{$$prog{created_by}}{obj_id} == $$target{obj_id} ||
          $$self{obj_id} == $$target{obj_id} ||
          $$target{obj_id} == @info{"conf.webuser"} || 
          $$target{obj_id} == @info{"conf.webobject"}
         )
        ) {
            my $stack = $$prog{output};
            push(@$stack,$msg);
            next;
      }

      if(!loggedin($target) && 
         !defined $$target{port} && 
         !defined $$target{hostname} && defined $$target{sock}) {
         my $s = @{$connected{$$self{sock}}}{sock};

         # this might crash if the websocket dies, the evals should
         # probably be removed once this is more stable. With that in mind,
         # currently crash will be treated as a disconnect.
         if(defined @connected{$s} &&
            @{@connected{$s}}{type} eq "WEBSOCKET") {
             ws_echo($s,$msg);
         } elsif(defined @connected{$s}) {
            printf($s "%s",$msg);
         }
      } elsif(!loggedin($target)) {
         echo_socket($target,
                     @arg{prog},
                     "%s",
                     $msg
                    );
      } else {
         log_output($self,$target,-1,$msg);

         echo_socket($$target{obj_id},
                     @arg{prog},
                     "%s%s",
                     nospoof(@arg{self},@arg{prog},$$target{obj_id}),
                     $msg
                    );
      }
   }
}

#
# echo_no_log
#    The same as the echo function but without logging anything to the
#    output table.
#
sub echo_nolog
{
   my ($target,$fmt,@args) = @_;
   my $match = 0;

   my $out = sprintf($fmt,@args);
   $out .= "\n" if($out !~ /\n$/);
   $out =~ s/\n/\r\n/g if($out !~ /\r/);

#   if(hasflag($target,"PLAYER")) {
      for my $key (keys %connected) {
         if($$target{obj_id} eq @{$connected{$key}}{obj_id}) {
            my $sock = @{$connected{$key}}{sock};
            if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
               ws_echo($sock,$out);
            } else {
               printf($sock "%s",$out);
            }
         }
      }
#   }
}

#
# e
#    set the number of rows the sql should return, so that sql()
#    can error out if the wrong amount of data is returned. This
#    may be a silly way of doing this.
#
sub e
{
   my ($db,$expect) = @_;

   $$db{expect} = $expect;
   return $db;
}


sub echo_flag
{
   my ($self,$prog,$flags,$fmt,@args) = @_;

   for my $key (keys %connected) {
      my $echo = 1;

      if(defined @{@connected{$key}}{obj_id}) {
         for my $flag (split(/,/,$flags)) {
            if(!hasflag(@{@connected{$key}}{obj_id},$flag)) {
               $echo = 0;
               last;
            }
         }
         if($echo) {
            necho(self => $self,
                  prog => $prog,
                  target => [ obj(@{@connected{$key}}{obj_id}), $fmt, @args ]
                 );
         }
      }
   }
}

sub connected_socket
{
   my $target = shift;
   my @result;

   if(!defined @connected_user{$$target{obj_id}}) {
      return undef;
   }
   return keys %{@connected_user{$$target{obj_id}}};
}

sub connected_user
{
   my $target = shift;

   if(!defined @connected_user{$$target{obj_id}}) {
      return undef;
   }
   my $hash = @connected_user{$$target{obj_id}};
   for my $key (keys %$hash) {
      if($key eq $$target{sock}) {
         return $key;
      }
   }
   return undef;
}

sub loggedin
{
   my $target = obj(shift);

  
   if(defined $$target{obj_id} && 
      defined @connected_user{$$target{obj_id}}) {
      return 1;
   } else {
      return 0;
   } 
}

sub valid_dbref 
{
   my $id = obj(shift);
   $$id{obj_id} =~ s/#//g;

   if(memorydb) {
      if($$id{obj_id} =~ /^\s*(\d+)\s*$/) {
         if(defined @info{backup_mode} && @info{backup_mode}) {
            if(defined @db[$1] || defined @delta[$1]) {
               return 1;
            }
         } else {
            return (defined @db[$$id{obj_id}]) ? 1 : 0;
         }
      }
   }  elsif(owner($id) eq undef) {                # owner will return undef on 
      return 0;                            # non-existant objects & its cached
   } else {
      return 1;
   }
}

sub owner_id
{

   my $object = obj(shift);

   my $owner = owner($object);
   return $owner if $owner eq undef;
   return $$owner{obj_id};
}


#
# set_flag
#   Add a flag to an object. Verify that the object does not already have
#   the flag first.
#
sub set_flag
{
   my ($self,$prog,$obj,$flag,$override) = 
      (obj($_[0]),$_[1],obj($_[2]),uc($_[3]),$_[4]);
   my $who = $$user{obj_name};;
   my ($remove,$count);

   if(!$override && !controls($user,$obj)) {
      return err($self,$prog,"#-1 PERMission denied.");
   }

   if(!is_flag($flag)) {
      return "I don't understand that flag.";
   } elsif(memorydb) {
      if($flag =~ /^\s*!\s*/) {
         $remove = 1;
         $flag = trim($');
      }

      if(!$override && !can_set_flag($self,$obj,$flag)) {
         return "Permission DeNied";
      } elsif($remove) {                  # remove, don't check if set or not
         db_remove_list($obj,"obj_flag",$flag);       # to mimic original mush
         return "Cleared.";
      } else {
         db_set_list($obj,"obj_flag",$flag);
         return "Set.";
      }
   } else {
       $who = "CREATE_USER" if($flag eq "PLAYER" && $who eq undef);
       ($flag,$remove) = ($',1) if($flag =~ /^\s*!\s*/);         # remove flag
   
       # lookup flag info
       my $hash = one($db,
           "select fde1.fde_flag_id, " .
           "       fde1.fde_name, " .
           "       fde2.fde_name fde_permission_name," .
           "       fde1.fde_permission" .
           "       from flag_definition fde1," .
           "            flag_definition fde2 " .
           " where fde1.fde_permission = fde2.fde_flag_id " .
           "   and fde1.fde_type = 1 " .
           "   and fde2.fde_type = 1 " .
           "   and fde1.fde_name=upper(?)",
           $flag
          );
   
       if($hash eq undef || !defined $$hash{fde_flag_id} ||
          $$hash{fde_name} eq "ANYONE") {       # unknown flag?
          return "#-1 Unknown Flag.";
       }
   
       if(!perm($user,$$hash{fde_name}) && $flag ne "PLAYER") {
          return "#-1 PERMission Denied.";
       }
   
       if($override || $$hash{fde_permission_name} eq "ANYONE" ||
          ($$hash{fde_permission} >= 0 &&
           hasflag($user,$$hash{fde_permission_name})
          )) {
   
          # check if the flag is already set
          my $count = one_val($db,"select count(*) value from flag ".
                                  " where obj_id = ? " .
                                  "   and fde_flag_id = ?" .
                                  "   and atr_id is null ",
                                  $$obj{obj_id},
                                  $$hash{fde_flag_id});
   
          # add flag to the object/user
          if($count > 0 && $remove) {
             sql($db,"delete from flag " .
                     " where obj_id = ? " .
                     "   and fde_flag_id = ?",
                     $$obj{obj_id},
                     $$hash{fde_flag_id});
   
             remove_flag_cache($obj,$flag);
   
             my_commit;
             if($flag =~ /^\s*(PUPPET|LISTENER)\s*$/i) {
                necho(self => $self,
                      prog => $prog,
                      all_room => [$obj,"%s is no longer listening.",
                         $$obj{obj_name} ]
                     );
             }
             return "Flag Removed.";
          } elsif($remove) {
             return "Flag not set.";
          } elsif($count > 0) {
             return "Already Set.";
          } else {
             if($flag =~ /^\s*(PUPPET|LISTENER)\s*$/i) {
                necho(self => $self,
                      prog => $prog,
                      all_room => [ $obj,
                                    "%s is now listening.", 
                                    $$obj{obj_name} ]
                     );
             }
             sql($db,
                 "insert into flag " .
                 "   (obj_id,ofg_created_by,ofg_created_date,fde_flag_id)" .
                 "values " .
                 "   (?,?,now(),?)",
                 $$obj{obj_id},
                 $who,
                 $$hash{fde_flag_id});
             my_commit;
             if($$db{rows} != 1) {
                return "#-1 Flag not removed [Internal Error]";
             }
             remove_flag_cache($obj,$flag);

             set_cache($obj,"FLAG_$flag",1);
   
             return "Set.";
          }
       } else {
          return "#-1 Permission Denied.";
       }
   }
}

#
# set_atr_flag
#   Add a flag to an object. Verify that the object does not already have
#   the flag first.
#
sub set_atr_flag
{
    my ($object,$atr,$flag,$override) = (obj($_[0]),$_[1],$_[2],$_[3]);
    my $who = $$user{obj_name};
    my ($remove,$count);
    $flag = uc(trim($flag));

    $who = "CREATE_USER" if($flag eq "PLAYER" && $who eq undef);
    ($flag,$remove) = ($',1) if($flag =~ /^\s*!\s*/);         # remove flag 
    

    # lookup flag info
    my $hash = one($db,
        "select fde1.fde_flag_id, " .
        "       fde1.fde_name, " .
        "       fde2.fde_name fde_permission_name," .
        "       fde1.fde_permission" .
        "       from flag_definition fde1," .
        "            flag_definition fde2 " .
        " where fde1.fde_permission = fde2.fde_flag_id " .
        "   and fde1.fde_type = 2 " .
        "   and fde1.fde_name=trim(upper(?))",
        $flag
       );

    if($hash eq undef || !defined $$hash{fde_flag_id} ||
       $$hash{fde_name} eq "ANYONE") {       # unknown flag?
       return "#-1 Unknown Flag. ($flag)";
    }

    if(!perm($object,$$hash{fde_name})) {
       return "#-1 Permission Denied.";
    }

    if($override || $$hash{fde_permission_name} eq "ANYONE" ||
       ($$hash{fde_permission} >= 0 && 
        hasflag($user,$$hash{fde_permission_name})
       )) {

       # check if the flag is already set

       my $atr_id = one_val($db,
                     "select atr.atr_id value " .
                     "  from attribute atr left join  " .
                     "       (flag flg) on (flg.atr_id = atr.atr_id) " .
                     " where atr.obj_id = ? " .
                     "   and atr_name = upper(?) ",
                     $$object{obj_id},
                     $atr
                    );

       if($atr_id eq undef) {
          return "#-1 Unknown attribute on object";
       }

       # see if flag is already set
       my $flag_id = one_val($db,
                             "select ofg_id value " .
                             "  from flag " .
                             " where atr_id = ? " .
                             "   and fde_flag_id = ?",
                             $atr_id,
                             $$hash{fde_flag_id}
                            );
                               
       # add flag to the object/user
       if($flag_id ne undef && $remove) {
          sql($db,
              "delete from flag " .
              " where ofg_id= ? ",
              $flag_id
             );
          my_commit;

          set_cache_atrflag($object,$atr,$flag);
          return "Flag Removed.";
       } elsif($remove) {
          return "Flag not set.";
       } elsif($flag_id ne undef) {
          return "Already Set.";
       } else {
          sql($db,
              "insert into flag " .
              "   (obj_id,ofg_created_by,ofg_created_date,fde_flag_id,atr_id)" .
              "values " .
              "   (?,?,now(),?,?)",
              $$object{obj_id},
              $who,
              $$hash{fde_flag_id},
              $atr_id);
          my_commit;
          return "#-1 Flag note removed [Internal Error]" if($$db{rows} != 1);
          set_cache_atrflag($object,$atr,$flag);
          return "Set.";
       }
    } else {
       return "#-1 Permission Denied."; 
    }
} 

sub perm
{
   my ($target,$perm) = (obj(shift),shift);

   return 0 if(defined $$target{loggedin} && !$$target{loggedin});
   return 1;

   $perm =~ s/@//;
   my $owner = owner($$target{obj_id});
   my $result = one_val($db,
                  "select min(fpr_permission) value " .
                  "  from flag_permission fpr1, ".
                  "       flag flg1 " .
                  " where fpr1.fde_flag_id = flg1.fde_flag_id " .
                  "   and flg1.obj_id = ? " .
                  "   and fpr1.fpr_name in ('ALL', upper(?) )" .
                  "   and atr_id is null " .
                  "   and not exists ( " .
                  "      select 1 " .
                  "        from flag_permission fpr2, flag flg2 " .
                  "       where fpr1.fpr_priority > fpr2.fpr_priority " .
                  "         and flg2.fde_flag_id = fpr2.fde_flag_id " .
                  "         and flg2.fde_flag_id = flg1.fde_flag_id " .
                  "         and flg2.obj_id = flg1.obj_id " .
                  "   ) " .
                  "group by obj_id",
                  $$owner{obj_id},
                  $perm
                 );
    if($result eq undef) {
       return 0;
    } else {
       return ($result > 0) ? 1 : 0;
    }
}

#
# destroy_object
#    Delete an object from the database and cache.
#
sub destroy_object 
{
    my $obj = obj(shift);

   my $loc = loc($obj);

   sql("delete " .
       "  from object ".
       " where obj_id = ?",
       $$obj{obj_id}
      );

   if($$db{rows} != 1) {
      my_rollback;
      return 0;
   }  else {
      delete $cache{$$obj{obj_id}};
      set_cache($loc,"lcon");
      set_cache($loc,"con_source_id");
      set_cache($loc,"lexits");
      my_commit;

      return 1;
   }
}

sub create_object
{
   my ($self,$prog,$name,$pass,$type) = @_;
   my ($where,$id);
   my $who = $$user{obj_name};
   my $owner = $$user{obj_id};

   # check quota
   if($type ne "PLAYER" && quota_left($$user{obj_id}) <= 0) {
      return 0;
   }
  
   if($type eq "PLAYER") {
      $where = get(0,"CONF.STARTING_ROOM");
      $where =~ s/^\s*#//;
      $who = $$user{hostname};
      $owner = 0;
   } elsif($type eq "OBJECT") {
      $where = $$user{obj_id};
   } elsif($type eq "ROOM") {
      $where = -1;
   } elsif($type eq "EXIT") {
      $where = -1;
   }

   if(memorydb) {
      my $id = get_next_dbref();
      db_delete($id);
      db_set($id,"obj_name",$name);
      if($pass ne undef && $type eq "PLAYER") {
         db_set($id,"obj_password",mushhash($pass));
      }
 
      my $out = set_flag($self,$prog,$id,$type,1);

      if($out =~ /^#-1 /) {
         necho(self => $self,
               prog => $prog,
               source => [ "%s", $out ]
              );
         db_delete($id);
         push(@free,$id);
         return undef;
      }

      if($type eq "PLAYER") {
         db_set($id,"obj_home",$where);
         @player{lc($name)} = $id;
         printf("Addiing: %s => '%s'\n",lc($name),$id);
      } else {
         db_set($id,"obj_home",$$self{obj_id});
      }

      db_set($id,"obj_owner",$$self{obj_id});
      db_set($id,"obj_created_date",scalar localtime());
      if($type eq "PLAYER" || $type eq "OBJECT") {
         move($self,$prog,$id,$where);
      }
      return $id;

   } else {
      # find an id to reuse. You shouldn't refuse IDs in a db, but it
      # part of the "charm" of a MUSH.
      my $id = one_val("select a.obj_id + 1 value ".
                       "  from object a ".
                       "     left join object b ".
                       "        on a.obj_id + 1 = b.obj_id ".
                       "where b.obj_id is null ".
                       "  and a.obj_id is not null ".
                       "limit 1"
                      );
      if($id ne undef) {
         sql($db,
             " insert into object " .
             "    (obj_id,obj_name,obj_password,obj_owner,obj_created_by," .
             "     obj_created_date, obj_home " .
             "    ) ".
             "values " .
             "   (?, ?,password(?),?,?,now(),?)",
             $id,$name,$pass,$owner,$who,$where);
      } else {
         sql($db,
             " insert into object " .
             "    (obj_name,obj_password,obj_owner,obj_created_by," .
             "     obj_created_date, obj_home " .
             "    ) ".
             "values " .
             "   (?,password(?),?,?,now(),?)",
             $name,$pass,$owner,$who,$where);
      }
   }

   if($$db{rows} != 1) {                           # oops, nothing happened
      necho(self => $self,
            prog => $prog,
            source => [ "object #%s was not created", $id ]
           );
      my_rollback($db);
      return undef;
   }

   if($id eq undef) {                             # grab newly created id
      $id = one_val($db,"select last_insert_id() obj_id") ||
          return my_rollback($db);
   }

   my $out = set_flag($self,$prog,$id,$type,1);
   if($out =~ /^#-1 /) {
      necho(self => $self,
            prog => $prog,
            source => [ "%s", $out ]
           );
      return undef;
   }
   if($type eq "PLAYER" || $type eq "OBJECT") {
      move($self,$prog,$id,fetch($where));
   }
   return $id;
}



sub curval
{
   return one_val($db,"select last_insert_id() value");
}

#
# ignoreit
#    Ignore certain hash key entries at all depths or just the specified
#    depth.
#
sub ignoreit
{
   my ($skip,$key,$depth) = @_;


   if(!defined $$skip{$key}) {
      return 0;
   } elsif($$skip{$key} < 0 || ($$skip{$key} >= 0 && $$skip{$key} == $depth)) {
     return 1;
   } else {
     return 0;
   }
}

#
# print_var
#    Return a "text" printable version of a HASH / Array
#
sub print_var
{
   my ($var,$depth,$name,$skip,$recursive) = @_;
   my ($PL,$PR) = ('{','}');
   my $out;

   if($depth > 4) {
       return (" " x ($depth * 2)) .  " -> TO_BIG\n";
   }
   $depth = 0 if $depth eq "";
   $out .= (" " x ($depth * 2)) . (($name eq undef) ? "UNDEFINED" : $name) .
           " $PL\n" if(!$recursive);
   $depth++;

   for my $key (sort ((ref($var) eq "HASH") ? keys %$var : 0 .. $#$var)) {

      my $data = (ref($var) eq "HASH") ? $$var{$key} : $$var[$key];

      if((ref($data) eq "HASH" || ref($data) eq "ARRAY") &&
         !ignoreit($skip,$key,$depth)) {
         $out .= sprintf("%s%s $PL\n"," " x ($depth*2),$key);
         $out .= print_var($data,$depth+1,$key,$skip,1);
         $out .= sprintf("%s$PR\n"," " x ($depth*2));
      } elsif(!ignoreit($skip,$key,$depth)) {
         $out .= sprintf("%s%s = %s\n"," " x ($depth*2),$key,$data);
      }
   }

   $out .= (" " x (($depth-1)*2)) . "$PR\n" if(!$recursive);
   return $out;
}


sub inuse_player_name
{
   my ($name) = @_;
   $name =~ s/^\s+|\s+$//g;

   if(memorydb) {
      return defined @player{lc($name)} ? 1 : 0;
   } else {
      my $result = one_val($db,
                     "select if(count(*) = 0,0,1) value " .
                     "  from object obj, flag flg, flag_definition fde " .
                     " where obj.obj_id = flg.obj_id " .
                     "   and flg.fde_flag_id = fde.fde_flag_id " .
                     "   and fde.fde_name = 'PLAYER' " .
                     "   and atr_id is null " .
                     "   and fde_type = 1 " .
                     "   and lower(obj_name) = lower(?) ",
                     $name
                    );
      return $result;
   }
}

#
# give_money
#    Give money to a person. Objects can't have money, so its given to
#    the object's owner.
#
sub give_money
{
   my ($target,$amount) = (obj(shift),shift);
   my $owner = owner($target);

   # $money doesn't contain a number
   return undef if($amount !~ /^\s*\-{0,1}(\d+)\s*$/);

   my $money = money($target);

   if(memorydb) {
      db_set($owner,"money",$money + $amount);
   } else {
      sql("update object " .
          "   set obj_money = ? ".
          " where obj_id = ? ",
          $money + $amount,
          $$owner{obj_id});

      return undef if($$db{rows} != 1);
      set_cache($target,"obj_money",$money + $amount);
   }

   return 1;
}

sub set
{
   my ($self,$prog,$obj,$attribute,$value,$quiet)=
      ($_[0],$_[1],obj($_[2]),$_[3],$_[4],$_[5]);
   my ($pat,$first,$type);

   # don't strip leading spaces on multi line attributes
   if(!@{$$prog{cmd}}{multi}) {
       $value =~ s/^\s+//g;
   }

   if($attribute !~ /^\s*([#a-z0-9\_\-\.]+)\s*$/i) {
      err($self,$prog,"Attribute name is bad, use the following characters: " .
           "A-Z, 0-9, and _ : $attribute");
   } elsif($value =~ /^\s*$/) {
      if(memorydb) {
         if(reserved($attribute)) {
            err($self,$prog,"That attribute name is reserved.");
         } else {
            db_set($obj,$attribute,undef);
            if(!$quiet) {
                necho(self => $self,
                      prog => $prog,
                      source => [ "Set." ]
                     );
            }
         }
      } else {
         sql($db,
             "delete " .
             "  from attribute " .
             " where atr_name = ? " .
             "   and obj_id = ? ",
             lc($attribute),
             $$obj{obj_id}
            );
         set_cache($obj,"latr_regexp_1");
         set_cache($obj,"latr_regexp_2");
         set_cache($obj,"latr_regexp_3");
         necho(self   => $self,
               prog   => $prog,
               source => [ "Set." ]
              );
      }
   } else {
      if(memorydb) {
         if(reserved($attribute)) {
            err($self,$prog,"That attribute name is reserved.");
         } else {
            db_set($obj,$attribute,$value);
            if(!$quiet) {
                necho(self => $self,
                      prog => $prog,
                      source => [ "Set." ]
                     );
            }
         }
      } else {
         # match $/^/! till the first unescaped :
         if($value =~ /([\$\^\!])(.+?)(?<![\\])([:])/) {
            ($pat,$value) = ($2,$');
            if($1 eq "\$") {
               $type = 1;
            } elsif($1 eq "^") {
               $type = 2;
            } elsif($1 eq "!") {
               $type = 3;
            }
            $pat =~ s/\\:/:/g;
         } else {
            $type = 0;
         }
   
         sql("insert into attribute " .
             "   (obj_id, " .
             "    atr_name, " .
             "    atr_value, " .
             "    atr_pattern, " .
             "    atr_pattern_type,  ".
             "    atr_regexp, ".
             "    atr_first,  ".
             "    atr_created_by, " .
             "    atr_created_date, " .
             "    atr_last_updated_by, " .
             "    atr_last_updated_date)  " .
             "values " .
             "   (?,?,?,?,?,?,?,?,now(),?,now()) " .
             "ON DUPLICATE KEY UPDATE  " .
             "   atr_value=values(atr_value), " .
             "   atr_pattern=values(atr_pattern), " .
             "   atr_pattern_type=values(atr_pattern_type), " .
             "   atr_regexp=values(atr_regexp), " .
             "   atr_first=values(atr_first), " .
             "   atr_last_updated_by=values(atr_last_updated_by), " .
             "   atr_last_updated_date = values(atr_last_updated_date)",
             $$obj{obj_id},
             uc($attribute),
             $value,
             $pat,
             $type,
             glob2re($pat),
             atr_first($pat),
             $$user{obj_name},
             $$user{obj_name}
            );
   
         set_cache($obj,"latr_regexp_1");
         set_cache($obj,"latr_regexp_2");
         set_cache($obj,"latr_regexp_3");
         if($$obj{obj_id} eq 0 && $attribute =~ /^conf./i) {
            @info{$attribute} = $value;
         }
   
         if(!$quiet) {
             necho(self => $self,
                   prog => $prog,
                   source => [ "Set." ]
                  );
         }
      }
   }
}

sub get
{
   my ($obj,$attribute,$flag) = (obj($_[0]),$_[1],$_[2]);
   my $hash;

   $attribute = "description" if(lc($attribute) eq "desc");
  
   if(memorydb) {
      my $attr = mget($obj,$attribute);

      if(ref($attr) eq "HASH") {
         if(defined $$attr{regexp}) {
           return "$$attr{type}$$attr{glob}:$$attr{value}";
         } else {
            return $$attr{value};
         } 
      } else {
        return undef;
      }
   } else {
      if((my $hash = one($db,"select atr_value, " .
                             "       atr_pattern, ".
                             "       atr_pattern_type ".
                             "  from attribute " .
                             " where obj_id = ? " .
                             "   and atr_name = upper( ? )",
                             $$obj{obj_id},
                             $attribute
                            ))) {
         if($$hash{atr_pattern} ne undef && !$flag) {
            my $type;                            # rebuild full attribute value
            if($$hash{atr_pattern_type} == 1) {
               $type = "\$";
            } elsif($$hash{atr_pattern_type} == 2) {
               $type = "^";
            } elsif($$hash{atr_pattern_type} == 3) {
               $type = "!";
            }
            return $type . $$hash{atr_pattern} . ":" . $$hash{atr_value};
         } else {                                      # no pattern to rebuild
            return $$hash{atr_value};
         }
      } else {                                                 # atr not found
         return undef;
      }
   }
}

sub loc
{
   my $loc = loc_obj($_[0]);
   return ($loc eq undef) ? undef : $$loc{obj_id};
}

sub player
{
   my $obj = shift;
   return hasflag($obj,"PLAYER");
}

sub same
{
   my ($one,$two) = @_;
   return ($$one{obj_id} == $$two{obj_id}) ? 1 : 0;
}

sub obj_ref
{
   my $obj  = shift;

   if(ref($obj) eq "HASH") {
      return $obj;
   } else {
      return fetch($obj);
   }
}

sub obj_name
{
   my ($self,$obj,$flag,$noansi) = (obj(shift),obj(shift),shift,shift);

   if(controls($self,$obj) || $flag) {
      return name($obj,$noansi) . "(#" . $$obj{obj_id} . flag_list($obj) . ")";
   } else {
      return name($obj,$noansi);
   }
}

#
# date_split
#    Segment up the seconds into somethign more readable then displaying
#    some large number of seconds.
#
sub date_split
{
   my $time = shift;
   my (%result,$num);

   # define how the date will be split up (i.e by month,day,..)
   my %chart = ( 3600 * 24 * 30 => 'M',
                 3600 * 24 * 7 => 'w',
                 3600 * 24 => 'd',
                 3600 => 'h',
                 60 => 'm',
                 0 => 's',
               );

    # loop through the chart and split the dates up
    for my $i (sort {$b <=> $a} keys %chart) {
       if($i == 0) {                             # handle seconds/leftovers
          @result{s} = ($time > 0) ? $time : 0;
          if(!defined $result{max_val}) {
             @result{max_val} = $result{s};
             @result{max_abr} = $chart{$i};
          }
       } elsif($time > $i) {                   # remaining seconds is larger
          $num = int($time / $i);                       # add it to the list
          $time -= $num * $i;
          @result{$chart{$i}} = $num;
          if(!defined $result{max_val}) {
             @result{max_val} = $num;
             @result{max_abr} = $chart{$i};
          }
       } else {
          @result{$chart{$i}} = 0;                          # fill in blanks
       }
   }
   return \%result;
}

#
# move
#    move an object from to a new location.
#
sub move
{
   my ($self,$prog,$target,$dest,$type) = 
      (obj($_[0]),obj($_[1]),obj($_[2]),obj($_[3]),$_[4]);

   my $loc = loc($target);

   if(memorydb) {
      if($loc ne undef) {
         db_set($loc,"OBJ_LAST_INHABITED",scalar localtime());
         db_remove_list($loc,"obj_content",$$target{obj_id});
      }
      db_set($target,"OBJ_LAST_INHABITED",scalar localtime());
      db_set($target,"obj_location",$$dest{obj_id});
      db_set_list($dest,"obj_content",$$target{obj_id});
      return 1;
   } else {
      if(hasflag($loc,"ROOM")) {
         set($self,$prog,$loc,"LAST_INHABITED",scalar localtime(),1);
      }
      set_cache($target,"lcon");                       # remove cached items
      set_cache($target,"con_source_id");
      set_cache($loc,"lcon");
      set_cache($loc,"con_source_id");
      set_cache($dest,"lcon");
      set_cache($dest,"con_source_id");

      # look up destination object
      # remove previous location record for object
      sql($db,"delete from content " .                  # remove previous loc
              " where obj_id = ?",
              $$target{obj_id});

      # insert current location record for object
      my $result = sql(e($db,1),                              # set new location
          "INSERT INTO content (obj_id, ".
          "                     con_source_id, ".
          "                     con_created_by, ".
          "                     con_created_date, ".
          "                     con_type) ".
          "     VALUES (?, ".
          "             ?, ".
          "             ?, ".
          "             now(), ".
          "             ?)",
          $$target{obj_id},
          $$dest{obj_id},
          ($$self{obj_name} eq undef) ? "CREATE_COMMAND": $$self{obj_name},
          ($type eq undef) ? 3 : 4
      );
   
      $loc = loc($target);
      if(hasflag($loc,"ROOM")) {
         set($self,$prog,$loc,"LAST_INHABITED",scalar localtime(),1);
      }
      my_commit($db);
      return 1;
   }
}

sub obj
{
   my $id = shift;

   if(ref($id) eq "HASH") {
      return $id;
   } else {
      if($id !~ /^\s*\d+\s*$/) {
         printf("ID: '%s' -> '%s'\n",$id,code());
#         die();
      }
      return { obj_id => $id };
   }
}

sub obj_import
{
   my @result;

   for my $i (0 .. $#_) {
      if(ref($_[$i]) eq "HASH") {
         push(@result,$_[$i]);
      } else {
         push(@result,{ obj_id => $_[$i] });
      }
   }
   return (@result);
}

sub set_home
{
   my ($self,$prog,$obj,$dest) = (obj(shift),obj(shift),obj(shift),obj(shift));

   if(memorydb) {
      db_set($obj,"obj_home",$$dest{obj_id});
   } else {
      sql("update object " .
          "   set obj_home = ? ".
          " where obj_id = ? ",
          $$dest{obj_id},
          $$obj{obj_id}
         );

      if($$db{rows} != 1) {
         return err($self,$prog,"Internal Error, unable to set home");
      } else {
         my_commit;
      }
   }
}
sub link_exit
{
   my ($self,$exit,$src,$dst) = obj_import(@_);

   my $count=one_val("select count(*) value " .
                     "  from content " .
                     "where obj_id = ?",
                     $$exit{obj_id});

   if($count > 0) {
      one($db,
          "update content " .
          "   set con_dest_id = ?," .
          "       con_updated_by = ? , ".
          "       con_updated_date = now() ".
          " where obj_id = ?",
          $$dst{obj_id},
          obj_name($self,$self,1),
          $$exit{obj_id});
   } else {
      one($db,                                     # set new location
          "INSERT INTO content (obj_id, ".
          "                     con_source_id, ".
          "                     con_dest_id, ".
          "                     con_created_by, ".
          "                     con_created_date, ".
          "                     con_type) ".
          "     VALUES (?, ".
          "             ?, ".
          "             ?, ".
          "             ?, ".
          "             now(), ".
          "             ?) ",
          $$exit{obj_id},
          $$src{obj_id},
          $$dst{obj_id},
          obj_name($self,$self,1),
          4
      );
   }

   if($$db{rows} == 1) {
      set_cache($src,"lexits");
      set_cache($exit,"con_source_id");
      my_commit;
      return 1;
   } else {
      my_rollback;
      return 0;
   }
}

sub lastsite
{
   my $target = obj(shift);

   if(memorydb) {
      my $attr = mget($target,"obj_lastsite");

      if($attr eq undef) {
         return undef;
      } else {
         my $list = $$attr{value};
         my $last = (sort {$a <=> $b} keys %$list)[-1];

         if($$list{$last} =~ /^\d+,\d+,(.*)$/) {
            return $1;
         } else {
            delete @$list{$last};
            return undef;
         }
      }
   } else {
      return one_val($db,
                     "SELECT skh_hostname value " .
                     "  from socket_history skh " .
                     "     join (select max(skh_id) skh_id  ".
                     "             from socket_history  ".
                     "            where obj_id = ?  ".
                     "          ) max ".
                     "       on skh.skh_id = max.skh_id",
                     $$target{obj_id}
                    );
   }
}

sub lasttime
{
   my $target = obj(shift);

   if(memorydb) {
      my $attr = mget($target,"obj_lastsite");

      if($attr eq undef) {
         return undef;
      } else {
         my $list = $$attr{value};
         return scalar localtime((sort keys %$list)[-1]);
      }
   } else {
      my $last = one_val($db,
                         "select ifnull(max(skh_end_time), " .
                         "              max(skh_start_time) " .
                         "             ) value " .
                         "  from socket_history " .
                         " where obj_id = ? ",
                         $$target{obj_id}
                        );
      return $last;
   }
}

sub firstsite
{
   my $target = obj(shift);

   if(!hasflag($target,"PLAYER")) {
      return undef;
   } elsif(memorydb) {
      return get($target,"obj_created_by");
   } else {
      return one_val($db,
                     "SELECT skh_hostname value " .
                     "  from socket_history skh " .
                     "     join (select min(skh_id) skh_id  ".
                     "             from socket_history  ".
                     "            where obj_id = ?  ".
                     "          ) min".
                     "       on skh.skh_id = min.skh_id",
                     $$target{obj_id}
                    );
   }
}

sub firsttime
{
   my $target = obj(shift);

   if(memorydb) {
      return scalar localtime(fuzzy(get($target,"obj_created_date")));
   } else {
      my $obj = fetch($target);

      return $$obj{obj_created_date};
   }
}

#
# fuzzy_secs
#    Determine a date based upon what each word looks like.
#
sub fuzzy
{
   my ($time) = @_;
   my ($sec,$min,$hour,$day,$mon,$year);
   my $AMPM = 1;

   return $1 if($time =~ /^\s*(\d+)\s*$/);
   for my $word (split(/\s+/,$time)) {

      if($word =~ /^(\d+):(\d+):(\d+)$/) {
         ($hour,$min,$sec) = ($1,$2,$3);
      } elsif($word =~ /^(\d+):(\d+)$/) {
         ($hour,$min) = ($1,$2);
      } elsif($word =~ /^(\d{4})[\/\-](\d+)[\/\-](\d+)$/) {
         ($mon,$day,$year) = ($2,$3,$1);
      } elsif($word =~ /^(\d+)[\/\-](\d+)[\/\-](\d+)$/) {
         ($mon,$day,$year) = ($1,$2,$3);
      } elsif(defined @months{lc($word)}) {
         $mon = @months{lc($word)};
      } elsif($word =~ /^\d{4}$/) {
         $year = $word;
      } elsif($word =~ /^\d{1,2}$/ && $word < 31) {
         $day = $word;
      } elsif($word =~ /^(AM|PM)$/i) {
         $AMPM = uc($1);
      } elsif(defined @days{lc($word)}) {
         # okay to ignore day of the week
      }
   }

   $year = (localtime())[5] if $year eq undef;
   $day = 1 if $day eq undef;

   if($AMPM eq "AM" || $AMPM eq "PM") {               # handle am/pm hour
      if($hour == 12 && $AMPM eq "AM") {
         $hour = 0;
      } elsif($hour == 12 && $AMPM eq "PM") {
         # do nothing
      } elsif($AMPM eq "PM") {
         $hour += 12;
      }
   }
   
   # don't go negative on which month it is, this will make
   # timelocal assume its the current month.
   if($mon eq undef) { 
      return timelocal($sec,$min,$hour,$day,$mon,$year);
   } else {
      return timelocal($sec,$min,$hour,$day,$mon-1,$year);
   }
}

sub quota_left
{
  my $obj = obj(shift);
  my $owner = owner($obj);

  if(hasflag($obj,"WIZARD")) {
     return 99999999;
  } else {
     return one_val($db,
                    "select max(obj_quota) - count(*) + 1 value " .
                    "  from object " .
                    " where obj_owner = ?" .
                    "    or obj_id = ?",
                    $$owner{obj_id},
                    $$owner{obj_id}
                );
   }
}

#
# get_segment
#    Return the position and text of a segment if the matching $delimiter
#    is found.
#
sub get_segment
{
   my ($array,$end,$delim,$toppings) = @_;
   my $start = $end;
   my @depth;

   while($start > 0) {
      $start--;
      if(defined $$toppings{$$array[$start]}) {
         push(@depth,$$toppings{$$array[$start]});
      } elsif($$array[$start] eq $depth[$#depth]) {
         pop(@depth);
      } elsif($$array[$start] eq $delim) {
         return $start,join('',@$array[$start .. $end]);
      }
   }
}

sub isatrflag
{
   my $txt = shift;
   $txt = $' if($txt =~ /^\s*!/);

   if(memorydb) {
      return flag_attr($txt);
   } else {
      return one_val($db,
                     "select count(*) value " .
                     "  from flag_definition " .
                     " where fde_name = upper(trim(?)) " .
                     "   and fde_type = 2",
                     $txt
                    );
   }
}

#
# source
#    Return if the source of the input is a player[1] or a object[0].
#
sub source
{
   if(defined $$user{internal} &&
      defined @{$$user{internal}}{cmd} &&
      defined @{@{$$user{internal}}{cmd}}{source}) {
      return @{@{$$user{internal}}{cmd}}{source};
   } else {
      return 0;
   }
}

sub is_flag
{
   my $flag = shift;

   $flag = trim($') if($flag =~ /^\s*!/);
   if(memorydb) {
      return (flag_letter($flag) eq undef) ? 0 : 1;
   } else {
      my $count = one_val("select count(*) value " .
                         "  from flag_definition fde1," .
                         " where fde_name = trim(upper(?)) ".
                         "   and fde_type = 1",
                         $flag
                        );
      return ($count == 0) ? 0 : 1;
   }
}
# #!/usr/bin/perl
#
# tm_lock.pl
#    Evaluation of a string based lock to let people use/not use things.
#

use strict;

sub lock_error
{
   my ($hash,$err) = @_;

   $$hash{errormsg} = $err;
   $$hash{error} = 1;
   $$hash{result} = 0;
   $$hash{lock} = undef;
   return $hash;
}

#
# do_lock_compare
#
#    A lock item has been found, which means that there should be
#    either a pending item and pending operand, or nothing at all.
#    Do the compare if need or store the item for later.
#
sub do_lock_compare
{
   my ($lock,$value) = @_;

   #
   # handle comparison
   #
   if($$lock{result} eq undef) {                              # first comp
      $$lock{result} = $value;
   } elsif($$lock{op} eq undef) {                 # second comp w/o op,err
      lock_error($lock,"Expecting next item instead of operand");
   } elsif($$lock{op} eq "&") {               # have 2 operands with & op
      delete @$lock{op};
      if($value && $$lock{result}) {
         $$lock{result} = 1;                                     # success
      } else {
         $$lock{result} = 0;                                        # fail
      }
   } elsif($$lock{op} eq "|") {               # have 2 operands with | op
      delete @$lock{op};
      if($value || $$lock{result}) {
         $$lock{result} = 1;                                      # sucess
      } else {
         $$lock{result} = 0;                                        # fail
      }
   }
}

#
# lock_item_eval
#    Each item is a comparison against the object trying to pass throught the
#    lock 
#
sub lock_item_eval
{
   my ($self,$prog,$obj,$lock,$item) = @_;
   my ($not, $target,$result);

   return if(defined $$lock{error} && $$lock{error});      # prev parse error

   if($item =~ /^\s*([\|\&]{1})\s*$/) {                           # handle op
      if(defined $$lock{op}) {                                 # too many ops
         return lock_error($lock,"Too many operators ($$lock{op} and $1)");
      } else {
         $$lock{op} = $1;
      }
   } elsif($item =~ /^\s*\((.*)\)\s*/) {             # handle ()'s
      $result = lock_eval($self,$prog,$obj,$1);

      if($$result{error}) {
         lock_error($lock,$$result{errormsg});
      } else {
         do_lock_compare($lock,$$result{result});
      }
   } elsif($item =~ /^\s*(!{0,1})\s*([^ ]+)\s*$/) {             # handle item
      $not = ($1 eq "!") ? 1 : 0;
      $target = find($obj,$prog,$2);

      if($target eq undef) {                             # verify item exists
         return lock_error($lock,"Target($2) does not exist.");
      } elsif(($not && $$target{obj_id} ne $$self{obj_id}) ||   # compare item
         (!$not && $$target{obj_id} eq $$self{obj_id})) { 
         $result = 1;                                               # success
      } else {
         $result = 0;                                               # failure
      }

      do_lock_compare($lock,$result);
   } else {
      return lock_error($lock,"Invalid item '$item'");       # invalid item/op
   }

   return $lock;
}

#
# lock_eval
#    This is the inital call to evaluating a lock.
#
sub lock_eval
{
    my ($self,$prog,$obj,$txt) = @_;
    my ($start,$depth) = (0,0);
    my $lock = {};

    my @list = split(/([\(\)&\|])/,$txt);
    for my $i (0 .. $#list) {
       if(@list[$i] eq "(") {
          $depth++;
       } elsif(@list[$i] eq ")") {
          $depth--;

          if($depth == 0) {
            lock_item_eval($self,$prog,$obj,$lock,join('',@list[$start .. $i]));
             $start = $i + 1;
          }
       } elsif($depth == 0 && 
               ( @list[$i] eq "&" ||
                 @list[$i] eq "|" ||
                 @list[$i] =~ /^\s*[^\(\)\s]/
               )
              ) {
          lock_item_eval($self,$prog,$obj,$lock,join('',@list[$start .. $i]));
          $start = $i + 1;
       }
    }
    return $lock;
}

#
# lock_item_compile
#    Each item is a comparison against the object trying to pass throught the
#    lock 
#
sub lock_item_compile
{
   my ($self,$prog,$obj,$lock,$item,$flag) = @_;
   my ($not, $target,$result);

   return if(defined $$lock{error} && $$lock{error});      # prev parse error

   if($item =~ /^\s*([\|\&]{1})\s*$/) {                           # handle op
      if(defined $$lock{op}) {                                 # too many ops
         return lock_error($lock,"Too many operators ($$lock{op} and $1)");
      } else {
         my $lock = $$lock{lock};
         push(@$lock,$1);
      }
   } elsif($item =~ /^\s*\((.*)\)\s*$/) {             # handle ()'s
      my ($array,$txt) = ($$lock{lock},$1);
      if($#$array >= 0 && @$array[$#$array] !~ /^\s*[\|\&]\s*$/) {
         lock_error($lock,"Expected operand but found '$item'");
      }
      $result = lock_compile($self,$prog,$obj,$txt);

      if($$result{error}) {
         lock_error($lock,$$result{errormsg});
      } else {
         push(@$array,"(".$$result{lock}.")");
      }
   } elsif($item =~ /^\s*(!{0,1})\s*([^ ]+)\s*$/) {             # handle item
      my ($array,$not,$txt) = ($$lock{lock},$1,$2);
      if($#$array >= 0 && @$array[$#$array] !~ /^\s*[\|\&]\s*$/) {
         lock_error($lock,"Expected operand but found '$item'");
      }

      $target = find($obj,$prog,$txt);
      
      if($target eq undef) {                             # verify item exists
         return lock_error($lock,"Target($obj) does not exist");
      } elsif($flag) {
         push(@$array,"$not" . obj_name($self,$target));
      } else {
         push(@$array,"$not#$$target{obj_id}");
      }
   } else {
      return lock_error($lock,"Invalid item '$item'");       # invalid item/op
   }

   return $$lock{result};
}

#
# lock_compile
#    Convert a string into a lock of dbrefs to protect against player 
#    renames.
#
sub lock_compile
{
    my ($self,$prog,$obj,$txt,$flag) = @_;
    my ($start,$depth) = (0,0);
    my $lock = {
       lock => []
    };

    my @list = split(/([\(\)&\|])/,$txt);
    for my $i (0 .. $#list) {
       if(@list[$i] eq "(") {
          $depth++;
       } elsif(@list[$i] eq ")") {
          $depth--;

          if($depth == 0) {
             lock_item_compile($self,
                               $prog,
                               $obj,
                               $lock,
                               join('',@list[$start .. $i]),
                               $flag
                              );
             $start = $i + 1;
          }
       } elsif($depth == 0 && 
               ( @list[$i] eq "&" ||
                 @list[$i] eq "|" ||
                 @list[$i] =~ /^\s*[^\(\)\s]/
               )
              ) {
          lock_item_compile($self,
                            $prog,
                            $obj,
                            $lock,
                            join('',@list[$start .. $i]),
                            $flag);
          $start = $i + 1;
       }
    }

    if($$lock{error}) {
       return $lock;
    } else {
       $$lock{lock} = join('',@{@$lock{lock}});
       return $lock;
    }
}

#
# lock_uncompile
#    Alias for lock_compile but return object names instead of object
#    dbrefs.
#
sub lock_uncompile
{
    my ($self,$prog,$txt) = @_;

    my $result = lock_compile($self,$prog,$self,$txt,1);

    if($$result{error}) {
       return "*UNLOCKED*";
    } else {
      return $$result{lock};
    }
}
# #!/usr/bin/perl
#
# tm_mysql.pl
#   Routines required for TeenyMUSH to access mysql.
#
use strict;
use Carp;


$db = {} if(ref($db) ne "HASH");
$log = {} if(ref($log) ne "HASH");
# delete @$db{keys %$db};
# delete @$log{keys %$log};

#
# get_db_credentials
#    Load the database credentials from the tm_config.dat file
#
sub get_db_credentials
{
   my $fn = "tm_config.dat";

   $fn .= ".dev" if(-e "$fn.dev");

   for my $line (split(/\n/,getfile($fn))) {
      $line =~ s/\r|\n//g;
      if($line =~ /^\s*(user|pass|database)\s*=\s*([^ ]+)\s*$/) {
         $$db{$1} = $2;
         $$log{$1} = $2;
      }
   }
}

get_db_credentials;


#
# sql
#    Connect / Reconnect to the database and run some sql.
#
sub sql
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;
   my (@result,$sth);
   @info{sqldone} = 0;

   delete @$con{rows};

#   if($sql !~ /^insert into io/) {
#     printf("SQL: '%s' -> '%s'\n",$sql,join(',',@args));
##      printf("     '%s'\n",code("short"));
#   }

   #
   # clean up the sql a little
   #  keep track of last sql that was run for debug purposes.
   #
   $sql =~ s/\s{2,999}/ /g;
   @info{sql_last} = $sql;
   @info{sql_last_args} = join(',',@args);
   @info{sql_last_code} = code();

   # connected/reconnect to DB if needed
   if(!defined $$con{db} || !$$con{db}->ping) {
      $$con{host} = "localhost" if(!defined $$con{host});
      $$con{db} = DBI->connect("DBI:mysql:database=$$con{database}:" .
                             "host=$$con{host}",
                             $$con{user},
                             $$con{pass},
                             {AutoCommit => 0, RaiseError => 1,
                               mysql_auto_reconnect => 1}
                            ) 
                            or die "Can't connect to database: $DBI::errstr\n";
   }

   $sth = @$con{db}->prepare($sql) ||
      die("Could not prepair sql: $sql");

   for my $i (0 .. $#args) {
      $sth->bind_param($i+1,$args[$i]);
   }

   if(!$sth->execute( )) {
      die("Could not execute sql");
   }
   @$con{rows} = $sth->rows;

   # produce an error if expectations are not met
   if(defined @$con{expect}) {
      if(@$con{expect} != $sth->rows) {
         delete @$con{expect};
         die("Expected @$con{expect} rows but got " . $sth->rows . 
             " when running SQL: $sql");
      } else {
         delete @$con{expect};
      }
   }
 
   # do not fetch results from inserts / deletes 
   if($sql !~ /^\s*(insert|delete|update) /i) {
      while(my $ref = $sth->fetchrow_hashref()) {
         push(@result,$ref);
      }
   }

   # clean up and return the results
   $sth->finish();
   delete @info{sql_last};
   delete @info{sql_last_args};
   return \@result;
}

#
# sql
#    Connect / Reconnect to the database and run some sql.
#
sub sql2
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;
   my (@result,$sth);

   delete @$con{rows};
#   # reconnect if we've been idle for an hour. Shouldn't be needed?
#   if(time() - $$db{last} > 3600) {
#      eval {
#         @$con{db}->disconnect;
#      };
#      delete @$con{db};
#   }
#   $$db{last} = time();

   #
   # clean up the sql a little
   #  keep track of last sql that was run for debug purposes.
   #
   $sql =~ s/\s{2,999}/ /g;
   @info{sql_last} = $sql;
   @info{sql_last_args} = join(',',@args);
#   if($sql =~ /flag_permission/i) {
#   printf("SQL: '%s'\n",$sql);
#   printf("     '%s'\n",$info{sql_last_args});
#   }

   # connected/reconnect to DB if needed
   if(!defined $$con{db} || !$$con{db}->ping) {
      $$con{host} = "localhost" if(!defined $$con{host});
      $$con{db} = DBI->connect("DBI:mysql:database=$$con{database}:" .
                             "host=$$con{host}",
                             $$con{user},
                             $$con{pass},
                             {AutoCommit => 0, RaiseError => 1,
                               mysql_auto_reconnect => 1}
                            ) 
                            or die "Can't connect to database: $DBI::errstr\n";
   }

   $sth = @$con{db}->prepare($sql) ||
      die("Could not prepair sql: $sql");

   for my $i (0 .. $#args) {
      $sth->bind_param($i+1,$args[$i]);
   }

   $sth->execute( ) || die("Could not execute sql");
   @$con{rows} = $sth->rows;

   # produce an error if expectations are not met
   if(defined @$con{expect}) {
      if(@$con{expect} != $sth->rows) {
         delete @$con{expect};
         die("Expected @$con{expect} rows but got " . $sth->rows . 
             " when running SQL: $sql");
      } else {
         delete @$con{expect};
      }
   }
 
   # do not fetch results from inserts / deletes 
   if($sql !~ /^\s*(insert|delete|update) /i) {
      while(my $ref = $sth->fetchrow_hashref()) {
         push(@result,$ref);
      }
   }

   # clean up and return the results
   $sth->finish();
   return @result;
}

#
# one_val
#    fetch the first entry in value column on a select that returns only
#    one row.
#
sub one_val
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;

   my $array = sql($con,$sql,@args);
   return ($$con{rows} == 1) ? @{$$array[0]}{value} : undef;
}

#
# fetch one row or nothing
#
sub one
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;

#   printf("SQL: '%s'\n",$sql);
   my $array = sql($con,$sql,@args);
#   printf("ONE: '%s'\n",$$con{rows});
#   printf("#ARRAY#: '%s'\n",join(',',@$array));

   if($$con{rows} == 1) {
      return $$array[0];
   } elsif($$con{rows} == 2 && $sql =~ /ON DUPLICATE/i) {
      $$con{rows} = 1;
      return $$array[0];
   } else {
      return undef;
   }
}

sub my_commit
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   $$con{db}->commit;
}

sub my_rollback
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($fmt,@args) = @_;

   if(mysqldb) {
      @$con{db}->rollback;
      return undef;
   }
}

sub fetch
{
   my $obj = obj($_[0]);
   my $debug = shift;

   $$obj{obj_id} =~ s/#//g;

   if(memorydb) {
      return $obj;
   } else {
      my $hash=one($db,"select * from object where obj_id = ?",$$obj{obj_id}) ||
         return undef;
      return $hash;
   }
}

# #!/usr/bin/perl
#
#
# tm_sockets.pl
#    Code to handle accessing sockets.
#

#
# add_last_info
#
#    Add details about when a user last did something.
#
sub add_last_info
{
   my $cmd = shift;

   # create structure to hold last info if needed
   $$user{last} = {} if(!defined $$user{last});

   # populate last hash with the info
   my $last = $$user{last};
   $$last{time} = time();
   $$last{cmd} = $cmd;
}

sub trim
{
   my $txt = shift;

   $txt =~ s/^\s+|\s+$//g;
   return $txt;
}

# ste_type
#
# -- 1   close connection as soon as possible
# -- 2   show banned.txt
# -- 3   registration
# -- 4   open
#
sub add_site_restriction 
{
   my $sock = shift;

   if(mysqldb) {
       my $hash=one($db,
                    "select ifnull(min(ste_type),4) ste_type" .
                    "  from site ".
                    " where (lower(?) like lower(ste_pattern) ".
                    "    or lower(?) like lower(ste_pattern))" .
                    "   and ifnull(ste_end_date,now()) >= now()",
                    $$sock{ip},
                    $$sock{hostname}
                   );
       $$sock{site_restriction} = $$hash{ste_type};
   } else {
       $$sock{site_restriction} = 4;
       ### ADD ###
   }
}

#
# lookup_command
#    Try to find a internal command, exit, or mush command to run.
#
sub lookup_command
{
   my ($self,$hash,$cmd,$txt,$type,$debug) =
      ($_[0],$_[1],lc($_[2]),$_[3],$_[4],$_[5]);
   my $match;

   if(defined $$hash{$cmd}) {                       # match on internal cmd
      return ($cmd,trim($txt));
   } elsif(defined $$hash{substr($cmd,0,1)} &&             # one letter cmd
           (defined @{$$hash{substr($cmd,0,1)}}{nsp} ||  # w/wo space after
            substr($cmd,1,1) eq " " ||                            # command
            length($cmd) == 1
           )
          ) {
      return (substr($cmd,0,1),trim(substr($cmd,1) . $txt));
   } else {                                     # match on partial cmd name
      return ('huh',trim($txt));

      $txt =~ s/^\s+|\s+$//g;
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
      if($match ne undef && lc($cmd) ne "q") {                # found match
         return ($match,trim($txt));
      } elsif($$user{site_restriction} == 69) {
         return ('huh',trim($txt));
      } elsif($txt =~ /^\s*$/ && $type && find_exit($self,{},$cmd)) {  # exit?
         printf("CMD: '$cmd'\n");
         return ("go",$cmd);
      } elsif(mush_command($self,$hash,trim($cmd . " " . $txt,1))) { #mush cmd
         return ("\@\@",$cmd . " " . $txt);    
      } else {                                                  # no match
         return ('huh',trim($txt));
      }
   }
}


sub add_telnet_data
{
   my($sock,$txt) = @_;

   my $prog = $$sock{prog};

   $$prog{socket_buffer} = [] if(!defined $$prog{socket_buffer});
   my $stack = $$prog{socket_buffer};
   push(@$stack,$txt);
}

#
# server_process_line
#
#    A line of text has finally come in, see if its a valid command and
#    run it. Commands differ for if the user is connected or not.
#    This is also where some server crashes are detected.
#
sub server_process_line
{

   my ($hash,$input) = @_;

#   if($input !~ /^\s*$/) {
#      printf("#%s# '%s'\n",((defined $$hash{obj_id}) ? obj_name($hash) : "?"),
#      $input);
#   }
   my $data = @connected{$$hash{sock}};

   if(defined $$data{raw} && $$data{raw} == 1) {
      handle_object_listener($data,"%s",$input);
   } elsif(defined $$data{raw} && $$data{raw} == 2) {
     add_telnet_data($data,$input);
   } else {
      eval {                                                  # catch errors
         local $SIG{__DIE__} = sub {
            printf("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            printf("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            if(mysqldb && defined @info{sql_last}) {
               printf("LastSQL: '%s'\n",@info{sql_last});
               printf("         '%s'\n",@info{sql_last_args});
               delete @info{sql_last};
               delete @info{sql_last_args};
            }
            printf("%s",code("long"));
         };

         if($input =~ /^\s*([^ ]+)/ || $input =~ /^\s*$/) {
            $user = $hash;
            if($$user{site_restriction} == 69) {
               my ($cmd,$arg) = lookup_command($data,\%honey,$1,$',0);
               &{@honey{$cmd}}($arg);                            # invoke cmd
            } elsif(loggedin($hash) || 
                    (defined $$hash{obj_id} && hasflag($hash,"OBJECT"))) {
               add_last_info($input);                                   #logit
               io($user,1,$input);
               return mushrun(self   => $user,
                              runas  => $user,
                              source => 1,
                              cmd    => $input,
                             );
            } else {
               my ($cmd,$arg) = lookup_command($data,\%offline,$1,$',0);
               &{@offline{$cmd}}($hash,prog($user,$user),$arg);  # invoke cmd
            }
         }
      };

      if($@) {                                # oops., you sunk my battle ship
#         printf("# %s crashed the server with: %s\n%s",name($hash),$_[1],$@); 
#         printf("LastSQL: '%s'\n",@info{sql_last});
#         printf("         '%s'\n",@info{sql_last_args});
#         printf("         '%s'\n",@info{sql_last_code});
         my_rollback($db);
   
         my $msg;
         if($_[1] =~ /^\s*connnect\s+/) {
            $msg = sprintf("%s crashed the server with: connect blah blah",
                name($hash),$_[1]);
         } else {
            $msg = sprintf("%s crashed the server with: %s",name($hash),$_[1]);
         }
         necho(self   => $hash,
               prog   => prog($hash,$hash),
               source => [ "%s",$msg ]
              );
         if($msg ne $$user{crash}) {
            necho(self   => $hash,
                  prog   => prog($hash,$hash),
                  room   => [ $hash, "%s",$msg ]
                 );
            $$user{crash} = $msg;
         }
         delete @$hash{buf};
      }
   }
}


#
# server_hostname
#    lookup the hostname based upon the ip address
#
sub server_hostname
{
   my $sock = shift;
   my $ip = $sock->peerhost;                           # contains ip address

   my $name = gethostbyaddr(inet_aton($ip),AF_INET);

   if($name eq undef || $name =~ /in-addr\.arpa$/) {
      return $ip;                            # last resort, return ip address
   } else {
      return $name;                                         # return hostname
   }
}

sub get_free_port
{
   my ($i,%used);
   my $max = (scalar keys %connected) + 2;

   for my $key (keys %connected) {
      my $hash = @connected{$key};
      if(defined $$hash{port}) {
         @used{$$hash{port}} = 1;
      };
   }

   for($i=1;$i < $max;$i++) {
      return $i if(!defined @used{$i});
   }

   return $i;                                        # should never happen
}


#
# server_handle_sockets
#    Open Handle all incoming I/O and try to sleep frequently enough
#    so that all of the cpu is not being used up.
#
sub server_handle_sockets
{
   eval {
         local $SIG{__DIE__} = sub {
            printf("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            printf("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            if(mysqldb && defined @info{sql_last}) {
               printf("LastSQL: '%s'\n",@info{sql_last});
               printf("         '%s'\n",@info{sql_last_args});
               delete @info{sql_last};
               delete @info{sql_last_args};
            }
            printf("%s",code("long"));
         };

      # wait for IO or 1 second
      my ($sockets) = IO::Select->select($readable,undef,undef,.4);
      my $buf;

      if(!defined @info{server_start} || @info{server_start} =~ /^\s*$/) {
         @info{server_start} = time();
      }

      # process any IO
      foreach my $s (@$sockets) {      # loop through active sockets [if any]
         if($s == $web) {                                # new web connection
            http_accept($s);
         } elsif(defined @http{$s}) {
            http_io($s);
         } elsif($s == $websock || defined $ws->{conns}{$s}) {
            websock_io($s);
         } elsif($s == $listener) {                     # new mush connection
            my $new = $listener->accept();                        # accept it
            if($new) {                                        # valid connect
               $readable->add($new);               # add 2 watch list 4 input
               my $hash = { sock => $new,             # store connect details
                            hostname => server_hostname($new),
                            ip       => $new->peerhost,
                            loggedin => 0,
                            raw      => 0,
                            start    => time(),
                            port     => get_free_port(),
                            type     => "MUSH",
                            last     => { time => time(),
                                          cmd => "connect"
                                        }
                          };
               add_site_restriction($hash);
               @connected{$new} = $hash;

               printf("# Connect from: %s [%s]\n",$$hash{hostname},ts());
               if($$hash{site_restriction} <= 2) {                  # banned
                  printf("   BANNED   [Booted]\n");
                  if($$hash{site_restriction} == 2) {
                     printf($new "%s",@info{"conf.badsite"});
                  }
                  server_disconnect(@{@connected{$new}}{sock});
               } elsif($$hash{site_restriction} == 69) {
                  printf($new "%s",getfile("honey.txt"));
               } elsif(!defined @info{"conf.login"}) {
                  printf($new "Welcome to %s\r\n\r\n",@info{"version"});
               } else {
                  printf($new "%s\r\n",@info{"conf.login"});    #  show login
               }
            }                                                        
         } elsif(sysread($s,$buf,1024) <= 0) {          # socket disconnected
            server_disconnect($s);
         } else {                                          # socket has input
            @{@connected{$s}}{pending} = 1;
            $buf =~ s/\r//g;                                 # remove returns
#            $buf =~ tr/\x80-\xFF//d;
#            $buf =~ s/\e\[[\d;]*[a-zA-Z]//g;
            @{@connected{$s}}{buf} .= $buf;                     # store input
          
                                                         # breakapart by line
            while(defined @connected{$s} && @{@connected{$s}}{buf} =~ /\n/) {
               @{@connected{$s}}{buf} = $';                # store left overs
               server_process_line(@connected{$s},$`);         # process line
#               if(@{@connected{$s}}{raw} > 0) {
#                  my $tmp = $`;
#                  $tmp =~ s/\e\[[\d;]*[a-zA-Z]//g;
#                  printf("#%s# %s\n",@{@connected{$s}}{raw},$tmp);
#               }
            }
         }
      }

     spin();

   };
   if($@){
      printf("Server Crashed, minimal details [main_loop]\n");

      if(mysqldb) {
         printf("LastSQL: '%s'\n",@info{sql_last});
         printf("         '%s'\n",@info{sql_last_args});
      }
      printf("%s\n---[end]-------\n",$@);
   }
}

#
# server_disconnect
#    Either the user has QUIT or disconnected, so handle the disconnect
#    approprately.
#
sub server_disconnect
{
   my $id = shift;
   my $prog;

   # notify connected users of disconnect
   if(defined @connected{$id}) {
      my $hash = @connected{$id};

      if(defined @connected{$id} && defined @{@connected{$id}}{prog}) {
         $prog = @{@connected{$id}}{prog};
      } else {
         $prog = prog($hash,$hash);
      }
      my $type = @{@connected{$id}}{type};

      if(defined $$hash{prog} && defined @{$$hash{prog}}{telnet_sock}) {
         delete @{$$hash{prog}}{telnet_sock};
      }

      if(defined $$hash{raw} && $$hash{raw} > 0) {             # MUSH Socket
         if($$hash{buf} !~ /^\s*$/) {
            server_process_line($hash,$$hash{buf});    # process pending line
         }                                                   # needed for www
         necho(self => $hash,
               prog => $prog,
               "[ Connection closed ]"
              );

         if(mysqldb) {
            sql($db,                             # delete socket table row
                "delete from socket " .
                " where sck_socket = ? ",
                $id
               );
            my_commit($db);
         }
      } elsif(defined $$hash{connect_time}) {                # Player Socket

         my $key = connected_user($hash);

         if(defined @connected_user{$$hash{obj_id}}) {
            delete @{@connected_user{$$hash{obj_id}}}{$key};
            if(scalar keys %{@connected_user{$$hash{obj_id}}} == 0) {
               delete @connected_user{$$hash{obj_id}};
            }
         }

         if(mysqldb) {
            my $sck_id = one_val($db,                        # find socket id
                                 "select sck_id value " .
                                 "  from socket " .
                                 " where sck_socket = ?" ,
                                 $id
                                );

            if($sck_id ne undef) {
                sql($db,                               # log disconnect time
                    "update socket_history " .
                    "   set skh_end_time = now() " .
                    " where sck_id = ? ",
                     $sck_id
                   );
   
                sql($db,                          # delete socket table row
                    "delete from socket " .
                    " where sck_id = ? ",
                    $sck_id
                   );
                my_commit($db);
            }
         }

         necho(self => $hash,
               prog => $prog,
               room => [ $hash, "%s has disconnected.",name($hash) ]
              );
         echo_flag($hash,$prog,"CONNECTED,PLAYER,MONITOR",
                   "[Monitor] %s has disconnected.",name($hash));
      }
   }

   # remove user out of the loop
   $readable->remove($id);
   $id->close;
   delete @connected{$id};
}

#
# server_start
#
#    Start listening on the specified port for new connections.
#
sub server_start
{
   read_config();

   #
   # close the loop on connections that have start times but not end times
   #

   if(mysqldb) {
      sql($db,"delete from socket");
      sql($db,"update socket_history " .
              "   set skh_end_time = skh_start_time " .
              " where skh_end_time is null");
      my_commit($db);
   }

   if(memorydb) {
      my $file = newest_full(@info{"conf.mudname"} . ".FULL.DB");

      if($file eq undef) {
         printf("   No database found, loading starter database.\n");
         printf("   Connect as: god potrzebie\n\n");
         db_read_string(<<__EOF__);
server: TeenyMUSH 0.9, dbversion=1.0, exported=Wed Oct 17 08:28:30 2018, type=normal
obj[0] {
   conf.starting_room::A:#1
   obj_created_by::A:Adrick
   obj_created_date::A:2016-05-05 13:30:56
   obj_flag::L:player,god
   obj_home::A:1
   obj_location::A:1
   obj_lock_default::A:#0
   obj_money::A:0
   obj_name::A:God
   obj_owner::A:0
   obj_password::A:*EF5D6D678BAE641D8DAF107523B0EA48D420E0E0
   obj_quota::A:0
}
obj[1] {
   description::A:A non-descript room
   last_inhabited::A:Thu Oct  4 14:26:25 2018
   obj_created_by::A:Adrick
   obj_created_date::A:2016-04-15 13:49:58
   obj_flag::L:room
   obj_home::A:-1
   obj_name::A:Void
   obj_owner::A:0
}
** Dump Completed Wed Oct 17 08:28:30 2018 **
__EOF__
      } else {
         db_read(undef,undef,$file);
      }
      @info{db_last_dump} = time();
   }

   read_atr_config();
   read_config();

   my $count = 0;

   @info{port} = 4201 if(@info{port} !~ /^\s*\d+\s*$/);
   printf("TeenyMUSH listening on port @info{port}\n");
   $listener = IO::Socket::INET->new(LocalPort => @info{port},
                                     Listen    => 1,
                                     Reuse     => 1
                                    );
 
   if(@info{"conf.httpd"} ne undef && @info{"conf.httpd"} > 0) {
      if(@info{"conf.httpd"} =~ /^\s*(\d+)\s*$/) {
         printf("HTTP listening on port %s\n",@info{"conf.httpd"});

         $web = IO::Socket::INET->new(LocalPort => @info{"conf.httpd"},
                                      Listen    =>1,
                                      Reuse=>1
                                     );
      } else {
         printf("Invalid httpd port number specified in #0/conf.httpd");
      }
   }

   if(@info{"conf.websocket"} ne undef && @info{"conf.websocket"} > 0) {
      if(@info{"conf.websocket"} =~ /^\s*(\d+)\s*$/) {
         printf("Websocket listening on port %s\n",@info{"conf.websocket"});
         websock_init();
      } else {
         printf("Invalid websocket port number specified in #0/conf.websocket");
      }
   }

   if($ws eq undef) {                             # emulate websocket listener
      $ws = {};                                              # when not in use
      $ws->{select_readable} = IO::Select->new();
   }

   $ws->{select_readable}->add($listener);

   if(@info{"conf.httpd"} ne undef) {
      $ws->{select_readable}->add($web);
   }
   $readable = $ws->{select_readable};

   # main loop;
   while(1) {
#      eval {
         server_handle_sockets();
#      };
      if($@){
         printf("Server Crashed, minimal details [main_loop]\n");
         if(mysqldb) {
            printf("LastSQL: '%s'\n",@info{sql_last});
            printf("         '%s'\n",@info{sql_last_args});
         }
         printf("%s\n---[end]-------\n",$@);
      }
   }
}

# #!/usr/bin/perl
#
# tm_websock.pl
#    Code required to access websockets from within the server. When this
#    code is enabled, the listener from websockets is used instead of
#    the standard INET one.
#

sub websock_init
{
   $websock = IO::Socket::INET->new( Listen    => 5,
                                     LocalPort => @info{"conf.websocket"},
                                     Proto     => 'tcp',
                                     Domain    => AF_INET,
                                     ReuseAddr => 1,
                                   )
   or die "failed to set up TCP listener: $!";

   $ws = Net::WebSocket::Server->new(
      listen => $websock,
      tick_period => 1,
      on_connect => sub { my( $serv, $conn ) = @_;
                          $conn->on( ready =>      sub{ ws_login_screen(@_); },
                                     utf8  =>      sub{ ws_process( @_, 0 );},
                                     disconnect => sub { ws_disconnect(@_); },
                                   );
                        },  
   );
   $ws->{select_readable}->add($websock);
   $ws->{conns} = {};
}

sub ws_disconnect
{
    my ($conn, $code, $reason) = @_;

    my $sock = $conn->{socket};
    $ws->{select_readable}->remove( $conn->{socket} );
    server_disconnect( $conn->{socket} );
    $conn->disconnect();
    delete $ws->{conns}{$sock};
}

sub ws_login_screen
{
   my $conn = shift;

   ws_echo($conn->{socket}, @info{"conf.login"});
}

#
# ws_echo
#    The send might crash if the websocket has disconnected the evals should
#    probably be removed once this is more stable. With that in mind,
#    currently crash will be treated as a disconnect.
#
sub ws_echo
{
   my ($s, $msg) = @_;

   return if not defined @connected{$s};
   my $conn = @{@connected{$s}}{conn};
   # this might crash if the websocket dies, the evals should
   # probably be removed once this is more stable. With that in mind,
   # currently crash will be treated as a disconnect.
   eval {
      $conn->send('','t'.$msg);
   };

   if($@) {
       ws_disconnect($conn);
   }
}


sub websock_io
{
   my $sock = shift;

   if( $sock == $ws->{listen} ) {
      my $sock = $ws->{listen}->accept;
      my $conn = new Net::WebSocket::Server::Connection(
                 socket => $sock, server => $ws );

      $ws->{conns}{$sock} = { conn     => $conn,
                              lastrecv => time,
                              ip       => server_hostname($sock)
                            };

      $ws->{select_readable}->add( $sock );
      $ws->{on_connect}($ws, $conn );
      @c{$conn} = $conn;

      # attach the socket to the mush data structure 
      my $hash = { sock     => $sock,             # store connect details
                   conn     => $conn,
                   hostname => server_hostname($sock),
                   ip       => $sock->peerhost,
                   loggedin => 0,
                   raw      => 0,
                   start    => time(),
                   port     => get_free_port(),
                   type     => "WEBSOCKET"
                 };
      add_site_restriction($hash);
      @connected{$sock} = $hash;
   } elsif( $ws->{watch_readable}{$sock} ) {
      $ws->{watch_readable}{$sock}{cb}( $ws , $sock );
   } elsif( $ws->{conns}{$sock} ) {
      my $connmeta = $ws->{conns}{$sock};
      $connmeta->{lastrecv} = time;
      $connmeta->{conn}->recv();
   } else {
      warn "filehandle $sock became readable, but no handler took " .
           "responsibility for it; removing it";
      $ws->{select_readable}->remove( $sock );
   }

#   if( $ws->{watch_writable}{$sock} ) {
#      $ws->{watch_writable}{$sock}{cb}( $ws, $sock);
#   } else {
#      warn "filehandle $sock became writable, but no handler took ".
#           "responsibility for it; removing it";
#      $ws->{select_writable}->remove( $sock );
#   }

}

#
# ws_process
#    A message has come in via the websocket, hand it off to the MUSH
#    via the server_proces_line() function. The websocket client sends
#    a flag via the first character (text, html, and publeo, etc). 
#    Currently, that flag is just being stripped and ignored. Maybe
#    later?
#
sub ws_process {
   my( $conn, $msg, $ssl ) = @_;
   $msg =~ s/\r|\n//g;

   $ssl = $ssl ? ',SSL' : '';

   if($msg =~ /^#M# /) {
      printf("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$');
      @{$ws->{conns}{$conn->{socket}}}{type} = "NON_INTERACTIVE";
      my $self = fetch(@info{"conf.webuser"});

      my $prog = mushrun(self   => $self,
                         runas  => $self,
                         source => 0,
                         cmd    => $',
                         hint   => "WEBSOCKET",
                         sock   => $conn,
                         output => []
                        );
      $$prog{sock} = $conn;
   } else {
      printf("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$msg);
      $msg = substr($msg,1);
      server_process_line(@connected{$conn->{socket}},$msg);
   }
}


sub websock_wall
{
   my $txt = shift;

   my $hash = $ws->{conns};

   for my $key ( keys %$hash) {
      my $client = $$hash{$key}->{conn};

      if(@{$ws->{conns}{$client->{socket}}}{type} eq "NON_INTERACTIVE") {
         eval {
            $client->send_utf8("### Trigger ### $txt");
         };
         if($@) {
            ws_disconnect($client);
         }
      } else {
#         printf("Skipped $client\n");
      }
   }
}
