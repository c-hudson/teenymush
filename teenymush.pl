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
#                       [ impossible but true ]
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
    $readable,                 #!# sockets to wait for input on
    $listener,                 #!# port details
    $web,                      #!# web port details
    $ws,                       #!# websocket server object
    $websock,                  #!# websocket listener
    %http,                     #!# http socket list
    %code,                     #!# loaded perl files w/mod times
    $log,                      #!# database connection for logs
    %info,                     #!# misc info storage
    $user,                     #!# current user details
    $enactor,                  #!# object who initated the action
    %cache,                    #!# cached data from sql database
    %c,                        #!#
    %default,                  #!# default values for config.
    %engine,                   #!# process holder for running
    %ansi_rgb,                 #!# color number to rgb code
    %ansi_name,                #!# color names to 256 color id

    #----[memory database structures]---------------------------------------#
    %help,                     #!# online-help
    @db,                       #!# whole database
    @delta,                    #!# db changes storage
    %player,                   #!# player list for quick lookup
    @free,                     #!# free objects list
    %deleted,                  #!# deleted objects during backup
    %flag,                     #!# flag definition
   );                          #!#

#
# load_modules
#    Some modules are "optional". Load these optional modules or disable
#    their use by setting the coresponding @info variable to -1.
#
sub load_modules
{
   my %mod = (
      'URI::Escape'            => 'httpd',    
      'DBI'                    => 'mysqldb',   
      'Net::WebSocket::Server' => 'websocket',
      'Net::HTTPS::NB'         => 'url_https',
      'Net::HTTP::NB'          => 'url_http',      
      'HTML::Entities'         => 'entities',
      'Digest::MD5'            => 'md5',
      'File::Copy'             => 'copy',
      'HTML::Restrict'         => 'html_restrict',   # libhtml-restrict-perl
   );

   for my $key (keys %mod) {
      if(!defined @info{"conf.@mod{$key}"} || @info{"conf.@mod{$key}"} == 1) {
         eval "use $key; 1;" or @info{"conf.@mod{$key}"} = -1;
         if(@info{"conf.@mod{$key}"} == -1) {
            con("WARNING: Missing $key  module, @mod{$key} disabled\n");
         } elsif(!defined @info{"conf.@mod{$key}"}) {
            @info{"conf.@mod{$key}"} = 0;
         }
      }
   }
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
#   @info{"conf.memorydb"} = 1;
#   @info{"conf.mysqldb"} = 0;
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
# getfile
#    Load a file into memory and return the contents of that file.
#    Depending upon the extention, files are loaded from different
#    folders.
#
sub getfile
{
   my ($fn,$code,$filter) = @_;
   my($file, $out);

   if($fn =~ /^[^\\|\/]+\.(pl|dat|dev|conf)$/i) {
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

sub load_config_default
{
   delete @default{keys %default};

   @default{money_name_plural}        = "Pennies";
   @default{money_name_singular}      = "Penny";
   @default{paycheck}                 = 50;
   @default{starting_money}           = 150;
   @default{linkcost}                 = 1;
   @default{digcost}                  = 10;
   @default{createcost}               = 10;
   @default{backup_interval}          = 3600;                  # once an hour
   @default{function_invocation_limit}= 2500;
   @default{weblog}                   = "teenymush.web.log";
   @default{conlog}                   = "teenymush.log";
   @default{httpd_invalid}            = 3;
   @default{login}                    = "Welcome to @info{version}\r\n\r\n" .
                                        "   Type the below command to " .
                                        "customize this screen after loging ".
                                        "in as God.\r\n\r\n    \@set #0/" .
                                        "conf.login = Login screen\r\n\r\n";
   @default{badsite}                  = "Your site has been banned.";
   @default{httpd_template}           = "<pre>";
   @default{mudname}                  = "TeenyMUSH";
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

   if($0 =~ /\.([^\.]+)$/ && -e "$1.conf.dev") {
      $fn = "$1.conf.dev";
   } elsif($0 =~ /\.([^\.]+)$/ && -e "$1.conf") {
      $fn = "$1.conf";
   } elsif(-e "teenymush.conf.dev") {
      $fn = "teenymush.conf.dev";
   } else {
      $fn = "teenymush.conf";
   }

   if(!-e $fn) {
      @info{"conf.mudname"} = "TeenyMUSH" if @info{"conf.mudname"} eq undef;
      return;
   }

   con("Reading Config: $fn\n") if $flag;
   for my $line (split(/\n/,getfile($fn))) {
      $line =~ s/\r|\n//g;
      if($line =~/^\s*#/ || $line =~ /^\s*$/) {
         # comment or blank line, ignore
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*#(\d+)\s*$/) {
         @info{$1} = $2 if @info{$1} != -1
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*(.*?)\s*$/) {
         @info{$1} = $2 if @info{$1} != -1
      } else {
         con("Invalid data in $fn:\n") if($count == 0);
         con("    '%s'\n",$line);
         $count++;
      }
   }

   load_config_default();
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
      con("%s ",$txt);                                     # show prompt
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
 
   con("Writing out: %s\n",$fn);

   open($file,"> $fn") ||
      die("Could not open $fn for writing");
 
   if(ref($data) eq "ARRAY") {
      printf($file "%s",join("\n",@$data));
   } else {
      printf($file "%s",$data);
   }

   close($file);
}

#
# get_credentials
#    Prompt the user for database credentials, if needed.
#
sub get_credentials
{
   my ($file,%save);

   return if memorydb;
   if(@info{user} =~ /^\s*$/) {
      @info{user} = prompt("Enter database user: ");
      @save{user} = @info{user};
   }
   if(@info{pass} =~ /^\s*$/) {
      @info{pass} = prompt("Enter database password: ");
      @save{pass} = @info{pass};
   }
   if(@info{database} =~ /^\s*$/) {
      @info{database} = prompt("Enter database name: ");
      @save{database} = @info{database};
   }
   if(@info{host} =~ /^\s*$/) {
      @info{host} = prompt("Enter database host: ");
      @save{host} = @info{host};
   }

   return if scalar keys %save == -1;
  
   open($file,">> teenymush.conf") ||                # write to teenymush.conf
     die("Could not append to teenymush.conf");

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

   con("##############################################################\n");
   con("##                                                          ##\n");
   con("##                  Empty database found                    ##\n");
   con("##                                                          ##\n");
   con("##############################################################\n");
   @info{no_db_found} = 1;

   con("\nDatabase: %s@%s on %s\n\n",
          @info{user},@info{database},$info{host});
   while($result ne "y" && $result ne "yes") {
       $result = prompt("No database found, load default database [yes/no]?");

       if($result eq "n" || $result eq "no") {
          return;
       }
   }
   con("Default database creation log: tm_db_create.log");
   system("mysql -u @info{user} -p{pass} {database} " .
          "< base_structure.sql >> tm_db_create.log");
   system("mysql -u @info{user} -p@info{pass} {database} " .
          " < base_objects.sql >> tm_db_create.log");
   system("mysql -u @info{user} -p@info{pass} @info{database} " .
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
      con("\nLoading backup requires backup stored as tm_backup.sql\n\n");
      con("tm_backup.sql file not found, aborting.\n");
      exit();
   }

   while($result ne "y" && $result ne "yes") {
       $result = prompt("Load database backup from tm_backup.sql [yes/no]? ");

       if($result eq "n" || $result eq "no") {
          exit();
          return;
       }
   }
   system("mysql -u @info{user} -p@info{pass} @info{database} < " .
          "tm_backup.sql >> tm_db_load.log");
   if(!rename("tm_backup.sql","tm_backup.sql.loaded")) {
      con("WARNING: Unable to rename tm_backup.sql, backup will be " .
             "reloaded upon next run unless the file is renamed/deleted.");
   }
}

#
# handle command line arguements
#
sub arg
{
   my $txt = shift;

   for my $i (0 .. $#ARGV) {
      return 1 if(@ARGV[$i] eq $txt || @ARGV[$i] eq "--$txt")
   }
   return 0;
}

sub main
{
   $SIG{HUP} = sub {
      my %ansi_name;
      my %ansi_rgb;
      my $count = reload_code();
      delete @engine{keys %engine};
      con("HUP signal caught, reloading: %s\n",$count ? $count : "none");
   };

   $SIG{'INT'} = sub {  if(memorydb && $#db > -1) {
                           con("**** Program Exiting ******\n");
                           cmd_dump(obj(0),{},"CRASH");
                           @info{crash_dump_complete} = 1;
                           con("**** Dump Complete Exiting ******\n");
                        }
                        exit(1);
                     };

   load_modules();

   @info{version} = "TeenyMUSH 0.9";
   @info{max} = 78;

   read_config(1);                                               #!# load once
   get_credentials();

   load_new_db();                                     #!# optional new db load
   load_db_backup();                                    #!#
   find_free_dbrefs();                                  #!# search for garbage

   initialize_functions();                              #!#
   initialize_ansi();                                   #!#
   initialize_commands();                               #!#
   initialize_flags();                                  #!#
   @info{source_prev} = get_source_checksums(1);        #!#
   reload_code();
   server_start();                                      #!# start only once
}

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

sub initialize_ansi
{
   delete @ansi_rgb{keys %ansi_rgb};
   delete @ansi_name{keys %ansi_name};

   %ansi_rgb = (
   0   => "000000", 1   => "800000", 2   => "008000", 3   => "808000",
   4   => "000080", 5   => "800080", 6   => "008080", 7   => "c0c0c0",
   8   => "808080", 9   => "ff0000", 10  => "00ff00", 11  => "ffff00",
   12  => "0000ff", 13  => "ff00ff", 14  => "00ffff", 15  => "ffffff",
   16  => "000000", 17  => "00005f", 18  => "000087", 19  => "0000af",
   20  => "0000d7", 21  => "0000ff", 22  => "005f00", 23  => "005f5f",
   24  => "005f87", 25  => "005faf", 26  => "005fd7", 27  => "005fff",
   28  => "008700", 29  => "00875f", 30  => "008787", 31  => "0087af",
   32  => "0087d7", 33  => "0087ff", 34  => "00af00", 35  => "00af5f",
   36  => "00af87", 37  => "00afaf", 38  => "00afd7", 39  => "00afff",
   40  => "00d700", 41  => "00d75f", 42  => "00d787", 43  => "00d7af",
   44  => "00d7d7", 45  => "00d7ff", 46  => "00ff00", 47  => "00ff5f",
   48  => "00ff87", 49  => "00ffaf", 50  => "00ffd7", 51  => "00ffff",
   52  => "5f0000", 53  => "5f005f", 54  => "5f0087", 55  => "5f00af",
   56  => "5f00d7", 57  => "5f00ff", 58  => "5f5f00", 59  => "5f5f5f",
   60  => "5f5f87", 61  => "5f5faf", 62  => "5f5fd7", 63  => "5f5fff",
   64  => "5f8700", 65  => "5f875f", 66  => "5f8787", 67  => "5f87af",
   68  => "5f87d7", 69  => "5f87ff", 70  => "5faf00", 71  => "5faf5f",
   72  => "5faf87", 73  => "5fafaf", 74  => "5fafd7", 75  => "5fafff",
   76  => "5fd700", 77  => "5fd75f", 78  => "5fd787", 79  => "5fd7af",
   80  => "5fd7d7", 81  => "5fd7ff", 82  => "5fff00", 83  => "5fff5f",
   84  => "5fff87", 85  => "5fffaf", 86  => "5fffd7", 87  => "5fffff",
   88  => "870000", 89  => "87005f", 90  => "870087", 91  => "8700af",
   92  => "8700d7", 93  => "8700ff", 94  => "875f00", 95  => "875f5f",
   96  => "875f87", 97  => "875faf", 98  => "875fd7", 99  => "875fff",
   100 => "878700", 101 => "87875f", 102 => "878787", 103 => "8787af",
   104 => "8787d7", 105 => "8787ff", 106 => "87af00", 107 => "87af5f",
   108 => "87af87", 109 => "87afaf", 110 => "87afd7", 111 => "87afff",
   112 => "87d700", 113 => "87d75f", 114 => "87d787", 115 => "87d7af",
   116 => "87d7d7", 117 => "87d7ff", 118 => "87ff00", 119 => "87ff5f",
   120 => "87ff87", 121 => "87ffaf", 122 => "87ffd7", 123 => "87ffff",
   124 => "af0000", 125 => "af005f", 126 => "af0087", 127 => "af00af",
   128 => "af00d7", 129 => "af00ff", 130 => "af5f00", 131 => "af5f5f",
   132 => "af5f87", 133 => "af5faf", 134 => "af5fd7", 135 => "af5fff",
   136 => "af8700", 137 => "af875f", 138 => "af8787", 139 => "af87af",
   140 => "af87d7", 141 => "af87ff", 142 => "afaf00", 143 => "afaf5f",
   144 => "afaf87", 145 => "afafaf", 146 => "afafd7", 147 => "afafff",
   148 => "afd700", 149 => "afd75f", 150 => "afd787", 151 => "afd7af",
   152 => "afd7d7", 153 => "afd7ff", 154 => "afff00", 155 => "afff5f",
   156 => "afff87", 157 => "afffaf", 158 => "afffd7", 159 => "afffff",
   160 => "d70000", 161 => "d7005f", 162 => "d70087", 163 => "d700af",
   164 => "d700d7", 165 => "d700ff", 166 => "d75f00", 167 => "d75f5f",
   168 => "d75f87", 169 => "d75faf", 170 => "d75fd7", 171 => "d75fff",
   172 => "d78700", 173 => "d7875f", 174 => "d78787", 175 => "d787af",
   176 => "d787d7", 177 => "d787ff", 178 => "d7af00", 179 => "d7af5f",
   180 => "d7af87", 181 => "d7afaf", 182 => "d7afd7", 183 => "d7afff",
   184 => "d7d700", 185 => "d7d75f", 186 => "d7d787", 187 => "d7d7af",
   188 => "d7d7d7", 189 => "d7d7ff", 190 => "d7ff00", 191 => "d7ff5f",
   192 => "d7ff87", 193 => "d7ffaf", 194 => "d7ffd7", 195 => "d7ffff",
   196 => "ff0000", 197 => "ff005f", 198 => "ff0087", 199 => "ff00af",
   200 => "ff00d7", 201 => "ff00ff", 202 => "ff5f00", 203 => "ff5f5f",
   204 => "ff5f87", 205 => "ff5faf", 206 => "ff5fd7", 207 => "ff5fff",
   208 => "ff8700", 209 => "ff875f", 210 => "ff8787", 211 => "ff87af",
   212 => "ff87d7", 213 => "ff87ff", 214 => "ffaf00", 215 => "ffaf5f",
   216 => "ffaf87", 217 => "ffafaf", 218 => "ffafd7", 219 => "ffafff",
   220 => "ffd700", 221 => "ffd75f", 222 => "ffd787", 223 => "ffd7af",
   224 => "ffd7d7", 225 => "ffd7ff", 226 => "ffff00", 227 => "ffff5f",
   228 => "ffff87", 229 => "ffffaf", 230 => "ffffd7", 231 => "ffffff",
   232 => "080808", 233 => "121212", 234 => "1c1c1c", 235 => "262626",
   236 => "303030", 237 => "3a3a3a", 238 => "444444", 239 => "4e4e4e",
   240 => "585858", 241 => "626262", 242 => "6c6c6c", 243 => "767676",
   244 => "808080", 245 => "8a8a8a", 246 => "949494", 247 => "9e9e9e",
   248 => "a8a8a8", 249 => "b2b2b2", 250 => "bcbcbc", 251 => "c6c6c6",
   252 => "d0d0d0", 253 => "dadada", 254 => "e4e4e4", 255 => "eeeeee",
   ); 

   %ansi_name = (
   aliceblue => 15, antiquewhite => 224, antiquewhite1 => 230,
   antiquewhite2 => 224, antiquewhite3 => 181, antiquewhite4 => 8,
   aquamarine => 122, aquamarine1 =>  122, aquamarine2 => 122,
   aquamarine3 =>  79, aquamarine4 => 66, azure => 15, azure1 => 15,
   azure2 => 255, azure3 => 251, azure4 => 102, beige => 230, bisque => 224,
   bisque1 => 224, bisque2 => 223, bisque3 => 181, bisque4 => 101,
   black => 0, blanchedalmond => 224, blue => 12, blue1 => 12, blue2 => 12,
   blue3 => 20, blue4 => 18, blueviolet => 92, brown => 124, blueviolet => 92,
   brown => 124, brown1 => 203, brown2 => 203, brown3 => 167, brown4 => 88,
   burlywood => 180, burlywood1 => 222, burlywood2 => 222, burlywood3 => 180,
   burlywood4 => 95, cadetblue => 73, cadetblue1 => 123, cadetblue2 => 117,
   cadetblue3 => 116, cadetblue4 => 66, chartreuse => 118, chartreuse1 => 118,
   chartreuse2 => 118, chartreuse3 => 76, chartreuse4 => 64, chocolate => 166,
   chocolate1 => 208, chocolate2 => 208, chocolate3 => 166, chocolate4 => 94,
   coral => 209, coral1 => 203, coral2 => 203, coral3 => 167, coral4 => 94,
   cornflowerblue => 69, cornsilk => 230, cornsilk1 => 230, cornsilk2 => 254,
   cornsilk3 => 187, cornsilk4 => 102, cyan => 14, cyan1 => 14, cyan2 => 14,
   cyan3 => 44, cyan4 => 30, darkblue => 18, darkcyan => 30,
   darkgoldenrod => 136, darkgoldenrod1 => 214, darkgoldenrod2 => 214,
   darkgoldenrod3 => 172, darkgoldenrod4 => 94, darkgray => 248,
   darkgreen => 22, darkgrey => 248, darkkhaki => 143, darkmagenta => 90,
   darkolivegreen => 239, darkolivegreen1 => 191, darkolivegreen2 => 155,
   darkolivegreen3 => 149, darkolivegreen4 => 65, darkorange => 208,
   darkorange1 => 208, darkorange2 => 208, darkorange3 => 166,
   darkorange4 => 94, darkorchid => 98, darkorchid1 => 135, darkorchid2 => 135,
   darkorchid3 => 98, darkorchid4 => 54, darkred => 88, darksalmon => 174,
   darkseagreen => 108, darkseagreen1 => 157, darkseagreen2 => 157,
   darkseagreen3 => 114, darkseagreen4 => 65, darkslateblue => 60,
   darkslategray => 238, darkslategray1 => 123, darkslategray2 => 123,
   darkslategray3 => 116, darkslategray4 => 66, darkslategrey => 238,
   darkturquoise => 44, darkviolet => 92, debianred => 161, deeppink => 198,
   deeppink1 => 198, deeppink2 => 198, deeppink3 => 162, deeppink4 => 89,
   deepskyblue => 39, deepskyblue1 => 39, deepskyblue2 => 39,
   deepskyblue3 => 32, deepskyblue4 => 24, dimgrey => 242, dodgerblue => 33,
   dodgerblue1 => 33, dodgerblue2 => 33, dodgerblue3 => 32, dodgerblue4 => 24,
   firebrick => 124, firebrick1 => 203, firebrick2 => 9, firebrick3 => 160,
   firebrick4 => 88, floralwhite => 15, forestgreen => 28, gainsboro => 253,
   ghostwhite => 15, gold => 220, gold1 => 220, gold2 => 220, gold3 => 178,
   gold4 => 3, goldenrod => 178, goldenrod1 => 214, goldenrod2 => 214,
   goldenrod3 => 172, goldenrod4 => 94, gray => 7, gray0 => 0, gray1 => 0,
   gray2 => 232, gray3 => 232, gray4 => 232, gray5 => 232, gray6 => 233,
   gray7 => 233, gray8 => 233, gray9 => 233, gray10 => 234, gray11 => 234,
   gray12 => 234, gray13 => 234, gray14 => 235, gray15 => 235, gray16 => 235,
   gray17 => 235, gray18 => 236, gray19 => 236, gray20 => 236, gray21 => 237,
   gray22 => 237, gray23 => 237, gray24 => 237, gray25 => 238, gray26 => 238,
   gray27 => 238, gray28 => 238, gray29 => 239, gray30 => 239, gray31 => 239,
   gray32 => 239, gray33 => 240, gray34 => 240, gray35 => 240, gray36 => 59,
   gray37 => 59, gray38 => 241, gray39 => 241, gray40 => 241, gray41 => 242,
   gray42 => 242, gray43 => 242, gray44 => 242, gray45 => 243, gray46 => 243,
   gray47 => 243, gray48 => 243, gray49 => 8, gray50 => 8, gray51 => 8,
   gray52 => 102, gray53 => 102, gray54 => 245, gray55 => 245, gray56 => 245,
   gray57 => 246, gray58 => 246, gray59 => 246, gray60 => 246, gray61 => 247,
   gray62 => 247, gray63 => 247, gray64 => 247, gray65 => 248, gray66 => 248,
   gray67 => 248, gray68 => 145, gray69 => 145, gray70 => 249, gray71 => 249,
   gray72 => 250, gray73 => 250, gray74 => 250, gray75 => 7, gray76 => 7,
   gray77 => 251, gray78 => 251, gray79 => 251, gray80 => 252, gray81 => 252,
   gray82 => 252, gray83 => 188, gray84 => 188, gray85 => 253, gray86 => 253,
   gray87 => 253, gray88 => 254, gray89 => 254, gray90 => 254, gray91 => 254,
   gray92 => 255, gray93 => 255, gray94 => 255, gray95 => 255, gray96 => 255,
   gray97 => 15, gray98 => 15, gray99 => 15, gray100 => 15, green => 10,
   green1 => 10, green2 => 10, green3 => 40, green4 => 28, greenyellow => 154,
   grey => 7, grey0 => 0, grey1 => 0, grey2 => 232, grey3 => 232, grey4 => 232,
   grey5 => 232, grey6 => 233, grey7 => 233, grey8 => 233, grey9 => 233,
   grey10 => 234, grey11 => 234, grey12 => 234, grey13 => 234, grey14 => 235,
   grey15 => 235, grey16 => 235, grey17 => 235, grey18 => 236, grey19 => 236,
   grey20 => 236, grey21 => 237, grey22 => 237, grey23 => 237, grey24 => 237,
   grey25 => 238, grey26 => 238, grey27 => 238, grey28 => 238, grey29 => 239,
   grey30 => 239, grey31 => 239, grey32 => 239, grey33 => 240, grey34 => 240,
   grey35 => 240, grey36 => 59, grey37 => 59, grey38 => 241, grey39 => 241,
   grey40 => 241, grey41 => 242, grey42 => 242, grey43 => 242, grey44 => 242,
   grey45 => 243, grey46 => 243, grey47 => 243, grey48 => 243, grey49 => 8,
   grey50 => 8, grey51 => 8, grey52 => 102, grey53 => 102, grey54 => 245,
   grey55 => 245, grey56 => 245, grey57 => 246, grey58 => 246, grey59 => 246,
   grey60 => 246, grey61 => 247, grey62 => 247, grey63 => 247, grey64 => 247,
   grey65 => 248, grey66 => 248, grey67 => 248, grey68 => 145, grey69 => 145,
   grey70 => 249, grey71 => 249, grey72 => 250, grey73 => 250, grey74 => 250,
   grey75 => 7, grey76 => 7, grey77 => 251, grey78 => 251, grey79 => 251,
   grey80 => 252, grey81 => 252, grey82 => 252, grey83 => 188, grey84 => 188,
   grey85 => 253, grey86 => 253, grey87 => 253, grey88 => 254, grey89 => 254,
   grey90 => 254, grey91 => 254, grey92 => 255, grey93 => 255, grey94 => 255,
   grey95 => 255, grey96 => 255, grey97 => 15, grey98 => 15, grey99 => 15,
   grey100 =>  231, honeydew => 255, honeydew1 => 255, honeydew2 =>  194,
   honeydew2 => 254, honeydew3 => 251, honeydew4 => 102, hotpink => 205,
   hotpink1 => 205, hotpink2 => 205, hotpink3 => 168, hotpink4 => 95,
   indianred => 167, indianred1 => 203, indianred2 => 203, indianred3 => 167,
   indianred4 => 95, indigo => 54, ivory => 15, ivory1 => 15, ivory2 => 255,
   ivory3 => 251, ivory4 => 102, khaki => 222, khaki1 => 228, khaki2 => 222,
   khaki3 => 185, khaki4 => 101, lavender => 255, lavenderblush => 15,
   lavenderblush1 => 15, lavenderblush2 => 254, lavenderblush3 => 251,
   lavenderblush4 => 102, lawngreen => 118, lemonchiffon => 230,
   lemonchiffon1 => 230, lemonchiffon2 => 223, lemonchiffon3 => 187,
   lemonchiffon4 => 101, lightblue => 152, lightblue1 => 159,
   lightblue2 => 153, lightblue3 => 110, lightblue4 => 66, lightcoral => 210,
   lightcyan => 195, lightcyan1 => 195, lightcyan2 => 254, lightcyan3 => 152,
   lightcyan4 => 102, lightgoldenrod => 222, lightgoldenrod1 => 228,
   lightgoldenrod2 => 222, lightgoldenrod3 => 179, lightgoldenrod4 => 101,
   lightgoldenrodyellow => 205, lightgray => 252, lightgreen => 120,
   lightgrey => 252, lightpink => 217, lightpink1 => 217, lightpink2 => 217,
   lightpink3 => 174, lightpink4 => 95, lightsalmon => 216,
   lightsalmon1 => 216, lightsalmon2 => 209, lightsalmon3 => 173,
   lightsalmon4 => 95, lightseagreen => 37, lightskyblue => 117,
   lightskyblue1 => 153, lightskyblue2 => 153, lightskyblue3 => 110,
   lightskyblue4 => 66, lightslateblue => 99, lightslategrey => 102,
   lightsteelblue => 152, lightsteelblue1 => 189, lightsteelblue2 => 153,
   lightsteelblue3 => 146, lightsteelblue4 => 66, lightyellow => 230,
   lightyellow1 => 230, lightyellow2 => 254, lightyellow3 => 187,
   lightyellow4 => 102, limegreen => 77, linen => 255, magenta => 13,
   magenta1 => 13, magenta2 => 13, magenta3 => 164, magenta4 => 90,
   maroon => 131, maroon1 => 205, maroon2 => 205, maroon3 => 162,
   maroon4 => 89, mediumaquamarine => 79, mediumblue => 20,
   mediumorchid => 134, mediumorchid1 => 171, mediumorchid2 => 171,
   mediumorchid3 => 134, mediumorchid4 => 96, mediumpurple => 98,
   mediumpurple1 => 141, mediumpurple2 => 141, mediumpurple3 => 98,
   mediumpurple4 => 60, mediumseagreen => 71, mediumslateblue => 99,
   mediumspringgreen => 48, mediumturquoise => 80, mediumvioletred => 162,
   midnightblue => 4, mintcream => 15, mistyrose => 224, mistyrose1 => 224,
   mistyrose2 => 224, mistyrose3 => 181, mistyrose4 => 8, moccasin => 223,
   navajowhite => 223, navajowhite1 => 223, navajowhite2 => 223,
   navajowhite3 => 180, navajowhite4 => 101, navy => 4, navyblue => 4,
   oldlace => 230, olivedrab => 64, olivedrab1 => 155, olivedrab2 => 155,
   olivedrab3 => 113, olivedrab4 => 64, orange => 214, orange1 => 214,
   orange2 => 208, orange3 => 172, orange4 => 94, orangered => 202,
   orangered1 => 202, orangered2 => 202, orangered3 => 166, orangered4 => 88,
   orchid => 170, orchid1 => 213, orchid2 => 212, orchid3 => 170,
   orchid4 => 96, palegoldenrod => 223, palegreen => 120, palegreen1 => 120,
   palegreen2 => 120, palegreen3 => 114, palegreen4 => 65,
   paleturquoise => 159, paleturquoise1 => 159, paleturquoise2 => 159,
   paleturquoise3 => 116, paleturquoise4 => 66, palevioletred => 168,
   palevioletred1 => 211, palevioletred2 => 211, palevioletred3 => 168,
   palevioletred4 => 95, papayawhip => 230, peachpuff => 223,
   peachpuff1 => 223, peachpuff2 => 223, peachpuff3 => 180, peachpuff4 => 101,
   peru => 173, pink => 218, pink1 => 218, pink2 => 217, pink3 => 175,
   pink4 => 95, plum => 182, plum1 => 219, plum2 => 183, plum3 => 176,
   plum4 => 96, powderblue => 152, purple => 129, purple1 => 99,
   purple2 => 93, purple3 => 92, purple4 => 54, red => 9, red1 => 9, red2=>9,
   red3 => 160, red4 => 88, rosybrown => 138, rosybrown1 => 217,
   rosybrown2 => 217, rosybrown3 => 174, rosybrown4 => 95, royalblue => 62,
   royalblue1 => 69, royalblue2 => 63, royalblue3 => 62, royalblue4 => 24,
   saddlebrown => 94, salmon => 209, salmon1 => 209, salmon2 => 209,
   salmon3 => 167, salmon4 => 95, sandybrown => 215, seagreen => 29,
   seagreen1 => 85, seagreen2 => 84, seagreen3 => 78, seagreen4 => 29,
   seashell => 255, seashell1 => 255, seashell2 => 254, seashell3 => 251,
   seashell4 => 102, sienna => 130, sienna1 => 209, sienna1 => 209,
   sienna2 => 209, sienna3 => 167, sienna4 => 94, skyblue => 116,
   skyblue1 => 117, skyblue2 => 111, skyblue3 => 74, skyblue4 => 60,
   slateblue => 62, slateblue1 => 99, slateblue2 => 99, slateblue3 => 62,
   slateblue4 => 60, slategray => 66, slategray1 => 189, slategray2 => 153,
   slategray3 => 146, slategray4 => 66, slategrey => 66, snow => 15,
   snow1 => 15, snow2 => 255, snow3 => 251, snow4 => 245, springgreen => 48,
   springgreen1 => 48, springgreen2 => 48, springgreen3 => 41,
   springgreen4 => 29, steelblue => 67, steelblue1 => 75, steelblue2 => 75,
   steelblue3 => 68, steelblue4 => 60, tan => 180, tan1 => 215, tan2 => 209,
   tan3 => 173, tan4 => 94, thistle => 182, thistle1 => 225, thistle2 => 254,
   thistle3 => 182, thistle4 => 102, tomato => 203, tomato1 => 203,
   tomato2 => 203, tomato3 => 167, tomato4 => 94, turquoise => 80,
   turquoise1 => 14, turquoise2 => 45, turquoise3 => 44, turquoise4 => 30,
   violet => 213, violetred => 162, violetred1 => 204, violetred2 => 204,
   violetred3 => 168, violetred4 => 89, wheat => 223, wheat1 => 223,
   wheat2 => 223, wheat3 => 180, wheat4 => 101, white => 15, whitesmoke => 255,
   xterm0 => 0, xterm1 => 1, xterm2 => 2, xterm3 => 3, xterm4 => 4,
   xterm5 => 5, xterm6 => 6, xterm7 => 7, xterm8 => 8, xterm9 => 9,
   xterm10 => 10, xterm11 => 11, xterm12 => 12, xterm13 => 13, xterm14 => 14,
   xterm15 => 15, xterm16 => 16, xterm17 => 17, xterm18 => 18, xterm19 => 19,
   xterm20 => 20, xterm21 => 21, xterm22 => 22, xterm23 => 23, xterm24 => 24,
   xterm25 => 25, xterm26 => 26, xterm27 => 27, xterm28 => 28, xterm29 => 29,
   xterm30 => 30, xterm31 => 31, xterm32 => 32, xterm33 => 33, xterm34 => 34,
   xterm35 => 35, xterm36 => 36, xterm37 => 37, xterm38 => 38, xterm39 => 39,
   xterm40 => 40, xterm41 => 41, xterm42 => 42, xterm43 => 43, xterm44 => 44,
   xterm45 => 45, xterm46 => 46, xterm47 => 47, xterm48 => 48, xterm49 => 49,
   xterm50 => 50, xterm51 => 51, xterm52 => 52, xterm53 => 53, xterm54 => 54,
   xterm55 => 55, xterm56 => 56, xterm57 => 57, xterm58 => 58, xterm59 => 59,
   xterm60 => 60, xterm61 => 61, xterm62 => 62, xterm63 => 63, xterm64 => 64,
   xterm65 => 65, xterm66 => 66, xterm67 => 67, xterm68 => 68, xterm69 => 69,
   xterm70 => 70, xterm71 => 71, xterm72 => 72, xterm73 => 73, xterm74 => 74,
   xterm75 => 75, xterm76 => 76, xterm77 => 77, xterm78 => 78, xterm79 => 79,
   xterm80 => 80, xterm81 => 81, xterm82 => 82, xterm83 => 83, xterm84 => 84,
   xterm85 => 85, xterm86 => 86, xterm87 => 87, xterm88 => 88, xterm89 => 89,
   xterm90 => 90, xterm91 => 91, xterm92 => 92, xterm93 => 93, xterm94 => 94,
   xterm95 => 95, xterm96 => 96, xterm97 => 97, xterm98 => 98, xterm99 => 99,
   xterm100 => 100, xterm101 => 101, xterm102 => 102, xterm103 => 103,
   xterm104 => 104, xterm105 => 105, xterm106 => 106, xterm107 => 107,
   xterm108 => 108, xterm109 => 109, xterm110 => 110, xterm111 => 111,
   xterm112 => 112, xterm113 => 113, xterm114 => 114, xterm115 => 115,
   xterm116 => 116, xterm117 => 117, xterm118 => 118, xterm119 => 119,
   xterm120 => 120, xterm121 => 121, xterm122 => 122, xterm123 => 123,
   xterm124 => 124, xterm125 => 125, xterm126 => 126, xterm127 => 127,
   xterm128 => 128, xterm129 => 129, xterm130 => 130, xterm131 => 131,
   xterm132 => 132, xterm133 => 133, xterm134 => 134, xterm135 => 135,
   xterm136 => 136, xterm137 => 137, xterm138 => 138, xterm139 => 139,
   xterm140 => 140, xterm141 => 141, xterm142 => 142, xterm143 => 143,
   xterm144 => 144, xterm145 => 145, xterm146 => 146, xterm147 => 147,
   xterm148 => 148, xterm149 => 149, xterm150 => 150, xterm151 => 151,
   xterm152 => 152, xterm153 => 153, xterm154 => 154, xterm155 => 155,
   xterm156 => 156, xterm157 => 157, xterm158 => 158, xterm159 => 159,
   xterm160 => 160, xterm161 => 161, xterm162 => 162, xterm163 => 163,
   xterm164 => 164, xterm165 => 165, xterm166 => 166, xterm167 => 167,
   xterm168 => 168, xterm169 => 169, xterm170 => 170, xterm171 => 171,
   xterm172 => 172, xterm173 => 173, xterm174 => 174, xterm175 => 175,
   xterm176 => 176, xterm177 => 177, xterm178 => 178, xterm179 => 179,
   xterm180 => 180, xterm181 => 181, xterm182 => 182, xterm183 => 183,
   xterm184 => 184, xterm185 => 185, xterm186 => 186, xterm187 => 187,
   xterm188 => 188, xterm189 => 189, xterm190 => 190, xterm191 => 191,
   xterm192 => 192, xterm193 => 193, xterm194 => 194, xterm195 => 195,
   xterm196 => 196, xterm197 => 197, xterm198 => 198, xterm199 => 199,
   xterm200 => 200, xterm201 => 201, xterm202 => 202, xterm203 => 203,
   xterm204 => 204, xterm205 => 205, xterm206 => 206, xterm207 => 207,
   xterm208 => 208, xterm209 => 209, xterm210 => 210, xterm211 => 211,
   xterm212 => 212, xterm213 => 213, xterm214 => 214, xterm215 => 215,
   xterm216 => 216, xterm217 => 217, xterm218 => 218, xterm219 => 219,
   xterm220 => 220, xterm221 => 221, xterm222 => 222, xterm223 => 223,
   xterm224 => 224, xterm225 => 225, xterm226 => 226, xterm227 => 227,
   xterm228 => 228, xterm229 => 229, xterm230 => 230, xterm231 => 231,
   xterm232 => 232, xterm233 => 233, xterm234 => 234, xterm235 => 235,
   xterm236 => 236, xterm237 => 237, xterm238 => 238, xterm239 => 239,
   xterm240 => 240, xterm241 => 241, xterm242 => 242, xterm243 => 243,
   xterm244 => 244, xterm245 => 245, xterm246 => 246, xterm247 => 247,
   xterm248 => 248, xterm249 => 249, xterm250 => 250, xterm251 => 251,
   xterm252 => 252, xterm253 => 253, xterm254 => 254, xterm255 => 255,
   yellow => 11, yellow1 => 11, yellow2 => 11, yellow3 => 184, yellow4 => 100,
   yellowgreen => 113,
   );
}

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

   @offline{connect}     = sub { return cmd_connect(@_);                    };
   @offline{who}         = sub { return cmd_who(@_);                        };
   @offline{create}      = sub { return cmd_pcreate(@_);                    };
   @offline{quit}        = sub { return cmd_quit(@_);                       };
   @offline{huh}         = sub { return cmd_offline_huh(@_);                };
   @offline{screenwidth} = sub { return;                                    };
   @offline{screenheight}= sub { return;                                    };
   # ------------------------------------------------------------------------#
   @command{screenwidth} ={ fun => sub { return 1;}                         };
   @command{screenheight}={ fun => sub { return 1;}                         };
   @command{"\@perl"}   = { fun => sub { return &cmd_perl(@_); }            };
   @command{say}        = { fun => sub { return &cmd_say(@_); }             };
   @command{"\""}       = { fun => sub { return &cmd_say(@_); },     nsp=>1 };
   @command{"`"}        = { fun => sub { return &cmd_to(@_); },      nsp=>1 };
   @command{"&"}        = { fun => sub { return &cmd_set2(@_); },    nsp=>1 };
   @command{"\@reload"} = { fun => sub { return &cmd_reload_code(@_); }     };
   @command{pose}       = { fun => sub { return &cmd_pose(@_); }            };
   @command{":"}        = { fun => sub { return &cmd_pose(@_); },    nsp=>1 };
   @command{";"}        = { fun => sub { return &cmd_pose(@_,1); },  nsp=>1 };
   @command{"emote"}    = { fun => sub { return &cmd_pose(@_,1); },  nsp=>1 };
   @command{who}        = { fun => sub { return &cmd_who(@_); }             };
   @command{whisper}    = { fun => sub { return &cmd_whisper(@_); }         };
   @command{w}          = { fun => sub { return &cmd_whisper(@_); }         };
   @command{doing}      = { fun => sub { return &cmd_DOING(@_); }           };
   @command{"\@doing"}  = { fun => sub { return &cmd_doing(@_); }           };
   @command{"\@poll"}   = { fun => sub { return &cmd_doing(@_[0],@_[1],@_[2],
                                                   { header=>1}); }};
   @command{help}       = { fun => sub { return &cmd_help(@_); }            };
   @command{"\@dig"}    = { fun => sub { return &cmd_dig(@_); }             };
   @command{"look"}     = { fun => sub { return &cmd_look(@_); }            };
   @command{"l"}        = { fun => sub { return &cmd_look(@_); }            };
   @command{quit}       = { fun => sub { return cmd_quit(@_); }             };
   @command{"\@trigger"}= { fun => sub { return cmd_trigger(@_); }          };
   @command{"\@commit"} = { fun => sub { return cmd_commit(@_); }           };
   @command{"\@set"}    = { fun => sub { return cmd_set(@_); }              };
   @command{"\@cls"}    = { fun => sub { return cmd_clear(@_); }            };
   @command{"\@create"} = { fun => sub { return cmd_create(@_); }           };
   @command{"print"}    = { fun => sub { return cmd_print(@_); }            };
   @command{"go"}       = { fun => sub { return cmd_go(@_); }               };
   @command{"home"}     = { fun => sub { return cmd_go($_[0],$_[1],"home");} };
   @command{"examine"}  = { fun => sub { return cmd_ex(@_); }               };
   @command{"ex"}       = { fun => sub { return cmd_ex(@_); }               };
   @command{"e"}        = { fun => sub { return cmd_ex(@_); }               };
   @command{"\@last"}   = { fun => sub { return cmd_last(@_); }             };
   @command{page}       = { fun => sub { cmd_page(@_); }                    };
   @command{p}          = { fun => sub { cmd_page(@_); }                    };
   @command{take}       = { fun => sub { cmd_take(@_); }                    };
   @command{get}        = { fun => sub { cmd_take(@_); }                    };
   @command{drop}       = { fun => sub { cmd_drop(@_); }                    };
   @command{"\@force"}  = { fun => sub { cmd_force(@_); }                   };
   @command{inventory}  = { fun => sub { cmd_inventory(@_); }               };
   @command{i}          = { fun => sub { cmd_inventory(@_); }               };
   @command{enter}      = { fun => sub { cmd_enter(@_); }                   };
   @command{leave}      = { fun => sub { cmd_leave(@_); }                   };
   @command{"\@name"}   = { fun => sub { cmd_name(@_); }                    };
   @command{"\@moniker"}= { fun => sub { cmd_name(@_); }                    };
   @command{"\@describe"}={ fun => sub { cmd_generic_set(@_); }             };
   @command{"\@pemit"}  = { fun => sub { cmd_pemit(@_); }                   };
   @command{"\@emit"}   = { fun => sub { cmd_emit(@_); }                    };
   @command{"think"}    = { fun => sub { cmd_think(@_); }                   };
   @command{"version"}  = { fun => sub { cmd_version(@_); }                 };
   @command{"\@version"}= { fun => sub { cmd_version(@_); }                 };
   @command{"\@link"}   = { fun => sub { cmd_link(@_); }                    };
   @command{"\@teleport"}={ fun => sub { cmd_teleport(@_); }                };
   @command{"\@tel"}    = { fun => sub { cmd_teleport(@_); }                };
   @command{"\@open"}   = { fun => sub { cmd_open(@_); }                    };
   @command{"\@uptime"} = { fun => sub { cmd_uptime(@_); }                  };
   @command{"\@destroy"}= { fun => sub { cmd_destroy(@_); }                 };
   @command{"\@wipe"}   = { fun => sub { cmd_wipe(@_); }                    };
   @command{"\@toad"}   = { fun => sub { cmd_toad(@_); }                    };
   @command{"\@sleep"}  = { fun => sub { cmd_sleep(@_); }                   };
   @command{"\@wait"}   = { fun => sub { cmd_wait(@_); }                    };
   @command{"\@sweep"}  = { fun => sub { cmd_sweep(@_); }                   };
   @command{"\@list"}   = { fun => sub { cmd_list(@_); }                    };
   @command{"\@mail"}   = { fun => sub { cmd_mail(@_); }                    };
   @command{"score"}    = { fun => sub { cmd_score(@_); }                   };
   @command{"\@recall"} = { fun => sub { cmd_recall(@_); }                  };
   @command{"\@telnet"} = { fun => sub { cmd_telnet(@_); }                  };
   @command{"\@close"}  = { fun => sub { cmd_close(@_); }                   };
   @command{"\@reset"}  = { fun => sub { cmd_reset(@_); }                   };
   @command{"\@send"}   = { fun => sub { cmd_send(@_); }                    };
   @command{"\@password"}={ fun => sub { cmd_password(@_); }                };
   @command{"\@newpassword"}={ fun => sub { cmd_newpassword(@_); }          };
   @command{"\@switch"}  ={ fun => sub { cmd_switch(@_); }                  };
   @command{"\@select"}  ={ fun => sub { cmd_switch(@_); }                  };
   @command{"\@ps"}      ={ fun => sub { cmd_ps(@_); }                      };
   @command{"\@kill"}    ={ fun => sub { cmd_killpid(@_); }                 };
   @command{"\@var"}     ={ fun => sub { cmd_var(@_); }                     };
   @command{"\@dolist"}  ={ fun => sub { cmd_dolist(@_); }                  };
   @command{"\@notify"}  ={ fun => sub { cmd_notify(@_); }                  };
   @command{"\@drain"}   ={ fun => sub { cmd_drain(@_); }                   };
   @command{"\@while"}   ={ fun => sub { cmd_while(@_); }                   };
   @command{"\@crash"}   ={ fun => sub { cmd_crash(@_); }                   };
   @command{"\@\@"}     = { fun => sub { return;}                           };
   @command{"\@lock"}   = { fun => sub { cmd_lock(@_);}                     };
   @command{"\@boot"}   = { fun => sub { cmd_boot(@_);}                     };
   @command{"\@halt"}   = { fun => sub { cmd_halt(@_);}                     };
   @command{"\@sex"}    = { fun => sub { cmd_generic_set(@_);}              };
   @command{"\@apay"}   = { fun => sub { cmd_generic_set(@_);}              };
   @command{"\@opay"}   = { fun => sub { cmd_generic_set(@_);}              };
   @command{"\@pay"}    = { fun => sub { cmd_generic_set(@_);}              };
   @command{"\@read"}   = { fun => sub { cmd_read(@_);}                     };
   @command{"\@compile"}= { fun => sub { cmd_compile(@_);}                  };
   @command{"\@clean"}=   { fun => sub { cmd_clean(@_);}                    };
   @command{"give"}=      { fun => sub { cmd_give(@_);}                     };
   @command{"\@squish"} = { fun => sub { cmd_squish(@_);}                   };
   @command{"\@split"}  = { fun => sub { cmd_split(@_); }                   };
   @command{"\@websocket"}={fun => sub { cmd_websocket(@_); }               };
   @command{"\@find"}   = { fun => sub { cmd_find(@_); }                    };
   @command{"\@bad"}    = { fun => sub { cmd_bad(@_); }                     };
   @command{"\@sqldump"}= { fun => sub { db_sql_dump(@_); }                 };
   @command{"\@dbread"} = { fun => sub { fun_dbread(@_); }                  };
   @command{"\@dump"}   = { fun => sub { cmd_dump(@_); }                    };
   @command{"\@import"} = { fun => sub { cmd_import(@_); }                  };
   @command{"\@stat"}   = { fun => sub { cmd_stat(@_); }                    };
   @command{"\@cost"}   = { fun => sub { cmd_generic_set(@_); }             };
   @command{"\@quota"}  = { fun => sub { cmd_quota(@_); }                   };
   @command{"\@player"} = { fun => sub { cmd_player(@_); }                  };
   @command{"huh"}      = { fun => sub { cmd_huh(@_); }                     };
   @command{"\@\@"}     = { fun => sub { return 1; }                        };

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
}
 

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

#
# get_mail_idx
#    Build an index of attributes for email messages.
#
sub get_mail_idx
{
   my $self = shift;

   return sort { substr($a,9) <=> substr($b,9) } # build index
                grep(/^obj_mail_/i,lattr($self));
}

sub get_mail
{
   my ($self,$num) = @_;

   return undef if($num !~ /^\s*(\d+)\s*$/ || $num <= 0);   # invalid number

   my @list = get_mail_idx($self);

   return undef if(!defined @list[$num-1]);          # invalid email number
   
   my $attr = get($self,@list[$num-1]) ||
      return undef;

   if($attr =~ /^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,/) {
       return { sent => $1,
                from => $2,
                new  => $3,
                msg  => $',
                attr => @list[$num-1],
                num  => trim($num)
         };
   } else {
      return undef;
   }
}

sub cmd_quota
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   my ($player,$value) = balanced_split($txt,"=",4);
   $player = "me" if ($player eq undef);

   my $target = find_player($self,$prog,evaluate($self,$prog,$player)) ||
      return err($self,$prog,"Unknown player.");

   if(!controls($self,$target)) {
      return err($self,$prog,"Permission denied.");
   }

   if($value ne undef) {
      if(!hasflag($self,"WIZARD")) {
         return err($self,$prog,"Permission denied.");
      } elsif($value =~ /^\s*(\d+)\s*$/) {
         db_set($target,"obj_quota",$1);
         db_set($target,"obj_total_quota",$1);
      } else {
         return err($self,$prog,"Invalid number ($value).");
      }
   }

   my $total = nvl(get($target,"obj_total_quota"),0);
   my $left = nvl(get($target,"obj_quota"),0);
   necho(self   => $self,                                    # notify user
         prog   => $prog,
         source => [ "%s Quota: %9s  Used: %9s",
                     name($target),
                     $total,
                     $total - $left
                   ]
        );
}

#
# cmd_wipe
#    Erase all the attribute on an object.
#
sub cmd_wipe
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $count = 0;

   my ($obj,$pattern) = meval($self,$prog,balanced_split(shift,"/",4));

   my $target = find($self,$prog,$obj) ||            # can't find target
      return err($self,$prog,"No match.");

   if(!controls($self,$target)) {                    # check permissions
      return err($self,$prog,"Permission denied.");
   } elsif(hasflag($target,"GOD") && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   }

   my $pat = glob2re($pattern) if($pattern ne undef); # convert pattern to
                                                      # regular expression

   for my $attr (grep {!/^obj_/} lattr($target)) {         # search object
      if($pat eq undef || $attr =~ /$pat/i) {       # wipe specified attrs
         set($self,$prog,$target,$attr,undef,1);
         $count++;
      }
   }

   necho(self   => $self,                                    # notify user
         prog   => $prog,
         source => [ "Wiped - %d attribute%s.",$count,($count != 1) ? "s" : ""]
        );
}

#
# cmd_generic_set
#    Lots of mush commands just set attributes. In TinyMUSH these each might
#    be handled differently, but they're all just attributes in TeenyMUSH.
#
sub cmd_generic_set
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   my $cmd = $$prog{cmd};         # the command isn't passed in, so get it.

   if(lc($$cmd{mushcmd}) eq "\@desc" ||
      lc($$cmd{mushcmd}) eq "\@describe") {
      $$cmd{mushcmd} = "\@description";
   }
   cmd_set2($self,$prog,substr($$cmd{mushcmd},1) . " " . $txt);
}

sub gather_stats
{
   my ($type,$txt,$target) = (shift,lc(trim(shift)),shift);
   my $owner;

   my $hash = {
      PLAYER  => 0,
      OBJECT  => 0,
      EXIT    => 0,
      ROOM    => 0,
      GARBAGE => 0
   };

   $txt eq "all" if($txt eq undef);                       # default to all

   if($target ne undef) {
      $owner = owner_id($target);
   }

   if(memorydb) {
      if($type == 2) {
         $$hash{OBJECT} = $#db + 1;
      } else {
         for my $i (0 .. $#db) {
            if(!valid_dbref($i)) {
               $$hash{GARBAGE}++;
            } elsif($txt eq "all" || owner($i) == $owner) {
               if(hasflag($i,"PLAYER")) {
                  $$hash{PLAYER}++;
               } elsif(hasflag($i,"OBJECT")) {
                  $$hash{OBJECT}++;
               } elsif(hasflag($i,"EXIT")) {
                  printf("HERE 3\n") if($i == 1);
                  $$hash{EXIT}++;
               } elsif(hasflag($i,"ROOM")) {
                  $$hash{ROOM}++;
               }
            }
         }
      }
   } elsif($type == 2) {
      $$hash{OBJECT} = one_val("select count(*) value from object");
   } else {
      for my $data (@{sql("select fde_name, count(*) count " .
                          "  from object obj, flag flg, flag_definition fde " .
                          " where obj.obj_id = flg.obj_id " .
                          "   and flg.fde_flag_id = fde.fde_flag_id " .
                          "   and (obj.obj_owner = ? or 'all' = ?) ".
                          "   and flg.fde_flag_id = fde.fde_flag_id " .
                          "   and fde_name in ('PLAYER', " .
                          "                    'OBJECT', " .
                          "                    'ROOM', " .
                          "                    'EXIT')" .
                          " group by fde_name",
                          $owner,
                          $txt
         )}) {
         $$hash{$$data{fde_name}} = $$data{count};
      }
   }

   return $hash;
}

sub cmd_stat
{
   my ($self,$prog,$txt,$switch) = (obj(shift),obj(shift),shift,shift);
   my ($hash, $target);

   verify_switches($self,$prog,$switch,"all","quiet") || return;

   $txt = evaluate($self,$prog,$txt);

   if(defined $$switch{all}) {
      $hash = gather_stats(1,"all");
   } elsif($txt =~ /^\s*$/) {
      $hash = gather_stats(2);
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "The universe contains %d objects.",
                                $$hash{OBJECT} ]
                  );
   } else {
      $target = find_player($self,$prog,$txt) ||
         return err($self,$prog,"Unknown player.");

      $hash = gather_stats(1,"",$target);
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s objects = %s rooms, %s exits, %s things, %s " .
                        "players. (%s garbage)",
                     $$hash{ROOM} + $$hash{EXIT} + $$hash{OBJECT} +
                         $$hash{PLAYER} +  $$hash{GARBAGE},
                     $$hash{ROOM},
                     $$hash{EXIT},
                     $$hash{OBJECT},
                     $$hash{PLAYER},
                     $$hash{GARBAGE} ]
        );
}


sub cmd_import
{
   my ($self,$prog,$txt) = (obj(shift),obj(shift),shift);

   if(!hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   } else {
      db_read_import($self,$prog,$txt);    
   }
}

sub cmd_mail
{
   my ($self,$prog) = (obj(shift),obj(shift));

   my ($txt,$value) = balanced_split(shift,"=",4);
   $txt = evaluate($self,$prog,$txt);
   my $switch = shift;

   if(defined $$switch{delete}) {                            # handle delete
      return err($self,$prog,"Invalid email message.") if ($value ne undef);

      my $mail = get_mail($self,$txt);

      return err($self,$prog,"Invalid email message.") if ($mail eq undef);

      set($self,$prog,$self,$$mail{attr},undef,1);

      necho(self   => $self,
            prog   => $prog,
            source => [ "MAIL: Deleted." ]
           );
   } elsif($value ne undef) {                           # handle mail send
      $value = evaluate($self,$prog,$value) if(@{$$prog{cmd}}{source} == 0);
      
      my $target = find_player($self,$prog,$txt) ||
         return err($self,$prog,"Unknown player.");

      my @list = (get_mail_idx($target));              # get next seq number
      my $seq = ($#list == -1) ? 1 : (substr(@list[$#list],9)+1);

      set($self,$prog,$target,"OBJ_MAIL_$seq",           # save email message
          time() .",". owner_id($self) . ",1," . trim($value),1);

      necho(self   => $self,
            prog   => $prog,
            source => [ "MAIL: You have sent mail to %s.", name($target) ],
            target => [ $target, "MAIL: You have a new message from %s.",
                        name(owner($self))]
           );
   } elsif($txt =~ /^\s*short\s*$/) {
      my @list = get_mail_idx($self);
      necho(self   => $self,
            prog   => $prog,
            source => [ "MAIL: You have %s messages.", $#list + 1 ]
           );
   } elsif($txt =~ /^\s*(\d+)\s*$/) {                       # display 1 email
      my $mail = get_mail($self,$1) ||
         return err($self,$prog,"Invalid email message.");

      necho(self   => $self,                                  # show results
            prog   => $prog,
            source => [ "%s\nFrom:    %-37s At: %s\n%s\n%s\n%s\n", 
                        ("-" x 75),
                        name($$mail{from}),
                        scalar localtime($$mail{sent}),
                        ("-" x 75),
                        trim($$mail{msg}),
                        ("-" x 75)
                      ]
           );

      set($self,$prog,$self,$$mail{attr},                      # set read flag
          "$$mail{sent},$$mail{from},0,$$mail{msg}",1);

   } else {                                         # show detailed mail list
      my $out;
      my @list = get_mail_idx($self);
      for my $pos (0 .. $#list) {
         my $mail = get_mail($self,$pos+1);

         my ($sec,$min,$hr,$day,$mon,$yr) = localtime($$mail{sent});
         my $name = ansi_substr(name($$mail{from}),0,15);
         $out .= sprintf("%3s|%4s | %02d:%02d %02d:%02d/%02d | %s%s " .
                         "| %s\n",
                         $pos+1,
                         $$mail{new} ? "Yes" : "",
                         $hr,$min,$mon+1,$day,$yr%100,$name,
                         (" " x (15 - ansi_length($name))),
                         (ansi_length($$mail{msg}) > 29) ?
                         (ansi_substr($$mail{msg},0,26) . "...") :
                         $$mail{msg}
                        );

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

      if(@info{rows} != 1 ) {
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

#
# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
   my ($self,$prog,$txt) = @_;
   my (%last,$first);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return out($prog,"#-1 \@WHILE can not be called from RUN function");

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

    if($$cmd{while_count} >= 5000) {
       con("#*****# while exceeded maxium loop of 1000, stopped\n");
       return err($self,$prog,"while exceeded maxium loop of 1000, stopped");
    } elsif(test($self,$prog,$$cmd{while_test})) {
       mushrun(self   => $self,
               prog   => $prog,
               source => 0,
               cmd    => $$cmd{while_cmd},
               child  => 1
              );
       return "RUNNING";
    }
    return "DONE";
}


sub member
{
   my ($loc,$id,@list) = @_;

   for my $i (@list) {
      return 1 if($id eq $$i{obj_id});
   } 
   return 0;
}

sub bad_object
{
   my $obj = shift;

   if(ref($obj) ne "HASH") {
      $obj = { obj_id => $obj };
   }

   if(!valid_dbref($obj,1)) {
      return 3;
   } elsif(name($obj) eq undef) {
      return 1;
   } elsif(flag_list($obj,1) eq undef) {
      return 2;
   } else {
      return 0;
   }
}

sub cmd_bad
{
   my ($self,$prog) = @_;
   my (@out, $start);

   if(mysqldb) {
      return err($self,$prog,"This command is disabled.");
   } elsif(defined $$prog{nomushrun}) {
      return err($self,$prog,"This command is not run() safe.");
   }

   my $cmd = $$prog{cmd_last};
   $$cmd{bad_pos} = 0 if(!defined $$cmd{bad_pos});     # initialize "loop"

   for($start=$$cmd{bad_pos};                   # loop for 100 objects
          $$cmd{bad_pos} < $#db &&
          $$cmd{bad_pos} - $start < 100;
          $$cmd{bad_pos}++) {
      if(valid_dbref($$cmd{bad_pos})) {              # does object match?
         if(bad_object($$cmd{bad_pos})) {
            push(@out,"#" . $$cmd{bad_pos} . " is corrupted, deleting.");
            db_delete($$cmd{bad_pos});
         } else {
            if(!hasflag($$cmd{bad_pos},"PLAYER") &&
               !hasflag($$cmd{bad_pos},"OBJECT") &&
               !hasflag($$cmd{bad_pos},"EXIT") &&
               !hasflag($$cmd{bad_pos},"ROOM")) {
               push(@out,"#" . $$cmd{bad_pos} ." No TYPE flag, set to -> '".
                  type($self,$prog,$$cmd{bad_pos}) . "'");
            }

            if(hasflag($$cmd{bad_pos},"PLAYER")) {
               my $total = get($$cmd{bad_pos},"obj_total_quota");
               my $left = get($$cmd{bad_pos},"obj_quota");

               if($total eq undef && $left eq undef) {
                  ($total,$left) = (0,0);
               } elsif($left ne undef && $total eq undef) {
                  $total = $left;
               } elsif($total ne undef && $left eq undef) {
                  $left = $total;
               }
               db_set($$cmd{bad_pos},"obj_total_quota",$total);
               db_set($$cmd{bad_pos},"obj_quota",$left);
            }

            if(hasflag($$cmd{bad_pos},"EXIT") && 
               !hasflag(loc($$cmd{bad_pos}),"ROOM")) {
               my $loc = loc($$cmd{bad_pos});
               push(@out,"#" . obj_name($self,$$cmd{bad_pos}) ." not in a room, is in " .
                  (($loc eq undef) ? "N/A" : obj_name($self,$loc)));
            }

            if(hasflag($$cmd{bad_pos},"PLAYER") && 
               money($$cmd{bad_pos}) eq undef) {
               push(@out,"#" . $$cmd{bad_pos} ." no money");
               db_set($$cmd{bad_pos},"obj_money",
                  @info{"conf.starting_money"});
             }

            if(hasflag($$cmd{bad_pos},"ROOM")) {
               my $loc = get($$cmd{bad_pos},"obj_location");
               if($loc ne undef) {
                  push(@out, "Room #$$cmd{bad_pos} has a location[$loc], removed.");
                  db_set($$cmd{bad_pos},"obj_location");
                  if(valid_dbref($loc)) {
                     db_remove_list($loc,"obj_content",$$cmd{bad_pos});
                  }
               }
            }

            for my $obj (lcon($$cmd{bad_pos})) {
               if(!valid_dbref($obj)) {
                  push(@out,"#" . $$cmd{bad_pos} . " removed from contents " .
                       "#" . $$obj{obj_id} . "[destroyed object]");
                  db_remove_list($$cmd{bad_pos},"obj_content",$$obj{obj_id});
               } elsif(!hasflag($obj,"PLAYER") && !hasflag($obj,"OBJECT")) {
                  push(@out,
                       "#$$obj{obj_id} is not an object in #$$cmd{bad_pos}");
               }
            }

            for my $obj (lexits($$cmd{bad_pos})) {
               if(!valid_dbref($obj)) {
                  con("Removing \@destroyed obj #%s from exit list of #%s\n",
                     $$obj{obj_id},$$cmd{bad_pos});
                  db_remove_list($$cmd{bad_pos},"obj_exits",$$obj{obj_id});
               } elsif(!hasflag($obj,"EXIT")) {
                  push(@out,"#$$obj{obj_id} is not an exit [$$cmd{bad_pos}]. ");
               }
            }

            if(!hasflag($$cmd{bad_pos},"ROOM")) {
               my $loc = loc($$cmd{bad_pos});

               if($loc eq undef) {
                  push(@out,"#" . $$cmd{bad_pos} ." No location, sent home(#".
                       home($$cmd{bad_pos}) . ").");
                  teleport($self,$prog,$$cmd{bad_pos},home($$cmd{bad_pos}));
               } elsif(hasflag($$cmd{bad_pos},"EXIT")) {
                  if(!member($loc,$$cmd{bad_pos},lexits($loc))) {
                     push(@out,"#" . $$cmd{bad_pos} ." not in lexit() of " .
                          "$loc");
                  }
               } elsif(!member($loc,$$cmd{bad_pos},lcon($loc))) {
                  if(valid_dbref($loc) && !bad_object($loc)) {
                     push(@out,"#" . $$cmd{bad_pos} ." not in lcon() of $loc," .
                          "teleporting to $loc.");
                     teleport($self,$prog,$$cmd{bad_pos},$loc);
                  } else {
                     push(@out,"#" . $$cmd{bad_pos} ." No location, sent " .
                          "home(#" .  home($$cmd{bad_pos}) . ").");
                     teleport($self,$prog,$$cmd{bad_pos},home($$cmd{bad_pos}));
                  }
               }
            }
         }
      }
   }
   if($#out > -1) {
      necho(self   => $self,
            prog   => $prog,
            source => [ join("\n",@out) ]
     );
   }
   if($$cmd{bad_pos} >= $#db) {                          # search is done
      delete @$cmd{bad_pos};
      necho(self   => $self,
            prog   => $prog,
            source => [ "**End of List***" ]
        );
      delete @$cmd{bad_pos};
   } else {
      return "RUNNING";                                     # more to do
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
 
   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   if(memorydb) {
      if(defined $$prog{nomushrun}) {
         out($prog,"#-1 \@find can not be used in the run() function");
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
            controls($$cmd{find_owner},$$cmd{find_pos}) &&
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
         if($#out > -1) {
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

   if(hasflag($self,"GOD")) {
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
}

#
# give
#    Give someone else penies and optionally handle @cost/@pay.
#
sub cmd_give
{
   my ($self,$prog) = (obj(shift),obj(shift));
   my ($apay, $cost);
 
   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   my ($obj,$amount) = meval($self,$prog,balanced_split(shift,"=",4));

   my $target = find($self,$prog,$obj) ||
      return err($self,$prog,"Give to whom?");

   hasflag(owner($target),"GUEST") &&
      return err($self,$prog,"Guests don't need that.");

   hasflag(owner($target),"EXIT") &&
      return err($self,$prog,"Exits don't need that.");

   hasflag(owner($target),"ROOM") &&
      return err($self,$prog,"Rooms don't need that.");


   if($$self{obj_id} == $$target{obj_id} && !hasflag($self,"WIZARD")) {
      return err($self,$prog,"You may not give yourself money.");
   } elsif($amount !~ /^\s*\-{0,1}(\d+)\s*$/) {
      return err($self,$prog,"That is not a valid amount.");
   } elsif($amount <= 0 && !hasflag($self,"WIZARD")) {
      return err($self,$prog,"You look through your pockets. Nope, no " .
                 pennies("negative") . ".");
   } elsif($amount > money($self) && !hasflag($self,"WIZARD")) {
      return err($self,$prog,"You don't have %s to give!",pennies($amount));
   }

   if(($apay = get($target,"APAY")) ne undef && # handle @pay/@apay
      ($cost = get($target,"COST")) ne undef) {

      if($cost !~ /^\s*(\d+)\s*$/) {
         return err($self,$prog,"Invalid \@cost set on object.");
      }

      if($amount > $cost) {                             # paid too much
          necho(self   => $self,
                prog   => $prog,
                source => [ "You get %s %s in change.",
                            trim($amount) - $cost, ($amount - $cost == 1) ? 
                               @info{"conf.money_name_singular"} :
                               @info{"conf.money_name_plural"} ]
               );
      } elsif($amount < $cost) {                           # not enough
         return err($self,$prog,"Feeling poor today?");
      }
      mushrun(self   => $self,                        # run code
              prog   => $prog,
              runas  => $target,
              invoker=> $self,
              source => 0,
              cmd    => $apay,
              );
      $amount = $cost;
   }

   give_money($self,"-$amount");
   give_money($target,"$amount");

   necho(self   => $self,
         prog   => $prog,
         source => [ "You give %s %s to %s.",
                     trim($amount),
                     ($amount== 1) ? @info{"conf.money_name_singular"} :
                                     @info{"conf.money_name_plural"},
                     name($target) ],
         target => [ $target, "%s gives you %s %s.",
                     name($self),
                     trim($amount),
                     ($amount == 1) ? @info{"conf.money_name_singular"} :
                                      @info{"conf.money_name_plural"} ]
        );

}


sub cmd_trigger
{
   my ($self,$prog) = (obj(shift),obj(shift));
   my (@wild,$last,$target,$name);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   # find where the "=" is without evaluating things.
   my ($txt,$params) = balanced_split(shift,"=",4);
 

   # where the / is without evaluating things
   my ($target,$name) = balanced_split($txt,"\/",4);

   # okay to evaluate object / attribute
   my $target = find($self,$prog,evaluate($self,$prog,$target));
   my $name = trim(evaluate($self,$prog,$name));

   return err($self,$prog,"No match.") if($target eq undef);

   my $attr = mget($target,$name) ||
      return err($self,$prog,"No such attribute.");

   if(!defined $$attr{glob} && !controls($self,$target)) {
      return err($self,$prog,"PermiSsion denied");
   }

   for my $i (balanced_split($params,',',2)) {             # split param list
      if($last eq undef) {
         $last = evaluate($self,$prog,$i);
      } else {
         push(@wild,evaluate($self,$prog,$i));
      }
   }
   push(@wild,$last) if($last ne undef);

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => $$attr{value},
           child  => 2,
           wild   => [ @wild ],
          );
}

#
# cmd_huh
#    Unknown command has been issued. Handle the echoing of VERBOSE
#    here for the unknown command.
#
sub cmd_huh
{
   my ($self,$prog,$txt) = @_;

   if(hasflag($self,"VERBOSE")) {
      necho(self   => owner($self),
            prog   => $prog,
            target => [ owner($self),
                        "%s] %s", 
                        name($self),
                        trim((($txt eq undef) ? "" : " " . $txt))
                      ]
           );
   }

#   printf("HUH: '%s' -> '%s'\n",print_var($prog));
   necho(self   => $self,
         prog   => $prog,
         source => [ "Huh? (Type \"HELP\" for help.)" ]
        );
}
                  
sub cmd_offline_huh
{ 
   my $sock = $$user{sock};
   if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
      ws_echo($sock,@info{"conf.login"});
   } else {
      printf($sock "%s\r\n",@info{"conf.login"});
   }
}


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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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
            set($self,$prog,$target,"OBJ_LOCK_DEFAULT",$$lock{lock},1);
            necho(self => $self,
                  prog => $prog,
                  source => [ "Set." ]
                 );
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

sub set_var
{
   my ($prog,$var,$value) = @_;

   $$prog{var} = {} if(!defined $$prog{var});

   @{$$prog{var}}{$var} = $value;
   return 0;
}

sub cmd_var
{
    my ($self,$prog,$txt) = @_;

    $$prog{var} = {} if !defined $$prog{var};
    if($txt =~ /^\s*\d+/) {
       necho(self   => $self,
             prog   => $prog,
             source => [ "Variables may not start with numbers\n" ],
            );
    } elsif($txt =~ /^\s*([^ ]+)\+\+\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)}++;
    } elsif($txt =~ /^\s*([^ ]+)\-\-\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)}--;
    } elsif($txt =~ /^\s*([^ ]+)\s*=\s*(.*?)\s*$/) {
       @{$$prog{var}}{evaluate($self,$prog,$1)} = evaluate($self,$prog,$2);
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
   my ($boot,$target) = (0,undef);

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission denied.");
   }
      
   my $god = hasflag($self,"GOD");
   
   $txt =~ s/^\s+|\s+$//g;

   if(defined $$switch{port}) {
      if($txt !~ /^\d+$/) {
         return err($self,$prog,"Ports numbers must be numeric.");
      }
   } else {
      $target = find_player($self,$prog,$txt) ||
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "I don't see that here." ]
                     );
   }
   
   for my $key (keys %connected) {
      my $hash = @connected{$key};

      if(!$god && hasflag(@connected{$key},"GOD") ||
         !controls($self,@connected{$key})) {
         # god can not be booted by non-god. 
         # must control the object to boot it

         # skip
      } elsif((defined $$switch{port} && $$hash{port} == $txt) ||
         (!defined $$switch{port} && name($hash) eq name($target))) {

         if(defined $$switch{port}) {
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
         $boot++;
      }
   }


   if($boot == 0) {
      if($$switch{port} && $boot == 0) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Unknown port specified." ],
              );
      } else {
          necho(self   => $self,
                prog   => $prog,
                source => [ "Unknown connected person specified." ],
               );
       }
   }
}

sub cmd_killpid
{
   my ($self,$prog,$txt) = @_;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*(\d+)\s*$/) {
      if(!defined @engine{$1}) {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "PID '%s' does not exist.", $1 ],
              );
      } elsif(hasflag(@engine{$1}->{created_by},"GOD") &&
              !hasflag($self,"GOD")) {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "Permission denied, pid $1 owned by a GOD." ],
              );
      } elsif(!controls($self,@engine{$1}->{created_by})) {
         necho(self   => $self,                           # target's room
               prog   => $prog,
               source => [ "Permission denied, you do not control pid $1." ],
              );
      } else {
         delete @engine{$1};
         necho(self   => $self,
               prog   => $prog,
               source => [ "PID '%s' has been killed", $1 ],
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

   necho(self   => $self,                           # target's room
         prog   => $prog,
         source => [ "----[ Start ]----" ],
        );

   for my $pid (keys %engine) {
      my $p = @engine{$pid};
      $$p{command} = 0 if !defined $$prog{command};
      $$p{function} = 0 if !defined $$p{function};

      if(defined $$p{stack} && ref($$p{stack}) eq "ARRAY" &&
         controls($self,$$p{created_by}) &&
         (!hasflag($$p{created_by},"GOD") || hasflag($self,"GOD"))) {
         # can only see processes they control
         # non-gods can not see god processes

         necho(self   => $self,
               prog   => $prog,
               source => [ "  PID: %s for %s [%sc/%sf]",
                              $pid,
                              obj_name($self,$$p{created_by}),
                              $$p{command},
                              $$p{function}
                         ]
              );
         for my $i (0 .. $#{$$p{stack}}) {
            my $cmd = @{$$p{stack}}[$i];
   
            necho(self   => $self,
                  prog   => $prog,
                  source => [ "    '%s%s'",
                              substr(single_line($$cmd{cmd}),0,64),
                              (length(single_line($$cmd{cmd})) > 67)?"..." : ""
                            ]
   
                  );
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
   my $obj = owner($self);
   my $count = 0;

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   my $iswiz = hasflag($self,"WIZARD");

   for my $pid (keys %engine) {                          # look at each pid
      my $program = @engine{$pid};

      # kill only your stuff but not the halt command
      if($$prog{pid} != $pid && 
         ($$obj{obj_id} == @{$$program{created_by}}{obj_id} || $iswiz)) {
         my $cmd = @{$$program{stack}}[0];
         necho(self => $self,
               prog => $prog,
               source => [ "Pid %s stopped : %s%s" ,
                           $pid,
                           substr(single_line($$cmd{cmd}),0,40),
                           (length(single_line($$cmd{cmd})) > 40) ? "..." : ""
                         ]
              );

         close_telnet($program);
         delete @engine{$pid};
         $count++;
      }
   }
   necho(self => $self,
            prog => $prog,
            source => [ "%s queue entries removed." , $count]
        );
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
      return evaluate($self,$prog,$txt) ? 1 : 0;
   }
}

sub cmd_split
{
   my ($self,$prog,$txt) = @_;
   my $max = 10;
   my @stack;
   
   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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
# find_free_dbrefs
#
#    @destroy will keep track of used dbrefs but this function will
#    populate the list on startup / reload of code.
#
sub find_free_dbrefs
{
   return if mysqldb;

   delete @free[0 .. $#free];

   for my $i (0 .. $#db) {
      push(@free,$i) if(!valid_dbref($i));
   }
}

sub cmd_player
{
   my ($self,$prog,$type) = @_;

   delete @player{keys %player};
   for(my $i=0;$i <= $#db;$i++) {
      if(valid_dbref($i) && hasflag($i,"PLAYER")) {
         @player{lc(name($i,1))} = $i;
      }
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

   if(in_run_function($prog)) {
      return out($prog,"#-1 \@DUMP can not be called from RUN function");
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
      if($type ne "CRASH" && $user ne undef) {
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
       if(valid_dbref($$cmd{dump_pos})) {
          printf($file "%s", db_object($$cmd{dump_pos}));
       }
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
         necho(self   => $self,
               prog   => $prog,
               source => [ "\@dump completed." ],
              );
         prune_dumps("dumps",@info{"conf.mudname"} . "\..*\.tdb");
      }
      return;
   } else {
      return "RUNNING";                                       # still running
   }
}

 
#
# show_stack
#    print out the stack to the console for a program
#
sub show_stack
{ 
   my ($prog,$txt) = @_;

   if($txt ne undef) {
      con("---[ start ]---- [%s]\n",$txt);
   } else {
      con("---[ start ]----\n",$txt);
   }
   for my $i (0 .. $#{$$prog{stack}}) {
      my $cmd = @{$$prog{stack}}[$i];
      con("   %3s[%s] : %s\n",
             $i,
             defined $$cmd{done} ? 1 : 0,
             substr(single_line($$cmd{cmd}),0,40)
            );
   }
   con("---[  end  ]----\n");
}

sub out
{
   my ($prog,$fmt,@args) = @_;

   if(defined $$prog{output}) {
      my $stack = $$prog{output};
      push(@$stack,sprintf($fmt,@args));
   }
   return undef;
}

sub cmd_notify
{
   my ($self,$prog,$txt,$switch)=(shift,shift,shift,shift);

   verify_switches($self,$prog,$switch,"first","all","quiet") || return;

   if(defined $$switch{all} && defined $$switch{first}) {
      return err($self,$prog,"Illegal combination of switches.");
   }

   #
   # semaphores will be triggered by setting their wait_time to 0, which
   # will cause them to be run on the next run through of the spin() loop.
   # We could execute the commands right now but this seems elegantly simple.
   #
   my $stack = $$prog{stack};
   my $current = $$prog{cmd};
   for my $i (0 .. $#$stack) {
      if($current eq $$stack[$i]) {           
         last;                             # don't run commands in the future
      } elsif(defined @{$$stack[$i]}{wait_semaphore}) {
         @{$$stack[$i]}{wait_time} = 0;
         last if(defined $$switch{first});      # notify 1, jump out of loop
      }
   }

   if(!defined $$switch{quiet}) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Notified." ],
           );
   }
}

sub cmd_drain
{
   my ($self,$prog,$txt,$switch)=(shift,shift,shift,shift);

   verify_switches($self,$prog,$switch,"quiet") || return;

   #
   # The command that contains the semaphore will be just erased and
   # marked as done. The spin() function will delete the command as soon
   # as it sees it next.
   #
   my $stack = $$prog{stack};
   my $current = $$prog{cmd};
   for my $i (0 .. $#$stack) {
      if($current eq $$stack[$i]) {           
         return;                          # don't run commands in the future
      } elsif(defined @{$$stack[$i]}{wait_semaphore}) {
         my $hash = $$stack[$i];
         delete @$hash{keys %$hash};
         $$hash{done} = 1;
      }
   }

   if(!defined $$switch{quiet}) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Notified." ],
           );
   }
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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return out($prog,"#-1 \@DOLIST can not be called from RUN function");

   verify_switches($self,$prog,$switch,"delimit","notify") || return;

   if(defined $$switch{delimit}) {                       # handle delimiter
      if($txt =~ /^\s*([^ ]+)\s*/) {
         $txt = $';                        # first word of list is delimiter
         $delim = $1;
      } else {
         return err($self,$prog,"Could not determine delimiter");
      }
   } else {
      $delim = " ";
   }

   if(!defined $$cmd{dolist_list}) {                      # initialize dolist
       my ($first,$second) = balanced_split($txt,"=",4);
       $$cmd{dolist_cmd}   = $second;
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
      delete $$prog{attr} if defined $$prog{attr};

      if(defined $$prog{cmd} && @{$$prog{cmd}}{source} == 1) {
         mushrun(self   => $self,                    # player typed in command,
                 runas  => $self,            # new environment for each command
                 source => 0,
                 cmd    => $cmds,
                 child  => 1,
                 invoker=> $self,
                );
      } else {
         mushrun(self   => $self,
                 prog   => $prog,
                 runas  => $self,
                 source => 0,
                 cmd    => $cmds,
                 child  => 1,
                );
      }
   }

   if($#{$$cmd{dolist_list}} == -1) {
      if(defined $$switch{notify}) {
         mushrun(self   => $self,
                 prog   => $prog,
                 runas  => $self,
                 source => 0,
                 cmd    => "\@notify/first/quiet",
                 child  => 2,
                );
      }
      return "DONE";
   } else {
      return "RUNNING";
   }
}

#
# good_password
#    enforce password pollicy
#
sub good_password
{
   my $txt = shift;

   if($txt !~ /^\s*.{8,999}\s*$/) {
      return "#-1 Passwords must be 8 characters or more";
   } elsif($txt !~ /[0-9]/) {
      return "#-1 Passwords must one digit [0-9]";
   } elsif($txt !~ /[A-Z]/) {
      "#-1 Passwords must contain at least one upper case character";
   } elsif($txt !~ /[a-z]/) {
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
                  source => [ "Password changed." ],
                 );
         }
      } else {                                                      # mysql
         if(one("select obj_password ".              # verify old password
                "  from object " .
                " where obj_id = ? " .
                "   and obj_password = password(?)",
                $$self{obj_id},
                $1
               )) {
            sql("update object ".                   # update to new password
                "   set obj_password = password(?) " . 
                " where obj_id = ?" ,
                $2,
                $$self{obj_id}
               );
            if(@info{rows} != 1) {
               return err($self,$prog,
                          "Internal error, unable to update password" 
                         );
            }
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

sub cmd_wait
{
   my ($self,$prog) = (obj(shift),shift);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return out($prog,"#-1 \@WAIT can not be called from RUN function");

   my $cmd = $$prog{cmd_last};

   if(!defined $$cmd{wait_time}) {
      ($$cmd{wait_time},$$cmd{wait_cmd}) = balanced_split(shift,"=",4);

      my ($obj,$time) = balanced_split($$cmd{wait_time},"/",4);

      if($time ne undef) {
         $$cmd{wait_time} = $time;
         $$cmd{wait_semaphore} = 1;

         my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
            return err($self,$prog,"I don't see that here.");

         if($$target{obj_id} != $$self{obj_id}) {
            return err($self,$prog,"Semaphores on other objects are not " .
                       "supported yet.");
         }
      }

      if(!looks_like_number(ansi_remove($$cmd{wait_time}))) {
         return err($self,$prog,"Invalid wait time provided.");
      } elsif($$cmd{wait_cmd} =~ /^\s*$/) {
         return;            # TinyMUSH actually waits, but we'll just quietly
                            # do nothing unless a reason to wait is found.
      } else {
         $$cmd{wait_time} += time();
      }
   }  elsif($$cmd{wait_time} <= time()) {
      return mushrun(self   => $self,
                     prog   => $prog,
                     source => 0,
                     child  => 1,
                     cmd    => $$cmd{wait_cmd},
                    );
   }
   $$cmd{idle} = 1;
   return "BACKGROUNDED";
}

sub cmd_sleep
{
   my ($self,$prog,$txt) = @_;

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return out($prog,"#-1 \@SLEEP can not be called from RUN function");

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
   return "DONE";
}

#
# read_atr_config
#    Read those values set on #0 into the @info variable so that they
#    are cached when using mysql.
#
sub read_atr_config
{
   my ($self,$prog) = @_;
   my %updated;

   for my $atr (lattr(0)) {
      if($atr =~ /^conf\./i) {
         my $value = get(0,$atr);
         $value = $` if($value =~ /\s*;\s*$/);
         $value = $1 if($value =~ /^\s*#(\d+)\s*$/);

         if((defined @info{lc($atr)} && @info{lc($atr)} != 0) ||
            @info{lc($atr)} == -1) {
            # skip, teenymush.conf file over-rides in db config items
            # and disabled items can't be re-enabled.
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
   my ($self,$prog,$txt,$flag) = @_;
   my ($file, $data, $name);
   my $count = 0;

   if(!hasflag($self,"WIZARD") && !$flag) {
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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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

   if(memorydb) { # escape out ":"
      my $hash = mget($target,$atr);
      $$hash{glob} =~ s/:/\\:/g if(defined $$hash{type});
   } else {
      # insert code for mysql version
   }

   for my $line (split(/\n/,get($target,$atr))) {
      $line =~ s/^\s+//;
      $out .= $line;
   }

   $out =~ s/\r|\n//g;
   set($self,$prog,$target,$atr,$out);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s",$out ],
        );
}

sub cmd_switch
{
    my ($self,$prog,@list) = (shift,shift,balanced_split(shift,',',3));
    my $switch = shift;
    my (%last, $pat,$done);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

    my ($first,$second) = (get_segment2(shift(@list),"="));
#    printf("FIRST: '%s'\n",$first);
    $first = trim(ansi_remove(evaluate($self,$prog,$first)));
    $first =~ s/[\r\n]//g;
    $first =~ tr/\x80-\xFF//d;
    unshift(@list,$second);
#    printf("FIRST: '%s'\n",$first);

    while($#list >= 0) {
       # ignore default place holder used for readability
       if($#list == 1 && @list[0] =~ /^\s*DEFAULT\s*$/) {
          shift(@list);
       }
       if($#list >= 1) {
          my $txt=ansi_remove(single_line(evaluate($self,$prog,shift(@list))));

          if(defined $$switch{regexp}) {   
             $pat = $txt;
          } else {
             $pat = glob2re($txt);
          }
          my $cmd = shift(@list);
          $cmd =~ s/^[\s\n]+//g;
          $txt =~ s/^\s+|\s+$//g;
#          printf("NEXT: '%s'\n",$txt);
          if($txt =~ /^\s*(<|>)\s*\d+\s*$/) {
             if($1 eq ">" && $first > $' || $1 eq "<" && $first < $') {
                return mushrun(self   => $self,
                               prog   => $prog,
                               source => 0,
                               child  => 1,
                               cmd    => $cmd,
                              );
             }
          } else {
             eval {                    # assume $pat could be a bad regexp
                if($first =~ /$pat/) {
                   mushrun(self   => $self,
                           prog   => $prog,
                           source => 0,
                           cmd    => $cmd,
                           child  => 1,
                           match  => { 0 => $1, 1 => $2, 2 => $3, 
                                       3 => $4, 4 => $5, 5 => $6,
                                       6 => $7, 7 => $8, 8 => $9 }
                          );
                   $done = 1;
                }
             };
             return if $done;
          }
       } else {
          @list[0] = $1 if(@list[0] =~ /^\s*{(.*)}\s*$/);
          @list[0] =~ s/\r|\n//g;
          mushrun(self   => $self,
                  prog   => $prog,
                  source => 0,
                  child  => 1,
                  cmd    => @list[0],
                 );
          return;
       }
    }
}
      

sub cmd_newpassword
{
   my ($self,$prog,$txt) = @_;

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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
         sql("update object ".
             "   set obj_password = password(?) " . 
             " where obj_id = ?" ,
             $2,
             $$player{obj_id}
            );
         if(@info{rows} != 1) {
            return err($self,$prog,"Internal error, unable to update password");
         }
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
   } elsif(defined $$prog{socket_id}) {
      return err($self,$prog,"A telnet connection is already open");
   } elsif($txt =~ /^\s*([^:]+)\s*[:| ]\s*(\d+)\s*$/) {
      my $addr = inet_aton($1) ||
         return err($self,$prog,"Invalid hostname '%s' specified.",$1);
      my $sock = IO::Socket::INET->new(Proto=>'tcp',
                                       blocking=>0,
                                       Timeout => 2) ||
         return err($self,$prog,"Could not create socket.");
      $sock->blocking(0);

      my $sockaddr = sockaddr_in($2, $addr) ||
         return err($self,$prog,"Could not resolve hostname");

      connect($sock,$sockaddr) or                     # start connect to host
      # $sock->connect($sockaddr) or                     # start connect to host
         $! == EWOULDBLOCK or $! == EINPROGRESS or         # and check status
         return err($self,$prog,"Could not open connection. $!");

      () = IO::Select->new($sock)->can_write(.2)     # see if socket is pending
          or $pending = 2;
      defined($sock->blocking(1)) ||
         return err($self,$prog,"Could not open a nonblocking connection");

      $$prog{socket_id} = $sock;

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
          sql("insert into socket " . 
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
            if(@info{rows} != 1) {
               return err($self,$prog,"Unable to insert into socket data");
            }
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
      return 1;
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "usage: \@telnet <id>=<hostname>:<port> {$txt}" ],
           );
      return 0;
   }
}


sub find_socket
{
    my ($self,$prog) = (obj(shift),shift);
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
                return @{@connected{$key}}{sock};
             }
          }
       }
    } elsif(hasflag($self,"SOCKET_INPUT") && defined $$prog{socket_id}) {
       return $$prog{socket_id};
    }
    return undef;
}

#
# send data to a connected @telnet socket. If the socket is pending,
# the socket will "pause" the @send till it times out or connects.
#
sub cmd_send
{
    my ($self,$prog,$txt) = (obj(shift),shift);
    my $sock;

    hasflag($self,"WIZARD") ||                             # wizard only
       return err($self,$prog,"Permission Denied.");

    my $sock = find_socket($self,$prog);

    if($sock eq undef) {
       return err($self,$prog,"Telnet connection needs to be opened first");
    } elsif(@{@connected{$sock}}{pending} == 2) {
       $$prog{idle} = 1;                   # socket pending, try again later
       return "RUNNING";
    } else {
       my $txt = ansi_remove(evaluate($self,$prog,shift));
       my $switch = shift;
       $txt =~ s/\r|\n//g;
       $txt =~ tr/\x80-\xFF//d;

#       printf("#SEND: '%s'\n",$txt);
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
    my ($self,$prog) = @_;

    hasflag($self,"WIZARD") ||
       return err($self,$prog,"Permission Denied.");

    my $sock = find_socket($self,$prog) ||
       return err($self,$prog,"No sockets open.");

    server_disconnect($sock);
    
    necho(self   => $self,
          prog   => $prog,
          source => [ "Socket Closed." ],
         );
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

    hasflag($self,"GUEST") &&
       return err($self,$prog,"Permission denied.");

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

       mushrun(self     => $target,
               prog     => $prog,
               runas    => $target,
               source   => 0,
               cmd      => evaluate($self,$prog,$'),
               child    => 2,
               hint     => "ALWAYS_RUN"
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
       if(memorydb) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "MySQL is not enabled. No data is cached." ]
                      );
       }
       
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
       my @out;

       for my $key (keys %flag) {
          push(@out,$key . "(" . @flag{$key}->{letter} . ")");
       }
       necho(self => $self,
             prog => $prog,
             source => [ "Flags: %s", join(', ',@out) ]
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
            $out .= "\n$$hash{hostname}$$hash{start}$$hash{port}";
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
   } elsif($txt =~ /^\s*last request\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", @info{socket_buffer} ]
           );
   } else {
       err($self,
           $prog,
           "syntax: \@list <option>\n\n" .
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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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

   necho(self      => $self,
         prog      => $prog,
         source    => [ "%s was destroyed.",$objname ],
         room      => [ $target, "%s was destroyed.",$name  ],
         all_room  => [ $target, "%s has left.",$name ]
        );
   if(!destroy_object($self,$prog,$target)) {
      necho(self    => $self,
            prog    => $prog,
            source  => [ "Internal error, object not destroyed." ],
            room    => [ $target, "%s remateralizes and was not destroyed.",
                         $name  ],
           );
   }
}

#
# cmd_toad
#    Delete a player. This cycles through the whole db, so the code will
#    search in 100 object increments.
#
sub cmd_toad
{
   my ($self,$prog,$txt) = @_;
   my $start;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*$/) {
       return err($self,$prog,"syntax: \@toad <object>");
   }

   #-----------------------------------------------------------------------#
   # initialize loop                                                       #
   #-----------------------------------------------------------------------#
   my $cmd = $$prog{cmd_last};

   if(!defined $$cmd{toad_pos}) {
      my $target = find($self,$prog,$txt) ||
         return err($self,$prog,"I don't see that here.");

      if(!hasflag($target,"PLAYER")) {
         return err($self,$prog,"Try \@destroy instead");
      }

      $$cmd{toad_pos} = 0;
      $$cmd{toad_dbref} = $$target{obj_id};
      $$cmd{toad_name} = name($target);
      $$cmd{toad_name2} = name($target,1);
      $$cmd{toad_objname} = obj_name($self,$target);
      $$cmd{toad_loc} = loc($target);

      if(hasflag($target,"CONNECTED")) {
         cmd_boot($self,$prog,"#" . $$target{obj_id});
      }
   }

   #-----------------------------------------------------------------------#
   # do 100 objects at a time                                              #
   #-----------------------------------------------------------------------#
   for($start=$$cmd{toad_pos};
       $$cmd{toad_pos} < $#db &&
       $$cmd{toad_pos} - $start < 100;
       $$cmd{toad_pos}++) {
      if(valid_dbref($$cmd{toad_pos}) &&
         $$cmd{toad_pos} != $$cmd{toad_dbref} &&
         owner_id($$cmd{toad_pos}) == $$cmd{toad_dbref}) {
         destroy_object($self,$prog,$$cmd{toad_pos});
      }
   }

   #-----------------------------------------------------------------------#
   # done?                                                                 #
   #-----------------------------------------------------------------------#
   if($$cmd{toad_pos} >= $#db) {
      if($$cmd{toad_loc} ne loc($self)) {
         necho(self       => $self,
               prog       => $prog,
               source     => [ "%s was \@toaded.",$$cmd{toad_objname} ],
               all_room   => [ $$cmd{toad_loc},
                               "%s was \@toaded.",
                               $$cmd{toad_name}
                             ],
               all_room2  => [ $$cmd{toad_dbref}, "%s has left.",
                               $$cmd{toad_name} ]
              );
      } else {
         necho(self       => $self,
               prog       => $prog,
               source     => [ "%s was \@toaded.",$$cmd{toad_objname} ],
               all_room   => [ $$cmd{toad_loc}, 
                               "%s was \@toaded.",
                               $$cmd{toad_name}
                             ],
               all_room2  => [ $$cmd{toad_dbref}, "%s has left.",
                               $$cmd{toad_name} ]
              );
      }
      delete @player{lc($$cmd{toad_name2})};
      db_delete($$cmd{toad_dbref});
   } else {
      return "RUNNING";                                      # still running
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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   if($txt =~ /^\s*([^ =]+)\s*=/s) {
      my $target = find($self,$prog,evaluate($self,$prog,$1));
      my $txt=$';

      if($target eq undef) {
         return err($self,$prog,"I don't see that here - '$target'");
      } 

      my $txt = evaluate($self,$prog,trim($txt));

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

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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

   teleport($self,$prog,$target,fetch(loc($self))) ||
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

   cmd_look($target,$prog);
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

   teleport($self,$prog,$self,$dest) ||
      return err($self,$prog,"Internal error, unable to leave that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s dropped %s.", name($container),name($self) ],
         room2  => [ $self, "%s has arrived.",name($self) ]
        );

   cmd_look($self,$prog);
}

sub cmd_take
{
   my ($self,$prog,$txt) = @_;
 
   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission Denied.");

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

   teleport($self,$prog,$target,$self) ||
      return err($self,$prog,"Internal error, unable to pick up that object");

   necho(self   => $self,
         prog   => $prog,
         room   => [ $target, "%s has arrived.",name($target) ]
        );

   cmd_look($target,$prog);
}

sub cmd_name
{
   my ($self,$prog,$txt) = @_;

   printf("NAME: '%s'\n",$txt);
   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*([^=]+?)\s*=\s*(.+?)\s*$/) {
      my $target = find($self,$prog,evaluate($self,$prog,$1)) ||
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

      if(hasflag($target,"PLAYER") && inuse_player_name($2,$self)) {
         return err($self,$prog,"That name is already in use");
      } elsif($name =~ /^\s*(\#|\*)/) {
         return err($self,$prog,"Names may not start with * or #");
      } elsif(length($name) > 50) {
         return err($self,$prog,"Names may only be 50 charaters");
      }

      if(memorydb) {
         if(hasflag($target,"PLAYER")) {
            delete @player{lc(name($target,1))};
            @player{$name} = $$target{obj_id};
         }
         db_set($target,"obj_name",$name);
         db_set($target,"obj_cname",$cname);
      } else {

         sql("update object " .
             "   set obj_name = ?, " .
             "       obj_cname = ? " .
             " where obj_id = ?",
             $name,
             $cname,
             $$target{obj_id},
             );
    
         set_cache($target,"obj_name");

         if(@info{rows} != 1) {
            err($self,$prog,"Internal error, name not updated.");
         } else {
            my_commit;
         }
      }

      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ],
           );
   } else {
      err($self,$prog,"syntax: \@name <object> = <new_name>");
   }
}

sub cmd_enter
{
   my ($self,$prog,$txt) = @_;

   hasflag($self,"GUEST") &&
     return err($self,$prog,"Permission denied.");
   
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

   teleport($self,$prog,$self,$target) ||
      return err($self,$prog,"Internal error, unable to pick up that object");

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         source => [ "You have entered %s.",name($target) ],
         room   => [ $self, "%s entered %s.",name($self),name($target)],
         room2  => [ $self, "%s has arrived.", name($self) ]
        );

   cmd_look($self,$prog);
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

   if($obj eq undef) {
      return err($self,$prog,"I don't see that here.");
   } elsif(hasflag($obj,"EXIT") || hasflag($obj,"ROOM")) {
      return err($self,$prog,"You may only whisper to objects or players");
   } elsif(loc($obj) != loc($self)) {
      return err($self,$prog,"%s is not here.",name($obj));
   } elsif($msg =~ /^\s*:/) {
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
# cmd_whisper
#    person to person communication in the same room.
#
sub cmd_whisper
{
   my ($self,$prog,$txt) = @_;

   if($txt =~ /^\s*([^ ]+)\s*=/) {                           # standard whisper
      whisper($self,$prog,$1,$');
   } else {
      my $target = get($self,"OBJ_LAST_WHISPER");          # no target whisper
      return whisper($self,$prog,$target,$txt) if ($target ne undef);

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

   !controls($self,$target) &&
      return err($self,$prog,"Permission denied.");

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
   my ($self,$prog,$txt) = (obj(shift),shift);
   my ($exit ,$dest);

   my $txt = evaluate($self,$prog,shift);
   $txt =~ s/^\s+|\s+$//g;

   my $loc = loc($self);

   if($txt =~ /^home$/i) {
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
   teleport($self,$prog,$self,$dest) ||
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

   $location = find($self,$prog,evaluate($self,$prog,$location)) ||
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

   teleport($self,$prog,$target,$location) ||
      return err($self,$prog,"Unable to teleport to that location");

   necho(self   => $self,
         prog   => $prog,
         all_room   => [ $target, "%s has arrived.",name($target) ]
        );


   cmd_look($target,$prog);
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
      con("%s\n%s\n%s\n","#" x 65,"-" x 65,"#" x 65);
      con("\033[2J");    #clear the screen
      con("\033[0;0H");  #jump to 0,0
      printf("%s\n%s\n%s\n","#" x 65,"-" x 65,"#" x 65);
      printf("\033[2J");    #clear the screen
      printf("\033[0;0H");  #jump to 0,0
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
      my_commit;
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
         ws_disconnect(@c{$sock}) if(defined @c{$sock});
      } else {
         printf($sock "%s",@info{"conf.logoff"});
         server_disconnect($sock);
      }
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
      cmd_read($self,$prog,"help",1) if(scalar keys %help == 0);

      if(defined @help{lc(trim($txt))}) {
         $help = @help{lc(trim($txt))};
      } elsif(defined @help{"@" . lc(trim($txt))}) {
         $help = @help{"@" . lc(trim($txt))};
      } elsif(defined @help{lc(trim($txt)). "()"}) {
         $help = @help{lc(trim($txt)) . "()"};
      } elsif($txt =~ /\(\s*\)\s*$/ && defined @help{lc(trim($`))}) {
         $help = @help{lc(trim($`))};
      }
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
              cmd    => $1,
              child  => 1,
             );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $help  ]
           );
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

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission denied.");
   } elsif(quota_left($self) <= 0) {
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

   my $cur = get($self,"obj_quota"); 
   db_set($self,"obj_quota",$cur - 1);

   my_commit if mysqldb;
}

sub cmd_link
{
   my ($self,$prog,$txt) = @_;
   my ($name,$target,$destination);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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
   my ($loc,$room_name,$room,$in,$out,$cost,$quota);
     
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

   $quota++;
   $quota++ if($in ne undef);
   $quota++ if($in ne out);

   if(quota_left($self) < $quota) {
      return err($self,$prog,"You need a quota of $quota or better to " .
                 "complete this \@dig"
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


   $loc = loc($self) ||
      return err($self,$prog,"Unable to determine your location");

   if($out ne undef) {
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

   my $cur = get($self,"obj_quota"); 
   db_set($self,"obj_quota",$cur - $quota);

   my_commit if(mysqldb);
}

sub cmd_open
{
   my ($self,$prog,$txt) = @_;
   my ($exit,$destination,$dest);
  
   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

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

   my $cur = get($self,"obj_quota"); 
   db_set($self,"obj_quota",$cur - 1);

   necho(self   => $self,
         prog   => $prog,
         source => [ "Exit created as %s(#%sE)",$exit,$dbref ],
        );

   my_commit if(mysqldb);
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
          $$self{obj_id} = @player{lc($name)};
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
 
   if($txt =~ /^\s*"\s*([^"]+)\s*"\s+([^ ]+)\s*$/ ||    #parse player password
      $txt =~ /^\s*([^ ]+)\s+([^ ]+)\s*$/ ||            #parse player password
      $txt =~ /^\s*"\s*([^"]+)\s*"\s*$/ ||
      $txt =~ /^\s*([^ ]+)\s*$/) {
      my ($username,$pass) = ($1,$2);

      # --- Valid User ------------------------------------------------------#

      if(invalid_player($self,$username,$pass)) {
         if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
            ws_echo($sock,"Either that player does not exist, or has a different password.\n");
         } else {
            printf($sock "Either that player does not exist, or has a different password.\n");
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
         @{@connected{$sock}}{connect} = time();
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
   
         my_commit;
      }

      # --- Provide users visual feedback / MOTD --------------------------#

      necho(self   => $user,                 # show message of the day file
            prog   => prog($user,$user),
            source => [ "%s\n", motd() ]
           );

      cmd_mail($user,prog($user,$user),"short");

      if(defined @info{"conf.paycheck"} && @info{"conf.paycheck"} > 0) {
         if(ts_date(lasttime($user)) ne ts_date()) {
            give_money($user,@info{"conf.paycheck"});
         }
      }

      necho(self   => $user,
            prog   => prog($user,$user),
            source => [ "\n" ]
           );

      cmd_look($user,prog($user,$user));                    # show room

      con("    %s@%s\n",name($user),$$user{hostname});


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
               mushrun(self    => $obj,                 # handle aconnect
                       runas   => $obj,
                       invoker => $self,
                       source  => 0,
                       cmd     => $atr
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

   if(hasflag($self,"GUEST")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ]
           );
   } elsif(!defined @connected{$$self{sock}}) {
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


#
# reconstitute
#    Take the an attribute value and put it back together so that it resembles
#    what was originally entered in + formating.
#
sub reconstitute
{
   my ($name,$type,$pattern,$value,$flag,$switch) = @_;

   $value =~ s/\r|\n//g;
#   printf("###GOT HERE###\n");
#   if($type eq undef && defined $$switch{command}) {
#      printf("###GOT HERE 2###\n");
#      return;
#   } elsif($type eq undef && $value !~ /^\s*\@/) {
#      if($flag eq undef) {
#         printf("###GOT HERE 3###\n");
#         return color("h",uc($name)) . ": $value" if($type eq undef);
#      } else {
#         printf("###GOT HERE 4###\n");
#         return color("h",uc($name)) . "[$flag]: $value" if($type eq undef);
#      }
#   }

   if($type eq 0) {
      $type = undef;
   } elsif($type eq 1) {                       # memorydb / mysql don't agree on
      $type = "\$";                               # how the type is defined
   } elsif($type eq 2) {
      $type = "^";
   } elsif($type eq 3) {
      $type = "!";
   }

   # convert single line unreadable mushcode into hopefully readable
   # multiple line code

   if(defined $$switch{command}) {
      $value = undef;
   } elsif(!$$switch{raw} &&
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

   return color("h",uc($name)) .
          (($flag ne undef) ? "[$flag]: " : ": ") .
          (($type ne undef) ? "$type$pattern:$value" : $value);
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

#
# viewable
#    Determine if an attribute should be viewable or not. Providing a
#    pattern will show more attributes.
#
sub viewable
{
   my ($obj,$name,$pat) = @_;

   if($$obj{obj_id} == 0 && $pat eq undef && $name =~ /^conf./i) {
      return 0;                   # hide conf. attrs on #0 without a pattern
   } elsif($name eq "description") {
      return ($pat ne undef) ? 1 : 0;
   } elsif($name eq "obj_lastsite") {
      return 1;
   } elsif($name eq "obj_created_by" && hasflag($obj,"PLAYER")) {
      return 1;
   } elsif($name !~ /^obj/) {
      return 1;
   } elsif($pat ne undef && 
           $name =~ /^obj_(last|last_page|created_date|last_whisper)$/) {
      return 1;
   } else {
      return 0;
   }
}

sub list_attr
{
   my ($obj,$pattern,$switch) = @_;
   my (@out,$pat,$keys);

   $pat = glob2re($pattern) if($pattern ne undef);

   if(memorydb) {
      for my $name (lattr($obj)) {
         my $short = $name;
         $short =~ s/^obj_//;
         if(viewable($obj,$name,$pat) && ($pat eq undef || $short =~ /$pat/i)) {
            my $attr = mget($obj,$name);

            if($name eq "obj_lastsite") {
               push(@out,reconstitute($short,"","",short_hn(lastsite($obj))));
            } elsif($name eq "obj_created_by") {
               push(@out,reconstitute("first","","",short_hn($$attr{value})));
            } else {
               push(@out,reconstitute($short,
                                      $$attr{type},
                                      $$attr{glob},
                                      $$attr{value},
                                      list_attr_flags($attr),
                                      $switch
                                     )
                );
            }
         }
      }
   } else {
      for my $hash (@{sql(
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
                                   $$hash{atr_flag},
                                   $switch
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

   verify_switches($self,$prog,$switch,"raw","command") || return;

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

   if(hasflag($target,"ROOM") && !($perm || $$target{obj_id} == loc($self))) {
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "%s is owned by %s.",
                               name($target),
                               name(owner($target))],
                  );
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

   if($perm) {
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
   }

   $out .= "\n" . color("h","Created") . ": " . firsttime($target);
   if(hasflag($target,"PLAYER")) {
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


   if($perm || $$target{obj_id} == loc($self)) {
      for my $obj (lcon($target)) {
        push(@content,obj_name($self,$obj));
      }

      if($#content > -1) {
         $out .= "\n" . color("h","Contents") . ":\n" . join("\n",@content);
      }
   }

   if(hasflag($target,"EXIT")) {

      my $src = loc_obj($target);

      if($src eq undef) {
         $out .= "\nSource: N/A";
      } else {
         $out .= "\nSource: " . obj_name($self,$src);
      }

      my $dest = dest($target);

      if($dest eq undef) {
         $out .= "\nDestination: *UNLINKED*";
      } else {
         $out .= "\nDestination: " . obj_name($self,$dest);
      }
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
   my ($flag,$desc,$target,@exit,@con,$out,$name,$attr);
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
      $attr = get($target,"CONFORMAT") if($$prog{hint} ne "WEB");

      for my $obj (lcon($target)) { 
         if(!hasflag($obj,"DARK") &&
            ((hasflag($obj,"PLAYER") && hasflag($obj,"CONNECTED") ||
            !hasflag($obj,"PLAYER"))) &&
            $$obj{obj_id} ne $$self{obj_id}) {

            if(!defined @db[$$obj{obj_id}]) {          # corrupt list, fix
               db_remove_list($target,"obj_content",$$obj{obj_id});
            } elsif($attr ne undef) {
               push(@con,"#" . $$obj{obj_id});
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

      if($attr ne undef) {
         my $prev = get_digit_variables($prog);              # save %0 .. %9
         set_digit_variables($self,$prog,"",join(' ',@con)); # update to new
         $out .= "\n" . evaluate($target,$prog,$attr);
         set_digit_variables($self,$prog,"",$prev);        # restore %0 .. %9
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
      for my $hash (@{sql(
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
                     invoker=> $self,
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
   my $pose = cf_convert(evaluate($self,$prog,$txt));

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s%s%s",name($self),$space,$pose ],
         room   => [ $self, "%s%s%s",name($self),$space,$pose ],
        );
}

#
# cmd_set
#    Set flags on objects or attributes. Setting attributes is no longer
#    supported, use &attribute object = value synax.
#
sub cmd_set
{
   my ($self,$prog) = (obj(shift),obj(shift));

   return err($self,$prog,"Permission denied") if hasflag($self,"GUEST");

   # find object / value
   my ($obj,$value) = balanced_split(shift,"=",4);

   # find attr name if provided
   my ($name,$attr) = balanced_split($obj,"\/",4);

   my $target = find($self,$prog,evaluate($self,$prog,$name)) || # find target
      return err($self,$prog,"I don't see that here.");

   !controls($self,$target) &&
      return err($self,$prog,"Permission denied");

   if($attr ne undef) {                                          # attr flag
       $attr = evaluate($self,$prog,$attr);

       if(!isatrflag($value)) {
          return err($self,$prog,"Invalid attribute flag");
       } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s", set_atr_flag($target,$attr,$value) ]
              );
       }
   } else {                                                  # standard flag
      necho(self   => $self,
            prog   => $prog,
            source => [ set_flag($self,$prog,$target,$value) ]
           );
   }
}

#
# cmd_set2
#    Set a user defined attribute.
#
sub cmd_set2
{
   my ($self,$prog) = (obj(shift),obj(shift));
   my ($obj,$attr);

   return err($self,$prog,"Permission denied") if hasflag($self,"GUEST");

   my ($txt,$value) = balanced_split(shift,"=",4);
   my $flag = shift;

   if(evaluate($self,$prog,$txt) =~ /^\s*([^ ]+)\s*/) {   # get attribute name
      ($attr,$obj) = ($1,$');        # never evaluate value if from user input
   } else {
      return err($self,$prog,"Unable to parse &attribute command");
   }

   my $target = find($self,$prog,$obj) || # find target
      return err($self,$prog,"I don't see that here.");

#   necho(self   => $self,
#         prog   => $prog,
#         source => [ "OBJ: '%s'", $obj ],
#        );
   

   if(!controls($self,$target)) {                                    # nope
      return err($self,$prog,"Permission denied");
   } elsif(reserved($attr) && !$flag) {                     # don't set that!
      return err($self,$prog,"Thats not a good name for an attribute.");
   } else {
      if(@{$$prog{cmd}}{source} == 0) {
         set($self,$prog,$target,$attr,trim(evaluate($self,$prog,$value)));
      } else {
         set($self,$prog,$target,$attr,trim($value));
      }

#      necho(self   => $self,
#            prog   => $prog,
#            source => [ "Set." ],
#           );
   }
}

sub myisnum
{
   my $num = shift;

   if($num =~ /^\s*-?(\d+)\s*$/ && substr($1,0,1) ne "0") {
      return 1;
   } elsif($num =~ /^\s*-?(\d+)\.\d+\s*$/ && substr($1,1,1) ne "0") {
      return 1;
   } else {
      return 0;
   }
}

sub cf_convert
{
   my $txt = shift;
   my $out;

   while($txt =~ /(\-{0,1})(\d+)(\.?)(\d*)\s*(F|C)/ && myisnum("$1$2$3$4")) {
       $out .= $`;
       $txt = $';
      if($5 eq "F") {
         my $value = sprintf("%s%s%s%s%s (%.1fC)",
            $1,$2,$3,$4,$5,("$1$2$3$4" - 32) * .5556);
         $value =~ s/\.0//g;
         $out .= $value;
      } else {
         my $value = sprintf("%s%s%s%s%s (%.1fF)",
            $1,$2,$3,$4,$5,"$1$2$3$4" * 1.8 + 32);
         $value =~ s/\.0$//g;
         $out .= $value;
      }
   }

   return $out . $txt;
}

#
# cmd_say
#    Say something outloud to anyone in the room the player is in.
#
sub cmd_say
{
   my ($self,$prog,$txt,$switch) = @_;
   my $say;

   verify_switches($self,$prog,$switch,"noeval") || return;

   if(defined $$switch{noeval}) {
      $say = $txt;
   } else {
      $say = cf_convert(evaluate($self,$prog,$txt));
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "You say, \"%s\"",$say ],
         room   => [ $self, "%s says, \"%s\"",name($self),$say ],
        );
}

sub get_source_checksums
{
    my $src = shift;
    my (%data, $file,$pos);
    my $ln = 0;

    open($file,"teenymush.pl") ||
       die("Unable to read teenymush.pl");
    
    for my $line (<$file>) {
       $ln++;
       if($_ =~ /ALWAYS_LOAD/ || $_ !~ /#!#/) { 
          if($line =~ /^sub\s+([^ \n\r]+)\s*$/) {
             $pos = $1;
             @data{$pos} = { chk => Digest::MD5->new,
                           };
             @{@data{$pos}}{chk}->add($line);
             @{@data{$pos}}{src} .= qq[#line 0 "$pos"\n] . $line if $src;
             @{@data{$pos}}{ln} .= $ln;
          } elsif($pos ne undef && $line !~ /^\s*$/) {
             @{@data{$pos}}{chk}->add($line);
             @{@data{$pos}}{src} .= $line if $src;
             
             # end of function
             if($line =~ /^}\s*$/) {
                @{@data{$pos}}{chk} = @{@data{$pos}}{chk}->hexdigest;
                $pos = undef;
             }
          } elsif($pos ne undef) {
             @{@data{$pos}}{src} .= "\n";
          }
       }
    }
    close($file);

    for my $pos (keys %data) {
       if(@{@data{$pos}}{chk} =~ /^Digest::MD5=SCALAR\((.*)\)$/) {
          con("WARNING: Didn't find end to $pos -> '%s'\n",@{@data{$pos}}{chk});
       }
    }
    return \%data;
}

sub reload_code
{
   my ($self,$prog) = @_;
   my $count = 0;
   my $prev = @info{source_prev};
   my $curr = get_source_checksums(1);

   if(!defined @info{reload_init}) {
      @info{reload_init} = 1;
   } else {
      @info{reload_init} = 0;
   }


   for my $key (sort keys %$curr) {
#      if(@{$$curr{$key}}{src} =~ /^#line (\d+)/) {
#         printf("$key -> '%s'\n",$1);
#      }
      if(@{$$prev{$key}}{chk} ne @{$$curr{$key}}{chk} || @info{reload_init}) {
         $count++;
         con("Reloading: %-40s",$key);
#         con("    before: '%s'\n",@{$$prev{$key}}{chk});
#         con("    after:  '%s'\n",@{$$curr{$key}}{chk});

         eval(@{$$curr{$key}}{src});

         if($@) {
            con("*FAILED*\n%s\n",renumber_code($@));
            @{$$curr{$key}}{chk} = -1;
            if($self ne undef) {
               necho(self   => $self,
                     prog   => $prog,
                     source => [ "Reloading %-40s *FAILED*", $key ]
                    );
            }
         } else {
            con("Successful\n");
            if($self ne undef) {
               necho(self   => $self,
                     prog   => $prog,
                     source => [ "Reloading %-40s Success", $key ]
                    );
            }
         }
      }
      @{$$curr{$key}}{src} = undef;
   }

   @info{source_prev} = $curr;

   load_modules();
   initialize_functions();
   initialize_commands();
   initialize_ansi();
   initialize_flags();
   find_free_dbrefs();

   return $count;
}

#
# cmd_reload_code
#    Let the code be reloaded from within the server. This should not be
#    disabled, so ignore the conf option unless its set to -1.
#
sub cmd_reload_code
{
   my ($self,$prog,$txt) = @_;
   my $count = 0;

   if(!hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(@info{"conf.md5"} == -1) {
      return err($self,$prog,"#-1 DISABLED");
   }

   $count = reload_code($self,$prog);

   if($count == 0) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "No code to load, no changes made." ]
           );
   } else {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s re-loads %d subrountines.\n",name($self),$count ]
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
      return "*" . substr($addr,length($addr) * .3);
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
            if(length(loc($hash)) > length($max) + 1) {
               $max = length(loc($hash)) + 1;
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


sub sweep_obj
{
   my ($self,$obj,$out) = @_;
   my @list;

   for my $obj (lcon($obj)) {
      delete @list[0 .. $#list];
      push(@list,"listening") if(hasflag($obj,"LISTENER"));
      push(@list,"commands") if(!hasflag($obj,"NO_COMMAND"));
      push(@list,"player") if(hasflag($obj,"PLAYER"));
      push(@list,"connected") if(hasflag($obj,"CONNECTED"));

      if($#list >= 0) {
         push(@$out,"  " . obj_name($self,$obj) . " is listening. [" .
            join(" ",@list) . "]");
      }
   }
}

sub cmd_sweep
{
   my ($self,$prog) = @_;
   my @out;

   push(@out,"Sweeping location...");
   sweep_obj($self,loc($self),\@out);
   push(@out,"Sweeping inventory...");
   sweep_obj($self,$self,\@out);
   push(@out,"Sweep Complete.");
   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", join("\n",@out) ]
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
    return atr_hasflag(shift,shift,"CASE");
}

sub atr_hasflag
{
   my ($obj,$atr,$flag) = (obj(shift),shift,shift);

   if(ref($obj) ne "HASH" || !defined $$obj{obj_id} || !valid_dbref($obj)) {
     return undef;
   } elsif(memorydb) {
      my $attr = mget($obj,$atr);
      if($attr eq undef || 
         !defined $$attr{flag} || 
         !defined $$attr{flag}->{lc($flag)}) {
         return 0;
      } else {
         return 1;
      }
   } elsif(!incache_atrflag($obj,$atr,uc($flag))) {
      my $val = one_val("select count(*) value " .
                        "  from attribute atr, " .
                        "       flag flg, " .
                        "       flag_definition fde " .
                        " where atr.obj_id = flg.obj_id ".
                        "   and fde.fde_flag_id = flg.fde_flag_id ".
                        "   and fde_name = ? ".
                        "   and fde_type = 2 ".
                        "   and atr_name = ? " .
                        "   and atr.atr_id = flg.atr_id " .
                        "   and atr.obj_id = ? ",
                        uc($flag),
                        $atr,
                        $$obj{obj_id}
                       );
      set_cache_atrflag($obj,$atr,$flag,$val);
   }
   return cache_atrflag($obj,$atr,$flag);
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
                              atr_name   => $name,
                              atr_owner  => $$obj{obj_id}
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
                         atr_name   => $$atr{atr_name},
                         atr_owner  => $$obj{obj_id}
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
       for my $obj (@{sql(
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
       for my $obj (@{sql("select con.obj_id " .
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

   if($owner eq undef) {
      return 0;
   } elsif(memorydb) {
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
         for my $key (sort {@flag{uc($a)}->{ord} <=> @flag{uc($b)}->{ord}} 
                      keys %$hash) {
            push(@list,$flag ? uc($key) : flag_letter($key));
         }
         if(defined $$hash{player} && defined @connected_user{$$obj{obj_id}}) {
            push(@list,$flag ? "CONNECTED" : 'c');
         }
         return join($flag ? ' ' : '',@list);
      }
   } elsif(!incache($obj,"FLAG_LIST_$flag")) {
      my (@list,$array);
      for my $hash (@{sql("select * from ( " .
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
         my $owner = get($obj,"obj_owner");
         return obj($owner);
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
   my ($target,$name) = (obj(shift),uc(shift));
   my $val;

   if($name eq "CONNECTED") {                  # not in db, no need to cache
      return (defined @connected_user{$$target{obj_id}}) ? 1 : 0;
   } elsif(!valid_dbref($target)) {
      return 0;
   } elsif(memorydb) {
      $target = owner($target) if($name eq "WIZARD" || $name eq "GOD");

      my $attr = mget($target,"obj_flag");

      if(!defined $$attr{value}) {                        # no flags at all
         return 0;
      }

      my $flag = $$attr{value};

      if($name eq "WIZARD") {
         if(defined $$flag{wizard}||defined $$flag{god}) {
            return 1;
         } else {
            return 0;
         }
      } elsif(!defined $$flag{lc($name)}) {
         return 0;
      } else {
         return 1;
      }
   } elsif(!incache($target,"FLAG_$name")) {
      if($name eq "WIZARD") {
         my $owner = owner_id($target);
         $val = one_val("select if(count(*) > 0,1,0) value " .  
                            "  from flag flg, flag_definition fde " .  
                            " where flg.fde_flag_id = fde.fde_flag_id " .
                            "   and atr_id is null ".
                            "   and fde_type = 1 " .
                            "   and obj_id = ? " .
                            "   and (fde_name = ? or fde_name = 'GOD')",
                            $owner,
                            $name);
         # let owner cache object know its value was used for this object
         $cache{$owner}->{FLAG_DEPENDANCY}->{$$target{obj_id}} = 1;
      } else {
         $val = one_val("select if(count(*) > 0,1,0) value " .
                            "  from flag flg, flag_definition fde " .
                            " where flg.fde_flag_id = fde.fde_flag_id " .
                            "   and atr_id is null ".
                            "   and fde_type = 1 " .
                            "   and obj_id = ? " .
                            "   and fde_name = ? ",
                            $$target{obj_id},
                            $name);
      }
      set_cache($target,"FLAG_$name",$val);
   }
   return cache($target,"FLAG_$name");
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
      my $home = get($obj,"obj_home");
 
      if(valid_dbref($home)) {                           # use object's home
         return $home;
      } elsif(valid_dbref(@info{"conf.starting_room"}) &&
              hasflag(@info{"conf.starting_room"},"ROOM")) {
                                                         # use starting_room
         db_set($obj,"obj_home",@info{"conf.starting_room"});
         return @info{"conf.starting_room"};
      } else {                             # default to first availible room
         my $first = first_room();
         db_set($obj,"obj_home",$first);
         return $first;
      }
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
   # foo

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
   my $data = shift;

   if(ref($txt) eq "HASH") {                           # already inited txt?
      $data = $txt;
   } else {
      $data = ansi_init($txt);
   }

   if($#{$$data{ch}} == -1) {                                       # empty
      return 0;
   } elsif(@{$$data{ch}}[-1] eq undef) {               # last char pos empty?
      return $#{$$data{ch}};
   } else {
      return $#{$$data{ch}} + 1;                        # last char populated
   }
}

#
# ansi_post_match
#    Match up $1 .. $9 with the original string.
#
sub ansi_post_match
{
   my ($data,$pat,@arg) = @_;
   my ($pos,$wild,@wildcard) = (0,0);

   while($pat =~ /(\*|\?)/ && $pos < 10) {
      $pos += length($`) if($` ne undef);
      push(@wildcard,ansi_substr($data,$pos,length(@arg[$wild])));
      $pos += length(@arg[$wild]);
      $pat = $';
      $wild++;
   }

   if($#wildcard > 8) {
      delete @wildcard[ 9 .. $#wildcard];
   } elsif($#wildcard < 8) {
      for my $i (($#wildcard+1) .. 8) {
         push(@wildcard,undef);
      }
   }
   return @wildcard
}


#
# ansi_match
#  
#   Match a string with a glob pattern and return the result containing
#   escape sequences. Since string matching can't be accurately done with
#   escape codes in them the following is done:
#
#      1. Perform a match after removing all escape sequences.
#      2. Pull the glob pattern apart to seperate wild cards
#         from non-wildcards.
#      3. Use the results from the match without escape sequences
#          to determine how to tear apart the original string
#         containing the escape sequences. This will allow the code
#         to return string segments with any escape sequences without
#         having to write a full pattern match algorithm.
#
sub ansi_match
{  
   my ($txt,$pattern) = @_;
   
   my $pat = glob2re($pattern);                    # convert pat to regexp
   my $str = ansi_init($txt);
   my $non = ansi_remove($txt);
   
   if($non =~ /$pat/) {                                          # matched
      return ansi_post_match($str,$pattern,$1,$2,$3,$4,$5,$6,$7,$8,$9);
   } else {
      return ();                                                # no match
   }
}

sub color
{
   my ($codes,$txt) = @_;
   my $pre;
   #
   # conversion table for letters to numbers used in escape codes as defined
   # by TinyMUSH, or maybe TinyMUX.
   #
   my %ansi = (
      x => 30, X => 40, r => 31, R => 41, g => 32, G => 42, y => 33, Y => 43,
      b => 34, B => 44, m => 35, M => 45, c => 36, C => 46, w => 37, W => 47,
      u => 4,  i => 7, h => 1,  f => 5, n => 0
   );


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
sub initialize_flags
{
   delete @flag{keys %flag};

   @flag{ANYONE}       ={ letter => "+",                   type => 1, ord=>99 };
   @flag{GOD}          ={ letter => "G", perm => "GOD",    type => 1, ord=>5  };
   @flag{WIZARD}       ={ letter => "W", perm => "GOD",    type => 1, ord=>6  };
   @flag{PLAYER}       ={ letter => "P", perm => "GOD",    type => 1, ord=>1  };
   @flag{ROOM}         ={ letter => "R", perm => "GOD",    type => 1, ord=>2  };
   @flag{EXIT}         ={ letter => "e", perm => "GOD",    type => 1, ord=>3  };
   @flag{OBJECT}       ={ letter => "o", perm => "GOD",    type => 1, ord=>4  };
   @flag{LISTENER}     ={ letter => "M", perm => "!GUEST", type => 1, ord=>7  };
   @flag{SOCKET_PUPPET}={ letter => "S", perm => "WIZARD", type => 1, ord=>8  };
   @flag{PUPPET}       ={ letter => "p", perm => "!GUEST", type => 1, ord=>9  };
   @flag{GUEST}        ={ letter => "g", perm => "WIZARD", type => 1, ord=>10 };
   @flag{SOCKET_INPUT} ={ letter => "I", perm => "WIZARD", type => 1, ord=>11 };
   @flag{DARK}         ={ letter => "D", perm => "!GUEST", type => 1, ord=>12 };
   @flag{CASE}         ={ letter => "C", perm => "!GUEST", type => 2, ord=>13 };
   @flag{NOSPOOF}      ={ letter => "N", perm => "!GUEST", type => 1, ord=>14 };
   @flag{VERBOSE}      ={ letter => "v", perm => "!GUEST", type => 1, ord=>15 };
   @flag{MONITOR}      ={ letter => "M", perm => "WIZARD", type => 1, ord=>16 };
   @flag{SQL}          ={ letter => "Q", perm => "WIZARD", type => 1, ord=>17 };
   @flag{ABODE}        ={ letter => "A", perm => "!GUEST", type => 1, ord=>18 };
   @flag{LINK_OK}      ={ letter => "L", perm => "!GUEST", type => 1, ord=>19 };
   @flag{ENTER_OK}     ={ letter => "E", perm => "!GUEST", type => 1, ord=>20 };
   @flag{VISUAL}       ={ letter => "V", perm => "!GUEST", type => 3, ord=>21 };
   @flag{ANSI}         ={ letter => "X", perm => "!GUEST", type => 1, ord=>22 };
   @flag{LOG}          ={ letter => "l", perm => "WIZARD", type => 1, ord=>23 };
   @flag{NO_COMMAND}   ={ letter => "n", perm => "!GUEST", type => 1, ord=>24 };
   @flag{GOING}        ={ letter => "g", perm => "GOD",    type => 1, ord=>25 };
   @flag{IMPORTED}     ={ letter => "I", perm => "GOD",    type => 1, ord=>26 };
}

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
#    WARNING: If this function is used for mysql, then the code assumes
#             that the returned data will never be modified.
#
sub mget
{
   my ($obj,$attr) = (obj(shift),shift);
   my $data;

   # handle if object exists

   if(memorydb) {
      if(defined @info{backup_mode} && @info{backup_mode}) {
         if(defined @deleted{$$obj{obj_id}}) {             # obj was deleted
            return undef;
         } elsif(defined @delta[$$obj{obj_id}]) {   # obj changed during backup
            $data = @delta[$$obj{obj_id}];
         } elsif(defined @db[$$obj{obj_id}]) {                # in actual db
            $data = @db[$$obj{obj_id}];
         } else {                                        # obj doesn't exist
            return undef;
         }
      } elsif(defined @db[$$obj{obj_id}]) {         # non-backup mode object
         $data = @db[$$obj{obj_id}];
      } else {
         return undef;                                   # obj doesn't exist
      }
   
      # handle if attribute exits on object
      if(!defined $$data{lc($attr)}) {           # check if attribute exists
         return undef;                                                # nope
      } else {
         return $$data{lc($attr)};                                  # exists
      }
   } else {                         # emulate how memorydb works in mysql
      my $hash = one("select atr_name name, " .
                     "      atr_value value,  " .
                     "      atr_pattern_type type," .
                     "      atr_pattern glob, ".
                     "      atr_regexp regexp" .
                     "  from attribute ".
                     " where atr_name = ? " .
                     "   and obj_id = ? ",
                     lc($attr),
                     $$obj{obj_id}
                    ) ||
         return undef;
      delete $$hash{regexp} if $$hash{regex} eq undef;
      delete $$hash{glob} if $$hash{glob} eq undef;
      delete $$hash{type} if $$hash{type} eq undef;

      if($$hash{type} eq undef) {
         delete @$hash{type};
      } elsif($$hash{type} == 1) {
         $$hash{type} = "\$";                     # how the type is defined
      } elsif($$hash{type} == 2) {
         $$hash{type} = "^";
      } elsif($$hash{type} == 3) {
         $$hash{type} = "!";
      }
      return $hash;
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
   my $obj = obj(shift);
  
   if(defined @info{backup_mode} && @info{backup_mode}) {  # in backup mode
      delete @delta[$$obj{obj_id}] if(defined @delta[$$obj{obj_id}]);
      @deleted{$$obj{obj_id}} = 1;
   } elsif(defined @db[$$obj{obj_id}]) {             # non-backup mode delete
      delete @db[$$obj{obj_id}];
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
      return shift(@free);
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
      return @flag{uc($txt)}->{letter};
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

   if(defined @flag{lc($txt)} && 
      (@flag{uc($txt)}->{type} == 1 ||
      @flag{uc($txt)}->{type} == 3)) {
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

   if(defined @flag{uc($txt)} && 
      (@flag{uc($txt)}->{type} == 2 ||
      @flag{uc($txt)}->{type} == 3)) {
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

   if(defined $$attr{glob}) {
      my $pat = $$attr{glob};
      $pat =~ s/:/\\:/g if($$attr{glob} =~ /:/);  # escape out :'s in pattern
      $txt = "$$attr{type}$pat:$$attr{value}";
   } else {
      $txt = $$attr{value};
   }

   if(defined $$attr{flag} && ref($$attr{flag}) eq "HASH") {
      $flag = lc(join(',',keys %{$$attr{flag}}));
   }


   # so, the user could put a <RETURN> in their attribute... big deal?
   if($txt =~ /[\r\n]/) { 
      $txt = db_safe($txt);
      return "$name:$flag:M:$txt";
   } else {
      return "$name:$flag:A:$txt";
   }
}

#
# db_safe
#   Make a string safe for writing to a db flat file. In the past, this
#   was just a call to encode_base64() but that is less readable.
#
sub db_safe
{
   my $txt = shift;

   my $ret = chr(23);
   $txt =~ s/\r\n/$ret/g;
   $txt =~ s/\n/$ret/g;
   $txt =~ s/\r/$ret/g;

   my $semi = chr(24);
   $txt =~ s/;/$semi/g;

   return $txt;
}

#
# db_unsafe
#    Take those special characters and convert them back to what they
#    really should be. This should only be used when reading from a
#    db flat file.
#
sub db_unsafe
{
   my $txt = shift;

   my $ret = chr(23);
   my $semi = chr(24);

   $txt =~ s/$ret/\n/g;
   $txt =~ s/$semi/;/g;
   return $txt;
}

#
# hash_serialize
#    Convert a hash table into a text based version that can be
#    written to a file. Limit some hash tables to certain sizes.
#
sub hash_serialize
{
   my ($attr,$name,$dbref) = @_;
   my ($out, $i);

   return undef if ref($attr) ne "HASH";

   for my $key (sort {$b cmp $a} keys %$attr) {
      $out .= ";" if($out ne undef);
      if($$attr{$key} =~ /;/) {
         $out .= "$key:M:" . db_safe($$attr{$key});
      } else {
         $out .= "$key:A:$$attr{$key}";
      }

      if(++$i >= 20 && $name eq "obj_lastsite") {
         return $out;
      }
   }
   return $out;
}

sub reserved
{
   my $attr = shift;

   if($attr =~ /^obj_/i) {
      return 1;
   } else {
      return 0;
   }
}


sub db_attr_exist
{
   my ($id,$key) = (obj(shift),trim(lc(shift)));

   my $obj = dbref($id);

   if($obj eq undef) {
      return 0;
   } elsif(reserved($key)) {
      return (defined $$obj{obj_$key}) ? 1 : 0;
   } else {
      return (defined $$obj{$key}) ? 1 : 0;
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
   if(!reserved($attr) && $value =~ /^([\$\^\!])(.+?)(?<![\\])([:])/) {
      my ($type,$pat,$seg) = ($1,$2,$');
      $pat =~ s/\\:/:/g;
      $$attr{type} = $type;
      $$attr{glob} = $pat;
      $$attr{regexp} = glob2re($pat);
      $$attr{value} = $seg;
   } else {                                                # non-listen/command
      $$attr{value} = $value;                             # set attribute value
      delete @$attr{type};
      delete @$attr{glob};
      delete @$attr{regexp};
   }
}

sub db_set_flag
{
   my ($id,$key,$flag,$value) = (obj(shift),lc(shift),shift,shift);

   return if $flag eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);
   $id = $$id{obj_id} if(ref($id) eq "HASH");

   my $obj = dbref_mutate($id);

   $$obj{$key} = {} if(!defined $$obj{$key});       # create attr if needed

   my $attr = $$obj{$key};

   $$attr{flag} = {} if(!defined $$attr{flag});

   if($value eq undef) {
      delete @{$$attr{flag}}{$flag};
   } else {
      @{$$attr{flag}}{$flag} = 1;
   }
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
      db_set_flag($$rec{obj_id},$$rec{atr_name},$$rec{fde_name},1);
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
      return con("Could not open json.txt for writing");

   printf(FILE "server: %s, dbversion=%s, exported=%s\n",
      @info{version},@info{dbversion},scalar localtime());
   
   for(my $i=0;$i <= $#db;$i++) {
      printf(FILE "%s",db_object($i));
   }
   close(FILE);
}

#
# db_object
#    Export an object from memory to a somewhat readable ascii
#    format.
#
sub db_object
{
   my $i = shift;
   my $out;

   if(defined @db[$i]) {
      $out = "obj[$i] {\n";
      my $obj = @db[$i];
      for my $name ( (sort grep {/^obj_/} keys %$obj), 
                     (sort grep {!/^obj_/} keys %$obj) ) {
         my $attr = $$obj{$name};
         
         if(reserved($name) && defined $$attr{value} &&
            $$attr{type} eq "list") {
            $out .= "   $name\::L:" . join(',',keys %{$$attr{value}}) . "\n";
         } elsif(reserved($name) && defined $$attr{value} &&
            $$attr{type} eq "hash") {
            $out .= "   $name\::H:" . hash_serialize($$attr{value},$name,$i)."\n";
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
      db_set($$state{obj},$1,db_unsafe($'));
      db_set_flag($$state{obj},$1,$2,1) if($2 ne undef);
   } elsif($$state{obj} ne undef && $line =~ /^\s*([^ \/:]+):([^:]*):A:/) {
      db_set($$state{obj},$1,$');
      db_set_flag($$state{obj},$1,$2,1) if($2 ne undef);
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
            db_set_hash($$state{obj},$attr,$1,db_unsafe($2));
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
      con("Unable to parse[$$state{obj}]: '%s'\n",$line);
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
      con("Unable to read file '$name'\n");

   con("Opening database file: %s\n",$name);

   while(<$file>) {
      db_process_line($state,$_);
   }

   if(!$$state{complete} && arg("forceload")) {
      con("\n### File %s is not complete, aborting ###\n\n",$name);
      exit(1);
   }
   con("    Database Version %s -- %s bytes read\n",
          $$state{ver},
          $$state{chars}
         );
   close($file);
}

$SIG{'INT'} = sub {  if(memorydb) {
                        con("**** Program Exiting ******\n"); 
                        cmd_dump(obj(0),{},"CRASH");
                        @info{crash_dump_complete} = 1;
                        con("**** Dump Complete Exiting ******\n");
                     }
                     con("CALLED\n");
                     exit(1);
                  };

END {
   if(memorydb && !defined @info{crash_dump_complete} && $#db > -1) {
      con("**** Program EXITING ******\n");
      cmd_dump(obj(0),{},"CRASH");
      con("**** Dump Complete Exiting 2 ******\n");
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
   $txt =~ s/\r\s*|\n\s*//g;
   return $txt;
}

sub run_obj_commands
{
   my ($self,$prog,$runas,$obj,$cmd) = @_;
   my $match = 0;

   if(!hasflag($obj,"NO_COMMAND")) {
      for my $hash (latr_regexp($obj,1)) {
         if($cmd =~ /$$hash{atr_regexp}/i) {
            # run attribute only if last run attritube isn't the new
            # attribute to run. I.e. infinite loop. Since we're not keeping
            # a stack of exec() attributes, this won't catch more complex
            # recursive calls. Future feature?
            if(!defined $$prog{attr} || 
               !(@{$$prog{attr}}{atr_owner} eq $$obj{obj_id} &&
               @{$$prog{attr}}{atr_name} eq $$hash{atr_name})) {
               mushrun(self   => $self,
                       prog   => $prog,
                       runas  => $obj,
                       invoker=> $self,
                       cmd    => single_line($$hash{atr_value}),
                       wild   => [ $1,$2,$3,$4,$5,$6,$7,$8,$9 ],
                       from   => "ATTR",
                       attr   => $hash,
                       source => 0,
                      );
               return 1;
            }
         }
      }
   }
   return 0;
}

#
# mush_command
#   Search Order is objects you carry, objects around you, and objects in
#   the master room. http/non-interactive websocket requests only search
#   objects you carry.
#
sub mush_command
{
   my ($self,$prog,$runas,$cmd,$src) = @_;
   my $match = 0;

   $cmd = evaluate($self,$prog,$cmd) if($src ne undef && $src == 0);

   if(@info{master_overide} eq "no") {      # search master room first
      for my $obj (lcon(@info{"conf.master"})) {
         run_obj_commands($self,$prog,$runas,$obj,$cmd) && return 1;
      }
   }

   # search player
   run_obj_commands($self,$prog,$runas,$self,$cmd) && return 1;

   # search player's contents
   for my $obj (lcon($self)) {
      run_obj_commands($self,$prog,$runas,$obj,$cmd) && return 1;
   }

   # don't search past the initial player if coming from web / websocket
   # unless the command came from an attribute.
   if(!defined $$prog{attr} &&
      defined $$prog{hint} && 
      ($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET")){
      return 0;
   }

   if(@info{master_overide} ne "no") {             # search master room
      for my $obj (lcon(@info{"conf.master"})) {             # but not twice
         run_obj_commands($self,$prog,$runas,$obj,$cmd) && return 1;
      }
   }

   # search all objects in player's location's contents
   for my $obj (lcon(loc($self))) {
      $match += run_obj_commands($self,$prog,$runas,$obj,$cmd);
   }

   return ($match) ? 1 : 0;
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
   my ($self,$runas,$invoker) = @_;

   return {
      stack => [ ],
      created_by => $self,
      user => $runas,
      var => {},
      invoker => $invoker,
      priority => priority($self),
      calls => 0
   };
}

sub mushrun_add_cmd
{
   my ($arg,@cmd) = @_;

   # add to command stack or program stack
   my $prog = @$arg{prog};
   my $stack = $$prog{stack};

   for my $i (0 .. $#cmd) {
      my $data = { runas   => $$arg{runas},
                   source  => $$arg{source},
                   invoker => $$arg{invoker},
                   prog    => $$arg{prog},
                   mdigits => $$arg{match}
                 };
      if($$arg{child} == 1) {                         # add to top of stack
         $$data{cmd} = @cmd[$#cmd - $i];
         unshift(@$stack,$data);
         $$prog{mutated} = 1;                # current cmd changed location
      } elsif($$arg{child} == 2) {                  # add after current cmd
         $$data{cmd} = @cmd[$#cmd - $i];
         my $current = $$prog{cmd};
         for my $i (0 .. $#$stack) {             #find current cmd in stack
            splice(@$stack,$i+1,0,$data) if($current eq $$stack[$i]);
         }
      } else {                                              # add to bottom
         $$data{cmd} = @cmd[$i];
         push(@$stack,$data);
      }
   }
}

#
# multiline
#    handle multiline input from the user
#
sub multiline
{
   my ($arg,$multi) = @_;

   # handle multi-line && command
   if($$arg{source} == 1 && $multi eq undef) {
      if($$arg{cmd} =~ /^\s*&&([^& =]+)\s+([^ =]+)\s*= *(.*?) *$/) {
         @{@connected{@{$$arg{self}}{sock}}}{inattr} = {
            attr    => $1,
            object  => $2,
            content => ($3 eq undef) ? [] : [ $3 ],
            prog    => $$arg{prog},
         };
         return 1;
      }
   } elsif($$arg{source} == 1 && $multi ne undef) {
      my $stack = $$multi{content};
      if($$arg{cmd} =~ /^\s*$/) {                                # attr is done
         $$arg{cmd} = "&$$multi{attr} $$multi{object}=" . join("\r\n",@$stack);
         delete @{$connected{@{$$arg{self}}{sock}}}{inattr};
         return 0;
      } elsif($$arg{cmd} =~  /^\s*\.\s*$/) {                       # blank line
         push(@$stack,"");
         return 1;
      } else {                                          # another line of atr
         push(@$stack,$$arg{cmd});
         return 1;
      }
   };
   return 0;
}


#
# in_run_function
#   Determine if the run() function has already been called or not.
#
sub in_run_function
{
   my $prog = shift;

   if(defined $$prog{output} && defined $$prog{nomushrun} && $$prog{nomushrun}){
      return 1;
   } else {
      return 0;
   }
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
   my $prog;

   # initialize variables.
   my $multi = inattr(@arg{self},@arg{source});              # multi-line attr
   @arg{match} = {} if(!defined @arg{match});
   @arg{runas} = @arg{self} if !defined @arg{runas};
   @arg{source} = 0 if(@arg{hint} eq "WEB");

   if(!$multi) {
      return if($arg{cmd} =~ /^\s*$/);
      @arg{cmd} = $1 if($arg{cmd} =~ /^\s*{(.*)}\s*$/s);
   }

   if(@arg{prog} eq undef) {                                       # new prog
      $prog = prog(@arg{self},@arg{runas});
      @arg{prog} = $prog;
      @engine{++$info{pid}} = $prog;                    # add to process list
      $$prog{pid} = $info{pid};
   } else {                                                   # existing prog
      $prog = @arg{prog};
      if(!defined $$prog{pid}) {
         @engine{++$info{pid}} = $prog;                 # add to process list
         $$prog{pid} = $info{pid};
      }
   }
   

   if(!defined @arg{invoker}) {              # handle who issued the command
      if(defined $$prog{cmd_last} && defined @$prog{cmd_last}->{invoker}) {
         @arg{invoker} = @$prog{cmd_last}->{invoker};
#         printf("     INVOKER1: '%s'\n",@arg{invoker});
      } elsif(defined $$prog{invoker}) {
         @arg{invoker} = $$prog{invoker};
#         printf("     INVOKER2: '%s'\n",@arg{invoker});
      } else {
         con("     INVOKER: NONE '%s' -> '%s'\n",@arg{invoker},code());
      }
    } else {
#         printf("     INVOKER: ALREADY SET\n",@arg{invoker});
    }

   # copy over program level data
   for my $i ("hint", "attr", "sock", "output", "from") {
      if(defined @arg{$i} && !defined $$prog{$i}) {
         $$prog{$i} = @arg{$i};
      }
   }

   if(in_run_function($prog)) {
      my $stack = $$prog{stack};
      push(@$stack,"#-1 Not a valid command inside RUN function");
      return;
   } elsif(multiline(\%arg,$multi)) {          # multiline handled in function
      return;
   } elsif(@arg{source} == 1) {                    # from user input, no split
      mushrun_add_cmd(\%arg,@arg{cmd});
   } else {                                   # non-user input, slice and dice
      mushrun_add_cmd(\%arg,balanced_split(@arg{cmd},";",3,1));
   }

   if(defined $arg{wild}) {
      set_digit_variables($arg{self},$arg{prog},"",@{$arg{wild}}); # copy %0-%9
   }
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
   my ($self,$prog,$sub) = (shift,shift,shift);
   my $hash;

   # clear previous variables > 9
   for my $i ( grep {/^$sub\d+$/} keys %{$$prog{var}}) {
      delete @{$$prog{var}}{$sub . $i};
   }

   if(ref($_[0]) eq "HASH") {
      my $new = shift;
#      for my $i (keys %$new) {
       for my $i (0 .. 9) {
         @{$$prog{var}}{$sub . $i} = "$$new{$i}";
      }
   } else {
      my @var = @_;

#      for my $i ( 0 .. (($#_ > 9) ? $#_ : 9)) {
      for my $i ( 0 .. 9 ) {
         @{$$prog{var}}{$sub . $i} = "$var[$i]";
      }
   }
}

sub get_digit_variables
{
    my ($prog,$sub) = (shift,shift);
    my $result = {};
  
    for my $i ( grep {/^\d+$/} keys %{$$prog{var}}) {
       $$result{$sub . $i} =  @{$$prog{var}}{$sub . $i};
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

sub mushrun_done
{
   my $prog = shift;
   my $cost = ($$prog{command} + ($$prog{function} / 10)) / 128;
   my $attr;

   
   if($cost > .5) {                                        # handle cost
      if(defined $$prog{attr}) {
         $attr = "#@{$$prog{attr}}{atr_owner}/@{$$prog{attr}}{atr_name} => ";
      }
      logit($$prog{hint} eq "WEB" ? "weblog" : "conlog",
            "Cost: %s%.3f pennies in %.3fs [%sc/%sf]\n",
            $attr,
            $cost,
            $$prog{function_duration} + $$prog{command_duration},
            nvl($$prog{command},0),
            nvl($$prog{function},0)
           );
#      for my $key (grep {/^fun_/} keys %$prog) {
#         printf("   $key = $$prog{$key}\n");
#      }
   }

   if($$prog{hint} eq "WEBSOCKET") {
      my $msg = join("",@{@$prog{output}});
      $prog->{sock}->send_utf8(ansi_remove($msg));
   } elsif($$prog{hint} eq "WEB") {
      if(defined $$prog{output}) {
         http_reply($prog,"%s",join("",@{@$prog{output}}));
      } else {
         http_reply($prog,"%s","No data returned");
      }
   }
   close_telnet($prog);
   delete @engine{$$prog{pid}};
}

sub spin_done
{
    die("alarm");
}

#
# spin
#    Run one command from each program that is running
#
sub spin
{
   my $start = Time::HiRes::gettimeofday();
   my ($count,$pid);

   $SIG{ALRM} = \&spin_done;

   eval {
       ualarm(15_000_000);                              # err out at 8 seconds
       local $SIG{__DIE__} = sub {
          delete @engine{@info{current_pid}};
          con("----- [ Crash REPORT@ %s ]-----\n",scalar localtime());
          con("%s\n",code("long"));
       };


      if(time()-@info{db_last_dump} > @info{"conf.backup_interval"}) {
         @info{db_last_dump} = time();
         my $self = obj(0);
         mushrun(self   => $self,
                 runas  => $self,
                 invoker=> $self,
                 source => 0,
                 cmd    => "\@dump",
                 from   => "ATTR",
                 hint   => "ALWAYS_RUN"
         );
      }


      for $pid (sort {$a cmp $b} keys %engine) {
         @info{current_pid} = $pid;
         my $prog = @engine{$pid};
         my $stack = $$prog{stack};
         my $pos = 0;
         $count = 0;

         # run 100 commands, backgrounded command are excluded because 
         # someone could put 100 waits in for far in the furture, the code
         # would never run the next command.
         while($#$stack - $pos >= 0 && ++$count <= 100 + $pos) {
            my $cmd = $$stack[$pos];                          # run 100 cmds
            my $before = $#$stack;

            if(defined $$cmd{done}) {                  # cmd already finished
               splice(@$stack,$pos,1);                   # safe to delete now
               next;
            }
     
            my $result = spin_run($prog,$cmd);

            if($result eq "BACKGROUNDED") {
               $pos++; 
            } elsif($result ne "RUNNING") {                   # command done
               if(defined $$prog{mutated}) {       # cmd moved from pos 0,
                  delete @$cmd{keys %$cmd};      # but where? delete later
                  $$cmd{done} = 1;
               } else {
                  splice(@$stack,$pos,1);             # safe to delete cmd
               }
            } elsif(defined $$prog{idle}) {                 # program idle
               delete @$prog{idle};
               last;
            }
            delete @$prog{mutated} if defined @$prog{mutated};

            if(Time::HiRes::gettimeofday() - $start >= 1) { # stop
               con("   Time slice ran long, exiting correctly [%d cmds]\n",
                      $count);
               mushrun_done($prog) if($#$stack == -1);     # program is done
               ualarm(0);
               return;
            }
         }
   
         mushrun_done($prog) if($#$stack == -1);            # program is done
      }
      ualarm(0);
   };

   if($@ =~ /alarm/i) {
      con("Time slice timed out (%2f w/%s cmd) $@\n",
         Time::HiRes::gettimeofday() - $start,$count);
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

   # the object was probably destroyed, do not run any more code from it.
   return if(!valid_dbref($$command{runas}));

   $$prog{cmd} = $command;
   if(length($cmd) ne 1) {
      while($arg =~ /^\s*\/([^ =\/]+) */) {                  # find switches
         @switch{lc($1)} = 1;
         $arg = $';
      }
   }

#   con("RUN(%s->%s): '%s%s'\n",
#          @{$$prog{created_by}}{obj_id},
#          @{$$command{runas}}{obj_id},
#          substr($cmd.$arg,0,60),
#          (length($cmd.$arg) > 60) ? "..." : ""
#         );
 
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
   

   
   my $start = Time::HiRes::gettimeofday();
   $$prog{function_command} = 0;

   my $cost = sprintf("%d",($$prog{command} + ($$prog{function} / 10)) / 128);
   if($cost != 0 && $$prog{cost} != $cost && 
      !hasflag($$command{runas},"WIZARD")) {
      $$prog{cost} = $cost;
      give_money($$command{runas},-1);
   }

   if($$command{source} == 1  || money($$command{runas}) > 0) {
       my $result = &{@{$$hash{$cmd}}{fun}}($$command{runas},
                                            $prog,
                                            trim($arg),
                                            \%switch
                                           );
       $$prog{command_duration} += Time::HiRes::gettimeofday() - $start;
       $$prog{command}++;
    #   $$prog{"command_$cmd"}++;
       return $result;
   }
}

sub spin_run
{
   my ($prog,$command,$foo) = @_;
   my $self = $$command{runas};
   my ($cmd,$hash,$arg,%switch);
   $$prog{cmd_last} = $command;
   $$prog{cmd} = $command;


   if($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET") {
      if(defined $$prog{from} && $$prog{from} eq "ATTR") {
         $hash = \%command;
      } else {
         $hash = \%switch;                                      # no commands
      }
   } else {
      $hash = \%command;
   }

   if($$command{cmd} =~ /^\s*([^ \/]+)(\s*)/s) {         # split cmd from args
      ($cmd,$arg) = ($1,$2.$'); 
       $cmd =~ s/^\\//g;

       # allow % substitutions in @command
       if(!defined $$hash{substr($cmd,0,1)}{nsp} && $cmd =~ /%/) { 
          $cmd = evaluate_substitutions($self,$prog,$cmd);
          if($cmd =~ /^\s*([^ \/]+)\s*/s) {
             ($cmd,$arg) = ($1,$' . $arg);
          }
       } elsif(!defined $$hash{substr($cmd,0,1)}{nsp}) {
          $arg =~ s/^\s+//g;                           # remove extra spaces
       }
       $$command{mushcmd} = $cmd;
   } else {
      return;                                                 # only spaces
   }

   # skip any @while command with an open socket without pending input
   if(lc($cmd) eq "\@while" &&
      defined $$prog{socket_id} && 
      !defined $$prog{socket_closed} &&
      (!defined $$prog{socket_buffer} ||
       $#{$$prog{socket_buffer}} == -1)) {
      $$prog{idle} = 1;
      return "RUNNING";
  } elsif(defined $$hash{lc($cmd)}) {                          # internal cmd
      return run_internal($hash,lc($cmd),$command,$prog,$arg);
  } elsif(defined $$hash{substr($cmd,0,1)} &&            # internal 1 char cmd
     (defined $$hash{substr($cmd,0,1)}{nsp} ||
      substr($cmd,1,1) eq " " ||
      length($cmd) == 1
     )) {
      $$command{mushcmd} = substr($cmd,0,1);
      return run_internal($hash,$$command{mushcmd},
                          $command,
                          $prog,
                          substr($cmd,1) . $arg,
                          \%switch,
                          1
                         );
   } elsif(find_exit($self,$prog,$$command{cmd})) {   # handle exit as command
      return &{@{$$hash{"go"}}{fun}}($$command{runas},$prog,$$command{cmd});
   } elsif(mush_command($self,
                        $prog,
                        $$command{runas},
                        $$command{cmd},
                        $$command{source})) {
      return 1;                                   # mush_command runs command
   } else {
      my $match;

      if($match ne undef && lc($cmd) ne "q") {                  # found match
         return run_internal($hash,$match,$command,$prog,$arg);
      } else {                                                     # no match
         return &{@{@command{"huh"}}{fun}}($$command{runas},
                                           $prog,
                                           $$command{cmd});
      }
   }
   return 1;
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
   my ($start_count,$start_obj,$middle_count,$middle_obj);

   return undef if $thing eq undef;

   my $start = glob2re("$thing*");
   my $middle = glob2re("*$thing*");

   for my $obj (@list) {
      my $name = lc(name($obj,1));
      if($name eq $thing) {                                    # exact match
         return obj($obj);
      } elsif($start > 1 || $middle > 1) {              # fuzzy match failed
         # skip
      } else {
         if($name =~ /$start/) {
            $start_count++;
            $start_obj = $obj;
         } elsif($name =~ /$middle/) {
            $middle_count++;
            $middle_obj = $obj;
         }
      }
   }

   if($start_count == 1) {
      return obj($start_obj);
   } elsif($middle_count == 1) {
      return obj($middle_obj);
   } else {
      return undef;
   }
}

#
# find
#    Find something in
sub find
{
   my ($self,$prog,$thing,$debug) = (shift,shift,trim(lc(shift)),shift);
   my ($partial, $dup);

   my $debug = 0;

   if(ansi_remove($thing) eq undef) {
      printf("got here: 0\n") if $debug;
      return undef;
   } elsif($thing =~ /^\s*#(\d+)\s*$/) {
      printf("got here: 1\n") if $debug;
      return valid_dbref($1) ? obj($1) : undef;
   } elsif($thing =~ /^\s*here\s*$/) {
      printf("got here: 2\n") if $debug;
      return loc_obj($self);
   } elsif($thing =~ /^\s*%#\s*$/) {
      printf("got here: 3\n") if $debug;
      return $$prog{created_by};
   } elsif($thing =~ /^\s*me\s*$/) {
      printf("got here: 4\n") if $debug;
      return $self;
   } elsif($thing =~ /^\s*\*/) {
       my $player = lc(trim($'));
       if(defined @player{$player}) {
      printf("got here: 5\n") if $debug;
          return obj(@player{$player});
       } else {
      printf("got here: 6\n") if $debug;
          return undef
       }
   }

   # search in contents of object
   my $obj = find_in_list($thing,lcon($self));
      printf("got here: 7 -> '$obj'\n") if $debug;
   return $obj if($obj ne undef);
      printf("got here: 8\n") if $debug;

   # search around object
   my $obj = find_in_list($thing,lcon(loc($self)));
      printf("got here: 9\n") if $debug;
   return $obj if($obj ne undef);
      printf("got here: 10\n") if $debug;

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

#
# find_player
#    Search for a player
#
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
      for my $rec (@{sql("select obj.obj_id, obj_name " .
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

    if($depth + length($txt) < @info{max}) {           # short, copy it as is.
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
    if($depth + length($cmd . " " . $txt) < @info{max}) {
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
    return dprint($depth,"%s %s",$cmd,$txt) if(length($txt)+$depth + 3 < @info{max});

    # split up command by ','
    my @list = fmt_balanced_split($txt,',',3);
  
    # split up first segment again by "="
    my ($first,$second) = fmt_balanced_split(shift(@list),'=',3);


    my $len = $depth + length($cmd) + 1;                  # first subsegment
    if($len + length($first)  > @info{max}) {                        # multilined
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
       } elsif($depth + $indent + length(@list[$i]) > @info{max} ||  # long cmd
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

      if(length($val) + $depth < @info{max}) {
         $out .= dprint($depth,"%s","$cmd$txt");
      } elsif($val =~ /^\s*\[.*\]\s*(;{0,1})\s*$/) {
         $out .= dprint($depth,"%s","&$atr $obj=");
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
   if($depth + length("$left$function($arguments)$right") - length(@array[0]) < @info{max}) {
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

   if($depth + length($txt) < @info{max}) {                      # too small
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

    if($depth + length($txt) < @info{max}) {
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
#my %exclude = 
#(
#   iter      => { 2 => 1 },
#   parse     => { 2 => 1 },
#   setq      => { 2 => 1 },
#   switch    => { all => 1 },
##   u         => { 2 => 1, 3 => 1, 4 => 1, 5 => 1, 6 => 1, 7 => 1, 8 => 1,
##                  9 => 1, 10 => 1 },
#);

sub initialize_functions
{
   @fun{html_strip}= sub { return &fun_html_strip(@_);             };
   @fun{foreach}   = sub { return &fun_foreach(@_);                };
   @fun{itext}     = sub { return &fun_itext(@_);                  };
   @fun{inum}      = sub { return &fun_inum(@_);                   };
   @fun{ilev}      = sub { return &fun_ilev(@_);                   };
   @fun{pack}      = sub { return &fun_pack(@_);                   };
   @fun{unpack}    = sub { return &fun_unpack(@_);                 };
   @fun{round}     = sub { return &fun_round(@_);                  };
   @fun{if}        = sub { return &fun_if(@_);                     };
   @fun{ifelse}    = sub { return &fun_if(@_);                     };
   @fun{pid}       = sub { return &fun_pid(@_);                    };
   @fun{lpid}      = sub { return &fun_lpid(@_);                   };
   @fun{null}      = sub { return &fun_null(@_);                   };
   @fun{args}      = sub { return &fun_args(@_);                   };
   @fun{shift}     = sub { return &fun_shift(@_);                  };
   @fun{unshift}   = sub { return &fun_unshift(@_);                };
   @fun{pop}       = sub { return &fun_pop(@_);                    };
   @fun{push}      = sub { return &fun_push(@_);                   };
   @fun{asc}       = sub { return &fun_ord(@_);                    };
   @fun{ord}       = sub { return &fun_ord(@_);                    };
   @fun{chr}       = sub { return &fun_chr(@_);                    };
   @fun{escape}    = sub { return &fun_escape(@_);                 };
   @fun{trim}      = sub { return &fun_trim(@_);                   };
   @fun{ansi}      = sub { return &fun_ansi(@_);                   };
   @fun{ansi_debug}= sub { return &fun_ansi_debug(@_);             };
   @fun{substr}    = sub { return &fun_substr(@_);                 };
   @fun{mul}       = sub { return &fun_mul(@_);                    };
   @fun{file}      = sub { return &fun_file(@_);                   };
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
   @fun{fdiv}      = sub { return &fun_fdiv(@_);                   };
   @fun{secs}      = sub { return &fun_secs(@_);                   };
   @fun{loadavg}   = sub { return &fun_loadavg(@_);                };
   @fun{after}     = sub { return &fun_after(@_);                  };
   @fun{before}    = sub { return &fun_before(@_);                 };
   @fun{member}    = sub { return &fun_member(@_);                 };
   @fun{index}     = sub { return &fun_index(@_);                  };
   @fun{replace}   = sub { return &fun_replace(@_);                };
   @fun{num}       = sub { return &fun_num(@_);                    };
   @fun{lnum}      = sub { return &fun_lnum(@_);                   };
   @fun{name}      = sub { return &fun_name(0,@_);                 };
   @fun{fullname}  = sub { return &fun_name(1,@_);                 };
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
   @fun{strmatch}  = sub { return &fun_strmatch(@_);               };
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
   @fun{listinter} = sub { return &fun_listinter(@_);              };
   @fun{sort}      = sub { return &fun_sort(@_);                   };
   @fun{mudname}   = sub { return &fun_mudname(@_);                };
   @fun{version}   = sub { return &fun_version(@_);                };
   @fun{inuse}     = sub { return &inuse_player_name(@_);          };
   @fun{web}       = sub { return &fun_web(@_);                    };
   @fun{run}       = sub { return &fun_run(@_);                    };
   @fun{graph}     = sub { return &fun_graph(@_);                  };
   @fun{lexits}    = sub { return &fun_lexits(@_);                 };
   @fun{lcon}      = sub { return &fun_lcon(@_);                   };
   @fun{home}      = sub { return &fun_home(@_);                   };
   @fun{rand}      = sub { return &fun_rand(@_);                   };
   @fun{lrand}     = sub { return &fun_lrand(@_);                  };
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
   @fun{max}        = sub { return &fun_max(@_);                   };
   @fun{controls}   = sub { return &fun_controls(@_);              };
   @fun{invocation} = sub { return &fun_invocation(@_);            };
   @fun{url}        = sub { return &fun_url(@_);                   };
   @fun{lflags}     = sub { return &fun_lflags(@_);                };
   @fun{huh}        = sub { return "#-1 Undefined function";       };
   @fun{money}      = sub { return &fun_money(@_);                 };
   @fun{ip}         = sub { return &fun_ip(@_);                    };
   @fun{entities}   = sub { return &fun_entities(@_);              };
   @fun{setunion}   = sub { return &fun_setunion(@_);              };
   @fun{setdiff}    = sub { return &fun_setdiff(@_);               };
   @fun{lit}        = sub { return &fun_lit(@_);                   };
   @fun{stats}      = sub { return &fun_stats(@_);                 };
   @fun{mod}        = sub { return &fun_mod(@_);                   };
   @fun{filter}     = sub { return &fun_filter(@_);                };
   @fun{pickrand}   = sub { return &fun_pickrand(@_);              };
}


#
# add_union_element
#     Dbrefs can not be sorted directly, so safe the dbref minus the "#"
#     as the hash value so it can be used to sort the list.
#
sub add_union_element
{
   my ($list,$item,$type) = @_;

   if($type eq "d") {
      if($item =~ /^\s*#(\d+)\s*$/) {
         $$list{$item} = $1;
      } else {
         $$list{$item} = $item;
      }
   } else {
      $$list{$item} = $item;
   }
}

sub atr_get
{
   my ($self,$prog) = (shift,shift);
   my ($target,$atr);

   my $txt = evaluate($self,$prog,shift);

   if($txt =~ /\//) {
      $target = find($self,$prog,$`) || return undef;
      $atr = $';
   } else {
      $target = $self;
      $atr = $txt;
   }

   return get($target,$atr);
}

sub fun_ansi_debug
{
   my($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (FOREACH) EXPECTS 1 ARGUMENT";

   return ansi_debug(evaluate($self,$prog,shift));
}
#
# for_foreach
#    Take a list of characters and feed it through the specified function
#    like u().
#
sub fun_foreach
{
   my($self,$prog) = (obj(shift),shift);
   my ($out,$left,$tmp);

   good_args($#_,2,4) ||
     return "#-1 FUNCTION (FOREACH) EXPECTS 2 OR 4 ARGUMENTS";

   my $atr = atr_get($self,$prog,shift);                  # no attr/ no error
   return "#-1 no attr" if($atr eq undef);                 # emulate mux/mush

   my $str = trim(evaluate($self,$prog,shift));

   if($#_ == 1) {                               # handle optional start/stop
      my $start     = evaluate($self,$prog,shift);
      my $end       = evaluate($self,$prog,shift);
      ($out,$tmp) = balanced_split($str,$start,4);

      return if($tmp eq undef);                           # no starting point
                                                                  # no change
      ($str,$left) = balanced_split($tmp,$end,4);
   }

   my $prev = get_digit_variables($prog);                     # save %0 .. %9
   my $count = 0;

   for(my ($i,$len)=(0,length($str));$i < $len;$i++) {
      set_digit_variables($self,$prog,"",substr($str,$i,1),$count++);
      $out .= evaluate($self,$prog,$atr);
   }

   set_digit_variables($self,$prog,"",$prev);              # restore %0 .. %9

   return $out . $left;
}


# src: http://rosettacode.org/wiki/Non-decimal_radices/Convert#Perl
sub fun_pack
{
   my($self,$prog,$n,$b) = (obj(shift),shift);

   good_args($#_,1,2,3) ||
     return "#-1 FUNCTION (PACK) EXPECTS 1, 2, or 3 ARGUMENTS - $#_";

   my $n = evaluate($self,$prog,shift);
   my $b = evaluate($self,$prog,shift);
   $b = 10 if $b eq undef;

   my $s = "";
   while ($n) {
      printf("Processing $n\n");
      $s .= ('0'..'9','a'..'z')[$n % $b];
      $n = int($n/$b);
   }
   return "x" . scalar(reverse($s));
}

sub fun_unpack
{
   my($self,$prog) = (obj(shift),shift);

   good_args($#_,1,2,3) ||
     return "#-1 FUNCTION (PACK) EXPECTS 1, 2, or 3 ARGUMENTS - $#_";

   my $n = evaluate($self,$prog,shift);
   my $b = evaluate($self,$prog,shift);
   $b = 16 if $b eq undef;

   my $t = 0;
   for my $c (split(//, lc($n))) {
     $t = $b * $t + index("0123456789abcdefghijklmnopqrstuvwxyz", $c);
   }
  return $t;
}

sub fun_pickrand
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1,2) ||
     return "#-1 FUNCTION (PICKRAND) EXPECTS 1 OR 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);
   $delim =  " " if($delim eq undef);
  
   my $list = [ safe_split($txt,$delim) ];

   return $$list[int(rand($#$list+1))];
}

#
# fun_if
#
sub fun_if
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (IF/IF_ELSE) EXPECTS 2 OR 3 ARGUMENTS";

   my $exp = evaluate($self,$prog,shift);

   shift if(!$exp);
   return trim(evaluate($self,$prog,shift));
}
#
# fun_round
#    Round a number with variable precision
#
sub fun_round
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1,2) ||
      return "#-1 FUNCTION (HTML_STRIP) EXPECTS 1 OR 2 ARGUMENTS";

   my $num = evaluate($self,$prog,shift);
   my $precision = evaluate($self,$prog,shift);

   if($precision eq undef || $precision !~ /^\s*\d+\s*$/) { # emulate tinymush
      $precision = 0;                                               # behavior
   }
   return sprintf("%.*f",$precision,$num);
}

sub fun_html_strip
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   if(@info{"conf.html_restrict"} == -1) {
      return "#-1 Not enabled";
   }

   good_args($#_,1) ||
      return "#-1 FUNCTION (HTML_STRIP) EXPECTS 1 ARGUMENTS";
    
   my $hr = HTML::Restrict->new();
   return $hr->process(evaluate($self,$prog,shift));
}

#
# fun_pid
#    Return the pid of the current program.
#
sub fun_pid
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   return $$prog{pid};
}

#
# fun_lpid
#    Return all pids that you own / can control.
#
sub fun_lpid
{
   my ($self,$prog) = (obj(shift),shift);
   my @list;

   for my $pid (keys %engine) {
      my $p = @engine{$pid};

      if(defined $$p{stack} && ref($$p{stack}) eq "ARRAY" &&
         controls($self,$$p{created_by}) &&
         (!hasflag($$p{created_by},"GOD") || hasflag($self,"GOD"))) {
         push(@list,$pid);
      }
   }
   return join(' ',@list);
}

sub fun_null
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   evaluate($self,$prog,shift);
   return undef;
}

sub fun_trim
{
   my ($self,$prog) = (obj(shift),shift);
   my ($start,$end,%filter);

   good_args($#_,1,2,3) ||
      return "#-1 FUNCTION (TRIM) EXPECTS 1, 2, OR 3 ARGUMENTS";

   my $txt    = ansi_init(evaluate($self,$prog,shift));
   my $type   = trim(ansi_remove(evaluate($self,$prog,shift)));
   my $chars  = trim(ansi_remove(evaluate($self,$prog,shift)));

   if($type =~ /^\s*(b|l|r)\s*$/) {                             # check args
      $type = $1;
   } else {
      $type = "b";                               # emulate Mush w/no errors
   }

   if($chars eq undef) {                               # set chars to filter
      @filter{" "} = 1;
   } else {
      for my $i (0 .. length($chars)) {
         @filter{substr($chars,$i,1)} = 1;
      }
   }

   if($type eq "b" || $type eq "l") {                  # find starting point
      for my $i (0 .. ansi_length($txt)) {
         $start = $i;
         last if(!defined @filter{ansi_remove(ansi_substr($txt,$i,1))});
         $start = $i;
      }
   } else {
      $start = 0;
   }

   
   if($type eq "b" || $type eq "r") {                   # find ending point
      for my $i (reverse 0 .. ansi_length($txt)) {
         $end = $i;
         last if(!defined @filter{ansi_remove(ansi_substr($txt,$i-1,1))});
      }
   } else {
      $end = ansi_length($txt);
   }

   return ansi_substr($txt,$start,$end-$start);              # return result
}

sub fun_escape
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   my $txt = evaluate($self,$prog,shift);

   $txt =~ s/([%\\\[\]{};,()])/\\\1/g;
   return "\\" . $txt;
}
#
# fun_mod
#    Return the modulus of two numbers
#
sub fun_mod
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (MOD) EXPECTS 2 ARGUMENTS";

   my $one = ansi_remove(evaluate($self,$prog,shift));
   my $two = ansi_remove(evaluate($self,$prog,shift));

   # divide by zero should result in an error in my opinion but TinyMUSH
   # just returns 0, so we emulate this behavior.
   if(!looks_like_number($one) || !looks_like_number($two) || $two == 0) {
      return 0;
   } else {
      return $one % $two;
   }
}

sub fun_stats
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
   my ($hash, $target);

   $txt = evaluate($self,$prog,$txt);

   if($txt =~ /^\s*all\s*$/i) {
      $hash = gather_stats(1,"all");
   } elsif($txt =~ /^\s*$/) {
      $hash = gather_stats(2);
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "The universe contains %d objects.",
                                $$hash{OBJECT} ]
                  );
   } else {
      $target = find_player($self,$prog,$txt) ||
         return "#-1 PLAYER NOT FOUND";

      $hash = gather_stats(1,"",$target);
   }

   return sprintf("%s %s %s %s %s %s",
                  $$hash{ROOM} + $$hash{EXIT} + $$hash{OBJECT} +
                      $$hash{PLAYER} +  $$hash{GARBAGE},
                  $$hash{ROOM},
                  $$hash{EXIT},
                  $$hash{OBJECT},
                  $$hash{PLAYER},
                  $$hash{GARBAGE});
}


sub type
{
   my ($self,$prog,$obj) = @_;
 
   if(hasflag($obj,"PLAYER")) {
      return "PLAYER";
   } elsif(hasflag($obj,"ROOM")) {
      return "ROOM";
   } elsif(hasflag($obj,"OBJECT")) {
      return "OBJECT";
   } elsif(hasflag($obj,"EXIT")) {
      return "EXIT";
   } else {
      if(dest($obj) ne undef) {                       # has destination, exit
         set_flag($self,$prog,$obj,"EXIT");
         return "EXIT";
      } else {
         set_flag($self,$prog,$obj,"OBJECT");
         return "OBJECT";
      }
   }
}

sub fun_lit
{
   my ($self,$prog) = (obj(shift),shift);

   return join(',',@_);
}

sub rgb2ansi
{
   my ($r1,$g1,$b1) = @_;
   my ($rgb_diff,$rgb_diff2,$result) = (1000,1000);

   for my $i (16 .. 255) {
      if(@ansi_rgb{$i} =~ /^(.{2})(.{2})(.{2})$/) {
         $rgb_diff = abs(hex($1)-$r1) + abs(hex($2)-$g1) + abs(hex($3)-$b1);

         if($rgb_diff < $rgb_diff2) {
            $rgb_diff2 = $rgb_diff;
            $result = $i;
            return $i if($rgb_diff2 ==  0);
         }
      } else {
         printf("Unparseable entry $i -> '@ansi_rgb{$i}'\n");
      }
   }
   return $result;
}

sub fun_ansi
{
   my ($self,$prog) = (obj(shift),shift);
   my $color;

   good_args($#_,2) ||
      return "#-1 FUNCTION (ANSI) EXPECTS 2 ARGUMENTS";

   my $code = evaluate($self,$prog,shift);
   my $txt = evaluate($self,$prog,trim(shift));
   printf("ANSI: '%s' -> '%s'\n",$code,$txt);

   if($code =~ /^\s*<\s*(\d+)\s+(\d+)\s+(\d+)\s*>\s*$/) {
      $color = rgb2ansi($1,$2,$3);
   } elsif($code =~ /^\s*<\s*#\s*(\d{2})(\d{2})(\d{2})\s*>\s*$/) {
      $color = rgb2ansi(hex($1),hex($2),hex($3));
   } elsif($code =~ /^\s*\+\s*([^ ]+)\s*$/) {
      if(defined @ansi_name{lc($1)}) {
         $color = @ansi_name{lc($1)};
      } else {
         return $txt;                               # emulate Rhost, no error
      }
   } elsif($code =~ /^\s*</) {
      return $txt;                                  # emulate Rhost, no error
   } else {
      return color($code,$txt);
   }

   return "\e[38;5;$color\m$txt\e[0m";
}

#
# fun_setunion
#    Join two lists together removing duplicates and return sorted.
#
sub fun_setunion
{
   my ($self,$prog) = (obj(shift),shift);
   my %list;

   #--- [ handle arguments ]---------------------------------------------#
   good_args($#_,2 .. 5) ||
      return "#-1 FUNCTION (SETUNION) EXPECTS 2 to 5 ARGUMENTS";

   my $list1 = evaluate($self,$prog,shift);
   my $list2 = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);
   my $sep = evaluate($self,$prog,shift);
   my $type  = evaluate($self,$prog,shift);

   $delim = " " if($delim eq undef);
   $sep   = " " if($sep eq undef);

   #--- [ do the work ]--------------------------------------------------#

   for my $i (safe_split($list1,$delim), safe_split($list2,$delim)) {
      add_union_element(\%list,$i,$type);
   }

   #--- [ return the results sorted ]------------------------------------#

   if($type eq "d") {                                           # dbref sort
      return join($sep,sort({@list{$a} <=> @list{$b}} keys %list));
   } elsif($type eq "f" || $type eq "n") {                     # number sort
      return join($sep,sort({$a <=> $b} keys %list));
   } else {                                              # alphanumeric sort
      return join($sep,sort({$a cmp $b} keys %list));
   }
}

#
# fun_listinter
#    Return only those items in both lists
#
sub fun_listinter
{
   my ($self,$prog) = (obj(shift),shift);
   my (%l1, %l2, @result,$count);

   #--- [ handle arguments ]---------------------------------------------#
   good_args($#_,2 .. 5) ||
      return "#-1 FUNCTION (SETUNION) EXPECTS 2 to 5 ARGUMENTS";

   my $list1 = evaluate($self,$prog,shift);
   my $list2 = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);
   my $sep = evaluate($self,$prog,shift);
   my $type  = evaluate($self,$prog,shift);

   $delim = " " if($delim eq undef);
   $sep   = " " if($sep eq undef);
   $type = 0 if($type ne 0 && $type ne 1);          # emulate rhost behavior

   #--- [ do the work ]--------------------------------------------------#

   for my $i (safe_split($list2,$delim)) {               # split up 2nd list
      @l2{$i} = 1;
   }

   for my $i (safe_split($list1,$delim)) {
      if(defined @l2{$i}) {                               # item in 2nd list
         push(@result,$i) if(!defined @l1{$i});             # weed out dups?
         @l2{$i} = 1 if($type == 0);
      }
   }

   #--- [ return the results ]-------------------------------------------#
   return join($sep,@result);
}

#
# fun_setdiff
#    Returns the difference of two sets of lists
#
sub fun_setdiff
{
   my ($self,$prog) = (obj(shift),shift);
   my (%list, %result);

   #--- [ handle arguments ]---------------------------------------------#
   good_args($#_,2 .. 5) ||
      return "#-1 FUNCTION (SETUNION) EXPECTS 2 to 5 ARGUMENTS";

   my $list1 = evaluate($self,$prog,shift);
   my $list2 = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);
   my $sep = evaluate($self,$prog,shift);
   my $type  = evaluate($self,$prog,shift);

   $delim = " " if($delim eq undef);
   $sep   = " " if($sep eq undef);

   #--- [ do the work ]--------------------------------------------------#

   for my $i (safe_split($list2,$delim)) {
      add_union_element(\%list,$i,$type);
   }

   for my $i (safe_split($list1,$delim)) {
      if(!defined @list{$i}) {
         add_union_element(\%result,$i,$type);
      }
   }

   #--- [ return the results sorted ]------------------------------------#

   if($type eq "d") {                                           # dbref sort
      return join($sep,sort({@result{$a} <=> @result{$b}} keys %result));
   } elsif($type eq "f" || $type eq "n") {                     # number sort
      return join($sep,sort({$a <=> $b} keys %result));
   } else {                                              # alphanumeric sort
      return join($sep,sort({$a cmp $b} keys %result));
   }
}

sub fun_entities
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (ENTITIES) EXPECTS 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);

   if($txt !~ /^\s*(encode|decode)\s*$/i) {
      return "#-1 EXPECTED FIRST ARGUEMENT OF ENCODE OR DECODE";
   } elsif($txt =~ /^\s*encode\s*$/i) {
      return encode_entities(evaluate($self,$prog,shift));
   } else {
      return decode_entities(evaluate($self,$prog,shift));
   }
}
#
# fun_file
#     Return the contents of a file
#
sub fun_file
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (FILE) EXPECTS 1 ARGUMENT";
 
   my $fn = evaluate($self,$prog,shift);

   if($fn !~ /\.txt$/i) {
      return "#-1 UNKNOWN FILE";
   } else {
      my $file = getfile($fn);

      if($file eq undef) {
         return "#-1 UNKNOWN FILE";
      } else {
         return $file;
      }
   }
}

sub fun_ip
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (IP) EXPECTS 1 ARGUMENT";

   my $target = find_player($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";


   return "#-1 PERMISSION DENIED" if(!controls($self,$target));

   for my $i (keys %connected) {
      my $hash = @connected{$i};
      if($$hash{raw} == 0 && $$hash{obj_id} == $$target{obj_id}) {
         return $$hash{ip};
      }
   }

   return undef;
}

#
# fun_money
#    Return how much money the target has. TinyMUSH does not seem to
#    put any restrictions on checking to see how much money something
#    has.
#
sub fun_money
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (MONEY) EXPECTS 1 ARGUMENT";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   return money($target);
}

#
# fun_lflags
#    Return the list of flags of the target in a readable format.
#
sub fun_lflags
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (URL) EXPECTS 1 ARGUMENT";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   return flag_list($target,1);
}


#
# fun_url
#    Open up a http/https connection to a website. Input from the socket
#    can be recieved by calling this function multiple times with the same
#    argument. Data is placed in %{data} variable.
#
sub fun_url
{
   my ($self,$prog) = (obj(shift),shift);
   my ($host,$path,$sock,$secure);

   good_args($#_,1) ||
      return "#-1 FUNCTION (URl) EXPECTS 1 ARGUMENT";

   my $txt = evaluate($self,$prog,shift);

   my $input = hasflag($self,"SOCKET_INPUT");

   if(!$input) {
      return err($self,$prog,"#-1 Permission DENIED.");
   } elsif($txt =~ /^https:\/\/([^\/]+)\//) {
      ($host,$path,$secure) = ($1,$',1);
   } elsif($txt =~ /^http:\/\/([^\/]+)\//) {
      ($host,$path,$secure) = ($1,$',0);
   } else {
      return set_var($prog,"data","#-1 Unable to parse URL");
   }

   if($secure && @info{"conf.url_https"} == -1) {
      return set_var($prog,"data","#-1 HTTPS DISABLED");
   } elsif(!$secure && @info{"conf.url_http"} == -1) {
      return set_var($prog,"data","#-1 HTTP DISABLED");
   } elsif(defined $$prog{socket_id} && $$prog{socket_url} ne $txt && 
      !defined $$prog{socket_closed}) {
      return set_var($prog,"data","#-1 CONNECTION ALREADY OPEN");
   } elsif($$prog{socket_url} eq $txt) {               # existing connection
      my $buff = $$prog{socket_buffer};

      if($#$buff >= 0) {
         my $data = shift(@$buff);

# wttr.in debug
#         if($data =~ /F/)  {
#            printf("%s -> %s\n",$data,lord($`));
#             printf("      '%s'\n",$data);
#             printf("      '%s'\n",base($data));
#         }

         set_var($prog,"data",$data);
         return 1;
      } elsif(!defined $$prog{socket_closed}) {
         $$prog{idle} = 1;                                 # hint to queue
         set_var($prog,"data","#-1 DATA PENDING");
         return 1;
      } elsif(defined $$prog{socket_closed}) {
         set_var($prog,"data","#-1 CONNECTION CLOSED");
         return 0;
      }
   } else {                                                # new connection
      delete @info{socket_buffer};                    # last request buffer

      if($secure) {                                      # open connection
         $sock = Net::HTTPS::NB->new(Host => $host);
      } else {
         $sock = Net::HTTP::NB->new(Host => $host);
      }

#      printf("HOST: '%s'\n",$host);
#      printf("PATH: '%s'\n",$path);
#      printf("SEC: '%s'\n",$secure);
#
      $$prog{socket_url} = $txt;

      if(!$sock) {
         $$prog{socket_closed} = 1;
         $$prog{socket_buffer} = [ "#-1 CONNECTION FAILED" ];
         return 1;
      }

      $sock->blocking(0);                                     # don't block

      $$prog{socket_id} = $sock;                    # link prog to socket
      delete @$prog{socket_closed};

      # make request as curl (helps with wttr.in)
      $path =~ s/ /%20/g;
      set_var($prog,"url",$path);
#      printf("PATH: '%s'\n",$path);

      eval {                        # protect against uncontrollable problems
         $sock->write_request(GET => "/$path", 'User-Agent' => 'curl/7.52.1');
#         $sock->write_request(GET => "/$path", 'User-Agent' => 'Wget/1.19.4');
#           printf($sock "GET /$path HTTP/1.1\n");
#           printf($sock "User-Agent: Wget/1.19.4 (linux-gnu)\n");
#           printf($sock "Accept: */*\n");
#           printf($sock "Accept-Encoding: identity\n");
#           printf($sock "Host: $host\n");
#           printf($sock "Connection: Keep-Alive\n\n");
#           printf("GET /$path HTTP/1.1\n");
#           printf("User-Agent: Wget/1.19.4 (linux-gnu)\n");
#           printf("Accept: */*\n");
#           printf("Accept-Encoding: identity\n");
#           printf("Host: $host\n");
#           printf("Connection: Keep-Alive\n\n");
#           printf("-------[done]-----\n");
      };

      if($@) {                                   # something went wrong?
         $$prog{socket_closed} = 1;
         $$prog{socket_buffer} = [ "#-1 PAGE LOAD FAILURE" ];
         return 1;
      }
   
      @connected{$sock} = {                      # add to mush sockets list
         obj_id    => $$self{obj_id},
         sock      => $sock,
         raw       => 1,
         hostname  => $1,
         port      => 80,
         loggedin  => 0,
         opened    => time(),
         enactor   => $self,
         prog      => $prog,
      };
   
      # set how socket data will be handled - i.e. @info{io}
      @{@connected{$sock}}{raw} = 2;
   
      $readable->add($sock);                                # add to listener
      return 1;
   }
}


#
# fun_args
#    Return all the arguements passed into the calling function.
#
sub fun_args
{
   my ($self,$prog) = (shift,shift);
   my @result;

   my $delim = evaluate($self,$prog,shift);
   $delim = " " if($delim eq undef);

   for my $i ( sort {$a <=> $b} grep {/^\d+$/} keys %{$$prog{var}}) {
      if(@{$$prog{var}} ne undef) {
         push(@result,@{$$prog{var}}{$i});
      }
   }

   return join($delim,@result);
}

#
# fun_shift
#    Remove an item from the begining of the list (%0 .. %999).
#
sub fun_shift
{
   my ($self,$prog) = (shift,shift);
   my $result;

   for my $i ( sort {$a <=> $b} grep {/^\d+$/} keys %{$$prog{var}}) {
      $result = @{$$prog{var}}{$i} if($i == 0);
      @{$$prog{var}}{$i} = @{$$prog{var}}{$i+1};
   }
   return $result;
}

#
# fun_unshift
#    Add an item to the begining of the list (%0 .. %999).
#
sub fun_unshift
{
   my ($self,$prog) = (shift,shift);
   my $result;

   for my $i ( reverse sort {$a <=> $b} grep {/^\d+$/} keys %{$$prog{var}}) {
      @{$$prog{var}}{$i+1} = @{$$prog{var}}{$i};
   }

   @{$$prog{var}}{0} = shift;
   return undef;
}

#
# fun_pop
#    Remove an item from the end of the list (%0 .. %999).
#
sub fun_pop
{
   my ($self,$prog) = (shift,shift);

   # search for last position
   for my $i (sort {$b <=> $a} grep {/^\d+$/} keys %{$$prog{var}}) {
      if(@{$$prog{var}}{$i} ne undef) {
         my $result = @{$$prog{var}}{$i};
         delete @{$$prog{var}}{$i};
         return $result;
      }
   }
   return undef;
}

#
# fun_push
#    Add an item to the end of the list (%0 .. %999).
#
sub fun_push
{
   my ($self,$prog) = (shift,shift);

   my $value = evaluate($self,$prog,shift);

   for my $i (sort {$b <=> $a} grep {/^\d+$/} keys %{$$prog{var}}) {
      if(@{$$prog{var}}{$i} ne undef) {
         @{$$prog{var}}{$i+1} = $value;
         return undef;
      }
   }
   @{$$prog{var}}{0} = $value;
   return undef;
}

#
# ord
#    Returns the ASCII numberical value of the first character.
#
sub fun_ord
{
   my ($self,$prog) = (shift,shift);

   return ord(substr(shift,0,1));
}

#
# chr
#    Returns the ASCII numberical value of the first character.
#
sub fun_chr
{
   my ($self,$prog) = (shift,shift);

   my $num = evaluate($self,$prog,shift);

   if(hasflag($self,"WIZARD")) { 
      return chr($num);
   } elsif(($num > 31 && $num < 127) || $num == 11 || $num == 13) {
      return chr($num);
   } else {
      return "!";
   } 
}


sub fun_invocation
{
   return "#-1 FUNCTION INVOCATION LIMIT HIT";
}

sub fun_controls
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1,2) ||
     return "#-1 FUNCTION (CONTROLS) EXPECTS 2 ARGUMENTS";

   my $obj = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 ARG1 NOT FOUND";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) || 
      return "#-1 ARG2 NOT FOUND";

   return controls($obj,$target);
}

sub fun_max
{
   my ($self,$prog,@list) = @_;
   my $max;

   for my $i (@list) {
      my $number = evaluate($self,$prog,$i);

      if($number !~ /^\s*(\d+)\s*$/) { # treat like zero
         $number = 0;
      }
      $max = $number if($number > $max || $max eq undef);
   }

   if($max eq undef) {
      return "#-1 FUNCTION (MAX) EXPECTS BETWEEN 1 AND 100 ARGUMENTS";
   } else {
      return $max;
   }
}
#
# fun_convsecs
#    Convert number of seconds from epoch to a readable date
#
sub fun_convsecs
{
    my ($self,$prog) = (shift,shift);
 
    good_args($#_,1) ||
       return "#-1 FUNCTION (CONVSECS) EXPECTS 1 ARGUMENT";

    my $txt = evaluate($self,$prog,shift);

    if($txt =~ /^\s*(\d+)\s*$/) {
       return scalar localtime($1);
    } else {
       return "#-1 INVALID SECONDS";
    }
}

sub fun_find
{
    my ($self,$prog) = (shift,shift);

    good_args($#_,1) ||
       return "#-1 FUNCTION (CONVSECS) EXPECTS 1 ARGUMENT";

    my $obj = find($self,$prog,evaluate($self,$prog,shift));

    if($obj ne undef) {
       return $$obj{obj_id};
    } else {
       return "#-1 UNFOUND OBJECT";
    }
}

sub fun_min
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $min;

   good_args($#_,1 .. 100) ||
     return "#-1 FUNCTION (MIN) EXPECTS 1 AND 100 ARGUMENTS";

   while($#_ >= 0) {
      my $txt = evaluate($self,$prog,shift);

      if($txt !~ /^\s*-{0,1}\d+\s*$/) {           # emulate mush behavior
         $min = 0 if ($min > 0 || $min eq undef);
      } elsif($min eq undef || $min > $txt) {
         $min = $txt;
      }
   }
   return $min;
}

sub fun_fold
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my ($count,$atr,$last,$zero,$one);

   good_args($#_,2,3,4) ||
     return "#-1 FUNCTION (FOLD) EXPECTS 2 TO 3 ARGUMENTS";

   my $atr = evaluate($self,$prog,shift);
   my $list = evaluate($self,$prog,shift);
   my $base = evaluate($self,$prog,shift);
   my $idelim = evaluate($self,$prog,shift);

   my $prev = get_digit_variables($prog);

   my $atr = fun_get($self,$prog,$atr);
   return $atr if($atr eq undef || $atr =~ /^#-1 /);

   my (@list) = safe_split($list,$idelim);
   while($#list >= 0) {
      if($count eq undef && $base ne undef) {
         ($zero,$one) = ($base,shift(@list));
      } elsif($count eq undef) {
         ($zero,$one) = (shift(@list),shift(@list));
      } else {
         ($zero,$one) = ($last,shift(@list));
      }

      set_digit_variables($self,$prog,"",$zero,$one);
      $last  = evaluate($self,$prog,$atr);
      $count++;
   }

   set_digit_variables($self,$prog,"",$prev);

   return $last;
}


sub fun_idle
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my $idle;

   good_args($#_,1) ||
     return "#-1 FUNCTION (IDLE) EXPECTS 1 ARGUMENT";

   my $name = evaluate($self,$prog,shift);

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
   my @out;

   while($#_ >= 0) {
      my $str = ansi_init(evaluate($self,$prog,shift));

      for my $i (0 .. $#{$$str{ch}}) {
         @{$$str{ch}}[$i] = uc(@{$$str{ch}}[$i]);
      }
      push(@out,ansi_string($str,1));
   }
   return join(',',@out);
}

sub fun_sort
{
   my ($self,$prog,$txt) = (obj(shift),shift);

   return join(' ',sort split(" ",evaluate($self,$prog,shift)));
}

sub fun_base64
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (BASE64) EXPECTS 2 ARGUMENT ($#_)";

   my $type = evaluate($self,$prog,shift);
   my $txt = evaluate($self,$prog,shift);

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

   my $txt = evaluate($self,$prog,shift);

   return uncompress($txt);
}

sub fun_reverse
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (REVERSE) EXPECTS 1 ARGUMENT";

   return reverse evaluate($self,$prog,shift);
}

sub fun_revwords
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (REVWORDS) EXPECTS 1 ARGUMENT";

   return join(' ',reverse split(/\s+/,evaluate($self,$prog,shift)));
}

sub fun_telnet
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (TELNET_OPEN) EXPECTS 1 ARGUMENT";

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
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (RAND) EXPECTS 1 ARGUMENT";

   my $txt = evaluate($self,$prog,shift);

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

sub isint
{
   my $num = shift;

   return ($num =~ /^\s*(\d+)\s*$/) ? 1 : 0;
}

sub fun_lrand
{
   my ($self,$prog) = (obj(shift),shift);
   my @result;

   good_args($#_,3,4) ||
     return "#-1 FUNCTION (LRAND) EXPECTS 3 OR 4 ARGUMENTS";

   my $lower = evaluate($self,$prog,shift);
   my $upper = evaluate($self,$prog,shift);
   my $count = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

   $lower = 0 if(!isint($lower));
   $upper = 0 if(!isint($upper));
   $delim = " " if $delim eq undef;

   if(!isint($count)) {
      $count = 0;
   } elsif($count > 4000) {                              # set upper limit
      $count = 4000;
   }

   my $diff = $upper - $lower;

   for my $i (1 .. $count) {
      push(@result,int(rand($diff) + $lower));
   }

   return join("$delim",@result);
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
   my ($self,$prog) = (obj(shift),shift);
   my @result;

   good_args($#_,1) ||
     return "#-1 FUNCTION (LEXITS) EXPECTS 1 ARGUMENT";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   my $perm = hasflag($self,"WIZARD");

   for my $exit (lexits($target)) {
      if($perm || !hasflag($exit,"DARK")) {
         push(@result,"#" . $$exit{obj_id});
      }
   }
   return join(' ',@result);
}

sub fun_lcon
{
   my ($self,$prog) = (obj(shift),shift);
   my @result;

   good_args($#_,1) ||
     return "#-1 FUNCTION (LCON) EXPECTS 1 ARGUMENT";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   my $perm = hasflag($self,"WIZARD");

   # object can lcon() its current location or if it owns the object
   if(!($perm || owner($target) == owner($self) || loc($self) == loc($target))){
      return "#-1";
   }

   for my $obj (lcon($target)) {
      push(@result,"#" . $$obj{obj_id}) if($perm || !hasflag($obj,"DARK"));
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
   my ($self,$prog) = (shift,shift);
   my (%none, $hash, %tmp, $match, $cmd,$arg);

   good_args($#_,1) ||
      return "#-1 FUNCTION (RUN) REQUIRES 1 ARGUMENT";

   my $txt = evaluate($self,$prog,shift);

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
   my ($start,$pos,@result) = (0,0);
   my $orig = $txt;

   if($delim =~ /^\s*\n\s*/m) {
      $delim = "\n";
   } else {
      $delim =~ s/^\s+|\s+$//g;
 
      if($delim eq " " || $delim eq undef) {
#         $txt =~ s/\s+/ /g;
#         $txt =~ s/^\s+|\s+$//g;
         $delim = " ";
      }
   }

   my $txt = ansi_init($txt);
   my $size = ansi_length($txt);
   my $dsize = ansi_length($delim);
   for($pos=0;$pos < $size;$pos++) {
      if(ansi_substr($txt,$pos,$dsize) eq $delim) {
         push(@result,ansi_substr($txt,$start,$pos-$start));
         $result[$#result] =~ s/^\s+|\s+$//g if($delim eq " ");
         $start = $pos + $dsize;
      }
   }

   push(@result,ansi_substr($txt,$start,$size)) if($start < $size);
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

   for my $i (split(/ /,evaluate($self,$prog,@_[0]))) {
       $i =~ s/^\s+|\s+$//g;
       @list{$i} = 1;
   }

   for my $i (split(/ /,evaluate($self,$prog,@_[1]))) {
      $i =~ s/^\s+|\s+$//g;
      @out{$i} = 1 if(defined @list{$i});
  }
  return join(' ',sort keys %out);
}


sub fun_lwho
{
   my ($self,$prog) = (shift,shift);
   my @who;

   good_args($#_,0,1) ||
      return "#-1 FUNCTION (LWHO) EXPECTS 0 OR 1 ARGUMENTS-$#_";

   my $flag = evaluate($self,$prog,shift);

   if($flag ne undef && $flag !~ /^\s*(0|1)\s*$/) {
      return "#-1 ARGUMENT 1 SHOULD BE EITHER 0 OR 1"; 
   }
   
   for my $key (keys %connected) {
      my $hash = @connected{$key};
      if($$hash{raw} != 0||!defined $$hash{obj_id}||$$hash{obj_id} eq undef) {
         next;
      }
      if($flag) {
         push(@who,
              "#" . 
              @{@connected{$key}}{obj_id} . ":" .
              @{@connected{$key}}{port}
             );
      } else {
         push(@who,"#" . @{@connected{$key}}{obj_id});
      }
   }
   return join(' ',@who);
}


sub fun_lcstr
{
   my ($self,$prog) = (shift,shift);
   my @out;

   good_args($#_,1) ||
     return "#-1 FUNCTION (LCSTR) EXPECTS 1 ARGUMENT ($#_)";

   while($#_ >= 0) {
      my $str = ansi_init(evaluate($self,$prog,shift));

      for my $i (0 .. $#{$$str{ch}}) {
         @{$$str{ch}}[$i] = lc(@{$$str{ch}}[$i]);
      }
      push(@out,ansi_string($str,1));
   }

   return join(',',@out);
}

sub fun_home
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,0,1) ||
      return "#-1 FUNCTION (HOME) EXPECT 0 OR 1 ARGUMENT";

   if(@_[0] eq undef) {
      return home($self);
   }

   my $target = find($self,$prog,evaluate($self,$prog,shift));

   if($target eq undef) {
      return "#-1 NOT FOUND";
   } elsif(hasflag($target,"EXIT")) {
      return "#" . loc($target);
   } else {
      return "#" . home($target);
   }
}

#
# capitalize the provided string
#
sub fun_capstr
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (SQUISH) EXPECTS 1 ARGUMENT ($#_)";

    return ucfirst(evaluate($self,$prog,shift));
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

   my $txt = evaluate($self,$prog,shift);

   $txt =~ s/^\s+|\s+$//g;
   $txt =~ s/\s+/ /g;
   return $txt;
}

sub fun_eq
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (EQ) EXPECTS 2 ARGUMENTS";

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   $one =~ s/^\s+|\s+$//g;
   $two =~ s/^\s+|\s+$//g;
   return ($one eq $two) ? 1 : 0;
}

sub fun_loc
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (LOC) EXPECTS 1 ARGUMENT $#_";

   my $foo = $_[0];
   my $target = find($self,$prog,evaluate($self,$prog,shift));

   if($target eq undef) {
      return "#-1 NOT FOUND";
   } elsif(hasflag($target,"ROOM")) {           # rooms can't be anywhere
      return "#-1";
   } elsif(hasflag($target,"EXIT")) {
      my $dest = dest($target);
      if($dest eq undef) {
         return "#-1";
      } else {
         return "#" . dest($target);
      }
   } else {
      return "#" . loc($target);
   }
}

sub fun_hasflag
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (HASFLAG) EXPECTS 2 ARGUMENTS";

   if((my $target = find($self,$prog,evaluate($self,$prog,shift))) ne undef) {
      return hasflag($target,shift);
   } else {
      return "#-1 Unknown Object";
   }
}

sub fun_gt
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (GT) EXPECTS 2 ARGUMENTS";

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   return ($one > $two) ? 1 : 0;
}

sub fun_gte
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (GTE) EXPECTS 2 ARGUMENTS";

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   return ($one >= $two) ? 1 : 0;
}

sub fun_lt
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (LT) EXPECTS 2 ARGUMENTS";

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   return ($one < $two) ? 1 : 0;
}

sub fun_lte
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (LT) EXPECTS 2 ARGUMENTS";

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   return ($one <= $two) ? 1 : 0;
}

sub fun_or
{
   my ($self,$prog) = (shift,shift);

   while($#_ >= 0) {
      my $val = evaluate($self,$prog,shift);
      return 1 if($val);
   }
   return 0;
}


sub fun_isnum
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (ISNUM) EXPECTS 1 ARGUMENT";

   my $val = evaluate($self,$prog,shift);

   return looks_like_number(ansi_remove($val)) ? 1 : 0;
}

sub fun_lnum
{
   my ($self,$prog) = (shift,shift);
   my @result;

   good_args($#_,1,2,3,4) ||
      return "#-1 FUNCTION (LNUM) EXPECTS 1,2,3 OR 4 ARGUMENTS";

   my $start  = evaluate($self,$prog,shift);
   my $end    = evaluate($self,$prog,shift);
   my $odelim = evaluate($self,$prog,shift);
   my $step   = evaluate($self,$prog,shift);

   if($end eq undef && $start ne undef) {
      $end = $start - 1;
      $start = 0;
   }
   $start = 0 if $start eq undef;
   $end = 0 if $end eq undef;
   $odelim = " " if $odelim eq undef;
   $step = 1 if $step eq undef;

   if($start <= $end) {
      for(my $i=$start;$i <= $end && $#result < 2000;$i += $step) {
         push(@result,$i);
      }
   } else {
      for(my $i=$start;$i >= $end && $#result < 2000;$i -= $step) {
         push(@result,$i);
      }
   }

   return join($odelim,@result);
}

sub fun_and
{
   my ($self,$prog) = (shift,shift);

   while($#_ >= 0) {
      my $num = evaluate($self,$prog,shift);
      return 0 if($num eq 0);
   }
   return 1;
}

sub fun_not
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NOT) EXPECTS 1 ARGUMENTS";

   return (! evaluate($self,$prog,shift)) ? 1 : 0;
}


sub fun_words
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1,2) ||
      return "#-1 FUNCTION (WORDS) EXPECTS 1 OR 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

   return scalar(safe_split(ansi_remove($txt),
                            ($delim eq undef) ? " " : $delim
                           )
                );
}

#
# fun_match
#    Match a string against a pattern with an optional delimiter.
#
sub fun_match
{
   my ($self,$prog) = (shift,shift);
   my $count = 1;

   good_args($#_,1,2,3) ||
      return "#-1 FUNCTION (MATCH) EXPECTS 1, 2 OR 3 ARGUMENTS";

   my $txt   = evaluate($self,$prog,shift);
   my $pat   = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

   $delim = " " if $delim eq undef; 
   $pat = glob2re($pat);

   for my $word (safe_split(ansi_remove($txt),$delim)) {
      return $count if($word =~ /$pat/);
      $count++;
   }
   return 0;
}

#
# fun_strmatch
#    Match a string against a pattern with an optional delimiter.
#
sub fun_strmatch
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (STRMATCH) EXPECTS 2 ARGUMENTS";

   my $txt   = evaluate($self,$prog,shift);
   my $pat   = evaluate($self,$prog,shift);

   $pat = glob2re($pat);

   return ($txt =~ /^$pat$/i) ? 1 : 0;
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
   my $txt = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);

   $txt = ansi_substr($txt,0,$size);

   my $len = ansi_length($txt);

   my $lpad = " " x (($size - $len) / 2);

   my $rpad = " " x ($size - length($lpad) - $len);
   
   return $lpad . $txt . $rpad;
}

sub fun_switch
{
   my ($self,$prog) = (shift,shift);
   my $debug = 0;

   my $first = single_line(evaluate($self,$prog,trim(shift)));

   while($#_ >= 0) {
      if($#_ >= 1) {
         my $txt = single_line(ansi_remove(evaluate($self,$prog,trim(shift))));
         my $cmd = shift;

         if($txt =~ /^\s*(<|>)\s*/) {
             if($1 eq ">" && $first > $' || $1 eq "<" && $first < $') {
                return evaluate($self,$prog,$cmd);
             }
         } else {
            my @wild = ansi_match($first,$txt);
            if($#wild >=0) {
               my $prev = get_digit_variables($prog);
               set_digit_variables($self,$prog,"m",@wild[0..9]);
               my $result = evaluate($self,$prog,$cmd);
               set_digit_variables($self,$prog,"m",$prev);
               return $result;
            }
         }
      } else {                                      # handle switch() default
         return evaluate($self,$prog,shift);
      }
   }
}

sub fun_member
{
   my ($self,$prog) = (shift,shift);
   my $i = 1;

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (MEMBER) EXPECTS 2 OR 3 ARGUMENTS";

   my $txt   = evaluate($self,$prog,shift);
   my $word  = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

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

   good_args($#_,4) ||
      return "#-1 FUNCTION (INDEX) EXPECTS 4 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);
   my $first = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);
   my $i = 1;

   if(!looks_like_number($first)) {
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
   my $i = 1;

   if(!good_args($#_,3,4,5)) {
      return "#-1 FUNCTION (REPLACE) EXPECTS 3, 4 or 5 ARGUMENTS";
   }

   my $txt = evaluate($self,$prog,shift);
   my $positions = evaluate($self,$prog,shift);
   my $word = evaluate($self,$prog,shift);
   my $idelim = evaluate($self,$prog,shift);
   my $odelim = evaluate($self,$prog,shift);

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

   my $txt = evaluate($self,$prog,shift);
   my $after = evaluate($self,$prog,shift);

   my $loc = index($txt,$after);
   if($loc == -1) {
      return undef;
   } else {
      my $result = substr(evaluate($self,$prog,$txt),$loc + length($after));
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_rest
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1 .. 2) ||
      return "#-1 Function (REST) EXPECTS 1 or 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);  
   my $delim = evaluate($self,$prog,shift);  
   $delim = " " if($delim eq undef);
   my $loc = index($txt,$delim);

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


   good_args($#_,1,2) ||
      return "#-1 Function (FIRST) EXPECTS 1 or 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

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

   good_args($#_,1,2) ||
      return "#-1 Function (LAST) EXPECTS 1 or 2 ARGUMENTS";

   my $txt   = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

   if($delim eq undef || $delim eq " ") {
      $txt =~ s/^\s+|\s+$//g;
      $txt =~ s/\s+/ /g;
      $delim = " ";
   }

   my $loc = rindex($txt,$delim);

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
   my ($self,$prog) = (shift,shift);

   good_args($#_,1,2) ||
      return "#-1 Function (BEFORE) EXPECTS 1 or 2 ARGUMENTS";
 
   my $txt = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

   my $loc = index($txt,$delim);

   if($loc == -1) {
      return undef;
   } else {
      my $result = substr($txt,0,$loc);
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

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   if($two eq undef || $two == 0) {
      return "#-1 DIVIDE BY ZERO";
   } else {
      return sprintf("%d",$one / $two);
   }
}

#
# fun_fdiv
#    Divide a number
#
sub fun_fdiv
{
   my ($self,$prog) = (shift,shift);

   return "#-1 Add requires at least two arguments" if $#_ < 1;

   my $one = evaluate($self,$prog,shift);
   my $two = evaluate($self,$prog,shift);

   if($two eq undef || $two == 0) {
      return "#-1 DIVIDE BY ZERO";
   } else {
      my $result = sprintf("%.6f",$one / $two);
      $result =~ s/0+$//g;
      $result =~ s/\.$//g;
      return $result;
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
      $result += evaluate($self,$prog,@_[$i]);
   }
   return $result;
}


#
# fun_mul
#    Multiple some numbers
#
sub fun_mul
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1 .. 100) ||
      return "#-1 FUNCTION (MUL) EXPECTS BETWEEN 1 and 100 ARGUMENTS";

   my $result = evaluate($self,$prog,shift);

   while($#_ > -1) {
      $result *= evaluate($self,$prog,shift);
   }

   return $result;
}

#
# fun_sub
#    Subtract some numbers
#
sub fun_sub
{
   my ($self,$prog) = (shift,shift);

   return "#-1 Sub requires at least one argument" if $#_ < 0;

   my $result = evaluate($self,$prog,shift);

   while($#_ >= 0) {
      $result -= evaluate($self,$prog,shift);
   }
   return $result;
}


sub lord
{
   my $txt = shift;
   my @result;
#   $txt =~ s/\e/<ESC>/g;
#   return $txt;

   for my $i (0 .. (length($txt)-1)) {
      push(@result,ord(substr($txt,$i,1)));
   }
   return join(',',@result);
}

sub fun_edit
{
   my ($self,$prog) = (shift,shift);
   my ($start,$out);

   good_args($#_,3) ||
      return "#-1 FUNCTION (EDIT) EXPECTS 3 ARGUMENTS";

   my $txt  = ansi_init(evaluate($self,$prog,shift));
   my $from = trim(ansi_remove(evaluate($self,$prog,shift)));
   my $to   = evaluate($self,$prog,shift);
   my $size = ansi_length($from);

   for(my $i = 0, $start=0;$i <= $#{$$txt{ch}};$i++) {
      if(ansi_remove(ansi_substr($txt,$i,$size)) eq $from) {
         if($start ne undef || $i != $start) {
            $out .= ansi_substr($txt,$start,$i - $start);
         }
         $out .= $to;
         $i += $size;
         $start = $i;
      }
   }

   if($start ne undef or $start >= $#{$$txt{ch}}) {       # add left over chars
      $out .= ansi_substr($txt,$start,$#{$$txt{ch}} - $start + 1);
   }

   return $out;
}

sub fun_num
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NUM) EXPECTS 1 ARGUMENT";

   my $result = find($self,$prog,evaluate($self,$prog,$_[0]));
 
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
 

   if(evaluate($self,$prog,$_[0]) =~ /^\s*#(\d+)\s*$/) { 
      my $owner = owner(obj($1)) ||
         return "#-1 NOT FOUND";
      return "#" . $$owner{obj_id};
   } else {
      return "#-1 NOT FOUND";
   }
   
   my $owner = owner(obj(shift));

   return ($owner eq undef) ? "#-1" : ("#" . $$owner{obj_id});
}

sub fun_name
{
#   for my $i (0 .. $#_) {
#      printf("$i: '%s'\n",$_[$i]);
#   }
   my ($flag,$self,$prog) = (shift,shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NAME) EXPECTS 1 ARGUMENT - $#_";

   my $target = find($self,$prog,evaluate($self,$prog,shift));

   if($target eq undef) {
      return "#-1";
   } elsif(hasflag($target,"EXIT") && !$flag) {
      return first(name($target));
   } else {
     return name($target);
   }
}

sub fun_type
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (TYPE) EXPECTS 1 ARGUMENT";

   my $target= find($self,$prog,evaluate($self,$prog,$_[0])) ||
      return "#-1 NOT FOUND";

   return type($self,$prog,$target);
}

sub fun_filter
{
   my ($self,$prog) = (obj(shift),shift);
   my @result;

   good_args($#_,2,3,4) ||
      return "#-1 FUNCTION (FILTER) EXPECTS BETWEEN 2 and 4 ARGUMENTS";

   my ($obj,$atr) = meval($self,$prog,balanced_split(shift,"\/",4));
   my $list   = evaluate($self,$prog,shift);
   my $delim  = evaluate($self,$prog,shift);
   my $odelim = evaluate($self,$prog,shift);

   # TinyMUSH doesn't provide any details if there is an error.
   if($atr eq undef) {
      ($obj,$atr) = ($self,$obj);
   } elsif(($obj = find($self,$prog,$obj)) eq undef) {
      return undef;
   }

   $delim = " " if($delim eq undef);
   $odelim = " " if($odelim eq undef);

   my $value = get($obj,$atr) ||
      return undef;

   my $prev = get_digit_variables($prog);                   # save %0 .. %9

   for my $word (safe_split($list,$delim)) {
      set_digit_variables($self,$prog,"",$word);       # update to new values
      if(evaluate($self,$prog,$value)) {
         push(@result,$word);
      }
   }

   set_digit_variables($self,$prog,"",$prev);            # restore %0 .. %9

   return join($odelim,@result);
}

sub fun_u
{
   my ($self,$prog) = (shift,shift);

   my $txt = evaluate($self,$prog,shift);
   my ($obj,$attr,@arg);

   for my $i (0 .. $#_) {
      @arg[$i] = evaluate($self,$prog,$_[$i]);
   } 

   if($txt =~ /\//) {                    # input in object/attribute format?
      ($obj,$attr) = (find($self,$prog,$`,"LOCAL"),$');
   } else {                                  # nope, just contains attribute
      ($obj,$attr) = ($self,$txt);
   }

   if($obj eq undef) {
      return "#-1 Unknown object";
   } elsif(!(controls($self,$obj) || 
             hasflag($obj,"VISUAL") || 
             atr_hasflag($obj,$attr,"VISUAL")
          )) {
      return "#-1 PerMISSion Denied";
   }

   my $prev = get_digit_variables($prog);                   # save %0 .. %9
   set_digit_variables($self,$prog,"",@arg);          # update to new values

   printf("U[%s/%s]: '%s'\n",$$obj{obj_id},$attr,single_line(get($obj,$attr)));
   my $result = evaluate($self,$prog,single_line(get($obj,$attr)));

   set_digit_variables($self,$prog,"",$prev);            # restore %0 .. %9
   return $result;
}


sub fun_get
{
   my ($self,$prog,$txt) = (shift,shift,shift);
   my ($obj,$atr);

   if($txt =~ /\//) {
      ($obj,$atr) = (evaluate($self,$prog,$`),evaluate($self,$prog,$'));
   } else {
      ($obj,$atr) = (evaluate($self,$prog,$txt),evaluate($self,$prog,shift));
   }

   my $target = find($self,$prog,$obj);

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!(controls($self,$target) ||
      hasflag($target,"VISUAL") || atr_hasflag($target,$atr,"VISUAL"))) {
      return "#-1 Permission Denied ($$self{obj_id} -> $$target{obj_id}/$atr)";
   } 

   if($atr =~ /^(last|last_page|last_created_date|create_by|last_whisper)$/) {
      return get($target,"obj_$atr");
   } elsif(lc($atr) eq "lastsite") {
      return short_hn(lastsite($target));
   } else {
      return get($target,$atr);
   }
}


#
# fun_v
#    Return a un-evaluated attribute
#
sub fun_v
{
   my ($self,$prog,$txt) = (shift,shift,shift);

   return get($self,evaluate($self,$prog,$txt));
}

sub fun_setq
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (SETQ) EXPECTS 2 ARGUMENTS";

   my $register = lc(trim(evaluate($self,$prog,shift)));

   if($register !~ /^\s*([0-9a-z])\s*$/) {
      return "#-1 INVALID GLOBAL REGISTER"
   }

   my $result = evaluate($self,$prog,shift);
   @{$$prog{var}}{"setq_$register"} = $result;
   return undef;
}

sub fun_r
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (R) EXPECTS 1 ARGUMENTS";

   my $register = trim(evaluate($self,$prog,shift));

   if($register !~ /^\s*(0|1|2|3|4|5|6|7|8|9)\s*$/) {
      return "#-1 INVALID GLOBAL REGISTER"
   }
   
   if(defined @{$$prog{var}}{"setq_$register"}) {
      return @{$$prog{var}}{"setq_$register"};
   } else {
      return undef;
   }
}

sub fun_extract
{
   my ($self,$prog) = (shift,shift);

   my $txt    = evaluate($self,$prog,shift);
   my $first  = evaluate($self,$prog,shift);
   my $length = evaluate($self,$prog,shift);
   my $idelim = evaluate($self,$prog,shift);
   my $odelim = evaluate($self,$prog,shift);

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
   if($first + $length > $#list) {
      $length = $#list - $first;
   } else {
      $length--;
   }
   return join($odelim,@list[$first .. ($first+$length)]);
}


sub fun_remove
{
   my ($self,$prog) = (shift,shift);
   my (%remove, @result);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (REMOVE) EXPECTS 2 OR 3 ARGUMENTS";

   my $list  = evaluate($self,$prog,shift);
   my $words = evaluate($self,$prog,shift);
   my $delim = evaluate($self,$prog,shift);

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
   my ($self,$prog) = (shift,shift);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (RJUST) EXPECTS 2 OR 3 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);
   my $fill = evaluate($self,$prog,shift);
#   printf("%s",print_var($$prog{var}));

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
   my ($self,$prog) = (shift,shift);


   good_args($#_,2,3) ||
      return "#-1 FUNCTION (LJUST) EXPECTS 2 OR 3 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);
   my $fill = evaluate($self,$prog,shift);
   $fill = " " if($fill =~ /^$/);

   if($size =~ /^\s*$/) {
      return $txt;
   } elsif($size !~ /^\s*(\d+)\s*$/) {
      return "#-1 ljust expects a numeric value for the second argument";
   } else {
      my $sub = ansi_substr(evaluate($self,$prog,$txt),0,$size);
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

   good_args($#_,2,3) ||
      return "#-1 Substr expects 2 - 3 arguments";

   my $txt = evaluate($self,$prog,shift);
   my $start = evaluate($self,$prog,shift);
   my $end = evaluate($self,$prog,shift);

   if($start !~ /^\s*\d+\s*/) {
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

   my $txt = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);

   if($size !~ /^\s*\d+\s*/) {
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT TO BE NUMERIC";
   }

   return ansi_substr($txt,length($txt) - $size,$size);
}

sub fun_left
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT";

   my $txt = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);

   if($size !~ /^\s*\d+\s*/) {
     return "#-1 FUNCTION (RIGHT) EXPECTS 2 ARGUMENT TO BE NUMERIC";
   }

   return ansi_substr($txt,0,$size);
}

#
# fun_input
#    Check to see if there is any input in the specified input buffer
#    variable. If there is, return the data or return #-1 No Data Found
# 
sub fun_input
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
  

   if($txt =~ /^\s*last\s*$/i) {
      if(hasflag($self,"WIZARD")) {
         return necho(self => $self,
                      prog => $prog,
                      source => [ "%s", @info{connected_raw}  ],
                     );
      } else {
         return "#-1 PERMISSION DENIED";
      }
   }
   if(!defined $$prog{socket_id} && !defined $$prog{socket_buffer}) {
      return "#-1 Connection Closed";
   } elsif(defined $$prog{socket_id} && !defined $$prog{socket_buffer}) {
      $$prog{idle} = 1;                                    # hint to queue
      return "#-1 No data found";
   }

   my $input = $$prog{socket_buffer};

   # check if there is any buffered data and return it.
   # if not, the socket could have closed
   if($#$input == -1) { 
      if(defined $$prog{socket_id} &&
         defined @connected{$$prog{socket_id}}) {
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
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     "#-1 FUNCTION (FLAGS) EXPECTS 1 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);

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
    my ($self,$prog) = (shift,shift);
    
    good_args($#_,0,1) ||
       return "#-1 Space expects 0 or 1 values";

    my $count = evaluate($self,$prog,shift);

    if($count =~ /^\s*$/) {
       $count = 1;
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

    good_args($#_,2) ||
       return "#-1 FUNCTION (REPEAT) EXPECTS 2 ARGUMENTS";

    my $txt = evaluate($self,$prog,shift);
    my $count = evaluate($self,$prog,shift);

    if($count !~ /^\s*\d+\s*/) {
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
   my $out;

   good_args($#_,1 .. 100) ||
      return "#-1 FUNCTION (CAT) EXPECTS BETWEEN 1 AND 100 ARGS";

   return join(" ",@_);
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
   my ($obj,$atr,@list);

   my $txt = evaluate($self,$prog,shift);
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

      for my $attr (grep {!/^obj_/i} lattr($target)) {
         push(@list,uc($attr)) if($pat eq undef || $attr =~ /$pat/i);
      }
   } else {
      for my $attr (@{sql("  select atr_name " .   # query for attribute names
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
# fun_itext
#    Returns the current value of iter() by depth.
#
sub fun_itext
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,0,1) ||
     return "#-1 FUNCTION (ITEXT) EXPECTS 0 OR 1 ARGUMENTS";

   return if(!defined $$prog{iter_stack});                 # not in iter()

   my $pos = evaluate($self,$prog,shift);

   if($pos eq undef) {
      $pos = 0;
   } elsif(!isint($pos)) {
      return "#-1 INVALID NUMBER";
   }

   my $stack = $$prog{iter_stack};

   return if($pos >= $#$stack+1);                  # request is to deep and
                                                 # MUSH doesn't return error

   return @{$$stack[$#$stack - $pos]}{val};
}

#
# fun_inum
#    Returns the positional count in the list of where iter() currently
#    is by depth.
#
sub fun_inum
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,0,1) ||
     return "#-1 FUNCTION (INUM) EXPECTS 0 OR 1 ARGUMENTS";

   return if(!defined $$prog{iter_stack});                 # not in iter()

   my $pos = evaluate($self,$prog,shift);

   if($pos eq undef) {
      $pos = 0;
   } elsif(!isint($pos)) {
      return "#-1 INVALID NUMBER";
   }

   my $stack = $$prog{iter_stack};

   return if($pos >= $#$stack+1);                  # request is to deep and
                                                 # MUSH doesn't return error

   return @{$$stack[$#$stack - $pos]}{pos};
}

sub fun_ilev
{
   for my $i (0 .. $#_) {
      printf("$i : '%s'\n",$_[$i]);
   }
   my ($self,$prog) = (shift,shift);

   good_args($#_,0) ||
     return "#-1 FUNCTION (ILEV) EXPECTS 0 ARGUMENTS - $#_";

   return -1 if(!defined $$prog{iter_stack});                 # not in iter()

   return $#{$$prog{iter_stack}};
}

#
# fun_iter
#
sub fun_iter
{
   my ($self,$prog) = (shift,shift);
   my $count = 0;

   good_args($#_,2 .. 4) ||
     return "#-1 FUNCTION (ITER) EXPECTS 2 AND 4 ARGUMENTS";

   my ($list,$txt) = ($_[0],$_[1]);
   my $idelim = evaluate($self,$prog,$_[2]);
   $idelim = " " if($idelim eq undef);
   my $odelim = ($#_ < 3) ? " " : evaluate($self,$prog,$_[3]);

   if($odelim =~ /^\s*\@\@\s*$/) {
      $odelim = "";
   }

   my @result;

   $$prog{iter_stack} = [] if(!defined $$prog{iter_stack});
   my $loc = $#{$$prog{iter_stack}} + 1;
   for my $item (safe_split(evaluate($self,$prog,$list),$idelim)) {
       @{$$prog{iter_stack}}[$loc] = { val => $item, pos => ++$count };
       my $new = $txt;
       $new =~ s/##/$item/g;
       push(@result,evaluate($self,$prog,$new));
   }
   delete @{$$prog{iter_stack}}[$loc];

   return join($odelim,@result);
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
   my ($self,$prog,$name,$before,$flag) = (shift,shift,lc(shift),shift,shift);

   if(!defined @fun{$name} && !$flag) {
      con("undefined function '%s'\n",$name);
      con("                   '%s'\n",ansi_debug($before));
      con("%s",code("long"));
   }
   return (defined @fun{$name}) ? $name: "huh";
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

   if($$prog{function_command}++ > @info{"conf.function_invocation_limit"}) {
      return undef; # "#-1 FUNCTION INVOCATION LIMIT HIT";
   }
   $$prog{function}++;

   my @array = balanced_split($txt,",",$type);
   return undef if($#array == -1);

   # type 1: expect ending ]
   # type 2: expect ending ) and nothing else
   if(($type == 1 && @array[0] =~ /^ *]/) ||
      ($type == 2 && @array[0] =~ /^\s*$/)) {
      @array[0] = $';                              # strip ending ] if there
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
# types:
#    1 : function split?
#    2 : split until end of function?
#    3 : split at delim
#    4 : split until delim, delim not included in result
#
sub balanced_split
{
   my ($txt,$delim,$type,$debug) = @_;
   my ($last,$i,@stack,@depth,$ch,$buf) = (0,-1);

   my $size = length($txt);
   while(++$i < $size) {
      $ch = substr($txt,$i,1);

      if($ch eq "\e" && substr($txt,$i,20) =~ /^\e\[([\d;]*)([a-zA-Z])/) {
         $i += length("x$1$2");                       # move 1 char short
         $buf .= "\e\[$1$2";
         next;
      } elsif($ch eq "\\") {
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
               if($type == 4) {                        # found delim, done
                  return $buf, substr($txt,$i+1);
               } else {
                  push(@stack,$buf);
                  $last = $i+1;
                  $buf = undef;
               }
            } elsif($type <= 2 && $ch eq ")") {                   # func end
               push(@stack,$buf) if($buf !~ /^\s*$/);
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

   if($type == 3 || $type == 4) {
      push(@stack,substr($txt,$last)) if(substr($txt,$last) !~ /^\s*$/);
      return @stack;
   } else {
      unshift(@stack,substr($txt,$last));
      return ($#depth != -1) ? undef : @stack;
   }
}

sub balanced_split_old
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
               if($type == 4) {                        # found delim, done
                  return $buf, substr($txt,$i+1);
               } else {
                  push(@stack,$buf);
                  $last = $i+1;
                  $buf = undef;
               }
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

   if($type == 3 || $type == 4) {
      push(@stack,substr($txt,$last)) if(substr($txt,$last) !~ /^\s*$/);
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
   my ($self,$prog,$fun,$args,$result) = @_;
   return;

   con("think [switch(%s(%s),%s,,{WRONG %s(%s) -> %s})]\n",
      $fun,
      evaluate_substitutions($self,$prog,$args),
      evaluate_substitutions($self,$prog,$result),
      $fun,
      evaluate_substitutions($self,$prog,$args),
      evaluate_substitutions($self,$prog,$result)
      );
#   if($result =~ /^\s*$/) {
#      con("FUN: '%s(%s) returned undef\n",$fun,$args);
#   }
#   return;
#   if($args !~ /(v|u|get|r)\(/i && $fun !~ /^(v|u|get|r)$/) {
#    my $eval_args = evaluate($self,$prog,$args);
#      con("think [switch(%s(%s),%s,,{WRONG %s(%s) -> %s})]\n",
#          $fun,$eval_args,$result,$fun,$eval_args,$result);
##   }
}

sub meval
{
   my ($self,$prog,@args) = @_;
   my @result;

   for my $i (0 .. $#args) {
      push(@result,evaluate($self,$prog,@args[$i]));
   }

   return @result;
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
   return if(!valid_dbref($self));
   if($txt =~ /^\s*([a-zA-Z_0-9]+)\((.*)\)\s*$/s) {
      my $fun = fun_lookup($self,$prog,$1,undef,1);
      if($fun ne "huh") {                   # not a function, do not evaluate
         my $result = parse_function($self,$prog,$fun,"$2)",2);
         if($result ne undef) {
            shift(@$result);
            con("undefined function: '%s'\n",$fun) if($fun eq "huh");

            my $start = Time::HiRes::gettimeofday();
            my $r=&{@fun{$fun}}($self,$prog,@$result);
            $$prog{function_duration} +=Time::HiRes::gettimeofday()-$start;
            $$prog{"fun_$fun"}++;
         
            script($self,$prog,$fun,join(',',@$result),$r);

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
   while($txt =~ /([\\]*)\[([a-zA-Z_0-9]+)\(/s && ord(substr($`,-1)) ne 27) {
      my ($esc,$before,$after,$unmod) = ($1,$`,$',$2);
      my $fun = fun_lookup($self,$prog,$unmod,$before);
      $out .= evaluate_substitutions($self,$prog,$before);
      $out .= "\\" x (length($esc) / 2);

      if(length($esc) % 2 == 0) {
         my $result = parse_function($self,$prog,$fun,$',1);

         if($result eq undef) {
            $txt = $after;
            $out .= "[$fun(";
         } else {                                    # good function, run it
            $txt = shift(@$result);

            my $start = Time::HiRes::gettimeofday();
            my $r = &{@fun{$fun}}($self,$prog,@$result);
            $$prog{function_duration} +=Time::HiRes::gettimeofday()-$start;

            script($self,$prog,$fun,join(',',@$result),$r);
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

   my $addr = server_hostname($new);

   $readable->add($new);

   @http{$new} = { sock => $new,
                   data => {},
                   ip   => $addr,
                 };

#   web("   %s\@web Connect\n",@{@http{$new}}{ip});
}

sub http_disconnect
{
   my $s = shift;

   delete @http{$s};
   $readable->remove($s);
   $s->close;

}


#
# manage_httpd_bans
#    If a client requests an invalid page, assume its not a typo and instead
#    assume they are hack attempts. I.E. Ban all hosts after X invalid
#    attempts for an hour.
#
sub manage_httpd_bans
{
   my $sock = shift;
   my $count;

   # setup structures
   @info{httpd_ban} = {} if(!defined @info{httpd_ban}); 
   @info{httpd_invalid_data} = {} if(!defined @info{httpd_invalid_data});

   # new invalid request has happened, log it.
   if($sock ne undef) {
      my $ip = @http{$sock}->{ip};
      if(!defined @{@http{$sock}}{$ip}) {
         @{@http{$sock}}{$ip} = {};
      }
      @info{httpd_invalid_data}->{$ip}->{time()}++;
   }

   #
   # clean up / manage existing ban data
   #
   if(!defined @info{httpd_invalid_data}) {          # no invalid hits at all
      @info{httpd_invalid_data} = {} if(!defined @info{httpd_invalid_data});
   } else {                                          # clean up old requests
      for my $key (keys %{@info{httpd_invalid_data}}) {     # cycle each host
         my $count = 0;
         for my $ts (keys %{@info{httpd_invalid_data}->{$key}}) {
            if(time() - 3600 > $ts) {                           # rm, too old
               delete @info{httpd_invalid_data}->{$key}->{$ts};
            } else {                                     # count current hits
               $count += @info{httpd_invalid_data}->{$key}->{$ts};
            }
         }

         if(scalar keys %{@info{httpd_invalid_data}->{$key}} == 0) {
            delete @info{httpd_invalid_data}->{$key};        # no current hits
         } elsif($count >= @info{"conf.httpd_invalid"}) {
            if(!defined @{@info{httpd_ban}}{$key}) {
               @{@info{httpd_ban}}{$key} = scalar localtime();     # too many
               web("   %s\@web *** BANNED **\n",$key);          # add ban
            }
         } elsif(defined @{@info{httpd_ban}}{$key} ) {  # too little,remove ban
            web("   %s\@web Un-BANNNED\n",$key);
            delete @{@info{httpd_ban}}{$key};
         }
      }
   }
}


#
# http_error
#    Something has gone wrong, inform the broswer.
#
sub http_error
{
   my ($s,$fmt,@args) = @_;

   if(defined @http{$s} && defined @http{$s}->{data}) {
      if(@http{$s}->{data}->{get}  !~ /^\s*(favicon\.ico|robots.txt)\s*$/i) {
         manage_httpd_bans($s);
      }
   }

   #
   # show the invalid page responce
   #
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

#
# http_reply
#    A http reply with evaluation but no fries.
#
sub http_reply
{
   my ($prog,$fmt,@args) = @_;
   my $s = $$prog{sock};

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
   http_out($s,"%s\n",evaluate($$prog{user},
                               $prog,
                               @info{"conf.httpd_template"}
                              )
           );
   http_out($s,"<body>\n");
   http_out($s,"<div id=\"Content\">\n");
   http_out($s,"<pre>%s\n</pre>\n",ansi_remove($msg));
   http_out($s,"</div>\n");
   http_out($s,"</body>\n");
   http_disconnect($s);
}


#
# http_reply_simple
#     A simple http reply with no evaluation.
#
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

#
# http_out
#     Send something out to an http socket if its still connected.
#
sub http_out
{
   my ($s,$fmt,@args) = @_;

   printf({@{@http{$s}}{sock}} "$fmt\r\n", @args) if(defined @http{$s});
}

#
# banable_urls
#    If you hit one of these urls, you're running a script to look for
#    security vulnerabilities and/or hacking... either way, you need to
#    go away. This should probably be a permanent ban.
#
sub banable_urls
{
   my $data = shift;

   if($$data{get} =~ /wget http/i) {        # poor wget is abused by hackers
      return 1;
   } elsif($$data{get} =~ /phpMyAdmin/i) {             # really, no php here
      return 1;
   } elsif($$data{get} =~ /trinity/i) {                    # matrix trinity?
      return 1;
   } elsif($$data{get} =~ /w00tw00t/i) {                        # woot woot!
      return 1;
   } elsif($$data{get} =~ /\.php/i) {                          # no php here
      return 1;
   } else {
      return 0;
   }
}

sub ban_add
{
   my $sock = shift;

   # setup structures
   @info{httpd_ban} = {} if(!defined @info{httpd_ban}); 
   @info{httpd_invalid_data} = {} if(!defined @info{httpd_invalid_data});

   if($sock ne undef) {
      my $ip = @http{$sock}->{ip};
      if(!defined @{@http{$sock}}{$ip}) {
         @{@http{$sock}}{$ip} = {};
      }
      @info{httpd_invalid_data}->{$ip}->{time()} = 999999;
   }
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
#      web("      %s\@web %s\n",@{@http{$s}}{ip},$1);
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

         $$data{get} = uri_unescape($$data{get});
         $$data{get} =~ s/\// /g;
         $$data{get} =~ s/^\s+|\s+$//g;

         # run the $default mush command as the default webpage.
         $$data{get} = "default" if($$data{get} =~ /^\s*$/);

         my $addr = @{@http{$s}}{hostname};
         $addr = @{@http{$s}}{ip} if($addr =~ /^\s*$/);
         $addr = $s->peerhost if($addr =~ /^\s*$/);
         return http_error($s,"Malformed Request or IP") if($addr =~ /^\s*$/);
         @http{$s}->{ip} = $addr;

         if(mysqldb && $$data{get} !~ /^\s*favicon\.ico\s*$/i) {
            sql("insert into socket_history ".
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
                substr($$data{get},0,254),
                2
               );
            if(@info{rows} != 1) {
               con("Unable to add data to socket_history\n");
            }
         }

         @info{httpd_ban} = {} if(!defined @info{httpd_ban});
         # html/js/css should be a static file, so just return the file

         if(($$data{get} =~ /_notemplate\.(html)$/i ||     # no template used
            $$data{get} =~ /\.(js|css)$/i) &&
            -e "txt/" . trim($$data{get})) {
            web("   %s\@web [%s]\n",$addr,$$data{get});
            http_reply_simple($s,$1,"%s",getfile(trim($$data{get})));
         } elsif($$data{get} =~ /\.txt$/i && -e "txt/" . trim($$data{get})) {
            web("   %s\@web [%s]\n",$addr,$$data{get});
            http_reply_simple($s,$1,"%s",getfile(trim($$data{get})));
         } elsif($$data{get} =~ /\.html$/i && -e "txt/" . trim($$data{get})) {
            my $prog = prog($self,$self);                    # uses template
            $$prog{sock} = $s;
            web("   %s\@web [%s]\n",$addr,$$data{get});
            http_reply($prog,getfile(trim($$data{get})));
         } elsif(banable_urls($data)) {
            ban_add($s);
            web("   %s\@web [BANNED-%s]\n",$addr,$$data{get});
            http_error($s,"%s","BANNED for HACKING");
         } elsif(defined @{@info{httpd_ban}}{$addr}) {
            web("   %s\@web [BANNED-%s]\n",$addr,$$data{get});
            http_error($s,"%s","BANNED for invalid requests");
         } else {                                          # mush command
            web("   %s\@web [%s]\n",$addr,$$data{get});
            my $prog = mushrun(self   => $self,
                               runas  => $self,
                               invoker=> $self,
                               source => 0,
                               cmd    => $$data{get},
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
            con("Delete file dumps/$$hash{fn} during cleanup FAILED.");
         } else {
		 #            con("# Deleting $$hash{fn} as part of db backup cleanup\n");
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
              invoker=> $self,
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
sub glob2re
{
    my ($pat) = trim(single_line(ansi_remove(shift)));

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

   my $tmp = @info{rows};
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
   @info{rows} = $tmp;
   my_commit;
}

#
# the mush program has finished, so clean up any telnet connections.
#
sub close_telnet
{
   my $prog = shift;

   if(!defined $$prog{socket_id}) {
      return;
   } elsif(!defined @connected{$$prog{socket_id}}) {
      return;
   } elsif(hasflag(@{@connected{$$prog{socket_id}}}{obj_id},
                   "SOCKET_PUPPET"
                  )
          ) {
         return;
   } else {
      $$prog{socket_closed} = 1;
      my $hash = @connected{$$prog{socket_id}};
      # delete any pending input
      con("Closed orphaned mush telnet socket to %s:%s\n",
          $$hash{hostname},$$hash{port});
      server_disconnect($$prog{socket_id});
      delete @$prog{socket_id};
   }
}

sub verify_switches 
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
   my ($self,$prog,$fmt) = (obj(shift),obj(shift),shift);
   my (@args) = @_;

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

   my $prev = @info{source_prev};

   if(!$type || $type eq "short") {
      for my $line (split(/\n/,Carp::shortmess)) {
         if($line =~ / at ([^ ]+) line (\d+)/) {
            my ($fun,$ln) = ($1,$2);
     
            if(defined $$prev{$fun}) {
               push(@stack,@{$$prev{$fun}}{ln} + $2);
            } else {
               push(@stack,"$ln*");
            }
         }
      }
      return join(',',@stack);
   } else {
      return renumber_code(Carp::shortmess);
   }
}

#
# renumber_code
#    Look for line number references in the provided text and massage
#    them into the correct line number.
#
sub renumber_code
{
   my @out;

   my $prev = @info{source_prev};

   for my $line (split(/\n/,shift)) {
      if($line =~ / at ([^ ]+) line (\d+)/ && defined $$prev{$1}) {
         push(@out,"$` at $1 line " . ($2 + @{$$prev{$1}}{ln}));
      } else {
         push(@out,$line . " [*]");
      }
   }
   return join("\n",@out);
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
   my ($out,$seq,$debug);

   my $orig = $t;
   while($t =~ /(\[|\]|\\|%m[0-9]|%q[0-9a-z]|%i[0-9]|%[!pbrtnk#0-9%]|%(v|w)[a-zA-Z]|\[|\]|%=<[^>]+>|%\{[^}]+\})/i) {
      ($seq,$t)=($1,$');                                   # store variables
      $out .= $`;

      if($seq eq "\\") {                               # skip over next char
         $out .= substr($t,0,1);
         $t = substr($t,1);
      } elsif($seq eq "%%") {
         $out .= "\%";
      } elsif($seq eq "[") {
         $out .= "[" if(ord(substr($`,-1)) == 27);       # escape sequence?
      } elsif($seq eq "]" || $seq eq "]") {
         # ignore
      } elsif($seq eq "%b") {                                        # space
         $out .= " ";
      } elsif($seq eq "%r") {                                       # return
         $out .= "\n";
      } elsif($seq eq "%t") {                                          # tab
         $out .= "\t";
      } elsif($seq eq "%!") {                                          # tab
         if(defined $$self{obj_id}) {
           $out .= "#$$self{obj_id}";
         }
      } elsif(lc($seq) eq "%p") {
         if(!defined $$prog{cmd}) {
           $out .= "its";
         } else {
           my $sex = get(@{@{$$prog{cmd}}{invoker}}{obj_id},"sex");

           if($sex =~ /(male|boy|garson|gent|father|mr|man|sir|son|brother)/i){
              $out .= ($seq eq "%p") ? "his" : "His";
           } elsif($sex =~ /(female|girl|woman|lady|dame|chick|gal|bimbo)/i) {
              $out .= ($seq eq "%p") ? "her" : "Her";
           } else {
              $out .= ($seq eq "%p") ? "its" : "Its";
           }
         }
      } elsif($seq eq "%#") {                                # current dbref
         if(!defined $$prog{cmd}) {
            $out .= "#" . $$self{obj_id};
         } else {
            $out .= "#" . @{@{$$prog{cmd}}{invoker}}{obj_id};
         }
      } elsif(lc($seq) eq "%n" || lc($seq) eq "%k") {         # current name 
         if(!defined $$prog{cmd}) {
            $out .= name($self);
         } else {
            $out .= name(@{@{$$prog{cmd}}{invoker}}{obj_id});
         }
      } elsif($seq =~ /^%q([0-9a-z])$/i) {
         if(defined $$prog{var}) {
            $out .= @{$$prog{var}}{"setq_$1"} if(defined $$prog{var});
         }
      } elsif($seq =~ /^%m([0-9])$/) {
         if(defined $$prog{cmd} && 
            defined @{$$prog{cmd}}{mdigits}) {
            $out .= @{@{$$prog{cmd}}{mdigits}}{$1};
         }
      } elsif($seq =~ /^%i([0-9])$/) {
         if(defined $$prog{iter_stack}) {
            $out .= fun_itext($self,$prog,$1);
         }
      } elsif($seq =~ /^%([0-9])$/ || $seq =~ /^%\{([^}]+)\}$/) {  # temp vars
         if($1 eq "hostname") {
            $out .= $$user{raw_hostname};
         } elsif($1 eq "socket") {
            $out .= $$user{raw_socket};
         } else {
            $out .= @{$$prog{var}}{$1} if(defined $$prog{var});
         }
      } elsif($seq =~ /^%((v|w)[a-zA-Z])$/ || $seq =~ /^%=<([^>]+)>$/) {
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

   for my $hash (@{sql($sql,@args)}) {                            # run query
      $out .= $$hash{text} . "\n";                                # add output
   }
   # $out .= "---[  End  ]---";                                   # add footer
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
   for my $hash (@{sql($sql,@args)}) {
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

   if(hasflag($enactor,"GOD")) {                   # gods control everything
      return 1;
#   } elsif(hasflag($target,"GOD") && !hasflag($enactor,"GOD")) {
#      return 0;                        # nothing can modify a god, but a god
   } elsif(hasflag($enactor,"WIZARD")) {
      return 1;                    # wizards can modify everything but a god
   } elsif(owner_id($enactor) == owner_id($target)) {
      return 1;                              # you can modify your own stuff
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
                 invoker=> $target,
                 from   => "ATTR",
                 attr   => $hash,
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
            $$hash{atr_regexp} =~ s/^\(\?msix/\(\?msx/; # make case sensitive
            if($msg =~ /$$hash{atr_regexp}/) {
               mushrun(self   => $self,
                       runas  => $obj,
                       cmd    => single_line($$hash{atr_value}),
                       wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                       source => 0,
                       attr   => $hash,
                       invoker=> $self,
                       from   => "ATTR"
                      );
                $match=1;
            }
         } elsif($msg =~ /$$hash{atr_regexp}/i) {
            mushrun(self   => $self,
                    runas  => $obj,
                    invoker=> $self,
                    cmd    => single_line($$hash{atr_value}),
                    wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                    source => 0,
                    attr   => $hash,
                    from   => "ATTR"
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

sub ts_date
{
   my $time = shift;

   $time = time() if $time eq undef;
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime($time);
   $mon++;

   return sprintf("%02d/%02d/%02d",$mon,$mday,$year % 100);
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

sub logit
{
   my ($type,$fmt,@args) = @_;
   my ($msg,$fd);

   # add newline if needed except when the fmt starts with a escape code
   $fmt .= "\n" if(substr($fmt,0,1) ne chr(27) && $fmt !~ /\n$/); 

   $fd = @info{"$type.fd"} if defined @info{"$type\.fd"};   # get existing fd

   # do not log requests
   return if(@info{"conf.$type"} =~ /^\s*nolog\s*$/i);

   # security - filename could be coming from inside the db, don't allow
   #            bad filenames - overwrite of important files.
   if(!defined @info{"conf.$type"} || 
      @info{"conf.$type"} =~ /(\\|\/|..)/ ||      # stay in current dir
      @info{"conf.$type"} !~ /web.log$/i ) {         # stay named *.web.log
      @info{"conf.$type"} = @default{$type};
   }

#   printf("$fmt", @args);
   # open log as needed if not using console
   if(@info{"conf.$type"} !~ /^\s*console\s*$/i  &&
      (!-e @info{"conf.$type"} || !defined @info{"$type\.fd"})) {
      if(open($fd,">> " . @info{"conf.$type"})) {
         $fd->autoflush(1);
         @info{"$type\.fd"} = $fd;
      } else {
         $fd = undef;
      }
   }

   if($type eq "conlog") {
#   if($fd eq undef || !defined @info{initial_load_done}) {       # console
      printf($fmt, @args);
   }

   my $txt = sprintf("$fmt",@args);
#   $txt =~ s/[^[::ascii::]]//g;
   printf($fd "%s", $txt) if($fd ne undef);
}

sub web
{
   logit("weblog",@_);
}

sub con
{
   logit("conlog",@_);
}


sub log_output
{
   my ($src,$dst,$loc,$txt) = (obj(shift),obj(shift),shift,shift);

   return if memorydb;
   return if($$src{obj_id} eq undef);

   $txt =~ s/([\r\n]+)$//g;

   my $tmp = @info{rows}; # its easy to try to necho() data before testing
                          # against $$db{rows}, which  will clear $$db{rows}.
                          # so we'll revert it after the below sql() call.

   sql("insert into io" .                      #store output in output table
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
   @info{rows} = $tmp;
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
   } elsif(defined $$obj{sock} && (!defined $$obj{raw} || $$obj{raw} == 0)) {
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

#   if($arg{self} eq undef) {
#      con("%s\n",print_var(\%arg));
#      con("%s\n",code("long"));
#   }

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

         if($target ne undef) {
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
   my ($id,$no_check_bad) = (shift,shift);

   $id = { obj_id => $id } if(ref($id) ne "HASH");
   $$id{obj_id} =~ s/#//g;

   if(memorydb) {
      if($$id{obj_id} =~ /^\s*(\d+)\s*$/) {
         if(!$no_check_bad && bad_object($1)) {
            return 0;
         } elsif(defined @info{backup_mode} && @info{backup_mode}) {
            if(defined @deleted{$1}) {
               return 0;
            } elsif(defined @db[$1] || @delta[$1]) {
               return 1;
            } else {
               return 0;
            }
         } elsif(defined @db[$1]) {
            return 1;
         } else {
            return 0;
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
      (obj($_[0]),$_[1],obj($_[2]),trim(uc($_[3])),$_[4]);
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
       my $hash = one(
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
          my $count = one_val("select count(*) value from flag ".
                                  " where obj_id = ? " .
                                  "   and fde_flag_id = ?" .
                                  "   and atr_id is null ",
                                  $$obj{obj_id},
                                  $$hash{fde_flag_id});
   
          # add flag to the object/user
          if($count > 0 && $remove) {
             sql("delete from flag " .
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
             sql("insert into flag " .
                 "   (obj_id,ofg_created_by,ofg_created_date,fde_flag_id)" .
                 "values " .
                 "   (?,?,now(),?)",
                 $$obj{obj_id},
                 $who,
                 $$hash{fde_flag_id});
             my_commit;
             if(@info{rows} != 1) {
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

    if(memorydb) {
       $atr = "obj_$atr" if reserved($atr);
       if($flag =~ /^\s*!\s*(.+?)\s*$/) {
          ($remove,$flag) = (1,$1);
       }
       if(!$override && !can_set_flag($object,$object,$flag)) {
          return "#-1 Permission Denied.";
       } elsif(!db_attr_exist($object,$atr)) {
          return "#-1 UNKNOWN ATTRIBUTE ($atr).";
       } else {
          db_set_flag($$object{obj_id},$atr,$flag,$remove ? undef : 1);
          return "Set.";
       }
    } else {

       $who = "CREATE_USER" if($flag eq "PLAYER" && $who eq undef);
       ($flag,$remove) = ($',1) if($flag =~ /^\s*!\s*/);         # remove flag 
       
   
       # lookup flag info
       my $hash = one(
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
   
          my $atr_id = one_val(
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
          my $flag_id = one_val("select ofg_id value " .
                                "  from flag " .
                                " where atr_id = ? " .
                                "   and fde_flag_id = ?",
                                $atr_id,
                                $$hash{fde_flag_id}
                               );
                                  
          # add flag to the object/user
          if($flag_id ne undef && $remove) {
             sql("delete from flag " .
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
             sql("insert into flag " .
                 "   (obj_id, " .
                 "    ofg_created_by, " .
                 "    ofg_created_date, " .
                 "    fde_flag_id, " .
                 "    atr_id)" .
                 "values " .
                 "   (?,?,now(),?,?)",
                 $$object{obj_id},
                 $who,
                 $$hash{fde_flag_id},
                 $atr_id);
             my_commit;
             if(@info{rows} != 1) {
                return "#-1 Flag note removed [Internal Error]";
             }
             set_cache_atrflag($object,$atr,$flag);
             return "Set.";
          }
       } else {
          return "#-1 Permission Denied."; 
       }
   }
} 

sub perm
{
   my ($target,$perm) = (obj(shift),shift);

   return 0 if(defined $$target{loggedin} && !$$target{loggedin});
   return 1;

   $perm =~ s/@//;
   my $owner = owner($$target{obj_id});
   my $result = one_val(
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

sub first_room
{
   my $skip = shift;

   for my $i (0 .. $#db) {                      # ick, pick first room
      return $i if($skip != $i && valid_dbref($i) && hasflag($i,"ROOM"));
   }
   return undef;
}

#
# destroy_object
#    Delete an object from the database and cache. This is not for deleting
#    players.
#
sub destroy_object 
{
   my ($self,$prog,$target) = (obj(shift),shift,obj(shift));

   my $loc = loc($target);

   if(memorydb) {
      for my $exit (lexits($target)) {                   # destroy all exits
         if(valid_dbref($exit)) {
            db_delete($exit);
         }
      }

      for my $obj (lcon($target)) {             # move objects out of the way
         my $home = home($obj);

         necho(self => $self,
               prog => $prog,
               target => [ $obj, "The room shakes and begins to crumble." ],
               room   => [ $obj, "%s has left.", name($obj) ]
              );

         # default to first room if home can't be determined.
         if($home eq undef || $home == $$target{obj_id}) {
            $home = first_room($$obj{obj_id}); 
         }
         set_home($self,$prog,$obj,$home);
         teleport($self,$prog,$obj,$home);

         cmd_look($obj,prog($obj,$obj,$obj));
      }
      
      if(!hasflag($target,"ROOM")) {
         my $loc = loc($target);                        # remove from location
         db_remove_list($loc,"obj_content",$$target{obj_id});
         db_remove_list($loc,"obj_exits",$$target{obj_id});
         necho(self    => $self,
               prog    => $prog,
               all_room    =>  [ $target, "%s was destroyed.", name($target) ],
               all_room2   => [ $target, "%s has left.", name($target) ]
              );
      }

      push(@free,$$target{obj_id});
      db_delete($target);
      return 1;
   } else {
      sql("delete " .
          "  from object ".
          " where obj_id = ?",
          $$target{obj_id}
         );
   
      if(@info{rows} != 1) {
         my_rollback;
         return 0;
      }  else {
         delete $cache{$$target{obj_id}};
         set_cache($loc,"lcon");                   # invalid cache entries
         set_cache($loc,"con_source_id");
         set_cache($loc,"lexits");
         my_commit;
   
         return 1;
      }
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
      db_set($id,"obj_created_by",$$user{hostname});

      if($pass ne undef && $type eq "PLAYER") {
         db_set($id,"obj_password",mushhash($pass));
      }
 
      my $out = set_flag($self,$prog,$id,$type,1);
      set_flag($self,$prog,$id,"NO_COMMAND",1);

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
         db_set($id,"obj_lock_default","#" . $id);
         db_set($id,"obj_home",$where);
         db_set($id,"obj_money",@info{"conf.starting_money"});
         db_set($id,"obj_firstsite",$where);
         db_set($id,"obj_quota",@info{"conf.starting_quota"});
         db_set($id,"obj_total_quota",@info{"conf.starting_quota"});
         @player{lc($name)} = $id;
      } else {
         db_set($id,"obj_home",$$self{obj_id});
      }

      db_set($id,"obj_owner",$$self{obj_id});
      db_set($id,"obj_created_date",scalar localtime());
      if($type eq "PLAYER" || $type eq "OBJECT") {
         teleport($self,$prog,$id,$where);
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
         sql(" insert into object " .
             "    (obj_id,obj_name,obj_password,obj_owner,obj_created_by," .
             "     obj_created_date, obj_home " .
             "    ) ".
             "values " .
             "   (?, ?,password(?),?,?,now(),?)",
             $id,$name,$pass,$owner,$who,$where);
      } else {
         sql(" insert into object " .
             "    (obj_name,obj_password,obj_owner,obj_created_by," .
             "     obj_created_date, obj_home " .
             "    ) ".
             "values " .
             "   (?,password(?),?,?,now(),?)",
             $name,$pass,$owner,$who,$where);
      }
   }

   if(@info{rows} != 1) {                           # oops, nothing happened
      necho(self => $self,
            prog => $prog,
            source => [ "object #%s was not created", $id ]
           );
      my_rollback;
      return undef;
   }

   if($id eq undef) {                             # grab newly created id
      $id = one_val("select last_insert_id() obj_id") ||
          return my_rollback;
   }

   my $out = set_flag($self,$prog,$id,$type,1);
   set_flag($self,$prog,$id,"NO_COMMAND",1);

   if($out =~ /^#-1 /) {
      necho(self => $self,
            prog => $prog,
            source => [ "%s", $out ]
           );
      return undef;
   }
   if($type eq "PLAYER" || $type eq "OBJECT") {
      teleport($self,$prog,$id,fetch($where));
   }
   return $id;
}



sub curval
{
   return one_val("select last_insert_id() value");
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
   my ($name,$self) = @_;
   $name =~ s/^\s+|\s+$//g;

   if($self ne undef && lc(trim($name)) eq lc(name($self,1))) {
      return 0;                                 # allow for changes in case
   } elsif(memorydb) {
      return defined @player{lc($name)} ? 1 : 0;
   } else {
      my $result = one_val(
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
      db_set($owner,"obj_money",$money + $amount);
   } else {
      sql("update object " .
          "   set obj_money = ? ".
          " where obj_id = ? ",
          $money + $amount,
          $$owner{obj_id});

      return undef if(@info{rows} != 1);
      set_cache($target,"obj_money",$money + $amount);
   }

   return 1;
}

sub set
{
   my ($self,$prog,$obj,$attribute,$value,$quiet)=
      ($_[0],$_[1],obj($_[2]),lc($_[3]),$_[4],$_[5]);
   my ($pat,$first,$type);

   # don't strip leading spaces on multi line attributes
   if(!@{$$prog{cmd}}{multi}) {
       $value =~ s/^\s+//g;
   }

   if($attribute !~ /^\s*([#a-z0-9\_\-\.]+)\s*$/i) {
      printf("ATTRIBUTE: '%s'\n",$attribute);
      err($self,$prog,"Attribute name is bad, use the following characters: " .
           "A-Z, 0-9, and _ : $attribute");
   } elsif($value =~ /^\s*$/) {
      if(memorydb) {
         if(reserved($attribute) && !$quiet) {
            err($self,$prog,"That attribute name is reserved -> $quiet.");
         } else {
            db_set($obj,$attribute,undef);
            if($$obj{obj_id} eq 0 && $attribute =~ /^conf./i) {
               if(defined @default{$'}) {
                  @info{$attribute} = @default{$'};
               } else {
                  delete @info{$attribute};
               }
            }
            if(!$quiet) {
                necho(self => $self,
                      prog => $prog,
                      source => [ "Set." ]
                     );
            }
         }
      } else {
         sql("delete " .
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
         if(reserved($attribute) && !$quiet) {
            err($self,$prog,"That attribute name is reserved.");
         } else {
            db_set($obj,$attribute,$value);
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
      if((my $hash = one("select atr_value, " .
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
# teleport
#    move an object from to a new location.
#
sub teleport
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
      sql("delete from content " .                      # remove previous loc
          " where obj_id = ?",
          $$target{obj_id});

      # insert current location record for object
      my $result = sql(
          "INSERT INTO content (obj_id, ".               # set new location
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
      my_commit;
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
         con("ID: '%s' -> '%s'\n",$id,code());
         die();
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

      if(@info{rows} != 1) {
         return err($self,$prog,"Internal Error, unable to set home");
      } else {
         my_commit;
      }
   }
}

sub link_exit
{
   my ($self,$exit,$src,$dst) = obj_import(@_);

   if(memorydb) {
      if($src ne undef && defined $$src{obj_id}) {
         db_set_list($$src{obj_id},"obj_exits",$$exit{obj_id});
         db_set($$exit{obj_id},"obj_location",$$src{obj_id});
      }

      if($dst ne undef && defined $$exit{obj_id}) {
         db_set($$exit{obj_id},"obj_destination",$$dst{obj_id});
      }
      return 1;
   } else {
      my $count=one_val("select count(*) value " .
                        "  from content " .
                        "where obj_id = ?",
                        $$exit{obj_id});
   
      if($count > 0) {
         one("update content " .
             "   set con_dest_id = ?," .
             "       con_updated_by = ? , ".
             "       con_updated_date = now() ".
             " where obj_id = ?",
             $$dst{obj_id},
             obj_name($self,$self,1),
             $$exit{obj_id});
      } else {
         one("INSERT INTO content (obj_id, ".                # set new location
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

      if(@info{rows} == 1) {
         set_cache($src,"lexits");
         set_cache($exit,"con_source_id");
         my_commit;
         return 1;
      } else {
         my_rollback;
         return 0;
      }
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
      return one_val("SELECT skh_hostname value " .
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
   my ($target,$flag) = (obj(shift),shift);

   if(memorydb) {
      my $attr = mget($target,"obj_lastsite");

      if($attr eq undef) {
         return undef;
      } else {
         my $list = $$attr{value};

         if($flag) {
            return (sort keys %$list)[-1];
         } else {
            return scalar localtime((sort keys %$list)[-1]);
         }
      }
   } else {
      my $last = one_val("select ifnull(max(skh_end_time), " .
                         "              max(skh_start_time) " .
                         "             ) value " .
                         "  from socket_history " .
                         " where obj_id = ? ",
                         $$target{obj_id}
                        );
      if($flag) {
         return fuzzy($last);
      } else {
         return $last;
      }
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
      return one_val("SELECT skh_hostname value " .
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

   my %months = (
      jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6,
      jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12,
   );

   my %days = (
      mon => 1, tue => 2, wed => 3, thu => 4, fri => 5, sat => 6, sun => 7,
   );

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
      } else {
         printf("Skipped: $word\n");
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
  } elsif(hasflag($obj,"GUEST")) {
     return 0;
  } elsif(memorydb) {
     return get(owner($obj),"obj_quota");
  } else {
     return one_val("select max(obj_quota) - count(*) + 1 value " .
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
      return flag_attr(trim($txt));
   } else {
      return one_val("select count(*) value " .
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


#
# get_db_credentials
#    Load the database credentials from the teenymush.conf file
#
sub get_db_credentials
{
   my $fn = "teenymush.conf";

   $fn .= ".dev" if(-e "$fn.dev");

   for my $line (split(/\n/,getfile($fn))) {
      $line =~ s/\r|\n//g;
      if($line =~ /^\s*(user|pass|database)\s*=\s*([^ ]+)\s*$/) {
         @info{$1} = $2;
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
   my ($sql,@args) = @_;
   my (@result,$sth);
   @info{sqldone} = 0;

   delete @info{rows};

#   if($sql !~ /^insert into io/) {
#     con("SQL: '%s' -> '%s'\n",$sql,join(',',@args));
##      con("     '%s'\n",code("short"));
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
   if(!defined @info{db_handle} || !@info{db_handle}->ping) {
      @info{host} = "localhost" if(!defined @info{host});
      @info{db_handle} = DBI->connect("DBI:mysql:database=@info{database}:" .
                                      "host=@info{host}",
                                      @info{user},
                                      @info{pass},
                                      {AutoCommit => 0, RaiseError => 1,
                                        mysql_auto_reconnect => 1}
                                      ) 
                                      or die "Can't connect to database: " .
                                         $DBI::errstr;
   }

   $sth = @info{db_handle}->prepare($sql) ||
      die("Could not prepair sql: $sql");

   for my $i (0 .. $#args) {
      $sth->bind_param($i+1,$args[$i]);
   }

   if(!$sth->execute( )) {
      die("Could not execute sql");
   }
   @info{rows} = $sth->rows;

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
# one_val
#    fetch the first entry in value column on a select that returns only
#    one row.
#
sub one_val
{
   my ($sql,@args) = @_;

   my $array = sql($sql,@args);
   return (@info{rows} == 1) ? @{$$array[0]}{value} : undef;
}

#
# fetch one row or nothing
#
sub one
{
   my ($sql,@args) = @_;
   my $array = sql($sql,@args);

   if(@info{rows} == 1) {
      return $$array[0];
   } elsif(@info{rows} == 2 && $sql =~ /ON DUPLICATE/i) {
      @info{rows} = 1;
      return $$array[0];
   } else {
      return undef;
   }
}

sub my_commit
{
   @info{db_handle}->commit;
}

sub my_rollback
{
   @info{db_handle}->rollback;
}

sub fetch
{
   my $obj = obj($_[0]);
   my $debug = shift;

   $$obj{obj_id} =~ s/#//g;

   if(memorydb) {
      return $obj;
   } else {
      my $hash=one("select * from object where obj_id = ?",$$obj{obj_id}) ||
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

   $txt =~ s/^ +| +$//g;
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
       my $hash=one("select ifnull(min(ste_type),4) ste_type" .
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

   if(!defined $$prog{socket_buffer}) {
      $$prog{socket_buffer} = [];
      delete @info{socket_buffer};
   }

   @info{socket_buffer} .= (defined @info{socket_buffer} ? "\n" : "") . $txt;
   if($$prog{socket_url}) {
      $$prog{socket_count}++;

      # if its a url() request, read the header and determine if there
      # was an error or not.
      if($$prog{socket_count} == 1 && 
         $txt =~ /^HTTP\/[\d\.]+ (\d+)/ && 
         $1 >= 400) {
         push(@$stack,"#-1 PAGE LOAD FAILURE");
         server_disconnect($$prog{socket_id});
      }
   }
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
#      con("#%s# '%s'\n",((defined $$hash{obj_id}) ? obj_name($hash) : "?"),
#      $input);
#   }
   my $data = @connected{$$hash{sock}};

   if(defined $$data{raw} && $$data{raw} == 1) {
      handle_object_listener($data,"%s",$input);
   } elsif(defined $$data{raw} && $$data{raw} == 2) {
     add_telnet_data($data,$input);
   } else {
#      eval {                                                  # catch errors
         local $SIG{__DIE__} = sub {
            con("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            con("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            if(mysqldb && defined @info{sql_last}) {
               con("LastSQL: '%s'\n",@info{sql_last});
               con("         '%s'\n",@info{sql_last_args});
               delete @info{sql_last};
               delete @info{sql_last_args};
            }
            con("%s",code("long"));
         };

         if($input =~ /^\s*([^ ]+)/ || $input =~ /^\s*$/) {
            $user = $hash;
            if(loggedin($hash) || 
                    (defined $$hash{obj_id} && hasflag($hash,"OBJECT"))) {
               add_last_info($input);                                   #logit
               io($user,1,$input);
               return mushrun(self   => $user,
                              runas  => $user,
                              invoker=> $user,
                              source => 1,
                              cmd    => $input,
                             );
            } else {
               my ($cmd,$arg) = lookup_command($data,\%offline,$1,$',0);
               &{@offline{$cmd}}($hash,prog($user,$user),$arg);  # invoke cmd
            }
         }
#      };

      if($@) {                                # oops., you sunk my battle ship
#         con("# %s crashed the server with: %s\n%s",name($hash),$_[1],$@); 
#         con("LastSQL: '%s'\n",@info{sql_last});
#         con("         '%s'\n",@info{sql_last_args});
#         con("         '%s'\n",@info{sql_last_code});
         my_rollback if mysqldb;
   
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
            con("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            printf("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            if(mysqldb && defined @info{sql_last}) {
               con("LastSQL: '%s'\n",@info{sql_last});
               con("         '%s'\n",@info{sql_last_args});
               delete @info{sql_last};
               delete @info{sql_last_args};
            }
            con("%s",code("long"));
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

               con("# Connect from: %s [%s]\n",$$hash{hostname},ts());
               if($$hash{site_restriction} <= 2) {                  # banned
                  con("   BANNED   [Booted]\n");
                  if($$hash{site_restriction} == 2) {
                     printf($new "%s",@info{"conf.badsite"});
                  }
                  server_disconnect(@{@connected{$new}}{sock});
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

           
               # store last transaction in @info{connected_raw_socket} 
               if(defined @connected{$s} && @{@connected{$s}}{raw} > 0) {
                  if(@info{connected_raw_socket} ne $s) {
                     delete @info{connected_raw};
                     @info{connected_raw_socket} = $s;
                  } 
                  @info{connected_raw} .= $` . "\n";
               }

#               if(@{@connected{$s}}{raw} > 0) {
#                  my $tmp = $`;
#                  $tmp =~ s/\e\[[\d;]*[a-zA-Z]//g;
#                  web("#%s# %s\n",@{@connected{$s}}{raw},$tmp);
#               }
            }
         }
      }

     spin();

   };
   if($@){
      con("Server Crashed, minimal details [main_loop]\n");

      if(mysqldb) {
         con("LastSQL: '%s'\n",@info{sql_last});
         con("         '%s'\n",@info{sql_last_args});
      }
      con("%s\n---[end]-------\n",$@);
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
   my ($prog, $type);

   # notify connected users of disconnect
   if(defined @connected{$id}) {
      my $hash = @connected{$id};

      if(memorydb) {                             # update disconnect time
         my $attr = mget(@connected{$id},"obj_lastsite");

         if($attr ne undef && defined $$attr{value} &&
            ref($$attr{value}) eq "HASH" && defined $$hash{connect}) {
            my $last = $$attr{value};

            my $ctime = $$hash{connect};
            if(defined $$last{$ctime} && $$last{$ctime} =~ /,([^,]+)$/) {
                db_set_hash(@connected{$id},
                            "obj_lastsite",
                            $ctime,
                            time() . ",1,$1"
                           );
            }
         }
      }


      if(defined @connected{$id} && defined @{@connected{$id}}{prog}) {
         $prog = @{@connected{$id}}{prog};
      } else {
         $prog = prog($hash,$hash);
      }
      $type = @{@connected{$id}}{type};


      # tell the running mushcode that the socket closed
      if(defined $$hash{prog} && defined @{$$hash{prog}}{socket_id}) {
         delete @{$$hash{prog}}{socket_id};
         @{$$hash{prog}}{socket_closed} = 1;
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
            sql("delete from socket " .             # delete socket table row
                " where sck_socket = ? ",
                $id
               );
            my_commit;
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
            my $sck_id = one_val("select sck_id value " .     # find socket id
                                 "  from socket " .
                                 " where sck_socket = ?" ,
                                 $id
                                );

            if($sck_id ne undef) {
                sql("update socket_history " .           # log disconnect time
                    "   set skh_end_time = now() " .
                    " where sck_id = ? ",
                     $sck_id
                   );
   
                sql("delete from socket " .         # delete socket table row
                    " where sck_id = ? ",
                    $sck_id
                   );
                my_commit;
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

   #
   # closing the socket here on a websocket causes a crash later on. 
   # not closing it here doesn't seem to cause any problems. 
   # i.e. no orphaned connections in netstat.
   #
   if($type eq "WEBSOCKET" && defined @c{$id}) {
      @c{$id}->disconnect();
      delete @c{$id};
   } else {
      $id->close;
   }
   delete @connected{$id};
}

#
# server_start
#
#    Start listening on the specified port for new connections.
#
sub server_start
{
   #
   # close the loop on connections that have start times but not end times
   #

   if(mysqldb) {
      sql("delete from socket");
      sql("update socket_history " .
              "   set skh_end_time = skh_start_time " .
              " where skh_end_time is null");
      my_commit;
   }

   if(memorydb) {
      my $file = newest_full(@info{"conf.mudname"} . ".FULL.DB");

      if($file eq undef) {
         con("   No database found, loading starter database.\n");
         con("   Connect as: god potrzebie\n\n");
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
         @info{db_last_dump} = time();
      }
   }

   read_atr_config();

   my $count = 0;

   @info{"conf.port"} = 4096 if(@info{"conf.port"} !~ /^\s*\d+\s*$/);
   con("TeenyMUSH listening on port %s\n",@info{"conf.port"});
   $listener = IO::Socket::INET->new(LocalPort => @info{"conf.port"},
                                     Listen    => 1,
                                     Reuse     => 1
                                    );

   if(@info{"conf.httpd"} ne undef && @info{"conf.httpd"} > 0) {
      if(@info{"conf.httpd"} =~ /^\s*(\d+)\s*$/) {
         con("HTTP listening on port %s\n",@info{"conf.httpd"});

         $web = IO::Socket::INET->new(LocalPort => @info{"conf.httpd"},
                                      Listen    =>1,
                                      Reuse=>1
                                     );
      } else {
         con("Invalid httpd port number specified in #0/conf.httpd");
      }
   }

   if(@info{"conf.websocket"} ne undef && @info{"conf.websocket"} > 0) {
      if(@info{"conf.websocket"} =~ /^\s*(\d+)\s*$/) {
         con("Websocket listening on port %s\n",@info{"conf.websocket"});
         websock_init();
      } else {
         con("Invalid websocket port number specified in #0/conf.websocket");
      }
   }
   @info{initial_load_done} = 1;

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
      eval {
         server_handle_sockets();
      };
      if($@){
         con("Server Crashed, minimal details [main_loop]\n");
         if(mysqldb) {
            con("LastSQL: '%s'\n",@info{sql_last});
            con("         '%s'\n",@info{sql_last_args});
         }
         con("%s\n---[end]-------\n",$@);
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
    server_disconnect( $conn->{socket} );
    $ws->{select_readable}->remove( $conn->{socket} );
    delete $ws->{conns}{$sock};
}

sub ws_login_screen
{
   my $conn = shift;

   ws_echo($conn->{socket}, @info{"conf.login"});
# foo
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
      @c{$sock} = $conn;

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
sub ws_process
{
   my( $conn, $msg, $ssl ) = @_;
   $msg =~ s/\r|\n//g;

   $ssl = $ssl ? ',SSL' : '';

   if($msg =~ /^#M# /) {
      web("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$');
      @{$ws->{conns}{$conn->{socket}}}{type} = "NON_INTERACTIVE";
      my $self = fetch(@info{"conf.webuser"});

      my $prog = mushrun(self   => $self,
                         runas  => $self,
                         invoker=> $self,
                         source => 0,
                         cmd    => $',
                         hint   => "WEBSOCKET",
                         sock   => $conn,
                         output => []
                        );
      $$prog{sock} = $conn;
   } else {
      $msg = substr($msg,1);
      web("   %s\@ws [%s]\n", @{$ws->{conns}{$conn->{socket}}}{ip},$msg);
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
#         web("Skipped $client\n");
      }
   }
}

#
# balanced
#    Determine if a line of text has a set of balanced parentheses
#
sub balanced
{
    my $txt = shift;
    my $open = $txt =~ tr/\(//;
    my $close = $txt =~ tr/\)//;
    return ($open == $close) ? 1 : 0;
}

sub decode_flags
{
   my @list;
   my ($flag,$num,$id) = @_;


   if($id == 1) {
      for my $type (grep {/^TYPE_/} keys %$flag) {

         # there has to be a better way to do this, but what i found
         # fails when comparing 0 to 0x0, and this is my work around.
         if(sprintf("'%032b'",$num & 0x7) eq 
            sprintf("'%032b'",oct($$flag{$type}))){
            push(@list,substr($type,5));
         }
      }
   }

   for my $type (grep {/_$id$/} keys %$flag) {
      if($num & oct($$flag{$type})) {
         push(@list,substr($type,0,-2));
      }
   }

   return @list;
}

#
# post_db_read_fix
#    TinyMUSH's db stores contents and exits in a linked list style format,
#    where the object in the list stores a pointer to the next object.
#    Teenymush just stores an array of objects. This function will
#
#
sub post_db_read_fix
{
   my $start = shift;

   for my $i ($start .. $#db) {
      if(valid_dbref($i) && defined @db[$i]->{obj_content}) {
         my $hash = @db[$i]->{obj_content}->{value};
         my $obj = (keys %$hash)[0];

         if($obj == -1) {
            db_set($i,"obj_content");
         } else {
            while($obj != -1 && valid_dbref($obj)) {          # traverse list
               db_set_list($i,"obj_content",$obj);            # add next item
               db_set($obj,"obj_location",$i);
   
               if(defined @db[$obj]->{obj_next}->{value} && 
                  @db[$obj]->{obj_next}->{value} != -1) {
                  my $prev = $obj;
                  $obj = @db[$obj]->{obj_next}->{value};     # move to next hop
                  db_set($prev,"obj_next");                 # delete next attr
               } else {
                  $obj = -1;
               }
            }
         }
      }
      if(valid_dbref($i) && defined @db[$i]->{obj_exits}) {
         my $hash = @db[$i]->{obj_exits}->{value};
         my $obj = (keys %$hash)[0];

         if($obj == -1) {
            db_set($i,"obj_exits");
         } else {
            while($obj != -1 && valid_dbref($obj)) {          # traverse list
               db_set_list($i,"obj_exits",$obj);              # add next item

               if(hasflag($obj,"EXIT")) {
                  if(@db[$obj]->{obj_location}->{value} == -1) {
                     db_set($obj,"obj_destination");
                  } else {
                     db_set($obj,
                            "obj_destination",
                            @db[$obj]->{obj_location}->{value});
                  }

                  my $loc = @db[$obj]->{obj_exits}->{value};
                  db_set($obj,"obj_location",(keys %$loc)[0]);
                  db_set($obj,"obj_exits");
               }

               if(defined @db[$obj]->{obj_next}->{value} && 
                  @db[$obj]->{obj_next}->{value} != -1) {
                  my $prev = $obj;
                  $obj = @db[$obj]->{obj_next}->{value};   # move to next hop
                  db_set($prev,"obj_next");                # delete next attr
               } else {
                  $obj = -1;
               }
            }
         }
      }
   }
   for my $i ($start .. $#db) {    # going objects are handled diferently
      delete @db[$i] if(hasflag($i,"GOING"));
   }
}

#
# db_read_import
#    Read a mush flat file and put it at the "end" of the database.
#    Dbrefs in code are not remapped but non-code things like exits and
#    contents are. This was only tested with a 1994 flat file database.
#
sub db_read_import
{
   my ($self,$prog,$file) = @_;
   my ($inattr,$id,$pos,$lock,$attr_id,%attr,$name,%impflag,$prev) = (1, undef);

   # The data from the flags.h and attrs.h could be hard coded into the
   # db but reading it from the source will probably allow for different
   # versions to be supported?

#   return if $#db > -1;
   my $start = $#db + 1;

   open(FILE,"attrs.h") ||
      die("Could not open 'attrs.h' for reading.");
   while(<FILE>) {
      s/\r|\n//g;

      if(/^\s*#define\s+A_(\w+)\s+(\d+)/) {           # get attribute ids
         @attr{$2} = "A_$1";
      }
   }
   close(FILE);

   # read flags.h for use in decoding flags
   $id = 1;
   open(FILE,"flags.h") ||
      die("Could not open 'flags.h' for reading.");
   while(<FILE>) {
      s/\r|\n//g;

      if(/^#define TYPE_(\w+)\s+([\dx]+)/) {
          @impflag{"TYPE_$1"} = $2;
      } elsif(/^#define\s+(\w+)\s+([\dx]+)/) {
          @impflag{"$1_$id"} = $2;
      } elsif(/Second word/) {
         $id = 2;
      } elsif(/Third word/) {
         $id = 3;
      } elsif(/^#define\s+\w+\(.+\).*Flags[2|3].*&\s+(\w+)\)/) {
         delete @impflag{$1};
      }
   }
   close(FILE);
   delete @impflag{"FLAG_WORD1_1"};   # delete unused flags that cause problems
   delete @impflag{"FLAG_WORD2_1"};
   delete @impflag{"FLAG_WORD3_1"}; 
   delete @impflag{"GOODTYPE_1"};
   delete @impflag{"NOTYPE_1"};

   open(FILE,$file) ||                            # start reading actual db
      return err($self,$prog,"Could not open file '%s' for reading",$file);

   while(<FILE>) {
      if($_ =~ /$/) {
         $prev = $_;
         next;
      } elsif($prev ne undef) {
         $_ = $prev . $_;
         $prev = undef;
      }

      s/\r|\n//g;
      if($. == 1 || $. == 2 || $. == 3) {
#         printf("# $_\n");
      } elsif($inattr && /^\+A(\d+)$/) {
         $id = $1;
      } elsif($inattr && $id ne undef && /^(\d+):([^ ]+)$/) {
         @attr{$id} = $2;
         $id = undef;
      } elsif(/^!(\d+)$/) {
         $inattr = 0;
         $id = $1;
         $pos = $.;
      } elsif($inattr) {
         printf("INATTR[$.,%s]: '$_'\n",$. - $pos);
         exit();
      } elsif($.  - $pos == 1) {                                   # name
         $name = $_;
         db_set($id+$start,"obj_name",$_);
         db_set($id+$start,"obj_cname",$_);
      } elsif($.  - $pos == 2) {
         db_set($id+$start,"obj_location",($_ == -1) ? -1 : ($_+$start));
      } elsif($.  - $pos == 3) {
         db_set_list($id+$start,"obj_content",($_ == -1) ? -1 : ($_+$start));
      } elsif($.  - $pos == 4) {
         db_set_list($id+$start,"obj_exits",($_ == -1) ? -1 : ($_+$start));
      } elsif($.  - $pos == 5) {
         db_set($id+$start,"obj_home",$_+$start);
      } elsif($.  - $pos == 6) {          # unused, but needed during clean up
         db_set($id+$start,"obj_next",($_ == -1) ? -1 : ($_+$start));
      } elsif($lock ne undef || $.  - $pos == 7) {
         $lock .= $_;
         if(balanced($lock)) {
            db_set($id+$start,"obj_lock_default",$lock);
            $lock = undef;
         } else {
            $pos++;
         }
      } elsif($.  - $pos == 8) {
         db_set($id+$start,"obj_owner",($_ == -1) ? -1 : ($_+$start));
      } elsif($.  - $pos == 9) {
         # printf("$id-PARENT[%s]? '%s'\n",$. - $pos,$_);     # unsupported
      } elsif($.  - $pos == 10) {
         db_set($id+$start,"obj_money",$_);
      } elsif($.  - $pos == 11) {
         for my $flag (decode_flags(\%impflag,$_,1)) {
            if(defined @flag{uc($flag)}) {
               db_set_list($id+$start,"obj_flag",lc($flag));
            }
            if($flag eq "PLAYER") {
               @player{lc($name)} = $id;
               db_set($id+$start,"obj_name","imp_$name");
               db_set($id+$start,"obj_cname","imp_$name");
            }
         }
         db_set_list($id+$start,"obj_flag","imported");
      } elsif($.  - $pos == 12) {
         for my $flag (decode_flags(\%impflag,$_,2)) {
            if(defined @flag{lc($flag)}) {
               db_set_list($id+$start,"obj_flag",lc($flag));
            }
         }
      } elsif($_ =~ /^>(\d+)$/) {
         db_set($id+$start,"obj_created_date",scalar localtime());
         $attr_id = $1;
      } elsif($attr_id ne undef) {
         if(@attr{$attr_id} eq "A_PASS") { # set password to name
            db_set($id+$start,"obj_password",mushhash(lc("imp_$name")));
         } elsif(@attr{$attr_id} eq "A_DESC") { # set password to name
            db_set($id+$start,"DESCRIPTION",$_);
         } elsif(@attr{$attr_id} eq "A_LAST") { # set password to name
            db_set($id+$start,"obj_last",$_);
         } else {
            db_set($id+$start,@attr{$attr_id},$_);
         }
         $attr_id = undef;
      } elsif($_ =~ /^<$/) {                                  # end of object
#         printf("----[ End of $id ]----\n");
         $id = undef;
      } elsif(/^\*\*\*END OF DUMP\*\*\*$/) {
         # yay!
      } else {
         printf("UNKNOWN[$.,%s]: '$_'\n",$. - $pos);
#         exit();
      }

#      exit() if $id == 8;
   }
   close(FILE);

   post_db_read_fix($start);
   necho(self   => $self,
         prog   => $prog,
         source => [ "Import starts at object $start" ]
        );
   necho(self   => $self,
         prog   => $prog,
         source => [ "    Objects Imported: %s",$#db - $start ]
        );
}

while(1) {
#   eval {
      main();                                               #!# run only once
#   };
}
