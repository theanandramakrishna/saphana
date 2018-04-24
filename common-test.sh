#!/bin/bash
# test cases for all the functionality in common.sh

node1="nfsvm0"
node2="nfsvm1"
username="testacc"

source "util-test.sh"

# test whether ssh keys exist for root
testRootSsh() {
    for n in $node1 $node2
    do
        invokeSsh $n "sudo test -f /root/.ssh/id_rsa"
        assertEquals "No private key found on $n" $SHUNIT_TRUE $?

        invokeSsh $n "sudo test -f /root/.ssh/id_rsa.pub"
        assertEquals "No public key found on $n" $SHUNIT_TRUE $?

        x=`invokeSsh $n 'sudo stat --print "%a" /root/.ssh/id_rsa'`
        assertEquals "Private key is not locked to root on $n" 600 "$x"
    done
}

#$1 is service name
#$2 is node
isServiceEnabled() {
    x=`invokeSsh $2 "sudo systemctl status $1 | grep -o 'enabled;'"`
    assertEquals "$1 service not enabled not $2" "enabled;" "$x"
}

#$1 is service name
#$2 is node
isServiceActive() {
    x=`invokeSsh $2 "sudo systemctl status $1 | grep -o 'Active: active'"`
    assertEquals "$1 service not active on $2" "Active: active" "$x"
}

# test whether the fence device
testFenceDevice() {
    for n in $node1 $node2
    do
        invokeSsh $n "sudo test -b /dev/loop0"
        assertEquals "Loop0 device not found on $n" $SHUNIT_TRUE $?

        isServiceEnabled "loopfence" $n
        isServiceActive "loopfence" $n
    done
}

testWatchdog() {
    for n in $node1 $node2
    do
        invokeSsh $n "sudo test -c /dev/watchdog"
        assertEquals "watchdog not found on $n" $SHUNIT_TRUE $?

        x=`invokeSsh $n "sudo sysctl kernel.panic"`
        assertEquals "kernel panic not set on $n" "kernel.panic = 60" "$x"
    done
}

testNtp() {
    for n in $node1 $node2
    do
        isServiceEnabled "ntpd" $n
        isServiceActive "ntpd" $n
    done
}

testClusterStatus() {
    for n in $node1 $node2
    do
        x=`invokeSsh $n "sudo crm status simple | grep -o 'CLUSTER OK: 2 nodes online'"`
        assertEquals "Cluster not OK on $n" "CLUSTER OK: 2 nodes online" "$x"
    done
}

testSbdStatus() {
    for n in $node1 $node2
    do
        isServiceEnabled "sbd" $n
        isServiceActive "sbd" $n
    done
}

sendSbdTestMessage() {
    # Send message to $2 from $1
    sender=$1
    receiver=$2
    x=`invokeSsh $sender "sudo sbd -d /dev/loop0 message $receiver test"`
    assertEquals "Test sbd message not sent from $sender" "" "$x"
}

testSendSbdTestMessage_1_2() {
    sendSbdTestMessage $node1 $node2
}

testSendSbdTestMessage_2_1() {
    sendSbdTestMessage $node2 $node1    
}

extractRebootTime() {
    x=`invokeSsh $1 "who -b | grep -oP 'system boot\K(.*)'"`
    y=`date --date "$x" +%s`
    echo $y
}

sendSbdResetMessage() {
    sender=$1
    receiver=$2
    boottime1=`extractRebootTime $receiver`
    x=`invokeSsh $sender "sudo sbd -d /dev/loop0 message $receiver reset"`
    echo "Sleeping 90s for VM to come back up"
    sleep 90s

    boottime2=`extractRebootTime $receiver`
    assertNotNull "did not extract reboot time" "$boottime2"
    assertNotEquals "Node $receiver did not reset" $boottime1 $boottime2
}

testSendSbdReset_1_2() {
    sendSbdResetMessage $node1 $node2
}

testSendSbdReset_2_1() {
    sendSbdResetMessage $node2 $node1
}

testCrmFence_1() {
    boottime1=`extractRebootTime $node1`
    fenceNode $node2 $node1
    boottime2=`extractRebootTime $node1`
    assertNotEquals "Node $node1 did not reset" $boottime1 $boottime2
}

testCrmFence_2() {
    boottime1=`extractRebootTime $node2`
    fenceNode $node1 $node2
    boottime2=`extractRebootTime $node2`
    assertNotEquals "Node $node2 did not reset" $boottime1 $boottime2
}

testNodeFailure() {
    boottime1=`extractRebootTime $node2`
    invokeSsh $node2 "sudo echo c > /proc/sysrq-trigger"
    x=`invokeSsh $node1 "sudo crm node status | grep Stopped"`
    #Assert that all resources are still up despite 1 node crashing
    assertNull "Some resources are stopped" "$x"
    validateResourceStatus $node1 "fencing-sbd" $node1
    validateResourceStatus $node1 "stonith-sbd" $node1

    #Assert that node2 should automatically restart since restart on panic is configured
    echo "Sleeping 90s for VM to come back up"
    sleep 90s
    boottime2=`extractRebootTime $node2`
    assertNotEquals "Node $node2 did not reboot" $boottime1 $boottime2
}

#
#testNetworkDown() {
#    invokeSsh $node2 "sudo ifdown eth0 &"
#    x=`invokeSsh $node1 "sudo crm node status"`
    #Assert that all resources are still up despite network being down on 1 node
#    validateResourceStatus $node1 "fencing-sbd" $node1
#    validateResourceStatus $node1 "stonith-sbd" $node1

    # Must reboot node2
#}





. ./shunit2
