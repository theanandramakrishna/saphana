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
  name     = "nfs"
  location = "${var.location}"

  tags {
    workload = "nfs"
  }
}

resource random_string "nfsvm_password" {
  length  = 16
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

locals {
  computer_name = [
    "nfsvm0",
    "nfsvm1",
  ]
}

//
// NICs and PIPs, load balancers
//

resource azurerm_network_interface "nfs_nic" {
  count               = 2
  name                = "nfs_nic_${count.index}"
  resource_group_name = "${azurerm_resource_group.nfs.name}"
  location            = "${azurerm_resource_group.nfs.location}"

  ip_configuration {
    name                                    = "nfs_nic_ipconfig"
    subnet_id                               = "${local.subnet_id}"
    private_ip_address_allocation           = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.nfs_lb_backend_address_pool.id}"]
  }
}

resource azurerm_lb "nfs_lb" {
  name                = "nfs_lb"
  resource_group_name = "${azurerm_resource_group.nfs.name}"
  location            = "${azurerm_resource_group.nfs.location}"

  frontend_ip_configuration {
    name                          = "nfs_lb_ip_config"
    subnet_id                     = "${local.subnet_id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource azurerm_lb_backend_address_pool "nfs_lb_backend_address_pool" {
  name                = "nfs_lb_backend_address_pool"
  resource_group_name = "${azurerm_resource_group.nfs.name}"
  loadbalancer_id     = "${azurerm_lb.nfs_lb.id}"
}

resource azurerm_lb_rule "nfs_lb_rule" {
  name                           = "nfs_lb_rule"
  resource_group_name            = "${azurerm_resource_group.nfs.name}"
  loadbalancer_id                = "${azurerm_lb.nfs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "2049"                                                              // NFS port
  backend_port                   = "2049"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.nfs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "nfs_lb_ip_config"
  probe_id                       = "${azurerm_lb_probe.nfs_lb_probe.id}"
  enable_floating_ip             = "true"
  idle_timeout_in_minutes        = "30"
}

resource azurerm_lb_probe "nfs_lb_probe" {
  name                = "nfs_lb_probe"
  resource_group_name = "${azurerm_resource_group.nfs.name}"
  loadbalancer_id     = "${azurerm_lb.nfs_lb.id}"
  port                = "61000"
  protocol            = "Tcp"
}

//
// Storage
//

resource random_string "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource azurerm_storage_account "nfs_storage_sbd" {
  name                     = "nfssbd${random_string.storage_suffix.result}"
  resource_group_name      = "${azurerm_resource_group.nfs.name}"
  location                 = "${azurerm_resource_group.nfs.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource azurerm_storage_share "nfs_share_sbd" {
  name                 = "nfssbd"
  resource_group_name  = "${azurerm_resource_group.nfs.name}"
  storage_account_name = "${azurerm_storage_account.nfs_storage_sbd.name}"
  quota                = 10
}

resource azurerm_storage_account "nfs_diagnostics" {
  name                     = "nfsdiag${random_string.storage_suffix.result}"
  resource_group_name      = "${azurerm_resource_group.nfs.name}"
  location                 = "${azurerm_resource_group.nfs.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

//
// VMs
//

resource azurerm_availability_set "nfs_as" {
  name                        = "nfs_as"
  resource_group_name         = "${azurerm_resource_group.nfs.name}"
  location                    = "${azurerm_resource_group.nfs.location}"
  managed                     = "true"
  platform_fault_domain_count = 2
}

resource azurerm_virtual_machine "nfs_vm" {
  count                         = 2
  name                          = "nfs_vm_${count.index}"
  location                      = "${azurerm_resource_group.nfs.location}"
  resource_group_name           = "${azurerm_resource_group.nfs.name}"
  network_interface_ids         = ["${element(azurerm_network_interface.nfs_nic.*.id, count.index)}"]
  delete_os_disk_on_termination = true
  vm_size                       = "${local.vmsize}"
  availability_set_id           = "${azurerm_availability_set.nfs_as.id}"

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
    name              = "nfs_data_disk_vm_${count.index}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    disk_size_gb      = "1023"
    lun               = 0
  }

  os_profile {
    computer_name  = "${element(local.computer_name, count.index)}"
    admin_username = "${local.nfs_admin_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.nfs_admin_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.nfs_diagnostics.primary_blob_endpoint}"
  }
}

resource null_resource "configure-nfs" {
  count      = 2
  depends_on = ["azurerm_virtual_machine.nfs_vm"]

  connection {
    type        = "ssh"
    user        = "${local.nfs_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.computer_name, count.index)}"

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
    content     = "${tls_private_key.nfsvm_key.private_key_pem}"
    destination = "/tmp/.ssh/id_rsa"
  }

  provisioner "file" {
    content     = "${tls_private_key.nfsvm_key.public_key_pem}"
    destination = "/tmp/.ssh/id_rsa.pub"
  }

  provisioner "file" {
    content     = "${tls_private_key.nfsvm_key.public_key_openssh}"
    destination = "/tmp/.ssh/authorized_keys"
  }

  provisioner "file" {
    source      = "config_nfs_phase1.sh"
    destination = "/tmp/config_nfs_phase1.sh"
  }

  provisioner "file" {
    source      = "config_nfs_phase2.sh"
    destination = "/tmp/config_nfs_phase2.sh"
  }

  provisioner "file" {
    source      = "common.sh"
    destination = "/tmp/common.sh"
  }
}

resource null_resource "configure-nfs-cluster-0" {
  depends_on = ["null_resource.configure-nfs"]

  connection {
    type        = "ssh"
    user        = "${local.nfs_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.computer_name, 0)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/common.sh",
      "chmod +x /tmp/config_nfs_phase1.sh",
      "/tmp/config_nfs_phase1.sh ${join(" ", azurerm_network_interface.nfs_nic.*.private_ip_address)} ${join(" ", local.computer_name)} 0 \"${random_string.nfsvm_password.result}\" ${azurerm_lb.nfs_lb.private_ip_address} ${azurerm_storage_account.nfs_storage_sbd.name} \"${azurerm_storage_account.nfs_storage_sbd.primary_access_key}\" ${azurerm_storage_share.nfs_share_sbd.name}",
    ]
  }
}

resource null_resource "configure-nfs-cluster-1" {
  depends_on = ["null_resource.configure-nfs", "null_resource.configure-nfs-cluster-0"]

  connection {
    type        = "ssh"
    user        = "${local.nfs_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.computer_name, 1)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/config_nfs_phase1.sh",
      "/tmp/config_nfs_phase1.sh ${join(" ", azurerm_network_interface.nfs_nic.*.private_ip_address)} ${join(" ", local.computer_name)} 1 \"${random_string.nfsvm_password.result}\" ${azurerm_lb.nfs_lb.private_ip_address} ${azurerm_storage_account.nfs_storage_sbd.name} \"${azurerm_storage_account.nfs_storage_sbd.primary_access_key}\" ${azurerm_storage_share.nfs_share_sbd.name}",
    ]
  }
}

resource null_resource "configure-nfs-cluster-phase2" {
  depends_on = ["null_resource.configure-nfs-cluster-1"]

  connection {
    type        = "ssh"
    user        = "${local.nfs_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.computer_name, 0)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/config_nfs_phase2.sh",
      "/tmp/config_nfs_phase2.sh ${join(" ", azurerm_network_interface.nfs_nic.*.private_ip_address)} ${join(" ", local.computer_name)} 0 \"${random_string.nfsvm_password.result}\" ${azurerm_lb.nfs_lb.private_ip_address} ${azurerm_storage_account.nfs_storage_sbd.name} \"${azurerm_storage_account.nfs_storage_sbd.primary_access_key}\" ${azurerm_storage_share.nfs_share_sbd.name}",
    ]
  }
}
