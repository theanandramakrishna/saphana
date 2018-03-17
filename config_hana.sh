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
hanasid="$8"
hanainstancenumber="$9"
# aadtenantid="$9"
# aadappid="$10"
# aadsecret="$11"
#subscription="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2017-08-01&format=text"}"
#resourcegroup="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2017-08-01&format=text"}"

echo "ip1=$ip1, host1=$host1, ip2=$ip2, host2=$host2, nodeindex=$nodeindex, password=REDACTED, lbip=$lbip"
echo "hanasid=$hanasid hanainstancenumber=$hanainstancenumber"

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
	PATH="$PATH:/usr/sap/$hanasid/HDB${hanainstancenumber}/exe"
	hdbsql -u system -i $hanainstancenumber 'CREATE USER hdbhasync PASSWORD "$password"' 
	hdbsql -u system -i $hanainstancenumber 'GRANT DATA ADMIN TO hdbhasync' 
	hdbsql -u system -i $hanainstancenumber 'ALTER USER hdbhasync DISABLE PASSWORD LIFETIME'
# BUGBUG Should the user number have hanasid in it?
fi

# Create keystore entry
echo "Creating keystore entry"
PATH="$PATH:/usr/sap/$hanasid/HDB$hanainstancenumber/exe"
hdbuserstore SET hdbhaloc localhost:3${hanainstancenumber}15 hdbhasync "$password"

# backup the db
if [ "$nodeindex" = "0" ]
then
	echo "Backing up the database"
	PATH="$PATH:/usr/sap/$hanasid/HDB${hanainstancenumber}/exe"
	hdbsql -u system -i $hanainstancenumber "BACKUP DATA USING FILE ('initialbackup')"

	echo "Creating primary site"
	su - hdbadm
	hdbnsutil -sr_enable –-name=SITE1	
fi

if [ "$nodeindex" = "1" ]
then
	echo "Creating secondary site"
	su - hdbadm
	sapcontrol -nr $hanainstancenumber -function StopWait 600 10
	hdbnsutil -sr_register --remoteHost=$host1 --remoteInstance=$hanainstancenumber --replicationMode=sync --name=SITE2	
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
primitive rsc_SAPHanaTopology_${hanasid}_HDB${hanainstancenumber} ocf:suse:SAPHanaTopology \
    operations $id="rsc_sap2_${hanasid}_HDB${hanainstancenumber}-operations" \
    op monitor interval="10" timeout="600" \
    op start interval="0" timeout="600" \
    op stop interval="0" timeout="300" \
    params SID="${hanasid}" InstanceNumber="${hanainstancenumber}"
clone cln_SAPHanaTopology_${hanasid}_HDB${hanainstancenumber} rsc_SAPHanaTopology_${hanasid}_HDB${hanainstancenumber} \
    meta is-managed="true" clone-node-max="1" target-role="Started" interleave="true"
commit
exit    
EOF

	echo "Configure more cluster for HANA"
	sudo crm configure << EOF
primitive rsc_SAPHana_${hanasid}_HDB${hanainstancenumber} ocf:suse:SAPHana \
    operations $id="rsc_sap_${hanasid}_HDB${hanainstancenumber}-operations" \
    op start interval="0" timeout="3600" \
    op stop interval="0" timeout="3600" \
    op promote interval="0" timeout="3600" \
    op monitor interval="60" role="Master" timeout="700" \
    op monitor interval="61" role="Slave" timeout="700" \
    params SID="${hanasid}" InstanceNumber="${hanainstancenumber}" PREFER_SITE_TAKEOVER="true" \
    DUPLICATE_PRIMARY_TIMEOUT="7200" AUTOMATED_REGISTER="false"
ms msl_SAPHana_${hanasid}_HDB{$hanainstancenumber} rsc_SAPHana_${hanasid}_HDB{$hanainstancenumber} \
    meta is-managed="true" notify="true" clone-max="2" clone-node-max="1" \
    target-role="Started" interleave="true"
primitive rsc_ip_${hanasid}_HDB${hanainstancenumber} ocf:heartbeat:IPaddr2 \ 
    meta target-role="Started" is-managed="true" \ 
    operations $id="rsc_ip_${hanasid}_HDB${hanainstancenumber}-operations" \ 
    op monitor interval="10s" timeout="20s" \ 
    params ip="${lbip}" 
primitive rsc_nc_${hanasid}_HDB${hanainstancenumber} anything \ 
    params binfile="/usr/bin/nc" cmdline_options="-l -k 625${hanainstancenumber}" \ 
    op monitor timeout=20s interval=10 depth=0 
group g_ip_${hanasid}_HDB${hanainstancenumber} rsc_ip_${hanasid}_HDB${hanainstancenumber} rsc_nc_${hanasid}_HDB${hanainstancenumber}
colocation col_saphana_ip_${hanasid}_HDB${hanainstancenumber} 2000: g_ip_${hanasid}_HDB${hanainstancenumber}:Started \ 
    msl_SAPHana_${hanasid}_HDB${hanainstancenumber}:Master  
order ord_SAPHana_${hanasid}_HDB${hanainstancenumber} 2000: cln_SAPHanaTopology_${hanasid}_HDB${hanainstancenumber} \ 
    msl_SAPHana_${hanasid}_HDB${hanainstancenumber}	
commit
exit    
EOF
fi

echo "Done!"




