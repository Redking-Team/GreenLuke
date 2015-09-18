#!/bin/bash
# dependencies: ssh, sshd, unison, awk, iproute2, socat, zenity, wc

# settings for user

port=1337
# for search-thread; in s
minSleep=$((60*10))
maxSleep=$((60*60))
# directory to sync
directory=/home/overflow/sync
# username for ssh
username=overflow
#network interface for broadcasting
interface=eth0
logfile=/home/overflow/.GreenLuke.log
# display log messages not in terminal
quietMode=0
# generate more log, set to 2 for even more logs
verboseMode=1 
# don't start listen-thread
noListeningMode=0
# token for security reasons; has to be the same on all PCs
token="something" # maybe from pwgen pwgen 100

# some internal files
TokenFile=/dev/shm/GreenLuke$$.token
IpFile=/dev/shm/GreenLuke$$.ip
SearchFile=/dev/shm/GreenLuke$$.search



# some functions

# function for logging; get's text via stdin
log() {
	# dirty hack because I didn't knew how to make this better.
	# just ignore the following
	if test $quietMode != 0; then
		hackedPipe=false
	else
		hackedPipe=cat
	fi
	date "+%Y-%m-%d %H:%M:%S : " | tr -d '\n' | tee -a $logfile | $hackedPipe
	tee -a $logfile | $hackedPipe
}

# to get and set "variables" acroos threads I wrote this nice functions
setIp() {
	echo -n $1 > $IpFile
}
getIp() {
	cat $IpFile
}
setSearch() {
	echo -n $1 > $SearchFile
}
getSearch() {
	cat $SearchFile
}

# guess what this does
# $1 is verbose mode to check
verbose() {
	param=$(($1 + 0))
	return $((($param - $verboseMode) <= 0))
}

# this function does the following:
#  - are we public key authenicated on remote host $1? if not: return
#      (this also checks for running ssh server; captain obvious is obvious)
#  - are the tokens the same on remote (content in file $2) and local host? if not: return
#  - is there unison available on remote host? if not: return
#  -> start unison
#  - if there any error?
#    - are there conflicts (return code 1)? 
#      -> display warning and return
#    - else display error and exit (the error is probably somthing serious)
connect() {
	verbose 2 || (echo "listen-thread: (vv) intering connect-routine" | log)
	remoteIp=$1
	remoteTokenFile=$2
	verbose 0 || (echo "listen-thread: trying to establish connection with $remoteIp" | log)
	verbose 0 || (echo "listen-thread: testing for public key auth..." | log)
	error=$(ssh -q -o BatchMode=yes $username@$remoteIp true 2>1)
	if test $? != 0; then
		verbose 1 || (echo -e "listen-thread: (v) ssh exited with $?.\n$error" | log)
		verbose 0 || (echo "listen-thread: ... no public key auth, stopping here" | log)
		return
	fi
	verbose 2 || (echo "listen-thread: (vv) requesting remote token file" | log)
	remoteToken=$(ssh -o BatchMode=yes $username@$remoteIp "cat $remoteTokenFile" 2> /dev/null)	
	verbose 0 || (echo "listen-thread: comparing tokens..." | log)
	if test "$remoteToken" != "$token"; then
		verbose 1 || (echo "listen-thread: (v) remote token is $remoteToken" | log)
		verbose 0 || (echo "listen-thread: ... tokens are not the same, stopping here" | log)
		return
	fi
	verbose 0 || (echo "listen-thread: testing for unison..." | log)
	error=$(unison $directory ssh://$username@$remoteIp/$directory -ui text -testserver 2>&1)
	if test $? != 0; then
		verbose 1 || (echo -e "listen-thread: (v) unison exited with $?,\n$error" | log)
		verbose 0 || (echo "listen-thread: ... unison error, stopping here" | log)
		return
	fi
	verbose 0 || (echo "listen-thread: starting sync..." | log)
	message=$(echo | unison $directory ssh://$username@$remoteIp/$directory -auto -owner -terse -batch 2>&1) 
	unisonError=$?
	verbose 1 || (echo -e "listen-thread: (v) unison says:\n$message" | log)
	if test $unisonError != 0; then
		verbose 0 || (echo "listen-thread: unison return some error" | log)
		verbose 1 || (echo "listen-thread: (v) unison exited with $?" | log)
		verbose 0 || (echo "listen-thread: informing user" | log)
		if test $unisonError == 1; then	
			verbose 1 || (echo "listen-thread: (v) errorcode is 1, probably some conflics in unison; display warning" | log)
			zenity --warning --text="$(echo $message | tr -d '<' | tr -d '>' |)" --title=="GreenLuke"
		else	
			verbose 1 || (echo "listen-thread: (v) unknown errorcode; display error" | log)
			zenity --error --text="There was a critical error while synchronizing.\nGreenLuke will exit now.\nPlease check out $log" --title="GreenLuke"
			verbose 0 || (echo "listen-thread: exiting. bye." | log)
			exit
		fi
	fi
	verbose 0 || (echo "listen-thread: successfully synchronized." | log)
	verbose 2 || (echo "listen-thread: (vv) returning to main loop" | log)
}

# this is the listen-thread
# if there is any data (while receiving send hostname):
#   - save it to array
#       (first element is the remote address, second element is the token filename)
# if remote address is not our own address:
#   - disable search-thread
#   -> function connect
#   - enable search thread
listen() {
	verbose 2 || (echo "(vv) starting listen-thread main loop" | log)
	while true; do		
		verbose 0 || (echo "listen-thread: listening..." | log)
		verbose 2 || (echo "listen-thread: ... on udp port $port" | log)
		request=$(hostname | socat -T 3 UDP-LISTEN:$port -)
		sleep 1s	# otherwise our logfiles get messed up	
		verbose 0 || (echo "listen-thread: incomming request" | log)
		verbose 2 || (echo "listen-thread: (vv) reformat request data" | log)
		oldIFS="$IFS"
		request=( $request )
		IFS="$oldIFS"
		remoteIp=${request[0]}
		remoteTokenFile=${request[1]}
		verbose 1 || (echo "listen-thread: (v) response from $remoteIp ($remoteTokenFile)" | log)
		verbose 2 || (echo "listen-thread: (vv) testing if this is our own ip" | log)
		if test "$remoteIp" == "$(getIp)"; then
			verbose 0 || (echo "listen-thread: oh, that's me. ignoring ourself" | log)
		else	
			verbose 1 || (echo "listen-thread: (v) pausing search-thread" | log)
			setSearch 0
			connect $remoteIp $remoteTokenFile	
			verbose 1 || (echo "listen-thread: (v) starting search-thread" | log)
			setSearch 1
			sleep 2s # to prevent token brute forcing
		fi
	done
}

verbose 0 || (echo "Welcome to GreenLuke" | log)
verbose 2 || (echo "(vv) init vars" | log)
setIp 127.0.0.1
setSearch 1

# so others can read the token
verbose 2 || (echo "(vv) writing token file $TokenFile" | log)
echo -n $token > $TokenFile

# if not in noListingMode: start listen-thread
if test $noListeningMode = 0; then
	verbose 1 || (echo "(v) starting listen-thread..." | log)
	listen $port &
	sleep 3s
fi

# this is the search-thread
# - broadcast ip address and token filename
# - display all hostnames
# - sleep a random time (see settings)
verbose 2 || (echo "(vv) starting search-thread main loop" | log)
while true; do
	if test $(getSearch) != 0; then
		verbose 2 || (echo "search-thread: (vv) we are enabled" | log)
		verbose 2 || (echo "search-thread: (vv) getting ip address of interface $interface" | log)
		ip=$(ip addr show $interface | grep "inet " | awk '{print $2}' | awk -F'/' '{print $1}')
		verbose 1 || (echo "search-thread: (v) our ip address is: $ip" | log)
		verbose 2 || (echo "search-thread: (vv) setting global ip var" | log)
		setIp $ip
		verbose 0 || (echo "search-thread: searching... " | log)
		verbose 2 || (echo "search-thread: (vv) sending upd broadcast on port $port" | log)
		remoteHostnames=$(echo -e "$ip\n$TokenFile" | socat - UDP-DATAGRAM:255.255.255.255:$port,broadcast)
		verbose 0 || (echo "search-thread: found $(echo "$remoteHostnames" | wc -l) host(s): " | log)
		echo "$remoteHostnames" | while read name; do
			verbose 0 || (echo "search-thread:   - $name" | log)
		done
	fi
	time=$(($RANDOM % ($maxSleep - $minSleep) + $minSleep))
	verbose 1 || (echo "search-thread: (v) sleeping for $time s..." | log)
	sleep  $time
done

