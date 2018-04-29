#!/bin/bash

# $1 is the node to ssh into
# $2 is the command to execute on the node
invokeSsh() {
    ssh $username@$1 "$2"
}

# $1 is the node to ssh into
# $2 is the resource name to get status on
extractResourceStatus() {
    invokeSsh $1 "sudo crm resource status $2"
}

# $1 is the node to ssh into
# $2 is the resource name to validate
# $3 is the expected node that the resource is running on
validateResourceStatus() {
    x=`extractResourceStatus $1 $2`
    y=`echo "$x" | grep -oP "resource $2 is running on: \K(\S*)"`
    assertEquals "$2 is not running on $3" "$3" "$y"
}

# $1 is the node to fence from
# $2 is the node to fence
fenceNode() {
    invokeSsh $1 "sudo crm -F node fence $2"
    echo "Sleeping 60s for VM to come back up"
    sleep 60s
}
