#!/bin/bash

node1="nfsvm0"
node2="nfsvm1"
nfsip="10.0.1.4"
username="testacc"

source "util-test.sh"

testNfsServerStatus() {
    fenceNode $node1 $node2
    validateResourceStatus $node1 "fs_NWS_sapmnt" $node1
    validateResourceStatus $node1 "exportfs_NWS" $node1
    validateResourceStatus $node1 "exportfs_NWS_sidsys" $node1
    validateResourceStatus $node1 "exportfs_NWS_sapmntsid" $node1
    validateResourceStatus $node1 "exportfs_NWS_trans" $node1
    validateResourceStatus $node1 "exportfs_NWS_ASCS" $node1
    validateResourceStatus $node1 "exportfs_NWS_ASCSERS" $node1
    validateResourceStatus $node1 "exportfs_NWS_SCS" $node1
    validateResourceStatus $node1 "exportfs_NWS_SCSERS" $node1
    validateResourceStatus $node1 "nc_NWS_nfs" $node1
    validateResourceStatus $node1 "vip_NWS_nfs" $node1
}

# $1 is where to get status from
# $2 is where drbd is expected to be master
validateDrbdStatus() {
    x=`extractResourceStatus $1 ms-drbd_NWS_nfs`
    y=`echo "$x" | grep -oP "resource ms-drbd_NWS_nfs is running on: \K(\S*) Master"`
    assertEquals "ms-drbd_NWS_nfs is not running on $2" "$2 Master" "$y"
}

testDrbdStatus() {
    validateDrbdStatus $node1 $node1
}

setUp() {
    sudo mkdir -p /mnt/test
    sudo mount $nfsip:/ /mnt/test
}

tearDown() {
    sudo umount /mnt/test
}

# $1 is the node to promote to master
promoteToMaster() {
    invokeSsh $1 "sudo crm resource promote ms-drbd_NWS_nfs"
    validateDrbdStatus $1 $1
}

testNfsRead() {
    assertTrue "/mnt/test/NWS does not exist" "[ -r /mnt/test/NWS ]"
    assertTrue "/mnt/test/NWS/trans does not exist" "[ -r /mnt/test/NWS/trans ]"
    assertTrue "/mnt/test/NWS/sidsys does not exist" "[ -r /mnt/test/NWS/sidsys ]"
    assertTrue "/mnt/test/NWS/SCSERS does not exist" "[ -r /mnt/test/NWS/SCSERS ]"
    assertTrue "/mnt/test/NWS/SCS does not exist" "[ -r /mnt/test/NWS/SCS ]"
    assertTrue "/mnt/test/NWS/sapmntsid does not exist" "[ -r /mnt/test/NWS/sapmntsid ]"
    assertTrue "/mnt/test/NWS/ASCSERS does not exist" "[ -r /mnt/test/NWS/ASCSERS ]"
    assertTrue "/mnt/test/NWS/ASCS does not exist" "[ -r /mnt/test/NWS/ASCS ]"
}


testNfsWrite() {
    sudo dd if=/dev/zero of=/mnt/test/NWS/testdata bs=1k count=16k
    assertTrue "/mnt/test/NWS/testdata does not exist" "[ -r /mnt/test/NWS/testdata ]"
    sudo rm /mnt/test/NWS/testdata
}

testNfsFailover_Read() {
    promoteToMaster $node1
    sudo dd if=/dev/zero of=/mnt/test/NWS/testdata bs=1k count=16k
    assertTrue "/mnt/test/NWS/testdata does not exist" "[ -r /mnt/test/NWS/testdata ]"
    fenceNode $node2 $node1
    assertTrue "/mnt/test/NWS/testdata does not exist after fencing" "[ -r /mnt/test/NWS/testdata ]"
}

testNfsFailover_Write() {
    # Write a 512M file (512k blocks of 1k each)
    sudo dd if=/dev/zero of=/mnt/test/NWS/testdata bs=1k count=512k &
    sleep 1s
    fenceNode $node2 $node1
    assertTrue "/mnt/test/NWS/testdata does not exist after fencing" "[ -r /mnt/test/NWS/testdata ]" 
    x=`sudo du -BM /mnt/test/NWS/testdata | cut -f1`
    assertEquals "/mnt/test/NWS/testdata is unexpected size" "512M" "$x"
}

. ./shunit2
