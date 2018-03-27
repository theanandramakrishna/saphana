#!/bin/bash

# Built with information from 
# in https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/high-availability-guide-suse

source `dirname $0`/common.sh

echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"


# Get the sync status going on the primary
if [ "$nodeindex" = "0" ]
then
    echo "Create new drbd uuid to skip initial sync since device is empty"
    sudo drbdadm new-current-uuid --clear-bitmap NWS_nfs
    
    echo "Make into drbd primary"
    sudo drbdadm -- --overwrite-data-of-peer --force primary NWS_nfs

    echo "wait until drbd devices are ready to synchronize"
    sudo drbdsetup wait-sync-resource NWS_nfs

    echo "Sleep 1m to let device settle"
    sleep 1m

    # Make file systems
    echo "Do mkfs on drbd device"
    sudo mkfs.xfs /dev/drbd0
    
    configureClusterDefaults

    echo "Configure cluster drbd resource"
    sudo crm configure << EOF
primitive drbd_NWS_nfs \
  ocf:linbit:drbd \
  params drbd_resource="NWS_nfs" \
  op monitor interval="15" role="Master" \
  op monitor interval="30" role="Slave"

ms ms-drbd_NWS_nfs drbd_NWS_nfs \
  meta master-max="1" master-node-max="1" clone-max="2" \
  clone-node-max="1" notify="true" interleave="true"

commit
exit
EOF

    echo "Configure cluster nfs resource"
    sudo crm configure << EOF
primitive nfsserver \
  systemd:nfs-server \
  op monitor interval="30s"
clone cl-nfsserver nfsserver interleave="true"
commit
exit
EOF

    echo "Configure cluster sap mount"
    sudo crm configure << EOF
primitive fs_NWS_sapmnt \
  ocf:heartbeat:Filesystem \
  params device=/dev/drbd0 \
  directory=/srv/nfs/NWS  \
  fstype=xfs \
  op monitor interval="10s"
group g-NWS_nfs fs_NWS_sapmnt
order o-NWS_drbd_before_nfs inf: \
  ms-drbd_NWS_nfs:promote g-NWS_nfs:start
colocation col-NWS_nfs_on_drbd inf: \
  g-NWS_nfs ms-drbd_NWS_nfs:Master
commit
exit    
EOF
    
    echo "Sleep for 1m to let device come up"
    sleep 1m

    echo "Make directories"
    sudo mkdir /srv/nfs/NWS/sidsys
    sudo mkdir /srv/nfs/NWS/sapmntsid
    sudo mkdir /srv/nfs/NWS/trans
    sudo mkdir /srv/nfs/NWS/ASCS
    sudo mkdir /srv/nfs/NWS/ASCSERS
    sudo mkdir /srv/nfs/NWS/SCS
    sudo mkdir /srv/nfs/NWS/SCSERS
    
    echo "configure cluster heartbeat"
    sudo crm configure << EOF
primitive exportfs_NWS \
 ocf:heartbeat:exportfs \
 params directory="/srv/nfs/NWS" \
 options="rw,no_root_squash" \
 clientspec="*" fsid=0 \
 wait_for_leasetime_on_stop=true \
 op monitor interval="30s"
modgroup g-NWS_nfs add exportfs_NWS
commit
exit
EOF

    echo "Configure cluster vip"
    sudo crm configure << EOF
primitive vip_NWS_nfs IPaddr2 \
  params ip=${lbip} cidr_netmask=24 \
  op monitor interval=10 timeout=20

primitive nc_NWS_nfs anything \
  params binfile="/usr/bin/nc" cmdline_options="-l -k 61000" \
  op monitor timeout=20s interval=10 depth=0

modgroup g-NWS_nfs add nc_NWS_nfs
modgroup g-NWS_nfs add vip_NWS_nfs

commit
exit
EOF

  echo "Done!"
fi


