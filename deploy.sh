#! /bin/bash

# Make the build directory if it doesn't exist
mkdir -p build

# Build the AWS Lambda function code
cd src/lambda

cd ListInstancesFunction
npm install
npm run build
cd ../

cd ServerStatusFunction
npm install
npm run build
cd ../

cd StartServerFunction
npm install
npm run build
cd ../

cd ../../

# Return to the terraform directory
cd ./terraform/

# Create the terraform deployment plan
terraform plan -var-file="../.tfvars" -out="deployment.plan"

# Apply the terraform deployment plan
terraform apply "deployment.plan"

# Wait for user input before closing
read -p "Press [Enter] key to exit..."