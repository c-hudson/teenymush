#!/usr/bin/perl
use strict;
use DBI;
use Carp;


$db = {} if(ref($db) ne "HASH");
$log = {} if(ref($log) ne "HASH");
# delete @$db{keys %$db};
# delete @$log{keys %$log};

#
# get_db_credentials
#    Load the database credentials from the tm_conf.dat file
#
sub get_db_credentials
{
   for my $line (split(/\n/,getfile("tm_config.dat"))) {
      $line =~ s/\r|\n//g;
      if($line =~ /^\s*(user|pass|database)\s*=\s*([^ ]+)\s*$/) {
         $$db{$1} = $2;
         $$log{$1} = $2;
      }
   }
}

get_db_credentials;


#
# sql
#    Connect / Reconnect to the database and run some sql.
#
sub sql
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;
   my (@result,$sth);
   @info{sqldone} = 0;

   delete @$con{rows};

#   if($sql !~ /^insert into output/) {
#      printf("SQL: '%s'\n",$sql);
#      printf("     '%s'\n",code("short"));
#   }

   #
   # clean up the sql a little
   #  keep track of last sql that was run for debug purposes.
   #
   $sql =~ s/\s{2,999}/ /g;
   @info{sql_last} = $sql;
   @info{sql_last_args} = join(',',@args);
   @info{sql_last_code} = code();

   # connected/reconnect to DB if needed
   if(!defined $$con{db} || !$$con{db}->ping) {
      $$con{host} = "localhost" if(!defined $$con{host});
      $$con{db} = DBI->connect("DBI:mysql:database=$$con{database}:" .
                             "host=$$con{host}",
                             $$con{user},
                             $$con{pass},
                             {AutoCommit => 0, RaiseError => 1,
                               mysql_auto_reconnect => 1}
                            ) 
                            or die "Can't connect to database: $DBI::errstr\n";
   }

   $sth = @$con{db}->prepare($sql) ||
      die("Could not prepair sql: $sql");

   for my $i (0 .. $#args) {
      $sth->bind_param($i+1,$args[$i]);
   }

   if(!$sth->execute( )) {
      printf("%s",code());
      die("Could not execute sql");
   }
   @$con{rows} = $sth->rows;

   # produce an error if expectations are not met
   if(defined @$con{expect}) {
      if(@$con{expect} != $sth->rows) {
         delete @$con{expect};
         die("Expected @$con{expect} rows but got " . $sth->rows . 
             " when running SQL: $sql");
      } else {
         delete @$con{expect};
      }
   }
 
   # do not fetch results from inserts / deletes 
   if($sql !~ /^\s*(insert|delete|update) /i) {
      while(my $ref = $sth->fetchrow_hashref()) {
         push(@result,$ref);
      }
   }

   # clean up and return the results
   $sth->finish();
   delete @info{sql_last};
   delete @info{sql_last_args};
   return \@result;
}

#
# sql
#    Connect / Reconnect to the database and run some sql.
#
sub sql2
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;
   my (@result,$sth);

   delete @$con{rows};
#   # reconnect if we've been idle for an hour. Shouldn't be needed?
#   if(time() - $$db{last} > 3600) {
#      eval {
#         @$con{db}->disconnect;
#      };
#      delete @$con{db};
#   }
#   $$db{last} = time();

   #
   # clean up the sql a little
   #  keep track of last sql that was run for debug purposes.
   #
   $sql =~ s/\s{2,999}/ /g;
   @info{sql_last} = $sql;
   @info{sql_last_args} = join(',',@args);
#   if($sql =~ /flag_permission/i) {
#   printf("SQL: '%s'\n",$sql);
#   printf("     '%s'\n",$info{sql_last_args});
#   }

   # connected/reconnect to DB if needed
   if(!defined $$con{db} || !$$con{db}->ping) {
      $$con{host} = "localhost" if(!defined $$con{host});
      $$con{db} = DBI->connect("DBI:mysql:database=$$con{database}:" .
                             "host=$$con{host}",
                             $$con{user},
                             $$con{pass},
                             {AutoCommit => 0, RaiseError => 1,
                               mysql_auto_reconnect => 1}
                            ) 
                            or die "Can't connect to database: $DBI::errstr\n";
   }

   $sth = @$con{db}->prepare($sql) ||
      die("Could not prepair sql: $sql");

   for my $i (0 .. $#args) {
      $sth->bind_param($i+1,$args[$i]);
   }

   $sth->execute( ) || die("Could not execute sql");
   @$con{rows} = $sth->rows;

   # produce an error if expectations are not met
   if(defined @$con{expect}) {
      if(@$con{expect} != $sth->rows) {
         delete @$con{expect};
         die("Expected @$con{expect} rows but got " . $sth->rows . 
             " when running SQL: $sql");
      } else {
         delete @$con{expect};
      }
   }
 
   # do not fetch results from inserts / deletes 
   if($sql !~ /^\s*(insert|delete|update) /i) {
      while(my $ref = $sth->fetchrow_hashref()) {
         push(@result,$ref);
      }
   }

   # clean up and return the results
   $sth->finish();
   return @result;
}

#
# one_val
#    fetch the first entry in value column on a select that returns only
#    one row.
#
sub one_val
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;

   my $array = sql($con,$sql,@args);
   return ($$con{rows} == 1) ? @{$$array[0]}{value} : undef;
}

#
# fetch one row or nothing
#
sub one
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($sql,@args) = @_;

#   printf("SQL: '%s'\n",$sql);
   my $array = sql($con,$sql,@args);
#   printf("ONE: '%s'\n",$$con{rows});
#   printf("#ARRAY#: '%s'\n",join(',',@$array));

   if($$con{rows} == 1) {
      return $$array[0];
   } elsif($$con{rows} == 2 && $sql =~ /ON DUPLICATE/i) {
      $$con{rows} = 1;
      return $$array[0];
   } else {
      return undef;
   }
}

sub my_commit
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   $$con{db}->commit;
}

sub my_rollback
{
   my $con = (ref($_[0]) eq "HASH") ? shift : $db;
   my ($fmt,@args) = @_;

#   printf("ROLLBACK CALLED %s\n",code("long"));
   @$con{db}->rollback;
   return undef;
}

sub fetch
{
   my $obj = obj($_[0]);
   my $debug = shift;

   $$obj{obj_id} =~ s/#//g;
   my $hash=one($db,"select * from object where obj_id = ?",$$obj{obj_id}) ||
      return undef;
   return $hash;
}

