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

conf.login              |  Login screen
conf.logoff             |  Log off message
conf.motd               |  Message of the day
conf.registration       |  Login screen shown when registration is in effect
conf.badsite            |  Login screen for banned sites
conf.godlike            |  This dbref may modify object #0
conf.master             |  dbref for the master room
conf.httpd              |  Port to listen for web requests
conf.webuser            |  The dbref of the object that all mushcode runs under
                        |  for the web server.
conf.webobject          |  The dbref of the object which contains the mushcoded
                        |  commands that may be run from the web.
conf.websocket          |  Port to listen to for websocket requests
conf.money_name_plural  |  Plural form of money's name
conf.money_name_singlar |  Singular form of money's name
conf.starting_money     |  How much money does a player get on @create
conf.paycheck           |  How much money does a player get per day on connect
conf.linkcost           |  Cost of link
conf.digcost            |  Cost of room
conf.createcost         |  Cost of object

see http://teenymush.blogspot.in/ for more details.
