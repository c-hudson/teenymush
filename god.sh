#!/bin/bash
#----------------------------------------------------------------------------#
#                                                                            #
# god.sh --port=8000                                                         #
#                                                                            #
#    Run a MUSH command from the command line as #0.                         #
#                                                                            #
# Requirements:                                                              #
#    1. httpd has to be turned on and running.                               #
#    2. This can onl be run from the server where the mush is located        #
#    3. The perl script for the MUSH must have teenymush in the name         #
#                                                                            #
# How does this work, is it secure?                                          #
#                                                                            #
#    This script runs curl to issue a MUSH command to the MUSH via httpd.    #
#    While curl is running, the script sends a SIGUSR1 to the MUSH.          #
#                                                                            #
#    The MUSH accepts the command via curl only if the request comes from    #
#    localhost. Once the MUSH accepts the command, it waits for up to 10     #
#    seconds for the server to receieve a SIGUSR1 signal. If it receives     #
#    the signal, the MUSH executes the command. If it does it does not,      #
#    it displays an error after 10 seconds.                                  #
#                                                                            #
#    Any requests older then 10 seconds will error out, multiple commands    #
#    can not be run at the same time.                                        #
#                                                                            #
#    Hopefully this lock step of the signal and the command requirement      #
#    from localhost will secure the command to only those with account       #
#                                                                            #
#----------------------------------------------------------------------------#

# handle command line arguements aka --port
for i in "$@"
do
  case $i in
     --port=*)
     PORT="${i#*=}"
     shift
     ;;
     *)
     ;;
   esac
done

# default port to 8000 if not specified
if [ "x$PORT" = "x" ]
then
   PORT=8000
fi

#
# Get the pid of the mush. The assumption is that there could be multiple
# MUSHes, and then you've got to jump through some hoops to find out which
# MUSH is on what port. Lets just ask the mush?
#
PID=`curl -s http://localhost:${PORT}/pid`

#
# since things could go wrong, verify the port returned is correct.
#
ps ww -q ${PID//[$'\t\r\n']} | grep perl | grep teenymush > /dev/null

if [ $? = 0 ]
then 
   # send signal 1 second in the future and run curl now
   (sleep 1;/bin/kill -SIGUSR1 ${PID//[$'\t\r\n']}) &
   curl "http://localhost:${PORT}/imc/$*"
else
   echo INVALID PID ${PID//[$'\t\r\n']}
fi
