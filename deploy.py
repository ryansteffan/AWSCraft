from datetime import datetime
import os
import shutil
import subprocess
import zipfile

BUILD_DIR = "./build"
SERVER_DIR = "./server"
LAMBDA_DIR = "./src/lambda"
TERRAFORM_DIR = "./terraform"
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
    # Check for terraform
    try:
        subprocess.run(["terraform", "-version"], 
                       check=True, 
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except Exception as e:
        print("Terraform is not installed or not found in PATH." +
        " Please install Terraform to proceed.")
    # Check for npm
    try:
        # shell=True for Windows compatibility
        subprocess.run(["npm", "-v"], 
                       check=True, 
                       shell=True, 
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except Exception as e:
        print("npm is not installed or not found in PATH. " +
        "Please install npm to proceed.")
    # Check for AWS
    try:
        subprocess.run(["aws", "--version"], 
                       check=True,
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except Exception as e:
        print("AWS CLI is not installed or not found in PATH. " +
        "Please install AWS CLI to proceed.")

    print("Preliminary checks complete.")

    # Require AWS login
    print("Please login to your AWS account...")
    print("NOTE: It is recommended that you make a NON-ROOT user with appropriate " +
          "permissions for deploying resources.")
    print("Details can be found here: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html")
    print("------------------------------------")
    print("AWS Login Methods:")
    print("------------------------------------")
    print("1. AWS Login (Recommended & Default)")
    print("2. AWS Configure")
    print("3. AWS SSO Login (Coming Soon)")
    print("4. Other (Use your own method to login outside of this script)")
    print("------------------------------------")

    login_result = input("Please select a login method you wish to use (Default 1): ")
    match login_result:
        case "2":
            print("Running 'aws configure'...")
            try:
                subprocess.run(["aws", "configure"], check=True)
                print("AWS configured successfully.")
            except subprocess.CalledProcessError as e:
                print(f"Error during AWS configure: {e}")
                print("Aborting deployment process.")
                return
        case "3":
            print("AWS SSO Login is not yet implemented. Please use another method.")
            return
        case "4":
            print("Please use your preferred method to login to AWS outside of this script.")
            input("Press Enter once you have logged in to continue...")
        case _:
            print("Running 'aws login'...")
            try:
                subprocess.run(["aws", "login"], check=True)
                print("AWS login successful.")
            except subprocess.CalledProcessError as e:
                print(f"Error during AWS login: {e}")
                print("Aborting deployment process.")
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
        subprocess.run(["terraform", "plan", "-var-file=.tfvars"], cwd=TERRAFORM_DIR, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error planning terraform deployment: {e}")
        print("Aborting deployment process.")
        return
    print("Terraform plan built successfully.")

    do_deployment = input("Do you want to deploy now? (y/n): ")
    if do_deployment.lower() == 'y' or do_deployment.lower() == 'yes':
        print("Deploying with terraform...")
        try:
           subprocess.run(["terraform", "apply", "-var-file=.tfvars"], cwd=TERRAFORM_DIR, check=True)
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
        backup_path = os.path.join(BACKUP_DIR, f"{datetime.now()}_terraform_backup")
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


if __name__ == "__main__":
    main()