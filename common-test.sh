#!/bin/bash
# test cases for all the functionality in common.sh

node1="nfsvm0"
node2="nfsvm1"
username="testacc"



# $1 is the node to ssh into, $2 is the command to execute on the node
invokeSsh() {
    ssh $username@$1 "$2"
}

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

#testSbdSendMessage() {
#TODO
#
#}

#testNodeFailure() {
#
#}

#testNetworkDown() {
#
#}

#testSbdFailure() {
#
#}



. ./shunit2
