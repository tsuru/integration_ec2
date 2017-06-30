#!/bin/bash
cd /tmp
curl https://s3.amazonaws.com//aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
chmod +x ./awslogs-agent-setup.py

cat >./logs-config <<EOL
[general]
state_file = /var/awslogs/state/agent-state

[/var/log/syslog]
file = /var/log/syslog
log_group_name = tsuru-integration
log_stream_name = {instance_id}
datetime_format = %b %d %H:%M:%S
EOL

./awslogs-agent-setup.py -n -r us-east-1 -c ./logs-config
