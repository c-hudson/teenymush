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
                    ip   => server_hostname($new),
                  };
#   printf("   %s\@web Connect\n",@{@http{$new}}{ip});
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

   http_out($s,"HTTP/1.1 404 Not Found");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,"<style>");
   http_out($s,".big {");
   http_out($s,"   line-height: 0;");
   http_out($s,"   font-size: 100pt;");
   http_out($s,"}");
   http_out($s,"</style>");
   http_out($s,"<center><h1 class=big>404</h1><hr>#-1 Page Not Found</center>");
   http_out($s,"<center>$fmt</center>",@args);
   http_disconnect($s);
}

sub http_reply
{
   my ($s,$fmt,@args) = @_;

   my $msg = sprintf($fmt,@args);

   if($msg =~ /^Huh\? \(Type \"help\" for help\.\)/) {
      return http_error($s,$fmt,@args);
   }
   if((stat("txt/http_template.txt"))[9] != @info{template_last}) {
      @info{template} = getfile("http_template.txt");
      @info{template_last} = time();
   }

   http_out($s,"HTTP/1.1 200 Default Request");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/html; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,"%s\n",@info{template});
   http_out($s,"<body>\n");
   http_out($s,"<div id=\"Content\">\n");
   http_out($s,"<pre>%s\n</pre>\n",ansi_remove($msg));
   http_out($s,"</div>\n");
   http_out($s,"</body>\n");
   http_disconnect($s);
}

sub http_reply_simple
{
   my ($s,$type,$fmt,@args) = @_;

   my $msg = sprintf($fmt,@args);

   http_out($s,"HTTP/1.1 200 Default Request");
   http_out($s,"Date: %s",scalar localtime());
   http_out($s,"Last-Modified: %s",scalar localtime());
   http_out($s,"Connection: close");
   http_out($s,"Content-Type: text/$type; charset=ISO-8859-1");
   http_out($s,"");
   http_out($s,$fmt,@args);
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
#      printf("      %s\@web %s\n",@{@http{$s}}{ip},$1);
      $$data{get} = $1;
   } elsif($txt =~ /^([\w\-]+): /) {
      $$data{lc($1)} = $';
   } elsif($txt =~ /^\s*$/) {                               # end of request
      my $msg =  uri_unescape($$data{get});

      if($msg eq undef) {
         http_error($s,"Malformed Request");
      } else {
         my $id = @info{"conf.webuser"};
         my $self = fetch(@info{"conf.webuser"});

         my $msg =  uri_unescape($$data{get});
#         $msg = $' if($msg =~ /^\s*\/+/);
         $msg =~ s/\// /g;

         # run the $default mush command as the default webpage.
         $msg = "default" if($msg =~ /^\s*$/);

         my $addr = @{@http{$s}}{hostname};
         $addr = @{@http{$s}}{ip} if($addr =~ /^\s*$/);
         $addr = $s->peerhost if($addr =~ /^\s*$/);
         return http_error($s,"Malformed Request or IP") if($addr =~ /^\s*$/);

         printf("   %s\@web [%s]\n",$addr,$msg);

         if($msg !~ /^\s*favicon\.ico\s*$/i) {
            sql(e($db,1),
                "insert into socket_history ".
                "( obj_id, " .
                "  skh_hostname, " .
                "  skh_start_time, " .
                "  skh_end_time, " .
                "  skh_success, " .
                "  skh_detail, " .
                "  skh_type " .
                ") values ( " .
                "  ?, ?, now(), now(), 0, ?, ? ".
                ")",
                @info{"conf.webuser"},
                $addr,
                substr($msg,0,254),
                2
               );
         }

         # html/js/css should be a static file, so just return the file
         if($msg =~ /\.(html|js|css)$/i && -e "txt/" . trim($msg)) {
            http_reply_simple($s,$1,"%s",getfile(trim($msg)));
         } else {                                          # mush command
            my $prog = mushrun(self   => $self,
                               runas  => $self,
                               source => 0,
                               cmd    => $msg,
                               hint   => "WEB",
                               sock   => $s,
                               output => [],
                               nosplit => 1,
                              );
         }
      }
   } else {
      http_error($s,"Malformed Request");
   }
}
