#!/bin/sh

cat <<__EOF__
#---------------------------------------------------------------------#

    This script will create the mysql peices that are required for
 TeenyMUSH. This script assumes that someone has already installed
 mysql, created a database, and give access to that database to the
 user who will be running the database If you haven't, below is a
 starting point for the commands you'll need to run. Otherwise, just
 answer the questions below.

 As root
  1. mysql -p
        type in the root password for your mysql instance

  2. create database teenymush;
  3. grant all privileges on teenymush.* to $USER@'%' 
       identified by 'password';

#---------------------------------------------------------------------#
__EOF__
read -p "Enter database user?  [$USER]: " dbuser

if [ "$dbuser" = "" ]; then
   dbuser=$USER;
fi

read -p "Enter database password?  [potrzebie]: " dbpass

if [ "$dbpass" = "" ]; then
   dbpass="potrzebie";
fi

read -p "Enter database name?  [teenymush]: " dbname

if [ "$dbname" = "" ]; then
   dbname="teenymush";
fi

read -p "Enter port number  [4096]: " port

if [ "$port" = "" ]; then
   port="4096";
fi

echo mysql -u $dbuser -pPASSWORD $dbname < base_structure.sql >> create.log
mysql -u $dbuser -p$dbpass $dbname < base_structure.sql >> create.log 2>&1

if [ $? -ne 0 ]; then
   echo "# Return Code: $?" >> create.log
   echo Error running base_structure.sql...
   echo
   tail create.log
   exit
fi

echo mysql -u $dbuser -pPASSWORD $dbname < base_objects.sql >> create.log
mysql -u $dbuser -p$dbpass $dbname < base_objects.sql >> create.log 2>&1

if [ $? -ne 0 ]; then
   echo "# Return Code: $?" >> create.log
   echo Error running base_objects.sql...
   echo
   tail create.log
   exit
fi
echo "# Return Code: $?" >> create.log

echo mysql -u $dbuser -pPASSWORD $dbname < base_inserts.sql >> create.log
mysql -u $dbuser -p$dbpass $dbname < base_inserts.sql >> create.log 2>&1

if [ $? -ne 0 ]; then
   echo "# Return Code: $?" >> create.log
   echo Error running base_inserts.sql...
   echo
   tail create.log
   exit
fi

echo Mysql objects created...

if [ -e tm_config.dat ]; then
   echo tm_config.dat already exists, not updating.
else
   echo user=$dbuser > tm_config.dat
   echo pass=$dbpass >> tm_config.dat
   echo database=$dbname >> tm_config.dat
   echo port=$port >> tm_config.dat
   echo Created tm_config.dat
fi
