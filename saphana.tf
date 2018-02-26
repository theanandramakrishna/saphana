provider "azurerm" {
}
//
// Parameters
// Jumpbox (y/n)
// VMSize GS5, M64s, M64ms, M128s, M128ms, E16_v3, E32_v3, E64_v3
// BYOS or ondemand
// HANA System ID
// provisioner
// 

variable "location" {
    default = "West US 2"
}

variable "want_jumpbox" {
    default = false
}

variable "vmsize" {
    default = "E16_v3"
}
variable "vmsizelist" {
    description = "Possible sizes for the VMs"
    type = "list"
    default = ["M64s", "M64ms", "M128s", "M128ms", "E16_v3", "E32_v3", "E64_v3"]
}
// The below is a hack for doing validations.  The count attribute does not exist on
// the null_resource, so assigning a non-zero value to it fails.
// The non-zero value is only assigned if the vmsize var is not in the vmsizelist
resource null_resource "is_vmsize_correct" {
    count = "${contains(var.vmsizelist, var.vmsize) == true ? 0 : 1}"
    "ERROR: vmsize must be one of ${var.vmsizelist}" = true
}

locals {
    vmsize = "Standard_${var.vmsize}"
}

variable "hana_sid" {
    description = "SAP HANA system id"
    default = "H10"
}

variable "hana_instance_number" {
    type = "string"
    default = "00"
}

variable "byos" {
    default = false
}

//
// Resource Group globals
//

resource azurerm_resource_group "saphana" {
    name = "saphana"
    location = "${var.location}"
    tags {
        workload = "saphana"
    }
}

//
// Networks
//

resource azurerm_virtual_network "saphana" {
    name = "saphana_vnet"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    address_space = ["10.0.0.0/16"]
}

resource azurerm_network_security_group "saphana" {
    name = "saphana_nsg"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    security_rule {
        name = "saphana_nsg_allow_rule"
        priority = 100
        direction = "Inbound"
        access = "Allow"
        protocol = "*"
        source_port_range = "*"
        destination_port_range = "*"
        source_address_prefix = "*"
        destination_address_prefix = "*"
    }
    security_rule {
        name = "saphana_nsg_deny_rule"
        priority = 1000
        direction = "Inbound"
        access = "Deny"
        protocol = "*"
        source_port_range = "*"
        destination_port_range = "*"
        source_address_prefix = "*"
        destination_address_prefix = "*"
    }
} 

resource azurerm_subnet "saphana" {
    name = "saphana_subnet"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    virtual_network_name = "${azurerm_virtual_network.saphana.name}"
    address_prefix = "10.0.1.0/24"
    network_security_group_id = "${azurerm_network_security_group.saphana.id}"
}

locals {
    subnet_id = "${azurerm_subnet.saphana.id}"
}



resource azurerm_subnet "saphana_mgmt" {
    name = "saphana_mgmt_subnet"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    virtual_network_name = "${azurerm_virtual_network.saphana.name}"
    address_prefix = "10.0.2.0/24"
    network_security_group_id = "${azurerm_network_security_group.saphana.id}"
}

resource random_string "hanavm_password" {
    length = 16
    special = true
}

output "hanavm_password" {
    value = "${random_string.hanavm_password.result}"
}


//
// NICs and PIPs
//

resource azurerm_public_ip "saphana_pip" {
    name = "saphana_pip"
    count = 2
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    public_ip_address_allocation = "Dynamic"
    idle_timeout_in_minutes = 30    
}

resource azurerm_network_interface "saphana_nic" {
    name = "saphana_nic"
    count = 2
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    location = "${azurerm_resource_group.saphana.location}"
    ip_configuration {
        name = "saphana_nic_ipconfig"
        subnet_id = "${azurerm_subnet.saphana.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id = "${element(azurerm_public_ip.saphana_pip.*.id, count.index)}"
    }
}


//
// VMs
//
resource azurerm_availability_set "saphana_as" {
    name = "saphana_as"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    managed = "true"
    platform_fault_domain_count = 2
}


resource azurerm_virtual_machine "saphana_vm" {
    name = "saphana_vm"
    count = 2
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    network_interface_ids = ["${element(azurerm_network_interface.saphana_nic.*.id, count.index)}"]
    delete_os_disk_on_termination = true
    vm_size = "${local.vmsize}"
    availability_set_id = "${azurerm_availability_set.saphana_as.id}"

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
        name = "sap_data_disk_vm_${count.index}"
        managed_disk_type = "Standard_LRS"
        create_option = "Empty"
        disk_size_gb = "1023"
        lun = 0
    }
    storage_data_disk {
        name = "sap_log_disk_vm_${count.index}"
        managed_disk_type = "Standard_LRS"
        create_option = "Empty"
        disk_size_gb = "1023"
        lun = 1
    }

    os_profile {
        computer_name = "saphanavm${count.index}"
        admin_username = "sapadmin"
        admin_password = "${random_string.hanavm_password.result}"
    }
    os_profile_linux_config {
        disable_password_authentication = false
    }
}

