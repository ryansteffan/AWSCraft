#! /bin/bash

# Source the environment variables from the user_data.sh script
env_vars_file="/opt/minecraft/env-vars.sh"
if [ -f "$env_vars_file" ]; then
    source "$env_vars_file"
else
    echo "Environment variables file not found: $env_vars_file"
    exit 1
fi

if [ ! -f "$START_SCRIPT" ]; then
	echo "$START_SCRIPT not found. Cannot start the Minecraft server."
	exit 1
fi

# Start file also requires path to jar
"$START_SCRIPT" "$SERVER_JAR" &
export SERVER_PID=$!
export IMS_TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
export INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $IMS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

python3 "$STOP_SCRIPT"