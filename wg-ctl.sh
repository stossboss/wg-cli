#!/bin/sh
#stossboss

helpFunc() {
printf "Wireguard Control Help:
        wg-ctl <options> [ add | start | stop | del ]
                options:
                        -D | disable/enable state on boot after stop/start
			-n | no start/stop after add/del
			-h | Hard network restart (default /etc/init.d/network reload)
			-f | filename < string >, required when add
                        -l | Specify local target < x.x.x.x/x > guesses otherwise
                        -g | Specify local gateway < x.x.x.x > guesses otherwise
                        -d | Specify a dns server < x.x.x.x >
			-i | Specify wireguard interface name < string > wg0 default

examples:
wg-ctl -l 10.32.0.0/16 -d 10.32.253.7 -f myWgVpn.conf add ## Adds & starts vpn file with route to 10.32.0.0/16 network
wg-ctl del ## Deletes an entire config (if it exists)
			\n"
}
ACTION="$@" && export ACTION="${ACTION##* }"
export LROUTE_NM="lroute"

while getopts 'Dnhf:l:g:d:i:' c
do
        case $c in
                D) export DONT_SAVE="Y";;
		n) export DONT_CHANGE="Y";;
		h) export NRESTART="Y";;
		f) export FNAME="$OPTARG";;
                l) export LOCAL_ROUTE="$OPTARG";;
		g) export LOCAL_GATE="$OPTARG";;
                d) export LOCAL_DNS="$OPTARG";;
                i) export WGC_IF="$OPTARG";;
        esac
done

uciDisabled() {
		uci "$3" set network."$1".disabled="$2" && uci commit network
}

getLocalEnv() {
. /lib/functions/network.sh; \
        network_find_wan "wan_name"; \
        network_get_ipaddr l_ip "$wan_name"; \
	network_get_gateway l_gw "$wan_name"; \
	network_get_subnet l_sub "$wan_name"; \
        network_get_dnsserver l_dns "$wan_name";
	export l_dns1="${l_dns%% *}"
	export l_dns2="${l_dns##* }"
	calcNet "$l_sub"
}

calcNet() {
	CALC=`ipcalc.sh "$1"`
	l_mask=`echo "$CALC" | grep "NETMASK"` && export l_mask="${l_mask#NETMASK=}"
	l_net=`echo "$CALC" | grep "NETWORK"` && export l_net="${l_net#NETWORK=}"
}

parseWgConf() {
	CONF="$1"
	ALLOWED="$2"
	WGC_IP=`grep Address "${CONF}"` &&\
		WGC_IP="${WGC_IP#Address = }" && \
		export WGC_IP="${WGC_IP%%,*}"
	WGC_PRIV=`grep PrivateKey "${CONF}"` && \
		export WGC_PRIV="${WGC_PRIV#PrivateKey = }"
	WGC_PSK=`grep PresharedKey "${CONF}"` && \
		export WGC_PSK="${WGC_PSK#PresharedKey = }"
	WGS_PUB=`grep PublicKey "${CONF}"` && \
		export WGS_PUB="${WGS_PUB#PublicKey = }"
	WGS_IP=`grep Endpoint "${CONF}"` && \
		export WGS_PORT="${WGS_IP#*:}" && \
		WGS_IP="${WGS_IP#Endpoint = }" && \
		export WGS_IP="${WGS_IP%:*}"
	WGC_ALL=`grep AllowedIPs "${CONF}"` && \
		WGC_ALL="${WGC_ALL#AllowedIPs = }" && \
		export WGC_ALL="${WGC_ALL%%,*}"
	[ -z "${ALLOWED}" ] && export WGC_ALL='0.0.0.0/0'
}

addWgConf() {
	uci rename firewall.@zone[0]="lan"
	uci rename firewall.@zone[1]="wan"
	uci del_list firewall."${wan_name}".network="${WGC_IF}"
	uci add_list firewall."${wan_name}".network="${WGC_IF}"
	uci commit firewall
	/etc/init.d/firewall restart
	uci -q delete network."${WGC_IF}"
	uci set network."${WGC_IF}"="interface"
	uci set network."${WGC_IF}".proto="wireguard"
	uci set network."${WGC_IF}".private_key="${WGC_PRIV}"
	uci add_list network."${WGC_IF}".addresses="${WGC_IP}"
	uci -q delete network.wgserver
	uci set network.wgserver="wireguard_${WGC_IF}"
	uci set network.wgserver.public_key="${WGS_PUB}"
	uci set network.wgserver.preshared_key="${WGC_PSK}"
	uci set network.wgserver.endpoint_host="${WGS_IP}"
	uci set network.wgserver.endpoint_port="${WGS_PORT}"
	uci set network.wgserver.route_allowed_ips="1"
	uci set network.wgserver.persistent_keepalive="15"
	uci add_list network.wgserver.allowed_ips="${WGC_ALL}"
	uci commit network
}

addLocalRoute() {
	THIS_NM="$1"
	THIS_ROUTE="$2"
	calcNet "$THIS_ROUTE"
	[ -n "$3" ] && l_gw="$3"
	tmp_nm=`uci add network route`
	uci rename network."${tmp_nm}"="${THIS_NM}"
	uci set network."${THIS_NM}".interface="${wan_name}"
	uci set network."${THIS_NM}".target="${l_net}"
	uci set network."${THIS_NM}".netmask="${l_mask}"
	uci set network."${THIS_NM}".gateway="${l_gw}"
	uci set network."${THIS_NM}".disabled="0"
	uci commit network
}

changeDNS() {
	[ -n "$1" ] && export l_dns2="$1"
	uci del dhcp.lan.dhcp_option
	uci add_list dhcp.lan.dhcp_option="6,${l_dns1}"
	uci add_list dhcp.lan.dhcp_option="6,${l_dns2}"
	uci commit dhcp
}

wgStart() {
	uciDisabled "${WGC_IF}" "0" "-q"
	uciDisabled "wgserver" "0" "-q"
	[ -z "$NRESTART" ] && /etc/init.d/network reload || \
		/etc/init.d/network restart
	[ -n "$DONT_SAVE" ] && \
		uciDisabled "${WGC_IF}" "1" && \
		uciDisabled "wgserver" "1" && \
		`uci -q get network."${LROUTE_NM}" > /dev/null` && \
		uciDisabled "${LROUTE_NM}" "1"
}

wgStop() {
	uciDisabled "${WGC_IF}" "1" "-q"
	uciDisabled "wgserver" "1" "-q"
	[ -z "$NRESTART" ] && /etc/init.d/network reload || \
		/etc/init.d/network restart
	[ -n "$DONT_SAVE" ] && \
		uciDisabled "${WGC_IF}" "0" && \
		uciDisabled "wgserver" "0" && \
		`uci -q get network."${LROUTE_NM}" > /dev/null` && \
		uciDisabled "${LROUTE_NM}" "0"
}

delWgConf() {
	uci del_list firewall."wan".network="${WGC_IF}"
	uci commit firewall
	uci -q delete network."${WGC_IF}"
	uci -q delete network.wgserver
	uci commit network
}

grabWgifFromUci() {
		`uci -q get network.wgserver > /dev/null` || exit 1
		WGC_IF=`uci get network.wgserver`
		export WGC_IF="${WGC_IF#wireguard_}"
}

getLocalEnv
case "$ACTION" in
	add)
		[ ! -f "$FNAME" ] && \
			echo "config file not found" && \
			exit 0;
		parseWgConf "${FNAME}"
		[ -z "$WGC_IF" ] && WGC_IF="wg0"
		addWgConf
		[ -n "$LOCAL_DNS" ] && changeDNS "${LOCAL_DNS}"
		[ -n "$LOCAL_ROUTE" ] && \
			addLocalRoute "${LROUTE_NM}" "${LOCAL_ROUTE}" "${LOCAL_GATE}"
		[ -z "$DONT_CHANGE" ] && wgStart
	;;

	start)
		grabWgifFromUci || \
			{ echo "Failed to find Wireguard interface" && exit 0 ; }
		wgStart
	;;

	stop)
		grabWgifFromUci || \
			{ echo "Failed to find Wireguard interface" && exit 0 ; }
		wgStop
	;;

	del)
		grabWgifFromUci || \
			{ echo "Failed to find Wireguard interface" && exit 0 ; }
		[ -z "$DONT_CHANGE" ] && wgStop
		`uci -q get network."${LROUTE_NM}" > /dev/null` && \
			uci del network."${LROUTE_NM}" && uci commit
		delWgConf
	;;

	*)
               helpFunc && exit 0
        ;;
esac
