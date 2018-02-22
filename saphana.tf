provider "azurerm" {
}

resource "azurerm_resource_group" "saphana" {
    name = "saphana"
    location = "West US 2"
}

resource "azurerm_virtual_network" "saphana" {
    name = "saphana_vnet"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    address_space = ["10.0.0.0/16"]
}

resource azurerm_subnet "saphana" {
    name = "saphana_subnet"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    virtual_network_name = "${azurerm_virtual_network.saphana.name}"
    address_prefix = "10.0.1.0/24"
}

resource azurerm_public_ip "saphana_pip_1" {
    name = "saphana_pip_1"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    public_ip_address_allocation = "Dynamic"
    idle_timeout_in_minutes = 30    
}
resource azurerm_public_ip "saphana_pip_2" {
    name = "saphana_pip_2"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    public_ip_address_allocation = "Dynamic"
    idle_timeout_in_minutes = 30    
}

resource azurerm_network_interface "saphana_nic_1" {
    name = "saphana_nic_1"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    location = "${azurerm_resource_group.saphana.location}"
    ip_configuration {
        name = "saphana_nic_ipconfig"
        subnet_id = "${azurerm_subnet.saphana.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id = "${azurerm_public_ip.saphana_pip_1.id}"
    }
}

/*
resource azurerm_managed_disk "saphana" {
    name = "saphana_disk_1"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    storage_account_type = "Standard_LRS"
    create_option = "Empty"
    disk_size_gb = "1023"
}
*/

resource azurerm_virtual_machine "saphana" {
    name = "saphana_vm_1"
    location = "${azurerm_resource_group.saphana.location}"
    resource_group_name = "${azurerm_resource_group.saphana.name}"
    network_interface_ids = ["${azurerm_network_interface.saphana_nic_1.id}"]
    vm_size = "Standard_DS1_v2"
    delete_os_disk_on_termination = true
    delete_data_disks_on_termination = true

    storage_image_reference {
        publisher = "SUSE"
        offer = "SLES-SAP"
        sku = "12-SP3"
        version = "latest"
    }
    storage_os_disk {
        name = "os_disk"
        caching = "ReadWrite"
        create_option = "FromImage"
        managed_disk_type = "Standard_LRS"
    }
    storage_data_disk {
        name = "data_disk_1"
        managed_disk_type = "Standard_LRS"
        create_option = "Empty"
        disk_size_gb = "1023"
        lun = 0
    }

    os_profile {
        computer_name = "saphanavm1"
        admin_username = "sapadmin"
        admin_password = "Password1234!"
    }
    os_profile_linux_config {
        disable_password_authentication = false
    }
}