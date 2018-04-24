#!/bin/bash

node1="nfsvm0"
node2="nfsvm1"
nfsip="10.0.1.4"
username="testacc"

testNfsServerStatus() {
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
    x=`extractResourceStatus $1 drbd_NWS_nfs`
    y=echo "$x" | grep -oP "resource drbd_NWS_nfs is running on: \K(.*) Master"
    assertEquals "drbd_NWS_nfs is not running on $2" "$2" "$y"
}

testDrbdStatus() {
    validateResourceStatus $node1 $node1
}

setUp() {
    sudo mkdir /mnt/test
    sudo mount $nfsip:/ /mnt/test
}

tearDown() {
    sudo umount /mnt/test
}

# $1 is the node to promote to master
promoteToMaster() {
    invokeSsh $1 "sudo crm resource promote drbd_NWS_nfs"
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
    dd if=/dev/zero of=/mnt/test/NWS/testdata bs=1k count=16k
    assertTrue "/mnt/test/NWS/testdata does not exist" "[ -r /mnt/test/NWS/testdata ]"
    rm /mnt/test/NWS/testdata
}

testNfsFailover_Read() {
    promoteToMaster $node1
    dd if=/dev/zero of=/mnt/test/NWS/testdata bs=1k count=16k
    assertTrue "/mnt/test/NWS/testdata does not exist" "[ -r /mnt/test/NWS/testdata ]"
    fenceNode $node2 $node1
    assertTrue "/mnt/test/NWS/testdata does not exist after fencing" "[ -r /mnt/test/NWS/testdata ]"
}

testNfsFailover_Write() {
    dd if=/dev/zero of=/mnt/test/NWS/testdata bs=1k count=128k &
    fenceNode $node2 $node1
    assertTrue "/mnt/test/NWS/testdata does not exist after fencing" "[ -r /mnt/test/NWS/testdata ]" 
    #TODO Also check size of file and ensure that no writes were missed.   
}

. ./shunit2
