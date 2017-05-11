TeenyMUSH
~~~~~~~~~

      This server is an implementation an ASCII based virtual world where
users may telnet into the server and interact with other users. The world
can be customized to meet the needs of its owner and/or users without
modifying internal server code. Typically users will use a client program
such as TinyFugue to connect to the server to make the interaction easier.

Connecting
~~~~~~~~~~
      Typically users will use a client program to connect to the server.
Many different clients have been created over the years from TinyFugue,
Potato MUSH Client, or Plantain MUSH Client. You provide the client with
an internet address and port and the client will connect. At that point
you may connect to an existing character or a guest character via the
connect command. Connecting via the guest character would be accomplished
by typing 'connect guest'. The TeenyMUSH development site may be found at
teenymush.ddns.net at port 4096.

Interacting
~~~~~~~~~~~
     Players may interact with other users by using the say, page, go commands. The say and page commands lets players talk with people in the same room or even distant locations. The go command lets users travel from one room to another.

Building
~~~~~~~~
     Users can create rooms or objects to help better describe the environment in which they wish to interact in. Rooms and objects can be extremely simple to overtly complex. Usually the owner of the world will pick a theme and users are asked to create within the bounds of that theme.

Programing Language
~~~~~~~~~~~~~~~~~~~
     TeenyMUSH supports a lot of the commands supported by TinyMUSH servers. Typically the commands start with a '@' followed by the name of the command. For example, to create an object one would type '@create TeddyBear' if they wanted a their own TeddyBear. The TeddyBear could then be embellished with a description by typing '@describe TeddyBear=You see a small fluffy TeddyBear'. See the on-line documentation for additional commands.

Focus
~~~~~
    While many of commands supported by this server mirror TinyMUSH's commands, the focus is more on providing users with a program language which is readable and more powerful. Reading something coded in MUSH code can be a daunting task. Writing something complex can be just as daunting or nearly impossible. While I would have preferred to have implemented these features in a TinyMUSH server, my skill sets prevent me from doing so in a reasonable time frame.

Arbitrary Features
~~~~~~~~~~~~~~~~~~
    Mysql Support. The internal database is done within MySQL. This solves many database corruption issues and Mysql provides lots of commands to help backup and maintain the database.
    Crash recovery. Perl provides a nifty eval command which can be used to catch crashes without shutting down the server.
    Dynamic code loading. Find a bug in the code or want to load a new version of the code? Change the code and reload it while everyone is on-line and no one will notice.
    Sockets. The server supports using sockets controlled by MUSH code. Example code has been created to query the current weather conditions, remote WHOs from other servers, and other tidbits of information.


Status
~~~~~~
     Code development started in April of 2016 during my spare time. The ability to connect and talk to users was up and working within a week. The first real "program" used MUSH sockets to provide weather information from wunderground's telnet based weather server. The first ported game using unmodified MUSH Code was Connect 4. It was completed on March of 2017. It was followed by a port of Othello a week later. Tweaking of code continues to provide better support for other programs. 

Download
~~~~~~~~
     The code can be downloaded at http://github.com/c-hudson/ascii. Getting a working server running from the code hosted at GitHub will be problematic. The process is not documented, nore has a script been provide to build the server. Hopefully this will change in the near future.

Requirements
~~~~~~~~~~~~
     The development MUSH currently runs on a Raspberry Pi 2 with a very limited database and player base. It should run on anything that supports Perl and Mysql without much trouble (hopefully).
