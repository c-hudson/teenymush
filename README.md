# TeenyMUSH
This is an implementation of a TinyMUSH like server in Perl. The server can
be used to create an ASCII based virtual world.
Users can telnet into the server and interact with other users in a world
of their creation. Customization of the world does not require
modification of the internal server code. 


   1. Download source from github. The source for this project is availible in two different formats. A single file (teenymush.pl) that contains the whole distributions or the seperate individual files. If you don't have all the required modules installed, using the multi-file distribution will allow the code to bypass those modules required for mysql, httpd, and websockets at the cost of disabling those features.


```
      Example:
          git clone https://github.com/c-hudson/teenymush.git

                                    or

          wget https://github.com/c-hudson/teenymush/raw/master/teenymush.pl
```

# Installation using in memory database [skip if using mysql]
   2. Create a tm_config.dat file containing at least these three lines:

```
         port=4096
         conf.mudname=Ascii
         conf.memorydb=1
```
   3. Run tm perl script or teenymush.pl script depending on if you downloaded
      all of the files or just the single teenymush.pl script.

   4. Login as god with a password of portrzebie

   5. Done
      

# Installation using Mysql [not required if using memory database]
   2. Create a mysql database that you can log into
 
      Example:
```
         mysql -p -u root
         mysql> create database teenymush;
         mysql> grant all privileges on teenymush.* to $USER@'%'
                   identified by 'password';
         Replace $USER with your db user name, and password with your
         prefered password.
```
   3. Create a tm_config.dat file containing at least these three lines:

```
         port=4096
         conf.mudname=Ascii
         conf.mysqldb=1
```

   4. Run the 'tm'  or 'teenymush.pl' script, answer prompts for username,
      password, and database name. Answer yes to loading default database,
      unless you
      have a database backup named as tm_backup.sql.

   5. Run tm perl script

   6. Login as god with a password of portrzebie

   7. Done

# Setup

Setup handled in the netmush.conf on TinyMUSH is handled by setting
attributes on object #0. This allows configuration of the server
to be done without shell access. Here are the attributes that are
currently supported:

```
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
conf.starting_room      |  Starting location for new players
conf.paycheck           |  How much money does a player get per day on connect
conf.linkcost           |  Cost of link
conf.digcost            |  Cost of room
conf.createcost         |  Cost of object
conf.doing_header       |  The default DOING header
conf.mudname            |  Name of your MUSH
conf.memorydb           |  Set this to 1 to use the memorydb
conf.mysql              |  Set this to 1 to use mysql for the database
conf.backup_interval    |  How often to dump the memorydb in seconds
```

see http://teenymush.blogspot.in/ for more details.
