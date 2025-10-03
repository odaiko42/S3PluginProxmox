import argparse
import getpass
from installer.file_copier import copy_files
from installer.config_manager import ConfigManager
from installer.s3_providers import get_s3_providers
from utils.interactive import interactive_prompt

def main():
    # Set up command-line argument parsing
    parser = argparse.ArgumentParser(
        description='Proxmox S3 Storage Plugin Installer',
        epilog='''
Example usage:
    python src/main.py 192.168.1.100 root
    
This script will:
1. Connect to your Proxmox server via SSH
2. Copy the S3 plugin files to the correct locations
3. Guide you through interactive configuration
4. Create the storage configuration in /etc/pve/storage.cfg
5. Optionally configure advanced parameters
        ''',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('ip', type=str, help='Proxmox server IP address')
    parser.add_argument('login', type=str, help='Proxmox server login username')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done without making changes')
    args = parser.parse_args()

    print("=== Proxmox S3 Storage Plugin Installer ===")
    print(f"Target Proxmox server: {args.ip}")
    print(f"Username: {args.login}")
    if args.dry_run:
        print("🔍 DRY RUN MODE - No actual changes will be made")
    print()

    if not args.dry_run:
        # Prompt for password
        password = getpass.getpass(prompt='Enter your Proxmox password: ')

        try:
            # Copy necessary files to Proxmox
            print("\n=== Step 1: Copying plugin files ===")
            copy_files(args.ip, args.login, password)
            print("✓ File copying completed successfully!")
            
        except Exception as e:
            print(f"✗ Error copying files: {str(e)}")
            print("Please check your connection and credentials.")
            return
    else:
        print("\n=== Step 1: Files that would be copied ===")
        print("The following files would be copied to your Proxmox server:")
        files_list = [
            "S3Plugin.pm → /usr/share/perl5/PVE/Storage/",
            "S3 modules → /usr/share/perl5/PVE/Storage/S3/",
            "CLI scripts → /usr/local/bin/",
        ]
        for file_desc in files_list:
            print(f"  • {file_desc}")
        print("✓ File list prepared")

    print("\n=== Step 2: S3 Provider Configuration ===")
    # Get S3 providers and prompt user for selection
    s3_providers = get_s3_providers()
    provider_names = [provider["name"] for provider in s3_providers]
    selected_provider_name = interactive_prompt("Select your S3 provider:", provider_names)
    
    # Find the selected provider details
    selected_provider = next(p for p in s3_providers if p["name"] == selected_provider_name)

    print(f"\n✓ Selected provider: {selected_provider['name']}")
    if selected_provider["endpoint"]:
        print(f"  Default endpoint: {selected_provider['endpoint']}")
        print(f"  Default region: {selected_provider['region']}")

    print("\n=== Step 3: Storage Configuration ===")
    # Create and configure the storage.cfg file
    config_manager = ConfigManager()
    config_manager.prompt_for_configuration()
    
    print("\n=== Step 4: Generating Configuration ===")
    if not args.dry_run:
        config_manager.create_storage_config()
    else:
        print("🔍 DRY RUN MODE - Preview of configuration that would be written to /etc/pve/storage.cfg:")
        print()
        # Show preview without actually writing the file
        config_manager.show_config_preview()

    print("\n=== Installation Complete! ===")
    # Display information about the web interface and command lines
    config_manager.display_information()

    # Offer to enter advanced configuration parameters
    if input("\nWould you like to see advanced configuration options? (y/n): ").lower() == 'y':
        print("\n=== Advanced Configuration Options ===")
        print("You can add these parameters to your storage configuration:")
        print()
        print("🔐 Server-side encryption:")
        print("    server_side_encryption AES256")
        print("    # or for AWS KMS:")
        print("    server_side_encryption aws:kms")
        print("    kms_key_id arn:aws:kms:region:account:key/key-id")
        print()
        print("📊 Lifecycle management:")
        print("    lifecycle_enabled 1")
        print("    transition_days 30")
        print("    glacier_days 365")
        print()
        print("⚡ Performance tuning:")
        print("    connection_timeout 60")
        print("    retry_count 5")
        print("    retry_delay 2")
        print()
        print("To add these options, edit /etc/pve/storage.cfg on your Proxmox server")
        print("or refer to the plugin documentation for more details.")
    
    print("\n🎉 Setup completed successfully!")
    print("Your Proxmox S3 storage plugin is now ready to use.")
    
    if not args.dry_run:
        print("\n" + "="*60)
        print("   OUTILS DE DIAGNOSTIC")
        print("="*60)
        print("📋 Si vous rencontrez des problèmes, utilisez ces outils :")
        print()
        print("1️⃣ DIAGNOSTIC COMPLET (sur le serveur Proxmox) :")
        print("   wget -O diagnostic.py https://raw.githubusercontent.com/your-repo/diagnostic-proxmox.py")
        print("   python3 diagnostic.py")
        print()
        print("2️⃣ DIAGNOSTIC RAPIDE (copier-coller) :")
        print("   Consultez le fichier DIAGNOSTIC_COMMANDS.md")
        print()
        print("3️⃣ COMMANDES ESSENTIELLES :")
        print("   systemctl restart pvedaemon pveproxy")
        print("   pvesm status")
        print("   journalctl -u pvedaemon | tail")

if __name__ == '__main__':
    main()