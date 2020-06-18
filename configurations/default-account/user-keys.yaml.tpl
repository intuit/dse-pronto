# cloud-config
system_info:
  default_user:
    name: ec2-user

groups:
  - users: [ansible, ec2-user]

users:
  - name: ansible
    groups: default
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - ##ANSIBLE_PUB_KEY##
  - name: ec2-user
    ssh-authorized-keys:
      - ##PERSONAL_PUB_KEY##
