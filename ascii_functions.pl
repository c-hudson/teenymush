#!/usr/bin/perl

use strict;
use HTML::HTML5::Entities;

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
   extract   => sub { return &fun_extract(@_);                          },
   get       => sub { return &fun_get(@_);                              },
   edit      => sub { return &fun_edit(@_);                             },
   decode_entities => sub { return &fun_de(@_);                         },
);

sub fun_de
{
   decode_entities(@_[0]);
}

sub fun_edit
{
   my ($txt,$from,$to) = @_;

   if($txt eq undef || $from eq undef) {
      return;
   }

   $txt =~ s/$from/$to/i;
   return $txt;
}

sub fun_get
{
   my $txt = shift;
   my ($obj,$atr);

   if($txt =~ /\//) {
      ($obj,$atr) = ($`,$');
   } else {
      ($obj,$atr) = ($txt,@_[0]);
   }

   my $target = locate_object($user,$obj,"LOCAL");

   if($target eq undef ) {
      return "#-1 Unknown object";
   } elsif(!controls($user,$target)) {
      return "#-1 Permission Denied";
   }

   return get($target,$atr);
}


sub fun_extract
{
   my ($txt,$first,$length,$idelim,$odelim) = @_;
   my (@list,$last);
   $idelim = " " if($idelim eq undef);
   $odelim = " " if($odelim eq undef);
   $first--;

   if($first !~ /^\s*\d+\s*$/) {
      return "#-1 Expected numberic value for second argument";
   } elsif($length !~ /^\s*\d+\s*$/) {
      return "#-1 Expected numberic value for third argument";
   } 
   my $text = evaluate($txt);
   $text =~ s/\r//g;
   $text =~ s/\n/<RETURN>/g;
   @list = split(/$idelim/,$text);
   if($first + $length > $#list) {
      $last = $#list;
   } else {
      $last = $first + $length;
   }

   return join($odelim,@list[$first .. $last]);
}

sub fun_ljust
{
   if(@_[1] =~ /^\s*$/) {
      return @_[0];
   } elsif(@_[1] =~ /^\s*(\d+)\s*$/) {
      return sprintf("%-*s",@_[1],evaluate(@_[0]));
   } else {
      return "#-1 Ljust expects a numeric value for the second argument";
   }
}

sub fun_strlen
{
    return length(evaluate(shift));
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

   for my $item (split(/ /,evaluate(@_[0]))) {
       my $new = @_[1];
       $new =~ s/##/$item/g;
       push(@result,evaluate($new));
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
   my ($txt,$type,$target) = @_;

   my @array = balanced_split($txt,",",$type);
   return undef if($#array == -1);

   # type 1: expect ending ]
   # type 2: expect ending ) and nothing else
   if(($type == 1 && @array[0] =~ /^\s*]/) ||
      ($type == 2 && @array[0] =~ /^\s*$/)) {
      
      @array[0] = $';                              # strip ending ] if there
      for my $i (1 .. $#array) {                            # eval arguments
         # evaluate args before passing them to function
         @array[$i] = evaluate_substitutions(@array[$i],$target);
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
   my ($txt,$delim,$type) = @_;
   my ($last,$i,@stack,@depth) = (0,-1);
   my %pair = ( '(' => ')', '{' => '}', '"' => '"',);
   $delim = "," if $delim eq undef;

   $txt = $1 if($type == 3 && $txt =~ /^\s*{(.*)}\s*$/);
   my @array = grep {!/^$/} split(/([\\\[\]\{\}\(\)$delim"])/,$txt);
   while(++$i <= $#array) {
      if(@array[$i] eq undef || length(@array[$i]) > 1 || escaped(\@array,$i)) {
         # skippable
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
   } else { 
      unshift(@stack,join('',@array[$last .. $#array]));
   }
   return ($#depth != -1) ? undef : @stack;
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
      my $result = parse_function("$2)",2,$target);
      if($result ne undef) {
         return &{@fun{fun_lookup($1)}}(@$result[1 .. $#$result]);
      }
   }

   #
   # pick functions out of string when enclosed in []'s 
   #
   while($txt =~ /\[([a-zA-Z_]+)\(/) {
      $out .= evaluate_substitutions($`);
      my $result = parse_function($',1,$target);

      if($result eq undef) {
         $txt = $';
         $out .= "[" . $1 . "(";
      } else {                                       # good function, run it
         $txt = shift(@$result);
         $out .= &{@fun{fun_lookup($1)}}(@$result);
      }
   }
   return $out . evaluate_substitutions($txt);   # return results + leftovers
}
