import re

def validate_ip(ip_address):
    pattern = r"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$"
    if re.match(pattern, ip_address):
        return True
    return False

def validate_non_empty(value):
    return bool(value.strip())

def validate_aws_credentials(access_key, secret_key):
    return validate_non_empty(access_key) and validate_non_empty(secret_key)

def validate_storage_config(bucket_name, endpoint, region):
    return (validate_non_empty(bucket_name) and 
            validate_non_empty(endpoint) and 
            validate_non_empty(region))

def validate_storage_name(storage_name):
    """
    Valide le nom de stockage Proxmox:
    - Doit contenir uniquement des lettres minuscules, chiffres et tirets
    - Doit commencer par une lettre
    - Ne peut pas se terminer par un tiret
    - Longueur entre 3 et 32 caractères
    """
    if not storage_name:
        return False, "Le nom de stockage ne peut pas être vide"
    
    if len(storage_name) < 3 or len(storage_name) > 32:
        return False, "Le nom de stockage doit contenir entre 3 et 32 caractères"
    
    if not re.match(r'^[a-z][a-z0-9-]*[a-z0-9]$', storage_name):
        return False, "Le nom de stockage doit commencer par une lettre minuscule, contenir uniquement des lettres minuscules, chiffres et tirets, et ne pas se terminer par un tiret"
    
    return True, "Nom de stockage valide"

def validate_s3_bucket_name(bucket_name):
    """
    Valide le nom de bucket S3 selon les règles AWS:
    - Entre 3 et 63 caractères
    - Uniquement des lettres minuscules, chiffres, points et tirets
    - Doit commencer et finir par une lettre ou un chiffre
    - Ne peut pas contenir deux points consécutifs
    - Ne peut pas ressembler à une adresse IP
    """
    if not bucket_name:
        return False, "Le nom du bucket ne peut pas être vide"
    
    if len(bucket_name) < 3 or len(bucket_name) > 63:
        return False, "Le nom du bucket doit contenir entre 3 et 63 caractères"
    
    # Vérification des caractères autorisés
    if not re.match(r'^[a-z0-9.-]+$', bucket_name):
        return False, "Le nom du bucket ne peut contenir que des lettres minuscules, chiffres, points et tirets"
    
    # Doit commencer et finir par une lettre ou un chiffre
    if not re.match(r'^[a-z0-9].*[a-z0-9]$', bucket_name):
        return False, "Le nom du bucket doit commencer et finir par une lettre minuscule ou un chiffre"
    
    # Ne peut pas contenir deux points consécutifs
    if '..' in bucket_name:
        return False, "Le nom du bucket ne peut pas contenir deux points consécutifs"
    
    # Ne peut pas ressembler à une adresse IP
    if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', bucket_name):
        return False, "Le nom du bucket ne peut pas ressembler à une adresse IP"
    
    return True, "Nom de bucket valide"

def validate_s3_prefix(prefix):
    """
    Valide le préfixe S3:
    - Peut être vide
    - Ne peut pas commencer par '/'
    - Doit se terminer par '/' si non vide
    """
    if not prefix:
        return True, "Préfixe valide (vide)"
    
    if prefix.startswith('/'):
        return False, "Le préfixe ne peut pas commencer par '/'"
    
    if not prefix.endswith('/'):
        return False, "Le préfixe doit se terminer par '/' s'il n'est pas vide"
    
    # Vérification des caractères autorisés (pas de caractères spéciaux)
    if not re.match(r'^[a-zA-Z0-9._-]+/$', prefix):
        return False, "Le préfixe ne peut contenir que des lettres, chiffres, points, tirets et underscores"
    
    return True, "Préfixe valide"

def validate_access_key(access_key):
    """
    Valide la clé d'accès S3 (flexible pour différents fournisseurs):
    - AWS: commence par 'AKIA', 20 caractères
    - MinIO/autres: 16-128 caractères alphanumériques
    """
    if not access_key:
        return False, "La clé d'accès ne peut pas être vide"
    
    # Validation AWS stricte
    if access_key.startswith('AKIA'):
        if len(access_key) != 20:
            return False, "La clé d'accès AWS doit contenir exactement 20 caractères"
        if not re.match(r'^[A-Z0-9]+$', access_key):
            return False, "La clé d'accès AWS ne peut contenir que des lettres majuscules et des chiffres"
        return True, "Clé d'accès AWS valide"
    
    # Validation générique pour autres fournisseurs (MinIO, etc.)
    if len(access_key) < 3 or len(access_key) > 128:
        return False, "La clé d'accès doit contenir entre 3 et 128 caractères"
    
    if not re.match(r'^[A-Za-z0-9_.-]+$', access_key):
        return False, "La clé d'accès ne peut contenir que des lettres, chiffres, tirets et points"
    
    return True, "Clé d'accès valide"

def validate_secret_key(secret_key):
    """
    Valide la clé secrète S3 (flexible pour différents fournisseurs):
    - AWS: 40 caractères en base64
    - MinIO/autres: 8-128 caractères
    """
    if not secret_key:
        return False, "La clé secrète ne peut pas être vide"
    
    # Pour les clés qui ressemblent à du base64 (AWS)
    if re.match(r'^[A-Za-z0-9+/]+=*$', secret_key) and len(secret_key) == 40:
        return True, "Clé secrète AWS valide"
    
    # Validation générique pour autres fournisseurs
    if len(secret_key) < 8 or len(secret_key) > 128:
        return False, "La clé secrète doit contenir entre 8 et 128 caractères"
    
    # Accepter plus de caractères pour MinIO et autres
    if not re.match(r'^[A-Za-z0-9+/=_.-]+$', secret_key):
        return False, "La clé secrète contient des caractères non autorisés"
    
    return True, "Clé secrète valide"

def get_storage_name_examples():
    return [
        "backup-s3-aws",
        "minio-local",
        "ceph-storage",
        "wasabi-backup",
        "s3-production"
    ]

def get_bucket_name_examples():
    return [
        "mon-entreprise-backups",
        "proxmox-vm-storage", 
        "backup-prod-2024",
        "storage.example.com",
        "test-bucket-dev"
    ]

def get_prefix_examples():
    return [
        "proxmox/",
        "backups/node1/",
        "vm-storage/",
        "production/",
        "" # Pas de préfixe
    ]

def get_access_key_examples():
    return {
        "aws": ["AKIAIOSFODNN7EXAMPLE"],
        "minio": ["minioadmin", "minio123", "myaccesskey"],
        "generic": ["admin", "s3user", "accesskey123"]
    }

def get_secret_key_examples():
    return {
        "aws": ["wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"],
        "minio": ["minioadmin", "minio123password", "mysecretkey"],
        "generic": ["password123", "secretkey456"]
    }