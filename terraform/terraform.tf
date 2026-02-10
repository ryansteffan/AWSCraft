#-------------------------------------
# Terraform Configuration for AWSCraft
#-------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.27.0"
    }
  }
}

provider "aws" {
  # Set the AWS region to deploy resources in.
  region = var.Region
}

# --------- 
# Variables  
# ---------
variable "BucketName" {
  type        = string
  description = "A globally unique name for your aws bucket."
}

variable "MinecraftServerName" {
  type        = string
  description = "The name to assign to the minecraft server instance."
}

variable "MinecraftServerDescription" {
  type        = string
  description = "A description to assign to the minecraft server instance."
}

variable "MinecraftServerPort" {
  type        = number
  description = "The port that the Minecraft server will run on."
}

variable "Region" {
  type        = string
  description = "The AWS region to deploy the infrastructure in."
}

variable "AvailabilityZone" {
  type        = string
  description = "The availability zone to deploy the EC2 instance and EBS volume in."
}

variable "InstanceType" {
  type        = string
  description = "The EC2 instance type to use for the Minecraft server."
}

variable "Architecture" {
  type        = string
  description = "The architecture of the AMI to use for the Minecraft server."
}

variable "EBSSize" {
  type        = number
  description = "The size of the EBS volume attached to the EC2 instance in GB."
}

# ----------------------------------------------------
# Create a VPC for the Minecraft server infrastructure
# ----------------------------------------------------
resource "aws_vpc" "MinecraftVPC" {
  cidr_block = "10.0.0.0/16"

  # Enable DNS support and hostnames for the VPC
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    "Name" : "MinecraftVPC"
  }
}

# Create a public subnet for the minecraft server
resource "aws_subnet" "MinecraftPublicSubnet" {
  vpc_id            = aws_vpc.MinecraftVPC.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.Region}${var.AvailabilityZone}"

  tags = {
    "Name" : "MinecraftPublicSubnet"
  }
}

# Create a private subnet for resources that need to be private
resource "aws_subnet" "MinecraftPrivateSubnet" {
  vpc_id            = aws_vpc.MinecraftVPC.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.Region}${var.AvailabilityZone}"

  tags = {
    "Name" : "MinecraftPrivateSubnet"
  }
}

# Create an internet gateway for the public subnet
resource "aws_internet_gateway" "MinecraftInternetGateway" {
  vpc_id = aws_vpc.MinecraftVPC.id

  tags = {
    "Name" : "MinecraftInternetGateway"
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "MinecraftPublicSubnetRouteTable" {
  vpc_id = aws_vpc.MinecraftVPC.id

  # Route to the internet for all traffic to leave the VPC from the public subnet
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.MinecraftInternetGateway.id
  }

  # Allow for communication between the public and private subnets
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    "Name" : "MinecraftPublicSubnetRouteTable"
  }
}

# Create a route table for the private subnet
resource "aws_route_table" "MinecraftPrivateSubnetRouteTable" {
  vpc_id = aws_vpc.MinecraftVPC.id

  # Allow for communication between the public and private subnets
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    "Name" : "MinecraftPrivateSubnetRouteTable"
  }
}

# Associate the route tables with the subnets
resource "aws_route_table_association" "MinecraftPrivateSubnetRouteTableAssociation" {
  subnet_id      = aws_subnet.MinecraftPrivateSubnet.id
  route_table_id = aws_route_table.MinecraftPrivateSubnetRouteTable.id
}

resource "aws_route_table_association" "MinecraftPublicSubnetRouteTableAssociation" {
  subnet_id      = aws_subnet.MinecraftPublicSubnet.id
  route_table_id = aws_route_table.MinecraftPublicSubnetRouteTable.id
}

# ----------------------------------
# Setup logging for lambda functions
# ----------------------------------
resource "aws_cloudwatch_log_group" "MinecraftLambdaLogGroup" {
  name              = "/aws/lambda/MinecraftLambdaFunctions"
  retention_in_days = 14
}

# ----------------------------
# Setup IAM Roles and Policies
# ----------------------------

# Basic Lambda execution role
data "aws_iam_policy_document" "LambdaAssumeRolePolicy" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com"
      ]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Policy document for logging from Lambda to CloudWatch
data "aws_iam_policy_document" "LambdaLogPolicyDocument" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

# Create the IAM role for Lambda to have access to EC2
data "aws_iam_policy_document" "LambdaEC2AccessPolicyDocument" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
    ]

    resources = ["*"]
  }
}

# Attach the basic policy and make the role
resource "aws_iam_role" "LambdaExecutionRole" {
  name = "LambdaExecutionRole"

  assume_role_policy = data.aws_iam_policy_document.LambdaAssumeRolePolicy.json
}

# Attach the logging and EC2 access policies to the role
resource "aws_iam_role_policy" "LambdaExecutionRolePolicy" {
  name   = "LambdaExecutionRolePolicy"
  role   = aws_iam_role.LambdaExecutionRole.id
  policy = data.aws_iam_policy_document.LambdaLogPolicyDocument.json
}
resource "aws_iam_role_policy" "LambdaEC2AccessRolePolicy" {
  name   = "LambdaEC2AccessRolePolicy"
  role   = aws_iam_role.LambdaExecutionRole.id
  policy = data.aws_iam_policy_document.LambdaEC2AccessPolicyDocument.json
}

# Create the assume role policy for EC2 to allow it to assume the role and access S3
data "aws_iam_policy_document" "EC2AssumeRolePolicy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Create the policy document for EC2 to have access to S3
data "aws_iam_policy_document" "MinecraftEC2S3AccessPolicyDocument" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject"
    ]

    resources = [aws_s3_bucket.MinecraftData.arn, "${aws_s3_bucket.MinecraftData.arn}/*"]
  }
}

# Create the IAM role for EC2 to have access to S3
resource "aws_iam_role" "MinecraftEC2Role" {
  name               = "MinecraftEC2Role"
  assume_role_policy = data.aws_iam_policy_document.EC2AssumeRolePolicy.json
}

# Attach the S3 access policy to the EC2 role
resource "aws_iam_role_policy" "MinecraftEC2S3AccessRolePolicy" {
  name   = "MinecraftEC2S3AccessRolePolicy"
  role   = aws_iam_role.MinecraftEC2Role.id
  policy = data.aws_iam_policy_document.MinecraftEC2S3AccessPolicyDocument.json
}

# ------------------------------------------
# Setup S3 Bucket for Minecraft Data Storage
# ------------------------------------------

# TODO: Add bucket policy to allow only EC2 access

resource "aws_s3_bucket" "MinecraftData" {
  bucket = var.BucketName
}

# Upload Minecraft server management scripts to S3
resource "aws_s3_object" "MinecraftStartScriptObject" {
  bucket = aws_s3_bucket.MinecraftData.id
  source = "../src/ec2/scripts/start-server.sh"
  key    = "scripts/start-server.sh"
  etag   = filemd5("../src/ec2/scripts/start-server.sh")
}

resource "aws_s3_object" "MinecraftStopScriptObject" {
  bucket = aws_s3_bucket.MinecraftData.id
  source = "../src/ec2/scripts/stop-server.py"
  key    = "scripts/stop-server.py"
  etag   = filemd5("../src/ec2/scripts/stop-server.py")
}

# Upload the Minecraft server services to S3
resource "aws_s3_object" "MinecraftStartServerServiceObject" {
  bucket = aws_s3_bucket.MinecraftData.id
  source = "../src/ec2/services/start-minecraft.service"
  key    = "services/start-minecraft.service"
  etag   = filemd5("../src/ec2/services/start-minecraft.service")
}

# Zip the server profile and upload to S3
data "archive_file" "MinecraftServerProfileArchive" {
  type        = "zip"
  source_dir  = "../server"
  output_path = "../build/minecraft_server_profiles/DefaultMinecraftProfile.zip"
}

resource "aws_s3_object" "MinecraftServerProfile" {
  bucket = aws_s3_bucket.MinecraftData.id
  source = data.archive_file.MinecraftServerProfileArchive.output_path
  key    = "profiles/DefaultMinecraftProfile.zip"
  etag   = filemd5(data.archive_file.MinecraftServerProfileArchive.output_path)
}

# ------------------------------------------------------
# Setup Lambda Functions for Minecraft Server Management
# ------------------------------------------------------
variable "LambdaEnv" {
  type = map(string)
  default = {
    # AWS_REGION = "ca-central-1"
  }
}

data "archive_file" "ListInstancesFunctionCode" {
  type        = "zip"
  source_dir  = "../src/lambda/ListInstancesFunction/dist"
  output_path = "../build/lambda_functions/list_instances.zip"
}

data "archive_file" "ServerStatusFunctionCode" {
  type        = "zip"
  source_dir  = "../src/lambda/ServerStatusFunction/dist"
  output_path = "../build/lambda_functions/server_status.zip"
}

data "archive_file" "StartServerFunctionCode" {
  type        = "zip"
  source_dir  = "../src/lambda/StartServerFunction/dist"
  output_path = "../build/lambda_functions/start_server.zip"
}

resource "aws_lambda_function" "ListInstancesFunction" {
  function_name = "ListInstancesFunction"
  role          = aws_iam_role.LambdaExecutionRole.arn
  handler       = "index.handler"
  runtime       = "nodejs24.x"

  filename         = data.archive_file.ListInstancesFunctionCode.output_path
  source_code_hash = data.archive_file.ListInstancesFunctionCode.output_base64sha256

  environment {
    variables = var.LambdaEnv
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.MinecraftLambdaLogGroup.name
  }

  depends_on = [aws_iam_role.LambdaExecutionRole, aws_cloudwatch_log_group.MinecraftLambdaLogGroup]
}

resource "aws_lambda_function" "ServerStatusFunction" {
  function_name = "ServerStatusFunction"
  role          = aws_iam_role.LambdaExecutionRole.arn
  handler       = "index.handler"
  runtime       = "nodejs24.x"

  filename         = data.archive_file.ServerStatusFunctionCode.output_path
  source_code_hash = data.archive_file.ServerStatusFunctionCode.output_base64sha256

  environment {
    variables = var.LambdaEnv
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.MinecraftLambdaLogGroup.name
  }

  depends_on = [aws_iam_role.LambdaExecutionRole, aws_cloudwatch_log_group.MinecraftLambdaLogGroup]
}

resource "aws_lambda_function" "StartServerFunction" {
  function_name = "StartServerFunction"
  role          = aws_iam_role.LambdaExecutionRole.arn
  handler       = "index.handler"
  runtime       = "nodejs24.x"

  filename         = data.archive_file.StartServerFunctionCode.output_path
  source_code_hash = data.archive_file.StartServerFunctionCode.output_base64sha256

  environment {
    variables = var.LambdaEnv
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.MinecraftLambdaLogGroup.name
  }

  depends_on = [aws_iam_role.LambdaExecutionRole, aws_cloudwatch_log_group.MinecraftLambdaLogGroup]
}

# -------------------------------------------------
# Setup API Gateway for Minecraft Server Management
# -------------------------------------------------

# Set up the domain name for the API Gateway

# Create the api routes
resource "aws_apigatewayv2_api" "MinecraftAPI" {
  name          = "MinecraftAPI"
  description   = "The api gateway to handle requests for the Minecraft server"
  protocol_type = "HTTP"
}

# Attache the routes to lambda functions
resource "aws_apigatewayv2_integration" "ListInstancesIntegration" {
  api_id             = aws_apigatewayv2_api.MinecraftAPI.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ListInstancesFunction.arn
  integration_method = "GET"
}

resource "aws_apigatewayv2_integration" "ServerStatusIntegration" {
  api_id             = aws_apigatewayv2_api.MinecraftAPI.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ServerStatusFunction.arn
  integration_method = "GET"
}

resource "aws_apigatewayv2_integration" "StartServerIntegration" {
  api_id             = aws_apigatewayv2_api.MinecraftAPI.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.StartServerFunction.arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "ListInstancesEndpoint" {
  api_id    = aws_apigatewayv2_api.MinecraftAPI.id
  route_key = "GET /list-instances"

  target = "integrations/${aws_apigatewayv2_integration.ListInstancesIntegration.id}"
}

resource "aws_apigatewayv2_route" "ServerStatusEndpoint" {
  api_id    = aws_apigatewayv2_api.MinecraftAPI.id
  route_key = "GET /status"

  target = "integrations/${aws_apigatewayv2_integration.ServerStatusIntegration.id}"
}

resource "aws_apigatewayv2_route" "StartServerEndpoint" {
  api_id    = aws_apigatewayv2_api.MinecraftAPI.id
  route_key = "POST /start"

  target = "integrations/${aws_apigatewayv2_integration.StartServerIntegration.id}"
}

resource "aws_apigatewayv2_stage" "MinecraftAPIProductionStage" {
  name        = "MinecraftAPIProd"
  api_id      = aws_apigatewayv2_api.MinecraftAPI.id
  auto_deploy = true
}

resource "aws_lambda_permission" "AllowApiGatewayInvokeListInstances" {
  statement_id  = "AllowExecutionFromApiGatewayListInstances"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ListInstancesFunction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.MinecraftAPI.execution_arn}/*/*"
}

resource "aws_lambda_permission" "AllowApiGatewayInvokeServerStatus" {
  statement_id  = "AllowExecutionFromApiGatewayServerStatus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ServerStatusFunction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.MinecraftAPI.execution_arn}/*/*"
}

resource "aws_lambda_permission" "AllowApiGatewayInvokeStartServer" {
  statement_id  = "AllowExecutionFromApiGatewayStartServer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.StartServerFunction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.MinecraftAPI.execution_arn}/*/*"
}

# --------------------------------------------
# Setup instance for running Minecraft servers
# --------------------------------------------

# Get the Ubuntu 24.04 AMI for Arm
data "aws_ami" "Ubuntu2404AMI" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.Architecture}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

# Create a security group for the Minecraft server instance
resource "aws_security_group" "MinecraftServerSecurityGroup" {
  name        = "MinecraftServerSecurityGroup"
  description = "Security group for the Minecraft server instance"
  vpc_id      = aws_vpc.MinecraftVPC.id

  tags = {
    "Name" : "MinecraftServerSecurityGroup"
  }
}

# Create the rules for the security group
resource "aws_vpc_security_group_ingress_rule" "AllowMinecraftServerIngress" {
  security_group_id = aws_security_group.MinecraftServerSecurityGroup.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.MinecraftServerPort
  to_port           = var.MinecraftServerPort
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "MinecraftServerSSHIngress" {
  security_group_id = aws_security_group.MinecraftServerSecurityGroup.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "AllowMinecraftAllDataEgress" {
  security_group_id = aws_security_group.MinecraftServerSecurityGroup.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_instance_profile" "MinecraftEC2InstanceIAMProfile" {
  name = "MinecraftEC2InstanceIAMProfile"
  role = aws_iam_role.MinecraftEC2Role.name
}

# Create ssh keys for the EC2 instance
resource "aws_key_pair" "MinecraftEC2KeyPair" {
  public_key = file("../ssh/minecraft_key.pub")

  tags = {
    "Name" = "MinecraftServerKeyPair"
  }
}

# Create the EC2 instance for the Minecraft server
resource "aws_instance" "MinecraftServerInstance" {
  ami                  = data.aws_ami.Ubuntu2404AMI.id
  instance_type        = var.InstanceType
  availability_zone    = "${var.Region}${var.AvailabilityZone}"
  iam_instance_profile = aws_iam_instance_profile.MinecraftEC2InstanceIAMProfile.name
  key_name             = aws_key_pair.MinecraftEC2KeyPair.key_name

  root_block_device {
    volume_size           = var.EBSSize
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      "Name" : "${var.MinecraftServerName}-RootVolume"
    }
  }

  # Setup the the network interface for the instance
  subnet_id                   = aws_subnet.MinecraftPublicSubnet.id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.MinecraftServerSecurityGroup.id]

  user_data = templatefile(
    "user_data.sh",
    {
      s3_bucket                = aws_s3_bucket.MinecraftData.bucket,
      start_server_service     = aws_s3_object.MinecraftStartServerServiceObject.key,
      minecraft_server_profile = aws_s3_object.MinecraftServerProfile.key,
    }
  )

  tags = {
    # Used to identify instances that are part of the Minecraft server infrastructure
    "IsMinecraftServer" = "true",
    "Name"              = var.MinecraftServerName,
    "Description"       = var.MinecraftServerDescription
  }
}
