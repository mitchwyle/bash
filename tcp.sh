#!/usr/bin/env bash

host=$1
port=$2

#exec 3<>/dev/tcp/$host/80
#echo -e "GET / HTTP/1.1\r\nhost: $prot://$host\r\nConnection: close\r\n\r\n" >&3
#cat <&3


exec 3<>"/dev/tcp/$host/$port"
#echo -e "GET / HTTP/1.1\r\nhost: http://www.google.com\r\nConnection: close\r\n\r\n" >&3
echo -e "GET / HTTP/1.1\r\n" >&3
cat <&3
exec 3>&-

