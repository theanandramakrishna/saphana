#!/bin/bash

# Built with information from 
# in https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/high-availability-guide-suse

echo "Getting arguments"
ip1="$1"
ip2="$2"
host1="$3"
host2="$4"
nodeindex="$5"
password="$6"
lbip="$7"

#subscription="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2017-08-01&format=text"}"
#resourcegroup="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2017-08-01&format=text"}"

echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"

# Copy over ssh info
sudo cp -R /tmp/.ssh /root/.ssh
sudo chmod 0600 /root/.ssh/id_rsa

#install fence agents
echo "Installing fence agents"
sudo zypper install -l -y sle-ha-release fence-agents

# Turn on ntp at boot
echo "Turn on ntp at boot"
sudo systemctl enable ntpd.service

echo "put /srv/nfs dir into exports"
sudo sh -c 'echo /srv/nfs/ *\(rw,no_root_squash,fsid=0\)>/etc/exports'

echo "Make nfs dirs"
sudo mkdir /srv/nfs/

echo "Enable nfsserver"
sudo systemctl enable nfsserver
echo "Setup nfsserver for restarts"
sudo service nfsserver restart

if [ "$nodeindex" = "0" ]
then 
    # Use unicast, not multicast due to Azure support
    echo "initialized ha cluster on primary"
    sudo ha-cluster-init -i eth0 -u -y
fi

# change cluster password
echo "Changing hacluster password"
echo "hacluster:$password" | sudo chpasswd

#add node(s) to cluster
if [ "$nodeindex" != "0" ]
then
    echo "Joining secondary to cluster on primary"
    sudo ha-cluster-join -c "$ip1" -i eth0 -y
fi


#configure corosync, only on primary.  Secondary will get config via replication
if [ "$nodeindex" = "0" ]
then
    echo "Configuring corosync config"
    cat << EOF | sudo tee -a /etc/corosync/corosync.conf
nodelist {
    node {
        ring0_addr: ${ip1}
    }
    node {
        ring0_addr: ${ip2}
    }
}
EOF
fi

#restart corosync
echo "Restarted corosync service"
sudo service corosync restart

#install drbd
echo "Installing drbd"
sudo zypper install -l -y drbd drbd-kmp-default drbd-utils

#create drbd partition
echo "Creating drbd partition"
sudo sh -c 'echo -e "n\n\n\n\n\nw\n" | fdisk /dev/disk/azure/scsi1/lun0'

#create lvm configs
echo "Creating lvm configs"
sudo pvcreate /dev/disk/azure/scsi1/lun0-part1   
sudo vgcreate vg_NFS /dev/disk/azure/scsi1/lun0-part1
sudo lvcreate -l 100%FREE -n NWS vg_NFS

#create nfs drbd device
echo "Creating nfs drbd device"
cat << EOF | sudo tee /etc/drbd.d/NWS_nfs.res
resource NWS_nfs {
   protocol     C;
   disk {
      on-io-error       pass_on;
   }
   on ${host1} {
      address   ${ip1}:7790;
      device    /dev/drbd0;
      disk      /dev/vg_NFS/NWS;
      meta-disk internal;
   }
   on ${host2} {
      address   ${ip2}:7790;
      device    /dev/drbd0;
      disk      /dev/vg_NFS/NWS;
      meta-disk internal;
   }
}
EOF

echo "Creating drbdadm nfs"
sudo drbdadm create-md NWS_nfs

echo "Bring up this node for drbd"
sudo drbdadm up NWS_nfs


