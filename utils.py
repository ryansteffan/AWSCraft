import subprocess

def Check_Command_Availability() -> bool:
    # Check for terraform
    try:
        subprocess.run(["terraform", "-version"], 
                       check=True, 
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except Exception as e:
        print("Terraform is not installed or not found in PATH." +
        " Please install Terraform to proceed.")
        return False
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
        return False
    # Check for AWS
    try:
        subprocess.run(["aws", "--version"], 
                       check=True,
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except Exception as e:
        print("AWS CLI is not installed or not found in PATH. " +
        "Please install AWS CLI to proceed.")
        return False
    return True

def Prompt_AWS_Login() -> bool:
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
                return False
        case "3":
            print("AWS SSO Login is not yet implemented. Please use another method.")
            return False
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
                return False
    return True