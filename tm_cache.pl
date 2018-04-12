#!/usr/bin/perl
# 
# tm_cache
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
   my ($obj,$atr) = (obj(shift),shift);

   if(ref($obj) ne "HASH" || !defined $$obj{obj_id}) {
     return undef;
   } elsif(!incache_atrflag($obj,$atr,"CASE")) {
      my $val = one_val("select count(*) value " .
                        "  from attribute atr, " .
                        "       flag flg, " .
                        "       flag_definition fde " .
                        " where atr.obj_id = flg.obj_id ".
                        "   and fde.fde_flag_id = flg.fde_flag_id ".
                        "   and fde_name = 'CASE' ".
                        "   and fde_type = 2 ".
                        "   and atr_name = ? " .
                        "   and atr.atr_id = flg.atr_id " .
                        "   and atr.obj_id = ? ",
                        $atr,
                        $$obj{obj_id}
                       );
      set_cache_atrflag($obj,$atr,"CASE",$val);
   }
   return cache_atrflag($obj,$atr,"CASE");
}

sub latr_regexp
{
   my ($obj,$type) = @_;
   my @result;

   if(!incache($obj,"latr_regexp_$type")) {
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
                         atr_name   => $$atr{atr_name}
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

   if(!incache($object,"lcon")) {
       my @list;
       for my $obj (@{sql($db,
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

   if(!incache($object,"lexits")) {
       my @list;
       for my $obj (@{sql($db,
                          "select con.obj_id " .
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

   if(!incache($owner,"obj_money")) {
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
   my $target = obj(shift);

   if(!incache($target,"obj_name")) {
      my $val = one_val("select obj_name value ".
                        "  from object ".
                        " where obj_id = ? ",
                        $$target{obj_id}
                       );
      return "[<UNKNOWN>]" if($val eq undef);
      set_cache($target,"obj_name",$val);
   }
   return cache($target,"obj_name");
}


sub flag_list
{
   my ($obj,$flag) = (obj($_[0]),uc($_[1]));
   $flag = 0 if !$flag;

   if(!incache($obj,"FLAG_LIST_$flag")) {
      my (@list,$array);
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
   my $object = obj(shift);
   my $owner;

   if(!incache($$object{obj_id},"OWNER")) {
      if(hasflag($$object{obj_id},"PLAYER")) {
         $owner = $$object{obj_id};
      } else {
         $owner = one_val("select obj_owner value" .
                          "  from object" .
                          " where obj_id = ?",
                          $$object{obj_id}
                         );
      }
      set_cache($$object{obj_id},"OWNER",$owner);
   }
   return obj(cache($$object{obj_id},"OWNER"));
}

#
# hasflag
#    Return if an object has a flag or not
#
sub hasflag
{
   my ($target,$flag) = (obj($_[0]),$_[1]);
   my $val;


   if($flag eq "CONNECTED") {                  # not in db, no need to cache
      return (defined @connected_user{$$target{obj_id}}) ? 1 : 0;
   } elsif(!incache($target,"FLAG_$flag")) {
      if($flag eq "WIZARD") {
         my $owner = owner_id($target);
         $val = one_val($db,"select if(count(*) > 0,1,0) value " .  
                            "  from flag flg, flag_definition fde " .  
                            " where flg.fde_flag_id = fde.fde_flag_id " .
                            "   and atr_id is null ".
                            "   and fde_type = 1 " .
                            "   and obj_id = ? " .
                            "   and fde_name = ? ",
                            $owner,
                            uc($flag));
         # let owner cache object know its value was used for this object
         $cache{$owner}->{FLAG_DEPENDANCY}->{$$target{obj_id}} = 1;
      } else {
         $val = one_val($db,"select if(count(*) > 0,1,0) value " .
                            "  from flag flg, flag_definition fde " .
                            " where flg.fde_flag_id = fde.fde_flag_id " .
                            "   and atr_id is null ".
                            "   and fde_type = 1 " .
                            "   and obj_id = ? " .
                            "   and fde_name = ? ",
                            $$target{obj_id},
                            uc($flag));
      }
      set_cache($target,"FLAG_$flag",$val);
   }
   return cache($target,"FLAG_$flag");
}

sub dest
{
    my $obj = obj(shift);

   if(!incache($obj,"con_dest_id")) {
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

   if(!incache($obj,"home")) {
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

   if(!incache($obj,"con_source_id")) {
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
