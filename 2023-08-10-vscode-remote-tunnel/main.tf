locals {
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEcx4KMXdon65582m1zLP87W8aniAVTYXNkQjiPPzz9H"
}

variable "hcloud_token" {
  sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "main" {
  name       = "code-server"
  public_key = local.ssh_public_key
}

resource "hcloud_firewall" "main" {
  name = "code-server-ssh"
  rule {
    direction = "in"
    port      = "22"
    protocol  = "tcp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_server" "main" {
  name        = "nfelger-code"
  server_type = "cax11"
  image       = "ubuntu-22.04"
  location    = "fsn1"

  firewall_ids = [
    hcloud_firewall.main.id
  ]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  ssh_keys = [
    hcloud_ssh_key.main.id
  ]
  backups = false

  user_data = <<EOF
#cloud-config
package_update: true
package_upgrade: true
package_reboot_if_required: true

packages:
- git
- python3-pip
- apt-transport-https

users:
- name: admini
  shell: /bin/bash
  groups: sudo
  sudo: ALL=(ALL) NOPASSWD:ALL
  ssh_authorized_keys:
    - ${local.ssh_public_key}

write_files:
- content: |
    ---
    - hosts: localhost
      become: true
      any_errors_fatal: true
      tasks:
        - name: Disable root user
          ansible.builtin.user:
            name: root
            password_lock: true
            shell: /usr/sbin/nologin
            state: present
        
        - name: Remove public key from root user
          ansible.builtin.file:
            path: /root/.ssh/authorized_keys
            state: absent
        
        - name: Checkout konstruktoid.hardening
          ansible.builtin.git:
            repo: 'https://github.com/konstruktoid/ansible-role-hardening'
            dest: /etc/ansible/roles/konstruktoid.hardening
            version: master

        - name: Include the hardening role
          ansible.builtin.include_role:
            name: konstruktoid.hardening
          vars:
            compilers: ['dummy-i-dont-want-to-block-compilers']
            packages_blocklist:
              # all but git, rsync, telnet*
              - apport*
              - autofs*
              - avahi*
              - avahi-*
              - beep
              - pastebinit
              - popularity-contest
              - prelink
              - rpcbind
              - rsh*
              - talk*
              - tftp*
              - tuned
              - whoopsie
              - xinetd
              - yp-tools
              - ypbind
            sshd_admin_net:
              - 0.0.0.0/0
            sshd_allow_agent_forwarding: "yes"
            sshd_allow_groups: sudo
            suid_sgid_permissions: false
            ufw_enable: false
  path: /etc/ansible/playbooks/setup.yml

runcmd:
  - pip3 install ansible
  - sudo -u admini ansible-playbook /etc/ansible/playbooks/setup.yml --skip-tags grub
  - wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
  - install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  - sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  - rm -f packages.microsoft.gpg
  - apt update
  - apt install code --yes
  - sudo -u admini code tunnel service install --accept-server-license-terms
  - loginctl enable-linger admini
EOF
}

output "ipv4_address" {
  value = hcloud_server.main.ipv4_address
}
