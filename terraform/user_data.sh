#! /bin/sh

# Update and install necessary packages
apt-get update -y
apt-get install -y unzip python3 python3-psutil dos2unix
snap install aws-cli --classic

# Define variables
s3_bucket=${s3_bucket}
minecraft_dir="/opt/minecraft"
minecraft_profiles_dir="$minecraft_dir/profiles"
minecraft_servers_dir="$minecraft_dir/servers"
minecraft_scripts_dir="$minecraft_dir/scripts"
default_profile_name="DefaultMinecraftProfile"
bootstrap_start_script="$minecraft_scripts_dir/start-server.sh"
stop_script="$minecraft_scripts_dir/stop-server.py"
username="minecraft"

# Create the required directories
sudo mkdir -p $minecraft_dir
sudo mkdir -p $minecraft_profiles_dir
sudo mkdir -p $minecraft_servers_dir
sudo mkdir -p $minecraft_scripts_dir

# Create a user for running the Minecraft server
sudo groupadd -r $username
sudo useradd -r -d $minecraft_dir -g $username -s /bin/bash $username

# Lock the user account
# sudo usermod -L $username

# Pull the Minecraft server profile from S3
sudo aws s3 cp "s3://$s3_bucket/profiles/$default_profile_name.zip" "$minecraft_profiles_dir/$default_profile_name.zip"

# Pull the start script from S3
sudo aws s3 cp s3://$s3_bucket/scripts/start-server.sh $bootstrap_start_script
sudo chmod 755 $bootstrap_start_script

# Pull the stop script from S3
sudo aws s3 cp s3://$s3_bucket/scripts/stop-server.py $stop_script
sudo chmod 755 $stop_script

# Unzip the Minecraft server profile
minecraft_server_profile_path="$minecraft_profiles_dir/$default_profile_name.zip"
extract_path="$minecraft_servers_dir/$default_profile_name"
sudo unzip $minecraft_server_profile_path -d $extract_path
server_start_script="$extract_path/start-server.sh"
sudo chmod 755 $server_start_script

# Run the java install script
sudo chmod +x $extract_path/install-java.sh
sudo $extract_path/install-java.sh

# Dump the variables to a file for use in the start script
echo "
#! /bin/bash
export S3_BUCKET=$s3_bucket
export MINECRAFT_DIR=$minecraft_dir
export MINECRAFT_PROFILES_DIR=$minecraft_profiles_dir
export MINECRAFT_SERVERS_DIR=$minecraft_servers_dir
export MINECRAFT_SCRIPTS_DIR=$minecraft_scripts_dir
export DEFAULT_PROFILE_NAME=$default_profile_name
export START_SCRIPT=$server_start_script
export STOP_SCRIPT=$stop_script
export SERVER_JAR=$extract_path/server.jar
" > $minecraft_dir/env-vars.sh

# Set permissions for the Minecraft user
sudo chown -R $username:$username $minecraft_dir
sudo chmod -R 755 $minecraft_dir

# Pull the start service from S3
sudo aws s3 cp s3://$s3_bucket/services/start-minecraft.service /etc/systemd/system/start-minecraft.service

# Enable the services to run at startup
sudo systemctl enable start-minecraft.service
sudo systemctl start start-minecraft.service