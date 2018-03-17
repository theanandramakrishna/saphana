#!/bin/bash

# Built with information from 
# in https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/sap-hana-high-availability

echo "Getting arguments"
ip1="$1"
ip2="$2"
host1="$3"
host2="$4"
nodeindex="$5"
password="$6"
lbip="$7"
# aadtenantid="$8"
# aadappid="$9"
# aadsecret="$10"
#subscription="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2017-08-01&format=text"}"
#resourcegroup="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2017-08-01&format=text"}"

echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"

# Copy over ssh info
sudo cp -R /tmp/.ssh /root/.ssh
sudo chmod 0600 /root/.ssh/id_rsa

#install fence agents
echo "Installing fence agents"
sudo zypper install -l -y sle-ha-release fence-agents

# setup disk layout
# this assumes that 4 disks are attached at lun 0 through 4

echo "Creating physical volumes"
sudo pvcreate /dev/disk/azure/scsi1/lun0-part1   
sudo pvcreate /dev/disk/azure/scsi1/lun1-part1   
sudo pvcreate /dev/disk/azure/scsi1/lun2-part1   
sudo pvcreate /dev/disk/azure/scsi1/lun3-part1   

echo "Creating volume groups"
sudo vgcreate vg_hana_data /dev/disk/azure/scsi1/lun0-part1 /dev/disk/azure/scsi1/lun1-part1
sudo vgcreate vg_hana_log /dev/disk/azure/scsi1/lun2-part1
sudo vgcreate vg_hana_shared /dev/disk/azure/scsi1/lun3-part1

echo "Creae logical volumes"
sudo lvcreate -l 100%FREE -n hana_data vg_hana_data
sudo lvcreate -l 100%FREE -n hana_log vg_hana_log
sudo lvcreate -l 100%FREE -n hana_shared vg_hana_shared
sudo mkfs.xfs /dev/vg_hana_data/hana_data
sudo mkfs.xfs /dev/vg_hana_log/hana_log
sudo mkfs.xfs /dev/vg_hana_shared/hana_shared

# mount volumes
echo "Mounting volumes into fstab"
cat << EOF | sudo tee -a /etc/fstab
/dev/vg_hana_data/hana_data /hana/data xfs  defaults,nofail  0  2
/dev/vg_hana_log/hana_log /hana/log xfs  defaults,nofail  0  2
/dev/vg_hana_shared/hana_shared /hana/shared xfs  defaults,nofail  0  2
EOF
sudo mount -a

# install cluster on node
if [ "$nodeindex" = "0" ]
then 
    # Use unicast, not multicast due to Azure support
    echo "initialized ha cluster on primary"
    sudo ha-cluster-init -i eth0 -u -y
fi

#add node(s) to cluster
if [ "$nodeindex" != "0" ]
then
    echo "Joining secondary to cluster on primary"
    sudo ha-cluster-join -c "$ip1" -i eth0 -y
fi

# change cluster password
echo "Changing hacluster password"
echo "hacluster:$password" | sudo chpasswd

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

# install HANA HA packages
echo "Installing HANA HA packages"
sudo zypper install SAPHanaSR

# Now install SAP HANA
# copy from other script

# Upgrade SAP host agents
#sudo /usr/sap/hostctrl/exe/saphostexec -upgrade -archive <path to SAP Host Agent SAR>

# Create HANA replication
if [ "$nodeindex" = "0" ]
then
	echo "Create hana user and database to setup replication"
	PATH="$PATH:/usr/sap/HDB/HDB03/exe"
	hdbsql -u system -i 03 'CREATE USER hdbhasync PASSWORD "$password"' 
	hdbsql -u system -i 03 'GRANT DATA ADMIN TO hdbhasync' 
	hdbsql -u system -i 03 'ALTER USER hdbhasync DISABLE PASSWORD LIFETIME'
fi

# Create keystore entry
echo "Creating keystore entry"
PATH="$PATH:/usr/sap/HDB/HDB03/exe"
hdbuserstore SET hdbhaloc localhost:30315 hdbhasync "$password"

# backup the db
if [ "$nodeindex" = "0" ]
then
	echo "Backing up the database"
	PATH="$PATH:/usr/sap/HDB/HDB03/exe"
	hdbsql -u system -i 03 "BACKUP DATA USING FILE ('initialbackup')"

	echo "Creating primary site"
	su - hdbadm
	hdbnsutil -sr_enable –-name=SITE1	
fi

if [ "$nodeindex" = "1" ]
then
	echo "Creating secondary site"
	su - hdbadm
	sapcontrol -nr 03 -function StopWait 600 10
	hdbnsutil -sr_register --remoteHost=$host1 --remoteInstance=03 --replicationMode=sync --name=SITE2	
fi


# configure cluster framework
# Need to set the defaults
###### BUGBUG - Check this.
if [ "$nodeindex" = "0" ]
then 
	echo "Configuring cluster defaults"
    sudo crm configure << EOF
rsc_defaults resource-stickiness="1000" migration-threshold="5000"
op_defaults timeout="600"
property no-quorum-policy="ignore" stonith-enabled="true" stonith-action="reboot" stonith-timeout="150s"
commit
exit
EOF

# Need to create stonith devices
# BUGBUG Not done

	# Create SAP HANA resource in cluster
	echo "Configure cluster for HANA resource"
	sudo crm configure << EOF
primitive rsc_SAPHanaTopology_HDB_HDB03 ocf:suse:SAPHanaTopology \
    operations $id="rsc_sap2_HDB_HDB03-operations" \
    op monitor interval="10" timeout="600" \
    op start interval="0" timeout="600" \
    op stop interval="0" timeout="300" \
    params SID="HDB" InstanceNumber="03"
clone cln_SAPHanaTopology_HDB_HDB03 rsc_SAPHanaTopology_HDB_HDB03 \
    meta is-managed="true" clone-node-max="1" target-role="Started" interleave="true"
commit
exit    
EOF

	echo "Configure more cluster for HANA"
	sudo crm configure << EOF
primitive rsc_SAPHana_HDB_HDB03 ocf:suse:SAPHana \
    operations $id="rsc_sap_HDB_HDB03-operations" \
    op start interval="0" timeout="3600" \
    op stop interval="0" timeout="3600" \
    op promote interval="0" timeout="3600" \
    op monitor interval="60" role="Master" timeout="700" \
    op monitor interval="61" role="Slave" timeout="700" \
    params SID="HDB" InstanceNumber="03" PREFER_SITE_TAKEOVER="true" \
    DUPLICATE_PRIMARY_TIMEOUT="7200" AUTOMATED_REGISTER="false"
ms msl_SAPHana_HDB_HDB03 rsc_SAPHana_HDB_HDB03 \
    meta is-managed="true" notify="true" clone-max="2" clone-node-max="1" \
    target-role="Started" interleave="true"
primitive rsc_ip_HDB_HDB03 ocf:heartbeat:IPaddr2 \ 
    meta target-role="Started" is-managed="true" \ 
    operations $id="rsc_ip_HDB_HDB03-operations" \ 
    op monitor interval="10s" timeout="20s" \ 
    params ip="${lbip}" 
primitive rsc_nc_HDB_HDB03 anything \ 
    params binfile="/usr/bin/nc" cmdline_options="-l -k 62503" \ 
    op monitor timeout=20s interval=10 depth=0 
group g_ip_HDB_HDB03 rsc_ip_HDB_HDB03 rsc_nc_HDB_HDB03
colocation col_saphana_ip_HDB_HDB03 2000: g_ip_HDB_HDB03:Started \ 
    msl_SAPHana_HDB_HDB03:Master  
order ord_SAPHana_HDB_HDB03 2000: cln_SAPHanaTopology_HDB_HDB03 \ 
    msl_SAPHana_HDB_HDB03	
commit
exit    
EOF
fi

echo "Done!"




