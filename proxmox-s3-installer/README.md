# Proxmox S3 Installer

This project provides a Python script to facilitate the installation and configuration of an S3 storage plugin for Proxmox VE. The script allows users to connect to a Proxmox server, copy necessary files, and configure the storage settings interactively.

## Features

- **Interactive Configuration**: Users can fill in the configuration file `/etc/pve/storage.cfg` through an interactive prompt.
- **Support for Multiple S3 Providers**: The script supports various S3-compatible storage providers, including AWS S3, MinIO, and Ceph RadosGW.
- **Environment Variable Configuration**: Users can set environment variables for S3 credentials and other settings.
- **File Copying**: The script handles the secure copying of necessary files to the Proxmox server.

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/proxmox-s3-installer.git
   cd proxmox-s3-installer
   ```

2. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

## Usage

Run the script with the Proxmox server IP and login as command-line arguments:
```
python src/main.py <proxmox_server_ip> <username>
```

You will be prompted to enter your password. After authentication, the script will guide you through the configuration process.

## Configuration

During the interactive setup, you will be asked to choose between the following S3 providers:

- AWS S3
- MinIO
- Ceph RadosGW
- Other major endpoints

You will also have the option to enter advanced configuration parameters after the initial setup.

## Command Line Interface

Once configured, you can use the following commands to manage your S3 storage:

- **Backup manual**: 
  ```
  pve-s3-backup --storage <storage_name> --source <source_path> --vmid <vm_id>
  ```

- **List backups**: 
  ```
  pve-s3-restore --storage <storage_name> --list
  ```

- **Restore backups**: 
  ```
  pve-s3-restore --storage <storage_name> --source <backup_file> --destination <destination_path>
  ```

## Advanced Configuration

After completing the initial setup, you can enter advanced configuration parameters such as:

- Multipart upload settings
- Server-side encryption options
- Lifecycle management settings

## Support

For issues or feature requests, please create an issue in the GitHub repository. Contributions are welcome!

## License

This project is licensed under the MIT License. See the LICENSE file for details.