#!/bin/bash -vx

# Fix OpsCenter configs
sudo chmod -R a+rx /etc/opscenter/scripts
sudo chmod a+x /etc/opscenter/scripts/*.sh
sudo sed -i -r "s/#ssl/ssl/g" /etc/opscenter/opscenterd.conf

# If DSE studio is enabled, start it

if [[ "${studio_enabled}" = "1" ]] ; then
  echo "Setting DSE studio..."
  sudo sed -i -r "s/httpBindAddress: localhost/httpBindAddress: 0.0.0.0/g" /etc/datastax-studio/conf/configuration.yaml
  sudo chmod +x /etc/datastax-studio/bin/server.sh
  sudo /etc/datastax-studio/bin/server.sh &
else
  echo "DSE studio is not needed..."
fi

# Setup config to send email alerts from OpsCenter
if [[ "${alert_email_enabled}" = "1" ]] ; then
  sudo sed -i "s/enabled=.*/enabled=1/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/levels=.*/levels=${alert_levels}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/clusters=.*/clusters=${alert_clusters}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/smtp_host=.*/smtp_host=${alert_email_smtp_host}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/smtp_user=.*/smtp_user=${alert_email_smtp_user}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/smtp_pass=.*/smtp_pass=${alert_email_smtp_pass}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/from_addr=.*/from_addr=${alert_email_from_addr}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/to_addr=.*/to_addr=${alert_email_to_addr}/" /etc/opscenter/event-plugins/email.conf
  sudo sed -i "s/OpsCenter Event on/OpsCenter Event on ${alert_email_env}/" /etc/opscenter/event-plugins/email.conf

  sudo chmod 755 /etc/opscenter/event-plugins/email.conf
  sudo chown opscenter:opscenter /etc/opscenter/event-plugins/email.conf
else
  echo "Email alerts from opscenter are not needed..."
fi

# Run bootstrap script
cd /etc/opscenter/scripts/

./bootstrap.sh ${bucket} ${vpc_name} ${account_name} >> /var/log/bootstrap_opscenter.log 2>&1
