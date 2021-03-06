#!/bin/bash

## pia v0.5 Copyright (C) 2017 d4rkcat (thed4rkcat@yandex.com)
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

# needed packages
DEPENDENCIES=( "openvpn" "openssl" "iptables" "curl" "unzip" "whois" )

fupdate()						# Update the PIA openvpn files.
{
	###  LOCAL DECLARATIONS ###
	##
	#

	# list of the available servers connection protocols
	Protocols=(
		"Default UDP (aes-128-cbc sha1 rsa-2048)"
		"Strong UDP (aes-256-cbc sha256 rsa-4096)"
		"Direct IP (aes-128-cbc sha1 rsa-2048)"
		"Default TCP (aes-128-cbc sha1 rsa-2048)"
		"Strong TCP (aes-256-cbc sha256 rsa-4096)"
	)
	# list of their related archives
	Url="https://www.privateinternetaccess.com/openvpn"
	Url_zip=(
		"$Url/openvpn.zip"
		"$Url/openvpn-strong.zip"
		"$Url/openvpn-ip.zip"
		"$Url/openvpn-tcp.zip"
		"$Url/openvpn-strong-tcp.zip"
	)

	# NEWS expressions will replace OLDS in .ovpn files
	OLDS=(
		"auth-user-pass"
		"crl-verify crl.rsa.2048.pem"
		"crl-verify crl.rsa.4096.pem"
		"ca ca.rsa.2048.crt"
		"ca ca.rsa.4096.crt"
		"verb 1"
	)
	NEWS=(
		"auth-user-pass $VPNPATH/pass.txt"
		"crl-verify $VPNPATH/crl.rsa.2048.pem"
		"crl-verify $VPNPATH/crl.rsa.4096.pem"
		"ca $VPNPATH/ca.rsa.2048.crt"
		"ca $VPNPATH/ca.rsa.4096.crt"
		"verb 2"
	)

	### TRAPS ###
	##
	#
	err_report() {
		local lc="$BASH_COMMAND" rc=$?
		echo "Error on line $1 IN $2. $lc exited with code $rc."
		echo "arg: $3"
		trap - ERR
	}
	trap 'err_report $LINENO $FUNCNAME $_ && return 1' ERR

	### MAIN ###
	##
	#
	printf "$PROMPT $BOLD%s$RESET\n" "Server configuration update"

	# Ask for protocol to use if not set yet
	if [ $CONFIGNUM -eq 0 ];then
		printf "$PROMPT %s\n" "Please choose configuration:"

		# Display options menu
		Format=" $BOLD$RED[$RESET%d$BOLD$RED]$RESET %s\n"
		for i in ${!Protocols[@]}; do
			# for convenience, displayed index starts from number 1
			printf "$Format" "$((i+1))" "${Protocols[$i]}"
		done

		# Prompt for user choice
		while true; do
			read -p "$PROMPT " CONFIGNUM
			size=${#Protocols[@]}
			last_index=$(( size - 1 ))

			if [[ $CONFIGNUM =~ ^[0-9]$ ]] ; then
				index=$((CONFIGNUM-1))
				if  (( index >= 0 )) && (( index <= last_index )); then
					printf "$INFO Selected %s.\n" "${Protocols[$index]}"
					break
				fi
			fi
			printf "$ERROR $CONFIGNUM is not a valid option! 1-%d only.\n" "${#Protocols[@]}"
		done
	fi

	# Download archive to temporary directory
	TMPDIR=$(mktemp -d)
	index=$((CONFIGNUM-1))
	DOWNURL=${Url_zip[$index]}
	printf "$PROMPT Updating PIA openvpn files...\n"
	# check files exists before downloading
	if (curl -s -S -o /dev/null --head --fail $DOWNURL); then
		curl --silent -o $TMPDIR/pia.zip $DOWNURL
	else
		printf "$ERROR Unable to download archive from $DOWNURL.\n"
		rm -r $TMPDIR
		return 1
	fi

	# work in temporary directory
	# before moving all to $VPNPATH
	pushd . >/dev/null
	cd $TMPDIR
	unzip -q pia.zip && rm pia.zip
	# save config information for auto-update
	echo "$CONFIGNUM $DOWNURL $(curl -sI $DOWNURL | grep Last-Modified | cut -d ' ' -f 2-)" > configversion.txt

	# linuxify ovpn files name
	for FILE in *.ovpn; do
		NEWNAME=$(tr ' ' '_' <<< $FILE)
		[[ $NEWNAME != $FILE ]] && mv "$FILE" "$NEWNAME" &>/dev/null
	done

	# ovpn files parsing
	for FILE in *.ovpn; do
		# update configuration files
		for i in ${!OLDS[@]};do
			sed -i "s|${OLDS[$i]}|${NEWS[$i]}|g" $FILE
		done
		printf "auth-nocache\n"         >> $FILE
		printf "log /var/log/pia.log\n" >> $FILE

		# updating servers list
		server="$(basename $FILE .ovpn)"
		cname="$(cat $FILE | grep -e "^remote\s" | cut -d' ' -f2)"
		echo "$server $cname" >> servers.txt
	done

	# remove and replace old configuration files
	rm -f $VPNPATH/*.ovpn $VPNPATH/servers.txt $VPNPATH/*.crt $VPNPATH/*.pem
	mv $TMPDIR/* $VPNPATH

	# clean
	popd >/dev/null
	rmdir $TMPDIR

	# success
	printf "\r$INFO Files Updated.\n"
	return 0
}

fforward()						# Forward a port.
{
	echo -n "$PROMPT Forwarding a port..."
	sleep 1.5
	if [ ! -f $VPNPATH/client_id ];then head -n 100 /dev/urandom | sha256sum | tr -d " -" > $VPNPATH/client_id;fi
	while [ $(echo $FORWARDEDPORT | wc -c) -lt 3 ];do
		FORWARDEDPORT=$(curl -s -m 4 "http://209.222.18.222:2000/?client_id=$(cat $VPNPATH/client_id)" | cut -d ':' -f 2 | cut -d '}' -f 1)
	done
}

fnewport()						# Change port forwarded.
{
	NEWPORT=1
	PORTFORWARD=1
	mv $VPNPATH/client_id $VPNPATH/client_id.bak
	head -n 100 /dev/urandom | sha256sum | tr -d " -" > $VPNPATH/client_id
}

ffirewall()						# Set up iptables firewall rules to only allow traffic on tunneled interface and (optionally) within LAN.
{
	fresetfirewall
	LAN=$(ip route show | grep default | awk '{print $3 }' | cut -d '.' -f 1-3)".0/24"
	DEFAULTDEVICE=$(ip route show | grep default | awk '{print $5}')
	VPNDEVICE=$(echo "$PLOG" | grep 'TUN/TAP device' | awk '{print $8}')
	VPNPORT=$(cat $VPNPATH/$CONFIG | grep 'remote ' | awk '{print $3}')
	PROTO=$(cat $VPNPATH/$CONFIG | grep proto | awk '{print $2}')

	iptables -P OUTPUT DROP																# default policy for outgoing packets
	iptables -P INPUT DROP																# default policy for incoming packets
	iptables -P FORWARD DROP															# default policy for forwarded packets

	# allowed outputs
	iptables -A OUTPUT -o lo -j ACCEPT													# enable localhost out
	iptables -A OUTPUT -o $VPNDEVICE -j ACCEPT											# enable outgoing connections on tunnel
	if [[ "$PROTO" == "udp" ]];then
		iptables -A OUTPUT -o $DEFAULTDEVICE -p udp --dport $VPNPORT -j ACCEPT			# enable port for communicating with PIA on default device
	else
		iptables -A OUTPUT -o $DEFAULTDEVICE -p tcp --dport $VPNPORT -j ACCEPT
	fi

	# allowed inputs
	iptables -A INPUT -i lo -j ACCEPT													# enable localhost in
	iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT					# enable requested packets on tunnel

	if [ $PORTFORWARD -eq 1 ];then
		iptables -A INPUT -i $VPNDEVICE -p tcp --dport $FORWARDEDPORT -j ACCEPT			# enable port forwarding
		iptables -A INPUT -i $VPNDEVICE -p udp --dport $FORWARDEDPORT -j ACCEPT
	fi

	if [ $FLAN -eq 1 ];then
		iptables -A OUTPUT -o $DEFAULTDEVICE -d $LAN -j ACCEPT							# enable incoming and outgoing connections within LAN (potentially dangerous!)
		iptables -A INPUT -i $DEFAULTDEVICE -s $LAN -j ACCEPT
	fi
	echo "$INFO Firewall enabled."
}

fresetfirewall()
{
	iptables --policy INPUT ACCEPT
	iptables --policy OUTPUT ACCEPT
	iptables --policy FORWARD ACCEPT
	iptables -Z
	iptables -F
	iptables -X
}

flockdown()
{
	fresetfirewall
	iptables -P OUTPUT DROP
	iptables -P INPUT DROP
	iptables -P FORWARD DROP
}

fhelp()						# Help function.
{
	cat <<-EOF

	Usage:
	 $PNAME [options]

	Options:
	 -d, --dns          change DNS servers to PIA.
	 -e, --allow-lan    allow LAN through firewall.
	 -f, --firewall     enable firewall to block all non tunnel traffic.
	 -h, --help         display this help.
	 -l, --list-servers list available servers.
	 -k, --killswitch   enable internet killswitch.
	 -m, --pia-mace     enable PIA MACE ad blocking.
	 -n, --new-port     change to another random port.
	 -p, --port-forward forward a port.
	 -s, --server <num> connect to server number "num". See list-servers for number.
	 -u, --update       update PIA openvpn files before connecting.
	 -v, --verbose      display verbose information.
	 -x, --encrypt      encrypt the credentials file.

	Examples:
	 pia -dps 6    -->  change DNS, forward a port and connect to CA_Montreal.
	 pia -nfv	   -->  forward a new port, run firewall and be verbose.
	EOF
}

fvpnreset()						# Restore all settings and exit openvpn gracefully.
{
	echo
	if [ $DNS -eq 1 ];then
		fdnsrestore
	fi

	kill -s SIGINT $VPNPID &>/dev/null

	if [ $RESTARTVPN -eq 0 ];then
		if [[ $FIREWALL -eq 1 && $KILLS -eq 0 ]];then
			fresetfirewall
			echo "$INFO Firewall disabled."
		elif [[ $KILLS -eq 1 && $RESTARTVPN -lt 1 ]];then
			echo -e "\r $BOLD$RED[$BOLD$GREEN*$BOLD$RED] WARNING:$RESET Killswitch engaged, no internet will be available until you run this script again."
			flockdown
			echo > $VPNPATH/.killswitch
		fi

		echo "$INFO VPN Disconnected."
		exit 0
	else
		RESTARTVPN=0
		echo "$PROMPT Restarting VPN..."
	fi
}

fdnschange()						# Change DNS servers to PIA.
{
	cp /etc/resolv.conf /etc/resolv.conf.bak
	echo '''#PIA DNS Servers
nameserver 209.222.18.222
nameserver 209.222.18.218
''' > /etc/resolv.conf.pia
	cp /etc/resolv.conf.pia /etc/resolv.conf
	echo "$INFO Changed DNS to PIA servers."
}

fmace()						# Enable PIA MACE DNS based ad blocking.
{
	curl -s "http://209.222.18.222:1111/"
	echo "$INFO PIA MACE enabled."
}

fdnsrestore()						# Revert to original DNS servers.
{
	cp /etc/resolv.conf.bak /etc/resolv.conf
	echo "$INFO Restored DNS servers."
}

flist()
{
	# Display a numbered list of available servers.
	# Servers that allow port forwarding are displayes in green

	local num servername cname
	portforward=(
		"CA_Montreal"
		"CA_Toronto"
		"CA_Vancouver"
		"Czech_Republic"
		"DE_Berlin"
		"DE_Frankfurt"
		"France"
		"Israel"
		"Romania"
		"Spain"
		"Sweden"
		"Switzerland"
		)

	echo "$INFO$BOLD$GREEN Green$RESET servers allow port forwarding."
	while read num servername cname; do
		printf " $BOLD$RED[$RESET%d$BOLD$RED]$RESET " $num
		if [[ ${portforward[@]} =~ $servername ]]; then
			echo $BOLD$GREEN$servername$RESET
		else
			echo $servername
		fi
	done <<< $(cat -n $VPNPATH/servers.txt)
}

fchecklog()						# Check openvpn logs to get connection state.
{
	LOGRETURN=0
	while [ $LOGRETURN -eq 0 ];do
		VCONNECT=$(cat /var/log/pia.log)
		if [ $(echo "$VCONNECT" | grep 'auth-failure' | wc -c) -gt 1 ];then
			LOGRETURN=2
		elif [ $(echo "$VCONNECT" | grep 'RESOLVE: Cannot resolve host address' | wc -c) -gt 1 ];then
			LOGRETURN=3
		elif [ $(echo "$VCONNECT" | grep 'process exiting' | wc -c) -gt 1 ];then
			LOGRETURN=4
		elif [ $(echo "$VCONNECT" | grep 'Exiting due to fatal error' | wc -c) -gt 1 ];then
			LOGRETURN=5
		elif [ $(echo "$VCONNECT" | grep 'ERROR: Linux route add command failed:' | wc -c) -gt 1 ];then
			LOGRETURN=6
		elif [ $(echo "$VCONNECT" | grep 'Initialization Sequence Completed' | wc -c) -gt 1 ];then
			LOGRETURN=1
		fi
		sleep 0.2
	done
}

fping()						# Get latency to VPN server.
{
	PINGINT=0
	while [ $PINGINT -lt 1 ];do
		PING=$(ping -c 3 $1 | grep rtt | cut -d '/' -f 4 | awk '{print $3}')
		PINGINT=$(echo $PING | cut -d '.' -f 1)
	done
	
	SPEEDCOLOR=$BOLD$GREEN
	SPEEDNAME="fast"
	if [ $PINGINT -gt 39 ];then
		SPEEDCOLOR=$BOLD$CYAN
		SPEEDNAME="medium"
	fi
	if [ $PINGINT -gt 79 ];then
		SPEEDCOLOR=$BOLD$BLUE
		SPEEDNAME="slow"
	fi
	if [ $PINGINT -gt 159 ];then
		SPEEDCOLOR=$BOLD$RED
		SPEEDNAME="very slow"
	fi
}

fcheckupdate()						# Check if a new config zip is available and download.
{
	CONFIGNUM=$(cat $VPNPATH/configversion.txt | cut -d ' ' -f 1)
	CONFIGURL=$(cat $VPNPATH/configversion.txt | cut -d ' ' -f 2)
	CONFIGVERSION=$(cat $VPNPATH/configversion.txt | cut -d ' ' -f 3-)
	CONFIGMODIFIED=''
	while [ $(echo $CONFIGMODIFIED | wc -c) -lt 6 ];do
		CONFIGMODIFIED=$(curl -sI $CONFIGURL | grep Last-Modified | cut -d ' ' -f 2-)
	done
	if [ $(echo $CONFIGMODIFIED | wc -c) -gt 6 ];then
		if [ "$CONFIGVERSION" != "$CONFIGMODIFIED" ];then
			RESTARTVPN=1
			echo "$ERROR WARNING: OpenVPN configuration is out of date!"
			echo "$PROMPT New PIA OpenVPN config file available! Updating..."
		else
			if [[ $VERBOSE -eq 1 && UPDATEOUTPUT -eq 1 ]];then
				echo "$INFO OpenVPN configuration up to date: $CONFIGMODIFIED"
			fi
		fi
	else
		if [ $UPDATEOUTPUT -eq 1 ];then
			echo "$ERROR Failed to check OpenVPN config Last-Modified date!"
		fi
	fi
	UPDATEOUTPUT=0
}

fconnect()						# Main function
{
	if [ $UNLOCK -eq 1 ];then
		fresetfirewall
		UNLOCK=0
	fi

	if [ $VERBOSE -eq 1 ];then
		echo -n "$PROMPT Testing latency to $DOMAIN..."
		fping $DOMAIN
		echo -e "\r$INFO $SERVERNAME latency: $SPEEDCOLOR$PING ms ($SPEEDNAME)$RESET                       "
	fi

	if [[ -f $VPNPATH/pass.enc && $(echo $CREDS | wc -c) -lt 3 ]];then
		fdecryptcreds
	fi

	if [ $(echo $CREDS | wc -c) -gt 3 ];then
		echo "$CREDS" > $VPNPATH/pass.txt
	fi

	echo -n "$PROMPT Connecting to $BOLD$GREEN$SERVERNAME$RESET, Please wait..."
	cd $VPNPATH && openvpn --config $CONFIG --daemon
	VPNPID=$(ps aux | grep openvpn | grep root | grep -v grep | awk '{print $2}')

	fchecklog

	case $LOGRETURN in
		1) echo -e "\r$INFO$BOLD$GREEN Connected$RESET, OpenVPN is running daemonized on PID $BOLD$CYAN$VPNPID$RESET                    ";;
		2) echo -e "\r$ERROR Authorization Failed. Please rerun script to enter correct login details.                    ";rm $VPNPATH/pass.txt;kill -s SIGINT $VPNPID&>/dev/null;exit 1;;
		3) echo -e "\r$ERROR OpenVPN failed to resolve $DOMAIN.                    ";kill -s SIGINT $VPNPID&>/dev/null;exit 1;;
		4) echo -e "\r$ERROR OpenVPN exited unexpectedly. Please review log:                    ";cat /var/log/pia.log;kill -s SIGINT $VPNPID&>/dev/null;exit 1;;
		5) echo -e "\r$ERROR OpenVPN suffered a fatal error. Please review log:                    ";cat /var/log/pia.log;kill -s SIGINT $VPNPID&>/dev/null;exit 1;;
		6) echo -e "\r$ERROR OpenVPN failed to add routes. Please review log:                    ";cat /var/log/pia.log;kill -s SIGINT $VPNPID&>/dev/null;exit 1;;
	esac

	if [ $ENCRYPT -eq 1 ];then
		CREDS="$(cat $VPNPATH/pass.txt 2>/dev/null)"
		fencryptcreds
	fi

	UPDATEOUTPUT=1
	fcheckupdate
	if [ $RESTARTVPN -eq 1 ];then
		fupdate
		fvpnreset
		return 0
	fi

	PLOG=$(cat /var/log/pia.log)

	if [ $VERBOSE -eq 1 ];then
		echo "$INFO OpenVPN Logs:"
		echo -n $CYAN
		while IFS= read -r LNE ;do echo "     $LNE" | awk '{$1=$2=$3=$4=$5=""; print $0}';done <<< "$PLOG"
		echo "$RESET$PROMPT OpenVPN Settings:"
		SETTINGS=$(cat $VPNPATH/$CONFIG)
		if [ $(echo "$SETTINGS" | grep 'proto udp' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$GREEN UDP$RESET Protocol."
		fi
		if [ $(echo "$SETTINGS" | grep 'proto tcp' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$CYAN TCP$RESET Protocol."
		fi
		if [ $(echo "$SETTINGS" | grep 'ca.rsa.2048.crt' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$CYAN 2048 Bit RSA$RESET Certificate."
		fi
		if [ $(echo "$SETTINGS" | grep 'ca.rsa.4096.crt' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$GREEN 4096 Bit RSA$RESET Certificate."
		fi
		if [ $(echo "$SETTINGS" | grep 'cipher aes-128-cbc' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$CYAN 128 Bit AES-CBC$RESET Cipher."
		fi
		if [ $(echo "$SETTINGS" | grep 'cipher aes-256-cbc' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$GREEN 256 Bit AES-CBC$RESET Cipher."
		fi
		if [ $(echo "$SETTINGS" | grep 'auth sha1' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$CYAN SHA1$RESET Authentication."
		fi
		if [ $(echo "$SETTINGS" | grep 'auth sha256' | wc -c) -gt 3 ];then
			echo "$INFO$BOLD$GREEN SHA256$RESET Authentication."
		fi

		echo  -n "$PROMPT Fetching IP..."
		while [ $(echo $NEWIP | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -c) -lt 3 ];do
			NEWIP=$(curl -s -m 4 icanhazip.com)
		done

		while [ $(echo $MYIP | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -c) -lt 3 ];do
			MYIP=$(cat /tmp/ip.txt)
			sleep 0.3
		done
		
		if [ $(echo $NEWIP | wc -c) -gt 2 ];then
			WHOISOLD="$(whois $MYIP)"
			WHOISNEW="$(whois $NEWIP)"
			COUNTRYOLD=$(echo "$WHOISOLD" | grep country | head -n 1)
			COUNTRYNEW=$(echo "$WHOISNEW" | grep country | head -n 1)
			DESCROLD="$(echo "$WHOISOLD" | grep descr)"$RESET
			DESCRNEW="$(echo "$WHOISNEW" | grep descr)"$RESET
			
			echo -e "\r$PROMPT Old IP:$RED$BOLD $MYIP"
			if [ $(echo $COUNTRYOLD | wc -c) -gt 8 ];then
				while IFS= read -r LNE ;do echo "     $LNE";done <<< "$COUNTRYOLD"
			fi
			if [ $(echo $DESCROLD | wc -c) -gt 8 ];then
				while IFS= read -r LNE ;do echo "     $LNE";done <<< "$DESCROLD"
			fi
			echo "$PROMPT Current IP:$GREEN$BOLD $NEWIP"
			if [ $(echo $COUNTRYNEW | wc -c) -gt 8 ];then
				while IFS= read -r LNE ;do echo "     $LNE";done <<< "$COUNTRYNEW"
			fi
			if [ $(echo $DESCRNEW | wc -c) -gt 8 ];then
				while IFS= read -r LNE ;do echo "     $LNE";done <<< "$DESCRNEW"
			fi
		else
			echo -e "\r$ERROR Failed to fetch new IP.                   "
		fi
	fi

	if [ $PORTFORWARD -eq 1 ];then
		if [ $NEWPORT -eq 1 ]; then
			echo -e "\r$INFO Identity changed to $BOLD$GREEN$(cat $VPNPATH/client_id)$RESET"
		else
			if [ $VERBOSE -eq 1 ];then
				echo -e "\r$PROMPT Using port forwarding identity $BOLD$CYAN$(cat $VPNPATH/client_id)$RESET"
			fi
		fi
		case $SERVERNAME in
			"CA_Montreal")    fforward;;
			"CA_Toronto")     fforward;;
			"CA_Vancouver")	  fforward;;
			"Czech_Republic") fforward;;
			"DE_Berlin")      fforward;;
			"DE_Frankfurt")   fforward;;
			"France")         fforward;;
			"Israel")         fforward;;
			"Romania")        fforward;;
			"Spain")          fforward;;
			"Sweden")         fforward;;
			"Switzerland")    fforward;;
			*) NOPORT=1;;
		esac

		if [ $NOPORT -eq 0 ];then
			if [ $FORWARDEDPORT -gt 0 ] &>/dev/null;then
				echo -e "\r$INFO Port $GREEN$BOLD$FORWARDEDPORT$RESET has been forwarded to you.                    "
			else
				echo -e "\r$ERROR $SERVERNAME failed to forward us a port!                   "
			fi
		else
			echo "$ERROR Port forwarding is only available at: Netherlands, Switzerland, CA_Toronto, CA_Montreal, CA_Vancouver, Romania, Israel, Sweden, France and Germany."
		fi
	fi

	if [ $DNS -eq 1 ];then
		fdnschange
	fi

	if [ $MACE -eq 1 ];then
		fmace
	fi

	if [ $FIREWALL -eq 1 ];then
		ffirewall
	fi
	if [[ $KILLS -eq 1 && $VERBOSE -eq 1 ]];then
		echo "$PROMPT Killswitch activated."
	fi


	echo -n "$INFO VPN setup complete, press$BOLD$RED Ctrl+C$RESET to shut down."
	flogwatcher
	if [ $RESTARTVPN -eq 0 ];then
		echo -e "\r$ERROR$RED$BOLD WARNING:$RESET New OpenVPN log entries detected:                         "
		NEWLOGS=$(cat /var/log/pia.log | tail -n +$(($LOGLENGTH + 1)) | sed '/^$/d')
		while IFS= read -r LNE ;do echo "$BOLD$RED     $LNE$RESET";done <<< "$NEWLOGS"
		RESTARTVPN=1
		if [ $FIREWALL -eq 1 ];then
			flockdown
			UNLOCK=1
		fi
	else
		fupdate
	fi	
	fvpnreset
}

flogwatcher()						# Check the log for new entries
{
	LOGLENGTH=$(cat /var/log/pia.log | wc -l)
	LOGALERT=$LOGLENGTH
	while [ $LOGALERT -eq $LOGLENGTH ];do
		sleep 20
		LOGALERT=$(cat /var/log/pia.log | wc -l)
		fcheckupdate
		if [ $RESTARTVPN -eq 1 ];then
			return 0
		fi
	done
	
}

fgetip()						# Get external IP
{
	while [ $(echo $MYIP | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -c) -lt 3 ];do
		MYIP=$(curl -m 5 -s icanhazip.com)
	done
	echo $MYIP > /tmp/ip.txt
}

fdecryptcreds()
{
	if [ $(cat $VPNPATH/pass.txt 2>/dev/null | wc -c) -lt 6 ];then	
		if [ $(cat $VPNPATH/pass.enc | wc -c) -gt 3 ];then
			echo "$PROMPT Decrypting creds.."
			cat $VPNPATH/pass.enc | openssl base64 -d | openssl enc -d -aes-256-cbc > $VPNPATH/pass.txt
			chmod 400 $VPNPATH/pass.txt && CREDS="$(cat $VPNPATH/pass.txt 2>/dev/null)" 
			if [ $ENCRYPT -eq 0 ];then
				rm $VPNPATH/pass.enc
			fi
		else
			rm $VPNPATH/pass.enc
		fi
	fi
}

fencryptcreds()
{
	echo "$INFO Encypting creds.."
	cat $VPNPATH/pass.txt 2>/dev/null | openssl enc -e -aes-256-cbc -a > $VPNPATH/pass.enc && rm $VPNPATH/pass.txt && chmod 400 $VPNPATH/pass.enc
}

fcheckroot() {
	# Check if user is root.
	if [[ $(id -u) == 0 ]]; then
		return 0
	else
		echo "$ERROR Script must be run as root."
		return 1
	fi
}

fcheckdependencies() {
	# Check for missing dependencies and install.

	# look out for the package manager
	pkg_managers=("pacman" "apt-get" "yum")
	pkg_command=("pacman --noconfirm -S" "apt-get install -y" "yum install -y")
	for n in ${!pkg_managers[@]}; do
		app=${pkg_managers[n]}
		if [[ $(command -v $app ) ]]; then
			INSTALLCMD=${pkg_command[n]}
			break
		fi
	done

	# test dependencies and install eventually
	for app in ${DEPENDENCIES[@]}; do
		if [[ ! $(command -v $app ) ]]; then
			if [[ ! -v INSTALLCMD ]]; then
				printf "missing dependency: %s\n" "$app"
				MISSINGDEP=1
			else
				printf "$INFO $app required, installing...\n"
				$INSTALLCMD $app
			fi
		fi
	done

	if [ $MISSINGDEP -eq 1 ];then
		echo "$ERROR OS not identified as arch or debian based, please install dependencies."
		exit 1
	fi
}

fcheckfiles() {
	# all configuration files are in VPNPATH
	if [[ ! -d $VPNPATH ]]; then
		mkdir -p $VPNPATH
	fi

	# Check for existence of credentials file.
	if [[ ! -f $VPNPATH/pass.txt && ! -f $VPNPATH/pass.enc ]];then
		local USERNAME PASSWORD
		read -p "$PROMPT Please enter your username: " USERNAME
		read -sp "$PROMPT Please enter your password: " PASSWORD
		echo -e "$USERNAME\n$PASSWORD" > $VPNPATH/pass.txt
		chmod 400 $VPNPATH/pass.txt
		echo
	fi

	# check servers list
	if [[ ! -f $VPNPATH/servers.txt ]]; then
		fupdate
	fi

}

fparsecommandline()
{
	# parse command line arguments
	parsed_args=$(getopt \
	--options lhupnmkdfevxs: \
	--long list-servers,help,update,port-forward,mace,killswitch,dns,firewall,allow-lan,verbose,encrypt,server: \
	--name $PNAME -- "$@")
	if [[ $? != 0 ]]; then
		error "terminating"
		return 1
	else
		eval set -- "$parsed_args"
	fi
}

# GLOBALS DECLARATIONS
PNAME=$0
						# Colour codes for terminal.
BOLD=$(tput bold)
BLUE=$(tput setf 1 || tput setaf 4)
GREEN=$(tput setf 2 || tput setaf 2)
CYAN=$(tput setf 3 || tput setaf 6)
RED=$(tput setf 4 || tput setaf 1)
RESET=$(tput sgr0)

INFO=" [$BOLD$GREEN*$RESET]"
ERROR=" [$BOLD$RED"'X'"$RESET]"
PROMPT=" [$BOLD$BLUE>$RESET]"

						# This is where we will store PIA openVPN files and user config.
VPNPATH='/etc/openvpn/pia'

						# Initialize switches.
PORTFORWARD=0
NEWPORT=0
NEWIP=0
NOPORT=0
MACE=0
KILLS=0
DNS=0
FORWARDEDPORT=0
VERBOSE=0
FIREWALL=0
SERVERNUM=0
FLAN=0
UNKNOWNOS=0
MISSINGDEP=0
CONFIGNUM=0
RESTARTVPN=0
UNLOCK=0
UPDATEOUTPUT=0
ENCRYPT=0
CREDS=0

fcheckroot || exit 1
fcheckdependencies
fcheckfiles

# use getopt to parse command line parameters
fparsecommandline $@ || exit 1
# loop through arguments
while true; do
	echo $1
	echo $2
	case "$1" in
	-l | --list-servers)
		flist; exit 0 ;;
	-h | --help)
		fhelp; exit 0;;
	-u | --update)
		fupdate
		shift;;
	-p | --port-forward)
		PORTFORWARD=1
		shift;;
	-n | --new-port)
		fnewport
		shift;;
	-m | --pia-mace)
		MACE=1; DNS=1
		shift;;
	-k | --kill-switch)
		KILLS=1; FIREWALL=1
		shift;;
	-d | --dns)
		DNS=1
		shift;;
	-f | --firewall)
		FIREWALL=1
		shift;;
	-e | --allow-lan)
		FLAN=1; FIREWALL=1
		shift;;
	-v | --verbose)
		VERBOSE=1; fgetip&
		shift;;
	-x | --encrypt)
		ENCRYPT=1
		shift;;
	-s | --server )
		SERVERNUM=$2
		shift 2;;
	'') break;;
	*)  printf "unknown option $1\n"
		exit 1;;
	esac
done
MAXSERVERS=$(cat $VPNPATH/servers.txt | wc -l)


if [ $SERVERNUM -lt 1 ];then
	echo "$PROMPT Please choose a server: "
	flist
	read -p "$PROMPT " SERVERNUM
	clear
fi

trap fvpnreset INT

if [[ $SERVERNUM =~ ^[0-9]+$ && $SERVERNUM -gt 0 && $SERVERNUM -le $MAXSERVERS ]];then
	:
else
	flist
	echo "$ERROR $SERVERNUM is not valid! 1-$MAXSERVERS only."
	exit 1
fi

SERVERNAME=$(cat $VPNPATH/servers.txt | head -n $SERVERNUM | tail -n 1 | awk '{print $1}')
DOMAIN=$(cat $VPNPATH/servers.txt | head -n $SERVERNUM | tail -n 1 | awk '{print $2}')
CONFIG=$SERVERNAME.ovpn

if [ -f $VPNPATH/.killswitch ];then
	UNLOCK=1
	rm -rf $VPNPATH/.killswitch
fi

while [ true ];do
	fconnect
done
