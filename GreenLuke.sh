#!/bin/bash
# dependencies: ssh, sshd, unison, awk, iproute2, socat, zenity

port=1337
minSleep=$((60*10))	# in s
maxSleep=$((60*60))	# in s
directory=/home/overflow/sync
username=overflow
logfile=/home/overflow/.GreenLuke.log
quietMode=0


IpFile=/dev/shm/GreenLuke$$.ip
SearchFile=/dev/shm/GreenLuke$$.search

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
	echo "trying to establish connection with $remoteIp" | log
	echo "testing for public key auth..." | log
	ssh -q -o BatchMode=yes $username@$remoteIp true 2> /dev/null
	if test $? != 0; then
		echo "... no public key auth, stopping here" | log
		return
	fi
	echo "testing server..." | log
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
		remoteIp=$(echo $(hostname) | socat -T 3 UDP-LISTEN:$port -) 
		sleep 1s 	# otherwise our logfiles get messed up
		echo "incomming request" | log
		if test "$remoteIp" == "$(getIp)"; then
			echo "oh, that's me. ignoring ourself" | log
		else
			setSearch 0
			connect $remoteIp
			setSearch 1
		fi
	done
}

listen $port &

sleep 3s

while true; do
	if test $(getSearch) != 0; then
		echo "searching... " | log
		ip=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | awk -F'/' '{print $1}')
		remoteHostname=$(echo $ip | socat - UDP-DATAGRAM:255.255.255.255:$port,broadcast)
		setIp $ip
		echo "found: $remoteHostname" | log
	fi
	sleep  $(($RANDOM % ($maxSleep - $minSleep) + $minSleep))
done
