#!/bin/bash 

# Update and install necessary packages
apt-get update -y
apt-get install -y unzip python3 python3-psutil
snap install aws-cli --classic

# Pull the start script from S3
aws s3 cp s3://${s3_bucket}/scripts/start-server.sh /home/ubuntu/start-server.sh
chmod +x /home/ubuntu/start-server.sh

# Pull the stop script from S3
aws s3 cp s3://${s3_bucket}/scripts/stop-server.py /home/ubuntu/stop-server.py
chmod +x /home/ubuntu/stop-server.py

# Pull the start service from S3
sudo aws s3 cp s3://${s3_bucket}/${start_server_service} /etc/systemd/system/start-server.service
  
# Enable the services to run at startup
systemctl enable start-server.service
systemctl start start-server.service

# Download the Minecraft minecraft_server_profile from S3
sudo aws s3 cp s3://${s3_bucket}/${minecraft_server_profile} /opt/minecraft_server_profiles/

sudo mkdir -p /opt/minecraft_servers

minecraft_server_profile_path="/opt/minecraft_server_profiles/${replace(minecraft_server_profile, "/profiles/", "")}"
extract_path="/opt/minecraft_servers/${replace(replace(minecraft_server_profile, "/profiles/", ""), ".zip", "")}"

echo "Extracting $minecraft_server_profile_path to $extract_path"

sudo unzip $minecraft_server_profile_path -d $extract_path

# Run the java install script
sudo chmod +x $extract_path/install-java.sh
sudo $extract_path/install-java.sh
