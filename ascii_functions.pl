#!/usr/bin/perl

use strict;

my %fun = 
(
   substr => sub { return &fun_substr(@_);                                 },
   cat    => sub { return &fun_cat(@_);                                    },
   space  => sub { return &fun_space(@_);                                  },
   repeat => sub { return &fun_repeat(@_);                                 },
   time   => sub { return &fun_time(@_);                                   },
   flags  => sub { return &fun_flags(@_);                                  },
   quota  => sub { return quota_left($$user{obj_id})                       },
   sql    => sub { return table(@_);                                       },
);

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

    if($#_ != 0) {
       return "#-1 Space expects 2 arguments but found " . ($#_ +1);
    } elsif($count !~ /^\s*\d+\s*/) {
       return "#-1 Space expects a numeric value";
    }
    return " " x $count ;
}

#
# fun_space
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
    if($#_ != -1) {
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


#
# exec_function
#    is_function has succesfully parsed the function, now the function
#    needs to be "run". Variables are evalutated before being passed to
#    the function (this sounds good, is it?)
#
sub exec_function
{
   my ($name,$hash) = @_;
   my $out;

   if(defined @fun{$name}) {
      my $stack = $$hash{stack};
      for my $i (0 .. $#$stack) {
         $$stack[$i] = $$stack[$i];
      }
      return &{@fun{$name}}(@{$$hash{stack}});
   } else {
      return "#-1 Undefined Function";
   }
}

sub cleanup_stack
{
   my $data = shift;

   my $stack = $$data{stack};
   for my $i (reverse 0 .. $#$stack) {
      if($$stack[$i] =~ /^\s*$/) {
         delete @$stack[$i];
      } else {
         return;
      }
   }
}

#
# is_function
#
#    This function tears apart the arguments to a function to determine
#    if it is a valid function or not. If any errors occure, there was a
#    parse error that signals this is not a valid function.
#
sub is_function
{
   my ($data,$txt,$end,$depth) = @_;
   my ($seg,$rest, $function, %result);
   $data = {} if(ref($data) ne "HASH");

   delete @$data{keys %$data};
   @$data{stack} = [];
  
   while($txt) {
      if($txt =~ /^\s*([a-zA-Z_]+)\(/ && is_function(\%result,$',1,$depth+1)) {
          push(@{$$data{stack}},exec_function($1,\%result));
          $txt = @result{txt};
          $function = 1;
      } elsif(!$end && ($txt =~ /^\s*"(.*?)(?<!(?<!\\)\\)"\s*(,|\)\s*])/ ||
         $txt =~ /^\s*(.*?)(?<!(?<!\\)\\)(,|\)\s*])/)) {
#         $txt =~ /^\s*([^,\)]*)\s*(,|\)\s*])/)) {
         ($seg,$txt) = ($1,$2 . $');
      } elsif($end && ($txt =~ /^\s*"(.*?)(?<!(?<!\\)\\)"\s*(,|\)\s*)/ ||
         $txt =~ /^\s*(.*?)(?<!(?<!\\)\\)(,|\)\s*)/)) {
#         $txt =~ /^\s*([^,\)]*)\s*(,|\)\s*)/)) {
         ($seg,$txt) = ($1,$2 . $');
      } else {                                             # parse error
         return 0;
      }

      if((!$end && $txt =~ /^\s*\)\s*]/) ||
         ($end && $txt =~ /^\s*\)/)) {
         push(@{$$data{stack}},$seg);
         $$data{txt} = $';
         cleanup_stack($data);
         return 1;
      } elsif($txt =~ /\s*,\s*/) {
         $txt = $';
         push(@{$$data{stack}},$seg);
         $txt = $';
      } else {
         return 0;
      }
   }
}

#
# evaluate_string
#    Take a string and parse any functions or variables
#
sub evaluate_string
{
   my $txt = shift;
   my (%data,$out);

   while($txt =~ /\[([a-zA-Z_]+)\(/) {
      if(is_function(\%data,$',undef,1)) {
         $txt = @data{txt};
         $out .= $` . exec_function($1,\%data);
      } else {
         $out .= $` . "[" . $1 . "(";
         $txt = $';
      }
   }

   if($txt ne undef) {
      return $out . $txt;
   } else {
      return $out;
   }
}
