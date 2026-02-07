# NOTE: This is an example for what files should be in the .tfvars file.
#       Copy this file to ".tfvars" and edit the values as needed.
#       Once you have setup your own tfvars file, it should not be deleted
#       as it has values required for destroying your infrastructure later.

# The AWS Region to deploy the infrastructure in. Select a region close to you to reduce latency.
# For a list of regions and their codes, see: 
# https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html
Region = "ca-central-1"

# The globally unique name for the S3 bucket used to store data used to deploy the infrastructure.
BucketName = "globally-unique-bucket-name"

# EC2 Instance type
# For a list of instance types, see: 
# https://instances.vantage.sh/
InstanceType = "m7i-flex.large"

