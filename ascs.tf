//
// NICs
//

locals {
  ascs_computer_name = [
    "ascs0",
    "ascs1",
  ]

  ascs_admin_user_name = "ascsadmin"
}

resource azurerm_network_interface "ascs_nic" {
  name                          = "ascs_nic_${count.index}"
  count                         = 2
  resource_group_name           = "${azurerm_resource_group.saphana.name}"
  location                      = "${azurerm_resource_group.saphana.location}"
  enable_accelerated_networking = true
  internal_dns_name_label       = "${element(local.ascs_computer_name, count.index)}"

  ip_configuration {
    name                          = "ascs_nic_ipconfig"
    subnet_id                     = "${azurerm_subnet.saphana.id}"
    private_ip_address_allocation = "dynamic"

    load_balancer_backend_address_pools_ids = [
      "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}",
      "${azurerm_lb_backend_address_pool.ascs_ers_lb_backend_address_pool.id}",
    ]
  }
}

//
// Load balancers
//

resource azurerm_lb "ascs_lb" {
  name                = "ascs_lb"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  location            = "${azurerm_resource_group.saphana.location}"

  frontend_ip_configuration {
    name                          = "ascs_lb_ip_config"
    subnet_id                     = "${azurerm_subnet.saphana.id}"
    private_ip_address_allocation = "Dynamic"
  }

  frontend_ip_configuration {
    name                          = "ascs_ers_lb_ip_config"
    subnet_id                     = "${azurerm_subnet.saphana.id}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource azurerm_lb_backend_address_pool "ascs_lb_backend_address_pool" {
  name                = "ascs_lb_backend_address_pool"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id     = "${azurerm_lb.ascs_lb.id}"
}

resource azurerm_lb_backend_address_pool "ascs_ers_lb_backend_address_pool" {
  name                = "ascs_ers_lb_backend_address_pool"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id     = "${azurerm_lb.ascs_lb.id}"
}

resource azurerm_lb_rule "ascs_lb_rule_1" {
  name                           = "ascs_lb_rule_1"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "3200"
  backend_port                   = "3200"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
}

resource azurerm_lb_rule "ascs_lb_rule_2" {
  name                           = "ascs_lb_rule_2"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "3600"
  backend_port                   = "3600"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_lb_rule_3" {
  name                           = "ascs_lb_rule_3"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "3900"
  backend_port                   = "3900"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_lb_rule_4" {
  name                           = "ascs_lb_rule_4"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "8100"
  backend_port                   = "8100"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_lb_rule_5" {
  name                           = "ascs_lb_rule_5"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "50013"
  backend_port                   = "50013"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_lb_rule_6" {
  name                           = "ascs_lb_rule_6"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "50014"
  backend_port                   = "50014"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_lb_rule_7" {
  name                           = "ascs_lb_rule_7"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "50016"
  backend_port                   = "50016"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_ers_lb_rule_1" {
  name                           = "ascs_ers_lb_rule_1"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "3302"
  backend_port                   = "3302"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_ers_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_ers_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_ers_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_ers_lb_rule_2" {
  name                           = "ascs_ers_lb_rule_2"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "50213"
  backend_port                   = "50213"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_ers_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_ers_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_ers_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_ers_lb_rule_3" {
  name                           = "ascs_ers_lb_rule_3"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "50214"
  backend_port                   = "50214"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_ers_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_ers_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_ers_lb_probe.id}"
}

resource azurerm_lb_rule "ascs_ers_lb_rule_4" {
  name                           = "ascs_ers_lb_rule_4"
  resource_group_name            = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id                = "${azurerm_lb.ascs_lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "50216"
  backend_port                   = "50216"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.ascs_ers_lb_backend_address_pool.id}"
  frontend_ip_configuration_name = "ascs_ers_lb_ip_config"
  idle_timeout_in_minutes        = "30"
  enable_floating_ip             = "true"
  probe_id                       = "${azurerm_lb_probe.ascs_ers_lb_probe.id}"
}

resource azurerm_lb_probe "ascs_lb_probe" {
  name                = "ascs_lb_probe"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id     = "${azurerm_lb.ascs_lb.id}"
  port                = "62000"
  protocol            = "Tcp"
  interval_in_seconds = "5"
  number_of_probes    = 2
}

resource azurerm_lb_probe "ascs_ers_lb_probe" {
  name                = "ascs_ers_lb_probe"
  resource_group_name = "${azurerm_resource_group.saphana.name}"
  loadbalancer_id     = "${azurerm_lb.ascs_lb.id}"
  port                = "62102"
  protocol            = "Tcp"
  interval_in_seconds = "5"
  number_of_probes    = 2
}

//
// Storage
//

resource azurerm_storage_account "ascs_storage_sbd" {
  name                     = "ascssbd${random_string.storage_suffix.result}"
  resource_group_name      = "${azurerm_resource_group.saphana.name}"
  location                 = "${azurerm_resource_group.saphana.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource azurerm_storage_share "ascs_share_sbd" {
  name                 = "ascssbd"
  resource_group_name  = "${azurerm_resource_group.saphana.name}"
  storage_account_name = "${azurerm_storage_account.ascs_storage_sbd.name}"
  quota                = 10
}

resource azurerm_storage_account "ascs_diagnostics" {
  name                     = "ascsdiag"
  resource_group_name      = "${azurerm_resource_group.saphana.name}"
  location                 = "${azurerm_resource_group.saphana.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

//
// VMs
//

resource azurerm_availability_set "ascs_as" {
  name                        = "ascs_as"
  resource_group_name         = "${azurerm_resource_group.saphana.name}"
  location                    = "${azurerm_resource_group.saphana.location}"
  managed                     = "true"
  platform_fault_domain_count = 2
}

resource azurerm_virtual_machine "ascs_vm" {
  count                         = 2
  name                          = "ascs_vm_${count.index}"
  location                      = "${azurerm_resource_group.saphana.location}"
  resource_group_name           = "${azurerm_resource_group.saphana.name}"
  network_interface_ids         = ["${element(azurerm_network_interface.ascs_nic.*.id, count.index)}"]
  delete_os_disk_on_termination = true
  vm_size                       = "Standard_D4_v2"
  availability_set_id           = "${azurerm_availability_set.ascs_as.id}"

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
    name              = "ascs_data_disk_vm_${count.index}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    disk_size_gb      = "1023"
    lun               = 0
  }

  os_profile {
    computer_name  = "${element(local.ascs_computer_name, count.index)}"
    admin_username = "${local.ascs_admin_user_name}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = [{
      path     = "/home/${local.ascs_admin_user_name}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/azureid_rsa.pub")}"
    }]
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.ascs_diagnostics.primary_blob_endpoint}"
  }
}

resource tls_private_key "ascsvm_key" {
  algorithm = "RSA"
}

data template_file "config_ascs_file" {
  template = "${file("${path.module}/configascs.sh")}"

  vars {
    ascs_privateip_0     = "${azurerm_network_interface.ascs_nic.0.private_ip_address}"
    ascs_privateip_1     = "${azurerm_network_interface.ascs_nic.1.private_ip_address}"
    ascs_computer_name_0 = "${element(local.ascs_computer_name, 0)}"
    ascs_computer_name_1 = "${element(local.ascs_computer_name, 1)}"
    ascs_user_password   = "${random_string.ascs_password.result}"
    ascs_lb_ip           = "${element(azurerm_lb.ascs_lb.private_ip_addresses, 0)}"
    ascs_ers_lb_ip       = "${element(azurerm_lb.ascs_lb.private_ip_addresses, 1)}"
    nfs_lb_ip            = "${azurerm_lb.nfs_lb.private_ip_address}"
    hana_lb_ip           = "${azurerm_lb.hanadb_lb.private_ip_address}"
    ascs_sbd_name        = "${azurerm_storage_account.ascs_storage_sbd.name}"
    ascs_sbd_key         = "${azurerm_storage_account.ascs_storage_sbd.primary_access_key}"
    ascs_sbd_share_name  = "${azurerm_storage_share.ascs_share_sbd.name}"
    ascs_sid             = "${var.hana_sid}"
    ascs_instance_number = "${var.hana_instance_number}"
  }
}

resource null_resource "ascs_copyfile" {
  count      = 2
  depends_on = ["azurerm_virtual_machine.ascs_vm", "azurerm_virtual_machine.bastion_vm"]

  connection {
    type        = "ssh"
    user        = "${local.ascs_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.ascs_computer_name, count.index)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/.ssh",
    ]
  }

  // Provision keys such that each vm can ssh to each other
  provisioner "file" {
    content     = "${tls_private_key.ascsvm_key.private_key_pem}"
    destination = "/tmp/.ssh/id_rsa"
  }

  provisioner "file" {
    content     = "${tls_private_key.ascsvm_key.public_key_pem}"
    destination = "/tmp/.ssh/id_rsa.pub"
  }

  provisioner "file" {
    content     = "${tls_private_key.ascsvm_key.public_key_openssh}"
    destination = "/tmp/.ssh/authorized_keys"
  }

  provisioner "file" {
    source      = "common.sh"
    destination = "/tmp/common.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.config_ascs_file.rendered}"
    destination = "/tmp/config_ascs.sh"
  }
}

resource random_string "ascs_password" {
  length  = 16
  special = true
}

resource null_resource "configure-ascs" {
  count      = 2
  depends_on = ["null_resource.ascs_copyfile"]

  connection {
    type        = "ssh"
    user        = "${local.ascs_admin_user_name}"
    private_key = "${file("~/.ssh/azureid_rsa")}"
    host        = "${element(local.ascs_computer_name, count.index)}"

    bastion_host = "${local.bastion_fqdn}"
    bastion_user = "${local.bastion_user_name}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/config_ascs.sh",
      "/tmp/config_ascs.sh  ${count.index}",
    ]
  }
}
