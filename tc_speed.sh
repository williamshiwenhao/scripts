#!/bin/bash
IDEV=enp1s0
IP=162.105.85.128/25

#bandwidth/bps
#FORWARD_BANDWITTH shoule > BACKWARD_BANDWIDTH
BACKWARD_BANDWIDTH=1mbit
FORWARD_BANDWIDTH=1mbit

FORWARD_BUFFER=1600
BACKWARD_BUFFER=1600
#delay
DELAY=10ms
DELAY_RANGE=3ms

#loss
LOSS=1%

if [ $(whoami) != "root" ]; then
	echo "Root is needed!"
	exit
fi
##############################
#load
echo "1" >/proc/sys/net/ipv4/ip_forward
modprobe sch_htb
modprobe sch_sfq
modprobe act_police
modprobe sch_netem
modprobe ifb #fake network card
##############################

function on() {
	#clear all
	ip link set dev ifb0 down
	ip link set dev ifb0 up
	tc qdisc del dev $IDEV ingress
	tc qdisc del dev $IDEV root 2>/dev/null >/dev/null
	echo "If already cleared, sometimes will get error msg, ignore it"
	#forward
	tc qdisc add dev $IDEV root handle 1:0 prio
	tc qdisc add dev $IDEV parent 1:3 handle 30:0 \
		tbf rate $FORWARD_BANDWIDTH buffer $FORWARD_BUFFER limit 3000
	tc qdisc add dev $IDEV parent 30:1 handle 31: netem delay $DELAY $DELAY_RANGE loss $LOSS
	tc qdisc add dev $IDEV parent 31:1 handle 32: bfifo limit 1600
	tc filter add dev $IDEV protocol ip parent 1:0 prio 3 u32 match ip dst $IP flowid 1:3
	#backward
	tc qdisc del dev ifb0 root
	tc qdisc add dev ifb0 parent root handle 30:0 \
		tbf rate $BACKWARD_BANDWIDTH buffer $BACKWARD_BUFFER limit 3000
	tc qdisc add dev ifb0 parent 30:1 handle 31: netem delay $DELAY $DELAY_RANGE loss $LOSS
	tc qdisc add dev ifb0 parent 31:1 handle 32: bfifo limit 1600

	#redirect input
	tc qdisc add dev $IDEV ingress handle ffff:
	tc filter add dev $IDEV parent ffff: \
		protocol ip u32 match ip src $IP flowid 1:1 action mirred egress redirect dev ifb0

	#print out all rulls
	#tc -s qdisc ls dev $IDEV
	#tc -s qdisc ls dev ifb0
}

function off() {
	ip link set dev ifb0 down
	tc qdisc del dev $IDEV ingress
	tc qdisc del dev $IDEV root 2>/dev/null >/dev/null
}

case $1 in
"on")
	on
	;;
"off")
	off
	;;
*)
	echo "usage :$0 on/off"
	;;
esac
