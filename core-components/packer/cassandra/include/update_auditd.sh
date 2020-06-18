#!/bin/bash
file=/etc/audit/auditd.conf
cp "$file" "$file.bak"
sed -i -r "s/num_logs = .*/num_logs = 5/g" $file
sed -i -r "s/max_log_file = .*/max_log_file = 100/g" $file
sed -i -r "s/max_log_file_action = .*/max_log_file_action = rotate/g" $file
sed -i -r "s/space_left = .*/space_left = 2048/g" $file
sed -i -r "s/space_left_action = .*/space_left_action = syslog/g" $file
sed -i -r "s/action_mail_acct = .*/action_mail_acct = root/g" $file
sed -i -r "s/admin_space_left = .*/admin_space_left = 1024/g" $file
sed -i -r "s/admin_space_left_action = .*/admin_space_left_action = SUSPEND/g" $file
