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

# --------- 
# Variables  
# ---------
variable "BucketName" {
  type        = string
  description = "A globally unique name for your aws bucket."
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

# Zip the minecraft server profile
resource "archive_file" "MinecraftServerProfileZip" {
  type        = "zip"
  source_dir  = "../minecraft_server_profile"
  output_path = "../build/minecraft_server_profile.zip"
}

# Upload the minecraft server profile to S3
resource "aws_s3_object" "MinecraftServerProfileObject" {
  bucket = aws_s3_bucket.MinecraftData.id
  source = archive_file.MinecraftServerProfileZip.output_path
  key    = "profiles/minecraft_server_profile.zip"
  etag   = filemd5(archive_file.MinecraftServerProfileZip.output_path)
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
