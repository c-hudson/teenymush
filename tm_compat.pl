#!/usr/bin/perl
#
# tm_compat.pl
#
#    This file contains those code that is required if a particular
#    non-esential file fails to load. Usually these missing tidbits will
#    never be called but are required to compile.
#
sub my_commit   
{        
   return;
}

sub my_rollback
{        
   return;
}       
