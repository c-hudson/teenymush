#!/usr/bin/perl
#
# mt_lock.pl
#    Evaluation of a string based lock to let people use/not use things.
#

use strict;

sub lock_error
{
   my ($hash,$err) = @_;

   printf("LOCK_ERROR: called '%s'\n",$err);
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
      $$lock{error} = 1;
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
   my ($self,$obj,$lock,$item) = @_;
   my ($not, $target,$result);

   return if(defined $$lock{error} && $$lock{error});      # prev parse error

   if($item =~ /^\s*([\|\&]{1})\s*$/) {                           # handle op
      if(defined $$lock{op}) {                                 # too many ops
         return lock_error($lock,"Too many operators ($$lock{op} and $1)");
      } else {
         $$lock{op} = $1;
      }
   } elsif($item =~ /^\s*\((.*)\)\s*/) {             # handle ()'s
      $result = lock_eval($self,$obj,$1);
      do_lock_compare($lock,$result);
   } elsif($item =~ /^\s*(!{0,1})\s*([^ ]+)\s*$/) {             # handle item
      $not = ($1 eq "!") ? 1 : 0;
      $target = locate_object($obj,$2,"LOCAL");

      if($target eq undef) {                             # verify item exists
         return lock_error($lock,"Target($2) does not exist.");
      } elsif(($not && $target ne $$self{obj_id}) ||  # handle item comparison
         (!$not && $target eq $$self{obj_id})) { 
         $result = 1;                                               # success
      } else {
         $result = 0;                                               # failure
      }

      do_lock_compare($lock,$result);
   } else {
      return lock_error($lock,"Invalid item '$item'");       # invalid item/op
   }

   return $$lock{result};
}

#
# lock_eval
#    This is the inital call to evaluating a lock.
#
sub lock_eval
{
    my ($self,$obj,$txt) = @_;
    my ($start,$depth) = (0,0);
    my $lock = {};

    my @list = split(/([\(\)&\|])/,$txt);
    for my $i (0 .. $#list) {
       if(@list[$i] eq "(") {
          $depth++;
       } elsif(@list[$i] eq ")") {
          $depth--;

          if($depth == 0) {
             lock_item_eval($self,$obj,$lock,join('',@list[$start .. $i]));
             $start = $i + 1;
          }
       } elsif($depth == 0 && 
               ( @list[$i] eq "&" ||
                 @list[$i] eq "|" ||
                 @list[$i] =~ /^\s*[^\(\)\s]/
               )
              ) {
          lock_item_eval($self,$obj,$lock,join('',@list[$start .. $i]));
          $start = $i + 1;
       }
    }
    return $$lock{result};
}

#
# lock_item_compile
#    Each item is a comparison against the object trying to pass throught the
#    lock 
#
sub lock_item_compile
{
   my ($self,$obj,$lock,$item) = @_;
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
      $result = lock_compile($self,$obj,$txt);

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

      $target = locate_object($obj,$txt,"LOCAL");
      
      if($target eq undef) {                             # verify item exists
         return lock_error($lock,"Target($obj) does not exist");
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
#    This is the inital call to evaluating a lock.
#
sub lock_compile
{
    my ($self,$obj,$txt) = @_;
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
             lock_item_compile($self,$obj,$lock,join('',@list[$start .. $i]));
             $start = $i + 1;
          }
       } elsif($depth == 0 && 
               ( @list[$i] eq "&" ||
                 @list[$i] eq "|" ||
                 @list[$i] =~ /^\s*[^\(\)\s]/
               )
              ) {
          lock_item_compile($self,$obj,$lock,join('',@list[$start .. $i]));
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
