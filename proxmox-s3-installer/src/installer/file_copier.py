import os
import paramiko
import getpass
from installer.config_manager import ConfigManager
from installer.s3_providers import get_s3_providers
from utils.interactive import interactive_prompt

def copy_files(proxmox_ip, username, password):
    # Define the S3 plugin files to be copied
    base_path = "C:/Projects/S3-plugin"
    files_to_copy = [
        {
            'local': f'{base_path}/PVE/Storage/S3Plugin.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3Plugin.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Client.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Client.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Config.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Config.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Auth.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Auth.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Transfer.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Transfer.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Metadata.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Metadata.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Utils.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Utils.pm'
        },
        {
            'local': f'{base_path}/PVE/Storage/S3/Exception.pm',
            'remote': '/usr/share/perl5/PVE/Storage/S3/Exception.pm'
        },
        {
            'local': f'{base_path}/scripts/pve-s3-backup',
            'remote': '/usr/local/bin/pve-s3-backup'
        },
        {
            'local': f'{base_path}/scripts/pve-s3-restore',
            'remote': '/usr/local/bin/pve-s3-restore'
        },
        {
            'local': f'{base_path}/scripts/pve-s3-maintenance',
            'remote': '/usr/local/bin/pve-s3-maintenance'
        }
    ]
    
    # Create an SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        # Connect to the Proxmox server
        ssh.connect(proxmox_ip, username=username, password=password)
        
        # Copy files using SCP
        scp = paramiko.SFTPClient.from_transport(ssh.get_transport())
        
        print("Copying S3 plugin files to Proxmox server...")
        
        for file_info in files_to_copy:
            local_file = file_info['local']
            remote_file = file_info['remote']
            
            # Create remote directory if it doesn't exist
            remote_dir = os.path.dirname(remote_file)
            try:
                ssh.exec_command(f'mkdir -p {remote_dir}')
            except:
                pass
            
            # Check if local file exists
            if not os.path.exists(local_file):
                print(f"Warning: Local file not found: {local_file}")
                continue
            
            try:
                scp.put(local_file, remote_file)
                # Make script files executable
                if remote_file.startswith('/usr/local/bin/'):
                    ssh.exec_command(f'chmod +x {remote_file}')
                print(f'✓ Copied {os.path.basename(local_file)} to {remote_file}')
            except Exception as e:
                print(f'✗ Failed to copy {local_file}: {str(e)}')
        
        scp.close()
        
        # Vérification post-installation
        print("\n🔍 Vérification de l'installation...")
        
        # Test de la syntaxe Perl du plugin principal
        stdin, stdout, stderr = ssh.exec_command('perl -c /usr/share/perl5/PVE/Storage/S3Plugin.pm')
        syntax_output = stderr.read().decode().strip()
        
        if "syntax OK" in syntax_output:
            print("✓ Syntaxe Perl du plugin validée")
        else:
            print(f"⚠️  Avertissement syntaxe Perl: {syntax_output}")
        
        # Vérification des permissions
        stdin, stdout, stderr = ssh.exec_command('ls -la /usr/share/perl5/PVE/Storage/S3Plugin.pm')
        perms_output = stdout.read().decode().strip()
        if perms_output:
            print(f"✓ Permissions: {perms_output}")
        
        # Redémarrage des services Proxmox
        print("\n🔄 Redémarrage des services Proxmox...")
        ssh.exec_command('systemctl restart pvedaemon')
        ssh.exec_command('systemctl restart pveproxy')
        print("✓ Services redémarrés (pvedaemon, pveproxy)")
        
        print("\n✅ Installation terminée avec succès!")
        print("📌 Le stockage devrait maintenant apparaître dans Proxmox > Datacenter > Storage")
        print("📌 Si ce n'est pas le cas, consultez la section dépannage ci-dessous")
        
    except Exception as e:
        print(f'Error during file copy: {e}')
    finally:
        ssh.close()

def main():
    proxmox_ip = input("Enter Proxmox server IP: ")
    username = input("Enter Proxmox username: ")
    password = getpass.getpass("Enter Proxmox password: ")
    
    copy_files(proxmox_ip, username, password)
    
    # Interactive configuration setup
    config_manager = ConfigManager()
    s3_providers = get_s3_providers()
    
    print("Available S3 providers:")
    for provider in s3_providers:
        print(f"- {provider}")
    
    selected_provider = interactive_prompt("Select your S3 provider: ", s3_providers)
    
    # Fill in the configuration file
    config_manager.create_config(selected_provider)

    print("Configuration file created successfully.")
    print("You can now access the Proxmox web interface and use the command line tools.")

if __name__ == "__main__":
    main()