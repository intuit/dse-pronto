#!/bin/bash -ex

# Ensure our PATH is set correctly (on Amazon Linux, cfn-signal is in /opt/aws/bin)
. ~/.bash_profile

# Apply all available security updates
yum update -y --security

#############
## authorized_keys
#############

cat <<EOF > /usr/local/bin/sync_authorized_keys
#!/bin/bash -ex
TZ=America/Los_Angeles date
timeout 60 aws s3api get-object --region ${region} --bucket ${ssh_bucket} --key ${ssh_prefix} /tmp/user-keys.yaml
cat /tmp/user-keys.yaml | sed -n '/- name: ec2-user/,/- name:/p' | grep "ssh-rsa" | tr -s ' ' | cut -d ' ' -f3- > /home/ec2-user/.ssh/authorized_keys
EOF

chmod 744 /usr/local/bin/sync_authorized_keys
/usr/local/bin/sync_authorized_keys || true
cat <<EOF > /etc/cron.d/sync_authorized_keys
*/5 * * * * root /usr/local/bin/sync_authorized_keys >> /var/log/sync_authorized_keys.log 2>&1
EOF
