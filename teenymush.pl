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
use Carp;
use IO::Select;
use IO::Socket;
use File::Basename;
use Text::Wrap;
use Digest::SHA qw(sha1 sha1_hex);
use Time::HiRes "ualarm";
use Scalar::Util qw(looks_like_number);
use Time::Local;
use Math::BigInt;
$Text::Wrap::huge = 'overflow';
use POSIX;
use Fcntl qw( SEEK_END SEEK_SET);

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
    %c,                        #!#
    %engine,                   #!# process holder for running
    %ansi_rgb,                 #!# color number to rgb code
    %ansi_name,                #!# color names to 256 color id
    %default,                  #!# default values for some config options

    #----[memory database structures]---------------------------------------#
    %help,                     #!# online-help
    @db,                       #!# whole database
    @delta,                    #!# db changes storage during @dump
    %dirty,                    #!# dirty "bit" to track db changes.
    %player,                   #!# player list for quick lookup
    @free,                     #!# free objects list
    %deleted,                  #!# deleted objects during backup
    %flag,                     #!# flag definition
   );                          #!#


# this should be a variable, but this allows us to reload the data
# without restarting the server.
sub version
{
   return "TeenyMUSH 0.91";
}

#
# load_modules
#    Some modules are "optional". Load these optional modules or disable
#    their use by setting the coresponding @info variable to -1.
#
# perl -MCPAN -e "install Net::WebSocket::Server"
sub load_modules
{
   my %mod = (
      'URI::Escape'            => 'uri_escape',       # liburi-encode-perl
      'Net::WebSocket::Server' => 'websocket',
      'Net::HTTPS::NB'         => 'url_https', # libnet-https-nb-perl
      'Net::HTTP::NB'          => 'url_http',
      'HTML::Entities'         => 'entities',
      'Digest::MD5'            => 'md5',
      'File::Copy'             => 'copy',
      'HTML::Restrict'         => 'html_restrict',   # libhtml-restrict-perl
      'MIME::Base64'           => 'mime',
      'Compress::Zlib'         => 'compress',
      'Net::DNS'               => 'dns',
      'Cwd'                    => 'cwd'
   );

   for my $key (keys %mod) {
      if(!defined @info{"@mod{$key}"} || @info{"@mod{$key}"} eq undef) {
	 @info{"@mod{$key}"} = 1;
         eval "use $key; 1;" or @info{"@mod{$key}"} = -1;
         if(@info{"@mod{$key}"} == -1) {
            printf("WARNING: Missing $key module, @mod{$key} disabled\n");
         }
      }
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

#
# getbinfile
#    Load a binary file into memory, such as a jpg for use by
#    httpd.
#
sub getbinfile
{
   my $fn = shift;
   my ($file, $content);

   open($file,"txt/$fn") || return undef;
   binmode($file);

   {
      local $/;
      $content =  <$file>;
   };
   close($file);
   return $content;
}

#
# load_defaults
#    Default values for common configuration items. This is handled as a
#    list of sets to allow reloading while running.
#
sub load_defaults
{
   delete @default{keys %default};
   @default{max}                      = 78;
   @default{dump_interval}            = 3600;
   @default{master_override}          = "no";
   @default{money_name_plural}        = "Pennies";
   @default{money_name_singular}      = "Penny";
   @default{paycheck}                 = 50;
   @default{starting_room}            = 1;
   @default{starting_money}           = 150;
   @default{linkcost}                 = 1;
   @default{digcost}                  = 10;
   @default{createcost}               = 10;
   @default{function_limit}           = 2500;
   @default{weblog}                   = "yes";
   @default{conlog}                   = "yes";
   @default{auditlog}                 = "yes";
   @default{httpd_invalid}            = 3;
   @default{login}                    = "Welcome to TeenyMUSH\r\n\r\n" .
                                        "Type the below command to " .
                                        "customize this screen after loging ".
                                        "in as God.\r\n\r\n    &conf.login #0" .
                                        "= Login screen\r\n\r\n";
   @default{badsite}                  = "Your site has been banned.";
   @default{httpd_template}           = "<pre>";
   @default{mudname}                  = "TeenyMUSH";
   @default{port}                     = "4096,4201,6250";
   @default{starting_quota}           = 5;
   @default{single_dirty_file}        = "yes";
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

#
# process_commandline
#    Allow the user to set config attributes when the mush is not running.
#    The mush will dump a new db and shutdown when complete.
#
sub process_commandline
{
   my $hit  = 0;
   my $value;

   if(conf_true("safemode")) {
      set(obj(0),{},0,"conf.safemode");
   }

   for my $i (0 .. $#ARGV) {             # set conf attributes from cmdline
      if(@ARGV[$i] =~ /^-{1,2}D([^=]+)(=)/ ||
         @ARGV[$i] =~ /^-{1,2}D([^=]+)$/) {
         if($2 eq "=" && $' eq undef) {
            con(" - Deleting conf.%s setting\n",$1);
            $value = undef;
         } elsif($2 eq "=") {
            con(" + Setting conf.%s to %s\n",$1,$');
            $value = $';
         } else {
            con(" + Setting conf.%s to on\n",$1,$');
            $value = 1;
         }
         set(obj(0),{},0,"conf.$1",$value);
         $hit = 1 if $1 ne "safemode";
      }
   }

   if($hit) {
     printf("\nShutting down as per commandline defines.\n");
     cmd_dirty_dump(obj(0),{});
     exit(0);
   }
}

#
# main
#   The one that rules them all
#
sub main
{
   @info{run} = 1;

   printf("%s\n",conf("version"));

   # trap signal HUP and try to reload the code
   $SIG{HUP} = sub {
      my $count = reload_code();
      delete @engine{keys %engine};
      con("HUP signal caught, reloading: %s\n",$count ? $count : "none");
   };

   load_modules();

   initialize_functions();
   initialize_ansi();
   initialize_commands();
   initialize_flags();
   @info{source_prev} = get_source_checksums(1);
   reload_code();

   load_db();

   load_defaults();
   find_free_dbrefs();

   process_commandline();

   fun_mush_address(obj(0),{});                      # cache public address
   server_start();                                      #!# start only once
}

#
# initalize_ansi
#    Define colors numbers to rgb values and color names to color numbers
#    for use by ansi. This is handled as a list of sets to allow reloading
#    while running.
#
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

   @offline{connect}        = sub { return cmd_connect(@_);                 };
   @offline{who}            = sub { return cmd_who(@_);                     };
   @offline{create}         = sub { return cmd_pcreate(@_);                 };
   @offline{quit}           = sub { return cmd_quit(@_);                    };
   @offline{huh}            = sub { return cmd_offline_huh(@_);             };
   @offline{screenwidth}    = sub { return;                                 };
   @offline{screenheight}   = sub { return;                                 };
   # ------------------------------------------------------------------------#
   @command{"\@search"}     ={ fun => sub { return &cmd_search(@_);}        };
   @command{screenwidth}    ={ fun => sub { return 1;}                      };
   @command{screenheight}   ={ fun => sub { return 1;}                      };
   @command{"\@wall"}       ={ fun => sub { return &cmd_wall(@_);}          };
   @command{"\@read"}       ={ fun => sub { return &cmd_read(@_);}          };
   @command{"\@function"}   ={ fun => sub { return &cmd_function(@_);}      };
   @command{"\@imc"}        ={ fun => sub { return &cmd_imc(@_);}           };
   @command{"\@perl"}       ={ fun => sub { return &cmd_perl(@_); }         };
   @command{say}            ={ fun => sub { return &cmd_say(@_); }          };
   @command{"\""}           ={ fun => sub { return &cmd_say(@_); },  nsp=>1 };
   @command{"`"}            ={ fun => sub { return &cmd_to(@_); },   nsp=>1 };
   @command{"&"}            ={ fun => sub { return &cmd_set2(@_); }, nsp=>1 };
   @command{"\@reload"}     ={ fun => sub { return &cmd_reload_code(@_); }  };
   @command{pose}           ={ fun => sub { return &cmd_pose(@_); }         };
   @command{":"}            ={ fun => sub { return &cmd_pose(@_); }, nsp=>1 };
   @command{";"}            ={ fun => sub { return &cmd_pose(@_,1); },nsp=>1};
   @command{"emote"}        ={ fun => sub { return &cmd_pose(@_,1); },nsp=>1};
   @command{"\\"}           ={ fun => sub { return &cmd_slash(@_,1);},nsp=>1};
   @command{who}            ={ fun => sub { return &cmd_who(@_);  }         };
   @command{whisper}        ={ fun => sub { return &cmd_whisper(@_); }      };
   @command{w}              ={ fun => sub { return &cmd_whisper(@_); }      };
   @command{doing}          ={ fun => sub { return &cmd_DOING(@_); }        };
   @command{"\@doing"}      ={ fun => sub { return &cmd_doing(@_); }        };
   @command{"\@poll"}       ={ fun => sub { return &cmd_doing(@_[0],@_[1],
                                               @_[2],{ header=>1}); }       };
   @command{help}           ={ fun => sub { return &cmd_help(@_); }         };
   @command{"\@dig"}        ={ fun => sub { return &cmd_dig(@_); }          };
   @command{"\@idesc"}      ={ fun => sub { return &cmd_generic_set(@_); }  };
   @command{"\@parent"}     ={ fun => sub { return &cmd_parent(@_); }       };
   @command{"look"}         ={ fun => sub { return &cmd_look(@_); }         };
   @command{"l"}            ={ fun => sub { return &cmd_look(@_); }         };
   @command{quit}           ={ fun => sub { return &cmd_quit(@_); }          };
   @command{"\@trigger"}    ={ fun => sub { return &cmd_trigger(@_); }       };
   @command{"\@set"}        ={ fun => sub { return &cmd_set(@_); }           };
   @command{"\@cls"}        ={ fun => sub { return &cmd_clear(@_); }         };
   @command{"\@create"}     ={ fun => sub { return &cmd_create(@_); }        };
   @command{"print"}        ={ fun => sub { return &cmd_print(@_); }         };
   @command{"go"}           ={ fun => sub { return &cmd_go(@_); }            };
   @command{"home"}         ={ fun => sub { return &cmd_home(@_); }          };
   @command{"examine"}      ={ fun => sub { return &cmd_ex(@_); }            };
   @command{"ex"}           ={ fun => sub { return &cmd_ex(@_); }            };
   @command{"e"}            ={ fun => sub { return &cmd_ex(@_); }            };
   @command{"\@last"}       ={ fun => sub { return &cmd_last(@_); }          };
   @command{page}           ={ fun => sub { return &cmd_page(@_); }          };
   @command{p}              ={ fun => sub { return &cmd_page(@_); }          };
   @command{take}           ={ fun => sub { return &cmd_take(@_); }          };
   @command{get}            ={ fun => sub { return &cmd_take(@_); }          };
   @command{drop}           ={ fun => sub { return &cmd_drop(@_); }          };
   @command{"\@force"}      ={ fun => sub { return &cmd_force(@_); }         };
   @command{inventory}      ={ fun => sub { return &cmd_inventory(@_); }     };
   @command{i}              ={ fun => sub { return &cmd_inventory(@_); }     };
   @command{enter}          ={ fun => sub { return &cmd_enter(@_); }         };
   @command{leave}          ={ fun => sub { return &cmd_leave(@_); }         };
   @command{"\@name"}       ={ fun => sub { return &cmd_name(@_); }          };
   @command{"\@moniker"}    ={ fun => sub { return &cmd_name(@_); }          };
   @command{"\@describe"}   ={ fun => sub { return &cmd_generic_set(@_); }   };
   @command{"\@pemit"}      ={ fun => sub { return &cmd_pemit(@_); }         };
   @command{"\@emit"}       ={ fun => sub { return &cmd_emit(@_); }          };
   @command{"think"}        ={ fun => sub { return &cmd_think(@_); }         };
   @command{"version"}      ={ fun => sub { return &cmd_version(@_); }       };
   @command{"\@version"}    ={ fun => sub { return &cmd_version(@_); }       };
   @command{"\@link"}       ={ fun => sub { return &cmd_link(@_); }          };
   @command{"\@teleport"}   ={ fun => sub { return &cmd_teleport(@_); }      };
   @command{"\@tel"}        ={ fun => sub { return &cmd_teleport(@_); }      };
   @command{"\@open"}       ={ fun => sub { return &cmd_open(@_); }          };
   @command{"\@uptime"}     ={ fun => sub { return &cmd_uptime(@_); }        };
   @command{"\@destroy"}    ={ fun => sub { return &cmd_destroy(@_); }       };
   @command{"\@wipe"}       ={ fun => sub { return &cmd_wipe(@_); }          };
   @command{"\@toad"}       ={ fun => sub { return &cmd_toad(@_); }          };
   @command{"\@sleep"}      ={ fun => sub { return &cmd_sleep(@_); }         };
   @command{"\@wait"}       ={ fun => sub { return &cmd_wait(@_); }          };
   @command{"\@sweep"}      ={ fun => sub { return &cmd_sweep(@_); }         };
   @command{"\@list"}       ={ fun => sub { return &cmd_list(@_); }          };
   @command{"\@mail"}       ={ fun => sub { return &cmd_mail(@_); }          };
   @command{"score"}        ={ fun => sub { return &cmd_score(@_); }         };
   @command{"\@telnet"}     ={ fun => sub { return &cmd_telnet(@_); }        };
   @command{"\@close"}      ={ fun => sub { return &cmd_close(@_); }         };
   @command{"\@reset"}      ={ fun => sub { return &cmd_reset(@_); }         };
   @command{"\@send"}       ={ fun => sub { return &cmd_send(@_); }          };
   @command{"\@password"}   ={ fun => sub { return &cmd_password(@_); }      };
   @command{"\@newpassword"}={ fun => sub { return &cmd_newpassword(@_); }   };
   @command{"\@switch"}     ={ fun => sub { return &cmd_switch(@_); }        };
   @command{"\@select"}     ={ fun => sub { return &cmd_switch(@_); }        };
   @command{"\@ps"}         ={ fun => sub { return &cmd_ps(@_); }            };
   @command{"\@kill"}       ={ fun => sub { return &cmd_killpid(@_); }       };
   @command{"\@var"}        ={ fun => sub { return &cmd_var(@_); }           };
   @command{"\@dolist"}     ={ fun => sub { return &cmd_dolist(@_); }        };
   @command{"\@notify"}     ={ fun => sub { return &cmd_notify(@_); }        };
   @command{"\@drain"}      ={ fun => sub { return &cmd_drain(@_); }         };
   @command{"\@while"}      ={ fun => sub { return &cmd_while(@_); }         };
   @command{"\@crash"}      ={ fun => sub { return &cmd_crash(@_); }         };
   @command{"\@\@"}         ={ fun => sub { return;}                         };
   @command{"\@lock"}       ={ fun => sub { return &cmd_lock(@_);}           };
   @command{"\@boot"}       ={ fun => sub { return &cmd_boot(@_);}           };
   @command{"\@halt"}       ={ fun => sub { return &cmd_halt(@_);}           };
   @command{"\@sex"}        ={ fun => sub { return &cmd_generic_set(@_);}    };
   @command{"\@apay"}       ={ fun => sub { return &cmd_generic_set(@_);}    };
   @command{"\@opay"}       ={ fun => sub { return &cmd_generic_set(@_);}    };
   @command{"\@pay"}        ={ fun => sub { return &cmd_generic_set(@_);}    };
   @command{"give"}         ={ fun => sub { return &cmd_give(@_);}           };
   @command{"\@squish"}     ={ fun => sub { return &cmd_squish(@_);}         };
   @command{"\@websocket"}  ={ fun => sub { return &cmd_websocket(@_); }     };
   @command{"\@find"}       ={ fun => sub { return &cmd_find(@_); }          };
   @command{"\@bad"}        ={ fun => sub { return &cmd_bad(@_); }           };
   @command{"\@dump"}       ={ fun => sub { return &cmd_dump(@_); }          };
   @command{"\@dirty_dump"} ={ fun => sub { return &cmd_dirty_dump(@_); }    };
   @command{"\@import"}     ={ fun => sub { return &cmd_import(@_); }        };
   @command{"\@stats"}      ={ fun => sub { return &cmd_stats(@_); }         };
   @command{"\@cost"}       ={ fun => sub { return &cmd_generic_set(@_); }   };
   @command{"\@quota"}      ={ fun => sub { return &cmd_quota(@_); }         };
   @command{"\@player"}     ={ fun => sub { return &cmd_player(@_); }        };
   @command{"\@big"}        ={ fun => sub { return &cmd_big(@_); }           };
   @command{"huh"}          ={ fun => sub { return &cmd_huh(@_); }           };
   @command{"\@capture"}    ={ fun => sub { return &cmd_capture(@_); }       };
   @command{"\@\@"}         ={ fun => sub { return 1; }                      };
   @command{"\@shutdown"}   ={ fun => sub { return &cmd_shutdown(@_); }      };
   @command{"train"}        ={ fun => sub { return &cmd_train(@_); }         };
   @command{"teach"}        ={ fun => sub { return &cmd_train(@_); }         };
   @command{"\@restore"}    ={ fun => sub { return &cmd_restore(@_); }       };
   @command{"\@ping"}       ={ fun => sub { return &cmd_ping(@_); }          };
   @command{"\@ban"}        ={ fun => sub { return &cmd_ban(@_); }           };
   @command{"\@missing"}    ={ fun => sub { return &cmd_missing(@_); }       };
   @command{"\@motd"}       ={ fun => sub { return &cmd_motd(@_); }          };
   @command{"\@chown"}      ={ fun => sub { return &cmd_chown(@_); }         };
   @command{"\@nohelp"}     ={ fun => sub { return &cmd_nohelp(@_); }         };

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
   delete @command{va};
   delete @command{var};
}


# ------------------------------------------------------------------------#

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

sub restore_process_line
{
   my ($obj, $atr,$state,$list,$line) = @_;

   $line =~ s/\r|\n//g;
   $$state{chars} += length($_);
   if($$state{obj} eq undef &&  $line =~                            # header
      /^server: ([^,]+), dbversion=([^,]+), exported=([^,]+), type=/) {
      $$state{ver} = $2;
   } elsif($line =~ /^\*\* Dump Completed (.*) \*\*$/) {
      $$state{complete} = 1;                                  # dump complete
   } elsif($$state{obj} eq undef && $line =~ /^obj\[(\d+)]\s*{\s*$/) {
      $$state{obj} = $1;                                    # start of object
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):M:/) {
      if($$state{obj} eq $obj && $atr eq $1) {
         if(!defined $$list{single_line(db_unsafe($'))}) {
            $$list{single_line(db_unsafe($'))} = $3;
         } elsif($$list{single_line(db_unsafe($'))} < $3) {
            $$list{single_line(db_unsafe($'))} = $3;
         }
      }
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):A:/) {
      if($$state{obj} eq $obj && $atr eq $1) {
         if(!defined $$list{single_line(db_unsafe($'))}) {
            $$list{single_line(db_unsafe($'))} = $3;
         } elsif($$list{single_line(db_unsafe($'))} < $3) {
            $$list{single_line(db_unsafe($'))} = $3;
         }
      }
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):L:/) {
#      not restoring lists?
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):H:/) {
#      not restoring hash lists?
   } elsif($$state{obj} ne undef && $line =~ /^\s*}\s*$/) {    # end of object
      delete @$state{obj};
      delete @$state{type};
      delete @$state{loc};
   } else {
#      con("Unable to parse[$$state{obj}]: '%s'\n",$line);
#      printf("Unable to parse[$$state{obj}]: '%s'\n",$line);
#      printf("%s\n",code("long"));
   }
}

sub cmd_chown
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my ($o,$t) = besplit($self,$prog,$txt,"=");
   my $target;

   if($t ne undef) {
      $target = find_player($self,$prog,$t) ||
         return err($self,$prog,"*Unknown player.");
   } else {
      $target = $self;
   }

   my $obj = find($self,$prog,$o) ||           # can't find object to chown
      return err($self,$prog,"I don't see that here. '$o'");

   if(hasflag($obj,"PLAYER")) {
      return err($self,$prog,"Players can not be \@chowned.");
   } elsif(quota_left($target) <= 0) {
      err($self,$prog,name($target) . " does not have enough quota to " .
         "\@chown that object");
   }

   if(!or_flag($self,"WIZARD","GOD") && $t ne undef) {
      return err($self,$prog,"Permission denied");
   } elsif(!or_flag($self,"WIZARD","GOD")) {
      if(hasflag($obj,"OBJECT") && $$target{obj_id} != loc($obj)) {
         err($self,$prog,"You don't have that!");
      } elsif(hasflag($obj,"EXIT") && loc($target) != loc($obj)) {
         err($self,$prog,"You must be in the same as the exit to \@chown it.");
      } elsif(hasflag($obj,"ROOM") && loc($target) != $obj) {
         err($self,$prog,"You must be in the room to \@chown it.");
      } elsif(!hasflag($obj,"CHOWN_OK")) {
         err($self,$prog,"Permission denied: The object must be set CHOWN_OK");
      }
   }

   set_quota($obj,"add",1);
   db_set($obj,"obj_owner",$$target{obj_id});
   set_flag($self,$prog,$obj,"HALTED");
   necho(self => $self,
         prog => $prog,
         source => [ "Set." ]
        );
}


sub cmd_motd
{
   my ($self,$prog,$txt,$switch) = @_;

   verify_switches($self,$prog,$switch,"list") ||
      return;

   !or_flag($self,"WIZARD","GOD") &&
      return err($self,$prog,"Permission denied.");

   if(defined $$switch{list}) {
      necho(self => $self,
            prog => $prog,
            source => [ "MOTD: %s", conf("motd") ]
           );
   } else {
      set($self,
          $prog,
          obj(0),
          "conf.motd",
          $txt
         );
   }
}
#
# cmd_missing
#    Report on missing commands or functions
#
sub cmd_missing
{
   my ($self,$prog,$txt,$switch) = @_;

   $$prog{missing} = {};                         # setup storage structure
   $$prog{missing}->{fun} = {};
   $$prog{missing}->{cmd} = {};

   mushrun(self   => $self,                         # run specified command
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => $txt
          );
}
#
# cmd_ban
#   List or remove http ban entries.
#
sub cmd_ban
{
   my ($self,$prog,$txt,$switch) = @_;
   my (@out, $count);

   verify_switches($self,$prog,$switch,"unban") ||
      return;

   !or_flag($self,"WIZARD","GOD") &&
      return err($self,$prog,"Permission denied.");

   my $hash = @info{httpd_ban};
   my $pat = glob2re(evaluate($self,$prog,$txt)) if($txt ne undef);

   if(defined $$switch{unban}) {                           # delete entries
      my $count = 0;
      for my $key (keys %$hash) {
         eval {                                # protect against bad patterns?
            if($pat eq undef || $key =~ /$pat/) {
               $count++;
               delete @$hash{$key};
            }
         };
      }
      necho(self    => $self,
            prog   => $prog,
            source => [ "%d entries removed.", $count ]
           );
   } else {                                   # show reverse date sorted list
      for my $key (sort {fuzzy($$hash{$b}) <=> fuzzy($$hash{$a})} keys %$hash) {
         eval {                                # protect against bad patterns?
            if($pat eq undef || $key =~ /$pat/) {
               push(@out,sprintf("%-55s  %s",$key,ts(fuzzy($$hash{$key}))));
            }
         };
      }

      if($#out == -1) {                                      # show results
         necho(self    => $self,
               prog   => $prog,
               source => [ "No sites matched." ]
              );
      } else {
         necho(self    => $self,
               prog   => $prog,
               source => [ "%s", join("\n",@out) ]
              );
      }
   }
}

#
# cmd_ping
#    Internal command for finding out which object/attribute match the
#    provided command.
#
sub cmd_ping
{
   my ($self,$prog,$cmd) = @_;
   my $tmp = $$prog{ping};            # save ping variable if already set?

   $$prog{ping} = 1; # tell mush command is just a ping
   my $fake = {
      runas => $self,
      created_by => $self,
      cmd => $cmd,
   };
   spin_run($prog,$fake);

   if($tmp eq undef) {
      delete @$prog{tmp};
   } else {
      $$prog{ping} = $tmp;
   }
}

sub cmd_restore
{
   my ($self,$prog) = (obj(shift),shift);
   my $cmd = $$prog{cmd};
   my @list;

   if(in_run_function($prog)) {
      return out($prog,"#-1 \@DUMP can not be called from RUN function");
   } elsif(!hasflag($self,"WIZARD") && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   }

   if(!defined $$cmd{restore_list}) {                 # initialize "loop"
      ($$cmd{obj},$$cmd{atr}) = balanced_split(shift,"/",4);

      if($$cmd{obj} ne undef && $$cmd{atr} eq undef) {
         if($$cmd{obj} =~ /^\s*#(\d+)\s*/) {
            $$cmd{obj} = $1;
         } else {
            return err($self,$prog,"usage: \@resTore <#dbref> '$$cmd{obj}'\n" .
                                   "       \@restore <object>/<attribute>");
         }
         if(valid_dbref($$cmd{obj})) {
            return err($self,$prog,"\@restore only a \@destroyed object");
         }
      } elsif($$cmd{obj} ne undef && $$cmd{atr} ne undef) {
         my $target = find($self,$prog,$$cmd{obj}) ||      # can't find target
            return err($self,$prog,"No match on object.");
         $$cmd{obj} = $$target{obj_id};
      } elsif($$cmd{obj} eq undef && $$cmd{atr} eq undef) {
         return err($self,$prog,"usage: \@restore <#dbref>\n" .
                                   "       \@restore <object>/<attribute>");
      }

      if(!defined $$cmd{restore_list}) {                 # initialize "loop"
         my $dir;
         $$cmd{restore_file} = [];
         $$cmd{restore_list} = {};

         opendir($dir,"dumps") ||
            return err($self,$prog,"Could not open directory dumps.");

         for my $file (readdir($dir)) {
            if($file =~ /\.tdb$/) {
               push(@{$$cmd{restore_file}},$file);
            }
         }
         closedir($dir);

         necho(self    => $self,
               prog   => $prog,
               source => [ "Restoring from %s db files in dumps folder...",
                         $#{$$cmd{restore_file}} ],
              );
      }
   }

   if($#{$$cmd{restore_file}} == -1) {
      if($$cmd{atr} eq undef) {                           # object not found
         necho(self    => $self,
               prog   => $prog,
               source => [ "Restore object #%s failed, not found.", $$cmd{obj}]
              );
         return "DONE";
      }

      my $list = $$cmd{restore_list};
      my $count = 0;
      delete @$list{single_line(get($$cmd{obj},$$cmd{atr}))};

      for my $i (keys %$list) {
         db_set($$cmd{obj},$$cmd{atr} . "_" . @$list{$i},$i);  # copy attr back
         $count++;
      }
      necho(self    => $self,
            prog   => $prog,
            source => [ "Restore done: %s versions restored to #%s/%s_*",
                        $count, $$cmd{obj},$$cmd{atr} ]
           );
      return "DONE";
   } elsif(defined $$cmd{restore_fd}) {
      my $fd = $$cmd{restore_fd};
      my $count = 0;
#      printf("    RESTORE: $fd\n");
#      printf("    # %s\n",<$fd>);

      while(<$fd>) {
         if($$cmd{atr} ne undef) {
            restore_process_line($$cmd{obj},
                                 $$cmd{atr},
                                 $$cmd{restore_state},
                                 $$cmd{restore_list},
                                 $_
                                );
         } else {
            db_process_line($$cmd{restore_state},
                            $_,
                            $$cmd{obj}
                           );
         }
         if(++$count > 500) {                       # 500 lines max at a time
            return "RUNNING";
         }
      }
      close($fd);
      delete @$cmd{restore_fd};                          # dump file is done

      if($$cmd{atr} eq undef && valid_dbref($$cmd{obj})) {
         necho(self    => $self,
               prog   => $prog,
               source => [ "\@restore of object #%s complete.", $$cmd{obj} ]
              );
         return "DONE";
      }
      return "RUNNING";
   } else {
      my $fd;
      my $fn = "dumps/" . pop(@{$$cmd{restore_file}});
#      printf("Restore: $fn\n");
      open($fd,$fn);      # get file to process
      $$cmd{restore_fd} = $fd;
      $$cmd{restore_state} = {};
      return "RUNNING";
   }
}

#
# cmd_train
#    Command to echo the unevaluated command followed by the results
#    for training purposes.
#
sub cmd_train
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   necho(self    => $self,
         prog   => $prog,
         room   => [ $self, "%s types -=> %s", name($self),$txt ],
         source => [ "%s types -=> %s",name($self),$txt ]
        );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => $txt
          );
}
#
# cmd_home: move the player to their home
#
sub cmd_home
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   if($txt !~ /^\s*$/) {                           # simulate non-command
       return cmd_huh($self,$prog);
   } else {
       cmd_go($self,$prog,"home");
   }
}

#
# cmd_wall
#    Send a message to everyone or just the wizards
#
sub cmd_wall
{
   my ($self,$prog) = (obj(shift),shift);
   my ($msg,$hash);

   hasflag($self,"GOD") || hasflag($self,"WIZARD") ||
      return err("Permission denied.");

   my $txt = evaluate($self,$prog,shift);
   my $switch = shift;

   verify_switches($self,$prog,$switch,"emit","pose","wizard","no_prefix") ||
      return;

   if($$switch{emit}) {                              # determine msg format
      $msg = "Announcment: " . trim($txt);
   } elsif($$switch{pose}) {
      $msg = "Announcment: " . name($self) . " " . trim($txt);
   } elsif($$switch{wizard}) {
      $msg = "Broadcast: " . name($self) . " says, \"" . trim($txt) . "\"";
   } elsif($$switch{no_prefix}) {
      $msg = name($self) . " shouts, \"" . trim($txt) . "\"";
   } else {
      $msg = "Announcment: " . name($self) . " shouts, \"" . trim($txt) . "\"";
   }

   for my $key (keys %connected) {
      $hash = @connected{$key};
      next if $$hash{raw} != 0;
      next if($$switch{wizard} && !hasflag($hash,"WIZARD"));

      necho(self => $self,
            prog => $prog,
            target => [ $hash, "%s", $msg ]
           );
   }
}

sub cmd_shutdown
{
   my ($self,$prog) = (obj(shift),shift);

   hasflag($self,"GOD") || hasflag($self,"WIZARD") ||
      return err("Permission denied.");

   cmd_wall($self,$prog,$_[0]) if($_[0] !~ /^\s*/);

   audit($self,$prog,"\@shutdown");

   for my $key (keys %connected) {
      my $hash = @connected{$key};
      necho(self   => $self,
            prog   => $prog,
            target => [ $hash, "%s has been shutdown by %s.",
                        conf("mudname"),obj_name($self,$self,1) ]
      );
      cmd_boot($self,$prog,"#" . $$hash{obj_id});
   }
   @info{run} = 0;                           # signal shutdown
   @info{shutdown_by} = obj_name($self,$self,1);
}

sub cmd_slash
{
   my ($self,$prog) = (obj(shift),shift);
   my $txt = @{$$prog{cmd}}{cmd};

   if($txt =~ /^\\\\/) {
      cmd_emit($self,$prog,$');
   } elsif($txt =~ /^\s\\$/) {
      # no op, do nothing.
   } elsif($txt =~ /^\\ /) {
      cmd_emit($self,$prog,$txt);
   }
}

sub cmd_parent
{
   my ($self,$prog) = (obj(shift),shift);
   my $parent;

   my ($object,$par) = balanced_split(shift,"=",4);

   my $target = find($self,$prog,$object) ||            # can't find target
      return err($self,$prog,"No match on object.");

   controls($self,$target) ||
      return err($self,$prog,"Permission denied on target.");

   if($par !~ /^\s*$/) {                                       # set parent
      $parent = find($self,$prog,$par) ||               # can't find parent
         return err($self,$prog,"No match on parent.");

      controls($self,$parent) ||
         return err($self,$prog,"Permission denied on parent.");
   }

   if($parent eq undef) {
      set($self,$prog,$target,"obj_parent",undef,1);
      necho(self   => $self,
            prog   => $prog,
            source => [ "Unset." ]
      );
   } else {
      set($self,$prog,$target,"obj_parent",$$parent{obj_id},1);
      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ]
      );
   }
}


sub cmd_capture
{
   my ($self,$prog) = (obj(shift),shift);

   my ($attr,$command) = balanced_split(shift,"=",4);
   $attr = evaluate($self,$prog,$attr);
   $command = evaluate($self,$prog,$command);

   if($attr eq undef || $command eq undef) {
      return err($self,$prog,"Usage: \@capture [attribute] = [command]");
   }

   $$prog{capture} = { type => "pemit",
                       attr => trim($attr),
                       output => $$prog{output},
                       self => $self
                     };

   necho(self   => $self,
         prog   => $prog,
         source => [ "Capture started (%s / %s)." , $attr,$command]
   );

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $self,
           source => 0,
           cmd    => trim($command),
           output => [],
          );
}

sub cmd_search
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my (@out, $start,$max);

   # if in run() search entire db, or 100 at a time
   my $max = in_run_function($prog) ? $#db + 1 : 100;

   my $cmd = $$prog{cmd};
   if(!defined $$cmd{search_pos}) {                       # initialize "loop"
      if($txt =~ /(type|flags|eval|object)\s*=\s*/i) {
         $txt = $`;
         $$cmd{search_type} = lc($1);
         $$cmd{search_txt} = $';

         if($$cmd{search_type} eq "type") {
            if($$cmd{search_txt} =~ /^\s*(room|player|object|exit)\s*$/i) {
               $$cmd{search_txt} = lc($1);
            } else {
               return err($self,$prog,"$$cmd{search_txt}: unknown type");
            }
         }
      }

      if($txt =~ /^\s*$/) {                         # default to current user
         $$cmd{search_target} = $self;
      } else {                                            # use provided user
         $$cmd{search_target} = find_player($self,$prog,$txt) ||
            return err($self,$prog,"Unknown player.");
      }
      $$cmd{search_pos} = 0;
      $$cmd{out} = [];
      $$prog{iter_stack} = [] if !defined $$prog{iter_stack};
      $$cmd{search_loc} = $#{$$prog{iter_stack}} + 1;
   }

   for($start=$$cmd{search_pos};                   # loop for $max objects
          $$cmd{search_pos} < $#db &&
          $$cmd{search_pos} - $start < $max;
          $$cmd{search_pos}++) {
      if(valid_dbref($$cmd{search_pos})) {              # does object match?
         if(owner_id($$cmd{search_pos}) == @{$$cmd{search_target}}{obj_id}) {
            my $add = 1;
            if($$cmd{search_type} eq "flags") {
               for my $letter (split(//,$$cmd{search_txt})) {
                  $add = 0 if(!hasflag($$cmd{search_pos},$letter));
               }
            } elsif($$cmd{search_type} eq "type") {
               $add = 0 if(!hasflag($$cmd{search_pos},$$cmd{search_txt}));
            } elsif($$cmd{search_type} eq "object") {
               if(lc(substr(name($$cmd{search_pos}),0,
                  length($$cmd{search_txt}))) ne lc($$cmd{search_txt})) {
                  $add = 0;
               }
            } elsif($$cmd{search_type} eq "eval") {
               my $array = $$prog{iter_stack};
               $$array[$$cmd{search_loc}] =
                  {val => "#$$cmd{search_pos}", pos => 1 };
               if(evaluate($self,$prog,$$cmd{search_txt}) == 0) {
                  $add = 0;
               }
               delete @$array[$$cmd{search_loc} .. $#$array];
            }

            if($add) {
               if(defined $$prog{nomushrun}) {
                  push(@{$$cmd{out}},"#$$cmd{search_pos}");
               } else {
                  push(@{$$cmd{out}},obj_name($self,$$cmd{search_pos}));
               }
            }
         }
      }
   }

   if($$cmd{search_pos} >= $#db) {                          # search is done
      delete @$cmd{search_pos};

      if($#{$$cmd{out}} == -1) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Nothing found." ]
           );
      } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ join(($$prog{nomushrun}) ? " " : "\n",@{$$cmd{out}})]
           );
      }
   } else {
      return "RUNNING";                                     # more to do
   }
}


sub cmd_big
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
   my (@out, $start);

   if(defined $$prog{nomushrun}) {
      return err($self,$prog,"This command is not run() safe.");
   }

   my $cmd = $$prog{cmd};
   if(!defined $$cmd{big_pos}) {                       # initialize "loop"
      $$cmd{big_pos} = 0;
      $$cmd{hash} = {};
   }
   my $hash = $$cmd{hash};

   for($start=$$cmd{big_pos};                   # loop for 100 objects
          $$cmd{big_pos} < $#db &&
          $$cmd{big_pos} - $start < 100;
          $$cmd{big_pos}++) {
      if(valid_dbref($$cmd{big_pos})) {              # does object match?
         if($txt eq "player") {
            $$hash{name(owner($$cmd{big_pos}))} += length(db_object($$cmd{big_pos}));
         } else {
            $$hash{length(db_object($$cmd{big_pos}))} = $$cmd{big_pos};
         }
      }
   }
   if($$cmd{big_pos} >= $#db) {                          # search is done
      delete @$cmd{big_pos};
      my @out;

      if($txt eq "player") {
         for my $i (sort {$$hash{$b} <=> $$hash{$a}} keys %$hash) {
            push(@out,"$i is $$hash{$i} bytes.");
             last if $#out > 10;
         }
      } else {
         for my $i (sort {$b <=> $a} keys %$hash) {
             push(@out,"#" . $$hash{$i} . " is " . $i . " bytes.");
             last if $#out > 10;
         }
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ join("\n",@out) ]
        );
      delete @$cmd{big_pos};
   } else {
      return "RUNNING";                                     # more to do
   }
}

sub list_user_functions
{
   my $out;

   if(!defined @info{mush_function} || ref(@info{mush_function}) ne "HASH") {
      return "No user functions defined.";
   }

   $out  = sprintf("%-28s  %-10s  %s\n","Function Name","Dbref","Attribute");
   $out .= sprintf("%s  %s  %s\n","-" x 28,"-" x 10,"-" x 30);
   for my $key (keys %{@info{mush_function}}) {
      if(@info{mush_function}->{$key} =~ /\//) {
         $out .= sprintf("%-28s  %-10s  %s\n",
                         $key,
                         $`,
                         $'
                        )
      }
   }
   $out .= sprintf("%s  %s  %s\n","-" x 28,"-" x 10,"-" x 30);
}

sub cmd_function
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   hasflag($self,"WIZARD") ||
      return err($self,$prog,"Permission denied.");

   verify_switches($self,$prog,$switch,"list") || return;

   if(defined $$switch{list} || $txt =~ /^\s*$/) {
      necho(self   => $self,                                    # notify user
            prog   => $prog,
            source => [ list_user_functions() ]
           );
      return;
   }

   my ($name,$atr) = besplit($self,$prog,shift,"=");

   if($name =~ /^\s*([a-z])([a-z0-9_]*)\s*$/) {
      $name = "$1$2";
   } else {
      return err($self,$prog,"Invalid user defined function name '$name'");
   }

   my $data = fun_get($self,$prog,trim($atr));

   if($atr eq undef) {
      return err($self,$prog,"Invalid object/attribute specified.");
   }

   @info{mush_function} = {} if(!defined @info{mush_function});

   @{@info{mush_function}}{$name} = trim($atr);

   necho(self   => $self,                                    # notify user
         prog   => $prog,
         source => [ "Set." ]
        );
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
         set_quota($target,"max",$1);
      } else {
         return err($self,$prog,"Invalid number ($value).");
      }
   }

   necho(self   => $self,                                    # notify user
         prog   => $prog,
         source => [ "%s Quota: %9s  Used: %9s",
                     obj_name($target),
                     quota($target,"max"),
                     quota($target,"used"),
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   my $cmd = $$prog{cmd};         # the command isn't passed in, so get it.

   if(lc($$cmd{mushcmd}) eq "\@desc" ||
      lc($$cmd{mushcmd}) eq "\@describe") {
      $$cmd{mushcmd} = "\@description";
   } elsif(defined @command{$$cmd{mushcmd}} &&
           defined @{@command{$$cmd{mushcmd}}}{full}) {
      $$cmd{mushcmd} = @{@command{$$cmd{mushcmd}}}{full};
   }

   cmd_set2($self,$prog,substr($$cmd{mushcmd},1) . " " . $txt,$switch);
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

   return $hash;
}

sub cmd_stats
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

#
# cmd_mail
#    Command for sending internal email.
#
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

#
# cmd_while
#    Loop while the expression is true
#
sub cmd_while
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
   my (%last,$first);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return out($prog,"#-1 \@WHILE can not be called from RUN function");

   my $cmd = $$prog{cmd};

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

#
# cmd_imc
#    interanal mush command - Execute a command without a password or
#    a messy temp file.
#
sub cmd_imc
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
   my (%last,$first);

   hasflag($self,"GOD") ||
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return err($self,$prog,"#-1 \@WHILE can not be called from RUN function");

   my $cmd = $$prog{cmd};

   if(!defined @info{imc} || ref(@info{imc}) ne "HASH") {
      return err($self,$prog,"imc command not recieved via HTTPD");
   } elsif(!defined $$cmd{imc_start}) {                  # initialize "loop"
      delete @info{sigusr1};
      $$cmd{imc_start} = time();
   } elsif(defined $$cmd{imc_running}) {                        # finished?
      delete @info{imc};
      delete @info{imc_running};
      delete @info{sigusr1};
      return "DONE";
   } elsif(time() - $$cmd{imc_start} > 10) {
      delete @info{imc};
      return err($self,$prog,"SIGUSR1 signal not recieved within 10 seconds");
   }

   my $hash = @info{imc};

   if(defined @info{sigusr1} &&              # wait for permission to start
      time() - @info{sigusr1} < 10 &&
      time() - $$hash{timestamp} < 10) {
      $$prog{from} = "ATTR";            # a lie, but it gets us where we want.
      mushrun(self   => $self,
              prog   => $prog,
              source => 0,
              cmd    => @{@info{imc}}{command},
              child  => 1
              );
      $$cmd{imc_running} = time();
   }
   $$prog{idle} = 1;
   return "RUNNING";
}


sub inlist
{
   my ($item,@list) = @_;

   for my $i (@list) {
      return 1 if(trim($item) eq trim($i));
   }
   return 0;
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
#   } elsif(name($obj) eq undef) {
#      return 1;
   } elsif(flag_list($obj,1) eq undef) {
      return 2;
   } else {
      return 0;
   }
}

sub cmd_bad
{
   my ($self,$prog) = (obj(shift),shift);
   my (@out, $start);

   if(defined $$prog{nomushrun}) {
      return err($self,$prog,"This command is not run() safe.");
   }

   my $cmd = $$prog{cmd};
   $$cmd{bad_pos} = 0 if(!defined $$cmd{bad_pos});     # initialize "loop"
   $$cmd{quota} = {} if(!defined $$cmd{quota});
   my $quota = $$cmd{quota};

   for($start=$$cmd{bad_pos};                   # loop for 100 objects
          $$cmd{bad_pos} < $#db &&
          $$cmd{bad_pos} - $start < 100;
          $$cmd{bad_pos}++) {
      if(valid_dbref($$cmd{bad_pos})) {              # does object match?
         if(!hasflag($$cmd{bad_pos},"PLAYER")) {
            $$quota{owner_id($$cmd{bad_pos})}++;
         }
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

            # arbitrarly choose exit over object due to previous bug.
            if(and_flag($$cmd{bad_pos},"EXIT","OBJECT")) {
               db_remove_list($$cmd{bad_pos},"obj_flag","OBJECT");
            }
            my $count += hasflag($$cmd{bad_pos},"PLAYER");
            $count += hasflag($$cmd{bad_pos},"OBJECT");
            $count += hasflag($$cmd{bad_pos},"EXIT");
            $count += hasflag($$cmd{bad_pos},"ROOM");

            if($count != 1) {
               push(@out,obj_name($$cmd{bad_pos}) ." has $count types.");
            }

            if(hasflag($$cmd{bad_pos},"EXIT") &&
               hasflag(loc($$cmd{bad_pos}),"EXIT")) {
               my $loc = loc($$cmd{bad_pos});
               push(@out,
                    "#" . obj_name($self,$$cmd{bad_pos}) .
                    " not in a room, is in " .
                    (($loc eq undef) ? "N/A" : obj_name($self,$loc))
                   );
            }

            if(hasflag($$cmd{bad_pos},"PLAYER") &&
               money($$cmd{bad_pos}) eq undef) {
               push(@out,"#" . $$cmd{bad_pos} ." no money");
               db_set($$cmd{bad_pos},"obj_money",conf("starting_money"));
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
      my $hash = $$cmd{quota};

      for(my $obj=0;$obj < $#db;$obj++) {
         if(valid_dbref($obj) && hasflag($obj,"PLAYER")) {
            if(quota($obj,"used") != $$hash{$obj}) {
               push(@out,"#" . obj_name($obj) .
                    "'s used quota updated to " . $$hash{$obj} .
                    " from " .  quota($obj,"left"));
               set_quota($obj,"used",$$hash{$obj});
            }
         }
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ join("\n",@out) . "\n**End of List***" ]
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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
   my ($start,@out);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   if(defined $$prog{nomushrun}) {
      out($prog,"#-1 \@find can not be used in the run() function");
      return;
   }

   my $cmd = $$prog{cmd};

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
}


sub cmd_perl
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   if(hasflag($self,"GOD")) {
      audit($self,$prog,"\@perl");
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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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
      return err($self,$prog,"You don't have %s to give!");
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
                               conf("money_name_singular") :
                               conf("money_name_plural") ]
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
                     ($amount== 1) ? conf("money_name_singular") :
                                     conf("money_name_plural"),
                     name($target) ],
         target => [ $target, "%s gives you %s %s.",
                     name($self),
                     trim($amount),
                     ($amount == 1) ? conf("money_name_singular") :
                                      conf("money_name_plural") ]
        );

}


#
# mini_trigger
#    Used after the command envoked by capture has finished to run the
#    code which should be outputing the results.
#
sub mini_trigger
{
#   my ($self,$prog,$a,$data) = @_;

   my $prog = shift;                                  # setup some shortcuts
   my $self = $$prog{user};
   my $hash = $$prog{capture};
   my $out = $$prog{output};
   delete @$prog{capture};
   my $data;

   @{$$prog{cmd}}{done} = 1;

   # get output to send
   if(defined $$prog{output} && $#{$$prog{output}} >= 0) {
      $data = join("\n",@{$$prog{output}});
   } else {
      $data = "No data returned";
   }
   delete @$prog{output};                                         # clean up.

   my $cmd = pget($$hash{self},trim($$hash{attr}));

   if($cmd eq undef) {
      delete @$prog{capture};
      return err($self,$prog,"No such attribute");
   }

   # if @capture was called from inside session already recording output,
   # it needs to be "restored" byt passing in the output into the mushrun().
   if(defined @$hash{output} && ref($$hash{output}) eq "ARRAY") {
      # $$prog{output} = $$hash{output};
      mushrun(self   => $self,
              runas  => $$hash{self},
              prog   => $prog,
              source => 0,
              cmd    => $cmd,
              wild   => [ $data ],
              invoker=> $self,
              output => []
             );
    } else {
      mushrun(self   => $self,
              runas  => $$hash{self},
              prog   => $prog,
              source => 0,
              cmd    => $cmd,
              wild   => [ $data ],
              invoker=> $self,
             );
    }
}

sub cmd_trigger
{
   my ($self,$prog) = (obj(shift),obj(shift));
   my (@wild,$last,$target,$name);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   # find where the "=" is without evaluating things.
   my ($txt,$params) = balanced_split(shift,"=",4);
   my $switch = shift;

   # where the / is without evaluating things
   ($target,$name) = balanced_split($txt,"\/",4);

   # okay to evaluate object / attribute
   $target = find($self,$prog,evaluate($self,$prog,$target));
   $name = trim(evaluate($self,$prog,$name));

   return err($self,$prog,"No match.") if($target eq undef);

   my $attr = pget($target,$name,1) ||
      return err($self,$prog,"No such attribute.");


#   printf("ATTR: '%s'\n",$$attr{value});

   if(!defined $$attr{glob} && !controls($self,$target)) {
      return err($self,$prog,"PermiSsion denied");
   }

#   for my $i (balanced_split($params,',',2)) {             # split param list
#      if($$switch{noeval} && $last eq undef) {
#         printf("Add[1]: $i\n");
#         $last = $i;
#      } elsif($$switch{noeval}) {
#         printf("Add[2]: $i\n");
#         push(@wild,$i);
#      } elsif($last eq undef) {
#         $last = evaluate($self,$prog,$i);
#         printf("Add[3]: %s\n",$last);
#      } else {
#         printf("Add[4]: %s\n",evaluate($self,$prog,$i));
#         push(@wild,evaluate($self,$prog,$i));
#      }
#   }
#   push(@wild,$last) if($last ne undef);
    for my $i (balanced_split($params,',',2)) {
       if($$switch{noeval}) {
         push(@wild,$i);
       } else {
	       #         printf("trig_Add: '%s' -> '%s'\n",$i,evaluate($self,$prog,$i));
         push(@wild,evaluate($self,$prog,$i));
       }
    }

    if($#wild >= 0) {   # first item is remainder, it should be last item
       push(@wild,shift(@wild));
    }

   # printf("SELF:  '$$self{obj_id}'\n");
   # printf("CMD:   '%s'\n",$$attr{value});
   # printf("RUNAS: '%s'\n",$$target{obj_id});
   # printf("WILD:  '%s'\n",join(',',@wild));
   # printf("PROG:  '%s'\n",$$prog{pid});
   # printf("%s\n",print_var($prog));

   mushrun(self   => $self,
           prog   => $prog,
           runas  => $target,
           source => 0,
           cmd    => $$attr{value},
           child  => 2,
           wild   => [ @wild ],
           invoker=> (defined $$prog{created_by}) ? $$prog{created_by} : $self,
          );
}

#
# cmd_huh
#    Unknown command has been issued. Handle the echoing of VERBOSE
#    here for the unknown command.
#
sub cmd_huh
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   $$prog{huh} = 1;
   if(defined $$prog{hint} &&
      ($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET")) {
      if(!(defined $$prog{from} && $$prog{from} eq "ATTR")) {
         $$prog{huh} = 1;
      }
   }
#   printf("%s\n",code("long"));
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

   # record missing command for @missing
   if(defined $$prog{missing} && ref($$prog{missing}) eq "HASH") {
      $$prog{missing}->{cmd}->{fun_extract($self,$prog,$txt,1,1)}++;
   }

#   printf("HUH: '%s'\n",$txt);

   if(lord(@{$$prog{cmd}}{cmd}) ne 0) {
      # printf("HuH: '%s' -> '%s'\n",$$self{obj_id},@{$$prog{cmd}}{cmd});
      necho(self   => $self,
            prog   => $prog,
            source => [ "Huh? (Type \"HELP\" for help.)" ]
           );
   }
}

sub cmd_offline_huh
{
   my $sock = $$user{sock};

   my $obj = obj(0);            #  show login in readonly mode
   my $prog = prog($obj,$obj,$obj);
   $$prog{read_only} = 1;
   if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
      ws_echo($sock,evaluate($obj,$prog,conf("login")));
   } else {
      printf($sock "%s\r\n",evaluate($obj,$prog,conf("login")));
   }
}


sub cmd_version
{
   my ($self,$prog) = (obj(shift),shift);
   my $src =  "https://github.com/c-hudson/teenymush";

   my $ver = (conf("version") =~ /^TeenyMUSH ([\d\.]+)$/i) ? $1 : "N/A";

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
   my ($self,$prog) = (obj(shift),shift);

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
   my ($self,$prog) = (obj(shift),shift);

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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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

sub set_var
{
   my ($prog,$var,$value) = @_;

   $$prog{var} = {} if(!defined $$prog{var});

   @{$$prog{var}}{$var} = $value;
   return 0;
}

sub cmd_var
{
   my ($self,$prog,$var,$rest);

   if($#_ == 2) {                                         # current behavior
      ($self,$prog,$var,$rest) = (obj(shift),shift,trim(shift),shift);
   } else {                                       # emulate previous behavior
      ($self,$prog,$var) = (obj(shift),shift,shift); # @var <var> = <value>
      if($var =~ /(=|\+=|-=|\*=|\/=|\+\+|\-\-)\s*/) {
         ($var,$rest) = (trim($`),$1 . $');
      }
   }
   $var = evaluate($self,$prog,$var);

   show_verbose($prog,$$prog{cmd});   # doesn't hit verbose code, so run it
   $$prog{var} = {} if !defined $$prog{var};

   if($var =~ /^\s*\d+/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Variables may not start with numbers\n" ],
           );
   } elsif($rest =~ /^\s*\+\+\s*$/) {                           # increment
       @{$$prog{var}}{$var}++;
   } elsif($rest =~ /^\s*\-\-\s*$/) {                            # decrement
      @{$$prog{var}}{$var}--;
   } elsif($rest =~ /^\s*\+=\s*/) {                                  # add
      @{$$prog{var}}{$var} += evaluate($self,$prog,$');
   } elsif($rest =~ /^\s*-=\s*/) {                                  # sub
      @{$$prog{var}}{$var} -= evaluate($self,$prog,$');
   } elsif($rest =~ /^\s*\*=\s*/) {                                  # mult
      @{$$prog{var}}{$var} *= evaluate($self,$prog,$');
   } elsif($rest =~ /^\s*\/=\s*/) {                                  # divide
      my $num = evaluate($self,$prog,$');

      if($num == 0) {
         return err($self,$prog,"Divide by Zero not allowed.");
      } else {
         @{$$prog{var}}{$var} = @{$$prog{var}}{$var} / $num;
      }
   } elsif($rest =~ /^\s*\.=\s*/) {                                  # append
      if(@{$$prog{cmd}}{source} == 0) {
         @{$$prog{var}}{$var} .=  evaluate($self,$prog,$');
      } else {
         @{$$prog{var}}{$var} = $';
      }
   } elsif($rest =~ /^\s*=\s*/) {                                      # set
      if(trim($') eq undef) {                             # no value, delete
         delete @{$$prog{var}}{$var};
      } elsif(@{$$prog{cmd}}{source} == 0) {           # from prog, evaluate
         @{$$prog{var}}{$var} = evaluate($self,$prog,$');
      } else {                                # from person, do not evaluate
         @{$$prog{var}}{$var} = $';
      }
   } else {
      return err($self,$prog,"Invalid command.");
   }
#   necho(self   => $self,
#         prog   => $prog,
#         source => [ "Set." ],
#        );
}

sub cmd_boot
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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
            audit($self,$prog,"Port $$hash{port} \@booted");
         } else {
            necho(self   => $self,
                  target => $hash,
                  prog   => $prog,
                  target => [ $hash, "%s has \@booted you.", name($self)],
                  source => [ "You \@booted %s off!", obj_name($self,$hash)],
                  room   => [ $hash, "%s has been \@booted.",name($hash) ],
                 );
            audit($self,$prog,"%s \@booted",obj_name($target,$target));
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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my (@out, $var, %max);

   verify_switches($self,$prog,$switch,"var") || return;

   # determine max column sizes
   @max{pid} = 3;
   @max{owner} = 5;
   @max{obj} = 3;
   for my $pid (keys %engine) {
      my $p = @engine{$pid};
      if(defined $$p{stack} && ref($$p{stack}) eq "ARRAY" &&
         controls($self,$$p{created_by}) &&
         (!hasflag($$p{created_by},"GOD") || hasflag($self,"GOD"))) {
         @max{pid} = length($pid) if (length($pid) > @max{pid});

         for my $i (0 .. $#{$$p{stack}}) {
            my $obj = @{@{@{$$p{stack}}[0]}{runas}}{obj_id};
            my $size = ansi_length(obj_name($self,$$p{created_by},1));
            $size = length($$p{created_by}) + 1 if($size > 20);
            @max{owner} = $size if $size > @max{owner};
            @max{obj} = length($obj) + 1 if (length($obj)+1 > @max{obj});
         }
      }
   }
   @max{cmd} = 68 - (@max{pid} + @max{owner} + @max{obj});

   # show header
   push(@out,sprintf("%-*s | %-*s | %-*s | %s",
       @max{pid},"Pid",
       @max{owner},"Owner",
       @max{obj},"Obj",
       "Command"));
   push(@out,sprintf("%s=|=%s=|=%s=|=%s",
       "=" x @max{pid},
       "=" x @max{owner},
       "=" x @max{obj},
       "=" x @max{cmd}),
      );

   for my $pid (sort {$a <=> $b} keys %engine) {               # show detail
      my $p = @engine{$pid};
      $$p{command} = 0 if !defined $$prog{command};
      $$p{function} = 0 if !defined $$p{function};
      $var = undef;

      if(defined $$p{stack} && ref($$p{stack}) eq "ARRAY" &&
         controls($self,$$p{created_by}) &&
         (!hasflag($$p{created_by},"GOD") || hasflag($self,"GOD"))) {
         # can only see processes they control
         # non-gods can not see god processes

         for my $i (0 .. $#{$$p{stack}}) {
            my $cmd = @{$$p{stack}}[$i];
            my ($max,$name,$sleep);

            # get owner details but shorten if bigger then > 20
            my $obj = @{@{@{$$p{stack}}[0]}{runas}}{obj_id};
            my $size = ansi_length(obj_name($self,$$p{created_by},1));
            if($size > 20) {
               $name = "#" . $$p{created_by};
               $max = @max{owner};
            } else {
               $name = obj_name($self,$$p{created_by},1);
               $max = (@max{owner} - $size) +
                  length(obj_name($self,$$p{created_by},1));
            }

            # fill in command details + sleep
            my $c =  single_line($$cmd{cmd});
            if(defined $$cmd{sleep}) {                   # show sleeping data
               $sleep = "[" . ($$cmd{sleep} - time()) . "s left]";
            }

            if(length($c . $sleep) > @max{cmd}) {           # shorten command
               $c = substr($c,0,@max{cmd} - length($sleep));
            }

            if($sleep ne undef) {                  # put sleep at end of line
               $sleep=(" " x (@max{cmd}-length($c)-length($sleep))) . $sleep;
            }

            push(@out,sprintf("%*s | %*s | %*s | %s",
                              @max{pid},
                              ($i == 0) ? $pid : "",
                              ($i == 0) ? $max : @max{owner},
                              ($i == 0) ? $name : "",
                              @max{obj},
                              "#" . $obj,
                              $c . $sleep
                             )
               );
         }
      }
   }
   necho(self   => $self,                           # target's room
         prog   => $prog,
         source => [ "%s", join("\n",@out) ]
        );

#    my ($self,$prog,$txt,$switch) = @_;
#    my (@out, $var);
#
#    verify_switches($self,$prog,$switch,"var") || return;
#
#    push(@out,"----[ Start ]----");
#
#    for my $pid (keys %engine) {
#       my $p = @engine{$pid};
#       $$p{command} = 0 if !defined $$prog{command};
#       $$p{function} = 0 if !defined $$p{function};
#       $var = undef;
#
#       if(defined $$p{stack} && ref($$p{stack}) eq "ARRAY" &&
#          controls($self,$$p{created_by}) &&
#          (!hasflag($$p{created_by},"GOD") || hasflag($self,"GOD"))) {
#          # can only see processes they control
#          # non-gods can not see god processes
#
#          push(@out,sprintf("  PID: %s for %s [%sc/%sf]",
#                               $pid,
#                               obj_name($self,$$p{created_by}),
#                               $$p{command},
#                               $$p{function}
#                          )
#              );
#
#          for my $i (0 .. $#{$$p{stack}}) {
#             my $cmd = @{$$p{stack}}[$i];
#             my $left;
#
#             if(defined @{$$p{stack}}[0] && @{@{$$p{stack}}[0]}{runas}) {
#                $left = " for " .
#                   obj_name($self,@{@{@{$$p{stack}}[0]}{runas}}{obj_id},1);
#             }
#             if(defined $$cmd{sleep}) {
#                $left .= "  [" . ($$cmd{sleep} - time()) . " seconds left]";
#             }
#             push(@out,sprintf("    '%s%s'%s",
#                               substr(single_line($$cmd{cmd}),0,64),
#                               (length(single_line($$cmd{cmd})) > 67)?"..." : "",
#                               $left
#                              )
#                 );
#          }
#
#          if(defined $$switch{var}) {
#             for my $key (keys %{@$p{var}}) {
#                if(@{$$p{var}}{$key} !~ /^\s*$/) {
#                   if($var eq undef) {
#                      push(@out,"  ### Variables ###");
#                      $var = 1;
#                   }
#                   push(@out, "    $key : " . substr(@{$$p{var}}{$key},1,60));
#                }
#             }
#          }
#       }
#    }
#    push(@out,"----[  End  ]----");
#    necho(self   => $self,                           # target's room
#          prog   => $prog,
#          source => [ "%s", join("\n",@out) ]
#         );
}

#
# cmd_halt
#    Delete all processes owned by the object running the @halt command.
#
sub cmd_halt
{
   my ($self,$prog) = (obj(shift),shift);
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

#
# find_free_dbrefs
#
#    @destroy will keep track of used dbrefs but this function will
#    populate the list on startup / reload of code.
#
sub find_free_dbrefs
{
   delete @free[0 .. $#free];

   for my $i (0 .. $#db) {
      push(@free,$i) if(!valid_dbref($i));
   }
}

sub cmd_player
{
   my ($self,$prog,$type) = (obj(shift),shift,shift);

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
   my ($self,$prog,$type) = (obj(shift),shift,shift);
   my ($file,$start);

   if(conf("mudname") eq undef) {
      printf("%s\n",code("long"));
      exit(0);
   }
   if(in_run_function($prog)) {
      return out($prog,"#-1 \@DUMP can not be called from RUN function");
   } elsif(!hasflag($self,"WIZARD") && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   }

   return if $#db == -1;
   con("**** Program EXITING ******\n") if($type eq "CRASH");
   $type = "normal" if($type eq undef);

   #-----------------------------------------------------------------------#
   # initialize loop                                                       #
   #-----------------------------------------------------------------------#
   my $cmd = $$prog{cmd};
   if(!defined $$cmd{dump_pos}) {                      # initialize "loop"
      if(defined @info{backup_mode} && is_running(@info{backup_mode})) {
         return err($self,$prog,"Backup is already running.");
      }
      $$cmd{dump_pos} = 0;

      my ($sec,$min,$hour,$day,$mon,$yr,$wday,$yday,$isdst) =
                                                localtime(time);
      $mon++;
      $yr -= 100;
#
      my $fn = sprintf("dumps/%s.%02d%02d%02d_%02d%02d%02d",
                       conf("mudname"),$yr,$mon,$day,$hour,$min,$sec);

      open($file,"> $fn.tdb") ||
        return err($self,$prog,"Unable to open $fn for writing");
      @info{dump_name} = $fn;

      printf($file "server: %s, version=%s, change#=0, exported=%s, type=%s\n",
         conf("version"),db_version(),scalar localtime(),$type);
      @info{change} = 0;

      $$cmd{dump_file} = $file;
      @info{backup_mode} = $$prog{pid};
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
       ($$cmd{dump_pos} - $start <= 50 || $type eq "CRASH" || @info{run} ==0)) {
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
      }
      con("**** Dump Complete: Exiting ******\n") if($type eq "CRASH");

      $$prog{command} = 1;                 # delete cost of running command
                                           # so it doesn't show in console
                                           # as expensive command
      return;
   } else {
      return "RUNNING";                                       # still running
   }
}


sub cmd_dirty_dump
{
   my ($self,$prog,$txt,$switch) = @_;
   $self = $$self{obj_id} if ref($self) eq "HASH";
   my ($file,$out,$fn);

   my $dirty = @info{dirty};
   return if ref($dirty) eq "HASH" && scalar keys %$dirty == 0; # nothing2save

   @info{dump_name} = $' if(@info{dump_name} =~ /^dumps\//i);
   if(is_true(conf("single_dirty_file"))) {
      @info{change} = 1;
      $fn = sprintf("%s.%06d",@info{dump_name},1);
   } else {
      $fn = sprintf("%s.%06d",@info{dump_name},++@info{change});
   }

   if(-e "dumps/$fn" && !is_true(conf("single_dirty_file"))) {
      return err($self,$prog,"Log file already exists, please wait longer " .
                 "between creating log files.");
   }

   open($file,">> dumps/$fn") ||
      return err($self,$prog,"Unable to open dumps/$fn for writing");

   printf($file "server: %s, version=%s, change#=%s, exported=%s, " .
       "type=archive_log\n",conf("version"),db_version(),@info{change},
       scalar localtime());

   my $dirty = @info{dirty};
   for my $dbref (sort keys %$dirty) {
      my $dobj = $$dirty{$dbref};
      my $obj = dbref($dbref);

      if(!valid_dbref($dbref)) {
         $out .= "$dbref,delobj";
      } else {
         # mark as previously deleted.
         printf($file "%s,delobj\n",$dbref) if(defined $$dobj{destroyed});

         # cycle all attributes that are dirty
         for my $key (sort keys %$dobj) {
            if($key =~ /^A_/ && !defined $$obj{$'}) {
               printf($file "%s,delatr,%s\n",$dbref,$');
            } elsif($key =~ /^A_/) {
               my $attr = $$obj{$'};
               my $name = $';
               $$attr{created} = time() if !defined $$attr{created};
               $$attr{modified} = time() if !defined $$attr{modified};

               if(reserved($name) && defined $$attr{value} &&
                  $$attr{type} eq "list") {
                  printf($file "%s,setatr,%s:%s:%s::L:%s\n",
                         $dbref,$name,$$attr{created},$$attr{modified},
                         join(',',keys %{$$attr{value}}));
               } elsif(defined $$attr{value} && $$attr{type} eq "hash") {
                  printf($file "%s,setatr,%s:%s:%s::H:%s\n",
                         $dbref,$name,$$attr{created},$$attr{modified},
                         hash_serialize($$attr{value},$name,$dbref));
               } else {
                  printf($file "%s,setatr,%s\n",$dbref,
                     serialize($name,$attr));
               }
            }
         }
      }
   }
   printf($file "** Dump Completed %s **\n", scalar localtime());
   close($file);

#   necho(self   => $self,
#         prog   => $prog,
#         source => [ "%s", $out ],
#        );
   @info{dirty} = {};                                         # empty pool;
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
   my ($self,$prog,$txt,$switch)=(obj(shift),shift,shift,shift);

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
   my ($self,$prog,$txt,$switch)=(obj(shift),shift,shift,shift);

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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my $cmd = $$prog{cmd};
   my ($delim, %last, $count);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&
      return out($prog,"#-1 \@DOLIST can not be called from RUN function");

   verify_switches($self,$prog,$switch,"delimit","notify") || return;

   if(defined $$switch{delimit}) {                       # handle delimiter
      if($txt =~ /^\s*([^ ]+)\s*/) {
         $txt = $';                       # first word of list is delimiter
         $delim = evaluate($self,$prog,$1);
      } else {
         return err($self,$prog,"Could not determine delimiter");
      }
   } else {
      $delim = " ";
   }

   if(!defined $$cmd{dolist_list}) {                      # initialize dolist
       my ($first,$second) = balanced_split($txt,"=",4);
       $$cmd{dolist_cmd}   = $second;
       my $txt = evaluate($self,$prog,$first);
       $$cmd{dolist_list} = [safe_split($txt,$delim)];
       $$cmd{dolist_count} = 0;
       $$prog{iter_stack} = [] if(!defined $$prog{iter_stack});
       $$cmd{dolist_loc} = $#{$$prog{iter_stack}} + 1;
   } elsif($#{$$cmd{dolist_list}} == -1) {
      if(defined $$switch{notify}) {
         mushrun(self   => $self,
                 prog   => $prog,
                 runas  => $self,
                 source => 0,
                 cmd    => "\@notify/first/quiet",
                 child  => 2,
                );
      }
      if(defined $$prog{iter_stack}) {
         my $array = $$prog{iter_stack};
         delete @$array[$$cmd{dolist_loc} .. $#$array];
      }
   }
   $$cmd{dolist_count}++;

   if($$cmd{dolist_count} > 500) {                  # force users to be nice
      return err($self,$prog,"dolist execeeded maxium count of 500, stopping");
   } elsif($#{$$cmd{dolist_list}} < 0) {
      return;                                                 # already done
   }

   my $item = trim(shift(@{$$cmd{dolist_list}}));
   if($item !~ /^\s*$/) {
#      $item = fun_escape($self,$prog,$item);
      my $cmds = $$cmd{dolist_cmd};
#      $cmds =~ s/\#\#/$item/g;

      @{$$prog{iter_stack}}[$$cmd{dolist_loc}]={val => $item, pos=>++$count};

      delete $$prog{attr} if defined $$prog{attr};

      if(defined $$prog{cmd} && @{$$prog{cmd}}{source} == 1) {
         my $new = prog($self,$self,$self);
         $$new{iter_stack} = [];
         @{$$new{iter_stack}}[0]={val => $item, pos=> 0 };
         mushrun(self   => $self,                    # player typed in command,
                 runas  => $self,            # new environment for each command
                 prog   => $new,
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

  return "RUNNING";
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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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

   my $cmd = $$prog{cmd};

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
   $$prog{idle} = 1;
   return "BACKGROUNDED";
}

#
# cmd_sleep
#    Let a program sleep for X seconds
#
sub cmd_sleep
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   hasflag($self,"GUEST") &&                     # no sleeping for guests
      return err($self,$prog,"Permission denied.");

   in_run_function($prog) &&      # sleep can not be called from inside run()
      return out($prog,"#-1 \@SLEEP can not be called from RUN function");

   my $cmd = $$prog{cmd};

   if(defined $$cmd{sleep}) {   # spin() will not run this command again
      delete @$cmd{sleep};      # until the sleep is done.
   } elsif(!isint($txt) || $txt > 5400) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "\@sleep is limited to 5400 seconds." ],
           );
   } elsif($txt > 0) {
      $$cmd{sleep} = time() + $txt;                # signal spin() to wait.
      return "RUNNING";
   }
}


sub cmd_read
{
   my ($self,$prog,$txt,$switch,$flag) = (obj(shift),shift,shift,shift,shift);
   my ($file, $data, $name);
   my $count = 0;

   if(!hasflag($self,"WIZARD") && !$flag) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denied." ],
           );
   } elsif($txt =~ /^\s*help\s*$/) {                     # import help data
      if(!open($file,"txt/help.txt")) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "Could not open help.txt for reading." ],
                     );
      }

      delete @help{keys %help};

      while(<$file>) {
         s/\r|\n//g;
         if(/^& /) {
            if($data ne undef) {
               $count++;
               $data =~ s/\n$//g;
               @help{$name} = $data;
            }
            $name = lc($');
            $data = undef;
         } else {
            $data .= $_ . "\n";
         }
      }

      if($data ne undef) {
         $data =~ s/\n$//g;
         @help{$name} = $data;
         $count++;
      }

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

sub cmd_squish
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
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

   my $hash = mget($target,$atr);
   $$hash{glob} =~ s/:/\\:/g if(defined $$hash{type});

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

sub invoker
{
   my ($prog,$self,$flag) = @_;

   if(ref($prog) eq "HASH" &&
      defined $$prog{cmd} &&
      defined @{$$prog{cmd}}{invoker}) {
      return ($flag) ? @{@{$$prog{cmd}}{invoker}}{obj_id} :
         @{$$prog{cmd}}{invoker};
   } elsif($self eq undef && $flag) {
      return undef;
   } else {
      return ($flag) ? $$self{obj_id} : $self;
   }
}

sub code_history
{
    my $prog = shift;

   printf("-----[ start ]----------\n");
   if(defined $$prog{cmd} &&
      defined @{$$prog{cmd}}{stack}) {
      my $hash = @{$$prog{cmd}}{stack};
      push(@$hash,invoker($prog,undef,1) . "->" . code());

      for my $i (0 .. $#$hash) {
         printf("$i : %s\n",$$hash[$i]);
      }
   } else {
      printf("0 : No stack history provided.\n");
      printf("1 : %s\n",invoker($prog,undef,1) . "->" . code());
   }
   printf("-----[  end  ]----------\n");
}

sub cmd_switch
{
#    printf("SWITCH: '%s'\n",$_[2]);
#    for my $i (balanced_split($_[2],',',3)) {
#       printf("#  '%s'\n",$i);
#    }
    my ($self,$prog,@list) = (obj(shift),shift,balanced_split(shift,',',3));
    my $switch = shift;
    my (%last, $pat,$done);
#    for my $i (0 .. $#list) {
#       printf("$i : '%s'\n",@list[$i]);
#    }


   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");
#
#    printf("FIRST: '%s'\n",@list[0]);
    my ($first,$second) = (get_segment2(shift(@list),"="));
#    printf("FIRST: '%s'\n",$first);
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
#          printf("1BEFORE_TXT: '%s'\n",@list[0]);
#          printf("2BEFORE_TXT: '%s'\n",evaluate($self,$prog,@list[0]));
          my $txt=ansi_remove(single_line(evaluate($self,$prog,shift(@list))));
#          printf("TXT: '%s'\n",$txt);

          if(defined $$switch{regexp}) {
             $pat = $txt;
          } else {
             $pat = glob2re($txt);
#             printf("PAT1: '%s'\n",$pat);
#             printf("PAT2: '%s'\n",$txt);
          }
          my $cmd = shift(@list);
          $cmd =~ s/^[\s\n]+//g;
          $txt =~ s/^\s+|\s+$//g;
          if($txt =~ /^\s*(<|>)\s*/) {
             my $val = evaluate($self,$prog,$');
             if(($1 eq ">" && $first > $') || ($1 eq "<" && $first < $')) {
                $cmd =~ s/\\,/,/g;
                return mushrun(self   => $self,
                               prog   => $prog,
                               source => 0,
                               child  => 1,
                               invoker=> invoker($prog,$self),
                               cmd    => $cmd,
                              );
             }
          } else {
             eval {                    # assume $pat could be a bad regexp
                if($first =~ /$pat/) {
#                   printf("PAT:   '%s'\n",$pat);
#                   printf("First: '%s'\n",$first);
                   $cmd =~ s/\\,/,/g;
                   mushrun(self   => $self,
                           prog   => $prog,
                           source => 0,
                           cmd    => $cmd,
                           child  => 1,
                           invoker=> invoker($prog,$self),
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
          @list[0] =~ s/\\,/,/g;
          mushrun(self   => $self,
                  prog   => $prog,
                  source => 0,
                  child  => 1,
                  invoker=> invoker($prog,$self),
                  cmd    => @list[0],
                 );
          return;
       }
    }
}


sub cmd_newpassword
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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

      db_set($player,"obj_password",mushhash($2));

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

   my $puppet = hasflag($self,"SOCKET_PUPPET");
   my $input = hasflag($self,"SOCKET_INPUT");

   if(!$input && !$puppet) {
      return err($self,$prog,"Permission DENIED.");
   } elsif(find_socket($self,$prog) ne undef) {
      return err($self,$prog,"A \@telnet/url() connection is already open");
   } elsif($txt =~ /^\s*([^:]+)\s*[:| ]\s*(\d+)\s*$/) {
      my ($host,$port) = ($1,$2);
#      printf("cmd_telnet: opening connection to '$host:$port'\n");

      my $sock = IO::Socket::INET->new(Proto => 'tcp',
                                       Blocking => 0) ||
         return err($self,$prog,"Socket error, $!.");

      my $iaddr = inet_aton($host) ||
         return err($self,$prog,"Unknown host '%s'",$host);

      my $paddr = sockaddr_in($port,$iaddr);

      my $ret = connect($sock,$paddr);

      if (!$ret && ! $!{EINPROGRESS}) {
         return err($self,$prog,"Unable to connect") if (!$ret);
      }

      $$prog{socket_id} = $sock;
      @connected{$sock} = {                         # store socket details
         obj_id    => $$self{obj_id},
         sock      => $sock,
         raw       => ($puppet) ? 1 : 2,
         hostname  => $host,
         port      => $port,
         loggedin  => 0,
         opened    => time(),
         enactor   => $enactor,
         pending   => ($!{EINPROGRESS}) ? 1 : 0,    # socket still opening?
         prog      => $prog
      };

      () = IO::Select->new($sock)->can_write(.2)    # see if socket is pending
          or @{@connected{$sock}}{pending} = 2;

      $readable->add($sock);                      # add to select() listener
      @info{io} = {} if(!defined @info{io});           # create input buffer
      @info{io}->{$sock} = {};
      @info{io}->{$sock}->{buffer} = [];
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
    my ($self,$prog) = (obj(shift),shift);
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
    my ($self,$prog) = (obj(shift),shift);

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
    my ($self,$prog,$txt) = (obj(shift),shift,shift);

    hasflag($self,"GUEST") &&
       return err($self,$prog,"Permission denied.");

    if($txt =~ /^\s*([^ ]+)\s*=\s*/) {
       my $target = find($self,$prog,$1) ||
          return err($self,$prog,"I can't find that");

       if(!controls($self,$target)) {
          return err($self,$prog,"Permission Denied.");
       }

       if(hasflag($target,"GOD") && !hasflag($self,"GOD")) {
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

       if(owner_id($self) != owner_id($target)) {
          audit($self,$prog,"%s \@forced",obj_name($target,$target));
       }
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

#
# motd
#    Display the message of the day. Since this will be run as #0,
#    don't allow any modifications to the db to prevent wizards
#    from doing anything interesting.
#
sub motd
{
   my ($self,$prog) = @_;

   my $atr = conf("motd");                                  # get motd

   if($atr eq undef) {                    # no motd, provide a default
      $atr = "   " .
             ansi_center("There is no MOTD today",70) .
             "\n   " .
             ansi_center("&conf.motd #0=<message> for your MOTD",70);
   } else {                                        # evaluate the motd
      my $tmp = $$prog{read_only};                    # set readonly mode
      $$prog{read_only} = 1;
      $atr = evaluate($self,$prog,$atr);

      if($tmp eq undef) {
         delete @$prog{read_only};
      } else {
         $$prog{read_only} = $tmp;
      }
   }

   return "   " . ("-" x 31) . "[ MOTD ]" . ("-" x 31) . "\n\n".
             $atr . "\n\n   " . ("-" x 70) . "\n";
}

sub cmd_list
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   if($txt =~ /^\s*motd\s*$/i) {
      necho(self => $self,
            prog => $prog,
            source => [ "%s", motd($self,$prog) ]
           );
   } elsif($txt =~ /^\s*functions\s*$/i) {
       my $user;
       $Text::Wrap::columns=75;
       if(!defined @info{mush_function}||ref(@info{mush_function}) ne "HASH") {
          $user = "N/A"
       } else {
          $user = uc(join(' ',keys %{@info{mush_function}}));
       }
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s\n%s",
                         wrap("Functions:     x",
                              "                ",
                              uc(list_functions())
                             ),
                         wrap("User-Functions: ",
                              "                ",
                              $user
                             ),
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
   } elsif($txt =~ /^\s*buffers{0,1}\s*$/) {
       my $hash = @info{io};
       necho(self   => $self,
             prog   => $prog,
             source => [ "%s",print_var($hash) ],
            );
   } elsif($txt =~ /^\s*sockets\s*$/) {
         my $out;
         for my $key (keys %connected) {
            my $hash = @connected{$key};
            $out .= "\n$$hash{hostname}:$$hash{port} -> '$$hash{start}' -> '$$hash{pending}'";
         }
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s",$out ],
              );
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

sub cmd_destroy
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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
   my $loc = loc($target);

   necho(self   => $self,
         prog   => $prog,
         source => [ "Destroyed %s", obj_name($target) ],
        );
   destroy_object($self,$prog,$target);
}

#
# cmd_toad
#    Delete a player. This cycles through the whole db, so the code will
#    search in 100 object increments.
#
sub cmd_toad
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
   my $start;

   if(!hasflag($self,"WIZARD")) {
      return err($self,$prog,"Permission Denied.");
   } elsif($txt =~ /^\s*$/) {
       return err($self,$prog,"syntax: \@toad <object>");
   }

   #-----------------------------------------------------------------------#
   # initialize loop                                                       #
   #-----------------------------------------------------------------------#
   my $cmd = $$prog{cmd};

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
      audit($self,$prog,"%s \@toaded",obj_name($target,$target));

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
      delete @player{trim(ansi_remove(lc($$cmd{toad_name2})))};
      db_delete($$cmd{toad_dbref});
   } else {
      return "RUNNING";                                      # still running
   }
}



sub cmd_think
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   verify_switches($self,$prog,$switch,"noeval") || return;

   if(!$$switch{noeval}) {
      $txt = evaluate($self,$prog,$txt);
   }

   if($txt !~ /^\s*$/) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $txt ],
           );
   }
}

sub cmd_pemit
{
   my ($self,$prog) = (obj(shift),shift);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission denied.");

   my ($obj,$txt) = balanced_split(shift,"=",4);

   if($txt eq undef) {
      return err($self,$prog,"syntax: \@pemit <object> = <message> '$txt'");
   }

   my $target = find($self,$prog,evaluate($self,$prog,$obj));

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
}

sub cmd_emit
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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

   my $loc = loc($self);

   teleport($self,$prog,$target,$loc) ||
      return err($self,$prog,"Internal error, unable to drop that object");

   # provide some visual feed back to the player
   generic_action($self,
                  $prog,
                  $target,
                  "DROP",
                  [ "dropped %s.\n%s has arrived.",
                    name($target),name($target) ],
                  [ "Dropped." ]);

#   necho(self    => $self,
#         prog    => $prog,
#         source  => [ "You have dropped %s.\n%s has arrived.",
#                      name($target), name($target)
#                    ],
#         room    => [ $self, "%s dropped %s.", name($self),name($target) ],
#         room2   => [ $self, "%s has arrived.",name($target) ]
#        );

   cmd_look($target,$prog);
}

sub cmd_leave
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   my $container = loc($self);

   if($container eq undef || hasflag($container,"ROOM")) {
      return err($self,$prog,"You can't leave.");
   }

   my $dest = loc($container);

   cmd_go($self,$prog,"home") if($dest eq undef);

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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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

   generic_action($self,
                  $prog,
                  $target,
                  "SUCC",
                  [ "takes %s.\n%s has left.",                # msg to room
                    name($target),name($target) ],
                  [ "Taken." ]                             # msg to enactor
                 );

   necho(self   => $self,
         prog   => $prog,
         target => [ $target, "%s has picked you up.", name($self) ],
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   verify_switches($self,$prog,$switch,"quiet") || return;

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

      if(hasflag($target,"PLAYER")) {
         delete @player{trim(ansi_remove(lc(name($target,1))))};
         @player{trim(ansi_remove(lc($name)))} = $$target{obj_id};
      }
      db_set($target,"obj_name",$name);
      db_set($target,"obj_cname",$cname);

      if(!defined $$switch{quiet}) {
         necho(self   => $self,
               prog   => $prog,
               source => [ "Set." ],
              );
      }
   } else {
      err($self,$prog,"syntax: \@name <object> = <new_name>");
   }
}

sub cmd_enter
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   hasflag($self,"GUEST") &&
     return err($self,$prog,"Permission denied.");

   my $target = find($self,$prog,$txt) ||
      return err($self,$prog,"I don't see that here.");

   # enter your own objects or things set ENTER_OK. This should be a
   # controls() for TinyMUSH compat but i'm against wizards entering that
   # aren't specifically set enter_ok. They can @teleport if they really
   # need too.
   if(!(owner_id($target) == owner_id($self) || hasflag($target,"ENTER_OK"))) {
     return err($self,$prog,"Permission denied.");
   } elsif(!(hasflag($target,"OBJECT") || hasflag($target,"PLAYER"))) {
      return err($self,$prog,"I don't see that here.");
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
    my ($self,$prog,$txt) = (obj(shift),shift,shift);

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
      set($self,$prog,$self,"OBJ_LAST_WHISPER","#$$obj{obj_id}",1,1);
   }
   return 1;
}

#
# cmd_whisper
#    person to person communication in the same room.
#
sub cmd_whisper
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

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

   my $msg = evaluate($self,$prog,$msg);

   if($msg =~ /^\s*:\s*/) {

      necho(self   => $self,
            prog   => $prog,
            source => [ "Long distance to %s: %s %s",name($target),
                        name($self),$'
                      ],
            target => [ $target, "From afar, %s %s\n",name($self),$msg ],
           );
   } else {
      $msg =~ s/^\s*//g;
      necho(self   => $self,
            prog   => $prog,
            source => [ "You paged %s with '%s'",name($target),$msg ],
            target => [ $target, "%s pages: %s\n",name($self),$msg ],
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my ($target,$extra, $hostname, $count,$out, $h);
   my $max = 0;

   verify_switches($self,$prog,$switch,"full") || return;

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

   if($$switch{full} && !hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   }

   !controls($self,$target) &&
      return err($self,$prog,"Permission denied.");

   my $attr = mget($target,"obj_lastsite");

   if($attr eq undef || !defined $$attr{value} ||
      ref($$attr{value}) ne "HASH") {
      return err($self,$prog,"Internal error, unable to continue");
   }

   # deterime site column sizing
   for my $key (sort {$b <=> $a} keys %{$$attr{value}}) {
      last if($count++ > 15);
      if(@{$$attr{value}}{$key} =~ /^([^,]+)\,([^,]+)\,/) {
         $h = (defined $$switch{full}) ? $' : short_hn($');
         $max = ansi_length($h) if ansi_length($h) >= $max;
      }
   }

   $count = 0;                                              # build header
   $out .= "Site:" . (" " x ($max-2)) . "Connection Start  | ".
           "Connection End\n";
   $out .= ("-" x ($max+1)) . "|-------------------|" .
           ("-" x 18) . "\n";

   for my $key (sort {$b <=> $a} keys %{$$attr{value}}) { # build contents
      last if($count++ > 15);
      if(@{$$attr{value}}{$key} =~ /^([^,]+)\,([^,]+)\,/) {
         $h = (defined $$switch{full}) ? $' : short_hn($');
         $out .= sprintf("%s%s | %s | %s\n",
                         $h,
                         " " x ($max - ansi_length($h)),
                         minits($key),
                         minits($1)
                        );
      }
   }

   $out .= ("-" x ($max+1)) . "|-------------------|" .          # footer
           ("-" x 18) . "\n";

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", $out ],
        );
}



#
# cmd_go
#    Move an object from one location to another via an exit.
#
sub cmd_go
{
   my ($self,$prog) = (obj(shift),shift);
   my ($exit ,$dest);

   my $txt = evaluate($self,$prog,shift);
   $txt =~ s/^\s+|\s+$//g;

   my $loc = loc($self);

   if(conf_true("master_override")) {          # search master room first?
      $dest = find_exit($self,$prog,conf("master"),$txt);

      if(dest($dest) eq undef) {
         return err($self,$prog,"That exit does not go anywhere");
      }
   }

   if($dest eq undef && $txt =~ /^home$/i) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "There's no place like home...\n" .
                        "There's no place like home...\n" .
                        "There's no place like home..."  ],
            room   => [ $loc, "%s goes home.",name($self) ],
            room2  => [ $loc, "%s has left.",name($self) ],
           );

      $dest = home($self);
   } elsif($dest eq undef)  {
      # find the exit to go through
      $exit = find_exit($self,$prog,loc($self),$txt);

      if($exit eq undef && conf("master") ne undef) {  # try master room
         $exit = find_exit($self,$prog,conf("master"),$txt);
      }

      if($exit eq undef) {
         return err($self,$prog,"You can't go that way.");
      }

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

#   generic_action($self,$prog,$self,"MOVE",$loc);
   generic_action($self,
                  $prog,
                  $self,
                  "MOVE",
                  [ "has arrived." ],
                  [ "" ]);

   # provide some visual feed back to the player
   necho(self   => $self,
         prog   => $prog,
         room   => [ $self, "%s has arrived.",name($self) ]
        );

   cmd_look($self,$prog);
}

sub cmd_teleport
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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

   (controls($self,$location) || hasflag($location,"JUMP_OK")) ||
      return err($self,$prog,"Permission Denied.");

   if(hasflag($location,"EXIT")) {
      if((owner(loc($location)) == $$self{obj_id} &&
         loc($location) == loc($target)) ||
         hasflag($self,"WIZARD")) {
         $location = dest($location);

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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

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

sub cmd_quit
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   if(!defined $$prog{user} || !defined $$prog{user}->{sock}) {
      return err($self,$prog,"Non-Players may not QUIT");
   }

   my $sock = $$prog{user}->{sock};

   if(@{@connected{$sock}}{type} eq "WEBSOCKET") {
      ws_echo($sock,conf("logoff"));
      ws_disconnect(@c{$sock}) if(defined @c{$sock});
   } else {
      printf($sock "%s",conf("logoff"));
      server_disconnect($sock);
   }
}

sub cmd_help
{
   my ($self,$prog,$txt) = (obj(shift),shift,ansi_remove(shift));

   my $help;
   $txt = "help" if($txt =~  /^\s*$/);

   # initalize help variable if needed
   cmd_read($self,$prog,"help",undef,1) if(scalar keys %help == 0);

   if(defined @help{lc(trim($txt))}) {
      $help = @help{lc(trim($txt))};
   } elsif(defined @help{lc(trim($txt)). "()"}) {
      $help = @help{lc(trim($txt)) . "()"};
   } elsif($txt =~ /\(\s*\)\s*$/ && defined @help{lc(trim($`))}) {
      $help = @help{lc(trim($`))};
   } elsif(defined @help{"@" . lc(trim($txt))}) {
      $help = @help{"@" . lc(trim($txt))};
   } else {
      $help = "No entry for '" . lc(trim($txt) . "'");
   }

   if($help =~ /^run: /i) {                # run a command to provide help
      mushrun(self   => $self,
              prog   => $prog,
              runas  => $self,
              source => 0,
              cmd    => $'
             );
   } else {                                       # send help output to user
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", $help ],
           );
   }
}

sub cmd_nohelp
{
   my ($self,$prog,$txt,$switch,$flag) = (obj(shift),shift,shift,shift,shift);
   my @result;

   for my $key (sort keys %command) {
      if(@command{$key}->{full} eq $key && !defined @help{$key}) {
         push(@result,$key);
      }
   }
   necho(self   => $self,
         prog   => $prog,
         source => [ wrap("commands: ",
                          "          ",
                           join(', ',@result)
                          )
                   ]
        );
   delete @result[0 .. $#result];
   
   for my $key (sort keys %fun) {
      if(!defined @help{"$key()"}) {
         push(@result,$key);
      }
   }
   necho(self   => $self,
         prog   => $prog,
         source => [ wrap("functions: ",
                          "           ",
                           join(', ',@result)
                          )
                   ]
        );
   delete @result[0 .. $#result];
}


sub cmd_pcreate
{
   my ($self,$prog,$txt,$switch,$flag) = (obj(shift),shift,shift,shift,shift);

   if($$user{site_restriction} == 3) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "%s", conf("registration") ],
           );
   } elsif($txt =~ /^\s*([^ ]+) ([^ ]+)\s*$/) {
      if(inuse_player_name($1)) {
         err($user,$prog,"That name is already in use.");
      } else {
         $$user{obj_id} = create_object($self,$prog,$1,$2,"PLAYER");
         $$user{obj_name} = $1;
         cmd_connect($self,$prog,$txt) if !$flag;
      }
   } else {
      err($user,$prog,"Invalid create command, try: create <user> <password> [$txt]");
   }
}

sub create_exit
{
   my ($self,$prog,$name,$in,$out,$verbose) = @_;

   # only ROOM, OBJECT, or PLAYERS may have exits;
   return undef if(!or_flag($in,"ROOM","OBJECT","PLAYER"));

   # only ROOM, OBJECT, or PLAYERS may have destinations;
   return undef if(!or_flag($out,"ROOM","OBJECT","PLAYER"));

   my $exit = create_object($self,$prog,$name,undef,"EXIT") ||
      return undef;

   if(!link_exit($self,$exit,$in,$out,1)) {
      return undef;
   }

   return $exit;
}

sub cmd_create
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,trim(shift),shift);

   if(hasflag($self,"GUEST")) {
      return err($self,$prog,"Permission denied.");
   } elsif(quota($self,"left") <= 0) {
      return err($self,$prog,"You are out of QUOTA to create objects.");
   } elsif(length($txt) > 50) {
      return err($self,$prog,
                 "Object name may not be greater then 50 characters"
                );
   } elsif(money($self) < conf("createcost")) {
      return err($self,$prog,"You need at least ".pennies("createcost").".");
   }

   my $dbref = create_object($self,$prog,$txt,undef,"OBJECT") ||
      return err($self,$prog,"Unable to create object");

   if(!give_money($self,"-" . conf("createcost"))) {
      return err($self,$prog,"Unable to deduct cost of object.");
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "Object created as: %s",obj_name($self,$dbref) ],
        );

   set_quota($self,"sub");
}

sub cmd_link
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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
      printf("Link: $$target{obj_id} -> $$dest{obj_id}\n");
      link_exit($self,$target,undef,$dest) ||
         return err($self,$prog,"Internal error while trying to link exit");
      necho(self   => $self, prog   => $prog, source => [ "Set." ],);
   } elsif(!hasflag($target,"EXIT") &&
      (controls($self,$dest)  || hasflag($dest,"ABODE"))) {
      printf("Link: $$target{obj_id} -> $$dest{obj_id}\n");
      set_home($self,$prog,$target,$dest) ||
         return err($self,$prog,"Internal error while trying to link exit");
      necho(self   => $self, prog   => $prog, source => [ "set." ],);
   } else {
      return err($self,$prog,"Permission denied");
   }
}

sub cmd_dig
{
   my ($self,$prog,$txt,$switch,$flag) = (obj(shift),shift,shift,shift,shift);
   my ($loc,$room_name,$room,$in,$out,$cost,$quota);

   hasflag($self,"GUEST") &&
      return err($self,$prog,"Permission Denied.");

   # parse command line
   my ($room_name,$rest) = bsplit($txt,"=");
   my $room_name = evaluate($self,$prog,$room_name);
   ($in,$out) = besplit($self,$prog,$rest,",");

   if(!$flag) {
      $loc = loc($self) ||
         return err($self,$prog,"Unable to determine your location");
   }

   $quota = 1;                            # determine required quota & cost
   $cost = conf("digcost");
   if($in ne undef) {
      $cost += conf("linkcost");
      $quota++;
   }
   if($out ne undef) {
      $cost += conf("linkcost");
      $quota++;
   }

   # permission / quota check.
   if(hasflag($self,"WIZARD") || hasflag($self,"GOD")) {
      # ignore QUOTA restrictions
   } elsif(quota($self,"left") < $quota) {
      return err($self,$prog,"A quota of $quota is needed for this \@dig.");
   } elsif($cost > money($self)) {
      return err($self,$prog,"%s is needed for this \@dig.",pennies($cost));
   } elsif($out ne undef && !(controls($self,$loc)||hasflag($loc,"LINK_OK"))) {
      return err($self,
                 $prog,
                 "You do not own this room or it is not LINK_OK"
                 );
   }

   # non-quota / permisison checks.
   if($room_name eq undef) {                                 # no room name
      return err($self,$prog,"Dig what?");
   } elsif($in ne undef && find_exit($self,$prog,loc($self),$in)) {
      return err($self,$prog,"Exit '%s' already exists in this location",$in);
   } elsif(hasflag($loc,"EXIT")) {
      return err($self,$prog,"You can not \@dig from inside an exit.");
   } else {                                           # okay to start @digging
      # create room
      my $room = create_object($self,$prog,$room_name,undef,"ROOM")||
         return err($self,$prog,"Unable to create a new object");

      give_money($self,"-" . $cost) ||
         return err($self,$prog,"Couldn't debit %s",pennies($cost));

      set_quota($self,"sub") ||
         return err($self,$prog,"Couldn't update quota.");

      give_money($room,conf("digcost"),1) ||
         return err($self,$prog,"Couldn't debit %s",pennies($cost));


      necho(self   => $self,
            prog   => $prog,
            source => [ "%s created as #%s.",$room_name,$room ],
           );

      if($in ne undef) {                    # create exit going into the room
         my $in_dbref = create_exit($self,$prog,$in,$loc,$room);

         if($in_dbref eq undef) {
            return err($self,
                       $prog,
                       "Unable to create exit '%s' going in to room",
                       $in
                      );
         }

         give_money($in_dbref,conf("linkcost"),1) ||
           return err($self,$prog,"Couldn't give #$in_dbref %s",pennies($cost));
         set_quota($self,"sub");

         necho(self   => $self,
               prog   => $prog,
               source => [ "   In exit created as:   %s(#%sE)",$in,$in_dbref ],
              );
      }

      if($out ne undef) {                # create exit going out of the room
         my $out_dbref = create_exit($self,$prog,$out,$room,$loc);
         if($out_dbref eq undef) {
            return err($self,
                       $prog,
                       "Unable to create exit '%s' going out of room",
                       $out
                      );
         }

         set_quota($self,"sub");
         give_money($out_dbref,conf("linkcost"),1) ||
            return err($self,
                       $prog,
                       "Couldn't give #%s %s",
                       $out_dbref,
                       pennies($cost)
                      );

         necho(self   => $self,
               prog   => $prog,
               source => [ "   Out exit created as:  %s(#%sE)",
                           $out,$out_dbref
                         ],
              );
      }
   }
}

sub cmd_open
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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

   if(quota($self,"left") < 1) {
      return err($self,$prog,"You are out of QUOTA to create objects");
   }

   !find_exit($self,$prog,loc($self),$exit,"EXACT") ||
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

   set_quota($self,"sub");

   necho(self   => $self,
         prog   => $prog,
         source => [ "Exit created as %s(#%sE)",$exit,$dbref ],
        );
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
   my ($self,$name,$pass) = (shift,ansi_remove(shift),shift);

   if($name =~ /^\s*#(\d+)\s*$/) {
      if(valid_dbref($1) && hasflag($1,"PLAYER") &&
         get($1,"obj_password") eq mushhash($pass)) {
         $$self{obj_id} = $1;
         return 0;
      } else {
         return 1;
      }
   } elsif(!defined @player{trim(ansi_remove(lc($name)))}) {
      return 1;
   } elsif(@player{trim(ansi_remove(lc($name)))} eq conf("webuser")) {
      printf("PLAYER: '%s' -> '%s'\n",@player{trim(ansi_remove(lc($name)))},conf("webuser"));
      return 1;                                    # don't allow webuser in
   } elsif(lc($name) eq "guest") {                 # any password for guest
      $$self{obj_id} = @player{lc($name)};
      return 0;
   } elsif(!valid_dbref(@player{trim(ansi_remove(lc($name)))}) ||
      get(@player{trim(ansi_remove(lc($name)))},"obj_password") ne
         mushhash($pass)) {
      $$self{obj_id} = @player{trim(ansi_remove(lc($name)))};
      return 1;
   } else {
      $$self{obj_id} = @player{trim(ansi_remove(lc($name)))};
      return 0;
   }
}

sub calculate_login_stats
{
   my $add = shift;
   my $count = 0;

   #---[ make timestamp ]------------------------------------------------#
   my ($hour,$mday,$mon,$year) = (localtime())[2..5];  # make timestamps
   $mon++;
   $year = $year % 100;
   my $tsday = sprintf("%02d/%02d/%02d",$mon,$mday,$year);

   #---[ count players ]-------------------------------------------------#
   for my $key (keys %connected) {                        # count players
      if(@connected{$key}->{raw} == 0 && @connected{$key}->{loggedin} == 1) {
         $count++;
      }
   }

   #---[ clean up old data > 9 days ]------------------------------------#
   my $data = mget(0,"stat_login");
   if($data ne undef && defined $$data{value}) {
      my $attr = $$data{value};
      for my $i (keys %$attr) {
         if(time() - fuzzy($i) > 86400 * 30) {
            db_remove_hash(0,"stat_login",$i);                   # delete entry
         }
      }

      #---[ Caculate max logged in for day ]------------------------------#
      if($attr eq undef || $$attr{$tsday} < $count) {
         db_set_hash(0,"stat_login",$tsday,$count);
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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
            ws_echo($sock,"Either that player does not exist, or has a " .
                    "different password.\n");
         } else {
            printf($sock "Either that player does not exist, or has a " .
                   "different password.\n");
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
      @{@connected{$sock}}{connect} = time();
      db_set_hash($$user{obj_id},
                  "obj_lastsite",
                  time(),
                  time() . ",1,$$user{hostname}"
                 );
      calculate_login_stats();

      # --- Provide users visual feedback / MOTD --------------------------#
      $prog = prog($user,$user);
      necho(self   => $user,                 # show message of the day file
            prog   => $prog,
            source => [ "%s\n", motd($user,$prog) ]
           );

      cmd_mail($user,prog($user,$user),"short");

      if(defined conf("paycheck") && conf("paycheck") > 0) {
         if(ts_date(lasttime($user)) ne ts_date()) {
            give_money($user,conf("paycheck"));
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

      if(conf("master") ne undef) {
         for my $obj (lcon(conf("master")),$player) {
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   if(hasflag($self,"GUEST")) {
      necho(self   => $self,
            prog   => $prog,
            source => [ "Permission denieD." ]
           );
   } elsif(defined $$switch{header} && $txt =~ /^\s*$/) {
      if(!hasflag($self,"WIZARD")) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "Permission denIed." ]
                      );
      }
      @info{"doing_header"} = $txt;
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "Removed." ]
                  );
   } elsif(defined $$switch{header}) {
      if(!hasflag($self,"WIZARD")) {
          return necho(self   => $self,
                       prog   => $prog,
                       source => [ "Permission deNied." ]
                      );
      }
      @info{"doing_header"} = $txt;
      return necho(self   => $self,
                   prog   => $prog,
                   source => [ "Set." ]
                  );
   } elsif($txt =~ /^\s*$/) {
      for my $s (keys %{@connected_user{$$self{obj_id}}}) {
         delete @connected{$s}->{obj_doing};
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "Removed." ]
           );
   } else {
      for my $s (keys %{@connected_user{$$self{obj_id}}}) {
         $connected{$s}->{obj_doing} = trim($txt);
      }
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

#   $value =~ s/\r|\n//g if !defined $$switch{raw};
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
   } elsif($type eq 1) {                    # memorydb / mysql don't agree on
      $type = "\$";                              # how the type is defined
   } elsif($type eq 2) {
      $type = "^";
   } elsif($type eq 3) {
      $type = "!";
   }

   # exclude attributes that are not commands when $$switch{command}
   return if($type eq undef && defined $$switch{command});

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

   if($type eq "hash") {
      my $hash = $value;
      $value = undef;
      for my $key (keys %$hash) {
         if($value eq undef) {
             $value = $key . " -> " . $$hash{$key};
         } else {
             $value .= ", " . $key . " -> " . $$hash{$key};
         }
      }
      return color("h",uc($name)) .  (($flag ne undef) ? "[$flag]: " : ": ") .
             "[" . $value . "]";
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
   } elsif($name eq "obj_last") {
      return 1;
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
   my ($obj,$pattern,$subpat,$switch) = @_;
   my (@out,$pat,$spat,$val,$keys);

   $pat = glob2re($pattern) if($pattern ne undef);
   $spat = glob2re($subpat) if($subpat ne undef);

   for my $name (lattr($obj), "last") {
      my $short = $name;
      $short =~ s/^obj_//;
      next if($pat ne undef && $short !~ /$pat/i || ($name eq "last" && $pat eq undef));


      if(viewable($obj,$name,$pat)) {
         my $attr = mget($obj,$name);
         if($name !~ /^obj_/ && db_set_ishash($obj,$name)) {
            next if($pattern ne undef && $short !~ /$pat/i);

            if($pattern eq undef) {
               my $hash = db_hash_keys($obj,$name);
               push(@out,color("h",$name) . ": [ " . $hash . " hash entries ]");
            } else {
               my $count = 0;
               for my $key (db_hash_keys($obj,$name)) {
                  if($subpat eq undef || $key =~ /$spat/i) {
                     push(@out,color("h",$name)) if($count++ == 0);
                     push(@out," + " . color("h","$key") .  " : " .
                        @{$$attr{value}}{$key});
                  }
               }
            }
         } else {
            if($name eq "obj_lastsite") {
               $val = reconstitute($short,"","",short_hn(lastsite($obj)));
            } elsif($name eq "obj_created_by") {
               $val = reconstitute("first","","",short_hn($$attr{value}));
            } elsif($name eq "last" && $pat ) {
               $val = reconstitute($short,"","",lasttime($obj));
            } else {
               $val = reconstitute($short,
                                   $$attr{type},
                                   $$attr{glob},
                                   $$attr{value},
                                   list_attr_flags($attr),
                                   $switch
                                  )
             }
            if(defined $$switch{detail}) {
               $val = color("h","Mod") . ":" . ts($$attr{created}). "," .
                      color("h","Created") . ":". ts($$attr{modified}) . "," .
                      color("h","Value") . ":" . $val;
            }
            push(@out,$val);
         }
      }
   }


   if($#out == -1 && $pattern ne undef) {
      return "No matching attributes";
   } else {
      return join("\n",@out);
   }
}


sub cmd_ex
{
   my ($self,$prog) = (obj(shift),shift);
   my ($sub,$target,$desc,@exit,@content,$atr,$out);

   my ($txt,$atr) = bsplit(shift,"/");
   my ($atr,$sub) = besplit($self,$prog,$atr,":");
   my $txt = evaluate($self,$prog,$txt);

   my $switch = shift;

   verify_switches($self,$prog,$switch,"raw","command","detail") || return;

   if($txt =~ /^\s*$/) {
      $target = loc_obj($self);
   } else {
      $target = find($self,$prog,$txt) ||
         return err($self,$prog,"I don't see that here. '$txt'");
   }

   my $perm = (controls($self,$target) || readonly($self,$target)) ? 1 : 0;

   if($atr ne undef) {
      if($perm) {
         return necho(self   => $self,
                      prog   => $prog,
                      source => [ "%s",list_attr($target,$atr,$sub,$switch)],
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
              "  " . color("h",ucfirst(conf("money_name_plural"))) .
              ": ". money($target,1);
       my $parent = get($target,"obj_parent");

       if($parent ne undef) {
          $out .= "\n" . color("h","Parent") . ": " . obj_name($self,$parent);
       }
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
      my $attr = list_attr($target,$atr,$sub,$switch);
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
      push(@exit,obj_name($self,$obj)) if(!hasflag($obj,"DARK") || $perm);
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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
   my ($self,$prog,$txt) = (obj(shift),shift,shift);
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

   if(!hasflag($target,"ROOM") && loc($self) == $$target{obj_id}) {
      if(hasattr($target,"A_IDESC")) {
         $out .= "\n" . evaluate($self,$prog,get($$target{obj_id},"A_IDESC"));
      } elsif(hasattr($target,"idesc")) {
         $out .= "\n" . evaluate($self,$prog,get($$target{obj_id},"idesc"));
      }
   } elsif(($desc = get($$target{obj_id},"DESCRIPTION")) && $desc ne undef) {
      $out .= "\n" . evaluate($target,$prog,$desc);
   } else {
      $out .= "\nYou see nothing special.";
   }

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

   $out .= "\n" . color("h","Exits") . ":\n" .
            join("  ",@exit) if($#exit >= 0);  # add any exits

   necho(self   => $self,
         prog   => $prog,
         source => ["%s",$out ]
        );

   generic_action($self,
                  $prog,
                  $target,
                  "describe",
                  [ "" ],
                  [ "" ]);

#   run_attr($self,$prog,$target,"ADESCRIBE");
}

sub is_true
{
   my $txt = shift;

   if($txt =~ /^\s*(yes|ye|y|1)\s*$/) {
      return 1;
   } else {
      return 0;
   }
}

#
# generic function to run attributes if they exist
#
sub run_attr
{
   my ($self,$prog,$target,$attr) = (obj(shift),shift,obj(shift),shift);
   my @args = @_;
   my $txt;

   return 0 if(conf_true("safemode"));            # nothing runs in safemode

   $txt = get($target,$attr) ||
      return 0;

   mushrun(self   => $self,           # handle adesc
           prog   => $prog,
           runas  => $target,
           invoker=> $self,
           source => 0,
           wild   => [ @args ],
           cmd    => $txt
          );
   return 1;
}





sub cmd_pose
{
   my ($self,$prog,$txt,$switch,$flag) = (obj(shift),shift,shift,shift,shift);

   my $space = ($flag) ? "" : " ";
   my $pose = colorize($self,$prog,cf_convert(evaluate($self,$prog,$txt)));

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

   my $switch = shift;

   verify_switches($self,$prog,$switch,"quiet") || return;

   my $target = find($self,$prog,evaluate($self,$prog,$name)) || # find target
      return err($self,$prog,"I don't see that here");

   !controls($self,$target) &&
      return err($self,$prog,"Permission denied");

   if($attr ne undef) {                                          # attr flag
       $attr = evaluate($self,$prog,$attr);

       if(!isatrflag($value)) {
          return err($self,$prog,"Invalid attribute flag");
       } else {
         necho(self   => $self,
               prog   => $prog,
               source => [ "%s", set_atr_flag($target,$attr,$value,0,$switch) ]
              );
       }
   } else {                                                  # standard flag
      necho(self   => $self,
            prog   => $prog,
            source => [ set_flag($self,$prog,$target,$value,0,$switch) ]
           );
   }
}

sub besplit
{
   my ($self,$prog,$txt,$delim) = @_;
   my ($first,$second) = balanced_split($txt,$delim,4);

   return evaluate($self,$prog,$first), evaluate($self,$prog,$second);
}

sub bsplit
{
   return balanced_split($_[0],$_[1],4);
}

#
# cmd_set2
#    Set a user defined attribute.
#
sub cmd_set2
{
   my ($self,$prog) = (obj(shift),obj(shift));
   my ($obj,$append,$attr);

   hasflag($self,"GUEST") &&                    # don't let guests modify
      return err($self,$prog,"Permission denied");

   my ($txt,$value) = bsplit(shift,"=");

   my $switch = shift;

   verify_switches($self,$prog,$switch,"quiet","notrim") || return;

   my $flag = shift;

   my ($attr,$obj) = bsplit($txt," ");
   my ($attr,$sub) = besplit($self,$prog,$attr,":");

   if($sub ne undef) {
      # hash set
   }

   $obj = evaluate($self,$prog,$obj);
   ($obj,$append) = ($`,1) if($obj =~ /\s*\+$/);             # flag appending

   my $target = find($self,$prog,$obj) || # find target
      return err($self,$prog,"I don't see that here. '$obj'");

   if(!controls($self,$target)) {                                    # nope
      return err($self,$prog,"Permission denied");
   } elsif(!good_atr_name($attr,$flag)) {
      return err($self,$prog,"Thats not a good name for an attribute.");
   } elsif($sub ne undef && !good_atr_name($sub,$flag)) {
      return err($self,$prog,"Thats not a good name for an sub attribute.");
   } elsif($sub ne undef && !db_set_hashable($target,$attr)) {
      return err($self,$prog,"That variable needs to be cleared before " .
                 "adding hash values.");
   } elsif($sub ne undef) {                    # handle hash table entries
      if($value eq undef) {
         db_remove_hash($target,$attr,$sub);                # delete entry
      } else {
         db_set_hash($target,$attr,$sub,$value);               # add entry
      }
      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ],
           );
   } else {
      if($append && get($target,$attr) ne undef) {
         $append = get($target,$attr) . " ";
      }

      if(@{$$prog{cmd}}{source} == 0) {
         set($self,
             $prog,
             $target,
             $attr,
             $append . trim(evaluate($self,$prog,$value)),
             $$switch{quiet}
            );
      } elsif(defined $$prog{multi}) {
         set($self,$prog,$target,$attr,join("\n",@{$$prog{multi}}));
      } else {
         set($self,$prog,$target,$attr,$append . trim($value),$$switch{quiet});
      }
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

   while($txt =~ /(\-{0,1})(\d+)(\.?)(\d*)(\s*)(F|C)/ && myisnum("$1$2$3$4")) {
      $out .= $`;
      $txt = $';
      if (!(substr($`,-1) eq " " || $` eq undef)) {
         $out .= "$1$2$3$4$5$6";
         next;
      }
      if($6 eq "F") {
         my $value = sprintf("%s%s%s%s%s (%.1fC)",
            $1,$2,$3,$4,$6,("$1$2$3$4" - 32) * .5556);
         $value =~ s/\.0//g;
         $out .= $value;
      } else {
         my $value = sprintf("%s%s%s%s%s (%.1fF)",
            $1,$2,$3,$4,$6,"$1$2$3$4" * 1.8 + 32);
         $value =~ s/\.0$//g;
         $out .= $value;
      }
   }

   return $out . $txt;
}

sub remove_punctuation
{
   my $txt = shift;

   if($txt =~ /\s*([:;.,"\(\)\[\]]+)\s*$/) {
      return $`;
   } else {
      return $txt;
   }
}

sub colorize
{
   my ($self,$prog,$txt) = @_;
   my $out;

   for my $word (safe_split($txt," ",1)) {
      my $lookfor = trim(lc(ansi_remove(remove_punctuation($word))));
      my $target = find($self,$prog,$lookfor);

      # don't colorize non-connected players who haven't connected in a week.
      if($target eq undef || (!hasflag($target,"CONNECTED") &&
         time()-lasttime($target,1) > 604800)){
         $out .= (($out eq undef) ? "" : " ") . $word;
      } elsif(lc(name($target,1)) eq $lookfor) {
         my ($before,$after);
         $before = $1 if($word =~ /^(\s+)/);           # preserve spaces
         $after = $1 if($word =~ /([ :;.,"\(\)\[\]]+)$/);
         $out .= (($out eq undef) ? "" : " ") .
                 $before .
                 name($target) .
                 $after;
      } else {
         $out .= (($out eq undef) ? "" : " ") . $word;
      }
   }
   return $out;
}

#
# cmd_say
#    Say something outloud to anyone in the room the player is in.
#
sub cmd_say
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my $out;

   verify_switches($self,$prog,$switch,"noeval","eval") || return;

   if(defined $$switch{noeval}) {
      $out = $txt;
   } elsif(defined $$switch{eval}) {
      $out = evaluate($self,$prog,$txt);
   } else {
      $out = colorize($self,$prog,cf_convert(evaluate($self,$prog,$txt)));
   }

   necho(self   => $self,
         prog   => $prog,
         source => [ "You say, \"%s\"",$out],
         room   => [ $self, "%s says, \"%s\"",name($self),$out ],
        );
}

sub get_source_checksums
{
    my $src = shift;
    my (%data, $file,$pos);
    my $ln = 0;

    open($file,$0) || die("Unable to read $0");

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
      if(@{$$prev{$key}}{chk} ne @{$$curr{$key}}{chk} || @info{reload_init}) {
         $count++;

         con("Reloading: %-40s",$key) if($self ne undef);

         eval(@{$$curr{$key}}{src});

         if($@) {
            con("*FAILED*\n%s\n",renumber_code($@)) if($self ne undef);
            @{$$curr{$key}}{chk} = -1;
            if($self ne undef) {
               necho(self   => $self,
                     prog   => $prog,
                     source => [ "Reloading %-40s *FAILED*", $key ]
                    );
            }
         } else {
            if($self ne undef) {
               con("Successful\n");
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
   my $count = 0;

   if(!hasflag($self,"GOD")) {
      return err($self,$prog,"Permission denied.");
   } elsif(@info{"md5"} == -1) {
      return err($self,$prog,"#-1 DISABLED");
   }

   audit($self,$prog,"\@reload");
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
   my ($val,$name) = (0,undef);
   my $data;

   if(conf("hostmask") =~ /^\s*(color|mask|colormask)\s*$/) {
      if($addr =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/) {
         $addr = "$1.$2.*.*";
      } elsif($addr =~ /[A-Za-z]/ && $addr  =~ /\.([^\.]+)\.([^\.]+)$/) {
         $addr = "*.$1.$2";
      } else {
         $addr = "*" . substr($addr,length($addr) * .3);
      }

      return $addr if conf("hostmask") eq "mask";

      for my $i (split(//,$addr)) {
         $val += ord($i);
      }

      if(!defined @info{short_hn}) {
         $data = {};
         for my $key (sort keys %ansi_name) {
            if(@ansi_name{$key} !~
               /^(15|195|222|223|224|230|253|255|118|187)$/) {
               if($key =~ /^light/) {
                  # skip
               } elsif($key =~ /^deep(.*)([^\d]+)/) {
                  $$data{$1} = $key;
               } elsif($key =~ /^([^\d]+)/) {
                  $$data{$1} = $key;
               }
            }
         }
         @info{short_hn} = [ sort values(%$data) ];
      }
      $data = @info{short_hn};

      if($val > $#$data) {
         $name = @$data[$val % $#$data];
      } else {
         $name = @$data[$#$data % $val];
      }

      if(conf("hostmask") eq "colormask") {
         return "\e[38;5;@ansi_name{$name}m$addr\e[0m";
      } elsif($name =~ /\d+$/) {
         return "\e[38;5;@ansi_name{$name}m$`\e[0m";
      } else {
         return "\e[38;5;@ansi_name{$name}m$name\e[0m";
      }
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,$prog,$txt) ]
        );
}

sub cmd_DOING
{
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);

   necho(self   => $self,
         prog   => $prog,
         source => [ "%s", who($self,$prog,$txt,1) ]
        );
}

sub who
{
   my ($self,$prog,$txt,$flag) = (obj(shift),shift,shift,shift);
   my ($max,$online,@who,$idle,$count,$out,$extra,$hasperm,$name) = (2,0);
   my ($nomushrun,$readonly) = (0,0);

   if(ref($self) eq "HASH") {
      $hasperm = ($flag || !hasflag($self,"WIZARD")) ? 0 : 1;
   } else {
      $hasperm = 0;
   }

   # query the database for connected user, location, and socket
   # details.
   $readonly = 1 if(defined $$prog{read_only});
   $nomushrun = 1 if(defined $$prog{nomushrun});
   $$prog{read_only} = 1;
   $$prog{nomushrun} = 1;

   for my $key (sort {@{@connected{$b}}{start} <=> @{@connected{$a}}{start}}
                keys %connected) {
      my $hash = @connected{$key};
      next if $$hash{raw} != 0;

      # only list users that start with provided text
      if($$hash{obj_id} ne undef) {
         if(($txt ne undef &&
            lc(substr(name($hash,1),0,length($txt))) eq lc($txt)) ||
            $txt eq undef) {
            if(length(loc($hash)) + 1 > $max) {
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
                      defined @info{"doing_header"} ?
                      @info{"doing_header"} : "\@doing"
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
         my $doing = evaluate($self,$prog,$$hash{obj_doing});
         $doing =~ s/\r|\n//g;
         $out .= sprintf("%s%4s %02d:%02d %4s  %s\r\n",$name,$extra,
             $$online{h},$$online{m},$$idle{max_val} . $$idle{max_abr},
             ansi_substr($doing,0,44));
      }
   }
   $out .= sprintf("%d Players logged in\r\n",$online);        # show totals
   delete @$prog{read_only} if !$readonly;
   delete @$prog{nomushrun} if !$nomushrun;
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
   my ($self,$prog,$txt,$switch) = (obj(shift),shift,shift,shift);
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



sub atr_case
{
    return atr_hasflag(shift,shift,"CASE");
}

sub atr_hasflag
{
   my ($obj,$atr,$flag) = (obj(shift),shift,shift);

   if(ref($obj) ne "HASH" || !defined $$obj{obj_id} || !valid_dbref($obj)) {
     return undef;
   }

   my $attr = mget($obj,$atr);
   if($attr eq undef ||
      !defined $$attr{flag} ||
      !defined $$attr{flag}->{lc($flag)}) {
      return 0;
   } else {
      return 1;
   }
}

sub latr_regexp
{
   my ($obj,$type) = (obj(shift),shift);
   my @result;

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
}


sub lcon
{
   return if $_[0] eq undef;               # no arguments, nothing to do

   my $object = obj_nocheck(shift);
   my @result;

   my $attr = mget($object,"obj_content");

   if($attr eq undef) {
      return @result;
   } else {
      for my $id ( keys %{$$attr{value}} ) {
         push(@result,obj($id));
      }
      return @result;
   }
}

sub lexits
{
   my $object = obj_nocheck(shift);
   my @result;

   my $attr = mget($object,"obj_exits");

   if($attr eq undef) {
      return @result;
   } else {
      for my $id ( keys %{$$attr{value}} ) {
         push(@result,obj($id));
      }
      return @result;
   }
}


sub money
{
   my ($target,$flag) = (obj(shift),shift);

   $target = owner($target) if !$flag;

   return 0 if($target eq undef);

   return get($target,"obj_money");
}

#
# name
#    Return the name of the object from the database if it hasn't already
#    been pulled.
#
sub name
{
   my ($target,$flag,$self,$prog) = (obj(shift),shift,shift,shift);

   if($flag) {
      return get($target,"obj_name");
   } elsif(get($target,"obj_cname") ne undef) {
      return get($target,"obj_cname");
   } elsif($prog ne undef && $$target{obj_id} eq conf("webuser")) {
      # return the hostname of the webuser object when coming from a http call
      if(defined $$prog{hint} && $$prog{hint} eq "WEB" &&
         defined $$prog{user} && defined @{$$prog{user}}{hostname}) {
         return @{$$prog{user}}{hostname}
      } else {
         return get($target,"obj_name");
      }
   } else {
      return get($target,"obj_name");
   }
}


sub flag_list
{
   my ($obj,$flag) = (obj($_[0]),uc($_[1]));
   my (@list,$array,$connected);
   $flag = 0 if !$flag;

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

   if(!valid_dbref($obj)) {
      return undef;
   } elsif(hasflag($obj,"PLAYER")) {
      return $obj;
   } else {
      my $owner = get($obj,"obj_owner");
      return obj($owner);
   }
}

#
# hasflag
#    Return if an object has a flag or not
#
sub hasflag
{
   my ($target,$name) = (obj(shift),shift);
   my $val;

   if(!valid_dbref($target)) {
      return 0;
   } elsif($name eq "CONNECTED" || $name eq "c") {        # not stored in db
      return (defined @connected_user{$$target{obj_id}}) ? 1 : 0;
   }

   $target = owner($target) if($name eq "WIZARD" || $name eq "GOD");

   my $attr = mget($target,"obj_flag");

   return 0 if(!defined $$attr{value});                   # no flags at all

   my $flag = $$attr{value};

   if(uc($name) eq "WIZARD") {                        # all gods are wizards
      return (defined $$flag{wizard}||defined $$flag{god}) ? 1 : 0;
   } elsif(length($name) == 1) {                     # look for flag letter
      for my $key (keys %$flag) {
         if(defined @flag{uc($key)} && @{@flag{uc($key)}}{letter} eq $name) {
            return 1;                                       # must match case
         }
      }
      return 0;
   } elsif(defined $$flag{lc($name)}) {                 # flag name match
      return 1;
   } else {
      return 0;
   }
}

sub or_flag
{
   my ($obj,@flags) = @_;

   for my $flag (@flags) {
      return 1 if(hasflag($obj,$flag));
   }
   return 0;
}

sub and_flag
{
   my ($obj,@flags) = @_;

   for my $flag (@flags) {
      return 0 if(!hasflag($obj,$flag));
   }
   return 1;
}


sub dest
{
    my $obj = obj(shift);

   return get($obj,"obj_destination");
}

sub home
{
   my $obj = obj(shift);

   my $home = get($obj,"obj_home");

   if(valid_dbref($home)) {                           # use object's home
      return $home;
   } elsif(valid_dbref(conf("starting_room")) &&
           hasflag(conf("starting_room"),"ROOM")) {
                                                      # use starting_room
      db_set($obj,"obj_home",conf("starting_room"));
      return conf("starting_room");
   } else {                             # default to first availible room
      my $first = first_room();
      db_set($obj,"obj_home",$first);
      return $first;
   }
}

sub loc_obj
{
   my $obj = obj(shift);

   my $loc = get($obj,"obj_location");
   return ($loc eq undef) ? undef : obj($loc);
}

sub lattr
{
   my $obj = obj(shift);

   return () if(!valid_dbref($obj));
   my $hash = dbref($obj);
   return ($hash eq undef) ? undef : (sort keys %$hash);
}

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

sub is_ansi_string
{
   my $txt = shift;

   if(ref($txt) ne "HASH" ||
      !defined $$txt{ch} ||
      !defined $$txt{snap} ||
      !defined $$txt{code}) {
      return 0;
   } else {
      return 1;
   }
}


sub ansi_reset
{
   my ($data,$pos) = @_;

   my $string = (is_ansi_string($data)) ? $data : ansi_init($data);

   printf("Ansi_reset: returning\n") if $pos < 0;
   return $string if $pos < 0;                               # sanity check

   my $code = $$string{code};
   my $array = $$code[$pos];

   # check to see if the last code is a reset, or no codes at all
   if($#$array == -1 || $$array[$#$array] ne "\e[0m") {
      push(@$array,"\e[0m");
   }
   return $string;
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

#
# ansi_clone
#   Clone the ansi escape codes at a particular position to the new
#   string.
#
sub ansi_clone
{
   my ($str,$pos,$txt) = @_;

   if(ref($str) ne "HASH") {
      $str = ansi_init($str);
   }

   my $snap = $$str{snap};

   if($#$snap >= 0 && $#$snap > $pos) {
      return join('',@{@$snap[$pos]}) . $txt . "\e[0m";
   } else {
      return $txt;
   }
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
#    no-ansi flag : do not copy over escape sequences
#
sub ansi_substr
{
   my ($txt,$start,$count,$noansi) = @_;
   my ($result,$data,$last);
   # foo

   if(ref($txt) eq "HASH") {
      $data = $txt;
   } else {
      $data = ansi_init($txt);
   }

   $start = 0 if($start !~ /^\s*\d+\s*$/);                  # sanity checks
   if($count !~ /^\s*\d+\s*$/) {
      $count = ansi_length($txt);
   } else {
      $count += $start;
   }
   return undef if($start < 0);                         # no starting point

   # loop through each "character" w/attached ansi codes
   for(my $i = $start;$i < $count && $i <= $#{$$data{ch}};$i++) {
      if(!$noansi) {
         my $code=join('',@{@{$$data{($i == $start) ? "snap" : "code"}}[$i]});
         $result .= $code . @{$$data{ch}}[$i];
      } else {
         $result .= @{$$data{ch}}[$i];
      }
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

   while($pat =~ /(\*|\?)/ && $wild < 10) {
      $pat = $';
      $pos += length($`) if($` ne undef);
      push(@wildcard,ansi_substr($data,$pos,length(@arg[$wild])));
      $pos += length(@arg[$wild]);
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
   my ($codes,$txt,$type) = @_;
   my $pre;
   #
   # conversion table for letters to numbers used in escape codes as defined
   # by TinyMUSH, or maybe TinyMUX.
   #
   my %ansi = (
      x => 30, X => 40, r => 31, R => 41, g => 32, G => 42, y => 33,
      Y => 43, b => 34, B => 44, m => 35, M => 45, c => 36, C => 46,
      w => 37, W => 47, u => 4, i => 7, h => 1, f => 5, n => 0
   );

   for my $ch (split(//,$codes)) {
      $pre .= "\e[@ansi{$ch}m" if(defined @ansi{$ch});
   }
   if($type eq 1) {
      return $pre;
   } else {
      return $pre . $txt . "\e[0m";
   }
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

#
# ansi_trim
#    Remove leading and trailing spaces from any string while ignoring
#    vt100 escape codes.
#
sub ansi_trim
{
   my ($start, $end);
   my $txt = (ref($_) eq "HASH") ? shift : ansi_init(shift);

   for my $i ( 0 .. $#{$$txt{ch}}) {                   # find leading spaces
      if(@{$$txt{ch}}[$i] ne " ") {
         $start = $i;
         last;
      }
   }

   for my $i ( reverse 0 .. $#{$$txt{ch}}) {          # find trailing spaces
      if(@{$$txt{ch}}[$i] ne " ") {
         $end = $i;
         last;
      }
   }

   if($start eq undef || $end eq undef) {
      return undef;
    } else {                                     # let ansi_substr do the work
      return ansi_substr($txt,$start,$end - $start + 1);
   }
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

# flag definitions
#    letter      => 1 letter unique abbrivation for flag
#    perm        => flags required to set this flag
#    type        => 1 for object flag, 2 for attribute flag
#    ord         => display flag order for vague compt w/tinymush.
#    target_type => object must have these flags to get the flag
#                   i.e. objects can not be set wizard, but players can.
#
sub initialize_flags
{
   delete @flag{keys %flag};

   @flag{ANYONE}       ={ letter => "+",                   type => 1, ord=>99 };
   @flag{GOD}          ={ letter      => "G",
                          perm        => "GOD",
                          type        => 1,
                          ord         => 5,
                          target_type => "PLAYER"
                        };
   @flag{WIZARD}       ={ letter      => "W",
                          perm        => "GOD",
                          type        => 1,
                          ord         => 6,
                          target_type => "PLAYER"
                        };
   @flag{CHOWN_OK}     ={ letter      => "C",
                          perm        => "!GUEST",
                          type        => 1,
                          ord         => 28,
                          target_type => "!PLAYER"
                        };
   @flag{HALTED}       ={ letter      => "H",
                          perm        => "",
                          type        => 1,
                          ord         => 29,
                          target_type => ""
                        };
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
   @flag{JUMP_OK}      ={ letter => "J", perm => "!GUEST", type => 1, ord=>27 };
}

#
# db_version
#    Define which version of the database the mush is dumping. This
#    should be incremented when anything changes.
#
# 1.5: Introduced attribute timestamps
#
sub db_version
{
   return "3.0";
}

sub dirty_bit
{
   my ($obj,$atr) = @_;
   @info{dirty} = {} if !defined @info{dirty};
   my $dirty = @info{dirty};

   my $obj = $$obj{obj_id} if(ref($obj) eq "HASH");

   if($atr eq undef) {
      $$dirty{$obj} = { destroyed => 1 };               # deleted attribute
   } else {
      # new object in dirty bit, or object no longer deleted.
      if(!defined $$dirty{$obj} || ref($$dirty{$obj}) ne "HASH") {
         $$dirty{$obj} = {};
      }
      $$dirty{$obj}->{"A_$atr"} = scalar localtime; # don't allow overwrite of deleted 'flag'
   }
}

sub hasparent
{
   my $obj = obj(shift);

   my $parent = mget($obj,"obj_parent");

   return ($parent ne undef && valid_dbref($parent)) ? 1 : 0;
}

sub parent
{
   my $obj = obj(shift);

   my $parent = mget($obj,"obj_parent");
   $parent =~ s/^\s*#\s*//g;
   return ($parent ne undef && valid_dbref($parent)) ? $parent : undef;
}

sub hasattr
{
   my ($obj,$attr,$parent) = (obj(shift),ansi_remove(shift),shift);
   my $data;

   # handle if object exists
   $attr = "description" if lc($attr) eq "desc";

   my $data = dbref($obj);
   return undef if $data eq undef;
   $parent = 1 if(lc($parent) eq "parent");

   # handle if attribute exits on object
   if(defined $$data{lc($attr)}) {           # check if attribute exists
      return 1;                                                  # exists
   } elsif($parent && hasparent($obj)) {                   # check parent?
      my $parent = parent($obj);
      my $data = dbref($parent);
      return (defined $$data{lc($attr)}) ? 1 : 0;
   } else {
      return 0;                                             # doesn't exist
   }
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
   my ($obj,$attr,$debug) = (obj(shift),ansi_remove(shift),shift);
   my $data;

   # handle if object exists
   $attr = "description" if lc($attr) eq "desc";

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
}


#
# db_readonly
#
#   There are some situations where the program shouldn't modify the
#   database. Determine what those are.
#
sub db_readonly
{
   return 0 if !defined @info{prog};            # no program info, assume RW

   if(defined @info{prog}->{read_only}) {                # program is set RO
      return 1;
   } else {
      return 0;                                                 # Read/Write
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

   return if db_readonly();

   dirty_bit($obj);                                      # mark object dirty
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
      printf("can_set: 0\n");
      return 0;
   }

   my $hash = @flag{uc($flag)};

   if(defined $$hash{target_type} && $$hash{target_type} =~ /^!/ &&
           hasflag($obj,$')) {
      return 0;
   } elsif(defined $$hash{target_type} && $$hash{target_type} !~ /^!/ &&
           !hasflag($obj,$$hash{target_type})) {
      return 0;
   } elsif($$hash{perm} =~ /^!/) {     # can't have this perm flag and set flag
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

sub get_flag_by_letter
{
   my $letter = trim(shift);

   for my $key (keys %flag) {
      if(@flag{$key}->{letter} eq $letter) {
         return $key;
      }
   }
   return undef;
}

#
# flag
#    Is the flag actually a valid object flag or not.
#
sub flag
{
   my $txt = shift;

   $txt = $' if($txt =~ /^\s*!\s*/);
   if(defined @flag{uc($txt)} &&
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
      return "$name:$$attr{created}:$$attr{modified}:$flag:M:$txt";
   } else {
      return "$name:$$attr{created}:$$attr{modified}:$flag:A:$txt";
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
   my ($id,$key,$value,$created,$modified)=
       (obj(shift),lc(shift),shift,shift,shift);

   return if db_readonly();

   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);

   dirty_bit($id,$key);
   if($value eq undef) {
      delete @$obj{$key};
      return;
   }

   $$obj{$key} = {} if(!defined $$obj{$key});       # create attr if needed
   my $attr = $$obj{$key};

   if($created ne undef) {
      $$attr{created} = $created;
   } elsif(!defined $$attr{created}) {
      $$attr{created} = time();
   }

   if($modified ne undef) {
      @$attr{modified} = $modified;
   } else {
      @$attr{modified} = time();
   }

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

   return if db_readonly();

   return if $flag eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);
   $id = $$id{obj_id} if(ref($id) eq "HASH");

   my $obj = dbref_mutate($id);

   $$obj{$key} = {} if(!defined $$obj{$key});       # create attr if needed

   my $attr = $$obj{$key};
   dirty_bit($id,"flag");

   $$attr{flag} = {} if(!defined $$attr{flag});

   if($value eq undef) {
      delete @{$$attr{flag}}{$flag};
   } else {
      @{$$attr{flag}}{$flag} = 1;
   }
}

sub db_set_list
{
   my ($id,$key,$value,$created,$modified) =
      (obj(shift),lc(shift),lc(shift),shift,shift);

   return if db_readonly();

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);
   dirty_bit($id,$key);

   $$obj{$key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};

   if($created ne undef) {
      $$attr{created} = $created;
   } elsif(!defined $$attr{created}) {
      $$attr{created} = time();
   }

   if($modified ne undef) {
      $$attr{modified} = $modified;
   } else {
      $$attr{modified} = time();
   }

   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "list";

   @{$$attr{value}}{$value} = 1;
}

sub db_remove_list
{
   my ($id,$key,$value) = (obj(shift),lc(shift),lc(shift));

   return if db_readonly();

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);
   dirty_bit($id,$key);
   $$obj{key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};
   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "list";

   delete @{$$attr{value}}{$value};
}

#
# db_set_hashable
#    Can this attribute be used as a hash table.
#
sub db_set_hashable
{
   my ($id,$attr) = @_;
   my $obj = dbref_mutate($id);

   if(!defined $$obj{$attr}) {                  # empty attribute can be set
      return 1;
   } elsif(db_set_ishash($id,$attr)) {
      return 1;
   } else {
      return 0;                                           # must be cleared
   }
}

sub db_set_ishash
{
   my ($id,$attr) = @_;
   my $obj = dbref_mutate($id);

   if(ref($$obj{$attr}) eq "HASH" && defined $$obj{$attr}->{value} &&
           ref($$obj{$attr}->{value}) eq "HASH") {
      return 1;                                           # is already hash
   } else {
      return 0;                                           # must be cleared
   }
}

sub db_hash_keys
{
   my ($id,$key,$sub) = (obj(shift),lc(shift),lc(shift));

   my $obj = dbref_mutate($id);
   return undef if $obj eq undef;

   return undef if(!defined $$obj{$key});
   my $attr = $$obj{$key};

   return undef if(!defined $$attr{value} || ref($$attr{value}) ne "HASH");

   return keys %{$$attr{value}};
}

sub db_set_hash
{
   my ($id,$key,$value,$sub,$created,$modified) =
       (obj(shift),lc(shift),lc(shift),shift,shift,shift);

   return if db_readonly();

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);
   dirty_bit($id,$key);

   $$obj{$key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};

   if($created ne undef) {
      $$attr{created} = $created;
   } elsif(!defined $$attr{created}) {
      $$attr{created} = time();
   }

   if($modified ne undef) {
      $$attr{modified} = $modified;
   } else {
      $$attr{modified} = time();
   }

   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "hash";

   @{$$attr{value}}{$value} = $sub;
}

sub db_remove_hash
{
   my ($id,$key,$value,$clean) = (obj(shift),lc(shift),lc(shift),shift);

   return if db_readonly();

   return if $value eq undef;
   croak() if($$id{obj_id} =~ /^HASH\(.*\)$/);

   my $obj = dbref_mutate($id);
   dirty_bit($id,$key);

   $$obj{$key} = {} if(!defined $$obj{$key});
   my $attr = $$obj{$key};
   $$attr{value} = {} if(!defined $$attr{value});
   $$attr{type} = "hash";

   delete @{$$attr{value}}{$value};

   if(scalar keys %{$$attr{value}} == 0) {
      delete @$obj{$key};
   }
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
         $$attr{created} = time() if !defined $$attr{created};
         $$attr{modified} = time() if !defined $$attr{modified};

         if(reserved($name) && defined $$attr{value} &&
            $$attr{type} eq "list") {
            $out .= "   $name\:$$attr{created}:$$attr{modified}::L:" .
               join(',',keys %{$$attr{value}}) . "\n";
         } elsif(defined $$attr{value} && $$attr{type} eq "hash") {
            $out .= "   $name\:$$attr{created}:$$attr{modified}::H:" .
               hash_serialize($$attr{value},$name,$i)."\n";
         } else {
            $out .= "   " . serialize($name,$attr) . "\n";
         }
      }
      $out .= "}\n";
   }
   return $out;
}

#
# db_process_line
#   Read one line from the db at a time, storing any vital information
#   in the state hash table.
#
#   When in a restore and an object number is passed in, then only that
#   object is restored. The process will not die() when restoring.
#
sub db_process_line
{
   my ($state,$line,$obj) = @_;

   $line =~ s/\r|\n//g;
   $$state{chars} += length($_);
   if($$state{obj} eq undef &&  $line =~                            # header
      /^server: ([^,]+), dbversion=([^,]+), exported=([^,]+), type=/) {
      $$state{ver} = $2;
   } elsif($$state{obj} eq undef && $line =~                        # header
      /^server: ([^,]+), version=([^,]+), change#=([^,]+), exported=([^,]+), type=/) {
      $$state{ver} = $2;
      @info{change} = $3;
   } elsif($line =~ /^\*\* Dump Completed (.*) \*\*$/) {
      $$state{complete} = 1;                                  # dump complete
   } elsif($$state{obj} eq undef && $line =~ /^obj\[(\d+)]\s*{\s*$/) {
      $$state{obj} = $1;                                    # start of object
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):M:/) {
      if($obj eq undef || $$state{obj} eq $obj) {
         db_set($$state{obj},$1,db_unsafe($'),$2,$3);       # MIME attribute
         db_set_flag($$state{obj},$1,$4,1) if($4 ne undef);
      }
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):A:/) {
      if($obj eq undef || $$state{obj} eq $obj) {
         db_set($$state{obj},$1,$',$2,$3);              # standard attribute
         db_set_flag($$state{obj},$1,$4,1) if($4 ne undef);
      }
      $$state{loc} = $' if($1 eq "obj_location");
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):L:/) {
      my ($attr,$list,$created,$modified) = ($1,$',$2,$3);   # list attribute
      if($obj eq undef || $$state{obj} eq $obj) {
         for my $item (split(/,/,$list)) {
            db_set_list($$state{obj},$attr,$item,$created,$modified);
            if($attr eq "obj_flag" && $item =~ /^\s*(PLAYER|EXIT)\s*$/i) {
            $$state{type} = uc($1);
            }
         }
      }
   } elsif($$state{obj} ne undef &&
      $line =~ /^\s*([^ \/:]+):(\d+):(\d+):([^:]*):H:/) {
      my ($attr,$list,$created,$mod) = ($1,$');         # hash attribute
      if($obj eq undef || $$state{obj} eq $obj) {
         for my $item (split(/;/,$list)) {
            if($item =~ /^([^:]+):A:([^;]+)/) {
               db_set_hash($$state{obj},$attr,$1,$2,$created,$mod);
            } elsif($item =~ /^([^:]+):M:([^;]+)/) {
               db_set_hash($$state{obj},$attr,$1,db_unsafe($2),$created,$mod);
            }
         }
      }
   } elsif($$state{obj} ne undef && $line =~ /^\s*}\s*$/) {    # end of object
      if($$state{type} eq "PLAYER" && ($obj eq undef || $$state{obj} eq $obj)) {
         @player{lc(@{@{@db[$$state{obj}]}{obj_name}}{value})} = $$state{obj};
      }
      delete @$state{obj};
      delete @$state{type};
      delete @$state{loc};
   } elsif($obj eq undef) {
      con("Unable to parse[$$state{obj}]: '%s'\n",$line);
      printf("Unable to parse[$$state{obj}]: '%s'\n",$line);
      printf("%s\n",code("long"));
      die();
   }
}

$SIG{'INT'} = sub {  if(defined @info{controlc} &&
		        time() - @info{controlc} < 30) {
   		        cmd_dirty_dump(obj(0),{},"CRASH");
                        @info{crash_dump_complete} = 1;
                        exit(1);
	             } else {
			printf("Warning: A Control-C was recieved. Two " .
                               "are needed within 30 seconds to shutdown ".
                               "the MUSH. This is a pre-caution against " .
                               "accidental aborts.\n");
			@info{controlc} = time();
	             }
                  };

$SIG{'USR1'} = sub { @info{sigusr1} = time(); };

END {
   if(@info{run} == 0) {
      con("%s shutdown by %s.\n",conf("mudname"),@info{shutdown_by});
      cmd_dirty_dump(obj(0),{});
      @info{crash_dump_complete} = 1;
   } elsif(!defined @info{crash_dump_complete} && $#db > -1) {
      cmd_dirty_dump(obj(0),{},"CRASH");
   }
}

sub single_line
{
   my $txt = shift;
   $txt =~ s/\r\s*|\n\s*//g;
   $txt =~ s/\r\s*|\n\s*//g;
   return $txt;
}

sub run_obj_commands
{
   my ($self,$prog,$runas,$obj,$cmd)= (obj(shift),shift,shift,obj(shift),shift);
   $cmd =~ s/\r|\n//g;
   my $match = 0;

   if(!or_flag($obj,"NO_COMMAND","HALTED")) {
#      for my $hash (latr_regexp($obj,1)) {
      for my $hash (sort {length(@{$b}{atr_regexp}) <=>
                       length(@{$a}{atr_regexp})} latr_regexp($obj,1)) {
         if($cmd =~ /$$hash{atr_regexp}/i) {
            # run attribute only if last run attritube isn't the new
            # attribute to run. I.e. infinite loop. Since we're not keeping
            # a stack of exec() attributes, this won't catch more complex
            # recursive calls. Future feature?
            if(!defined $$prog{attr} ||
               !(@{$$prog{attr}}{atr_owner} eq $$obj{obj_id} &&
               @{$$prog{attr}}{atr_name} eq $$hash{atr_name})) {

               # http head request requires just find the command, no run
               if(defined $$prog{ping} && $$prog{ping}) {
                   necho(self   => $self,
                         prog   => $prog,
                         source => [ "PONG: \$command : %s/%s in %s",
                                     obj_name($obj,$obj),
                                     $$hash{atr_name},
                                     obj_name(loc($obj),loc($obj)) ]
                        );
               } elsif(!defined $$prog{head}) {
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
               }
               return 1;
            }
         }
      }
   }

   my $parent = mget($obj,"obj_parent");
   return 0 if($parent eq undef || !valid_dbref($$parent{value}));

#   printf("Parent: '$$parent{value}'\n");
   if(!or_flag($$parent{value},"NO_COMMAND","HALTED")) {
      for my $hash (latr_regexp($$parent{value},1)) {
         if($cmd =~ /$$hash{atr_regexp}/i) {
            # run attribute only if last run attritube isn't the new
            # attribute to run. I.e. infinite loop. Since we're not keeping
            # a stack of exec() attributes, this won't catch more complex
            # recursive calls. Future feature?
            if(!defined $$prog{attr} ||
               !(@{$$prog{attr}}{atr_owner} eq $$obj{obj_id} &&
               @{$$prog{attr}}{atr_name} eq $$hash{atr_name})) {
#              printf("RUNNING: '%s' -> '%s'\n",$$obj{obj_id},$$hash{atr_name});
#              printf("          '%s'\n",single_line($$hash{atr_value}));
               if(!defined $$prog{head}) {
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
               }
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

   return if(conf_true("safemode"));
   $cmd = evaluate($self,$prog,$cmd) if($src ne undef && $src == 0);

   if(conf_true("master_override")) {            # search master room first
      for my $obj (lcon(conf("master"))) {
         run_obj_commands($self,$prog,$runas,$obj,$cmd) && return 1;
      }
   }

   # search player
   run_obj_commands($self,$prog,$runas,$self,$cmd) && return 1;

   # search player's contents
   for my $obj (lcon($self)) {
      if(!hasflag($obj,"PLAYER")) {
         run_obj_commands($self,$prog,$runas,$obj,$cmd) && return 1;
      }
   }

   # don't search past the initial player if coming from web / websocket
   # unless the command came from an attribute.
   if(!defined $$prog{attr} &&
      defined $$prog{hint} &&
      ($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET")){
      return 0;
   }

   if(!conf_true("master_override")) {                # search master room
      for my $obj (lcon(conf("master"))) {             # but not twice
         if(!hasflag($obj,"PLAYER")) {
            run_obj_commands($self,$prog,$runas,$obj,$cmd) && return 1;
         }
      }
   }

   # search all objects in player's location's contents
   for my $obj (lcon(loc($self))) {
      if(!hasflag($obj,"PLAYER")) {
         $match += run_obj_commands($self,$prog,$runas,$obj,$cmd);
      }
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
   my $invoker;

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

      if(conf_true("debug")) {
         #
         # Extra Debuging to trace calls back to the begining, when needed.
         # useful for code_history()
         if(defined $$data{invoker} && ref($$data{invoker}) eq "HASH") {
            $invoker = @{$$data{invoker}}{obj_id};
         } else {
            $invoker = "N/A";
         }
         if(defined $$prog{cmd} && defined @{$$prog{cmd}}{stack}) {
            $$data{stack} = [ join("-#-",@{@{$$prog{cmd}}{stack}}), $invoker .
               "->" . code() ];
         } else {
            $$data{stack} = [ $invoker . ":" . code() ];
         }
      }

      $$data{wild} = $$arg{wild} if(defined $$arg{wild});
      if($$arg{child} == 1) {                         # add to top of stack
         $$data{cmd} = @cmd[$#cmd - $i];
         unshift(@$stack,$data);
         $$prog{mutated} = 1;                # current cmd changed location
	 # printf("add[1-%s]: '%s'\n",@{$$data{invoker}}{obj_id},@cmd[$#cmd - $i]);
      } elsif($$arg{child} == 2) {                  # add after current cmd
         $$data{cmd} = @cmd[$#cmd - $i];
         my $current = $$prog{cmd};
         for my $i (0 .. $#$stack) {             #find current cmd in stack
            splice(@$stack,$i+1,0,$data) if($current eq $$stack[$i]);
         }
	 # printf("add[2-%s]: '%s'\n",@{$$data{invoker}}{obj_id},@cmd[$#cmd - $i]);
      } else {                                              # add to bottom
         $$data{cmd} = @cmd[$i];
         push(@$stack,$data);
	 # printf("add[3-%s]: '%s'\n",@{$$data{invoker}}{obj_id},@cmd[$i]);
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
         $$arg{cmd} = "&$$multi{attr} $$multi{object}= multi";
         delete @{$connected{@{$$arg{self}}{sock}}}{inattr};
         @$arg{prog}->{multi} = $stack;
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

   if(defined $$prog{nomushrun} && $$prog{nomushrun}){
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
      if(defined $$prog{cmd} && defined @$prog{cmd}->{invoker}) {
         @arg{invoker} = @$prog{cmd}->{invoker};
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

   if(defined @arg{ppid}) {
      $$prog{var} = {} if not defined $$prog{var};
      @{$$prog{var}}{calling_pid} = @arg{ppid};
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

#   if(defined $arg{wild}) {
#      set_digit_variables($arg{self},$arg{prog},"",@{$arg{wild}}); # copy %0-%9
#   }
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
       for my $i (0 .. 9) {
         @{$$prog{var}}{$sub . $i} = $$new{$i};
      }
   } else {
      my @var = @_;

      for my $i ( 0 .. 9 ) {
         @{$$prog{var}}{$sub . $i} = $var[$i];
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

#   if(defined $$prog{attr}) {
#      printf("%s\n",print_var($prog));
#   }
   if(defined $$prog{capture} && ref($$prog{capture}) eq "HASH") {                    # nope, not actually done
      return if mini_trigger($prog);       # handle trigger part of @capture
   }

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
   } elsif($$prog{hint} eq "IMC") {
      http_out($$prog{sock},"%s",join("",@{@$prog{output}}));
      http_disconnect($$prog{sock});
   } elsif($$prog{hint} eq "WEB") {
      if(defined $$prog{output}) {
         if(defined $$prog{huh}) {
            http_error($$prog{sock},"Page not found");
         } elsif(defined $$prog{head}) {
            http_reply_simple($$prog{sock},"html","","");
         } elsif(defined $$prog{get} && $$prog{get} =~ /^\~/) {
            http_out($$prog{sock},"%s",join("",@{@$prog{output}}));
            http_disconnect($$prog{sock});
         } else {
            http_reply($prog,"%s",join("",@{@$prog{output}}));
         }
      } else {
         http_error($prog,"%s","Page not found");
      }
   } elsif(defined $$prog{missing} && ref($$prog{missing}) eq "HASH") {
      my (@cmds, @fun);                  # show result for @missing command
      my $c = $$prog{missing}->{cmd};
      my $clist = join(', ',keys %$c);
      $clist = "None" if $clist eq undef;

      my $f = $$prog{missing}->{fun};
      my $flist = join(', ',keys %$f);
      $flist = "None" if $flist eq undef;
      necho(self   => $$prog{created_by},
            prog   => $prog,
            target => [ $$prog{created_by}, "Missing commands: %s\n".
                        "Missing functions: %s",
                        $clist,$flist
                      ]
           );
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
   my ($count,$pid,$result);

   $SIG{ALRM} = \&spin_done;

   eval {
       ualarm(15_000_000);                              # err out at 8 seconds
       local $SIG{__DIE__} = sub {
          delete @engine{@info{current_pid}};
          con("----- [ Crash REPORT@ %s ]-----\n",scalar localtime());
          con("%s\n",code("long"));
       };

      if(!defined @info{stat_time} || time() - @info{stat_time} > 3600) {
         calculate_login_stats();
         @info{stat_time} = time();
      }

      if(!defined @info{dump_time}) {
         @info{dump_time} = time();
      } elsif(@info{dump_name} eq "" ||  # initial db?
              time()-@info{dump_time} > nvl(conf("dump_interval"),86400)) {
         @info{dump_time} = time();
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

      if(!defined @info{dirty_time}) {
         @info{dirty_time} = time();
      } elsif(time()-@info{dirty_time} > 300 && defined @info{dump_name}) {
         @info{dirty_time} = time();
         my $self = obj(0);
         mushrun(self   => $self,
                 runas  => $self,
                 invoker=> $self,
                 source => 0,
                 cmd    => "\@dirty_dump",
                 from   => "ATTR",
                 hint   => "ALWAYS_RUN"
         );
      }


      for $pid (sort {$a cmp $b} keys %engine) {
         @info{current_pid} = $pid;

         if(defined @info{timeout_pid} && @info{timeout_pid} == $pid) {
            delete @info{timeout_pid};
            next;
         }
         my $prog = @engine{$pid};
         my $stack = $$prog{stack};
         my $pos = 0;
         $count = 0;
         @info{prog} = @engine{$pid};

         # run 100 commands, backgrounded command are excluded because
         # someone could put 100 waits in for far in the furture, the code
         # would never run the next command.
         while($#$stack - $pos >= 0 && ++$count <= 100 + $pos) {
            my $cmd = $$stack[$pos];                          # run 100 cmds
            my $before = $#$stack;

            if($$cmd{cmd} =~ /^\s*$/ || defined $$cmd{done}) { # cmd already
               splice(@$stack,$pos,1);                   # finished or null
               next;                               # cmd. safe to delete now
            }

            # optimization for sleeping process
            last if(defined $$cmd{sleep} && $$cmd{sleep} > time());
            if(!hasflag($$cmd{runas},"HALTED")) {
               $result = spin_run($prog,$cmd);
            }

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
               @info{timeout_pid} = $pid;
               return;
            }
         }

         mushrun_done($prog) if($#$stack == -1);            # program is done
         delete @info{prog};
      }
      ualarm(0);
   };

   if($@ =~ /alarm/i) {
      con("Time slice timed out (%2f w/%s cmd) $@\n",
         Time::HiRes::gettimeofday() - $start,$count);
   }
}

sub show_verbose
{
   my ($prog,$command) = @_;

   if(hasflag($$command{runas},"VERBOSE")) {
      my $owner= owner($$command{runas});
      necho(self   => $owner,
            prog   => $prog,
            target => [ $owner,
                        "%s] %s",
                        name($$command{runas}),
                        $$command{cmd}
                      ]
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
   my (%switch,$result,$runas);

   # The player is probably disconnected but there are commands in the queue.
   # These orphaned commands are being run against the not logged in commands
   #  set which will crash this function. These commands should just be ignored.
   return if($$hash{cmd} =~ /^CODE\(.*\)$/);

   # the object was probably destroyed, do not run any more code from it.
   return if(!valid_dbref($$command{runas}));

   $$prog{cmd} = $command;

   show_verbose($prog,$command);

   my $start = Time::HiRes::gettimeofday();
   $$prog{function_command} = 0;

   # handle cost of running commands
   my $cost = sprintf("%d",($$prog{command} + ($$prog{function} / 10)) / 128);
   if($cost != 0 && $$prog{cost} != $cost &&
      !hasflag($$command{runas},"WIZARD")) {
      $$prog{cost} = $cost;
      give_money($$command{runas},-1);
   }

   if(defined $$command{runas}) {
      if(ref($$command{runas}) eq "HASH") {
         $runas = $$command{runas}->{obj_id};
      } else {
         $runas = $$command{runas};
      }
   }

   if($$prog{hint} eq "ALWAYS_RUN" ||
      $runas eq conf("webobject") ||
      $$command{source} == 1  ||
      money($$command{runas}) > 0) {
      if(defined $$command{wild}) {
         set_digit_variables($$command{runas},                    # copy %0-%9
                             $prog,
                             "",
                             @{$$command{wild}}
                            );
      }

      # command is just a @ping, echo to user but do not run.
      if(defined $$prog{ping} && $$prog{ping}) {
         necho(self   => $$command{created_by},
               prog   => $prog,
               source => [ "PONG: \@command : Internal Command" ]
              );
         return;
      }
      my $target = $$command{runas};
      $target = $$target{obj_id} if(ref($target) eq "HASH");
      $result = &{@{$$hash{$cmd}}{fun}}($target,
                                        $prog,
                                        trim($arg),
                                        $$command{switch}
                                       );
      $$prog{command_duration} += Time::HiRes::gettimeofday() - $start;
      $$prog{command}++;
    #   $$prog{"command_$cmd"}++;
      return $result;
   }
}

#
# parse_switch
#    Take a command and split off the switches at the end of the command.
#
sub parse_switch
{
   my ($command,$txt) = @_;
   my ($count,$name);

   return $$command{cmd} if defined $$command{switch};
   return $txt if($txt =~ /^("|;|&)/);

   my ($txt,$args)= bsplit($txt," ");
   $args = " " . $args if($args ne undef);

   $$command{switch} = {};
   my ($cmd,$rest) = balanced_split($txt,"/",4);
   return $cmd . $args if($rest eq undef);

   while($rest ne undef) {
      ($name,$rest) = balanced_split($rest,"/",4);
      @{$$command{switch}}{lc($name)} = 1;
      return $cmd . $args if($count++ > 20);     # no more  then 20 switches
   }

   return $cmd . $args;
}

#
# spin_run
#    Run a command that came from spin() doing the following:
#
#    1. Determine which command set may be used.
#    2. Handle %{variable} holding command / variable set
#    3. Check/run internal command
#    4. Check/run mushcoded command.
#    5. Check/use exit
#    6. Show huh message
#
sub spin_run
{
   my ($prog,$cmd,$foo) = @_;
   my $self = $$cmd{runas};
   my ($hash,$arg,%switch);
   $$cmd{origcmd} = $$cmd{cmd};
   $$prog{cmd} = $cmd;

   # determine which command set to use
   if($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCKET") {
      if(defined $$prog{from} && $$prog{from} eq "ATTR") {
         $hash = \%command;                     # from attr, use all commands
      } else {
         $hash = \%switch;                             # no internal commands
      }
   } else {
      $hash = \%command;                              # all internal commands
   }

   $$cmd{origcmd} = $$cmd{cmd};
#   printf("PING: '%s'\n",$$prog{ping});
   if($$cmd{cmd} =~ /^\s*$/) {
      return;                                                 # empty command
   } elsif($$cmd{cmd} =~ /^\s*%\{([^ ]+)\}/) {                # found variable
      my ($var,$rest) = ($1,$');

      if($rest =~ /^\s*(=|\+=|-=|\*=|\/=|\+\+|\-\-)\s*/) { # variable operation
         return cmd_var($$cmd{runas},$prog,$var,$rest);
      } elsif(!defined $$prog{var} || !defined @{$$prog{var}}{$var}) {
         return cmd_huh($$cmd{runas},$prog,$$cmd{cmd});         # invalid var
      } else {
         $$cmd{cmd} = @{$$prog{var}}{$var} . $rest;
      }
   }

   $$cmd{cmd} =~ s/^\s+//g;                            # strip leading spaces
   $$cmd{cmd} =~ s/^\\//g if($$cmd{source} == 0);          # fix for escape()
   $$cmd{cmd} = parse_switch($cmd,$$cmd{cmd});
   my ($first,$arg) = bsplit($$cmd{cmd}," ");
   $$cmd{mushcmd} = $first;

   if(lc($first) eq "\@while" &&                   # optimization for @while
      defined $$prog{socket_id} &&
      !defined $$prog{socket_closed} &&
      (!defined $$prog{socket_buffer} ||
       $#{$$prog{socket_buffer}} == -1)) {
      $$prog{idle} = 1;
      return "RUNNING";
  } elsif(defined $$hash{lc($first)}) {                         # internal cmd
      return run_internal($hash,lc($first),$cmd,$prog,$arg);
  } elsif(defined $$hash{substr($first,0,1)} &&          # internal 1 char cmd
     (defined $$hash{substr($first,0,1)}{nsp} ||
      substr($first,1,1) eq " " ||
      length($first) == 1
     )) {
      $$cmd{mushcmd} = substr($first,0,1);

      return run_internal($hash,
                          $$cmd{mushcmd},
                          $cmd,
                          $prog,
                          substr($first,1) . " " . $arg,
                          {},
                          1
                         );
   } elsif(find_exit($self,$prog,loc($self),$$cmd{cmd})) {   # exit as command
      return &{@{$$hash{"go"}}{fun}}($$cmd{runas},$prog,$$cmd{cmd});
   } elsif(find_exit($self,$prog,conf("master"),$$cmd{cmd})) { # exit as master room command
      return &{@{$$hash{"go"}}{fun}}($$cmd{runas},$prog,$$cmd{cmd});
   } elsif(mush_command($self,$prog,$$cmd{runas},$$cmd{origcmd},$$cmd{source})) {
      return 1;                                   # mush_command runs command
   } else { # no match, show HUH?
      if(defined $$prog{ping} && $$prog{ping}) {
         necho(self   => $$cmd{created_by},
               prog   => $prog,
               source => [ "PONG: No matching command found." ]
              );
         return;
      }
      return cmd_huh($$cmd{runas},$prog,$$cmd{cmd});
   }
   return 1;
}


#
# find_in_list
#    given an @array, find $thing within the list using matching.
#
sub find_in_list
{
   my $thing = lc(shift);
   my (@list) = @_;
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

   if($start_count == 1) {                  # one match at begining of string
      return obj($start_obj);
   } elsif($middle_count == 1) {              # one match in middle of string
      return obj($middle_obj);
   } else {
      return undef;                               # too many matches, or none
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
      return undef;
   } elsif($thing =~ /^\s*#(\d+)\s*$/) {
      return valid_dbref($1) ? obj($1) : undef;
   } elsif($thing =~ /^\s*here\s*$/) {
      return loc_obj($self);
   } elsif($thing =~ /^\s*%#\s*$/) {
      return $$prog{created_by};
   } elsif($thing =~ /^\s*#master\s*$/) {             # return master room
      my $master = get(0,"conf.master");
      return ($master =~ /^\s*#{0,1}(\d+)\s*/) ? obj($1) : undef;
   } elsif($thing =~ /^\s*#web\s*$/) {               # return web object
      my $master = get(0,"conf.webobject");
      return ($master =~ /^\s*#{0,1}(\d+)\s*/) ? obj($1) : undef;
   } elsif($thing =~ /^\s*#starting\s*$/) {           # return starting room
      my $master = get(0,"conf.starting_room");
      return ($master =~ /^\s*#{0,1}(\d+)\s*/) ? obj($1) : undef;
   } elsif($thing =~ /^\s*me\s*$/) {
      return $self;
   } elsif($thing =~ /^\s*\*/) {
       my $player = trim(ansi_remove(lc($')));
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
   return find_exit($self,$prog,loc($self),$thing);
}

#
# find_exit
#    Given a location, see if there is an exit named after $thing
#
sub find_exit
{
   my ($self,$prog,$loc,$thing) = (obj(shift),shift,shift,trim(lc(shift)));
   my ($partial,$dup);

   if($thing =~ /^\s*#(\d+)\s*$/) {
      return hasflag($1,"EXIT") ? obj($1) : "#foo";
   }

   for my $obj (lexits($loc)) {
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
      return ($$self{obj_id} == loc($1)) ? obj($1) : undef;
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
   my ($self,$prog,$thing) = (obj(shift),shift,trim(ansi_remove(lc(shift))));
   my ($partial,$dup);

   if($thing =~ /^\s*#(\d+)\s*$/) {
      return hasflag($1,"PLAYER") ? obj($1) : undef;
   } elsif($thing =~ /^\s*me\s*$/ ) {
      return hasflag($self,"PLAYER") ? $self : undef;
   } elsif($thing =~ /^\s*%#\s*$/) {
      return $$prog{created_by};
   } elsif($thing =~ /^\s*\*/) {
       my $player = trim(ansi_remove(lc($')));
       if(defined @player{$player}) {
          return obj(@player{$player});
       } else {
          return undef
       }
   }

   if(defined @player{lc($thing)}) {
      return obj(@player{lc($thing)});
   } else {
      return find_in_list($thing,values %player);
   }
   return obj($partial);
}

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

    if($depth + length($txt) < conf("max")) {           # short, copy it as is.
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
    if($depth + length($cmd . " " . $txt) < conf("max")) {
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
    if(length($txt)+$depth + 3 < conf("max")) {
       return dprint($depth,"%s %s",$cmd,$txt);
    }

    # split up command by ','
    my @list = fmt_balanced_split($txt,',',3);

    # split up first segment again by "="
    my ($first,$second) = fmt_balanced_split(shift(@list),'=',3);


    my $len = $depth + length($cmd) + 1;                  # first subsegment
    if($len + length($first)  > conf("max")) {                 # multilined
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
       } elsif($depth + $indent + length(@list[$i]) > conf("max") || # long cmd
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

      if(length($val) + $depth < conf("max")) {
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
   if($depth + length("$left$function($arguments)$right") - length(@array[0])
      < conf("max")) {
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

   if($depth + length($txt) < conf("max")) {                      # too small
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

    if($depth + length($txt) < conf("max")) {
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
   delete @fun{keys %fun};
   @fun{info}       = sub { return &fun_info(@_);                  };
   @fun{dump}       = sub { return &fun_dump(@_);                  };
   @fun{variables}  = sub { return &fun_variables(@_);             };
   @fun{lvariable}  = sub { return &fun_lvariable(@_);             };
   @fun{password}   = sub { return &fun_password(@_);              };
   @fun{s}          = sub { return &fun_s(@_);                     };
   @fun{set}        = sub { return &fun_set(@_);                   };
   @fun{EVAL}       = sub { return &fun_u(@_);                     };
   @fun{html_strip} = sub { return &fun_html_strip(@_);            };
   @fun{tohex}      = sub { return &fun_tohex(@_);                 };
   @fun{foreach}    = sub { return &fun_foreach(@_);               };
   @fun{itext}      = sub { return &fun_itext(@_);                 };
   @fun{inum}       = sub { return &fun_inum(@_);                  };
   @fun{ilev}       = sub { return &fun_ilev(@_);                  };
   @fun{pack}       = sub { return &fun_pack(@_);                  };
   @fun{unpack}     = sub { return &fun_unpack(@_);                };
   @fun{round}      = sub { return &fun_round(@_);                 };
   @fun{if}         = sub { return &fun_if(@_);                    };
   @fun{ifelse}     = sub { return &fun_if(@_);                    };
   @fun{pid}        = sub { return &fun_pid(@_);                   };
   @fun{lpid}       = sub { return &fun_lpid(@_);                  };
   @fun{null}       = sub { return &fun_null(@_);                  };
   @fun{args}       = sub { return &fun_args(@_);                  };
   @fun{shift}      = sub { return &fun_shift(@_);                 };
   @fun{unshift}    = sub { return &fun_unshift(@_);               };
   @fun{pop}        = sub { return &fun_pop(@_);                   };
   @fun{push}       = sub { return &fun_push(@_);                  };
   @fun{asc}        = sub { return &fun_ord(@_);                   };
   @fun{ord}        = sub { return &fun_ord(@_);                   };
   @fun{chr}        = sub { return &fun_chr(@_);                   };
   @fun{escape}     = sub { return &fun_escape(@_);                };
   @fun{trim}       = sub { return &fun_trim(@_);                  };
   @fun{ansi}       = sub { return &fun_ansi(@_);                  };
   @fun{ansi_remove}= sub { return &fun_ansi_remove(@_);           };
   @fun{colors}     = sub { return &fun_colors(@_);                };
   @fun{ansi_debug} = sub { return &fun_ansi_debug(@_);            };
   @fun{substr}     = sub { return &fun_substr(@_);                };
   @fun{mul}        = sub { return &fun_mul(@_);                   };
   @fun{file}       = sub { return &fun_file(@_);                  };
   @fun{cat}        = sub { return &fun_cat(@_);                   };
   @fun{space}      = sub { return &fun_space(@_);                 };
   @fun{repeat}     = sub { return &fun_repeat(@_);                };
   @fun{time}       = sub { return &fun_time(@_);                  };
   @fun{keys}       = sub { return &fun_keys(@_);                  };
   @fun{timezone}   = sub { return &fun_timezone(@_);              };
   @fun{flags}      = sub { return &fun_flags(@_);                 };
   @fun{quota}      = sub { return &fun_quota(@_);                 };
   @fun{mush_address}=sub { return &fun_mush_address(@_);          };
   @fun{input}      = sub { return &fun_input(@_);                 };
   @fun{has_input}  = sub { return &fun_has_input(@_);             };
   @fun{strlen}     = sub { return &fun_strlen(@_);                };
   @fun{right}      = sub { return &fun_right(@_);                 };
   @fun{left}       = sub { return &fun_left(@_);                  };
   @fun{lattr}      = sub { return &fun_lattr(@_);                 };
   @fun{iter}       = sub { return &fun_iter(@_);                  };
   @fun{list}       = sub { return &fun_list(@_);                  };
   @fun{citer}      = sub { return &fun_citer(@_);                 };
   @fun{parse}      = sub { return &fun_iter(@_);                  };
   @fun{huh}        = sub { return "#-1 Undefined function";       };
   @fun{ljust}      = sub { return &fun_ljust(@_);                 };
   @fun{rjust}      = sub { return &fun_rjust(@_);                 };
   @fun{loc}        = sub { return &fun_loc(@_);                   };
   @fun{extract}    = sub { return &fun_extract(@_);               };
   @fun{lwho}       = sub { return &fun_lwho(@_);                  };
   @fun{remove}     = sub { return &fun_remove(@_);                };
   @fun{get}        = sub { return &fun_get(@_);                   };
   @fun{xget}       = sub { return &fun_get(@_);                   };
   @fun{default}    = sub { return &fun_default(@_);               };
   @fun{eval}       = sub { return &fun_eval(@_);                  };
   @fun{edit}       = sub { return &fun_edit(@_);                  };
   @fun{add}        = sub { return &fun_add(@_);                   };
   @fun{sub}        = sub { return &fun_sub(@_);                   };
   @fun{div}        = sub { return &fun_div(@_);                   };
   @fun{fdiv}       = sub { return &fun_fdiv(@_);                  };
   @fun{secs}       = sub { return &fun_secs(@_);                  };
   @fun{loadavg}    = sub { return &fun_loadavg(@_);               };
   @fun{after}      = sub { return &fun_after(@_);                 };
   @fun{before}     = sub { return &fun_before(@_);                };
   @fun{member}     = sub { return &fun_member(@_);                };
   @fun{index}      = sub { return &fun_index(@_);                 };
   @fun{replace}    = sub { return &fun_replace(@_);               };
   @fun{num}        = sub { return &fun_num(@_);                   };
   @fun{locate}     = sub { return &fun_locate(@_);                };
   @fun{lnum}       = sub { return &fun_lnum(@_);                  };
   @fun{name}       = sub { return &fun_name(0,@_);                };
   @fun{fullname}   = sub { return &fun_name(1,@_);                };
   @fun{type}       = sub { return &fun_type(@_);                  };
   @fun{u}          = sub { return &fun_u(@_);                     };
   @fun{v}          = sub { return &fun_v(@_);                     };
   @fun{r}          = sub { return &fun_r(@_);                     };
   @fun{setq}       = sub { return &fun_setq(@_);                  };
   @fun{setr}       = sub { return &fun_setr(@_);                  };
   @fun{mid}        = sub { return &fun_substr(@_);                };
   @fun{strtrunc}   = sub { return &fun_strtrunc(@_);              };
   @fun{center}     = sub { return &fun_center(@_);                };
   @fun{inc}        = sub { return &fun_inc(@_);                   };
   @fun{dec}        = sub { return &fun_dec(@_);                   };
   @fun{rest}       = sub { return &fun_rest(@_);                  };
   @fun{first}      = sub { return &fun_first(@_);                 };
   @fun{last}       = sub { return &fun_last(@_);                  };
   @fun{switch}     = sub { return &fun_switch(@_);                };
   @fun{words}      = sub { return &fun_words(@_);                 };
   @fun{eq}         = sub { return &fun_eq(@_);                    };
   @fun{not}        = sub { return &fun_not(@_);                   };
   @fun{match}      = sub { return &fun_match(@_);                 };
   @fun{strmatch}   = sub { return &fun_strmatch(@_);              };
   @fun{isnum}      = sub { return &fun_isnum(@_);                 };
   @fun{gt}         = sub { return &fun_gt(@_);                    };
   @fun{gte}        = sub { return &fun_gte(@_);                   };
   @fun{lt}         = sub { return &fun_lt(@_);                    };
   @fun{lte}        = sub { return &fun_lte(@_);                   };
   @fun{or}         = sub { return &fun_or(@_);                    };
   @fun{bor}        = sub { return &fun_bor(@_);                   };
   @fun{owner}      = sub { return &fun_owner(@_);                 };
   @fun{and}        = sub { return &fun_and(@_);                   };
   @fun{hasflag}    = sub { return &fun_hasflag(@_);               };
   @fun{orflags}    = sub { return &fun_orflags(@_);               };
   @fun{squish}     = sub { return &fun_squish(@_);                };
   @fun{capstr}     = sub { return &fun_capstr(@_);                };
   @fun{lcstr}      = sub { return &fun_lcstr(@_);                 };
   @fun{ucstr}      = sub { return &fun_ucstr(@_);                 };
   @fun{setinter}   = sub { return &fun_setinter(@_);              };
   @fun{listinter}  = sub { return &fun_listinter(@_);             };
   @fun{sort}       = sub { return &fun_sort(@_);                  };
   @fun{mudname}    = sub { return &fun_mudname(@_);               };
   @fun{version}    = sub { return &fun_version(@_);               };
   @fun{inuse}      = sub { return &inuse_player_name(@_);         };
   @fun{web}        = sub { return &fun_web(@_);                   };
   @fun{run}        = sub { return &fun_run(@_);                   };
   @fun{lexits}     = sub { return &fun_lexits(@_);                };
   @fun{lcon}       = sub { return &fun_lcon(@_);                  };
   @fun{home}       = sub { return &fun_home(@_);                  };
   @fun{rand}       = sub { return &fun_rand(@_);                  };
   @fun{lrand}      = sub { return &fun_lrand(@_);                 };
   @fun{reverse}    = sub { return &fun_reverse(@_);               };
   @fun{base64}     = sub { return &fun_base64(@_);                };
   @fun{compress}   = sub { return &fun_compress(@_);              };
   @fun{uncompress} = sub { return &fun_uncompress(@_);            };
   @fun{revwords}   = sub { return &fun_revwords(@_);              };
   @fun{idle}       = sub { return &fun_idle(@_);                  };
   @fun{conn}       = sub { return &fun_conn(@_);                  };
   @fun{fold}       = sub { return &fun_fold(@_);                  };
   @fun{telnet_open}= sub { return &fun_telnet(@_);                };
   @fun{min}        = sub { return &fun_min(@_);                   };
   @fun{find}       = sub { return &fun_find(@_);                  };
   @fun{convsecs}   = sub { return &fun_convsecs(@_);              };
   @fun{convtime}   = sub { return &fun_convtime(@_);              };
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
   @fun{ldelete}    = sub { return &fun_ldelete(@_);               };
   @fun{hasattr}    = sub { return &fun_hasattr(@_);               };
   @fun{hasattrp}   = sub { return &fun_hasattrp(@_);              };
   @fun{attr_created}=sub { return &fun_attr_created(@_);          };
   @fun{attr_modified}=sub{ return &fun_attr_modified(@_);         };
   @fun{ansi2mush}  = sub { return &fun_ansi2mush(@_);             };
   @fun{lhelp}      = sub { return &fun_lhelp(@_);                 };
   @fun{conf}       = sub { return &fun_conf(@_);                  };
   @fun{help}       = sub { return &fun_help(@_);                  };
   @fun{graph}      = sub { return &fun_graph(@_);                 };
   @fun{strcat}     = sub { return &fun_strcat(@_);                };
   @fun{readonly}   = sub { return &fun_readonly(@_);              };
   @fun{encrypt}    = sub { return &fun_encrypt(@_);               };
   @fun{decrypt}    = sub { return &fun_decrypt(@_);               };
   @fun{haspower}   = sub { return &fun_haspower(@_);              };
   @fun{zone}       = sub { return &fun_zone(@_);                  };
   @fun{starttime}  = sub { return &fun_starttime(@_);             };
   @fun{delete}     = sub { return &fun_delete(@_);                };
   @fun{findable}   = sub { return &fun_findable(@_);              };
   @fun{power}      = sub { return &fun_power(@_);                 };
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

#
# tomush
#   Convert the a string into its mush equivalent. $flag tells the function
#   if the code is going to be used inside a function.
#
sub tomush
{
   my ($txt,$flag,$start,$end) = @_;
   my ($i,$out,$output);

   for($i = 0;$i < length($txt);$i++) {                    # cycle each char
      my $ch = substr($txt,$i,1);
      if($ch eq " " && ($i + $start == 0 || ($i + 1 == length($txt) && $flag)||
         $i + $start + 1 == $end && !$flag)) {
         $out = "%b";                                 # special case spaces
      } elsif($ch eq " ") {
         $out = ($out eq " ") ? "%b" : " ";                 # alternate %bs
      } elsif($ch eq "\n") {
         $out = "%r";
      } elsif($ch eq '[' || $ch eq ']' || $ch eq '%' || $ch eq '\\' ||
         $ch eq '{' || $ch eq '}' || $ch eq '(' || $ch eq ')' || ($ch eq "," && $flag)) { # escape char
         $out = "\\$ch";
      } else {
         $out = $ch;                                          # normal char
      }
      $output .= $out;                                      # add to output
   }
   return $output;
}

#
# mushify
#    Convert a string into its mush equivalent while trying to use as
#    few characters as possible. Do character compression using the
#    repeat() command.
#
sub mushify
{
   my $txt = shift;
   my ($ch,$done,$start,$i,$mult,$mush,$out,$loc);

   $txt =~ s/\t/     /g;                                      # expand tabs
   $txt =~ s/^\n{2,999}/\n/g;
   for($loc=0,$done=0;$loc <= length($txt);$loc++,$done=0) {
      for($i=1;$i < 10 && $i < (length($txt)- $loc) / 2 && !$done;$i++) {
         my $seg = substr($txt,$loc,$i);
         for($mult=1;$seg eq substr($txt,$loc + ($i*$mult),$i);$mult++) {};
         if(($seg eq " " && $mult > 6) || ((length($mush=tomush($seg,1,0,
            length($txt)))+length($mult) + 11) < (length($seg)*$mult))) {
            $out .= tomush(substr($txt,$start,$loc-$start),0,$loc,length($txt));
            $out .= ($seg eq " ") ? "[space($mult)]" : "[repeat($mush,$mult)]";
            $loc += length($seg) * $mult - 1;                  # skip chars
            $done = 1;                                    # get out of loop
         }
      }
      $start = $loc + 1 if($done);              # set next starting point
   }
   return $out . tomush(substr($txt,$start,length($txt)),0,$start,length($txt));
}

#
# ansi_compress_segment
#    Given a color code, strip out any sequental calls to ansi() that
#    are at the begining of the string.
#
sub ansi_compress_segment
{
   my ($data,$code) = @_;
   my $out;

   while($data =~ /^\[ansi\(\<#([a-f0-9]+)\>,(.+?)\)\]/) {
      my ($pre,$color,$txt,$post)= ($',$1,$2,$');

      if($color eq $code) {
         $data = $post;
         $out .= $txt;
      } else {
         return $out, $post;
      }
   }
   return $out, $data;
}

#
# ansi_compress
#    Take a string from ansi2mush and remove any extra ansi() calls that
#    are not needed to produce a smaller string.
#
sub ansi_compress
{
   my $data = shift;
   my ($chunk,$pending,$result);

   while($data =~ /\[ansi\(/) {
       my ($pre,$post) = ($`,$');
       $result .= $`;

       if($post =~ /\<#([a-f0-9]+)\>,(.+?)\)\]/ ||
          $post =~ /([a-z]+),(.+?)\)\]/) {
#       printf("FUNCTION: '%s' -> '%s'\n",$1,$2);
          $result .= "[ansi(<#$1>,";
          ($chunk,$data) = ansi_compress_segment($',$1);
          $result .= $2 . $chunk . ")]";
#          printf("COMPRESS: '%s%s' -> '%s'\n",$2,$chunk,mushify($2 . $chunk));
       } else {
          $result .= "[ansi(";
          $data = $post;
       }
   }
   return $result . $data;
}

#
# crypt_code
#    This is a port of the C code in TinyMUSH/Rhost to perl. It is
#    functionally the same.
#
sub crypt_code
{
   my ($self,$prog,$txt,$pass,$type) = @_;
   my $txt = evaluate($self,$prog,$txt);
   my $out;

   for(my ($x,$y)=(0,0);$x < length($txt);$x++,$y++) {
      $y = 0 if $y >= length($pass);
      my $ch = ord(substr($txt,$x,1));
      my $p  = ord(substr($pass,$y,1));

      $out .= ($type) ? chr(($ch-32+$p-32)%95+32) : chr(($ch-$p+190)%95+32);
   }
   return $out;
}

#
# fun_haspower
#    Place holder for when powers are implimented.
#
sub fun_haspower
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (ZONE) EXPECTS 2 ARGUMENTS";

   return 0;
}

#
# public_address
#    Return the hostname of the MUSH server
#
sub fun_mush_address
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,0) ||
     return "#-1 FUNCTION (MUSH_ADDRESS) EXPECTS NO ARGUMENTS";

   if(@info{"dns"} == -1) {
      return err($self,$prog,"#-1 DISABLED");
   } elsif(!defined @info{mush_address}) {                 # not cached, yet
      my $r = Net::DNS::Resolver->new(nameservers=>["resolver1.opendns.com"])||
         return;

      my $query = $r->search("myip.opendns.com") || return;

      foreach my $record ($query->answer) {
         my $name = gethostbyaddr(inet_aton($record->address),AF_INET);

         if($name eq undef || $name =~ /in-addr\.arpa$/) {
            @info{mush_address} = $record->address;
            return $record->address;
         } else {
            @info{mush_address} = $name;
            return $name;
         }
      }
   } else {
      return @info{mush_address};                  # return cached address
   }
}

sub fun_quota
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (QUOTA) EXPECTS 1 ARGUMENTS";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NO SUCH OBJECT";

   return quota($target,"max") . " " .
          quota($target,"used") . " " .
          quota($target,"left");
}

#
# fun_zone
#    Place holder for when powers are implimented.
#
sub fun_zone
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (ENCRYPT) EXPECTS 1 ARGUMENT";

   return 0;
}

sub fun_starttime
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,0) ||
     return "#-1 FUNCTION (STARTTIME) EXPECTS 0 ARGUMENTS";

   return scalar localtime(@info{server_start});
}

sub fun_encrypt
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (ENCRYPT) EXPECTS 2 ARGUMENTS";

   my $text = evaluate($self,$prog,shift);
   my $pass = evaluate($self,$prog,shift);

   return crypt_code($self,$prog,$text,$pass,1);
}

sub fun_decrypt
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (DECRYPT) EXPECTS 2 ARGUMENTS";

   my $text = evaluate($self,$prog,shift);
   my $pass = evaluate($self,$prog,shift);

   return crypt_code($self,$prog,$text,$pass,0);
}

sub fun_readonly
{
   my ($self,$prog) = @_;

   $$prog{read_only} = 1;
   return undef;
}

sub fun_power
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
     return "#-1 FUNCTION (POWER) EXPECTS 2 ARGUMENTS";

   my $num = evaluate($self,$prog,shift);
   my $pow = evaluate($self,$prog,shift);

   $num = 1 if(!looks_like_number($num));
   $pow = 1 if(!looks_like_number($pow));

   return $num ** $pow;
}

sub fun_strcat
{
   my ($self,$prog) = (obj(shift),shift);
   my $result;

   for my $i (0 .. $#_) {
      $result .= trim(evaluate($self,$prog,shift));
   }

   return $result;
}
sub fun_info
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (INFO) EXPECTS 1 ARGUMENT";

   my $var = evaluate($self,$prog,shift);

   if(defined @info{$var}) {
      return @info{$var};
   } else {
      return undef;
   }
}

sub fun_graph
{
   my ($self,$prog,$x,$y) = @_;

   return graph_connected($x,$y);
}

sub fun_password
{
   my ($self,$prog) = (obj(shift),shift);

   hasflag($self,"WIZARD") ||
     hasflag($self,"GOD") ||
     $$self{obj_id} eq conf("webuser") ||
     return "#-1 PERMISSION DENIED";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NO SUCH OBJECT";

   if(mushhash(evaluate($self,$prog,shift)) eq get($target,"obj_password")) {
      return 1;
   } else {
      return 0;
   }
}

sub fun_lvariable
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,0,1) ||
     return "#-1 FUNCTION (LVARIABLE) EXPECTS 0 OR 1 ARGUMENTS";

   if(!defined $$prog{var}) {
      return undef;
   } elsif($#_ == -1) {
      return uc(join(' ',keys %{$$prog{var}}));
   } else {
      my $pat = glob2re(shift);
      my @result;

      for my $key (keys %{$$prog{var}}) {
         push(@result,uc($key)) if($key =~ /$pat/i);
      }
      return join(' ',@result);
   }
}

sub fun_variables
{
   my ($self,$prog) = (obj(shift),shift);

   my $txt = evaluate($self,$prog,"\@rfind [escape(name(*adrick))]");

   for my $i (balanced_split($txt,";",3,1)) {
      printf("   split: '%s'\n",$i);
   }
   return print_var($$prog{var});
}
sub fun_conf
{
   my ($self,$prog,$txt) = (obj(shift),shift,lc(trim(shift)));

   if($txt ne undef) {
      if($txt =~ /^CONF./i && (defined @info{conf}->{$'} ||
         hasattr(obj(0),"conf.$'"))) {
         printf("Trying: '$''\n");
         return conf(lc(trim($')));
      } else {
         printf("!Trying: '$''\n");
         return undef;
      }
   } else {
      my @list;
      if(defined @info{conf}) {
         for my $key (sort keys %{@info{conf}}) {
            push(@list,uc("CONF.$key")) if lc($key) ne "version";
         }
         return join(' ',@list);
      } else {
         return undef;
      }
   }
}

sub fun_lhelp
{
   return join(' ',sort keys %help);
}

sub fun_s
{
   my ($self,$prog) = (obj(shift),shift);

   return evaluate($self,$prog,shift)
}

sub fun_help
{
   my ($self,$prog,$txt) = (obj(shift),shift,shift);

   if(defined @help{lc(trim($txt))}) {
      return @help{lc(trim($txt))};
   } elsif(defined @help{lc(trim($txt)) . "()"}) {
      return @help{lc(trim($txt)) . "()"};
   } else {
      return "#-1";
   }
}

# return the flat file database structure for an object
sub fun_dump
{
   my ($self,$prog) = (obj(shift),shift);


   if(!(hasflag($self,"WIZARD") || hasflag($self,"GOD"))) {
      return "#-1 PERMISSION DENIED";
   }

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   return "#-1" if(!valid_dbref($target));

   return db_object($$target{obj_id});
#   return encode_base64(compress(db_object($$target{obj_id})));
}

sub fun_ansi2mush
{
   my($self,$prog) = (obj(shift),shift);
   my ($depth,$out) = (0);

   my %ansi_letter = (
      30 => "x", 40 => "X", 31 => "r", 41=> "R", 32 => "g", 42 => "G",
      33 => "y", 43 => "Y", 34 => "b", 44 => "B", 35 => "m", 45 => "M",
      36 => "c", 46 => "C", 37 => "w", 47 => "W", 4=> "u", 7 => "i",
      1 => "h", 5 => "f", 0 => "n"
   );

   my $txt = evaluate($self,$prog,shift);
   $txt =~ s/\r//g;
#   $txt =~ s/ /%b/g;
   my $str = ansi_init($txt);

   my $snap = $$str{snap};
   my $code = $$str{code};
   my $ch = $$str{ch};
   my $seg;

   for my $i (0 .. $#$ch) {
      for my $y (0 .. $#{$$code[$i]}) {
         my $seq = @{$$code[$i]}[$y];

         if($seq eq "\e[0m") {
            $out .= mushify($seg) . (($depth) ? ")]"  : "");
            $seg = undef;
            $depth = 0;
         } elsif($seq =~ /^\e\[38;5;(\d+)m/ && defined @ansi_rgb{$1}){
            $out .= mushify($seg) . (($depth) ? ")]"  : "");
            $out .= "[ansi(<#" . @ansi_rgb{$1} . ">,";
            $depth = 1;
            $seg = undef;
         } elsif($seq =~ /^\e\[(\d+)m/ && defined @ansi_letter{$1}){
            $out .= mushify($seg) . (($depth) ? ")]"  : "");
            $out .= "[ansi(" . @ansi_letter{$1} . ",";
            $depth = 1;
            $seg = undef;
         } elsif($seq =~ /^\e\[38;5;(\d+);\d+m/ && defined @ansi_rgb{$1}){
            $out .= mushify($seg) . (($depth) ? ")]"  : "");
            $out .= "[ansi(<#" . @ansi_rgb{$1} . ">,";
            $depth = 1;
            $seg = undef;
#         } else {
#            $out .= "[ansi(#unknown-" . ansi_debug($seq,1) . ",";
#            $prev = undef;
#            $depth++;
          }
       }
       $seg .= $$ch[$i];
   }

   $out .= mushify($seg) . (($depth) ? "#)]"  : "");
   return $out;
}

sub fun_hasattr
{
   my($self,$prog) = (obj(shift),shift);
   my ($obj,$attr);

   # handle args in "object/attr" or "object,attr" format

   if($#_ == 0) {
      ($obj,$attr) = balanced_split(shift,"/",4);
   } else {
      ($obj,$attr) = (shift,shift);
   }
   $obj = evaluate($self,$prog,$obj);
   $attr = evaluate($self,$prog,$attr);

   my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
      return "#-1 NOT FOUND";

   my $hash = mget($target,$attr);

   return (ref($hash) eq "HASH") ? 1 : 0;
}

sub fun_hasattrp
{
   my($self,$prog) = (obj(shift),shift);
   my ($obj,$attr);

   # handle args in "object/attr" or "object,attr" format

   if($#_ == 0) {
      ($obj,$attr) = balanced_split(shift,"/",4);
   } else {
      ($obj,$attr) = (shift,shift);
   }
   $obj = evaluate($self,$prog,$obj);
   $attr = evaluate($self,$prog,$attr);

   my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
      return "#-1 NOT FOUND";

   my $hash = mget($target,$attr);                   # check object attribute
   return 1 if (ref($hash) eq "HASH");


   my $parent = mget($target,"obj_parent");          # check parent attribute
   return 0 if (ref($parent) ne "HASH" || !valid_dbref($$parent{value}));

   if($attr =~ /one/) {
      $hash = mget($$parent{value},$attr,1);
   } else {
      $hash = mget($$parent{value},$attr);
   }
   return (ref($hash) eq "HASH") ? 1 : 0;
}

sub fun_attr_created
{
   my($self,$prog) = (obj(shift),shift);
   my ($obj,$attr);

   # handle args in "object/attr" or "object,attr" format

   if($#_ == 0) {
      ($obj,$attr) = balanced_split(shift,"/",4);
   } else {
      ($obj,$attr) = (shift,shift);
   }
   $obj = evaluate($self,$prog,$obj);
   $attr = evaluate($self,$prog,$attr);

   my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
      return "#-1 NOT FOUND";

   my $hash = mget($target,$attr);

   if(ref($hash) eq "HASH") {
      return $$hash{created};
   } else {
      return $$hash{created};
   }
}

sub fun_attr_modified
{
   my($self,$prog) = (obj(shift),shift);
   my ($obj,$attr);

   # handle args in "object/attr" or "object,attr" format

   if($#_ == 0) {
      ($obj,$attr) = balanced_split(shift,"/",4);
   } else {
      ($obj,$attr) = (shift,shift);
   }
   $obj = evaluate($self,$prog,$obj);
   $attr = evaluate($self,$prog,$attr);

   my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
      return "#-1 NOT FOUND";

   my $hash = mget($target,$attr);

   if(ref($hash) eq "HASH") {
      return $$hash{modified};
   } else {
      return $$hash{modified};
   }
}

sub fun_tohex
{
   my($self,$prog) = (obj(shift),shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (TOHEX) EXPECTS 1 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);

   return sprintf("%X",$txt);
}

sub fun_colors
{
   my($self,$prog) = (obj(shift),shift);
   my @result;

   good_args($#_,1,2) ||
     return "#-1 FUNCTION (COLORS) EXPECTS 1 OR 2 ARGUMENTS";

   my $txt = trim(evaluate($self,$prog,shift));
   my $key = evaluate($self,$prog,shift);

   if($key =~ /^\s*x\s*$/) {
      if($txt =~ /^\s*0x\+\s*(.+?)\s*$/ || $txt =~ /^\s*\+\s*(.+?)\s*$/) {
         if(defined @ansi_name{lc($1)}) {
            if(!defined @ansi_rgb{@ansi_name{lc($1)}}) {
               return "#-1 INTERNAL ERROR - UNDEFINED RGB VALUE " .
                  @ansi_name{lc($1)};
            } else {
               return "#" . @ansi_rgb{@ansi_name{lc($1)}};
            }
         }
      }
      return "#-1 INVALID COLOR SPECIFIED";
   } elsif($key =~ /^\s*n\s*$/) {
      if($txt =~ /^\s*0x\+\s*(.+?)\s*$/ || $txt =~ /^\s*\+\s*(.+?)\s*$/) {
         if(defined @ansi_name{lc($1)}) {
            for my $i (keys %ansi_name) {
               if(@ansi_name{$i} eq @ansi_name{lc($1)}) {
                  push(@result,$i);
               }
            }
            return join(" ",@result);
         }
      }
      return "#-1 INVALID COLOR SPECIFIED";
   } else {
      return "#-1 UNIMPLIMENTED KEY";
   }
}
#
# fun_ldelete
#    Delete a word/item from the text.
sub fun_ldelete
{
   my($self,$prog) = (obj(shift),shift);
   my (@delete, @result);

   good_args($#_,2,3,4) ||
     return "#-1 FUNCTION (LDELETE) EXPECTS BETWEEN 2 AND 4 ARGUMENTS";

   my $txt       = evaluate($self,$prog,shift);
   my $positions = evaluate($self,$prog,shift);
   my $idelim    = evaluate($self,$prog,trim(shift));
   my $odelim    = evaluate($self,$prog,trim(shift));
   $idelim = " " if $idelim eq undef;
   $odelim = $idelim if $odelim eq undef;

   my @list = safe_split($txt,$idelim);

   for my $i (sort {$b <=> $a} safe_split($positions," ")) {
      if(isint($i) && $i >= 1 && $i <= $#list + 1) {
         splice(@list,$i-1,1);
      }
   }

   if($odelim ne " ") {
      for my $i (0 .. $#list) {
         @list[$i] = fun_squish($self,$prog,@list[$i]);
      }
   }
   return join($odelim,@list);
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

   if(@info{"html_restrict"} == -1) {
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

   my $return = chr(13);
   my $input = evaluate($self,$prog,shift);
   $input =~ s/\r//mg;

   my $txt    = ansi_init($input);
   my $type   = trim(ansi_remove(evaluate($self,$prog,shift)));
   my $chars  = trim(ansi_remove(evaluate($self,$prog,shift)));

   if($type =~ /^\s*(b|l|r)\s*$/) {                             # check args
      $type = $1;
   } else {
      $type = "b";                               # emulate Mush w/no errors
   }

   if($chars eq undef) {                               # set chars to filter
      @filter{" "} = 1;
      @filter{chr(9)} = 1;
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
   my ($self,$prog,$txt,$noeval) = (obj(shift),shift,shift,shift);
   my ($str,$out);
#   printf("%s\n",print_var($prog));

   if($noeval) {
      $str = ansi_init($txt);
   } else {
      $str = ansi_init(evaluate($self,$prog,$txt));
   }

   for my $i (0 .. $#{$$str{ch}}) {
      if(@{$$str{ch}}[$i] eq "%" ||
         @{$$str{ch}}[$i] eq "\\" ||
         @{$$str{ch}}[$i] eq "[" ||
         @{$$str{ch}}[$i] eq "]" ||
         @{$$str{ch}}[$i] eq "(" ||
         @{$$str{ch}}[$i] eq ")" ||
         @{$$str{ch}}[$i] eq "," ||
         @{$$str{ch}}[$i] eq ";") {
         $out .= join('',@{@{$$str{code}}[$i]}) . "\\" . @{$$str{ch}}[$i];
      } else {
         $out .= join('',@{@{$$str{code}}[$i]}) . @{$$str{ch}}[$i];
      }
   }
   return "\\" . $out;
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

   if($txt =~ /^\s*all\s*$/i || $txt =~ /^\s*$/) {
      $hash = gather_stats(1,"all");
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
            return "\e[38;5;$i\m" if($rgb_diff2 ==  0);
         }
      } else {
         printf("Unparseable entry $i -> '@ansi_rgb{$i}'\n");
      }
   }
   return "\e[38;5;$result\m";
}

sub fun_ansi_remove
{
   my ($self,$prog,$txt) = (obj(shift),shift);


   good_args($#_,1) ||
      return "#-1 FUNCTION (ANSI_REMOVE) EXPECTS 1 ARGUMENT";
   return ansi_remove(evaluate($self,$prog,shift));
}

sub fun_ansi
{
   my ($self,$prog) = (obj(shift),shift);
   my $out;

   good_args($#_,2) ||
      return "#-1 FUNCTION (ANSI) EXPECTS 2 ARGUMENTS";

   my $code = evaluate($self,$prog,shift);
   my $txt = evaluate($self,$prog,shift);

   my $item = $code;
#   for my $item (split(" ",$code)) {
      if($item =~ /^\s*<\s*(\d+)\s+(\d+)\s+(\d+)\s*>\s*$/) {
         $out .= rgb2ansi($1,$2,$3);
      } elsif($item=~/^\s*#\s*([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})\s*$/i ||
         $item=~/^\s*<\s*#\s*([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})\s*>\s*$/i){
         $out .= rgb2ansi(hex($1),hex($2),hex($3));
      } elsif($item=~ /^\s*\+\s*([^ ]+)\s*$/) {
         if(defined @ansi_name{lc($1)}) {
            $out .= "\e[38;5;" . @ansi_name{lc($1)} . "m";
         }
      } elsif($code !~ /^\s*</) {
         $out .= color($code,undef,1);
      }
#   }

   return $out . $txt . "\e[0m";
}

sub fun_set
{
   my ($self,$prog,$value) = (obj(shift),shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (SET) EXPECTS 2 ARGUMENTS";

   my ($obj,$attr,$delim) = balanced_split(shift,"/",4);

   my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
      return "#-1";

   return "#-1 PERMISSION DENIED" if(!controls($self,$target));

   if($delim) {                                       # set attribute flag
      my $flag = trim(evaluate($self,$prog,shift));

      if(!isatrflag($flag)) {
         return "#-1 INVALID ATTRIBUTE FLAG";
      } elsif(!hasattr($target,$attr)) {
         return "#-1 ATTRIBUTE DOES NOT EXIST";
      } elsif(!can_set_flag($self,$target,$flag)) {
         return "#-1 PERMISSION DENIED";
      } else {
         set_atr_flag($target,$attr,$flag,0);
         return undef;
      }
   }

   my ($attr,$value,$delim) = balanced_split(shift,":",4);
   my $attr = trim(evaluate($self,$prog,$attr));

   if($delim && !reserved($attr)) {                   # set attribute
      set($self,$prog,$target,$attr,evaluate($self,$prog,$value),1);
      # set attribute value
   } elsif($delim) {
      return "#-1 INVALID ATTRIBUTE NAME";
   } else {                                                      # set flag
      my $flag = trim(evaluate($self,$prog,$attr));

      if(!can_set_flag($self,$target,$flag)) {
         return "#-1 PERMISSION DENIED";
      } elsif(flag($flag)) {
        set_flag($self,$prog,$target,$flag);
      } else {
        return "#-1 INVALID FLAG";
      }
   }
   return undef;
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

   return "#-1 FUNCTION (ENTITIES) NOT ENABLED" if (@info{entities} == -1);
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

   if($fn !~ /\.(txt|pl|js)$/i) {
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

   good_args($#_,1,2) ||
     return set_var($prog,"data","#-1 FUNCTION (URL) EXPECTS 1 OR 2 ARGUMENTS");

   hasflag($self,"SOCKET_INPUT") ||
      return set_var($prog,"data","#-1 PERMISSION DENIED");

   my $txt = ansi_remove(evaluate($self,$prog,shift));
   my $accept = ansi_remove(evaluate($self,$prog,shift));

   $accept = "*/*" if($accept =~ /^\s*$/);

   if($txt =~ /^https:\/\/([^\/]+)\//) {
      ($host,$path,$secure) = ($1,$',1);
   } elsif($txt =~ /^http:\/\/([^\/]+)\//) {
      ($host,$path,$secure) = ($1,$',0);
   } else {
      return set_var($prog,"data","#-1 Unable to parse URL");
   }

   if($secure && @info{"url_https"} == -1) {
      return set_var($prog,"data","#-1 HTTPS DISABLED");
   } elsif(!$secure && @info{"url_http"} == -1) {
      return set_var($prog,"data","#-1 HTTP DISABLED");
   } elsif(hasflag($self,"SOCKET_PUPPET") && find_socket($self,$prog) ne undef){
      return set_var($prog,"data","#-1 CONNECTION ALREADY OPEN WITH \@TELNET");
   } elsif(defined $$prog{socket_id} && $$prog{socket_url} ne $txt &&
      !defined $$prog{socket_closed}) {
      return set_var($prog,"data","#-1 CONNECTION ALREADY OPEN");
   } elsif($$prog{socket_url} eq $txt) {               # existing connection
      my $buff = $$prog{socket_buffer};

      if($#$buff >= 0) {
         my $data = shift(@$buff);

# wttr.in debug
#         if($data =~ /mph/)  {
#            printf("%s -> %s\n",$data,lord($`));
#             printf("      '%s'\n",$data);
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

      # printf("HOST: '%s'\n",$host);
      # printf("PATH: '%s'\n",$path);
      # printf("SEC: '%s'\n",$secure);

      $$prog{socket_url} = $txt;

      if(!$sock) {
         $$prog{socket_closed} = 1;
         $$prog{socket_buffer} = [ "#-1 CONNECTION FAILED" ];
         return 1;
      }

#      $sock->blocking(0);                                     # don't block

      $$prog{socket_id} = $sock;                    # link prog to socket
      delete @$prog{socket_closed};

      # make request as curl (helps with wttr.in)
      $path =~ s/ /%20/g;
      set_var($prog,"url",$path);

      eval {                        # protect against uncontrollable problems
         if($#_ == 1) {
            printf("ARGS: 1\n");
            my ($type,$value) = (shift,shift);
            $sock->write_request(GET => "/$path",
               'User-Agent' => 'curl/7.52.1',
               $type => $value,
                Accept => $accept
            );
         } else {
#            printf("ARGS: $#_\n");
            $sock->write_request("GET" => "\/$path",
                                 "User-Agent" => "curl/7.52.1",
                                 "Accept" => $accept
                                );
#            printf("got this far\n");
         }
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
         printf("ERROR: '%s'\n",$@);
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

# what should i draw today


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

   good_args($#_,1) ||
     return "#-1 FUNCTION (CONTROLS) EXPECTS 1 ARGUMENT";

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

#
# convtime
#    Convert a time string to epoch time. TinyMUSH's version only converts a
#    specific format. This function taps into a function that already exists
#    that tries to convert a timestring of almost any format.
#
#
sub fun_convtime
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (CONVTIME) EXPECTS 1 ARGUMENTS";

  return fuzzy(evaluate($self,$prog,shift));
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

sub fun_conn
{
   my ($self,$prog,$txt) = (obj(shift),shift);
   my ($result,$target,$port) = (-1);

   good_args($#_,1) ||
     return "#-1 FUNCTION (CONN) EXPECTS 1 ARGUMENT";

   my $lookfor = evaluate($self,$prog,shift);

   if(isint($lookfor)) {
      $port = $lookfor;
   } else {
     $target = find_player($self,$prog,$lookfor) ||
        return -1;
   }

   for my $key (keys %connected) {
      my $hash = @connected{$key};

      if(!hasflag($hash,"DARK")) {
         if(($port eq undef && $$target{obj_id} == $$hash{obj_id}) ||
            ($port ne undef && $$hash{port} == $port)) {

            my $onfor = time() - $$hash{start};
            $result = $onfor if($onfor > $result);
         }
      }
   }
   return $result;
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

   my $type = ansi_remove(evaluate($self,$prog,shift));
   my $txt = ansi_remove(evaluate($self,$prog,shift));

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

   @info{compress} ||
      return "#-1 function disable due to missing perl module";

   hasflag($self,"WIZARD") ||
     $$self{obj_id} eq conf("webuser") ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 WIZARD FLAG OR IS WEBUSER";

   good_args($#_,1) ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 ARGUMENT";

   my $txt = evaluate($self,$prog,shift);

   return compress($txt);
}

sub fun_uncompress
{
   my ($self,$prog) = (obj(shift),shift);

   @info{compress} ||
      return "#-1 function disable due to missing perl module";

   hasflag($self,"WIZARD") ||
     $$self{obj_id} eq conf("webuser") ||
     return "#-1 FUNCTION (COMPRESS) EXPECTS 1 WIZARD FLAG OR IS WEBUSER";

   good_args($#_,1) ||
     return "#-1 FUNCTION (UNCOMPRESS) EXPECTS 1 ARGUMENT";

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
   my ($size_x,$size_y) = @_;
   my (%all, %usage,$max,$val,$min,@out, $prev);

   $size_y = 8 if($size_y eq undef || $size_y < 8);

   my $attr = mget(0,"stat_login");

   if($attr ne undef) {
      my $hash = $$attr{value};
      for my $key (keys %$hash) {
         @all{age(fuzzy($key))} = $$hash{$key};
         $max = $$hash{$key} if $$hash{$key} > $max;
         if($$hash{$key} < $max || $max eq undef) {
            $min = $$hash{$key};
         }
      }
   }
   $min = 1 if $min == 0;

    # build the graph from the data within @all
    for my $x ( 1 .. $size_x ){
       if($x == 1) {
          $val = $max;
#       } elsif($x == $size_x) {
#          $val = $min;
      } else {
          $val = sprintf("%d",int($max-($x *($max/$size_x))+1.5));
       }

       if($val ne $prev) {
          @out[$x-1] = sprintf("%*d|",length($max),$val);
          $prev = $val;
       } else {
          @out[$x-1] = sprintf("%*s|",length($max)," ");
       }
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
    $prev = undef;

    for(my $y=0;$y <= $size_y-1;$y++) {
       my $curr = sprintf("%02d",(localtime(time() - ($y * 86400)))[3]);
       my $next = sprintf("%02d",(localtime(time() - (($y+1) * 86400)))[3]);

       if(substr($curr,0,1) ne substr($next,0,1)) {
          @out[$start] .= sprintf("=[%s]",substr($next,0,1));
          @out[$start+1] .= substr(sprintf("%2d",$curr),1,1) . "|";
          @out[$start+1] .= substr(sprintf("%2d",$next),1,1) . "|";
          $y++;
       } else {
          @out[$start] .= "==";
          @out[$start+1] .= substr(sprintf("%2d",$curr),1,1) . "|";
       }
    }
    return join("\n",@out);
}


#
# fun_run
#    Run a command as if it was a function. Each @command cannot be run
#    as a function should will need a test condition to prevent it
#    from running like below:
#
#  in_run_function($prog) &&      # sleep can not be called from inside run()
#     return out($prog,"#-1 \@SLEEP can not be called from RUN function");
#
sub fun_run
{
   my ($self,$prog) = (shift,shift);
   my (%none, $hash, %tmp, $match, $cmd,$arg);

   good_args($#_,1) ||
      return "#-1 FUNCTION (RUN) REQUIRES 1 ARGUMENT";

   in_run_function($prog) &&
      return "#-1 Function run cannot be called recursively or not allowed.";

   my $txt = evaluate($self,$prog,shift);

   my $command = { runas => $self };
   if($txt  =~ /^\s*([^ \/]+)(\s*)/) {        # split cmd from args
      ($cmd,$arg) = (lc($1),$');
   } else {
      return #-1 No command given to run;                       # only spaces
   }
   $$prog{nomushrun} = 1;
   my $cmd = { runas   => $self,
               source  => $$prog{source},
               invoker => invoker($prog,$self),
               prog    => $prog,
               mdigits => {},
               cmd     => $txt,
             };
   my $tmp = $$prog{output};
   $$prog{output} = [];
   spin_run($prog,$cmd);
   my $output = join(',',@{$$prog{output}});
   if($tmp eq undef) {
      delete @$prog{output};
   } else {
      $$prog{output} = $tmp;
   }
   delete @$prog{nomushrun};
   $output =~ s/\n+$//;
   return $output;
}

sub safe_split
{
   my ($txt,$delim,$flag) = @_;
   my ($start,$pos,@result) = (0,0);
   my $orig = $txt;
   $delim = ansi_remove($delim);

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
   my $ch = $$txt{ch};

   if($delim eq " " && !$flag) {                      # exclude inital spaces
      for(;$pos < $size;$pos++) {                     # when delim is a space
          last if(ansi_substr($txt,$pos,$dsize,1) ne $delim);
      }
   }

   for(;$pos < $size;$pos++) {
      if(ansi_substr($txt,$pos,$dsize,1) eq $delim) {
         if($delim eq " ") {
            for($pos++;$pos < $size &&
                ansi_substr($txt,$pos,1,1) eq " ";$pos++) {};
            $pos-- if($$ch[$pos] ne " ");
         }
         push(@result,ansi_substr($txt,$start,$pos-$start));
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

# sub quota
# {
#    my $self = shift;
#
#    return quota_left($self);
# }

sub quota
{
   my ($self,$type) = (obj(shift),shift);
   my $target = owner($self);

   return undef if($type !~ /^(max|used|left)$/);
   return undef if(!valid_dbref($self) || !hasflag($target,"PLAYER"));

   if(get($target,"obj_quota") =~ /^([-\d]+),([-\d]+)$/) {
      if($type eq "max") {
         return $1;
      } elsif($type eq "used") {
         return $2;
      } elsif($type eq "left") {
         return $1 - $2;
      }
   } else {
      return 0;
   }
}

#
# set_quota
#    type
#       max  : set the maxium allowed objects
#       used : set number of used objects
#       add  : Add one object to the number of used objects
#       sub  : Subtract one object to the number of used objects
#
sub set_quota
{
   my ($target,$type,$amount) = (obj(shift),shift,shift);
   my $owner = owner($target);

   # verify arguments
   return 0 if($type !~ /^(max|used|add|subtract|sub)$/);
   if(!(($type =~ /^(max|used)$/ && $amount =~ /^\s*(\d+)\s*$/) ||
        ($type =~ /^(add|sub)$/ && $amount eq undef))) {
      return 0;
   }
   return 0 if($owner eq undef);

   # do the work
   if(get($owner,"obj_quota") =~ /^([-\d]*),([-\d]*)$/) {
      if($type eq "max") {
         db_set($owner,"obj_quota","$amount," . nvl($2,0));
      } elsif($type eq "used") {
         db_set($owner,"obj_quota",nvl($1,0) . ",$amount");
      } elsif($type eq "add") {
         db_set($owner,"obj_quota",nvl($1,0) . "," . ($2 - 1));
      } elsif($type eq "subtract" || $type eq "sub") {
         db_set($owner,"obj_quota",nvl($1,0) . "," . ($2 + 1));
      } else {
         return 0;
      }
   } elsif($type eq "max") {
      db_set($owner,"obj_quota","$amount,1");
   } else {
      return 0;
   }
   return 1;
}



sub fun_mudname
{
   my ($self,$prog) = (shift,shift);

   my $name = conf("mudname");

   return ($name eq undef) ? "TeenyMUSH" : $name;
}

sub fun_version
{
   return conf("version");
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

   for my $key (sort {@{@connected{$b}}{start} <=> @{@connected{$a}}{start}}
                keys %connected) {
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
   my $y;

   good_args($#_,1) ||
     return "#-1 FUNCTION (SQUISH) EXPECTS 1 ARGUMENT ($#_)";

   my $txt = ansi_init(evaluate($self,$prog,shift));
   my $ch = $$txt{ch};
   my $snap = $$txt{snap};
   my $code = $$txt{code};

   for(my $i=0;$i <= $#$ch;$i++) {
      if($i == 0 || ( $i < $#$ch && $$ch[$i] eq " " && $$ch[$i+1] eq " ")) {
         for($y=0;$y < $#$ch;$y++) {
            if($$ch[$i + $y] ne " ") {            # found non-space, exit
               last;
            }
            last if $y > 500;
         }

         if($y > 0) {
            $$code[$i+2] = [ "\e[0m", @{@$snap[$i+1]} ];
            if($i == 0) {
               splice(@$ch,$i,$y);
            } else {
               splice(@$ch,$i+1,$y-1);
               splice(@$snap,$i+1,$y-1);
               splice(@$code,$i+1,$y-1);
            }
            if($i == 0) {
               $$code[$i] = [ @{@$snap[$i]} ];
            } elsif(join('',@{$$snap[$i]}) eq join('',@{$$snap[$i+1]})) {
               # ansi codes are the same, do nothing.
            } else {
               $$code[$i+1] = [ "\e[0m", @{@$snap[$i+1]} ];
            }
            $i--;
         }
      }
      last if $i > 500;
   }

   if($$ch[$#$ch-1] eq " ") {    # trim end, should be one space at this point
      delete @$ch[$#$ch-1];
      ansi_reset($txt,$#$ch-1);
   }

   return ansi_string($txt,1);
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
      return "#-1 FUNCTION (LOC) EXPECTS 1 ARGUMENT";

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
   } elsif(controls($self,$target)) {
      return "#" . loc($target);
   } elsif(hasflag($target,"UNFINDABLE") || hasflag($target,"DARK")) {
      return "#-1";
   } else {
      return "#" . loc($target);
   }
}

sub fun_findable
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (FINDABLE) EXPECTS 2 ARGUMENTS";

   my $obj = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   return "#-1 PERMISSION DENIED" if(!readonly($self,$obj));

   my $loc = fun_loc($obj,$prog,"#" . $$target{obj_id});

   if($loc =~ /^#-/) {
      return 0;
   } else {
      return 1;
   }
}

sub fun_orflags
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (HASFLAG) EXPECTS 2 ARGUMENTS";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   my $flags = shift;
   $flags =~ s/ //g;

   for my $i (split(//,$flags)) {
      my $flag = get_flag_by_letter($i);
      return 1 if($flag ne undef && hasflag($target,$flag));
   }
   return 0;
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

sub fun_bor
{
   my ($self,$prog) = (shift,shift);
   my $result = 0;

   good_args($#_,1 .. 100) ||
      return "#-1 FUNCTION (BOR) EXPECTS 1 AND 100 ARGUMENTS";

   for my $i (@_) {
      my $value = evaluate($self,$prog,$i);
      if(isint($value)) {
         $result |= $value;
      } else {
         return "#-1 ARGUMENTS MUST BE INTEGERS"
      }
   }
   return $result;
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

   my $txt = trim(evaluate($self,$prog,shift));
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
   my ($self,$prog) = (obj(shift),shift);
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

sub fun_inc
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,0,1) ||
      return "#-1 FUNCTION (INC) EXPECTS 0 OR 1 ARGUMENTS";

   my $number = evaluate($self,$prog,shift);

   if($number =~ /^\s*(\d+)\s*$/) {
      return sprintf("%d",$1 + 1);
   } else {
      return 1;
   }
}

sub fun_dec
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,0,1) ||
      return "#-1 FUNCTION (DEC) EXPECTS 0 OR 1 ARGUMENTS";

   my $number = evaluate($self,$prog,shift);

   if($number =~ /^\s*(\d+)\s*$/) {
      return sprintf("%d",$1 - 1);
   } else {
      return -1;
   }
}

sub fun_center
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (CENTER) EXPECTS 2 OR 3 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $size = evaluate($self,$prog,shift);
   my $fill = evaluate($self,$prog,shift);

   if(!isint($size)) {
      return "#-1 SECOND ARGUMENT MUST BE NUMERIC - '$size'";
   } elsif($size eq 0) {
      return "#-1 SECOND ARGUMENT MUST NOT BE ZERO";
   } elsif($size >= 8000) {
      return "#-1 OUT OF RANGE";
   }

   $fill = " " if($fill eq undef);

   $txt = ansi_substr($txt,0,$size);

   my $len = ansi_length($txt);

   my $lpad = sprintf("%d",($size - $len) / 2);
   my $ltxt = ansi_substr($fill x $lpad,0,$lpad);
   my $rpad = $size - $lpad - $len;
   my $rtxt = ansi_substr($fill x $rpad,0,$rpad);
   return "$ltxt$txt$rtxt";
}

sub ansi_center
{
   my ($txt,$size,$fill) = @_;

   $fill = " " if($fill eq undef);
   $txt = ansi_substr($txt,0,$size);
   my $len = ansi_length($txt);
   my $lpad = sprintf("%d",($size - $len) / 2);
   my $ltxt = ansi_substr($fill x $lpad,0,$lpad);
   my $rpad = $size - $lpad - $len;
   my $rtxt = ansi_substr($fill x $rpad,0,$rpad);
   return "$ltxt$txt$rtxt";
}

sub fun_switch
{
   my ($self,$prog) = (shift,shift);

   my $first = single_line(evaluate($self,$prog,trim(shift)));

   while($#_ >= 0) {
      if($#_ >= 1) {
         my $txt = single_line(evaluate($self,$prog,trim(shift)));
         my $cmd = shift;

         if(ansi_remove($txt) =~ /^\s*(<|>)\s*/) {
             if($1 eq ">" && $first > $' || $1 eq "<" && $first < $') {
                return evaluate($self,$prog,$cmd);
             }
         } else {
            my @wild = ansi_match($first,$txt);
            if($#wild >=0) {
               my $prev = get_digit_variables($prog);
               my $tmp = @{$$prog{cmd}}{mdigit};
               @{$$prog{cmd}}{mdigits} = {
                  0 => @wild[0], 1 => @wild[1], 2 => @wild[2], 3 => @wild[3],
                  4 => @wild[4], 5 => @wild[5], 6 => @wild[6], 7 => @wild[7],
                  8 => @wild[8], 9 => @wild[9],
               };
               my $result = evaluate($self,$prog,$cmd);
               @{$$prog{cmd}}{mdigits} = $tmp;
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
      my $result = substr($txt,$loc + length($after));
      return $result;
   }
}

sub fun_rest
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1 .. 2) ||
      return "#-1 Function (REST) EXPECTS 1 or 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $delim = ansi_remove(evaluate($self,$prog,shift));
   $delim = " " if($delim eq undef);
   my $loc = index(ansi_remove($txt),$delim);

   if($loc == -1) {
      return $txt;
   } else {
      return fun_trim($self,$prog,ansi_substr($txt,$loc + length($delim),9999));
   }
}

sub fun_first
{
   my ($self,$prog) = (shift,shift);


   good_args($#_,1,2) ||
      return "#-1 Function (FIRST) EXPECTS 1 or 2 ARGUMENTS";

   my $txt = evaluate($self,$prog,shift);
   my $delim = ansi_remove(evaluate($self,$prog,shift));

   if($delim eq undef || $delim eq " ") {
      $txt =~ s/^\s+|\s+$//g;
      $txt =~ s/\s+/ /g;
      $delim = " ";
   }
   my $loc = index(evaluate($self,$prog,ansi_remove($txt)),$delim);

   if($loc == -1) {
      return $txt;
   } else {
      return fun_trim($self,$prog,ansi_substr($txt,0,$loc));
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

   my $one = ansi_remove(evaluate($self,$prog,shift));
   my $two = ansi_remove(evaluate($self,$prog,shift));

   $one = hex(trim($one)) if($one =~ /^\s*0x([0-9a-f]{2})\s*$/i);
   $two = hex(trim($two)) if($two =~ /^\s*0x([0-9a-f]{2})\s*$/i);

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

   my $one = ansi_remove(evaluate($self,$prog,shift));
   my $two = ansi_remove(evaluate($self,$prog,shift));

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
   my (@out, @before);

   return "#-1 Add requires at least one argument" if $#_ < 0;

   for my $i (0 .. $#_) {
      push(@before,@_[$i]);
      my $val = ansi_remove(evaluate($self,$prog,@_[$i]));

      push(@out,$val);
      if($val =~ /^\s*0x([0-9a-f]{2})\s*$/i) {
         $result += hex(trim($val));
      } else {
         $result += $val;
      }
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

   my $result = ansi_remove(evaluate($self,$prog,shift));
   $result = tohex($1) if($result =~ /^\s*0x([0-9a-f]{2})\s*$/i);

   while($#_ > -1) {
      my $val = ansi_remove(evaluate($self,$prog,shift));
      $val = tohex($1) if($val =~ /^\s*0x([0-9a-f]{2})\s*$/i);
      $result *= $val;
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

   my $result = ansi_remove(evaluate($self,$prog,shift));

   $result = hex(trim($result)) if($result =~ /^\s*0x([0-9a-f]{2})\s*$/i);

   while($#_ >= 0) {
      my $val = ansi_remove(evaluate($self,$prog,shift));

      if($val =~ /^\s*0x([0-9a-f]{2})\s*$/i) {
         $result -= hex(trim($val));
      } else {
         $result -= $val;
      }
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

   good_args($#_,3,4,5) ||
      return "#-1 FUNCTION (EDIT) EXPECTS 3 AND 5 ARGUMENTS";

   my $txt    = evaluate($self,$prog,shift);
   my $from   = ansi_remove(evaluate($self,$prog,trim(shift)));
#   my $from   = trim(ansi_remove(evaluate($self,$prog,shift)));
   my $to     = evaluate($self,$prog,shift);
   my $type   = evaluate($self,$prog,shift);
   my $strict = evaluate($self,$prog,shift);
   my $size   = ansi_length($from);
   $strict = 1 if($strict eq undef || ($strict ne 1 & $strict ne 2));

   if($strict == 2) {                                   # edit whole string
      my $size   = length($from);
      for(my $i = 0, $start = 0;$i <= length($txt);$i++) {
         if(substr($txt,$i,$size) eq $from) {
            if($start ne undef || $i != $start) {
               $out .= substr($txt,$start,$i - $start);
            }
            $out .= $to;
            $i += $size;
            $start = $i;
            last if($type);
         }
      }
      if($start ne undef or $start >= length($txt)) {  # add left over chars
         $out .= substr($txt,$start,length($txt) - $start + 1);
      }
   } else {                                         # don't edit ansi strings
      $txt = ansi_init($txt);
      my $size   = ansi_length($from);
      for(my $i = 0, $start=0;$i <= $#{$$txt{ch}};$i++) {
         if(ansi_remove(ansi_substr($txt,$i,$size)) eq $from) {
            if($start ne undef || $i != $start) {
               $out .= ansi_substr($txt,$start,$i - $start);
            }
            $out .= ansi_clone($txt,$i,$to);
            $i += $size;
            $start = $i;
            last if($type);
         }
      }
      if($start ne undef or $start >= $#{$$txt{ch}}) {  # add left over chars
         $out .= ansi_substr($txt,$start,$#{$$txt{ch}} - $start + 1);
      }
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

sub fun_locate
{
   my ($self,$prog) = (shift,shift);
   my (%result, @r, $prefer);
   my $random = 0;

   good_args($#_,3) ||
      return "#-1 FUNCTION (LOCATE) EXPECTS 3 ARGUMENT";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   readonly($self,$target) ||
      return err($self,$prog,"#-1 PERMISSION DENIED");

   my $what = lc(trim(ansi_remove(evaluate($self,$prog,shift))));
   my $where  = evaluate($self,$prog,shift);

   for(my $i=0;$i < length($where);$i++) {
      if(substr($where,$i,1) eq "a") {
         @result{"a"} = $1 if($what =~ /^\s*#(\d+)\s*$/ && valid_dbref($1));
      } elsif(substr($where,$i,1) eq "c") {
         my $obj= find_exit($self,$prog,$target,$what);
         @result{c} = $$obj{obj_id} if $obj ne undef;
      } elsif(substr($where,$i,1) eq "e") {
         my $obj = find_exit($self,$prog,loc($target),$what);
         @result{e} = $$obj{obj_id} if $obj ne undef;
      } elsif(substr($where,$i,1) eq "h") {
         if($what eq lc(ansi_remove(name(loc($target))))) {
            @result{h} = return loc($target);
         }
      } elsif(substr($where,$i,1) eq "i") {
         my $obj = find_in_list($what,lcon($target));
         @result{e} = $$obj{obj_id} if $obj ne undef;
      } elsif(substr($where,$i,1) eq "m") {
         @result{m} = $$target{obj_id} if $what eq "me";
      } elsif(substr($where,$i,1) eq "n") {
         my $obj = find_in_list($what,lcon(loc($target)));
         @result{n} = $$obj{obj_id} if $obj ne undef;
      } elsif(substr($where,$i,1) eq "p") {
         if($what =~ /^\s*\*/) {
            my $player = trim(ansi_remove(lc($')));
            if(defined @player{$player}) {
               @result{p} = @player{$player};
            }
         }
      } elsif(substr($where,$i,1) eq "E") {
         $prefer = "E";
      } elsif(substr($where,$i,1) eq "L") {
         $prefer = "L";
      } elsif(substr($where,$i,1) eq "P") {
         $prefer = "P";
      } elsif(substr($where,$i,1) eq "R") {
         $prefer = "R";
      } elsif(substr($where,$i,1) eq "T") {
         $prefer = "T";
      } elsif(substr($where,$i,1) eq "V") {
         $prefer = "V";
      } elsif(substr($where,$i,1) eq "X") {
         $random = 1;
      }
   }

   for my $key (keys %result) {
      if($prefer eq undef) {
        return "#-2" if(!$random && $#r == 0);
        push(@r,@result{$key});
      } else {
         if($prefer eq "E" && hasflag(@result{$key},"EXIT")) {
            return "#-2" if(!$random && $#r == 0);
            push(@r,@result{$key});
         }
         if($prefer eq "L" && hasflag(@result{$key},"EXIT")) {
            my $atr = get($target,"OBJ_LOCK_DEFAULT");
            if($atr ne undef) {
               my $lock = lock_eval($self,$prog,$target,$atr);

               if(!$$lock{error} && $$lock{result}) {
                  return "#-2" if(!$random && $#r == 0);
                  push(@r,@result{$key});
               }
            }
         }
         if($prefer eq "P" && hasflag(@result{$key},"PLAYER")) {
            return "#-2" if(!$random && $#r == 0);
            push(@r,@result{$key});
         }
         if($prefer eq "T" && hasflag(@result{$key},"OBJECT")) {
            return "#-2" if(!$random && $#r == 0);
            push(@r,@result{$key});
         }
      }
   }

   if($random) {
      return @r[rand($#r + 1)];
   } else {
      return @r[0];
   }
}


sub fun_owner
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (OWNER) EXPECTS 1 ARGUMENT";

   my $target = find($self,$prog,evaluate($self,$prog,shift)) ||
      return "#-1 NOT FOUND";

   my $owner = owner($target);

   if(ref($owner) eq "HASH") {
      return "#" . $$owner{obj_id};
   } else {
      return "#-1";                            # this should never happen
   }
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
#     printf("%s\n",print_var($prog));
     return name($target,undef,$self,$prog);
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

   my $value = pget($obj,$atr) ||
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
   my ($txt,$obj,$attr,@arg);

#   stack_print();

   if(defined $$prog{mush_function_name}) {
      if(defined @info{mush_function} &&
         defined @{@info{mush_function}}{$$prog{mush_function_name}}) {
         $txt =  @{@info{mush_function}}{$$prog{mush_function_name}};
      } else {
         return "#-1 INVALID USER DEFINED FUNCTION";
      }
   } else {
      $txt = evaluate($self,$prog,shift);
   }

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
#   printf("---[ start ]-----\n");
#   for my $i (0 .. $#arg) {
#      printf("$i : '%s'\n",@arg[$i]);
#   }
#   printf("---[  end  ]-----\n");
   my $result = evaluate($obj,$prog,single_line(pget($obj,$attr)));

   set_digit_variables($self,$prog,"",$prev);            # restore %0 .. %9
   return $result;
}


sub hash_item
{
    my ($obj,$key,$sub) = @_;

    my $attr = mget($obj,$key);
    return undef if $attr eq undef;                      # invalid attribute

    if(ref($$attr{value}) eq "HASH") {                            # is hash?
       my $hash = $$attr{value};

       if(defined $$hash{$sub}) {                            # valid sub key
          return $$hash{$sub};
       } else {                                            # invalid sub key
          return undef;
       }
    } else {                                                    # not a hash
       return undef;
    }
}

sub fun_keys
{
   my ($self,$prog) = (shift,shift);
   my ($obj,$atr,$sub);

   good_args($#_,1,2) ||
      return "#-1 FUNCTION (KEYS) EXPECTS BETWEEN 1 and 2 ARGUMENTS";

   if($#_ == 0) {
      ($obj,$atr) = besplit($self,$prog,shift,"\/");
   } else {
      ($obj,$atr) = (shift,shift);
   }

   ($atr,$sub) = besplit($self,$prog,$atr,".");

   my $target = find($self,$prog,$obj);

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!(controls($self,$target) ||
      hasflag($target,"VISUAL") || atr_hasflag($target,$atr,"VISUAL"))) {
      return "#-1 Permission Denied ($$self{obj_id} -> $$target{obj_id}/$atr)";
   } elsif(db_set_ishash($target,$atr)) {
      return join(" ",db_hash_keys($target,$atr,$sub));
   } else {
      return undef;
   }

   if($sub ne undef) {
      return hash_item($target,$atr,$sub);
   }
}

sub fun_get
{
   my ($self,$prog) = (obj(shift),shift);
   my ($obj,$atr,$sub);

   good_args($#_,1,2) ||
      return "#-1 FUNCTION (GET) EXPECTS BETWEEN 1 and 2 ARGUMENTS";

   if($#_ == 0) {
      ($obj,$atr) = besplit($self,$prog,shift,"\/");
   } else {
      ($obj,$atr) = (evaluate($self,$prog,shift),evaluate($self,$prog,shift));
   }

   ($atr,$sub) = besplit($self,$prog,$atr,":");

   my $target = find($self,$prog,$obj);
   $atr = "description" if($atr =~ /^\s*desc\s*$/);

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!(controls($self,$target) ||
      hasflag($target,"VISUAL") || atr_hasflag($target,$atr,"VISUAL") ||
      hasflag($target,"WIZARD"))) {
      return "#-1 Permission Denied";
   }

   if($sub ne undef) {
      return hash_item($target,$atr,$sub);
   } elsif($atr =~
      /^(last|last_page|last_created_date|create_by|last_whisper)$/) {
      return pget($target,"obj_$atr");
   } elsif(lc($atr) eq "lastsite") {
      return short_hn(lastsite($target));
   } else {
      return pget($target,$atr);
   }
}

sub fun_default
{
   my ($self,$prog) = (obj(shift),shift);
   my ($obj,$atr,$sub);

   good_args($#_,2) ||
      return "#-1 FUNCTION (DEFAULT) EXPECTS 2 ARGUMENTS";

   ($obj,$atr) = besplit($self,$prog,shift,"\/");

   my $target = find($self,$prog,$obj);
   $atr = "description" if($atr =~ /^\s*desc\s*$/);

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!(controls($self,$target) ||
      hasflag($target,"VISUAL") || atr_hasflag($target,$atr,"VISUAL") ||
      hasflag($self,"WIZARD"))) {
      return "#-1 Permission Denied ($$self{obj_id} -> $$target{obj_id}/$atr)";
   }

   if(hasattr($target,$atr)) {                             # has attribute
      return get($target,$atr);
   } elsif(hasattr($target,$atr,"PARENT")) {                        # parent
      return get(parent($target),$atr);
   } else {
      return evaluate($self,$prog,shift);
   }
}

sub fun_eval
{
   my ($self,$prog,$txt) = (shift,shift,shift);

#   printf("EVAL: '%s' -> '%s'\n",$txt,evaluate($self,$prog,evaluate($self,$prog,evaluate($self,$prog,$txt))));
   if($#_ == 0) {
      return evaluate($self,$prog,fun_get($self,$prog,$txt . "/" . $_));
   } elsif($txt =~ /\//) {
      return evaluate($self,$prog,fun_get($self,$prog,$txt));
   } else {
      return evaluate($self,$prog,evaluate($self,$prog,evaluate($self,$prog,$txt)));
   }
}



#
# fun_v
#    Return a un-evaluated attribute
#
sub fun_v
{
   my ($self,$prog,$txt) = (shift,shift,shift);

   return pget($self,evaluate($self,$prog,$txt));
}

sub fun_setq
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (SETQ) EXPECTS 2 ARGUMENTS";

   my $register = lc(trim(evaluate($self,$prog,shift)));

   if($register =~ /^\s*([0-9a-z])\s*$/) {
      @{$$prog{var}}{"setq_$register"} = evaluate($self,$prog,shift);
   } else {
      @{$$prog{var}}{$register} = evaluate($self,$prog,shift);
   }
   return undef;
}

sub fun_setr
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2) ||
      return "#-1 FUNCTION (SETR) EXPECTS 2 ARGUMENTS";

   my $register = lc(trim(evaluate($self,$prog,shift)));

   if($register =~ /^\s*([0-9a-z])\s*$/) {
      @{$$prog{var}}{"setq_$register"} = evaluate($self,$prog,shift);
      return @{$$prog{var}}{"setq_$register"};
   } else {
      @{$$prog{var}}{$register} = evaluate($self,$prog,shift);
      return @{$$prog{var}}{$register};
   }
}

sub fun_r
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (R) EXPECTS 1 ARGUMENTS";

   my $register = trim(evaluate($self,$prog,shift));

   if($register =~ /^\s*(0|1|2|3|4|5|6|7|8|9)\s*$/) {
      if(defined $$prog{var}->{"setq_$register"}) {
         return $$prog{var}->{"setq_$register"};
      } else {
         return undef;
       }
   } elsif(defined $$prog{var}->{$register}) {
      return $$prog{var}->{$register};
   } else {
      return undef;
   }
}

sub fun_extract
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,3,4,5) ||
      return "#-1 FUNCTION (EXTRACT) EXPECTS BETWEEN 3 AND 5 ARGUMENTS";

   my $txt    = evaluate($self,$prog,shift);
   my $first  = evaluate($self,$prog,shift);
   my $length = evaluate($self,$prog,shift);
   my $idelim = evaluate($self,$prog,shift);
   my $odelim = evaluate($self,$prog,shift);
   my $orig = $length;

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

   @list = safe_split($txt,$idelim);
   if($first + $length > $#list) {
      $length = $#list - $first;
   } else {
      $length--;
   }

   if($idelim eq " ") {
#   printf("1Extract: %s,%s,%s,%s='%s'\n",$txt,$first,$length,$idelim,$odelim,
#       trim(join($odelim,@list[$first .. ($first+$length)])));
      return trim(join($odelim,@list[$first .. ($first+$length)]));
   } else {
#   printf("2Extract: %s,%s,%s,%s='%s'\n",$txt,$first,$length,$idelim,$odelim,
#      join($odelim,@list[$first .. ($first+$length)]));
      return join($odelim,@list[$first .. ($first+$length)]);
   }
}

sub fun_delete
{
   my ($self,$prog) = (obj(shift),shift);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (DELETE) EXPECTS 3 OR 4 ARGUMENTS";

   my $txt = shift;
   my $first = ansi_remove(evaluate($self,$prog,shift));
   my $len   = ansi_remove(evaluate($self,$prog,shift));

   if($first !~ /^\s*(\d+)\s*$/) {                    # compat with TinyMUSH
      return $txt;
   } elsif($first !~ /^\s*(\d+)\s*$/) {               # compat with TinyMUSH
      return $txt;
   }

   $txt   = ansi_init(evaluate($self,$prog,$txt));
   return ansi_substr($txt,0,trim($first)) . ansi_substr($txt,$first + $len)

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
   } elsif($size <= 0 || $size >= 8000) {
      return "#-1 OUT OF RANGE";
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
   } elsif($size <= 0 || $size >= 8000) {
      return "#-1 OUT OF RANGE";
   } else {
      my $sub = ansi_substr($txt,0,$size);
      return $sub . ($fill x ($size - ansi_length($sub)));
   }
}

sub fun_strlen
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (STRLEN) EXPECTS 1 ARGUMENTS";

   return ansi_length(ansi_trim(evaluate($self,$prog,shift)));
}


sub fun_strtrunc
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (STRTRUNC) EXPECTS 2 arguments";

   return fun_substr($self,$prog,shift,0,shift);
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
     return "#-1 FUNCTION (LEFT) EXPECTS 2 ARGUMENT";

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

    if($count > 1000 && $count * length($txt) > 1000) {
       return undef;
    } else {
       return $txt x $count;
    }
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

#
# fun_lattr
#    Return a list of attributes on an object or the enactor.
#
sub fun_lattr
{
   my ($self,$prog) = (shift,shift);
   my ($obj,$atr,@list);

   good_args($#_,1) ||
      return "#-1 FUNCTION (LATTR) EXPECTS 1 ARGUMENT";

   my ($obj,$atr) = bsplit(shift,"/");

   my ($atr,$sub) = besplit($self,$prog,$atr,":");

   my $target = find($self,$prog,evaluate($self,$prog,$obj)) ||
      return "#-1 Unknown object";

   if(!controls($self,$target) && !hasflag($target,"VISUAL")) {
      return "#-1 Permission Denied.";
   }

   my $pat = ($atr eq undef) ? undef : glob2re($atr);
   my $spat = ($sub eq undef) ? undef : glob2re($sub);

   for my $attr (grep {!/^obj_/i} lattr($target)) {
      if(db_set_hashable($target,$attr)) {
         for my $key (db_hash_keys($target,$attr)) {
            if($spat eq undef || $key =~ /$spat/) {
               push(@list,uc($attr) . ":" . uc($key));
            }
         }
      } elsif($spat eq undef) {
         push(@list,uc($attr)) if($pat eq undef || $attr =~ /$pat/i);
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

sub stack_print
{
   my $count = 0;
   my $sub = "N/A";

   for my $line (split(/\n/,Carp::shortmess)) {
      if($line =~ /^\s*main::([^ \(]+).* at ([^ ]+) line (\d+)/) {
         if(++$count == 2) {
            $sub = $1;
            last;
         }
      } elsif($count > 3) {
         last;
      }
   }
   printf("---[ start: $sub ]---\n");
   for my $i (0 .. $#_) {
      printf("%-3s : '%s'\n",$i,$_[$i]);
   }
   printf("---[ End ]---\n");
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
   my $argc = $#_;

   my ($list,$txt) = ($_[0],$_[1]);
   my $idelim = evaluate($self,$prog,$_[2]);
   $idelim = " " if($idelim eq undef || $idelim eq "\@\@");
   my $odelim = evaluate($self,$prog,$_[3]);


   if($odelim eq "\@\@") {
      $odelim = "";
   } elsif($argc < 3 && $odelim eq undef) {
      $odelim = " ";
   }

   my @result;

   $$prog{iter_stack} = [] if(!defined $$prog{iter_stack});
   my $loc = $#{$$prog{iter_stack}} + 1;
   for my $item (safe_split(evaluate($self,$prog,$list),$idelim)) {
       $item = trim($item) if ($idelim eq " ");
       @{$$prog{iter_stack}}[$loc] = { val => evaluate($self,$prog,$item),
                                       pos => ++$count };
#       $$prog{var} = {} if !defined $$prog{var};
       push(@result,evaluate($self,$prog,$txt));
   }
   delete @{$$prog{iter_stack}}[$loc .. $#{$$prog{iter_stack}}];

   return join($odelim,@result);
}

#
# fun_list
#
sub fun_list
{
   my ($self,$prog) = (obj(shift),shift);
   my ($count,$target) = (0);

   good_args($#_,2 .. 4) ||
     return "#-1 FUNCTION (LIST) EXPECTS 2 AND 4 ARGUMENTS";
   my $argc = $#_;

   my ($list,$txt) = ($_[0],$_[1]);
   my $idelim = evaluate($self,$prog,$_[2]);
   $idelim = " " if($idelim eq undef || $idelim eq "\@\@");

   my @result;

   $$prog{iter_stack} = [] if(!defined $$prog{iter_stack});
   my $loc = $#{$$prog{iter_stack}} + 1;

   if(defined $$prog{cmd} && defined @{$$prog{cmd}}{invoker}) {
      $target = @{$$prog{cmd}}{invoker};
   } else {
      $target = $self;
   }

   for my $item (safe_split(evaluate($self,$prog,$list),$idelim)) {
#      printf("LIST: '%s'\n",$item);
      $item = trim($item) if ($idelim eq " ");
      @{$$prog{iter_stack}}[$loc] = { val => evaluate($self,$prog,$item),
                                      pos => ++$count };
      my $result = evaluate($self,$prog,$txt);
#      printf("   # '%s'\n",$result);
      necho(self   => $self,
            prog   => $prog,
            target => [ $target, "%s", $result ],
      );
   }
   delete @{$$prog{iter_stack}}[$loc .. $#{$$prog{iter_stack}}];

   return;
}

#
# fun_citer
#
sub fun_citer
{
   my ($self,$prog) = (shift,shift);
   my ($count) = 0;
   my @result;

   good_args($#_,2,3) ||
     return "#-1 FUNCTION (ITER) EXPECTS 2 OR 3 ARGUMENTS";
   my $argc = $#_;

   my $list   = evaluate($self,$prog,shift);
   my $txt    = shift;
   my $odelim = evaluate($self,$prog,shift);

   $odelim = " " if(($argc != 2 && $odelim eq undef) || $odelim eq "\@\@");

   $$prog{iter_stack} = [] if(!defined $$prog{iter_stack});
   my $loc = $#{$$prog{iter_stack}} + 1;
   my $data = ansi_init(evaluate($self,$prog,$list));

   for my $i (0 .. $#{$$data{ch}}) {
       my $item = ansi_substr($data,$i,1);
       @{$$prog{iter_stack}}[$loc] = { val => $item, pos => ++$count };
       my $new = trim($txt);
       $new =~ s/##/$item/g;
       $new =~ s/#\@/$count/g;
       push(@result,trim(evaluate($self,$prog,$new)));
   }
   delete @{$$prog{iter_stack}}[$loc];

   return join($odelim,@result);
}


#
# fun_lookup
#    See if the function exists or not. Return "huh" if only to be
#    consistent with the command lookup
#
sub fun_lookup
{
   my ($self,$prog,$name,$before,$flag) = (shift,shift,lc(shift),shift,shift);

   if(defined @fun{lc($name)}) {
      return lc($name);
   } elsif(defined @info{mush_function} &&
      defined @{@info{mush_function}}{lc($name)}) {
      return "EVAL";
   }

#   if(!$flag) {
#      con("undefined function '%s'\n",$name);
#      con("                   '%s'\n",ansi_debug($before));
#      con("%s",code("long"));
#   }

   # record missing function for @missing
   if(defined $$prog{missing} && ref($$prog{missing}) eq "HASH") {
      $$prog{missing}->{fun}->{lc($name)}++;
   }

   return "huh";
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
   my (@result, $stack);

   if($$prog{function_command}++ > conf("function_limit")) {
      return undef; # "#-1 FUNCTION INVOCATION LIMIT HIT";
   }
   $$prog{function}++;


#   my $stack = new_balanced_split("mid(time(woot(biz))x,0,5)");
#   for my $i (0 .. $#$stack) {
#      printf("%s : %s\n",$$stack[$i]->{depth},$$stack[$i]->{data});
#   }
#   printf("Parsing: '%s'\n","[$fun($txt");
   if(0) {

   if($type == 1) {
      $stack = new_balanced_split("[$fun($txt");
   } else {
      $stack = new_balanced_split("$fun($txt");
   }
   if($stack eq undef || $#$stack < 1) {
      return undef if $stack eq undef || $#$stack <= 1;
   }
#   for my $i (0 .. $#$stack) {
#      printf("%s : %s\n",$$stack[$i]->{depth},$$stack[$i]->{data});
#   }

   for my $i (1 .. $#$stack) {              # convert to old data structure
      if($i == $#$stack) {                       # is end of function right?
         if($$stack[$i]->{depth} != 0) {
            return undef;                          # parentheses not matched
         } elsif($type == 1 && $$stack[$i]->{data} =~ /^\s*\)\s*]/) {
            unshift(@result,$');
         } elsif($type == 2 && $$stack[$i]->{data} ne ")") {
            return undef;                  # parse error, should be no data
         } elsif($type == 2) {
            unshift(@result,undef);
         }
         return \@result;
      } else {
         push(@result,$$stack[$i]->{data});
      }
   }
   return undef;                                       # shouldn't happen?
   }

   my @array = balanced_split($txt,",",$type);
   return undef if($#array == -1);

   # type 1: expect ending ]
   # type 2: expect ending ) and nothing else
   if(($type == 1 && @array[0] =~ /^ *]/) ||
      ($type == 2 && @array[0] =~ /^\s*$/)) {
      @array[0] = $';                              # strip ending ] if there
#      for my $i (0 .. $#array) {
#         printf("# $i : '%s' -> '%s'\n",@array[$i],@result[$i]);
#      }
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
   my ($last,$i,@stack,@depth,$ch,$buf,$found,$escape) = (0,-1);

   my $size = length($txt);
   while(++$i < $size) {
      $ch = substr($txt,$i,1);

      if($ch eq "\e" && substr($txt,$i,20) =~ /^\e\[([\d;]*)([a-zA-Z])/) {
         $i += length("x$1$2");                       # move 1 char short
	 $buf .= "\e\[$1$2";
      } elsif($ch eq "\\" && $#depth == -1) {
	 $buf .= $ch;
	 $escape = 1;
      } elsif($escape) {
	 $buf .= $ch;
	 $escape = 0;
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
               $found = 1;
               if($type == 4) {                        # found delim, done
                  return $buf, substr($txt,$i+1), 1;
               } else {
                  push(@stack,$buf);
                  $last = $i+1;
                  $buf = undef;
               }
            } elsif($type <= 2 && $ch eq ")") {                   # func end
               push(@stack,$buf) if($found || $i != $last);
               $last = $i+1;
               $i = $size;
               $buf = undef;
               $found = 0;
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

   if($type == 4) {
      return $buf, undef, 0;
#   } elsif($type == 3 || $type == 4) {
   } elsif($type == 3) {
      push(@stack,substr($txt,$last)) if($found || $last != $size);
      #      push(@stack,$buf) if($found || $last != $size);
      return @stack;
   } else {
	   unshift(@stack,substr($txt,$last));
	   # unshift(@stack,$buf);
      return ($#depth != -1) ? undef : @stack;
   }
}

sub balanced_add
{
   my ($depth,$stack,$ch,$new) = @_;

   push(@$stack,{depth => 0, data => undef}) if $#$stack < 0;
   if($$stack[-1]->{done} && ($depth == 1 || $depth == 0 && $new)) {
      push(@$stack,{ depth => $depth, data => $ch });
   } else {
      $$stack[-1]->{data} .= $ch;
   }
   $$stack[-1]->{done} = $new;
}

sub new_balanced_split
{
   my ($txt,$delim) = @_;
   my ($depth,$look,$stack) = (0, undef,[]);

#   printf("NEW: '%s'\n",$txt);

   for(my ($size,$i)=(length($txt),0);$i < $size;$i++) {
      my $ch = substr($txt,$i,1);

      if($ch eq "\\") {                                   # character escaped
         balanced_add($depth,$stack,substr($txt,$i++,2));
      } elsif($ch eq "\e" && substr($txt,$i,20) =~ /^\e\[([\d;]*)([a-zA-Z])/) {
         $i += length("x$1$2");                       # found escape sequence
         balanced_add($depth,$stack,"\e\[$1$2");
      } elsif($look ne undef) {                          # slurp up charaters
         balanced_add($depth,$stack,$ch);
         $look = undef if $look eq $ch;                        # end look for
      } elsif($ch eq '{') {                              # start look for '}'
         balanced_add($depth,$stack,$ch);
         $look = '}';
      } elsif($ch eq "(") {
         if($delim ne undef || $depth >= 1) {
            balanced_add(++$depth,$stack,$ch,0);
         } else {
            balanced_add(++$depth,$stack,$ch,1);
         }
      } elsif($depth == 0 && $delim ne undef && $ch eq $delim) {
         $$stack[-1]->{done} = 1;                        # delim end of split
         balanced_add($depth,$stack,"<".substr($txt,$i+1).">",1);
         return $stack;
      } elsif($depth == 1 && $delim eq undef && $ch eq ')') {
         $$stack[-1]->{done} = 1;                     # function end of split
         balanced_add(--$depth,$stack,substr($txt,$i),1);
         return $stack;
      } elsif($ch eq ")") {                                        # go down
         balanced_add(--$depth,$stack,$ch);
      } elsif($delim eq undef && $ch eq ",") {                  # delimiter
         if($depth == 1) {
            balanced_add($depth,$stack,undef,1);
         } else {
            balanced_add($depth,$stack,$ch);
         }
      } elsif($delim ne undef && $ch eq $delim && $depth == 0) { # comma end
         $$stack[-1]->{done} = 1;
         balanced_add(--$depth,$stack,substr($txt,$i),1);
         return $stack;
      } else {                                           # non-important char
         balanced_add($depth,$stack,$ch);
      }
   }

   return ($delim ne undef) ? $stack : undef;
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
   my $id = (ref($self) eq "HASH") ? $$self{obj_id} : $self;
   my $out;

   #
   # handle string containing a single non []'ed function
   #
   return if(!valid_dbref($self));
   return $txt if(conf("safemode"));
   if($txt =~ /^\s*([a-zA-Z_0-9]+)\((.*)\)\s*$/m) {
      my $fun = fun_lookup($self,$prog,$1,undef,1);
      if($fun ne "huh") {                   # not a function, do not evaluate
         my $result = parse_function($self,$prog,$fun,"$2)",2);
         if($result ne undef) {
            shift(@$result);
            con("undefined function: '%s'\n",$fun) if($fun eq "huh");

            my $start = Time::HiRes::gettimeofday();
            $$prog{mush_function_name} = $1 if($fun eq "EVAL");
            my $r=&{@fun{$fun}}($id,$prog,@$result);
            delete @$prog{mush_function_name};
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
      $out .= evaluate_substitutions($self,$prog,$before);
      $out .= "\\" x (length($esc) / 2);

      if(length($esc) % 2 == 0) {
         my $fun = fun_lookup($self,$prog,$unmod,$before);
         my $result = parse_function($self,$prog,$fun,$',1);

         if($result eq undef) {
            $txt = $after;
            $out .= "[$fun(";
         } else {                                    # good function, run it
            $txt = shift(@$result);

            my $start = Time::HiRes::gettimeofday();
            $$prog{mush_function_name} = $unmod if($fun eq "EVAL");
            my $r = &{@fun{$fun}}($id,$prog,@$result);
            delete @$prog{mush_function_name};
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

      if(defined @http{$s} && defined @{@http{$s}}{data}) {
         my $data = @{@http{$s}}{data};
         if(defined $$data{headers_done}) {
            http_process_line($s,@{@http{$s}}{buf});
            @{@http{$s}}{buf} = undef;
         }
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

   if(defined @info{httpd_ban} && defined @{@info{httpd_ban}}{$addr}) {
      $new->close();
      web("   %s %s\@web [BANNED-CLOSE]\n",ts(),$addr);
      $new->close();
   } else {
      $readable->add($new);

      @http{$new} = { sock => $new,
                      data => {},
                      ip   => $addr,
                    };
   }
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
         } elsif($count >= nvl(conf("httpd_invalid"),3)) {
            if(!defined @{@info{httpd_ban}}{$key}) {
               @{@info{httpd_ban}}{$key} = scalar localtime();     # too many
               web("   %s %s\@web *** BANNED **\n",ts(),$key);       # add ban
            }
         } elsif(defined @{@info{httpd_ban}}{$key} ) {  # too little,remove ban
            web("   %s %s\@web Un-BANNNED\n",ts(),$key);
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
   http_out($s,"<html><meta name=\"viewport\" content=\"initial-scale=.5, maximum-scale=1\">");
   http_out($s,"<style>");
   http_out($s,".big {");
   http_out($s,"   line-height: .7;");
   http_out($s,"   margin-bottom: 0px;");
   http_out($s,"   font-size: 100pt;");
   http_out($s,"   color: hsl(0,100%,30%);");
   http_out($s,"}");
   http_out($s,"div.big2 {");
#   http_out($s,"   border: 2px solid red;");
   http_out($s,"   line-height: .2;");
   http_out($s,"   display:inline-block;");
   http_out($s,"   -webkit-transform:scale(2,1); /* Safari and Chrome */");
   http_out($s,"   -moz-transform:scale(2,1); /* Firefox */");
   http_out($s,"   -ms-transform:scale(2,1); /* IE 9 */");
   http_out($s,"   -o-transform:scale(2,1); /* Opera */");
   http_out($s,"   transform:scale(2,1); /* W3C */");
   http_out($s,"}");
   http_out($s,"</style>");
   http_out($s,"<body>");
   http_out($s,"<br>");
   http_out($s,"<table width=100%>");
   http_out($s,"   <tr>");
   http_out($s,"      <td width=30px>");
   http_out($s,"         <div class=\"big\">404</div><br>");
   http_out($s,"         <center>");
   http_out($s,"            <div class=\"big2\">Page not found</div>");
   http_out($s,"         </center>");
   http_out($s,"      </td>");
   http_out($s,"      <td width=30px>");
   http_out($s,"      </td>");
   http_out($s,"      <td>");
   http_out($s,"         <center><hr size=2>$fmt<hr></center>",@args);
   http_out($s,"         <pre>%s</pre>\n",code("long"));
   http_out($s,"      </td>");
   http_out($s,"      </td>");
   http_out($s,"      <td width=30px>");
   http_out($s,"      </td>");
   http_out($s,"   </tr>");
   http_out($s,"</table>");
   http_out($s,"</body>");
   http_out($s,"</html>");
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

   http_out($s,"HTTP/1.1 200 Default Request");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");

   # must store result so cookies can be checked after evaluation
   my $result = ansi_remove(evaluate($$prog{user},
                                     $prog,
                                     conf("httpd_template")
                                    )
                           );

   if(defined $$prog{var} && defined $$prog{var}->{cookie}) {
      http_out($s,"Set-Cookie: %s",$$prog{var}->{cookie});
   }
   http_out($s,"");
   http_out($s,"%s\n",$result);
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
   if(lc($type) eq "pdf") {
      http_out($s,"Content-Type: application/pdf; charset=ISO-8859-1");
   } else {
      http_out($s,"Content-Type: text/$type; charset=ISO-8859-1");
   }
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

   if(defined @http{$s}) {
      printf({@{@http{$s}}{sock}} "$fmt\r\n", @args);
   }
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
   } elsif($$data{get} =~ /testget/i) {                        # woot woot!
      # example: http://110.249.212.46/testget?q=23333&port=80
      return 1;
   } elsif($$data{get} =~ /\.php/i) {                          # no php here
      return 1;
   } elsif($$data{get} =~ /\.cgi/i) {                          # or cgi
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

#   printf("# %s\n",$txt);
   if($txt =~ /^GET (.*) HTTP\/([\d\.]+)$/i) {              # record details
      $$data{get} = $1;
   } elsif($txt =~ /^POST \/{0,1}(.*) HTTP\/([\d\.]+)$/i) {
      $$data{post} = $1;
   } elsif($txt =~ /^HEAD (.*) HTTP\/([\d\.]+)$/i) {          # record details
      $$data{get} = $1;
      $$data{head} = 1;
   } elsif(defined $$data{post} && defined $$data{headers_done}) {
      $$data{post_data} .= $txt;
      if($$data{"VAR_content-length"} == length($$data{post_data})) {
         my $addr = @{@http{$s}}{hostname};
         my $self = obj(conf("webuser"));
         my $prog = mushrun(self   => $self,
                            runas  => $self,
                            invoker=> $self,
                            source => 0,
                            cmd    => $$data{post},
                            hint   => "WEB",
                            sock   => $s,
                            output => [],
                            nosplit => 1,
                           );
          $$prog{get} = $$data{post};
          $$self{hostname} = $addr;
          @{$$prog{var}}{post}=$$data{post};
          for my $item (keys %$data) {           # make header data availible
             @{$$prog{var}}{$'}=$$data{$item} if($item =~ /^VAR_/);
          }
                                     # make post data availible via variable
          for my $item (split('&',$$data{post_data})) {
             if($item =~ /=/ && length($`) < 80) { # and variable names
                my ($var,$dat) = (lc($`),$');      # need to be <80 chars
                $var =~ s/ //g;                          # removes spaces
                $dat =~ s/\+/ /g;
                if(@info{uri_escape} == -1) {        # decode if possible
                   @{$$prog{var}}{$var}=$dat;
                } else {
                   @{$$prog{var}}{$var}=uri_unescape($dat);
                }
            }
         }
      }
   } elsif($txt =~ /^([\w\-]+): /) {
      if(lc($1) eq "content-length" && $' > 4096) {
         http_error($s,"%s","POST REQUEST TO BIG");
      }
      $$data{"VAR_" . lc($1)} = $';
   } elsif($txt =~ /^\s*$/ && defined $$data{post}) {
      $$data{headers_done} = 1;
   } elsif($txt =~ /^\s*$/ && defined $$data{get}) {         # end of request
      $$data{get} = uri_unescape($$data{get}) if(@info{uri_escape} != -1);
      $$data{get} =~ s/\// /g;
      $$data{get} =~ s/^\s+|\s+$//g;
      $$data{get} = "default" if($$data{get} =~ /^\s*$/);

      if($$data{get} eq undef) {
         http_error($s,"Malformed Request");
      } else {
         my $id = conf("webuser");
         my $self = obj(conf("webuser"));

         # run the $default mush command as the default webpage.

         my $addr = @{@http{$s}}{hostname};
         $addr = @{@http{$s}}{ip} if($addr =~ /^\s*$/);
         $addr = $s->peerhost if($addr =~ /^\s*$/);
         return http_error($s,"Malformed Request or IP") if($addr =~ /^\s*$/);
         @http{$s}->{ip} = $addr;

         @info{httpd_ban} = {} if(!defined @info{httpd_ban});
         # html/js/css should be a static file, so just return the file

         if($$data{get} eq "unban") {
            delete @{@info{httpd_ban}}{$addr};
            delete @info{httpd_invalid_data}->{$addr};
            http_reply_simple($s,"html","%s","$addr has been unbanned.");
         } elsif(banable_urls($data)) {
            ban_add($s);
            web("   %s %s\@web [BANNED-%s]\n",ts(),$addr,$$data{get});
            http_error($s,"%s","BANNED for HACKING");
         } elsif(defined @{@info{httpd_ban}}{$addr}) {
            web("   %s %s\@web [BANNED-%s]\n",ts(),$addr,$$data{get});
            http_error($s,"%s","BANNED for invalid requests");
         } elsif(($$data{get} =~ /_notemplate\.(html)$/i ||  # no template used
            $$data{get} =~ /\.(js|css|ico)$/i) &&
            -e "txt/" . trim($$data{get})) {
            web("   %s %s\@web [%s]\n",ts(),$addr,$$data{get});
            http_reply_simple($s,$1,"%s",getfile(trim($$data{get})));
         } elsif($$data{get} !~ /[\\\/]/ &&
                 $$data{get} ne ".." &&
                 $$data{get} =~ /\.([^.]+)$/ &&
                 -e "txt/" . trim($$data{get})) {
            web("   %s %s\@web [%s]\n",ts(),$addr,$$data{get});
            http_reply_simple($s,$1,"%s",getbinfile(trim($$data{get})));
         } elsif($$data{get} =~ /\.html$/i && -e "txt/" . trim($$data{get})) {
            my $prog = prog($self,$self);                    # uses template
            $$prog{sock} = $s;
            web("   %s %s\@web [%s]\n",ts(),$addr,$$data{get});
            http_reply($prog,getfile(trim($$data{get})));
         } elsif($$data{get} =~ /^pid$/) {
            web(" * %s %s\@web [%s]\n",ts(),$addr,$$data{get});
            if($addr eq "localhost" || $addr eq "127.0.0.1") {
               if(@info{cwd} != -1) {
                  http_reply_simple($s,$1,"%s",$$.",".getcwd());
               } else {
                  http_reply_simple($s,$1,"%s","$$,%s");
               }
            } else {
               http_error($s,"%s","pid request from bad location. '$addr'");
            }
         } elsif($$data{get} =~ /^imc /) {
            delete @info{sigusr1};
            web(" * %s %s\@web [%s]\n",ts(),$addr,$$data{get});
            if($addr eq "localhost" || $addr eq "127.0.0.1") {
               @info{imc}={ timestamp => time(), command => substr($',0,1024) };
               my $god = obj(0);
               my $prog = mushrun(self   => $god,
                                  runas  => $god,
                                  invoker=> $god,
                                  source => 0,
                                  cmd    => "\@imc",
                                  hint   => "IMC",
                                  sock   => $s,
                                  output => [],
                                  nosplit => 1,
                                 );
                $$prog{get} = $$data{get};
                $$prog{head} = $$data{head} if defined $$data{head};
                @{$$prog{var}}{get}=$$data{get};
                for my $item (keys %$data) {    # make header data availible
                   @{$$prog{var}}{$'}=$$data{$item} if($item =~ /^VAR_/);
                }
            } else {
               http_error($s,"%s","imc request from bad location.");
            }
         } else {                                          # mush command
            web("   %s %s\@web [%s]\n",ts(),$addr,$$data{get});
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
             $$prog{get} = $$data{get};
             $$prog{head} = $$data{head} if defined $$data{head};
             $$self{hostname} = $addr;
             @{$$prog{var}}{get}=$$data{get};
             for my $item (keys %$data) {    # make header data availible
                @{$$prog{var}}{$'}=$$data{$item} if($item =~ /^VAR_/);
             }
         }
      }
   } else {
      printf("---BAD REQUEST---\n");
      http_error($s,"Malformed Request");
   }
}

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
# load_db
#
sub load_db
{
   my ($dir, $file, %state);

   if(!-d "dumps") {
     mkdir("dumps") || die("Unable to create directory 'dumps'.");
   }

   opendir($dir,"dumps") || die("Unable to find dumps directory");

   my $fn =(sort {(stat("dumps/$a"))[9] <=> (stat("dumps/$b"))[9]}
             grep {/\.tdb$/}                         # find most current db
             readdir($dir))[-1];

   closedir($dir);

   if($fn eq undef) {
      printf("\nNo database found, loading starter database.\n\n");
      printf("Connect as: god potrzebie\n\n");
      my $obj = {obj_id => 0};
      my $prog = prog($obj,$obj,$obj);
      cmd_pcreate($obj,$prog,"god potrzebie",{},1);             # create god
      set_flag($obj,$prog,$obj,"GOD",,1);                  # set god wizard

      create_object($obj,$prog,"The Void",undef,"ROOM",1);
      set($obj,$prog,$obj,"CONF.STARTING_ROOM","#1");   # set starting room
      teleport($obj,$prog,$obj,1);             # teleport god into the void

      cmd_pcreate($obj,$prog,"webuser potrzebie",{},1);        # create webuser
      cmd_give(3,$prog,"#0 = 9999999");             # give webobject money
      teleport(3,$prog,$obj,1);             # teleport god into the void
      set($obj,$prog,$obj,"CONF.WEBUSER","#2");         # set webuser object
      create_object(obj(2),$prog,"WebSecurityObject",undef,"OBJECT",1);
      set($obj,$prog,$obj,"CONF.WEBOBJECT","#3");        # set webuser object
      set_flag($obj,$prog,3,"!NO_COMMAND",,1);       # remove NO_COMMAND
      set($obj,$prog,3,"DEFAULT",
         "\$default:\@pemit %#=This is the minimal default web page for " .
         "[version()]. Please update this with: &default #3=Your web page");

      return;
   }

   if(!dump_complete("dumps/$fn")) {
      die("$fn is incomplete, remove or use --forceload to override");
   }

   open($file,"< dumps/$fn") ||
      die("Unable to open database 'dumps/$fn'\n");

   @info{dump_name} = $` if($fn =~ /\.tdb$/);

   while(<$file>) {
      db_process_line(\%state,$_);
   }
   close($file);

   printf(" + Database: %s [%s Version, %s bytes]\n",
      $fn,@state{ver},@state{chars});

   recover_db();

   delete @info{dirty};     # delete, this will get populated by the db load
}

sub recover_db
{
   while(-e sprintf("dumps/@info{dump_name}.%06d",@info{change}+1)) {
      @info{change}++;
      load_archive_log(sprintf("@info{dump_name}.%06d",@info{change}));
   }

   if(@info{change} == 1) {
      printf(" +           DB Sequence 1 loaded.\n");
   } elsif(@info{change} > 1) {
      printf(" +           DB Sequences 1 .. @info{change} loaded.\n");
   }
}

#
# load_archive_log
#    Load the archive log files which contain just the changes since
#    the last full dump.
#
sub load_archive_log
{
   my $fn = shift;
   my %state;
   my $file;

   if(!dump_complete("dumps/$fn")) {
      die("$fn is incomplete, remove or use --forceload to override");
   }

   open($file,"< dumps/$fn") ||
      die("Unable to open database 'dumps/$fn'\n");

   while(<$file>) {
      s/\r|\n//g;
      if($_ =~ /^(\d+),([^,]+),{0,1}/) {
         @state{obj} = $1;
         my $type = $2;
         my $rest = $';

         if($type eq "delatr") {
            my $obj = @db[@state{obj}];
            delete @$obj{$rest};
         } elsif($type eq "delobj") {
            delete @db[@state{obj}];
         } else {
            db_process_line(\%state,$rest);
         }
      }
   }
   close($file);
}

sub generic_action
{
   my ($self,$prog,$target,$action,$target_msg,$src_msg) = @_;

#   if((my $atr = get($target,$action)) ne undef) {
#         necho(self => $self,
#               prog => $prog,
#               room => [ $self,
#                         "%s %s", 
#                         name($self),
#                         evaluate($self,$prog,$atr)
#                       ],
#         );
#   }

   run_attr($self,$prog,$target,"A$action");           # handle @aACTION

# actions off the web shouldn't trigger any messages outside of
# maybe actions.
   return if(defined $$prog{hint} && $$prog{hint} eq "WEB");

   my ($sfmt,@sargs) = @$src_msg;
   my $msg = sprintf($sfmt,@sargs);               # handle msg to enactor

   if($msg !~ /^\s*$/) {
      necho(self =>   $self,
            prog =>   $prog,
            source => [ "%s", evaluate($self,$prog,$msg) ],
           );
   }

   my $atr = get($target,"o$action");

   if($atr ne undef) {                                # standard message
      necho(self =>   $self,
            prog =>   $prog,
            room =>   [ $self,
                        "%s %s",
                        name($self),
                        evaluate($self,$prog,$atr)
                      ],
      );
   } else {                                            # oACTION message
      my ($tfmt,@targs) = @$target_msg;
      my $msg = sprintf($tfmt,@targs);
      if($msg !~ /^\s*$/) {
         necho(self   =>   $self,
               prog   =>   $prog,
               room   => [ $self, "%s %s", name($self), $msg ],
              );
      }
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
      $amount = conf("$what");
   } else {
      $amount = $what;
   }

   if($amount == 1) {
      return $amount . " " . conf("money_name_singular");
   } else {
      return $amount . " " . conf("money_name_plural");
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


#
# gender
#    Handle gender pronouns. Peek at the currently running $prog
#    to determine the gender of the thing invoking the command.
#    Then use the $male, $female, or $it version that is passed
#    in based upon that gender.
#
sub gender
{
   my ($prog,$case,$male,$female,$it,$other) = @_;
   my ($atr, $result);

   $result = $it;                                         # default to it
   if(defined $$prog{cmd} && defined $$prog{cmd}->{invoker}) {
      $atr = get($$prog{cmd}->{invoker},"sex");

      if($atr =~ /(female|girl|woman|lady|dame|chick|gal|bimbo|ms|mrs|miss)/i) {
         $result = $female;
      } elsif($atr =~ /(male|boy|garson|gent|father|mr|man|sir|son|brother)/i) {
         $result = $male;
      } elsif($atr =~ /(plural|enby|fluid|mx)/i) {
         $result = $other
      }
   }

   # does the result need to be first character uppercased?
   return ($case =~ /[A-Z]/) ? ucfirst($result) : $result;
}

#
# evaluate
#    Take a string and evaluate any functions, and mush variables
#
sub evaluate_substitutions
{
   my ($self,$prog,$t) = (obj(shift),shift,shift);
   my ($out,$seq,$debug);

   my $orig = $t;
   while($t =~ /(\\|%m[0-9]|%q[0-9a-z]|%i[0-9]|%[!psaobrtnk#0-9%]|%(v|w)[a-zA-Z]|%=<[^>]+>|%\{[^}]+\}|##|#@)/i) {
      ($seq,$t)=($1,$');                                   # store variables
      $out .= $`;
      if($seq eq "\\") {                               # skip over next char
         $out .= ansi_substr($t,0,1);
         $t = ansi_substr($t,1,ansi_length($t));
      } elsif($seq eq "%%") {
         $out .= "\%";
      } elsif($seq eq "##") {
         if(!defined $$prog{iter_stack} || $#{$$prog{iter_stack}} == -1 ) {
            $out .= "##";
         } else {
            $out .= @{@{$$prog{iter_stack}}[-1]}{val};
         }
      } elsif($seq eq "#@") {
         if(!defined $$prog{iter_stack} || $#{$$prog{iter_stack}} == -1 ) {
            $out .= "#@";
         } else {
            $out .= @{@{$$prog{iter_stack}}[-1]}{pos};
         }
      } elsif($seq eq "[") { # remove this later?
         $out .= "[" if(ord(substr($`,-1)) == 27);       # escape sequence?
#      } elsif($seq eq "]") {                           # removed for compat
#         printf("FOUND: ']'\n");
#         # ignore
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
         $out .= gender($prog,$seq,"his","her","its","their");
      } elsif(lc($seq) eq "%s") {
         $out .= gender($prog,$seq,"he","she","it","they");
      } elsif(lc($seq) eq "%o") {
         $out .= gender($prog,$seq,"him","her","it","them");
      } elsif(lc($seq) eq "%a") {
         $out .= gender($prog,$seq,"his","hers","its","theirs");
      } elsif($seq eq "%#") {                                # current dbref
         if(defined $$prog{cmd} && defined @{$$prog{cmd}}{invoker}) {
            if(ref($$prog{cmd}->{invoker}) eq "HASH") {
               $out .= "#" . $$prog{cmd}->{invoker}->{obj_id};
            } else {
               $out .= "#" . $$prog{cmd}->{invoker};
            }
         } else {
            $out .= "#" . $$self{obj_id};
         }
      } elsif(lc($seq) eq "%n" || lc($seq) eq "%k") {         # current name
         if(!defined $$prog{cmd}) {
            $out .= name($self,undef,$self,$prog);
         } else {
            $out .= name($$prog{cmd}->{invoker},undef,$self,$prog);
         }
      } elsif($seq =~ /^%q([0-9a-z])$/i) {
         if(defined $$prog{var}) {
            $out .= @{$$prog{var}}{"setq_$1"} if(defined $$prog{var});
         }
      } elsif($seq =~ /^%m([0-9])$/ ||
              $seq =~ /^%\{m([0-9])\}$/) {
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
         } elsif($1 eq "##") {
            if(defined $$prog{iter_stack} && $#{$$prog{iter_stack}} != -1 ) {
               my $var = @{@{$$prog{iter_stack}}[-1]}{val};
               $out .= @{$$prog{var}}{$var} if(defined $$prog{var});
            }
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
# controls
#    Does the $enactor control the $target?
#
sub controls
{
   my ($enactor,$target,$flag) = (obj(shift),obj(shift),shift);

   if(hasflag($enactor,"GOD")) {                   # gods control everything
      return 1;
   } elsif(hasflag($target,"GOD") && !hasflag($enactor,"GOD")) {
      return 0;                        # nothing can modify a god, but a god
   } elsif(hasflag($enactor,"WIZARD")) {
      return 1;                    # wizards can modify everything but a god
   } elsif(owner_id($enactor) == owner_id($target)) {
      return 1;                              # you can modify your own stuff
   } else {
      return 0;
   }
}

#
# controls
#    Does the $enactor control the $target?
#
sub readonly
{
   my ($enactor,$target,$flag) = (obj(shift),obj(shift),shift);

   if(hasflag($enactor,"GOD")) {                   # gods control everything
      return 1;
   } elsif(owner($target) == 0) {
      return 0;
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

   my $parent = get($target,"obj_parent");

   return if handle_socket_listener($target,$target,$txt,@args);

   if($parent ne undef) {                             # handle parent
      $parent = obj($parent);

      if(valid_dbref($parent)) {
         return if handle_socket_listener($parent,$target,$txt,@args);
      }
   }
}

sub handle_socket_listener
{
   my ($src,$target,$txt,@args) = @_;
   my $msg = ansi_remove(sprintf($txt,@args));

   $msg =~ s/(%|\\)/\\$1/g;

   for my $hash (sort {length(@{$b}{atr_regexp}) <=>
                       length(@{$a}{atr_regexp})} latr_regexp($src,3)) {
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
         return 1;
      }
   }
   return 0;
}

sub handle_directed_listen
{
   my ($self,$prog,$target,$msg) = (obj(shift),shift,obj(shift),shift);

   if($$target{obj_id} == $$self{obj_id} ||
      !hasflag($target,"LISTENER")) {
      return;
   }

   for my $hash (sort {length(@{$b}{atr_regexp}) <=>
                       length(@{$a}{atr_regexp})} latr_regexp($target,2)) {
#   for my $hash (latr_regexp($target,2)) {
      if(atr_case($target,$$hash{atr_name})) {
         $$hash{atr_regexp} =~ s/^\(\?msix/\(\?msx/; # make case sensitive
         if($msg =~ /$$hash{atr_regexp}/) {
            mushrun(self   => $self,
                    runas  => $target,
                    cmd    => single_line($$hash{atr_value}),
                    wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                    source => 0,
                    attr   => $hash,
                    invoker=> $self,
                    from   => "ATTR",
                    ppid   => $$prog{pid}
                   );
            return;
         }
      } elsif($msg =~ /$$hash{atr_regexp}/i) {
         mushrun(self   => $self,
                 runas  => $target,
                 invoker=> $self,
                 cmd    => single_line($$hash{atr_value}),
                 wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                 source => 0,
                 attr   => $hash,
                 from   => "ATTR",
                 ppid   => $$prog{pid}
                );
            return;
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

      for my $hash (sort {length(@{$b}{atr_regexp}) <=>
                          length(@{$a}{atr_regexp})} latr_regexp($obj,2)) {
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
            return 1;
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
            return 1;
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
   my ($msg,$fd,$fn);

   # add newline if needed except when the fmt starts with a escape code
   $fmt .= "\n" if(substr($fmt,0,1) ne chr(27) && $fmt !~ /\n$/);

   $fd = @info{"$type.fd"} if defined @info{"$type\.fd"};   # get existing fd

   # do not log requests
   return if(conf("$type") =~ /^\s*nolog\s*$/i);

#   printf("$fmt", @args);
   # open log as needed if not using console

   if($type eq "weblog") {
      $fn = "teenymush.web.log";
   } elsif($type eq "auditlog") {
      $fn = "teenymush.audit.log";
   } else {
      $fn = "teenymush.log";
   }

   if(conf($type) !~ /^\s*console\s*$/i  &&
      (!-e $fn || !defined @info{"$type\.fd"})) {
      if(open($fd,">> $fn")) {
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
   printf($fd "%s", ansi_remove($txt)) if($fd ne undef);
}

sub web
{
   logit("weblog",@_) if(conf_true("weblog"));
}

sub con
{
   logit("conlog",@_) if(conf_true("conlog"));
}

sub audit
{
   my ($self,$prog,$fmt,@args) = @_;
   return if(!conf_true("auditlog"));

   my $info = sprintf("[%s] $fmt by " . obj_name($self,$self),ts(),@args);

   # add actual command issued
   if(defined $$prog{created_by} &&
      defined $$prog{created_by}->{last} &&
      defined $$prog{created_by}->{last}->{cmd}) {
      $info .= ", cmd: '" . $$prog{created_by}->{last}->{cmd} . "'";
   } elsif(defined $$prog{user} &&
      defined $$prog{user}->{last} &&
      defined $$prog{user}->{last}->{cmd}) {
      $info .= ", cmd: '" . $$prog{user}->{last}->{cmd} . "'";
   }

   # add hostname / ip information
   if(defined $$prog{created_by} &&
      defined $$prog{created_by}->{hostname}) {
      $info .= ", Host: " . $$prog{created_by}->{hostname};
   } elsif(defined $$prog{created_by} &&
      defined $$prog{created_by}->{ip}) {
      $info .= ", Host: " . $$prog{created_by}->{ip};
   } elsif(defined $$prog{user} &&
      defined $$prog{user}->{hostname}) {
      $info .= ", Host: '" . $$prog{user}->{hostname};
   } elsif(defined $$prog{user} &&
      defined $$prog{user}->{ip}) {
      $info .= ", Host: '" . $$prog{user}->{ip};
   }

   logit("auditlog","%s",$info);
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
   my $self = obj($arg{self});
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

   if(defined $arg{"source"}) {
         unshift(@{$arg{source}},$self);
#      if(defined $$prog{created_by}) {
#         unshift(@{$arg{source}},$$prog{created_by});
#      } else {
#         unshift(@{$arg{source}},$self);
#      }
   }

   for my $type ("source", "target") {
      next if !defined $arg{$type};

      if(ref($arg{$type}) ne "ARRAY") {
         return err($self,$prog,"Argument $type is not an array");
      }


      my ($target,$fmt) = (obj(shift(@{$arg{$type}})), shift(@{$arg{$type}}));
      my $msg = filter_chars(sprintf($fmt,@{$arg{$type}}));

      handle_directed_listen($self,$prog,$target,$msg);

      # output needs to be saved for use by http, websocket, or run()
       if(defined $$prog{output}) {
          my $stack = $$prog{output};

          if(@{obj($$prog{created_by})}{obj_id} == $$target{obj_id} ||
             (defined $$prog{capture} &&
                 $$target{obj_id} == @{@{$$prog{capture}}{self}}{obj_id}) ||
             @{obj($$prog{created_by})}{obj_id} == loc($target)) {
             if(defined $$prog{capture}) {
                my $h = $$prog{capture};
                if($$h{type} eq "all" ||
                   ($$h{type} eq "pemit" &&
                    defined $$prog{cmd} &&
                    defined @{$$prog{cmd}}{cmd} &&
                    lc(@{$$prog{cmd}}{mushcmd}) eq "\@pemit"
                   )
                  ) {
                   push(@$stack,$msg);
                   @$stack[$#$stack] =~ s/\n+$//;
#                   printf("ADD: '%s' - '%s'\n",$msg,$#{$$prog{output}});
                   next;
                } else {
#                   printf("CMD: '%s'\n",lc(@{$$prog{cmd}}{mushcmd}));
#                   printf("SKIP1: '%s'\n",$msg);
                }
             } else {
                push(@$stack,$msg);
                next;
             }
          } else {
#             printf("WHO: '%s' -> '%s' -> '%s'\n",
#                 @{$$prog{created_by}}{obj_id},
#                 $$target{obj_id},
#                 $$self{obj_id});
#             printf("%s\n",print_var($prog));
#             printf("SKIP2: '%s'\n",$msg);
          }
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

         echo_socket($$target{obj_id},
                     @arg{prog},
                     "%s%s",
                     nospoof(@arg{self},@arg{prog},$$target{obj_id}),
                     $msg
                    );
      }
   }
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
   } else {
      return 0;
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
      return "I don't understand that flag. " . code();
   }

   if($flag =~ /^\s*!\s*/) {
      $remove = 1;
      $flag = trim($');
   }

   if(!$override && !can_set_flag($self,$obj,$flag)) {
      return "Permission DeNied";
   } elsif($remove) {                  # remove, don't check if set or not
      if(($flag eq "WIZARD" || $flag eq "GOD") && hasflag($obj,$flag)) {
         audit($self,$prog,"%s set !%s",obj_name($obj,$obj),$flag);
      }
      db_remove_list($obj,"obj_flag",$flag);       # to mimic original mush
      return "Cleared.";
   } else {
      if(($flag eq "WIZARD" || $flag eq "GOD") && !hasflag($obj,$flag)) {
         audit($self,$prog,"%s set %s",obj_name($obj,$obj),$flag);
      }
      db_set_list($obj,"obj_flag",$flag);
      return "Set.";
   }
}

#
# set_atr_flag
#   Add a flag to an object. Verify that the object does not already have
#   the flag first.
#
sub set_atr_flag
{
   my ($object,$atr,$flag,$override,$switch) =
      (obj(shift),shift,shift,shift,shift);
   my $who = $$user{obj_name};
   my ($remove,$count);
   $flag = uc(trim($flag));

   $atr = "obj_$atr" if reserved($atr);
   if($flag =~ /^\s*!\s*(.+?)\s*$/) {
      ($remove,$flag) = (1,$1);
   }
   if(!$override && !can_set_flag($object,$object,$flag)) {
      return "#-1 Permission Denied.";
   } elsif(!db_attr_exist($object,$atr)) {
      return "#-1 UNKNOWN ATTRIBUTE ($atr).";
   } else {
      db_set_flag($$object{obj_id},$atr,lc($flag),$remove ? undef : 1);
      return "Set." if(!defined $$switch{quiet});
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
   my $owner = owner($target);

   for my $exit (lexits($target)) {                   # destroy all exits
      if(valid_dbref($exit)) {
         give_money($owner,money($exit,1));                # refund money
         set_quota($owner,"add");                          # refund quota
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
   give_money($owner,money($target,1));                        # refund money
   set_quota($owner,"add");                                    # refund quota
   db_delete($target);
   return 1;
}

sub create_object
{
   my ($self,$prog,$name,$pass,$type,$flag) = @_;
   my ($where,$id);
   my $who = $$user{obj_name};
   my $owner = $$user{obj_id};

   # check quota

   if(!$flag && !or_flag($self,"WIZARD","GOD") &&
      $type ne "PLAYER" && quota($owner,"left") <= 0) {
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
      printf("abort: couldn't set flag?\n");
      return undef;
   }

   if($type eq "PLAYER") {
      db_set($id,"obj_lock_default","#" . $id);
      db_set($id,"obj_home",$where);
      db_set($id,"obj_money",conf("starting_money"));
      db_set($id,"obj_firstsite",$where);
      db_set($id,"obj_quota",nvl(conf("starting_quota"),0) . ",0");
      @player{trim(ansi_remove(lc($name)))} = $id;
   } else {
      db_set($id,"obj_home",$$self{obj_id});
   }

   db_set($id,"obj_owner",$$self{obj_id});
   db_set($id,"obj_created_date",scalar localtime());

   # #0 was just created, don't move it around
   if($id != 0 && ($type eq "PLAYER" || $type eq "OBJECT")) {
      teleport($self,$prog,$id,$where);
   }
   return $id;
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
   }

   return defined @player{trim(ansi_remove(lc($name)))} ? 1 : 0;
}

#
# give_money
#    Give money to a person. Objects can't have money, so its given to
#    the object's owner.
#
sub give_money
{
   my ($target,$amount,$flag) = (obj(shift),shift,shift);

   $target = owner($target) if(!$flag);

   # $money doesn't contain a number
   return 0 if($amount !~ /^\s*\-{0,1}(\d+)\s*$/);

   if($flag) {
      db_set($target,"obj_money",$amount);
   } else {
      my $money = money($target);
      db_set($target,"obj_money",$money + $amount);
   }

   return 1;
}

#
# set_used_quota
#    Update how much quota has been used by $obj
#

sub good_atr_name
{
   my ($attr,$flag) = @_;

   if(reserved($attr) && !$flag) {                     # don't set that!
      return 0;
   } elsif($attr =~ /^\s*([#a-z0-9\_\-\.\/]+)\s*$/i) {
      return 1;
   } else {
      return 0;
   }
}

sub set
{
   my ($self,$prog,$obj,$attribute,$value,$quiet,$override)=
      (obj($_[0]),$_[1],obj($_[2]),lc($_[3]),$_[4],$_[5]);
   my ($pat,$first,$type);

   # don't strip leading spaces on multi line attributes
   $value =~ s/^\s+//g if(!defined $$prog{multi});

   if(!good_atr_name($attribute),$override) {
      err($self,$prog,"Attribute name is bad, use the following characters: " .
           "A-Z, 0-9, and _ : $attribute");
   } elsif($value =~ /^\s*$/) {                           # delete attribute
      db_set($obj,$attribute,undef);
      if(!$quiet) {
          necho(self => $self,
                prog => $prog,
                source => [ "Set." ]
            );
      }
   } else {                                                  # set attribute
      db_set($obj,$attribute,$value);
      if(!$quiet) {
          necho(self => $self,
                prog => $prog,
                source => [ "Set." ]
               );
      }
   }
}

sub subget
{
   my ($attr,$debug) = @_;

   if(ref($attr) eq "HASH") {
      if(defined $$attr{regexp}) {
        return "$$attr{type}$$attr{glob}:$$attr{value}";
      } else {
        return $$attr{value};
      }
   }
}

#
# pget
#   A get with a fall back to the parent
#
sub pget
{
   my ($obj,$attribute,$flag) = @_;

   my $attr = mget($obj,$attribute);                           # check object
   return $attr if(ref($attr) eq "HASH" && $flag);
   return subget($attr) if(ref($attr) eq "HASH");

   my $parent = mget($obj,"obj_parent");                     # look up parent
   return undef if(ref($parent) ne "HASH" || !valid_dbref($$parent{value}));

   return mget($$parent{value},$attribute) if $flag;  # get attr from parent
   return subget(mget($$parent{value},$attribute));   # get attr from parent
}

#
# conf
#    Grab a configuration option from off of "#0/conf.name" or the @default
#    variable. Also strip any "#" from dbrefs.
#
sub conf
{
   my $attr;

   @info{conf} = {} if !defined @info{conf};
   @info{conf}->{$_[0]} = 1;              # auto store used config options

   if($_[0] eq "version") {
      return version();
   } elsif(hasattr(obj(0),"conf.$_[0]")) {
      $attr = get(obj(0),"conf." . $_[0]);
   } elsif(defined @default{lc($_[0])}) {             # use @defaults?
      $attr = @default{lc($_[0])};
   } else {
      return undef;
   }

   if($attr =~ /^\s*#(\d+)\s*$/) {         # return just the number of a dbref
      return $1;
   } else {
      return $attr;
   }
}

sub conf_true
{
   return is_true(conf($_[0]));
}

sub get
{
   my ($obj,$attribute,$flag) = (obj($_[0]),$_[1],$_[2]);
   my $hash;

   $attribute = "description" if(lc($attribute) eq "desc");

   my $attr = subget(mget($obj,$attribute,$flag),$flag);
   return $attr;
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

sub obj_name
{
   my ($self,$obj,$flag,$noansi) = (obj(shift),shift,shift,shift);

   if($obj eq undef) {                   # assume full name if not qualified
      $obj = $self;
   } else {
      $obj = obj($obj);                                     # convert to obj
   }


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

   if($loc ne undef) {
      db_set($loc,"OBJ_LAST_INHABITED",scalar localtime());
      db_remove_list($loc,"obj_content",$$target{obj_id});
   }
   db_set($target,"OBJ_LAST_INHABITED",scalar localtime());
   db_set($target,"obj_location",$$dest{obj_id});
   db_set_list($dest,"obj_content",$$target{obj_id});
   return 1;
}

sub obj
{
   my $id = shift;

   if(ref($id) eq "HASH") {
      return $id;
   } else {
      if($id !~ /^\s*\d+\s*$/) {
         con("ID: '%s' -> '%s'\n",$id,code());
         croak();
      }
      return { obj_id => $id };
   }
}

sub obj_nocheck
{
   my $id = shift;

   if(ref($id) eq "HASH") {
      return $id;
   } else {
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

   db_set($obj,"obj_home",$$dest{obj_id});
   return 1;
}

sub link_exit
{
   my ($self,$exit,$src,$dst) = obj_import(@_);

   if($src ne undef && defined $$src{obj_id}) {
      db_set_list($$src{obj_id},"obj_exits",$$exit{obj_id});
      db_set($$exit{obj_id},"obj_location",$$src{obj_id});
   }

   if($dst ne undef && defined $$exit{obj_id}) {
      db_set($$exit{obj_id},"obj_destination",$$dst{obj_id});
   }
   return 1;
}

sub lastsite
{
   my $target = obj(shift);

   my $attr = mget($target,"obj_lastsite");

   if($attr eq undef) {
      return undef;
   } else {
      my $list = $$attr{value};
      my $last = (sort {$a <=> $b} keys %$list)[-1];
#      printf("%s\n",print_var($$attr{value}));

#      for my $key (keys %$list) {
#         if($$list{$key} =~ /^(\d+),/) {
#            printf("diff: '%s' - '%s' = '%s'\n",$1,$key,$1 - $key);
#         }
#      }

      if($$list{$last} =~ /^\d+,\d+,(.*)$/) {
         return $1;
      } else {
         delete @$list{$last};
         return undef;
      }
   }
}

sub lasttime
{
   my ($target,$flag) = (obj(shift),shift);

   if(!hasflag($target,"PLAYER")) {
      return undef;
   } else {
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
   }
}

sub firstsite
{
   my $target = obj(shift);

   if(!hasflag($target,"PLAYER")) {
      return undef;
   }

   return get($target,"obj_created_by");
}

sub firsttime
{
   my $target = obj(shift);

   return scalar localtime(fuzzy(get($target,"obj_created_date")));
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
#         printf("Skipped: $word\n");
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

sub isatrflag
{
   my $txt = shift;
   $txt = $' if($txt =~ /^\s*!/);

   return flag_attr(trim($txt));
}

sub is_flag
{
   my $flag = shift;

   $flag = trim($') if($flag =~ /^\s*!/);

   return (flag_letter($flag) eq undef) ? 0 : 1;
}

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

   $$sock{site_restriction} = 4;
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
      printf("FIND($cmd): '%s'\n",find_exit($self,{},conf("master"),$cmd));
      if($match ne undef && lc($cmd) ne "q") {                # found match
         return ($match,trim($txt));
      } elsif($$user{site_restriction} == 69) {
         return ('huh',trim($txt));
      } elsif($txt =~ /^\s*$/ && $type && find_exit($self,{},loc($self),$cmd)){
         return ("go",$cmd);                                            # exit
      } elsif($txt =~ /^\s*$/ && $type &&
         find_exit($self,{},conf("master"),$cmd)){          # master room exit
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
         $1 >= 500) {
         push(@$stack,"#-1 PAgE LOAD FAILURE");
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
      $input =~ s/\r//mg;
      handle_object_listener($data,"%s",$input);
   } elsif(defined $$data{raw} && $$data{raw} == 2) {
      $input =~ s/\r//mg;
     add_telnet_data($data,$input);
   } else {
#      eval {                                                  # catch errors
         local $SIG{__DIE__} = sub {
            con("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            con("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            con("%s",code("long"));
         };

         if($input =~ /^\s*([^ ]+)/ || $input =~ /^\s*$/) {
            $user = $hash;
            if(loggedin($hash) ||
                    (defined $$hash{obj_id} && hasflag($hash,"OBJECT"))) {
               add_last_info($input);                                   #logit
               return mushrun(self   => $user,
                              runas  => $user,
                              invoker=> $user,
                              source => 1,
                              cmd    => $input,
                             );
            } else {
               if(conf("show_offline_cmd")) {
                  con("[%s:%s] %s <Offline>\n",ts(),$$hash{hostname},$input);
               }
               my ($cmd,$arg) = lookup_command($data,\%offline,$1,$',0);
               &{@offline{$cmd}}($hash,prog($user,$user),$arg);  # invoke cmd
            }
         }
#      };

      if($@) {                                # oops., you sunk my battle ship

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
   if(!defined @info{server_start} || @info{server_start} =~ /^\s*$/) {
      @info{server_start} = time();
   }
   eval {
         local $SIG{__DIE__} = sub {
            con("----- [ Crash Report@ %s ]-----\n",scalar localtime());
            printf("User:     %s\nCmd:      %s\n",name($user),$_[0]);
            con("%s",code("long"));
         };

      # wait for IO or 1 second
      my ($sockets) = IO::Select->select($readable,undef,undef,.1);
      my $buf;

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


               my $ignore = get(0,"conf.host_filter");
               if($ignore eq undef ||
                  !inlist($$hash{hostname},split(/,/,$ignore))) {
                  con("# Connect from: %s [%s]\n",$$hash{hostname},ts());
               }
               if($$hash{site_restriction} <= 2) {                  # banned
                  con("   BANNED   [Booted]\n");
                  if($$hash{site_restriction} == 2) {
                     printf($new "%s",conf("badsite"));
                  }
                  server_disconnect(@{@connected{$new}}{sock});
               } elsif(!defined conf("login")) {
                  printf($new "Welcome to %s\r\n\r\n",conf("version"));
               } else {
                  my $obj = obj(0);            #  show login in readonly mode
                  my $prog = prog($obj,$obj,$obj);
                  $$prog{read_only} = 1;
                  printf($new "%s\r\n",evaluate($obj,$prog,conf("login")));
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


#               # store last transaction in @info{connected_raw_socket}
#               if(defined @connected{$s} && @{@connected{$s}}{raw} > 0) {
#                  if(@info{connected_raw_socket} ne $s) {
#                     delete @info{connected_raw};
#                     @info{connected_raw_socket} = $s;
#                  }
#                  @info{connected_raw} .= $` . "\n";
#               }

#               if(!defined @connected{$s}) {
#                  printf("## no socket??? '$s'\n");
#               } elsif(@{@connected{$s}}{raw} > 0) {
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
      con("Server Crashed, minimal details [main_loop]\n");

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

   calculate_login_stats();

   # notify connected users of disconnect
   if(defined @connected{$id}) {
      my $hash = @connected{$id};

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
      } elsif(defined $$hash{connect_time}) {                # Player Socket

         my $key = connected_user($hash);

         if(defined @connected_user{$$hash{obj_id}}) {
            delete @{@connected_user{$$hash{obj_id}}}{$key};
            if(scalar keys %{@connected_user{$$hash{obj_id}}} == 0) {
               delete @connected_user{$$hash{obj_id}};
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
   my @port;
   my @tried;

   # my dev instant just needs a free port, so choose from a list
   for my $p (split(/,/,conf("port"))) {
      $listener = IO::Socket::INET->new(LocalPort => $p,
                                        Listen    => 1,
                                        Reuse     => 1
                                       );
      if($listener ne undef) {
         push(@port,"$p\{Mush\}");
         last;
      } else {
         push(@tried,$p);
      }
   }
   die("Ports " . join(',',@tried) . " already in use.") if $listener eq undef;

   # uri_escape is required for httpd
   if(@info{"uri_escape"} == -1 && conf("httpd") > 0) {
      con("httpd disabled because of missing URI::Escape module");
   } elsif(@info{"uri_escape"} == 1 && conf("httpd") > 0) {
      if(conf("httpd") =~ /^\s*(\d+)\s*$/) {
         push(@port,conf("httpd") . "{httpd}");

         $web = IO::Socket::INET->new(LocalPort => conf("httpd"),
                                      Listen    =>1,
                                      Reuse     =>1
                                     );
      } else {
         con("Invalid httpd port number specified in #0/conf.httpd");
      }
   }

   if(conf("websocket") ne undef && conf("websocket") > 0) {
      if(conf("websocket") =~ /^\s*(\d+)\s*$/) {
         push(@port,conf("websocket") . "{websocket}");
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

   if(conf("httpd") ne undef) {
      $ws->{select_readable}->add($web);
   }
   $readable = $ws->{select_readable};
   printf(" + Listening on ports: %s\n",join(',',@port));

   # main loop;
   @info{run} = 1;

   run_attr(0,{},0,"conf.startup");

   if(!conf("safemode")) {
      for my $obj (lcon(conf("master"))) {             # handle astartup
         my $atr;
         if(hasflag($obj,"WIZARD") &&
            ($atr = get($obj,"ASTARTUP")) &&
            $atr ne undef) {
            mushrun(self    => $obj,
                    runas   => $obj,
                    invoker => $obj,
                    source  => 0,
                    cmd     => $atr
                   );
         }
      }
   }

   while(@info{run}) {
      eval {
         server_handle_sockets();
      };
      if($@){
         con("Server Crashed, minimal details [main_loop]\n");
         con("%s\n---[end]-------\n",$@);
      }
   }
}


sub websock_init
{
   $websock = IO::Socket::INET->new( Listen    => 5,
                                     LocalPort => conf("websocket"),
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

   ws_echo($conn->{socket}, conf("login"));
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
      web("   %s %s\@ws [%s]\n",ts(),@{$ws->{conns}{$conn->{socket}}}{ip},$');
      @{$ws->{conns}{$conn->{socket}}}{type} = "NON_INTERACTIVE";
      my $self = conf("webuser");

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
      web("   %s %s\@ws [%s]\n",ts(),@{$ws->{conns}{$conn->{socket}}}{ip},$msg);
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
   my $max;

   for my $i ($start .. $#db) {
      $max = length(db_object($i)) if(length(db_object($i)) > $max);
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

sub fudge
{
   my $txt = shift;

#   return $txt;
   if($txt < 3) {
      return $txt;
   } elsif($txt == 3) {
      return -99999999;
   } else {
      return ($txt - 1);
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
   my $unnamed = 0;

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

   for my $y ( "A" .. "Z" ) {                # not defined in attrs.h fully
      @attr{ord($y) + 35} = "V_V" . $y;             # so fill in the blanks
      @attr{ord($y) + 64} = "V_Z" . $y;
   }

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
   my $ctl_a = chr(1);

   open(FILE,$file) ||                            # start reading actual db
      return err($self,$prog,"Could not open file '%s' for reading",$file);

#   my $one = char(1);
   while(<FILE>) {
      if($_ =~ /^"$ctl_a(\d+):(\d+):(.*)"$/) {
         $_ = $3;
      } elsif($_ =~ /^"(.*)"$/) {
         $_ = $1;
      }

      if($_ =~ /\r$/) {
         $prev = $_;
         next;
      } elsif($prev ne undef) {
         $_ = $prev . $_;
         $prev = undef;
      }

      s/\r|\n//g;
      if($. == 1 || $. == 2 || $. == 3) {
#         printf("# $_\n");
      } elsif($inattr && /^\+A(\d+)$/) {                           # attr id
         $id = $1;
      } elsif($inattr && $id ne undef &&                    # attr flag/name
              (/^(\d+):([^ ]+)$/ || /^"(\d+):([^ ]+)"$/)) {
         @attr{$id} = $2;
         $id = undef;
      } elsif(/^!(\d+)$/) {                                     # new object
         $inattr = 0;
         $id = $1;
         $pos = $.;
         $unnamed = 1;
         db_set($id+$start,"imported_dbref",$id);
      } elsif($inattr) {
         printf("INATTR[$.,%s]: '$_'\n",$. - $pos);
#         exit();
      } elsif(fudge($.  - $pos) == 1) {                                # name
         $name = $_;
         db_set($id+$start,"obj_name",$_);
         db_set($id+$start,"obj_cname",$_);
      } elsif(fudge($.  - $pos) == 2) {
         db_set($id+$start,"obj_location",($_ == -1) ? -1 : ($_+$start));
      } elsif(fudge($.  - $pos) == 3) {
         db_set_list($id+$start,"obj_content",($_ == -1) ? -1 : ($_+$start));
      } elsif(fudge($.  - $pos) == 4) {
         db_set_list($id+$start,"obj_exits",($_ == -1) ? -1 : ($_+$start));
      } elsif(fudge($.  - $pos) == 5) {
         db_set($id+$start,"obj_home",$_+$start);
      } elsif(fudge($.  - $pos) == 6) {    # unused, but needed during clean up
         db_set($id+$start,"obj_next",($_ == -1) ? -1 : ($_+$start));
      } elsif($lock ne undef || fudge($.  - $pos) == 7) {
         $lock .= $_;
         if(($lock =~ /\(/ && balanced($lock)) || $_ eq undef) {
            db_set($id+$start,"obj_lock_default",$lock);
            $lock = undef;
         } else {
            $pos++;
         }
      } elsif(fudge($.  - $pos) == 8) {
         db_set($id+$start,"obj_owner",($_ == -1) ? -1 : ($_+$start));
      } elsif(fudge($.  - $pos) == 9) {
         db_set($id+$start,"A_PARENT",$_) if($_ ne "-1");
      } elsif(fudge($.  - $pos) == 10) {
         db_set($id+$start,"obj_money",$_);
      } elsif(fudge($.  - $pos) == 11) {
         my %list;
         for my $flag (decode_flags(\%impflag,$_,1)) {
            @list{$flag} = 1;
            if(defined @flag{uc($flag)}) {
               db_set_list($id+$start,"obj_flag",lc($flag));
            }
            if($flag eq "PLAYER") {
               @player{trim(ansi_remove(lc($name)))} = $id;
               db_set($id+$start,"obj_name","imp_$name");
               db_set($id+$start,"obj_cname","imp_$name");
            }
         }
         if(!defined @list{PLAYER} && !defined @list{ROOM}) {
            db_set_list($id+$start,"obj_flag","object");
         }
         db_set_list($id+$start,"obj_flag","imported");
      } elsif(fudge($.  - $pos) == 12) {
         for my $flag (decode_flags(\%impflag,$_,2)) {
            if(defined @flag{lc($flag)}) {
               db_set_list($id+$start,"obj_flag",lc($flag));
            }
         }
      } elsif($_ =~ /^>(\d+)$/) {
         $unnamed = 0;
         db_set($id+$start,"obj_created_date",scalar localtime());
         $attr_id = $1;
      } elsif($attr_id ne undef) {
         if(@attr{$attr_id} eq "A_PASS") { # set password to name
            db_set($id+$start,"obj_password",mushhash(lc("imp_$name")));
         } elsif(@attr{$attr_id} eq "A_DESC") { # set password to name
            db_set($id+$start,"DESCRIPTION",$_);
         } elsif(@attr{$attr_id} eq "A_LAST") { # set password to name
            db_set($id+$start,"obj_last",$_);
         } elsif(defined @attr{$attr_id}) {
            db_set($id+$start,@attr{$attr_id},$_);
         } else {
            db_set($id+$start,"UNKNOWN_$attr_id",$_);
         }
         $attr_id = undef;
      } elsif($_ =~ /^<$/) {                                  # end of object
#         printf("----[ End of $id ]----\n");
         $id = undef;
      } elsif(/^\*\*\*END OF DUMP\*\*\*$/) {
         # yay!
      } elsif($unnamed == 1) {
         # unsupported attribute type?
      } else {
#         printf("UNKNOWN[$.,%s]: '$_'\n",$. - $pos);
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

main();                                                  #!# run only once
