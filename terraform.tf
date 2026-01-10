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
  region = "ca-central-1"
}

# ----------------------------
# Setup IAM Roles and Policies
# ----------------------------

# Lambda Function Role
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

resource "aws_iam_role" "LambdaExecutionRole" {
  name = "LambdaExecutionRole"

  assume_role_policy = data.aws_iam_policy_document.LambdaAssumeRolePolicy.json

}

# ------------------------------------------
# Setup S3 Bucket for Minecraft Data Storage
# ------------------------------------------

# TODO: Add bucket policy to allow only EC2 access

resource "aws_s3_bucket" "MinecraftData" {
  bucket = "minecraft-data-bucket"
}

# Upload Minecraft server management scripts to S3
resource "aws_s3_object" "MinecraftStartScriptObject" {
  bucket = aws_s3_bucket.MinecraftData.name
  source = "src/ec2/scripts/start-server.sh"
  key    = "scripts/start-server.sh"
  etag   = filemd5("src/ec2/scripts/start-server.sh")
}

resource "aws_s3_object" "MinecraftStopScriptObject" {
  bucket = aws_s3_bucket.MinecraftData.name
  source = "src/ec2/scripts/stop-server.py"
  key    = "scripts/stop-server.py"
  etag   = filemd5("src/ec2/scripts/stop-server.py")
}

# Upload the Minecraft server services to S3
resource "aws_s3_object" "MinecraftStartServerServiceObject" {
  bucket = aws_s3_bucket.MinecraftData.name
  source = "src/ec2/services/start-minecraft.service"
  key    = "services/start-minecraft.service"
  etag   = filemd5("src/ec2/services/start-minecraft.service")
}

# Upload the minecraft server profile to S3
resource "aws_s3_object" "MinecraftServerProfileObject" {
  bucket = aws_s3_bucket.MinecraftData.name
  source = "minecraft_server_profile.zip"
  key    = "profiles/minecraft_server_profile.zip"
  etag   = filemd5("minecraft_server_profile.zip")
}

# ------------------------------------------------------
# Setup Lambda Functions for Minecraft Server Management
# ------------------------------------------------------
variable "LambdaEnv" {
  type = map(string)
  default = {
  }
}

data "archive_file" "ListInstancesFunctionCode" {
  type        = "zip"
  source_file = "src/lambda/ListInstancesFunction/build/index.js"
  output_path = "lambda_functions/list_instances.zip"
}

data "archive_file" "ServerStatusFunctionCode" {
  type        = "zip"
  source_file = "src/lambda/ServerStatusFunction/build/index.js"
  output_path = "lambda_functions/server_status.zip"
}

data "archive_file" "StartServerFunctionCode" {
  type        = "zip"
  source_file = "src/lambda/StartServerFunction/build/index.js"
  output_path = "lambda_functions/start_server.zip"
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

resource "aws_apigatewayv2_route" "ListInstancesEndpoint" {
  api_id    = aws_apigatewayv2_api.MinecraftAPI.id
  route_key = "/list-instances"
}

resource "aws_apigatewayv2_route" "ServerStatusEndpoint" {
  api_id    = aws_apigatewayv2_api.MinecraftAPI.id
  route_key = "/status"
}

resource "aws_apigatewayv2_route" "StartServerEndpoint" {
  api_id    = aws_apigatewayv2_api.MinecraftAPI.id
  route_key = "/start"
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

# --------------------------------------------
# Setup instance for running Minecraft servers
# --------------------------------------------

# Get the Ubuntu 24.04 AMI
# data "aws_ami" "Ubuntu2404AMI" {
#   most_recent = true

#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }

#   owners = ["099720109477"]
# }

# variable "MinecraftEC2InstanceUserData" {
#   type    = string
#   default = <<-EOF
#                 #!/bin/bash

#                 # Update and install necessary packages
#                 apt-get update -y
#                 apt-get install -y awscli unzip python3

#                 # Pull the start script from S3
#                 aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/scripts/start-server.sh /home/ubuntu/start-server.sh
#                 chmod +x /home/ubuntu/start-server.sh

#                 # Pull the stop script from S3
#                 aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/scripts/stop-server.py /home/ubuntu/stop-server.py
#                 chmod +x /home/ubuntu/stop-server.py

#                 # Pull the start service from S3
#                 aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/services/${aws_s3_object.MinecraftStartServerServiceObject.key} /etc/systemd/system/start-server.service

#                 # Enable the services to run at startup
#                 systemctl enable start-server.service

#                 # Download the Minecraft Profile from S3
#                 aws s3 cp s3://${aws_s3_bucket.MinecraftData.bucket}/profiles/${aws_s3_object.MinecraftServerProfileObject.key} /opt/minecraft_server_profiles/

#                 # Setup the profile
#                 unzip /opt/minecraft_server_profiles/${aws_s3_object.MinecraftServerProfileObject.key} \ 
#                 -d ${replace("/opt/minecraft_servers/${aws_s3_object.MinecraftServerProfileObject.key}", ".zip", "")}

#                 # Run the java install script
#                 chmod +x /opt/minecraft_servers/${replace(aws_s3_object.MinecraftServerProfileObject.key, ".zip", "")}/install_java.sh
#                 bash /opt/minecraft_servers/${replace(aws_s3_object.MinecraftServerProfileObject.key, ".zip", "")}/install_java.sh

#                 EOF
# }


# resource "aws_instance" "MinecraftEC2Instance" {
#   instance_type = "t4g.large"
#   ami           = data.aws_ami.Ubuntu2404AMI.id
#   user_data     = var.MinecraftEC2InstanceUserData.default


#   tags = {
#     IsMinecraftInstance = "true"
#   }
# }
