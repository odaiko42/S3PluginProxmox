import os
import getpass

def interactive_prompt(prompt_text, options=None):
    """Interactive prompt function that can handle multiple choice options"""
    if options:
        print(f"\n{prompt_text}")
        for idx, option in enumerate(options, start=1):
            print(f"{idx}. {option}")
        
        while True:
            try:
                choice = int(input("Enter your choice (number): "))
                if 1 <= choice <= len(options):
                    return options[choice - 1]
                else:
                    print(f"Please enter a number between 1 and {len(options)}")
            except ValueError:
                print("Please enter a valid number")
    else:
        return input(prompt_text)

def prompt_for_password():
    return getpass.getpass("Enter your Proxmox password: ")

def prompt_for_proxmox_details():
    ip = input("Enter the Proxmox server IP: ")
    login = input("Enter your Proxmox login: ")
    password = prompt_for_password()
    return ip, login, password

def choose_s3_provider():
    providers = [
        "AWS S3",
        "MinIO",
        "Ceph RadosGW",
        "Other"
    ]
    print("Choose your S3 provider:")
    for idx, provider in enumerate(providers, start=1):
        print(f"{idx}. {provider}")
    
    choice = int(input("Enter the number of your choice: "))
    if 1 <= choice <= len(providers):
        return providers[choice - 1]
    else:
        print("Invalid choice. Defaulting to AWS S3.")
        return providers[0]

def configure_storage_file(provider):
    bucket = input("Enter the S3 bucket name: ")
    endpoint = input("Enter the S3 endpoint (leave blank for default): ")
    region = input("Enter the S3 region (leave blank for default): ")
    access_key = input("Enter your S3 access key: ")
    secret_key = input("Enter your S3 secret key: ")
    
    config_content = f"""
s3: my-s3-storage
    bucket {bucket}
    endpoint {endpoint or 's3.amazonaws.com'}
    region {region or 'us-east-1'}
    access_key {access_key}
    secret_key {secret_key}
    content backup,iso,vztmpl,snippets
    storage_class STANDARD
    multipart_chunk_size 100
    max_concurrent_uploads 3
"""
    return config_content.strip()

def write_config_file(config_content):
    config_path = "/etc/pve/storage.cfg"
    with open(config_path, 'w') as config_file:
        config_file.write(config_content)
    print(f"Configuration written to {config_path}")

def main():
    ip, login, password = prompt_for_proxmox_details()
    provider = choose_s3_provider()
    config_content = configure_storage_file(provider)
    write_config_file(config_content)
    
    print("\nConfiguration completed. You can now access the Proxmox web interface.")
    print("Use the following commands for S3 operations:")
    print("Backup: pve-s3-backup --storage my-s3-storage --source <source> --vmid <vmid>")
    print("Restore: pve-s3-restore --storage my-s3-storage --source <source> --destination <destination>")
    
    advanced_config = input("Would you like to enter advanced configuration parameters? (yes/no): ")
    if advanced_config.lower() == 'yes':
        # Placeholder for advanced configuration logic
        print("Advanced configuration not implemented yet.")

if __name__ == "__main__":
    main()