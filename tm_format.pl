#!/usr/bin/perl
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
my %info;

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
               push(@stack,$buf . $delim);
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
       $out .= wrap(" " x $depth," " x $depth,$txt) . "\n";
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
       $out .= dprint($depth,"%s %s",$cmd,trim($first));
    }


    $out .= dprint($depth+3,"%s",$second);               # second subsegment

    # show the rest of the segments at alternating depths
    for my $i (0 .. $#list) {                         # remaining segments
       my $indent = ($i % 2 == 0) ? 6 : 3;

       if($depth + $indent + length(@list[$i]) < $max ||
          @list[$i] =~ /^\s*{.*}\s*;{0,1}\s*$/) {
          $out .= dprint($depth + $indent,"%s",@list[$i]);
       } else {
          $out .= pretty($depth+6,@list[$i]);
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
         $out .= function_print($depth,$val);
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
   if(length("$left$function($arguments)$right") - length(@array[0]) < $max) {
      if($mright ne undef) {                 # does the function end right?
         if(@array[0] =~ /^\s*$mright/) {
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

   for my $i (2 .. $#array) {                      # show function arguments
      $out .= noret(function_print($depth+$len-4,@array[$i])) ."\n";
   }

   $out .= dprint($depth,"%s",")$right");                    # show ending )

   if($mright ne undef) {
      if(@array[0] =~ /^\s*$mright/) {
          return ($out,$',0);
      } else {
          return (undef,undef,2);
      }
   } elsif(@array[0] =~ /^\s*$/ || @array[0] =~ /\s*(,)/) {
      return ($out,@array[0].$1,0);
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
      my ($fmt,$left,$err) = function_print_segment($depth+3,
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
          my ($fmt,$left,$err) = function_print_segment($depth+3,
                                                     '[',
                                                     $unmod,
                                                     $after,
                                                     ']',
                                                     1
                                                    );
          if($err) {
             $out .= "[$unmod(";
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

   return $out . $txt;

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
# 
# 
# printf("%s\n",pretty(0,$code));
