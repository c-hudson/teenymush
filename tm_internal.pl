#!/usr/bin/perl



use strict;
use IO::Select;
use IO::Socket;
use Time::Local;
use Carp;

my %months = (
   jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6,
   jul => 7, aug => 8, sep => 9, oct => 10, nov => 11, dec => 12,
);

my %days = (
   mon => 1, tue => 2, wed => 3, thu => 4, fri => 5, sat => 6, sun => 7,
);

sub glob2re {
    my ($pat) = @_;
    $pat =~ s{(\W)}{
        $1 eq '?' ? '.' :
        $1 eq '*' ? '(*PRUNE)(.*?)' :
        '\\' . $1
    }eg;

    return qr/\A$pat\z/s;
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

   my_rollback;

   return sprintf($fmt,@args);
   # insert log entry? 
}

sub first
{
   my ($txt,$delim) = @_;

   $delim = ';' if $delim eq undef;

   return (split($delim,$txt))[0];
}

sub code
{
   my $type = shift;
   my @stack;

   if(Carp::shortmess =~ /#!\/usr\/bin\/perl/) {

      if(!$type || $type eq "short") {
         for my $line (split(/\n/,$`)) {
            if($line =~ /at ([^ ]+) line (\d+)\s*$/) {
               push(@stack,"$1:$2");
            }
         }
         return join(',',@stack);
      } else {
         return $`;
      }
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
         $out .= @{$$prog{created_by}}{obj_name};
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

#   printf("handle_object_listener: CALLED ($$target{obj_id}:%s)\n",$msg);
#   printf("target: '%s' -> '%s'\n",$$target{hostname},$$target{raw});
#    printf("handle_object_listen: '%s'\n",$msg);
#    printf("%s\n",code("long"));
    echo_output_to_puppet_owner($target,prog($target,$target),$msg);

   for my $hash (@{sql("select obj.obj_id, " .
                    "       substr(atr_value,2,instr(atr_value,':')-2) cmd,".
                    "       substr(atr_value,instr(atr_value,':')+1) txt ".
                    "  from object obj, " .
                    "       attribute atr, " .
                    "       flag_definition fld, " . 
                    "       flag flg  " . 
                    " where obj.obj_id = atr.obj_id " .
                    "   and fld.fde_flag_id = flg.fde_flag_id " .
                    "   and obj.obj_id = flg.obj_id " .
                    "   and obj.obj_id = ? " .
                    "   and ? like replace(substr(atr_value,1," .
                    "                      instr(atr_value,':')-1),'*','%')" .
                    "   and flg.atr_id is null " .
                    "   and fde_type = 1 " .
                    "   and fde_name = ? ",
                    $$target{obj_id},
                    "\!" . lc($msg),
                    "SOCKET_PUPPET"
                   )
                }) {
      $$hash{raw_hostname} = $$target{hostname};
      $$hash{raw_raw} = $$target{raw};
      $$hash{raw_socket} = $$target{socket};
#      $$hash{raw_enactor} = $$target{enactor};

      # determine %0 - %9
      if($$hash{cmd} ne $msg) {
         $$hash{cmd} =~ s/\*/\(.*\)/g;
         if($msg =~ /^$$hash{cmd}$/) {
            mushrun(self   => $hash,
                    runas  => $hash,
                    cmd    => $$hash{txt},
                    wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                    source => 0,
                   );
         } else {
            mushrun(self   => $hash,
                    runas  => $hash,
                    cmd    => $$hash{txt},
                    wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                    source => 0,
                   );
         }
      }
   }
}

#
# handle_listener
#    handle listening objects and the listener flag. This allows objects
#    to listen via the "^pattern:mush command".
#
sub handle_listener
{
   my ($self,$prog,$runas,$txt,@args) = @_;
   my $match = 0;

   my $msg = sprintf($txt,@args);

   # search the $$user's location for things that listen

   for my $hash (@{sql("select atr.obj_id, ".
                       "       atr_value, ".
                       "       atr_regexp, ".
                       "       atr_pattern, ".
                       "       f2.fde_flag_id ".
                       "  from content con,  ".
                       "       content con2, ".
                       "       flag flg,  ".
                       "       flag_definition fde, ".
                       "       attribute atr left outer join flag f2 on ".
                       "          atr.obj_id = f2.obj_id ".
                       "          and fde_flag_id = 13 ".
                       " where atr.obj_id = con.obj_id  ".
                       "   and atr.obj_id = flg.obj_id  ".
                       "   and flg.fde_flag_id = fde.fde_flag_id  ".
                       "   and fde_name = \"LISTENER\"  ".
                       "   and fde_type = 1 ".
                       "   and atr.atr_pattern_type = 2 ".
                       "   and con2.obj_id = ? ".
                       "   and (con.con_source_id = con2.con_source_id  ".
                       "      or con.con_source_id = ? ) ",
                        $$self{obj_id},
                        $$self{obj_id}
                      )
                }) {
      if($$hash{fde_flag_id} ne undef) {
         if($msg =~ /$$hash{atr_regexp}/) {
            mushrun(self   => $self,
                    runas => $hash,
                    cmd    => $$hash{atr_value},
                    wild   => [$1,$2,$3,$4,$5,$6,$7,$8,$9],
                    source => 0,
                   );
             $match=1;
         }
      } elsif($msg =~ /$$hash{atr_regexp}/) {
         mushrun(self   => $self,
                 runas  => $hash,
                 source => 0,
                 cmd    => $$hash{atr_value},
                 wild   => [ $1,$2,$3,$4,$5,$6,$7,$8,$9 ]
                );
         $match=1;
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

sub lcon
{
   my $object = obj(shift);
   my @result;

   for my $obj (@{sql($db,
                      "select obj.* " .
                      "  from object obj, " .
                      "       content con " . 
                      " where obj.obj_id = con.obj_id " .
                      "   and con.con_source_id = ? ",
                      $$object{obj_id},
                )}) {
      push(@result,$obj);
   }
   return @result;
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

   $txt =~ s/([\r\n]+)$//g;

   my $tmp = $$db{rows}; # its easy to try to necho() data before testing
                         # against $$db{rows}, which  will clear $$db{rows}.
                         # so we'll revert it after the below sql() call.

   sql($db,                                     #store output in output table
       "insert into output" .
       "(" .
       "   out_text, " .
       "   out_source, ".
       "   out_location, ".
       "   out_destination ".
       ") values ( ".
       "   ?, " .
       "   ?, " .
       "   ?, " .
       "   ? " .
       ")",
       substr($txt,0,63999),
       $$src{obj_id},
       $loc,
       $$dst{obj_id}
      );
   $$db{rows} = $tmp;
   my_commit;
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

   if(defined @{$arg{self}}{loggedin} && !@{$arg{self}}{loggedin}) {
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

   for my $type ("room", "room2") {                       # handle room echos
      if(defined $arg{$type}) {
         my $array = $arg{$type};
         my $target = obj(shift(@$array));
         my $fmt = shift(@$array);
         my $msg = filter_chars(sprintf($fmt,@{$arg{$type}}));
         for my $sock (@{sql("select c1.obj_id,  ".
                             "       c1.con_source_id, ".
                             "       s.sck_socket ".
                             "  from content c1 left outer join socket s on  ".
                             "          c1.obj_id = s.obj_id,  ".
                             "       content c2,  ".
                             "       flag flg,  ".
                             "       flag_definition fde ".
                             " where c1.con_source_id = c2.con_source_id ".
                             "   and c1.obj_id = flg.obj_id ".
                             "   and c1.obj_id != ? ".
                             "   and flg.fde_flag_id = fde.fde_flag_id  ".
                             "   and c2.obj_id = ? ".
                             "   and fde_name in ('OBJECT','PLAYER')",
                             $$target{obj_id},
                             $$target{obj_id},
                      )}) {
             if($$sock{sck_socket} ne undef) {
                my $s = @{@connected{$$sock{sck_socket}}}{sock};
                printf($s "%s%s",nospoof(@arg{self},@arg{prog},$$sock{obj_id}),
                   $msg);
                $loc = $$sock{con_source_id};
             } else {
                echo_output_to_puppet_owner($$sock{obj_id},
                                            $arg{prog},
                                            $msg,
                                            $arg{debug}
                                           );
             }
         }

         log_output($self,-1,$loc,$msg);
         handle_listener($arg{self},$arg{prog},$target,$fmt,@$array);
      }
   }
 
   unshift(@{$arg{source}},$arg{self}) if(defined $arg{source});

   for my $type ("source", "target") {
      next if !defined $arg{$type};

      if(ref($arg{$type}) ne "ARRAY") {
         return err($arg{self},$arg{prog},"Argument $type is not an array");
      }

      my ($target,$fmt) = (shift(@{$arg{$type}}), shift(@{$arg{$type}}));
      my $msg = filter_chars(sprintf($fmt,@{$arg{$type}}));


      # output needs to be saved for use by http, websocket, or run()
      if(defined $$prog{output} && 
         (@{$$prog{created_by}}{obj_id} == $$target{obj_id} ||
          $$target{obj_id} == @info{"conf.webuser"} || 
          $$target{obj_id} == @info{"conf.webobject"}
         )
        ) {
            my $stack = $$prog{output};
            push(@$stack,$msg);
            next;
      }

#      if(!defined @arg{hint} ||
#         (@arg{hint} eq "ECHO_ROOM" && loc($target) != loc(owner($target)))) {
         echo_output_to_puppet_owner($target,$arg{prog},$msg,$arg{debug});
#      }

      if(defined @{$arg{self}}{loggedin} && !@{$arg{self}}{loggedin}) {
         my $self = $arg{self};
         my $s = @{$connected{$$self{sock}}}{sock};
         printf($s "%s",$msg);
      } else {
         log_output($self,$target,-1,$msg);

         if(hasflag($target,"PLAYER")) {         # echo to all player's sockets
            for my $sock (@{sql($db,
                          "select * from socket " .
                          " where obj_id = ? " .
                          " and sck_type = 1",
                          $$target{obj_id}
                         )}) {
               my $s = @{@connected{$$sock{sck_socket}}}{sock};
               printf($s "%s%s",nospoof(@arg{self},@arg{prog},$$sock{obj_id}),
                   $msg);
            }
         }
      }
   }
}

sub echo_output_to_puppet_owner
{
   my ($self,$prog,$msg,$debug) = (obj(shift),obj(shift),shift,shift);
   $msg =~ s/\n*$//;

   my $obj_loc = loc($self);

   if(hasflag($self,"PUPPET")) {                      # forward if puppet
      for my $player (@{sql($db,
                            "select sck_socket, " .
                            "       obj2.obj_id, " .
                            "       obj2.obj_name, " .
                            "       c.con_source_id " .
                            "  from socket sck, " .
                            "       object obj1, " .
                            "       object obj2, " .
                            "       content c " .
                            " where sck.obj_id = obj1.obj_owner ".
                            "   and obj1.obj_id = ? ".
                            "   and obj1.obj_owner = obj2.obj_id ".
                            "   and c.obj_id = obj2.obj_id ".
                            "   and sck_type = 1 ",
                            $$self{obj_id}
                     )}) {
         my $sock = @{@connected{$$player{sck_socket}}}{sock};

         if($obj_loc != $$player{con_source_id}) {
             printf($sock "%s%s> %s\n",
                    nospoof($self,$prog,$player),
                    name($self),
                    $msg
                   );
         }
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
            printf($sock "%s",$out);
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

#
# name
#    Return the name of the object from the database if it hasn't already
#    been pulled.
#
sub name
{
   my $target = obj(shift);

#   if(!defined $$target{obj_name} && defined $$target{obj_id} && $$target{obj_id} ne undef) {     # no name, query db
      $$target{obj_name} = one_val("select obj_name value " .
                                   "  from object "  .
                                   " where obj_id = ?",
                                   $$target{obj_id}); 
#   }

   if($$target{obj_name} eq undef) {           # no name, how'd that happen?
      $$target{obj_name} = "[<UNKNOWN>]";
   }

   return $$target{obj_name}; 
}

sub echo_flag
{
   my ($self,$prog,$flags,$fmt,@args) = @_;
   my ($list,@where,$connected);

   for my $flag (split(/,/,$flags)) {
      if($flag eq "CONNECTED") {
         $connected = 1;
      } else {
         $list .= " and " if($#where != -1) ;
         $list .= "exists (select 1 " .
                  "          from flag flg, " .
                  "               flag_definition fde " .
                  "         where obj.obj_id = flg.obj_id " . 
                  "           and flg.fde_flag_id = fde.fde_flag_id " .
                  "           and fde_name = ?) ";
         push(@where,$flag);
      }
   }

   for my $player (@{sql($db,                    # search room target is in
                         "select distinct obj.* " . 
                         "  from object obj" .
                         (($connected) ? ", socket sck" : "") .
                         " where $list " .
                         (($connected) ? "and sck.obj_id = obj.obj_id " : ""),
                         @where
                   )}) {
      necho(self => $self,
            prog => $prog,
            target => [ $player, $fmt, @args ]
           );
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
   my $target = shift;

   if(ref($target) eq "HASH") {
      if(defined $$target{sock} && 
         defined @connected{$$target{sock}} &&
         defined @{@connected{$$target{sock}}}{loggedin}) {
         return  @{@connected{$$target{sock}}}{loggedin};
      } else {
         my $result = one_val($db,
                              "select count(*) value from socket " .
                              " where obj_id = ? ",
                              $$target{obj_id}
                             );
         return ($result > 0) ? 1 : 0;
      }
   } else {
      return 0;
   }
}

sub flag_list
{
   my ($obj,$flag) = (obj($_[0]),$_[1]);
   my (@list,$array);
   $flag = 0 if !$flag;
 
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
   return join($flag ? " " : '',@list);
}

sub valid_dbref 
{
   my $id = obj(shift);
   $$id{obj_id} =~ s/#//g;

   return one_val("select if(count(*) = 0,0,1) value " . 
                  "  from object " . 
                  " where obj_id = ?",
                  $$id{obj_id}) || return 0;
}

sub owner
{
   my $object = obj(shift);

   if(hasflag($object,"PLAYER")) {            # players are owned by god,
      return fetch($object);                # but really they own themselves
   } elsif(defined $$object{obj_owner}) {
      return fetch($$object{obj_owner});
   } else {
      my $child = fetch($$object{obj_id});
      return fetch($$child{obj_owner});
   }
}

sub owner_id
{
   my $object = obj(shift);

   if(hasflag($object,"PLAYER")) {                # players are owned by god,
      return $$object{obj_id};               # but really they own themselves
   } elsif(defined $$object{obj_owner}) {
      return $$object{obj_owner};
   } else {
      return one_val("select obj_owner value " .
                     "  from object " . 
                     " where obj_id = ?",
                     $$object{obj_id});
   }
}

sub locate_player
{
   my ($name,$type) = @_;
   my @part;

   if($name =~ /^\s*#(\d+)\s*$/) {      # specified dbref, verify is player
      my $target=one("select * ".
                     " from object obj, flag flg, flag_definition fde ".
                     "where obj.obj_id = flg.obj_id " .
                     "  and fde.fde_flag_id = flg.fde_flag_id " .
                     "  and fde_name = 'PLAYER' " .
                     "  and flg.atr_id is null " .
                     "  and fde_type = 1 " .
                     "  and obj.obj_id = ? ",$1) ||
          return undef;
      return $target;
   } elsif($name =~ /^\s*me\s*$/) {              # use current object/player
      return $user;
   } elsif($name =~ /^\s*\*([^ ]+)\s*$/) {
      $name = $1;
   }

   if($type eq "online") {                                  # online player
      for my $i (keys %connected) {
         if(uc(@{$connected{$i}}{obj_name}) eq uc($name)) {
            return $connected{$i};
         } elsif(${$connected{$i}}{obj_name}=~/^\s*$name/i) {
            return undef if($#part == 0);
            push(@part,$connected{$i});
         }
      }
      return $part[0];
   } else {
      my $target = one($db,
                       "select * " .
                       "  from object obj, flag flg, flag_definition fde " .
                       " where obj.obj_id = flg.obj_id " .
                       "   and flg.fde_flag_id = fde.fde_flag_id " .
                       "   and fde.fde_name = 'PLAYER' " .
                       "   and flg.atr_id is null " .
                       "   and fde_type = 1 " .
                       "   and upper(obj_name) = upper(?) ",
                       $name
                      ) ||
         return undef;
      return $target;
   }
}
  

sub locate_object
{
   my ($self,$prog,$name,$type) = @_;
   my ($where, @what,$exact,$indirect);

   if($name =~ /^\s*#(\d+)\s*$/) {                                  # dbref
      return fetch($1);
   } elsif($name =~ /^\s*%#\s*$/) {
      return $$prog{created_by};
   } elsif($name =~ /^\s*me\s*$/) {                                # myself
      return $self;
   } elsif($name =~ /^\s*here\s*$/) {
      return loc_obj($self);
   } elsif($name =~ /^\s*\*([^ ]+)\s*$/) {                  # online-player
      return locate_player($name,"all");
   } elsif($type eq "CONTENT") {
      $where = 'con.con_source_id in ( ? )';
      (@what[0]) = ($$self{obj_id});
   } elsif($type eq "LOCAL") {
      $where = 'con.con_source_id in ( ? , ? )';
      ($what[0],$what[1]) = (loc($self),$$self{obj_id});
   } else {
      $where = 'con.con_source_id in ( ? , ? )';
      ($what[0],$what[1]) = (loc($self),$$self{obj_id});
   }
    
   
   for my $hash (@{sql($db,"select * " .
                           "  from object obj, flag flg, flag_definition fde, ".
                           "       content con " .
                           " where obj.obj_id = flg.obj_id " .
                           "   and flg.fde_flag_id = fde.fde_flag_id " .
                           "   and con.obj_id = obj.obj_id ".
                           "   and fde.fde_name in ('PLAYER','OBJECT', 'EXIT')".
                           "  and upper(substr(obj_name,1,length(?)))=upper(?)".
                           "   and atr_id is null " .
                           "   and fde_type = 1 " .
                           "   and $where",
                    $name,
                    $name,
                    @what)}) {
      if(($$hash{fde_name} ne "EXIT" &&
         lc($name) eq lc($$hash{obj_name})) ||
        ($$hash{fde_name} eq 'EXIT' && 
         $$hash{obj_name} =~ /(^|;)\s*$name\s*(;|$)/i)) {
         if($exact eq undef) {
            $exact = $hash;
         } else {
            return undef;
         }
      } elsif($indirect ne undef) {
#         $$hash{obj_name} =~ /(^|;)\s*$name([^;]*)\s*(;|$)/i)) {
         if(length($$indirect{obj_name}) > length($$hash{obj_name})) {
            $indirect = $hash;
         }
      } else {
         $indirect = $hash;
      }
   }
   return ($exact ne undef) ? $exact : $indirect;
}

sub locate_exit
{
   my ($name,$type) = @_;
   my @partial;

   if($name =~ /^\s*#(\d+)\s*$/) {
      return fetch($1);
   } elsif($name =~ /^\s*home\s*/i) {
      return fetch(3);
   }

   for my $hash (@{sql($db,
                      "select obj.*, con1.* " .
                      "  from object obj, flag flg, flag_definition fde, ".
                      "       content con1, content con2 " .
                      " where obj.obj_id = flg.obj_id " .
                      "   and flg.fde_flag_id = fde.fde_flag_id " .
                      "   and con1.obj_id = obj.obj_id ".
                      "   and con1.con_source_id = con2.con_source_id " .
                      "   and fde.fde_name = 'EXIT' " .
                      "   and atr_id is null " .
                      "   and fde_type = 1 " .
                      "   and con2.obj_id = ? ",
                      $$user{obj_id}
                   )}) { 

      for my $item (split(';',$$hash{obj_name})) {       # exits have multiple 
         if(lc($item) eq lc($name)) {                     # ; seperated names
            return $hash;                                  # found exact match
         } elsif(substr(lc($item),0,length($name)) eq lc($name)) {
            push(@partial,$hash);                              # partial match
         }
      }
   }

   if($#partial != 0 || $type eq "EXACT") {            # if too many matches, 
      return undef;                                     # or need exact match
   } else {                                          
      return $partial[0];                            # single partial is good
   }
}



#
# set_flag
#   Add a flag to an object. Verify that the object does not already have
#   the flag first.
#
sub set_flag
{
    my ($self,$prog,$obj,$flag,$override) = 
       (obj($_[0]),$_[1],obj($_[2]),$_[3],$_[4]);
    my $who = $$user{obj_name};;
    my ($remove,$count);

    if(!$override && !controls($user,$obj)) {
       return err($self,$prog,"#-1 PERMission denied.");
    }

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
          my_commit;
          if($flag =~ /^\s*(PUPPET|LISTENER)\s*$/i) {
             necho(self => $self,
                   prog => $prog,
                   room => [$obj,"%s is no longer listening.",$$obj{obj_name} ]
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
                   room => [$obj,"%s is now listening.", $$obj{obj_name} ]
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
          return "#-1 Flag note removed [Internal Error]" if($$db{rows} != 1);
          return "Set.";
       }
    } else {
       return "#-1 Permission Denied.";
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
        "   and fde1.fde_name=upper(?)",
        $flag
       );

    if($hash eq undef || !defined $$hash{fde_flag_id} ||
       $$hash{fde_name} eq "ANYONE") {       # unknown flag?
       return "#-1 Unknown Flag.";
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
       my $flag = one_val($db,
                          "select ofg_id value " .
                          "  from flag " .
                          " where atr_id = ? " .
                          "   and fde_flag_id = ?",
                          $atr_id,
                          $$hash{fde_flag_id}
                         );
                               
       # add flag to the object/user
       if($flag ne undef && $remove) {
          sql($db,
              "delete from flag " .
              " where ofg_id= ? ",
              $flag
             );
          my_commit;
          return "Flag Removed.";
       } elsif($remove) {
          return "Flag not set.";
       } elsif($flag ne undef) {
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
# hasflag
#    Return if an object has a flag or not
#
sub hasflag
{
   my ($target,$flag) = (obj($_[0]),$_[1]);

   if($flag eq "WIZARD") {
      return one_val($db,"select if(count(*) > 0,1,0) value " . 
                         "  from flag flg, flag_definition fde " .
                         " where flg.fde_flag_id = fde.fde_flag_id " .
                         "   and atr_id is null ".
                         "   and fde_type = 1 " .
                         "   and obj_id = ? " .
                         "   and fde_name = ? ",
                         owner_id($target),
                         uc($flag));
   
   } else {
      return one_val($db,"select if(count(*) > 0,1,0) value " . 
                         "  from flag flg, flag_definition fde " .
                         " where flg.fde_flag_id = fde.fde_flag_id " .
                         "   and atr_id is null ".
                         "   and fde_type = 1 " .
                         "   and obj_id = ? " .
                         "   and fde_name = ? ",
                         $$target{obj_id},
                         uc($flag));
   }
}

#
# atr_hasflag
#    Return if an object's attriubte has a flag or not
#
sub atr_hasflag
{
   my ($attribute,$flag) = @_;

   return one_val($db,
                 "select if(count(*) > 0,1,0) value " .
                 "  from flag flg, flag_definition fde " .
                 " where flg.fde_flag_id = fde.fde_flag_id " .
                 "   and fde_type = 2 " .
                 "   and atr_id = ? " .
                 "   and fde_name = upper(?) ",
                 $attribute,
                 $flag
                );
}

sub create_object
{
   my ($self,$prog,$name,$pass,$type) = @_;
   my ($where);
   my $who = $$user{obj_name};
   my $owner = $$user{obj_id};

   # check quota
   if($type ne "PLAYER" && quota_left($$user{obj_id}) <= 0) {
      printf("No quota, no create\n");
      return 0;
   }
  
   if($type eq "PLAYER") {
      $where = 3;
      $who = $$user{hostname};
      $owner = 0;
   } elsif($type eq "OBJECT") {
      $where = $$user{obj_id};
   } elsif($type eq "ROOM") {
      $where = -1;
   } elsif($type eq "EXIT") {
      $where = -1;
   }


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

sub set
{
   my ($self,$prog,$obj,$attribute,$value,$quiet,$type)=
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
      sql($db,
          "delete " .
          "  from attribute " .
          " where atr_name = ? " .
          "   and obj_id = ? ",
          lc($attribute),
          $$obj{obj_id}
         );
      necho(self   => $self,
            prog   => $prog,
            source => [ "Set." ]
           );
   } else {
      if($value =~ /^\s*(\$|\^|\!)([^:]+?):/) {
         ($pat,$value) = ($2,$');
         if($1 eq "\$") {
            $type = 1;
         } elsif($1 eq "^") {
            $type = 2;
         } elsif($1 eq "!") {
            $type = 3;
         }
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

sub get
{
   my ($obj,$attribute) = (obj($_[0]),$_[1]);
   my $hash;

   $obj = { obj_id => $obj } if ref($obj) ne "HASH";
   $attribute = "description" if(lc($attribute) eq "desc");

   if(($hash = one($db,"select atr_value from attribute " .
                         " where obj_id = ? " .
                         "   and atr_name = upper( ? )",
                         $$obj{obj_id},
                         $attribute
                        ))) {
      return $$hash{atr_value};
   } else {
      return undef;
   }
}

sub loc_obj
{
   my $obj = obj(shift);

   return fetch(one_val($db,
                        "select con_source_id value " .
                        "  from content " .
                        " where obj_id = ?",
                        $$obj{obj_id}
                       ));
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
   my ($self,$obj,$flag) = (obj(shift),obj(shift),shift);
   
#   $obj = fetch($obj) if(!defined $$obj{obj_name});
   $obj = fetch($obj);
   if(controls($self,$obj) || $flag) {
      return $$obj{obj_name} . "(#" . $$obj{obj_id} . flag_list($obj) . ")";
   } else {
      return $$obj{obj_name};
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

   my $current = loc($target);
   if(hasflag($current,"ROOM")) {
      set($self,$prog,$current,"LAST_INHABITED",scalar localtime(),1);
   }

   # look up destination object
   # remove previous location record for object
   sql($db,"delete from content " .           # remove previous loc
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

   $current = loc($target);
   if(hasflag($current,"ROOM")) {
      set($self,$prog,$current,"LAST_INHABITED",scalar localtime(),1);
   }
   my_commit($db);
   return 1;
}

sub obj
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

   return one_val($db,
                  "SELECT skh_hostname value " .
                  "  from socket_history skh1 " .
                  " where obj_id = ? " .
                  "   and skh_id = (select max(skh_id) " .
                  "                   from socket_history skh2 " .
                  "                  where skh1.obj_id = skh2.obj_id )",
                  $$target{obj_id}
                 );
}

sub firstsite
{
   my $target = obj(shift);

   return one_val($db,
                  "SELECT skh_hostname value " .
                  "  from socket_history skh1 " .
                  " where obj_id = ? " .
                  "   and skh_id = (select min(skh_id) " .
                  "                   from socket_history skh2 " .
                  "                  where skh1.obj_id = skh2.obj_id )",
                  $$target{obj_id}
                 );
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

    return one_val($db,
                   "select count(*) value " .
                   "  from flag_definition " .
                   " where fde_name = upper(trim(?)) " .
                   "   and fde_type = 2",
                   $txt
                   );
}

sub read_config
{
   my $count=0;
   for my $line (split(/\n/,getfile("tm_config.dat"))) {
      $line =~ s/\r|\n//g;
      if($line =~/^\s*#/ || $line =~ /^\s*$/) {
         # comment or blank line, ignore
      } elsif($line =~ /^\s*([^ =]+)\s*=\s*(.*?)\s*$/) {
         @info{$1} = $2;
      } else {
         printf("Invalid data in tm_config.dat:\n") if($count == 0);
         printf("    '%s'\n",$line);
         $count++;
      }
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
