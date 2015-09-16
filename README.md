# GreenLuke
Synchronize multiple PCs in your local network.

Well, I'm not questioning that this is complete garbage, but hey: It works.

Dependencies: ssh, sshd, unison, awk, iproute2, socat, zenity

To make this peace of shit work do the following: 
- Install all dependencies.
- Setup public key auth for ssh across _all_ machines you want to sync.
(Just to be clear: If you have 3 PCs A, B and C, then A is authorized at B and C, B is authorized at A and C and C is authorized at A and C.)
- Run this script at login on all machines (make sure X11 is running, otherwise you won't get any error messages).

This script has security issues, use at your own risk.
