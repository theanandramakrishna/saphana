#!/bin/bash

# Built with information from 
# in https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/high-availability-guide-suse

source `dirname $0`/common.sh

echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"
echo "storageacctname=$storageacctname storageacctkey=REDACTED sharename=$sharename"

# Do all common initialization
initialize

echo "put /srv/nfs dir into exports"
sudo sh -c 'echo /srv/nfs/ *\(rw,no_root_squash,fsid=0\)>/etc/exports'

echo "Make nfs dirs"
sudo mkdir -p /srv/nfs/

echo "Enable nfsserver"
sudo systemctl enable nfsserver
echo "Setup nfsserver for restarts"
sudo service nfsserver restart

initializeCluster
initializeCorosync

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


