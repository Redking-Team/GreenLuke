#!/bin/bash
# dependencies: ssh, sshd, unison, awk, iproute2, socat, zenity, wc

port=1337
minSleep=$((60*10))	# in s
maxSleep=$((60*60))	# in s
directory=/home/overflow/sync
username=overflow
logfile=/home/overflow/.GreenLuke.log
quietMode=0
noServerMode=0

token="something" # maybe from pwgen pwgen 100

TokenFile=/dev/shm/GreenLuke$$.token
IpFile=/dev/shm/GreenLuke$$.ip
SearchFile=/dev/shm/GreenLuke$$.search

echo -n $token > $TokenFile

log() {
	if test $quietMode != 0; then
		hackedPipe=false
	else
		hackedPipe=cat
	fi
	date "+%Y-%m-%d %H:%M:%S : " | tr -d '\n' | tee -a $logfile | $hackedPipe
	tee -a $logfile | $hackedPipe
}

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

if test $noServerMode = 0; then
	listen $port &
	sleep 3s
fi

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
