import random
import subprocess
import os
import shutil
import tempfile

from utils import Check_Command_Availability, Prompt_AWS_Login

TERRAFORM_DIR = "./terraform"
TERRAFORM_PLAN_FILE = "terraform.tfplan"
TF_VARS_FILE = ".tfvars"


def main():
    print("Starting AWSCraft Terraform Destroy Process...")

    print("Running preliminary checks...")
    if not Check_Command_Availability():
        return
    
    if not Prompt_AWS_Login():
        return
    print("Preliminary checks complete.")

    do_minecraft_backup = None
    while do_minecraft_backup not in ["y", "yes", "n", "no"]:
        do_minecraft_backup = input("WARNING: If you do not backup the data before destruction, " \
        "ALL DATA WILL BE LOST PERMANENTLY. Do you wish to backup your Minecraft server data " \
        "before destruction? (Y/n): ").lower()
        if do_minecraft_backup in ["y", "yes"]:
            ...
        elif do_minecraft_backup in ["n", "no"]:
            print("Proceeding without backup. All data will be lost permanently.") 
        

    print("-------------------------------------------")
    print("Please select a method of destruction:")
    print("-------------------------------------------")
    print("1. Use existing ./terraform state and vars")
    print("2. Use a backup terraform_backup.zip")
    print("-------------------------------------------")
    destruction_method = None
    while destruction_method not in ["1", "2"]:
        destruction_method = input("Select destruction method: ")
        match destruction_method:
            case "1": 
                print("Using ./terraform state and vars for destruction.")
                Run_Terraform_Destroy(TERRAFORM_DIR)
            case "2":
                backup_path = Restore_Terraform_From_Backup()
                Run_Terraform_Destroy(backup_path)

    print("Destruction process completed.")
    print("please review your AWS account to ensure all resources have been deleted.")


def Run_Terraform_Destroy(terraform_dir: str):
    final_warn_msg = "FINAL WARNING: This will permanently destroy all AWS resources created by this project. "
    print("-" * len(final_warn_msg))
    print(final_warn_msg)
    print("-" * len(final_warn_msg))
    del_key = random.randint(1000, 9999)
    confirm = None
    while confirm != str(del_key):
        confirm = input(f"To confirm, please type the following key `{del_key}`: ")
    try:
        subprocess.run(["terraform", "destroy", "-var-file=.tfvars", "-auto-approve"],
                   check=True,
                   cwd=terraform_dir)
    except subprocess.CalledProcessError as e:
        print(f"Error during terraform destroy: {e}")
        print("Aborting destroy process.")
        return
    print("Confirmation received. Proceeding with Terraform destroy...")


def Backup_Minecraft_Server(output_dir: str):
    ...


def Restore_Terraform_From_Backup() -> str:
    backup_zip_path = None
    while not backup_zip_path:
        backup_zip_path = input("Enter the path to your terraform backup zip file: ")
        if not os.path.isfile(backup_zip_path):
            print("Invalid file path. Please try again.")
            backup_zip_path = None
    shutil.unpack_archive(backup_zip_path, TERRAFORM_DIR)
    print(f"Terraform files restored to {TERRAFORM_DIR}...")
    return TERRAFORM_DIR


if __name__ == "__main__":
    main()