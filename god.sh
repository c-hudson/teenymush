#!/bin/bash
#----------------------------------------------------------------------------#
#                                                                            #
# god.sh
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
#    The script finds the httpd port by examining the last dump file.        #
#    The script then issues a curl command to query the pid and current      #
#    directory for the MUSH via the http port. If everything looks good,     #
#    the script then sends a special command to the MUSH over httpd. Once    #
#    the MUSH receives it waits for up to 10 seconds for a SIGUSR1 signal.   #
#    If it receives the signal, the MUSH executes the command. If it does    #
#    it does not, it displays an error after 10 seconds. Any output from     #
#    the command (if run) will be displayed on the screen                    #
#                                                                            #
#    Hopefully this lock step of the signal and the command requirement      #
#    from localhost will secure the command to only those with account       #
#                                                                            #
#----------------------------------------------------------------------------#

# find last dump file
FN=`ls -t1 dumps/*.tdb | head -1`
# find port in dump file
PORT=`grep -m 1 "   conf.httpd:"  dumps/${FN##*/}| awk -F : '{printf("%s\n",$6);}'`
#
# Get the pid of the mush. The assumption is that there could be multiple
# MUSHes, and then you've got to jump through some hoops to find out which
# MUSH is on what port. Lets just ask the mush?
#
RESPONCE=`curl -s http://localhost:${PORT}/pid`
IFS=","
readarray -d , -t info <<<$RESPONCE
IFS=" "
PID=${info[0]}
MWD=${info[1]}
MWD=${MWD//[$'\t\r\n']}

# verify pid
ps ww -q $PID | grep perl | grep teenymush > /dev/null
if [ $? != 0 ]
then
   echo Unable to match up process $PID to a teenymush instance.
   exit;
fi

# verify current directory
if [ "$MWD" != "`pwd`" ]; then
   echo ERROR: script in wrong directory, expected $MWD;
   exit;
fi

(sleep 1;/bin/kill -SIGUSR1 ${PID//[$'\t\r\n']}) &
   curl --http0.9 "http://localhost:${PORT}/imc/$*"

exit
