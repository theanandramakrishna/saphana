variable "username" {}

variable "public_key" {}

variable "conn_username" {}

variable "conn_host" {}

variable "conn_private_key" {}

variable "conn_bastion_host" {
  default = ""
}

variable "conn_bastion_user" {
  default = ""
}

variable "enabled" {
  default = "1"
}

variable "depends_on" {
  default = [], type = "list"
}

resource null_resource "adduser" {
  count = "${var.enabled}"

  connection {
    type        = "ssh"
    user        = "${var.conn_username}"
    private_key = "${var.conn_private_key}"
    host        = "${var.conn_host}"

    bastion_host = "${var.conn_bastion_host}"
    bastion_user = "${var.conn_bastion_user}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo useradd -m ${var.username}",
      "echo '${var.username} ALL=(ALL) NOPASSWD: ALL' | sudo tee -a /etc/sudoers.d/tf-test",
      "sudo chmod 0400 /etc/sudoers.d/tf-test",
      "sudo mkdir /home/${var.username}/.ssh",
      "sudo chmod 0700 /home/${var.username}/.ssh",
      "echo '${var.public_key}' | sudo tee -a /home/${var.username}/.ssh/authorized_keys",
      "sudo chmod 0644 /home/${var.username}/.ssh/authorized_keys",
    ]
  }
}
