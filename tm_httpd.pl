#!/usr/bin/perl

use URI::Escape;

#
# http_input
#    Handle the incoming data and look for disconnects.
#
sub http_io
{
   my $s = shift;
   my $buf;

   if(sysread($s,$buf,1024) <= 0) {                      # oops socket died
      http_disconnect($s);
   } else {
      $buf =~ s/\r//g;
      @{@http{$s}}{buf} .= $buf;                         # store new input

      while(defined @http{$s} && @{@http{$s}}{buf} =~ /\n/){ 
         @{@http{$s}}{buf} = $';                  # process any full lines
         http_process_line($s,$`);
      }
   }
}

#
# http_accept
#    The listener has detected a new socket
#
sub http_accept
{
   my $s = shift;

   my $new = $web->accept();

   $readable->add($new);

   @http{$new} = { sock => $new,
                    data => {},
                    ip   => $new->peerhost,
                  };
   printf("   %s\@web Connect\n",$new->peerhost);
}

sub http_disconnect
{
   my $s = shift;

   delete @http{$s};
   $readable->remove($s);
   $s->close;

}

sub http_error
{
   my ($s,$fmt,@args) = @_;

   http_out($s,"HTTP/1.1 400 Not Found");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,$fmt,@args);
   http_disconnect($s);
}

sub http_reply
{
   my ($s,$fmt,@args) = @_;

   my $msg = sprintf($fmt,@args);
   my $css = getfile("mudtape.css");
   $css =~ s/--CONTENTS--/$msg/;
   $css =~ s/--TITLE--/TeenyMUSH Web Portal/;

   http_out($s,"HTTP/1.1 200 Default Request");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,"%s","<pre>\n" . $css . "\n<pre>\n");
   http_disconnect($s);
}

sub http_out
{
   my ($s,$fmt,@args) = @_;

   printf({@{@http{$s}}{sock}} "$fmt\r\n", @args) if(defined @http{$s});
}

#
# http_process_line
#
#    A line of data has been found, store the information for later
#    use if the request is not done.
#
sub http_process_line
{
   my ($s,$txt) = @_;

   my $data = @{@http{$s}}{data};

   if($txt =~ /^GET (.*) HTTP\/([\d\.]+)$/i) {              # record details
      $$data{get} = $1;
   } elsif($txt =~ /^([\w\-]+): /) {
      $$data{lc($1)} = $';
   } elsif($txt =~ /^\s*$/) {                               # end of request
      my $msg =  uri_unescape($$data{get});

      if($msg eq undef) {
         http_error($s,"Malformed Request");
      } else {
         my $self = fetch("118");

         my $msg =  uri_unescape($$data{get});
         $msg = $' if($msg =~ /^\s*\/+/);
 
         # run the $default mush command as the default webpage.
         $msg = "default" if $msg eq undef;
   
         printf("   %s\@web [%s]\n",@{@http{$s}}{ip},$msg);

         my $prog = mushrun(self   => $self,
                            runas  => $self,
                            source => 0,
                            cmd    => $msg,
                            hint   => "WEB"
                           );
         $$prog{sock} = $s;
      }
   } else {
      http_error($s,"Malformed Request");
   }
}
