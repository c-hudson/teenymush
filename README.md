# TeenyMUSH
This is a full implementation of a TinyMUSH like server in Perl. The server
can be used to create an ASCII based virtual world of your own.  Customization
of the world does not require modification of the server but instead uses
internal commands documented in the help command. People can interact with
other users via telnet, web, or websockets.

   1. Download teenymush.pl and help.txt
```
          wget https://github.com/c-hudson/teenymush/raw/master/teenymush.pl
          wget https://github.com/c-hudson/teenymush/raw/master/help.txt
          wget https://github.com/c-hudson/teenymush/raw/master/god.sh
```

   2. Run teenymush.pl script
```
          chmod u+x teenymush.pl
          ./teenymush.pl
```

   4. Login as god on port 4096 with a password of portrzebie
```
          telnet localhost 4096
```

   5. Done
      

# Setup

See: https://teenymush.dynu.net/FAQ or 
     https://teenymush.dynu.net/ for more details.
