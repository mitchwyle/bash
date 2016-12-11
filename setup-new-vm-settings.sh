#!/usr/bin/env bash

# creating new VM on laptop, pull down and execute these basic settings once.

# add other two interfaces:
cat >> /etc/network/interfaces <<'EOF'
auto ens34
iface ens34 inet dhcp
auto ens35
iface ens35 inet dhcp
EOF

# vim / vi
cat >> ~/.bashrc <<'EOF'

export VISUAL=vi
export EDITOR=vi
EOF

# enable no password on sudo for me
cat >> /etc/sudoers <<'EOF'

mwyle   ALL=(ALL:ALL) NOPASSWD:ALL
EOF

# grab the must-have stuff for this vm
apt-get install vim -y
apt-get install byobu -y
apt-get install openssh-server -y
apt-get install git -y
apt-get install curl -y

echo  edit /etc/apt/sources.list 
echo  and remove or comment out the cdrom:// lines


