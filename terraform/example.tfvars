# NOTE: This is an example for what files should be in the .tfvars file.
#       Copy this file to ".tfvars" and edit the values as needed.
#       Once you have setup your own tfvars file, it should not be deleted
#       as it has values required for destroying your infrastructure later.

# The AWS Region to deploy the infrastructure in. Select a region close to you to reduce latency.
# For a list of regions and their codes, see: 
# https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html
Region = "ca-central-1"

# The globally unique name for the S3 bucket used to store data used to deploy the infrastructure.
BucketName = "my-awscraft-bucket"

# EC2 Instance type
# For a list of instance types, see: 
# https://instances.vantage.sh/
InstanceType = "m7i-flex.large"

# The architecture of the EC2 instance. This is used to select the correct AMI for the instance.
# It is important that this matches the architecture of the InstanceType you are using.
# If it is not correct, an invalid AMI will be selected and the EC2 instance will fail to launch.
Architecture = "amd64"

# The availability zone to deploy the EC2 instance in.
# Generally valid values are "a", "b", "c", etc. depending on the region you are deploying in.
AvailabilityZone = "a"

# The amount of storage (in GB) to allocate for the EBS volume attached to the EC2 instance. 
# This is used to store the Minecraft server data.
EBSSize = 15

# The name, description, and port for the Minecraft server. 
# These values are what the server will be described as when the API is used to 
# query the server information.
MinecraftServerName        = "My Minecraft Server"
MinecraftServerDescription = "A Minecraft server deployed on AWS using AWSCraft."

# The port to open for the minecraft server to allow players to connect through the firewall.
# This must be the same as what you have configured in the server.properties file for your Minecraft server.
MinecraftServerPort = 25565

# Enable support for API authentication using AWS Cognito.
# When this is set to true, a Cognito User Pool will be created to manage users who have access to the Minecraft server, and the API Gateway will be configured to use this user pool for authentication.
# When false the API will be treated as public and allow for anyone to call it.
EnableAuth = true

# The email address to use for the default admin user in the Cognito User Pool. 
# This user will be added to the admin group and can be used to log in and manage the server through the API.
AdminEmailAddress = "example@example.com"

# The temporary password for the default admin user in the Cognito User Pool. 
# This should be changed immediately after the first login to ensure the security of the admin account.
AdminPassword = "examplePassword123!"

EnableWebUI = true

WebUIBucketName = "my-awscraft-webui-bucket"
