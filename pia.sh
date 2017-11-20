#!/bin/bash

## pia v0.2 Copyright (C) 2017 d4rkcat (thed4rkcat@yandex.com)
#
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License Version 2 as published by
## the Free Software Foundation.
#
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License at (http://www.gnu.org/licenses/) for
## more details.

fupdate()						# Update the PIA openvpn files.
{
	CONFIGDEFAULT="https://www.privateinternetaccess.com/openvpn/openvpn.zip"
	CONFIGSTRONG="https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip"
	CONFIGIP="https://www.privateinternetaccess.com/openvpn/openvpn-ip.zip"
	CONFIGTCP="https://www.privateinternetaccess.com/openvpn/openvpn-tcp.zip"
	CONFIGTCPSTRONG="https://www.privateinternetaccess.com/openvpn/openvpn-strong-tcp.zip"

	echo " [$BOLD$BLUE>$RESET] Please choose configuration:"
	echo " $BOLD$RED[$RESET""1""$BOLD$RED]$RESET Default UDP (aes-128-cbc sha1 rsa-2048)"
	echo " $BOLD$RED[$RESET""2""$BOLD$RED]$RESET Strong UDP (aes-256-cbc sha256 rsa-4096)"
	echo " $BOLD$RED[$RESET""3""$BOLD$RED]$RESET Direct IP (aes-128-cbc sha1 rsa-2048)"
	echo " $BOLD$RED[$RESET""4""$BOLD$RED]$RESET Default TCP (aes-128-cbc sha1 rsa-2048)"
	echo " $BOLD$RED[$RESET""5""$BOLD$RED]$RESET Strong TCP (aes-256-cbc sha256 rsa-4096)"
	read -p " [$BOLD$BLUE>$RESET] " CONFIGNUM

	if [[ $CONFIGNUM =~ ^[0-9]+$ && $CONFIGNUM -lt 6 && $CONFIGNUM -gt 0 ]];then
		case $CONFIGNUM in
			1) DOWNURL=$CONFIGDEFAULT;echo " [$BOLD$GREEN*$RESET] Selected Default UDP configuration.";;
			2) DOWNURL=$CONFIGSTRONG;echo " [$BOLD$GREEN*$RESET] Selected Strong UDP configuration.";;
			3) DOWNURL=$CONFIGIP;echo " [$BOLD$GREEN*$RESET] Selected Direct IP configuration.";;
			4) DOWNURL=$CONFIGTCP;echo " [$BOLD$GREEN*$RESET] Selected Default TCP configuration.";;
			5) DOWNURL=$CONFIGTCPSTRONG;echo " [$BOLD$GREEN*$RESET] Selected Strong TCP configuration.";;
		esac
	else
		echo " [$BOLD$RED"'X'"$RESET] $CONFIGNUM is not a valid option! 1-5 only."
		exit 1
	fi
	
	echo " [$BOLD$BLUE>$RESET] Updating PIA openvpn files..."
	rm -rf $VPNPATH/*.ovpn $VPNPATH/servers $VPNPATH/*.crt $VPNPATH/*.pem
	wget -q $DOWNURL -O $VPNPATH/pia.zip
	cd $VPNPATH && unzip -q pia.zip && rm pia.zip
	cd $VPNPATH && for file in *.ovpn;do mv "$file" `echo $file | tr ' ' '_'` &>/dev/null;done
	for file in $VPNPATH/*.ovpn;do
		sed -i 's/auth-user-pass/auth-user-pass pass.txt/' $file
		echo -e "auth-nocache\nlog /var/log/pia.log" >> $file
		echo -n $(basename $file | cut -d '.' -f 1)" " >> $VPNPATH/servers;cat $file | grep .com | awk '{print $2}' >> $VPNPATH/servers
	done
	echo " [$BOLD$GREEN*$RESET] Files Updated."
}

fforward()						# Forward a port.
{
	echo -n " [$BOLD$BLUE>$RESET] Forwarding a port..."
	sleep 1
	if [ ! -f $VPNPATH/client_id ];then head -n 100 /dev/urandom | sha256sum | tr -d " -" > $VPNPATH/client_id;fi
	CNT=0
	while [[ $(echo $FORWARDEDPORT | wc -c) -lt 3 && $CNT -lt 3 ]];do
		FORWARDEDPORT=$(curl -s -m 4 "http://209.222.18.222:2000/?client_id=$(cat $VPNPATH/client_id)" | cut -d ':' -f 2 | cut -d '}' -f 1)
		((++CNT))
	done
}

fnewport()						# Change port forwarded.
{
	NEWPORT=1
	PORTFORWARD=1
	mv $VPNPATH/client_id $VPNPATH/client_id.bak
	head -n 100 /dev/urandom | sha256sum | tr -d " -" > $VPNPATH/client_id
}

ffirewall()						# Set up ufw firewall rules to only allow traffic on tunneled interface and within LAN.
{
	echo y | ufw reset &>/dev/null
	ufw default deny outgoing &>/dev/null
	ufw default deny incoming &>/dev/null
	ufw allow in from $LAN &>/dev/null
	ufw allow out to $LAN &>/dev/null
	ufw allow in on $DEVICE from 0.0.0.0/0 &>/dev/null
	ufw allow out on $DEVICE to 0.0.0.0/0 &>/dev/null
	echo " [$BOLD$GREEN*$RESET] $(ufw enable 2>/dev/null)."
}

fhelp()						# Help function.
{
	echo """Usage: $(basename $0) [Options]

	-s	- Server number to connect to.
	-l	- List available servers.
	-u	- Update PIA openvpn files before connecting.
	-p	- Forward a port.
	-n	- Change to another random port.
	-d	- Change DNS servers to PIA.
	-f	- Enable firewall to block all traffic apart from tun0.
	-m	- Enable PIA MACE ad blocking.
	-k	- Enable internet killswitch.
	-v	- Display verbose information.
	-h	- Display this help.

Examples: 
	pia -dps 24 	- Change DNS, forward a port and connect to Switzerland.
	pia -nfv	- Forward a new port, run firewall and be verbose."""
}

fvpnreset()						# Restore all settings and exit openvpn gracefully.
{
	if [ $DNS -gt 0 ];then
		fdnsrestore
	fi
	kill -s SIGINT $VPNPID &>/dev/null
	if [[ $FIREWALL -gt 0 && $KILLS -eq 0 ]];then
		echo " [$BOLD$GREEN*$RESET] $(ufw disable 2>/dev/null)"
	elif [ $KILLS -gt 0 ];then
		echo -e "\r $BOLD$RED[$BOLD$GREEN*$BOLD$RED] WARNING:$RESET Killswitch engaged, no internet will be available until you run this script again."
	fi
	echo " [$BOLD$GREEN*$RESET] VPN Disconnected."
	exit 0
}

fdnschange()						# Change DNS servers to PIA.
{
	echo " [$BOLD$GREEN*$RESET] Changed DNS to PIA servers."
	cp /etc/resolv.conf /etc/resolv.conf.bak
	echo '''#PIA DNS Servers
nameserver 209.222.18.222
nameserver 209.222.18.218
''' > /etc/resolv.conf.pia
	cp /etc/resolv.conf.pia /etc/resolv.conf
}

fmace()						# Enable PIA MACE DNS based ad blocking.
{
	curl -s "http://209.222.18.222:1111/"
	echo " [$BOLD$GREEN*$RESET] PIA MACE enabled."
}

fdnsrestore()						# Revert to original DNS servers.
{
	echo " [$BOLD$GREEN*$RESET] Restored DNS servers."
	cp /etc/resolv.conf.bak /etc/resolv.conf
}

flist()						# List available servers.
{
	if [ ! -f $VPNPATH/servers ];then
		fupdate
	fi
	
	echo " [$BOLD$GREEN*$RESET]$BOLD$GREEN Green$RESET servers allow port forwarding."
	for i in $(seq $(cat $VPNPATH/servers | wc -l));do
		echo -n " $BOLD$RED[$RESET$i$BOLD$RED]$RESET "
		SERVERNAME=$(cat $VPNPATH/servers | head -n $i | tail -n 1 | awk '{print $1}')
		case $SERVERNAME in
			"Netherlands") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"Switzerland") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"CA_Toronto") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"CA_Montreal") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"Romania") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"Israel") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"Sweden") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"France") echo $BOLD$GREEN$SERVERNAME$RESET;;
			"Germany") echo $BOLD$GREEN$SERVERNAME$RESET;;
			*) echo $SERVERNAME;;
		esac
	done
}

fchecklog()						# Check openvpn logs to get connection state.
{
	LOGRETURN=0
	while [ $LOGRETURN -eq 0 ]; do
		VCONNECT=$(cat /var/log/pia.log)
		if [ $(echo "$VCONNECT" | grep 'Initialization Sequence Completed' | wc -c) -gt 1 ];then
			LOGRETURN=1
		elif [ $(echo "$VCONNECT" | grep 'auth-failure' | wc -c) -gt 1 ];then
			LOGRETURN=2
		elif [ $(echo "$VCONNECT" | grep 'RESOLVE: Cannot resolve host address' | wc -c) -gt 1 ];then
			LOGRETURN=3
		elif [ $(echo "$VCONNECT" | grep 'process exiting' | wc -c) -gt 1 ];then
			LOGRETURN=4
		fi
		sleep 0.2
	done
}

fcheckinput()						# Check if user supplied server number is valid.
{
	if [[ $SERVERNUM =~ ^[0-9]+$ && $SERVERNUM -gt 0 && $SERVERNUM -le $MAXSERVERS ]];then
		:
	else
		flist
		echo " [$BOLD$RED"'X'"$RESET] $SERVERNUM is not valid! 1-$MAXSERVERS only."
		exit 1
	fi
}

fping()						# Get latency to VPN server.
{
	PING=$(ping -c 3 $1 | grep rtt | cut -d '/' -f 4 | awk '{print $3}')
	PINGINT=$(echo $PING | cut -d '.' -f 1)
	SPEEDCOLOR=$BOLD$GREEN
	SPEEDNAME="fast"
	if [ $PINGINT -gt 40 ];then
		SPEEDCOLOR=$BOLD$CYAN
		SPEEDNAME="medium"
	fi
	if [ $PINGINT -gt 80 ];then
		SPEEDCOLOR=$BOLD$BLUE
		SPEEDNAME="slow"
	fi
	if [ $PINGINT -gt 160 ];then
		SPEEDCOLOR=$BOLD$RED
		SPEEDNAME="very slow"
	fi
}

						# Colour codes for terminal.
BOLD=$(tput bold)
BLUE=$(tput setf 1)
GREEN=$(tput setf 2)
CYAN=$(tput setf 3)
RED=$(tput setf 4)
RESET=$(tput sgr0)

						# This is where we will store PIA openVPN files and user config.
VPNPATH='/etc/openvpn/pia'

						# Initialize switches.
PORTFORWARD=0
NEWPORT=0
NOPORT=0
MACE=0
KILLS=0
DNS=0
FORWARDEDPORT=0
VERBOSE=0
FIREWALL=0
SERVERNUM=0

						# Check if user is root.
if [ $(id -u) != 0 ];then echo " [$BOLD$RED"'X'"$RESET] Script must be run as root." && exit 1;fi

						# Check for missing dependencies and install.
if [ $(uname -r | grep ARCH | wc -c) -gt 1 ];then
	command -v openvpn >/dev/null 2>&1 || { echo >&2 " [$BOLD$GREEN*$RESET] openvpn required, installing...";pacman --noconfirm -S openvpn; }
	command -v ufw >/dev/null 2>&1 || { echo >&2 " [$BOLD$GREEN*$RESET] ufw required, installing...";pacman --noconfirm -S ufw; }
else
	command -v apt-get >/dev/null 2>&1 || { echo >&2 " [$BOLD$RED"'X'"$RESET] OS not detected as Arch or Debian, Please install openvpn and ufw packages for your system and retry.";exit 1; }
	command -v openvpn >/dev/null 2>&1 || { echo >&2 " [$BOLD$GREEN*$RESET] openvpn required, installing...";apt-get install -y openvpn; }
	command -v ufw >/dev/null 2>&1 || { echo >&2 " [$BOLD$GREEN*$RESET] ufw required, installing...";apt-get install -y ufw; }
fi

if [ ! -d $VPNPATH ];then mkdir -p $VPNPATH;fi

						# Check for existence of credentials file.
if [ ! -f $VPNPATH/pass.txt ];then
	fupdate
	read -p " [$BOLD$BLUE>$RESET] Please enter your username: " USERNAME
	read -sp " [$BOLD$BLUE>$RESET] Please enter your password: " PASSWORD
	echo -e "$USERNAME\n$PASSWORD" > $VPNPATH/pass.txt
	echo
	chmod 400 $VPNPATH/pass.txt
	unset USERNAME PASSWORD
fi

MAXSERVERS=$(cat $VPNPATH/servers | wc -l)
LAN=$(hostname --ip-address | awk '{print $1}' | cut -d '.' -f 1-3)".0/24"

						# Check for the killswitch and allow ourselves out the firewall.
if [ -f $VPNPATH/.killswitch ];then
	ufw disable&>/dev/null
	rm $VPNPATH/.killswitch
fi

while getopts "lhupnmkdfvs:" opt
do
 	case $opt in
 		l) flist;exit 0;;
		h) fhelp;exit 0;;
		u) fupdate;;
		p) PORTFORWARD=1;;
		n) fnewport;;
		m) MACE=1;DNS=1;;
		k) KILLS=1;FIREWALL=1;echo > $VPNPATH/.killswitch;;
		d) DNS=1;;
		f) FIREWALL=1;;
		v) VERBOSE=1;curl -s icanhazip.com > /tmp/ip.txt&;;
		s) SERVERNUM=$OPTARG;;
		*) echo " [$BOLD$RED"'X'"$RESET] Error: Unrecognized arguments.";fhelp;exit 1;;
	esac
done

if [ $SERVERNUM -lt 1 ];then
	echo " [$BOLD$BLUE>$RESET] Please choose a server: "
	flist
	read -p " [$BOLD$BLUE>$RESET] " SERVERNUM
	clear
fi

fcheckinput
SERVERNAME=$(cat $VPNPATH/servers | head -n $SERVERNUM | tail -n 1 | awk '{print $1}')
DOMAIN=$(cat $VPNPATH/servers | head -n $SERVERNUM | tail -n 1 | awk '{print $2}')
CONFIG=$SERVERNAME.ovpn

if [ $VERBOSE -gt 0 ];then
	echo -n " [$BOLD$BLUE>$RESET] Testing latency to $DOMAIN..."
	fping $DOMAIN
	echo -e "\r [$BOLD$GREEN*$RESET] $SERVERNAME latency: $SPEEDCOLOR$PING ms ($SPEEDNAME)$RESET                    "
fi

trap fvpnreset INT
echo -n " [$BOLD$BLUE>$RESET] Connecting to $BOLD$GREEN$SERVERNAME$RESET, Please wait..."
cd $VPNPATH && openvpn --config $CONFIG --daemon
VPNPID=$(ps aux | grep openvpn | grep root | grep -v grep | awk '{print $2}')

fchecklog

case $LOGRETURN in
	1) echo -e "\r [$BOLD$GREEN*$RESET]$BOLD$GREEN Connected$RESET, OpenVPN is running daemonized on PID $BOLD$CYAN$VPNPID$RESET                    ";;
	2) echo -e "\r [$BOLD$RED"'X'"$RESET] Authorization Failed. Please rerun script to enter correct login details.                    ";rm $VPNPATH/pass.txt;exit 1;;
	3) echo -e "\r [$BOLD$RED"'X'"$RESET] OpenVPN failed to resolve $DOMAIN.                    ";kill -s SIGINT $VPNPID&>/dev/null;exit 1;;
	4) echo -e "\r [$BOLD$RED"'X'"$RESET] OpenVPN exited unexpectedly. Please review log:                    ";cat /var/log/pia.log;exit 1;;
esac

PLOG=$(cat /var/log/pia.log)
if [ $VERBOSE -gt 0 ];then
	echo " [$BOLD$GREEN*$RESET] OpenVPN Logs:"
	echo -n $CYAN
	while IFS= read -r LNE ; do echo "     $LNE" | awk '{$1=$2=$3=$4=$5=""; print $0}';done <<< "$PLOG"
	echo "$RESET [$BOLD$BLUE>$RESET] OpenVPN Settings:"
	SETTINGS=$(cat $VPNPATH/$CONFIG)
	if [ $(echo "$SETTINGS" | grep 'proto udp' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$GREEN UDP$RESET Protocol."
	fi
	if [ $(echo "$SETTINGS" | grep 'proto tcp' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$CYAN TCP$RESET Protocol."
	fi
	if [ $(echo "$SETTINGS" | grep 'ca ca.rsa.2048.crt' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$CYAN 2048 Bit RSA$RESET Certificate."
	fi
	if [ $(echo "$SETTINGS" | grep 'ca ca.rsa.4096.crt' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$GREEN 4096 Bit RSA$RESET Certificate."
	fi
	if [ $(echo "$SETTINGS" | grep 'cipher aes-128-cbc' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$CYAN 128 Bit AES-CBC$RESET Cipher."
	fi
	if [ $(echo "$SETTINGS" | grep 'cipher aes-256-cbc' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$GREEN 256 Bit AES-CBC$RESET Cipher."
	fi
	if [ $(echo "$SETTINGS" | grep 'auth sha1' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$CYAN SHA1$RESET Authentication."
	fi
	if [ $(echo "$SETTINGS" | grep 'auth sha256' | wc -c) -gt 3 ];then
		echo " [$BOLD$GREEN*$RESET]$BOLD$GREEN SHA256$RESET Authentication."
	fi

	NEWIP=''
	CURRIP=$(cat /tmp/ip.txt)
	rm /tmp/ip.txt
	echo  -n " [$BOLD$BLUE>$RESET] Fetching IP..."
	sleep 1
	while [ $(echo $NEWIP | wc -c) -lt 2 ];do
		NEWIP=$(curl -s -m 4 icanhazip.com)
	done

	WHOISOLD="$(whois $CURRIP)"
	WHOISNEW="$(whois $NEWIP)"
	COUNTRYOLD=$(echo "$WHOISOLD" | grep country | head -n 1)
	COUNTRYNEW=$(echo "$WHOISNEW" | grep country | head -n 1)
	DESCROLD="$(echo "$WHOISOLD" | grep descr)"$RESET
	DESCRNEW="$(echo "$WHOISNEW" | grep descr)"$RESET
	
	echo -e "\r [$BOLD$BLUE>$RESET] Old IP:$RED$BOLD $CURRIP"
	while IFS= read -r LNE ; do echo "     $LNE";done <<< "$COUNTRYOLD"
	while IFS= read -r LNE ; do echo "     $LNE";done <<< "$DESCROLD"
	echo -e " [$BOLD$BLUE>$RESET] Current IP:$GREEN$BOLD $NEWIP"
	while IFS= read -r LNE ; do echo "     $LNE";done <<< "$COUNTRYNEW"
	while IFS= read -r LNE ; do echo "     $LNE";done <<< "$DESCRNEW"
fi

DEVICE=$(echo "$PLOG" | grep 'TUN/TAP device' | awk '{print $8}')

if [ $DNS -gt 0 ];then
	fdnschange
fi

if [ $MACE -gt 0 ];then
	fmace
fi

if [ $FIREWALL -gt 0 ];then
	ffirewall
fi

if [[ $KILLS -gt 0 && $VERBOSE -gt 0 ]];then
	echo " [$BOLD$BLUE>$RESET] Killswitch is active and enabled on system startup."
fi

if [ $PORTFORWARD -gt 0 ];then
	case $SERVERNAME in
		"Netherlands") fforward;;
		"Switzerland") fforward;;
		"CA_Toronto") fforward;;
		"CA_Montreal") fforward;;
		"Romania") fforward;;
		"Israel") fforward;;
		"Sweden") fforward;;
		"France") fforward;;
		"Germany") fforward;;
		*) NOPORT=1;;
	esac
	if [ $NOPORT -eq 0 ];then
		if [ $NEWPORT -gt 0 ]; then
			echo -e "\r [$BOLD$GREEN*$RESET] Identity changed to $BOLD$GREEN$(cat $VPNPATH/client_id)$RESET"
		else
			if [ $VERBOSE -gt 0 ];then
				echo -e "\r [$BOLD$BLUE>$RESET] Using port forwarding identity $BOLD$CYAN$(cat $VPNPATH/client_id)$RESET"
			fi
		fi

		if [ $FORWARDEDPORT -gt 0 ] &>/dev/null;then
			echo -e "\r [$BOLD$GREEN*$RESET] Port $GREEN$BOLD$FORWARDEDPORT$RESET has been forwarded to you.                    "
		else
			echo -e "\r [$BOLD$RED"'X'"$RESET] $SERVERNAME failed to forward us a port!                   "
		fi
	else
		echo " [$BOLD$RED"'X'"$RESET] Port forwarding is only available at: Netherlands, Switzerland, CA_Toronto, CA_Montreal, Romania, Israel, Sweden, France and Germany."
	fi
fi

echo -n " [$BOLD$GREEN*$RESET] VPN setup complete, press$BOLD$RED ENTER$RESET or$BOLD$RED Ctrl+C$RESET to shut down."
read -p "" WAITVAR
fvpnreset
