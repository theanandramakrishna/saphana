provider "azurerm" {}

//
// Parameters
// Jumpbox (y/n)
// VMSize GS5, M64s, M64ms, M128s, M128ms, E16_v3, E32_v3, E64_v3
// BYOS or ondemand
// HANA System ID
// provisioner
// 

variable "location" {
  default = "westus2"
}

variable "vmsize" {
  default = "E16_v3"
}

variable "vmsizelist" {
  description = "Possible sizes for the VMs"
  type        = "list"
  default     = ["M64s", "M64ms", "M128s", "M128ms", "E16_v3", "E32_v3", "E64_v3"]
}

variable "testmode" {
  default = "1"
}

// The below is a hack for doing validations.  The count attribute does not exist on
// the null_resource, so assigning a non-zero value to it fails.
// The non-zero value is only assigned if the vmsize var is not in the vmsizelist
resource null_resource "is_vmsize_correct" {
  count                                            = "${contains(var.vmsizelist, var.vmsize) == true ? 0 : 1}"
  "ERROR: vmsize must be one of ${var.vmsizelist}" = true
}

locals {
  vmsize = "Standard_${var.vmsize}"
}

variable "hana_sid" {
  description = "SAP HANA system id"
  default     = "HDB"
}

variable "hana_instance_number" {
  type    = "string"
  default = "003"
}

variable "byos" {
  default = false
}

//
// Resource Group globals
//

resource azurerm_resource_group "saphana" {
  name     = "saphana"
  location = "${var.location}"

  tags {
    workload = "saphana"
  }
}

//
// Networks
//

resource azurerm_virtual_network "saphana" {
  name                = "saphana_vnet"
  location            = "${azurerm_resource_group.saphana.location}"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  address_space       = ["10.0.0.0/16"]
}

resource azurerm_network_security_group "saphana" {
  name                = "saphana_nsg"
  location            = "${azurerm_resource_group.saphana.location}"
  resource_group_name = "${azurerm_resource_group.saphana.name}"

  security_rule {
    name                       = "saphana_nsg_allow_rule"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "71.227.232.59"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "saphana_nsg_allow_vnet_rule"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "saphana_nsg_allow_lb_rule"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "saphana_nsg_deny_rule"
    priority                   = 3000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource azurerm_subnet "saphana" {
  name                      = "saphana_subnet"
  resource_group_name       = "${azurerm_resource_group.saphana.name}"
  virtual_network_name      = "${azurerm_virtual_network.saphana.name}"
  address_prefix            = "10.0.1.0/24"
  network_security_group_id = "${azurerm_network_security_group.saphana.id}"
}

locals {
  subnet_id = "${azurerm_subnet.saphana.id}"
}

resource azurerm_subnet "saphana_mgmt" {
  name                      = "saphana_mgmt_subnet"
  resource_group_name       = "${azurerm_resource_group.saphana.name}"
  virtual_network_name      = "${azurerm_virtual_network.saphana.name}"
  address_prefix            = "10.0.2.0/24"
  network_security_group_id = "${azurerm_network_security_group.saphana.id}"
}

resource random_string "hanavm_password" {
  length  = 16
  special = true
}

output "hanavm_password" {
  value = "${random_string.hanavm_password.result}"
}

//
// NICs and PIPs
//

resource azurerm_public_ip "bastion_pip" {
  name                         = "bastion_pip"
  location                     = "${azurerm_resource_group.saphana.location}"
  resource_group_name          = "${azurerm_resource_group.saphana.name}"
  public_ip_address_allocation = "Dynamic"
  idle_timeout_in_minutes      = 30
  domain_name_label            = "sapbastion"
}

locals {
  bastion_fqdn      = "${azurerm_public_ip.bastion_pip.fqdn}"
  bastion_user_name = "bastionuser"
}

resource azurerm_network_interface "bastion_nic" {
  name                = "bastion_nic"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  location            = "${azurerm_resource_group.saphana.location}"

  ip_configuration {
    name                          = "bastion_nic_ipconfig"
    subnet_id                     = "${azurerm_subnet.saphana.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.bastion_pip.id}"
  }
}

resource azurerm_network_interface "saphana_nic" {
  name                          = "saphana_nic_${count.index}"
  count                         = 2
  resource_group_name           = "${azurerm_resource_group.saphana.name}"
  location                      = "${azurerm_resource_group.saphana.location}"
  enable_accelerated_networking = true

  ip_configuration {
    name                                    = "saphana_nic_ipconfig"
    subnet_id                               = "${azurerm_subnet.saphana.id}"
    private_ip_address_allocation           = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.hanadb_lb_backend_address_pool.id}"]
  }
}

//
// Load balancers
//

resource azurerm_lb "hanadb_lb" {
  name                = "hanadb_lb"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  location            = "${azurerm_resource_group.saphana.location}"

  frontend_ip_configuration {
    name                          = "hanadb_lb_ip_config"
    subnet_id                     = "${azurerm_subnet.saphana.id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource azurerm_lb_backend_address_pool "hanadb_lb_backend_address_pool" {
  name                = "hanadb_lb_backend_address_pool"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id     = "${azurerm_lb.hanadb_lb.id}"
}

resource azurerm_lb_rule "hanadb_lb_rule_1" {
  name                           = "hanadb_lb_rule_1"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.hanadb_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "30315"                                                                // hana port
  backend_port                   = "30315"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.hanadb_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "hanadb_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
}

resource azurerm_lb_rule "hanadb_lb_rule_2" {
  name                           = "hanadb_lb_rule_2"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.hanadb_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "30317"                                                                // hana port
  backend_port                   = "30317"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.hanadb_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "hanadb_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.hanadb_lb_probe.id}"
}

resource azurerm_lb_probe "hanadb_lb_probe" {
  name                = "hanadb_lb_probe"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id     = "${azurerm_lb.hanadb_lb.id}"
  port                = "62503"
  protocol            = "Tcp"
}

//
// Storage
//

resource azurerm_storage_account "sap_storage_sbd" {
  name                     = "sapsbd${random_string.storage_suffix.result}"
  resource_group_name      = "${azurerm_resource_group.saphana.name}"
  location                 = "${azurerm_resource_group.saphana.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource azurerm_storage_share "sap_share_sbd" {
  name                 = "sapsbd"
  resource_group_name  = "${azurerm_resource_group.saphana.name}"
  storage_account_name = "${azurerm_storage_account.sap_storage_sbd.name}"
  quota                = 10
}

resource azurerm_storage_account "sap_diagnostics" {
  name                     = "sapdiag"
  resource_group_name      = "${azurerm_resource_group.saphana.name}"
  location                 = "${azurerm_resource_group.saphana.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

//
// VMs
//

locals {
  sap_admin_user_name = "sapadmin"

  sap_computer_name = [
    "hanavm0",
    "hanavm1",
  ]
}

resource tls_private_key "bastion_key_pair" {
  algorithm = "RSA"
}

resource azurerm_virtual_machine "bastion_vm" {
  name                          = "bastion"
  location                      = "${azurerm_resource_group.saphana.location}"
  resource_group_name           = "${azurerm_resource_group.saphana.name}"
  delete_os_disk_on_termination = true
  vm_size                       = "Standard_A1_v2"
  network_interface_ids         = ["${azurerm_network_interface.bastion_nic.id}"]

  storage_image_reference {
    publisher = "SUSE"
    offer     = "SLES-SAP"
    sku       = "12-SP3"
    version   = "latest"
  }

  storage_os_disk {
    name              = "os_disk_bastion"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "bastion"
    admin_username = "${local.bastion_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.bastion_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.sap_diagnostics.primary_blob_endpoint}"
  }
}

data template_file "common_test" {
  template = "${file("${path.module}/common-test.sh")}"

  vars {
    unittestuser                    = "unittestuser"
    unittestuser_public_key_openssh = "${tls_private_key.bastion_key_pair.public_key_openssh}"
    nfsvm0_name                     = "${element(local.computer_name, 0)}"
    nfsvm1_name                     = "${element(local.computer_name, 1)}"
    nfs_lb_ip                       = "${azurerm_lb.nfs_lb.private_ip_address}"
  }
}

data template_file "nfs_test" {
  template = "${file("${path.module}/nfs-test.sh")}"

  vars {
    unittestuser                    = "unittestuser"
    unittestuser_public_key_openssh = "${tls_private_key.bastion_key_pair.public_key_openssh}"
    nfsvm0_name                     = "${element(local.computer_name, 0)}"
    nfsvm1_name                     = "${element(local.computer_name, 1)}"
    nfs_lb_ip                       = "${azurerm_lb.nfs_lb.private_ip_address}"
  }
}

resource tls_private_key "sapvm_key" {
  algorithm = "RSA"
}

resource null_resource "tests" {
  depends_on = [
    "null_resource.configure-nfs-cluster-phase2", //"null_resource.configure-hana-cluster-1",
  ]

  connection {
    type        = "ssh"
    user        = "${local.bastion_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${local.bastion_fqdn}"
  }

  // Provision keys such that each vm can ssh to each other
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/tests",
    ]
  }

  provisioner "file" {
    content     = "${tls_private_key.bastion_key_pair.private_key_pem}"
    destination = "/tmp/tests/id_rsa"
  }

  provisioner "file" {
    source      = "shunit2"
    destination = "/tmp/tests/shunit2"
  }

  provisioner "file" {
    content     = "${data.template_file.common_test.rendered}"
    destination = "/tmp/tests/common-test.sh"
  }

  provisioner "file" {
    source      = "util-test.sh"
    destination = "/tmp/tests/util-test.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.nfs_test.rendered}"
    destination = "/tmp/tests/nfs-test.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /tmp/tests/id_rsa /home/${local.bastion_user_name}/.ssh",
      "sudo chown ${local.bastion_user_name} /home/${local.bastion_user_name}/.ssh/id_rsa",
      "sudo chmod 0400 /home/${local.bastion_user_name}/.ssh/id_rsa",
      "chmod +x /tmp/tests/*.sh",
    ]
  }
}

resource azurerm_availability_set "saphana_as" {
  name                        = "saphana_as"
  location                    = "${azurerm_resource_group.saphana.location}"
  resource_group_name         = "${azurerm_resource_group.saphana.name}"
  managed                     = "true"
  platform_fault_domain_count = 2
}

resource azurerm_virtual_machine "saphana_vm" {
  name                          = "saphana_vm_${count.index}"
  count                         = 2
  location                      = "${azurerm_resource_group.saphana.location}"
  resource_group_name           = "${azurerm_resource_group.saphana.name}"
  network_interface_ids         = ["${element(azurerm_network_interface.saphana_nic.*.id, count.index)}"]
  delete_os_disk_on_termination = true
  vm_size                       = "${local.vmsize}"
  availability_set_id           = "${azurerm_availability_set.saphana_as.id}"

  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "SUSE"
    offer     = "SLES-SAP"
    sku       = "12-SP3"
    version   = "latest"
  }

  storage_os_disk {
    name              = "os_disk_vm_${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name              = "sap_data_disk_vm_${count.index}_0"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    disk_size_gb      = "1023"
    lun               = 0
  }

  storage_data_disk {
    name              = "sap_data_disk_vm_${count.index}_1"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    disk_size_gb      = "1023"
    lun               = 1
  }

  storage_data_disk {
    name              = "sap_data_disk_vm_${count.index}_2"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    disk_size_gb      = "1023"
    lun               = 2
  }

  storage_data_disk {
    name              = "sap_data_disk_vm_${count.index}_3"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    disk_size_gb      = "1023"
    lun               = 3
  }

  os_profile {
    computer_name  = "${element(local.sap_computer_name, count.index)}"
    admin_username = "${local.sap_admin_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.sap_admin_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.sap_diagnostics.primary_blob_endpoint}"
  }
}

resource null_resource "configure-hana" {
  count      = 2
  depends_on = ["azurerm_virtual_machine.saphana_vm", "azurerm_virtual_machine.bastion_vm"]

  connection {
    type        = "ssh"
    user        = "${local.sap_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.sap_computer_name, count.index)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  // Provision keys such that each vm can ssh to each other
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/.ssh",
    ]
  }

  provisioner "file" {
    content     = "${tls_private_key.sapvm_key.private_key_pem}"
    destination = "/tmp/.ssh/id_rsa"
  }

  provisioner "file" {
    content     = "${tls_private_key.sapvm_key.public_key_pem}"
    destination = "/tmp/.ssh/id_rsa.pub"
  }

  provisioner "file" {
    content     = "${tls_private_key.sapvm_key.public_key_openssh}"
    destination = "/tmp/.ssh/authorized_keys"
  }

  provisioner "file" {
    source      = "config_hana.sh"
    destination = "/tmp/config_hana.sh"
  }

  provisioner "file" {
    source      = "common.sh"
    destination = "/tmp/common.sh"
  }
}

resource null_resource "configure-hana-cluster-0" {
  depends_on = ["null_resource.configure-hana"]

  connection {
    type        = "ssh"
    user        = "${local.sap_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.sap_computer_name, 0)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/config_hana.sh",
      "/tmp/config_hana.sh ${join(" ", azurerm_network_interface.saphana_nic.*.private_ip_address)} ${join(" ", local.sap_computer_name)} 0 \"${random_string.hanavm_password.result}\" ${azurerm_lb.hanadb_lb.private_ip_address} ${azurerm_storage_account.sap_storage_sbd.name} \"${azurerm_storage_account.sap_storage_sbd.primary_access_key}\" ${azurerm_storage_share.sap_share_sbd.name} ${var.hana_sid} ${var.hana_instance_number}",
    ]
  }
}

resource null_resource "configure-hana-cluster-1" {
  depends_on = ["null_resource.configure-hana-cluster-0"]

  connection {
    type        = "ssh"
    user        = "${local.sap_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.sap_computer_name, 1)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/config_hana.sh",
      "/tmp/config_hana.sh ${join(" ", azurerm_network_interface.saphana_nic.*.private_ip_address)} ${join(" ", local.sap_computer_name)} 1 \"${random_string.hanavm_password.result}\" ${azurerm_lb.hanadb_lb.private_ip_address} ${azurerm_storage_account.sap_storage_sbd.name} \"${azurerm_storage_account.sap_storage_sbd.primary_access_key}\" ${azurerm_storage_share.sap_share_sbd.name} ${var.hana_sid} ${var.hana_instance_number}",
    ]
  }
}
