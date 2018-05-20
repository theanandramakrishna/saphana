#!/bin/bash

ascs_privateip_0="${ascs_privateip_0}"
ascs_privateip_1="${ascs_privateip_1}"
ascs_computer_name_0="${ascs_computer_name_0}"
ascs_computer_name_1="${ascs_computer_name_1}"
ascs_user_password="${ascs_user_password}"
ascs_lb_ip="${ascs_lb_ip}"
ascs_ers_lb_ip="${ascs_ers_lb_ip}"
nfs_lb_ip="${nfs_lb_ip}"
hana_lb_ip="${hana_lb_ip}"
ascs_sbd_name="${ascs_sbd_name}"
ascs_sbd_key="${ascs_sbd_key}"
ascs_sbd_share_name="${ascs_sbd_share_name}"
hanasid="${ascs_sid}"
hanainstancenumber="${ascs_instance_number}"

source `dirname $0`/common.sh $ascs_privateip_0 $ascs_privateip_1 $ascs_computer_name_0 $ascs_computer_name_1 "$ascs_user_password" $ascs_lb_ip $ascs_ers_lb_ip $ascs_sbd_name "$ascs_sbd_key" $ascs_sbd_share_name
echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"

initialize

echo "Configure keepalive timeout"
# Change the Linux system configuration
sudo sysctl net.ipv4.tcp_keepalive_time=120

sudo zypper install sap_suse_cluster_connector

echo "create partitions"
sudo sh -c 'echo -e "n\n\n\n\n\nw\n" | fdisk /dev/disk/azure/scsi1/lun0'
sudo pvcreate /dev/disk/azure/scsi1/lun0-part1   

echo "creating shared directories"
sudo mkdir -p /sapmnt/NW1
sudo mkdir -p /usr/sap/trans
sudo mkdir -p /usr/sap/NW1/SYS
sudo mkdir -p /usr/sap/NW1/ASCS00
sudo mkdir -p /usr/sap/NW1/ERS02

sudo chattr +i /sapmnt/NW1
sudo chattr +i /usr/sap/trans
sudo chattr +i /usr/sap/NW1/SYS
sudo chattr +i /usr/sap/NW1/ASCS00
sudo chattr +i /usr/sap/NW1/ERS02

echo "Configuring autofs"
echo "+auto.master" | sudo tee -a /etc/auto.master
echo "/- /etc/auto.direct" | sudo tee -a /etc.auto.master

cat << EOF | sudo tee /etc/auto.direct
/sapmnt/NW1 -nfsvers=4,nosymlink,sync $nfs_lb_ip:/NW1/sapmntsid
/usr/sap/trans -nfsvers=4,nosymlink,sync $nfs_lb_ip:/NW1/trans
/usr/sap/NW1/SYS -nfsvers=4,nosymlink,sync $nfs_lb_ip:/NW1/sidsys
/usr/sap/NW1/ASCS00 -nfsvers=4,nosymlink,sync $nfs_lb_ip:/NW1/ASCS
/usr/sap/NW1/ERS02 -nfsvers=4,nosymlink,sync $nfs_lb_ip:/NW1/ASCSERS
EOF

echo "Restarting autofs"
sudo systemctl enable autofs
sudo service autofs restart

if [ "$nodeindex" = "0" ]
then
    echo "Doing crm configuration for ascs"
    sudo crm node standby $ascs_computer_name_1

    sudo crm configure primitive vip_NW1_ASCS IPaddr2 \
    params ip=$ascs_lb_ip cidr_netmask=24 \
    op monitor interval=10 timeout=20

    sudo crm configure primitive nc_NW1_ASCS anything \
    params binfile="/usr/bin/nc" cmdline_options="-l -k 62000" \
    op monitor timeout=20s interval=10 depth=0

    sudo crm configure group g-NW1_ASCS nc_NW1_ASCS vip_NW1_ASCS \
    meta resource-stickiness=3000

    # Install ascs
    #sudo <swpm>/sapinst SAPINST_REMOTE_ACCESS_USER=sapadmin

    echo "Configure vips"
    sudo crm node online nw1-cl-1
    sudo crm node standby nw1-cl-0

    sudo crm configure primitive vip_NW1_ERS IPaddr2 \
    params ip=$ascs_ers_lb_ip cidr_netmask=24 \
    op monitor interval=10 timeout=20

    sudo crm -F configure primitive nc_NW1_ERS anything \
    params binfile="/usr/bin/nc" cmdline_options="-l -k 62102" \
    op monitor timeout=20s interval=10 depth=0

    sudo crm configure group g-NW1_ERS nc_NW1_ERS vip_NW1_ERS
fi

if [ "$nodeindex" = "1" ]
    echo "Installing ASCS ERS"
    #sudo <swpm>/sapinst SAPINST_REMOTE_ACCESS_USER=sapadmin
fi

if [ "$nodeindex" = "0" ]
    echo "Adapting ASCS and ERS instance profiles"
    #sudo vi /sapmnt/NW1/profile/NW1_ASCS00_nw1-ascs

    # Change the restart command to a start command
    #Restart_Program_01 = local $(_EN) pf=$(_PF)
    #Start_Program_01 = local $(_EN) pf=$(_PF)

    # Add the following lines
    #service/halib = $(DIR_CT_RUN)/saphascriptco.so
    #service/halib_cluster_connector = /usr/bin/sap_suse_cluster_connector

    # Add the keep alive parameter
    #enque/encni/set_so_keepalive = true

    #sudo vi /sapmnt/NW1/profile/NW1_ERS02_nw1-aers

    # Add the following lines
    #service/halib = $(DIR_CT_RUN)/saphascriptco.so
    #service/halib_cluster_connector = /usr/bin/sap_suse_cluster_connector
fi

# Add sidadm to the haclient group
sudo usermod -aG haclient nw1adm

if [ "$nodeindex" = "0" ]
    cat /usr/sap/sapservices | grep ASCS00 | sudo ssh $ascs_computer_name_1 "cat >>/usr/sap/sapservices"
    sudo ssh $ascs_computer_name_1 "cat /usr/sap/sapservices" | grep ERS02 | sudo tee -a /usr/sap/sapservices
fi
