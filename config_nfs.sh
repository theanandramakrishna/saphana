#!/bin/bash

echo "Getting arguments"
ip1="$1"
ip2="$2"
host1="$3"
host2="$4"
nodeindex="$5"
password="$6"
lbip="$7"

echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"

# Copy over ssh info
sudo cp -R /tmp/.ssh /root/.ssh
sudo chmod 0600 /root/.ssh/id_rsa

#install fence agents
echo "Installing fence agents"
sudo zypper install -l -y sle-ha-release fence-agents

if [ "$nodeindex" = "0" ]
then 
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


#configure corosync
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

#restart corosync
echo "Restarted corosync service"
sudo service corosync restart

#install drbd
echo "Installing drbd"
sudo zypper install -l -y drbd drbd-kmp-default drbd-utils

#create drbd partition
echo "Creating drbd partition"
sudo sh -c 'echo -e "n\n\n\n\n\nw\n" | fdisk /dev/sdc'

#create lvm configs
echo "Creating lvm configs"
sudo pvcreate /dev/sdc1   
sudo vgcreate vg_NFS /dev/sdc1
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


# Get the sync status going on the primary
if [ "$nodeindex" = "0" ]
then
    echo "Create new drbd uuid"
    sudo drbdadm new-current-uuid --clear-bitmap NWS_nfs
    echo "Make into drbd primary"
    sudo drbdadm primary --force NWS_nfs

    sudo cat /proc/drbd

    # Make file systems
    echo "Do mkfs on drbd device"
    sudo mkfs.xfs /dev/drbd0

    # Now configure cluster framework
    echo "Configure cluster framework"
    sudo crm configure << EOF
rsc_defaults resource-stickiness="1"
commit
exit
EOF

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

# What about create a virtual IP resource and health-probe for the internal load balancer
# step in https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/high-availability-guide-suse

fi

#Need to config stonith device
