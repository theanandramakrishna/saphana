#!/bin/bash

ip1 = $1
ip2 = $2
username = $3
password = $4
lbip = $5
primary = $6

#install fence agents
sudo zypper install -l -y sle-ha-release fence-agents

if [ "$6" = "primary"]
then 
    sudo ha-cluster-init -y
fi

# change cluster password
sudo passwd hacluster << EOF
$4
$4
EOF

#add node(s) to cluster
if [ "$6" != "primary"]
then
    sudo ha-cluster-join -c "$1"
fi


#configure corosync
sudo cat << EOF >> /etc/corosync/corosync.conf
nodelist {
    node {
        ring0_addr: ${1}
    }
    node {
        ring0_addr: ${2}
    }
}
EOF

#restart corosync
sudo service corosync restart

#install drbd
sudo zypper install -l -y drbd drbd-kmp-default drbd-utils

#create drbd partition
sudo sh -c 'echo -e "n\n\n\n\n\nw\n" | fdisk /dev/sdc'

#create lvm configs
sudo pvcreate /dev/sdc1   
sudo vgcreate vg_NFS /dev/sdc1
sudo lvcreate -l 100%FREE -n NWS vg_NFS

#create nfs drbd device

#automate more from https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/high-availability-guide-suse


