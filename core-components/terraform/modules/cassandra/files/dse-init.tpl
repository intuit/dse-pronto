#!/bin/bash -vx

AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# stop services

systemctl stop dse
systemctl stop datastax-agent

agent_pid=$(ps -ef | grep -i "[d]atastax-agent" | awk '{print $2}')
kill -9 $agent_pid

echo "Beginning preparation of cassandra directories"

chown -R cassandra:cassandra /var/run/dse
chown -R cassandra:cassandra /var/run/datastax-agent

# fix configs

sed -i "s/rack=.*/rack=$AZ/" /etc/dse/cassandra/cassandra-rackdc.properties
sed -i "s/dc=.*/dc=${dc_name}/" /etc/dse/cassandra/cassandra-rackdc.properties

sed -i "s/GRAPH_ENABLED=.*/GRAPH_ENABLED=${graph_enabled}/" /etc/default/dse
sed -i "s/SOLR_ENABLED=.*/SOLR_ENABLED=${solr_enabled}/" /etc/default/dse
sed -i "s/SPARK_ENABLED=.*/SPARK_ENABLED=${spark_enabled}/" /etc/default/dse

sed -i 's@\*/10@*/1@' /etc/cron.d/sysstat
echo "Modified /etc/cron.d/sysstat to gather metrics every minute"

# run bootstrap script

echo "auto_start_dse = ${auto_start_dse}" > /var/log/bootstrap_cassandra.log 2>&1
echo "graph_enabled = ${graph_enabled}" >> /var/log/bootstrap_cassandra.log 2>&1
echo "solr_enabled = ${solr_enabled}" >> /var/log/bootstrap_cassandra.log 2>&1
echo "spark_enabled = ${spark_enabled}" >> /var/log/bootstrap_cassandra.log 2>&1

chmod +x /opt/dse/cassandra/scripts
/opt/dse/cassandra/scripts/bootstrap.sh ${auto_start_dse} >> /var/log/bootstrap_cassandra.log 2>&1

#############
## reasonable block device settings for SSD (post-mount)
#############

for dev in $(ls /sys/block); do
  echo 4 > /sys/block/$dev/queue/read_ahead_kb
  echo 1 > /sys/block/$dev/queue/nomerges
  #echo deadline > /sys/block/$dev/queue/scheduler
done

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

# set the ansible user's passwd to not expire
chage -I -1 -m 0 -M 99999 -E -1 ansible

###################################
# Tag root volume with tags
###################################
instance_id=`curl http://169.254.169.254/latest/meta-data/instance-id/`
volume_id=`aws ec2 describe-instances --instance-id $instance_id --query "Reservations[].Instances[].BlockDeviceMappings[0].{VolumeID: Ebs.VolumeId}" --region ${region} | jq -r '.[0] | .VolumeID'`
tags=""
tag_keys=$(echo '${ec2_tag_map}' |  jq -r '.|keys | .[]')
for k in $tag_keys; do 
  echo "$k = $(echo '${ec2_tag_map}' |  jq -r --arg k "$k" '.[$k]')"
  tags="$tags Key=$k,Value=$(echo '${ec2_tag_map}' |  jq -r --arg k "$k" '.[$k]')"
done
aws ec2 create-tags --region ${region} --resources $volume_id --tags $tags

