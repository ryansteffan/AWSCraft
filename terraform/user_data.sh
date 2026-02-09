#!/bin/bash 

# Update and install necessary packages
apt-get update -y
apt-get install -y awscli unzip python3

# Pull the start script from S3
aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/scripts/start-server.sh /home/ubuntu/start-server.sh
chmod +x /home/ubuntu/start-server.sh

# Pull the stop script from S3
aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/scripts/stop-server.py /home/ubuntu/stop-server.py
chmod +x /home/ubuntu/stop-server.py

# Pull the start service from S3
aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/services/${aws_s3_object.MinecraftStartServerServiceObject.key} /etc/systemd/system/start-server.service
  
# Enable the services to run at startup
systemctl enable start-server.service

# Download the Minecraft Profile from S3
aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/profiles/${aws_s3_object.MinecraftServerProfileObject.key} /opt/minecraft_server_profiles/

# Setup the profile
unzip /opt/minecraft_server_profiles/${aws_s3_object.MinecraftServerProfileObject.key} -d ${replace("/opt/minecraft_servers/${aws_s3_object.MinecraftServerProfileObject.key}", ".zip", "")}

# Run the java install script
chmod +x /opt/minecraft_servers/${replace(aws_s3_object.MinecraftServerProfileObject.key, ".zip", "")}/install_java.sh
bash /opt/minecraft_servers/${replace(aws_s3_object.MinecraftServerProfileObject.key, ".zip", "")}/install_java.sh
