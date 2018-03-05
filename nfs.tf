
/*
variable "location" {
    default = "West US 2"
}

variable "byos" {
    default = false
}
*/

//
// Resource group globals
//

resource azurerm_resource_group "nfs" {
    name = "nfs"
    location = "${var.location}"
    tags {
        workload = "nfs"
    }
}

resource random_string "nfsvm_password" {
    length = 16
    special = true
}

output "nfsvm_password" {
    value = "${random_string.nfsvm_password.result}"
}


resource tls_private_key "nfsvm_key" {
    algorithm = "RSA"
}

locals {
    nfs_admin_user_name = "nfsadmin"
}
//
// NICs and PIPs, load balancers
//

resource azurerm_public_ip "nfs_pip" {
    count = 2
    name = "nfs_pip_${count.index}"
    location = "${azurerm_resource_group.nfs.location}"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    public_ip_address_allocation = "Dynamic"
    idle_timeout_in_minutes = 30
    domain_name_label = "nfs${count.index}"    
}

resource azurerm_network_interface "nfs_nic" {
    count = 2
    name = "nfs_nic_${count.index}"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    location = "${azurerm_resource_group.nfs.location}"
    ip_configuration {
        name = "nfs_nic_ipconfig"
        subnet_id = "${local.subnet_id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id = "${element(azurerm_public_ip.nfs_pip.*.id, count.index)}"
        load_balancer_backend_address_pools_ids = 
            ["${azurerm_lb_backend_address_pool.nfs_lb_backend_address_pool.id}"]
    }
}


resource azurerm_lb "nfs_lb" {
    name = "nfs_lb"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    location = "${azurerm_resource_group.nfs.location}"

    frontend_ip_configuration {
        name = "nfs_lb_ip_config"
        subnet_id = "${local.subnet_id}"
        private_ip_address_allocation = "Dynamic"
    }    
}

resource azurerm_lb_backend_address_pool "nfs_lb_backend_address_pool" {
    name = "nfs_lb_backend_address_pool"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    loadbalancer_id = "${azurerm_lb.nfs_lb.id}"    
}

resource azurerm_lb_rule "nfs_lb_rule" {
    name = "nfs_lb_rule"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    loadbalancer_id = "${azurerm_lb.nfs_lb.id}"    
    protocol = "Tcp"
    frontend_port = "2049" // NFS port
    backend_port = "2049"
    frontend_ip_configuration_name = "nfs_lb_ip_config"
}

resource azurerm_lb_probe "nfs_lb_probe" {
    name = "nfs_lb_probe"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    loadbalancer_id = "${azurerm_lb.nfs_lb.id}"    
    port = "2049"    
}

//
// VMs
//

resource azurerm_availability_set "nfs_as" {
    name = "nfs_as"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    location = "${azurerm_resource_group.nfs.location}"    
    managed = "true"
    platform_fault_domain_count = 2
}

resource azurerm_virtual_machine "nfs_vm" {
    count = 2
    name = "nfs_vm_${count.index}"
    location = "${azurerm_resource_group.nfs.location}"
    resource_group_name = "${azurerm_resource_group.nfs.name}"
    network_interface_ids = ["${element(azurerm_network_interface.nfs_nic.*.id, count.index)}"]
    delete_os_disk_on_termination = true
    vm_size = "${local.vmsize}"
    availability_set_id = "${azurerm_availability_set.nfs_as.id}"

    delete_data_disks_on_termination = true

    storage_image_reference {
        publisher = "SUSE"
        offer = "SLES-SAP"
        sku = "12-SP3"
        version = "latest"
    }
    storage_os_disk {
        name = "os_disk_vm_${count.index}"
        caching = "ReadWrite"
        create_option = "FromImage"
        managed_disk_type = "Standard_LRS"
    }
    storage_data_disk {
        name = "nfs_data_disk_vm_${count.index}"
        managed_disk_type = "Standard_LRS"
        create_option = "Empty"
        disk_size_gb = "1023"
        lun = 0
    }

    os_profile {
        computer_name = "nfsvm${count.index}"
        admin_username = "${local.nfs_admin_user_name}"
    }
    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys = [{
            path = "/home/${local.nfs_admin_user_name}/.ssh/authorized_keys"
            key_data = "${file("~/.ssh/id_rsa.pub")}"
        }]
    }

    connection {
        type = "ssh"
        user = "${local.nfs_admin_user_name}"
        private_key = "${file("~/.ssh/azureid_rsa")}"
        host = "nfs${count.index}.${var.location}.cloudapp.azure.com"
    }

    // Provision keys such that each vm can ssh to each other
    provisioner "file" {
        content = "${tls_private_key.nfsvm_key.private_key_pem}"
        destination = ".ssh/id_rsa"
    }

    provisioner "file" {
        content = "${tls_private_key.nfsvm_key.public_key_pem}"
        destination = ".ssh/id_rsa.pub"
    }

    provisioner "file" {
        content = "${tls_private_key.nfsvm_key.public_key_openssh}"
        destination = ".ssh/authorized_keys"
    }

    provisioner "file" {
        source = "config_nfs.sh"
        destination = "/tmp/config_nfs.sh"
    }
/*
    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/config_nfs.sh",
            "/tmp/config_nfs.sh ${join(" ", azurerm_network_interface.nfs_nic.*.private_ip_address)} ${join(" ", azurerm_virtual_machine.nfs_vm.*.computer_name)} ${count.index} ${random_string.nfsvm_password.result} ${azurerm_lb.nfs_lb.private_ip_address}" 
        ]
    }
*/
}
