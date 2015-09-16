#!/bin/bash
# dependencies: ssh, sshd, unison, awk, iproute2, socat, zenity

port=1337
minSleep=$((60*10))	# in s
maxSleep=$((60*60))	# in s
directory=/home/overflow/sync
username=overflow
logfile=/home/overflow/.GreenLuke.log


IpFile=/dev/shm/GreenLuke$$.ip
SearchFile=/dev/shm/GreenLuke$$.search

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
	echo "trying to establish connection with $remoteIp" | tee -a $logfile
	echo "testing for public key auth..." | tee -a $logfile
	ssh -q -o BatchMode=yes $username@$remoteIp true 2> /dev/null
	if test $? != 0; then
		echo "... no public key auth, stopping here" | tee -a $logfile
		return
	fi
	echo "testing server..." | tee -a $logfile
	unison $directory ssh://$username@$remoteIp/$directory -ui text -testserver 2>&1 | tee -a $logfile
	if test $? != 0; then
		echo "... unison error. : (" | tee -a $logfile
		return
	fi
	echo "let's get this party started" | tee -a $logfile
	message=$(echo | unison $directory ssh://$username@$remoteIp/$directory -auto -owner -terse -batch 2>&1) 
	echo $message | tee -a $logfile
	unisonError=$?
	if test $unisonError != 0; then
		echo "unison return some error" | tee -a $logfile
		echo "informing user" | tee -a $logfile
		if test $unisonError == 1; then
			zenity --warning --text="$(echo $message | tr -d '<' | tr -d '>' |)" --title=="GreenLuke"
		else
			zenity --error --text="There was a critical error while synchronizing.\nGreenLuke will exit now.\nPlease check out $log" --title="GreenLuke"
			echo "exiting" | tee -a $logfile
			exit
		fi
	fi
	echo "successfully synchronized." | tee -a $logfile
	echo "restarting daemon." | tee -a $logfile
}

listen() {
	while true; do		
		echo "listening..." | tee -a $logfile
		remoteIp=$(echo $(hostname) | socat -T 3 UDP-LISTEN:$port -) 
		echo "incomming request" | tee -a $logfile
		if test "$remoteIp" == "$(getIp)"; then
			echo "oh, that's me. ignoring ourself" | tee -a $logfile
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
		echo -n "searching... " | tee -a $logfile
		ip=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | awk -F'/' '{print $1}')
		remoteHostname=$(echo $ip | socat - UDP-DATAGRAM:255.255.255.255:$port,broadcast)
		setIp $ip
		echo "found: $remoteHostname" | tee -a $logfile
	fi
	sleep  $(($RANDOM % ($maxSleep - $minSleep) + $minSleep))
done
