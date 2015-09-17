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
logfile=/home/overflow/.GreenLuke.log
# display log messages not in terminal
quietMode=0
# generate more log; not yet implemented
verboseMode=1 
# don't start listen-thread
noListeningMode=0
# token for security reasons; has to be the same on all PCs
token="something" # maybe from pwgen pwgen 100

# some internal files
TokenFile=/dev/shm/GreenLuke$$.token
IpFile=/dev/shm/GreenLuke$$.ip
SearchFile=/dev/shm/GreenLuke$$.search

# here starts the program

# so others can read the token
echo -n $token > $TokenFile

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

setIp 127.0.0.1
setSearch 1

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
	remoteIp=$1
	remoteTokenFile=$2
	echo "trying to establish connection with $remoteIp" | log
	echo "testing for public key auth..." | log
	ssh -q -o BatchMode=yes $username@$remoteIp true 2> /dev/null
	if test $? != 0; then
		echo "... no public key auth, stopping here" | log
		return
	fi
	echo "testing for token... ($remoteTokenFile)" | log
	remoteToken=$(ssh -o BatchMode=yes $username@$remoteIp "cat $remoteTokenFile" 2> /dev/null)
	if test "$remoteToken" != "$token"; then
		echo "... not the same token ($remoteToken), stopping here" | log
		return
	fi

	echo "testing for unison..." | log
	unison $directory ssh://$username@$remoteIp/$directory -ui text -testserver 2>&1 | log
	if test $? != 0; then
		echo "... unison error. : (" | log
		return
	fi
	echo "let's get this party started" | log
	message=$(echo | unison $directory ssh://$username@$remoteIp/$directory -auto -owner -terse -batch 2>&1) 
	unisonError=$?
	echo $message | log
	if test $unisonError != 0; then
		echo "unison return some error" | log
		echo "informing user" | log
		if test $unisonError == 1; then
			zenity --warning --text="$(echo $message | tr -d '<' | tr -d '>' |)" --title=="GreenLuke"
		else
			zenity --error --text="There was a critical error while synchronizing.\nGreenLuke will exit now.\nPlease check out $log" --title="GreenLuke"
			echo "exiting" | log
			exit
		fi
	fi
	echo "successfully synchronized." | log
	echo "restarting daemon." | log
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
	while true; do		
		echo "listening..." | log
		response=$(hostname | socat -T 3 UDP-LISTEN:$port -)
		oldIFS="$IFS"
		response=( $response )
		IFS="$oldIFS"
		remoteIp=${response[0]}
		remoteTokenFile=${response[1]}
		sleep 1s 	# otherwise our logfiles get messed up
		echo "incomming request" | log
		if test "$remoteIp" == "$(getIp)"; then
			echo "oh, that's me. ignoring ourself" | log
		else
			setSearch 0
			connect $remoteIp $remoteTokenFile
			setSearch 1
			sleep 2s # to prevent token brute forcing
		fi
	done
}

# if not in noListingMode: start listen-thread
if test $noListeningMode = 0; then
	listen $port &
	sleep 3s
fi

# this is the search-thread
# - broadcast ip address and token filename
# - display all hostnames
# - sleep a random time (see settings)
while true; do
	if test $(getSearch) != 0; then
		echo "searching... " | log
		ip=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | awk -F'/' '{print $1}')
		setIp $ip
		remoteHostnames=$(echo -e "$ip\n$TokenFile" | socat - UDP-DATAGRAM:255.255.255.255:$port,broadcast)
		echo "found $(echo "$remoteHostnames" | wc -l) host(s): " | log
		echo "$remoteHostnames" | while read name; do
			echo "  - $name" | log
		done
	fi
	sleep  $(($RANDOM % ($maxSleep - $minSleep) + $minSleep))
done
