#!/usr/bin/perl

use strict;
use HTML::HTML5::Entities;
use Carp;
use Text::Glob qw( match_glob glob_to_regex );
use Scalar::Util qw(looks_like_number);

#
# define which function's arguements should not be evaluated before
# executing the function. The sub-hash defines exactly which argument
# should be not evaluated ( starts at 1 not 0 )
#
my %exclude = 
(
   iter      => { 2 => 1 },
   setq      => { 2 => 1 },
   switch    => { all => 1 },
#   u         => { 2 => 1, 3 => 1, 4 => 1, 5 => 1, 6 => 1, 7 => 1, 8 => 1,
#                  9 => 1, 10 => 1 },
);

my %fun = 
(
   substr    => sub { return &fun_substr(@_);                           },
   cat       => sub { return &fun_cat(@_);                              },
   space     => sub { return &fun_space(@_);                            },
   repeat    => sub { return &fun_repeat(@_);                           },
   time      => sub { return &fun_time(@_);                             },
   flags     => sub { return &fun_flags(@_);                            },
   quota     => sub { return quota_left($$user{obj_id})                 },
#  sql       => sub { return &fun_sql(@_);                              },
   input     => sub { return &fun_input(@_);                            },
   has_input => sub { return &fun_has_input(@_);                        },
   strlen    => sub { return &fun_strlen(@_);                           },
   lattr     => sub { return &fun_lattr(@_);                            },
   iter      => sub { return &fun_iter(@_);                             },
   huh       => sub { return "#-1 Undefined function";                  },
   ljust     => sub { return &fun_ljust(@_);                            },
   rjust     => sub { return &fun_rjust(@_);                            },
   extract   => sub { return &fun_extract(@_);                          },
   lwho      => sub { return &fun_lwho(@_);                             },
   remove    => sub { return &fun_remove(@_);                           },
   get       => sub { return &fun_get(@_);                              },
   edit      => sub { return &fun_edit(@_);                             },
   add       => sub { return &fun_add(@_);                              },
   sub       => sub { return &fun_sub(@_);                              },
   div       => sub { return &fun_div(@_);                              },
   secs      => sub { return &fun_secs(@_);                             },
   loadavg   => sub { return &fun_loadavg(@_);                          },
   after     => sub { return &fun_after(@_);                            },
   before    => sub { return &fun_before(@_);                           },
   member    => sub { return &fun_member(@_);                           },
   index     => sub { return &fun_index(@_);                            },
   replace   => sub { return &fun_replace(@_);                          },
   num       => sub { return &fun_num(@_);                              },
   lnum      => sub { return &fun_lnum(@_);                             },
   name      => sub { return &fun_name(@_);                             },
   type      => sub { return &fun_type(@_);                             },
   u         => sub { return &fun_u(@_);                                },
   v         => sub { return &fun_v(@_);                                },
   r         => sub { return &fun_r(@_);                                },
   setq      => sub { return &fun_setq(@_);                             },
   mid       => sub { return &fun_substr(@_);                           },
   center    => sub { return &fun_center(@_);                           },
   rest      => sub { return &fun_rest(@_);                             },
   first     => sub { return &fun_first(@_);                            },
   switch    => sub { return &fun_switch(@_);                           },
   words     => sub { return &fun_words(@_);                            },
   eq        => sub { return &fun_eq(@_);                               },
   not       => sub { return &fun_not(@_);                              },
   match     => sub { return &fun_match(@_);                            },
   isnum     => sub { return &fun_isnum(@_);                            },
   gt        => sub { return &fun_gt(@_);                               },
   gte       => sub { return &fun_gte(@_);                              },
   lt        => sub { return &fun_lt(@_);                               },
   lte       => sub { return &fun_lte(@_);                              },
   or        => sub { return &fun_or(@_);                               },
   and       => sub { return &fun_and(@_);                              },
   hasflag   => sub { return &fun_hasflag(@_);                          },
   squish    => sub { return &fun_squish(@_);                           },
   capstr    => sub { return &fun_capstr(@_);                           },
   lcstr     => sub { return &fun_lcstr(@_);                            },
   ucstr     => sub { return &fun_ucstr(@_);                            },
   setinter  => sub { return &fun_setinter(@_);                         },
   mudname   => sub { return &fun_mudname(@_);                          },
   version   => sub { return &fun_version(@_);                          },
   decode_entities => sub { return &fun_de(@_);                         },
);


sub safe_split
{
    my ($txt,$delim) = @_;
    $delim =~ s/^\s+|\s+$//g;
 
    if($delim eq " " || $delim eq undef) {
       $txt =~ s/\s+/ /g;
       $txt =~ s/^\s+|\s+$//g;
       $delim = " ";
    }
    my ($start,$pos,$size,$dsize,@result) = (0,0,length($txt),length($delim));

    for($pos=0;$pos < $size;$pos++) {
       if(substr($txt,$pos,$dsize) eq $delim) {
          push(@result,substr($txt,$start,$pos-$start));
          @result[$#result] =~ s/^\s+|\s+$//g;
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
      return 1 if($count eq @possible[$i]);
   }
   return 0;
}

sub fun_mudname
{
   if(defined @info{mudname}) {
      return @info{mudname};
   } else {
      return "TeenyMUSH";
   }
}

sub fun_version
{
   if(defined @info{version}) {
      return @info{version};
   } else {
      return "TeenyMUSH";
   }
}

sub fun_setinter
{
   my (%list, %out);

   for my $i (split(/,/,@_[0])) {
       @list{$i} = 1;
   }

   for my $i (split(/,/,@_[1])) {
      if(defined @out{$i}) {
         @out{$i} = 1;
      }
  }
  return sort keys %out;
}


sub fun_lwho
{
   my @who;

   for my $key (@{sql($db,
                    "select obj_id " .
                    "  from socket sck " .
                    " where sck_type = 1 ",
                   )}
               ) {
      push(@who,"#" . $$key{obj_id});
   }
   return join(' ',@who);
}
sub fun_lcstr
{
    good_args($#_,1) ||
      return "#-1 FUNCTION (LCSTR) EXPECTS 1 ARGUEMENT ($#_)";

    return lc(shift);
}

sub fun_ucstr
{
    good_args($#_,1) ||
      return "#-1 FUNCTION (UCSTR) EXPECTS 1 ARGUEMENT ($#_)";

    return uc(shift);
}

sub fun_capstr
{
    good_args($#_,1) ||
      return "#-1 FUNCTION (SQUISH) EXPECTS 1 ARGUEMENT ($#_)";

    return ucfirst(shift);
}
sub fun_squish
{
    my $txt = @_[0];

    good_args($#_,1) ||
      return "#-1 FUNCTION (SQUISH) EXPECTS 1 ARGUEMENT ($#_)";

    $txt =~ s/^\s+|\s+$//g;
    $txt =~ s/\s+/ /g;
    return $txt;
}
sub fun_eq
{
   good_args($#_,2) ||
      return "#-1 FUNCTION (EQ) EXPECTS 2 ARGUEMENTS";

   my ($one,$two) = @_;

   $one =~ s/^\s+|\s+$//g;
   $two =~ s/^\s+|\s+$//g;
   return ($one eq $two) ? 1 : 0;
}

sub fun_hasflag
{
   good_args($#_,2) ||
      return "#-1 FUNCTION (HASFLAG) EXPECTS 2 ARGUEMENTS";

   return 0 if($_[1] =~ /^s*(nospoof|haven|dark|royal|royalty)\s*$/i);

   my $target = locate_object($$prog{user},$_[0]);
 
   return "#-1 Unknown Object" if($target eq undef);

   my $result = one_val("select count(*) value " . 
                        "  from flag_definition ".
                        " where fde_name = ?",
                        $_[1]);
   return "#-1 Invalid Flag" if($result eq undef or $result == 0);

   
   return hasflag($target,$_[1]);
}

sub fun_gt
{
   good_args($#_,2) ||
      return "#-1 FUNCTION (GT) EXPECTS 2 ARGUEMENTS";
   return (@_[0] > @_[1]) ? 1 : 0;
}

sub fun_gte
{
   good_args($#_,2) ||
      return "#-1 FUNCTION (GTE) EXPECTS 2 ARGUEMENTS";
   return (@_[0] >= @_[1]) ? 1 : 0;
}

sub fun_lt
{
   good_args($#_,2) ||
      return "#-1 FUNCTION (LT) EXPECTS 2 ARGUEMENTS";
   return (@_[0] < @_[1]) ? 1 : 0;
}

sub fun_lte
{
   good_args($#_,2) ||
      return "#-1 FUNCTION (LT) EXPECTS 2 ARGUEMENTS";
   return (@_[0] <= @_[1]) ? 1 : 0;
}

sub fun_or
{
   for my $i (0 .. $#_) {
      return 1 if($_[$i]);
   }
   return 0;
}


sub fun_isnum
{
   good_args($#_,1) ||
      return "#-1 FUNCTION (ISNUM) EXPECTS 1 ARGUEMENT";

   return looks_like_number($_[0]) ? 1 : 0;
}

sub fun_lnum
{
   good_args($#_,1) ||
      return "#-1 FUNCTION (LNUM) EXPECTS 1 ARGUEMENT";

   return "#-1 ARGUMENT MUST BE NUMBER" if(!looks_like_number($_[0]));

   return join(' ',0 .. ($_[0]-1));
}

sub fun_and
{
    for my $i (0 .. $#_) {
       return 0 if($_[$i] eq 0);
    }
    return 1;
}

sub fun_not
{
   good_args($#_,1) ||
      return "#-1 FUNCTION (NOT) EXPECTS 1 ARGUEMENTS";

   return (! $_[0] ) ? 1 : 0;
}


sub fun_words
{
   my ($txt,$delim) = @_;

   good_args($#_,1,2) ||
      return "#-1 FUNCTION (WORDS) EXPECTS 1 OR 2 ARGUMENTS";

   return scalar(safe_split($txt,($delim eq undef) ? " " : $delim));
}

sub fun_match
{
   my ($txt,$pat,$delim) = @_;
   my $count = 1;

   good_args($#_,1,2,3) ||
      return "#-1 FUNCTION (MATCH) EXPECTS 1, 2 OR 3 ARGUMENTS";

   $delim = " " if $delim eq undef; 

   for my $word (safe_split($txt,$delim)) {
      return $count if(match_glob(lc($pat),lc($word)));
      $count++;
   }
   return 0;
}

sub fun_center
{
   my ($txt,$size) = @_;

   if(!good_args($#_,2)) {
      return "#-1 FUNCTION (MEMBER) EXPECTS 2 ARGUMENTS";
   } elsif($size !~ /^\s*\d+\s*$/) {
      return "#-1 SECOND ARGUMENT MUST BE NUMERIC";
   } elsif($size eq 0) { 
      return "#-1 SECOND ARGUMENT MUST NOT BE ZERO";
   }
   $txt = substr($txt,0,$size);
   return sprintf("%-*s",$size,(" " x (($size - length($txt))/2)).$txt);
}

sub fun_switch
{
   my $first = evaluate(shift,$$prog{user});

   while($#_ >= 0) {
      if($#_ >= 1) {
         my $txt = evaluate(shift,$$prog{user});
         $txt =~ s/\*/\(.*\)/g;
         $txt =~ s/^\s+|\s+$//g;

         if($first =~ /^\s*$txt\s*$/i) {
            return evaluate(@_[0],$$prog{user});
         } else {
            shift;
         }
      } else {
         return evaluate(shift,$$prog{user});
      }
   }
}

sub fun_member
{
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
   my ($txt,$positions,$word,$idelim,$odelim) = @_;
   my $i = 1;

   if(!good_args($#_,3,4,5)) {
      return "#-1 FUNCTION (INDEX) EXPECTS 3, 4 or 5 ARGUMENTS";
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
   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (AFTER) EXPECTS 1 or 2 ARGUMENTS";
   }

   my $loc = index(@_[0],@_[1]);
   if($loc == -1) {
      return undef;
   } else {
      my $result = substr(@_[0],$loc + length(@_[1]));
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_rest
{
   my ($txt,$delim) = @_;
   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (REST) EXPECTS 1 or 2 ARGUMENTS";
   }

   $delim = " " if($delim eq undef);
   my $loc = index(evaluate($txt,$user),$delim);

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
   my ($txt,$delim) = @_;
   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (FIRST) EXPECTS 1 or 2 ARGUMENTS";
   }

   if($delim eq undef || $delim eq " ") {
      $txt =~ s/^\s+|\s+$//g;
      $txt =~ s/\s+/ /g;
      $delim = " ";
   }
   my $loc = index(evaluate($txt,$user),$delim);

   if($loc == -1) {
      return $txt;
   } else {
      my $result = substr($txt,0,$loc);
      $result =~ s/^\s+//g;
      return $result;
   }
}

sub fun_before
{
   if($#_ != 0 && $#_ != 1) {
      return "#-1 Function (BEFORE) EXPECTS 1 or 2 ARGUMENTS";
   }
 
   my $loc = index(@_[0],@_[1]);

   if($loc == -1) {
      return undef;
   } else {
      my $result = substr(@_[0],0,$loc);
      $result =~ s/\s+$//;
      return $result;
   }
}


sub fun_loadavg
{
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
   return time();
}

#
# fun_div
#    Divide a number
#
sub fun_div
{
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
   my $result = 0;

   return "#-1 Add requires at least one argument" if $#_ < 0;

   for my $i (0 .. $#_) {
      $result += @_[$i];
   }
   return $result;
}

sub fun_sub
{
   my $result = @_[0];

   return "#-1 Sub requires at least one argument" if $#_ < 0;

   for my $i (1 .. $#_) {
      $result -= @_[$i];
   }
   return $result;
}

sub fun_de
{
   decode_entities(@_[0]);
}

sub fun_edit
{
   my ($txt,$from,$to) = @_;

   good_args($#_,3) ||
      return "#-1 FUNCTION (EDIT) EXPECTS 3 ARGUMENTS";

   $from =~ s/(.)/\\\1/g;
   $txt =~ s/$from/$to/ig;
   return $txt;
}

sub fun_num
{
   good_args($#_,1) ||
      return "#-1 FUNCTION (NUM) EXPECTS 1 ARGUMENT";

   my $result = locate_object($user,$_[0]);
 
   if($result eq undef) {
      return "#-1";
   } else {
      return "#$$result{obj_id}";
   }
}

sub fun_name
{
   good_args($#_,1) ||
      return "#-1 FUNCTION (NAME) EXPECTS 1 ARGUMENT";

   my $result = locate_object($user,$_[0]);
 
   if($result eq undef) {
      return "#-1";
   } else {
      return $$result{obj_name};
   }
}

sub fun_type
{
   good_args($#_,1) ||
      return "#-1 FUNCTION (TYPE) EXPECTS 1 ARGUMENT";

   my $obj = locate_object($user,$_[0]);

   return one_val("select fde_name value " . 
                     "  from object obj, " .
                     "       flag flg,  " .
                     "       flag_definition fde " .
                     " where obj.obj_id = flg.obj_id " .
                     "   and flg.fde_flag_id = fde.fde_flag_id " .
                     "   and fde.fde_name in " .
                     "          ('PLAYER','OBJECT','ROOM','EXIT') ".
                     "   and obj.obj_id = ?",
                     $$obj{obj_id}
                    );
}

sub fun_u
{
   my $txt = shift;
   my ($obj,$attr);

   my $prev = get_digit_variables($prog);                   # save %0 .. %9
   set_digit_variables(undef,@_);              # update to new values

   if($txt =~ /\//) {                    # input in object/attribute format?
      ($obj,$attr) = (locate_object($$prog{user},$`,"LOCAL"),$');
   } else {                                  # nope, just contains attribute
      ($obj,$attr) = ($$prog{user},$txt);
   }
   my $foo = $$obj{obj_name};

   if($obj eq undef) {
      return "#-1 Unknown object";
   } elsif(!controls($$prog{user},$obj)) {
      return "#-1 PerMISSion Denied";
   }
   my $data = get($obj,$attr);
   $data =~ s/^\s+|\s+$//gm;
   $data =~ s/\n|\r//g;

   my $result = evaluate($data,$obj);
   set_digit_variables(undef,$prev);                       # restore %0 .. %9
   return $result;
}


sub fun_get
{
   my $txt = $_[0];
   my ($obj,$atr);

   if($txt =~ /\//) {
      ($obj,$atr) = ($`,$');
   } else {
      ($obj,$atr) = ($txt,@_[0]);
   }

   my $target = locate_object($user,evaluate($obj,$user),"LOCAL");

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!controls($user,$target)) {
      return "#-1 Permission Denied";
   }
   return get($target,$atr);
}


sub fun_v
{
   return get($user,$_[0]);
}

sub fun_setq
{
   my ($register,$value) = @_;

   good_args($#_,2) ||
      return "#-1 FUNCTION (SETQ) EXPECTS 2 ARGUEMENTS";

   $register =~ s/^\s+|\s+$//g;
   $value =~ s/^\s+|\s+$//g;

   @{$$prog{var}}{"setq_$register"} = evaluate($value,$$prog{user});
   return undef;
}

sub fun_r
{
   my ($register) = @_;

   good_args($#_,1) ||
      return "#-1 FUNCTION (R) EXPECTS 1 ARGUEMENTS";

   $register =~ s/^\s+|\s+$//g;
   
   if(defined @{$$prog{var}}{"setq_$register"}) {
      return @{$$prog{var}}{"setq_$register"};
   } else {
      return undef;
   }
}

sub fun_extract
{
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
   my ($list,$words,$delim) = @_;
   my (%remove, @result);

   good_args($#_,2,3) ||
      return "#-1 FUNCTION (REMOVE) EXPECTS 2 OR 3 ARGUEMENTS";

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

sub fun_ljust
{
   if(@_[1] =~ /^\s*$/) {
      return @_[0];
   } elsif(@_[1] !~ /^\s*(\d+)\s*$/) {
      return "#-1 Ljust expects a numeric value for the second argument";
   } else {
      return sprintf("%-*s",@_[1],@_[0]);
   }
}

sub fun_rjust
{
   my ($text,$size) = @_;

   if($size =~ /^\s*$/) {
      return @_[0];
   } elsif($size !~ /^\s*(\d+)\s*$/) {
      return "#-1 Rjust expects a numeric value for the second argument";
   } else {
      $text = substr($text,0,$size);
      return  $text . (" " x ($size - length($text)));
   }
}

sub fun_strlen
{
#    return length(evaluate(shift));
    return length(shift);
}

sub fun_sql
{
    my (@txt) = @_;

    my $sql = join(' ',@txt);
    $sql =~ s/\_/%/g;
#    printf("SQL: $sql\n");
    table($sql);
}

#
# fun_substr
#   substring function
#
sub fun_substr
{
   my ($txt,$start,$end) = @_; 

   if(!($#_ == 2 || $#_ == 3)) {
      return "#-1 Substr expects 2 - 3 arguments but found " . ($#_+1);
   } elsif($start !~ /^\s*\d+\s*/) {
      return "#-1 Substr expects a numeric value for second argument";
   } elsif($end !~ /^\s*\d+\s*/) {
      return "#-1 Substr expects a numeric value for third argument";
   }

   return substr($txt,$start,$end);
}

#
# has_socket
#    Check the database to see if the named socket exists or not
#    
sub has_socket
{
   my $txt = shift;

   my $con = one_val("select count(*) value " .
                     "  from socket " .
                     " where upper(sck_tag) = upper(trim(?))",
                     $txt
                    );
   return ($con == 0) ? 0 : 1;
}

sub socket_status
{
   my ($tag) = @_;

   if(!has_socket($tag)) {
      return "#-1 Connection Closed",
   } else {
      return "#-1 NO Data Found",
   }
}

#
# fun_input
#    Check to see if there is any input in the specified input buffer
#    variable. If there is, return the data or return #-1 No Data Found
# 
sub fun_input
{
    my $txt = shift;

    @info{io} = {} if !defined @info{io};
    my $input = @info{io};

    if($txt =~ /^\s*([^ ]+)\s*$/) {
       return socket_status(uc($1)) if(!defined $$input{uc($1)});

       my $data = $$input{uc($1)};

       if(!defined $$data{buffer} || $#{$$data{buffer}} == -1) {
          return socket_status(uc($1));
       } else {
          my $buffer = $$data{buffer};
          return shift(@$buffer);
       }
   } else {
       return "#-1 Usage: [input(<socket>)]";
   }
}

sub fun_flags
{
   if($#_ != 0) {
      return "#-1 flags expects an argument but found " . ($#_+1);
   } elsif(@_[0] =~ /^\s*#(\d+)\s*$/) {
      if(!valid_dbref($1)) {
         return "#-1 Object #$1 does not exist";
      } else {
         return flag_list($1);
      }
   } else {
      return "#-1 Flags expects an object dbref (example: #1)";
   }
}

#
# fun_space
#
sub fun_space
{
    my ($count) = @_;

    if($count =~ /^\s*$/) {
       $count = 1;
    } elsif(!($#_ == -1 or $#_ == 0)) {
       return "#-1 Space expects 0 or 1 numeric value but found " . ($#_ +1);
    } elsif($count !~ /^\s*\d+\s*/) {
       return "#-1 Space expects a numeric value";
    }
    return " " x $count ;
}

# [repeat(^'+.\,.+',6)]

#
# fun_repeat
#
sub fun_repeat
{
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
    if($#_ != -1 && $#_ != 0) {
       return "#-1 Time expects no arguments but found " . ($#_ +1);
    }
    return scalar localtime();
}

#
# fun_cat
#   Concatination function
#
sub fun_cat
{
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
   return $txt;
}

#
# fun_lattr
#    Return a list of attributes on an object or the enactor.
#
sub fun_lattr
{
   my $txt = shift;
   my ($obj,$atr,@list);

   if($txt =~ /\s*\/\s*/) {                               # input has a slash 
      ($obj,$atr) = ($`,$');                          # designating a pattern
   } else {
      ($obj,$atr) = ($txt ,"*");                   # no slash, match anything
   }

   $txt = "me" if $txt eq undef;                # default to searching enactor
   my $target = locate_object($user,$obj,"LOCAL");
   return "#-1 Unknown object" if $target eq undef;  # oops, can't find object

   for my $attr (@{sql($db,                     # query db for attribute names
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
   return join(' ',@list);
}

sub fun_iter
{
   my @result;

#   printf("ITER: '%s' -> '%s'\n",@_[0],@_[1]);
   for my $item (split(/ /,evaluate(@_[0]))) {
       my $new = @_[1];
       $new =~ s/##/$item/g;
#       printf("   '@_[2]' -> '$new'\n");
       push(@result,evaluate($new,$user));
   }

   return join((@_[2] eq undef) ? " " : @_[2],@result);
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
   if(!defined @fun{lc($_[0])}) {
      printf("undefined function '%s'\n",@_[0]);
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
   my ($fun,$txt,$type,$target) = @_;

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
            @array[$i] = evaluate(@array[$i],$target);
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
   my ($last,$i,$esc,@stack,$escaped,@depth) = (0,-1,-1);
#   my %pair = ( '(' => ')', '{' => '}', '"' => '"',);
   my %pair = ( '(' => ')', '{' => '}');
   $delim = "," if $delim eq undef;

   $txt = $1 if($type == 3 && $txt =~ /^\s*{(.*)}\s*$/);
#   my @array = grep {!/^$/} split(/([\\\[\]\{\}\(\)$delim"])/,$txt);
   my @array = grep {!/^$/} split(/([\\\[\]\{\}\(\)$delim])/,$txt);
   while(++$i <= $#array) {

      if($esc > 0 && @array[$i] ne "\\") { # end of escaped characters
         for my $y ($esc .. ($i-1)) {
            if($y == $i) {
               @array[$y] = "\\" x (($i - $esc) / 2);
            } else {
               @array[$y] = undef;
            }
         }
         $escaped = ($esc % 2 == 0) ? 0 : 1;
         $esc = -1;
      }

      if(@array[$i] eq undef || length(@array[$i]) > 1 || $escaped) {
         $escaped = 0;
      } elsif(@array[$i] eq "\\") {
         $esc = $i if($esc == -1);
      } elsif($#depth >=0 && @{@depth[$#depth]}{ch} eq @array[$i]) {
         pop(@depth);                                      # found pair match
      } elsif(defined @pair{@array[$i]}) {
         push(@depth,{  ch    => @pair{@array[$i]},      # found special char
                        last  => $last,
                        i     => $i,
                        stack => $#stack+1
                     });
      } elsif($#depth == -1 && @array[$i] eq $delim) { # delim at right depth
         push(@stack,join('',@array[$last .. ($i-1)]));
         $last = $i+1;
      } elsif($type <= 2 && $#depth == -1 && @array[$i] eq ")") { # func end
         push(@stack,join('',@array[$last .. ($i-1)]));
         $last = $i+1;
         $i = $#array;
      }

      if($i > $#array && $#depth > -1) {                      # missing match
         my $hash = pop(@depth);
         delete @stack[$$hash{stack} .. $#stack];      # rollback to starting
         $last = $$hash{last};                                    # character
         $i = $$hash{i} + 1;
      }
   }

   if($type == 3) {
      push(@stack,join('',@array[$last .. $#array]));
      return @stack;
   } else { 
      unshift(@stack,join('',@array[$last .. $#array]));
      return ($#depth != -1) ? undef : @stack;
   }
}


#
# evaluate_string
#    Take a string and parse/run any functions in the string.
#
sub evaluate_string
{
   my ($txt,$target) = @_;
   my $out;

   #
   # handle string containing a single non []'ed function
   #
   if($txt =~ /^([a-zA-Z_]+)\((.*)\)$/) {
      my $fun = $1;
      my $result = parse_function($fun,"$2)",2,$target);
      if($result ne undef) {
         shift(@$result);
         if(fun_lookup($fun) eq "huh") {
            printf("undefined function: '%s'\n",$fun);
         }
         my $r=&{@fun{fun_lookup($fun)}}(@$result);
#         printf("Fun: %s(%s)\n",$fun,join(',',@$result));
#         printf("   Result: '%s'\n",$r);
#         return $r;
         return &{@fun{fun_lookup($fun)}}(@$result);
      }
   }

   if($txt =~ /^\s*{\s*(.*)\s*}\s*$/) {                # mush strips these
      $txt = $1;
   }

   #
   # pick functions out of string when enclosed in []'s 
   #
   while($txt =~ /([\\]*)\[([a-zA-Z_]+)\(/) {
      my ($esc,$fun,$before,$after) = ($1,$2,$`,$');
      $out .= evaluate_substitutions($before);
      $out .= "\\" x (length($esc) / 2);

      if(length($esc) % 2 == 0) {
         my $result = parse_function($fun,$',1,$target);

         if($result eq undef) {
            $txt = $after;
            $out .= "[" . $1 . "(";
         } else {                                    # good function, run it
            $txt = shift(@$result);
            if(fun_lookup($fun) eq "huh") {
               printf("undefined function: '%s'\n",$fun);
            }
            my $r = &{@fun{fun_lookup($fun)}}(@$result);
#            printf("FUN: %s(%s)\n",$fun,join(',',@$result));
#            printf("   Result: '%s'\n",$r);
            $out .= $r;
         }
      } else {                                # start of function escaped out
         $out .= "[" . $fun . "(";
         $txt = $after;
      }
   }

   if($txt ne undef) {
      return $out . evaluate_substitutions($txt);   # return results + leftovers
   } else {
      return $out;
   }
}
