#!/bin/bash

sudo useradd -m ${unittestuser}
echo "${unittestuser} ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers.d/tf-test
sudo chmod 0400 /etc/sudoers.d/tf-test
sudo mkdir /home/${unittestuser}/.ssh
sudo chmod 0700 /home/${unittestuser}/.ssh
echo "${unittestuser_public_key_openssh}" | sudo tee -a /home/${unittestuser}/.ssh/authorized_keys
sudo chmod 0644 /home/${unittestuser}/.ssh/authorized_keys
