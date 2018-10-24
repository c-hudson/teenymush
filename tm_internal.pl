#!/usr/bin/perl
#
# tm_internal
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

sub arg
{
   my $txt = shift;

   for my $i (0 .. $#ARGV) {
      return 1 if(@ARGV[$i] eq $txt || @ARGV[$i] eq "--$txt") 
   }
   return 0;
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

   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime(time);
   $mon++;

   return sprintf("%02d:%02d@%02d/%02d",$hour,$min,$mon,$mday);
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

#sub getfile
#{
#   my ($fn,$code) = @_;
#   my($actual,$file, $out);
#
#   if($fn =~ /\||;/) {         # ignore bad file names and attempt to be safe
#      return undef;
#   } elsif($fn =~ /^[^\\|\/]+\.(pl|dat)$/i) {
#      $actual = $fn;
#   } elsif($fn =~ /^[^\\|\/]+$/i) {
#      $actual = "txt\/$fn";
#   } else {
#      return undef;
#   }
#
#   my $newmod = (stat($actual))[9];                  # find modification time
#
#   if(defined @info{"file_$fn"}) {                      # look at cached data
#      my $hash = @info{"file_$fn"};
#
#      # use cached version if its still good
#      return $$hash{data} if($$hash{mod} == $newmod);
#   }
#
#   open($file,$actual) || return undef;
#
#   @{$$code{$fn}}{lines} = 0 if(ref($code) eq "HASH");
#   while(<$file>) {                                           # read all data
#      @{$$code{$fn}}{lines}++ if(ref($code) eq "HASH");
#      $out .= $_;
#   }
#   close($file);
#   $out =~ s/\r//g;
#   $out =~ s/\n/\r\n/g;
#
#   @info{"file_$fn"} = {                                 # store cached data
#      mod => $newmod,
#      data => $out
#   };
#
#   return $out;                                                # return data
#}

sub lastsite
{
   my $target = obj(shift);

   if(memorydb) {
      my $attr = mget($target,"obj_lastsite");

      if($attr eq undef) {
         return undef;
      } else {
         my $list = $$attr{value};
         my $data = $$list{(sort keys %$list)[-1]};

         if($data =~ /^\d+,\d+,(.*)$/) {
            return $1;
         } else {
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
