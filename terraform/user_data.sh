#!/bin/bash 

# Update and install necessary packages
apt-get update -y
apt-get install -y unzip python3
snap install aws-cli --classic

# Pull the start script from S3
aws s3 cp s3://${s3_bucket}/scripts/start-server.sh /home/ubuntu/start-server.sh
chmod +x /home/ubuntu/start-server.sh

# Pull the stop script from S3
aws s3 cp s3://${s3_bucket}/scripts/stop-server.py /home/ubuntu/stop-server.py
chmod +x /home/ubuntu/stop-server.py

# Pull the start service from S3

# FAILS
sudo aws s3 cp s3://${s3_bucket}/${start_server_service} /etc/systemd/system/start-server.service
  
# Enable the services to run at startup
systemctl enable start-server.service
systemctl start start-server.service

# Download the Minecraft minecraft_server_profile from S3

# FAILS
sudo aws s3 cp s3://${s3_bucket}/${minecraft_server_profile} /opt/minecraft_server_profiles/

# Setup the minecraft_server_profile
unzip /opt/minecraft_server_profiles/${minecraft_server_profile} -d ${replace("/opt/minecraft_servers/${minecraft_server_profile}", ".zip", "")}

# Run the java install script
chmod +x /opt/minecraft_servers/${replace(minecraft_server_profile, ".zip", "")}/install_java.sh
bash /opt/minecraft_servers/${replace(minecraft_server_profile, ".zip", "")}/install_java.sh
