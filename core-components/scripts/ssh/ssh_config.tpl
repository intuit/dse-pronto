Host *
  StrictHostKeyChecking no
  GlobalKnownHostsFile /dev/null
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  ServerAliveInterval 30
  TCPKeepAlive yes
  ForwardAgent yes

##########################################################

Host bastion
  HostName ##BASTION_DNS##
  User ##USER##
  ProxyCommand none
  IdentityFile ##SSH_KEY_PATH##

Host ##SEED_IP##
  User ##USER##
  IdentityFile ##SSH_KEY_PATH##
  ProxyCommand ssh -F ssh_config bastion -W %h:%p
