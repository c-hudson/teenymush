#!/usr/bin/perl
#
# tm_ansi.pl
#    Any routines for handling the limited support for ansi characters
#    within TeenyMUSH.
#
use strict;
use MIME::Base64;

#
# conversion table for letters to numbers used in escape codes as defined
# by TinyMUSH, or maybe TinyMUX.
#
my %ansi = (
   x => 30, X => 40,
   r => 31, R => 41,
   g => 32, G => 42,
   y => 33, Y => 43,
   b => 34, B => 44,
   m => 35, M => 45,
   c => 36, C => 46,
   w => 37, W => 47,
   u => 4,  i => 7,
   h => 1
);

#
# ansi_debug
#    Convert an ansi string into something more readable.
#
sub ansi_debug
{
    my $txt = shift;

    $txt =~ s/\e/<ESC>/g;
    return $txt;
}
#
# ansi_add
#   Add a character or escape code to the data array. Every add of a
#   character results in a new element, escape codes are added to existing
#   elements as long as a character has not been added yet. The ansi state
#   is also kept track of here.
#
sub ansi_add
{
   my ($data,$type,$txt) = @_;

   if(ref($data) ne "HASH"   ||                           # insanity check
      !defined $$data{ch}    ||
      !defined $$data{state} ||
      !defined $$data{code}  ||
      !defined $$data{ch}) {
      croak("Invalid data structure provided");
   }

   my $ch   = $$data{ch};                      # make things more readable
   my $code = $$data{code};
   my $snap = $$data{snap};

   # $ch will be the controlling array
   if($#$ch == -1 || $$ch[$#$ch] ne undef) {
      $$ch[$#$ch+1] = undef;
      $$code[$#$ch] = [];
      $$snap[$#$ch] = [];
   }
   
   if(!$type) {                                           # add escape code
      push(@{$$code[$#$ch]}, $txt);

      if(substr($txt,1,3) eq "[0m") {
         $$data{state} = [];
      } else {
         push(@{$$data{state}},$txt);            # keep track of current state
      }
   } else {                                                 # add character
      $$ch[$#$ch] = $txt;
      $$snap[$#$ch] = [ @{@$data{state}} ];  # copy current state to char
   }
   return length($txt);
}

#
# ansi_init
#    Read in a string and convert it into a data structure that can be
#    easily parsed / modified, i hope. 
#
#     {
#       code => [ [ array of arrays containing escape codes ] ]
#       ch   => [ Array containing each character one by one ]
#       snap => [ [ array of arrays containing all active escape codes 
#                   at the time the character was encountered ] ]
#       state=> [ internal, current state of active escape does ]
#     }
#
sub ansi_init
{
   my $str = shift;
   my $data = {
      ch     => [],
      code   => [],
      state  => [],
      snap   => []
   };

   for(my ($len,$i)=(length($str),0);$i < $len;) {
       if(ord(substr($str,$i,1)) eq 27) {                      # found escape
          my $sub = substr($str,$i+1);

          # parse known escape sequences
          if($sub =~ /^\[([\d;]*)([a-zA-Z])/) {
             $i += ansi_add($data,0,chr(27) . "[" . $1 . $2);
          } elsif($sub =~ /^([#O\(\)])([a-z0-9])/i) {
             $i += ansi_add($data,0,chr(27) . $1 . $2);
          } elsif($sub =~ /^(\[{0,1})([\?0-9]*);([0-9]*)([a-z])/i) {
             $i += ansi_add($data,0,chr(27) . $1 . $2 . ";" . $3 . $4);
          } elsif($sub =~ /^(\[{0,1})([\?0-9]*)([a-z])/i) {
             $i += ansi_add($data,0,chr(27) . $1 . $2 . $3);
          } elsif($sub =~ /^([\<\=\>78])/) {
             $i += ansi_add($data,0,chr(27) . $1);
          } elsif($sub =~ /^\/Z/i) {
             $i += ansi_add($data,0,chr(27) . "\/Z");
          } else {
             $i++;                   # else ignore non-known escape codes
          }
      } else {
         $i += ansi_add($data,1,substr($str,$i,1));          # non-escape code
      }
   }
   return $data;
}

#sub ansi_debug
#{
#   my @array = @_;
#   my $result;
#
#   for my $i (0 .. $#array) {
#      $result .= "<ESC>" . substr(@array[$i],1);
#   }
#   return $result;
#}

#
# ansi_string
#    Take ansi data structure and return 
#        type => 0 : everything but the escape codes
#        type => 1 : original string [including escape codes]
#
sub ansi_string
{
   my ($data,$type) = @_;
   my $buf;

   for my $i (0 .. $#{$$data{ch}}) {
      $buf .= join('', @{@{$$data{code}}[$i]}) if($type);
      $buf .= @{$$data{ch}}[$i];
   }
   return $buf;
}

#
# ansi_substr
#    Do a substr on a string while preserving the escape codes.
#
sub ansi_substr
{
   my ($txt,$start,$count) = @_;
   my ($result,$data,$last);

   $start = 0 if($start !~ /^\s*\d+\s*$/);                  # sanity checks
   if($count !~ /^\s*\d+\s*$/) {
      $count = $start;
   } else {
      $count += $start;
   }
   return undef if($start < 0);                         # no starting point


   if(ref($txt) eq "HASH") {
      $data = $txt;
   } else {
      $data = ansi_init($txt);
   }

   # loop through each "character" w/attached ansi codes
   for(my $i = $start;$i < $count && $i <= $#{$$data{ch}};$i++) {

      my $code=join('',@{@{$$data{($i == $start) ? "snap" : "code"}}[$i]});
      $result .= $code . @{$$data{ch}}[$i];
      $last = $#{@{$$data{snap}}[$i]};
   }

   # are attributes turned on on last character? if so, reset them.
   return $result . (($last == -1) ? "" : (chr(27) . "[0m"));
}

#
# ansi_length
#    Return the length of a string without counting all those pesky escape
#    codes.
#
sub ansi_length
{
   my $txt = shift;

   my $data = ansi_init($txt);

   if($#{$$data{ch}} == -1) {                                       # empty
      return 0;
   } elsif(@{$$data{ch}}[-1] eq undef) {               # last char pos empty?
      return $#{$$data{ch}};
   } else {
      return $#{$$data{ch}} + 1;                        # last char populated
   }
}

sub color
{
   my ($codes,$txt) = @_;
   my $pre;

   for my $ch (split(//,$codes)) {
      if(defined @ansi{$ch}) {
         $pre .= "\e[@ansi{$ch};1m";
      } elsif(defined @ansi{$ch}) {
         $pre .= "\e[@ansi{$ch}m";
      }
   }
   return $pre . $txt . "\e[0m";
}


#
# ansi_remove
#    remove any escape codes from the string
#
sub ansi_remove
{
#   my $txt = ansi_init(shift);
#   return ansi_print($txt,0);

   my $txt = shift;
   $txt =~ s/\e\[[\d;]*[a-zA-Z]//g;
   return $txt;
}

sub space_scan
{
   my ( $data, $start )= @_;

   for my $i ( $start .. $#{$$data{ch}}) {
      return $i if(@{$$data{ch}}[$i] ne " ");
   }
   return $#{$$data{ch}};
}

sub ansi_wrap
{
   my $rules = {
      max_x => 79,
      max_word => 25,
   };

   my $txt = ansi_init(shift);
   my $str = $$txt{ch};
   my ($start,$word_end,$i,$out) = (0,0,0,undef);

   while($i < $#$str) {
      if($i - $start >= $$rules{max_x}) {
         if($i - $word_end >= $$rules{max_word}) {       # split at screen
            $out .= ansi_substr($txt,$start,$i-$start) . "\n";
            $i = space_scan($txt,$i);
            $start = $i;
         } else {                                             # split at word
            $out .= ansi_substr($txt,$start,$word_end-$start) . "\n";
            $i = space_scan($txt,$word_end + 1);
            $start = $i;
         }
         $word_end = $start + 1;
      } elsif($$str[$i] eq " " && ($i == 0 || $$str[$i-1] ne " ")) {
         $word_end = $i;
         $i++;
      }  else {
         $i++;
      }
   }

   if($start < $#$str) {
      $out .= ansi_substr($txt,$start,$#$str);
   }

   return $out;
}

sub lord
{
   my $txt = shift;

   $txt =~ s/\e/<ESC>/g;
   return $txt;
}

# open(FILE,"iweb") ||
#    die("Could not open file iweb for reading");
#  
# while(<FILE>) {
#    s/\r|\n//g;
# #   if(/This/) {
#      printf("%s\n",ansi_wrap($_));
# #   }
# }
# close(FILE);


#my $str = "[32;1m|[0m [1m[34;1m<*>[0m [32;1m|[0m [31;1mA[0m[31ms[0m[31mh[0m[31me[0m[31mn[0m[33;1m-[0m[31;1mS[0m[31mh[0m[31mu[0m[31mg[0m[31mar[0m                   [32;1m|[0m Meetme(#260V)                        [32;1m|[0m";

#for my $i (0 .. 78) {
#   printf("%0d : '%s'\n",$i,ansi_length(ansi_substr($str,$i,7)));
#}

#my $str = decode_base64("CiAgICAtLS0tLS0tLS0tLS0tLS0gICAgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQogMSB8LnwufC58LnwufC58LnwufCAgfCAgICAgICBUYW86IFRoaXMgQWluJ3QgT3RoZWxsbyAgICAgICB8CiAyIHwufC58T3xPfC58LnwufC58ICB8ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHwKIDMgfC58I3xPfE98I3xPfC58LnwgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfAogNCB8LnwufCN8T3xPfC58LnwufCAgfCAgIzogV2ViT2JqZWN0ICAgICAgICBoYXMgIDYgcGllY2VzICB8CiA1IHwufCN8T3xPfE98T3wufC58ICB8ICBPOiAbWzM0bUFkcmljaxtbMG0bW20gICAgICAgICAgIGhhcyAxMSBwaWVjZXMgIHwKIDYgfC58LnwufCN8LnwjfC58LnwgIHwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfAogNyB8LnwufC58LnwufC58LnwufCAgfCAgICoqKiBJdCBpcyBXZWJPYmplY3QncyB0dXJuICoqKiAgICB8CiA4IHwufC58LnwufC58LnwufC58ICB8ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHwKICAgIC0tLS0tLS0tLS0tLS0tLSAgICAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tCiAgICAxIDIgMyA0IDUgNiA3IDhd");



# printf("%s\n",ansi_debug($str));
#my $a = ansi_init($str);
#printf("%s\n",$str);
#printf("%s\n",lord(ansi_string($a,1)));
#printf("SUB:%s\n",ansi_substr($a,11,1));
