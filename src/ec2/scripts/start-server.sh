#! /bin/bash
/opt/minecraft_servers/{SERVER_PROFILE_DIR}/start-server.sh &
export SERVER_PID=$!
export IMS_TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300"`
export INSTANCE_ID=`curl -H "X-aws-ec2-metadata-token: $IMS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id`

python3 /opt/minecraft_servers/scripts/stop-server.py