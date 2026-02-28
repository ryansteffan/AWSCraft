from datetime import datetime
import os
import shutil
import subprocess

from utils import Check_Command_Availability, Prompt_AWS_Login

BUILD_DIR = "./build"
SERVER_DIR = "./server"
LAMBDA_DIR = "./src/lambda"
WEBSITE_DIR = "./src/website"
TERRAFORM_DIR = "./terraform"
TERRAFORM_PLAN_NAME = "terraform.tfplan"
# NOTE: Ensure that the BACKUP_DIR is changed in the ./destroy.py file as well
BACKUP_DIR = "./backup"

def main():
    print("Running preliminary checks and setup...")

    # Ensure build and server directories exist
    if not os.path.exists(BUILD_DIR):
        print(f"Creating build directory at {BUILD_DIR}...")
        os.makedirs(BUILD_DIR)

    if not os.path.exists(SERVER_DIR):
        print(f"Creating server directory at {SERVER_DIR}...")
        os.makedirs(SERVER_DIR)
        with open(os.path.join(SERVER_DIR, "start-server.sh"), "w") as f:
            f.write("#!/bin/bash\n" +
            "echo 'This is a placeholder start script for your Minecraft server.'\n" +
            "echo 'Please replace this with your actual server start command.'\n" +
            "echo 'Example: java -Xmx1024M -Xms1024M -jar server.jar nogui'\n")
        
        with open(os.path.join(SERVER_DIR, "install-java.sh"), "w") as f:
            f.write("#!/bin/bash\n" +
            "echo 'This is a placeholder script for installing Java.'\n" +
            "echo 'Please replace this with your actual Java installation commands.'\n")

        with open(os.path.join(SERVER_DIR, "README.txt"), "w") as f:
            f.write("This directory is meant for your Minecraft server files.\n" +
            "Please place your server.jar and any other necessary files here.\n" +
            "The start-server.sh script is a placeholder and should be replaced with your actual server start command.\n" +
            "The install-java.sh script is a placeholder and should be replaced with your actual Java installation commands.\n" +
            "Make sure that the server is ready to run before deploying, as the deployment process will attempt to start the" +
            "server after deployment.\n")
        print(
            f"Please setup your server in {SERVER_DIR}.\n" +
            "Once done, re-run this script.")
        return
    
    # Check for terraform requirements
    if not os.path.exists(TERRAFORM_DIR):
        print("Terraform configuration not found. Please ensure terraform files are in place.")
        return
    
    # Ensure that the .tfvars file exists
    if not os.path.exists(os.path.join(TERRAFORM_DIR, ".tfvars")):
        print("Terraform variables file (.tfvars) not found." +
        f"\n One has been created from a template in the {TERRAFORM_DIR} directory.\n " +
        "Please edit it with your settings and re-run this script.")
        # Attempt to create .tfvars from example
        try:
            shutil.copyfile(
                os.path.join(TERRAFORM_DIR, "example.tfvars"),
                os.path.join(TERRAFORM_DIR, ".tfvars"))
        except Exception as e:
            print(f"Error creating .tfvars file: {e}")
        return
    
    # Ensure that the required commands are installed
    if not Check_Command_Availability():
        return

    print("Preliminary checks complete.")

    # Require AWS login
    if not Prompt_AWS_Login():
        return

    # Build all of the lambda functions
    print("Building lambda functions...")
    for lambda_function_path in os.listdir(LAMBDA_DIR):
        full_path = os.path.abspath(os.path.join(LAMBDA_DIR, lambda_function_path))
        print(f"Building lambda function at {full_path}...")
        try:
            BuildLambdaFunction(full_path)
        except subprocess.CalledProcessError as e:
            print(f"Error building lambda function at {full_path}: {e}")
            print("Aborting deployment process.")
            return 

    print("All lambda functions built successfully.")

    print("Building website...")
    try:
        BuildWebsite(os.path.abspath(WEBSITE_DIR))
    except subprocess.CalledProcessError as e:
        print(f"Error building website: {e}")
        print("Aborting deployment process.")
        return

    print("Building terraform plan...")

    print("Initializing terraform...")
    try:
        subprocess.run(["terraform", "init"], cwd=TERRAFORM_DIR, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error initializing terraform: {e}")
        print("Aborting deployment process.")
        return
    print("Planning terraform deployment...")
    try:
        subprocess.run(["terraform", "plan", "-var-file=.tfvars", f"-out={TERRAFORM_PLAN_NAME}"], 
                       cwd=TERRAFORM_DIR, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error planning terraform deployment: {e}")
        print("Aborting deployment process.")
        return
    print("Terraform plan built successfully.")

    do_deployment = input("Do you want to deploy now? (y/n): ")
    if do_deployment.lower() == 'y' or do_deployment.lower() == 'yes':
        print("Deploying with terraform...")
        try:
           subprocess.run(["terraform", "apply", "-var-file=.tfvars", TERRAFORM_PLAN_NAME], cwd=TERRAFORM_DIR, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error during terraform deployment: {e}")
            print("Aborting deployment process.")
            return
        print("Deployment complete.")
    else:
        print("Deployment canceled.")

    print("Do you wish to make a backup of your terraform files?")
    print("This is recommended as it will allow for easy deletion of resources later.")
    backup_choice = input("Make backup? (y/n): ")
    if backup_choice.lower() == 'y' or backup_choice.lower() == 'yes':
        if not os.path.exists(BACKUP_DIR):
            os.makedirs(BACKUP_DIR)
        backup_path = os.path.join(BACKUP_DIR, f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_terraform_backup")
        print(f"Creating backup at {backup_path}...")
        try:
            shutil.make_archive(backup_path, 'zip', TERRAFORM_DIR)
            print("Backup created successfully.")
        except Exception as e:
            print(f"Error creating backup: {e}")
    else:
        print("Backup skipped.")


def BuildLambdaFunction(path: str):
    # Cleanup the old build dir
    if os.path.exists(os.path.join(path, "dist")):
        shutil.rmtree(os.path.join(path, "dist"))

    # Runs npm commands with shell=True for Windows compatibility
    print("Installing npm dependencies...")
    subprocess.run(["npm", "install"], check=True, cwd=path, shell=True)

    print("Building the lambda function...")
    subprocess.run(["npm", "run", "build"], check=True, cwd=path, shell=True)


def BuildWebsite(path: str):
    # Cleanup the old build dir
    if os.path.exists(os.path.join(path, "out")):
        shutil.rmtree(os.path.join(path, "out"))

    # Runs npm commands with shell=True for Windows compatibility
    print("Installing npm dependencies for website...")
    subprocess.run(["npm", "install"], check=True, cwd=path, shell=True)

    print("Building the website...")
    subprocess.run(["npm", "run", "build"], check=True, cwd=path, shell=True)
    
    # Copy the website to the build dir for deployment
    if os.path.exists(os.path.join(BUILD_DIR, "website")):
        shutil.rmtree(os.path.join(BUILD_DIR, "website"))

    shutil.copytree(os.path.join(path, "out"), os.path.join(BUILD_DIR, "website"))
    print("Website built and copied to build directory successfully.")


if __name__ == "__main__":
    main()