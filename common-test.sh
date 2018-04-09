#!/bin/bash
# test cases for all the functionality in common.sh

# test whether ssh keys exist for root
testRootSsh() {
    test -f /root/.ssh/id_rsa
    assertEquals "No private key found" $? 0

    test -f /root/.ssh/id_rsa.pub
    assertEquals "No public key found" $? 0

    x=`stat --print "%a" /root/.ssh/id_rsa`
    assertEquals "Private key is not locked to root" "$x" 600
}

isServiceEnabled() {
    x=`sudo systemctl status $1 | grep -o "enabled;"`
    assertEquals "$1 service not enabled" "$x" "enabled;"
}

isServiceActive() {
    x=`sudo systemctl status $1 | grep -o "Active: active"`
    assertEquals "$1 service not active" "$x" "Active: active"
}

# test whether the fence device
testFenceDevice() {
    test -b /dev/loop0
    assertEquals "Loop0 device not found" $? 0

    isServiceEnabled "loopfence"
    isServiceActive "loopfence"
}

testWatchdog() {
    test -c /dev/watchdog
    assertEquals "watchdog not found" $? 0

    x=`sudo sysctl kernel.panic`
    assertEquals "kernel panic not set" "$x" "kernel.panic = 60"
}

testNtp() {
    isServiceEnabled "ntpd"
    isServiceActive "ntpd"
}

testClusterStatus() {
    x=`sudo crm status simple | grep -o "CLUSTER OK: 2 nodes online"`
    assertEquals "Cluster not OK" "$x" "CLUSTER OK: 2 nodes online" 
}

testSbdStatus() {
    isServiceEnabled "sbd"
    isServiceActive "sbd"
}

testSbdSendMessage() {
#TODO
}

testNodeFailure() {

}

testNetworkDown() {

}

testSbdFailure() {

}

. ./shunit2
