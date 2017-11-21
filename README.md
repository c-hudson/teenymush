TeenyMUSH
~~~~~~~~~
     This is an implementation of a TinyMUSH like server in Perl and
MySQL. The server can be used to create an ASCII based virtual world.
Users can telnet into the server and interact with other users in a world
of their creation. Customization of the world does not require
modification of the internal server code. 

Installation
~~~~~~~~~~~~
     Run the create.sh to create the mysql peices and the tm_config.dat.
This will create a god character with a password of portrzebie, and an
initial room. Then run the "tm" perl script.

Setup
~~~~~
     Setup handled in the netmush.conf on TinyMUSH is going to be handled
by setting attributes on object #0. This allows configuration of the server
to be done without shell access. Here are the attributes that are
currently supported:

LOGIN        |  Login screen
LOGOFF       |  Log off message
MOTD         |  Message of the day
REGISTRATION |  Login screen shown when registration is in effect


see http://teenymush.blogspot.in/ for more details.
