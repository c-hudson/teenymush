#!/usr/bin/perl

use strict;
use HTML::HTML5::Entities;
use Carp;
use Text::Glob qw( match_glob glob_to_regex );
use Scalar::Util qw(looks_like_number);
use Math::BigInt;

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
   quota     => sub { return &fun_quota_left(@_);                       },
   sql       => sub { return &fun_sql(@_);                              },
   input     => sub { return &fun_input(@_);                            },
   has_input => sub { return &fun_has_input(@_);                        },
   strlen    => sub { return &fun_strlen(@_);                           },
   lattr     => sub { return &fun_lattr(@_);                            },
   iter      => sub { return &fun_iter(@_);                             },
   huh       => sub { return "#-1 Undefined function";                  },
   ljust     => sub { return &fun_ljust(@_);                            },
   rjust     => sub { return &fun_rjust(@_);                            },
   loc       => sub { return &fun_loc(@_);                              },
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
   inuse     => sub { return &inuse_player_name(@_);                    },
   web       => sub { return &fun_web(@_);                              },
   run       => sub { return &fun_run(@_);                              },
   graph     => sub { return &fun_graph(@_);                            },
   lexits    => sub { return &fun_lexits(@_);                           },
   home      => sub { return &fun_home(@_);                             },
   latr      => sub { return &fun_latr(@_); },
   decode_entities => sub { return &fun_de(@_);                         },
);

sub fun_latr
{
   my ($self,$prog,$obj,$atr) = @_;

   return atr_case(obj($obj),$atr);
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

   my $target = locate_object($self,$prog,$txt);
   return "#-1 NOT FOUND" if($target eq undef);

   for my $rec (@{sql("select con.obj_id " .
                      "  from content con, " .
                      "       flag flg, " .
                      "       flag_definition fde " .
                      " where con.obj_id = flg.obj_id " .
                      "   and flg.fde_flag_id = fde.fde_flag_id " .
                      "   and fde_name = 'EXIT' ".
                      "   and con.con_source_id = ?",
                      $$target{obj_id}
               )}) {
       push(@result,"#" . $$rec{obj_id});
   }
   return join(' ',@result);
}

sub fun_graph
{
   my ($self,$prog,$txt,$x,$y) = @_;

   if($txt =~ /^\s*(mush|web)\s*$/i) {
      return graph_connected(lc($1),$x,$y);
   } else {
      return "Specify Connected";
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
      return;                                                 # only spaces
   }

   if($$prog{hint} eq "WEB" || $$prog{hint} eq "WEBSOCK") {
      if(defined $$prog{from} && $$prog{fun} eq "ATTR") {
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
      run_internal($hash,$cmd,$command,$prog,$arg);
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
         return run_internal($hash,$match,$command,$prog,$arg);
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

   my $name = @info{"conf.master"};

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

   for my $i (split(/,/,@_[0])) {
       $i =~ s/^\s+|\s+$//g;
       @list{$i} = 1;
   }

   for my $i (split(/,/,@_[1])) {
      $i =~ s/^\s+|\s+$//g;
      @out{$i} = 1 if(defined @list{$i});
  }
  return join(' ',sort keys %out);
}


sub fun_lwho
{
   my ($self,$prog) = (shift,shift);
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
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
     return "#-1 FUNCTION (LCSTR) EXPECTS 1 ARGUMENT ($#_)";

    return lc(shift);
}

sub fun_home
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,0,1) ||
      return "#-1 FUNCTION (HOME) EXPECT 0 OR 1 ARGUMENT";

   my $target = locate_object($self,$prog,shift);
   return "#-1 NOT FOUND" if($target eq undef);

   return "#" . home($target);
}

#
# lowercase the provided string
#
sub fun_ucstr
{
   my ($self,$prog) = (shift,shift);

    good_args($#_,1) ||
      return "#-1 FUNCTION (UCSTR) EXPECTS 1 ARGUMENT ($#_)";

    return uc(shift);
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

   my $target = locate_object($self,$prog,$txt);

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

   return 0 if($_[1] =~ /^s*(nospoof|haven|dark|royal|royalty)\s*$/i);

   my $target = locate_object($self,$prog,$_[0]);
 
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

   return looks_like_number($_[0]) ? 1 : 0;
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

   return scalar(safe_split($txt,($delim eq undef) ? " " : $delim));
}

sub fun_match
{
   my ($self,$prog) = (shift,shift);

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
   my ($self,$prog) = (shift,shift);

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
   my ($self,$prog) = (shift,shift);

   my $first = evaluate($self,$prog,shift);

   while($#_ >= 0) {
      if($#_ >= 1) {
         my $txt = evaluate($self,$prog,shift);
         $txt =~ s/\*/\(.*\)/g;
         $txt =~ s/^\s+|\s+$//g;

         if($first =~ /^\s*$txt\s*$/i) {
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

sub fun_de
{
   my ($self,$prog) = (shift,shift);

   decode_entities(@_[0]);
}

sub fun_edit
{
   my ($self,$prog) = (shift,shift);

   my ($txt,$from,$to) = @_;

   good_args($#_,3) ||
      return "#-1 FUNCTION (EDIT) EXPECTS 3 ARGUMENTS";

   $from = quotemeta($from);
   $to= quotemeta($to);
   $txt =~ s/$from/$to/ig;
   return $txt;
}

sub fun_num
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NUM) EXPECTS 1 ARGUMENT";

   my $result = locate_object($self,$prog,$_[0]);
 
   if($result eq undef) {
      return "#-1";
   } else {
      return "#$$result{obj_id}";
   }
}

sub fun_name
{
   my ($self,$prog) = (shift,shift);

   good_args($#_,1) ||
      return "#-1 FUNCTION (NAME) EXPECTS 1 ARGUMENT";

   my $result = locate_object($self,$prog,$_[0]);
 
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

   my $obj = locate_object($self,$prog,$_[0]);

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
   my ($self,$prog) = (shift,shift);

   my $txt = shift;
   my ($obj,$attr);

   my $prev = get_digit_variables($prog);                   # save %0 .. %9
   set_digit_variables($self,$prog,@_);              # update to new values

   if($txt =~ /\//) {                    # input in object/attribute format?
      ($obj,$attr) = (locate_object($self,$prog,$`,"LOCAL"),$');
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

   my $target = locate_object($self,$prog,evaluate($self,$prog,$obj),"LOCAL");

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!controls($self,$target)) {
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
   my ($self,$prog) = (shift,shift);

   return get($self,$_[0]);
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

sub fun_ljust
{
   my ($self,$prog) = (shift,shift);

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
   my ($self,$prog) = (shift,shift);

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
   my ($self,$prog) = (shift,shift);

#    return length(evaluate(shift));
    return length(evaluate($self,$prog,shift));
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

   return substr($txt,$start,$end);
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
   my ($self,$prog,$txt) = @_;

    if($txt =~ /^\s*([^ ]+)\s*$/) {                           # strip spaces
       $txt = $1;
    } else {
       return "#-1 Usage: [input(<socket>)]";
    }

    if(!defined @info{io} || !defined @{@info{io}}{uc($1)}) {    # is socket
       return "#-1 Unknown socket $txt";                           # defined
    }

    my $input = @{@info{io}}{uc($1)};                      # shortcut 2 data

    # check if there is any buffered data and return it.
    # if not, the socket could have closed
    if(!defined $$input{buffer} || $#{$$input{buffer}} == -1) {
       if(get_socket($1) ne undef) {
          return "#-1 No data found";                  # wait for more data?
       } else {
          return "#-1 Connection closed";                    # socket closed
       }
    } else {
       if($#{$$input{buffer}} > 0) {           # give hint more input pending
          my $cmd = $$prog{cmd_last};
          $$prog{pending} = 1;
       }
       my $data = shift(@{$$input{buffer}});             # return buffered data
       $data =~ s/\\/\\\\/g;
       $data =~ s/\//\\\//g;
       $data =~ s/’/\\\'/g;
       $data =~ s/―/\\\-/g;
       $data =~ s/`/\\`/g;
       $data =~ s/‘/\\`/g;
       $data =~ s/‚/\\,/g;
       $data =~ s/⚡/`/g;
       $data =~ s/↑ /N /g;
       $data =~ s/↓ /S /g;
       $data =~ s/↘ /SE /g;
       $data =~ s/→ /E /g;
       return $data;
    }
}

sub fun_flags
{
   my ($self,$prog,$txt) = @_;

   # verify arguments
   return "#-1" if($txt =~ /^\s*$/);

   # find object
   my $target = locate_object($self,$prog,$txt,"LOCAL");
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
    return scalar localtime();
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
      ($obj,$atr) = ($`,$');                          # designating a pattern
   } elsif($txt =~ /^\s*$/) {                                      # no input
      return "#-1 FUNCTION (LATTR) EXPECTS 1 ARGUMENTS";
   } else {
      ($obj,$atr) = ("me",$txt);                         # only attr provided
   }

   my $target = locate_object($self,$prog,$obj,"LOCAL");
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
         $buf .= substr($txt,++$i,1);
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
   return;
   if($args !~ /(v|u|get|r)\(/i && $fun !~ /^(v|u|get|r)$/) {
      printf("think [switch(%s(%s),%s,,{WRONG %s(%s) -> %s})]\n",
          $fun,$args,$result,$fun,$args,$result);
   }
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
   if($txt =~ /^\s*([a-zA-Z_]+)\((.*)\)\s*$/s) {
      my $fun = fun_lookup($self,$prog,$1,$txt);
      my $result = parse_function($self,$prog,$fun,"$2)",2);
      if($result ne undef) {
         shift(@$result);
         printf("undefined function: '%s'\n",$fun) if($fun eq "huh");
         my $r=&{@fun{$fun}}($self,$prog,@$result);
         script($fun,join(',',@$result),$r);

         return $r;
      }
   }

   if($txt =~ /^\s*{\s*(.*)\s*}\s*$/) {                # mush strips these
      $txt = $1;
   }

   #
   # pick functions out of string when enclosed in []'s 
   #
   while($txt =~ /([\\]*)\[([a-zA-Z_]+)\(/s) {
      my ($esc,$before,$after,$unmod) = ($1,$`,$',$2);
      my $fun = fun_lookup($self,$prog,$unmod,$txt);
      $out .= evaluate_substitutions($self,$prog,$before);
      $out .= "\\" x (length($esc) / 2);

      if(length($esc) % 2 == 0) {
         my $result = parse_function($self,$prog,$fun,$',1);

         if($result eq undef) {
            $txt = $after;
            $out .= "[$fun(";
         } else {                                    # good function, run it
            $txt = shift(@$result);
            my $r = &{@fun{$fun}}($self,$prog,@$result);
            script($fun,join(',',@$result),$r);
            $out .= $r;
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
