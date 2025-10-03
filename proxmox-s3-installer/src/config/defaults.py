# Default configuration values for the Proxmox S3 Installer

# Proxmox server default values
DEFAULT_PROXMOX_IP = "192.168.1.100"
DEFAULT_PROXMOX_USER = "root@pam"

# S3 configuration defaults
DEFAULT_S3_BUCKET = "my-proxmox-bucket"
DEFAULT_S3_ENDPOINT = "s3.amazonaws.com"
DEFAULT_S3_REGION = "us-east-1"
DEFAULT_S3_ACCESS_KEY = "AKIA..."
DEFAULT_S3_SECRET_KEY = "..."
DEFAULT_S3_PREFIX = "proxmox/"
DEFAULT_STORAGE_CLASS = "STANDARD"
DEFAULT_MULTIPART_CHUNK_SIZE = 100
DEFAULT_MAX_CONCURRENT_UPLOADS = 3

# Supported S3 providers
SUPPORTED_S3_PROVIDERS = [
    "AWS S3",
    "MinIO",
    "Ceph RadosGW",
    "Wasabi"
]

# Advanced configuration defaults
DEFAULT_CONNECTION_TIMEOUT = 60
DEFAULT_SERVER_SIDE_ENCRYPTION = "AES256"
DEFAULT_LIFECYCLE_ENABLED = 1
DEFAULT_TRANSITION_DAYS = 30
DEFAULT_GLACIER_DAYS = 365