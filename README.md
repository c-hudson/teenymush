TeenyMUSH
~~~~~~~~~
This is an implementation of a TinyMUSH like server in Perl and
MySQL. The server can be used to create an ASCII based virtual world.
Users can telnet into the server and interact with other users in a world
of their creation. Customization of the world does not require
modification of the internal server code. 


Installation
~~~~~~~~~~~~
   1. Create a mysql database that you can log into
 
      Example:
         mysql -p -u root
         mysql> create database teenymush
         mysql> grant all privileges on teenymush.* to $USER@'%'
                   identified by 'password';

         Replace $USER with your db user name, and password with your
         prefered password.

   2. Download source from github:

      Example: git clone https://github.com/c-hudson/teenymush.git
               cd teenymush

   3. Run the 'tm' script, answer prompts for username, password, and
      database name. Answer yes to loading default database, unless you
      have a database backup named tm_backup.sql.

   4. Login as god with a password of portrzebie


Setup
~~~~~
Setup handled in the netmush.conf on TinyMUSH is handled by setting
attributes on object #0. This allows configuration of the server
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
