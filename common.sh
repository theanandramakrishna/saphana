#!/bin/bash

echo "Getting arguments"

ip1="$1"
ip2="$2"
host1="$3"
host2="$4"
nodeindex="$5"
password="$6"
lbip="$7"
storageacctname="$8"
storageacctkey="$9"
sharename="${10}"
#subscription="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2017-08-01&format=text"}"
#resourcegroup="${curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2017-08-01&format=text"}"

function initialize () {
    copySsh
    setupFenceDevice
    enableWatchdog
    enableNtp
    installPackages
}

# Copy over ssh keys for root account
# Assumes that keys have already been placed into /tmp
function copySsh () {
    echo "Copying ssh keys"
    sudo cp -R /tmp/.ssh /root/.ssh
    sudo chmod 0600 /root/.ssh/id_rsa  
    sudo shred -u -z /tmp/.ssh/*  
}

#Make directories, etc. for fencing device
function setupFenceDevice () {
    echo "Mounting share for fence device"
    sudo mkdir /mnt/$sharename

    cat << EOF | sudo tee /etc/smb.creds
username=${storageacctname}
password=${storageacctkey}
EOF
    sudo chmod 0600 /etc/smb.creds
    cat << EOF | sudo tee -a /etc/fstab
//${storageacctname}.file.core.windows.net/${sharename} /mnt/${sharename} cifs nofail,hard,vers=2.1,credentials=/etc/smb.creds,dir_mode=0777,cache=none,file_mode=0777,serverino
EOF

    sudo mount -a

    fencedevicepath="/mnt/$sharename/fencedevice"

    if [ "$nodeindex" = "0" ]
    then
        sudo dd if=/dev/zero of=$fencedevicepath bs=1M count=1024
    fi

    echo "Creating fence device"
    cat << EOF | sudo tee /usr/lib/systemd/system/loopfence.service
[Unit]
Description=Setup loop device for fencing
DefaultDependencies=false
ConditionFileIsExecutable=/usr/lib/systemd/scripts/createfenceloop.sh
After=systemd-udev-settle.service mnt-${sharename}.mount
Requires=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=/usr/lib/systemd/scripts/createfenceloop.sh
TimeoutSec=60
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat << EOF | sudo tee /usr/lib/systemd/scripts/createfenceloop.sh
#!/bin/bash
sudo losetup /dev/loop0 ${fencedevicepath}
EOF

    sudo chmod +x /usr/lib/systemd/scripts/createfenceloop.sh
    sudo systemctl enable loopfence.service
    sudo systemctl start loopfence.service
}

function enableWatchdog () {
    # Turn on softdog
    echo "Enabling softdog"
    echo softdog | sudo tee /etc/modules-load.d/watchdog.conf
    sudo systemctl restart systemd-modules-load    

    # Turn on reboot on panic, both for now and persistent across reboots
    sudo sysctl -w kernel.panic=60
    echo "kernel.panic=60" | sudo tee -a /etc/sysctl.conf    
}

function enableNtp () {
    # Turn on ntp at boot
    echo "Turn on ntp at boot"
    sudo systemctl enable ntpd.service   

    echo "Start ntp if not already"
    sudo systemctl start ntpd.service 
}

function installPackages () {
    #install fence agents
    echo "Installing fence agents and sle-ha-release"
    sudo zypper install -l -y sle-ha-release fence-agents    
}

function initializeCluster () {
    if [ "$nodeindex" = "0" ]
    then 
        # Use unicast, not multicast due to Azure support
        # Use the loopback device loop0 for sbd.
        # loopback was configured earlier in the fence setup
        echo "initialized ha cluster on primary"
        sudo ha-cluster-init -i eth0 -u -y -s /dev/loop0
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
}

function initializeCorosync () {
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
}

function configureClusterDefaults () {
    # Now configure cluster framework
    echo "Configure cluster defaults"
    sudo crm configure << EOF
rsc_defaults resource-stickiness="1"
property no-quorum-policy="ignore" stonith-enabled="true" stonith-action="reboot" stonith-timeout="150s"
commit
exit
EOF

    # Configure STONITH 
    echo "Configuring STONITH"
    sudo crm configure << EOF
primitive fencing-sbd stonith:external/sbd \
    op start start-delay="15"
EOF
}